import AVFoundation

/// Clip time → source position for one ramped clip, sampled by the caller
/// (SR2: the core): breakpoints, linear between them, extended before the
/// first and past the last at the end segments' slopes.
struct RampAudioMap: Equatable {
    /// First 0, strictly increasing, last = the clip's duration.
    let clipTicks: [Ticks]
    /// Media time (the direction the clip plays), strictly increasing, ≥ 0.
    let sourceTicks: [Double]

    /// Why the map cannot be rendered, or nil.
    var problem: String? {
        guard clipTicks.count >= 2, clipTicks.count == sourceTicks.count else {
            return "\(clipTicks.count) clip and \(sourceTicks.count) source breakpoints"
        }
        guard clipTicks[0] == 0 else { return "the first clip tick is \(clipTicks[0]), not 0" }
        for i in 1..<clipTicks.count where clipTicks[i] <= clipTicks[i - 1] {
            return "clip tick \(clipTicks[i]) does not follow \(clipTicks[i - 1])"
        }
        for (i, s) in sourceTicks.enumerated() {
            if !s.isFinite || s < 0 { return "source tick \(s) is not a finite time ≥ 0" }
            if i > 0, s <= sourceTicks[i - 1] {
                return "source tick \(s) does not follow \(sourceTicks[i - 1])"
            }
        }
        return nil
    }

    /// The source tick under clip tick `t` (a fraction of a tick allowed).
    func source(at t: Double) -> Double {
        var lo = 0
        var hi = clipTicks.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if Double(clipTicks[mid]) <= t { lo = mid } else { hi = mid }
        }
        let c0 = Double(clipTicks[lo])
        let slope = (sourceTicks[lo + 1] - sourceTicks[lo]) / (Double(clipTicks[lo + 1]) - c0)
        return sourceTicks[lo] + (t - c0) * slope
    }
}

/// A ramped clip's audio rendered offline into a file (spec §11 SR-6), as a
/// reversed clip's media is pre-rendered: the composition then carries it as
/// ONE ×1 segment, with no rate boundary inside the clip. Keep pitch off is a
/// variable-rate band-limited interpolator (`RampAudioResampler`); keep pitch
/// on drives Apple's time-pitch unit offline (`+TimePitch`, SY-41).
///
/// Blocking, on the caller's queue; no caller in the app yet (SR2 adds it,
/// with `cache/ramp-audio/` and its key).
enum RampAudioRenderer {
    static let sampleRate = 48_000
    /// Part of SR2's cache key: bump it whenever the written file changes.
    static let version = 1
    /// Clip ticks per output frame: 600 000 / 48 000.
    static let ticksPerFrame = Double(ReelTime.perSecond) / Double(sampleRate)
    /// Output frames computed and written at a time.
    static let chunkFrames = 4096

    struct Job {
        /// The file read: 48 kHz, no MP3 trim (`AudioRateCopy`'s copy where
        /// `needsCopy`: the caller's job). A source whose first audio track
        /// fails `AudioRateCopy.needsCopy`'s test throws `.unreadable`.
        let source: URL
        let map: RampAudioMap
        let keepPitch: Bool
        /// A `.caf`; written as "<destination>.partial", then renamed.
        let destination: URL
    }

    struct Report: Equatable {
        /// round(duration × 48000 / ReelTime.perSecond).
        let frames: Int64
        /// The source's, clamped 1…2.
        let channels: Int
        let wallSeconds: Double
        let bytes: Int64
        /// Keep pitch on: the unit's reported latency, discarded.
        let latencyFrames: Int?
        /// Keep pitch on: source frames the unit pulled past the clip's first.
        let pulledFrames: Int64?
        /// Keep pitch on: p(N) − p(0), the map's own source span in frames.
        let mapFrames: Int64?
    }

    enum RenderError: LocalizedError, Equatable {
        case invalidMap(String), unreadable(String), failed(String), cancelled

        var errorDescription: String? {
            switch self {
            case .invalidMap(let why): return "The ramp's map cannot be rendered: \(why)."
            case .unreadable(let why): return "The ramp's source cannot be read: \(why)."
            case .failed(let why): return "The ramp's audio could not be rendered: \(why)."
            case .cancelled: return "The ramp's audio render was cancelled."
            }
        }
    }

