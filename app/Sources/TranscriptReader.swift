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
