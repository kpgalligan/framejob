import AppKit

/// `record_screen`'s RESULT shaping and its SENTENCES — what the answer says
/// about the files and the ids they landed as, and what a refusal says once
/// a file is on disk — cut out of `AgentServer+Recording.swift` when that
/// file stood at 397 lines against app/CLAUDE.md's 400-line cap for a new
/// file, with the R1 review's fixes still to land on it. The seam is the one
/// the file already had: `record_screen`'s waits and its argument vocabulary
/// stay there; the pure functions from a `RecordingResult` (and a document,
/// or an error) to result fields and sentences are here. Every member is
/// `static` and reads nothing off the server, which is what made them the
/// cut: the other side keeps the semaphores and the `onMain` hops, this side
/// keeps what a probe could call with no server at all. `private` →
/// internal is the whole cost, because a `private` extension member reaches
/// only its own file.
///
/// **Road map 3, R2d — a recording is a SEQUENCE of files** (decision 6): a
/// `RecordingResult` carries `segments`, one per stretch between a start or
/// resume and a pause or the stop, and there is deliberately no
/// `result.micDescriptor` or `result.micOffset` any more — those are a
/// segment's, and this file used to read both off the result. So the answer
/// grew two keys that are ALWAYS present, `pauses` and `segments`, and every
/// top-level key keeps its R1 meaning for the FIRST segment — the recording's
/// file, the one a new project is addressed by — except `duration`, which is
/// the TOTAL recorded and for an unpaused recording is the number it always
/// was. The ids are carried per segment as `RecordingSegmentIds`, ONE shape
/// for both doors, filled by `newProjectIds` (every file looked up by path
/// on the document `untitled(around:)` built) and `documentIds` (the
/// placement's four lists, each indexed by SEGMENT — one entry per segment
/// since the R2 review, nil where nothing was minted — the ids it predicted
/// and the panel selects), so `recordingFields` derives the top-level four
/// from the first entry and no caller writes an id key by hand. Each entry
/// of `segments` also carries its own `width`, `height` and `fps`, because
/// on a variable-rate file `fps` genuinely differs from segment to segment.
///
/// **A failure after the recording was written names the file** (R1 review):
/// the recorder's own `.filesKept` already does that for a failure INSIDE
/// the recorder, and `savedButNotAdded` is the same rule for the three
/// places the TOOL can fail after a clean result — the placement's trial,
/// the commit, and the untitled document — because a caller told only "a
/// drag is in progress" has no way to find the footage that exists. The
/// files are spelled by `RecordingResult.filesClause`, the ONE spelling the
/// panel's note shares: every movie comma-joined, then every microphone file
/// that landed; the one-segment sentence is byte for byte R1's.
extension AgentServer {

    // MARK: - The result

    /// The ids ONE segment's files landed as, each nil until known: a
    /// `place: false` landing mints no clip, a segment whose microphone
    /// failed has no `micMedia`, and a result built before any landing
    /// (a probe's, or a throw's) has none of the four.
    struct RecordingSegmentIds {
        var media: UInt32?
        var clip: UInt32?
        var micMedia: UInt32?
        var micClip: UInt32?

        init(
            media: UInt32? = nil, clip: UInt32? = nil, micMedia: UInt32? = nil,
            micClip: UInt32? = nil
        ) {
            self.media = media
            self.clip = clip
            self.micMedia = micMedia
            self.micClip = micClip
        }
    }

