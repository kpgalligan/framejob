import AppKit

// MARK: - The curve editor (spec §11 GR-12, grading-2 G2-3; GR-32, grading-4 T4-2)

/// The curve plot: a square with a 4 × 4 grid, the identity diagonal, the
/// other channels faint behind the edited one, the edited curve in its
/// channel's tint (`CurveTable.value`, the strip's own spline) and its
/// points as 7 × 7 squares, the selected one filled. A hue channel (GR-32)
/// plots in its domain's units — hue 0…360 across, the shift −180…180 or
/// the gain 0…2 up — over `CurvePlotDecor`'s hue grid and spectrum strip,
/// the faint others only those of its own domain; its points never cross
/// 0°/360°.
///
/// **Gestures** (owner choices 2–4): a press on a point grabs it where it
/// stands (no jump) and a drag moves it, held `minGap` inside each
/// neighbour's x and inside 0…1, the end points too; ⌥ moves at a tenth. A
/// press anywhere else adds a point ON the curve at the press's x — on an
/// identity channel at y = x exactly — selects it, and the same press drags
/// it; a 17th beeps. Every drag is the live trio (`begin`, `write`, `end`):
/// one undo step. On an identity channel the added point waits in
/// `state.working` and is written by its first movement, nudge or field
/// entry, so a press and release there writes nothing. ⌫ or ⌦, and a
/// double-click on a point, delete it (`commit`, one step; never below two
/// points); the arrows nudge it by `nudge` (⇧ `bigNudge`), one step each;
/// Esc deselects. `press`, `drag`, `release` and `key` are the event
/// handlers' bodies, internal so a probe drives them as the mouse and
/// keyboard do.
///
/// **⇧ axis lock** (#270): the first drag event with ⇧ held whose travel
/// from the press is at least `lockTravel` picks the axis it moved most
/// along for the rest of the gesture; while ⇧ is held the other coordinate
/// stays the grabbed point's (before the axis is picked the point stays
/// put), and without it the point follows the pointer. ⌥ and ⇧ combine.
/// **Hover readout** (#270): while the pointer is over the plot, and during
/// a drag, `CurvePlotDecor`'s label reads the pointer's x and the curve's
/// value there (`readout(at:)`); none outside the plot, the strip included.
///
/// **First responder only while a point is selected**: a press on the plot
/// takes it, and deselecting returns it to the content view (#60's
/// pattern); a key it does not use goes on up the chain, so Space still
/// plays and the editor's bare keys still work.
final class CurveEditorView: NSView, OptionControl {
    /// The tone domain's gap (`CurveDomain` holds every domain's gap and nudges).
    static let minGap = 0.001
    static let maxPoints = 16
    /// How far the pointer must travel from the press, in points, before ⇧
    /// picks the axis.
    static let lockTravel: CGFloat = 4
    private static let inset: CGFloat = 4, handle: CGFloat = 7, reach: CGFloat = 5

    /// One drag in flight: the list being dragged, the dragged point's
    /// unclamped position, the pointer's last location, and for the ⇧ lock
    /// the press's location, the point's position at the press and the axis
    /// once picked.
    private struct Gesture {
        var list: [CurvePoint]
        var target: CurvePoint
        var last: NSPoint
        let press: NSPoint
        let origin: CurvePoint
        var axis: CurveAxis?
    }

    let state: CurveEditorState
    private let read: (CurveChannel) -> [CurvePoint]
    private let start: (CurveChannel) -> [CurvePoint]?
    private let write: ([CurvePoint]) -> Void
    private let begin: () -> Void
    private let end: () -> Void
    private let commit: ([CurvePoint]) -> Void
    /// Whether the row is keyed — set by the Curves section from its gutter.
    var keyed: () -> Bool = { false }
    /// Called when the selected point or the list changes, so the section's
    /// fields and Delete button follow.
    var onSelection: () -> Void = {}
    /// The gesture in flight.
    private var dragged: Gesture?
    /// The point the first click of a double-click added, which its second
    /// click must not delete.
    private var added: Int?
    /// The pointer over the view, for the readout; nil when it is away.
    private var hovered: NSPoint?
    private var hoverArea: NSTrackingArea?

