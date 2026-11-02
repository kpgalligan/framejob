import Foundation

/// `get_cursor_events`' arithmetic (road map "creator-jobs" CU5, spec §11
/// CU-53), pure and named no `rc_*`: the asked window mapped to the file's
/// source ticks, each event mapped back to the answer's time and kept inside
/// the window, the clip's region frame Q, the merge by time and the page.
/// `AgentServer+Cursor.swift` calls it; the reads go through `ReelCursor`'s
/// typed `events` and `path` (`CursorValues.swift`).
enum CursorEventsAnswer {
    /// The most rows one answer holds: events of every asked kind and path
    /// samples together (CU-53 (e)).
    static let pageSize = 5_000
    /// The path's step in source ticks: the core's 10 Hz bound (CU-53 (d)).
    static let pathStep: Ticks = 60_000

    /// What a call may ask for, in the order a tick's rows are listed.
    enum Kind: String, CaseIterable {
        case clicks, scrolls, shortcuts, typing, path
    }

    /// Every kind but `path`, when the call names none.
    static let defaultKinds: [Kind] = [.clicks, .scrolls, .shortcuts, .typing]

    /// The resolved call: kinds, the window in the answer's time, the path's
    /// smoothing and the media's size in source pixels.
    struct Request {
        let kinds: [Kind]
        let from: Ticks
        let to: Ticks
        let smoothing: Double
        let size: (width: Double, height: Double)
    }

    /// One row of the merged list, in the answer's time.
    enum Row {
        case click(CursorEvents.Click)
        case scroll(CursorEvents.Scroll)
        case shortcut(CursorEvents.Shortcut)
        case typing(from: Ticks, to: Ticks, marks: Int)
        case path(x: Double, y: Double)

        var order: Int {
            switch self {
            case .click: return 0
            case .scroll: return 1
            case .shortcut: return 2
            case .typing: return 3
            case .path: return 4
            }
        }
    }

    /// What the file answered, mapped and kept: each row with its time (a
    /// typing stretch's the later of its start and the window's), in no
    /// order yet. `clipTime` when the times are a clip's.
    struct Read {
        var rows: [(t: Ticks, row: Row)] = []
        var clipTime = false
    }

    /// `kinds` read (CU-53 (a)): absent is the default four; an empty list or
    /// a name outside the five is refused by name.
    static func kinds(_ names: [String]?) throws -> [Kind] {
        guard let names else { return defaultKinds }
        let all = Kind.allCases.map(\.rawValue).joined(separator: ", ")
        guard !names.isEmpty else {
            throw AgentServer.ToolError(message: "kinds is empty — name at least one of \(all).")
        }
        var kinds: [Kind] = []
        for name in names {
            guard let kind = Kind(rawValue: name) else {
                throw AgentServer.ToolError(
                    message: "kinds may hold only \(all), not \"\(name)\".")
            }
            if !kinds.contains(kind) { kinds.append(kind) }
        }
        return kinds
    }

    /// The forward source tick at clip tick `t` (CU-53 (b)): through the
    /// source map on a ramp, else `in + t × speed`.
    static func source(atClip t: Ticks, _ times: AnalysisClipTimes) -> Double {
        if let map = times.map { return map.source(atClip: Double(t)) }
        return Double(times.sourceIn) + Double(t) * times.speed
    }

    /// The source range a window reads: itself in media time; in clip time
    /// the window's ends mapped and widened to whole ticks, so the mapped
    /// events can be kept by their own clip time.
    static func sourceRange(_ request: Request, times: AnalysisClipTimes?) -> (Ticks, Ticks) {
        guard let times else { return (request.from, request.to) }
        let low = max(0, Ticks(source(atClip: request.from, times).rounded(.down)))
        let high = Ticks(source(atClip: request.to, times).rounded(.up)) + 1
        return (low, max(high, low + 1))
    }

