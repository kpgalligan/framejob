import AppKit

/// The inspector panel (spec §4.3): the tab strip and the scroll view that
/// hosts one pane at a time.
///
/// **Frozen at wiring**, like `EditorViewController` and `TimelineView`: the
/// controls live in the pane files and the shared pieces in
/// `InspectorPane.swift`. What this file owns is the policy —
///
///  - a PICKED clip shows the Clip tab, because that is what the user just
///    asked about — `clipPicked()` for a click (which switches even when the
///    click re-picks the clip that was already selected) and, on top of it, a
///    selection that changed under an unrelated path (paste, ⌘A, the agent);
///  - a pane is REBUILT only when the model's shape changes
///    (`structureSignature`) and merely refreshed otherwise, so a live canvas
///    drag updates every field without tearing down the control the user is
///    holding.
///
/// The policy used to be three times this size — a tab was disabled when no
/// selected clip had that aspect, a new selection picked the most relevant
/// enabled tab, and a pin existed to defeat that pick. Three tabs, all always
/// live, retire all of it: which SECTIONS the Clip tab shows is now
/// `ClipPane.makeSections()`'s answer, and there is nothing left for a pin to
/// protect.
///
/// Edits leave through the `on*` closures, wired in
/// `EditorViewController+Inspector.swift`; nothing here touches
/// `ProjectDocument` directly except to READ it.
final class InspectorViewController: NSViewController {
    // MARK: - Model

    /// Read-only from here: every write goes out through the closures below,
    /// so `ProjectDocument` stays the single mutation point.
    weak var document: ProjectDocument?

    lazy var binding = InspectorBinding(inspector: self)

    // MARK: - Intent out

    var onEdit: ((String, [ReelOp]) -> Void)?
    /// For commits made outside an AppKit event (a sheet or alert's
    /// completion) — `ProjectDocument.performGroupedEdit`.
    var onGroupedEdit: ((String, [ReelOp]) -> Void)?
    var onLiveBegin: (() -> Void)?
    var onLiveUpdate: (([ReelOp]) -> Void)?
    var onLiveEnd: ((String) -> Void)?
    /// Files dropped on the Media tab, or picked by Add Media….
    var onImportFiles: (([URL]) -> Void)?
    /// A PURE trial application, for learning an id the core is about to mint
    /// (the new track a canvas drop needs). Never an edit.
    var onProbe: (([ReelOp]) -> ProjectSnapshot?)?
    /// Jump the playhead — the markers list and the actions table.
    var onSeek: ((Ticks) -> Void)?
    /// Hand a command back to the editor (Crop on Canvas, Detach Audio).
    var onCommand: ((Selector) -> Void)?
    /// Select an action of the single selected clip, or nil to leave the mode.
    var onSelectAction: ((UInt32?) -> Void)?

    // MARK: - State

    private(set) var tab: InspectorTab = .clip

    private var tabsContainer: NSView!
    private var tabsView: PanelTabsView?
    /// The previous strip, held one generation past its removal — the pitfall
    /// is named in `buildTabs()`.
    private var retiredTabs: PanelTabsView?
    private var scroll: NSScrollView!
    private var panes: [InspectorTab: InspectorPaneView] = [:]
    private var currentPane: InspectorPaneView?
    private var lastSelection: [UInt32] = []
    private var lastSignature: String?

    // MARK: - Life cycle

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorViewController does not support NSCoder")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 640))
        root.wantsLayer = true
        root.layer?.backgroundColor = DS.chromeBackground.cgColor

