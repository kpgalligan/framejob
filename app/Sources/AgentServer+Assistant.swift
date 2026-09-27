import AppKit

#if REELCUT_DEV_TOOLS
/// `assistant_send` and `assistant_answer` — dev tools (road map 12 A1, spec
/// §11 V-1..V-2): type a message into a project window's assistant session
/// and wait for its turn, and answer the ask-first question it stopped on
/// (Allow, Deny) or Stop it. They are how a proof drives a real turn against
/// the stand-in server; the person's own door is A2's pane.
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
        let (session, project, cursor) = try onMain {
            () throws -> (AssistantSession, Any, Int) in
            let (editor, project) = try self.assistantEditor(a)
            let session: AssistantSession
            switch editor.assistantSession() {
            case .failure(let error): throw ToolError(message: error.message)
            case .success(let live): session = live
            }
            guard session.phase == .idle else { throw ToolError(message: Self.midTurn) }
            let cursor = session.events.count
            guard session.send(text) else {
                throw ToolError(
                    message: "The assistant helper is not running; assistant_send again starts "
                        + "a new conversation.")
            }
            return (session, project, cursor)
        }
        return try jsonResult(assistantWait(session, project, cursor, timeout))
    }

    func assistantAnswer(_ a: [String: Any]) throws -> String {
        guard let raw = try stringArg(a, "answer") else {
            throw ToolError(message: "Missing required argument: answer")
        }
        guard ["allow", "deny", "stop"].contains(raw) else {
            throw ToolError(message: "answer must be allow, deny or stop (got \"\(raw)\").")
        }
        let timeout = try assistantTimeout(a)
        let (session, project, cursor) = try onMain {
            () throws -> (AssistantSession, Any, Int) in
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
                session.cancel()
            } else {
                guard session.answer(raw == "allow") else {
                    throw ToolError(
                        message: "No question is pending: allow and deny answer the "
                            + "assistant's ask-first question.")
                }
            }
            return (session, project, cursor)
        }
        return try jsonResult(assistantWait(session, project, cursor, timeout))
    }

    private static let midTurn =
        "The assistant is in the middle of a turn: assistant_answer answers its question or "
        + "stops it."

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
    /// `timeout` passes, reading its phase on main every 50 ms; then answers
    /// what happened since `cursor`.
    private func assistantWait(
        _ session: AssistantSession, _ project: Any, _ cursor: Int, _ timeout: Double
    ) -> [String: Any] {
        let started = Date()
        AgentLane.shared.releasingLock {
            while onMain({ session.phase == .busy }),
                Date().timeIntervalSince(started) < timeout
            {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        let waited = Int((Date().timeIntervalSince(started) * 1000).rounded())
        return onMain { Self.assistantReply(session, project, cursor, waited) }
    }

    /// The tools' answer. Main thread.
    private static func assistantReply(
        _ session: AssistantSession, _ project: Any, _ cursor: Int, _ waited: Int
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
        }
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
                + "progress deltas. Refused while a turn is running: assistant_answer answers "
                + "or stops it.",
            [
                "text": ["type": "string", "description": "The message, as the person types it."],
                "timeout": [
                    "type": "number",
                    "description": "Seconds to wait for the turn, 1 to 600 (default 120).",
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
                + "question pending, stop with no turn running, and a window with no "
                + "conversation.",
            [
                "answer": [
                    "type": "string", "enum": ["allow", "deny", "stop"],
                    "description": "allow, deny, or stop.",
                ],
                "timeout": [
                    "type": "number",
                    "description": "Seconds to wait for the turn, 1 to 600 (default 120).",
                ],
            ], required: ["answer"])
    }
}
#endif
