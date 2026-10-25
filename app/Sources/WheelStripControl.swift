import AppKit

// MARK: - The master strip

/// A wheel's `master`, −1…1: the slider's look (a 3 pt rail, the 7 × 11 block
/// knob, the accent fill from the LEFT end as Light's ±1 rows have), dragged
/// as a live edit. A press off the knob jumps to the pointer like every
/// inspector slider; one on the knob grabs it where it stands, so the first
/// click of a double-click there writes nothing; ⌥ held drags RELATIVE at a
/// tenth (no jump); a double-click resets the master (`reset`), ONE undo step
/// on or off the knob — off it, `ColorWheelsView` undoes the first click's
/// jump before the reset (#272). Keyed, the fill is the action ink from the action's
/// start value and the knob is in action ink; a coral tick marks the
/// playhead's value when it differs. `press`, `drag` and `release` are the
/// mouse handlers' bodies, internal so a probe drives the gesture.
final class WheelStripControl: NSView, OptionControl {
    private static let rail = InspectorRail(lower: -1, upper: 1)

    private let read: () -> Double
    private let write: (Double) -> Void
    private let begin: () -> Void
    private let end: () -> Void
    private let reset: () -> Void
    private let enabled: () -> Bool
    private let start: () -> Double?
    private let now: () -> Double?
    var keyed: () -> Bool = { false }
    private var isActive = true
    /// The value being dragged and the pointer's last x; nil between
    /// gestures.
    private var dragged: Double?
    private var lastX: CGFloat = 0
    /// The pointer's offset from the knob's centre when a press grabbed the
    /// knob; 0 after a jump.
    private var grab: CGFloat = 0

    init(
        read: @escaping () -> Double, write: @escaping (Double) -> Void,
        begin: @escaping () -> Void, end: @escaping () -> Void, reset: @escaping () -> Void,
        enabled: @escaping () -> Bool, start: @escaping () -> Double?,
        now: @escaping () -> Double?
    ) {
        self.read = read
        self.write = write
        self.begin = begin
        self.end = end
        self.reset = reset
        self.enabled = enabled
        self.start = start
        self.now = now
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WheelStripControl does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 13)
    }

    func refresh() {
        isActive = enabled()
        alphaValue = isActive ? 1 : 0.42
        needsDisplay = true
    }

    private var span: CGFloat { Self.rail.span(width: bounds.width) }

    /// The knob's centre for `raw`, the x `draw` puts it at.
    private func knobX(of raw: Double) -> CGFloat {
        Self.rail.knobX(of: raw, width: bounds.width)
    }

    func value(atX x: CGFloat) -> Double { Self.rail.value(atX: x, width: bounds.width) }

    // MARK: Gesture

    /// A press at `x`: a double-click resets; ⌥ (`fine`) begins a relative
    /// drag from the value as it stands; a press on the knob grabs it with
    /// no write; otherwise the value jumps to `x`.
    func press(atX x: CGFloat, fine: Bool, clickCount: Int = 1) {
        guard isActive else { return }
        if clickCount >= 2 {
            dragged = nil
            reset()
            return
        }
        guard dragged == nil else { return }
        begin()
        lastX = x
        grab = 0
        let current = read()
        let offset = x - knobX(of: current)
        if fine {
            dragged = current
        } else if abs(offset) <= InspectorRail.knobSize.width / 2 {
            grab = offset
            dragged = current
        } else {
            let next = value(atX: x)
            dragged = next
            write(next)
        }
        needsDisplay = true
    }

    /// The pointer at `x`: ⌥ moves the value by a tenth of the pointer's
    /// travel since the last event, otherwise it follows the pointer.
    func drag(toX x: CGFloat, fine: Bool) {
        guard let from = dragged else { return }
        let next: Double
        if fine {
            let rail = Self.rail
            let delta = Double((x - lastX) / span) * (rail.upper - rail.lower)
            next = min(max(from + delta * ColorWheelControl.fine, rail.lower), rail.upper)
        } else {
            next = value(atX: x - grab)
        }
        lastX = x
        dragged = next
        write(next)
        needsDisplay = true
    }

    func release() {
        guard dragged != nil else { return }
        dragged = nil
        end()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        press(atX: convert(event.locationInWindow, from: nil).x,
              fine: event.modifierFlags.contains(.option), clickCount: event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        drag(toX: convert(event.locationInWindow, from: nil).x,
             fine: event.modifierFlags.contains(.option))
    }

    override func mouseUp(with event: NSEvent) {
        release()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        Self.rail.draw(
            in: self, value: dragged ?? read(), start: start(), now: now(), keyed: keyed(),
            keyedKnobInk: DS.action)
    }
}
