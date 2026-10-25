import AppKit

// MARK: - The rail

/// The inspector slider's rail, shared by `InspectorSliderControl` and
/// `WheelStripControl`: a 3 pt track, the 7 × 11 block knob, the mapping
/// between a value in `lower…upper` and an x across the view's width, and the
/// drawing — the accent fill from the left, or keyed (spec §4.3's marks) the
/// action ink from the value at the action's START to the knob, the coral
/// playhead tick when it is not where the knob is, then the knob. The keyed
/// knob's ink is the caller's: textStrong for the slider (spec §11 CI-6), the
/// action ink for a wheel's strip (§4.3b, GR-11).
struct InspectorRail {
    let lower: Double
    let upper: Double

    static let knobSize = NSSize(width: 7, height: 11)
    static let track: CGFloat = 3

    /// The width the knob's centre travels.
    func span(width: CGFloat) -> CGFloat { max(width - Self.knobSize.width, 1) }

    func fraction(of raw: Double) -> CGFloat {
        let value = min(max(raw, lower), upper)
        return CGFloat((value - lower) / (upper - lower))
    }

    /// The knob's centre for `raw`, the x `draw` puts it at.
    func knobX(of raw: Double, width: CGFloat) -> CGFloat {
        Self.knobSize.width / 2 + span(width: width) * fraction(of: raw)
    }

    func value(atX x: CGFloat, width: CGFloat) -> Double {
        let t = min(max((x - Self.knobSize.width / 2) / span(width: width), 0), 1)
        return lower + Double(t) * (upper - lower)
    }

    func draw(
        in view: NSView, value: Double, start: Double?, now: Double?,
        keyed: Bool, keyedKnobInk: NSColor
    ) {
        let knobSize = Self.knobSize
        let mid = view.bounds.midY
        let rail = NSRect(
            x: knobSize.width / 2, y: mid - Self.track / 2,
            width: span(width: view.bounds.width), height: Self.track)
        DS.border.setFill()
        rail.fill()

        // The block knob (`BlockSliderCell.drawKnob`'s shape), snapped to
        // device pixels; the fill runs to the SNAPPED centre so the two meet
        // on a pixel edge.
        let centre = rail.minX + rail.width * fraction(of: value)
        let knob = view.backingAlignedRect(
            NSRect(x: centre - knobSize.width / 2, y: mid - knobSize.height / 2,
                   width: knobSize.width, height: knobSize.height),
            options: .alignAllEdgesNearest)
        if let from = start, keyed {
            let startX = rail.minX + rail.width * fraction(of: from)
            DS.action.setFill()
            NSRect(x: min(startX, knob.midX), y: rail.minY, width: abs(knob.midX - startX),
                   height: rail.height).fill()
        } else {
            DS.accent.setFill()
            NSRect(x: rail.minX, y: rail.minY, width: max(knob.midX - rail.minX, 0),
                   height: rail.height).fill()
        }
        if let at = now, abs(at - value) > (upper - lower) / 1000 {
            let x = rail.minX + rail.width * fraction(of: at)
            DS.playhead.setFill()
            view.backingAlignedRect(
                NSRect(x: x - 1, y: mid - knobSize.height / 2, width: 2, height: knobSize.height),
                options: .alignAllEdgesNearest
            ).fill()
        }
        (keyed ? keyedKnobInk : DS.textStrong.withAlphaComponent(1)).setFill()
        knob.fill()
    }
}
