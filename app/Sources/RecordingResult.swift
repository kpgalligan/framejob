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
    /// The movie, probed through `MediaImporter.probe` (completion on main);
    /// for a voice-over (`RecordingResult.isVoiceOver`) that stretch's `.m4a`,
    /// with `micDescriptor` nil and `micOffset` 0.
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
    /// `micDescriptor` is nil whenever this is set. For a voice-over it is
    /// set only on a segment whose writer stopped on its own (spec §11
    /// recording, "A voice-over is a recording with no picture").
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

/// A segment whose MOVIE would not probe, left out of the recording (#97),
/// or a CLOSED segment whose writer failed after its stop, left out
/// unprobed (#181): the movie as named, the files it left on disk at settle
/// (movie, then microphone, each only if there), and the error `settle`
/// built for it — the writer's own sentence for the second.
/// `sentence` is what the panel's note and the tool's `note` say about it.
/// `micDescriptor` is its microphone file, probed, when it reads (#181 item
/// 2, spec §11 recording): the landing puts that voice in the picture's
/// slot. `position` is how many of `RecordingResult.segments` were recorded
/// before it — where that slot is among the landed segments.
struct UnreadableSegment {
    /// For a voice-over, the `.m4a` that would not probe.
    let moviePath: String
    let keptFiles: [String]
    let error: RecorderError
    let micDescriptor: MediaDescriptor?
    let position: Int

    init(
        moviePath: String, keptFiles: [String], error: RecorderError,
        micDescriptor: MediaDescriptor? = nil, position: Int = 0
    ) {
        self.moviePath = moviePath
        self.keptFiles = keptFiles
        self.error = error
        self.micDescriptor = micDescriptor
        self.position = position
    }

    var sentence: String {
        "A segment was left out. " + error.localizedDescription
            + (keptFiles.isEmpty
                ? " It left no file on disk."
                : " Its files are kept at " + keptFiles.joined(separator: ", ") + ".")
    }
}

/// What a camera recording records with (spec §11 CAM-3): the device's name,
/// the format it recorded at as `CameraDevices.spelled` writes it
/// (`1760x1328@30`), and `problem` — the sentence of a camera that stopped on
/// its own (a runtime error, an interruption, a disconnect), which ended the
/// recording with `stoppedBy` `.systemStopped`; nil when it did not. `note`
/// is the warm-up's sentence when the stream had not reached the format's
/// rate by the bound and the recording began anyway (`CameraCapture.WarmUp`).
struct RecordingCamera: Equatable {
    let name: String
    let format: String
    var problem: String?
    var note: String?
}

/// What a recording ends as: its segments, in order — ONE for a recording
/// never paused — and what `RecordingLanding` turns into ops, one clip per
/// segment placed at the previous segment's end. `unreadable` is every
/// segment whose movie would not probe, or whose writer failed after the
/// segment closed (#181), left out of `segments` and named in
/// `unreadableNote` (#97); a recording with NO readable movie is a failure,
/// never a result.
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
    /// A camera recording's camera (`isCamera`); nil for every other source.
    let camera: RecordingCamera?

    /// The FIRST segment's movie.
    var descriptor: MediaDescriptor { segments[0].descriptor }
    /// The FIRST segment's screen did-start, wall clock.
    var startedAt: Date { segments[0].startedAt }
    /// A voice-over: the microphone alone, every segment's `descriptor` its
    /// `.m4a` (spec §11 recording, #99).
    var isVoiceOver: Bool { choice.source == .voiceOver }
    /// A camera alone (spec §11 CAM-3): every segment's `descriptor` is the
    /// camera's `.mov`, landed by the picture rule as a screen's is.
    var isCamera: Bool { choice.source == .camera }
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
    /// The segments left out because their movie would not probe, or
    /// because their writer failed after the segment closed (#181), in
    /// segment order; empty when every movie read.
    let unreadable: [UnreadableSegment]
    /// Every left-out segment's sentence, joined by a space; nil when none.
    var unreadableNote: String? {
        unreadable.isEmpty ? nil : unreadable.map(\.sentence).joined(separator: " ")
    }

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
        pauses: Int, unreadable: [UnreadableSegment] = [], camera: RecordingCamera? = nil
    ) {
        precondition(!segments.isEmpty, "a RecordingResult carries at least one segment")
        self.segments = segments
        self.choice = choice
        self.stoppedBy = stoppedBy
        self.pauses = pauses
        self.unreadable = unreadable
        self.camera = camera
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

/// One stretch of the recording's timeline, in recording order: a landed
/// segment (an index into `segments`), or a left-out segment's readable
/// voice with no picture (an index into `unreadable`) — #181 item 2.
enum RecordingStretch: Equatable {
    case segment(Int)
    case voiceOnly(Int)
}

extension RecordingResult {
    /// Every landed segment and every left-out voice that reads, in the
    /// order they were recorded: before each segment `k`, the left-out
    /// entries at `position == k` with a microphone (in `unreadable`'s
    /// order), then the segment; after the last, those at `segments.count`.
    /// With no left-out voice it is `.segment(0)…` exactly, so every landing
    /// over it is the one before #181 item 2.
    var stretches: [RecordingStretch] {
        func voices(at k: Int) -> [RecordingStretch] {
            unreadable.indices.filter { unreadable[$0].position == k && unreadable[$0].micDescriptor != nil }
                .map { RecordingStretch.voiceOnly($0) }
        }
        var list: [RecordingStretch] = []
        for k in segments.indices {
            list += voices(at: k)
            list.append(.segment(k))
        }
        return list + voices(at: segments.count)
    }

    /// What a landing that SUCCEEDED says about each left-out voice it
    /// added, joined by a space; nil when no left-out segment's microphone
    /// read. Never said by a failed landing (`savedButNotAdded`,
    /// `failedToLand`), which `unreadableNote` alone serves.
    var leftOutVoiceNote: String? {
        let paths = unreadable.compactMap { $0.micDescriptor?.path }
        guard !paths.isEmpty else { return nil }
        return paths.map {
            "The left-out segment's microphone, \($0), was added to the project without its "
                + "picture."
        }.joined(separator: " ")
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
/// comma-joined lists, and the one-file sentence is byte for byte R1's; an
/// EMPTY `movie` (no movie on disk) names the microphone files alone (B55).
/// `.cameraDevice` is the camera's `.microphoneDevice`: no such camera, or one
/// that cannot be recorded from (spec §11 CAM-3).
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
    case cameraDevice(String)
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
        case .cameraDevice(let why): return why
        case .filesKept(let inner, let movie, let microphone):
            let base = inner.errorDescription ?? "The recording failed."
            guard !movie.isEmpty else {
                return microphone.map { base + " The microphone is at \($0)." } ?? base
            }
            let clause = microphone.map { "; the microphone at \($0)" } ?? ""
            return base + " The recording is at \(movie)\(clause)."
        }
    }
}
