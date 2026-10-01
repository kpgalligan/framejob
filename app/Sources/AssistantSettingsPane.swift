import AppKit

/// Settings' Assistant pane (road map 12 A2): the person's Anthropic key
/// (spec §11 AI-8), the model (AI-11) and the chat settings (AI-20), under
/// the Transcription pane in `SettingsWindowController`'s one stack.
///
/// **It mirrors the Transcription pane's key handling, rule for rule.** The
/// key is typed into a secure field and never shown back: a stored key is a
/// FIXED-LENGTH mask in the field's placeholder
/// (`SettingsWindowController.maskedPlaceholder`), never its `stringValue`;
/// Save writes what was typed and empties the field; "No API key is set." is
/// a state in the muted colour, not an error. There is no Verify and no
/// account link (AI-1: the app never calls Anthropic itself).
///
/// **A change ends each window's conversation.** A session keeps the key and
/// model it was opened with, so Save, Remove and a model that actually
/// changes post `AssistantConfiguration.didChangeNotification` — this pane is
/// its only poster — and each editor ends its session
/// (`EditorViewController.assistantConfigurationDidChange`). A model commit
/// that leaves `AssistantConfiguration.model` where it was posts nothing.
///
/// **A chat-settings change ends nothing** (AI-20). The compaction switch, its
/// threshold and the clearing switch apply at once, with no Save, and post
/// "settings" only when `AssistantChatSettings` actually changes; each
/// editor writes them to its open session. A threshold outside the range
/// beeps and the field shows the stored value again.
///
/// The store is a FACTORY, as the Transcription pane's is, so the harness and
/// the probes hand it a `MemoryStore` and no file is read or written.
///
/// **The month's spend (road map 13 P4, spec §11 P-7)** is the two labels
/// under the buttons: the UTC month folded from the spend folder's ledger
/// (`AssistantSpendMonth`) and the note that it is Reelcut's own estimate
/// (P-4). The folder is a FACTORY too, so the harness hands it an absent one.
/// `init` and `sync()` never read the ledger; `refreshSpend` does, when the
/// window shows and after each line `AssistantSpend.record` writes while it
/// is visible. Only the latest refresh's answer is shown.
final class AssistantSettingsPane: NSStackView, NSTextFieldDelegate {
    static let paneTitle = "Assistant"
    static let emptyPlaceholder = "Paste your Anthropic API key"
    /// The Settings window's width less its two insets.
    private static let textWidth: CGFloat = 420

    private let store: () -> any SecretStore
    private let defaults: UserDefaults
    private let environment: [String: String]
    private let spendFolder: () -> URL?
    /// The reading `spendLabel` last showed, and the refresh whose answer may
    /// still be shown.
    private var shown: AssistantSpendMonth.Reading = .reading
    private var spendGeneration = 0

    let headingLabel = NSTextField(labelWithString: AssistantSettingsPane.paneTitle)
    let keyField = NSSecureTextField()
    let modelField = NSTextField()
    let compactBox = NSButton(checkboxWithTitle: "Compact when context reaches", target: nil, action: nil)
    let compactTokensField = NSTextField()
    let tokensLabel = NSTextField(labelWithString: "tokens")
    let clearToolResultsBox = NSButton(
        checkboxWithTitle:
            "Clear old tool results past \(AssistantChatSettings.clearTriggerTokens.formatted()) tokens",
        target: nil, action: nil)
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let explanationLabel = NSTextField(wrappingLabelWithString: "")
    let spendLabel = NSTextField(wrappingLabelWithString: "")
    let spendNoteLabel = NSTextField(wrappingLabelWithString: AssistantSpendMonth.note)
    private(set) var saveButton: NSButton!
    private(set) var removeButton: NSButton!

