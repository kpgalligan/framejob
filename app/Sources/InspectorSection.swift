import AppKit

// MARK: - Sections

/// One disclosure group: a header with the title, a right-aligned summary of
/// what the group currently says, an optional reset-to-default button, and the
/// rows. Collapsed state is per section id in `UserDefaults`, so a pane
/// rebuilt after every edit does not keep re-opening a group the user closed.
///
/// **The stored value records COLLAPSED, not expanded** — a section nobody has
/// touched has no stored value at all, which is what lets `defaultExpanded`
/// mean anything. Flipping that spelling would invert every saved panel.
final class InspectorSection: NSView {
    /// `UserDefaults` key prefix; the suffix is the section's stable id.
    static let collapsedKeyPrefix = "ReelcutInspectorSection."

    let id: String
    let title: String
    private let header = InspectorSectionHeader()
    private let content = NSStackView()
    private(set) var isExpanded = true
    private let summary: (() -> String?)?
    /// The rows' marks, folded (road map 9 §5) at the end of `init` and on
    /// every `refresh()`.
    private(set) var marks = SectionMarks.empty
    /// "Actions don't animate this" — shown while every row that writes is ⊘.
    private var inertNote: InspectorNoteLabel?
    /// The header's click, after the preference is stored — and nothing else:
    /// `reveal()` and `expandByDefault()` never call it (`KeyedReveal`).
    var didToggle: ((InspectorSection) -> Void)?