        // `PanelTabsView` fixes its active tab at init (Controls.swift is
        // carried from Rasterize and is not forked here), so the strip is
        // rebuilt inside this container whenever the tab changes.
        tabsContainer = NSView()
        tabsContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tabsContainer)

        scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        root.addSubview(scroll)

        NSLayoutConstraint.activate([
            tabsContainer.topAnchor.constraint(equalTo: root.topAnchor),
            tabsContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabsContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabsContainer.heightAnchor.constraint(equalToConstant: DS.tabHeight),
            scroll.topAnchor.constraint(equalTo: tabsContainer.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        buildTabs()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh(isLive: false)
    }

    // MARK: - Selection

    /// The selected clips in timeline order — what every pane edits.
    var selectedClips: [ClipSnapshot] {
        guard let document = document else { return [] }
        let ids = document.selection
        return document.editedProject.snapshot.clips.filter { ids.contains($0.id) }
            .sorted { $0.start < $1.start }
    }

    // MARK: - Tabs

    private func buildTabs() {
        // **Pitfall:** this usually runs from inside the OUTGOING strip's own
        // `mouseDown` — a tab click calls `onSelect`, which lands here — and
        // `tabsView` plus the superview are that view's only strong
        // references. Dropping both mid-event would deallocate the view the
        // window is still dispatching the event to. Held one generation, for
        // the same reason and in the same shape as
        // `InspectorPaneView.rebuild()`'s `retired`; the NEXT build releases
        // it, which is never inside its event.
        retiredTabs = tabsView
        tabsView?.removeFromSuperview()
        let strip = PanelTabsView(
            titles: InspectorTab.allCases.map { $0.title }, activeIndex: tab.rawValue,
            onSelect: { [weak self] index in self?.tabPicked(index) })
        strip.translatesAutoresizingMaskIntoConstraints = false
        tabsContainer.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: tabsContainer.topAnchor),
            strip.bottomAnchor.constraint(equalTo: tabsContainer.bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: tabsContainer.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: tabsContainer.trailingAnchor),
        ])
        tabsView = strip
    }

    private func tabPicked(_ index: Int) {
        guard let picked = InspectorTab(rawValue: index) else { return }
        select(picked)
    }

    /// Programmatic tab selection, and the only writer of `tab`. `clipPicked()`
    /// is its one caller besides the strip itself; the "show me the Media tab
    /// after Add Media…" this comment used to promise has never had a call
    /// site, and is not worth inventing one for — the import lands rows in a
    /// tab the user can already see.
    func select(_ next: InspectorTab) {
        guard tab != next else { return }
        tab = next
        buildTabs()
        refresh(isLive: false)
    }

    /// "The user just picked a clip" — called by the timeline's and the
    /// canvas's click handlers AFTER they have written the new selection.
    ///
    /// The handoff's rule is unconditional: "Clicking a clip selects it,
    /// switches the inspector to the Clip tab". `refresh(isLive:)` cannot
    /// implement that on its own, because a re-click of the ALREADY selected
    /// clip looks exactly like every unrelated refresh — an edit, a playhead
    /// move, an agent op — and switching on those would make the Media and
    /// Document tabs unusable, since almost anything the user did there would
    /// throw them back to Clip. So the pick says so out loud, and the refresh
    /// keeps its own narrower rule for a selection that actually CHANGED
    /// (paste, ⌘A, the agent's `set_selection`).
    ///
    /// Empty selections are ignored: clicking bare lane deselects, and a Clip
    /// tab reading "Select a clip to edit its properties" is not what the user
    /// asked to see.
    func clipPicked() {
        guard isViewLoaded, !selectedClips.isEmpty else { return }
        select(.clip)
    }

    private func pane(for tab: InspectorTab) -> InspectorPaneView {
        if let existing = panes[tab] { return existing }
        let made: InspectorPaneView
        switch tab {
        case .clip: made = ClipPane(inspector: self)
        case .media: made = MediaPane(inspector: self)
        case .document: made = DocumentPane(inspector: self)
        }
        panes[tab] = made
        return made
    }

    /// Swaps the scroll view's document view, answering whether it actually
    /// swapped. A pane keeps its instance — and so its controls and its
    /// disclosure state — for the panel's life; the scroll POSITION belongs to
    /// the one scroll view, and `refresh(isLive:)` sends it back to the top
    /// whenever the pane under it changes.
    private func showPane(_ next: InspectorPaneView) -> Bool {
        guard currentPane !== next else { return false }
        currentPane = next
        next.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = next
        NSLayoutConstraint.activate([
            next.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            next.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            next.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            // Fills the visible area even when the sections are short, so the
            // panel has one background and the Media tab's drop target is the
            // whole pane rather than just its rows.
            next.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
        ])
        // A pane that was never shown has no rows yet; forcing the signature
        // to differ makes the refresh below build it.
        lastSignature = nil
        return true
    }

    /// Back to the top of the panel.
    ///
    /// Deliberately NOT called after every rebuild: a rebuild also happens
    /// when a filter is added, an action appears or a transition comes and
    /// goes, and yanking the panel to the top under a user who is dialling a
    /// filter halfway down it would trade one bug for another. The two moments
    /// the design names — a different clip, a different tab — are the two that
    /// ask for it.
    ///
    /// The pane is flipped (`InspectorPaneView.isFlipped`), so the top is
    /// y = 0 whatever the content height is, and this needs no layout pass to
    /// have run first.
    private func scrollToTop() {
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    // MARK: - Refresh

    /// The ONE path from a changed document to the panel, called by
    /// `EditorViewController.refreshFromDocument`. `isLive` suppresses
    /// rebuilds: mid-gesture the values change but the shape does not.
    func refresh(isLive: Bool) {
        guard isViewLoaded else { return }
        binding.invalidate()
        let clips = selectedClips

        // Picking a clip in the timeline or on the canvas asks about THAT
        // clip, so the panel answers about it — one selection model, and the
        // panel is one of its three views (the timeline bar's block and the
        // canvas handles are the others).
        // Switched in place rather than through `select(_:)`: that one starts
        // a refresh of its own, and this one is already running — with
        // `isLive` in hand, which a nested call would drop.
        let ids = clips.map { $0.id }
        // A different clip and a different tab are the two things that make
        // the panel a different list, so they are the two that send it back to
        // the top; everything else leaves the user where they were reading.
        var toTop = false
        if ids != lastSelection {
            lastSelection = ids
            toTop = true
            if !clips.isEmpty, tab != .clip {
                tab = .clip
                buildTabs()
            }
        }

        let pane = pane(for: tab)
        if showPane(pane) { toTop = true }
        let signature = pane.structureSignature
        // A rebuild replaces every control, so it must never happen under a
        // live gesture — the slider being dragged would vanish mid-drag.
        if signature != lastSignature, !isLive, document?.isLiveEditing != true {
            lastSignature = signature
            pane.rebuild()
        }
        pane.refresh()
        if toTop { scrollToTop() }
    }
}
