import AppKit

/// A ramped clip's rate as a line across its action lane (spec §11 SR-26):
/// the timeline's lane at M and L and the Clip tab's lane both draw it here,
/// so the two cannot disagree (CI-4's shared-painter rule).
///
/// The rate is the core's (`SourceMap.rate`, from `rc_project_source_map`):
/// Swift only maps its numbers to pixels and computes no rate (SR-21 (b)).
/// The scale is linear in rate, from the clip's own slowest to its fastest,
/// the fastest at the top — so a ×1 → ×1.1 ramp is as tall as ×1 → ×10, and
/// the figures stay the Speed section's. Drawn in a FLIPPED view.
enum RateGraph {
    /// The line's points in `rect`, or nil — no line — unless the map is
    /// ramped, its `rate` has at least two points, its fastest is above its
    /// slowest, and `rect` has area. `x` places a clip tick; y is
    /// `rect.maxY − (rate − min)/(max − min) · rect.height`.
    static func points(_ map: SourceMap?, in rect: CGRect, x: (Ticks) -> CGFloat) -> [CGPoint]? {
        guard let map, map.ramped, map.rate.count >= 2, rect.width > 0, rect.height > 0,
              let slowest = map.rate.map(\.rate).min(), let fastest = map.rate.map(\.rate).max(),
              fastest > slowest
        else { return nil }
        let range = fastest - slowest
        return map.rate.map { point in
            CGPoint(
                x: x(point.tick),
                y: rect.maxY - CGFloat((point.rate - slowest) / range) * rect.height)
        }
    }

    /// The line, clipped to `lane`: one path through `points` with round
    /// joins, stroked black 50 % at 2.75 pt, then white 95 % at 1.25 pt over
    /// it, so it reads on a band's fill and on the lane's backing alike.
    static func draw(_ points: [CGPoint], in lane: CGRect) {
        guard points.count >= 2, let first = points.first else { return }
        NSGraphicsContext.current?.saveGraphicsState()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }
        NSBezierPath(rect: lane).addClip()
        let path = NSBezierPath()
        path.move(to: first)
        for point in points.dropFirst() { path.line(to: point) }
        path.lineJoinStyle = .round
        path.lineWidth = 2.75
        NSColor.black.withAlphaComponent(0.5).setStroke()
        path.stroke()
        path.lineWidth = 1.25
        NSColor.white.withAlphaComponent(0.95).setStroke()
        path.stroke()
    }

    /// The ease a band strokes when selected: nil — none — for a Speed
    /// action while the rate line is drawn over it, else the action's curve.
    static func bandCurve(_ action: ActionSnapshot, graphed: Bool) -> Curve? {
        graphed && action.end.speed != nil ? nil : action.curve
    }
}
