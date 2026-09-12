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
/// two are the stream delegate's `didStopWithError` codes −3817
/// (`.userStopped`, the system's own menu-bar indicator) and −3821
/// (`.systemStoppedStream`, a display that slept or went away).
enum StopReason: Equatable {
    case stopped
    case userStopped
    case systemStopped
}

/// The two files, probed, and how they line up — what `RecordingLanding`
/// turns into ops.
struct RecordingResult {
    /// The movie, probed through `MediaImporter.probe` (completion on main).
    let descriptor: MediaDescriptor
    /// The `.m4a`, probed, when a microphone was chosen AND its file landed;
    /// nil otherwise, and `micProblem` says which.
    let micDescriptor: MediaDescriptor?
    /// Screen did-start minus microphone did-start, in ticks. POSITIVE means
    /// the picture began AFTER the microphone, so the microphone clip starts
    /// that much earlier than the picture's (or has its in point trimmed by
    /// it). Measured per recording, never a constant (R0 q6b: +11 ms mean,
    /// 35 ms scatter with the session started first). 0 with no microphone.
    let micOffset: Ticks
    let choice: RecordingChoice
    /// The screen's did-start, wall clock.
    let startedAt: Date
    let stoppedBy: StopReason
    /// Non-nil when a microphone was chosen but its file did not land — it
    /// never started, the writer reported an error, the device went away,
    /// or the file would not probe (R1 review finding 0: a microphone
    /// problem does not fail a recording whose picture is on disk). The
    /// sentence names the file when one was left behind. `micDescriptor` is
    /// nil whenever this is set.
    let micProblem: String?

    init(
        descriptor: MediaDescriptor, micDescriptor: MediaDescriptor?, micOffset: Ticks,
        choice: RecordingChoice, startedAt: Date, stoppedBy: StopReason,
        micProblem: String? = nil
    ) {
        self.descriptor = descriptor
        self.micDescriptor = micDescriptor
        self.micOffset = micOffset
        self.choice = choice
        self.startedAt = startedAt
        self.stoppedBy = stoppedBy
        self.micProblem = micProblem
    }
}

/// `.busy` is `start()` while not idle, and nothing else answers it any
/// more: a `stop()` in any state joins the finishing already under way
/// (R1 review finding 1). `.startTimedOut` is the arm ceiling and
/// `.timedOut` the finish ceiling, two sentences because they name two
/// different waits (finding 5). `.filesKept` wraps a failure reached once
/// a file was on disk, so the panel's note and the tool's error carry the
/// path with no change on their side (finding 6).
indirect enum RecorderError: Error, LocalizedError {
    case busy
    case notRecording
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
