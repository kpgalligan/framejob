import Foundation

/// The timeline transcript's fill (road map "creator-jobs" TX1, spec §11
/// TX-12): each heard media with no cloud transcript and no stored run over
/// the whole file is read ONCE, whole, by this Mac's recogniser and kept in
/// TR-14's cache (`DeviceTranscriptCache`).
///
/// **One per document**, keyed by its `recipeKey` (`ProjectDocument.swift`
/// takes nothing), and dropped once the document is no longer open
/// (`RecipeSource` no longer holds its key, `isOpenForAnalysis`'s test).
///
/// **Owners** — each tool call while it waits; the Transcript tab from TX2a
/// — `want` a list of items, which REPLACES that owner's list; `release`
/// withdraws only that owner's want. An item no owner wants is dropped from
/// the queue, or, running, cancelled through its `Transcriber.CancelToken`;
/// one another owner still wants runs on, and one cancelled and wanted again
/// before its run unwound runs afresh. `AnalysisLane`'s shape.
///
/// **One media at a time**, on one serial `.userInitiated` queue, off main
/// (TX-S1: a sibling process's whole-file run left `play_preview` composing
/// 300 of 300 frames). The queue takes the wanted items in the order the
/// owners gave them (the caller puts the media under the playhead first).
/// A run is a whole-file `Transcriber.Job` through
/// `TranscriptReader.recognize`, then `Heard(runs:over:)`, then `store` —
/// only when it was not cancelled and the file's stamp did not change.
final class TranscriptFill: @unchecked Sendable {

    /// One media to read whole, with everything the run needs by value.
    struct Item: Hashable {
        let media: UInt32
        let url: URL
        let name: String
        let duration: Ticks
        let stamp: DeviceTranscriptCache.Stamp
        let cacheDir: URL
        let language: Transcriber.Language
        /// The media record, for the stamp's re-read after the run.
        let record: MediaSnapshot

        func hash(into hasher: inout Hasher) {
            hasher.combine(media)
            hasher.combine(url)
            hasher.combine(language.identifier)
        }

        /// The whole file as one job: clip 0, from tick 0, at speed 1.
        var job: Transcriber.Job {
            Transcriber.Job(
                clip: 0, media: media, name: name, source: url, sourceIn: 0,
                sourceLength: duration, start: 0, duration: duration, speed: 1)
        }
    }

    /// How an item's run ended.
    enum Outcome: Equatable {
        case stored, failed(String), cancelled
    }

    /// Main only: the live fills by document key.
    private static var fills: [Int: TranscriptFill] = [:]

    /// The document's fill, made on first use; every fill whose document has
    /// closed is dropped (its queue emptied, its run cancelled). Main.
    static func fill(for document: ProjectDocument) -> TranscriptFill {
        for (key, fill) in fills where !fill.isAlive {
            fill.drop()
            fills[key] = nil
        }
        if let fill = fills[document.recipeKey] { return fill }
        let fill = TranscriptFill(key: document.recipeKey)
        fills[document.recipeKey] = fill
        return fill
    }

    private let key: Int
    private let condition = NSCondition()
    private var owners: [Int: [Item]] = [:]
    /// What each owner last asked for, kept past its release so `wait` can
    /// answer `.cancelled` for what it withdrew.
    private var asked: [Int: [Item]] = [:]
    private var nextOwner = 0
    private var outcomes: [Item: Outcome] = [:]
    private var running: (item: Item, token: Transcriber.CancelToken)?
    private var fraction: (media: UInt32, fraction: Double)?
    private let queue = DispatchQueue(
        label: "com.kgalligan.framejob.transcript-fill", qos: .userInitiated)

    /// A fill for the document whose `RecipeSource` key is `key`. Internal
    /// for `timeline_transcript_probe.swift`; the app makes one through
    /// `fill(for:)`.
    init(key: Int) {
        self.key = key
    }

    private var isAlive: Bool { RecipeSource.shared.project(for: key) != nil }

    /// A fresh owner id. Any thread.
    func newOwner() -> Int {
        condition.lock()
        defer { condition.unlock() }
        nextOwner += 1
        return nextOwner
    }

    /// Replaces `owner`'s want with `items`, in the caller's order. An item
    /// wanted ANEW after it ended runs again (its caller found the cache
    /// missing it). Any thread.
    func want(owner: Int, items: [Item]) {
        condition.lock()
        let earlier = owners[owner] ?? []
        for item in items where !earlier.contains(item) && running?.item != item {
            outcomes[item] = nil
        }
        owners[owner] = items.isEmpty ? nil : items
        asked[owner] = items
        reconcileLocked()
        condition.unlock()
    }

