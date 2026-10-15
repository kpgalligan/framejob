import AppKit

// MARK: - The curve plot's decoration (spec §11 GR-32, grading-4 T4-2)

/// What `CurveEditorView` draws besides its curves and points, kept here so
/// the editor stays a gesture file: a hue curve's grid and the spectrum
/// strip under its plot, and the hover readout's text and label (#270).
///
/// **The hue plot** (owner choices 2 and 5): the square less its bottom
/// `stripHeight + stripGap` (10 pt), so the row's height and every tone
/// capture are unchanged; verticals every 60°, horizontals at the quarters,
/// and the neutral line (shift 0, gain 1) across the middle in
/// `DS.borderStrong` in place of the tone plot's diagonal. Under it, the
/// spectrum strip: `NSColor(hue: t, saturation: 1, brightness: 1)` per
/// column, 0° on the left and 360° on the right, the direction a positive
/// Hue vs Hue value turns a colour.
///
/// **The readout** (owner choice 4): mono 9 in `DS.textStrong` on the chrome
/// background at 0.85, 2 pt padding, at the pointer + (8, 8), flipped inward
/// at the plot's right and top edges.
enum CurvePlotDecor {
    static let stripHeight: CGFloat = 8, stripGap: CGFloat = 2
    static let readoutOffset: CGFloat = 8, readoutPadding: CGFloat = 2

    /// The readout's text for the pointer at model `x` over a curve whose
    /// value there is `y`: `In 0.42 → Out 0.47` on a tone curve (2
    /// decimals), `Hue 34° → +12°` on Hue vs Hue (whole degrees, "+" for 0
    /// and up, "−" U+2212 below), `Hue 34° → ×0.80` on Hue vs Sat.
    static func readoutText(_ domain: CurveDomain, x: Double, y: Double) -> String {
        switch domain {
        case .tone:
            return String(format: "In %.2f → Out %.2f", x, y)
        case .hueShift:
            let turn = Int(y.rounded())
            return "Hue \(degrees(x))° → \(turn >= 0 ? "+" : "\u{2212}")\(abs(turn))°"
        case .hueGain:
            return "Hue \(degrees(x))° → ×" + String(format: "%.2f", y)
        }
    }

    /// A hue in whole degrees on the circle: 359.6 reads as 0°, as it is.
    private static func degrees(_ x: Double) -> Int {
        Int(x.rounded()) % 360
    }

    /// The hue grid in `plot`: verticals every 60°, horizontals at the
    /// quarters, the middle one (the neutral) strong.
    static func drawHueGrid(in plot: NSRect, view: NSView) {
        DS.border.setFill()
        for k in 1..<6 {
            let x = plot.minX + CGFloat(k) / 6 * plot.width
            view.backingAlignedRect(
                NSRect(x: x, y: plot.minY, width: 1, height: plot.height),
                options: .alignAllEdgesNearest
            ).fill()
        }
        for k in [1, 3] {
            let y = plot.minY + CGFloat(k) / 4 * plot.height
            view.backingAlignedRect(
                NSRect(x: plot.minX, y: y, width: plot.width, height: 1),
                options: .alignAllEdgesNearest
            ).fill()
        }
        DS.borderStrong.setFill()
        view.backingAlignedRect(
            NSRect(x: plot.minX, y: plot.midY, width: plot.width, height: 1),
            options: .alignAllEdgesNearest
        ).fill()
    }

    /// The spectrum strip in `rect`: one fully saturated hue per column of
    /// backing pixels, 0° at the left edge, 360° at the right, framed.
    static func drawHueStrip(in rect: NSRect, view: NSView) {
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let columns = max(Int((rect.width * scale).rounded()), 1)
        let step = rect.width / CGFloat(columns)
        for column in 0..<columns {
            let t = (CGFloat(column) + 0.5) / CGFloat(columns)
            NSColor(hue: t, saturation: 1, brightness: 1, alpha: 1).setFill()
            NSRect(x: rect.minX + CGFloat(column) * step, y: rect.minY, width: step + 0.01,
                   height: rect.height).fill()
        }
        DS.border.setStroke()
        let frame = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        frame.lineWidth = 1
        frame.stroke()
    }

    /// The readout label for the pointer at `point`, kept inside `plot`.
    static func drawReadout(_ text: String, at point: NSPoint, in plot: NSRect) {
        let label = NSAttributedString(
            string: text,
            attributes: [.font: DS.mono(9), .foregroundColor: DS.textStrong])
        let size = label.size()
        var box = NSRect(
            x: point.x + readoutOffset, y: point.y + readoutOffset,
            width: ceil(size.width) + 2 * readoutPadding,
            height: ceil(size.height) + 2 * readoutPadding)
        if box.maxX > plot.maxX { box.origin.x = point.x - readoutOffset - box.width }
        if box.maxY > plot.maxY { box.origin.y = point.y - readoutOffset - box.height }
        box.origin.x = max(box.minX, plot.minX)
        box.origin.y = max(box.minY, plot.minY)
        DS.chromeBackground.withAlphaComponent(0.85).setFill()
        box.fill()
        label.draw(at: NSPoint(x: box.minX + readoutPadding, y: box.minY + readoutPadding))
    }
}
