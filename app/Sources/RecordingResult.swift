import AVFoundation
import AppKit

/// What a recording ENDS as — `StopReason`, `RecordingResult` and
/// `RecorderError` — the foot of `RecordingSetup.swift` moved whole, as a
/// pure move landed alone (road map 3, R2's toll), because that file stood
/// at 387 lines against the 400-line cap for a new file and the result
/// type is where R2's segments land. Values a probe can make, as before:
/// `tools/proof/recording_probe.py` constructs every one of them without a
/// stream. `RecordingSetup.swift` keeps what a recording IS before it
/// starts; `ScreenRecorder+Finishing.swift` is the one producer of a
/// `RecordingResult`; `RecordingLanding.swift` and the two doors are its
/// readers.

/// How the recording ended. `.stopped` is `ScreenRecorder.stop()`; the other
/// two are the stream delegate's `didStopWithError` codes: `.userStopped`
/// is −3817 (`SCStreamError.Code.userStopped`, the system's own menu-bar
/// indicator) and `.systemStopped` is −3821 (the code is spelled
/// `.systemStoppedStream`; a display that slept or went away) — and, while
/// PAUSED, any other stream stop as well, since nothing was writing
/// (`ScreenRecorder+Delegates.swift`).
enum StopReason: Equatable {
    case stopped
    case userStopped
    case systemStopped
}

/// One SEGMENT of a recording — the two files one stretch between a start
/// (or a resume) and a pause (or the stop) wrote, probed, and how they line
/// up (road map 3, decision 6: a paused recording is a sequence of files
/// over one stream, and every segment carries its OWN offset, because R0 q7
/// measured a different number for each resume).
struct RecordingSegment {
    /// The movie, probed through `MediaImporter.probe` (completion on main).
    let descriptor: MediaDescriptor
    /// The `.m4a`, probed, when a microphone was chosen AND this segment's
    /// file landed; nil otherwise, and `micProblem` says which.
    let micDescriptor: MediaDescriptor?
    /// Screen did-start minus microphone did-start, in ticks, for THIS
    /// segment. POSITIVE means the picture began AFTER the microphone, so
    /// the microphone clip starts that much earlier than the picture's (or
    /// has its in point trimmed by it). Measured per segment, never a
    /// constant (R0 q6b: +11 ms mean, 35 ms scatter with the session
    /// started first; q7: −22 to +33 ms across resumes). 0 with no
    /// microphone.
    let micOffset: Ticks
    /// The screen's did-start, wall clock (its fallbacks are the call that
    /// asked for it, `ScreenRecorder+Finishing.swift`'s rule).
    let startedAt: Date
    /// Non-nil when a microphone was chosen but this segment's file did
    /// not land — it never started, the writer reported an error, the
    /// device went away, or the file would not probe (R1 review finding 0:
    /// a microphone problem does not fail a recording whose picture is on
    /// disk). The sentence names the file when one was left behind.
    /// `micDescriptor` is nil whenever this is set.
    let micProblem: String?

    init(
        descriptor: MediaDescriptor, micDescriptor: MediaDescriptor?, micOffset: Ticks,
        startedAt: Date, micProblem: String? = nil
    ) {
        self.descriptor = descriptor
        self.micDescriptor = micDescriptor
        self.micOffset = micOffset
        self.startedAt = startedAt
        self.micProblem = micProblem
    }
}

/// What a recording ends as: its segments, in order — ONE for a recording
/// never paused — and what `RecordingLanding` turns into ops, one clip per
/// segment placed at the previous segment's end.
///
/// There is deliberately no `micDescriptor` and no `micOffset` on the
/// result: those are a SEGMENT's, and a reader that compiled against a
/// first-segment convenience would be silently wrong for a paused
/// recording. `descriptor` and `startedAt` ARE the first segment's, because
/// "the recording's file" is one thing to the readers that use them — the
/// untitled document's source and name, the path a tool addresses that
/// document by.
struct RecordingResult {
    /// Never empty.
    let segments: [RecordingSegment]
    let choice: RecordingChoice
    let stoppedBy: StopReason

