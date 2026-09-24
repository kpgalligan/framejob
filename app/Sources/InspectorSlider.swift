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

    private static let knobSize = NSSize(width: 7, height: 11)
    private static let track: CGFloat = 3

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

    private var fraction: CGFloat { fraction(of: read()) }

    private func fraction(of raw: Double) -> CGFloat {
        let value = Swift.min(Swift.max(raw, lower), upper)
        return CGFloat((value - lower) / (upper - lower))
    }

    private func value(atX x: CGFloat) -> Double {
        let inset = Self.knobSize.width / 2
        let span = Swift.max(bounds.width - Self.knobSize.width, 1)
        let t = Swift.min(Swift.max((x - inset) / span, 0), 1)
        return lower + Double(t) * (upper - lower)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard isActive else { return }
        dragging = true
        begin()
        write(value(atX: convert(event.locationInWindow, from: nil).x))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        write(value(atX: convert(event.locationInWindow, from: nil).x))
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
        let knobSize = Self.knobSize
        let mid = bounds.midY
        let rail = NSRect(
            x: knobSize.width / 2, y: mid - Self.track / 2,
            width: max(bounds.width - knobSize.width, 1), height: Self.track)
        DS.border.setFill()
        rail.fill()

        // The block knob (`BlockSliderCell.drawKnob`'s shape), snapped to
        // device pixels; the fill runs to the SNAPPED centre so the two meet
        // on a pixel edge.
        let center = rail.minX + rail.width * fraction
        let knob = backingAlignedRect(
            NSRect(x: center - knobSize.width / 2, y: mid - knobSize.height / 2,
                   width: knobSize.width, height: knobSize.height),
            options: .alignAllEdgesNearest)
        // Keyed (spec §4.3's marks): no accent fill, and the action ink from
        // the value at the action's START to the knob, either way round.
        if let from = start(), keyed() {
            let startX = rail.minX + rail.width * fraction(of: from)
            DS.action.setFill()
            NSRect(x: min(startX, knob.midX), y: rail.minY, width: abs(knob.midX - startX),
                   height: rail.height).fill()
        } else {
            DS.accent.setFill()
            NSRect(x: rail.minX, y: rail.minY, width: max(knob.midX - rail.minX, 0),
                   height: rail.height).fill()
        }
        // The playhead's value: a coral tick over the fill, under the knob,
        // when it is not where the knob is.
        if let value = now(), abs(value - read()) > (upper - lower) / 1000 {
            let x = rail.minX + rail.width * fraction(of: value)
            DS.playhead.setFill()
            backingAlignedRect(
                NSRect(x: x - 1, y: mid - knobSize.height / 2, width: 2,
                       height: knobSize.height),
                options: .alignAllEdgesNearest
            ).fill()
        }
        DS.textStrong.withAlphaComponent(1).setFill()
        knob.fill()
    }
}
