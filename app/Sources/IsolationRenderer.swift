import AVFoundation
import AudioToolbox

/// A clip window's isolated voice rendered offline into a file (spec §11
/// AU-51), S2's recipe: Apple's `AUSoundIsolation` (`aufx`/`vois`/`appl`)
/// with the High Quality Voice model (parameter 1 = 0) at 100 % wet
/// (parameter 0 = 100), each channel through its own engine in
/// `AVAudioEngine`'s offline manual rendering at 48 kHz mono, the engines in
/// lockstep over ONE `RampSourceReader`.
///
/// The model adapts over 0.5–2 s and silence resets it, so 4 s of the media
/// is fed before the window (from frame 0 when the window starts sooner),
/// then the media to the window's end and zeros past it until the window's
/// last frame is out. The unit's latency is a constant 4440 frames at
/// 48 kHz; a unit that reports anything else fails the render rather than
/// writing a misaligned file. The first preroll + 4440 output frames are
/// discarded, so kept frame 0 is the window's first frame.
///
/// Blocking, on the caller's queue: `RampAudioRenders` renders into
/// `cache/isolated/`, named by `IsolationCache`. Windows starting mid-file
/// differ from a whole-file render by about −51 dB (S2), so a render is never
/// checked by rendering it again.
enum IsolationRenderer {
    /// Part of the cache key (AU-52): bump it whenever the written file changes.
    static let version = 1
    static let sampleRate = 48_000
    /// The unit's latency at 48 kHz mono (S2), discarded and pinned.
    static let latencyFrames = 4440
    /// 4 s of media fed before the window.
    static let prerollFrames: Int64 = 192_000
    static let maxFrames: AVAudioFrameCount = 4096

    struct Job {
        /// 48 kHz with no MP3 trim (`RampAudioCache.renderSource`'s copy, or
        /// a reversed file).
        let source: URL
        let window: IsolationWindow
        /// A `.caf`; written as "<destination>.partial", then renamed.
        let destination: URL
    }

    struct Report: Equatable {
        /// The window's length.
        let frames: Int64
        /// The source's, clamped 1…2.
        let channels: Int
        /// The unit's reported latency, discarded.
        let latencyFrames: Int
        let wallSeconds: Double
    }

    enum RenderError: LocalizedError, Equatable {
        case unreadable(String), failed(String), cancelled

        var errorDescription: String? {
            switch self {
            case .unreadable(let why): return "The isolated voice's source cannot be read: \(why)."
            case .failed(let why): return "The isolated voice could not be rendered: \(why)."
            case .cancelled: return "The isolated voice's render was cancelled."
            }
        }
    }

    /// One channel's feed: frame after frame of channel `channel` from
    /// `next`, the media inside the window's end and zeros past it.
    private final class Feeder: @unchecked Sendable {
        let source: RampSourceReader
        let channel: Int
        let end: Int64
        private(set) var next: Int64
        private(set) var error: Error?

        init(source: RampSourceReader, channel: Int, from start: Int64, end: Int64) {
            self.source = source
            self.channel = channel
            self.end = end
            next = start
        }