    /// What the files are, and — through `ids`, one entry per segment in
    /// order, absent entries reading as unknown — where they landed. The
    /// top-level keys are the FIRST segment's: `path`, `width`, `height`,
    /// `fps`, `has_audio`, `audio_tracks` (what the MOVIE holds, 1 with
    /// system audio, else 0: the microphone is a second file, reported as
    /// `mic_path` and `mic_duration`, never a second track of this one),
    /// `mic_offset` — ALWAYS present, 0 for a segment with no microphone,
    /// because the key is a measurement and not a flag: `mic_path` is what
    /// says whether a file landed — and `media` / `clip` / `mic_media` /
    /// `mic_clip` from `ids.first`. `duration` is the SUM of every
    /// segment's — the total recorded, the paused stretches excluded because
    /// no file holds them.
    /// `mic_problem` is every segment's sentence joined
    /// (`RecordingResult.micProblem`), present when any segment's microphone
    /// was asked for and did not land — which is why, unlike R1, it can
    /// stand beside a `mic_path`: a second segment's failure leaves the
    /// first's file in place. `pauses` and `segments` are always present;
    /// `segments` has exactly one entry for a recording never paused.
    /// `unreadable` (#97) is present only when a segment was LEFT OUT because
    /// its movie would not probe, or its writer failed after it closed (#181):
    /// one entry per such segment, in order, with its movie's `path`, the
    /// `kept_files` still on disk and the `reason` — and, when its
    /// microphone file read (#181 item 2), `mic_path` and `mic_duration`,
    /// with `mic_media` and `mic_clip` from `leftOutIds` (one entry per
    /// left-out segment) when known.
    static func recordingFields(
        _ result: RecordingResult, ids: [RecordingSegmentIds] = [],
        leftOutIds: [RecordingSegmentIds] = []
    ) -> [String: Any] {
        let first = result.segments[0]
        let movie = first.descriptor
        let total = result.segments.reduce(Ticks(0)) { $0 + $1.descriptor.duration }
        let segments = result.segments.enumerated().map { index, segment in
            segmentFields(segment, ids: index < ids.count ? ids[index] : nil)
        }
        var fields: [String: Any] = [
            "path": movie.path, "duration": total, "width": movie.width,
            "height": movie.height, "fps": [movie.fps.num, movie.fps.den],
            "has_audio": movie.hasAudio, "audio_tracks": movie.hasAudio ? 1 : 0,
            "mic_offset": first.micOffset, "stopped_by": stopReasonName(result.stoppedBy),
            "pauses": result.pauses, "segments": segments,
        ]
        if let mic = first.micDescriptor {
            fields["mic_path"] = mic.path
            fields["mic_duration"] = mic.duration
        }
        if let problem = result.micProblem { fields["mic_problem"] = problem }
        if !result.unreadable.isEmpty {
            fields["unreadable"] = result.unreadable.enumerated().map { i, left -> [String: Any] in
                var entry: [String: Any] = [
                    "path": left.moviePath, "kept_files": left.keptFiles,
                    "reason": left.error.localizedDescription,
                ]
                if let mic = left.micDescriptor {
                    entry["mic_path"] = mic.path
                    entry["mic_duration"] = mic.duration
                }
                let known = i < leftOutIds.count ? leftOutIds[i] : nil
                if let id = known?.micMedia { entry["mic_media"] = Int(id) }
                if let id = known?.micClip { entry["mic_clip"] = Int(id) }
                return entry
            }
        }
        fields.merge(idFields(ids.first)) { _, new in new }
        return fields
    }

    /// One entry of `segments`: `path`, `duration`, `width`, `height`, `fps`
    /// (this FILE's, which on a variable-rate recording differs per segment
    /// — the top level's is the first segment's) and `started_at` (the
    /// screen's did-start, `startedAtFormatter`'s spelling), then `mic_path`,
    /// `mic_duration`, `mic_offset` (always, 0 with no microphone) and
    /// `mic_problem` on the top level's terms for THIS segment's files, and
    /// the four ids when known.
    static func segmentFields(
        _ segment: RecordingSegment, ids: RecordingSegmentIds? = nil
    ) -> [String: Any] {
        let movie = segment.descriptor
        var fields: [String: Any] = [
            "path": movie.path, "duration": movie.duration, "width": movie.width,
            "height": movie.height, "fps": [movie.fps.num, movie.fps.den],
            "started_at": startedAtFormatter.string(from: segment.startedAt),
            "mic_offset": segment.micOffset,
        ]
        if let mic = segment.micDescriptor {
            fields["mic_path"] = mic.path
            fields["mic_duration"] = mic.duration
        }
        if let problem = segment.micProblem { fields["mic_problem"] = problem }
        fields.merge(idFields(ids)) { _, new in new }
        return fields
    }

    /// `started_at`'s spelling: ISO 8601 in UTC to the millisecond
    /// (`2026-09-12T13:04:22.417Z`). The server reports no other date, so
    /// there was no spelling to match; UTC because the file's own name
    /// (`RecordingFiles.stem`) is already the local-time reading of the same
    /// instant and a second local spelling would say nothing new, and the
    /// fraction because the segments' offsets are measured in milliseconds.
    static let startedAtFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func idFields(_ ids: RecordingSegmentIds?) -> [String: Any] {
        var fields: [String: Any] = [:]
        if let id = ids?.media { fields["media"] = Int(id) }
        if let id = ids?.clip { fields["clip"] = Int(id) }
        if let id = ids?.micMedia { fields["mic_media"] = Int(id) }
        if let id = ids?.micClip { fields["mic_clip"] = Int(id) }
        return fields
    }

