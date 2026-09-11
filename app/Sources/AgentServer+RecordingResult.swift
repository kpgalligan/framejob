import AppKit

/// `record_screen`'s RESULT shaping and its SENTENCES — what the answer says
/// about the two files and the ids they landed as, and what a refusal says
/// once a file is on disk — cut out of `AgentServer+Recording.swift` when
/// that file stood at 397 lines against app/CLAUDE.md's 400-line cap for a
/// new file, with the R1 review's fixes still to land on it. The seam is the
/// one the file already had: `record_screen`'s waits and its argument
/// vocabulary stay there; the pure functions from a `RecordingResult` (and a
/// document, or an error) to result fields and sentences are here. Every
/// member is `static` and reads nothing off the server, which is what made
/// them the cut: the other side keeps the semaphores and the `onMain` hops,
/// this side keeps what a probe could call with no server at all. `private`
/// → internal is the whole cost, because a `private` extension member
/// reaches only its own file.
///
/// **A failure after the recording was written names the file** (R1 review):
/// the recorder's own `.filesKept` already does that for a failure INSIDE
/// the recorder, and `savedButNotAdded` is the same rule for the three
/// places the TOOL can fail after a clean result — the placement's trial,
/// the commit, and the untitled document — because a caller told only "a
/// drag is in progress" has no way to find the footage that exists.
extension AgentServer {

    // MARK: - The result

    /// What the two files are, before anything is known about where they
    /// landed. `audio_tracks` is what the MOVIE holds (1 with system audio,
    /// else 0): the microphone is a second file, reported as `mic_path` and
    /// `mic_duration`, never a second track of this one. `mic_problem` is
    /// present only when a microphone was chosen and its file did not land
    /// (`RecordingResult.micProblem`), and then `mic_path` is absent.
    static func recordingFields(_ result: RecordingResult) -> [String: Any] {
        let movie = result.descriptor
        var fields: [String: Any] = [
            "path": movie.path, "duration": movie.duration, "width": movie.width,
            "height": movie.height, "fps": [movie.fps.num, movie.fps.den],
            "has_audio": movie.hasAudio, "audio_tracks": movie.hasAudio ? 1 : 0,
            "mic_offset": result.micOffset, "stopped_by": stopReasonName(result.stoppedBy),
        ]
        if let mic = result.micDescriptor {
            fields["mic_path"] = mic.path
            fields["mic_duration"] = mic.duration
        }
        if let problem = result.micProblem { fields["mic_problem"] = problem }
        return fields
    }

    static func stopReasonName(_ reason: StopReason) -> String {
        switch reason {
        case .stopped: return "stopped"
        case .userStopped: return "user_stopped"
        case .systemStopped: return "system_stopped"
        }
    }

    /// The `note` clause for a result whose microphone did not land — the
    /// picture is in the project and the answer must say what is missing.
    static func microphoneNote(_ result: RecordingResult) -> String? {
        result.micProblem.map {
            "The picture landed without its microphone — the microphone file could not be "
                + "used: " + $0
        }
    }

    /// The ids a new project holds for the two files, read off its snapshot
    /// — `untitled(around:)` placed both, so nothing here predicted them.
    static func newProjectIds(
        _ result: RecordingResult, in document: ProjectDocument
    ) -> [String: Any] {
        let snapshot = document.project.snapshot
        var fields: [String: Any] = [:]
        func ids(for path: String) -> (media: UInt32, clip: UInt32?)? {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let media = snapshot.media.first(where: { $0.path == trimmed })?.id else {
                return nil
            }
            let clip = snapshot.clips.first { clip in
                if case .media(let id, _, _) = clip.source { return id == media }
                return false
            }?.id
            return (media, clip)
        }
        if let picture = ids(for: result.descriptor.path) {
            fields["media"] = Int(picture.media)
            if let clip = picture.clip { fields["clip"] = Int(clip) }
        }
        if let mic = result.micDescriptor, let voice = ids(for: mic.path) {
            fields["mic_media"] = Int(voice.media)
            if let clip = voice.clip { fields["mic_clip"] = Int(clip) }
        }
        return fields
    }

    // MARK: - The sentences

    /// An error's sentence — a `ToolError`'s `localizedDescription` is generic.
    static func sentence(of error: any Error) -> String {
        (error as? ToolError)?.message ?? error.localizedDescription
    }

    /// The clause both of the tool's timeout sentences end with, and the
    /// recorder's own arm timeout gets it too: macOS 15 periodically puts up
    /// a consent alert — whether to keep letting Reelcut bypass the system
    /// window picker — which is a prompt neither `CGPreflightScreenCaptureAccess`
    /// (still true) nor this tool can see, and a capture waiting behind it
    /// looks exactly like a recorder that hung.
    static let recordingAlertClause =
        " A system alert about screen recording may be waiting on the screen — macOS "
        + "periodically asks whether to keep allowing Reelcut to record, and neither the "
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
    /// `stopCeiling`: it names the movie the recorder still holds — the
    /// recording may finish on its own after the tool has answered, and a
    /// person can then import it — and the alert clause.
    static func finishTimeoutSentence(movie: String?) -> String {
        let where_ =
            movie.map {
                "The recording may still finish on its own; its movie is at \($0)."
            }
            ?? "The recorder no longer holds the session, so the recording may already have "
            + "finished without answering."
        return "record_screen asked the recorder to stop and it did not finish within "
            + "\(Int(stopCeiling)) s. " + where_ + recordingAlertClause
    }

    /// A failure AFTER the recording landed on disk, as a `ToolError` naming
    /// the file(s): the placement's trial, the commit and the untitled
    /// document are the three throw sites, and every one of them is reached
    /// with the footage already written.
    static func savedButNotAdded(_ result: RecordingResult, _ error: any Error) -> ToolError {
        let mic = result.micDescriptor.map { " and its microphone at \($0.path)" } ?? ""
        return ToolError(
            message: "The recording was saved at \(result.descriptor.path)\(mic) but could not "
                + "be added: " + sentence(of: error))
    }
}