        func feed(_ count: Int, into list: UnsafeMutablePointer<AudioBufferList>) {
            do {
                try source.fill(through: min(next + Int64(count), end))
            } catch {
                self.error = error
            }
            for buffer in UnsafeMutableAudioBufferListPointer(list) {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }
                for i in 0..<count {
                    let k = next + Int64(i)
                    data[i] = k < end ? source.sample(k, channel: channel) : 0
                }
            }
            next += Int64(count)
        }
    }

    /// One channel's engine: its feeder → the unit → the main mixer.
    private struct Lane {
        let engine: AVAudioEngine
        let buffer: AVAudioPCMBuffer
        let feeder: Feeder
    }

    static func render(_ job: Job, cancelled: () -> Bool) throws -> Report {
        let started = Date()
        let asset = AVURLAsset(url: job.source)
        guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio) else {
            throw RenderError.unreadable("\(job.source.lastPathComponent) has no audio track")
        }
        guard let signature = CompositionBuilder.audioFormatSignature(of: track) else {
            throw RenderError.unreadable(
                "\(job.source.lastPathComponent)'s audio format cannot be read")
        }
        let trim = MP3Gapless.leadingTrim(of: job.source, track: track)
        guard !AudioRateCopy.needsCopy(signature, trim: trim) else {
            throw RenderError.unreadable(
                "\(job.source.lastPathComponent) is \(Int(signature.sampleRate)) Hz"
                    + (trim > .zero ? " with an MP3 encoder delay" : "")
                    + "; only a 48 kHz source with no trim is rendered")
        }
        let window = job.window
        let frames = window.endFrame - window.firstFrame
        guard window.firstFrame >= 0, frames > 0 else {
            throw RenderError.failed(
                "the window [\(window.firstFrame), \(window.endFrame)) holds no frame")
        }
        let channels = Int(min(max(signature.channels, 1), 2))
        let preroll = min(prerollFrames, window.firstFrame)
        let feedStart = window.firstFrame - preroll
        let partial = URL(fileURLWithPath: job.destination.path + ".partial")
        try? FileManager.default.removeItem(at: partial)
        var writer: RampCAFWriter?
        do {
            let source = try RampSourceReader(
                asset: asset, track: track, channels: channels, from: feedStart)
            let lanes = try (0..<channels).map {
                try lane(
                    Feeder(source: source, channel: $0, from: feedStart, end: window.endFrame))
            }
            defer { lanes.forEach { $0.engine.stop() } }
            writer = try RampCAFWriter(url: partial, channels: channels)
            let discard = preroll + Int64(latencyFrames)
            var out = [Float](repeating: 0, count: Int(maxFrames) * channels)
            var rendered: Int64 = 0
            var written: Int64 = 0
            while written < frames {
                if cancelled() { throw RenderError.cancelled }
                var got = Int64(maxFrames)
                for lane in lanes {
                    let status: AVAudioEngineManualRenderingStatus
                    do {
                        status = try lane.engine.renderOffline(maxFrames, to: lane.buffer)
                    } catch {
                        throw RenderError.failed("renderOffline: \(error.localizedDescription)")
                    }
                    if let error = lane.feeder.error {
                        throw RenderError.failed("the source: \(error.localizedDescription)")
                    }
                    guard status == .success else {
                        throw RenderError.failed("renderOffline answered status \(status.rawValue)")
                    }
                    got = min(got, Int64(lane.buffer.frameLength))
                }
                if got == 0 { throw RenderError.failed("renderOffline rendered no frames") }
                source.drop(before: lanes.map(\.feeder.next).min() ?? feedStart)
                let from = max(0, discard - rendered)
                let upTo = min(got, discard + frames - rendered)
                if upTo > from {
                    let count = Int(upTo - from)
                    for (c, lane) in lanes.enumerated() {
                        guard let data = lane.buffer.floatChannelData?[0] else {
                            throw RenderError.failed("a render buffer had no samples")
                        }
                        for i in 0..<count { out[i * channels + c] = data[Int(from) + i] }
                    }
                    try writer!.write(out, frames: count)
                    written += Int64(count)
                }
                rendered += got
            }
            try writer!.close()
            writer = nil
            guard rename(partial.path, job.destination.path) == 0 else {
                throw RenderError.failed("the file could not be moved into place (errno \(errno))")
            }
            return Report(
                frames: frames, channels: channels, latencyFrames: latencyFrames,
                wallSeconds: Date().timeIntervalSince(started))
        } catch {
            writer?.abandon()
            try? FileManager.default.removeItem(at: partial)
            throw reworded(error)
        }
    }

    /// The reader's and the writer's errors in this renderer's words.
    private static func reworded(_ error: Error) -> RenderError {
        switch error {
        case let known as RenderError: return known
        case RampAudioRenderer.RenderError.unreadable(let why): return .unreadable(why)
        case RampAudioRenderer.RenderError.failed(let why): return .failed(why)
        case RampAudioRenderer.RenderError.cancelled: return .cancelled
        default: return .failed(error.localizedDescription)
        }
    }

    /// One mono engine with the unit set to S2's recipe, started in offline
    /// manual rendering; refuses a unit whose latency is not 4440 frames.
    private static func lane(_ feeder: Feeder) throws -> Lane {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate), channels: 1)
        else { throw RenderError.failed("no mono float format") }
        let unit = AVAudioUnitEffect(
            audioComponentDescription: AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_AUSoundIsolation,
                componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0,
                componentFlagsMask: 0))
        let model = AudioUnitSetParameter(
            unit.audioUnit, AudioUnitParameterID(kAUSoundIsolationParam_SoundToIsolate),
            kAudioUnitScope_Global, 0, 0, 0)
        let mix = AudioUnitSetParameter(
            unit.audioUnit, AudioUnitParameterID(kAUSoundIsolationParam_WetDryMixPercent),
            kAudioUnitScope_Global, 0, 100, 0)
        guard model == noErr, mix == noErr else {
            throw RenderError.failed(
                "the voice isolation unit refused its settings (\(model), \(mix))")
        }
        let node = AVAudioSourceNode(format: format) { _, _, count, list in
            feeder.feed(Int(count), into: list)
            return noErr
        }
        let engine = AVAudioEngine()
        engine.attach(node)
        engine.attach(unit)
        engine.connect(node, to: unit, format: format)
        engine.connect(unit, to: engine.mainMixerNode, format: format)
        do {
            try engine.enableManualRenderingMode(
                .offline, format: format, maximumFrameCount: maxFrames)
            try engine.start()
        } catch {
            throw RenderError.failed(
                "the voice isolation engine did not start: \(error.localizedDescription)")
        }
        let latency = Int((unit.latency * Double(sampleRate)).rounded())
        guard latency == latencyFrames else {
            engine.stop()
            throw RenderError.failed(
                "the voice isolation unit reports a latency of \(latency) frames, not "
                    + "\(latencyFrames)")
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames)
        else {
            engine.stop()
            throw RenderError.failed("no render buffer")
        }
        return Lane(engine: engine, buffer: buffer, feeder: feeder)
    }
}
