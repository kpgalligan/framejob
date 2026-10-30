import AppKit

/// Every view of the Assistant tab (road map 12 A2): the context meter and
/// Clear along the top, the conversation's Spend row under them (road map 13
/// P4), the transcript (one selectable text, spec §11 AI-17), the ask-first
/// row, and the composer — a text view that grows from one line to five —
/// whose Send becomes Stop — or, with no key, a pointer at Settings.
///
/// **It holds no conversation** (spec §11 AI-4): the transcript is
/// `EditorViewController.assistantTranscript`, the question the session's
/// `pendingQuestion`, the session `EditorViewController.assistant`. What it
/// is shown arrives through `reload`, `apply` and the two `show`s; what the
/// person does leaves through the five closures, which
/// `EditorViewController.attachAssistant` wires. A floating window later is
/// a new host for this same view.
///
/// **Return never answers a question.** Allow and Deny are
/// `OptionButtonControl`s, which take a click and no key; Send has no key
/// equivalent; the composer's bare Return (`onReturn`) sends only while idle
/// and beeps otherwise, and a modified Return is a new line (AI-17, K-2).
/// Stop is a click on Send while it reads Stop.
final class AssistantView: NSView {
    static let placeholder = "Ask about or edit this project…"
    static let questionHeading = "The assistant asks first:"
    static let noKeyText = "Add your Anthropic API key in Settings to use the assistant."
    private static let inset: CGFloat = InspectorMetrics.inset

    // MARK: - Intent out

    /// The message; true when it was taken, and only then does the composer
    /// empty.
    var onSend: ((String) -> Bool)?
    var onStop: (() -> Void)?
    var onAnswer: ((Bool) -> Void)?
    var onClear: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    // MARK: - Views

    var composer: AssistantComposerTextView { composerField.textView }
    let sendButton: AccentButton
    let allowButton: OptionButtonControl
    let denyButton: OptionButtonControl
    let settingsButton: OptionButtonControl
    let questionLabel = NSTextField(wrappingLabelWithString: "")
    let noKeyLabel = NSTextField(wrappingLabelWithString: AssistantView.noKeyText)
    let clearButton: GhostButton

    private let meter = AssistantContextMeterView()
    private let spend = AssistantConversationCostView()
    private let transcript = AssistantTranscriptView()
    private let composerField = AssistantComposerField()
    private let questionHeadingLabel = NSTextField(labelWithString: AssistantView.questionHeading)
    private let questionRow = NSStackView()
    private let composerRow = NSStackView()
    private let noKeyRow = NSStackView()
    private let foot = NSStackView()
    /// The phase last shown: whether Send reads Stop, and whether Return
    /// sends. View state, not the session's.
    private var shownPhase: AssistantPhase = .idle

