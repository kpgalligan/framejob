import AppKit

/// The histogram slot's body (spec §11 GR-10): a near-black well, levels
/// 0…255 left to right, each plane's height the log of its count normalised
/// to the peak over all four planes; R′, G′ and B′ as translucent tinted
/// fills, Y′ a white line on top.
final class HistogramView: NSView {
    /// The fills' inks, R′ first.
    static let fills: [NSColor] = [
        NSColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 0.45),
        NSColor(srgbRed: 0.3, green: 1, blue: 0.3, alpha: 0.45),
        NSColor(srgbRed: 0.4, green: 0.55, blue: 1, alpha: 0.45),
    ]

    var trace: HistogramTrace? {
        didSet {
            guard trace != oldValue else { return }
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        WaveformTraceView.well.setFill()
        bounds.fill()
        guard let trace, let peak = trace.counts.max(), peak > 0 else { return }
        let scale = 1 / log(1 + Double(peak))
        let levels = WaveformTrace.levels
        let step = bounds.width / CGFloat(levels)
        /// Each level's height in the well.
        func heights(_ plane: Int) -> [CGFloat] {
            trace.plane(plane).map { CGFloat(log(1 + Double($0)) * scale) * bounds.height }
        }
        for plane in 0..<3 {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.minX, y: bounds.minY))
            for (level, height) in heights(plane).enumerated() {
                let x = bounds.minX + CGFloat(level) * step
                path.line(to: NSPoint(x: x, y: bounds.minY + height))
                path.line(to: NSPoint(x: x + step, y: bounds.minY + height))
            }
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.minY))
            path.close()
            Self.fills[plane].setFill()
            path.fill()
        }
        let luma = NSBezierPath()
        luma.lineWidth = 1.5
        for (level, height) in heights(3).enumerated() {
            let x = bounds.minX + CGFloat(level) * step
            let y = min(bounds.maxY - 0.75, bounds.minY + height)
            if level == 0 {
                luma.move(to: NSPoint(x: x, y: y))
            } else {
                luma.line(to: NSPoint(x: x, y: y))
            }
            luma.line(to: NSPoint(x: x + step, y: y))
        }
        NSColor.white.setStroke()
        luma.stroke()
    }
}
