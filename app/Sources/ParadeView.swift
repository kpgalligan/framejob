import AppKit

/// The parade slot's body (spec §11 GR-10): R′, G′ and B′ side by side, three
/// wells 4 pt apart after the waveform's labelled gutter, each drawn as the
/// waveform's well is (`ScopeWell`: graticule at 0/25/50/75/100 %, log
/// density, the red clip marks per channel) with its density tinted red,
/// green or blue.
final class ParadeView: NSView {
    static let gap: CGFloat = 4
    /// Each channel's density ink, premultiplied by the density's alpha.
    static let tints: [(Double, Double, Double)] = [
        (1, 0.35, 0.35), (0.35, 1, 0.35), (0.45, 0.6, 1),
    ]

    var trace: ParadeTrace? {
        didSet {
            guard trace != oldValue else { return }
            let channels = (0..<3).map { index in trace?.channel(index) }
            images = channels.enumerated().map { index, channel in
                channel.flatMap { ScopeWell.density($0, tint: Self.tints[index]) }
            }
            marks = channels.map { channel in
                channel.map { ($0.marks(high: true), $0.marks(high: false)) } ?? ([], [])
            }
            if let trace { signal = trace.signal }
            needsDisplay = true
        }
    }
    /// The scale drawn (spec §11 HD-15 (f)): the last trace's signal, kept
    /// while there is none.
    var signal: ScopeSignal = .sdr {
        didSet {
            guard signal != oldValue else { return }
            needsDisplay = true
        }
    }
    private var images: [CGImage?] = [nil, nil, nil]
    /// Each channel's clip-mark column bins, high and low, found once per trace.
    private var marks: [(high: [Int], low: [Int])] = Array(repeating: ([], []), count: 3)

    /// The three wells' rects, R′ first.
    func wells() -> [NSRect] {
        let start = WaveformTraceView.gutter
        let width = max(0, (bounds.width - start - 2 * Self.gap) / 3)
        return (0..<3).map { index in
            NSRect(
                x: start + CGFloat(index) * (width + Self.gap), y: 0, width: width,
                height: bounds.height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, well) in wells().enumerated() {
            ScopeWell.fill(well, image: images[index])
            ScopeWell.graticule(well, labelsIn: index == 0 ? bounds : nil, signal: signal)
            ScopeWell.marks(high: marks[index].high, low: marks[index].low, in: well)
        }
    }
}
