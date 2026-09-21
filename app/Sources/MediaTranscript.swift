import Foundation

/// The transcript cache — road map 6 §5b: where a media's transcript lives in
/// the package, what is in it, what marks it current, the loader that reads
/// one per media, THE MAPPING from AssemblyAI's milliseconds to project
/// ticks, and the janitor's list. `TranscriptStamp`, the marker's own type,
/// is in `AssemblyAITranscript.swift` with the request it records; this file
/// stood at 436 lines with it, against the 400-line cap.
///
/// **R6-3: it is a per-media asset of the package.** One upload per media
/// file, the provider's words stored VERBATIM — their milliseconds, their
/// confidence, their speaker — beside what was requested and what ran, under
/// `cache/transcripts/`, stamped on spec §5.6's terms so a relink or a
/// changed file re-transcribes and nothing else does. Every clip's cues are
/// derived from it at run time; it is the reversed render's kind of cache,
/// regenerable at a cost, which is why it travels with the package.
/// `ProjectDocument.fileWrapper(ofType:)` carries `cache/` whole, so
/// `transcripts/` rides into a saved package and out of an untitled
/// document's temporary cache with no line there. The paths are here and not
/// in `MediaCacheFiles.swift`, which was measured at 555 lines against the
/// ~600 cap and takes exactly one line for this feature —
/// `MediaImporter.transcriptsKind`, which has to sit beside the other three
/// kind constants because a notification's `userInfo` compares them.
///
/// **VERBATIM means bytes, not values.** `wordsJSON` is the served bytes of
/// the `words` array, carried through the client, the file and back out
/// untouched; a `Codable` round trip cannot make that claim true, because a
/// served `0.98` does not survive being decoded to a `Double` and re-encoded.
/// So `File.encoded()` splices the bytes in and `File.init(data:)` cuts them
/// back out with `JSONValueRange`; the decoded `words` are for READING only.
///
/// **No words is never invented.** A `completed` transcript whose `words` is
/// absent, `null` or anything but a JSON array is refused — by the client as
/// `.malformed`, by both `File` initialisers as `FileError.malformed` — so
/// `read(for:)` answers nil, `isCurrent` false, and the next run
/// re-transcribes. An empty array IS an array: zero words is a real answer
/// about audio nobody spoke in, and substituting one for a missing key would
/// cache a broken response as "nobody said anything".
enum MediaTranscript {

    /// The cache file's and the marker's `provider`, so a later build with
    /// a second service can tell whose answer it holds.
    static let provider = "assemblyai"

