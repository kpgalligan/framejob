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
    private var usage = AssistantContextUsage()
    /// Measures a rung in the label's font; never in the hierarchy.
    private let measure = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        title.attributedStringValue = DS.microLabel("Context")
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        figuresLabel.font = DS.mono(10)
        measure.font = DS.mono(10)
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
        self.usage = usage
        figuresLabel.toolTip = Self.figures(usage)
        showFittingFigure()
        bar.fraction = Self.fraction(usage)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        showFittingFigure()
    }

    /// The first rung of `figureLadder` that fits beside the title, or the
    /// last when none does. The 12 is the constraints' 2 pt inset, 8 pt gap
    /// and 2 pt inset.
    private func showFittingFigure() {
        let room = bounds.width - title.intrinsicContentSize.width - 12
        let shown = fittingRung(Self.figureLadder(usage), room: room, measure: measure)
        if figuresLabel.stringValue != shown { figuresLabel.stringValue = shown }
    }

    /// The full figures — "Nothing reported yet", "N of L tokens · P%", or
    /// "N tokens (window size unknown)": `figureLadder`'s first rung.
    static func figures(_ usage: AssistantContextUsage) -> String {
        figureLadder(usage)[0]
    }

    /// The figures from longest to shortest: the full figures (`figures(_:)`)
    /// first, then "N / L · P%" and "P%", or "N tokens".
    static func figureLadder(_ usage: AssistantContextUsage) -> [String] {
        let used = usage.used.formatted()
        switch (usage.reported, usage.limit) {
        case (false, _):
            return ["Nothing reported yet"]
        case (true, let limit?) where limit > 0:
            let percent = (fraction(usage) * 100)
                .formatted(.number.precision(.fractionLength(0...1)))
            return [
                "\(used) of \(limit.formatted()) tokens · \(percent)%",
                "\(used) / \(limit.formatted()) · \(percent)%", "\(percent)%",
            ]
        case (true, _):
            return ["\(used) tokens (window size unknown)", "\(used) tokens"]
        }
    }

    private static func fraction(_ usage: AssistantContextUsage) -> Double {
        guard usage.reported, let limit = usage.limit, limit > 0 else { return 0 }
        return min(1, Double(usage.used) / Double(limit))
    }
}

/// The Assistant tab's Spend row (road map 13 P4, spec §11 P-7): a "Spend"
/// micro label and what the conversation has cost so far, as Frame Job
/// estimates it (`AssistantTurnCost.figure`, or its shorter rung where that
/// does not fit, P-8), laid out like the meter's label row.
final class AssistantConversationCostView: NSView {
    private let title = NSTextField(labelWithString: "")
    let figureLabel = NSTextField(labelWithString: "")
    private var cost = AssistantTurnCost()
    /// Measures a rung in the label's font; never in the hierarchy.
    private let measure = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        title.attributedStringValue = DS.microLabel("Spend")
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        figureLabel.font = DS.mono(10)
        measure.font = DS.mono(10)
        figureLabel.textColor = DS.textFaint
        figureLabel.lineBreakMode = .byTruncatingTail
        figureLabel.alignment = .right
        figureLabel.toolTip = AssistantTurnCost.figureTooltip
        figureLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        figureLabel.setAccessibilityIdentifier("assistant.spend")
        for view in [title, figureLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // The meter's 2 pt insets: a label's frame is 2 pt wider than its text.
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor),
            title.bottomAnchor.constraint(equalTo: bottomAnchor),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            figureLabel.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            figureLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
            figureLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
        ])
        update(AssistantTurnCost())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AssistantConversationCostView does not support NSCoder")
    }

    func update(_ cost: AssistantTurnCost) {
        self.cost = cost
        showFittingFigure()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        showFittingFigure()
    }

    /// The first rung of `figureLadder` that fits beside the title, or the
    /// last when none does (spec §11 P-8) — the meter's shape and its 12 pt.
    private func showFittingFigure() {
        let room = bounds.width - title.intrinsicContentSize.width - 12
        let shown = fittingRung(cost.figureLadder, room: room, measure: measure)
        if figureLabel.stringValue != shown { figureLabel.stringValue = shown }
    }
}

/// The first rung of `ladder` whose width in `measure`'s font fits `room`, or
/// the last when none does — the meter's and the Spend row's one search.
private func fittingRung(_ ladder: [String], room: CGFloat, measure: NSTextField) -> String {
    ladder.first { rung in
        measure.stringValue = rung
        return measure.intrinsicContentSize.width <= room
    } ?? ladder[ladder.count - 1]
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
