import Foundation

/// What this Mac's recogniser heard for `get_transcript` (spec §11 TR-14,
/// #332), cached per media and language so a later call inside a stored run
/// answers without recognising again.
///
/// `cache/device-transcripts/<media id>-<language identifier>.json`: one
/// `File` per (media, language), the whole cached state, sorted keys and
/// `.atomic`, written only through `CacheLedger.publish` so it never lands
/// mid-save. It never shares `cache/transcripts/` with AssemblyAI's files,
/// and only `get_transcript` reads it: captions, Remove Filler Words,
/// `detect_fillers` and `transcribe_for_fillers` never do (TR-7).
///
/// - The KEY is `Stamp`: R6-15's four-field source stamp, the language, the
///   OS version (the recogniser ships with the OS) and `version`. A file of
///   another stamp is a miss, and the next store replaces it whole.
/// - A HIT is the first stored run, in file order, whose source span
///   contains the span the call would hear. A miss runs exactly that span,
///   and the store drops every stored run the new one contains. No gap is
///   filled and no words are merged across runs.
/// - Words are MEDIA source ticks, so another clip, speed or window over the
///   same file reuses them (`TranscriptReader.deviceWords` maps them).
enum DeviceTranscriptCache {

    /// The folder under the document's cache directory.
    static let kind = "device-transcripts"
    /// Bumped when what a stored run means changes; a file of another
    /// version is a miss.
    static let version = 1

    /// One recognised word, in MEDIA source ticks.
    struct Word: Codable, Equatable {
        let text: String
        let start: Ticks
        let end: Ticks
    }

    /// One run of the recogniser: the source span it heard and its words.
    struct Heard: Codable, Equatable {
        let sourceIn: Ticks
        let sourceLength: Ticks
        let words: [Word]

        enum CodingKeys: String, CodingKey {
            case sourceIn = "source_in"
            case sourceLength = "source_length"
            case words
        }

        init(sourceIn: Ticks, sourceLength: Ticks, words: [Word]) {
            self.sourceIn = sourceIn
            self.sourceLength = sourceLength
            self.words = words
        }

        /// A run's seconds into the extract as media source ticks:
        /// `sourceIn + round(clamp(t × 600000, 0, sourceLength))`, the clamp
        /// in `Double` before the conversion. A word with a non-finite time
        /// is dropped.
        init(runs: [SpeechEngine.Run], over job: Transcriber.Job) {
            let length = max(job.sourceLength, 0)
            func source(_ t: Double) -> Ticks {
                let ticks = min(max(t * Double(ReelTime.perSecond), 0), Double(length))
                return job.sourceIn + Ticks(ticks.rounded(.toNearestOrAwayFromZero))
            }
            self.init(
                sourceIn: job.sourceIn, sourceLength: job.sourceLength,
                words: runs.compactMap { run in
                    guard run.start.isFinite, run.end.isFinite else { return nil }
                    return Word(text: run.text, start: source(run.start), end: source(run.end))
                })
        }

        /// Whether this run heard all of [sourceIn, sourceIn + sourceLength).
        /// False for a non-positive length, or an end that overflows.
        func covers(sourceIn: Ticks, sourceLength: Ticks) -> Bool {
            guard sourceLength > 0, self.sourceLength > 0 else { return false }
            let (end, over) = sourceIn.addingReportingOverflow(sourceLength)
            let (ownEnd, ownOver) = self.sourceIn.addingReportingOverflow(self.sourceLength)
            guard !over, !ownOver else { return false }
            return self.sourceIn <= sourceIn && end <= ownEnd
        }
    }

    /// The key a file is current for.
    struct Stamp: Codable, Equatable {
        let source: TranscriptSourceStamp
        let language: String
        let system: String
        let version: Int
    }

    /// What one file holds: its key and the runs stored under it.
    struct File: Codable, Equatable {
        let stamp: Stamp
        let runs: [Heard]
    }

    // MARK: - Where it lives

    /// `cache/device-transcripts/<media id>-<language>.json`.
    static func fileURL(for media: UInt32, language: String, in cacheDir: URL) -> URL {
        directory(in: cacheDir).appendingPathComponent("\(media)-\(language).json")
    }

    private static func directory(in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent(kind, isDirectory: true)
    }

    // MARK: - Reading