    static func stopReasonName(_ reason: StopReason) -> String {
        switch reason {
        case .stopped: return "stopped"
        case .userStopped: return "user_stopped"
        case .systemStopped: return "system_stopped"
        }
    }

    /// The `note` clause for a result some segment's microphone did not
    /// land for — the pictures are in the project and the answer must say
    /// what is missing. Over the JOINED problems, whose sentences name the
    /// segment's file when one was left behind. A voice-over has no picture:
    /// its problem — a microphone that stopped on its own — is said verbatim.
    static func microphoneNote(_ result: RecordingResult) -> String? {
        if result.isVoiceOver { return result.micProblem }
        return result.micProblem.map {
            "The picture landed without its microphone — the microphone file could not be "
                + "used: " + $0
        }
    }

    /// The result's own `note` clauses, in order: the segments left out as
    /// unreadable (#97), the left-out voices that landed (#181 item 2), then
    /// the microphone's. Both doors append these after their own, on a
    /// landing that succeeded only.
    static func resultNotes(_ result: RecordingResult) -> [String] {
        [result.unreadableNote, result.leftOutVoiceNote, microphoneNote(result)].compactMap { $0 }
    }

    /// The ids a new project holds for every segment's files, read off its
    /// snapshot by path, SEGMENT BY SEGMENT — `untitled(around:)` placed
    /// them (the first picture as the document, the rest through
    /// `remainderPlacement`), so nothing here predicted an id, and a file
    /// the remainder landed as media alone (its sentence in the landing's
    /// `notes`) answers a `media` and no `clip`, which is the truth. A new
    /// project has no nest, so its top-level clips are the only clips there
    /// are.
    static func newProjectIds(
        _ result: RecordingResult, in document: ProjectDocument
    ) -> [RecordingSegmentIds] {
        let snapshot = document.project.snapshot
        return result.segments.map { segment in
            let media = landedMedia(for: segment.descriptor.path, in: snapshot)
            let micMedia = segment.micDescriptor.flatMap { landedMedia(for: $0.path, in: snapshot) }
            return RecordingSegmentIds(
                media: media, clip: media.flatMap { landedClip(of: $0, in: snapshot) },
                micMedia: micMedia, micClip: micMedia.flatMap { landedClip(of: $0, in: snapshot) })
        }
    }

    /// The ids a DOCUMENT landing gives every segment — the placement's own
    /// four lists, the ids it predicted off the purely-applied trial (R1's
    /// contract: `next_id` before each op that mints) and the ones the panel
    /// selects, so the tool reports what the panel highlights. All four
    /// lists have ONE entry per segment, in order, nil where nothing was
    /// minted (`Placement`'s doc), so every one is indexed by SEGMENT and
    /// none is consumed by an iterator — the first shape here walked the two
    /// `mic…` lists as "segments with a microphone file" were met, and a
    /// voice that minted no clip then shifted every later segment's ids by
    /// one. Read BEFORE the commit, as R1 read the singulars, which is what
    /// lets `land()` keep `editResult`'s tail.
    static func documentIds(
        _ result: RecordingResult, placement: RecordingLanding.Placement
    ) -> [RecordingSegmentIds] {
        func entry(_ list: [UInt32?], _ k: Int) -> UInt32? { k < list.count ? list[k] : nil }
        return result.segments.indices.map { k in
            RecordingSegmentIds(
                media: k < placement.mediaIds.count ? placement.mediaIds[k] : nil,
                clip: entry(placement.clipIds, k), micMedia: entry(placement.micMediaIds, k),
                micClip: entry(placement.micClipIds, k))
        }
    }

    /// The ids a DOCUMENT landing gives each left-out segment's voice (#181
    /// item 2): the placement's two left-out lists, one entry per
    /// `result.unreadable`, `micMedia` and `micClip` only.
    static func documentLeftOutIds(
        _ result: RecordingResult, placement: RecordingLanding.Placement
    ) -> [RecordingSegmentIds] {
        func entry(_ list: [UInt32?], _ i: Int) -> UInt32? { i < list.count ? list[i] : nil }
        return result.unreadable.indices.map { i in
            RecordingSegmentIds(
                micMedia: entry(placement.leftOutMicMediaIds, i),
                micClip: entry(placement.leftOutMicClipIds, i))
        }
    }

    /// The ids a NEW project holds for each left-out segment's voice, read
    /// off its snapshot by trimmed path as `newProjectIds` reads the
    /// segments': a voice before the first segment is media with no clip.
    static func newProjectLeftOutIds(
        _ result: RecordingResult, in document: ProjectDocument
    ) -> [RecordingSegmentIds] {
        let snapshot = document.project.snapshot
        return result.unreadable.map { left in
            let micMedia = left.micDescriptor.flatMap { landedMedia(for: $0.path, in: snapshot) }
            return RecordingSegmentIds(
                micMedia: micMedia, micClip: micMedia.flatMap { landedClip(of: $0, in: snapshot) })
        }
    }

