import Foundation

/// The process-wide scheduler of every offline audio render (spec §11 SR-12
/// (c)–(g), (j), AU-52, AU-144): a ramp segment's retimed sound, a clip
/// window's isolated voice, its voice effect and a retimed segment's mix
/// (`OfflineAudioJob`), what
/// each OWNER wants, one serial
/// `.utility` queue rendering one at a time, and the waits an export makes
/// on it.
///
/// **Owners.** A document wants its plans' ramp and isolation renders under
/// its `recipeKey` in one `want` (`ProjectDocument+RampAudio.swift`); an
/// export wants its plan's under its own key while it writes
/// (`Exporter+RampAudio.swift`).
/// `want` REPLACES an owner's set, so an edit that moves a map simply stops
/// wanting the old file: a queued render no owner wants is dropped and a
/// running one cancelled, and an edit storm costs at most the one in flight.
///
/// **Landing.** A render writes `<name>.landing` outside the package
/// (`RenderLanding`, spec §11 #553) and is moved to `<name>` inside the cache
/// ledger's `publish`, which makes the folder too, so never mid-save and
/// nothing in the package outside the ledger (SR-12 (e)). A
/// refused publish removes it and puts the render straight back at the
/// queue's end while anyone still wants the name — not a failure, so a
/// waiting export and the document finish with no further edit. A landed
/// render calls every owner that wants it back on the main queue.
///
/// **Failure** (SR-12 (g)): a name that failed is not rendered again in this
/// launch; one log line says why, never with the parity check's prefix. A
/// failed render calls every owner that wants it back on the main queue too,
/// as a landing does (AU-52), so a pane's status can say why.
final class RampAudioRenders: @unchecked Sendable {
    static let shared = RampAudioRenders()
    /// The dev-only launch default that holds each render that many seconds,
    /// polling cancellation, so a proof sees an export wait. Read only under
    /// `FRAMEJOB_DEV_TOOLS`.
    static let devHoldKey = "RCDevRampRenderHold"

    enum WaitError: Error, Equatable {
        case failed(request: RampAudioRequest, message: String), cancelled
    }

    private enum Outcome { case landed, refused, failed(String), cancelled }

    private let condition = NSCondition()
    private var wants: [Int: [RampAudioRequest]] = [:]
    private var settlements: [Int: () -> Void] = [:]
    private var queue: [RampAudioRequest] = []
    private var running: RampAudioRequest?
    private var runningCancelled = false
    private var draining = false
    /// Destination path → why it failed.
    private var failures: [String: String] = [:]
    private let work = DispatchQueue(label: "com.kgalligan.framejob.ramp-audio", qos: .utility)

    private init() {}

    /// Replaces `owner`'s wanted renders; `settled` (main queue) is called
    /// after each one of them lands or fails. Any thread.
    func want(_ requests: [RampAudioRequest], owner: Int, settled: (() -> Void)?) {
        condition.lock()
        wants[owner] = requests.isEmpty ? nil : requests
        settlements[owner] = requests.isEmpty ? nil : settled
        reconcileLocked()
        condition.unlock()
    }