    /// Why a cache file could not be read.
    enum FileError: LocalizedError, Equatable {
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .malformed(let reason): return "The transcript file is malformed: \(reason)"
            }
        }
    }

    // MARK: - Where it lives

    /// `cache/transcripts/<media id>.json` — `speechURL`'s shape.
    static func fileURL(for media: UInt32, in cacheDir: URL) -> URL {
        directory(in: cacheDir).appendingPathComponent("\(media).json")
    }

    /// `cache/transcripts/<media id>.complete.json`, a SIDECAR beside the
    /// file and not a child, so either can be deleted without the other.
    static func markerURL(for media: UInt32, in cacheDir: URL) -> URL {
        directory(in: cacheDir).appendingPathComponent("\(media).complete.json")
    }

    private static func directory(in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent(MediaImporter.transcriptsKind, isDirectory: true)
    }

    // MARK: - What is in it

    /// Everything about a transcript except its words. Road map 6 §5b's
    /// keys exactly, in snake case, nil written as JSON `null` rather than
    /// dropped: a file that omitted `language_code` could not be told from
    /// one written before the key existed.
    struct Header: Codable, Equatable {
        let provider: String
        let transcriptID: String
        /// What was ASKED for — 5b's `requested` block, the marker's too.
        let requested: TranscriptOptions
        /// R6-8: which model actually ran, so a fallback is reported.
        let speechModelUsed: String?
        let languageCode: String?
        /// Set when the language was detected, not when it was named (q1).
        let languageConfidence: Double?
        /// Seconds, as AssemblyAI reported them — what was billed.
        let audioDuration: Int
        /// What was extracted, which is not what was billed: `audio_duration`
        /// rounds UP (§3 q1).
        let extractedSeconds: Double
        /// `"flac"` or `"wav"` — q2's format and its fallback, so the file
        /// says what was SENT.
        let uploadedFormat: String
        /// ALWAYS 0, and the field exists for the day that stops being
        /// true. Road map 6 §3 q4 measured that an extract of a file whose
        /// audio starts 1.5 s after its picture KEEPS that 1.5 s at its
        /// head, so a word's millisecond in the extract is its millisecond
        /// in the media and the mapping adds nothing. A later macOS that
        /// trimmed the empty edit would move every caption of such a file.
        let audioTrackStartMs: Int
        let fetchedAt: String
        /// R6-4: whether we have deleted the remote transcript. False is
        /// what `undeleted(in:)` lists, so it is `var`: a successful retry
        /// rewrites this field and nothing else.
        var remoteDeleted: Bool

        enum CodingKeys: String, CodingKey {
            case provider
            case transcriptID = "transcript_id"
            case requested
            case speechModelUsed = "speech_model_used"
            case languageCode = "language_code"
            case languageConfidence = "language_confidence"
            case audioDuration = "audio_duration"
            case extractedSeconds = "extracted_seconds"
            case uploadedFormat = "uploaded_format"
            case audioTrackStartMs = "audio_track_start_ms"
            case fetchedAt = "fetched_at"
            case remoteDeleted = "remote_deleted"
        }

        /// Every key, always, nil as `null` — `TranscriptOptions.encode`'s
        /// reason.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(provider, forKey: .provider)
            try container.encode(transcriptID, forKey: .transcriptID)
            try container.encode(requested, forKey: .requested)
            try encodeOrNull(speechModelUsed, into: &container, forKey: .speechModelUsed)
            try encodeOrNull(languageCode, into: &container, forKey: .languageCode)
            try encodeOrNull(languageConfidence, into: &container, forKey: .languageConfidence)
            try container.encode(audioDuration, forKey: .audioDuration)
            try container.encode(extractedSeconds, forKey: .extractedSeconds)
            try container.encode(uploadedFormat, forKey: .uploadedFormat)
            try container.encode(audioTrackStartMs, forKey: .audioTrackStartMs)
            try container.encode(fetchedAt, forKey: .fetchedAt)
            try container.encode(remoteDeleted, forKey: .remoteDeleted)
        }
    }

    /// A whole cache file: the header, the served bytes of `words`, and
    /// those words decoded for reading.
    struct File: Equatable {
        var header: Header
        /// The bytes that were served, and the ones that will be written.
        let wordsJSON: Data
        /// The same array, decoded. Nothing writes from this.
        let words: [TranscriptWord]

        /// From a fetch. Throws when `wordsJSON` is not a JSON array of
        /// words — the client has already refused such a body, and this is
        /// the second gate: no path into this type invents an empty one.
        init(header: Header, wordsJSON: Data) throws {
            self.header = header
            self.wordsJSON = wordsJSON
            self.words = try MediaTranscript.decodeWords(wordsJSON)
        }

        /// From a cache file. The header decodes normally; the words are
        /// cut out by byte range, so what is read is what was written.
        init(data: Data) throws {
            let decoded: Header
            do {
                decoded = try JSONDecoder().decode(Header.self, from: data)
            } catch {
                throw FileError.malformed(error.localizedDescription)
            }
            guard let range = JSONValueRange.topLevel(key: "words", in: data) else {
                throw FileError.malformed("it has no top-level `words`")
            }
            try self.init(header: decoded, wordsJSON: data.subdata(in: range))
        }

        /// The document, sorted keys, ready for `.atomic`: the header
        /// encoded with `.sortedKeys`, its final `}` replaced by
        /// `,"words":` plus the served bytes plus `}`. `words` sorts after
        /// every other key this header has — `transcript_id`,
        /// `uploaded_format` and the rest all begin below `w` — so the
        /// document stays sorted and a proof can compare two as text.
        /// Encoding the words with the rest is what the byte-equality claim
        /// forbids.
        func encoded() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(header)
            guard data.last == UInt8(ascii: "}") else {
                throw FileError.malformed("the header did not encode as an object")
            }
            data.removeLast()
            data.append(contentsOf: Array(",\"words\":".utf8))
            data.append(wordsJSON)
            data.append(UInt8(ascii: "}"))
            return data
        }
    }

    /// `wordsJSON` as words, or a refusal: the first non-space byte must be
    /// `[`, because only an array is a word list.
    private static func decodeWords(_ json: Data) throws -> [TranscriptWord] {
        guard let first = json.first(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }),
            first == UInt8(ascii: "[")
        else { throw FileError.malformed("its `words` is not a JSON array") }
        do {
            return try JSONDecoder().decode([TranscriptWord].self, from: json)
        } catch {
            throw FileError.malformed("its `words` did not decode: \(error.localizedDescription)")
        }
    }

    // MARK: - Reading and writing

    /// Writes the file, creating `cache/transcripts/` if it is not there.
    /// `.atomic`, so a file is whole or absent. `false` is every way it can
    /// fail: a cache that could not be written is a run that has to upload
    /// again, not a run that failed.
    @discardableResult
    static func write(_ file: File, for media: UInt32, in cacheDir: URL) -> Bool {
        guard let data = try? file.encoded() else { return false }
        let folder = directory(in: cacheDir)
        guard
            (try? FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true)) != nil
        else { return false }
        return (try? data.write(to: fileURL(for: media, in: cacheDir), options: .atomic)) != nil
    }

    /// The cache file, or nil. A file of a different shape, or one whose
    /// `words` is missing or is not an array, reads as ABSENT — the answer
    /// that re-transcribes.
    static func read(for media: UInt32, in cacheDir: URL) -> File? {
        guard let data = try? Data(contentsOf: fileURL(for: media, in: cacheDir)) else {
            return nil
        }
        return try? File(data: data)
    }

    /// The stamp the marker carries, or nil when there is no marker or it
    /// will not decode — `MediaImporter.readStamp`'s rule.
    static func readStamp(for media: UInt32, in cacheDir: URL) -> TranscriptStamp? {
        guard let data = try? Data(contentsOf: markerURL(for: media, in: cacheDir)) else {
            return nil
        }
        return try? JSONDecoder().decode(TranscriptStamp.self, from: data)
    }

    /// The marker, through `MediaImporter.writeStamp` — sorted keys and
    /// `.atomic`, so two markers of one stamp are byte-identical.
    @discardableResult
    static func writeStamp(_ stamp: TranscriptStamp, for media: UInt32, in cacheDir: URL) -> Bool {
        let folder = directory(in: cacheDir)
        guard
            (try? FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true)) != nil
        else { return false }
        return MediaImporter.writeStamp(stamp, to: markerURL(for: media, in: cacheDir))
    }

    /// Whether a run may skip this media: the marker decodes EQUAL to the
    /// stamp the caller computed from the file as it is NOW, **and** the
    /// transcript itself reads. Both, because they are separate files.
    static func isCurrent(_ stamp: TranscriptStamp, for media: UInt32, in cacheDir: URL) -> Bool {
        guard readStamp(for: media, in: cacheDir) == stamp else { return false }
        return read(for: media, in: cacheDir) != nil
    }

    /// The janitor's list (R6-4): every cached transcript whose remote copy
    /// this app has not managed to delete, by media id, so a run's first act
    /// can be to try again. Sorted, so two runs report it the same way. A
    /// file that will not read is not on it: it holds no id to delete.
    static func undeleted(in cacheDir: URL) -> [(media: UInt32, transcriptID: String)] {
        let folder = directory(in: cacheDir)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        var rows: [(media: UInt32, transcriptID: String)] = []
        for name in names.sorted() {
            guard name.hasSuffix(".json"), !name.hasSuffix(".complete.json"),
                let media = UInt32(String(name.dropLast(5))),
                let file = read(for: media, in: cacheDir), !file.header.remoteDeleted
            else { continue }
            rows.append((media, file.header.transcriptID))
        }
        return rows.sorted { $0.media < $1.media }
    }

    // MARK: - The mapping

    /// THE MAPPING, and the one piece of arithmetic in this file: the words
    /// of a media's transcript that belong to ONE clip, in PROJECT ticks.
    ///
    /// A word at media milliseconds `[s, e)` is at source ticks `m = s × 600`
    /// (600 000 ticks a second). It is this clip's when
    /// `in ≤ m < in + content_length`, where `content_length = duration ×
    /// speed` is the core's own `content_length_in_source`
    /// (`core/src/source_window.rs`, `Transcriber.contentLength` in Swift),
    /// and it lands at `clip.start + (m − in) / speed`. Its end is the same
    /// arithmetic over `e × 600`, and both are clamped into
    /// `[clip.start, clip.start + clip.duration]`.
    ///
    /// **This is where phase 4's "no `in` term" simplicity is given back.**
    /// The on-device engine extracts a clip's source WINDOW and hands the
    /// recogniser that, so a word's time is already relative to the window.
    /// The cloud engine uploads a media's WHOLE audio once and derives every
    /// clip from it (R6-3), so the `in` term is back and the window test is
    /// what keeps two clips over one media from each getting all its words.
    ///
    /// The half-open test is deliberate at both ends: a word starting exactly
    /// AT `in` is the clip's first, and one starting exactly at the window's
    /// end belongs to whatever plays next — which is what makes a split
    /// clip's halves partition the words with none lost and none doubled. A
    /// word that STRADDLES `in` is not this clip's: the test is on the
    /// word's START, so half a word does not appear at a cut.
    static func words(for job: Transcriber.Job, in file: File) -> [CaptionCues.Word] {
        let windowEnd = job.sourceIn + job.sourceLength
        let limit = job.start + job.duration
        var out: [CaptionCues.Word] = []
        for word in file.words {
            let startTicks = Ticks(word.start) * 600
            guard startTicks >= job.sourceIn, startTicks < windowEnd else { continue }
            let endTicks = Ticks(max(word.start, word.end)) * 600
            out.append(
                CaptionCues.Word(
                    text: word.text,
                    start: project(startTicks, in: job, limit: limit),
                    end: project(endTicks, in: job, limit: limit),
                    speaker: word.speaker))
        }
        return out
    }

    /// One source tick into project time, clamped into the clip. The clamp
    /// is what a word running past the window's end earns: its start is
    /// inside the clip, so the word is the clip's, but the rest is played by
    /// whatever comes next and a cue past its own clip would be a caption
    /// over somebody else's picture.
    private static func project(_ source: Ticks, in job: Transcriber.Job, limit: Ticks) -> Ticks {
        // A degenerate `speed` — 0, negative, NaN or infinite — would make
        // `Ticks(_:)` trap; `Transcriber.project` guards it the same way.
        let speed = job.speed.isFinite && job.speed > 0 ? job.speed : 1
        let offset = Double(source - job.sourceIn) / speed
        let placed = job.start + Ticks(offset.rounded(.toNearestOrAwayFromZero))
        return min(max(placed, job.start), limit)
    }

    // MARK: - Reading one per media

    /// `MediaPeaks.Loader`'s shape: one read per media for a whole pass,
    /// with the media that had no cache remembered.
    final class Loader {
        private let cacheDirectory: URL?
        private var loaded: [UInt32: File] = [:]
        /// Media whose `cache/transcripts/<id>.json` was asked for and was
        /// not there, or was there and would not read.
        private(set) var pending: Set<UInt32> = []

        /// nil is a document with nowhere to keep caches, which answers every
        /// media as pending — the same answer as a cache that has not been
        /// written yet, and the correct one.
        init(cacheDirectory: URL?) {
            self.cacheDirectory = cacheDirectory
        }

        func file(for media: UInt32) -> File? {
            if let cached = loaded[media] { return cached }
            if pending.contains(media) { return nil }
            guard let cacheDirectory = cacheDirectory,
                let read = MediaTranscript.read(for: media, in: cacheDirectory)
            else {
                pending.insert(media)
                return nil
            }
            loaded[media] = read
            return read
        }
    }
}
