import AppKit

/// View ▸ Loudness Meter's column (road map "audio" AP7, spec §11 AU-75,
/// AU-76): a fixed 132 pt column at the preview pane's right edge, left of
/// Scopes, its full height. Off, it is zero wide and hidden; its contents are
/// a 132 pt block pinned to its leading edge and clipped, as `ScopesPanelView`'s
/// are, so a zero width never asks a constraint for a negative one.
///
/// It shows `LiveLoudness`'s reading: a −48…0 LUFS scale with the momentary
/// and short-term bars and the Normalize target as a line, then the four
/// figures and a footer saying what is measured. It redraws when the reading
/// changes and never animates, so a capture settles.
///
/// **Nothing here persists** (GR-5's rule): a new window starts with the
/// column off and the meter empty.
final class LoudnessPanelView: NSView {
    static let width: CGFloat = 132
    static let preMasterNote = "The mix as the preview plays it, before the export's loudness setting."
    static let offSpeedNote = "Measured only at normal speed."

    private let content = NSView()
    private let title = NSTextField(labelWithString: "Loudness")
    private let reset = GhostButton(
        symbol: "arrow.counterclockwise", fallback: "↺", caption: nil, tooltip: "Reset",
        action: #selector(EditorViewController.resetLoudnessMeter(_:)),
        size: NSSize(width: 22, height: 22), pointSize: 13)
    private let scale = LoudnessScaleView()
    private let values = ["momentary", "short", "integrated", "truepeak"].map {
        LoudnessPanelView.valueField(id: $0)
    }
    private let names = ["Momentary", "Short-term", "Integrated", "True peak max"].map {
        LoudnessPanelView.nameField($0)
    }
    private let footer = NSTextField(wrappingLabelWithString: LoudnessPanelView.preMasterNote)
    /// Just under required, as Scopes' is.
    private lazy var widthConstraint: NSLayoutConstraint = {
        let width = widthAnchor.constraint(equalToConstant: 0)
        width.priority = NSLayoutConstraint.Priority(999)
        return width
    }()

    init() {
        super.init(frame: .zero)
        widthConstraint.isActive = true
        isHidden = true
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityIdentifier("loudness.panel")
        build()
        show(.empty)
        // The target line reads `NormalizeChoice.targetLUFS` at draw, so a
        // target changed while paused (no new reading) redraws it here.
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged(_:)),
            name: UserDefaults.didChangeNotification, object: nil)
    }

    @objc private func defaultsChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShown else { return }
            self.scale.needsDisplay = true
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("LoudnessPanelView does not support NSCoder")
    }

    var isShown: Bool { widthConstraint.constant > 0 }

    func setShown(_ shown: Bool) {
        widthConstraint.constant = shown ? Self.width : 0
        isHidden = !shown
    }

    /// Follows `loudness` from now on: every change of its reading redraws.
    func bind(_ loudness: LiveLoudness) {
        loudness.onReading = { [weak self] reading in self?.show(reading) }
        show(loudness.reading)
    }

    func show(_ reading: LiveLoudnessReading) {
        scale.momentary = reading.momentaryLUFS
        scale.shortTerm = reading.shortTermLUFS
        values[0].stringValue = Self.format(reading.momentaryLUFS, unit: "LUFS")
        values[1].stringValue = Self.format(reading.shortTermLUFS, unit: "LUFS")
        values[2].stringValue = Self.format(reading.integratedLUFS, unit: "LUFS")
        values[3].stringValue = Self.format(reading.truePeakDBTP, unit: "dBTP")
        values[3].textColor = (reading.truePeakDBTP ?? -.infinity) > -1 ? DS.meterClip : DS.textStrong
        footer.stringValue = reading.offSpeed ? Self.offSpeedNote : Self.preMasterNote
    }

    /// One decimal with U+2212, "—" for none, "−∞" for digital silence.
    static func format(_ value: Double?, unit: String) -> String {
        guard let value else { return "—" }
        guard value.isFinite else { return value < 0 ? "\u{2212}∞ \(unit)" : "∞ \(unit)" }
        let text = String(format: "%.1f", abs(value) < 0.05 ? 0 : value)
        return text.replacingOccurrences(of: "-", with: "\u{2212}") + " " + unit
    }

    override func draw(_ dirtyRect: NSRect) {
        DS.chromeBackground.setFill()
        bounds.fill()
        DS.border.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }

    private static func nameField(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = DS.sans(10)
        field.textColor = DS.textMuted
        return field
    }

    private static func valueField(id: String) -> NSTextField {
        let field = NSTextField(labelWithString: "—")
        field.font = DS.mono(11)
        field.textColor = DS.textStrong
        field.setAccessibilityIdentifier("loudness.\(id)")
        return field
    }

    private func build() {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        title.font = DS.sans(11, weight: .semibold)
        title.textColor = DS.textStrong
        reset.setAccessibilityIdentifier("loudness.reset")
        footer.font = DS.sans(10)
        footer.textColor = DS.textFaint
        footer.preferredMaxLayoutWidth = Self.width - 20
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 1
        for (name, value) in zip(names, values) {
            rows.addArrangedSubview(name)
            rows.addArrangedSubview(value)
            rows.setCustomSpacing(6, after: value)
        }
        for view in [title, reset, scale, rows, footer] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.widthAnchor.constraint(equalToConstant: Self.width),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            reset.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            reset.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            scale.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            scale.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scale.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scale.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            rows.topAnchor.constraint(equalTo: scale.bottomAnchor, constant: 10),
            rows.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            rows.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -6),
            footer.topAnchor.constraint(equalTo: rows.bottomAnchor, constant: 4),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            footer.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -8),
        ])
        // The scale takes whatever height the pane leaves; the rows and the
        // footer keep theirs.
        let fill = footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8)
        fill.priority = .defaultLow
        fill.isActive = true
        scale.setContentHuggingPriority(.defaultLow, for: .vertical)
        scale.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }
}

