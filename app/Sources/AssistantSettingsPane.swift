import AppKit

/// Settings' Assistant pane (road map 12 A2): the person's Anthropic key
/// (spec §11 AI-8) and the model (AI-11), under the Transcription pane in
/// `SettingsWindowController`'s one stack.
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
/// The store is a FACTORY, as the Transcription pane's is, so the harness and
/// the probes hand it a `MemoryStore` and no file is read or written.
final class AssistantSettingsPane: NSStackView, NSTextFieldDelegate {
    static let paneTitle = "Assistant"
    static let emptyPlaceholder = "Paste your Anthropic API key"
    /// The Settings window's width less its two insets.
    private static let textWidth: CGFloat = 420

    private let store: () -> any SecretStore
    private let defaults: UserDefaults
    private let environment: [String: String]

    let headingLabel = NSTextField(labelWithString: AssistantSettingsPane.paneTitle)
    let keyField = NSSecureTextField()
    let modelField = NSTextField()
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let explanationLabel = NSTextField(wrappingLabelWithString: "")
    private(set) var saveButton: NSButton!
    private(set) var removeButton: NSButton!

    init(
        store: @escaping () -> any SecretStore, defaults: UserDefaults,
        environment: [String: String]
    ) {
        self.store = store
        self.defaults = defaults
        self.environment = environment
        super.init(frame: .zero)
        build()
        sync()
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

        orientation = .vertical
        alignment = .leading
        spacing = 12
        let views: [NSView] = [
            headingLabel, row([fieldLabel("API key:"), keyField]),
            row([fieldLabel("Model:"), modelField]), statusLabel, explanationLabel,
            row([saveButton, removeButton]),
        ]
        for view in views { addArrangedSubview(view) }
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    // MARK: - Syncing

    /// The placeholder, the model, and whether Remove can do anything. Never
    /// writes `keyField.stringValue` (the Transcription pane's rule).
    func sync() {
        let stored = store().read()
        keyField.placeholderString =
            stored != nil ? SettingsWindowController.maskedPlaceholder : Self.emptyPlaceholder
        removeButton?.isEnabled = stored != nil
        modelField.stringValue = defaults.string(forKey: AssistantConfiguration.modelKey) ?? ""
        sayKeyState(stored: stored)
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

    private func post(_ change: String) {
        NotificationCenter.default.post(
            name: AssistantConfiguration.didChangeNotification, object: self,
            userInfo: [AssistantConfiguration.changeKey: change])
    }

    /// What the assistant sends and to whom, what it costs, and where the key
    /// is kept.
    static func explanation() -> String {
        "The assistant sends your messages, the project's details and the frames it renders "
            + "to Anthropic, using your own API key; what it costs is billed to that key. It "
            + "asks before writing a file. The key is kept in a file only you can read and is "
            + "never shown again once it is saved. Leave the model blank for "
            + "\(AssistantConfiguration.defaultModel). Changing the key or the model starts "
            + "a new conversation."
    }
}