    init() {
        sendButton = AccentButton(
            title: "Send", symbol: nil, fallback: "", tooltip: "Send the message",
            action: nil)
        clearButton = GhostButton(
            symbol: "arrow.counterclockwise", fallback: "↺", caption: nil,
            tooltip: "Clear the conversation", action: nil, size: NSSize(width: 26, height: 22),
            pointSize: 13)
        var answer: ((Bool) -> Void)?
        allowButton = OptionButtonControl(
            title: "Allow", action: { answer?(true) }, enabled: { true }, onEdit: {})
        denyButton = OptionButtonControl(
            title: "Deny", action: { answer?(false) }, enabled: { true }, onEdit: {})
        var openSettings: (() -> Void)?
        settingsButton = OptionButtonControl(
            title: "Open Settings…", action: { openSettings?() }, enabled: { true },
            onEdit: {})
        super.init(frame: .zero)
        answer = { [weak self] allowed in self?.onAnswer?(allowed) }
        openSettings = { [weak self] in self?.onOpenSettings?() }
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AssistantView does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    /// The wrapping labels need their width to know their height.
    override func layout() {
        super.layout()
        let width = max(bounds.width - 2 * Self.inset - 4, 0)
        var changed = false
        for label in [questionLabel, noKeyLabel] where label.preferredMaxLayoutWidth != width {
            label.preferredMaxLayoutWidth = width
            changed = true
        }
        if changed { super.layout() }
    }

    // MARK: - Building

    private func build() {
        sendButton.target = self
        sendButton.action = #selector(sendClicked(_:))
        sendButton.setAccessibilityIdentifier("assistant.send")
        clearButton.target = self
        clearButton.action = #selector(clearClicked(_:))
        clearButton.setAccessibilityIdentifier("assistant.clear")
        allowButton.setAccessibilityIdentifier("assistant.allow")
        denyButton.setAccessibilityIdentifier("assistant.deny")
        settingsButton.setAccessibilityIdentifier("assistant.settings")

        composer.placeholder = Self.placeholder
        composer.onReturn = { [weak self] in self?.composerReturn() }
        composer.setAccessibilityIdentifier("assistant.composer")
        composerField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        composerField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sendButton.widthAnchor.constraint(equalToConstant: 64).isActive = true

        questionHeadingLabel.font = DS.sans(11)
        questionHeadingLabel.textColor = DS.textMuted
        questionLabel.font = DS.sans(12, weight: .semibold)
        questionLabel.textColor = DS.textStrong
        questionLabel.setAccessibilityIdentifier("assistant.question")
        noKeyLabel.font = DS.sans(12)
        noKeyLabel.textColor = DS.textMuted
        noKeyLabel.setAccessibilityIdentifier("assistant.nokey")
        for label in [questionLabel, noKeyLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let answers = row([allowButton, denyButton], spacing: 6)
        // Hugs its two buttons: at the default the row's width in the
        // leading-aligned stack above it was ambiguous.
        answers.setHuggingPriority(.required, for: .horizontal)
        questionRow.orientation = .vertical
        questionRow.alignment = .leading
        questionRow.spacing = 6
        for view in [questionHeadingLabel, questionLabel, answers] as [NSView] {
            questionRow.addArrangedSubview(view)
        }
        composerRow.orientation = .horizontal
        composerRow.alignment = .bottom
        composerRow.distribution = .fill
        composerRow.spacing = 6
        composerRow.addArrangedSubview(composerField)
        composerRow.addArrangedSubview(sendButton)
        noKeyRow.orientation = .vertical
        noKeyRow.alignment = .leading
        noKeyRow.spacing = 8
        noKeyRow.addArrangedSubview(noKeyLabel)
        noKeyRow.addArrangedSubview(settingsButton)

        foot.orientation = .vertical
        foot.alignment = .leading
        foot.spacing = 10
        foot.detachesHiddenViews = true
        for view in [questionRow, composerRow, noKeyRow] {
            foot.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: foot.widthAnchor).isActive = true
        }
        // A label's frame is 2 pt wider than its text on each side: the rows
        // inset by that much keep every frame inside them.
        for (label, rowStack) in [(questionLabel, questionRow), (noKeyLabel, noKeyRow)] {
            rowStack.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
            label.widthAnchor.constraint(equalTo: rowStack.widthAnchor, constant: -4)
                .isActive = true
        }
        questionRow.isHidden = true
        noKeyRow.isHidden = true

        let top = NSStackView(views: [meter, clearButton])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 8
        let rule = AssistantRule()
        for view in [top, spend, rule, transcript, foot] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            top.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            top.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            spend.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 6),
            spend.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            spend.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            rule.topAnchor.constraint(equalTo: spend.bottomAnchor, constant: 8),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            transcript.topAnchor.constraint(equalTo: rule.bottomAnchor),
            transcript.leadingAnchor.constraint(equalTo: leadingAnchor),
            transcript.trailingAnchor.constraint(equalTo: trailingAnchor),
            transcript.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            foot.topAnchor.constraint(equalTo: transcript.bottomAnchor, constant: 8),
            foot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            foot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            foot.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.inset),
        ])
    }

    private func row(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    // MARK: - What it is shown

    func reload(
        _ entries: [AssistantEntry], usage: AssistantContextUsage, cost: AssistantTurnCost
    ) {
        transcript.reload(entries)
        meter.update(usage)
        spend.update(cost)
    }

    func apply(_ change: AssistantTranscriptChange) {
        if case .usage(let usage) = change { meter.update(usage) }
        if case .conversationCost(let cost) = change { spend.update(cost) }
        transcript.apply(change)
    }

    /// Send reads Stop while a turn runs or a question waits; the ask-first
    /// row shows the question's sentence while there is one.
    func show(phase: AssistantPhase, question: AssistantQuestion?) {
        shownPhase = phase
        let stops = phase == .busy || phase == .asking
        let title = stops ? "Stop" : "Send"
        if sendButton.title != title {
            sendButton.title = title
            sendButton.toolTip = stops ? "Stop the turn" : "Send the message"
            sendButton.needsDisplay = true
        }
        questionLabel.stringValue = question?.sentence ?? ""
        questionRow.isHidden = question == nil
    }

    /// With no key, the composer gives way to a pointer at Settings.
    func show(hasKey: Bool) {
        composerRow.isHidden = !hasKey
        noKeyRow.isHidden = hasKey
    }

    func focusComposer() {
        guard !composerRow.isHidden else { return }
        window?.makeFirstResponder(composer)
    }

    // MARK: - Actions

    @objc private func sendClicked(_ sender: Any?) {
        if shownPhase == .busy || shownPhase == .asking {
            onStop?()
            return
        }
        send()
    }

    /// Return in the composer: a send while idle, a beep otherwise — never an
    /// answer, and never a Stop.
    private func composerReturn() {
        guard shownPhase == .idle || shownPhase == .closed else {
            NSSound.beep()
            return
        }
        send()
    }

    /// A message taken empties the composer and, when it held the keys, hands
    /// them back to the editor, so Space plays while the turn runs (spec §11
    /// K-4); a message refused keeps both.
    private func send() {
        let text = composer.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard onSend?(text) == true else { return }
        composer.string = ""
        if window?.firstResponder === composer { window?.makeFirstResponder(window?.contentView) }
    }

    @objc private func clearClicked(_ sender: Any?) {
        onClear?()
    }
}

/// The hairline under the meter row.
private final class AssistantRule: NSView {
    override func draw(_ dirtyRect: NSRect) {
        DS.border.setFill()
        bounds.fill()
    }
}