    /// `summary` is a closure rather than a string because it is re-read on
    /// every `refresh()`: a collapsed section still has to tell the truth
    /// about the value under it. `defaultExpanded` is the state before the
    /// user has ever touched THIS section — the design opens Transform and
    /// the primary section of a text or shape selection, and closes the rest.
    init(
        id: String, title: String, summary: (() -> String?)? = nil,
        note: (() -> String?)? = nil, reset: (() -> Void)? = nil,
        defaultExpanded: Bool = true, rows: [NSView]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        super.init(frame: .zero)
        let key = Self.collapsedKeyPrefix + id
        if let collapsed = UserDefaults.standard.object(forKey: key) as? Bool {
            isExpanded = !collapsed
        } else {
            isExpanded = defaultExpanded
        }

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = InspectorMetrics.rowSpacing
        content.edgeInsets = NSEdgeInsets(
            top: 2, left: InspectorMetrics.inset, bottom: 8, right: InspectorMetrics.inset)
        let inert = InspectorNoteLabel { [weak self] in
            self?.marks.allNotAnimatable == true
                ? "Actions don't animate this. Edits here change the clip." : nil
        }
        inert.textColor = DS.textFaint
        inertNote = inert
        addRow(inert)
        if let note = note {
            addRow(InspectorNoteLabel(note: note))
        }
        for row in rows { addRow(row) }

        header.configure(title: title, reset: reset)
        header.onToggle = { [weak self] in self?.toggle() }

        let stack = NSStackView(views: [header, content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            content.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        content.isHidden = !isExpanded
        header.isExpanded = isExpanded
        for gutter in Self.gutters(in: content) { gutter.refresh() }
        foldMarks()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorSection does not support NSCoder")
    }

    private func addRow(_ row: NSView) {
        content.addArrangedSubview(row)
        row.widthAnchor.constraint(
            equalTo: content.widthAnchor, constant: -2 * InspectorMetrics.inset).isActive = true
    }

    private func toggle() {
        isExpanded.toggle()
        content.isHidden = !isExpanded
        header.isExpanded = isExpanded
        UserDefaults.standard.set(!isExpanded, forKey: Self.collapsedKeyPrefix + id)
        didToggle?(self)
    }

    /// Opens the section and writes NO preference — the selected action's
    /// auto-open (spec §11 CI-8), which must leave the person's own layout
    /// standing for when the action is left.
    func reveal() {
        isExpanded = true
        content.isHidden = false
        header.isExpanded = true
    }

    /// Opens the section as a DEFAULT, for a pane that decided after building
    /// it that this is the group to open (`ClipPane`'s "the first section is
    /// open when there is no Transform"). `defaultExpanded` cannot say it: the
    /// pane only knows which section is first once it has them all.
    ///
    /// **It defers to the user and writes nothing.** A section the user has
    /// ever toggled has a stored value, and re-opening a group somebody closed
    /// on every rebuild would be worse than the closed panel this fixes;
    /// storing the state here would then make that override permanent.
    /// Returns whether it opened the section, so a caller walking a list can
    /// stop at the first one that had no stored preference.
    @discardableResult
    func expandByDefault() -> Bool {
        guard UserDefaults.standard.object(forKey: Self.collapsedKeyPrefix + id) == nil,
              !isExpanded
        else { return false }
        isExpanded = true
        content.isHidden = false
        header.isExpanded = true
        return true
    }

    func refresh() {
        refreshOptionControls(in: content)
        foldMarks()
    }

    /// The rows' gutters, in the order `refreshOptionControls(in:)` walks.
    private static func gutters(in view: NSView) -> [InspectorMarkGutter] {
        view.subviews.flatMap { subview -> [InspectorMarkGutter] in
            if let gutter = subview as? InspectorMarkGutter { return [gutter] }
            return gutters(in: subview)
        }
    }

    /// `marks` from the gutters as they stand, then the two things drawn from
    /// it: the ⊘ note and the header.
    private func foldMarks() {
        let gutters = Self.gutters(in: content)
        let writing = gutters.filter { !$0.writes.isEmpty }
        marks = SectionMarks(
            keyed: gutters.reduce(into: Set<String>()) { $0.formUnion($1.keyedWrites()) }.count,
            other: gutters.contains {
                if case .other = $0.mark { return true } else { return false }
            },
            allNotAnimatable: !writing.isEmpty
                && writing.allSatisfy { $0.mark == .notAnimatable })
        inertNote?.refresh()
        header.refresh(summary: summary?(), marks: marks)
    }
}

/// The section header: disclosure triangle, title in the micro-label face, the
/// current-state summary, and the reset button pinned to the trailing edge.
/// The button is a subview so it eats its own clicks — everything else toggles
/// the group.
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
    /// Held so the summary can stop short of it: the two share the header's
    /// trailing end, and a summary drawn under the button would be unreadable.
    private weak var resetButton: NSView?

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

    func configure(title: String, reset: (() -> Void)?) {
        self.title = title
        guard let reset = reset else { return }
        let button = OptionButtonControl(
            title: "Reset", action: reset, enabled: { true }, onEdit: {})
        button.toolTip = "Reset this section to its defaults"
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        resetButton = button
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -InspectorMetrics.inset),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// Takes the summary and the marks; redraws only when either moved.
    func refresh(summary: String?, marks: SectionMarks) {
        guard summary != lastSummary || marks != self.marks else { return }
        lastSummary = summary
        self.marks = marks
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
    /// title and the Reset button. Truncated rather than clipped: it is a
    /// sentence fragment, and half a word with no ellipsis reads as a bug.
    private func drawSummary(after titleEnd: CGFloat) {
        guard let text = lastSummary, !text.isEmpty else { return }
        // A Reset button that Auto Layout has not placed yet has a zero frame,
        // and taking its minX would put the summary's right edge at −6 and skip
        // it below. `refreshSummary` only redraws when the TEXT changes, so a
        // summary skipped on the first pass would stay missing until its value
        // moved — hence the unplaced button falls back to the inset.
        let button = resetButton.map { $0.frame.width > 0 ? $0.frame.minX : nil } ?? nil
        let right = (button ?? bounds.width - InspectorMetrics.inset) - 6
        let left = titleEnd + 8
        guard right - left > 14 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: DS.mono(10), .foregroundColor: marks.keyed > 0 ? DS.action : DS.textFaint,
            .paragraphStyle: paragraph,
        ]
        let height = text.size(withAttributes: attributes).height
        text.draw(
            in: NSRect(x: left, y: bounds.midY - height / 2, width: right - left, height: height),
            withAttributes: attributes)
    }
}

/// The auto-open (spec §11 CI-8): the sections the selected action keys are
/// revealed on the sub-tab showing them, remembered for as long as that
/// action stays selected — so a rebuild under the same action re-reveals
/// them, a sub-tab first shown later adds its own, and a header click that
/// closes one drops it. One per `ClipPane`, applied at the end of every
/// `makeSections()`; it lives here because `ClipPane.swift` is at its cap.
final class KeyedReveal {
    private(set) var action: UInt32?
    private(set) var seen: Set<String> = []
    private(set) var ids: Set<String> = []

    func apply(_ sections: [InspectorSection], action: UInt32?, subTab: String) {
        guard let action else {
            (self.action, seen, ids) = (nil, [], [])
            return
        }
        if action != self.action { (self.action, seen, ids) = (action, [], []) }
        if !seen.contains(subTab) {
            seen.insert(subTab)
            ids.formUnion(sections.filter { $0.marks.keyed > 0 }.map(\.id))
        }
        for section in sections {
            section.didToggle = { [weak self] in self?.ids.remove($0.id) }
            if ids.contains(section.id) { section.reveal() }
        }
    }
}
