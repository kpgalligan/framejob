import AVFoundation

/// One automation point's Amount on a retimed segment (spec §11 AU-87): the
/// clip tick it sits at, counted from the segment's start.
struct MixPoint: Equatable {
    let at: Ticks
    let amount: Double
}

/// A retimed segment's window crossfaded with its isolated voice (spec §11
/// AU-55 as amended, #387): `dry + a·(iso − dry)` written to a file, because
/// a retimed segment's Amount cannot be a crossfade in the tap (AU-53 lines
/// the two up only at ×1).
struct MixJob: Equatable {
    /// The window both files cover (`RetimedSound.window`).
    let window: IsolationWindow
    /// The window's isolated render.
    let isolated: URL
    /// The base Amount, 0…1; read only when `points` is empty.
    let amount: Double
    /// The segment's `[clip tick, source tick]` map, and the Amount at each
    /// automation point: both empty unless an action moves the Amount.
    let map: [[Ticks]]
    let points: [MixPoint]
}

/// The mix's writer and its name in `cache/isolated/`.
enum IsolationMix {
    /// Part of the name: bump it whenever the written file changes.
    static let version = 1

    struct Job {
        /// 48 kHz with no MP3 trim (`RampAudioCache.renderSource`'s copy, or
        /// a reversed file): the source the composition plays.
        let source: URL
        let job: MixJob
        /// A `.caf`; written as "<destination>.partial", then renamed.
        let destination: URL
    }

