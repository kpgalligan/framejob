import AppKit

/// Frame Job ▸ Settings… ⌘, — road map 6 §5d's window, and the app's first
/// piece of chrome for something PERSISTED beyond view state.
///
/// **A window and not a sheet, deliberately.** A sheet belongs to a document
/// and these settings belong to the person: the key and the region are the
/// same whichever project is open, and the Settings item has to work with no
/// document open at all (`WelcomeWindowController` is what is on screen
/// then). `ExportQueueWindowController` is the mould — one instance for the
/// life of the process, `isReleasedWhenClosed = false` because the controller
/// owns the window, `applyBackground()` in `show()` so a window reopened
/// after an appearance change repaints, and no frame autosave, because this
/// window is one fixed lockup and remembering where it was is not worth a
/// key. It is NOT `isExcludedFromWindowsMenu`: unlike the queue, nothing in
/// the Window menu opens it, so AppKit's own row is the only way back to a
/// window the person has buried.
///
/// **Four panes, "MCP", "Assistant", "Transcription" then "Playback"** (issue
/// batch B74's `MCPSettingsPane`, spec §11 MC-7; road map 12 A2's
/// `AssistantSettingsPane`; `transcriptionPane`; then G-38's
/// `PlaybackSettingsPane`), each a vertical stack
/// and each one of `content`'s arranged subviews, 24 pt apart through
/// `content.spacing`. §5d's one pane was taken as a HEADING inside a window
/// titled Settings rather than as a tab bar with one tab. The Assistant,
/// Transcription and Playback panes open with `settingsSectionHeader` — a heading and a
/// `SettingsInfoButton` whose popover holds its explanation (spec §11 SH-5);
/// the MCP pane opens with its bare heading and shows its blurb, because
/// MC-7 asked for the text above its button. There is still a Transcription
/// section, so the sentence the `transcribe` tool and its catalog entry both
/// print — the one that sends a caller to Settings and then to Transcription
/// — stays true without either of them being edited. The window's first
/// responder is the Assistant key field, so the MCP pane's selectable path
/// never opens selected. **A later section is one more pane**: a vertical
/// stack, put in `buildContent`'s pane list where it belongs; the gap comes
/// from `content.spacing`, so nothing else moves.
///
/// **The panes scroll when the screen is short.** `content` sits in `scroll`,
/// as tall as the panes but capped at the screen's visible height less the
/// title bar (`fitScreen`): four panes are taller than a 1440 × 900 display
/// leaves, and the window must never outgrow its screen. On a taller screen
/// nothing scrolls and the window is exactly the panes' height.
///
/// **The key is never shown, never logged, and never in `UserDefaults`.**
/// `sync()` writes a FIXED-LENGTH mask into the field's PLACEHOLDER when a
/// key is stored — never into its `stringValue`, so the value cannot be
/// copied out of the field, read by accessibility, or photographed, and the
/// mask's length says nothing about the key's. What a person TYPES is theirs
/// until they press Save, and Save clears the field. The store is reached
/// through `AssemblyAIConfiguration.store()` by default, so R6-9's
/// `-RCSecretFolder` override holds for every proof that launches the app —
/// and the initialiser takes a store FACTORY so the offscreen harness can
/// hand it a `MemoryStore` and photograph this window without any file
/// anywhere being read or written.
///
/// **No key set is not an error.** It is a state, said in `No API key is
/// set.` in the ordinary muted colour: a person who has not set one yet has
/// done nothing wrong, and a red window on first open would say they had.
/// Only a refusal from AssemblyAI and a store that would not write are
/// styled as problems.
///
/// **R6-12** — the key and the region are settings a PERSON makes and no tool
/// reads or writes either. This window is the one writer of both.
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {

    /// The app's one Settings window. A probe never comes near it: every
    /// instrument builds its own controller with a store of its own.
    static let shared = SettingsWindowController()

    /// Posted after Save, Remove and a region change, so the Generate
    /// Captions sheet can re-enable its button without being reopened.
    static let didChangeNotification = Notification.Name("FrameJobSettingsDidChange")

    /// The Transcription pane's heading, the third of the window's four panes.
    static let paneTitle = "Transcription"

    /// What the field shows when a key IS stored. Fixed length on purpose:
    /// a mask as long as the key would leak its length.
    static let maskedPlaceholder = "••••••••••••••••"
    /// And when one is not.
    static let emptyPlaceholder = "Paste your key"
    /// The key row's label, which names the service the field does not.
    static let keyLabel = "AssemblyAI API key:"

    /// Where a person gets a key and sees what they have spent.
    static let accountURL = "https://www.assemblyai.com/dashboard"

    private static let inset: CGFloat = 20
    private static let windowWidth: CGFloat = 460

    /// A FACTORY rather than a store, because `AssemblyAIConfiguration.store()`
    /// answers a value built from the argument domain and the harness must be
    /// able to replace it wholesale.
    let store: () -> any SecretStore
    let defaults: UserDefaults
    let environment: [String: String]

    /// The latest request owns the controls and answer. Its transcriber is
    /// held until that request finishes or a newer invocation supersedes it.
    var verifying: Verification?

    let headingLabel = NSTextField(labelWithString: SettingsWindowController.paneTitle)
    let keyField = NSSecureTextField()
    let regionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    /// The Transcription heading's ⓘ, holding `explanation()` (SH-5).
    let infoButton = SettingsInfoButton(
        section: SettingsWindowController.paneTitle,
        infoText: SettingsWindowController.explanation())
    /// The window's one stack: its arranged subviews are the panes, in order.
    let content = NSStackView()
    /// `content`'s scroll view, capped at the screen's height (`fitScreen`).
    let scroll = NSScrollView()
    private var heightCap: NSLayoutConstraint?
    /// Settings' MCP pane, `content`'s first (MC-7).
    let mcpPane: MCPSettingsPane
    /// Settings' Assistant pane, after the MCP pane.
    let assistantPane: AssistantSettingsPane
    /// The Transcription pane, after the Assistant pane.
    let transcriptionPane = NSStackView()
    /// Settings' Playback pane, last (G-38).
    let playbackPane: PlaybackSettingsPane

    private(set) var saveButton: NSButton!
    private(set) var removeButton: NSButton!
    private(set) var verifyButton: NSButton!
    private(set) var accountButton: NSButton!

    init(
        store: @escaping () -> any SecretStore = { AssemblyAIConfiguration.store() },
        assistantStore: @escaping () -> any SecretStore = { AssistantConfiguration.store() },
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        spendFolder: @escaping () -> URL? = { AssistantSpend.folder() },
        mcpHelper: URL = AgentServer.mcpHelperURL,
        pasteboard: NSPasteboard = .general
    ) {
        self.store = store
        self.defaults = defaults
        self.environment = environment
        mcpPane = MCPSettingsPane(helperURL: mcpHelper, pasteboard: pasteboard)
        assistantPane = AssistantSettingsPane(
            store: assistantStore, defaults: defaults, environment: environment,
            spendFolder: spendFolder)
        playbackPane = PlaybackSettingsPane(defaults: defaults)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 340),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = buildContent()
        fitScreen(window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
        window.initialFirstResponder = assistantPane.keyField
        applyBackground()
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController does not support NSCoder")
    }

    // MARK: - The view

    private func buildContent() -> NSView {
        headingLabel.font = DS.sans(15, weight: .bold)
        headingLabel.textColor = DS.textStrong

        DSField.style(keyField)
        keyField.placeholderString = Self.emptyPlaceholder
        keyField.target = self
        keyField.action = #selector(saveClicked(_:))
        keyField.delegate = self
        keyField.widthAnchor.constraint(equalToConstant: 240).isActive = true

        // A popup built from model objects carries the object, never an
        // index — app/CLAUDE.md's popup rule, and `CaptionExporter`'s.
        regionPopup.menu?.autoenablesItems = false
        for region in AssemblyAIConfiguration.Region.allCases {
            let item = NSMenuItem(title: region.displayName, action: nil, keyEquivalent: "")
            item.representedObject = region.rawValue
            regionPopup.menu?.addItem(item)
        }
        regionPopup.font = DS.sans(13)
        regionPopup.target = self
        regionPopup.action = #selector(regionChanged(_:))
        regionPopup.widthAnchor.constraint(equalToConstant: 180).isActive = true

        statusLabel.font = DS.sans(12)
        statusLabel.textColor = DS.textMuted
        statusLabel.preferredMaxLayoutWidth = Self.windowWidth - Self.inset * 2
        infoButton.setAccessibilityIdentifier("settings.transcription.info")

        saveButton = StickerButton(
            title: "Save", style: .primary, target: self, action: #selector(saveClicked(_:)))
        removeButton = StickerButton(
            title: "Remove", style: .secondary, target: self, action: #selector(removeClicked(_:)))
        verifyButton = StickerButton(
            title: "Verify", style: .secondary, target: self, action: #selector(verifyClicked(_:)))
        accountButton = StickerButton(
            title: "Account Page", style: .secondary, target: self,
            action: #selector(openAccount(_:)))

        let keyRow = row([fieldLabel(Self.keyLabel), keyField])
        let regionRow = row([fieldLabel("Region:"), regionPopup])
        // Hug at their content, so the column's leading alignment is their
        // one answer and not a tie with its width (#143). `buttons` is left
        // alone: its spacer pushes Account Page right.
        keyRow.setHuggingPriority(.required, for: .horizontal)
        regionRow.setHuggingPriority(.required, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        let buttons = row([saveButton, removeButton, verifyButton, spacer, accountButton])

        transcriptionPane.orientation = .vertical
        transcriptionPane.alignment = .leading
        transcriptionPane.spacing = 12
        let header = settingsSectionHeader(headingLabel, info: infoButton)
        for view in [header, keyRow, regionRow, statusLabel, buttons] {
            transcriptionPane.addArrangedSubview(view)
        }

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 24
        for pane in [mcpPane, assistantPane, transcriptionPane, playbackPane] {
            content.addArrangedSubview(pane)
        }
        content.translatesAutoresizingMaskIntoConstraints = false

        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document

        let root = NSView(
            frame: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 340))
        root.wantsLayer = true
        root.addSubview(scroll)
        let clip = scroll.contentView
        // As tall as the panes, below the labels' compression resistance so
        // a short screen's cap shortens the scroll view, never a pane.
        let fit = scroll.heightAnchor.constraint(equalTo: document.heightAnchor)
        fit.priority = .defaultHigh - 1
        let cap = scroll.heightAnchor.constraint(lessThanOrEqualToConstant: 10_000)
        heightCap = cap
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.windowWidth),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: Self.inset),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: Self.inset),
            content.trailingAnchor.constraint(
                equalTo: document.trailingAnchor, constant: -Self.inset),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -Self.inset),
            fit, cap,
        ])
        return root
    }

    /// Caps `scroll` at `visible`'s height less the title bar, so the window
    /// never outgrows its screen and taller panes scroll, then moves the
    /// window up or down into `visible` when it sticks out. A window that
    /// fits stays where it is. Main only; `init` and `show()` call it.
    func fitScreen(_ visible: NSRect?) {
        guard let window, let visible, let cap = heightCap else { return }
        let titleBar = NSWindow.frameRect(forContentRect: .zero, styleMask: window.styleMask).height
        cap.constant = max(200, visible.height - titleBar)
        window.layoutIfNeeded()
        var frame = window.frame
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        if frame != window.frame { window.setFrame(frame, display: false) }
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func applyBackground() {
        window?.backgroundColor = DS.chromeBackground
        window?.contentView?.layer?.backgroundColor = DS.chromeBackground.cgColor
    }

    // MARK: - Showing and syncing

    func show() {
        applyBackground()
        sync()
        mcpPane.sync()
        assistantPane.sync()
        assistantPane.refreshSpend()
        playbackPane.sync()
        fitScreen(window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Everything the window shows that is not a message about something the
    /// person just did: the placeholder, the region, and which buttons can do
    /// anything.
    ///
    /// It never writes `keyField.stringValue` — not from the store, which
    /// would put the key on screen, and not to clear it, which would throw
    /// away what somebody was in the middle of typing when the region popup
    /// moved. Save and Remove clear it themselves.
    func sync() {
        // ONE store per sync: the factory builds a `FileStore` and every read
        // opens the key file, and this runs on init, on `show`, on Save, on
        // Remove and on a region change (05-review's nit 4).
        let store = self.store()
        let stored = store.read()
        let credential = effectiveCredential(storedCredential: stored)
        keyField.placeholderString =
            stored != nil ? Self.maskedPlaceholder : Self.emptyPlaceholder
        removeButton?.isEnabled = stored != nil
        let region = AssemblyAIConfiguration.region(defaults: defaults)
        if let index = regionPopup.itemArray.firstIndex(where: {
            $0.representedObject as? String == region.rawValue
        }) {
            regionPopup.selectItem(at: index)
        }
        updateVerifyButton(credential: credential)
        if let verifying {
            if (try? verificationInput(credential: credential ?? "")) == verifying.input {
                say("Checking…", problem: false)
            } else {
                say("Settings changed since this check began. Verify again.", problem: false)
            }
        } else {
            // Not an error, and not styled as one: it is where everybody starts.
            say(credential == nil ? "No API key is set." : "", problem: false)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        let credential = effectiveCredential(storedCredential: store().read())
        updateVerifyButton(credential: credential)
        if let verifying,
            (try? verificationInput(credential: credential ?? "")) == verifying.input
        {
            say("Checking…", problem: false)
        } else if verifying != nil {
            say("Settings changed since this check began. Verify again.", problem: false)
        } else {
            say(credential == nil ? "No API key is set." : "", problem: false)
        }
    }

    func say(_ text: String, problem: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = problem ? DS.textStrong : DS.textMuted
    }

    // MARK: - Buttons

    /// Writes what is in the field and then empties it. A key that stayed in
    /// the field after Save would be copyable out of the window for the rest
    /// of the session.
    @objc func saveClicked(_ sender: Any?) {
        let typed = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            NSSound.beep()
            return
        }
        do {
            try store().write(typed)
        } catch {
            keyField.stringValue = ""
            sync()
            say(error.localizedDescription, problem: true)
            return
        }
        keyField.stringValue = ""
        sync()
        say("Key saved.", problem: false)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    @objc func removeClicked(_ sender: Any?) {
        do {
            try store().remove()
        } catch {
            sync()
            say(error.localizedDescription, problem: true)
            return
        }
        keyField.stringValue = ""
        sync()
        say("Key removed.", problem: false)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// The region, read off the ITEM and not off the popup's index — two
    /// regions could one day localize to one display name.
    @objc func regionChanged(_ sender: Any?) {
        guard let raw = regionPopup.selectedItem?.representedObject as? String,
            AssemblyAIConfiguration.Region(rawValue: raw) != nil
        else { return }
        defaults.set(raw, forKey: AssemblyAIConfiguration.regionKey)
        sync()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    @objc func openAccount(_ sender: Any?) {
        guard let url = URL(string: Self.accountURL) else { return }
        NSWorkspace.shared.open(url)
    }

    /// §5d's plain words, the ⓘ's text in three paragraphs: what leaves
    /// this Mac and that it is deleted afterwards, what it costs, and where
    /// the key is kept.
    static func explanation() -> String {
        [
            "With AssemblyAI chosen in the Generate Captions sheet, the AUDIO of the files you "
                + "are captioning is uploaded to AssemblyAI, transcribed, read back, and then "
                + "deleted from AssemblyAI — Frame Job asks for the delete as soon as it has the "
                + "words, and retries it at the start of the next run if it did not land. "
                + "Nothing is uploaded until you press Generate, and captions made on this Mac "
                + "never leave it.",
            "AssemblyAI's published rate is $\(AssemblyAIRates.perHour) an hour of audio, "
                + "$\(AssemblyAIRates.speakersPerHour) more with Speakers on, read on "
                + "\(AssemblyAIRates.readOn).",
            "The key is kept in a file only you can read and is never shown again once it is "
                + "saved.",
        ].joined(separator: "\n\n")
    }
}

// MARK: - The menu command

/// `SettingsWindowController.scroll`'s document: flipped, so the panes start
/// at the top.
private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// The command half, at the foot of the file that owns the feature —
/// `CaptionImporter.swift`'s precedent, and what keeps `AppDelegate.swift`
/// out of this change entirely.
extension AppDelegate {

    /// Frame Job ▸ Settings… ⌘, — a nil-target selector like every other item
    /// in `AppDelegate+Menus.swift`, which is what lets it resolve with no
    /// document open.
    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }
}
