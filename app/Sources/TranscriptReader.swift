import Foundation

/// `get_transcript`'s reader (road map "cut-by-transcript" CT-4, spec §11
/// TR-11): one clip's words in TIMELINE ticks, each flagged by TR-8's filler
/// rule, from the media's cached transcript or else from this Mac's
/// recogniser over the clip's own window. Never the network (TR-5), and no
/// cache is written.
///
/// Three pieces, kept apart so a probe can reach each one:
/// - `cached(for:url:in:)` is the cache DOOR, and it is `FillerDetector`'s
///   (TR-2's one marker rule, R6-15), not a new one: a transcript is read
///   only when its marker serves `.captions` for the file as it is now.
/// - `cloudWords` and `deviceWords` are the pure MAPPING, R6-10's two
///   conversions (`MediaTranscript.words(for:in:)` for a cached media
///   transcript, `Transcriber.project` for an extract's seconds), sorted the
///   same way and flagged the same way.
/// - `recognize` is the on-device RUN, `Transcriber.transcribe`'s model
///   questions and its one-job body without the caption paging: blocking,
///   off main, its temporary WAV removed on every exit.
enum TranscriptReader {

    /// One word of the clip, in project (timeline) ticks.
    struct Word: Equatable {
        let text: String
        let start: Ticks
        let end: Ticks
        /// The cached word's speaker label; nil for the on-device engine.
        let speaker: String?
        /// TR-8's spelling (`FillerWords.isFiller`), for either engine.
        let filler: Bool
    }

    /// A media's current cached transcript, and whether it was asked for
    /// filler words.
    struct Cached {
        let file: MediaTranscript.File
        let fillersReported: Bool
    }

    // MARK: - The cache door

    /// The media's cached transcript when its marker serves captions for the
    /// file as it is now; nil when there is none, it does not read, or the
    /// source has changed under it. `fillersReported` is whether the same
    /// cache also serves filler removal (TR-7's door).
    static func cached(for media: MediaSnapshot, url: URL, in cacheDir: URL) -> Cached? {
        guard
            let file = FillerDetector.transcriptFile(
                for: media, url: url, in: cacheDir, use: .captions)
        else { return nil }
        let fillers = FillerDetector.fillersFile(for: media, url: url, in: cacheDir) != nil
        return Cached(file: file, fillersReported: fillers)
    }

    // MARK: - The mapping

    /// A cached media transcript's words for one clip: R6-10's mapping
    /// (`MediaTranscript.words(for:in:)` — a word is the clip's when its
    /// start is in the clip's source window), sorted by start, then end,
    /// then the file's own order.
    static func cloudWords(for job: Transcriber.Job, in file: MediaTranscript.File) -> [Word] {
        let mapped = MediaTranscript.words(for: job, in: file).enumerated().map {
            (index: $0.offset,
             word: Word(
                text: $0.element.text, start: $0.element.start, end: $0.element.end,
                speaker: $0.element.speaker, filler: FillerWords.isFiller($0.element.text)))
        }
        return sortedWords(mapped)
    }

    /// An on-device run's tokens for one clip: each second into the extract
    /// through `Transcriber.project`, a token whose mapped start is at or
    /// past the clip's end dropped (the extract can run past the window),
    /// sorted as `cloudWords` sorts.
    static func deviceWords(_ runs: [SpeechEngine.Run], for job: Transcriber.Job) -> [Word] {
        let end = job.start + job.duration
        var mapped: [(index: Int, word: Word)] = []
        for (index, run) in runs.enumerated() {
            let start = Transcriber.project(run.start, in: job)
            guard start < end else { continue }
            mapped.append(
                (index,
                 Word(
                    text: run.text, start: start, end: Transcriber.project(run.end, in: job),
                    speaker: nil, filler: FillerWords.isFiller(run.text))))
        }
        return sortedWords(mapped)
    }

    /// By (start, end, source order).
    private static func sortedWords(_ words: [(index: Int, word: Word)]) -> [Word] {
        words.sorted {
            ($0.word.start, $0.word.end, $0.index) < ($1.word.start, $1.word.end, $1.index)
        }.map(\.word)
    }

    // MARK: - The window

    /// A part of the timeline, [from, to) in project ticks, already clamped
    /// to the clip (spec §11 TR-13).
    struct Window: Equatable {
        let from: Ticks
        let to: Ticks
    }

    /// Why a `from`/`to` pair names no part of the clip, in TR-13's
    /// sentences (the dispatcher puts the tool's name in front).
    enum WindowError: LocalizedError, Equatable {
        case empty(from: Ticks, to: Ticks)
        case outside(from: Ticks?, to: Ticks?, clip: UInt32, start: Ticks, end: Ticks)

