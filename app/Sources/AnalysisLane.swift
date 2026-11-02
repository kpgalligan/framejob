import Foundation

/// One analysis job's identity (spec §11 CJ-21): a kind over one media's
/// missing ranges (before pre-roll), with the stamp it will be stored under
/// and the converted reader's input. Equal, and hashed, by kind, cache
/// folder, media id, stamp and ranges.
struct AnalysisRequest: Hashable, @unchecked Sendable {
    let kind: AnalysisKind
    let cacheDir: URL
    let media: MediaSnapshot
    let url: URL
    let stamp: AnalysisStamp
    let input: ThumbnailInput?
    let ranges: [ClosedRange<Int>]

    static func == (lhs: AnalysisRequest, rhs: AnalysisRequest) -> Bool {
        lhs.kind == rhs.kind && lhs.cacheDir.standardizedFileURL == rhs.cacheDir.standardizedFileURL
            && lhs.media.id == rhs.media.id && lhs.stamp == rhs.stamp && lhs.ranges == rhs.ranges
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(cacheDir.standardizedFileURL)
        hasher.combine(media.id)
        hasher.combine(ranges)
    }
}

/// One job's run, in process uptime (`ProcessInfo.systemUptime`): queued,
/// started, ended, and how it ended — nil until it does, never `.timedOut`.
struct AnalysisRun: Equatable {
    let queuedAt: Double
    let startedAt: Double?
    let endedAt: Double?
    let outcome: AnalysisWait?
}

/// How a wait, or a job, ended.
enum AnalysisWait: Equatable {
    case landed, failed(String), cancelled, timedOut
}

/// The process-wide analysis lane (spec §11 CJ-21; road map "creator-jobs"
/// CJ2a), `RampAudioRenders`' shape.
///
/// **Owners** want requests: `want` REPLACES an owner's set; a queued job no
/// owner wants is dropped and a running one cancelled, and one wanted again
/// while it runs is not; an owner whose `alive()` answers false is dropped at
/// the next 50 ms poll (a running job's cancellation check, a wait). A job
/// that lands or fails calls each owner wanting it back with `settled` on the
/// main queue. A landed or failed request runs again only when an owner
/// wants it anew (its caller found the store missing it); one an owner keeps
/// wanting does not.
///
/// **Queues.** The picture queue (`.utility`, at most `pictureWidth` jobs at
/// once, CJ-S3 (a)) and the sound queue (serial, idle until a sound kind
/// exists, FC3) — never the cooperative pool, never `MediaCacheLane`. A job
/// takes no `CachePass`; it writes only through `AnalysisStore.publish`.
///
/// **Runs.** The lane keeps the last `runLimit` jobs' runs, read by
/// `run(of:)` (a tool's `run`, the dev tool's `jobs`).
final class AnalysisLane: @unchecked Sendable {
    static let shared = AnalysisLane()
    /// `-RCDevAnalysisHold <s>`: each job waits that long before its first
    /// frame, polling cancellation every 50 ms (dev tools only, CJ-8 (k)).
    static let devHoldKey = "RCDevAnalysisHold"
    /// `-RCDevAnalysisCanned YES`: canned markers are honoured (CJ-26).
    static let devCannedKey = "RCDevAnalysisCanned"
    /// The picture queue's width: spike CJ-S3 (a), two converted jobs
    /// reaching only 1.05× one.
    static let pictureWidth = 1
    /// How long a tool call waits for its job (CJ-25): ten minutes of 4K HLG
    /// through the converted reader at 256 took 26.9 s; × 2, up to 10 s.
    static let callWaitLimit: TimeInterval = 60
    static let runLimit = 256
    /// How often owners' `alive()` is asked.
    static let pollInterval: TimeInterval = 0.05

    private struct Owner {
        var requests: [AnalysisRequest]
        let alive: @Sendable () -> Bool
        let settled: (() -> Void)?
    }

    private let condition = NSCondition()
    private var owners: [Int: Owner] = [:]
    private var nextOwner = 1
    private var queued: [AnalysisRequest] = []
    /// Running request → whether it is cancelled.
    private var running: [AnalysisRequest: Bool] = [:]
    private var runs: [AnalysisRequest: AnalysisRun] = [:]
    private var runOrder: [AnalysisRequest] = []
    /// A running job's share of its ranges read (CJ-28), from its first
    /// frame until its run ends.
    private var fractions: [AnalysisRequest: Double] = [:]
    private var lastPoll = 0.0
    private let picture = DispatchQueue(
        label: "com.kgalligan.framejob.analysis-picture", qos: .utility, attributes: .concurrent)
    private let sound = DispatchQueue(label: "com.kgalligan.framejob.analysis-sound", qos: .utility)

