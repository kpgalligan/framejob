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
    static let collapsedKeyPrefix = "FrameJobInspectorSection."

    let id: String
    let title: String
    let header = InspectorSectionHeader()
    private let content = NSStackView()
    private(set) var isExpanded = true
    private let summary: (() -> String?)?
    /// An explicit "differs from its default" (spec §11 CI-9), for a section
    /// whose rows do not read the props or whose Reset writes fewer keys
    /// than its rows read; nil folds the rows' own defaults.
    private let differs: (() -> Bool)?
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
        differs: (() -> Bool)? = nil, defaultExpanded: Bool = true, rows: [NSView]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.differs = differs
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

        header.configure(title: title, reset: reset, clear: { [weak self] in self?.clear() })
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
        // The redesign's one animation (spec §11 CI-15): through `DS.animate`,
        // which runs it unanimated under Reduce Motion. The state is set at once.
        DS.animate(DS.stateDuration) {
            content.isHidden = !isExpanded
            superview?.layoutSubtreeIfNeeded()
        }
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

    /// The header's Clear (spec §11 CI-9): every key the section's rows
    /// write that the selected action holds, out of its end patch in ONE
    /// `set_action_end`.
    func clear() {
        let gutters = Self.gutters(in: content)
        guard let binding = gutters.lazy.compactMap({ $0.binding }).first else { return }
        let keys = gutters.reduce(into: Set<String>()) { $0.formUnion($1.keyedWrites()) }
        binding.apply("Clear", binding.clearOps(keys))
    }

    /// The rows' gutters, in the order `refreshOptionControls(in:)` walks.
    private static func gutters(in view: NSView) -> [InspectorMarkGutter] {
        view.subviews.flatMap { subview -> [InspectorMarkGutter] in
            if let gutter = subview as? InspectorMarkGutter { return [gutter] }
            return gutters(in: subview)
        }
    }

    /// `marks` from the gutters as they stand, then the two things drawn from
    /// it: the ⊘ note and the header. A section is EDITING the selected
    /// action when any of its rows animates; one that none does (Document,
    /// Shape, a ⊘-only section) keeps its Reset, since its edits go to the
    /// clip.
    private func foldMarks() {
        let gutters = Self.gutters(in: content)
        let writing = gutters.filter { !$0.writes.isEmpty }
        let binding = gutters.lazy.compactMap { $0.binding }.first
        marks = SectionMarks(
            keyed: gutters.reduce(into: Set<String>()) { $0.formUnion($1.keyedWrites()) }.count,
            other: gutters.contains {
                if case .other = $0.mark { return true } else { return false }
            },
            allNotAnimatable: !writing.isEmpty
                && writing.allSatisfy { $0.mark == .notAnimatable },
            differs: differs?() ?? gutters.contains { $0.default?.differs() == true },
            editing: gutters.contains { $0.animates } ? binding?.selectedActionNumber : nil)
        inertNote?.refresh()
        header.refresh(summary: summary?(), marks: marks)
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
