import AppKit

/// The Reelcut mark: three overlapping multiply-blended shapes reading as a
/// strip of frames with a play triangle over them. The app's only decorative
/// use of the brand inks (`Theme.swift`).
private final class FrameMotifView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 148, height: 96) }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setBlendMode(.multiply)
        let frameSize = NSSize(width: 52, height: 52)
        let top = bounds.height - 22
        for (index, color) in [DS.forest, DS.butter].enumerated() {
            color.setFill()
            let rect = NSRect(
                x: bounds.midX - 46 + CGFloat(index) * 40,
                y: top - frameSize.height,
                width: frameSize.width, height: frameSize.height)
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        }
        DS.coral.setFill()
        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: bounds.midX - 14, y: top - 62))
        triangle.line(to: NSPoint(x: bounds.midX + 26, y: top - 40))
        triangle.line(to: NSPoint(x: bounds.midX - 14, y: top - 18))
        triangle.close()
        triangle.fill()
    }
}

/// The no-document window: shown when the app is frontmost with nothing open,
/// replacing the bare open panel (spec §3). Offers Open Video…, New Project
/// and Recent, accepts dropped files through `FileDropView`, and closes as
/// soon as a document window becomes main.
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()

    /// Rebuilt on every `show()` — the recent list changes while the window
    /// is closed, so it cannot be built once in init.
    private let recentStack = NSStackView()
    private let recentLabel = NSTextField(labelWithString: "")

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Reelcut"
        window.center()
        super.init(window: window)

        let root = FileDropView(frame: NSRect(x: 0, y: 0, width: 720, height: 520))
        root.wantsLayer = true

        let motif = FrameMotifView(frame: .zero)
        motif.translatesAutoresizingMaskIntoConstraints = false

        let headline = NSTextField(labelWithString: "Open a file. Start cutting.")
        headline.translatesAutoresizingMaskIntoConstraints = false
        headline.font = DS.display(42)
        headline.textColor = DS.textStrong
        headline.alignment = .center

        let paragraph = NSTextField(
            wrappingLabelWithString:
                "Opening a movie makes an untitled project at its own size and rate, "
                + "with the file as the first clip on Track 1.")
        paragraph.translatesAutoresizingMaskIntoConstraints = false
        paragraph.font = DS.sans(15)
        paragraph.textColor = DS.textMuted
        paragraph.alignment = .center
        paragraph.isEditable = false
        paragraph.preferredMaxLayoutWidth = 420

        let openButton = StickerButton(
            title: "Open Video…", style: .primary, target: nil,
            action: #selector(NSDocumentController.openDocument(_:)))
        let newButton = StickerButton(
            title: "New Project", style: .secondary, target: nil,
            action: #selector(AppDelegate.newProject(_:)))
        let buttons = NSStackView(views: [openButton, newButton])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.orientation = .horizontal
        buttons.spacing = 12

        recentLabel.translatesAutoresizingMaskIntoConstraints = false
        recentLabel.attributedStringValue = DS.microLabel("Recent")
        recentLabel.alignment = .center

        recentStack.translatesAutoresizingMaskIntoConstraints = false
        recentStack.orientation = .vertical
        recentStack.alignment = .centerX
        recentStack.spacing = 2

        let formats = NSTextField(
            labelWithString: "MOV · MP4 · M4V · M4A · MP3 · WAV · AIFF · PNG · JPEG · HEIC")
        formats.translatesAutoresizingMaskIntoConstraints = false
        formats.font = DS.mono(11)
        formats.textColor = DS.textFaint
        formats.alignment = .center

        let stack = NSStackView(views: [
            motif, headline, paragraph, buttons, recentLabel, recentStack, formats,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(22, after: motif)
        stack.setCustomSpacing(10, after: headline)
        stack.setCustomSpacing(24, after: paragraph)
        stack.setCustomSpacing(24, after: buttons)
        stack.setCustomSpacing(8, after: recentLabel)
        stack.setCustomSpacing(24, after: recentStack)

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -6),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
        ])
        window.contentView = root
        applyBackground()

        // Close as soon as any document window becomes main; the welcome
        // window returns via applicationShouldOpenUntitledFile when the app
        // reactivates with nothing open.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowBecameMain(_:)),
            name: NSWindow.didBecomeMainNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WelcomeWindowController does not support NSCoder")
    }

    private func applyBackground() {
        window?.backgroundColor = DS.chromeBackground
        window?.contentView?.layer?.backgroundColor = DS.chromeBackground.cgColor
    }

    @objc private func windowBecameMain(_ note: Notification) {
        guard let main = note.object as? NSWindow, main !== window,
              main.windowController?.document != nil
        else { return }
        window?.close()
    }

    func show() {
        applyBackground()
        rebuildRecentList()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Up to five recent documents, most recent first. The tag is the index
    /// into the same list the click re-reads, which is stable for as long as
    /// the window is up.
    private func rebuildRecentList() {
        for view in recentStack.arrangedSubviews {
            recentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let urls = Array(NSDocumentController.shared.recentDocumentURLs.prefix(5))
        recentLabel.isHidden = urls.isEmpty
        for (index, url) in urls.enumerated() {
            let button = NSButton(
                title: url.deletingPathExtension().lastPathComponent, target: self,
                action: #selector(openRecent(_:)))
            button.isBordered = false
            button.font = DS.sans(13)
            button.contentTintColor = DS.accent
            button.setButtonType(.momentaryChange)
            button.tag = index
            button.toolTip = url.path
            recentStack.addArrangedSubview(button)
        }
    }

    @objc private func openRecent(_ sender: Any?) {
        let urls = Array(NSDocumentController.shared.recentDocumentURLs.prefix(5))
        guard let tag = (sender as? NSButton)?.tag, urls.indices.contains(tag) else {
            NSSound.beep()
            return
        }
        NSDocumentController.shared.openDocument(
            withContentsOf: urls[tag], display: true
        ) { _, _, error in
            if let error = error {
                NSApp.presentError(error)
            }
        }
    }
}
