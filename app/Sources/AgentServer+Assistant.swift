import AppKit

#if REELCUT_DEV_TOOLS
/// `assistant_send` and `assistant_answer` — dev tools (road map 12 A1, spec
/// §11 V-1..V-2): type a message into a project window's assistant session
/// and wait for its turn, and answer the ask-first question it stopped on
/// (Allow, Deny) or Stop it. They are how a proof drives a real turn against
/// the stand-in server; the person's own door is A2's Assistant tab, and
/// with `pane` both go through that tab's own composer, Send, Allow and Deny
/// (road map 12 A2), refused by name when the control is not on screen.
///
/// **Both run on the SERVER thread** (`devOffMainTools`), under the lane's
/// lock, which `serve` took on this thread. The wait RELEASES it
/// (`AgentLane.releasingLock`): the turn's tool calls go through the lane's
/// `submit` and need the lock, so waiting while holding it would deadlock.
/// The target is resolved in the first `onMain`, BEFORE the release, never
/// inside it, where an assistant call may be holding `callDocument`.
///
/// **They answer when the turn is no longer busy** — finished, stopped on a
/// question, closed — or at `timeout` ("running"). Never the key, never the
/// model (AI-8, AI-11): `events` are the session's own, which carry neither.
/// With `stop_after` the wait presses Stop once that many seconds have passed
/// with the turn still running (`editor.assistantStop()`, the tab's forward;
/// spec §11 AI-16), and `stopped_ms` says when.
extension AgentServer {

    private static let assistantTimeoutDefault = 120.0

    func assistantSend(_ a: [String: Any]) throws -> String {
        guard let text = try stringArg(a, "text") else {
            throw ToolError(message: "Missing required argument: text")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolError(message: "text must not be empty.")
        }
        let timeout = try assistantTimeout(a)
        let stopAfter = try assistantStopAfter(a, timeout)
        let pane = try boolArg(a, "pane") ?? false
        let (session, project, cursor, editor) = try onMain {
            () throws -> (AssistantSession, Any, Int, EditorViewController) in
            let (editor, project) = try self.assistantEditor(a)
            // With `pane`, the tab must be showing BEFORE anything is opened.
            let view = try pane ? Self.visibleAssistantView(editor, "composer", \.composer) : nil
            let session: AssistantSession
            switch editor.assistantSession() {
            case .failure(let error): throw ToolError(message: error.message)
            case .success(let live): session = live
            }
            guard session.phase == .idle else { throw ToolError(message: Self.midTurn) }
            let cursor = session.events.count
            if let view {
                try Self.sendThroughComposer(view, text, editor)
            } else if !editor.assistantSend(text) {
                throw ToolError(
                    message: "The assistant helper is not running; assistant_send again starts "
                        + "a new conversation.")
            }
            return (session, project, cursor, editor)
        }
        return try jsonResult(
            assistantWait(session, project, cursor, timeout, stopAfter: stopAfter, editor: editor))
    }

    func assistantAnswer(_ a: [String: Any]) throws -> String {
        guard let raw = try stringArg(a, "answer") else {
            throw ToolError(message: "Missing required argument: answer")
        }
        guard ["allow", "deny", "stop"].contains(raw) else {
            throw ToolError(message: "answer must be allow, deny or stop (got \"\(raw)\").")
        }
        let timeout = try assistantTimeout(a)
        let stopAfter = try assistantStopAfter(a, timeout)
        guard stopAfter == nil || raw == "allow" else {
            throw ToolError(message: "stop_after applies only with answer \"allow\".")
        }
        let pane = try boolArg(a, "pane") ?? false
        let (session, project, cursor, editor) = try onMain {
            () throws -> (AssistantSession, Any, Int, EditorViewController) in
            let (editor, project) = try self.assistantEditor(a)
            guard let session = editor.assistant else {
                throw ToolError(
                    message: "This window has no assistant conversation: assistant_send starts "
                        + "one.")
            }
            let cursor = session.events.count
            if raw == "stop" {
                guard session.phase == .busy || session.phase == .asking else {
                    throw ToolError(message: "No turn is running, so there is nothing to stop.")
                }
                if pane {
                    try Self.stopThroughPane(editor, session)
                } else {
                    session.cancel()
                }
            } else if pane {
                guard session.pendingQuestion != nil else {
                    throw ToolError(message: Self.noQuestion)
                }
                try Self.answerThroughPane(editor, session, allow: raw == "allow")
            } else {
                guard session.answer(raw == "allow") else {
                    throw ToolError(message: Self.noQuestion)
                }
            }
            return (session, project, cursor, editor)
        }
        return try jsonResult(
            assistantWait(session, project, cursor, timeout, stopAfter: stopAfter, editor: editor))
    }

    private static let noQuestion =
        "No question is pending: allow and deny answer the assistant's ask-first question."

