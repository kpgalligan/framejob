import AVFoundation

/// Keep pitch on inside a ramp (spec §11 SR-11, SR-12 (i)): the held spans
/// keep their pitch through SR-8's arm and the ramp spans glide like tape
/// through the keep-pitch-off arm, the whole clip ONE file.
///
/// Three renders, then one streamed mix. The off arm renders the whole map
/// into `<destination>.glide`; each held span is rendered ALONE by SR-8's arm
/// on its own two-point map (its constant rate, from the source under its
/// first frame) into `<destination>.held-<i>`, so the pitch-shifter never
/// sees a rate change; then the output is read back chunk by chunk as
/// `y = w·held + (1 − w)·glide`, `w` 1 inside a held span but over the
/// crossfade at each of its ends that meets a glide, 0 outside every held
/// span. Every temporary is removed on every exit; nothing is held whole.
extension RampAudioRenderer {
    /// SR-11's crossfade, 10 ms at 48 kHz — or half the held span when shorter.
    static let crossfadeFrames: Int64 = 480

    /// The output frames of `[0, D) − glide`: each held span `[a, b)` of clip
    /// ticks as `[⌈a / 12.5⌉, ⌈b / 12.5⌉)`, the last one ending at `frames`.
    static func heldFrames(glide: [Range<Ticks>], frames: Int64) -> [Range<Int64>] {
        func frame(_ t: Ticks) -> Int64 { min(frames, (2 * max(0, t) + 24) / 25) }
        var held: [Range<Int64>] = []
        var cursor: Int64 = 0
        for span in glide.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            let from = frame(span.lowerBound)
            if from > cursor { held.append(cursor..<from) }
            cursor = max(cursor, frame(span.upperBound))
        }
        if cursor < frames { held.append(cursor..<frames) }
        return held
    }

    /// The held render's weight at output frame `n` of `span`: 1, but over
    /// `X = min(480, length / 2)` frames at the span's start when it is not
    /// the clip's (`(n − fa + 0.5) / X`) and at its end when it is not the
    /// clip's (`(fb − n − 0.5) / X`), the lesser when both; 0 outside it.
    static func heldWeight(_ n: Int64, span: Range<Int64>, frames: Int64) -> Float {
        guard span.contains(n) else { return 0 }
        let fade = min(Double(crossfadeFrames), Double(span.count) / 2)
        var w = 1.0
        if span.lowerBound > 0 { w = min(w, (Double(n - span.lowerBound) + 0.5) / fade) }
        if span.upperBound < frames { w = min(w, (Double(span.upperBound - n) - 0.5) / fade) }
        return Float(max(0, min(1, w)))
    }

    static func renderHybrid(
        _ job: Job, cancelled: () -> Bool, progress: ((Double) -> Void)?
    ) throws -> Report {
        let started = Date()
        if let why = job.map.problem { throw RenderError.invalidMap(why) }
        let duration = job.map.clipTicks[job.map.clipTicks.count - 1]
        let frames = Int64((Double(duration) / ticksPerFrame).rounded())
        let base = job.destination.path
        let glideURL = URL(fileURLWithPath: base + ".glide")
        let partial = URL(fileURLWithPath: base + ".partial")
        var temporaries = [glideURL]
        defer { for url in temporaries { try? FileManager.default.removeItem(at: url) } }
        let glided = try render(
            Job(source: job.source, map: job.map, keepPitch: false, destination: glideURL),
            cancelled: cancelled)
        var held: [(span: Range<Int64>, url: URL)] = []
        var first: Report?
        for (i, span) in heldFrames(glide: job.glide, frames: frames).enumerated() {
            let url = URL(fileURLWithPath: base + ".held-\(i)")
            temporaries.append(url)
            let report = try render(
                Job(source: job.source, map: heldMap(job.map, span: span), keepPitch: true,
                    destination: url),
                cancelled: cancelled)
            if first == nil { first = report }
            held.append((span, url))
        }
        try? FileManager.default.removeItem(at: partial)
        var writer: RampCAFWriter?
        do {
            writer = try RampCAFWriter(url: partial, channels: glided.channels)
            try mix(
                glide: glideURL, held: held, frames: frames, channels: glided.channels,
                writer: writer!, cancelled: cancelled, progress: progress)
            try writer!.close()
            writer = nil
            guard rename(partial.path, job.destination.path) == 0 else {
                throw RenderError.failed("the file could not be moved into place (errno \(errno))")
            }
        } catch {
            writer?.abandon()
            try? FileManager.default.removeItem(at: partial)
            if let known = error as? RenderError { throw known }
            throw RenderError.failed(error.localizedDescription)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: job.destination.path))?[
            .size] as? NSNumber
        return Report(
            frames: frames, channels: glided.channels,
            wallSeconds: Date().timeIntervalSince(started), bytes: size?.int64Value ?? 0,
            oversampling: first?.oversampling, latencyFrames: first?.latencyFrames,
            delayFrames: first?.delayFrames, pulledFrames: nil)
    }

    /// One held span's own map: `[0, L] → [s0, s0 + r·L]`, s0 the source under
    /// its first frame, r the map's slope at its middle, L its length in
    /// ticks rounded up.
    private static func heldMap(_ map: RampAudioMap, span: Range<Int64>) -> RampAudioMap {
        let start = Double(span.lowerBound) * ticksPerFrame
        let middle = (Double(span.lowerBound) + Double(span.upperBound)) / 2 * ticksPerFrame
        let s0 = map.source(at: start)
        let rate = map.source(at: middle + 0.5) - map.source(at: middle - 0.5)
        let length = Ticks((Double(span.count) * ticksPerFrame).rounded(.up))
        return RampAudioMap(clipTicks: [0, length], sourceTicks: [s0, s0 + rate * Double(length)])
    }

    /// One reader over a render this file just wrote — a CAF whose name does
    /// not end `.caf`, so its type is named.
    private static func reader(_ url: URL, channels: Int) throws -> RampSourceReader {
        let asset = AVURLAsset(url: url, options: [AVURLAssetOverrideMIMETypeKey: "audio/x-caf"])
        guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio) else {
            throw RenderError.failed("\(url.lastPathComponent) has no audio track")
        }
        return try RampSourceReader(asset: asset, track: track, channels: channels, from: 0)
    }

    /// The streamed mix: the glide read once, each held render opened at its
    /// span and let go after it, a chunk written at a time.
    private static func mix(
        glide url: URL, held: [(span: Range<Int64>, url: URL)], frames: Int64, channels: Int,
        writer: RampCAFWriter, cancelled: () -> Bool, progress: ((Double) -> Void)?
    ) throws {
        let glide = try reader(url, channels: channels)
        var out = [Float](repeating: 0, count: chunkFrames * channels)
        var index = 0
        var open: RampSourceReader?
        var n: Int64 = 0
        while n < frames {
            if cancelled() { throw RenderError.cancelled }
            let count = Int(min(Int64(chunkFrames), frames - n))
            try glide.fill(through: n + Int64(count))
            for i in 0..<count {
                let m = n + Int64(i)
                while index < held.count, held[index].span.upperBound <= m {
                    index += 1
                    open = nil
                }
                guard index < held.count, held[index].span.contains(m) else {
                    for c in 0..<channels { out[i * channels + c] = glide.sample(m, channel: c) }
                    continue
                }
                let span = held[index].span
                if open == nil { open = try reader(held[index].url, channels: channels) }
                let k = m - span.lowerBound
                try open!.fill(through: k + 1)
                let w = heldWeight(m, span: span, frames: frames)
                for c in 0..<channels {
                    let g = glide.sample(m, channel: c)
                    let h = open!.sample(k, channel: c)
                    out[i * channels + c] = w == 1 ? h : w * h + (1 - w) * g
                }
                open!.drop(before: k)
            }
            try writer.write(out, frames: count)
            glide.drop(before: n + Int64(count))
            n += Int64(count)
            progress?(Double(n) / Double(frames))
        }
    }
}
