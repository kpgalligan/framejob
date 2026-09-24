import AppKit

/// What the Clip tab's lane draws of the clip itself, under its bands (spec
/// §11 CI-12): the transition overlap's hatch, the two audio fades and the
/// two motion wedges — each nil when the timeline would not draw it, by the
/// timeline's own gates. Pure geometry, so a probe can read it.
struct ActionLaneDecor: Equatable {
    var hatch: CGRect?
    var fadeIn: CGRect?
    var fadeOut: CGRect?
    var wedgeIn: CGRect?
    var wedgeOut: CGRect?
}

extension ActionLaneView {
    /// `lane` is the whole clip, start to end; every width is a fraction of
    /// the clip's length, at least 2 pt and never wider than the lane.
    func decor(_ clip: ClipSnapshot, in lane: CGRect) -> ActionLaneDecor {
        var decor = ActionLaneDecor()
        guard clip.duration > 0, lane.width > 0, lane.height > 0 else { return decor }
        let snapshot = binding.snapshot
        func width(_ ticks: Ticks) -> CGFloat {
            min(max(lane.width * CGFloat(ticks) / CGFloat(clip.duration), 2), lane.width)
        }
        // `drawTransition`'s gate: a transition, over a predecessor that
        // still runs when this clip starts.
        if clip.transitionIn != nil,
           let previous = snapshot.clips(onTrack: clip.track).last(where: {
               $0.start < clip.start
           }),
           previous.end > clip.start
        {
            decor.hatch = CGRect(
                x: lane.minX, y: lane.minY, width: width(previous.end - clip.start),
                height: lane.height)
        }
        if InspectorTab.hasAudio(clip, in: snapshot) {
            let audio = clip.audioProps
            let tall = min(10, lane.height)
            if audio.fadeIn > 0 {
                decor.fadeIn = CGRect(
                    x: lane.minX, y: lane.maxY - tall, width: width(audio.fadeIn), height: tall)
            }
            if audio.fadeOut > 0 {
                let w = width(audio.fadeOut)
                decor.fadeOut = CGRect(
                    x: lane.maxX - w, y: lane.maxY - tall, width: w, height: tall)
            }
        }
        // `drawNameStrip`'s gate, and `drawMotionWedges`' length: the EDGE's.
        if InspectorTab.hasPixels(clip, in: snapshot), let motion = clip.videoProps.motion {
            let tall = min(8, lane.height)
            if let edge = motion.inEdge, edge.isActive {
                decor.wedgeIn = CGRect(
                    x: lane.minX, y: lane.minY, width: width(edge.duration), height: tall)
            }
            if let edge = motion.out, edge.isActive {
                let w = width(edge.duration)
                decor.wedgeOut = CGRect(x: lane.maxX - w, y: lane.minY, width: w, height: tall)
            }
        }
        return decor
    }

    /// The decor, drawn in the well before the bands: the hatch (white 26 %,
    /// the timeline's 3 pt on a 7 pt perpendicular period) with a 1 pt
    /// white-40 % right edge; each fade a right triangle along the bottom,
    /// rising toward the clip's inside, at white 16 % (the handoff's shape);
    /// each wedge a triangle hanging from the top, deepest at the clip's
    /// edge, in `DS.textFaint`.
    func drawDecor(_ clip: ClipSnapshot, in lane: CGRect) {
        let decor = decor(clip, in: lane)
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: lane).addClip()
        if let hatch = decor.hatch {
            TimelineDraw.hatch(
                hatch, color: NSColor.white.withAlphaComponent(0.26),
                spacing: 7 * 2.0.squareRoot(), lineWidth: 3)
            NSColor.white.withAlphaComponent(0.4).setFill()
            NSRect(x: hatch.maxX - 1, y: hatch.minY, width: 1, height: hatch.height).fill()
        }
        NSColor.white.withAlphaComponent(0.16).setFill()
        if let fade = decor.fadeIn {
            triangle(fade.minX, fade.maxY, fade.maxX, fade.maxY, fade.maxX, fade.minY)
        }
        if let fade = decor.fadeOut {
            triangle(fade.maxX, fade.maxY, fade.minX, fade.maxY, fade.minX, fade.minY)
        }
        DS.textFaint.setFill()
        if let wedge = decor.wedgeIn {
            triangle(wedge.minX, wedge.minY, wedge.maxX, wedge.minY, wedge.minX, wedge.maxY)
        }
        if let wedge = decor.wedgeOut {
            triangle(wedge.maxX, wedge.minY, wedge.minX, wedge.minY, wedge.maxX, wedge.maxY)
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func triangle(
        _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat
    ) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: x0, y: y0))
        path.line(to: CGPoint(x: x1, y: y1))
        path.line(to: CGPoint(x: x2, y: y2))
        path.close()
        path.fill()
    }
}

extension Curve {
    /// The lane's Curve popup titles, "Ease " dropped (spec §11 CI-12);
    /// `displayName` stays the spelling everywhere else.
    var laneName: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "In"
        case .easeOut: return "Out"
        case .easeInOut: return "In Out"
        }
    }
}

/// The 16 × 10 curve glyph before the lane's Curve popup: the band's own
/// `ActionBands.curvePath`, 1.25 pt in `DS.action`. Beside the popup rather
/// than inside it, because `OptionPopupControl` is Rasterize's and is not
/// forked (CI-12).
final class CurveGlyphView: NSView, OptionControl {
    private let read: () -> Curve
    private var shown: Curve?

    init(read: @escaping () -> Curve) {
        self.read = read
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 10))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 16),
            heightAnchor.constraint(equalToConstant: 10),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CurveGlyphView does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    func refresh() {
        let curve = read()
        guard curve != shown else { return }
        shown = curve
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = ActionBands.curvePath(read(), in: bounds.insetBy(dx: 0.75, dy: 0.75))
        path.lineWidth = 1.25
        DS.action.setStroke()
        path.stroke()
    }
}