    private static let midTurn =
        "The assistant is in the middle of a turn: assistant_answer answers its question or "
        + "stops it."

    // MARK: - Through the pane

    /// The Assistant tab's view, when `control` (and Send) is in a window
    /// and not hidden; else refused by name, changing nothing. Main thread.
    private static func visibleAssistantView(
        _ editor: EditorViewController, _ name: String,
        _ control: KeyPath<AssistantView, some NSView>
    ) throws -> AssistantView {
        func onScreen(_ view: NSView) -> Bool {
            view.window != nil && !view.isHiddenOrHasHiddenAncestor
        }
        guard let view = editor.assistantView, onScreen(view[keyPath: control]),
            name == "Allow" || name == "Deny" || onScreen(view.sendButton)
        else {
            throw ToolError(
                message: "The Assistant tab's \(name) is not on screen: "
                    + "select_inspector_tab {tab: \"assistant\"} first.")
        }
        return view
    }

    /// The composer set to `text` (any marked text committed first) and Send
    /// clicked, as the person would. Refused when the composer still holds
    /// the text after.
    private static func sendThroughComposer(
        _ view: AssistantView, _ text: String, _ editor: EditorViewController
    ) throws {
        if view.composer.hasMarkedText() { view.composer.unmarkText() }
        view.composer.string = text
        editor.assistantRefresh()
        view.sendButton.performClick(nil)
        guard view.composer.string != text else {
            throw ToolError(
                message: "The Assistant tab's Send did not take the message, so nothing was "
                    + "sent.")
        }
    }

