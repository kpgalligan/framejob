import Foundation

/// What the Transcript tab shows, and its fill (road map "creator-jobs" TX2a,
/// spec §11 TX-22): the edited container's words as `TranscriptTokens`, the
/// clips with no words, the notes and the status line, rebuilt from a
/// per-media words cache, with this Mac's misses read by the tab's ONE
/// `TranscriptFill` owner (TX-12).
///
/// Main thread, but for two serial `.utility` queues of its own: the LOAD
/// queue reads a media's cloud transcript (TR-11), else its stored run, then
/// its pause set; the WAIT queue runs the one waiter, which wants the first
/// pending miss, waits for it and moves on — never the load queue, so a load
/// never waits behind a fill. Each media's words show as soon as its run is
/// stored, not when the last one ends.
///
/// `pending` (the misses in the fill's order, the media under the playhead
/// first) and the waiter's state are guarded by `lock`; `update()` replaces
/// `pending`, and releases the want when the media the waiter waits on is no
/// longer needed, which `wait` answers as `.cancelled`.
///
/// The bar's view state (TX2b, spec §11 TX-25, TX-26) is here too: Words from
/// (one track, or all), Language (an installed one, or the Mac's default),
/// and Stop, which withdraws only the tab's want, and Read.
final class TranscriptTabSource {
    enum Status: Equatable {
        case idle, loading, reading(name: String, fraction: Double, index: Int, of: Int), noModel
        case failed([String])
        case stopped(remaining: Int)
    }

    private weak var document: ProjectDocument?
    private let onChange: () -> Void
    private(set) var model = TranscriptTokens.empty
    private(set) var noWords: [TimelineTranscript.NoWords] = []
    private(set) var notes: [String] = []
    private(set) var status: Status = .idle
    private(set) var rebuilds = 0
    private(set) var lastRebuildMilliseconds: Double = 0

    /// Words from: nil is All tracks (TX-25).
    private(set) var wordsFrom: UInt32?
    /// Language: a BCP-47 identifier; nil is Automatic, the Mac's default.
    private(set) var language: String?
    /// The edited container's tracks, from the last read, in snapshot order.
    private(set) var tracks: [TrackSnapshot] = []
    /// The installed languages; nil until read off main.
    private(set) var languages: [Transcriber.Language]?
    /// Stop was pressed and neither Read nor a show has come since (TX-26).
    private(set) var stopped = false

    /// Whether Stop applies: the tab's waiter reads on this Mac.
    var canStop: Bool {
        if case .reading = status { return true }
        return false
    }

    /// Whether the tab's owner wants a media of the fill now.
    var ownsWant: Bool {
        lock.lock()
        defer { lock.unlock() }
        return wanting
    }