    static func render(
        _ job: Job, cancelled: () -> Bool = { false }, progress: ((Double) -> Void)? = nil
    ) throws -> Report {
        let started = Date()
        if let why = job.map.problem { throw RenderError.invalidMap(why) }
        let asset = AVURLAsset(url: job.source)
        guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio),
            let signature = CompositionBuilder.audioFormatSignature(of: track)
        else { throw RenderError.unreadable("\(job.source.lastPathComponent) has no audio track") }
        let trim = MP3Gapless.leadingTrim(of: job.source, track: track)
        guard !AudioRateCopy.needsCopy(signature, trim: trim) else {
            throw RenderError.unreadable(
                "\(job.source.lastPathComponent) is \(Int(signature.sampleRate)) Hz"
                    + (trim > .zero ? " with an MP3 encoder delay" : "")
                    + "; only a 48 kHz source with no trim is rendered")
        }
        let channels = Int(min(max(signature.channels, 1), 2))
        let duration = job.map.clipTicks[job.map.clipTicks.count - 1]
        let frames = Int64((Double(duration) / ticksPerFrame).rounded())
        let partial = URL(fileURLWithPath: job.destination.path + ".partial")
        try? FileManager.default.removeItem(at: partial)
        var writer: RampCAFWriter?
        do {
            writer = try RampCAFWriter(url: partial, channels: channels)
            let p0 = position(job.map, 0)
            var extra: (latency: Int, pulled: Int64)?
            if job.keepPitch {
                let source = try RampSourceReader(
                    asset: asset, track: track, channels: channels,
                    from: Int64(p0.rounded(.down)) - Int64(timePitchPreroll))
                extra = try renderTimePitch(
                    job.map, source: source, frames: frames, writer: writer!,
                    cancelled: cancelled, progress: progress)
            } else {
                let first = chunk(job.map, from: 0, count: Int(min(Int64(chunkFrames), frames)))
                let source = try RampSourceReader(
                    asset: asset, track: track, channels: channels, from: first.lo)
                try renderVarispeed(
                    job.map, source: source, frames: frames, writer: writer!,
                    cancelled: cancelled, progress: progress)
            }
            try writer!.close()
            writer = nil
            guard rename(partial.path, job.destination.path) == 0 else {
                throw RenderError.failed("the file could not be moved into place (errno \(errno))")
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: job.destination.path))?[
                .size] as? NSNumber
            return Report(
                frames: frames, channels: channels,
                wallSeconds: Date().timeIntervalSince(started),
                bytes: size?.int64Value ?? 0, latencyFrames: extra?.latency,
                pulledFrames: extra?.pulled,
                mapFrames: job.keepPitch
                    ? Int64((position(job.map, frames) - p0).rounded()) : nil)
        } catch {
            writer?.abandon()
            try? FileManager.default.removeItem(at: partial)
            if let known = error as? RenderError { throw known }
            throw RenderError.failed(error.localizedDescription)
        }
    }

    /// p(n): output frame n's source position in 48 kHz frames, the map read
    /// at clip tick 12.5 · n.
    static func position(_ map: RampAudioMap, _ n: Int64) -> Double {
        map.source(at: Double(n) * ticksPerFrame) / ticksPerFrame
    }

    /// One chunk's positions p(n … n + count) and the source frames the
    /// kernel reads for them, `lo … hi`.
    static func chunk(_ map: RampAudioMap, from n: Int64, count: Int)
        -> (positions: [Double], lo: Int64, hi: Int64)
    {
        var positions = [Double](repeating: 0, count: count + 1)
        var fastest = 0.0
        for i in 0...count {
            positions[i] = position(map, n + Int64(i))
            if i > 0 { fastest = max(fastest, positions[i] - positions[i - 1]) }
        }
        let reach = Int64(RampAudioResampler.reach(rate: fastest))
        return (
            positions, Int64(positions[0].rounded(.down)) - reach - 1,
            Int64(positions[count].rounded(.up)) + reach + 1
        )
    }

    /// Keep pitch off: every output frame interpolated at p(n) with the
    /// cutoff of r(n) = p(n+1) − p(n), a chunk at a time, the source read
    /// ahead to the chunk's reach and dropped behind the map's steepest
    /// reach: a later chunk's `lo` can fall below this one's when the rate
    /// jumps, never below that bound.
    private static func renderVarispeed(
        _ map: RampAudioMap, source: RampSourceReader, frames: Int64, writer: RampCAFWriter,
        cancelled: () -> Bool, progress: ((Double) -> Void)?
    ) throws {
        let resampler = RampAudioResampler()
        let channels = source.channels
        var steepest = 0.0
        for i in 1..<map.clipTicks.count {
            steepest = max(
                steepest,
                (map.sourceTicks[i] - map.sourceTicks[i - 1])
                    / Double(map.clipTicks[i] - map.clipTicks[i - 1]))
        }
        // + 1 past `chunk`'s own, + 1 for a measured rate a rounding above the slope.
        let behind = Int64(RampAudioResampler.reach(rate: steepest)) + 2
        var out = [Float](repeating: 0, count: chunkFrames * channels)
        var n: Int64 = 0
        while n < frames {
            if cancelled() { throw RenderError.cancelled }
            let count = Int(min(Int64(chunkFrames), frames - n))
            let span = chunk(map, from: n, count: count)
            try source.fill(through: span.hi)
            source.drop(before: Int64(span.positions[0].rounded(.down)) - behind)
            for i in 0..<count {
                let p = span.positions[i]
                let r = span.positions[i + 1] - p
                for c in 0..<channels {
                    out[i * channels + c] = resampler.value(at: p, rate: r) {
                        source.sample($0, channel: c)
                    }
                }
            }
            try writer.write(out, frames: count)
            n += Int64(count)
            progress?(Double(n) / Double(frames))
        }
    }
}

