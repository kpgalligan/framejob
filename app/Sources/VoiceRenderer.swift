import AVFoundation
import AudioToolbox

/// A clip window's voice effect rendered offline into a file (spec §11
/// AU-142), E8's contract line by line: 48 kHz STEREO connections (reverb
/// given mono aborts the process), an `AVAudioPlayerNode` playing a stereo
/// input file through `VoiceChain.units`, schedule → `start()` → `play()`,
/// every `renderOffline` call asking for 4,096 frames (the output is
/// byte-identical only at a fixed call size), float CAF out through
/// `RampCAFWriter`.
///
/// The input file (`writeInput`) is the window of the source the composition
/// plays — or, when the clip isolates, `dry + i·(iso − dry)` from its
/// isolated render (AU-143) — always stereo, a mono source in both channels.
/// The chain's latency `L` (the sum of its units' `auAudioUnit.latency` at
/// 48 kHz, read after `start()`) is discarded as `IsolationRenderer`
/// discards its 4440: `L + window` frames are rendered (the player gives
/// silence once the input ends), the first `L` dropped, and exactly the
/// window's length written, so kept frame 0 is the window's first frame and
/// the tail is cut at the clip's end. The window renders cold, with no
/// preroll. A mono source's output is `(L+R)/2`; the makeup gain is applied
/// in float before the write.
///
/// Blocking, on the caller's queue: `RampAudioRenders` renders into
/// `cache/voiced/`, named by `VoiceCache`.
enum VoiceRenderer {
    static let sampleRate = 48_000
    static let callFrames: AVAudioFrameCount = 4096

    struct Job {
        /// 48 kHz with no MP3 trim (`RampAudioCache.renderSource`'s copy, or
        /// a reversed file).
        let source: URL
        let job: VoiceJob
        /// A `.caf`; written as "<destination>.partial", then renamed.
        let destination: URL
    }

    struct Report: Equatable {
        /// The window's length.
        let frames: Int64
        /// The source's, clamped 1…2.
        let channels: Int
        let units: Int
        /// The chain's summed latency at 48 kHz, discarded.
        let latencyFrames: Int
        let wallSeconds: Double
    }

    enum RenderError: LocalizedError, Equatable {
        case unreadable(String), failed(String), cancelled

        var errorDescription: String? {
            switch self {
            case .unreadable(let why): return "The voice effect's source cannot be read: \(why)."
            case .failed(let why): return "The voice effect could not be rendered: \(why)."
            case .cancelled: return "The voice effect's render was cancelled."
            }
        }
    }

