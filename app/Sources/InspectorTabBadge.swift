import AppKit

/// The Assistant tab's question dot (spec §11 AI-19): a small accent-coloured
/// dot just right of "Assistant" in the inspector's tab strip, shown while
/// the window's assistant waits on an ask-first question, whichever tab is
/// showing.
///
/// Its own view laid over the strip rather than a fork of `PanelTabsView`
/// (`Controls.swift` is carried from Rasterize and kept in sync), so it
/// mirrors `PanelTabsView.tabRect`'s arithmetic and the way the strip centres
/// a title, as `ClipSubTabsView.cellRect` does. It is the inspector root's
/// LAST subview, above the container `buildTabs()` refills on every tab
/// change. Passive: it takes no click (`hitTest` answers nil, so a click
/// reaches the strip) and no key.
final class InspectorTabBadge: NSView {
    static let identifier = "inspector.assistant.badge"
    static let diameter: CGFloat = 6
    static let gap: CGFloat = 3

    init() {
        super.init(frame: .zero)
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityIdentifier(Self.identifier)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorTabBadge does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        DS.accent.setFill()
        NSBezierPath(
            ovalIn: Self.dotRect(stripWidth: bounds.width, stripHeight: bounds.height)
        ).fill()
    }

    /// Added to `root` with its four edges on `strip`'s.
    func install(over strip: NSView, in root: NSView) {
        root.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: strip.topAnchor),
            bottomAnchor.constraint(equalTo: strip.bottomAnchor),
            leadingAnchor.constraint(equalTo: strip.leadingAnchor),
            trailingAnchor.constraint(equalTo: strip.trailingAnchor),
        ])
    }

    /// `PanelTabsView.tabRect`'s arithmetic (equal widths, `.rounded()`
    /// edges) for the Assistant tab of `InspectorTab.allCases.count`.
    static func tabRect(stripWidth: CGFloat, stripHeight: CGFloat) -> NSRect {
        let index = InspectorTab.assistant.rawValue
        let width = stripWidth / CGFloat(max(InspectorTab.allCases.count, 1))
        let left = (CGFloat(index) * width).rounded()
        let right = (CGFloat(index + 1) * width).rounded()
        return NSRect(x: left, y: 0, width: right - left, height: stripHeight)
    }

    /// The Assistant title in the active tab's font, centred in `tabRect`
    /// exactly as `PanelTabsView` draws a title. The semibold face is the
    /// wider of the strip's two, so the dot clears the word either way.
    static func titleRect(stripWidth: CGFloat, stripHeight: CGFloat) -> NSRect {
        let tab = tabRect(stripWidth: stripWidth, stripHeight: stripHeight)
        let size = InspectorTab.assistant.title.size(
            withAttributes: [.font: DS.sans(12, weight: .semibold)])
        return NSRect(
            x: tab.midX - size.width / 2, y: tab.midY - size.height / 2,
            width: size.width, height: size.height)
    }

    /// Just right of the title, never past the tab's trailing edge less 2 pt.
    static func dotRect(stripWidth: CGFloat, stripHeight: CGFloat) -> NSRect {
        let tab = tabRect(stripWidth: stripWidth, stripHeight: stripHeight)
        let title = titleRect(stripWidth: stripWidth, stripHeight: stripHeight)
        let x = min(title.maxX + gap, tab.maxX - 2 - diameter).rounded()
        let y = (tab.midY - diameter / 2).rounded()
        return NSRect(x: x, y: y, width: diameter, height: diameter)
    }
}

extension InspectorViewController {
    /// The editor's forward from `assistantRefresh()`: the dot while a
    /// question waits.
    func showAssistantBadge(_ shown: Bool) {
        assistantBadge.isHidden = !shown
    }
}
