import AppKit

/// Settings' ⓘ (spec §11 SH-5): an image-only button beside a section's
/// heading whose `NSPopover` shows its explanation, 13 pt in `DS.textStrong`.
/// **`infoState` is the policy; the popover follows it.** Resting for
/// `hoverDelay` opens it (`.hover`) and leaving closes a hover-opened one; a
/// press opens and holds it (`.held`), promotes a hover-opened one without
/// closing it, and closes a held one. `.transient` ends it on a click
/// elsewhere, Escape or the window closing (`popoverDidClose`), but never on a
/// press ON the icon (`popoverShouldClose`), so the action alone decides. No
/// `toolTip` (it would double the popover); VoiceOver reads "About <section>"
/// with the text as its help, and Space presses it under Keyboard navigation.
final class SettingsInfoButton: NSButton {
    static let hoverDelay: TimeInterval = 0.35
    static let textWidth: CGFloat = 320  // the label's preferredMaxLayoutWidth
    static let textInset: CGFloat = 12  // the popover content's padding, all sides

    enum InfoState { case closed, hover, held }

    let section: String
    let infoText: String
    let infoLabel: NSTextField
    let popover = NSPopover()

    private(set) var hoverPending = false  // a hover show is scheduled
    private(set) var infoState: InfoState = .closed
    var isShowingInfo: Bool { popover.isShown }
    private var hoverWork: DispatchWorkItem?

    init(section: String, infoText: String) {
        self.section = section
        self.infoText = infoText
        infoLabel = NSTextField(wrappingLabelWithString: infoText)
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        isBordered = false
        imagePosition = .imageOnly
        title = ""
        image = NSImage(
            systemSymbolName: "info.circle", accessibilityDescription: "About \(section)")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        contentTintColor = DS.textMuted
        toolTip = nil
        setAccessibilityLabel("About \(section)")
        setAccessibilityHelp(infoText)
        target = self
        action = #selector(toggleInfo(_:))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 16).isActive = true
        heightAnchor.constraint(equalToConstant: 16).isActive = true
        buildPopover()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsInfoButton does not support NSCoder")
    }

    private func buildPopover() {
        infoLabel.font = DS.sans(13)
        infoLabel.textColor = DS.textStrong
        infoLabel.isSelectable = false
        infoLabel.preferredMaxLayoutWidth = Self.textWidth
        infoLabel.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(infoLabel)
        let inset = Self.textInset, label = infoLabel
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: Self.textWidth),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
        ])
        let controller = NSViewController()
        controller.view = container
        container.layoutSubtreeIfNeeded()
        popover.contentViewController = controller
        popover.contentSize = container.fittingSize
        popover.behavior = .transient
        popover.delegate = self
    }

    func showInfo(byHover: Bool) {
        infoState = byHover ? .hover : .held
        guard window?.isVisible == true else { return }
        popover.animates = !DS.reduceMotion
        if !popover.isShown {
            popover.show(relativeTo: bounds, of: self, preferredEdge: isFlipped ? .maxY : .minY)
        }
    }

    func hideInfo() {
        infoState = .closed
        if popover.isShown { popover.close() }
    }

    /// The action: opens and holds, promotes a hover-opened one, closes a held one.
    @objc func toggleInfo(_ sender: Any?) {
        cancelHover()
        switch infoState {
        case .closed: showInfo(byHover: false)
        case .hover: infoState = .held
        case .held: hideInfo()
        }
    }

    /// True when a mouse-down at `locationInWindow` in `eventWindow` lands on it.
    func isOnIcon(locationInWindow: NSPoint, in eventWindow: NSWindow?) -> Bool {
        guard let window, eventWindow === window else { return false }
        return bounds.contains(convert(locationInWindow, from: nil))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        contentTintColor = DS.textStrong
        guard infoState == .closed else { return }
        cancelHover()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hoverPending else { return }
            self.hoverPending = false
            self.hoverWork = nil
            self.showInfo(byHover: true)
        }
        hoverWork = work
        hoverPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverDelay, execute: work)
    }

    override func mouseExited(with event: NSEvent) {
        contentTintColor = DS.textMuted
        cancelHover()
        if infoState == .hover { hideInfo() }
    }

    private func cancelHover() {
        hoverWork?.cancel()
        hoverWork = nil
        hoverPending = false
    }
}

extension SettingsInfoButton: NSPopoverDelegate {
    /// A press on the icon never closes it through `.transient` (the action
    /// would reopen it); any other outside click does.
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown else { return true }
        return !isOnIcon(locationInWindow: event.locationInWindow, in: event.window)
    }

    func popoverDidClose(_ notification: Notification) {
        infoState = .closed
    }
}

/// A Settings section's heading row: the title and its ⓘ, hugging (#143).
func settingsSectionHeader(_ title: NSTextField, info: SettingsInfoButton) -> NSStackView {
    let stack = NSStackView(views: [title, info])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 6
    stack.setHuggingPriority(.required, for: .horizontal)
    return stack
}