    private init() {}

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// A fresh owner id. Any thread.
    func newOwner() -> Int {
        condition.lock()
        defer { condition.unlock() }
        nextOwner += 1
        return nextOwner
    }

    /// Replaces `owner`'s wanted requests. Any thread; `alive` is asked
    /// under the lane's lock and must take no lock of the lane's.
    func want(
        _ requests: [AnalysisRequest], owner: Int, alive: @escaping @Sendable () -> Bool,
        settled: (() -> Void)?
    ) {
        condition.lock()
        // A request wanted ANEW after it ended runs again: its caller looked
        // it up as a miss, so the store no longer holds what it landed (a
        // stamp changed and back, a cache removed). Re-passing an earlier
        // request — the dev owner's — keeps its run.
        let earlier = owners[owner]?.requests ?? []
        for request in requests where !earlier.contains(request) && running[request] == nil {
            if let run = runs[request], run.outcome != nil {
                runs[request] = AnalysisRun(
                    queuedAt: run.queuedAt, startedAt: run.startedAt, endedAt: run.endedAt,
                    outcome: nil)
            }
        }
        if requests.isEmpty {
            owners[owner] = nil
        } else {
            owners[owner] = Owner(requests: requests, alive: alive, settled: settled)
        }
        reconcileLocked()
        condition.unlock()
    }

    /// Drops everything `owner` wanted.
    func release(owner: Int) {
        condition.lock()
        owners[owner] = nil
        reconcileLocked()
        condition.unlock()
    }

    /// Blocks until every request landed (`.landed`), one failed or was
    /// cancelled for good, `cancelled()` answers true, or `deadline` passes.
    /// Never on the main thread.
    func wait(
        for requests: [AnalysisRequest], owner: Int, deadline: Date, cancelled: () -> Bool
    ) -> AnalysisWait {
        condition.lock()
        defer { condition.unlock() }
        while true {
            pollLocked(force: false)
            if cancelled() { return .cancelled }
            var all = true
            for request in requests {
                switch runs[request]?.outcome {
                case .landed?: continue
                case .failed(let why)?: return .failed(why)
                case .cancelled? where !wantedLocked(request): return .cancelled
                default: all = false
                }
            }
            if all { return .landed }
            if Date() >= deadline { return .timedOut }
            condition.wait(until: min(deadline, Date().addingTimeInterval(Self.pollInterval)))
        }
    }

    /// The request's run, kept after it ends (the last `runLimit` jobs').
    func run(of request: AnalysisRequest) -> AnalysisRun? {
        condition.lock()
        defer { condition.unlock() }
        return runs[request]
    }

    /// How much of the request's ranges its running job has read, 0…1: nil
    /// until its first frame and again once its run ended (the Analyzing
    /// sheet's bar, spec §11 CJ-28). Any thread.
    func progress(of request: AnalysisRequest) -> Double? {
        condition.lock()
        defer { condition.unlock() }
        return fractions[request]
    }

    /// What `owner` wants now (spec §11 CO-22 (h)). Any thread; no poll.
    func requests(of owner: Int) -> [AnalysisRequest] {
        condition.lock()
        defer { condition.unlock() }
        return owners[owner]?.requests ?? []
    }

    /// Every owner's running and queued requests of `kind` for `cacheDir` (compared
    /// standardized), running first — the jobs a cutout's want may share (spec §11 CO-22 (c)).
    /// Any thread; no poll.
    func openRequests(kind: AnalysisKind, cacheDir: URL) -> [AnalysisRequest] {
        let folder = cacheDir.standardizedFileURL
        condition.lock()
        defer { condition.unlock() }
        let mine = { (request: AnalysisRequest) in
            request.kind == kind && request.cacheDir.standardizedFileURL == folder
        }
        let started = running.keys.filter(mine).sorted {
            ($0.media.id, $0.ranges.first?.lowerBound ?? 0)
                < ($1.media.id, $1.ranges.first?.lowerBound ?? 0)
        }
        return started + queued.filter(mine)
    }

    // MARK: - The queue

    private func wantedLocked(_ request: AnalysisRequest) -> Bool {
        owners.values.contains { $0.requests.contains(request) }
    }

    /// Drops the owners whose `alive()` answers false, at most every
    /// `pollInterval` unless forced, and reconciles when one went.
    private func pollLocked(force: Bool) {
        let now = Self.now
        guard force || now - lastPoll >= Self.pollInterval else { return }
        lastPoll = now
        let dead = owners.filter { !$0.value.alive() }.map(\.key)
        guard !dead.isEmpty else { return }
        dead.forEach { owners[$0] = nil }
        reconcileLocked()
    }

