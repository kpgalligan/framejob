import AppKit

/// The waveform slot's body (spec §11 GR-5): a near-black well in both
/// appearances, the counts as a white density (log scale, so a level a few
/// pixels reach still shows beside one the whole column sits at), graticule
/// lines at 0/25/50/75/100 % labelled 0, 50 and 100 in a gutter to the left,
/// and the red clip marks on the well's top edge (high) and bottom edge
/// (low). The parade (`ParadeView`) draws each of its three wells the same
/// way through `ScopeWell`. An HLG trace's scale (spec §11 HD-15 (f)) labels
/// every line in cd/m² (0, 10, 51, 203, 1000) and dashes the 75 % line,
/// reference white.
final class WaveformTraceView: NSView {
    static let gutter: CGFloat = 24
    static let markHeight: CGFloat = 3
    /// Fixed inks: the well and the trace read the same in either appearance.
    static let well = NSColor(white: 0.06, alpha: 1)
    static let mark = NSColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1)

    var trace: WaveformTrace? {
        didSet {
            guard trace != oldValue else { return }
            image = trace.flatMap(Self.density)
            if let trace { signal = trace.signal }
            needsDisplay = true
        }
    }
    /// The scale drawn: the last trace's signal, kept while there is none.
    var signal: ScopeSignal = .sdr {
        didSet {
            guard signal != oldValue else { return }
            needsDisplay = true
        }
    }
    private var image: CGImage?

    override func draw(_ dirtyRect: NSRect) {
        let well = NSRect(
            x: Self.gutter, y: 0, width: max(0, bounds.width - Self.gutter),
            height: bounds.height)
        ScopeWell.fill(well, image: image)
        ScopeWell.graticule(well, labelsIn: bounds, signal: signal)
        guard let trace else { return }
        ScopeWell.marks(trace, in: well)
    }

    /// The counts as a 256 × 256 white-on-clear image, level 255 at the top.
    static func density(_ trace: WaveformTrace) -> CGImage? {
        ScopeWell.density(trace, tint: (1, 1, 1))
    }
}

/// What the waveform's well and each of the parade's three wells share: the
/// well, the density image, the graticule with its gutter labels, and the
/// clip marks.
enum ScopeWell {
    /// The well's ink and, when there is one, the density image over it.
    static func fill(_ well: NSRect, image: CGImage?) {
        WaveformTraceView.well.setFill()
        well.fill()
        if let image, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.interpolationQuality = .none
            context.draw(image, in: well)
            context.restoreGState()
        }
    }

    /// The reference-white line's dash, on and off (HD-15 (f)), and its ink.
    static let dash: CGFloat = 3
    static let referenceInk = NSColor(white: 1, alpha: 0.45)

    /// Lines at 0/25/50/75/100 % across `well`; with `labelsIn`, `signal`'s
    /// labels (0, 50 and 100 in SDR; every line's cd/m² in HLG) drawn
    /// right-aligned in the gutter left of the well (in `labelsIn`'s height).
    /// `signal`'s reference-white line is dashed in place of its solid line.
    static func graticule(_ well: NSRect, labelsIn bounds: NSRect?, signal: ScopeSignal = .sdr) {
        for (percent, label) in signal.graticule {
            let y = well.minY + well.height * CGFloat(percent) / 100
            let row = min(y, well.maxY - 1)
            if percent == signal.referenceWhitePercent {
                referenceInk.setFill()
                var x = well.minX
                while x < well.maxX {
                    NSRect(x: x, y: row, width: min(dash, well.maxX - x), height: 1).fill()
                    x += 2 * dash
                }
            } else {
                NSColor(white: 1, alpha: 0.18).setFill()
                NSRect(x: well.minX, y: row, width: well.width, height: 1).fill()
            }
            guard let bounds, let label else { continue }
            let text = NSAttributedString(
                string: label,
                attributes: [.font: DS.mono(9), .foregroundColor: DS.textFaint])
            let size = text.size()
            let top = min(max(y - size.height / 2, 0), bounds.height - size.height)
            text.draw(at: NSPoint(x: well.minX - signal.labelGap - size.width, y: top))
        }
    }

    /// The red clip marks: a column bin where at least 0.5 % of the
    /// column's pixels clip gets a mark on the well's top (high) or bottom
    /// (low) edge.
    static func marks(_ trace: WaveformTrace, in well: NSRect) {
        marks(high: trace.marks(high: true), low: trace.marks(high: false), in: well)
    }

    /// The same, from column bins already found (the parade's, cached per
    /// trace).
    static func marks(high: [Int], low: [Int], in well: NSRect) {
        WaveformTraceView.mark.setFill()
        let column = well.width / CGFloat(WaveformTrace.columns)
        let height = WaveformTraceView.markHeight
        for (columns, y) in [(high, well.maxY - height), (low, well.minY)] {
            for index in columns {
                NSRect(
                    x: well.minX + CGFloat(index) * column, y: y, width: max(column, 1),
                    height: height
                ).fill()
            }
        }
    }

    /// The counts as a 256 × 256 image on clear, level 255 at the top, each
    /// cell `tint` at the log density's alpha (premultiplied).
    static func density(_ trace: WaveformTrace, tint: (Double, Double, Double)) -> CGImage? {
        let side = WaveformTrace.columns
        let peak = trace.counts.max() ?? 0
        guard peak > 0, trace.counts.count == side * WaveformTrace.levels else { return nil }
        let scale = 1 / log(1 + Double(peak))
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for column in 0..<side {
            for level in 0..<side {
                let count = trace.counts[column * side + level]
                guard count > 0 else { continue }
                let alpha = min(255, (255 * log(1 + Double(count)) * scale).rounded())
                let at = ((side - 1 - level) * side + column) * 4
                pixels[at] = UInt8((alpha * tint.0).rounded())
                pixels[at + 1] = UInt8((alpha * tint.1).rounded())
                pixels[at + 2] = UInt8((alpha * tint.2).rounded())
                pixels[at + 3] = UInt8(alpha)
            }
        }
        return image(pixels, side: side)
    }

    /// A `side` × `side` premultiplied RGBA image of `pixels`.
    static func image(_ pixels: [UInt8], side: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: side * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
