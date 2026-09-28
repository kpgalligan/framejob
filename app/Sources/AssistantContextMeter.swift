import AppKit

/// How full the assistant conversation's context is: tokens in play after
/// the last response, against the model's context window, both reported by
/// the helper (`context_usage`). Rasterize's, ported.
struct AssistantContextUsage: Equatable {
    var used = 0
    /// The model's context window; nil until the helper has looked it up, or
    /// when the Models API did not say.
    var limit: Int?
    /// False until the helper has reported at all.
    var reported = false
}

/// The Assistant tab's context meter, inline along the tab's top rather than in
/// Rasterize's popover: a square 3 pt track filled to the used fraction (the
/// block slider's track, `Controls.swift`), and the figures beside a "Context"
/// micro label. Road map 12 A2.
final class AssistantContextMeterView: NSView {
    private let bar = AssistantContextBar()
    private let title = NSTextField(labelWithString: "")
    let figuresLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        title.attributedStringValue = DS.microLabel("Context")
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        figuresLabel.font = DS.mono(10)
        figuresLabel.textColor = DS.textFaint
        figuresLabel.lineBreakMode = .byTruncatingTail
        figuresLabel.alignment = .right
        figuresLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        figuresLabel.setAccessibilityIdentifier("assistant.context")
        for view in [title, figuresLabel, bar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // A label's frame is 2 pt wider than its text on each side; the
        // insets keep both frames inside this view.
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            figuresLabel.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            figuresLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
            figuresLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            bar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 3),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        update(AssistantContextUsage())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AssistantContextMeterView does not support NSCoder")
    }

    func update(_ usage: AssistantContextUsage) {
        figuresLabel.stringValue = Self.figures(usage)
        bar.fraction = Self.fraction(usage)
    }

    /// "Nothing reported yet", "N of L tokens · P%", or "N tokens (window
    /// size unknown)".
    static func figures(_ usage: AssistantContextUsage) -> String {
        let used = usage.used.formatted()
        switch (usage.reported, usage.limit) {
        case (false, _):
            return "Nothing reported yet"
        case (true, let limit?) where limit > 0:
            let percent = (fraction(usage) * 100)
                .formatted(.number.precision(.fractionLength(0...1)))
            return "\(used) of \(limit.formatted()) tokens · \(percent)%"
        case (true, _):
            return "\(used) tokens (window size unknown)"
        }
    }

    private static func fraction(_ usage: AssistantContextUsage) -> Double {
        guard usage.reported, let limit = usage.limit, limit > 0 else { return 0 }
        return min(1, Double(usage.used) / Double(limit))
    }
}

/// A square track with the used fraction filled in the accent; the fill
/// turns to the meter's clip colour past 80%.
private final class AssistantContextBar: NSView {
    var fraction: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        DS.border.setFill()
        bounds.fill()
        guard fraction > 0 else { return }
        (fraction > 0.8 ? DS.meterClip : DS.accent).setFill()
        // At least a sliver, so a small conversation still shows as used.
        let width = max(2, bounds.width * CGFloat(fraction))
        NSRect(x: 0, y: 0, width: width, height: bounds.height).fill()
    }
}