    /// Drops what no owner wants, cancels (or un-cancels) running jobs,
    /// queues what is wanted and neither queued, running, landed nor failed
    /// (owners in key order), and starts what the width allows.
    private func reconcileLocked() {
        queued.removeAll { !wantedLocked($0) }
        for request in running.keys { running[request] = !wantedLocked(request) }
        for owner in owners.keys.sorted() {
            for request in owners[owner]?.requests ?? []
            where running[request] == nil && !queued.contains(request) {
                switch runs[request]?.outcome {
                case .landed?, .failed?: continue
                default: break
                }
                queued.append(request)
                record(request, AnalysisRun(
                    queuedAt: Self.now, startedAt: nil, endedAt: nil, outcome: nil))
            }
        }
        let width = Self.pictureWidth
        while running.count < width, let index = queued.firstIndex(where: { !$0.kind.usesSoundQueue }) {
            let request = queued.remove(at: index)
            running[request] = false
            picture.async { [self] in execute(request) }
        }
        if let index = queued.firstIndex(where: { $0.kind.usesSoundQueue }),
            !running.keys.contains(where: { $0.kind.usesSoundQueue })
        {
            let request = queued.remove(at: index)
            running[request] = false
            sound.async { [self] in execute(request) }
        }
        condition.broadcast()
    }

    private func record(_ request: AnalysisRequest, _ run: AnalysisRun) {
        if runs[request] == nil {
            runOrder.append(request)
            if runOrder.count > Self.runLimit {
                let dropped = runOrder.removeFirst()
                if running[dropped] == nil, !queued.contains(dropped) { runs[dropped] = nil }
            }
        }
        runs[request] = run
    }

    private func isCancelled(_ request: AnalysisRequest) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        pollLocked(force: false)
        return running[request] ?? true
    }

    private func execute(_ request: AnalysisRequest) {
        condition.lock()
        let queuedAt = runs[request]?.queuedAt ?? Self.now
        runs[request] = AnalysisRun(
            queuedAt: queuedAt, startedAt: Self.now, endedAt: nil, outcome: nil)
        condition.unlock()
        let outcome = perform(request)
        condition.lock()
        running[request] = nil
        fractions[request] = nil
        let started = runs[request]?.startedAt
        runs[request] = AnalysisRun(
            queuedAt: queuedAt, startedAt: started, endedAt: Self.now, outcome: outcome)
        var called: [() -> Void] = []
        if outcome != .cancelled {
            called = owners.values.filter { $0.requests.contains(request) }.compactMap(\.settled)
        }
        reconcileLocked()
        condition.unlock()
        if !called.isEmpty { DispatchQueue.main.async { called.forEach { $0() } } }
    }

    /// The hold, then the kind's job.
    private func perform(_ request: AnalysisRequest) -> AnalysisWait {
        let cancelled = { [self] in isCancelled(request) }
        hold(cancelled: cancelled)
        if cancelled() { return .cancelled }
        do {
            let finished: Bool
            switch request.kind {
            case .shots:
                finished = try AnalysisShots.run(
                    request, cancelled: cancelled,
                    progress: { [self] fraction in setProgress(fraction, of: request) })
            case .masks:
                finished = try AnalysisMasks.run(
                    request, cancelled: cancelled,
                    progress: { [self] fraction in setProgress(fraction, of: request) })
            }
            return finished ? .landed : .cancelled
        } catch {
            let why = error.localizedDescription
            NSLog("AnalysisLane: %@ of media %u failed: %@", request.kind.rawValue,
                request.media.id, why)
            return .failed(why.hasSuffix(".") ? String(why.dropLast()) : why)
        }
    }

    /// Stores a running job's share read; no broadcast — nothing waits on it.
    private func setProgress(_ fraction: Double, of request: AnalysisRequest) {
        condition.lock()
        if running[request] != nil { fractions[request] = fraction }
        condition.unlock()
    }

    /// `-RCDevAnalysisHold <s>`: the job waits s seconds first, polling
    /// cancellation every 50 ms (dev tools only).
    private func hold(cancelled: () -> Bool) {
        #if FRAMEJOB_DEV_TOOLS
        let until = Date().addingTimeInterval(UserDefaults.standard.double(forKey: Self.devHoldKey))
        while Date() < until, !cancelled() { Thread.sleep(forTimeInterval: Self.pollInterval) }
        #endif
    }
}
