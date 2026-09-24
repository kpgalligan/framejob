import AppKit

/// The section header: disclosure triangle, title in the micro-label face, the
/// current-state summary, and the Reset or Clear button pinned to the trailing
/// edge. The buttons are subviews so they eat their own clicks — everything
/// else toggles the group.
///
/// Spec §11 CI-9: a section EDITING an action (`marks.editing`) shows Clear,
/// only while the action keys one of its rows; otherwise it shows Reset, only
/// while it differs from its default. Both share the one slot, and at most
/// one is visible.
final class InspectorSectionHeader: NSView {
    var onToggle: (() -> Void)?
    var isExpanded = true {
        didSet { needsDisplay = true }
    }
    private var title = ""
    /// The last summary and marks drawn, so a refresh only redraws when one
    /// CHANGED — the panel refreshes on every document change and on every
    /// playhead move inside an action.
    private var lastSummary: String?
    private var marks = SectionMarks.empty
    /// Held so the summary can stop short of the VISIBLE one: they share the
    /// header's trailing end, and a summary drawn under a button would be
    /// unreadable. Clear is always built; Reset only for a section with one.
    private weak var resetButton: NSView?
    private weak var clearButton: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorSectionHeader does not support NSCoder")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: InspectorMetrics.headerHeight)
    }

    func configure(title: String, reset: (() -> Void)?, clear: @escaping () -> Void) {
        self.title = title
        clearButton = install(
            OptionButtonControl(title: "Clear", action: clear, enabled: { true }, onEdit: {}))
        if let reset {
            let button = install(
                OptionButtonControl(title: "Reset", action: reset, enabled: { true }, onEdit: {}))
            button.toolTip = "Reset this section to its defaults"
            resetButton = button
        }
        showButtons()
    }

    private func install(_ button: NSView) -> NSView {
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -InspectorMetrics.inset),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        return button
    }

    /// CI-9's one slot: Clear while editing an action that keys the section,
    /// Reset while not editing and the section differs, else nothing.
    private func showButtons() {
        let editing = marks.editing
        clearButton?.isHidden = editing == nil || marks.keyed == 0
        clearButton?.toolTip = editing.map { "Remove this section from action \($0)" }
        resetButton?.isHidden = editing != nil || !marks.differs
    }

    /// The visible button's title — "Clear", "Reset" or nil.
    var buttonTitle: String? {
        if clearButton?.isHidden == false { return "Clear" }
        if resetButton?.isHidden == false { return "Reset" }
        return nil
    }

    /// The summary's ink: the action's when keyed, the body tier
    /// (`DS.textMuted`, spec §11 CI-9) when the section differs from its
    /// default, else faint.
    var summaryInk: NSColor {
        marks.keyed > 0 ? DS.action : marks.differs ? DS.textMuted : DS.textFaint
    }

    /// Takes the summary and the marks; redraws only when either moved.
    func refresh(summary: String?, marks: SectionMarks) {
        guard summary != lastSummary || marks != self.marks else { return }
        lastSummary = summary
        self.marks = marks
        showButtons()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onToggle?()
    }

    override func draw(_ dirtyRect: NSRect) {
        // **Pitfall:** `DS.hoverFill` is `quaternaryLabelColor`, which is
        // ALREADY about 10% ink — taking 0.35 of it left a 3.5% wash that is
        // invisible in the light appearance, so the header did not separate
        // from the rows under it. Drawn at its own alpha it is a quiet band
        // that reads in both appearances.
        DS.hoverFill.setFill()
        bounds.fill()
        DS.border.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        let glyph = isExpanded ? "chevron.down" : "chevron.right"
        let box = NSRect(x: InspectorMetrics.inset, y: bounds.midY - 5, width: 10, height: 10)
        if let icon = NSImage(systemSymbolName: glyph, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        {
            let tinted = icon.tinted(with: DS.textMuted)
            let size = tinted.size
            tinted.draw(
                in: NSRect(
                    x: box.minX, y: box.midY - size.height / 2, width: size.width,
                    height: size.height))
        } else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: DS.sans(9), .foregroundColor: DS.textMuted,
            ]
            (isExpanded ? "▾" : "▸").draw(
                at: NSPoint(x: box.minX, y: box.minY), withAttributes: attributes)
        }

        let label = Self.titleLabel(title)
        label.draw(at: NSPoint(x: box.maxX + 6, y: bounds.midY - label.size().height / 2))
        drawSummary(after: drawMarks(after: box.maxX + 6 + label.size().width))
    }

    /// `◆N` in the action ink, then ◇ and ⊘ faint, after the title; answers
    /// where they end.
    private func drawMarks(after titleEnd: CGFloat) -> CGFloat {
        var x = titleEnd
        var parts: [(String, NSFont, NSColor)] = []
        if marks.keyed > 0 {
            parts.append(("◆\(marks.keyed)", DS.mono(9, weight: .medium), DS.action))
        }
        if marks.other { parts.append(("◇", DS.mono(9), DS.textFaint)) }
        if marks.allNotAnimatable { parts.append(("⊘", DS.mono(9), DS.textFaint)) }
        for (text, font, ink) in parts {
            let mark = NSAttributedString(
                string: text, attributes: [.font: font, .foregroundColor: ink])
            let size = mark.size()
            mark.draw(at: NSPoint(x: x + 6, y: bounds.midY - size.height / 2))
            x += 6 + size.width
        }
        return x
    }

    /// The title in the micro-label FACE — mono 10, uppercase, 0.09em tracking
    /// — but not in the micro-label's ink.
    ///
    /// **Pitfall:** `DS.microLabel` paints in `DS.textFaint`
    /// (`tertiaryLabelColor`), which over this header's fill is grey on grey;
    /// with the Clip tab now stacking up to twenty collapsed headers, that
    /// reads as a list of DISABLED rows rather than a list of groups. Built
    /// here rather than by changing `DS.microLabel`, whose other callers draw
    /// one quiet label over the chrome, where faint is right. The summary
    /// beside it stays `textFaint`: it is secondary to the title.
    private static func titleLabel(_ title: String) -> NSAttributedString {
        let size: CGFloat = 10
        return NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: DS.mono(size), .kern: size * 0.09, .foregroundColor: DS.textMuted,
            ])
    }

    /// The state summary, right-aligned in whatever room is left between the
    /// title and the visible button. Truncated rather than clipped: it is a
    /// sentence fragment, and half a word with no ellipsis reads as a bug.
    private func drawSummary(after titleEnd: CGFloat) {
        guard let text = lastSummary, !text.isEmpty else { return }
        // A button that Auto Layout has not placed yet has a zero frame, and
        // taking its minX would put the summary's right edge at −6 and skip it
        // below. `refresh(summary:marks:)` only redraws when the summary or
        // the marks change, so a summary skipped on the first pass would stay
        // missing until one moved — hence the unplaced button falls back to
        // the inset.
        let visible = [clearButton, resetButton].compactMap { $0 }.first { !$0.isHidden }
        let button = visible.map { $0.frame.width > 0 ? $0.frame.minX : nil } ?? nil
        let right = (button ?? bounds.width - InspectorMetrics.inset) - 6
        let left = titleEnd + 8
        guard right - left > 14 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: DS.mono(10), .foregroundColor: summaryInk,
            .paragraphStyle: paragraph,
        ]
        let height = text.size(withAttributes: attributes).height
        text.draw(
            in: NSRect(x: left, y: bounds.midY - height / 2, width: right - left, height: height),
            withAttributes: attributes)
    }
}
