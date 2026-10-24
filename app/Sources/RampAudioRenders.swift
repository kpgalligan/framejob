import Foundation

/// The process-wide scheduler of ramp renders (spec §11 SR-12 (c)–(g), (j)):
/// what each OWNER wants, one serial `.utility` queue rendering one at a
/// time, and the waits an export makes on it.
///
/// **Owners.** A document wants its plans' ramp segments under its
/// `recipeKey` (`ProjectDocument+RampAudio.swift`); an export wants its
/// plan's under its own key while it writes (`Exporter+RampAudio.swift`).
/// `want` REPLACES an owner's set, so an edit that moves a map simply stops
/// wanting the old file: a queued render no owner wants is dropped and a
/// running one cancelled, and an edit storm costs at most the one in flight.
///
/// **Landing.** A render writes `<name>.landing` and is renamed to `<name>`
/// inside the cache ledger's `publish`, so never mid-save (SR-12 (e)). A
/// refused publish removes it and puts the render straight back at the
/// queue's end while anyone still wants the name — not a failure, so a
/// waiting export and the document finish with no further edit. A landed
/// render calls every owner that wants it back on the main queue.
///
/// **Failure** (SR-12 (g)): a name that failed is not rendered again in this
/// launch; one log line says why, never with the parity check's prefix.
final class RampAudioRenders: @unchecked Sendable {
    static let shared = RampAudioRenders()
    /// The dev-only launch default that holds each render that many seconds,
    /// polling cancellation, so a proof sees an export wait. Read only under
    /// `FRAMEJOB_DEV_TOOLS`.
    static let devHoldKey = "RCDevRampRenderHold"

    enum WaitError: Error, Equatable {
        case failed(clip: UInt32, message: String), cancelled
    }

    private enum Outcome { case landed, refused, failed(String), cancelled }

    private let condition = NSCondition()
    private var wants: [Int: [RampAudioRequest]] = [:]
    private var landings: [Int: () -> Void] = [:]
    private var queue: [RampAudioRequest] = []
    private var running: RampAudioRequest?
    private var runningCancelled = false
    private var draining = false
    /// Destination path → why it failed.
    private var failures: [String: String] = [:]
    private let work = DispatchQueue(label: "com.kgalligan.framejob.ramp-audio", qos: .utility)

    private init() {}

    /// Replaces `owner`'s wanted renders; `landed` (main queue) is called after
    /// each one of them lands. Any thread.
    func want(_ requests: [RampAudioRequest], owner: Int, landed: (() -> Void)?) {
        condition.lock()
        wants[owner] = requests.isEmpty ? nil : requests
        landings[owner] = requests.isEmpty ? nil : landed
        reconcileLocked()
        condition.unlock()
    }

    /// Drops everything `owner` wanted — a closed document, a finished export.
    func release(owner: Int) {
        condition.lock()
        wants[owner] = nil
        landings[owner] = nil
        reconcileLocked()
        condition.unlock()
    }