    init(
        store: @escaping () -> any SecretStore, defaults: UserDefaults,
        environment: [String: String],
        spendFolder: @escaping () -> URL? = { AssistantSpend.folder() }
    ) {
        self.store = store
        self.defaults = defaults
        self.environment = environment
        self.spendFolder = spendFolder
        super.init(frame: .zero)
        build()
        sync()
        NotificationCenter.default.addObserver(
            self, selector: #selector(spendRecorded(_:)),
            name: AssistantSpend.didRecordNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AssistantSettingsPane does not support NSCoder")
    }

    private func build() {
        headingLabel.font = DS.sans(15, weight: .bold)
        headingLabel.textColor = DS.textStrong

        DSField.style(keyField)
        keyField.placeholderString = Self.emptyPlaceholder
        keyField.target = self
        keyField.action = #selector(saveClicked(_:))
        keyField.delegate = self
        keyField.widthAnchor.constraint(equalToConstant: 240).isActive = true

        DSField.style(modelField)
        modelField.placeholderString = AssistantConfiguration.defaultModel
        modelField.target = self
        modelField.action = #selector(modelChanged(_:))
        modelField.cell?.sendsActionOnEndEditing = true
        modelField.widthAnchor.constraint(equalToConstant: 240).isActive = true

        compactBox.font = DS.sans(13)
        compactBox.target = self
        compactBox.action = #selector(compactToggled(_:))
        compactBox.setAccessibilityIdentifier("settings.assistant.compact")
        DSField.style(compactTokensField)
        compactTokensField.alignment = .right
        compactTokensField.target = self
        compactTokensField.action = #selector(compactTokensChanged(_:))
        compactTokensField.cell?.sendsActionOnEndEditing = true
        compactTokensField.widthAnchor.constraint(equalToConstant: 84).isActive = true
        compactTokensField.setAccessibilityIdentifier("settings.assistant.compacttokens")
        tokensLabel.font = DS.sans(13)
        tokensLabel.textColor = DS.textMuted
        clearToolResultsBox.font = DS.sans(13)
        clearToolResultsBox.target = self
        clearToolResultsBox.action = #selector(clearToolResultsToggled(_:))
        clearToolResultsBox.setAccessibilityIdentifier("settings.assistant.cleartoolresults")

        statusLabel.font = DS.sans(12)
        statusLabel.textColor = DS.textMuted
        statusLabel.preferredMaxLayoutWidth = Self.textWidth
        explanationLabel.stringValue = Self.explanation()
        explanationLabel.font = DS.sans(11)
        explanationLabel.textColor = DS.textFaint
        explanationLabel.preferredMaxLayoutWidth = Self.textWidth

        saveButton = StickerButton(
            title: "Save", style: .primary, target: self, action: #selector(saveClicked(_:)))
        removeButton = StickerButton(
            title: "Remove", style: .secondary, target: self, action: #selector(removeClicked(_:)))

        spendLabel.font = DS.sans(12)
        spendLabel.textColor = DS.textStrong
        spendLabel.preferredMaxLayoutWidth = Self.textWidth
        spendLabel.setAccessibilityIdentifier("settings.assistant.spend")
        spendNoteLabel.font = DS.sans(11)
        spendNoteLabel.textColor = DS.textFaint
        spendNoteLabel.preferredMaxLayoutWidth = Self.textWidth
        spendNoteLabel.setAccessibilityIdentifier("settings.assistant.spendnote")

        orientation = .vertical
        alignment = .leading
        spacing = 12
        let buttons = row([saveButton, removeButton])
        let compactRow = row([compactBox, compactTokensField, tokensLabel])
        compactRow.spacing = 6
        let views: [NSView] = [
            headingLabel, row([fieldLabel("API key:"), keyField]),
            row([fieldLabel("Model:"), modelField]), compactRow, clearToolResultsBox,
            statusLabel, explanationLabel, buttons, spendLabel, spendNoteLabel,
        ]
        for view in views { addArrangedSubview(view) }
        setCustomSpacing(16, after: buttons)
        setCustomSpacing(4, after: spendLabel)
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        // Hugs at its content, so its width is not a tie with the column's (#143).
        stack.setHuggingPriority(.required, for: .horizontal)
        return stack
    }

    // MARK: - Syncing

    /// The placeholder, the model, the chat settings, and whether Remove can
    /// do anything. Never writes `keyField.stringValue` (the Transcription
    /// pane's rule).
    func sync() {
        let stored = store().read()
        keyField.placeholderString =
            stored != nil ? SettingsWindowController.maskedPlaceholder : Self.emptyPlaceholder
        removeButton?.isEnabled = stored != nil
        modelField.stringValue = defaults.string(forKey: AssistantConfiguration.modelKey) ?? ""
        syncChatSettings()
        sayKeyState(stored: stored)
    }

    /// The stored chat settings; the threshold field is enabled only while
    /// compaction is on, and never written while it is being edited.
    private func syncChatSettings() {
        let settings = AssistantChatSettings.load(from: defaults)
        compactBox.state = settings.autoCompact ? .on : .off
        clearToolResultsBox.state = settings.clearToolResults ? .on : .off
        compactTokensField.isEnabled = settings.autoCompact
        if compactTokensField.currentEditor() == nil {
            compactTokensField.stringValue = settings.autoCompactTokens.formatted()
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === keyField else { return }
        sayKeyState(stored: store().read())
    }

    /// "No API key is set." when neither the field, the store nor the
    /// environment has one; nothing otherwise.
    private func sayKeyState(stored: String?) {
        let typed = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasKey =
            !typed.isEmpty
            || AssistantConfiguration.credential(
                store: MemoryStore(stored), environment: environment) != nil
        say(hasKey ? "" : "No API key is set.", problem: false)
    }

    private func say(_ text: String, problem: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = problem ? DS.textStrong : DS.textMuted
    }

    // MARK: - The month's spend

    /// The UTC month holding `now`, from the spend folder's ledger: no
    /// folder says so at once, an absent ledger is an empty month at once,
    /// and a present one reads "Reading…" while `AssistantSpendMonth.read`
    /// folds it — except that with `keepShown` a sentence already shown for
    /// a summary or a failure stays until the fold answers (P-7). Each call
    /// supersedes every earlier one.
    func refreshSpend(now: Date = Date(), keepShown: Bool = false) {
        spendGeneration += 1
        let generation = spendGeneration
        let month = AssistantSpendMonth.month(containing: now)
        guard let folder = spendFolder() else {
            showSpend(.noLedger, month: month)
            return
        }
        let ledger = folder.appendingPathComponent(AssistantSpend.ledgerName)
        guard FileManager.default.fileExists(atPath: ledger.path) else {
            showSpend(.summary(AssistantSpendMonth.Summary()), month: month)
            return
        }
        var keeps = false
        switch shown {
        case .summary, .failed: keeps = keepShown
        case .noLedger, .reading: keeps = false
        }
        if !keeps { showSpend(.reading, month: month) }
        AssistantSpendMonth.read(ledger: ledger, month: month) { [weak self] reading in
            guard let self, self.spendGeneration == generation else { return }
            self.showSpend(reading, month: month)
        }
    }

    private func showSpend(_ reading: AssistantSpendMonth.Reading, month: DateInterval) {
        shown = reading
        spendLabel.stringValue = AssistantSpendMonth.sentence(reading, month: month)
    }

    /// A ledger line was written: re-read it, only while the window shows.
    @objc private func spendRecorded(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        refreshSpend(keepShown: true)
    }

    // MARK: - Buttons

    /// Writes what is in the field and then empties it.
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
        post("key")
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
        post("key")
    }

    /// The model field's commit (Return or leaving it). Blank is AI-11's
    /// default.
    @objc func modelChanged(_ sender: Any?) {
        let before = AssistantConfiguration.model(defaults: defaults)
        let typed = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(typed, forKey: AssistantConfiguration.modelKey)
        guard AssistantConfiguration.model(defaults: defaults) != before else { return }
        post("model")
    }

    // MARK: - Chat settings (AI-20)

    @objc func compactToggled(_ sender: Any?) {
        var settings = AssistantChatSettings.load(from: defaults)
        settings.autoCompact = compactBox.state == .on
        commit(settings)
    }

    @objc func clearToolResultsToggled(_ sender: Any?) {
        var settings = AssistantChatSettings.load(from: defaults)
        settings.clearToolResults = clearToolResultsBox.state == .on
        commit(settings)
    }

    /// The threshold field's commit (Return or leaving it). Outside the range
    /// beeps and shows the stored value again, writing nothing.
    @objc func compactTokensChanged(_ sender: Any?) {
        var settings = AssistantChatSettings.load(from: defaults)
        guard let tokens = Int(compactTokensField.stringValue.filter(\.isNumber)),
            AssistantChatSettings.compactTokensRange.contains(tokens)
        else {
            NSSound.beep()
            compactTokensField.stringValue = settings.autoCompactTokens.formatted()
            return
        }
        settings.autoCompactTokens = tokens
        commit(settings)
        compactTokensField.stringValue = tokens.formatted()
    }

    /// Saves and posts "settings" only when `settings` differs from what is
    /// stored; the controls show the stored settings after.
    private func commit(_ settings: AssistantChatSettings) {
        let changed = settings != AssistantChatSettings.load(from: defaults)
        if changed { settings.save(to: defaults) }
        syncChatSettings()
        if changed { post("settings") }
    }

    private func post(_ change: String) {
        NotificationCenter.default.post(
            name: AssistantConfiguration.didChangeNotification, object: self,
            userInfo: [AssistantConfiguration.changeKey: change])
    }

    /// What the assistant sends and to whom, what it costs, where the key is
    /// kept, and what the chat settings do.
    static func explanation() -> String {
        let range = AssistantChatSettings.compactTokensRange
        return "The assistant sends your messages, the project's details and the frames it renders "
            + "to Anthropic, using your own API key; what it costs is billed to that key. It "
            + "asks before writing a file. The key is kept in a file only you can read and is "
            + "never shown again once it is saved. Leave the model blank for "
            + "\(AssistantConfiguration.defaultModel). Changing the key or the model starts "
            + "a new conversation. At the end of a turn past the compaction threshold "
            + "(\(range.lowerBound.formatted()) to \(range.upperBound.formatted()) tokens; "
            + "\(AssistantChatSettings.defaultCompactTokens.formatted()) by default), the "
            + "conversation is replaced by a summary, and earlier renders don't survive it. "
            + "Clearing lets Anthropic drop old tool results from what the model sees, even "
            + "mid-turn (never tool search results), and each clearing costs a fresh "
            + "prompt-cache write. Changing either keeps the conversation."
    }
}

