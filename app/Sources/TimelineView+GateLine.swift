import AppKit

/// Hide while silent's line (format 43, spec §11 CO-93): over a clip with a
/// gate, the gate the core multiplies its opacity by — the plan's `gates`
/// entry, read through `TimelineView.gateCurves` — stroked across the clip's
/// VIDEO region in teal, gate 1 at the top and 0 at the bottom, so a person
/// sees where the camera fades out in each pause and back in before speech.
///
/// Inside an open nest the timeline's handle is the scope's, so a gate read
/// from a container outside the nest is not drawn there (the recipe still
/// applies it). An extension of `TimelineContentView` in a file of its own,
/// as the duck line is: `TimelineView.swift` is frozen at wiring.
extension TimelineContentView {
    func drawGateLine(_ clip: ClipSnapshot, in rect: CGRect, owner: TimelineView, visible: CGRect) {
        guard clip.video?.hideSilent != nil, rect.height >= 8, rect.width > 1,
              let ramps = owner.gateCurves?.ramps(for: clip.id), !ramps.isEmpty
        else { return }
        let layout = owner.layout
        // Flipped: the region's top is its minY, and gate 1 sits there.
        func y(_ gate: Double) -> CGFloat {
            rect.minY + 1 + CGFloat(1 - min(max(gate, 0), 1)) * (rect.height - 2)
        }
        let from = max(rect.minX, visible.minX) - 1
        let to = min(rect.maxX, visible.maxX) + 1
        guard to > from else { return }
        // The core's ramps tile the clip's span, so the line is one polyline
        // through every ramp that reaches the visible part; one off screen is
        // skipped, the ramps being in order.
        let path = NSBezierPath()
        var started = false
        for ramp in ramps {
            let start = layout.x(for: ramp.start)
            let end = layout.x(for: ramp.start + ramp.duration)
            guard end >= from, start <= to else { continue }
            let head = CGPoint(x: start, y: y(ramp.from))
            if started { path.line(to: head) } else { path.move(to: head) }
            started = true
            path.line(to: CGPoint(x: end, y: y(ramp.to)))
        }
        guard started else { return }
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        NSColor.systemTeal.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1
        path.stroke()
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
