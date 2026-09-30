import Foundation

/// The bookkeeping under `generateCaches`: which pass is current for a media,
/// which task a new pass waits for, and which saves of a package are in
/// flight. Nothing here awaits — the awaiting is `MediaImporter.swift`'s —
/// so it is an `extension MediaImporter` in a file of its own, the shape
/// `MediaCacheFiles.swift` has for the same reason.
extension MediaImporter {

    /// One pass as the ledger handed it out: its key (cache directory and
    /// media id), the generation it belongs to, and its ticket. A pass asks
    /// `isCurrent()` before each write it makes and publishes its markers,
    /// waveform and voice file only through `CacheLedger.publish`, which asks
    /// the same question under the ledger's lock.
    ///
    /// `hold` is a probe's pause, run first in `isCurrent()` and never under
    /// the lock; it is nil in the product.
    struct CachePass: Sendable {
        let key: String
        let generation: Int
        let ticket: Int
        var hold: (@Sendable () -> Void)? = nil

        /// `hold`, then whether this pass's generation is still its key's
        /// latest.
        func isCurrent() -> Bool {
            hold?()
            return CacheLedger.shared.isCurrent(self)
        }

        /// Called last, on every path out of the pass's task.
        func done() {
            CacheLedger.shared.finish(self)
        }
    }

    /// One pass per (cache directory, media id) at a time, and no
    /// publication while a save of the package is in flight.
    ///
    /// **Order.** Each pass carries the URL the media resolved to when it
    /// was asked for, so passes for one URL run in the order they were asked
    /// for: `enqueue` calls `make` under the lock with the task enqueued
    /// before it, and the task awaits that one. A lock rather than an actor,
    /// because an actor is reached from synchronous code only through a
    /// `Task` hop, and two hops from one thread are not ordered.
    ///
    /// **Generations.** A pass asked for ANOTHER file (a relink, a file
    /// changed under the same id) starts a new generation. The running task
    /// is cancelled, the new pass waits for it at most `waitLimit`, and every
    /// pass of an older generation stops writing: each frame, each head
    /// clear and each publication asks whether its generation is still the
    /// latest. So a pass stuck inside one AVFoundation call on a stalled
    /// volume no longer holds a relink AWAY from it, and when it wakes it
    /// certifies nothing. A pass for the same file keeps the generation and
    /// waits in call order, as before; the record of the last URL asked for
    /// outlives `finish`.
    ///
    /// **Saves.** A save of a titled document lists the package for its lazy
    /// `cache/` wrapper and later swaps the new package in, so a file written
    /// between the two goes with the old package. `ProjectDocument`'s save
    /// override announces each save (`saveBegan` … `saveEnded`), and
    /// `publish` runs its body only while no save of that directory is in
    /// flight, waiting up to `waitLimit` for one to end; a save waits the
    /// same limit for a publication already being written. A save whose
    /// completion never arrives stops counting `saveLimit` after it began.
    ///
    /// One `NSCondition` guards all of it, and under it the ledger touches
    /// only its own state: never `CachePass.isCurrent()`, a `hold`, a
    /// `publish` body or another public method of its own.
    final class CacheLedger: @unchecked Sendable {
        static let shared = CacheLedger()
        /// How long a superseding pass waits for the one it cancelled, a
        /// publication for a save, and a save for a publication.
        static let waitLimit: TimeInterval = 30
        /// How long a save counts as in flight without its completion:
        /// `save_project`'s own ceiling (`AgentServer+Project.swift`).
        static let saveLimit: TimeInterval = 120

        private let condition = NSCondition()
        private var running: [String: (ticket: Int, task: Task<Void, Never>)] = [:]
        private var latest: [String: (generation: Int, path: String)] = [:]
        private var nextTicket = 0
        private var saves: [String: [Int: Date]] = [:]
        private var nextSave = 0
        private var publishing: [String: Int] = [:]

