import AppKit
import CoreMedia

/// A recording's cursor, segment by segment (road map creator-jobs CU1b1, spec §11 CU-11): one
/// `CursorCaptureBuffer` per segment, fed while that segment is the current one and closed into
/// its file body when the walker reaches it (`ScreenRecorder+Cursor.swift`). PURE — no clock,
/// no queue, no file — so `tools/proof/cursor_capture_probe.swift` drives it with synthetic
/// polls; its owner (`CursorCapture`) touches it from one queue.
///
/// **What it adds to the buffer's rules (CU-17).** The poll's dedupe: a polled point is a move
/// only when it differs from the last polled one, across segments, and a nil records nothing.
/// The seed: a segment opened is fed the last polled point as a move at its open, before its
/// anchor, so the buffer keeps it at t 0 and a segment opened after the pointer stopped still
/// has its position. Its opening geometry is the last one fed, else the start's. A segment
/// `end`ed is fed nothing more and keeps its samples until `close`.
struct CursorSegments {
    /// The segment samples go to; nil between a pause's `end` and the resume's `open`.
    private(set) var current: Int?
    private var buffers: [Int: CursorCaptureBuffer] = [:]
    private var lastPoint: CGPoint?
    private var lastGeometry: CursorGeometry?

    /// Segment `index` opens at `host`: a fresh buffer on `start`, its geometry the last fed,
    /// seeded with the last polled point.
    mutating func open(_ index: Int, start: CursorSegmentStart, host: Double) {
        var buffer = CursorCaptureBuffer()
        buffer.openSegment(
            CursorSegmentStart(
                inPicture: start.inPicture, source: start.source, displayID: start.displayID,
                sourceFrame: start.sourceFrame, pointSize: start.pointSize,
                pixelsPerPoint: start.pixelsPerPoint, contentSize: start.contentSize,
                cursorImage: start.cursorImage, geometry: lastGeometry ?? start.geometry))
        if let lastPoint { buffer.move(to: lastPoint, host: host) }
        buffers[index] = buffer
        current = index
    }

    /// One poll: a move when the point differs from the last; nil records nothing.
    mutating func poll(_ point: CGPoint?, host: Double) {
        guard let point, point != lastPoint else { return }
        lastPoint = point
        guard let current else { return }
        buffers[current]?.move(to: point, host: host)
    }

    mutating func click(button: Int, down: Bool, at point: CGPoint, count: Int, host: Double) {
        guard let current else { return }
        buffers[current]?.click(button: button, down: down, at: point, count: count, host: host)
    }

    mutating func scroll(dx: Double, dy: Double, at point: CGPoint, host: Double) {
        guard let current else { return }
        buffers[current]?.scroll(dx: dx, dy: dy, at: point, host: host)
    }

    /// The frames' geometry at `host`, remembered for the next segment's open.
    mutating func geometry(_ geometry: CursorGeometry, host: Double) {
        lastGeometry = geometry
        guard let current else { return }
        buffers[current]?.geometry(geometry, host: host)
    }

    /// Segment `index` takes nothing more; its samples wait for `close`.
    mutating func end(_ index: Int) {
        if current == index { current = nil }
    }

    /// Segment `index`'s body, its buffer let go; nil when it was never opened.
    mutating func close(_ index: Int, movieSize: CursorPixelSize, anchor: CursorAnchor) -> Data? {
        end(index)
        guard var buffer = buffers.removeValue(forKey: index) else { return nil }
        return buffer.closeSegment(movieSize: movieSize, anchor: anchor)
    }
}

/// The live sources behind `CursorSegments` (spec §11 CU-11): the position polled at 120 Hz on
/// its own queue, and clicks and scrolls from `NSEvent`'s global and local monitors, which need
/// no grant (CU-S1, the owner's `clicks=monitor`). Monitors are added and removed on MAIN; the
/// segments are touched on `queue` ALONE. An event's time is its `cgEvent.timestamp` in host
/// seconds (`event_clock=ns`), else its arrival. No image sampler, hidden spans or dirty boxes
/// (CU-6); keys are CU6's.
final class CursorCapture {
    /// 120 Hz (CU-S1 `positions=poll`; the core's `POLL_US` is its µs).
    static let pollInterval: Double = 1.0 / 120
    let queue = DispatchQueue(label: "com.kgalligan.FrameJob.cursor", qos: .userInteractive)

    private let position: () -> CGPoint?
    /// On `queue` only.
    private var segments = CursorSegments()
    /// Main only.
    private var timer: DispatchSourceTimer?
    private var monitors: [Any] = []

