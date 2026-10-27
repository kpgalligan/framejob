import AppKit

/// `record_screen`'s SENTENCES (camera-recording CR3-0): an error's sentence,
/// the start's and the finish's timeout sentences with the alert clause they
/// share, and `savedButNotAdded`, a failure after the files are on disk. A
/// pure move out of `AgentServer+RecordingResult.swift` at the 400-line cap,
/// landed alone before camera + screen grows the result; nothing changed,
/// and `isStartTimeout` stays `private`, because only `startSentence` calls
/// it. Every member is `static` and reads nothing off the server, the rule
/// the result file was cut by.
extension AgentServer {
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
    /// `stopCeiling(segments:camera:)`: it names every movie the recorder still
    /// holds — one per segment, the recording may finish on its own after
    /// the tool has answered, and a person can then import them — and the
    /// alert clause. Empty means the recorder no longer holds a session at
    /// all. The seconds it spells are the ceiling over `movies.count`, which
    /// is the number the wait used: the same count while the session is
    /// held (a stop removes no segment), and the one-segment number — the
    /// wait's own `?? 1` — when the recorder had let the session go. A
    /// voice-over's files are named "file", not "movie". `cameras` are the
    /// camera files beside a screen's movies (spec §11 CAM-10 (7)), named
    /// after them. `camera` is the wait's own `cameraBeside`, so the ceiling
    /// spelled is the one the wait used — with the camera's probe whenever a
    /// camera was asked for beside the screen, even when no camera file is
    /// held (CAM-11 (7)).
    static func finishTimeoutSentence(
        movies: [String], cameras: [String] = [], camera: Bool = false, voiceOver: Bool = false
    ) -> String {
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
        let besideClause: String
        switch cameras.count {
        case 0: besideClause = ""
        case 1: besideClause = " Its camera file is at \(cameras[0])."
        default: besideClause = " Its camera files are at " + cameras.joined(separator: ", ") + "."
        }
        let ceiling = stopCeiling(segments: movies.count, camera: camera)
        return "record_screen asked the recorder to stop and it did not finish within "
            + "\(Int(ceiling)) s. " + where_ + besideClause + recordingAlertClause
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
