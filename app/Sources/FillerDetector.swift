import Foundation

/// Remove Filler Words' detector (road map "cut-by-transcript" CT-2, spec §11
/// TR-4, TR-7, TR-9): a clip's cached cloud filler words as project ranges
/// `ripple_delete_ranges` cuts, every edge on the Silero 32 ms grid and then
/// on the frame grid.
///
/// `SilenceDetector`'s shape: `read(from:clips:)` is the one seam that touches
/// a document — its snapshot, its selection, its media URLs and the transcript
/// cache, read ONCE — and everything after it (`runs`, `gridded`, `placed`,
/// `detect`) is arithmetic over values. The words are a Swift cache like the
/// peaks (spec §7), so nothing here crosses the FFI.
///
/// **Only a transcript that asked for fillers is read** (TR-7): the scope's
/// files come through `fillersFile`, whose marker must serve `.fillers`
/// (TR-2's one rule, `TranscriptStamp.serves`). A media without one is named
/// in `needsTranscript` and gives no candidate. The NEIGHBOURS' words — which
/// protect a span from a cut — are taken from any transcript that serves
/// `.captions`, because a word is a word whichever request heard it.
///
/// **TR-9, the edges.** A run of consecutive fillers is widened OUTWARD to the
/// grid so the whole filler goes, but never past the words beside it; each
/// edge then maps to project time through `MediaTranscript.project` (R6-10's
/// door) and snaps INWARD to the frame grid, as Remove Silences snaps. A
/// candidate that would cut into another clip's word, a nest clip or a
/// transition is dropped whole, never trimmed, so every kept edge is a grid
/// edge.
enum FillerDetector {

    /// The Silero VAD's chunk in source ticks (512 samples at 16 kHz), from
    /// absolute source time 0 — the speech cache's own index.
    static var grid: Ticks { MediaSpeech.chunkTicks }

    /// Which clips were read: the ones named or selected, or every clip.
    enum Scope: String { case selected, all }

    /// One clip's job and the transcript file of its media.
    struct ClipWords {
        let job: Transcriber.Job
        let file: MediaTranscript.File
    }

    /// Everything a detection reads, taken off the document once.
    struct Input {
        let fps: Fps
        let scope: Scope
        /// The scope's clips whose media has a transcript that asked for fillers.
        let clips: [ClipWords]
        /// Media ids in scope with no such transcript, sorted and distinct.
        let needsTranscript: [UInt32]
        /// The named clips `Transcriber.jobs` refused, each with its reason.
        let skipped: [CaptionLayout.Problem]
        /// In-scope clip ids on locked tracks, sorted: the ripple neither cuts
        /// nor moves a locked track, so their fillers are not read.
        let locked: [UInt32]
        /// Every top-level clip on an unlocked track whose media's transcript
        /// serves `.captions`, in scope or not: the ripple cuts every
        /// unlocked track, so their words protect a span.
        let neighbours: [ClipWords]
        let nests: [SilenceDetector.NestExtent]
        let walls: [SilenceDetector.Span]
    }

    /// One run of consecutive fillers in a clip's word order, in source ticks.
    struct Run: Equatable {
        let words: [String]
        let source: SilenceDetector.Span
        /// The latest end of a non-filler word before the run, or the clip's `in`.
        let previousEnd: Ticks
        /// The earliest start of a non-filler word after it, or the window's end.
        let nextStart: Ticks
    }

    /// A run that became a cut: its source span on the grid and its project span.
    struct Candidate: Equatable {
        let clip: UInt32
        let words: [String]
        let source: SilenceDetector.Span
        let span: SilenceDetector.Span
    }

    enum DropReason: Equatable {
        case tooShort
        case overlapsWord(clip: UInt32, text: String)
        case nest(clip: UInt32)
        case transition
    }

    struct Dropped: Equatable {
        let clip: UInt32
        let words: [String]
        let reason: DropReason
    }

    struct Outcome {
        /// The kept candidates merged where they overlap or touch.
        let spans: [SilenceDetector.Span]
        let candidates: [Candidate]
        let dropped: [Dropped]
        let scope: Scope
        /// The clips whose words were read, sorted.
        let clips: [UInt32]
        let needsTranscript: [UInt32]
        let skipped: [CaptionLayout.Problem]
        let locked: [UInt32]

        var removed: Ticks { spans.reduce(0) { $0 + $1.length } }
    }

    // MARK: - The read

