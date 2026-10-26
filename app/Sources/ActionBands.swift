import AppKit

/// What the timeline's action lane and the Clip tab's lane share (spec §11
/// CI-4): the ORDER actions are numbered in, the words a band's label is made
/// of, the zoom test, and the one painter both call — so a band on the
/// timeline and the same band in the inspector cannot disagree about its
/// number or its ink.
///
/// Drawn in a FLIPPED view: `minY` is the band's top. Everything here is
/// relative to the band it is handed; where the band sits is its caller's.
enum ActionBands {
    /// Time order — start, then id for two that share one (they cannot
    /// overlap, but a zero-length action can sit on another's start). An
    /// action's NUMBER is its index here plus one, everywhere.
    static func ordered(_ clip: ClipSnapshot) -> [ActionSnapshot] {
        clip.actions.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// Which properties an action changes — the end patch's keys, spelled
    /// the way the model spells them, sorted (what the old Actions table
    /// printed beside each curve); `speed` when the end names a rate (spec
    /// §11 SR-21 (d)).
    static func keys(of patch: ActionPatch) -> [String] {
        var keys: [String] = []
        if let video = patch.video { keys.append(contentsOf: video.dictionary.keys) }
        if let audio = patch.audio { keys.append(contentsOf: audio.dictionary.keys) }
        if let text = patch.text { keys.append(contentsOf: text.dictionary.keys) }
        if let graphic = patch.graphic { keys.append(contentsOf: graphic.props.keys) }
        if patch.speed != nil { keys.append("speed") }
        return keys.sorted()
    }

    /// A screencast zoom's shape — `add_zoom_action` writes exactly `scale`,
    /// `x` and `y` and nothing else, so an end patch of those three keys is
    /// drawn with the zoom glyph whichever door wrote it. An end naming a rate
    /// is not a zoom (spec §11 SR-21 (d)).
    static func isZoom(_ action: ActionSnapshot) -> Bool {
        let end = action.end
        guard let video = end.video, end.audio?.isEmpty ?? true, end.text?.isEmpty ?? true,
              end.graphic?.props.isEmpty ?? true, end.speed == nil
        else { return false }
        return Set(video.dictionary.keys) == ["scale", "x", "y"]
    }

    /// How much a band says, by track size: S bars only, M the number (and
    /// the zoom glyph and the selected band's curve), L the label too.
    enum Level {
        case bars, number, label

        init(sizeIndex: Int) {
            switch sizeIndex {
            case ..<1: self = .bars
            case 1: self = .number
            default: self = .label
            }
        }
    }

    /// The resize zone at each end of a band (spec §11 CI-11): its outer
    /// 5 pt, on a band wide enough to hold two of them and a body.
    static let grip: CGFloat = 5

    /// Which end of `band` the x falls in the grip of, or nil for the body —
    /// always nil on a band 15 pt wide or less, which is all body.
    static func gripEdge(in band: CGRect, at x: CGFloat) -> TimelineEdge? {
        guard band.width > grip * 3 else { return nil }
        if x - band.minX <= grip { return .start }
        if band.maxX - x <= grip { return .end }
        return nil
    }

    /// One band. Normal: the action ink at 34 % with 1 pt ends at 75 %;
    /// hovered, 62 % with solid ends. Selected: solid, its text in
    /// `DS.actionInk`, and — from M — the curve as a 1.25 pt black-45 % line
    /// from the bottom-left corner to the top-right, unless `curve` is nil
    /// (a Speed band under the rate line, `RateGraph.bandCurve`, spec §11
    /// SR-26). The number, the glyph and the label run from the LEADING
    /// edge, so the band's bottom-right corner holds fill only (the proof
    /// samples it there). Hovered, a band wide enough to resize draws its two
    /// 5 pt grips last — white 80 %, or black 45 % on the selected band — so
    /// an unhovered band never has them (CI-11).
    static func draw(
        band: CGRect, number: Int, label: String?, curve: Curve?, zoom: Bool, selected: Bool,
        hovered: Bool, level: Level
    ) {
        guard band.width > 0, band.height > 0 else { return }
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: band).addClip()
        if selected {
            DS.action.setFill()
            band.fill()
        } else {
            DS.action.withAlphaComponent(hovered ? 0.62 : 0.34).setFill()
            band.fill()
            DS.action.withAlphaComponent(hovered ? 1 : 0.75).setFill()
            NSRect(x: band.minX, y: band.minY, width: 1, height: band.height).fill()
            NSRect(x: band.maxX - 1, y: band.minY, width: 1, height: band.height).fill()
        }
        defer {
            if hovered, band.width > grip * 3 {
                (selected ? NSColor.black.withAlphaComponent(0.45)
                    : NSColor.white.withAlphaComponent(0.8)).setFill()
                NSRect(x: band.minX, y: band.minY, width: grip, height: band.height).fill()
                NSRect(x: band.maxX - grip, y: band.minY, width: grip, height: band.height).fill()
            }
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        guard level != .bars else { return }
        if selected, let curve {
            let path = curvePath(curve, in: band)
            path.lineWidth = 1.25
            NSColor.black.withAlphaComponent(0.45).setStroke()
            path.stroke()
        }
        let ink = selected ? DS.actionInk : NSColor.white
        let numberFont = DS.mono(9, weight: .semibold)
        let text = "\(number)"
        let numberWidth = ceil(text.size(withAttributes: [.font: numberFont]).width)
        var x = band.minX + 3
        TimelineDraw.truncated(
            text, in: CGRect(x: x, y: band.minY, width: numberWidth + 5, height: band.height),
            font: numberFont, color: ink)
        x += numberWidth + 2
        if zoom {
            TimelineDraw.symbol(
                "plus.magnifyingglass", fallback: "+",
                in: CGRect(x: x, y: band.minY, width: 11, height: band.height), tint: ink)
            x += 11 + 2
        }
        if level == .label, let label, !label.isEmpty {
            x += 2
            let room = CGRect(
                x: x, y: band.minY, width: max(band.maxX - 3 - x, 0), height: band.height)
            TimelineDraw.truncated(
                label, in: room, font: DS.sans(10, weight: .semibold), color: ink)
        }
    }

    /// The easing as a line across `rect`: progress along x, the eased value
    /// up the rect (the view is flipped, so "up" is toward `minY`). The
    /// selected band strokes it, and so does the lane's `CurveGlyphView`.
    static func curvePath(_ curve: Curve, in rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        let steps = 16
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(
                x: rect.minX + t * rect.width, y: rect.maxY - eased(curve, t) * rect.height)
            if step == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        return path
    }

    /// A glyph's easing, not the core's: the shape reads as the curve, and no
    /// frame is computed from it.
    private static func eased(_ curve: Curve, _ t: CGFloat) -> CGFloat {
        switch curve {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return 1 - (1 - t) * (1 - t)
        case .easeInOut: return t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t)
        }
    }
}

extension NSView {
    /// A band's cursor rects, the timeline's and the Clip tab lane's alike:
    /// `.openHand` over the body and `.resizeLeftRight` over the two
    /// `ActionBands.grip`-wide ends; a band too narrow for both grips and a
    /// body is all `.openHand`. Which bands get them is the caller's.
    func addGripCursorRects(_ band: CGRect) {
        let grip = ActionBands.grip
        guard band.width > grip * 3 else {
            addCursorRect(band, cursor: .openHand)
            return
        }
        addCursorRect(band.insetBy(dx: grip, dy: 0), cursor: .openHand)
        addCursorRect(
            CGRect(x: band.minX, y: band.minY, width: grip, height: band.height),
            cursor: .resizeLeftRight)
        addCursorRect(
            CGRect(x: band.maxX - grip, y: band.minY, width: grip, height: band.height),
            cursor: .resizeLeftRight)
    }
}
