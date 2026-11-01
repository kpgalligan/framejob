import AppKit

/// One recording's cursor samples, segment by segment (spec §11 CU-17): fed host-timed moves,
/// clicks, scrolls, images, hidden spans, geometry changes, dirty boxes and key entries while a
/// segment is open, it answers that segment's cursor file body at its close. PURE — no clock,
/// no file, no `rc_*` — so a probe drives it with synthetic segments
/// (`tools/proof/cursor_capture_probe.swift`). Not thread-safe: its owner feeds it from one
/// queue.
///
/// The rules, so a body it writes is always one the core accepts: `openSegment` resets every
/// array and the dedupe state, and records the start's geometry as the latest one before the
/// anchor; a sample fed while closed is dropped. At the close, times are
/// `round((host − anchor) × 1e6)` µs and positions and scroll deltas `round(pt × 100)`.
/// Before the anchor the latest move, image change and geometry are kept at t 0, every event
/// is dropped and a hidden span is clipped at 0. Each column is sorted by time, stably; hidden
/// spans empty after clipping are dropped and overlapping or touching ones merged. Images are
/// interned by their PNG bytes; an image change is kept only when the id differs, a geometry
/// entry only when it differs from the last. Under `cursorImage: .none` images are dropped,
/// and `current-system` with no image recorded writes `none`.
struct CursorCaptureBuffer {
    private(set) var isOpen = false
    private var start: CursorSegmentStart?
    private var samples = Samples()

    /// Everything one segment collects, reset whole at each open.
    private struct Samples {
        var moves: [(host: Double, value: (x: Int64, y: Int64))] = []
        var clicks: [(host: Double, value: (button: Int64, down: Int64, x: Int64, y: Int64,
                                            count: Int64))] = []
        var scrolls: [(host: Double, value: (x: Int64, y: Int64, dx: Int64, dy: Int64))] = []
        var images: [CursorFileBody.Image] = []
        var imageIDs: [Data: Int] = [:]
        var imageChanges: [(host: Double, value: Int)] = []
        var lastImageID: Int?
        var hidden: [(from: Double, to: Double)] = []
        var geometries: [(host: Double, value: CursorGeometry)] = []
        var lastGeometry: CursorGeometry?
        var dirty: [(host: Double, value: (x: Int64, y: Int64, w: Int64, h: Int64))] = []
        var shortcuts: [(host: Double, value: (keys: String, code: Int64))] = []
        var typed: [(host: Double, value: Void)] = []
    }

    mutating func openSegment(_ start: CursorSegmentStart) {
        samples = Samples()
        samples.geometries = [(host: -.infinity, value: start.geometry)]
        samples.lastGeometry = start.geometry
        self.start = start
        isOpen = true
    }

    mutating func move(to point: CGPoint, host: Double) {
        guard isOpen else { return }
        samples.moves.append((host, (Self.scaled(point.x), Self.scaled(point.y))))
    }

    mutating func click(button: Int, down: Bool, at point: CGPoint, count: Int, host: Double) {
        guard isOpen else { return }
        samples.clicks.append((host, (Int64(button), Int64(down ? 1 : 0), Self.scaled(point.x),
                                      Self.scaled(point.y), Int64(count))))
    }

    /// `dx` and `dy` are the event's point deltas as delivered, signed.
    mutating func scroll(dx: Double, dy: Double, at point: CGPoint, host: Double) {
        guard isOpen else { return }
        samples.scrolls.append((host, (Self.scaled(point.x), Self.scaled(point.y),
                                       Self.scaled(dx), Self.scaled(dy))))
    }

    mutating func image(png: Data, hotSpot: CGPoint, pointSize: CGSize, kind: CursorKind?,
                        host: Double) {
        guard isOpen, let start, start.cursorImage == .currentSystem else { return }
        let id: Int
        if let known = samples.imageIDs[png] {
            id = known
        } else {
            id = samples.images.count
            samples.imageIDs[png] = id
            samples.images.append(CursorFileBody.Image(
                png: png.base64EncodedString(), hotX: Self.scaled(hotSpot.x),
                hotY: Self.scaled(hotSpot.y), w: Self.scaled(pointSize.width),
                h: Self.scaled(pointSize.height), kind: kind))
        }
        guard id != samples.lastImageID else { return }
        samples.lastImageID = id
        samples.imageChanges.append((host, id))
    }

    mutating func hidden(fromHost: Double, toHost: Double) {
        guard isOpen else { return }
        samples.hidden.append((fromHost, toHost))
    }

    mutating func geometry(_ geometry: CursorGeometry, host: Double) {
        guard isOpen, geometry != samples.lastGeometry else { return }
        samples.lastGeometry = geometry
        samples.geometries.append((host, geometry))
    }

    mutating func dirty(_ box: CGRect, host: Double) {
        guard isOpen else { return }
        samples.dirty.append((host, (Self.scaled(box.minX), Self.scaled(box.minY),
                                     Self.scaled(box.width), Self.scaled(box.height))))
    }

    mutating func shortcut(keys: String, keyCode: Int, host: Double) {
        guard isOpen else { return }
        samples.shortcuts.append((host, (keys, Int64(keyCode))))
    }

    mutating func typed(host: Double) {
        guard isOpen else { return }
        samples.typed.append((host, ()))
    }