    /// Allow or Deny through the control's own `mouseDown`, at its centre.
    private static func answerThroughPane(
        _ editor: EditorViewController, _ session: AssistantSession, allow: Bool
    ) throws {
        editor.assistantRefresh()
        let name = allow ? "Allow" : "Deny"
        let view = try visibleAssistantView(
            editor, name, allow ? \AssistantView.allowButton : \AssistantView.denyButton)
        let control: NSView = allow ? view.allowButton : view.denyButton
        let centre = control.convert(
            NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
        guard let window = control.window,
            let event = NSEvent.mouseEvent(
                with: .leftMouseDown, location: centre, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1)
        else {
            throw ToolError(message: "Could not make a click for the \(name) button.")
        }
        control.mouseDown(with: event)
        guard session.pendingQuestion == nil else {
            throw ToolError(message: "The \(name) button did not answer the question.")
        }
    }

    /// Stop: a click on Send while it reads Stop.
    private static func stopThroughPane(
        _ editor: EditorViewController, _ session: AssistantSession
    ) throws {
        editor.assistantRefresh()
        let view = try visibleAssistantView(editor, "Stop button", \.sendButton)
        guard view.sendButton.title == "Stop" else {
            throw ToolError(message: "The Assistant tab's Send does not read Stop.")
        }
        view.sendButton.performClick(nil)
    }

    /// `timeout`, seconds: 120 when absent, else 1…600.
    private func assistantTimeout(_ a: [String: Any]) throws -> Double {
        guard let value = try doubleArg(a, "timeout") else { return Self.assistantTimeoutDefault }
        guard value >= 1, value <= 600 else {
            let shown = Int(exactly: value).map(String.init) ?? String(value)
            throw ToolError(
                message: "timeout must be between 1 and 600 seconds (got \(shown)).")
        }
        return value
    }

    /// `stop_after`, seconds: nil when absent, else 0.1…600 and under `timeout`.
    private func assistantStopAfter(_ a: [String: Any], _ timeout: Double) throws -> Double? {
        guard let value = try doubleArg(a, "stop_after") else { return nil }
        guard value >= 0.1, value <= 600, value < timeout else {
            let shown = Int(exactly: value).map(String.init) ?? String(value)
            throw ToolError(
                message: "stop_after must be between 0.1 and 600 seconds and less than timeout "
                    + "(got \(shown)).")
        }
        return value
    }

    /// The target's editor and its path (or null). Main thread.
    private func assistantEditor(_ a: [String: Any]) throws -> (EditorViewController, Any) {
        let document = try target(a)
        guard let editor = editor(document) else {
            let name = Self.path(of: document) ?? document.displayName ?? "Untitled"
            throw ToolError(
                message: "The project \(name) has no window: its assistant lives in its editor "
                    + "window.")
        }
        return (editor, UISnapshot.orNull(Self.path(of: document)))
    }

    /// Waits, WITHOUT the lane's lock, until the session is not busy or
    /// `timeout` passes, reading its phase on main every 50 ms; once
    /// `stopAfter` has passed with the phase busy or asking, it presses Stop,
    /// once. Then answers what happened since `cursor`.
    private func assistantWait(
        _ session: AssistantSession, _ project: Any, _ cursor: Int, _ timeout: Double,
        stopAfter: Double?, editor: EditorViewController
    ) -> [String: Any] {
        let started = Date()
        var stopped: Int?
        AgentLane.shared.releasingLock {
            while true {
                let elapsed = Date().timeIntervalSince(started)
                let phase = onMain { session.phase }
                if stopped == nil, let stopAfter, elapsed >= stopAfter,
                    phase == .busy || phase == .asking
                {
                    stopped = Int((elapsed * 1000).rounded())
                    onMain { editor.assistantStop() }
                    continue
                }
                guard phase == .busy, elapsed < timeout else { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        let waited = Int((Date().timeIntervalSince(started) * 1000).rounded())
        return onMain { Self.assistantReply(session, project, cursor, waited, stopped) }
    }

    /// The tools' answer. Main thread.
    private static func assistantReply(
        _ session: AssistantSession, _ project: Any, _ cursor: Int, _ waited: Int,
        _ stopped: Int?
    ) -> [String: Any] {
        let state: String
        switch session.phase {
        case .idle: state = "finished"
        case .asking: state = "asking"
        case .closed: state = "closed"
        case .busy: state = "running"
        }
        let fresh = session.events.count >= cursor ? Array(session.events[cursor...]) : []
        let text = fresh.filter { $0["type"] as? String == "text_delta" }
            .compactMap { $0["text"] as? String }.joined()
        let events = fresh.filter {
            let type = $0["type"] as? String
            return type != "text_delta" && type != "progress_delta"
        }.map(AssistantSpend.toolView)
        var question: Any = NSNull()
        if let asked = session.pendingQuestion {
            question = [
                "tool": asked.tool, "path": UISnapshot.orNull(asked.path),
                "exists": asked.exists, "sentence": asked.sentence,
            ]
        }
        return [
            "ok": true, "project": project, "state": state, "question": question,
            "text": text, "events": events, "waited_ms": waited,
            "stopped_ms": stopped.map { $0 as Any } ?? NSNull(),
        ]
    }

    // MARK: - Catalog

    func assistantSendTool() -> [String: Any] {
        tool(
            "assistant_send",
            "DEV TOOL (absent from Distribution builds). Type a message into a project "
                + "window's assistant conversation, as the Assistant tab's field would, and "
                + "wait for the turn: it answers once the turn has finished, stopped on an "
                + "ask-first question (state asking, with the question), or the conversation "
                + "closed; past timeout it answers state running. The first call opens the "
                + "window's session (the person's key and model, never an argument). Answers "
                + "the streamed text joined, and every event since the call but the text and "
                + "progress deltas, and stopped_ms (null unless stop_after pressed Stop). "
                + "Refused while a turn is running: assistant_answer answers or stops it.",
            [
                "text": ["type": "string", "description": "The message, as the person types it."],
                "timeout": [
                    "type": "number",
                    "description": "Seconds to wait for the turn, 1 to 600 (default 120).",
                ],
                "pane": [
                    "type": "boolean",
                    "description": "Type into the Assistant tab's composer and click its Send "
                        + "instead (default false). Refused, opening nothing, unless the tab "
                        + "is showing (select_inspector_tab {tab: \"assistant\"}).",
                ],
                "stop_after": [
                    "type": "number",
                    "description": "Press Stop, once, this many seconds into the wait if the "
                        + "turn is still running, 0.1 to 600 and less than timeout (absent: "
                        + "never).",
                ],
            ], required: ["text"])
    }

    func assistantAnswerTool() -> [String: Any] {
        tool(
            "assistant_answer",
            "DEV TOOL (absent from Distribution builds). Answer the question a project "
                + "window's assistant stopped on — allow runs the ask-first call, deny answers "
                + "it \"The person declined: …\" — or stop the running turn, which declines a "
                + "pending question and cancels the calls not yet run. Then waits and answers "
                + "as assistant_send does. Refused, changing nothing: allow or deny with no "
                + "question pending, stop with no turn running, stop_after with any answer but "
                + "allow, and a window with no conversation.",
            [
                "answer": [
                    "type": "string", "enum": ["allow", "deny", "stop"],
                    "description": "allow, deny, or stop.",
                ],
                "timeout": [
                    "type": "number",
                    "description": "Seconds to wait for the turn, 1 to 600 (default 120).",
                ],
                "pane": [
                    "type": "boolean",
                    "description": "Answer through the Assistant tab's own Allow and Deny "
                        + "buttons, or its Send while it reads Stop (default false). Refused, "
                        + "changing nothing, when the control is not on screen.",
                ],
                "stop_after": [
                    "type": "number",
                    "description": "Press Stop, once, this many seconds into the wait if the "
                        + "turn is still running, 0.1 to 600 and less than timeout (absent: "
                        + "never); only with answer allow.",
                ],
            ], required: ["answer"])
    }
}
#endif
