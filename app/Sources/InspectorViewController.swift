import AppKit

/// The inspector panel (spec §4.3): the tab strip, the pin, and the scroll
/// view that hosts one pane at a time.
///
/// **Frozen at wiring**, like `EditorViewController` and `TimelineView`: the
/// controls live in the six pane files and the shared pieces in
/// `InspectorPane.swift`. What this file owns is the policy —
///
///  - a tab is disabled when no selected clip has that aspect;
///  - a NEW selection switches to the most relevant enabled tab unless the
///    user pinned one;
///  - a pane is REBUILT only when the model's shape changes
///    (`structureSignature`) and merely refreshed otherwise, so a live canvas
///    drag updates every field without tearing down the control the user is
///    holding.
///
/// Edits leave through the `on*` closures, wired in
/// `EditorViewController+Inspector.swift`; nothing here touches
/// `ProjectDocument` directly except to READ it.
final class InspectorViewController: NSViewController {
    /// The pinned tab's raw value, or −1 for "follow the selection".
    static let pinnedTabKey = "ReelcutInspectorPinnedTab"

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

    // MARK: - State

    private(set) var tab: InspectorTab = .video
    private(set) var pinnedTab: InspectorTab?

    private var tabsView: InspectorTabsView!
    private var scroll: NSScrollView!
    private var panes: [InspectorTab: InspectorPaneView] = [:]
    private var currentPane: InspectorPaneView?
    private var lastSelection: [UInt32] = []
    private var lastSignature: String?

    // MARK: - Life cycle