    /// Withdraws `owner`'s want: a run no other owner wants is cancelled.
    func release(owner: Int) {
        condition.lock()
        owners[owner] = nil
        reconcileLocked()
        condition.unlock()
    }

    /// Blocks until each item `owner` last asked for has settled — its run
    /// stored, failed or was cancelled, or the owner withdrew it (answered
    /// `.cancelled`) — and answers each by media. Never on main.
    func wait(owner: Int) -> [UInt32: Outcome] {
        condition.lock()
        defer {
            asked[owner] = nil
            condition.unlock()
        }
        while true {
            if !isAlive { dropLocked() }
            let wanted = owners[owner] ?? []
            var answer: [UInt32: Outcome] = [:]
            var settled = true
            for item in asked[owner] ?? [] {
                if let outcome = outcomes[item] {
                    answer[item.media] = outcome
                } else if !wanted.contains(item) {
                    answer[item.media] = .cancelled
                } else {
                    settled = false
                }
            }
            if settled { return answer }
            condition.wait(until: Date().addingTimeInterval(0.05))
        }
    }

    /// The running media and how much of it has been heard, 0…1. Any thread.
    func progress() -> (media: UInt32, fraction: Double)? {
        condition.lock()
        defer { condition.unlock() }
        return fraction
    }

    // MARK: - The queue

    private func drop() {
        condition.lock()
        dropLocked()
        condition.unlock()
    }

    /// The document closed: no owner is left and the run is cancelled.
    private func dropLocked() {
        owners = [:]
        reconcileLocked()
    }

    /// Cancels a run nobody wants and starts the next wanted item.
    private func reconcileLocked() {
        let wanted = wantedLocked()
        if let running, !wanted.contains(running.item) { running.token.cancel() }
        condition.broadcast()
        guard running == nil, let next = wanted.first(where: { outcomes[$0] == nil }) else {
            return
        }
        let token = Transcriber.CancelToken()
        running = (next, token)
        queue.async { [self] in
            let outcome = run(next, token: token)
            condition.lock()
            // A run cancelled for an owner's release that another owner
            // wanted before it unwound is no answer to that owner: no
            // outcome, so the reconcile below starts it again.
            let rewanted = token.isCancelled && wantedLocked().contains(next)
            outcomes[next] = outcome == .cancelled && rewanted ? nil : outcome
            running = nil
            fraction = nil
            reconcileLocked()
            condition.unlock()
        }
    }

    /// Every owner's items, in owner order then each owner's own, each once.
    private func wantedLocked() -> [Item] {
        var out: [Item] = []
        for owner in owners.keys.sorted() {
            for item in owners[owner] ?? [] where !out.contains(item) { out.append(item) }
        }
        return out
    }

    /// One whole-file run, off main. A stored run that already covers the
    /// file (another caller's) answers `.stored` without recognising.
    private func run(_ item: Item, token: Transcriber.CancelToken) -> Outcome {
        let job = item.job
        if DeviceTranscriptCache.lookup(
            job, media: item.media, stamp: item.stamp, in: item.cacheDir) != nil
        {
            return .stored
        }
        let seconds = max(ReelTime.seconds(item.duration), 0.001)
        let runs: [SpeechEngine.Run]
        do {
            runs = try TranscriptReader.recognize(
                job, language: item.language, cancel: token,
                progress: { [weak self] reached in self?.heard(item.media, reached / seconds) })
        } catch Transcriber.TranscribeError.cancelled {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
        if token.isCancelled { return .cancelled }
        let heard = DeviceTranscriptCache.Heard(runs: runs, over: job)
        guard
            DeviceTranscriptCache.currentStamp(
                item.record, url: item.url, language: item.language.identifier)
                == item.stamp
        else {
            return .failed("“\(item.name)” changed while it was being transcribed. Call again.")
        }
        guard DeviceTranscriptCache.store(heard, media: item.media, stamp: item.stamp, in: item.cacheDir)
        else {
            return .failed(
                "What was heard in “\(item.name)” could not be kept in the project's cache.")
        }
        return .stored
    }

    private func heard(_ media: UInt32, _ share: Double) {
        condition.lock()
        fraction = (media, min(max(share, 0), 1))
        condition.unlock()
    }
}
