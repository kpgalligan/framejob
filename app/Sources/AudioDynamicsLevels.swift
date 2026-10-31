import AppKit
import Foundation

/// Each gated, levelled or de-essed clip's reference level (spec §11 AU-41,
/// AU-42, AU-66): the clip's `ClipLoudness` reading — the Volume section's
/// Loudness figure, pre-fader, over the window that plays, in the export's
/// layout through pan · fold · pick — which the three stages' relative
/// thresholds (and the leveller's target) are added to.
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
/// **The leveller's curves** (AU-66 (e), `curves`) are made beside L from
/// the same reading and the clip's speech mask, one per response its base and
/// its ends name, and memoised the same way with the `media.speech` they used:
/// a change of it makes them again. Without spans they are pending while
/// speech detection can still land a VAD file, and unmeasurable when it
/// cannot (`SileroVAD.isAvailable`, read on each call).
///
/// **The watch.** A `loudness` cache post (a landing or a withdrawal) drops
/// that media's memo, curves and loaded file, then posts
/// `.reversedMediaDidChange` for each open document with a gate, leveller or
/// de-esser on that media, so its editor rebuilds with no edit — the plan did
/// not change, the disk did. A `speech` post drops its curves and rebuilds
/// each document levelling it.
///
/// **The export's wait** (`wait`) polls every 0.1 s, never on main, until no
/// clip it names has a pending level or curve, the caller cancels, or the
/// timeout passes.
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

    /// A clip's curves and what they were made from: the matrix, the media,
    /// the `media.speech` read (nil: the VAD file's), the responses.
    private struct CurveEntry {
        let matrix: ClipLoudness.ChannelMatrix
        let media: UInt32?
        let speech: [[Ticks]]?
        let responses: Set<Ticks>
        let curves: Curves
    }

    /// The most (cache, plan) memos kept; the oldest goes first.
    private static let memoCap = 8

    private let lock = NSLock()
    private var memo: [Key: [UInt32: Entry]] = [:]
    private var order: [Key] = []
    private var curveMemo: [Key: [UInt32: CurveEntry]] = [:]
    private var curveOrder: [Key] = []
    private var files: [String: [UInt32: MediaLoudness]] = [:]
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .mediaCacheDidChange, object: nil, queue: .main
        ) { [weak self] note in
            let kind = note.userInfo?[MediaImporter.cacheKindKey] as? String
            guard
                kind == MediaImporter.loudnessKind || kind == MediaImporter.speechKind,
                let media = note.userInfo?[MediaImporter.mediaIDKey] as? UInt32
            else { return }
            self?.cacheChanged(media: media, loudness: kind == MediaImporter.loudnessKind)
        }
    }

    /// The clips of `snapshot` that ask for a level: not a nest clip (whose
    /// gate, leveller and de-esser reach nothing, AU-46, AU-66), with a gate,
    /// a leveller or a de-esser on the base or keyed on at any action's end
    /// (AU-88).
    static func wanting(_ snapshot: ProjectSnapshot) -> [ClipSnapshot] {
        func ended(_ clip: ClipSnapshot) -> Bool {
            clip.actions.contains {
                if case .some(.some) = $0.end.audio?.gate { return true }
                if case .some(.some) = $0.end.audio?.leveller { return true }
                if case .some(.some) = $0.end.audio?.deEsser { return true }
                return false
            }
        }
        return (snapshot.clips + snapshot.nests.flatMap(\.clips)).filter {
            $0.source.nestID == nil
                && ($0.audio?.gate != nil || $0.audio?.leveller != nil
                    || $0.audio?.deEsser != nil || ended($0))
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
            let curves = curves(for: project, cache: cache)
            let pending = clips.filter {
                if case .pending = curves[$0] { return true }
                return levels[$0] == .pending
            }
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

    /// A `loudness` or `speech` post for `media`: its curves go, and on a
    /// `loudness` post its levels and file too; every open document with a
    /// gate, leveller or de-esser on it rebuilds (a leveller alone on a
    /// `speech` post). Main thread.
    private func cacheChanged(media: UInt32, loudness: Bool) {
        lock.lock()
        for key in curveMemo.keys {
            curveMemo[key] = curveMemo[key]?.filter { $0.value.media != media }
        }
        if loudness {
            for key in memo.keys {
                memo[key] = memo[key]?.filter { $0.value.media != media }
            }
            for cache in files.keys { files[cache]?.removeValue(forKey: media) }
        }
        lock.unlock()
        for case let document as ProjectDocument in NSDocumentController.shared.documents {
            // A speech post moves only the leveller's curves.
            let snapshot = document.project.snapshot
            let clips = loudness ? Self.wanting(snapshot) : Self.levelling(snapshot)
            let gated = clips.contains { $0.source.mediaID == media }
            guard gated else { continue }
            NotificationCenter.default.post(name: .reversedMediaDidChange, object: document)
        }
    }
}

// MARK: - The leveller's curves (AU-66 (e))

extension AudioDynamicsLevels {
    enum Curves: Equatable {
        /// The clip's curve for each response it names.
        case ready([Ticks: AudioLevellerCurve])
        /// "loudness" or "speech": what it waits for.
        case pending(what: String)
        case unmeasurable(reason: String)
    }

    /// Why a clip with no spans is not levelled where no VAD file can land.
    static let noSpeechDetection = "speech detection is unavailable"

    /// The clips of `snapshot` with a leveller on the base or keyed on at any
    /// action's end, never a nest clip (whose leveller reaches nothing).
    static func levelling(_ snapshot: ProjectSnapshot) -> [ClipSnapshot] {
        (snapshot.clips + snapshot.nests.flatMap(\.clips)).filter { clip in
            clip.source.nestID == nil
                && (clip.audio?.leveller != nil
                    || clip.actions.contains {
                        if case .some(.some) = $0.end.audio?.leveller { return true }
                        return false
                    })
        }
    }

    /// The responses a clip's curves are made for: its base's and each
    /// end's, each in the model's range — every value an automation point
    /// can carry (an end that names no response holds one of these).
    private static func responses(_ clip: ClipSnapshot) -> Set<Ticks> {
        var made: Set<Ticks> = [AudioLevellerSettings.response(clip.audio?.leveller ?? LevellerProps())]
        for action in clip.actions {
            if case .some(.some(let end)) = action.end.audio?.leveller {
                made.insert(AudioLevellerSettings.response(end))
            }
        }
        return made
    }

    /// Every levelling clip's curves; empty, with no plan decoded, when no
    /// clip levels. `speechDetection` is whether a VAD file can still land
    /// (read on each call; a probe passes it).
    func curves(
        for project: ReelProject, cache: URL?, speechDetection: Bool = SileroVAD.isAvailable
    ) -> [UInt32: Curves] {
        let snapshot = project.snapshot
        let wanted = Self.levelling(snapshot)
        guard !wanted.isEmpty else { return [:] }
        guard let cache else {
            return Dictionary(uniqueKeysWithValues: wanted.map { ($0.id, .pending(what: "loudness")) })
        }
        let key = Key(cache: cache.standardizedFileURL.path, plan: project.planJSON)
        var result: [UInt32: Curves] = [:]
        var missing: [ClipSnapshot] = []
        lock.lock()
        let held = curveMemo[key] ?? [:]
        lock.unlock()
        for clip in wanted {
            if let entry = held[clip.id], entry.matrix == ClipLoudness.ChannelMatrix(clip.audio),
                entry.speech == entry.media.flatMap({ snapshot.media($0)?.speech }),
                entry.responses == Self.responses(clip) {
                result[clip.id] = entry.curves
            } else {
                missing.append(clip)
            }
        }
        guard !missing.isEmpty else { return result }

        let segments = project.plan.map(AudioNormalize.audioSegments(in:)) ?? [:]
        let loader = MediaCacheLoader(cacheDirectory: cache) { [weak self] media, url in
            self?.file(media: media, cache: key.cache, url: url)
        }
        var made: [UInt32: CurveEntry] = [:]
        for clip in missing {
            let own = (segments[clip.id] ?? []).filter { $0.media == segments[clip.id]?.first?.media }
            let media = own.first.flatMap { snapshot.media($0.media) }
            let responses = Self.responses(clip)
            let curves = Self.curves(
                ClipLoudness.answer(for: clip.id, snapshot: snapshot, segments: segments, loader: loader),
                own: own, media: media, cache: cache, responses: responses,
                speechDetection: speechDetection)
            result[clip.id] = curves
            // Neither waiting nor speech detection's absence is kept: each is
            // asked again on the next call (AU-66 (e)).
            if case .pending = curves { continue }
            if curves == .unmeasurable(reason: Self.noSpeechDetection) { continue }
            made[clip.id] = CurveEntry(
                matrix: ClipLoudness.ChannelMatrix(clip.audio), media: media?.id,
                speech: media?.speech, responses: responses, curves: curves)
        }
        if !made.isEmpty {
            lock.lock()
            if curveMemo[key] == nil {
                curveOrder.append(key)
                while curveOrder.count > Self.memoCap {
                    curveMemo.removeValue(forKey: curveOrder.removeFirst())
                }
            }
            curveMemo[key, default: [:]].merge(made) { _, new in new }
            lock.unlock()
        }
        return result
    }

    /// One clip's curves from its loudness answer and its media's spans.
    private static func curves(
        _ answer: ClipLoudness.Answer, own: [PlanSegment], media: MediaSnapshot?, cache: URL,
        responses: Set<Ticks>, speechDetection: Bool
    ) -> Curves {
        let reading: ClipLoudness.Reading
        switch level(answer) {
        case .pending: return .pending(what: "loudness")
        case .unmeasurable(let reason): return .unmeasurable(reason: reason)
        case .measured:
            guard case .reading(let read) = answer else { return .pending(what: "loudness") }
            reading = read
        }
        guard let media, let L = reading.lufs else {
            return .unmeasurable(reason: "it plays no sound in this timeline")
        }
        guard let spans = media.speech ?? AudioEnhance.speechSpans(media, cache: cache) else {
            return speechDetection
                ? .pending(what: "speech") : .unmeasurable(reason: noSpeechDetection)
        }
        let mask = AudioEnhance.speechMask(sources: reading.stepSources, spans: spans)
        var made: [Ticks: AudioLevellerCurve] = [:]
        for response in responses {
            guard
                let curve = AudioLevellerCurve.make(
                    reading: reading, segments: own, speech: mask, level: L, response: response)
            else { return .unmeasurable(reason: "it has no phrase with 1 s of speech") }
            made[response] = curve
        }
        return .ready(made)
    }
}
