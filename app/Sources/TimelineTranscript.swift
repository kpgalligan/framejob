import Foundation

/// The timeline transcript (road map "creator-jobs" TX1, spec §11 TX-10,
/// TX-13): every heard word of the edited container in timeline order,
/// nested instances included, each with its clip, track, editability and a
/// stable identity. Pure: it is handed the plan, the snapshot and each
/// media's source words, and reads no file, no cache and no window.
///
/// - `read` finds the INSTANCES — the plan's audio segments, each through
///   `Transcriber.jobs`' gate on its inner clip and the envelope's
///   `SilenceDetector.isAudible` — and the clips the gate refuses, found by
///   walking the clips rather than the segments (the core places no segment
///   for a clip with its audio off).
/// - `words` places each media's source words in each instance by R6-10's
///   mapping, orders them (start, end, front track first, source order),
///   counts their identities and asks `TimelineTranscript+Rules.swift`
///   whether each may be cut (TX-11).
/// - `window`, `overlapping`, `page` and `frameFloor` are TX-13's window and
///   paging.
enum TimelineTranscript {

    /// A word's identity (TX-10): the enclosing nest clip ids, the media, the
    /// word's SOURCE start tick and k, the earlier words sharing the other
    /// three. The inner clip's id is left out: a ripple gives every split's
    /// second half a fresh id.
    struct Identity: Hashable {
        let nestPath: [UInt32]
        let media: UInt32
        let source: Ticks
        let k: Int
    }

    /// One word of a media, in its SOURCE ticks. An on-device word's
    /// `source` is its MOVED start (TX-15); `recognisedStart` is the
    /// recogniser's own when TX-15 moved it.
    struct SourceWord: Equatable {
        let text: String
        let source: Ticks
        let sourceEnd: Ticks
        let speaker: String?
        var recognisedStart: Ticks? = nil

        /// The tick an identity, a cut's match and a pause set key by
        /// (TX-17): the recogniser's start, moved or not.
        var identityTick: Ticks { recognisedStart ?? source }
    }

    /// A heard media's words and where they came from.
    struct MediaWords: Equatable {
        let media: UInt32
        let engine: TranscriptionEngine
        let language: String?
        let fillersReported: Bool
        let words: [SourceWord]
        /// An on-device media read with no voice cache: its starts are the
        /// recogniser's, unmoved (TX-18).
        var voiceCacheMissing: Bool = false
    }

    /// One heard instance: a plan audio segment, its inner clip, that clip's
    /// job (in its own container's time) and the CONTAINER track it plays
    /// under, with that track's stacking index.
    struct Instance: Equatable {
        let segment: PlanSegment
        let clip: ClipSnapshot
        let job: Transcriber.Job
        let track: UInt32
        let trackIndex: Int
    }

    /// A media clip the gate refuses, and why.
    struct NoWords: Equatable {
        let clip: UInt32
        let nestPath: [UInt32]
        let tag: String
        let reason: String
    }

    /// One word on the timeline.
    struct Word: Equatable {
        let text: String
        let start: Ticks
        let end: Ticks
        let clip: UInt32
        let track: UInt32
        let media: UInt32
        let engine: TranscriptionEngine
        let filler: Bool
        let speaker: String?
        let editable: Bool
        let why: String?
        let id: Identity
    }

    /// The words one answer carries at most (TX-13).
    static let pageLimit = 2000

    // MARK: - Source words

    /// A cached media transcript's words: each word's start and
    /// `max(start, end)` through `MediaTranscript.sourceTicks`, the one door.
    static func sourceWords(cloud file: MediaTranscript.File) -> [SourceWord] {
        file.words.map {
            SourceWord(
                text: $0.text, source: MediaTranscript.sourceTicks(milliseconds: $0.start),
                sourceEnd: MediaTranscript.sourceTicks(milliseconds: max($0.start, $0.end)),
                speaker: $0.speaker)
        }
    }

    /// A stored on-device run's words, already media source ticks; with
    /// `moved` (`WordOnsets.moved`, one per word), each start moved to its
    /// sound and the recogniser's kept for its identity (TX-15, TX-17).
    static func sourceWords(
        device heard: DeviceTranscriptCache.Heard, moved: [Ticks]? = nil
    ) -> [SourceWord] {
        heard.words.enumerated().map { index, word in
            let end = max(word.start, word.end)
            guard let moved, index < moved.count, moved[index] != word.start else {
                return SourceWord(text: word.text, source: word.start, sourceEnd: end, speaker: nil)
            }
            return SourceWord(
                text: word.text, source: moved[index], sourceEnd: end, speaker: nil,
                recognisedStart: word.start)
        }
    }

