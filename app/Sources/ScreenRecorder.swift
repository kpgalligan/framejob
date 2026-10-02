import AVFoundation
import AppKit
import ScreenCaptureKit

/// The recording session (road map 3, R1a; pause and resume R2a): a state
/// machine `idle → arming → recording ⇄ paused → finishing → idle` owning
/// the `SCStream`, one `SCRecordingOutput` per SEGMENT and — when a
/// microphone is chosen — the `AVCaptureSession` that writes the microphone
/// to a SECOND file per segment (R0 q2: `captureMicrophone` on the stream
/// sums the microphone into the system track, decision 5's bad case, so it
/// is never set). The panel and the `record_screen` tool both drive this
/// one object and both receive a `RecordingResult` (`RecordingResult.swift`);
/// `RecordingLanding` turns that into ops. This file is the arming half and
/// `stop()`; `ScreenRecorder+Pause.swift` is what a segment is and the two
/// transitions that close one and open the next; `+Microphone.swift` the
/// capture session's preparation and the meter; `+Finishing.swift`
/// everything that ENDS a session; `+Delegates.swift` the three delegates;
/// `+Content.swift` the static helpers over shareable content, filters and
/// error codes.
///
/// **A paused recording is a sequence of files over one stream** (decision
/// 6). ScreenCaptureKit has no pause, so `pause()` REMOVES the segment's
/// recording output — its file closes — and `resume()` ADDS a fresh one to
/// a new file while the stream keeps capturing (R0 q7: 57 fps while
/// paused, the did-finish 5–25 ms after the remove, the did-start 8–10 ms
/// after the add); the microphone's writer is stopped and restarted per
/// segment on its one running session. `Session.segments` is that
/// sequence, never empty, and every callback finds ITS segment — by the
/// output's identity, by the microphone file's URL — rather than "the"
/// one, because the closed segment's did-finish can land after the next
/// has begun and a resume never waits for it.
///
/// **One hook, one delivery** (R1 review finding 4). `start` takes
/// `onFinish`, which is stored ON THE SESSION — installed only once every
/// guard has passed, when the arm really begins — and called exactly once,
/// at conclude, whoever ended the recording: a `stop()`, the menu bar's
/// indicator, the system, a failure. There is no settable hook on the
/// recorder any more, because there was one and a panel Record refused
/// `.busy` erased the tool's, after which an external stop reached nobody.
/// A start that FAILS never concludes: its error is the start completion's
/// alone. `stop()` in any state past idle JOINS (finding 1): its completion
/// is registered and every registered completion receives the one outcome
/// beside `onFinish`, so a person's Stop in the second after the menu
/// bar's cannot drop the landing. `.busy` is `start()` while not idle —
/// paused included — and nothing else.
///
/// **No `async`** (spec §11): every ScreenCaptureKit and AVFoundation entry
/// point used has a completion-handler or delegate form. **No queue of its
/// own**: the frameworks deliver their callbacks on private queues (R0 q6b:
/// the microphone's did-start on one labelled "File ou", the recording
/// output's on ScreenCaptureKit's), and each is stamped with `Date()` where
/// it arrives and hopped to main through `DispatchQueue.main.async` —
/// `MediaImporter.probe`'s shape —
/// so every transition runs on the main thread and needs no lock. The
/// microphone's did-finish arrived ON main in every measured run and is
/// hopped anyway.
///
/// **The callback ORDER the machine tolerates**, all measured (R0 q2, q6b,
/// q7): `recordingOutputDidStartRecording` fires 86–107 ms BEFORE
/// `startCapture`'s completion in every run, so did-start is a stamp taken
/// whenever it arrives and the completion consults it, never the reverse;
/// the microphone output's `startRecording` returns with `isRecording`
/// still false, so its did-start callback is the truth and the property is
/// never read for it; `session.startRunning()` BLOCKS main for 100–180 ms,
/// which is why `prepareMicrophone` exists — a countdown pays it before it
/// ends, so the first 0.4 s of voice is in the file — and why the session
/// goes FIRST when it was not prepared (the two files' first samples then
/// land within a frame of each other, offset +11 ms mean, 35 ms scatter);
/// stop → did-finish is 0.03 s without a microphone and up to 1.1 s with
/// one, so the finishing wait is bounded at `finishCeiling` rather than
/// open. The system's own menu-bar indicator can stop a capture from
/// outside the app (`.userStopped`; `.systemStopped` for a display that
/// sleeps, the stream's `.systemStoppedStream` code), while recording OR
/// paused — it stays up through a pause, since the stream never stops:
/// both take the SAME finishing path as `stop()`.
///
/// **Grants** (decision 4): this class never calls
/// `CGRequestScreenCaptureAccess` or `AVCaptureDevice.requestAccess`. It
/// reads `RecordingGrant.screenRecordingGranted` before building the stream
/// and the microphone status before constructing an `AVCaptureDeviceInput`
/// (whose initializer auto-prompts on `.notDetermined`), and refuses by name.
final class ScreenRecorder: NSObject {
    static let shared = ScreenRecorder()

