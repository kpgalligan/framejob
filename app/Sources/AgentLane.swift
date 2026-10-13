import AppKit

// MARK: - The agent lane: one lock around every tool call, from every caller

/// The ask-first hook the assistant's session supplies (spec §11 AI-7): it is
/// handed the question on the main thread and answers once, Allow (`true`) or
/// Deny (`false`), from any thread.
typealias AssistantAskFirst = (AssistantQuestion, @escaping (Bool) -> Void) -> Void

/// Every tool call goes through here: the MCP trampoline (`serve`) and the
/// assistant's session (`submit`). Road map 12 A1; spec §11 AI-2, AI-3, AI-5,
/// AI-7 and AI-12.
///
/// **The lock.** One `NSLock` admits one call at a time, which is what keeps
/// `AgentServer.callScope` and `callDocument` race-free now that there are two
/// callers. It is never taken on main (AI-2): an `offMainTools` member holding
/// it waits for main, so a main thread waiting on it would deadlock.
/// `onMainWhenIdle` never locks, `submit` never blocks its caller, and nothing
/// on main waits on the lane.
///
/// **The gesture wait (AI-12, #144).** A call that reaches main while any
/// open document is mid-gesture waits for mouse-up, then runs: before this,
/// a call run between two ticks of a drag answered ok and was then undone by
/// the next tick. Every `onMain` hop is this wait, so it covers the off-main
/// tools' hops too. Risk accepted: the call, and the lock with it, waits as
/// long as the mouse is held down.
///
/// **The queues (#148).** `submit` runs on its document's serial queue, one
/// per document with a call outstanding, so each window's calls are answered
/// in order, its caller never waits, and a question pending in one window
/// holds no other window's calls. `queuesLock` guards only the dictionary and
/// is never held across a call, a wait or a completion; a document's queue is
/// dropped once none of its calls is outstanding, so a new one is made only
/// when there is nothing left to keep in order.
final class AgentLane {
    static let shared = AgentLane()

    private let lock = NSLock()
    private let queuesLock = NSLock()
    private var queues: [ObjectIdentifier: LaneQueue] = [:]
    private let server: AgentServer

    /// The token of the `submit` call running now, nil in `serve` (spec §11
    /// AI-16). Written only in `answer`, under `lock`, and cleared before it
    /// is released, so a handler reads it on its own (lane) thread before any
    /// `onMain` hop and links its own cancel with `onCancel`.
    private(set) var callCancel: AgentCallCancel?

    private init() {
        server = AgentServer.shared
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AgentLane does not support NSCoder")
    }

    // MARK: - Launch

    /// The catalog, the gate and the parity check, once, from `main.swift`
    /// before `NSApplicationMain` (AI-3): the assistant's calls need the gate
    /// in a launch that never starts the MCP server.
    static func prepareAtLaunch() {
        do {
            try AgentServer.shared.prepareCatalog()
        } catch {
            NSLog("Frame Job: %@", error.localizedDescription)
        }
    }

    // MARK: - Callers

    /// An MCP call, on the server thread, answered synchronously. It never
    /// pins a document and never asks anyone anything (AI-7: an MCP caller is
    /// never asked).
    func serve(tool: String, argumentsJSON: String) -> String {
        guard !Thread.isMainThread else {
            // The core header says the server thread calls this, never main.
            assertionFailure("AgentLane.serve was called on the main thread")
            return server.execute(tool: tool, argumentsJSON: argumentsJSON)
        }
        lock.lock()
        defer { lock.unlock() }
        return route(tool, argumentsJSON)
    }

    /// An assistant call, pinned to `document` (AI-5). Returns at once;
    /// `completion` runs exactly once, on `document`'s serial queue (#148).
    /// A withheld tool is refused, and an ask-first one is put to `askFirst`
    /// BEFORE the lock, so a pending question never holds up an MCP caller,
    /// nor another document's calls. A call whose `cancel` is cancelled when
    /// it takes the lock answers "Cancelled by the user." and never runs (AI-16).
    func submit(
        tool: String, argumentsJSON: String, document: ProjectDocument,
        cancel: AgentCallCancel? = nil,
        askFirst: @escaping AssistantAskFirst,
        completion: @escaping (String) -> Void
    ) {
        let key = ObjectIdentifier(document)
        enter(key).async { [self] in
            completion(answer(tool, argumentsJSON, document, cancel, askFirst))
            leave(key)
        }
    }

    /// `key`'s queue, made on first use, with one more call outstanding.
    private func enter(_ key: ObjectIdentifier) -> DispatchQueue {
        queuesLock.lock()
        defer { queuesLock.unlock() }
        var entry =
            queues[key]
            ?? LaneQueue(
                queue: DispatchQueue(label: "com.kgalligan.framejob.agent-lane"), calls: 0)
        entry.calls += 1
        queues[key] = entry
        return entry.queue
    }

    /// One call fewer outstanding on `key`'s queue; the entry is dropped at 0.
    private func leave(_ key: ObjectIdentifier) {
        queuesLock.lock()
        defer { queuesLock.unlock() }
        guard var entry = queues[key] else { return }
        entry.calls -= 1
        queues[key] = entry.calls > 0 ? entry : nil
    }