    // MARK: - Instances and the clips with no words

    /// Every clip id the container shows, with the nest clip ids leading to
    /// it and the nest that holds it (nil on the container itself): the
    /// container's clips, then recursively every shown nest's, each clip
    /// once, its first path kept.
    static func walk(_ snapshot: ProjectSnapshot)
        -> [(clip: ClipSnapshot, nestPath: [UInt32], nest: NestSnapshot?)]
    {
        var out: [(clip: ClipSnapshot, nestPath: [UInt32], nest: NestSnapshot?)] = []
        var seen = Set<UInt32>()
        func visit(_ clips: [ClipSnapshot], path: [UInt32], nest: NestSnapshot?, open: [UInt32]) {
            for clip in clips.sorted(by: { ($0.start, $0.id) < ($1.start, $1.id) }) {
                if seen.insert(clip.id).inserted { out.append((clip, path, nest)) }
                guard let inner = snapshot.nest(for: clip), !open.contains(inner.id) else {
                    continue
                }
                visit(inner.clips, path: path + [clip.id], nest: inner, open: open + [inner.id])
            }
        }
        visit(snapshot.clips, path: [], nest: nil, open: [])
        return out
    }

    /// The instances the plan's audio segments make, and every media clip
    /// the gate refuses (TX-10). `maps` answers a clip's source map given
    /// the nest clip ids leading to it.
    static func read(
        plan: CompositionPlan, snapshot: ProjectSnapshot, urls: [UInt32: URL],
        maps: (_ clip: UInt32, _ nestPath: [UInt32]) -> SourceMap?
    ) -> (instances: [Instance], noWords: [NoWords]) {
        let walked = walk(snapshot)
        var noWords: [NoWords] = []
        var clips: [UInt32: ClipSnapshot] = [:]
        for entry in walked {
            clips[entry.clip.id] = entry.clip
            guard case .media = entry.clip.source else { continue }
            let path = entry.nestPath
            let gate = Transcriber.jobs(
                for: [entry.clip], in: snapshot, urls: urls, maps: { maps($0, path) })
            guard gate.jobs.isEmpty, let problem = gate.problems.first else { continue }
            let tag = entry.nest.map {
                "clip \(entry.clip.id) in nest \($0.name.isEmpty ? "\($0.id)" : $0.name)"
            } ?? "clip \(entry.clip.id)"
            noWords.append(
                NoWords(clip: entry.clip.id, nestPath: path, tag: tag, reason: problem.reason))
        }
        var instances: [Instance] = []
        for track in plan.audioTracks {
            for segment in track.segments where segment.duration > 0 {
                guard let clip = clips[segment.clip], case .media = clip.source else { continue }
                let nestPath = Array(segment.path.dropLast())
                let gate = Transcriber.jobs(
                    for: [clip], in: snapshot, urls: urls, maps: { maps($0, nestPath) })
                guard let job = gate.jobs.first else { continue }
                let span = (segment.start, segment.start + segment.duration)
                guard SilenceDetector.isAudible(track.ramps, over: span) else { continue }
                let container = track.track ?? clip.track
                instances.append(
                    Instance(
                        segment: segment, clip: clip, job: job, track: container,
                        trackIndex: snapshot.trackIndex(of: container) ?? -1))
            }
        }
        return (instances, noWords)
    }

    // MARK: - Words

