import AppKit

/// View ▸ Waveform's panel (spec §11 GR-5): a fixed 248 pt column at the
/// right edge of the preview pane, between the picture and the inspector, the
/// pane's full height. Off, it is zero wide and hidden, and the canvas, pinned
/// to its leading edge, takes the whole pane.
///
/// Its contents are a 248 pt block pinned to its leading edge and clipped, so
/// a zero width never asks a constraint for a negative one. Showing it
/// attaches its window's tap (`WaveformTaps`), hiding it — or leaving the
/// window — detaches it, so the GPU pass runs only while it is on screen.
/// Nothing here persists (GR-5): a new window starts with it off.
final class WaveformPanelView: NSView {
    static let width: CGFloat = 248
    /// The trace's height: the well plus its two 3 pt mark bands' room.
    static let traceHeight: CGFloat = 200
    private static let inset: CGFloat = 12

    private let content = NSView()
    private let header = NSTextField(labelWithString: "Waveform")
    private let traceView = WaveformTraceView()
    private let highlights = NSTextField(labelWithString: WaveformTrace.noHighlights)
    private let shadows = NSTextField(labelWithString: WaveformTrace.noShadows)
    /// Just under required: a pane narrower than the panel (never reached,
    /// the split keeps 380 pt) squeezes it rather than logging a conflict.
    private lazy var widthConstraint: NSLayoutConstraint = {
        let width = widthAnchor.constraint(equalToConstant: 0)
        width.priority = NSLayoutConstraint.Priority(999)
        return width
    }()
    /// The key the tap is attached under, while shown.
    private var key: Int?

    init() {
        super.init(frame: .zero)
        widthConstraint.isActive = true
        isHidden = true
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityIdentifier("waveform.panel")
        build()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("WaveformPanelView does not support NSCoder")
    }

    var isShown: Bool { widthConstraint.constant > 0 }

    /// Shows or hides the panel for the document keyed `key`.
    func setShown(_ shown: Bool, key: Int) {
        widthConstraint.constant = shown ? Self.width : 0
        isHidden = !shown
        if shown {
            self.key = key
            attach()
        } else {
            WaveformTaps.shared.detach(key: key)
            self.key = nil
            show(nil)
        }
    }

    /// The trace to draw; nil is "no frame yet" (the readouts say "—").
    func show(_ trace: WaveformTrace?) {
        traceView.trace = trace
        highlights.stringValue = trace?.highlightsReadout ?? WaveformTrace.noHighlights
        shadows.stringValue = trace?.shadowsReadout ?? WaveformTrace.noShadows
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let key else { return }
        if window == nil {
            WaveformTaps.shared.detach(key: key)
        } else {
            attach()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        DS.chromeBackground.setFill()
        bounds.fill()
        DS.border.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }

    private func attach() {
        guard let key else { return }
        WaveformTaps.shared.attach(key: key) { [weak self] trace in self?.show(trace) }
    }

    private func build() {
        header.font = DS.sans(12, weight: .semibold)
        header.textColor = DS.textStrong
        for readout in [highlights, shadows] {
            readout.font = DS.mono(11)
            readout.textColor = DS.textMuted
        }
        highlights.setAccessibilityIdentifier("waveform.highlights")
        shadows.setAccessibilityIdentifier("waveform.shadows")
        traceView.setAccessibilityIdentifier("waveform.trace")
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        for view in [header, traceView, highlights, shadows] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        let inset = Self.inset
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.widthAnchor.constraint(equalToConstant: Self.width),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            traceView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            traceView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            traceView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            traceView.heightAnchor.constraint(equalToConstant: Self.traceHeight),
            highlights.topAnchor.constraint(equalTo: traceView.bottomAnchor, constant: 8),
            highlights.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            shadows.topAnchor.constraint(equalTo: highlights.bottomAnchor, constant: 4),
            shadows.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
        ])
    }
}

/// The trace itself: a near-black well in both appearances, the counts as a
/// white density (log scale, so a level a few pixels reach still shows beside
/// one the whole column sits at), graticule lines at 0/25/50/75/100 %
/// labelled 0, 50 and 100 in a gutter to the left, and the red clip marks on
/// the well's top edge (high) and bottom edge (low).
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
            needsDisplay = true
        }
    }
    private var image: CGImage?

    override func draw(_ dirtyRect: NSRect) {
        let well = NSRect(
            x: Self.gutter, y: 0, width: max(0, bounds.width - Self.gutter),
            height: bounds.height)
        Self.well.setFill()
        well.fill()
        if let image, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.interpolationQuality = .none
            context.draw(image, in: well)
            context.restoreGState()
        }
        let labels = [0: "0", 50: "50", 100: "100"]
        for percent in stride(from: 0, through: 100, by: 25) {
            let y = well.minY + well.height * CGFloat(percent) / 100
            NSColor(white: 1, alpha: 0.18).setFill()
            NSRect(x: well.minX, y: min(y, well.maxY - 1), width: well.width, height: 1).fill()
            guard let label = labels[percent] else { continue }
            let text = NSAttributedString(
                string: label,
                attributes: [.font: DS.mono(9), .foregroundColor: DS.textFaint])
            let size = text.size()
            let top = min(max(y - size.height / 2, 0), bounds.height - size.height)
            text.draw(at: NSPoint(x: Self.gutter - 4 - size.width, y: top))
        }
        guard let trace else { return }
        Self.mark.setFill()
        let column = well.width / CGFloat(WaveformTrace.columns)
        for (high, y) in [(true, well.maxY - Self.markHeight), (false, well.minY)] {
            for index in trace.marks(high: high) {
                NSRect(
                    x: well.minX + CGFloat(index) * column, y: y, width: max(column, 1),
                    height: Self.markHeight
                ).fill()
            }
        }
    }

    /// The counts as a 256 × 256 white-on-clear image, level 255 at the top.
    static func density(_ trace: WaveformTrace) -> CGImage? {
        let side = WaveformTrace.columns
        let peak = trace.counts.max() ?? 0
        guard peak > 0, trace.counts.count == side * WaveformTrace.levels else { return nil }
        let scale = 1 / log(1 + Double(peak))
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for column in 0..<side {
            for level in 0..<side {
                let count = trace.counts[column * side + level]
                guard count > 0 else { continue }
                let alpha = UInt8(min(255, (255 * log(1 + Double(count)) * scale).rounded()))
                let at = ((side - 1 - level) * side + column) * 4
                // Premultiplied white: every channel is the alpha.
                pixels[at] = alpha
                pixels[at + 1] = alpha
                pixels[at + 2] = alpha
                pixels[at + 3] = alpha
            }
        }
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

/// The "Ungraded" tag (spec §11 GR-4): top-left of the preview pane, inside
/// the canvas's 24 pt void, shown while View ▸ Show Ungraded is on. It takes
/// no clicks, so a gesture on the canvas beneath it is the canvas's.
final class UngradedTagView: NSTextField {
    init() {
        super.init(frame: .zero)
        stringValue = "Ungraded"
        isEditable = false
        isSelectable = false
        isBezeled = false
        isBordered = false
        drawsBackground = true
        backgroundColor = DS.chromeBackground
        textColor = DS.textMuted
        font = DS.mono(10)
        isHidden = true
        setAccessibilityIdentifier("preview.ungraded")
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("UngradedTagView does not support NSCoder")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
