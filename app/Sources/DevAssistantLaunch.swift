import AppKit

#if REELCUT_DEV_TOOLS
/// `-RCDevAssistantSend <text> -RCDevAssistantReport <path>` — a dev-only
/// LAUNCH default (road map 12 A1): one assistant turn in a launch that may
/// have no MCP server at all, which no MCP tool can drive. Once the app has
/// finished launching it opens an untitled project, sends `text` through the
/// editor's own `assistantSession()`, waits (120 s from the send) for the
/// turn to leave `busy`, notes the turn and closes the session (declining a
/// question still pending), reads the project back with `get_project`
/// through the lane pinned to that document and writes one report.
///
/// Both keys are read from the ARGUMENT domain alone
/// (`AssemblyAIConfiguration.argument`), so a persisted default can start
/// nothing. One without the other is one stderr line and nothing else.
///
/// **The report**, written once and atomically at the report path:
/// `{"ok","error"|null,"server_running","state","text","events",
/// "get_project"|null}` — the events without the text and progress deltas,
/// never the key or the model (AI-8, AI-11).
enum DevAssistantLaunch {
    static let sendKey = "RCDevAssistantSend"
    static let reportKey = "RCDevAssistantReport"

    /// Kept for the launch's life: the observer and the turn it runs.
    private static var run: DevAssistantRun?

    /// From `main.swift`, before `NSApplicationMain`.
    static func installIfAsked() {
        let defaults = UserDefaults.standard
        let text = AssemblyAIConfiguration.argument(sendKey, defaults: defaults)
        let report = AssemblyAIConfiguration.argument(reportKey, defaults: defaults)
        guard text != nil || report != nil else { return }
        guard let text, let report else {
            let line = "-\(sendKey) and -\(reportKey) go together; one alone does nothing.\n"
            FileHandle.standardError.write(Data(line.utf8))
            return
        }
        let run = DevAssistantRun(text: text, reportPath: report)
        NotificationCenter.default.addObserver(
            run, selector: #selector(DevAssistantRun.didFinishLaunching(_:)),
            name: NSApplication.didFinishLaunchingNotification, object: nil)
        self.run = run
    }
}

/// One launch-default turn. Main only.
final class DevAssistantRun: NSObject {
    private let text: String
    private let reportPath: String
    private var session: AssistantSession?
    private var timer: Timer?
    private var cursor = 0
    private var sentAt = Date()
    private var reported = false

    private static let wall: TimeInterval = 120

    init(text: String, reportPath: String) {
        self.text = text
        self.reportPath = reportPath
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("DevAssistantRun does not support NSCoder")
    }

    @objc func didFinishLaunching(_ note: Notification) {
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didFinishLaunchingNotification, object: nil)
        let document: ProjectDocument
        do {
            guard
                let made = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
                    as? ProjectDocument
            else { return finish(error: "A new project could not be created.") }
            document = made
        } catch {
            return finish(error: "A new project could not be created: \(error.localizedDescription)")
        }
        guard let editor = AgentServer.shared.editor(document) else {
            return finish(error: "The new project has no editor window.")
        }
        switch editor.assistantSession() {
        case .failure(let error):
            return finish(error: error.message)
        case .success(let live):
            session = live
            cursor = live.events.count
            guard live.send(text) else {
                return finish(error: "The assistant did not take the message.")
            }
        }
        sentAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.poll(document)
        }
    }

    private func poll(_ document: ProjectDocument) {
        guard let session else { return }
        let waiting = session.phase == .busy && Date().timeIntervalSince(sentAt) < Self.wall
        if waiting { return }
        timer?.invalidate()
        timer = nil
        // The turn as it stood, then the close — which declines a pending
        // question and drops the queue — BEFORE `get_project`: the lane's
        // serial queue would otherwise hold it behind that question's wait.
        let captured = capture()
        session.close()
        AgentLane.shared.submit(
            tool: "get_project", argumentsJSON: "{}", document: document,
            askFirst: { _, reply in reply(false) },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    self?.finish(error: nil, project: result, captured: captured)
                }
            })
    }

    /// The session's state, text and events since the send, for the report.
    private func capture() -> [String: Any] {
        guard let session else { return [:] }
        var captured: [String: Any] = [:]
        switch session.phase {
        case .idle: captured["state"] = "finished"
        case .asking: captured["state"] = "asking"
        case .closed: captured["state"] = "closed"
        case .busy: captured["state"] = "running"
        }
        let fresh = session.events.count >= cursor ? Array(session.events[cursor...]) : []
        captured["text"] = fresh.filter { $0["type"] as? String == "text_delta" }
            .compactMap { $0["text"] as? String }.joined()
        captured["events"] = fresh.filter {
            let type = $0["type"] as? String
            return type != "text_delta" && type != "progress_delta"
        }.map(AssistantSpend.toolView)
        return captured
    }

    /// Writes the report once, then closes the session. `captured` is the
    /// turn as `poll` saw it before its close; without it, the turn now.
    private func finish(error: String?, project: String? = nil, captured: [String: Any]? = nil) {
        guard !reported else { return }
        reported = true
        var report: [String: Any] = [
            "ok": error == nil, "error": UISnapshot.orNull(error),
            "server_running": AgentServer.shared.isRunning,
            "state": "none", "text": "", "events": [[String: Any]](),
            "get_project": NSNull(),
        ]
        report.merge(captured ?? capture()) { _, turn in turn }
        if let project { report["get_project"] = Self.projectObject(project) }
        let url = URL(fileURLWithPath: (reportPath as NSString).expandingTildeInPath)
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
        session?.close()
    }

    /// `get_project`'s answer as the object its text holds, else the result
    /// whole, as text.
    private static func projectObject(_ result: String) -> Any {
        guard
            let call = (try? JSONSerialization.jsonObject(with: Data(result.utf8)))
                as? [String: Any],
            call["isError"] as? Bool != true,
            let content = call["content"] as? [[String: Any]],
            let text = content.first?["text"] as? String,
            let object = try? JSONSerialization.jsonObject(with: Data(text.utf8))
        else { return result }
        return object
    }
}
#endif
