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
    /// printed beside each curve).
    static func keys(of patch: ActionPatch) -> [String] {
        var keys: [String] = []
        if let video = patch.video { keys.append(contentsOf: video.dictionary.keys) }
        if let audio = patch.audio { keys.append(contentsOf: audio.dictionary.keys) }
        if let text = patch.text { keys.append(contentsOf: text.dictionary.keys) }
        return keys.sorted()
    }

    /// A screencast zoom's shape — `add_zoom_action` writes exactly `scale`,
    /// `x` and `y` and nothing else, so an end patch of those three keys is
    /// drawn with the zoom glyph whichever door wrote it.
    static func isZoom(_ action: ActionSnapshot) -> Bool {
        let end = action.end
        guard let video = end.video, end.audio?.isEmpty ?? true, end.text?.isEmpty ?? true
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

    /// One band. Normal: the action ink at 34 % with 1 pt ends at 75 %.
    /// Selected: solid, its text in `DS.actionInk`, and — from M — the curve
    /// as a 1.25 pt black-45 % line from the bottom-left corner to the
    /// top-right. The number, the glyph and the label run from the LEADING
    /// edge, so the band's bottom-right corner holds fill only (the proof
    /// samples it there).
    static func draw(
        band: CGRect, number: Int, label: String?, curve: Curve, zoom: Bool, selected: Bool,
        level: Level
    ) {
        guard band.width > 0, band.height > 0 else { return }
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: band).addClip()
        if selected {
            DS.action.setFill()
            band.fill()
        } else {
            DS.action.withAlphaComponent(0.34).setFill()
            band.fill()
            DS.action.withAlphaComponent(0.75).setFill()
            NSRect(x: band.minX, y: band.minY, width: 1, height: band.height).fill()
            NSRect(x: band.maxX - 1, y: band.minY, width: 1, height: band.height).fill()
        }
        guard level != .bars else {
            NSGraphicsContext.current?.restoreGraphicsState()
            return
        }
        if selected { drawCurve(curve, in: band) }
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
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// The easing as a line across the band: progress along x, the eased
    /// value up the band (the view is flipped, so "up" is toward `minY`).
    private static func drawCurve(_ curve: Curve, in band: CGRect) {
        let path = NSBezierPath()
        let steps = 16
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(
                x: band.minX + t * band.width, y: band.maxY - eased(curve, t) * band.height)
            if step == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.lineWidth = 1.25
        NSColor.black.withAlphaComponent(0.45).setStroke()
        path.stroke()
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
