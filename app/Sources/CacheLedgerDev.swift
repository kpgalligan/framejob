#if FRAMEJOB_DEV_TOOLS
import Foundation

/// What a proof reads and arms on the cache ledger (spec §11 #552), compiled
/// only under dev tools: per cache folder and WRITER (the name each caller
/// of `CacheLedger.publish` gives), how many publishes found a save of the
/// package in flight and waited it out, and a one-shot GATE that holds a
/// named writer's next publish until a save of that folder is inside its
/// `-RCDevSaveHold`. The dev tool `cache_ledger` answers and arms it
/// (`AgentServer+CacheLedger.swift`).
///
/// **Why a gate and not a clock.** The media passes publish one after
/// another inside one task, so a hold of so many seconds before each publish
/// would put only the first of them into a held save, and which one would
/// depend on decode times. A gate makes the meeting a fact: the writer waits
/// at `arrive` until the save is in its hold, then goes on into `publish`,
/// whose own wait for the save's end is what is being proved.
///
/// **Locks.** One `NSCondition` of its own. `CacheLedger.publish` calls
/// `arrive` before it takes the ledger's lock and `noteWait` after it has
/// released it, so the ledger's rule (under its lock it touches only its own
/// state) stands, and a writer at the gate is not a publication: a save
/// never waits for it.
final class CacheLedgerDev: @unchecked Sendable {
    static let shared = CacheLedgerDev()

    /// A gate's course: `armed` until its writer arrives, `waiting` while it
    /// is held, then how the hold ended.
    enum Gate: String {
        case armed, waiting, save, timeout, disarmed
    }

    /// How long a writer is held at its gate when the tool names no bound.
    static let defaultBound: TimeInterval = 60

    private let condition = NSCondition()
    private var waits: [String: [String: Int]] = [:]
    private var gates: [String: [String: Gate]] = [:]
    private var bounds: [String: TimeInterval] = [:]
    private var holding: [String: Int] = [:]

    private init() {}

    // MARK: - The count

    /// A publish by `writer` in `directory` found a save in flight.
    func noteWait(_ directory: String, _ writer: String) {
        condition.lock()
        waits[directory, default: [:]][writer, default: 0] += 1
        condition.unlock()
    }

    /// Publishes that waited a save out since launch, by writer.
    func saveWaits(in cacheDir: URL) -> [String: Int] {
        condition.lock()
        defer { condition.unlock() }
        return waits[cacheDir.standardizedFileURL.path] ?? [:]
    }

    func saveWaits(in cacheDir: URL, writer: String) -> Int {
        saveWaits(in: cacheDir)[writer] ?? 0
    }

    // MARK: - The gate

    /// Replaces the armed set of `cacheDir`: each name in `writers` is armed
    /// (again, if it had ended), and a gate not named that was armed or
    /// waiting is disarmed, releasing its writer. `seconds` bounds each wait.
    func arm(_ writers: [String], in cacheDir: URL, seconds: TimeInterval) {
        let directory = cacheDir.standardizedFileURL.path
        condition.lock()
        var next = gates[directory] ?? [:]
        for (writer, state) in next where state == .armed || state == .waiting {
            if !writers.contains(writer) { next[writer] = .disarmed }
        }
        for writer in writers where next[writer] != .waiting { next[writer] = .armed }
        gates[directory] = next
        bounds[directory] = seconds
        condition.broadcast()
        condition.unlock()
    }

    /// Every gate `cacheDir` has had, by writer.
    func gateStates(in cacheDir: URL) -> [String: Gate] {
        condition.lock()
        defer { condition.unlock() }
        return gates[cacheDir.standardizedFileURL.path] ?? [:]
    }

    /// `publish`'s first line. An armed writer waits here until a save of
    /// `directory` is in its hold, its gate is disarmed, or its bound passes.
    func arrive(_ directory: String, _ writer: String) {
        condition.lock()
        defer { condition.unlock() }
        guard gates[directory]?[writer] == .armed else { return }
        gates[directory]?[writer] = .waiting
        let deadline = Date().addingTimeInterval(bounds[directory] ?? Self.defaultBound)
        while gates[directory]?[writer] == .waiting {
            if (holding[directory] ?? 0) > 0 {
                gates[directory]?[writer] = .save
            } else if Date() >= deadline {
                gates[directory]?[writer] = .timeout
            } else {
                condition.wait(until: deadline)
            }
        }
    }

    /// A save of `cacheDir` entered its `-RCDevSaveHold` sleep, or left it.
    func saveHold(_ began: Bool, in cacheDir: URL) {
        let directory = cacheDir.standardizedFileURL.path
        condition.lock()
        holding[directory, default: 0] += began ? 1 : -1
        if holding[directory] == 0 { holding[directory] = nil }
        condition.broadcast()
        condition.unlock()
    }
}
#endif