    /// The media entry for `path`, matched TRIMMED because that is what the
    /// core stored (`RecordingLanding.addMedia`'s rule).
    private static func landedMedia(for path: String, in snapshot: ProjectSnapshot) -> UInt32? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.media.first(where: { $0.path == trimmed })?.id
    }

    /// The first top-level clip whose source is `media`.
    private static func landedClip(of media: UInt32, in snapshot: ProjectSnapshot) -> UInt32? {
        snapshot.clips.first { clip in
            if case .media(let id, _, _) = clip.source { return id == media }
            return false
        }?.id
    }

    // MARK: - The sentences

    /// An error's sentence — a `ToolError`'s `localizedDescription` is generic.
    static func sentence(of error: any Error) -> String {
        (error as? ToolError)?.message ?? error.localizedDescription
    }

    /// The clause both of the tool's timeout sentences end with, and the
    /// recorder's own arm timeout gets it too: macOS 15 periodically puts up
    /// a consent alert — whether to keep letting Frame Job bypass the system
    /// window picker — which is a prompt neither `CGPreflightScreenCaptureAccess`
    /// (still true) nor this tool can see, and a capture waiting behind it
    /// looks exactly like a recorder that hung.
    static let recordingAlertClause =
        " A system alert about screen recording may be waiting on the screen — macOS "
        + "periodically asks whether to keep allowing Frame Job to record, and neither the "
        + "preflight nor this tool can see that prompt; answer it and call again."

    /// The start's failure as the caller reads it: the recorder's sentence,
    /// plus the alert clause when the recorder's own arm ceiling is what
    /// answered (`.startTimedOut`, bare or wrapped in `.filesKept`).
    static func startSentence(of error: any Error) -> String {
        sentence(of: error) + (isStartTimeout(error) ? recordingAlertClause : "")
    }

    private static func isStartTimeout(_ error: any Error) -> Bool {
        guard let failure = error as? RecorderError else { return false }
        switch failure {
        case .startTimedOut: return true
        case .filesKept(let inner, _, _): return isStartTimeout(inner)
        default: return false
        }
    }

    /// The sentence for a `stop()` that did not conclude within
    /// `stopCeiling(segments:)`: it names every movie the recorder still
    /// holds — one per segment, the recording may finish on its own after
    /// the tool has answered, and a person can then import them — and the
    /// alert clause. Empty means the recorder no longer holds a session at
    /// all. The seconds it spells are the ceiling over `movies.count`, which
    /// is the number the wait used: the same count while the session is
    /// held (a stop removes no segment), and the one-segment number — the
    /// wait's own `?? 1` — when the recorder had let the session go. A
    /// voice-over's files are named "file", not "movie".
    static func finishTimeoutSentence(movies: [String], voiceOver: Bool = false) -> String {
        let noun = voiceOver ? "file" : "movie"
        let where_: String
        switch movies.count {
        case 0:
            where_ =
                "The recorder no longer holds the session, so the recording may already have "
                + "finished without answering."
        case 1:
            where_ = "The recording may still finish on its own; its \(noun) is at \(movies[0])."
        default:
            where_ =
                "The recording may still finish on its own; its \(noun)s are at "
                + movies.joined(separator: ", ") + "."
        }
        return "record_screen asked the recorder to stop and it did not finish within "
            + "\(Int(stopCeiling(segments: movies.count))) s. " + where_ + recordingAlertClause
    }

    /// A failure AFTER the recording landed on disk, as a `ToolError` naming
    /// the file(s): the placement's trial, the commit and the untitled
    /// document are the three throw sites, and every one of them is reached
    /// with the footage already written. The files are
    /// `RecordingResult.filesClause` — every segment's movie comma-joined,
    /// then every microphone file that landed — the one spelling the panel's
    /// note uses too; with one segment the sentence is byte for byte R1's,
    /// which `tools/proof/recording_proof.py` matches by shape. A segment
    /// left out as unreadable (#97) is named after it, its files too.
    static func savedButNotAdded(_ result: RecordingResult, _ error: any Error) -> ToolError {
        ToolError(
            message: "The recording was saved at \(result.filesClause) but could not "
                + "be added: " + sentence(of: error)
                + (result.unreadableNote.map { " " + $0 } ?? ""))
    }
}