        var errorDescription: String? {
            switch self {
            case .empty(let from, let to):
                return "to must be after from: the window from \(from) to \(to) ticks "
                    + "(both snapped to frames) is empty."
            case .outside(let from, let to, let clip, let start, let end):
                let bounds = [from.map { "from \($0)" }, to.map { "to \($0)" }]
                    .compactMap { $0 }.joined(separator: " ")
                return "The window \(bounds) is outside clip \(clip), which plays from \(start) "
                    + "to \(end) ticks."
            }
        }
    }

    /// The window a call's (already snapped) bounds name on this clip; nil
    /// when it gave neither. A missing `from` is the clip's start, a missing
    /// `to` its end, and the window is clamped into the clip. Refused as
    /// `.empty` when both were given and `to` is not after `from` (checked
    /// first), and as `.outside` when nothing is left once clamped.
    static func window(from: Ticks?, to: Ticks?, clip job: Transcriber.Job) throws -> Window? {
        guard from != nil || to != nil else { return nil }
        if let from, let to, to <= from { throw WindowError.empty(from: from, to: to) }
        let clipEnd = job.start + job.duration
        let lower = max(from ?? job.start, job.start)
        let upper = min(to ?? clipEnd, clipEnd)
        guard lower < upper else {
            throw WindowError.outside(
                from: from, to: to, clip: job.clip, start: job.start, end: clipEnd)
        }
        return Window(from: lower, to: upper)
    }

    /// The words that overlap the window, in their input order and
    /// unchanged: a word across an edge is kept whole, with its own times. A
    /// word with no length belongs when from <= its start < to.
    static func overlapping(_ words: [Word], in window: Window) -> [Word] {
        words.filter { word in
            word.start < window.to && max(word.end, word.start + 1) > window.from
        }
    }

    /// The SOURCE seconds an on-device run hears either side of a window.
    static let recognitionPadSeconds: Double = 2

    /// The sub-job a windowed on-device run hears: the window widened by
    /// `recognitionPadSeconds` of source on each side, clamped to the clip.
    /// Its `sourceIn` is the padded start's own source time, so the extract
    /// still begins at the job's `in` point — `Transcriber.project`'s premise.
    /// The whole clip answers `job` itself.
    static func recognitionJob(_ job: Transcriber.Job, for window: Window) -> Transcriber.Job {
        let speed = job.speed.isFinite && job.speed > 0 ? job.speed : 1
        let pad = Ticks((recognitionPadSeconds * Double(ReelTime.perSecond) / speed).rounded(.up))
        let clipEnd = job.start + job.duration
        let start = max(job.start, window.from - pad)
        let end = min(clipEnd, window.to + pad)
        if start == job.start && end == clipEnd { return job }
        let sourceIn = job.sourceIn + Ticks((Double(start - job.start) * speed).rounded())
        let sourceLength = end < clipEnd
            ? Ticks((Double(end - start) * speed).rounded())
            : job.sourceIn + job.sourceLength - sourceIn
        return Transcriber.Job(
            clip: job.clip, media: job.media, name: job.name, source: job.source,
            sourceIn: sourceIn, sourceLength: sourceLength, start: start, duration: end - start,
            speed: job.speed)
    }

    // MARK: - The on-device run

    /// One clip through this Mac's recogniser, waited for. Off main only:
    /// `SpeechEngine.transcribe` blocks its caller.
    ///
    /// The model questions are `Transcriber.transcribe`'s, in its order and
    /// with its sentences: the engine's availability, then whether the ONE
    /// chosen locale is installed (a question that could not be answered is
    /// `.unavailable`, never "not installed"). It never downloads (W-8). The
    /// extract is the clip's own source window, removed on every exit.
    static func recognize(
        _ job: Transcriber.Job, language: Transcriber.Language,
        cancel: Transcriber.CancelToken
    ) throws -> [SpeechEngine.Run] {
        guard SpeechEngine.isAvailable else {
            throw Transcriber.TranscribeError.unavailable(language.displayName)
        }
        switch SpeechEngine.isInstalled(language.locale) {
        case .none:
            throw Transcriber.TranscribeError.unavailable(language.displayName)
        case .some(false):
            throw Transcriber.TranscribeError.notInstalled(language.displayName)
        case .some(true):
            break
        }
        if cancel.isCancelled { throw Transcriber.TranscribeError.cancelled }
        let extract = try Transcriber().extractAudio(job, cancel: cancel)
        defer { try? FileManager.default.removeItem(at: extract.url) }
        return try SpeechEngine.transcribe(
            file: extract.url, locale: language.locale, seconds: extract.seconds,
            name: job.name, cancel: cancel, progress: { _ in })
    }
}