    enum State: Equatable { case idle, arming, recording, paused, finishing }

    /// Seconds the finishing path waits for the writers' did-finish before
    /// probing whatever is on disk.
    static let finishCeiling: TimeInterval = 10
    /// Seconds `startCapture` may take to answer (R0: under 0.2 s).
    static let armCeiling: TimeInterval = 20

    /// Written by this class's own six files and nothing else; the pausing,
    /// finishing and delegate halves live in extensions, which is why this
    /// is not `private(set)`.
    var state: State = .idle
    /// Every state past idle, PAUSED included: File ▸ Stop Recording, the
    /// quit guard and `.busy` all read a paused recording as one in
    /// progress. `isPaused` (`+Pause.swift`) is the narrower question.
    var isRecording: Bool { state != .idle }
    /// The microphone's level. The panel binds a `LevelMeterView(meter:)` to
    /// it — never `LevelMeter.shared`, or the timeline bar would meter the
    /// microphone.
    let meter = LevelMeter()
    /// Non-nil from the moment a microphone problem is detected — the file
    /// output's did-finish carrying an error while the picture still
    /// records (finding 3), a device that went away — so the panel's tick
    /// can show it live; set ONCE and kept for the session (the panel
    /// writes its note once; a later segment's failure is on its own
    /// segment), nil while idle. The result's `micProblem` carries the
    /// final sentences, which may say more (each file's path).
    var microphoneProblem: String?

    /// Seconds RECORDED: the sum over segments of each one's span — its
    /// screen did-start (Date-based: the output's `recordedDuration` is
    /// whole seconds) to its `stoppedAt`, or to now for the one still open
    /// — each floored at 0, so it freezes while paused and never counts a
    /// gap; frozen at the stop call; 0 idle, and 0 while arming until the
    /// first did-start or `startCapture`'s completion lands (R1's rule,
    /// kept for the first segment: an arm can take seconds and none of
    /// them is footage).
    var elapsed: TimeInterval {
        guard state != .idle, let session else { return 0 }
        let now = Date()
        var total: TimeInterval = 0
        for (index, segment) in session.segments.enumerated() {
            guard let start = session.screenStart(of: index) else { continue }
            total += max(0, (segment.stoppedAt ?? now).timeIntervalSince(start))
        }
        return total
    }

    /// Everything one recording owns, so a stale callback from a previous
    /// session is told apart by object identity and the finishing path can
    /// hand the probes a copy. The two failures are SEPARATE (finding 0):
    /// a screen failure is what the caller receives, a microphone failure
    /// is a `micProblem` on the segment whose file it cost, on a result
    /// that still carries the picture. What one FILE PAIR owns is a
    /// `Segment` (`ScreenRecorder+Pause.swift`); `segments` holds them in
    /// order — the first minted by `start`, each later one by `resume()` —
    /// and is never empty. `displayPointSize` and `scale` are the geometry
    /// `start` read off the filter, kept so `resume()` can ask
    /// `RecordingConfiguration.make` for the next output on exactly the
    /// arguments the first was built from.
    struct Session {
        let choice: RecordingChoice
        /// Whether the finished movie's probe may ask the conversion
        /// question: false for `record_screen` (spec §11 MC-5).
        let mayAsk: Bool
        let displayPointSize: CGSize
        let scale: CGFloat
        let stream: SCStream
        let micSession: AVCaptureSession?
        let micOutput: AVCaptureAudioFileOutput?
        let calledAt: Date
        /// Installed when the arm begins; called exactly once, at conclude.
        let onFinish: (Result<RecordingResult, Error>) -> Void
        /// Never empty. The last is the segment recording now or, paused,
        /// the one just closed (`latest`).
        var segments: [Segment]
        /// Presses of `pause()`, STORED: `segments.count − 1` reads 0 for
        /// a pause with no resume before the Stop (R2 review).
        var pauses = 0
        var captureStartedAt: Date?
        var stoppedBy: StopReason = .stopped
        /// A `stop()` ENDED this recording (while arming, recording or
        /// paused). A stop that joined the finishing did not, and leaves
        /// this false, so an external reason that arrives late is still
        /// adopted (finding 7).
        var stopAsked = false
        var screenFailure: RecorderError?
        var timedOut = false
        /// `settle` has begun: one probe, one conclude (finding 2).
        var settling = false
    }

