import AppKit

/// The vectorscope slot's body (spec §11 GR-10): a near-black square, Cb
/// running right and Cr up, the counts as a white log density; a faint
/// centre cross; the six 75 % targets as 7 pt boxes labelled R, Mg, B, Cy, G
/// and Yl; and the skin line from the centre to the edge. No circles, no
/// zoom. The slot keeps it square and centres it.
final class VectorscopeView: NSView {
    static let targetBox: CGFloat = 7
    static let crossArm: CGFloat = 6
    /// Fixed inks over the near-black square, the same in either appearance.
    static let graticule = NSColor(white: 1, alpha: 0.28)
    static let label = NSColor(white: 1, alpha: 0.6)

    var trace: VectorscopeTrace? {
        didSet {
            guard trace != oldValue else { return }
            image = trace.flatMap(Self.density)
            needsDisplay = true
        }
    }
    private var image: CGImage?

    /// The point at the centre of bin (`cb`, `cr`) in the view.
    func point(cb: Int, cr: Int) -> NSPoint {
        let bin = bounds.width / CGFloat(VectorscopeTrace.bins)
        return NSPoint(
            x: bounds.minX + (CGFloat(cb) + 0.5) * bin, y: bounds.minY + (CGFloat(cr) + 0.5) * bin)
    }

    override func draw(_ dirtyRect: NSRect) {
        ScopeWell.fill(bounds, image: image)
        let centre = point(cb: VectorscopeTrace.centre, cr: VectorscopeTrace.centre)
        Self.graticule.setStroke()
        let cross = NSBezierPath()
        cross.lineWidth = 1
        cross.move(to: NSPoint(x: centre.x - Self.crossArm, y: centre.y))
        cross.line(to: NSPoint(x: centre.x + Self.crossArm, y: centre.y))
        cross.move(to: NSPoint(x: centre.x, y: centre.y - Self.crossArm))
        cross.line(to: NSPoint(x: centre.x, y: centre.y + Self.crossArm))
        cross.stroke()
        // The skin line, centre to edge, at its angle from +Cb.
        let angle = VectorscopeTrace.skinLineDegrees * .pi / 180
        let reach = bounds.width / 2
        let skin = NSBezierPath()
        skin.lineWidth = 1
        skin.move(to: centre)
        skin.line(
            to: NSPoint(
                x: centre.x + reach * CGFloat(cos(angle)), y: centre.y + reach * CGFloat(sin(angle))))
        skin.stroke()
        for target in VectorscopeTrace.targets {
            let at = point(cb: VectorscopeTrace.bin(target.cb), cr: VectorscopeTrace.bin(target.cr))
            let half = Self.targetBox / 2
            let box = NSBezierPath(rect: NSRect(
                x: at.x - half, y: at.y - half, width: Self.targetBox, height: Self.targetBox))
            box.lineWidth = 1
            box.stroke()
            let text = NSAttributedString(
                string: target.name,
                attributes: [.font: DS.mono(9), .foregroundColor: Self.label])
            let size = text.size()
            // Beyond the box, away from the centre.
            let dx = at.x - centre.x
            let dy = at.y - centre.y
            let length = max(1, hypot(dx, dy))
            let away = half + 2 + max(size.width, size.height) / 2
            let x = at.x + dx / length * away - size.width / 2
            let y = at.y + dy / length * away - size.height / 2
            text.draw(at: NSPoint(
                x: min(max(x, bounds.minX), bounds.maxX - size.width),
                y: min(max(y, bounds.minY), bounds.maxY - size.height)))
        }
    }

    /// The counts as a 256 × 256 white-on-clear image, Cr bin 255 at the top.
    static func density(_ trace: VectorscopeTrace) -> CGImage? {
        let side = VectorscopeTrace.bins
        let peak = trace.counts.max() ?? 0
        guard peak > 0, trace.counts.count == side * side else { return nil }
        let scale = 1 / log(1 + Double(peak))
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for cr in 0..<side {
            for cb in 0..<side {
                let count = trace.counts[cr * side + cb]
                guard count > 0 else { continue }
                let alpha = UInt8(min(255, (255 * log(1 + Double(count)) * scale).rounded()))
                let at = ((side - 1 - cr) * side + cb) * 4
                pixels[at] = alpha
                pixels[at + 1] = alpha
                pixels[at + 2] = alpha
                pixels[at + 3] = alpha
            }
        }
        return ScopeWell.image(pixels, side: side)
    }
}