    /// No load in flight, no waiter running, nothing pending.
    var settled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return inFlight == 0 && !waiterRunning && pending.isEmpty && waiting.isEmpty
    }

    // Main only.
    private var shown = false
    private var read: TimelineTranscript.DocumentRead?
    private var words: [UInt32: TimelineTranscript.MediaWords] = [:]
    private var pauseSets: [UInt32: Set<Ticks>] = [:]
    private var missItems: [UInt32: TranscriptFill.Item] = [:]
    private var failures: [UInt32: String] = [:]
    private var loading: Set<UInt32> = []
    private var noModel = false
    private var dirty = false
    private var poll: Timer?

    private let fill: TranscriptFill
    private let owner: Int
    private let loadQueue = DispatchQueue(
        label: "com.kgalligan.framejob.transcript-tab-load", qos: .utility)
    private let waitQueue = DispatchQueue(
        label: "com.kgalligan.framejob.transcript-tab-wait", qos: .utility)

    // Guarded by `lock`.
    private let lock = NSLock()
    private var pending: [TranscriptFill.Item] = []
    private var pendingTotal = 0
    private var waiting: [TranscriptFill.Item] = []
    private var waiterRunning = false
    private var wanting = false
    private var inFlight = 0
    private var generation = 0

    /// Main. A pane is only made for an inspector that has its document;
    /// without one the source answers nothing and its fill is never used.
    init(document: ProjectDocument?, onChange: @escaping () -> Void) {
        self.document = document
        self.onChange = onChange
        fill = document.map { TranscriptFill.fill(for: $0) } ?? TranscriptFill(key: Int.min)
        owner = fill.newOwner()
    }

    deinit {
        poll?.invalidate()
        fill.release(owner: owner)
    }

    /// Shown: load and want. Hidden: release the want, stop the poll, drop
    /// the words cache.
    func setShown(_ shown: Bool) {
        guard shown != self.shown else { return }
        self.shown = shown
        if shown {
            failures = [:]
            noModel = false
            stopped = false
            loadLanguages()
            update()
            poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.polled()
            }
            return
        }
        poll?.invalidate()
        poll = nil
        lock.lock()
        generation += 1
        pending = []
        pendingTotal = 0
        waiting = []  // so a show before the waiter wakes pends its media again
        wanting = false
        fill.release(owner: owner)
        lock.unlock()
        words = [:]
        pauseSets = [:]
        missItems = [:]
        loading = []
        status = .idle
    }

    /// A new edited project: re-read the instances, rebuild from the cached
    /// words, and load the misses. Never while a live gesture runs; the next
    /// call after it rebuilds.
    func update() {
        guard shown, let document else { return }
        if document.isLiveEditing {
            dirty = true
            return
        }
        dirty = false
        let started = DispatchTime.now().uptimeNanoseconds
        read = TimelineTranscript.read(document: document)
        tracks = read?.snapshot.tracks ?? []
        if let chosen = wordsFrom, !tracks.contains(where: { $0.id == chosen }) { wordsFrom = nil }
        rebuild(started: started)
        refreshPending()
        loadMisses()
    }

    /// Whether a rebuild was put off by a live gesture.
    var isDirty: Bool { dirty }

    // MARK: - The bar's choices (TX-25, TX-26)

    /// Words from: one track of the edited container, or nil for all.
    func setWordsFrom(_ track: UInt32?) {
        guard track != wordsFrom else { return }
        wordsFrom = track
        update()
    }

    /// Language: drops this Mac's words, their misses and failures, and the
    /// waiter's want, as a hide does, then reads again in the new language.
    func setLanguage(_ identifier: String?) {
        guard identifier != language else { return }
        language = identifier
        lock.lock()
        generation += 1
        pending = []
        pendingTotal = 0
        waiting = []
        wanting = false
        fill.release(owner: owner)
        lock.unlock()
        for (media, heard) in words where heard.engine == .apple {
            words[media] = nil
            pauseSets[media] = nil
        }
        missItems = [:]
        failures = [:]
        loading = []
        noModel = false
        update()
    }

    /// Stop: the tab's want only, the waiter's queue emptied first, so a
    /// tool call's run of the same media goes on (TX-26).
    func stop() {
        guard shown else { return }
        stopped = true
        lock.lock()
        pending = []
        pendingTotal = 0
        waiting = []  // so a Read before the waiter wakes pends its media again
        wanting = false
        fill.release(owner: owner)  // Stop: the tab's want only (TX-26)
        lock.unlock()
        refreshPending()
        onChange()
    }

    /// Read: the misses wanted again.
    func resume() {
        guard stopped else { return }
        stopped = false
        update()
        onChange()
    }

    /// The installed languages, read once per show on the load queue.
    private func loadLanguages() {
        lock.lock()
        inFlight += 1
        lock.unlock()
        loadQueue.async { [weak self] in
            let list = Transcriber.languages()
            DispatchQueue.main.async {
                guard let self else { return }
                self.end()
                self.languages = list
                self.onChange()
            }
        }
    }

    /// The chosen language among `list`, else the Mac's default. Any thread.
    private static func resolve(
        _ wanted: String?, in list: [Transcriber.Language]
    ) -> Transcriber.Language? {
        wanted.flatMap { Transcriber.language(matching: $0, in: list) }
            ?? Transcriber.defaultLanguage(in: list)
    }

    /// Words and pause sets given whole, then `update()` — for
    /// `transcript_tab_probe.swift` only.
    func preload(
        _ words: [UInt32: TimelineTranscript.MediaWords], pauses: [UInt32: Set<Ticks>]
    ) {
        self.words.merge(words) { _, new in new }
        pauseSets.merge(pauses) { _, new in new }
        update()
    }

    // MARK: - The model

    /// The media the shown words need; with a track chosen, only those with
    /// an instance on it (TX-25).
    private var needed: [UInt32] {
        guard let read else { return [] }
        let instances = read.instances.filter { wordsFrom == nil || $0.track == wordsFrom }
        return TimelineTranscript.neededMedia(instances, window: nil, playhead: read.playhead)
    }

    private func rebuild(started: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        if document?.isLiveEditing == true {
            dirty = true
            return
        }
        if let read {
            let all = TimelineTranscript.words(read.instances, media: words, snapshot: read.snapshot)
            let shown = all.filter { wordsFrom == nil || $0.track == wordsFrom }
            model = TranscriptTokens.build(shown, pauses: pauseSets)
            noWords = read.noWords
            notes = TimelineTranscript.sameSpeech(shown, instances: read.instances)
        } else {
            model = .empty
            noWords = []
            notes = []
        }
        rebuilds += 1
        refreshStatus()
        onChange()
        lastRebuildMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e6
    }

    // MARK: - Loads

    /// Reads each needed media with no words yet: its cloud transcript,
    /// else its stored run, else a fill item; then its pause set.
    private func loadMisses() {
        guard let read, let document else { return }
        let toLoad = needed.filter {
            words[$0] == nil && failures[$0] == nil && missItems[$0] == nil && !loading.contains($0)
        }
        guard !toLoad.isEmpty else { return }
        let jobs = toLoad.compactMap { media -> (MediaSnapshot, URL)? in
            guard let record = read.records[media], let url = read.urls[media] else { return nil }
            return (record, url)
        }
        guard let cacheDir = read.cacheDir ?? document.cacheDirectory else {
            for media in toLoad { failures[media] = "The project has no cache folder to keep the words in." }
            refreshStatus()
            onChange()
            return
        }
        loading.formUnion(toLoad)
        let generation = begin()
        let wanted = self.language
        loadQueue.async { [weak self] in
            var found: [UInt32: (TimelineTranscript.MediaWords, Set<Ticks>)] = [:]
            var missed: [UInt32: TranscriptFill.Item] = [:]
            var unreadable: [UInt32: String] = [:]
            var modelMissing = false
            var language: Transcriber.Language??
            for (record, url) in jobs {
                if let cloud = TimelineTranscript.cloudWords(record, url: url, cacheDir: cacheDir) {
                    found[record.id] = (cloud, Self.pauses(cloud, cacheDir: cacheDir))
                    continue
                }
                if language == nil { language = Self.resolve(wanted, in: Transcriber.languages()) }
                guard let chosen = language ?? nil else {
                    modelMissing = true
                    continue
                }
                guard
                    let item = TimelineTranscript.fillItem(
                        record, url: url, cacheDir: cacheDir, language: chosen)
                else {
                    unreadable[record.id] = "“\(record.name)” cannot be read."
                    continue
                }
                if let device = TimelineTranscript.deviceWords(item) {
                    found[record.id] = (device, Self.pauses(device, cacheDir: cacheDir))
                } else {
                    missed[record.id] = item
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.end()
                self.loading.subtract(jobs.map(\.0.id))
                guard self.isCurrent(generation) else { return }
                for (media, pair) in found {
                    self.words[media] = pair.0
                    self.pauseSets[media] = pair.1
                }
                self.missItems.merge(missed) { _, new in new }
                self.failures.merge(unreadable) { _, new in new }
                self.noModel = self.noModel || modelMissing
                self.rebuild()
                self.refreshPending()
            }
        }
    }

    private static func pauses(_ words: TimelineTranscript.MediaWords, cacheDir: URL) -> Set<Ticks> {
        TranscriptTokens.pauses(
            words.words, speech: MediaImporter.loadSpeech(for: words.media, in: cacheDir),
            confidence: Float(SilenceDetector.Settings.defaultVoiceConfidence))
    }

    private func begin() -> Int {
        lock.lock()
        defer { lock.unlock() }
        inFlight += 1
        return generation
    }

    private func end() {
        lock.lock()
        inFlight -= 1
        lock.unlock()
    }

    private func isCurrent(_ generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return shown && generation == self.generation
    }

    // MARK: - The fill, one media at a time

    /// The misses still needed, in the fill's order, as the new pending
    /// list; the want released when what the waiter waits on is not needed.
    private func refreshPending() {
        let order = needed
        let items = stopped ? [] : order.compactMap { media in
            words[media] == nil && failures[media] == nil ? missItems[media] : nil
        }
        lock.lock()
        let running = Set(waiting.map(\.media))
        if !waiting.isEmpty, !waiting.contains(where: { order.contains($0.media) }) {
            fill.release(owner: owner)
            wanting = false
        }
        pending = items.filter { !running.contains($0.media) }
        pendingTotal = items.count
        if !waiterRunning, !pending.isEmpty {
            waiterRunning = true
            waitQueue.async { [weak self] in self?.waitLoop() }
        }
        lock.unlock()
        refreshStatus()
    }

    /// The one waiter: wants the first pending media, waits until it
    /// settles, and moves on until nothing is pending.
    private func waitLoop() {
        while true {
            lock.lock()
            guard !pending.isEmpty else {
                waiterRunning = false
                if wanting {
                    fill.release(owner: owner)
                    wanting = false
                }
                lock.unlock()
                DispatchQueue.main.async { [weak self] in self?.polled() }
                return
            }
            let take = 1
            let batch = Array(pending.prefix(take))
            pending.removeFirst(batch.count)
            waiting = batch
            wanting = true
            fill.want(owner: owner, items: batch)
            let generation = self.generation
            lock.unlock()
            let outcomes = fill.wait(owner: owner)
            lock.lock()
            waiting = []
            let current = generation == self.generation
            lock.unlock()
            guard current else { continue }
            for item in batch {
                switch outcomes[item.media] ?? .cancelled {
                case .stored: loadStored(item, generation: generation)
                case .failed(let why):
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isCurrent(generation) else { return }
                        self.failures[item.media] = why
                        self.refreshStatus()
                        self.onChange()
                    }
                case .cancelled: break
                }
            }
        }
    }

    /// A stored run's words and pause set, read on the load queue, then a
    /// rebuild on main.
    private func loadStored(_ item: TranscriptFill.Item, generation: Int) {
        lock.lock()
        inFlight += 1
        lock.unlock()
        loadQueue.async { [weak self] in
            let words = TimelineTranscript.deviceWords(item)
            let pauses = words.map { Self.pauses($0, cacheDir: item.cacheDir) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.end()
                guard self.isCurrent(generation), let words, let pauses else { return }
                self.words[item.media] = words
                self.pauseSets[item.media] = pauses
                self.missItems[item.media] = nil
                self.rebuild()
            }
        }
    }

    // MARK: - Status

    private func polled() {
        let before = status
        refreshStatus()
        if status != before { onChange() }
    }

    private func refreshStatus() {
        lock.lock()
        let running = waiting.first
        let remaining = pending.count
        let total = pendingTotal
        lock.unlock()
        let unread = stopped ? needed.filter { words[$0] == nil && missItems[$0] != nil }.count : 0
        if let running {
            let progress = fill.progress()
            let fraction = progress?.media == running.media ? progress?.fraction ?? 0 : 0
            let of = max(total, 1)
            status = .reading(
                name: running.name, fraction: fraction, index: min(max(total - remaining, 1), of), of: of)
        } else if unread > 0 {
            status = .stopped(remaining: unread)
        } else if !failures.isEmpty {
            status = .failed(failures.keys.sorted().compactMap { failures[$0] })
        } else if noModel {
            status = .noModel
        } else if !loading.isEmpty {
            status = .loading
        } else {
            status = .idle
        }
    }

    /// The fill's running media and its fraction, for `transcript_view`.
    var fillProgress: (media: UInt32, fraction: Double)? { fill.progress() }
}