    /// The document's snapshot, scope and transcript cache, read once.
    ///
    /// Named clips are the scope (`.selected`); with none named, the
    /// selection when `Transcriber.jobs` accepts any of it, else every clip.
    /// The EDITED project, as `SilenceDetector.read` takes it: with a nest
    /// open the ranges are the nest's, in the nest's own time.
    static func read(from document: ProjectDocument, clips named: [UInt32]?) -> Input {
        let snapshot = document.editedProject.snapshot
        let urls = document.mediaURLs()
        let scope: Scope
        let chosen: [ClipSnapshot]
        if let named {
            let ids = Set(named)
            chosen = snapshot.clips.filter { ids.contains($0.id) }
            scope = .selected
        } else {
            let selected = snapshot.clips.filter { document.selection.contains($0.id) }
            if !Transcriber.jobs(for: selected, in: snapshot, urls: urls).jobs.isEmpty {
                chosen = selected
                scope = .selected
            } else {
                chosen = snapshot.clips
                scope = .all
            }
        }
        let (kept, locked) = onUnlockedTracks(chosen, in: snapshot)
        let (jobs, problems) = Transcriber.jobs(for: kept, in: snapshot, urls: urls)
        let cacheDirectory = document.cacheDirectory

        var clips: [ClipWords] = []
        var needs: Set<UInt32> = []
        var scopeFiles: [UInt32: MediaTranscript.File?] = [:]
        for job in jobs {
            if scopeFiles[job.media] == nil {
                scopeFiles[job.media] = .some(
                    cacheDirectory.flatMap { cache in
                        snapshot.media(job.media).flatMap {
                            fillersFile(for: $0, url: job.source, in: cache)
                        }
                    })
            }
            if let file = scopeFiles[job.media] ?? nil {
                clips.append(ClipWords(job: job, file: file))
            } else {
                needs.insert(job.media)
            }
        }

        var neighbours: [ClipWords] = []
        if let cacheDirectory {
            let unlocked = onUnlockedTracks(snapshot.clips, in: snapshot).kept
            var files: [UInt32: MediaTranscript.File?] = [:]
            for job in Transcriber.jobs(for: unlocked, in: snapshot, urls: urls).jobs {
                if files[job.media] == nil {
                    files[job.media] = .some(
                        snapshot.media(job.media).flatMap {
                            transcriptFile(
                                for: $0, url: job.source, in: cacheDirectory, use: .captions)
                        })
                }
                if let file = files[job.media] ?? nil {
                    neighbours.append(ClipWords(job: job, file: file))
                }
            }
        }
        return Input(
            fps: snapshot.canvas.fps, scope: scope, clips: clips, needsTranscript: needs.sorted(),
            skipped: named == nil ? [] : problems, locked: locked, neighbours: neighbours,
            nests: SilenceDetector.nestExtents(in: snapshot),
            walls: SilenceDetector.overlapWalls(snapshot))
    }

    /// The scope's door: a media's transcript only when its marker serves
    /// filler removal (TR-7, TR-2).
    static func fillersFile(
        for media: MediaSnapshot, url: URL, in cacheDir: URL
    ) -> MediaTranscript.File? {
        transcriptFile(for: media, url: url, in: cacheDir, use: .fillers)
    }

    /// A media's cached transcript when the file as it is NOW stamps the
    /// marker's source, the file reads, and the marker serves `use` for the
    /// request the file records; else nil.
    static func transcriptFile(
        for media: MediaSnapshot, url: URL, in cacheDir: URL, use: TranscriptUse
    ) -> MediaTranscript.File? {
        guard let stamp = MediaImporter.CacheStamp.stamp(for: media, url: url),
            let file = MediaTranscript.read(for: media.id, in: cacheDir),
            let marker = MediaTranscript.readStamp(for: media.id, in: cacheDir),
            marker.serves(TranscriptStamp(source: stamp, options: file.header.requested), for: use)
        else { return nil }
        return file
    }

    /// The clips not on a locked track, and the ids of those that are,
    /// sorted. A track the snapshot cannot find counts as unlocked, as the
    /// nest walls read it.
    static func onUnlockedTracks(
        _ clips: [ClipSnapshot], in snapshot: ProjectSnapshot
    ) -> (kept: [ClipSnapshot], locked: [UInt32]) {
        var kept: [ClipSnapshot] = []
        var locked: [UInt32] = []
        for clip in clips {
            if snapshot.track(clip.track)?.locked == true {
                locked.append(clip.id)
            } else {
                kept.append(clip)
            }
        }
        return (kept, locked.sorted())
    }

    // MARK: - The arithmetic

    /// One word of a clip's window, in source ticks.
    private struct Timed {
        let text: String
        let start: Ticks
        let end: Ticks
        let filler: Bool
    }

