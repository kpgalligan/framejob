import AppKit

/// The window's one assistant session (spec §11 AI-4): opened on first ask,
/// replaced once it has closed (a dead helper), and closed with the window.
/// The stored `assistant`, `assistantTranscript` and `assistantView` are in
/// `EditorViewController.swift`. Road map 12 A1; A2 adds the Assistant tab's
/// glue: the view is handed over by the inspector (`installAssistant`), its
/// five intents come back here, and every change of phase or question is
/// pushed to it by `assistantRefresh()`, which runs last in each path that
/// can change either — `AssistantSession.send` switches to busy and emits
/// nothing, so no event would say so.
extension EditorViewController {

    /// The live session, else a new one for this window's project. Main only.
    func assistantSession() -> Result<AssistantSession, AssistantOpenError> {
        if let live = assistant, live.phase != .closed { return .success(live) }
        guard let document else {
            return .failure(AssistantOpenError(message: "This window has no project."))
        }
        switch AssistantSession.open(document: document) {
        case .failure(let error):
            return .failure(error)
        case .success(let session):
            assistant = session
            session.onEvent = assistantEventHandler(spendFolder: AssistantSpend.folder())
            if let window = view.window {
                let center = NotificationCenter.default
                center.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
                center.addObserver(
                    self, selector: #selector(assistantWindowWillClose(_:)),
                    name: NSWindow.willCloseNotification, object: window)
            }
            return .success(session)
        }
    }

    /// Each session event: into the transcript, and a `cost` into the spend
    /// ledger in `spendFolder`, resolved once for the session (spec §11 P-5).
    /// A ledger that cannot be written is one transcript note per session.
    private func assistantEventHandler(spendFolder: URL?) -> ([String: Any]) -> Void {
        var ledgerFailed = false
        return { [weak self] event in
            self?.assistantTranscript.take(event)
            if let failure = AssistantSpend.record(event, in: spendFolder), !ledgerFailed {
                ledgerFailed = true
                self?.assistantTranscript.note(failure)
            }
            self?.assistantRefresh()
        }
    }

    /// Closing the window ends its conversation: a pending question is
    /// declined (AI-7) and the helper's stdin is closed.
    @objc func assistantWindowWillClose(_ note: Notification) {
        assistant?.close()
        assistant = nil
    }

    // MARK: - The Assistant tab

    /// From `installInspector`: the view arrives when the tab is first shown,
    /// and a key or model change from Settings reaches this window.
    func installAssistant(on inspector: InspectorViewController) {
        inspector.onAssistantView = { [weak self] view in self?.attachAssistant(view) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(assistantConfigurationDidChange(_:)),
            name: AssistantConfiguration.didChangeNotification, object: nil)
    }

    /// Hosts the conversation in `view`: the tab today, a floating window
    /// later (AI-4).
    func attachAssistant(_ view: AssistantView) {
        assistantView = view
        view.onSend = { [weak self] text in self?.assistantSend(text) ?? false }
        view.onStop = { [weak self] in self?.assistantStop() }
        view.onAnswer = { [weak self] allowed in self?.assistantAnswer(allowed) }
        view.onClear = { [weak self] in self?.assistantClear() }
        view.onOpenSettings = {
            NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
        }
        assistantTranscript.onChange = { [weak view] change in view?.apply(change) }
        view.reload(
            assistantTranscript.entries, usage: assistantTranscript.usage,
            cost: assistantTranscript.conversationCost)
        view.show(hasKey: assistantHasKey)
        assistantRefresh()
    }

    /// The phase and the question, pushed to the view.
    func assistantRefresh() {
        assistantView?.show(
            phase: assistant?.phase ?? .idle, question: assistant?.pendingQuestion)
    }

    /// The composer's message: the session (an open failure is an error
    /// entry), only while idle; the person's line is written once the session
    /// took it. False = not taken, and the composer keeps the text.
    @discardableResult
    func assistantSend(_ text: String) -> Bool {
        defer { assistantRefresh() }
        let session: AssistantSession
        switch assistantSession() {
        case .failure(let error):
            assistantTranscript.take(["type": "error", "message": error.message])
            return false
        case .success(let live):
            session = live
        }
        guard session.phase == .idle, session.send(text) else { return false }
        assistantTranscript.person(text)
        return true
    }

    func assistantStop() {
        assistant?.cancel()
        assistantRefresh()
    }

    func assistantAnswer(_ allowed: Bool) {
        assistant?.answer(allowed)
        assistantRefresh()
    }

    /// Clear: the conversation ends and its transcript goes; the next message
    /// starts a new one.
    func assistantClear() {
        assistant?.close()
        assistant = nil
        assistantTranscript.clear()
        assistantRefresh()
    }

    /// View ▸ Assistant ⌃⌘A: the inspector shown, the Assistant tab picked,
    /// the composer focused.
    @objc func showAssistant(_ sender: Any?) {
        if inspectorContainer.isHidden { toggleInspector(sender) }
        inspector?.select(.assistant)
        assistantView?.focusComposer()
    }

    /// Settings' Assistant pane saved or removed the key, or changed the
    /// model. A session keeps what it was opened with, so the conversation
    /// ends here and the next message opens a new one (as in Rasterize).
    @objc func assistantConfigurationDidChange(_ note: Notification) {
        assistantView?.show(hasKey: assistantHasKey)
        if let session = assistant {
            session.close()
            assistant = nil
            let change = note.userInfo?[AssistantConfiguration.changeKey] as? String
            assistantTranscript.endConversation(
                note: change == "model"
                    ? "The model is now \(AssistantConfiguration.model()); the next message "
                        + "starts a new conversation."
                    : "The API key changed; the next message starts a new conversation.")
        }
        assistantRefresh()
    }

    /// Whether a key would open a session: the store, then the environment
    /// (AI-8).
    private var assistantHasKey: Bool {
        AssistantConfiguration.credential(store: AssistantConfiguration.store()) != nil
    }
}
