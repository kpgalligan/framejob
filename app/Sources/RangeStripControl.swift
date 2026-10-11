import AppKit

/// One qualifier range's strip (spec §11 GR-13, owner choice 6): 14 pt tall
/// and square-framed, over the range's own scale — the hue spectrum 0–360°
/// at full saturation, a neutral → red ramp for Saturation, black → white
/// for Luma. Outside the range and its softness the strip is dimmed 60 %,
/// the soft bands 30 %. The range's edges are the slider's 7 × 11 block
/// knobs and the softness edges 5 × 5 squares: drag a knob for the width
/// (hue, symmetric about the centre) or low / high; a square for the
/// softness (symmetric); the band's body to move the range (hue wraps); ⌥
/// held moves at a tenth (GR-11's convention). A double-click resets the
/// range to its default. Every gesture is a live one — `begin`, `update`
/// with the WHOLE range, `end` — so it is one undo step, named after the
/// range by the caller. Keyed, the band is outlined and the knobs drawn in
/// action ink. Off (the range nil), it draws dimmed and takes no press.
/// `press`, `drag` and `release` are the mouse handlers' bodies, internal
/// so a probe drives the gesture.
final class RangeStripControl: NSView, OptionControl {
    static let height: CGFloat = 14
    private static let knob = NSSize(width: 7, height: 11)
    private static let square: CGFloat = 5
    /// How near a handle a press must land to take it, in points.
    private static let reach: CGFloat = 5

    let kind: QualifierRange
    private let read: () -> ColorQualifier
    private let begin: () -> Void
    private let update: (ColorQualifierPatch) -> Void
    private let end: () -> Void
    var keyed: () -> Bool = { false }

    /// What a press took hold of.
    private enum Handle { case low, high, lowSoft, highSoft, body }

    /// The gesture in flight: the handle, the range as it is being dragged,
    /// and the value the pointer stood at last (on the range's scale).
    private struct Drag {
        let handle: Handle
        var hue: QualifierHue?
        var levels: QualifierLevels?
        var pointer: Double
    }
    private var dragging: Drag?