    init(
        state: CurveEditorState, read: @escaping (CurveChannel) -> [CurvePoint],
        start: @escaping (CurveChannel) -> [CurvePoint]?,
        write: @escaping ([CurvePoint]) -> Void, begin: @escaping () -> Void,
        end: @escaping () -> Void, commit: @escaping ([CurvePoint]) -> Void
    ) {
        (self.state, self.read, self.start, self.write) = (state, read, start, write)
        (self.begin, self.end, self.commit) = (begin, end, commit)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CurveEditorView does not support NSCoder")
    }

    // MARK: State

    /// The list the plot shows and edits: `working` while the channel reads
    /// back as an identity of another count, the read-back otherwise.
    var points: [CurvePoint] {
        let back = read(state.channel)
        guard let working = state.working, holds(working, over: back) else { return back }
        return working
    }

    /// Whether `working` stands for `back`: an identity of another count.
    private func holds(_ working: [CurvePoint], over back: [CurvePoint]) -> Bool {
        domain.isIdentity(back) && back.count != working.count
    }

    /// The edited channel's domain.
    var domain: CurveDomain { state.channel.domain }

    /// The selected point, nil with none.
    var selectedPoint: CurvePoint? {
        guard let index = state.selected else { return nil }
        let list = points
        return list.indices.contains(index) ? list[index] : nil
    }

    /// Whether ⌫ belongs to the plot: a point is selected and the plot holds
    /// first responder (the Delete menu item's validator asks).
    var holdsDeleteKey: Bool { state.selected != nil && window?.firstResponder === self }

    var canDelete: Bool { state.selected != nil && points.count > 2 }

    func refresh() {
        if let working = state.working, !holds(working, over: read(state.channel)) {
            state.working = nil
        }
        if let index = state.selected, !points.indices.contains(index) { state.selected = nil }
        needsDisplay = true
    }