    init() {
        super.init(nibName: nil, bundle: nil)
        let stored = UserDefaults.standard.object(forKey: Self.pinnedTabKey) as? Int
        if let stored = stored, let pinned = InspectorTab(rawValue: stored) {
            pinnedTab = pinned
            tab = pinned
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorViewController does not support NSCoder")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 640))
        root.wantsLayer = true
        root.layer?.backgroundColor = DS.chromeBackground.cgColor

        tabsView = InspectorTabsView()
        tabsView.translatesAutoresizingMaskIntoConstraints = false
        tabsView.onSelect = { [weak self] index in self?.tabPicked(index) }
        tabsView.onTogglePin = { [weak self] in self?.togglePin() }
        root.addSubview(tabsView)

        scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        root.addSubview(scroll)

        NSLayoutConstraint.activate([
            tabsView.topAnchor.constraint(equalTo: root.topAnchor),
            tabsView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabsView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabsView.heightAnchor.constraint(equalToConstant: DS.tabHeight),
            scroll.topAnchor.constraint(equalTo: tabsView.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
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
        return document.project.snapshot.clips.filter { ids.contains($0.id) }
            .sorted { $0.start < $1.start }
    }

    // MARK: - Tabs

    private func tabPicked(_ index: Int) {
        guard let picked = InspectorTab(rawValue: index) else { return }
        tab = picked
        // A pin follows an explicit pick: the user asked for THIS tab, so
        // pinning keeps meaning "stay here".
        if pinnedTab != nil { setPinned(picked) }
        refresh(isLive: false)
    }

    /// The strip's pin affordance (§4.3: "unless the user pinned one").
    func togglePin() {
        setPinned(pinnedTab == nil ? tab : nil)
        refresh(isLive: false)
    }

    private func setPinned(_ pinned: InspectorTab?) {
        pinnedTab = pinned
        UserDefaults.standard.set(pinned?.rawValue ?? -1, forKey: Self.pinnedTabKey)
    }

    /// Programmatic tab selection — the editor's "show me the Media tab"
    /// after Add Media….
    func select(_ next: InspectorTab) {
        tab = next
        refresh(isLive: false)
    }

    private func pane(for tab: InspectorTab) -> InspectorPaneView {
        if let existing = panes[tab] { return existing }
        let made: InspectorPaneView
        switch tab {
        case .video: made = VideoPane(inspector: self)
        case .audio: made = AudioPane(inspector: self)
        case .text: made = TextPane(inspector: self)
        case .shape: made = ShapePane(inspector: self)
        case .media: made = MediaPane(inspector: self)
        case .document: made = DocumentPane(inspector: self)
        }
        panes[tab] = made
        return made
    }

    /// Swaps the scroll view's document view. A pane keeps its instance (and
    /// so its scroll position and disclosure state) for the panel's life.
    private func showPane(_ next: InspectorPaneView) {
        guard currentPane !== next else { return }
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
    }

    // MARK: - Refresh

    /// The ONE path from a changed document to the panel, called by
    /// `EditorViewController.refreshFromDocument`. `isLive` suppresses
    /// rebuilds: mid-gesture the values change but the shape does not.
    func refresh(isLive: Bool) {
        guard isViewLoaded else { return }
        binding.invalidate()
        let clips = selectedClips
        let snapshot = document?.project.snapshot ?? .empty

        let ids = clips.map { $0.id }
        if ids != lastSelection {
            lastSelection = ids
            if pinnedTab == nil, !clips.isEmpty {
                tab = InspectorTab.preferred(for: clips, in: snapshot)
            }
        }
        if !tab.isEnabled(for: clips, in: snapshot) {
            tab = InspectorTab.allCases.first { $0.isEnabled(for: clips, in: snapshot) } ?? .media
        }

        tabsView.enabledTabs = InspectorTab.allCases.map { $0.isEnabled(for: clips, in: snapshot) }
        tabsView.activeIndex = tab.rawValue
        tabsView.pinned = pinnedTab != nil
        tabsView.needsDisplay = true

        let pane = pane(for: tab)
        showPane(pane)
        let signature = pane.structureSignature
        // A rebuild replaces every control, so it must never happen under a
        // live gesture — the slider being dragged would vanish mid-drag.
        if signature != lastSignature, !isLive, document?.isLiveEditing != true {
            lastSignature = signature
            pane.rebuild()
        }
        pane.refresh()
    }
}

// MARK: - Tab strip

/// The inspector's tab row: six tabs plus the pin cell. Modelled on
/// `PanelTabsView` (Controls.swift) rather than reusing it, because that one
/// is copied verbatim from Rasterize and knows nothing about disabled tabs or
/// a pin — forking it would break the "keep them in sync" rule.
final class InspectorTabsView: NSView {
    var activeIndex = 0
    var enabledTabs: [Bool] = InspectorTab.allCases.map { _ in true }
    var pinned = false
    var onSelect: ((Int) -> Void)?
    var onTogglePin: (() -> Void)?

    private let tabs = InspectorTab.allCases
    private var hovered: Int?
    private static let pinWidth: CGFloat = 26

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorTabsView does not support NSCoder")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: DS.tabHeight)
    }

    private var stripWidth: CGFloat { max(bounds.width - Self.pinWidth, 1) }

    /// Equal widths with the rounding remainder folded into the boundaries,
    /// so N tabs always tile the row exactly (PanelTabsView's rule).
    private func tabRect(_ index: Int) -> NSRect {
        let width = stripWidth / CGFloat(max(tabs.count, 1))
        let left = (CGFloat(index) * width).rounded()
        let right = (CGFloat(index + 1) * width).rounded()
        return NSRect(x: left, y: 0, width: right - left, height: bounds.height)
    }

    private var pinRect: NSRect {
        NSRect(x: stripWidth, y: 0, width: Self.pinWidth, height: bounds.height)
    }

    private func index(at point: NSPoint) -> Int? {
        tabs.indices.first { tabRect($0).contains(point) }
    }

    private func isEnabled(_ index: Int) -> Bool {
        enabledTabs.indices.contains(index) ? enabledTabs[index] : true
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
                owner: self, userInfo: nil))
        removeAllToolTips()
        addToolTip(pinRect, owner: self, userData: nil)
    }

    private func updateHover(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var next: Int?
        if let index = index(at: point), index != activeIndex, isEnabled(index) { next = index }
        guard next != hovered else { return }
        hovered = next
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { updateHover(with: event) }
    override func mouseMoved(with event: NSEvent) { updateHover(with: event) }

    override func mouseExited(with event: NSEvent) {
        guard hovered != nil else { return }
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if pinRect.contains(point) {
            onTogglePin?()
            return
        }
        guard let index = index(at: point) else { return }
        guard isEnabled(index) else {
            NSSound.beep()
            return
        }
        guard index != activeIndex else { return }
        onSelect?(index)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for (index, tab) in tabs.enumerated() {
            let rect = tabRect(index)
            if index == activeIndex || index == hovered {
                DS.hoverFill.setFill()
                rect.fill()
            }
            let active = index == activeIndex
            let live = isEnabled(index)
            var color = active ? DS.textStrong : DS.textMuted
            if !live { color = color.withAlphaComponent(0.42) }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: active ? DS.sans(11, weight: .semibold) : DS.sans(11),
                .foregroundColor: color,
            ]
            var title = tab.title
            if title.size(withAttributes: attributes).width > rect.width - 6 {
                title = tab.shortTitle
            }
            // Still too wide on a narrow panel: shrink rather than clip, so a
            // disabled tab is still readable enough to explain itself.
            if title.size(withAttributes: attributes).width > rect.width - 4 {
                attributes[.font] = DS.sans(10, weight: active ? .semibold : .regular)
            }
            let size = title.size(withAttributes: attributes)
            title.draw(
                at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                withAttributes: attributes)
        }

        DS.border.setFill()
        for index in 1..<max(tabs.count, 1) {
            NSRect(x: tabRect(index).minX, y: 0, width: 1, height: bounds.height).fill()
        }
        NSRect(x: pinRect.minX, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        if tabs.indices.contains(activeIndex) {
            let active = tabRect(activeIndex)
            DS.accent.setFill()
            NSRect(x: active.minX, y: bounds.height - 2, width: active.width, height: 2).fill()
        }

        drawPin()
    }

    private func drawPin() {
        let rect = pinRect
        let tint = pinned ? DS.accent : DS.textFaint
        if let icon = NSImage(
            systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "Pin tab")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        {
            let tinted = icon.tinted(with: tint)
            let size = tinted.size
            tinted.draw(
                in: NSRect(
                    x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                    width: size.width, height: size.height))
            return
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: DS.sans(11), .foregroundColor: tint,
        ]
        let size = "📌".size(withAttributes: attributes)
        "📌".draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes)
    }
}

extension InspectorTabsView: NSViewToolTipOwner {
    func view(
        _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        pinned ? "Unpin — follow the selection" : "Pin this tab"
    }
}