    /// Every word of every instance whose media has words, in TX-10's order,
    /// each with its identity and TX-11's editability.
    static func words(
        _ instances: [Instance], media: [UInt32: MediaWords], snapshot: ProjectSnapshot
    ) -> [Word] {
        struct Placed {
            let start: Ticks
            let end: Ticks
            let trackIndex: Int
            let order: Int
            let instance: Int
            let source: SourceWord
            let mediaWords: MediaWords
        }
        var placed: [Placed] = []
        for (number, instance) in instances.enumerated() {
            guard let heard = media[instance.job.media] else { continue }
            let job = instance.job
            let windowEnd = job.sourceIn + job.sourceLength
            let segmentStart = instance.segment.start
            let segmentEnd = segmentStart + instance.segment.duration
            let shift = instance.segment.origin.map { $0 - instance.clip.start }
            for (order, word) in heard.words.enumerated() {
                guard word.source >= job.sourceIn, word.source < windowEnd else { continue }
                var start = MediaTranscript.project(word.source, in: job)
                var end = MediaTranscript.project(max(word.source, word.sourceEnd), in: job)
                if let shift {
                    start += shift
                    end += shift
                    guard start >= segmentStart, start < segmentEnd else { continue }
                }
                placed.append(
                    Placed(
                        start: start, end: end, trackIndex: instance.trackIndex, order: order,
                        instance: number, source: word, mediaWords: heard))
            }
        }
        placed.sort {
            ($0.start, $0.end, -$0.trackIndex, $0.order, $0.instance)
                < ($1.start, $1.end, -$1.trackIndex, $1.order, $1.instance)
        }
        let walls = SilenceDetector.overlapWalls(snapshot)
        var counts: [Identity: Int] = [:]
        return placed.map { p in
            let instance = instances[p.instance]
            let nestPath = Array(instance.segment.path.dropLast())
            let key = Identity(
                nestPath: nestPath, media: instance.job.media, source: p.source.identityTick, k: 0)
            let k = counts[key, default: 0]
            counts[key] = k + 1
            let why = whyNotEditable(
                start: p.start, end: p.end, nestPath: nestPath, track: instance.track,
                snapshot: snapshot, walls: walls)
            return Word(
                text: p.source.text, start: p.start, end: p.end, clip: instance.clip.id,
                track: instance.track, media: instance.job.media, engine: p.mediaWords.engine,
                filler: FillerWords.isFiller(p.source.text), speaker: p.source.speaker,
                editable: why == nil, why: why,
                id: Identity(
                    nestPath: nestPath, media: instance.job.media, source: p.source.identityTick,
                    k: k))
        }
    }

    // MARK: - The window and paging (TX-13)

    /// Why a window names no part of the timeline.
    enum WindowError: LocalizedError, Equatable {
        case outside(from: Ticks?, to: Ticks?, duration: Ticks)

        var errorDescription: String? {
            switch self {
            case .outside(let from, let to, let duration):
                let bounds = [from.map { "from \($0)" }, to.map { "to \($0)" }]
                    .compactMap { $0 }.joined(separator: " ")
                return "The window \(bounds) is outside the timeline, which runs from 0 to "
                    + "\(duration) ticks."
            }
        }
    }

    /// TR-13's window over the container: nil with neither bound; `to` not
    /// after `from` refused as TR-13's `.empty`; clamped to [0, duration);
    /// nothing left refused as `.outside`.
    static func window(from: Ticks?, to: Ticks?, duration: Ticks) throws -> TranscriptReader.Window? {
        guard from != nil || to != nil else { return nil }
        if let from, let to, to <= from {
            throw TranscriptReader.WindowError.empty(from: from, to: to)
        }
        let lower = max(from ?? 0, 0)
        let upper = min(to ?? duration, duration)
        guard lower < upper else {
            throw WindowError.outside(from: from, to: to, duration: duration)
        }
        return TranscriptReader.Window(from: lower, to: upper)
    }

    /// TR-13's overlap rule: a word across an edge is kept whole; a word with
    /// no length belongs when from <= its start < to.
    static func overlapping(_ words: [Word], in window: TranscriptReader.Window) -> [Word] {
        words.filter { $0.start < window.to && max($0.end, $0.start + 1) > window.from }
    }

    /// The largest frame boundary at or before `t`, on the canvas's grid
    /// through `ReelTime.snapToFrame` — so the nearest-frame snap of a
    /// `from` returns it unchanged.
    static func frameFloor(_ t: Ticks, fps: Fps) -> Ticks {
        let nearest = ReelTime.snapToFrame(t, fps: fps)
        guard nearest > t else { return nearest }
        return ReelTime.snapToFrame(nearest - max(1, fps.frameDuration), fps: fps)
    }

    /// One page of `words` (already windowed): all of them when they fit;
    /// else the first `pageLimit`, cut back until the next word's frame
    /// floor is past the last kept word's, and `nextFrom` that floor. A cut
    /// that would empty the page keeps it whole, and `nextFrom` is then the
    /// frame boundary after its last word's frame.
    static func page(_ words: [Word], fps: Fps) -> (words: [Word], nextFrom: Ticks?) {
        guard words.count > pageLimit else { return (words, nil) }
        var count = pageLimit
        while count > 0,
            frameFloor(words[count].start, fps: fps) <= frameFloor(words[count - 1].start, fps: fps)
        {
            count -= 1
        }
        if count == 0 {
            let last = frameFloor(words[pageLimit - 1].start, fps: fps)
            let next = ReelTime.snapToFrame(last + max(1, fps.frameDuration), fps: fps)
            return (Array(words.prefix(pageLimit)), next)
        }
        return (Array(words.prefix(count)), frameFloor(words[count].start, fps: fps))
    }
}