    /// No point, no working list, and first responder back to the window.
    func deselect() {
        state.clear()
        added = nil
        if window?.firstResponder === self { window?.makeFirstResponder(window?.contentView) }
        onSelection()
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { state.selected != nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window?.firstResponder === self { window?.makeFirstResponder(window?.contentView) }
        super.viewWillMove(toWindow: newWindow)
    }

    // MARK: Geometry

    /// The square, inset: the tone plot whole, a hue plot over its strip.
    private var square: NSRect {
        let side = min(bounds.width, bounds.height)
        return NSRect(x: bounds.minX, y: bounds.minY, width: side, height: side)
            .insetBy(dx: Self.inset, dy: Self.inset)
    }

    /// Where the curve is drawn: the square, less its bottom strip and gap on
    /// a hue channel.
    var plot: NSRect {
        let s = square
        guard domain.period != nil else { return s }
        let below = CurvePlotDecor.stripHeight + CurvePlotDecor.stripGap
        return NSRect(x: s.minX, y: s.minY + below, width: s.width, height: s.height - below)
    }

    /// A hue channel's spectrum strip, under its plot.
    private var strip: NSRect {
        let s = square
        return NSRect(x: s.minX, y: s.minY, width: s.width, height: CurvePlotDecor.stripHeight)
    }

    /// A point in the domain's units on screen: x from `lower.x` across
    /// `span.x`, y from `lower.y` up `span.y` (0…1 both on a tone curve).
    func screen(_ point: CurvePoint) -> NSPoint {
        let p = plot
        let (low, span) = (domain.lower, domain.span)
        return NSPoint(x: p.minX + CGFloat((point.x - low.x) / span.x) * p.width,
                       y: p.minY + CGFloat((point.y - low.y) / span.y) * p.height)
    }

    private func model(_ point: NSPoint) -> CurvePoint {
        let p = plot
        let (low, span) = (domain.lower, domain.span)
        return CurvePoint(x: low.x + Double((point.x - p.minX) / max(p.width, 1)) * span.x,
                          y: low.y + Double((point.y - p.minY) / max(p.height, 1)) * span.y)
    }

    /// The index of the point within `reach` of `point`, the nearest first.
    private func hit(_ point: NSPoint, in list: [CurvePoint]) -> Int? {
        func distance(_ index: Int) -> CGFloat {
            let at = screen(list[index])
            return max(abs(at.x - point.x), abs(at.y - point.y))
        }
        return list.indices.filter { distance($0) <= Self.reach }.min { distance($0) < distance($1) }
    }

    /// `point` held the domain's `minGap` inside its neighbours' x and inside
    /// the domain (0…1 both on a tone curve; a hue point 0…359.9 across, so
    /// it never crosses the wrap).
    static func clamped(
        _ point: CurvePoint, at index: Int, in list: [CurvePoint], domain: CurveDomain = .tone
    ) -> CurvePoint {
        let (lower, upper, gap) = (domain.lower, domain.upper, domain.minGap)
        let low = max(index > 0 ? list[index - 1].x + gap : lower.x, lower.x)
        let high = min(index < list.count - 1 ? list[index + 1].x - gap : upper.x, upper.x)
        let x = low <= high ? min(max(point.x, low), high) : list[index].x
        return CurvePoint(x: x, y: min(max(point.y, lower.y), upper.y))
    }

    // MARK: Gesture

    func press(at point: NSPoint, clickCount: Int = 1) {
        guard dragged == nil else { return }
        let list = points
        if let index = hit(point, in: list) {
            if clickCount >= 2, index != added {
                state.selected = index
                deleteSelected()
                return
            }
            added = clickCount >= 2 ? added : nil
            select(index)
            dragged = Gesture(
                list: list, target: list[index], last: point, press: point, origin: list[index])
            begin()
            return
        }
        added = nil
        guard list.count < Self.maxPoints else {
            NSSound.beep()
            return
        }
        let at = model(point)
        let (domain, lower, upper) = (self.domain, self.domain.lower.x, self.domain.upper.x)
        let index = list.firstIndex { $0.x > at.x } ?? list.count
        let low = index > 0 ? list[index - 1].x + domain.minGap : lower
        let high = index < list.count ? list[index].x - domain.minGap : upper
        let x = min(max(at.x, max(low, lower)), min(high, upper))
        guard max(low, lower) <= min(high, upper) else {
            NSSound.beep()
            return
        }
        // On a straight channel the point lies exactly on y = x (a hue
        // channel's on its neutral); on a curve it lies on the curve, so
        // adding it changes nothing it passes through.
        let straight = domain.isIdentity(list)
        let new = CurvePoint(
            x: x,
            y: straight ? domain.neutral ?? x : CurveTable.value(list, at: x, domain: domain))
        var next = list
        next.insert(new, at: index)
        added = index
        select(index)
        dragged = Gesture(list: next, target: new, last: point, press: point, origin: new)
        begin()
        if straight { state.working = next } else { write(next) }
        needsDisplay = true
    }

    func drag(to point: NSPoint, fine: Bool, lock: Bool = false) {
        guard var gesture = dragged, let index = state.selected,
              gesture.list.indices.contains(index)
        else { return }
        let p = plot
        let span = domain.span
        let scale = fine ? 0.1 : 1
        gesture.target.x += Double((point.x - gesture.last.x) / max(p.width, 1)) * scale * span.x
        gesture.target.y += Double((point.y - gesture.last.y) / max(p.height, 1)) * scale * span.y
        gesture.last = point
        var aim = gesture.target
        if lock {
            let dx = point.x - gesture.press.x
            let dy = point.y - gesture.press.y
            if gesture.axis == nil, hypot(dx, dy) >= Self.lockTravel {
                gesture.axis = abs(dx) >= abs(dy) ? .x : .y
            }
            switch gesture.axis {
            case .x?: aim.y = gesture.origin.y
            case .y?: aim.x = gesture.origin.x
            case nil: aim = gesture.origin
            }
        }
        let moved = Self.clamped(aim, at: index, in: gesture.list, domain: domain)
        let changed = moved != gesture.list[index]
        gesture.list[index] = moved
        dragged = gesture
        guard changed else { return }
        added = nil
        if state.working != nil { state.working = gesture.list }
        write(gesture.list)
        onSelection()
        needsDisplay = true
    }

    func release() {
        guard dragged != nil else { return }
        dragged = nil
        // Ends the gesture even when nothing moved: the document registers no
        // undo step for an unchanged handle.
        end()
        onSelection()
        needsDisplay = true
    }

    /// The selected point deleted: one step, never below two points (a beep
    /// there). Deleting an unwritten point (`working`) off a straight channel
    /// leaves it straight, and writes nothing.
    func deleteSelected() {
        guard let index = state.selected else { return }
        var list = points
        guard list.count > 2, list.indices.contains(index) else {
            NSSound.beep()
            return
        }
        list.remove(at: index)
        added = nil
        let unwritten = state.working != nil
        state.working = nil
        if !(unwritten && domain.isIdentity(list)) { commit(list) }
        deselect()
    }

    /// The selected point moved to `x`, `y` (either nil to keep it), clamped
    /// like a drag: one step. The In and Out fields and the arrows write here.
    func place(x: Double? = nil, y: Double? = nil) {
        guard let index = state.selected else { return }
        var list = points
        guard list.indices.contains(index) else { return }
        let target = CurvePoint(x: x ?? list[index].x, y: y ?? list[index].y)
        let moved = Self.clamped(target, at: index, in: list, domain: domain)
        guard moved != list[index] else { return }
        list[index] = moved
        added = nil
        if state.working != nil { state.working = list }
        commit(list)
        onSelection()
        needsDisplay = true
    }

    private func select(_ index: Int) {
        state.selected = index
        window?.makeFirstResponder(self)
        onSelection()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        press(at: convert(event.locationInWindow, from: nil), clickCount: event.clickCount)
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        drag(to: point, fine: event.modifierFlags.contains(.option),
             lock: event.modifierFlags.contains(.shift))
        hover(at: point)
    }
    override func mouseUp(with event: NSEvent) { release() }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp,
                                   .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hover(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseMoved(with event: NSEvent) {
        hover(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseExited(with event: NSEvent) { hover(at: nil) }

    /// The pointer is at `point` (nil: away): the readout follows it.
    func hover(at point: NSPoint?) {
        guard point != hovered else { return }
        hovered = point
        needsDisplay = true
    }

    /// The readout for the pointer at `point`: the model x there (held in
    /// the domain) and the edited curve's value at it; nil outside the plot.
    func readout(at point: NSPoint) -> String? {
        let p = plot
        guard p.width > 8, p.contains(point) else { return nil }
        let (domain, lower, upper) = (self.domain, self.domain.lower.x, self.domain.upper.x)
        let x = min(max(model(point).x, lower), upper)
        let list = dragged?.list ?? points
        let y = CurveTable.value(list, at: x, domain: domain)
        return CurvePlotDecor.readoutText(domain, x: x, y: y)
    }

    // MARK: Keys

    /// ⌫ / ⌦, the arrows and Esc while a point is selected; false for every
    /// other key, and for every key with none selected.
    func key(_ event: NSEvent) -> Bool {
        guard let index = state.selected, points.indices.contains(index),
              let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first?.value
        else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.subtracting([.shift, .capsLock, .numericPad, .function]).isEmpty else {
            return false
        }
        let step = flags.contains(.shift) ? domain.bigNudge : domain.nudge
        let point = points[index]
        switch scalar {
        case 0x7F, 0x08, UInt32(NSDeleteFunctionKey):
            deleteSelected()
        case UInt32(NSUpArrowFunctionKey): place(y: point.y + step.y)
        case UInt32(NSDownArrowFunctionKey): place(y: point.y - step.y)
        case UInt32(NSLeftArrowFunctionKey): place(x: point.x - step.x)
        case UInt32(NSRightArrowFunctionKey): place(x: point.x + step.x)
        case 27: deselect()
        default: return false
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if key(event) { return }
        super.keyDown(with: event)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let p = plot
        guard p.width > 8 else { return }
        let domain = self.domain
        NSColor.controlBackgroundColor.setFill()
        p.fill()
        if domain.period != nil {
            // The hue grid, its neutral line, and the spectrum strip below.
            CurvePlotDecor.drawHueGrid(in: p, view: self)
            CurvePlotDecor.drawHueStrip(in: strip, view: self)
        } else {
            // The 4 × 4 grid and the identity diagonal.
            DS.border.setFill()
            for k in 1..<4 {
                let t = CGFloat(k) / 4
                backingAlignedRect(NSRect(x: p.minX + t * p.width, y: p.minY, width: 1,
                                          height: p.height), options: .alignAllEdgesNearest).fill()
                backingAlignedRect(NSRect(x: p.minX, y: p.minY + t * p.height, width: p.width,
                                          height: 1), options: .alignAllEdgesNearest).fill()
            }
            let diagonal = NSBezierPath()
            diagonal.move(to: NSPoint(x: p.minX, y: p.minY))
            diagonal.line(to: NSPoint(x: p.maxX, y: p.maxY))
            diagonal.lineWidth = 1
            DS.borderStrong.setStroke()
            diagonal.stroke()
        }

        // The other channels of the same domain, faint, where they are not
        // the identity.
        for channel in CurveChannel.allCases
        where channel != state.channel && channel.domain == domain {
            let list = read(channel)
            guard !domain.isIdentity(list) else { continue }
            stroke(list, color: channel.tint.withAlphaComponent(0.35), width: 1)
        }
        let isKeyed = keyed()
        let ink = isKeyed ? DS.action : state.channel.tint
        if isKeyed, let from = start(state.channel) {
            stroke(from, color: DS.action.withAlphaComponent(0.7), width: 1, dashed: true)
        }
        let list = dragged?.list ?? points
        stroke(list, color: ink, width: 1.5)
        for (index, point) in list.enumerated() {
            let at = screen(point)
            let square = backingAlignedRect(
                NSRect(x: at.x - Self.handle / 2, y: at.y - Self.handle / 2,
                       width: Self.handle, height: Self.handle),
                options: .alignAllEdgesNearest)
            DS.chromeBackground.setFill()
            square.insetBy(dx: -1, dy: -1).fill()
            if index == state.selected {
                ink.setFill()
                square.fill()
            } else {
                NSColor.controlBackgroundColor.setFill()
                square.fill()
                ink.setStroke()
                let frame = NSBezierPath(rect: square.insetBy(dx: 0.5, dy: 0.5))
                frame.lineWidth = 1
                frame.stroke()
            }
        }
        DS.border.setStroke()
        let frame = NSBezierPath(rect: p.insetBy(dx: -0.5, dy: -0.5))
        frame.lineWidth = 1
        frame.stroke()
        if let hovered, let text = readout(at: hovered) {
            CurvePlotDecor.drawReadout(text, at: hovered, in: p)
        }
    }

    /// The curve through `list`, one segment per point of plot width.
    private func stroke(_ list: [CurvePoint], color: NSColor, width: CGFloat, dashed: Bool = false) {
        let p = plot
        let steps = max(Int(p.width.rounded()), 2)
        let domain = self.domain
        let spline = CurveTable.Spline(list, domain: domain)
        let path = NSBezierPath()
        for step in 0...steps {
            let x = domain.lower.x + Double(step) / Double(steps) * domain.span.x
            let at = screen(CurvePoint(x: x, y: spline.value(at: x)))
            if step == 0 { path.move(to: at) } else { path.line(to: at) }
        }
        path.lineWidth = width
        if dashed { path.setLineDash([3, 3], count: 2, phase: 0) }
        color.setStroke()
        path.stroke()
    }
}