/// The column's −48…0 LUFS scale: ticks every 6 LU labelled at the left, the
/// momentary and short-term bars, and the Normalize target as a 1 pt accent
/// line (read at draw; the panel redraws it on a defaults change, so a target
/// changed while paused shows at once).
final class LoudnessScaleView: NSView {
    static let floorLUFS = -48.0
    var momentary: Double? { didSet { if momentary != oldValue { needsDisplay = true } } }
    var shortTerm: Double? { didSet { if shortTerm != oldValue { needsDisplay = true } } }

    private static let labelWidth: CGFloat = 24
    private static let barWidth: CGFloat = 26
    private static let barGap: CGFloat = 8
    private static let captionHeight: CGFloat = 14

    /// The height a level sits at in a plot `height` tall.
    static func y(_ lufs: Double, in plot: NSRect) -> CGFloat {
        let clamped = min(0, max(floorLUFS, lufs))
        return plot.minY + plot.height * CGFloat((clamped - floorLUFS) / -floorLUFS)
    }

    override func draw(_ dirtyRect: NSRect) {
        let plot = NSRect(
            x: bounds.minX + Self.labelWidth, y: bounds.minY + Self.captionHeight,
            width: Self.barWidth * 2 + Self.barGap,
            height: max(0, bounds.height - Self.captionHeight - 6))
        let tickAttributes: [NSAttributedString.Key: Any] = [
            .font: DS.mono(9), .foregroundColor: DS.textFaint,
        ]
        for step in 0...8 {
            let lufs = -6.0 * Double(step)
            let y = Self.y(lufs, in: plot)
            let text = step == 0 ? "0" : "\u{2212}\(6 * step)"
            let size = (text as NSString).size(withAttributes: tickAttributes)
            (text as NSString).draw(
                at: NSPoint(x: Self.labelWidth - 4 - size.width, y: y - size.height / 2),
                withAttributes: tickAttributes)
            DS.textFaint.setFill()
            NSRect(x: plot.minX - 2, y: y, width: 2, height: 1).fill()
        }
        for (index, value) in [momentary, shortTerm].enumerated() {
            let column = NSRect(
                x: plot.minX + CGFloat(index) * (Self.barWidth + Self.barGap), y: plot.minY,
                width: Self.barWidth, height: plot.height)
            DS.meterTrough.setFill()
            column.fill()
            if let value, value.isFinite {
                DS.meterFill.setFill()
                NSRect(
                    x: column.minX, y: column.minY, width: column.width,
                    height: Self.y(value, in: plot) - column.minY
                ).fill()
            }
            let caption = index == 0 ? "M" : "S"
            let size = (caption as NSString).size(withAttributes: tickAttributes)
            (caption as NSString).draw(
                at: NSPoint(x: column.midX - size.width / 2, y: bounds.minY + 1),
                withAttributes: tickAttributes)
        }
        DS.accent.setFill()
        NSRect(
            x: plot.minX, y: Self.y(NormalizeChoice.targetLUFS, in: plot),
            width: plot.width, height: 1
        ).fill()
    }
}
