import AppKit

/// One sub-tab of the Clip tab (spec §11 CI-5). The case order is the display
/// order: Text and Shape come first for those kinds, Clip is always last.
enum ClipSubTab: String, CaseIterable {
    case text, shape, graphic, picture, color, sound, clip

    var title: String {
        switch self {
        case .text: return "Text"
        case .shape: return "Shape"
        case .graphic: return "Graphic"
        case .picture: return "Picture"
        case .color: return "Color"
        case .sound: return "Sound"
        case .clip: return "Clip"
        }
    }

    /// The `◆N` badge (spec §11 CI-6): how many KEYS of an action's end patch
    /// this tab's sections write. Motion lives on Clip, so Picture counts the
    /// video keys without it; a shape's props are not animatable; Graphic
    /// counts the end's `graphic.props`, a key its module no longer declares
    /// included (CI-6 amended, G-34 (l)). Color counts `color`, one key
    /// however many of its thirteen the end names, and Picture no longer does
    /// (CI-6 amended by GR-2); for an all-adjustment selection (`adjustment`)
    /// it also counts `opacity`, the Adjustment section's Strength (GR-6). An
    /// end's `look` is Color's too, one key (GR-7), and so is its `wheels`,
    /// one key however many of its nine it names (GR-11); Picture counts
    /// neither.
    func keyedCount(in end: ActionPatch, adjustment: Bool = false) -> Int {
        switch self {
        case .text: return end.text?.dictionary.count ?? 0
        case .shape: return 0
        case .graphic: return end.graphic?.props.count ?? 0
        case .picture:
            let other: Set<String> = ["motion", "color", "look", "wheels"]
            return end.video?.dictionary.keys.filter { !other.contains($0) }.count ?? 0
        case .color:
            return (end.video?.color?.isEmpty == false ? 1 : 0)
                + (end.video?.dictionary["look"] != nil ? 1 : 0)
                + (end.video?.wheels?.isEmpty == false ? 1 : 0)
                + (adjustment && end.video?.dictionary["opacity"] != nil ? 1 : 0)
        case .sound: return end.audio?.dictionary.count ?? 0
        case .clip: return end.video?.dictionary["motion"] == nil ? 0 : 1
        }
    }
}

/// The strip of sub-tabs under the action lane: equal square cells whose 1 pt
/// borders collapse into one, the active cell in the selection fill with an
/// accent border, and a mint `◆N` after a label whose tab the selected action
/// keys. Built with its tabs and its active one, like `PanelTabsView`: a pick
/// goes out through `onSelect` and the pane is rebuilt with a new strip.
/// No hover — a mode switch is instant.
final class ClipSubTabsView: NSView, OptionControl {
    static let cell: CGFloat = 24, top: CGFloat = 8, bottom: CGFloat = 8
    private static let side = InspectorMetrics.inset

    let tabs: [ClipSubTab]
    let active: ClipSubTab
    private let badge: (ClipSubTab) -> Int
    private let onSelect: (ClipSubTab) -> Void
    private var badges: [Int] = []

    init(
        tabs: [ClipSubTab], active: ClipSubTab, badge: @escaping (ClipSubTab) -> Int,
        onSelect: @escaping (ClipSubTab) -> Void
    ) {
        self.tabs = tabs
        self.active = active
        self.badge = badge
        self.onSelect = onSelect
        super.init(frame: .zero)
        wantsLayer = true
        badges = tabs.map(badge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClipSubTabsView does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.top + Self.cell + Self.bottom)
    }

    /// Equal cells, each sharing its left border with the previous one's
    /// right (a −1 overlap), with `PanelTabsView.tabRect`'s rounding so the
    /// row tiles exactly.
    func cellRect(_ index: Int) -> CGRect {
        let step = (bounds.width - 2 * Self.side - 1) / CGFloat(max(tabs.count, 1))
        let left = Self.side + (CGFloat(index) * step).rounded()
        let right = Self.side + (CGFloat(index + 1) * step).rounded() + 1
        return CGRect(x: left, y: Self.top, width: right - left, height: Self.cell)
    }

    /// Re-reads the badges; redraws only when they changed.
    func refresh() {
        let next = tabs.map(badge)
        guard next != badges else { return }
        badges = next
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = tabs.indices.first(where: { cellRect($0).contains(point) }),
              tabs[index] != active
        else { return }
        onSelect(tabs[index])
    }