    private func answer(
        _ tool: String, _ argumentsJSON: String, _ document: ProjectDocument,
        _ cancel: AgentCallCancel?, _ askFirst: @escaping AssistantAskFirst
    ) -> String {
        let arguments =
            (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8)))
            as? [String: Any] ?? [:]
        if let refusal = AssistantToolTable.refusal(tool: tool, arguments: arguments) {
            return errorResult(refusal)
        }
        if AssistantToolTable.row(for: tool)?.rule == .askFirst {
            let question = DispatchQueue.main.sync {
                AssistantToolTable.question(tool: tool, arguments: arguments, document: document)
            }
            if let question = question, !ask(question, askFirst) {
                return errorResult("The person declined: \(question.sentence).")
            }
        }
        lock.lock()
        defer { lock.unlock() }
        if cancel?.isCancelled == true { return AssistantSession.cancelledResult }
        callCancel = cancel
        defer { callCancel = nil }
        return server.pinning(document) { route(tool, argumentsJSON) }
    }

    /// Puts `question` to the hook on main and waits for its answer here, on
    /// the document's queue, which holds only that document's calls (#148).
    /// The first answer counts.
    private func ask(_ question: AssistantQuestion, _ askFirst: @escaping AssistantAskFirst)
        -> Bool {
        let reply = LaneAnswer()
        DispatchQueue.main.async {
            askFirst(question) { allowed in reply.settle(allowed) }
        }
        return reply.wait()
    }

    /// `execute` in place for an `offMainTools` member, else on main once no
    /// gesture is live. The caller holds the lock.
    private func route(_ tool: String, _ argumentsJSON: String) -> String {
        if AgentServer.offMainTools.contains(tool) {
            return server.execute(tool: tool, argumentsJSON: argumentsJSON)
        }
        return onMainWhenIdle { server.execute(tool: tool, argumentsJSON: argumentsJSON) }
    }

    private func errorResult(_ message: String) -> String {
        let fallback = #"{"content":[{"type":"text","text":"tool failed"}],"isError":true}"#
        let content: [[String: Any]] = [["type": "text", "text": message]]
        return (try? server.callResult(content: content, isError: true)) ?? fallback
    }

    /// `body` with the lock RELEASED, relocked in a `defer` before this
    /// returns. Its only callers are the two assistant dev tools, which
    /// `serve` runs under the lock on this thread: while one waits for a
    /// turn, the turn's own `submit` calls need the lock.
    func releasingLock<T>(_ body: () throws -> T) rethrows -> T {
        assert(!Thread.isMainThread)
        lock.unlock()
        defer { lock.lock() }
        return try body()
    }

    // MARK: - The gesture wait (AI-12)

    /// On main: `body` in place, with no gesture check, no `main.sync` and no
    /// sleep (what `onMain` always did there; a gesture can only end on main,
    /// so a wait here would never end). Off main: `body` on main once no open
    /// document is mid-gesture, retried every 20 ms with no bound. Never locks.
    func onMainWhenIdle<T>(_ body: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try body() }
        while true {
            let outcome: T? = try DispatchQueue.main.sync {
                Self.gestureInProgress() ? nil : try body()
            }
            if let outcome = outcome { return outcome }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    /// Main only: whether any open project is in a live gesture (a timeline,
    /// canvas or inspector-slider drag).
    static func gestureInProgress() -> Bool {
        assert(Thread.isMainThread)
        return AgentServer.shared.openProjects().contains { $0.isLiveEditing }
    }
}

/// Stop's reach into the call it is running (spec §11 AI-16): the session
/// makes one per call and cancels it on Stop; the lane never starts a call
/// whose token is already cancelled, and a long-running handler links its own
/// cancel to it with `onCancel`. Only the first `cancel()` runs the handlers.
final class AgentCallCancel {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [() -> Void] = []

    init() {}

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("AgentCallCancel does not support NSCoder")
    }

    /// Any thread.
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Main only. Idempotent; each handler runs once, outside the lock, here.
    func cancel() {
        assert(Thread.isMainThread)
        lock.lock()
        let run = cancelled ? [] : handlers
        cancelled = true
        handlers = []
        lock.unlock()
        run.forEach { $0() }
    }

    /// Any thread. Already cancelled: `handler` runs at once, on this thread.
    func onCancel(_ handler: @escaping () -> Void) {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            handler()
            return
        }
        handlers.append(handler)
        lock.unlock()
    }
}

/// The ask-first answer crossing from main (or wherever the hook replies) to
/// the document's queue on the lane. Only the first `settle` counts.
private final class LaneAnswer {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var value: Bool?

    init() {}

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("LaneAnswer does not support NSCoder")
    }

    func settle(_ allowed: Bool) {
        lock.lock()
        let first = value == nil
        if first { value = allowed }
        lock.unlock()
        if first { semaphore.signal() }
    }

    func wait() -> Bool {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return value ?? false
    }
}

/// One document's serial queue and how many of its calls are outstanding.
private struct LaneQueue {
    let queue: DispatchQueue
    var calls: Int
}

// MARK: - The pinned document (AI-5)

extension AgentServer {
    /// The document an assistant call targets: its own window's project,
    /// always. Main only, from `targetDocument`'s first statement.
    func pinnedTarget(_ pinned: ProjectDocument, _ a: [String: Any]) throws -> ProjectDocument {
        let name = pinned.displayName ?? "Untitled"
        guard openProjects().contains(where: { $0 === pinned }) else {
            throw ToolError(message: "The assistant's project, \(name), is no longer open.")
        }
        guard let wanted = try stringArg(a, "project") else { return pinned }
        // Compared the way `targetDocument` compares an explicit path.
        let path = (wanted as NSString).expandingTildeInPath
        if let open = Self.path(of: pinned),
            open == path || Self.canonical(open) == Self.canonical(wanted)
        {
            return pinned
        }
        throw ToolError(
            message: "The assistant edits its own window's project, \(name); \(wanted) is a "
                + "different project.")
    }
}