    /// The clip's words in source ticks: those whose start is in its window
    /// (R6-10), sorted by start then end.
    private static func timed(_ file: MediaTranscript.File, in job: Transcriber.Job) -> [Timed] {
        let windowEnd = job.sourceIn + job.sourceLength
        var out: [Timed] = []
        for word in file.words {
            let start = MediaTranscript.sourceTicks(milliseconds: word.start)
            guard start >= job.sourceIn, start < windowEnd else { continue }
            out.append(
                Timed(
                    text: word.text, start: start,
                    end: MediaTranscript.sourceTicks(milliseconds: max(word.start, word.end)),
                    filler: FillerWords.isFiller(word.text)))
        }
        return out.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// Every maximal run of consecutive fillers in the clip's word order,
    /// with the non-filler words that bound it (TR-9).
    static func runs(of file: MediaTranscript.File, in job: Transcriber.Job) -> [Run] {
        let words = timed(file, in: job)
        let windowEnd = job.sourceIn + job.sourceLength
        // The latest non-filler end before each index, and the earliest
        // non-filler start after it.
        var before = [Ticks](repeating: job.sourceIn, count: words.count + 1)
        for (index, word) in words.enumerated() {
            before[index + 1] = word.filler ? before[index] : max(before[index], word.end)
        }
        var after = [Ticks](repeating: windowEnd, count: words.count + 1)
        for index in stride(from: words.count - 1, through: 0, by: -1) {
            let word = words[index]
            after[index] = word.filler ? after[index + 1] : min(after[index + 1], word.start)
        }
        var runs: [Run] = []
        var open: [Int] = []
        func close() {
            guard let first = open.first, let last = open.last else { return }
            runs.append(
                Run(
                    words: open.map { words[$0].text },
                    source: SilenceDetector.Span(
                        start: words[first].start, end: open.map { words[$0].end }.max() ?? 0),
                    previousEnd: before[first], nextStart: after[last + 1]))
            open = []
        }
        for (index, word) in words.enumerated() {
            guard word.filler else {
                close()
                continue
            }
            open.append(index)
        }
        close()
        return runs
    }

    private static func down(_ t: Ticks, _ grid: Ticks) -> Ticks {
        let q = t / grid
        return (t % grid != 0 && t < 0 ? q - 1 : q) * grid
    }

    private static func up(_ t: Ticks, _ grid: Ticks) -> Ticks {
        let q = t / grid
        return (t % grid != 0 && t > 0 ? q + 1 : q) * grid
    }

    /// A run's source span widened outward to the grid, bounded by its
    /// neighbours' grid points inward; nil when nothing is left.
    static func gridded(_ run: Run, grid: Ticks) -> SilenceDetector.Span? {
        guard grid > 0 else { return nil }
        let start = max(down(run.source.start, grid), up(run.previousEnd, grid))
        let end = min(up(run.source.end, grid), down(run.nextStart, grid))
        guard end > start else { return nil }
        return SilenceDetector.Span(start: start, end: end)
    }

    /// A source span in project time, its start snapped up and its end down
    /// to the frame grid; nil when nothing is left.
    static func placed(
        _ source: SilenceDetector.Span, in job: Transcriber.Job, fps: Fps
    ) -> SilenceDetector.Span? {
        let span = SilenceDetector.Span(
            start: SilenceDetector.snapUpToFrame(
                MediaTranscript.project(source.start, in: job), fps: fps),
            end: SilenceDetector.snapDownToFrame(
                MediaTranscript.project(source.end, in: job), fps: fps))
        guard span.end > span.start else { return nil }
        return span
    }

    // MARK: - Detection

    /// The candidates, what was dropped and why, and the merged ranges.
    static func detect(_ input: Input) -> Outcome {
        // Every neighbour's non-filler words in project time, read once.
        let guarded: [(clip: UInt32, words: [CaptionCues.Word])] = input.neighbours.map {
            ($0.job.clip,
             MediaTranscript.words(for: $0.job, in: $0.file).filter {
                 !FillerWords.isFiller($0.text)
             })
        }
        var candidates: [Candidate] = []
        var dropped: [Dropped] = []
        for clip in input.clips {
            let id = clip.job.clip
            for run in runs(of: clip.file, in: clip.job) {
                guard let source = gridded(run, grid: grid),
                    let span = placed(source, in: clip.job, fps: input.fps)
                else {
                    dropped.append(Dropped(clip: id, words: run.words, reason: .tooShort))
                    continue
                }
                if let reason = conflict(span, clip: id, guarded: guarded, input: input) {
                    dropped.append(Dropped(clip: id, words: run.words, reason: reason))
                    continue
                }
                candidates.append(Candidate(clip: id, words: run.words, source: source, span: span))
            }
        }
        return Outcome(
            spans: SilenceDetector.merged(candidates.map(\.span)), candidates: candidates,
            dropped: dropped, scope: input.scope,
            clips: Set(input.clips.map { $0.job.clip }).sorted(),
            needsTranscript: input.needsTranscript, skipped: input.skipped, locked: input.locked)
    }

    /// Why a span may not be cut, in TR-9's order: another clip's word, a
    /// nest clip, a transition wall; nil when it may.
    private static func conflict(
        _ span: SilenceDetector.Span, clip: UInt32,
        guarded: [(clip: UInt32, words: [CaptionCues.Word])], input: Input
    ) -> DropReason? {
        for neighbour in guarded where neighbour.clip != clip {
            if let word = neighbour.words.first(where: {
                SilenceDetector.overlap(span, SilenceDetector.Span(start: $0.start, end: $0.end)) > 0
            }) {
                return .overlapsWord(clip: neighbour.clip, text: word.text)
            }
        }
        if let nest = input.nests.first(where: { SilenceDetector.overlap(span, $0.span) > 0 }) {
            return .nest(clip: nest.clip)
        }
        if input.walls.contains(where: { SilenceDetector.overlap(span, $0) > 0 }) {
            return .transition
        }
        return nil
    }
}
