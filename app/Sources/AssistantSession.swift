import AppKit

/// Where a session is: `closed` > `asking` > `busy` > `idle`, the first that
/// holds. Main only.
enum AssistantPhase: String {
    case idle, busy, asking, closed
}

/// Why a session could not be opened, in the sentence a caller shows as is.
struct AssistantOpenError: Error {
    let message: String
}

/// One window's assistant conversation (spec §11 AI-4), run by the helper in
/// `Contents/Helpers` (AI-1): Rasterize's `AssistantHelperSession`, ported.
/// JSON lines over the helper's stdin and stdout (`agent/src/protocol.ts`):
/// the helper streams events and asks for tool calls, and each call goes
/// through `AgentLane.submit` (AI-2), never `AgentServer.execute`, pinned to
/// this window's project (AI-5). Road map 12 A1.
///
/// **Main only**, unless a comment says otherwise; helper lines and the
/// lane's completions are hopped there.
///
/// **Every question is answered exactly once** (AI-7). The lane's `ask` puts
/// an ask-first call to `askFirst` on main and waits with no timeout, holding
/// its window's queue on the lane, so a question left unanswered stops this
/// window's assistant (#148). The person answers it (`answer`); Stop, close, the
/// helper's death and `deinit` decline it; and a question that reaches a
/// session already closed, cancelling or released is declined at once.
///
/// **The key** (AI-8, R6-12) is in `configure` on stdin and nowhere else. The
/// helper's environment is exactly `HOME`, `TMPDIR` and `PATH`.
final class AssistantSession {
    private(set) weak var document: ProjectDocument?

    /// Every helper event but `tool_request`, and the session's own, in
    /// order. Append-only.
    private(set) var events: [[String: Any]] = []

    /// The ask-first question waiting for the person, if any.
    private(set) var pendingQuestion: AssistantQuestion?

    var phase: AssistantPhase {
        if closed { return .closed }
        if pendingQuestion != nil { return .asking }
        return busy ? .busy : .idle
    }

    /// Each appended event, on main (A2's pane).
    var onEvent: (([String: Any]) -> Void)?

    private let process = Process()
    private let toHelper: Pipe
    private let fromHelper = Pipe()
    /// Every write to the helper, in order, off main: a result carrying a
    /// render can be more than a pipe buffer holds.
    private let writeQueue = DispatchQueue(label: "com.kgalligan.reelcut.assistant.write")
    private let input: HelperInput
    /// Touched only on the readability handler's thread.
    private var lineBuffer = Data()
    private var busy = false, cancelRequested = false, closed = false
    private var pendingReply: ((Bool) -> Void)?
    /// The helper's tool requests not yet handed to the lane, oldest first.
    private var toolQueue: [[String: Any]] = []
    private var toolRunning = false
    /// The running call's token, cancelled by Stop (AI-16).
    private var runningCall: AgentCallCancel?

    static let cancelledResult =
        #"{"content":[{"type":"text","text":"Cancelled by the user."}],"isError":true}"#

    private init(document: ProjectDocument) {
        self.document = document
        let pipe = Pipe()
        toHelper = pipe
        input = HelperInput(pipe.fileHandleForWriting)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AssistantSession does not support NSCoder")
    }

    deinit {
        pendingReply?(false)
        pendingReply = nil
        fromHelper.fileHandleForReading.readabilityHandler = nil  // a session never closed
        let input = self.input
        writeQueue.async { input.close() }
    }

    // MARK: - Opening