    var session: Session?
    var startCompletion: ((Error?) -> Void)?
    /// Every `stop()` completion registered since the arm began, delivered
    /// together at conclude (or by `failStart`, with its error).
    var stopCompletions: [(Result<RecordingResult, Error>) -> Void] = []
    /// A `stop()` arrived while arming: finishing begins the moment the
    /// start lands.
    var pendingStop = false
    /// `prepareMicrophone`'s running session, adopted by the next `start`
    /// whose choice names its device (`ScreenRecorder+Microphone.swift`).
    var preparedMicrophone: PreparedMicrophone?
    var timer: Timer?

    override init() { super.init() }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ScreenRecorder does not support NSCoder")
    }

    // MARK: - Start

    /// MAIN THREAD. `completion` on main, nil on success. A refusal — busy, a
    /// grant absent, an unknown microphone, a folder that cannot be made —
    /// completes BEFORE this returns, tears down any prepared microphone
    /// and touches nothing else; `.busy` in particular touches NOTHING of
    /// the running session, its hook included. A start that reaches
    /// `startCapture` completes from its completion handler. `onFinish` is
    /// the session's (the header): installed here only once every guard
    /// has passed, never called for a start that fails.
    ///
    /// The geometry is the FILTER's own — `contentRect` (points) and
    /// `pointPixelScale` — the one source that also covers a picker-made
    /// filter; measured, a display filter reports the display's point size
    /// and backing scale, a window filter the window's frame. ORDER (R0
    /// q6b): the microphone session (prepared, or started here), then its
    /// file output, then the stream, all in this one run-loop turn. The
    /// first segment is minted here, named by the call's own time.
    func start(
        filter: SCContentFilter, choice: RecordingChoice, mayAsk: Bool,
        onFinish: @escaping (Result<RecordingResult, Error>) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        guard state == .idle else { return completion(RecorderError.busy) }
        guard RecordingGrant.screenRecordingGranted else {
            return refuse(.startFailed(RecordingGrant.screenRecordingRefusal), completion)
        }
        var microphone: AVCaptureDevice?
        if let id = choice.microphone {
            let status = RecordingGrant.microphoneStatus
            guard status == .authorized else {
                return refuse(.startFailed(RecordingGrant.microphoneRefusal(status)), completion)
            }
            guard let device = Self.microphone(withID: id) else {
                return refuse(
                    .microphoneDevice("No microphone with the id \(id) is connected."), completion)
            }
            microphone = device
        }
        do {
            try RecordingFiles.create(choice.folder)
        } catch {
            return refuse(
                .startFailed(
                    "The recordings folder \(choice.folder.path) could not be created: "
                        + error.localizedDescription), completion)
        }
        let calledAt = Date()
        let movieURL = RecordingFiles.uniqueURL(
            in: choice.folder, stem: RecordingFiles.stem(at: calledAt), ext: "mov")
        let displayPointSize = filter.contentRect.size
        let scale = CGFloat(filter.pointPixelScale)
        let configs = RecordingConfiguration.make(
            choice, displayPointSize: displayPointSize, scale: scale, outputURL: movieURL)
        let stream = SCStream(filter: filter, configuration: configs.stream, delegate: self)
        let output = SCRecordingOutput(configuration: configs.output, delegate: self)
        do {
            // BEFORE `startCapture`, the header's own rule, so the first
            // sample lands in the file.
            try stream.addRecordingOutput(output)
        } catch {
            return refuse(
                .startFailed(
                    "The recording output could not be added: " + error.localizedDescription),
                completion)
        }
        var mic: MicrophoneCapture?
        if let device = microphone {
            do {
                mic = try microphoneCapture(for: device, beside: movieURL)
            } catch let failure as RecorderError {
                return refuse(failure, completion)
            } catch {
                return refuse(.microphoneDevice(error.localizedDescription), completion)
            }
        }
        microphoneProblem = nil
        session = Session(
            choice: choice, mayAsk: mayAsk, displayPointSize: displayPointSize, scale: scale,
            stream: stream,
            micSession: mic?.session, micOutput: mic?.output, calledAt: calledAt,
            onFinish: onFinish,
            segments: [
                Segment(movieURL: movieURL, micURL: mic?.url, output: output, addedAt: calledAt)
            ])
        state = .arming
        startCompletion = completion
        if let mic {
            if !mic.session.isRunning { mic.session.startRunning() }
            guard mic.session.isRunning else {
                return failStart(
                    RecorderError.microphoneDevice("The microphone session did not start."))
            }
            session?.segments[0].micRecordingCalledAt = Date()
            mic.output.startRecording(to: mic.url, outputFileType: .m4a, recordingDelegate: self)
        }
        stream.startCapture { [weak self] error in
            let at = Date()
            DispatchQueue.main.async { self?.captureStarted(stream, error: error, at: at) }
        }
        // The stream's own report wins over the bare ceiling (finding 5).
        // `.common`, the panel's rule: an open status-item menu runs the
        // loop in tracking mode, where a default-mode timer waits.
        let ceiling = Timer(timeInterval: Self.armCeiling, repeats: false) { [weak self] _ in
            guard let self, self.state == .arming else { return }
            self.failStart(self.session?.screenFailure ?? RecorderError.startTimedOut)
        }
        RunLoop.main.add(ceiling, forMode: .common)
        timer = ceiling
    }

    /// A refusal before the arm: nothing was made, and a microphone the
    /// countdown prepared is let go so the input does not stay open.
    private func refuse(_ error: RecorderError, _ completion: (Error?) -> Void) {
        discardPreparedMicrophone()
        completion(error)
    }

    private func captureStarted(_ stream: SCStream, error: (any Error)?, at: Date) {
        guard state == .arming, let current = session, current.stream === stream else { return }
        if let error { return failStart(RecorderError.startFailed(Self.sentence(for: error))) }
        // A stream stop or an output failure that arrived while arming. A
        // MICROPHONE failure that arrived meanwhile is not one: the picture
        // records and the result will say what became of the microphone.
        if let failure = current.screenFailure { return failStart(failure) }
        timer?.invalidate()
        timer = nil
        session?.captureStartedAt = at
        state = .recording
        let completion = startCompletion
        startCompletion = nil
        completion?(nil)
        // `.paused` too: the completion just ran, and may have paused.
        if pendingStop, state == .recording || state == .paused {
            pendingStop = false
            beginFinishing(.stopped)
        }
    }

    /// Tears a failed start down: the microphone session stopped, the stream
    /// asked to stop in case it did start, every completion answered — the
    /// start's with the error, every registered stop's with the same. A
    /// start that fails has ONE segment (no resume has happened). When its
    /// output had NOT begun writing the half-made microphone file is
    /// removed (it is ours and holds nothing); when it had (the arm timer
    /// past a stream that started), both files are footage: they stay, and
    /// the error names them (finding 6).
    private func failStart(_ error: RecorderError) {
        timer?.invalidate()
        timer = nil
        var delivered = error
        if let current = session {
            current.micOutput?.stopRecording()
            current.micSession?.stopRunning()
            current.stream.stopCapture { _ in }
            let first = current.segments[0]
            if first.screenStartedAt != nil {
                delivered = Self.namingFiles(error, current)
            } else if let micURL = first.micURL {
                try? FileManager.default.removeItem(at: micURL)
            }
        }
        session = nil
        state = .idle
        microphoneProblem = nil
        pendingStop = false
        discardPreparedMicrophone()
        let completion = startCompletion
        startCompletion = nil
        completion?(delivered)
        let stops = stopCompletions
        stopCompletions = []
        stops.forEach { $0(.failure(delivered)) }
    }

    // MARK: - Stop

    /// MAIN THREAD. `completion`, when given, on main with every file
    /// probed, or an error. Idle → `.notRecording`, synchronously; arming →
    /// held, finishing begins the moment the start lands; recording →
    /// finishing begins now; PAUSED → finishing begins now on the same
    /// path, with the segment's output already closed and the microphone
    /// already stopped, so only `stopCapture` remains; finishing → JOINED
    /// (finding 1): the completion is registered beside the others and
    /// never answered `.busy`, because a person's Stop a second after the
    /// menu bar's is a stop that must land. Every registered completion and
    /// the session's `onFinish` receive the ONE outcome at conclude. The
    /// wait for the writers is bounded at `finishCeiling`: past it the files
    /// are probed anyway (the writer may have finished without saying so),
    /// and an unfinished movie that will not probe is answered `.timedOut`.
    func stop(completion: ((Result<RecordingResult, Error>) -> Void)? = nil) {
        switch state {
        case .idle:
            completion?(.failure(RecorderError.notRecording))
        case .arming:
            if let completion { stopCompletions.append(completion) }
            session?.stopAsked = true
            pendingStop = true
        case .recording, .paused:
            if let completion { stopCompletions.append(completion) }
            session?.stopAsked = true
            beginFinishing(.stopped)
        case .finishing:
            if let completion { stopCompletions.append(completion) }
        }
    }
}
