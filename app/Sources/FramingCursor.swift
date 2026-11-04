import Foundation

/// `reframe_clip`'s `subjects` for `follow: cursor` (road map "creator-jobs" VR5, spec §11
/// VR-50 (i)): a recorded cursor read into the JSON the core's strict reader takes,
/// `{samples: [], shots: [], cursor: [{t, x, y, click?, typing?}]}` — `t` in forward-media
/// source ticks, `x`, `y` 0…1 of the picture from its top-left (CJ-22).
///
/// - **The path.** Per window (`FramingAnalysis.windows`), CU-25's `path` at `smoothing` 0.5,
///   its step `max(60_000, ⌈Σ window lengths ÷ 90_000⌉)` ticks, so a long clip stays under the
///   core's sample cap.
/// - **The clicks.** `events {clicks}`: each down click (`down == 1`) is a `click: true` point
///   at its own `t`, and a path point at that `t` is dropped.
/// - **Typing.** `events {typing}`: a point inside a stretch `[from, to]` is `typing: true`.
///
/// Positions are movie px ÷ the media's width and height, clamped to 0…1. The files are
/// `AutoZoom.cursorFiles` / `readTracks`'. Reads files only, so any thread; names no `rc_*`
/// (`ReelCursor` is the core's edge).
enum FramingCursor {
    /// CU-21's smoothing the path is read at.
    static let smoothing = 0.5
    /// The finest path step the core takes (10 a second), and the most samples a read asks.
    private static let minStep: Ticks = 60_000
    private static let mostSamples: Ticks = 90_000

    /// `{samples: [], shots: [], cursor: [...]}` for one clip's windows; throws the core's
    /// sentence.
    static func read(_ track: ReelCursor, media: MediaSnapshot, windows: [ClosedRange<Ticks>])
        throws -> [String: Any]
    {
        let total = windows.reduce(Ticks(0)) { $0 + ($1.upperBound - $1.lowerBound) }
        let step = max(minStep, (total + mostSamples - 1) / mostSamples)
        var path: [(t: Ticks, x: Double, y: Double)] = []
        var clicks: [(t: Ticks, x: Double, y: Double)] = []
        var typing: [ClosedRange<Ticks>] = []
        for window in windows {
            let (from, to) = (window.lowerBound, window.upperBound + 1)
            let read = try object(
                track,
                ["path": ["from": from, "to": to, "step": step, "smoothing": smoothing]])
            let ts = (read["t"] as? [NSNumber]) ?? []
            let xs = (read["x"] as? [NSNumber]) ?? []
            let ys = (read["y"] as? [NSNumber]) ?? []
            for i in 0..<min(ts.count, xs.count, ys.count) {
                path.append((ts[i].int64Value, xs[i].doubleValue, ys[i].doubleValue))
            }
            let events = try object(
                track, ["events": ["from": from, "to": to, "kinds": ["clicks", "typing"]]])
            for click in (events["clicks"] as? [[String: Any]]) ?? [] {
                guard (click["down"] as? NSNumber)?.intValue == 1,
                    let t = (click["t"] as? NSNumber)?.int64Value,
                    let x = (click["x"] as? NSNumber)?.doubleValue,
                    let y = (click["y"] as? NSNumber)?.doubleValue
                else { continue }
                clicks.append((t, x, y))
            }
            for stretch in (events["typing"] as? [[String: Any]]) ?? [] {
                guard let a = (stretch["from"] as? NSNumber)?.int64Value,
                    let b = (stretch["to"] as? NSNumber)?.int64Value, a <= b
                else { continue }
                typing.append(a...b)
            }
        }
        let clickTimes = Set(clicks.map(\.t))
        var merged = clicks.map { (t: $0.t, x: $0.x, y: $0.y, click: true) }
        merged += path.filter { !clickTimes.contains($0.t) }.map {
            (t: $0.t, x: $0.x, y: $0.y, click: false)
        }
        merged.sort { $0.t < $1.t }
        let (w, h) = (Double(media.width), Double(media.height))
        var cursor: [[String: Any]] = []
        var last: Ticks?
        for p in merged where w > 0 && h > 0 && p.x.isFinite && p.y.isFinite {
            if let last, p.t <= last { continue }
            last = p.t
            var point: [String: Any] = [
                "t": p.t, "x": min(max(p.x / w, 0), 1), "y": min(max(p.y / h, 0), 1),
            ]
            if p.click { point["click"] = true }
            if typing.contains(where: { $0.contains(p.t) }) { point["typing"] = true }
            cursor.append(point)
        }
        return ["samples": [Any](), "shots": [Any](), "cursor": cursor]
    }

    /// Per clip, any thread: its media's cursor file found (`AutoZoom.cursorFiles`) and opened
    /// (`readTracks`, once per media), then `read` over the clip's `FramingAnalysis.windows`. A
    /// clip whose file is missing or unreadable, or that has no windows, is omitted.
    static func subjects(_ clips: [UInt32], in project: ReelProject) -> [UInt32: [String: Any]] {
        let snapshot = project.snapshot
        var tracks: [UInt32: ReelCursor?] = [:]
        var out: [UInt32: [String: Any]] = [:]
        for id in clips {
            guard let clip = snapshot.clip(id),
                let entry = FramingAnalysis.windows(clips: [id], in: project).first,
                let media = snapshot.media(entry.media)
            else { continue }
            if tracks[media.id] == nil {
                let files = try? AutoZoom.cursorFiles([clip], in: snapshot)
                tracks[media.id] = files.flatMap { try? AutoZoom.readTracks($0)[media.id] }
            }
            guard let track = tracks[media.id] ?? nil,
                let read = try? read(track, media: media, windows: entry.windows)
            else { continue }
            out[id] = read
        }
        return out
    }

    /// One request's answer as an object; throws the core's sentence.
    private static func object(_ track: ReelCursor, _ request: [String: Any]) throws
        -> [String: Any]
    {
        let data = try JSONSerialization.data(withJSONObject: request)
        let text = try track.query(String(decoding: data, as: UTF8.self))
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
    }
}