    /// The helper, started and configured for `document`. Main only. Each
    /// failure is answered in its own sentence, in this order.
    static func open(document: ProjectDocument) -> Result<AssistantSession, AssistantOpenError> {
        assert(Thread.isMainThread)
        func failure(_ message: String) -> Result<AssistantSession, AssistantOpenError> {
            .failure(AssistantOpenError(message: message))
        }
        let base: URL?
        do {
            base = try AssistantConfiguration.baseURL()
        } catch {
            return failure(error.localizedDescription)
        }
        let store = AssistantConfiguration.store()
        guard let key = AssistantConfiguration.credential(store: store) else {
            return failure(
                "No Anthropic API key is set. The assistant uses the person's own key (spec "
                    + "§11 AI-8): the anthropic-key file in Reelcut's Application Support "
                    + "folder, or ANTHROPIC_API_KEY.")
        }
        // Read, never prepared here (AI-3): a launch that skipped
        // `prepareAtLaunch()` must refuse the session, not repair itself.
        guard let catalog = AgentServer.shared.preparedCatalog,
            let tools = (try? JSONSerialization.jsonObject(with: Data(catalog.utf8)))
                as? [[String: Any]]
        else {
            return failure(
                "The tool catalog was not prepared at launch (spec §11 AI-3), so the assistant "
                    + "cannot start.")
        }
        let executable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/reelcut-agent")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            return failure("The assistant helper is not in this build.")
        }
        var configure: [String: Any] = [
            "type": "configure", "api_key": key,
            "model": AssistantConfiguration.model(), "system": AssistantPrompt.system,
            "tools": AssistantToolTable.assistantCatalog(tools),
            "core_tools": AssistantPrompt.coreTools,
            "search_guide": AssistantPrompt.searchGuide,
            "compaction_instructions": AssistantPrompt.compactionInstructions,
            "settings": AssistantConfiguration.settingsJSON,
        ].merging(AssistantSpend.configureFields()) { _, new in new }
        if let base { configure["api_base"] = base.absoluteString }

        let session = AssistantSession(document: document)
        let process = session.process
        process.executableURL = executable
        process.standardInput = session.toHelper
        process.standardOutput = session.fromHelper
        process.environment = [
            "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory(), "PATH": "/usr/bin:/bin",
        ]
        // A write after the helper has exited fails rather than raise SIGPIPE.
        _ = fcntl(session.toHelper.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        session.fromHelper.fileHandleForReading.readabilityHandler = { [weak session] handle in
            session?.consume(handle.availableData)
        }
        process.terminationHandler = { [weak session] _ in
            DispatchQueue.main.async { session?.helperExited() }
        }
        do {
            try process.run()
        } catch {
            session.fromHelper.fileHandleForReading.readabilityHandler = nil
            return failure("Could not start the assistant helper: \(error.localizedDescription)")
        }
        session.write(configure)
        return .success(session)
    }

    // MARK: - The person's side

    /// Starts a turn, `text` behind the window's live context (AI-15). Only
    /// while idle and the helper runs; `busy` the moment this returns true.
    @discardableResult
    func send(_ text: String) -> Bool {
        guard phase == .idle, process.isRunning else { return false }
        busy = true
        cancelRequested = false
        write(["type": "send", "text": AssistantPrompt.message(text, document: document)])
        return true
    }

    /// Allow (`true`) or Deny (`false`) for the pending question. False when
    /// nothing is pending.
    @discardableResult
    func answer(_ allowed: Bool) -> Bool {
        guard let reply = pendingReply else { return false }
        pendingReply = nil
        pendingQuestion = nil
        append(["type": "answer", "allowed": allowed, "by": "person"])
        reply(allowed)
        return true
    }

    /// Stop: the helper aborts its request, a pending question is declined,
    /// and every call not yet run answers "Cancelled by the user.". Only
    /// while busy or asking. A running `export` or on-device `transcribe` is
    /// cancelled through its token; any other running call finishes (AI-16).
    func cancel() {
        guard phase == .busy || phase == .asking else { return }
        cancelRequested = true
        write(["type": "cancel"])
        decline(by: "stop")
        runningCall?.cancel()
        for callID in toolQueue.compactMap({ $0["call_id"] as? String }) {
            writeResult(callID, Self.cancelledResult)
        }
        toolQueue = []
    }

    /// Idempotent. Closing stdin ends the helper; one still running 2 s later
    /// is terminated.
    func close() {
        guard !closed else { return }
        closed = true
        decline(by: "close")
        toolQueue = []
        fromHelper.fileHandleForReading.readabilityHandler = nil
        closeInput()
    }

    // MARK: - Helper output