    /// The FIRST segment's movie.
    var descriptor: MediaDescriptor { segments[0].descriptor }
    /// The FIRST segment's screen did-start, wall clock.
    var startedAt: Date { segments[0].startedAt }
    /// Every segment's microphone problem, in order, joined by a space; nil
    /// when no segment has one.
    var micProblem: String? {
        let problems = segments.compactMap { $0.micProblem }
        return problems.isEmpty ? nil : problems.joined(separator: " ")
    }
    /// How many times Pause was pressed — STORED and counted on the session,
    /// never `segments.count − 1`: a pause with no resume before the Stop
    /// leaves ONE file and was still a pause (the R2 review: it read 0).
    let pauses: Int

    /// The files on disk, for a sentence that sends a person to them: every
    /// segment's movie in order, comma-joined, then — when any landed —
    /// " and its microphone at <file>" for one microphone file or " and its
    /// microphone files at <a>, <b>" for several. One shape for the panel's
    /// note and the tool's `savedButNotAdded`, so a three-segment failure
    /// names three files at both doors (the R2 review: the panel named one).
    var filesClause: String {
        let movies = segments.map { $0.descriptor.path }.joined(separator: ", ")
        let mics = segments.compactMap { $0.micDescriptor?.path }
        switch mics.count {
        case 0: return movies
        case 1: return movies + " and its microphone at " + mics[0]
        default: return movies + " and its microphone files at " + mics.joined(separator: ", ")
        }
    }

    init(
        segments: [RecordingSegment], choice: RecordingChoice, stoppedBy: StopReason,
        pauses: Int
    ) {
        precondition(!segments.isEmpty, "a RecordingResult carries at least one segment")
        self.segments = segments
        self.choice = choice
        self.stoppedBy = stoppedBy
        self.pauses = pauses
    }

    /// ONE segment — R1's shape, kept so a single-segment construction (the
    /// probe's rows, a recording never paused) reads as it did; `pauses`
    /// defaults to 0 for it, since one file with no pause is what it means.
    init(
        descriptor: MediaDescriptor, micDescriptor: MediaDescriptor?, micOffset: Ticks,
        choice: RecordingChoice, startedAt: Date, stoppedBy: StopReason,
        micProblem: String? = nil, pauses: Int = 0
    ) {
        self.init(
            segments: [
                RecordingSegment(
                    descriptor: descriptor, micDescriptor: micDescriptor, micOffset: micOffset,
                    startedAt: startedAt, micProblem: micProblem)
            ], choice: choice, stoppedBy: stoppedBy, pauses: pauses)
    }
}

/// `.busy` is `start()` while not idle, and nothing else answers it any
/// more: a `stop()` in any state joins the finishing already under way
/// (R1 review finding 1). `.notPaused` is `resume()` while not paused
/// (R2); `.alreadyPaused` is `pause()` while paused — its own sentence,
/// because "no recording is in progress" is false while `isRecording` is
/// true — and `.notRecording` is `pause()` idle, arming or finishing.
/// `.startTimedOut` is the arm ceiling and `.timedOut` the finish ceiling,
/// two sentences because they name two different waits (finding 5).
/// `.filesKept` wraps a failure reached once a file was on disk, so the
/// panel's note and the tool's error carry the path with no change on their
/// side (finding 6); with segments its `movie` and `microphone` strings are
/// comma-joined lists, and the one-file sentence is byte for byte R1's.
indirect enum RecorderError: Error, LocalizedError {
    case busy
    case notRecording
    case notPaused
    case alreadyPaused
    case startFailed(String)
    case finishFailed(String)
    case startTimedOut
    case timedOut
    case microphoneDevice(String)
    case filesKept(RecorderError, movie: String, microphone: String?)

    var errorDescription: String? {
        switch self {
        case .busy: return "A recording is already in progress."
        case .notRecording: return "No recording is in progress."
        case .notPaused: return "The recording is not paused."
        case .alreadyPaused: return "The recording is already paused."
        case .startFailed(let why): return why
        case .finishFailed(let why): return why
        case .startTimedOut:
            return "The recording did not start within \(Int(ScreenRecorder.armCeiling)) s."
        case .timedOut:
            return "The recording did not finish writing within "
                + "\(Int(ScreenRecorder.finishCeiling)) s."
        case .microphoneDevice(let why): return why
        case .filesKept(let inner, let movie, let microphone):
            let clause = microphone.map { "; the microphone at \($0)" } ?? ""
            return (inner.errorDescription ?? "The recording failed.")
                + " The recording is at \(movie)\(clause)."
        }
    }
}