        /// Hands `make` the task to wait for, whether that wait is bounded
        /// (a superseded task), and the new pass; `make` only creates the
        /// task, under the lock.
        func enqueue(
            cacheDir: URL, media: UInt32, url: URL,
            _ make: (Task<Void, Never>?, Bool, CachePass) -> Task<Void, Never>
        ) {
            let key = "\(cacheDir.standardizedFileURL.path)\u{0}\(media)"
            let path = url.standardizedFileURL.path
            condition.lock()
            defer { condition.unlock() }
            let previous = running[key]?.task
            var bounded = false
            var generation = latest[key]?.generation ?? 0
            if latest[key]?.path != path {
                generation += 1
                latest[key] = (generation, path)
                if let previous {
                    previous.cancel()
                    bounded = true
                }
            }
            nextTicket += 1
            let pass = CachePass(key: key, generation: generation, ticket: nextTicket)
            running[key] = (nextTicket, make(previous, bounded, pass))
        }

        func isCurrent(_ pass: CachePass) -> Bool {
            condition.lock()
            defer { condition.unlock() }
            return currentLocked(pass)
        }

        /// Drops the entry a finished pass made, unless a later pass has
        /// already replaced it — that one is still owed its wait.
        func finish(_ pass: CachePass) {
            condition.lock()
            defer { condition.unlock() }
            if running[pass.key]?.ticket == pass.ticket { running[pass.key] = nil }
        }

        /// Records a save of `cacheDir`, after waiting up to `waitLimit` for
        /// any publication being written there. Runs on main.
        @discardableResult
        func saveBegan(cacheDir: URL) -> Int {
            let directory = cacheDir.standardizedFileURL.path
            let deadline = Date().addingTimeInterval(Self.waitLimit)
            condition.lock()
            defer { condition.unlock() }
            while (publishing[directory] ?? 0) > 0, Date() < deadline {
                condition.wait(until: deadline)
            }
            nextSave += 1
            saves[directory, default: [:]][nextSave] = Date()
            return nextSave
        }

        /// Ends the save `save`; an id the ledger does not hold does nothing.
        func saveEnded(cacheDir: URL, save: Int) {
            let directory = cacheDir.standardizedFileURL.path
            condition.lock()
            defer { condition.unlock() }
            guard saves[directory]?.removeValue(forKey: save) != nil else { return }
            if saves[directory]?.isEmpty == true { saves[directory] = nil }
            condition.broadcast()
        }

        /// Runs `body` — a marker, a waveform or a voice file and its post —
        /// when no save of `cacheDir` is in flight and `pass` (when given)
        /// is current. Waits up to `waitLimit` for a save to end; answers
        /// false, without running `body`, when that wait runs out or the pass
        /// is superseded. `body` never calls the ledger.
        @discardableResult
        func publish(in cacheDir: URL, for pass: CachePass?, _ body: () -> Void) -> Bool {
            let directory = cacheDir.standardizedFileURL.path
            let deadline = Date().addingTimeInterval(Self.waitLimit)
            condition.lock()
            while let expiry = saveExpiryLocked(directory) {
                guard Date() < deadline else {
                    condition.unlock()
                    return false
                }
                condition.wait(until: min(deadline, expiry))
            }
            if let pass, !currentLocked(pass) {
                condition.unlock()
                return false
            }
            publishing[directory, default: 0] += 1
            condition.unlock()
            body()
            condition.lock()
            publishing[directory, default: 1] -= 1
            if publishing[directory] == 0 { publishing[directory] = nil }
            condition.broadcast()
            condition.unlock()
            return true
        }

        /// The lock is held. Whether `pass`'s generation is its key's latest.
        private func currentLocked(_ pass: CachePass) -> Bool {
            latest[pass.key]?.generation == pass.generation
        }

        /// The lock is held. When the earliest in-flight save of `directory`
        /// stops counting, or nil when none is in flight; expired saves are
        /// dropped here.
        private func saveExpiryLocked(_ directory: String) -> Date? {
            guard let began = saves[directory] else { return nil }
            let now = Date()
            let live = began.filter { now.timeIntervalSince($0.value) < Self.saveLimit }
            saves[directory] = live.isEmpty ? nil : live
            return live.values.min().map { $0.addingTimeInterval(Self.saveLimit) }
        }
    }
}