    init(
        kind: QualifierRange, read: @escaping () -> ColorQualifier, begin: @escaping () -> Void,
        update: @escaping (ColorQualifierPatch) -> Void, end: @escaping () -> Void
    ) {
        self.kind = kind
        self.read = read
        self.begin = begin
        self.update = update
        self.end = end
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        setAccessibilityIdentifier("qualifier.\(kind.rawValue).strip")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RangeStripControl does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    func refresh() { needsDisplay = true }

    // MARK: Scale

    /// The range's scale: 0…360 for hue, 0…1 for the levels.
    private var span: Double { kind == .hue ? 360 : 1 }

    /// The strip's drawable run, inside the frame and half a knob from each
    /// end so an edge at 0 or at the top of the scale is still graspable.
    private var run: (x: CGFloat, width: CGFloat) {
        let inset = Self.knob.width / 2
        return (inset, max(bounds.width - 2 * inset, 1))
    }

    func x(of value: Double) -> CGFloat {
        run.x + run.width * CGFloat(value / span)
    }

    func value(atX x: CGFloat) -> Double {
        Double((x - run.x) / run.width) * span
    }

    /// The range as it stands: the gesture's while one runs, else the read.
    private var hue: QualifierHue? { dragging?.hue ?? read().hue }
    private var levels: QualifierLevels? { dragging?.levels ?? read().levels(kind) }
    private var isOn: Bool { kind == .hue ? hue != nil : levels != nil }

    /// The handles' values on the scale (hue's may lie outside 0…360 before
    /// wrapping).
    private func handles() -> [(Handle, Double)] {
        if kind == .hue, let hue {
            let half = hue.width / 2
            return [(.low, hue.center - half), (.high, hue.center + half),
                    (.lowSoft, hue.center - half - hue.softness),
                    (.highSoft, hue.center + half + hue.softness)]
        }
        guard let levels else { return [] }
        return [(.low, levels.low), (.high, levels.high), (.lowSoft, levels.low - levels.softness),
                (.highSoft, levels.high + levels.softness)]
    }

    /// The x's a value on the scale draws at: a hue edge past either end
    /// wraps onto the other.
    private func xs(of value: Double) -> [CGFloat] {
        guard kind == .hue else { return [x(of: min(max(value, 0), 1))] }
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return [x(of: wrapped < 0 ? wrapped + 360 : wrapped)]
    }

    // MARK: Gesture

    /// A press at `point`: a double-click resets the range to its default;
    /// otherwise the nearest knob within reach, then square, then the band's
    /// body is taken; a press elsewhere, or on a range that is off, does
    /// nothing.
    func press(at point: NSPoint, clickCount: Int) {
        guard isOn, dragging == nil else { return }
        if clickCount >= 2 {
            begin()
            update(kind == .hue ? ColorQualifierPatch(hue: .set(.initial))
                       : .levels(kind, .set(.initial)))
            end()
            return
        }
        guard let handle = handle(at: point.x) else { return }
        begin()
        dragging = Drag(handle: handle, hue: hue, levels: levels, pointer: value(atX: point.x))
        needsDisplay = true
    }

    /// The pointer at `point`: the handle follows it, or moves by a tenth of
    /// its travel with ⌥ (`fine`).
    func drag(to point: NSPoint, fine: Bool) {
        guard var drag = dragging else { return }
        let raw = value(atX: point.x)
        let pointer = fine ? drag.pointer + (raw - drag.pointer) * ColorWheelControl.fine : raw
        let delta = pointer - drag.pointer
        drag.pointer = pointer
        if kind == .hue, var hue = drag.hue {
            Self.move(&hue, drag.handle, to: pointer, by: delta)
            drag.hue = hue
            update(ColorQualifierPatch(hue: .set(hue)))
        } else if var levels = drag.levels {
            Self.move(&levels, drag.handle, to: pointer, by: delta)
            drag.levels = levels
            update(.levels(kind, .set(levels)))
        }
        dragging = drag
        needsDisplay = true
    }

    func release() {
        guard dragging != nil else { return }
        dragging = nil
        end()
        needsDisplay = true
    }

    private func handle(at x: CGFloat) -> Handle? {
        let found = handles().flatMap { handle, value in xs(of: value).map { (handle, $0) } }
        let knobs = found.filter { $0.0 == .low || $0.0 == .high }
        let squares = found.filter { $0.0 == .lowSoft || $0.0 == .highSoft }
        for group in [knobs, squares] {
            if let near = group.min(by: { abs($0.1 - x) < abs($1.1 - x) }),
                abs(near.1 - x) <= Self.reach
            {
                return near.0
            }
        }
        return inside(value(atX: x)) ? .body : nil
    }

    /// Whether `value` lies in the fully selected band.
    private func inside(_ value: Double) -> Bool {
        if kind == .hue, let hue {
            return Self.distance(value, hue.center) <= hue.width / 2
        }
        guard let levels else { return false }
        return value >= levels.low && value <= levels.high
    }

    static func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    private static func move(
        _ hue: inout QualifierHue, _ handle: Handle, to pointer: Double, by delta: Double
    ) {
        let reach = distance(pointer, hue.center)
        switch handle {
        case .low, .high: hue.width = min(max(2 * reach, 0), 360)
        case .lowSoft, .highSoft: hue.softness = min(max(reach - hue.width / 2, 0), 180)
        case .body:
            let moved = (hue.center + delta).truncatingRemainder(dividingBy: 360)
            hue.center = moved < 0 ? moved + 360 : moved
        }
    }

    private static func move(
        _ levels: inout QualifierLevels, _ handle: Handle, to pointer: Double, by delta: Double
    ) {
        switch handle {
        case .low: levels.low = min(max(pointer, 0), levels.high)
        case .high: levels.high = min(max(pointer, levels.low), 1)
        case .lowSoft: levels.softness = min(max(levels.low - pointer, 0), 1)
        case .highSoft: levels.softness = min(max(pointer - levels.high, 0), 1)
        case .body:
            let width = levels.high - levels.low
            let low = min(max(levels.low + delta, 0), 1 - width)
            levels.low = low
            levels.high = min(low + width, 1)
        }
    }

    override func mouseDown(with event: NSEvent) {
        press(at: convert(event.locationInWindow, from: nil), clickCount: event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        drag(to: convert(event.locationInWindow, from: nil),
             fine: event.modifierFlags.contains(.option))
    }

    override func mouseUp(with event: NSEvent) {
        release()
    }

    // MARK: Drawing

    /// The scale's colour at `t` (0…1 along the strip).
    private func ink(_ t: Double) -> NSColor {
        switch kind {
        case .hue: return NSColor(hue: CGFloat(t), saturation: 1, brightness: 1, alpha: 1)
        case .saturation: return NSColor(hue: 0, saturation: CGFloat(t), brightness: 1, alpha: 1)
        case .luma: return NSColor(white: CGFloat(t), alpha: 1)
        }
    }

    /// How much a value is selected, for the dimming: 1 in the band, 0.5 in
    /// the soft bands, 0 outside.
    private func selection(_ value: Double) -> Double {
        if kind == .hue, let hue {
            let d = Self.distance(value, hue.center)
            return d <= hue.width / 2 ? 1 : (d <= hue.width / 2 + hue.softness ? 0.5 : 0)
        }
        guard let levels else { return 0 }
        if value >= levels.low && value <= levels.high { return 1 }
        return value >= levels.low - levels.softness && value <= levels.high + levels.softness
            ? 0.5 : 0
    }

    override func draw(_ dirtyRect: NSRect) {
        let strip = bounds.insetBy(dx: run.x, dy: 1)
        let columns = max(Int(strip.width.rounded(.up)), 1)
        for column in 0..<columns {
            let t = (Double(column) + 0.5) / Double(columns)
            let cell = NSRect(x: strip.minX + CGFloat(column), y: strip.minY, width: 1,
                              height: strip.height)
            ink(t).setFill()
            cell.fill()
            let chosen = isOn ? selection(t * span) : 0
            let dim: CGFloat = chosen >= 1 ? 0 : (chosen > 0 ? 0.3 : 0.6)
            if dim > 0 {
                NSColor.black.withAlphaComponent(dim).setFill()
                cell.fill(using: .sourceOver)
            }
        }
        DS.border.setStroke()
        NSBezierPath(rect: strip.insetBy(dx: -0.5, dy: -0.5)).stroke()
        guard isOn else { return }
        let isKeyed = keyed()
        let mark = isKeyed ? DS.action : DS.textStrong
        if isKeyed, let band = bandRect(in: strip) {
            DS.action.setStroke()
            NSBezierPath(rect: band.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
        for (handle, value) in handles() {
            for at in xs(of: value) {
                let size = handle == .low || handle == .high
                    ? Self.knob : NSSize(width: Self.square, height: Self.square)
                let box = backingAlignedRect(
                    NSRect(x: at - size.width / 2, y: bounds.midY - size.height / 2,
                           width: size.width, height: size.height),
                    options: .alignAllEdgesNearest)
                mark.setFill()
                box.fill()
                if size.width == Self.square {
                    DS.chromeBackground.setStroke()
                    NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)).stroke()
                }
            }
        }
    }

    /// The fully selected band's rectangle, when it does not wrap.
    private func bandRect(in strip: NSRect) -> NSRect? {
        let edges = handles().filter { $0.0 == .low || $0.0 == .high }.map(\.1)
        guard edges.count == 2, let lo = edges.min(), let hi = edges.max(),
            kind != .hue || (lo >= 0 && hi <= 360)
        else { return nil }
        return NSRect(x: x(of: lo), y: strip.minY, width: max(x(of: hi) - x(of: lo), 1),
                      height: strip.height)
    }
}
