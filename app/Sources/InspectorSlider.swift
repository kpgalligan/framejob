import AppKit

// MARK: - Slider

/// A continuous value slider whose drag is a LIVE edit: `begin` on mouse
/// down, `write` on every move, `end` on mouse up (§4.3, the document's
/// `beginLiveEdit`/`updateLiveEdit`/`endLiveEdit` trio). Paired with an
/// `OptionFieldControl` in the same row, which commits typed values as a
/// single `applyEdit` instead.
///
/// It lives here rather than in `OptionControls.swift` because that file is
/// carried verbatim from Rasterize (app/CLAUDE.md: keep it in sync, do not
/// fork); it still conforms to `OptionControl` so `refreshOptionControls`
/// finds it like every other control.
final class InspectorSliderControl: NSView, OptionControl {
    private let lower: Double
    private let upper: Double
    private let read: () -> Double
    private let write: (Double) -> Void
    private let begin: () -> Void
    private let end: () -> Void
    private let enabled: () -> Bool
    /// The value at the selected action's START and at the PLAYHEAD
    /// (`InspectorBinding.startValue` / `nowValue`), nil when there is none.
    private let start: () -> Double?
    private let now: () -> Double?
    /// Whether the row is keyed — set by `inspectorValueRow` from the row's
    /// gutter once the row exists.
    var keyed: () -> Bool = { false }
    private var isActive = true
    private var dragging = false

    init(
        min lower: Double, max upper: Double, read: @escaping () -> Double,
        write: @escaping (Double) -> Void, begin: @escaping () -> Void,
        end: @escaping () -> Void, enabled: @escaping () -> Bool,
        start: @escaping () -> Double?, now: @escaping () -> Double?
    ) {
        self.start = start
        self.now = now
        self.lower = lower
        self.upper = Swift.max(upper, lower + 0.000_001)
        self.read = read
        self.write = write
        self.begin = begin
        self.end = end
        self.enabled = enabled
        super.init(frame: .zero)
        wantsLayer = true
        setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorSliderControl does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: DS.controlHeight)
    }

    func refresh() {
        isActive = enabled()
        alphaValue = isActive ? 1 : 0.42
        needsDisplay = true
    }

    private var rail: InspectorRail { InspectorRail(lower: lower, upper: upper) }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard isActive else { return }
        dragging = true
        begin()
        write(rail.value(atX: convert(event.locationInWindow, from: nil).x, width: bounds.width))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        write(rail.value(atX: convert(event.locationInWindow, from: nil).x, width: bounds.width))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        // Ends the gesture even when the value never moved: the document
        // registers no undo step for an unchanged handle, so this is free.
        end()
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        rail.draw(
            in: self, value: read(), start: start(), now: now(), keyed: keyed(),
            keyedKnobInk: DS.textStrong.withAlphaComponent(1))
    }
}