    /// Blocks until every request's file exists (each landed), one of them has
    /// failed, or `cancelled()` answers true — polled every 0.1 s. Never on
    /// the main thread: a render's landing may wait for a save there.
    func wait(for requests: [RampAudioRequest], owner: Int, cancelled: () -> Bool) throws {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if cancelled() { throw WaitError.cancelled }
            for request in requests {
                if let message = failures[request.destination.path] {
                    throw WaitError.failed(clip: request.clip, message: message)
                }
            }
            if requests.allSatisfy({ FileManager.default.fileExists(atPath: $0.destination.path) }) {
                return
            }
            condition.wait(until: Date().addingTimeInterval(0.1))
        }
    }

    /// Why the render landing at `destination` failed in this launch, or nil.
    func failure(for destination: URL) -> String? {
        condition.lock()
        defer { condition.unlock() }
        return failures[destination.path]
    }

    /// Every name an owner wants in `directory`, and the running render's —
    /// which prefixes its temporaries — so `RampAudioCache.prune` keeps them.
    func keptNames(in directory: URL) -> Set<String> {
        let folder = directory.standardizedFileURL.path
        func inside(_ request: RampAudioRequest) -> Bool {
            request.destination.deletingLastPathComponent().standardizedFileURL.path == folder
        }
        condition.lock()
        defer { condition.unlock() }
        var names = Set(wants.values.joined().filter(inside).map(\.destination.lastPathComponent))
        if let running, inside(running) { names.insert(running.destination.lastPathComponent) }
        return names
    }

    // MARK: - The queue

    private func wantedLocked(_ destination: URL) -> Bool {
        wants.values.contains { $0.contains { $0.destination == destination } }
    }

    /// Drops what no owner wants, cancels the running render if no owner
    /// wants it (and un-cancels it if one wants it again before it stops),
    /// queues what is wanted, not on disk, not failed and not already queued
    /// or running (owners in key order), and starts the queue.
    private func reconcileLocked() {
        queue.removeAll { !wantedLocked($0.destination) }
        if let running { runningCancelled = !wantedLocked(running.destination) }
        for owner in wants.keys.sorted() {
            for request in wants[owner] ?? []
            where failures[request.destination.path] == nil
                && running?.destination != request.destination
                && !queue.contains(where: { $0.destination == request.destination })
                && !FileManager.default.fileExists(atPath: request.destination.path)
            {
                queue.append(request)
            }
        }
        if !draining, !queue.isEmpty {
            draining = true
            work.async { [self] in drain() }
        }
        condition.broadcast()
    }

    private func drain() {
        while true {
            condition.lock()
            guard !queue.isEmpty else {
                draining = false
                condition.unlock()
                return
            }
            let request = queue.removeFirst()
            running = request
            runningCancelled = false
            condition.unlock()
            let outcome = perform(request)
            condition.lock()
            running = nil
            var called: [() -> Void] = []
            switch outcome {
            case .landed:
                called = wants.compactMap { owner, requests in
                    requests.contains(where: { $0.destination == request.destination })
                        ? landings[owner] : nil
                }
            case .refused, .cancelled:
                // Wanted again while it stopped: the want skipped it as running.
                if wantedLocked(request.destination),
                    !queue.contains(where: { $0.destination == request.destination })
                {
                    queue.append(request)
                }
            case .failed(let message):
                failures[request.destination.path] = message
            }
            condition.broadcast()
            condition.unlock()
            if !called.isEmpty { DispatchQueue.main.async { called.forEach { $0() } } }
        }
    }

    private var isRunningCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return runningCancelled
    }

    /// One render into `<name>.landing`, then the rename under the ledger.
    private func perform(_ request: RampAudioRequest) -> Outcome {
        let landing = URL(fileURLWithPath: request.destination.path + ".landing")
        let cancelled = { [self] in isRunningCancelled }
        do {
            try FileManager.default.createDirectory(
                at: request.destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            hold(cancelled: cancelled)
            if cancelled() { return .cancelled }
            let job = RampAudioRenderer.Job(
                source: try RampAudioCache.renderSource(for: request.source),
                map: RampAudioCache.map(of: request.ramp), keepPitch: request.ramp.keepPitch,
                destination: landing)
            _ = try RampAudioRenderer.render(job, cancelled: cancelled)
        } catch RampAudioRenderer.RenderError.cancelled {
            try? FileManager.default.removeItem(at: landing)
            return .cancelled
        } catch {
            try? FileManager.default.removeItem(at: landing)
            let why = error.localizedDescription
            NSLog("RampAudioRenders: clip %u's ramp audio was not rendered into %@: %@",
                request.clip, request.destination.lastPathComponent, why)
            return .failed(why.hasSuffix(".") ? String(why.dropLast()) : why)
        }
        let cache = request.destination.deletingLastPathComponent().deletingLastPathComponent()
        var moved = false
        var renameErrno: Int32 = 0
        let published = MediaImporter.CacheLedger.shared.publish(in: cache, for: nil) {
            moved = rename(landing.path, request.destination.path) == 0
            if !moved { renameErrno = errno }
        }
        if published, moved { return .landed }
        try? FileManager.default.removeItem(at: landing)
        if published {
            NSLog("RampAudioRenders: %@ could not be moved into place (errno %d)",
                request.destination.lastPathComponent, renameErrno)
            return .failed("the render could not be moved into place")
        }
        return .refused
    }

    /// `-RCDevRampRenderHold <s>`: each render waits s seconds first, polling
    /// cancellation (dev tools only; SR-12 (j)).
    private func hold(cancelled: () -> Bool) {
        #if FRAMEJOB_DEV_TOOLS
        let until = Date().addingTimeInterval(UserDefaults.standard.double(forKey: Self.devHoldKey))
        while Date() < until, !cancelled() { Thread.sleep(forTimeInterval: 0.05) }
        #endif
    }
}