    /// The open segment's body, and the segment closed; nil when none is open. `movieSize` is
    /// the written track's (CU-16), `anchor` the frame its times count from.
    mutating func closeSegment(movieSize: CursorPixelSize, anchor: CursorAnchor) -> Data? {
        guard isOpen, let start else { return nil }
        isOpen = false
        let a = anchor.host
        let kept = Self.timed(samples.moves, anchor: a, keepLatestBefore: true)
        let changes = Self.timed(samples.imageChanges, anchor: a, keepLatestBefore: true)
        let geometries = Self.timed(samples.geometries, anchor: a, keepLatestBefore: true)
        let images = start.cursorImage == .currentSystem ? samples.images : []
        var body = CursorFileBody(
            version: ReelCursor.fileVersion, inPicture: start.inPicture, source: start.source,
            displayID: start.displayID, sourceFrame: Self.rect(start.sourceFrame),
            pointSize: [Self.scaled(start.pointSize.width), Self.scaled(start.pointSize.height)],
            pixelsPerPoint: start.pixelsPerPoint,
            contentSize: [start.contentSize.width, start.contentSize.height],
            movieSize: [movieSize.width, movieSize.height], anchor: anchor.kind,
            anchorHostUs: max(0, Self.micros(a)),
            cursorImage: images.isEmpty ? .none : .currentSystem)
        for (t, p) in kept {
            body.moves.t.append(t); body.moves.x.append(p.x); body.moves.y.append(p.y)
        }
        if !images.isEmpty {
            body.images = images
            for (t, id) in changes {
                body.imageChanges.t.append(t); body.imageChanges.id.append(Int64(id))
            }
        }
        body.hidden = Self.spans(samples.hidden, anchor: a)
        for (t, c) in Self.timed(samples.clicks, anchor: a, keepLatestBefore: false) {
            body.clicks.t.append(t); body.clicks.button.append(c.button)
            body.clicks.down.append(c.down); body.clicks.x.append(c.x)
            body.clicks.y.append(c.y); body.clicks.count.append(c.count)
        }
        for (t, s) in Self.timed(samples.scrolls, anchor: a, keepLatestBefore: false) {
            body.scrolls.t.append(t); body.scrolls.x.append(s.x); body.scrolls.y.append(s.y)
            body.scrolls.dx.append(s.dx); body.scrolls.dy.append(s.dy)
        }
        body.geometry = geometries.map { t, g in
            CursorFileBody.Geometry(t: t, screenRect: Self.rect(g.screenRect),
                                    contentRect: Self.rect(g.contentRect),
                                    contentScale: g.contentScale, scaleFactor: g.scaleFactor)
        }
        for (t, d) in Self.timed(samples.dirty, anchor: a, keepLatestBefore: false) {
            body.dirty.t.append(t); body.dirty.x.append(d.x); body.dirty.y.append(d.y)
            body.dirty.w.append(d.w); body.dirty.h.append(d.h)
        }
        for (t, k) in Self.timed(samples.shortcuts, anchor: a, keepLatestBefore: false) {
            body.keys.shortcut.t.append(t); body.keys.shortcut.keys.append(k.keys)
            body.keys.shortcut.code.append(k.code)
        }
        body.keys.typed.t = Self.timed(samples.typed, anchor: a, keepLatestBefore: false)
            .map { $0.t }
        return body.encoded()
    }

    // MARK: - Conversions

    /// `round(value × 100)`; 0 for a value that is not finite, and clamped inside `Int64`.
    static func scaled(_ value: Double) -> Int64 { integer(value * 100) }

    /// `round(seconds × 1e6)` µs.
    static func micros(_ seconds: Double) -> Int64 { integer(seconds * 1_000_000) }

    private static func integer(_ value: Double) -> Int64 {
        let rounded = value.rounded()
        guard rounded.isFinite else { return 0 }
        return Int64(min(max(rounded, -9.0e18), 9.0e18))
    }

    private static func rect(_ r: CGRect) -> [Int64] {
        [scaled(r.minX), scaled(r.minY), scaled(r.width), scaled(r.height)]
    }

    /// A column in µs from `anchor`, sorted by time with feed order breaking ties. Before the
    /// anchor, the latest sample is kept at t 0 when `keepLatestBefore`, and every one is
    /// dropped otherwise.
    private static func timed<T>(_ items: [(host: Double, value: T)], anchor: Double,
                                 keepLatestBefore: Bool) -> [(t: Int64, value: T)] {
        var before: (host: Double, value: T)?
        var after: [(t: Int64, index: Int, value: T)] = []
        for (index, item) in items.enumerated() {
            if item.host < anchor {
                if keepLatestBefore, item.host >= (before?.host ?? -.infinity) {
                    before = (item.host, item.value)
                }
            } else {
                after.append((micros(item.host - anchor), index, item.value))
            }
        }
        after.sort { ($0.t, $0.index) < ($1.t, $1.index) }
        return (before.map { [(t: Int64(0), value: $0.value)] } ?? [])
            + after.map { (t: $0.t, value: $0.value) }
    }

    /// Hidden spans in µs, clipped at 0, empty ones dropped, sorted by start, and overlapping
    /// or touching ones merged.
    private static func spans(_ items: [(from: Double, to: Double)], anchor: Double)
        -> CursorFileBody.Hidden {
        let clipped = items.enumerated()
            .map { (index: $0.offset, from: max(0, micros($0.element.from - anchor)),
                    to: micros($0.element.to - anchor)) }
            .filter { $0.to > $0.from }
            .sorted { ($0.from, $0.index) < ($1.from, $1.index) }
        var hidden = CursorFileBody.Hidden()
        for span in clipped {
            if let last = hidden.to.last, span.from <= last {
                hidden.to[hidden.to.count - 1] = max(last, span.to)
            } else {
                hidden.from.append(span.from)
                hidden.to.append(span.to)
            }
        }
        return hidden
    }
}
