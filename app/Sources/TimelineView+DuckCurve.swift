import AppKit

/// The speech duck's line (format 29, spec §11 AU-113): over a clip that
/// ducks by SPEECH, its own multiplier — the plan's `ducks` entry, read
/// through `TimelineView.duckCurves` — stroked across the clip's audio
/// region, gain 1 at the top and 0 at the bottom, so a person sees where the
/// rest of the mix goes down for each run of words and comes back between
/// them. An extent duck draws nothing new: it ducks for the clip's length,
/// which the clip already shows.
///
/// An extension of `TimelineContentView` in a file of its own, as the
/// filmstrip and the waveform are `TimelineClipDrawing.swift`'s:
/// `TimelineView.swift` is frozen at wiring.
extension TimelineContentView {
    func drawDuckCurve(_ clip: ClipSnapshot, in rect: CGRect, owner: TimelineView, visible: CGRect) {
        guard clip.audioProps.duck?.mode == .speech, rect.height >= 8, rect.width > 1,
              let ramps = owner.duckCurves?.ramps(for: clip.id)
        else { return }
        let layout = owner.layout
        // Flipped: the region's top is its minY, and gain 1 sits there.
        func y(_ gain: Double) -> CGFloat {
            rect.minY + 1 + CGFloat(1 - min(max(gain, 0), 1)) * (rect.height - 2)
        }
        let from = max(rect.minX, visible.minX) - 1
        let to = min(rect.maxX, visible.maxX) + 1
        guard to > from else { return }
        // The core's ramps tile the ducker's widened extent with no gap and
        // the gain is 1 on either side of it, so the line is one polyline:
        // in at gain 1, through every ramp that reaches the visible part,
        // out at gain 1. A ramp off screen is skipped; the segment that
        // replaces it lies off screen too, since the ramps are in order.
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: y(1)))
        for ramp in ramps {
            let start = layout.x(for: ramp.start)
            let end = layout.x(for: ramp.start + ramp.duration)
            guard end >= from, start <= to else { continue }
            path.line(to: CGPoint(x: start, y: y(ramp.from)))
            path.line(to: CGPoint(x: end, y: y(ramp.to)))
        }
        path.line(to: CGPoint(x: rect.maxX, y: y(1)))
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        NSColor.systemYellow.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 1
        path.stroke()
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