    /// Reads the asked kinds of `track` over the window and maps them to the
    /// answer's time, keeping each inside `[from, to)` (a typing stretch
    /// when it overlaps). Throws the core's sentence.
    static func read(_ track: ReelCursor, _ request: Request, times: AnalysisClipTimes?) throws
        -> Read
    {
        let (low, high) = sourceRange(request, times: times)
        let time: (Int64) -> Ticks = { t in times.map { $0.clipTime(ofSource: t) } ?? t }
        let inside: (Ticks) -> Bool = { request.from <= $0 && $0 < request.to }
        var read = Read(clipTime: times != nil)
        let eventKinds = request.kinds.compactMap { CursorEventKind(rawValue: $0.rawValue) }
        if !eventKinds.isEmpty {
            let events = try track.events(from: low, to: high, kinds: eventKinds)
            for c in events.clicks ?? [] where inside(time(c.t)) {
                read.rows.append((time(c.t), .click(c)))
            }
            for s in events.scrolls ?? [] where inside(time(s.t)) {
                read.rows.append((time(s.t), .scroll(s)))
            }
            for k in events.shortcuts ?? [] where inside(time(k.t)) {
                read.rows.append((time(k.t), .shortcut(k)))
            }
            for stretch in events.typing ?? [] {
                let from = time(stretch.from)
                let to = time(stretch.to)
                guard to > request.from, from < request.to else { continue }
                read.rows.append(
                    (max(from, request.from), .typing(from: from, to: to, marks: stretch.marks)))
            }
        }
        if request.kinds.contains(.path) {
            let path = try track.path(
                from: low, to: high, step: pathStep, smoothing: request.smoothing)
            for i in path.t.indices where i < path.x.count && i < path.y.count {
                let t = time(path.t[i])
                if inside(t) { read.rows.append((t, .path(x: path.x[i], y: path.y[i]))) }
            }
        }
        return read
    }

    /// The rows one page holds, and the first time left out (CU-53 (e)):
    /// every row up to `pageSize`, then only the times before the first left
    /// out, so the rows at one tick are never split; a first tick holding
    /// more than a page is answered whole.
    static func page(_ rows: [(t: Ticks, row: Row)]) -> (rows: [(t: Ticks, row: Row)], next: Ticks?)
    {
        let sorted = rows.enumerated().sorted {
            ($0.element.t, $0.element.row.order, $0.offset)
                < ($1.element.t, $1.element.row.order, $1.offset)
        }.map(\.element)
        guard sorted.count > pageSize else { return (sorted, nil) }
        let next = sorted[pageSize].t
        var kept = sorted.prefix { $0.t < next }
        if kept.isEmpty {
            let first = sorted[0].t
            kept = sorted.prefix { $0.t == first }
            let after = sorted.first { $0.t > first }?.t
            return (Array(kept), after)
        }
        return (Array(kept), next)
    }

    /// A click's or a scroll's position in the clip's region frame (CU-53
    /// (c)): an offset in source pixels from the centre of the cropped rect,
    /// the frame `add_zoom_action`'s region takes.
    static func q(x: Double, y: Double, size: (width: Double, height: Double), crop: CropInsets)
        -> [Double]
    {
        [x - size.width / 2 - (crop.l - crop.r) / 2, y - size.height / 2 - (crop.t - crop.b) / 2]
    }

    /// The answer's fields but the caller's own (`media`, `clip`, `size`,
    /// `cursor_file`, `in_picture`, `project`). `crop` answers a clip's crop
    /// at a clip tick; it is asked only in clip time.
    static func answer(_ read: Read, _ request: Request, crop: (Ticks) -> CropInsets)
        -> [String: Any]
    {
        let (rows, next) = page(read.rows)
        var clicks: [[String: Any]] = []
        var scrolls: [[String: Any]] = []
        var shortcuts: [[String: Any]] = []
        var typing: [[String: Any]] = []
        var pathT: [Ticks] = []
        var pathX: [Double] = []
        var pathY: [Double] = []
        for (t, row) in rows {
            switch row {
            case .click(let c):
                var out: [String: Any] = [
                    "t": t, "button": c.button, "down": c.down, "count": c.count, "x": c.x,
                    "y": c.y,
                ]
                if read.clipTime { out["q"] = q(x: c.x, y: c.y, size: request.size, crop: crop(t)) }
                clicks.append(out)
            case .scroll(let s):
                var out: [String: Any] = ["t": t, "x": s.x, "y": s.y, "dx": s.dx, "dy": s.dy]
                if read.clipTime { out["q"] = q(x: s.x, y: s.y, size: request.size, crop: crop(t)) }
                scrolls.append(out)
            case .shortcut(let k):
                shortcuts.append(["t": t, "keys": k.keys, "code": k.code])
            case .typing(let from, let to, let marks):
                typing.append(["from": from, "to": to, "marks": marks])
            case .path(let x, let y):
                pathT.append(t)
                pathX.append(x)
                pathY.append(y)
            }
        }
        var result: [String: Any] = [
            "ok": true, "time": read.clipTime ? "clip" : "media", "from": request.from,
            "to": request.to, "count": rows.count,
        ]
        let kinds = request.kinds
        if kinds.contains(.clicks) { result["clicks"] = clicks }
        if kinds.contains(.scrolls) { result["scrolls"] = scrolls }
        if kinds.contains(.shortcuts) { result["shortcuts"] = shortcuts }
        if kinds.contains(.typing) { result["typing"] = typing }
        if kinds.contains(.path) {
            result["path"] = [
                "smoothing": request.smoothing, "t": pathT, "x": pathX, "y": pathY,
            ] as [String: Any]
        }
        if let next { result["next"] = next }
        return result
    }
}