    /// `<media>-<16 hex>.caf`: FNV-1a 64 over the isolated file's name (which
    /// carries the media, the reversal and the window), `version`, the
    /// Amount, and the map and points when an action moves the Amount.
    /// Nothing else shapes the file.
    static func name(media: UInt32, job: MixJob) -> String {
        func pairs(_ list: [[Ticks]]) -> String {
            list.map { $0.map(String.init).joined(separator: ":") }.joined(separator: ",")
        }
        var key = "mix|v\(version)|\(job.isolated.lastPathComponent)|a\(job.amount)"
        if !job.points.isEmpty {
            key += "|m\(pairs(job.map))|p"
                + job.points.map { "\($0.at):\($0.amount)" }.joined(separator: ",")
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return "\(media)-" + String(repeating: "0", count: max(0, 16 - hex.count)) + hex + ".caf"
    }

    /// The segment's Amount at each automation point, in clip ticks from its
    /// start; empty when no point moves it from `base` (the tap's rule,
    /// `AudioIsolationTrack.amounts`).
    static func points(of s: PlanSegment, base: Double, dsp: AudioDSPParameters) -> [MixPoint] {
        guard let automation = dsp.automation(for: s) else { return [] }
        let out = automation.points.map {
            MixPoint(at: $0.at - s.start, amount: min(max($0.audio.isolation, 0), 1))
        }
        return out.allSatisfy { $0.amount == min(max(base, 0), 1) } ? [] : out
    }

    /// The Amount per source frame of a job whose `points` move it: each
    /// frame's clip time through the inverse of `map` (held at the map's
    /// ends), then the straight line between the points in clip time, as the
    /// tap draws it in composition time (AU-87). Frames ascend, so both
    /// walks only move forward.
    struct Curve {
        private let clip: [Double]
        private let source: [Double]
        private let points: [MixPoint]
        private var leg = 0
        private var point = 0

        /// Nil for a map that cannot be inverted.
        init?(_ job: MixJob) {
            guard !job.points.isEmpty, job.map.count >= 2,
                job.map.allSatisfy({ $0.count > 1 })
            else { return nil }
            clip = job.map.map { Double($0[0]) }
            source = job.map.map { Double($0[1]) }
            for i in 1..<source.count where source[i] <= source[i - 1] { return nil }
            points = job.points
        }

        mutating func amount(atSourceFrame frame: Int64) -> Float {
            let x = Double(frame) * RampAudioRenderer.ticksPerFrame
            while leg + 2 < source.count, source[leg + 1] <= x { leg += 1 }
            let span = source[leg + 1] - source[leg]
            let u = min(max((x - source[leg]) / span, 0), 1)
            let t = clip[leg] + u * (clip[leg + 1] - clip[leg])
            while point + 1 < points.count, Double(points[point + 1].at) <= t { point += 1 }
            let a = points[point]
            guard point + 1 < points.count, t > Double(a.at) else { return Float(a.amount) }
            let b = points[point + 1]
            let width = Double(b.at - a.at)
            guard width > 0 else { return Float(b.amount) }
            return Float(a.amount + (b.amount - a.amount) * min((t - Double(a.at)) / width, 1))
        }
    }

    /// Writes the window of `source` crossfaded with the isolated render, in
    /// the source's own channel count (a mono source stays mono, so the
    /// channel pick downstream reads what it read dry). A frame the isolated
    /// render does not hold stays dry. Blocking, on `RampAudioRenders`'
    /// queue; its errors are the isolation's (the Status row shows them).
    static func render(_ job: Job, cancelled: () -> Bool) throws {
        typealias Failure = IsolationRenderer.RenderError
        let partial = URL(fileURLWithPath: job.destination.path + ".partial")
        try? FileManager.default.removeItem(at: partial)
        var writer: RampCAFWriter?
        do {
            let asset = AVURLAsset(url: job.source)
            guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio),
                let signature = CompositionBuilder.audioFormatSignature(of: track)
            else {
                throw Failure.unreadable("\(job.source.lastPathComponent) has no readable audio")
            }
            let trim = MP3Gapless.leadingTrim(of: job.source, track: track)
            guard !AudioRateCopy.needsCopy(signature, trim: trim) else {
                throw Failure.unreadable(
                    "\(job.source.lastPathComponent) is not a 48 kHz source with no trim")
            }
            let window = job.job.window
            guard window.firstFrame >= 0, window.endFrame > window.firstFrame else {
                throw Failure.failed(
                    "the window [\(window.firstFrame), \(window.endFrame)) holds no frame")
            }
            guard let iso = IsolatedAudioStore.shared.audio(at: job.job.isolated) else {
                throw Failure.unreadable("its isolated voice cannot be read")
            }
            let channels = Int(min(max(signature.channels, 1), 2))
            let reader = try RampSourceReader(
                asset: asset, track: track, channels: channels, from: window.firstFrame)
            writer = try RampCAFWriter(url: partial, channels: channels)
            var curve = Curve(job.job)
            let base = Float(min(max(job.job.amount, 0), 1))
            let chunk: Int64 = 65_536
            var out = [Float](repeating: 0, count: Int(chunk) * channels)
            var at = window.firstFrame
            while at < window.endFrame {
                if cancelled() { throw Failure.cancelled }
                let upTo = min(at + chunk, window.endFrame)
                try reader.fill(through: upTo)
                for k in at..<upTo {
                    let n = Int(k - at)
                    let w = Int(k - window.firstFrame)
                    let a = curve?.amount(atSourceFrame: k) ?? base
                    for c in 0..<channels {
                        var x = reader.sample(k, channel: c)
                        if w < iso.frames {
                            x += a * (iso.samples(channel: min(c, iso.channels - 1))[w] - x)
                        }
                        out[n * channels + c] = x
                    }
                }
                try writer!.write(out, frames: Int(upTo - at))
                reader.drop(before: upTo)
                at = upTo
            }
            try writer!.close()
            writer = nil
            guard rename(partial.path, job.destination.path) == 0 else {
                throw Failure.failed("the file could not be moved into place (errno \(errno))")
            }
        } catch {
            writer?.abandon()
            try? FileManager.default.removeItem(at: partial)
            switch error {
            case let known as Failure: throw known
            case RampAudioRenderer.RenderError.unreadable(let why): throw Failure.unreadable(why)
            case RampAudioRenderer.RenderError.failed(let why): throw Failure.failed(why)
            case RampAudioRenderer.RenderError.cancelled: throw Failure.cancelled
            default: throw Failure.failed(error.localizedDescription)
            }
        }
    }
}
