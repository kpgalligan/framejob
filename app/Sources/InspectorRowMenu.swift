import AppKit

/// One inspector row (spec §11 CI-9): the horizontal stack `inspectorRow`
/// always built — the mark gutter FIRST, with no spacing after it (CI-7) —
/// which now tracks the pointer over itself and answers a context menu.
///
/// The pointer is over the ROW, so the row tells its gutter (`hovered`); the
/// gutter decides whether that makes its ◆ a ×. The menu never reads the
/// hover: a window that is not key tracks none, and a right-click there must
/// offer the same items.
///
/// A field's or a popup's own right-click keeps its own menu, because neither
/// forwards it; the gutter, the label, a slider, a checkbox, the tags and the
/// trailing spacer reach this one.
final class InspectorRowView: NSStackView {
    let gutter: InspectorMarkGutter

    init(views: [NSView], gutter: InspectorMarkGutter) {
        self.gutter = gutter
        super.init(frame: .zero)
        for view in views { addArrangedSubview(view) }
        orientation = .horizontal
        alignment = .centerY
        spacing = 6
        setCustomSpacing(0, after: gutter)
        // As tall as the row and no taller: a fixed height would grow a row
        // of bare text (the "No filters" lines) and move everything under it.
        gutter.heightAnchor.constraint(equalTo: heightAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorRowView does not support NSCoder")
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Only this view's own areas: a tooltip is a tracking area too.
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    func setHovered(_ hovered: Bool) {
        gutter.hovered = hovered
    }

    // MARK: The menu

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu()
    }

    /// The row's items, in order: "Remove from action N" on a keyed row, "Go
    /// to action M" on a ◇ row, then — for a row with a default — "Set end
    /// value to default" with an action selected on a row that animates, else
    /// "Reset to default", disabled while the row already holds it. Nil when
    /// there would be no item.
    func contextMenu() -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let binding = gutter.binding
        if gutter.isKeyed, let number = binding?.selectedActionNumber {
            add("Remove from action \(number)", #selector(removeFromAction(_:)), to: menu)
        }
        if case .other(let number) = gutter.mark {
            add("Go to action \(number)", #selector(goToAction(_:)), to: menu)
        }
        if let rowDefault = gutter.default {
            let atEnd = binding?.selectedAction != nil && gutter.animates
            let item = add(
                atEnd ? "Set end value to default" : "Reset to default",
                #selector(resetToDefault(_:)), to: menu)
            item.isEnabled = rowDefault.differs()
        }
        return menu.items.isEmpty ? nil : menu
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc func removeFromAction(_ sender: Any?) {
        gutter.removeFromAction()
    }

    /// Selects the action the ◇ names, through the lane's own intent.
    @objc func goToAction(_ sender: Any?) {
        guard case .other(let number) = gutter.mark, let binding = gutter.binding,
              let id = binding.actionID(number: number)
        else { return }
        binding.selectAction(id)
    }

    @objc func resetToDefault(_ sender: Any?) {
        guard let rowDefault = gutter.default, let binding = gutter.binding else { return }
        binding.apply(rowDefault.name, rowDefault.ops())
    }
}
