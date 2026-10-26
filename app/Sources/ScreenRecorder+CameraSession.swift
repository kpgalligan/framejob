import AVFoundation

/// The two types a camera recording holds (camera-recording CR2-0):
/// `CameraSession`, everything one recording owns, and `CameraSegment`, one
/// stretch between a start or resume and a pause or the stop. The machine
/// that holds them is `ScreenRecorder+Camera.swift`; they moved out of it at
/// the 400-line cap as a pure move, as `Session` moved whole into
/// `ScreenRecorder+Pause.swift` (`designs/adr/app-file-history.md`).
extension ScreenRecorder {
    /// Everything one camera recording owns. `segments` is empty only while
    /// arming.
    struct CameraSession {
        /// The caller's choice with `rate` set to the format's
        /// (`CameraDevices.canvasRate`), so a new project's canvas is the
        /// camera's rate (`ProjectDocument.untitled(around:)` reads it).
        let choice: RecordingChoice
        /// Whether a segment's probe may ask the conversion question:
        /// false for `record_screen` (spec §11 MC-5).
        let mayAsk: Bool
        let capture: CameraCapture
        /// `startCamera`'s call: segment 0's name.
        let calledAt: Date
        let micSession: AVCaptureSession?
        let micOutput: AVCaptureAudioFileOutput?
        let micDelegate: CameraMicrophoneDelegate?
        /// Called exactly once, at conclude.
        let onFinish: (Result<RecordingResult, Error>) -> Void
        /// The name and format; `problem` is set when the camera stopped on
        /// its own.
        var camera: RecordingCamera
        var segments: [CameraSegment] = []
        /// Presses of Pause, stored (`RecordingResult.pauses`).
        var pauses = 0
        var stoppedBy: StopReason = .stopped
        /// The settle has begun: one probe walk, one conclude.
        var settling = false
        /// The finishing ceiling fired before every report landed.
        var timedOut = false
    }

    /// One stretch between a start (or a resume) and a pause (or the stop):
    /// its movie, its microphone file, and the stamps its offset and
    /// `cameraElapsed` are read from. `stoppedAt` non-nil means its close was
    /// ASKED for. `wrote` is false for a writer that took no buffer (the
    /// segment is dropped); `movieFailure` is a writer that did not complete.
    /// `micProblem` is the microphone's sentence for this segment — its
    /// writer failed or stopped on its own — set once.
    struct CameraSegment {
        let movieURL: URL
        let micURL: URL?
        /// When it was minted: `cameraElapsed`'s start until its first buffer.
        let calledAt: Date
        var startedAt: Date?
        var firstPTS: Double?
        var micStartedAt: Date?
        var micPTS: Double?
        var stoppedAt: Date?
        var movieFinished = false
        var wrote = false
        var movieFailure: String?
        var micFinished = false
        var micProblem: String?

        init(movieURL: URL, micURL: URL?, calledAt: Date) {
            self.movieURL = movieURL
            self.micURL = micURL
            self.calledAt = calledAt
        }
    }
}