    /// Drops everything `owner` wanted — a closed document, a finished export.
    func release(owner: Int) {
        condition.lock()
        wants[owner] = nil
        settlements[owner] = nil
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
                    throw WaitError.failed(request: request, message: message)
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
                called = settledOwnersLocked(request.destination)
            case .refused, .cancelled:
                // Wanted again while it stopped: the want skipped it as running.
                if wantedLocked(request.destination),
                    !queue.contains(where: { $0.destination == request.destination })
                {
                    queue.append(request)
                }
            case .failed(let message):
                failures[request.destination.path] = message
                called = settledOwnersLocked(request.destination)
            }
            condition.broadcast()
            condition.unlock()
            if !called.isEmpty { DispatchQueue.main.async { called.forEach { $0() } } }
        }
    }

    /// The closures of every owner that wants `destination`.
    private func settledOwnersLocked(_ destination: URL) -> [() -> Void] {
        wants.compactMap { owner, requests in
            requests.contains(where: { $0.destination == destination })
                ? settlements[owner] : nil
        }
    }

    private var isRunningCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return runningCancelled
    }

    /// One render into a landing file outside the package, then the folder
    /// and the move under the ledger (spec §11 #553).
    private func perform(_ request: RampAudioRequest) -> Outcome {
        let landing = RenderLanding(for: request.destination)
        defer { landing.remove() }
        let cancelled = { [self] in isRunningCancelled }
        do {
            hold(cancelled: cancelled)
            if cancelled() { return .cancelled }
            switch request.job {
            case .ramp(let ramp):
                // A processed window (AU-55 as amended) is a 48 kHz float
                // CAF and answers itself; its map is counted from its frame 0.
                let job = RampAudioRenderer.Job(
                    source: try RampAudioCache.renderSource(for: request.source),
                    map: RampAudioCache.map(of: ramp, lessFrames: request.sourceFirstFrame),
                    keepPitch: ramp.keepPitch, destination: landing.url)
                _ = try RampAudioRenderer.render(job, cancelled: cancelled)
            case .mix(let mix):
                // The source as `.isolation`'s, a refusal in its words.
                let source: URL
                do {
                    source = request.reversed
                        ? request.source : try RampAudioCache.renderSource(for: request.source)
                } catch RampAudioRenderer.RenderError.unreadable(let why) {
                    throw IsolationRenderer.RenderError.unreadable(why)
                }
                try IsolationMix.render(
                    IsolationMix.Job(source: source, job: mix, destination: landing.url),
                    cancelled: cancelled)
            case .isolation(let window):
                // A reversed file is 48 kHz LPCM already; a forward one is
                // read from what the composition plays (AU-51), a refusal in
                // the isolation's own words: the Status row shows it (AU-56).
                let source: URL
                do {
                    source = request.reversed
                        ? request.source : try RampAudioCache.renderSource(for: request.source)
                } catch RampAudioRenderer.RenderError.unreadable(let why) {
                    throw IsolationRenderer.RenderError.unreadable(why)
                }
                let job = IsolationRenderer.Job(
                    source: source, window: window, destination: landing.url)
                _ = try IsolationRenderer.render(job, cancelled: cancelled)
            case .voice(let voice):
                // The source as `.isolation`'s (AU-142), a refusal in the
                // voice's words; the isolated render it crossfades from is
                // named in the job.
                let source: URL
                do {
                    source = request.reversed
                        ? request.source : try RampAudioCache.renderSource(for: request.source)
                } catch RampAudioRenderer.RenderError.unreadable(let why) {
                    throw VoiceRenderer.RenderError.unreadable(why)
                }
                let job = VoiceRenderer.Job(source: source, job: voice, destination: landing.url)
                _ = try VoiceRenderer.render(job, cancelled: cancelled)
            }
        } catch RampAudioRenderer.RenderError.cancelled {
            return .cancelled
        } catch IsolationRenderer.RenderError.cancelled {
            return .cancelled
        } catch VoiceRenderer.RenderError.cancelled {
            return .cancelled
        } catch {
            let why = error.localizedDescription
            let kind: String
            switch request.job {
            case .ramp: kind = "ramp audio"
            case .isolation, .mix: kind = "isolated voice"
            case .voice: kind = "voice effect"
            }
            NSLog("RampAudioRenders: clip %u's %@ was not rendered into %@: %@",
                request.clip, kind, request.destination.lastPathComponent, why)
            return .failed(why.hasSuffix(".") ? String(why.dropLast()) : why)
        }
        let cache = request.destination.deletingLastPathComponent().deletingLastPathComponent()
        var renameErrno: Int32 = 0
        // The ledger's writer is the render's folder: ramp-audio, isolated, voiced.
        let writer = request.destination.deletingLastPathComponent().lastPathComponent
        let published = MediaImporter.CacheLedger.shared.publish(in: cache, for: nil, as: writer) {
            renameErrno = landing.publish(to: request.destination)
        }
        if published, renameErrno == 0 { return .landed }
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