    /// The file, or nil when it is missing, unreadable or of another shape.
    static func read(for media: UInt32, language: String, in cacheDir: URL) -> File? {
        let url = fileURL(for: media, language: language, in: cacheDir)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }

    /// The first stored run, in file order, that heard all of `job`'s source
    /// span, when the file's stamp is `stamp`; nil otherwise.
    static func lookup(
        _ job: Transcriber.Job, media: UInt32, stamp: Stamp, in cacheDir: URL
    ) -> Heard? {
        guard let file = read(for: media, language: stamp.language, in: cacheDir) else {
            return nil
        }
        guard file.stamp == stamp else { return nil }
        return file.runs.first { $0.covers(sourceIn: job.sourceIn, sourceLength: job.sourceLength) }
    }

    // MARK: - Writing

    /// `file` with `heard` added: under the same stamp, the stored runs
    /// `heard` contains are dropped and `heard` is appended; under another
    /// stamp (or none), `heard` alone.
    static func merged(_ file: File?, adding heard: Heard, stamp: Stamp) -> File {
        guard let file, file.stamp == stamp else { return File(stamp: stamp, runs: [heard]) }
        let kept = file.runs.filter { !heard.covers(sourceIn: $0.sourceIn, sourceLength: $0.sourceLength) }
        return File(stamp: stamp, runs: kept + [heard])
    }

    /// Reads, merges and writes the file whole and `.atomic`, inside one
    /// `CacheLedger.publish` so no save of the package overlaps it. False
    /// for every way it can fail: a run not kept is a run made again.
    @discardableResult
    static func store(_ heard: Heard, media: UInt32, stamp: Stamp, in cacheDir: URL) -> Bool {
        var written = false
        let published = MediaImporter.CacheLedger.shared.publish(in: cacheDir, for: nil) {
            let file = merged(
                read(for: media, language: stamp.language, in: cacheDir), adding: heard,
                stamp: stamp)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(file),
                (try? FileManager.default.createDirectory(
                    at: directory(in: cacheDir), withIntermediateDirectories: true)) != nil
            else { return }
            let url = fileURL(for: media, language: stamp.language, in: cacheDir)
            written = (try? data.write(to: url, options: .atomic)) != nil
        }
        return published && written
    }

    // MARK: - The door

    /// The stamp of `media`'s file as it is now, or nil when there is no
    /// media or the file cannot be stat'ed.
    private static func currentStamp(
        _ media: MediaSnapshot?, url: URL, language: String
    ) -> Stamp? {
        guard let media, let source = MediaImporter.CacheStamp.stamp(for: media, url: url) else {
            return nil
        }
        return Stamp(source: source, language: language)
    }

    /// `run`'s words: a stored run that contains its span (`cached` true),
    /// else `recognize()`'s, stored when there is somewhere to keep them,
    /// the run was not cancelled and the file did not change during it.
    /// With no `cacheDir`, no `media` or a file that cannot be stat'ed it
    /// reads nothing and writes nothing. Rethrows `recognize`'s error.
    static func heard(
        _ run: Transcriber.Job, language: String, media: MediaSnapshot?, in cacheDir: URL?,
        cancelled: () -> Bool, recognize: () throws -> [SpeechEngine.Run]
    ) throws -> (heard: Heard, cached: Bool) {
        let stamp = cacheDir == nil ? nil : currentStamp(media, url: run.source, language: language)
        if let cacheDir, let stamp,
            let hit = lookup(run, media: run.media, stamp: stamp, in: cacheDir)
        {
            return (hit, true)
        }
        let heard = Heard(runs: try recognize(), over: run)
        guard let cacheDir, let stamp else { return (heard, false) }
        guard !cancelled() else { return (heard, false) }
        guard currentStamp(media, url: run.source, language: language) == stamp else { return (heard, false) }
        store(heard, media: run.media, stamp: stamp, in: cacheDir)
        return (heard, false)
    }
}

extension DeviceTranscriptCache.Stamp {
    /// The key for `source` and `language` on this Mac, at this version.
    init(source: MediaImporter.CacheStamp, language: String) {
        self.init(
            source: TranscriptSourceStamp(source), language: language,
            system: ProcessInfo.processInfo.operatingSystemVersionString,
            version: DeviceTranscriptCache.version)
    }
}