/// The source's audio as 48 kHz float frames, read forward in chunks by an
/// `AVAssetReader` and dropped behind the reader's caller: never the whole
/// window. Frame k is the track's time k / 48 000 (each buffer placed by its
/// presentation time, a gap read as zeros, an overlap trimmed); a frame
/// before 0, or past the end of the file, reads zero.
final class RampSourceReader {
    let channels: Int
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var base: Int64
    private var samples: [Float] = []
    private var started = false
    private var exhausted = false
    /// A dead prefix is cut once it is at least this many frames.
    private static let dropFrames: Int64 = 65_536

    private var end: Int64 { base + Int64(samples.count / channels) }

    init(asset: AVAsset, track: AVAssetTrack, channels: Int, from start: Int64) throws {
        self.channels = channels
        base = max(0, start)
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag =
            channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: RampAudioRenderer.sampleRate,
            AVNumberOfChannelsKey: channels,
            AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw RampAudioRenderer.RenderError.unreadable(error.localizedDescription)
        }
        if base > 0 {
            reader.timeRange = CMTimeRange(
                start: CMTime(value: base, timescale: CMTimeScale(RampAudioRenderer.sampleRate)),
                duration: .positiveInfinity)
        }
        output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw RampAudioRenderer.RenderError.unreadable("the reader refused the track")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw RampAudioRenderer.RenderError.unreadable(
                reader.error?.localizedDescription ?? "the reader did not start")
        }
    }

    deinit { if reader.status == .reading { reader.cancelReading() } }

    /// Frame `k`'s sample on channel `c`.
    func sample(_ k: Int64, channel c: Int) -> Float {
        guard k >= base, k < end else { return 0 }
        return samples[Int(k - base) * channels + c]
    }

    /// Reads on until frame `k` is held or the file has ended.
    func fill(through k: Int64) throws {
        while !exhausted, end <= k {
            guard let buffer = output.copyNextSampleBuffer() else {
                exhausted = true
                if reader.status == .failed {
                    throw RampAudioRenderer.RenderError.failed(
                        reader.error?.localizedDescription ?? "the reader failed")
                }
                return
            }
            try append(buffer)
        }
    }

    /// Lets go of the frames before `k`.
    func drop(before k: Int64) {
        let dead = min(k, end) - base
        guard dead >= Self.dropFrames else { return }
        samples.removeFirst(Int(dead) * channels)
        base += dead
    }

    /// Throws on a buffer it cannot read whole, so a failed read is never
    /// written as a good render.
    private func append(_ buffer: CMSampleBuffer) throws {
        let frames = Int(CMSampleBufferGetNumSamples(buffer))
        guard frames > 0 else { return }
        guard let block = CMSampleBufferGetDataBuffer(buffer) else {
            throw RampAudioRenderer.RenderError.failed("a source buffer of \(frames) frames had no data")
        }
        let stamp = CMTimeConvertScale(
            CMSampleBufferGetPresentationTimeStamp(buffer),
            timescale: CMTimeScale(RampAudioRenderer.sampleRate),
            method: .roundHalfAwayFromZero)
        let at = stamp.isNumeric ? stamp.value : end
        if !started {
            started = true
            base = min(base, max(0, at))
        }
        if at > end {
            samples.append(contentsOf: [Float](repeating: 0, count: Int(at - end) * channels))
        }
        var values = [Float](repeating: 0, count: frames * channels)
        let length = values.count * 4
        guard CMBlockBufferGetDataLength(block) >= length else {
            throw RampAudioRenderer.RenderError.failed(
                "a source buffer held \(CMBlockBufferGetDataLength(block)) bytes for \(frames) frames")
        }
        let status = values.withUnsafeMutableBytes { raw -> OSStatus in
            guard let pointer = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: length, destination: pointer)
        }
        guard status == kCMBlockBufferNoErr else {
            throw RampAudioRenderer.RenderError.failed("a source buffer could not be copied (\(status))")
        }
        let skip = max(0, end - at)
        guard skip < Int64(frames) else { return }
        samples.append(contentsOf: values[(Int(skip) * channels)...])
    }
}
