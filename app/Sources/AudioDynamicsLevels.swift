import AppKit
import Foundation

/// Each gated or de-essed clip's reference level (spec §11 AU-41, AU-42): the
/// clip's `ClipLoudness` reading — the Volume section's Loudness figure,
/// pre-fader, over the window that plays, in the export's layout through pan
/// · fold · pick — which both stages' relative thresholds are added to.
///
/// **Measured once per (cache folder, plan text, the clip's channel
/// matrix).** A trim moves the plan and a pan or a pick moves the matrix, so
/// either measures again; a property edit that moves neither reads the memo.
/// A PENDING answer — no loudness file yet, or no cache folder — is never
/// memoised, and the media files are read through a fresh `MediaCacheLoader`
/// each time (it would hold a miss as pending), so the first ask after the
/// file lands answers measured with no invalidation. Loaded files are kept
/// per cache folder until that media's `loudness` post.
///
/// **The watch.** A `loudness` cache post (a landing or a withdrawal) drops
/// that media's memo and loaded file, then posts `.reversedMediaDidChange`
/// for each open document with a gate or de-esser on that media, so its
/// editor rebuilds with no edit — the plan did not change, the disk did.
///
/// **The export's wait** (`wait`) polls every 0.1 s, never on main, until no
/// clip it names is pending, the caller cancels, or the timeout passes.
///
/// One `NSLock` guards the memo and the files; the files are read and the
/// readings computed outside it.
final class AudioDynamicsLevels {
    static let shared = AudioDynamicsLevels()

    enum Level: Equatable {
        case measured(lufs: Double)
        /// No loudness file yet, or no cache folder published.
        case pending
        /// There will be no reading: why, in a few words.
        case unmeasurable(reason: String)
    }

    enum WaitResult: Equatable {
        case landed
        case cancelled
        /// The first clip (by id) still pending when the time ran out.
        case timedOut(clip: UInt32)
    }

    /// How long an export waits for a clip's loudness (AU-42).
    static let exportTimeout: TimeInterval = 300

    private struct Key: Hashable {
        let cache: String
        let plan: String
    }

    private struct Entry {
        let matrix: ClipLoudness.ChannelMatrix
        let media: UInt32?
        let level: Level
    }

    /// The most (cache, plan) memos kept; the oldest goes first.
    private static let memoCap = 8

    private let lock = NSLock()
    private var memo: [Key: [UInt32: Entry]] = [:]
    private var order: [Key] = []
    private var files: [String: [UInt32: MediaLoudness]] = [:]
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .mediaCacheDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard
                note.userInfo?[MediaImporter.cacheKindKey] as? String
                    == MediaImporter.loudnessKind,
                let media = note.userInfo?[MediaImporter.mediaIDKey] as? UInt32
            else { return }
            self?.loudnessChanged(media: media)
        }
    }

    /// The clips of `snapshot` that ask for a level: not a nest clip (whose
    /// gate and de-esser reach nothing, AU-46), with a gate or a de-esser.
    static func wanting(_ snapshot: ProjectSnapshot) -> [ClipSnapshot] {
        (snapshot.clips + snapshot.nests.flatMap(\.clips)).filter {
            $0.source.nestID == nil && ($0.audio?.gate != nil || $0.audio?.deEsser != nil)
        }
    }

    /// Every wanting clip's level; empty, with no plan decoded, when no clip
    /// wants one.
    func levels(for project: ReelProject, cache: URL?) -> [UInt32: Level] {
        let snapshot = project.snapshot
        let wanted = Self.wanting(snapshot)
        guard !wanted.isEmpty else { return [:] }
        guard let cache else {
            return Dictionary(uniqueKeysWithValues: wanted.map { ($0.id, .pending) })
        }
        let key = Key(cache: cache.standardizedFileURL.path, plan: project.planJSON)

        var result: [UInt32: Level] = [:]
        var missing: [ClipSnapshot] = []
        lock.lock()
        let held = memo[key] ?? [:]
        lock.unlock()
        for clip in wanted {
            if let entry = held[clip.id], entry.matrix == ClipLoudness.ChannelMatrix(clip.audio) {
                result[clip.id] = entry.level
            } else {
                missing.append(clip)
            }
        }
        guard !missing.isEmpty else { return result }

        let segments = project.plan.map(AudioNormalize.audioSegments(in:)) ?? [:]
        let loader = MediaCacheLoader(cacheDirectory: cache) { [weak self] media, url in
            self?.file(media: media, cache: key.cache, url: url)
        }
        var measured: [UInt32: Entry] = [:]
        for clip in missing {
            let level = Self.level(
                ClipLoudness.answer(
                    for: clip.id, snapshot: snapshot, segments: segments, loader: loader))
            result[clip.id] = level
            guard level != .pending else { continue }
            measured[clip.id] = Entry(
                matrix: ClipLoudness.ChannelMatrix(clip.audio),
                media: segments[clip.id]?.first?.media, level: level)
        }
        if !measured.isEmpty { remember(measured, under: key) }
        return result
    }

    /// Blocks the calling thread (never main) until no clip of `clips` is
    /// pending, polling every 0.1 s.
    func wait(
        for clips: Set<UInt32>, in project: ReelProject, cache: URL?, timeout: TimeInterval,
        cancelled: () -> Bool
    ) -> WaitResult {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let levels = levels(for: project, cache: cache)
            let pending = clips.filter { levels[$0] == .pending }
            guard let first = pending.min() else { return .landed }
            if cancelled() { return .cancelled }
            if Date() >= deadline { return .timedOut(clip: first) }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    // MARK: - Inside

    private static func level(_ answer: ClipLoudness.Answer) -> Level {
        switch answer {
        case .pending:
            return .pending
        case .unavailable:
            return .unmeasurable(reason: "it plays no sound in this timeline")
        case .reading(let reading):
            if let lufs = reading.lufs { return .measured(lufs: lufs) }
            return .unmeasurable(
                reason: reading.playedTicks < ClipLoudness.minimumPlayedTicks
                    ? "it plays for under 0.4 s" : "it is too quiet to measure")
        }
    }

    /// A media's loudness file, read once per cache folder; a miss is not
    /// kept.
    private func file(media: UInt32, cache: String, url: URL) -> MediaLoudness? {
        lock.lock()
        let held = files[cache]?[media]
        lock.unlock()
        if let held { return held }
        guard let read = MediaImporter.loadLoudness(for: media, in: url) else { return nil }
        lock.lock()
        files[cache, default: [:]][media] = read
        lock.unlock()
        return read
    }

    private func remember(_ entries: [UInt32: Entry], under key: Key) {
        lock.lock()
        defer { lock.unlock() }
        if memo[key] == nil {
            order.append(key)
            while order.count > Self.memoCap { memo.removeValue(forKey: order.removeFirst()) }
        }
        memo[key, default: [:]].merge(entries) { _, new in new }
    }

    /// A `loudness` post for `media`: its memo and file go, and every open
    /// document with a gate or de-esser on it rebuilds. Main thread.
    private func loudnessChanged(media: UInt32) {
        lock.lock()
        for key in memo.keys {
            memo[key] = memo[key]?.filter { $0.value.media != media }
        }
        for cache in files.keys { files[cache]?.removeValue(forKey: media) }
        lock.unlock()
        for case let document as ProjectDocument in NSDocumentController.shared.documents {
            let gated = Self.wanting(document.project.snapshot).contains {
                $0.source.mediaID == media
            }
            guard gated else { continue }
            NotificationCenter.default.post(name: .reversedMediaDidChange, object: document)
        }
    }
}