    override func draw(_ dirtyRect: NSRect) {
        DS.border.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        // The active cell last, so its accent border wins the shared edges.
        let order = tabs.indices.filter { tabs[$0] != active }
            + tabs.indices.filter { tabs[$0] == active }
        for index in order {
            drawCell(index)
        }
    }

    private func drawCell(_ index: Int) {
        let rect = cellRect(index)
        let isActive = tabs[index] == active
        (isActive ? DS.selectionFill : NSColor.controlBackgroundColor).setFill()
        rect.fill()
        (isActive ? DS.accent : DS.border).setStroke()
        NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()

        let label = NSAttributedString(
            string: tabs[index].title,
            attributes: [
                .font: DS.sans(11, weight: .semibold),
                .foregroundColor: isActive ? DS.textStrong : DS.textMuted,
            ])
        let count = badges.indices.contains(index) ? badges[index] : 0
        let mark = count > 0
            ? NSAttributedString(
                string: "◆\(count)",
                attributes: [.font: DS.mono(9, weight: .medium), .foregroundColor: DS.action])
            : nil
        let labelSize = label.size()
        let markSize = mark?.size() ?? .zero
        let gap: CGFloat = mark == nil ? 0 : 4
        let width = ceil(labelSize.width) + gap + ceil(markSize.width)
        let x = (rect.midX - width / 2).rounded()
        label.draw(at: NSPoint(x: x, y: rect.midY - labelSize.height / 2))
        mark?.draw(
            at: NSPoint(
                x: x + ceil(labelSize.width) + gap, y: rect.midY - markSize.height / 2))
    }
}

/// The Clip tab's pinned block (the clip inspector handoff's "Pinned action
/// lane block", road map 9 §1 and §3): the selection header, the action lane
/// and the sub-tab strip, stacked, and under them the matte note when the
/// pane gives one (spec §11 MT-7, `ClipPane+Matte.swift`). One
/// `OptionControl`, because the pane has one header slot
/// (`InspectorPaneView.makeHeader()`), refreshed with it and hosted ABOVE the
/// scroll view by the controller (`pinnedBlock`).
final class ClipHeaderBlock: NSView, OptionControl {
    private let header: ClipSelectionHeaderView
    private let lane: ActionLaneView
    private let strip: ClipSubTabsView?
    private let noteLabel: InspectorNoteLabel?

    /// `note` is given only while it has words: the pane's structure
    /// signature carries whether it shows, so its coming or going rebuilds
    /// the block, and a refresh only re-reads its words.
    init(
        binding: InspectorBinding, inspector: InspectorViewController?,
        subTabs: ClipSubTabsView?, note: (() -> String?)? = nil
    ) {
        header = ClipSelectionHeaderView(binding: binding)
        lane = ActionLaneView(binding: binding, inspector: inspector)
        strip = subTabs
        noteLabel = note.map { InspectorNoteLabel(note: $0) }
        super.init(frame: .zero)
        var views: [NSView] = [header, lane]
        if let subTabs { views.append(subTabs) }
        var above = topAnchor
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: above),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            above = view.bottomAnchor
        }
        if let label = noteLabel {
            // A sentence of two lines at the panel's width: it wraps.
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: above, constant: 6),
                label.leadingAnchor.constraint(
                    equalTo: leadingAnchor, constant: InspectorMetrics.inset),
                label.trailingAnchor.constraint(
                    equalTo: trailingAnchor, constant: -InspectorMetrics.inset),
            ])
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8).isActive = true
        } else {
            above.constraint(equalTo: bottomAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClipHeaderBlock does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    /// The lane, for a probe.
    var actionLane: ActionLaneView { lane }

    /// The sub-tab strip, for a probe.
    var subTabsView: ClipSubTabsView? { strip }

    /// The matte note's words as shown, for a probe; nil when it has none.
    var noteText: String? { noteLabel.flatMap { $0.isHidden ? nil : $0.stringValue } }

    /// A wrapping label needs its width to know its height.
    override func layout() {
        super.layout()
        guard let label = noteLabel else { return }
        let width = max(bounds.width - 2 * InspectorMetrics.inset, 0)
        guard label.preferredMaxLayoutWidth != width else { return }
        label.preferredMaxLayoutWidth = width
        super.layout()
    }

    func refresh() {
        header.refresh()
        lane.refresh()
        strip?.refresh()
        noteLabel?.refresh()
    }
}