    /// `position` is the poll's source, `CGEvent(source: nil)?.location` (global points, top
    /// left) unless a probe passes its own.
    init(position: @escaping () -> CGPoint? = { CGEvent(source: nil)?.location }) {
        self.position = position
    }

    deinit {
        timer?.cancel()
        monitors.forEach { NSEvent.removeMonitor($0) }
    }

    /// The host clock's now, in seconds: the frames' PTS and E1 are on it (CR0).
    static func hostNow() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    /// MAIN. The poll and the monitors; a second call does nothing.
    func start() {
        guard timer == nil else { return }
        let poll = DispatchSource.makeTimerSource(queue: queue)
        poll.schedule(
            deadline: .now(), repeating: .nanoseconds(Int(Self.pollInterval * 1_000_000_000)),
            leeway: .milliseconds(1))
        poll.setEventHandler { [weak self] in
            guard let self else { return }
            self.segments.poll(self.position(), host: Self.hostNow())
        }
        poll.resume()
        timer = poll
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown,
            .otherMouseUp, .scrollWheel,
        ]
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: mask, handler: { [weak self] event in self?.take(event) })
        {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                self?.take(event)
                return event
            })
        {
            monitors.append(local)
        }
    }

    /// MAIN. The poll and the monitors gone; the segments are kept for their close.
    func stop() {
        timer?.cancel()
        timer = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    /// MAIN. Segment `index` opens now, onto `queue`.
    func openSegment(_ index: Int, _ start: CursorSegmentStart) {
        let host = Self.hostNow()
        queue.async { self.segments.open(index, start: start, host: host) }
    }

    /// MAIN. Segment `index` takes nothing more, onto `queue`.
    func endSegment(_ index: Int) {
        queue.async { self.segments.end(index) }
    }

    /// Any thread: a frame's geometry at `host` (its PTS).
    func geometry(_ geometry: CursorGeometry, host: Double) {
        queue.async { self.segments.geometry(geometry, host: host) }
    }

    /// Segment `index`'s body, to `then` ON `queue` (nil when it was never opened).
    func closeSegment(
        _ index: Int, movieSize: CursorPixelSize, anchor: CursorAnchor,
        then: @escaping (Data?) -> Void
    ) {
        queue.async { then(self.segments.close(index, movieSize: movieSize, anchor: anchor)) }
    }

    /// Every segment let go, onto `queue`.
    func discard() {
        queue.async { self.segments = CursorSegments() }
    }

    /// MAIN, from a monitor: the event's click or scroll onto `queue`.
    private func take(_ event: NSEvent) {
        let arrival = Self.hostNow()
        if let c = Self.click(from: event, arrival: arrival) {
            queue.async {
                self.segments.click(
                    button: c.button, down: c.down, at: c.at, count: c.count, host: c.host)
            }
        } else if let s = Self.scroll(from: event, arrival: arrival) {
            queue.async { self.segments.scroll(dx: s.dx, dy: s.dy, at: s.at, host: s.host) }
        }
    }

    /// A mouse-down or mouse-up as a click: `buttonNumber` (0…31, else nil), down or up,
    /// `cgEvent.location`, `clickCount` (at least 1) and the event's host time; nil for any
    /// other event or one without a `cgEvent`.
    static func click(from e: NSEvent, arrival: Double)
        -> (button: Int, down: Bool, at: CGPoint, count: Int, host: Double)?
    {
        let down: Bool
        switch e.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: down = true
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: down = false
        default: return nil
        }
        guard let cg = e.cgEvent, (0...31).contains(e.buttonNumber) else { return nil }
        return (e.buttonNumber, down, cg.location, max(1, e.clickCount), host(of: cg, arrival))
    }

    /// A `scrollWheel` as a scroll: the point deltas (`Axis2` horizontal, `Axis1` vertical) as
    /// delivered, at `cgEvent.location`, with the event's host time; nil otherwise.
    static func scroll(from e: NSEvent, arrival: Double)
        -> (dx: Double, dy: Double, at: CGPoint, host: Double)?
    {
        guard e.type == .scrollWheel, let cg = e.cgEvent else { return nil }
        return (
            cg.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
            cg.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), cg.location,
            host(of: cg, arrival)
        )
    }

    /// `event_clock=ns`: the timestamp's nanoseconds as host seconds; the arrival without one.
    private static func host(of event: CGEvent, _ arrival: Double) -> Double {
        event.timestamp > 0 ? Double(event.timestamp) / 1e9 : arrival
    }
}
