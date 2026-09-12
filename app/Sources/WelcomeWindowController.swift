import AppKit

/// The no-document window: shown when the app is frontmost with nothing open,
/// replacing the bare open panel (spec §3). Offers Open Video…, New Project,
/// New Recording… and Recent, accepts dropped files through `FileDropView`,
/// and closes as soon as a document window becomes main.
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()

    /// Rebuilt on every `show()` — the recent list changes while the window
    /// is closed, so it cannot be built once in init.
    private let recentStack = NSStackView()
    private let recentLabel = NSTextField(labelWithString: "")

    private init() {
        // 600 rather than the old 520: the lockup is taller than the motif it
        // replaces and it asks for a clip height of clear space under it, and
        // the window does not resize (no `.resizable`), so the content has to
        // fit at the one size it has.
        let size = NSSize(width: 720, height: 600)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Reelcut"
        window.center()
        super.init(window: window)

        let root = FileDropView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true

        let lockup = BrandLockupView()
        lockup.translatesAutoresizingMaskIntoConstraints = false

        // Demoted from display(42): the lockup above it is already a display
        // face over a drawn mark, and a second display line would fight the
        // wordmark for the page. It stays rather than being dropped because
        // it is the only imperative on the screen — the paragraph explains
        // what opening a file does, it does not ask for one.
        let headline = NSTextField(labelWithString: "Open a file. Start cutting.")
        headline.translatesAutoresizingMaskIntoConstraints = false
        headline.font = DS.sans(17)
        headline.textColor = DS.textMuted
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
        // Road map 3, R1c: the recorder panel, reachable with no document
        // open — a nil-target action, `newProject`'s shape, resolved by the
        // application delegate at the end of the responder chain. Its OWN
        // action since the R2 review, not the File menu's `newRecording`:
        // that item reads Stop Recording and stops while a recording runs,
        // and a button whose title never changes must not.
        let recordButton = StickerButton(
            title: "New Recording…", style: .secondary, target: nil,
            action: #selector(AppDelegate.showRecorderPanel(_:)))
        let buttons = NSStackView(views: [openButton, newButton, recordButton])
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
            lockup, headline, paragraph, buttons, recentLabel, recentStack, formats,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        // The mark's clear space is one clip height on every side; the window
        // itself supplies it above, this supplies it below. The wordmark's
        // descender slack sits inside the lockup's own box, so the optical
        // gap is a little more than the minimum, which is the right way to
        // miss it.
        stack.setCustomSpacing(BrandLockupView.clearSpace, after: lockup)
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