    /// Splits the stream into lines on the handler's thread; each line is
    /// handled on main.
    private func consume(_ data: Data) {
        if data.isEmpty { return }  // EOF; termination is reported separately
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = lineBuffer[lineBuffer.startIndex..<newline]
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            guard
                let object = (try? JSONSerialization.jsonObject(with: Data(line)))
                    as? [String: Any]
            else { continue }
            DispatchQueue.main.async { [weak self] in self?.handle(object) }
        }
    }

    private func handle(_ event: [String: Any]) {
        guard !closed else { return }
        switch event["type"] as? String {
        case "tool_request":
            enqueue(event)
            return
        case "turn_started":
            // `cancelRequested` is kept: a Stop between `send` and here holds.
            busy = true
        case "turn_finished":
            busy = false
        default:
            break
        }
        append(event)
    }

    private func append(_ event: [String: Any]) {
        events.append(event)
        onEvent?(event)
    }

    private func helperExited() {
        guard !closed else { return }
        closed = true
        decline(by: "helper")
        toolQueue = []
        fromHelper.fileHandleForReading.readabilityHandler = nil
        closeInput()
        append([
            "type": "error",
            "message": "The assistant helper stopped. Clear the conversation to start a new one.",
        ])
        if busy {
            busy = false
            append(["type": "turn_finished"])
        }
    }

    // MARK: - Tool calls, one at a time, through the lane

    private func enqueue(_ request: [String: Any]) {
        guard let callID = request["call_id"] as? String, request["name"] is String else { return }
        if cancelRequested {
            writeResult(callID, Self.cancelledResult)
            return
        }
        toolQueue.append(request)
        runNextTool()
    }

    private func runNextTool() {
        guard !closed, !toolRunning, !toolQueue.isEmpty else { return }
        let request = toolQueue.removeFirst()
        guard let callID = request["call_id"] as? String, let name = request["name"] as? String
        else { return runNextTool() }
        let arguments = request["arguments_json"] as? String ?? "{}"
        guard let document else {
            writeResult(callID, Self.errorResult("The assistant's project is no longer open."))
            return runNextTool()
        }
        toolRunning = true
        let stop = AgentCallCancel()
        runningCall = stop
        AgentLane.shared.submit(
            tool: name, argumentsJSON: arguments, document: document, cancel: stop,
            askFirst: { [weak self] question, reply in
                // Released, closed or stopping: declined here, never dropped.
                guard let self, !self.closed, !self.cancelRequested else {
                    reply(false)
                    return
                }
                self.ask(question, reply)
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.toolRunning = false
                    self.runningCall = nil
                    if !self.closed { self.writeResult(callID, result) }
                    self.runNextTool()
                }
            })
    }

    private func ask(_ question: AssistantQuestion, _ reply: @escaping (Bool) -> Void) {
        decline(by: "replaced")  // never pending: the lane asks one at a time
        pendingQuestion = question
        pendingReply = reply
        append([
            "type": "question", "tool": question.tool,
            "path": question.path.map { $0 as Any } ?? NSNull(),
            "exists": question.exists, "sentence": question.sentence,
        ])
    }

    /// Declines the pending question, if any, naming who did.
    private func decline(by who: String) {
        guard let reply = pendingReply else { return }
        pendingReply = nil
        pendingQuestion = nil
        append(["type": "answer", "allowed": false, "by": who])
        reply(false)
    }

    private static func errorResult(_ message: String) -> String {
        let content: [[String: Any]] = [["type": "text", "text": message]]
        return (try? AgentServer.shared.callResult(content: content, isError: true))
            ?? #"{"content":[{"type":"text","text":"tool failed"}],"isError":true}"#
    }

    // MARK: - Writing

    /// The result is already JSON: spliced in verbatim, never re-encoded.
    private func writeResult(_ callID: String, _ result: String) {
        guard let idJSON = try? JSONSerialization.data(withJSONObject: [callID]),
            let idArray = String(data: idJSON, encoding: .utf8)
        else { return }
        let quotedID = idArray.dropFirst().dropLast()
        writeLine(#"{"type":"tool_result","call_id":\#(quotedID),"result":\#(result)}"#)
    }

    private func write(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
            let line = String(data: data, encoding: .utf8)
        else { return }
        writeLine(line)
    }

    private func writeLine(_ line: String) {
        let input = self.input
        let data = Data((line + "\n").utf8)
        writeQueue.async { input.write(data) }
    }

    /// Closes stdin after every queued write; terminates a helper still up 2 s on.
    private func closeInput() {
        let process = self.process
        let input = self.input
        writeQueue.async {
            input.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}
