import AppKit

/// Reelcut ▸ Settings… ⌘, — road map 6 §5d's window, and the app's first
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
/// **Two panes, "Assistant" then "Transcription"** (road map 12 A2's
/// `AssistantSettingsPane`, then `transcriptionPane`), each a vertical stack
/// and each one of `content`'s arranged subviews, 24 pt apart through
/// `content.spacing`. §5d's one pane was taken as a HEADING inside a window
/// titled Settings rather than as a tab bar with one tab. Each pane opens
/// with `settingsSectionHeader` — its heading and a `SettingsInfoButton`
/// whose popover holds its explanation (spec §11 SH-5). There is still a
/// Transcription section, so the sentence the `transcribe` tool and its
/// catalog entry both print — the one that sends a caller to Settings and
/// then to Transcription — stays true without either of them being edited.
/// **A later section is one more pane**: built the same way (a vertical stack
/// opening with `settingsSectionHeader`) and put first with
/// `content.insertArrangedSubview(pane, at: 0)`; the gap comes from
/// `content.spacing`, so nothing else moves.
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
    static let didChangeNotification = Notification.Name("ReelcutSettingsDidChange")

    /// §5d's "one pane for now", as the heading this window opens with.
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
    /// Settings' Assistant pane, `content`'s first.
    let assistantPane: AssistantSettingsPane
    /// The Transcription pane, after the Assistant pane.
    let transcriptionPane = NSStackView()

    private(set) var saveButton: NSButton!
    private(set) var removeButton: NSButton!
    private(set) var verifyButton: NSButton!
    private(set) var accountButton: NSButton!

    init(
        store: @escaping () -> any SecretStore = { AssemblyAIConfiguration.store() },
        assistantStore: @escaping () -> any SecretStore = { AssistantConfiguration.store() },
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        spendFolder: @escaping () -> URL? = { AssistantSpend.folder() }
    ) {
        self.store = store
        self.defaults = defaults
        self.environment = environment
        assistantPane = AssistantSettingsPane(
            store: assistantStore, defaults: defaults, environment: environment,
            spendFolder: spendFolder)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 340),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = buildContent()
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
            regionPopup.addItem(withTitle: region.displayName)
            regionPopup.lastItem?.representedObject = region.rawValue
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
        for pane in [assistantPane, transcriptionPane] {
            content.addArrangedSubview(pane)
        }
        content.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView(
            frame: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 340))
        root.wantsLayer = true
        root.addSubview(content)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.windowWidth),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.inset),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Self.inset),
            content.trailingAnchor.constraint(
                equalTo: root.trailingAnchor, constant: -Self.inset),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Self.inset),
        ])
        return root
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
        assistantPane.sync()
        assistantPane.refreshSpend()
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
                + "deleted from AssemblyAI — Reelcut asks for the delete as soon as it has the "
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

/// The command half, at the foot of the file that owns the feature —
/// `CaptionImporter.swift`'s precedent, and what keeps `AppDelegate.swift`
/// out of this change entirely.
extension AppDelegate {

    /// Reelcut ▸ Settings… ⌘, — a nil-target selector like every other item
    /// in `AppDelegate+Menus.swift`, which is what lets it resolve with no
    /// document open.
    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }
}