    /// The source's audio track and its channel count (1 or 2); refuses a
    /// source the composition would not play as it is.
    private static func open(_ source: URL) throws -> (AVURLAsset, AVAssetTrack, Int) {
        let asset = AVURLAsset(url: source)
        guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio) else {
            throw RenderError.unreadable("\(source.lastPathComponent) has no audio track")
        }
        guard let signature = CompositionBuilder.audioFormatSignature(of: track) else {
            throw RenderError.unreadable("\(source.lastPathComponent)'s audio format cannot be read")
        }
        let trim = MP3Gapless.leadingTrim(of: source, track: track)
        guard !AudioRateCopy.needsCopy(signature, trim: trim) else {
            throw RenderError.unreadable(
                "\(source.lastPathComponent) is \(Int(signature.sampleRate)) Hz"
                    + (trim > .zero ? " with an MP3 encoder delay" : "")
                    + "; only a 48 kHz source with no trim is rendered")
        }
        return (asset, track, Int(min(max(signature.channels, 1), 2)))
    }

    /// Writes "<destination>.input.caf": the window, stereo, crossfaded with
    /// the isolated render when the job names one (AU-143).
    static func writeInput(_ job: Job, cancelled: () -> Bool) throws -> URL {
        let url = URL(fileURLWithPath: job.destination.path + ".input.caf")
        try? FileManager.default.removeItem(at: url)
        var writer: RampCAFWriter?
        do {
            let (asset, track, channels) = try open(job.source)
            let window = job.job.window
            let frames = window.endFrame - window.firstFrame
            guard window.firstFrame >= 0, frames > 0 else {
                throw RenderError.failed(
                    "the window [\(window.firstFrame), \(window.endFrame)) holds no frame")
            }
            var isolated: IsolatedAudio?
            if let file = job.job.isolated {
                guard let audio = IsolatedAudioStore.shared.audio(at: file) else {
                    throw RenderError.unreadable("its isolated voice cannot be read")
                }
                isolated = audio
            }
            let i = Float(min(max(job.job.isolation, 0), 1))
            let source = try RampSourceReader(
                asset: asset, track: track, channels: channels, from: window.firstFrame)
            writer = try RampCAFWriter(url: url, channels: 2)
            let chunk: Int64 = 65_536
            var out = [Float](repeating: 0, count: Int(chunk) * 2)
            var at = window.firstFrame
            while at < window.endFrame {
                if cancelled() { throw RenderError.cancelled }
                let upTo = min(at + chunk, window.endFrame)
                try source.fill(through: upTo)
                for k in at..<upTo {
                    let n = Int(k - at)
                    for c in 0..<2 {
                        var x = source.sample(k, channel: min(c, channels - 1))
                        if let iso = isolated {
                            let w = Int(k - window.firstFrame)
                            let wet = w < iso.frames
                                ? iso.samples(channel: min(c, iso.channels - 1))[w] : 0
                            x += i * (wet - x)
                        }
                        out[2 * n + c] = x
                    }
                }
                try writer!.write(out, frames: Int(upTo - at))
                source.drop(before: upTo)
                at = upTo
            }
            try writer!.close()
            writer = nil
            return url
        } catch {
            writer?.abandon()
            try? FileManager.default.removeItem(at: url)
            throw reworded(error)
        }
    }

    static func render(_ job: Job, cancelled: () -> Bool) throws -> Report {
        let started = Date()
        let partial = URL(fileURLWithPath: job.destination.path + ".partial")
        try? FileManager.default.removeItem(at: partial)
        var writer: RampCAFWriter?
        var input: URL?
        defer { if let input { try? FileManager.default.removeItem(at: input) } }
        do {
            let (_, _, channels) = try open(job.source)
            let settings = job.job.settings
            let frames = job.job.window.endFrame - job.job.window.firstFrame
            let units = try VoiceChain.units(for: settings)
            guard !units.isEmpty else { throw RenderError.failed("the voice is inert") }
            input = try writeInput(job, cancelled: cancelled)
            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: Double(sampleRate), channels: 2)
            else { throw RenderError.failed("no stereo float format") }
            let file = try AVAudioFile(forReading: input!)
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            do {
                try engine.enableManualRenderingMode(
                    .offline, format: format, maximumFrameCount: callFrames)
            } catch {
                throw RenderError.failed(
                    "the voice engine refused offline rendering: \(error.localizedDescription)")
            }
            engine.attach(player)
            units.forEach { engine.attach($0) }
            var previous: AVAudioNode = player
            for unit in units {
                engine.connect(previous, to: unit, format: format)
                previous = unit
            }
            engine.connect(previous, to: engine.mainMixerNode, format: format)
            player.scheduleFile(file, at: nil)
            do {
                try engine.start()
            } catch {
                throw RenderError.failed(
                    "the voice engine did not start: \(error.localizedDescription)")
            }
            defer {
                player.stop()
                engine.stop()
            }
            let latency = units.reduce(0) { sum, unit in
                let seconds = (unit as? AVAudioUnit)?.auAudioUnit.latency ?? 0
                return sum + Int((seconds * Double(sampleRate)).rounded())
            }
            player.play()
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat, frameCapacity: callFrames)
            else { throw RenderError.failed("no render buffer") }
            writer = try RampCAFWriter(url: partial, channels: channels)
            let gain = VoiceChain.makeup(settings)
            let discard = Int64(latency)
            var out = [Float](repeating: 0, count: Int(callFrames) * channels)
            var rendered: Int64 = 0
            var written: Int64 = 0
            while written < frames {
                if cancelled() { throw RenderError.cancelled }
                let status: AVAudioEngineManualRenderingStatus
                do {
                    status = try engine.renderOffline(callFrames, to: buffer)
                } catch {
                    throw RenderError.failed("renderOffline: \(error.localizedDescription)")
                }
                guard status == .success else {
                    throw RenderError.failed("renderOffline answered status \(status.rawValue)")
                }
                let got = Int64(buffer.frameLength)
                if got == 0 { throw RenderError.failed("renderOffline rendered no frames") }
                guard let data = buffer.floatChannelData else {
                    throw RenderError.failed("a render buffer had no samples")
                }
                let from = max(0, discard - rendered)
                let upTo = min(got, discard + frames - rendered)
                if upTo > from {
                    let count = Int(upTo - from)
                    for i in 0..<count {
                        let l = data[0][Int(from) + i]
                        let r = data[1][Int(from) + i]
                        if channels == 1 {
                            out[i] = (l + r) * 0.5 * gain
                        } else {
                            out[2 * i] = l * gain
                            out[2 * i + 1] = r * gain
                        }
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
                frames: frames, channels: channels, units: units.count, latencyFrames: latency,
                wallSeconds: Date().timeIntervalSince(started))
        } catch {
            writer?.abandon()
            try? FileManager.default.removeItem(at: partial)
            throw reworded(error)
        }
    }

    /// The reader's, the writer's and the chain's errors in this renderer's
    /// words.
    private static func reworded(_ error: Error) -> RenderError {
        switch error {
        case let known as RenderError: return known
        case RampAudioRenderer.RenderError.unreadable(let why): return .unreadable(why)
        case RampAudioRenderer.RenderError.failed(let why): return .failed(why)
        case RampAudioRenderer.RenderError.cancelled: return .cancelled
        default: return .failed(error.localizedDescription)
        }
    }
}
