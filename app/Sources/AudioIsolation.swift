import AVFoundation
import Foundation

/// Voice isolation's half of the tap (spec §11 AU-53, AU-54): a clip's
/// isolated render read into memory when the composition is built, and the
/// crossfade `out = dry + a·(wet − dry)` the tap runs BEFORE its chain.
///
/// **Real-time.** The pass reads only memory loaded at build time
/// (`AudioTap.swift`'s header; S1's rule): no file, no lock, no allocation
/// on the audio thread. A render not on disk when the composition is built
/// adds no span, so its clip plays dry until the editor rebuilds on its
/// landing.

/// One render's samples, planar 32-bit float at 48 kHz.
final class IsolatedAudio: @unchecked Sendable {
    let channels: Int
    let frames: Int
    /// One allocation per channel, freed with the object.
    private let storage: [UnsafeMutablePointer<Float>]

    /// Nil for a file that does not read whole as 48 kHz float. Read in
    /// chunks until the file's length is in: one `read(into:)` of a whole
    /// render's CAF was measured stopping 256 frames short.
    init?(contentsOf url: URL) {
        guard let file = try? AVAudioFile(
            forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
            file.processingFormat.sampleRate == Double(IsolationRenderer.sampleRate),
            file.length > 0, file.length <= Int64(Int32.max),
            file.processingFormat.channelCount > 0
        else { return nil }
        let channels = Int(file.processingFormat.channelCount)
        let length = Int(file.length)
        let chunk: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk)
        else { return nil }
        let storage = (0..<channels).map { _ -> UnsafeMutablePointer<Float> in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: length)
            pointer.initialize(repeating: 0, count: length)
            return pointer
        }
        var filled = 0
        while filled < length {
            let ask = min(chunk, AVAudioFrameCount(length - filled))
            guard (try? file.read(into: buffer, frameCount: ask)) != nil,
                buffer.frameLength > 0, let data = buffer.floatChannelData
            else { break }
            let got = min(Int(buffer.frameLength), length - filled)
            for c in 0..<channels { (storage[c] + filled).update(from: data[c], count: got) }
            filled += got
        }
        guard filled == length else {
            storage.forEach { $0.deallocate() }
            return nil
        }
        self.channels = channels
        frames = length
        self.storage = storage
    }

    deinit { storage.forEach { $0.deallocate() } }

    func samples(channel: Int) -> UnsafePointer<Float> {
        UnsafePointer(storage[min(max(channel, 0), channels - 1)])
    }
}

/// One read per file while any composition holds it: a path maps WEAKLY to
/// its loaded render, so a render lives exactly as long as a composition's
/// tap holds it, and a rebuild that keeps it reads no file.
final class IsolatedAudioStore {
    static let shared = IsolatedAudioStore()

    private let lock = NSLock()
    private let loaded = NSMapTable<NSString, IsolatedAudio>.strongToWeakObjects()

    private init() {}

    func audio(at url: URL) -> IsolatedAudio? {
        let key = url.standardizedFileURL.path as NSString
        lock.lock()
        defer { lock.unlock() }
        if let held = loaded.object(forKey: key) { return held }
        guard let read = IsolatedAudio(contentsOf: url) else { return nil }
        loaded.setObject(read, forKey: key)
        return read
    }
}

/// One isolated segment on a composition audio track.
struct AudioIsolationSpan {
    /// Composition input frames, `[startFrame, endFrame)`.
    let startFrame: Int64
    let endFrame: Int64
    /// Wet index = frame + wetOffset (`IsolationCache.wetOffset`).
    let wetOffset: Int64
    let amount: Float
    let audio: IsolatedAudio
}

/// One composition audio track's isolation pass: its spans, sorted.
struct AudioIsolationTrack {
    let spans: [AudioIsolationSpan]

    var isEmpty: Bool { spans.isEmpty }

    /// One span per segment of the family whose clip asks for isolation and
    /// whose render is loaded, placed through `placement(of:shift:)` so the
    /// track's leads compose: `[r(at), r(at + duration))` with `r` the
    /// nearest frame, and the wet offset rounded once (AU-53).
    init(
        segments: [PlanSegment], shift: CompositionBuilder.AudioShift,
        dsp: AudioDSPParameters, renders: [IsolationSegmentKey: IsolatedAudio]
    ) {
        var spans: [AudioIsolationSpan] = []
        for s in segments where s.duration > 0 {
            let amount = dsp.isolation(for: s.clip)
            guard amount > 0, let audio = renders[IsolationSegmentKey(s)],
                let p = CompositionBuilder.placement(of: s, shift: shift)
            else { continue }
            let start = IsolationCache.frame(ofTicks: p.at)
            let end = IsolationCache.frame(ofTicks: p.at + p.duration)
            guard end > start else { continue }
            spans.append(
                AudioIsolationSpan(
                    startFrame: start, endFrame: end,
                    wetOffset: IsolationCache.wetOffset(
                        at: p.at, sourceIn: p.sourceIn, window: IsolationCache.window(of: s)),
                    amount: Float(min(amount, 1)), audio: audio))
        }
        self.spans = spans.sorted { $0.startFrame < $1.startFrame }
    }

    /// The first span whose end is past `frame`.
    private func firstSpan(endingAfter frame: Int64) -> Int {
        var low = 0
        var high = spans.count
        while low < high {
            let middle = (low + high) / 2
            if spans[middle].endFrame <= frame { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// Crossfades `frames` frames starting at composition input frame
    /// `frame` in place: inside a span, `dry + a·(wet − dry)` (exactly `wet`
    /// at a = 1), the wet channel `min(c, channels − 1)`; a frame whose wet
    /// index falls outside the render, or outside every span, stays dry.
    func apply(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        frames: Int, at frame: Int64
    ) {
        guard !spans.isEmpty, frames > 0 else { return }
        let last = frame + Int64(frames)
        var index = firstSpan(endingAfter: frame)
        while index < spans.count {
            let span = spans[index]
            if span.startFrame >= last { break }
            let from = max(frame, span.startFrame)
            let to = min(last, span.endFrame)
            // Only frames whose wet index is inside the render.
            let lo = max(from, -span.wetOffset)
            let hi = min(to, Int64(span.audio.frames) - span.wetOffset)
            if hi > lo {
                let offset = Int(lo - frame)
                let wetStart = Int(lo + span.wetOffset)
                let n = Int(hi - lo)
                let a = span.amount
                for c in 0..<min(count, channels.count) {
                    guard let out = channels[c]?.advanced(by: offset) else { continue }
                    let wet = span.audio.samples(channel: c).advanced(by: wetStart)
                    if a >= 1 {
                        for i in 0..<n { out[i] = wet[i] }
                    } else {
                        for i in 0..<n { out[i] += a * (wet[i] - out[i]) }
                    }
                }
            }
            index += 1
        }
    }
}
