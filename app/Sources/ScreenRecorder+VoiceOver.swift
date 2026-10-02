import AVFoundation
import AppKit

/// A VOICE-OVER (spec §11 recording, "A voice-over is a recording with no
/// picture", #99): the same machine with no stream. The microphone's
/// `AVCaptureSession` — the one a screen recording writes its second file
/// with, adopted from `prepareMicrophone` when the countdown made it — writes
/// one `.m4a` per stretch between pauses, named `Voice-over <date> at
/// <time>.m4a` by the moment the stretch began, exactly as a screen
/// recording's segments are. `ScreenRecorder.voiceSession` is set instead of
/// `session`, never beside it, and `stop()`, `elapsed`, `pause()` and
/// `resume()` forward here when it is; `state` is the one state machine
/// (`idle → recording ⇄ paused → finishing → idle`, with NO arming state —
/// the writer's `startRecording` is the whole start), so `isRecording`,
/// `isPaused`, the quit guard and both doors read a voice-over as they read a
/// recording. This file is the start, the two transitions and the stop;
/// `+VoiceOverFinishing.swift` is everything the writer reports and
/// everything that ends one.
///
/// **One writer, a file per segment.** Its delegate is `VoiceOverFileDelegate`
/// rather than the recorder — the recorder's own microphone delegate
/// (`+Delegates.swift`) reads `session` — and each callback finds ITS
/// segment by the output's identity and the file URL it reports, because a
/// paused segment's did-finish can land after the resume has opened the
/// next. A resume never waits for it (the screen machine's rule, R0 q7).
///
/// **No prompt**: the microphone status is read before the session is built
/// (`adoptMicrophone`), and nothing here asks for a grant or reads the
/// Screen Recording one.
extension ScreenRecorder {
    /// Everything one voice-over owns. `segments` is never empty: the first
    /// is minted by `startVoiceOver`, each later one by `resumeVoiceOver`.
    struct VoiceSession {
        let choice: RecordingChoice
        let micSession: AVCaptureSession
        let micOutput: AVCaptureAudioFileOutput
        let fileDelegate: VoiceOverFileDelegate
        /// Called exactly once, at conclude.
        let onFinish: (Result<RecordingResult, Error>) -> Void
        var segments: [VoiceSegment]
        /// Presses of Pause, stored (`RecordingResult.pauses`).
        var pauses = 0
        /// The settle has begun: one probe walk, one conclude.
        var settling = false
        /// The finishing ceiling fired before every did-finish landed.
        var timedOut = false
    }

    /// One `.m4a`: its URL, the call that asked for it (`calledAt`, the
    /// fallback for a did-start that never came), the writer's did-start,
    /// and `stoppedAt` — a pause's or the stop's, so non-nil means its
    /// did-finish was ASKED for. `failure` is the writer's error when it did
    /// not finish well; `stoppedOnItsOwn` is set by a did-finish that came
    /// with `stoppedAt` nil — the writer stopped and nobody asked — and holds
    /// `<desc>`, that did-finish's error or "It reported no error.".
    struct VoiceSegment {
        let url: URL
        let calledAt: Date
        var startedAt: Date?
        var stoppedAt: Date?
        var finished = false
        var failure: String?
        var stoppedOnItsOwn: String?

        init(url: URL, calledAt: Date) {
            self.url = url
            self.calledAt = calledAt
        }
    }

    static let voiceOverNeedsMicrophoneSentence =
        "A voice-over records the microphone alone, so it needs a microphone; none is chosen."

    // MARK: - Start

    /// MAIN THREAD. `completion` on main, nil on success, and always BEFORE
    /// this returns: there is no arming state. A refusal touches nothing —
    /// `.busy` not even a prepared microphone; every other refusal lets a
    /// prepared one go — in this order: `.busy` when not idle; a choice
    /// that is not `.voiceOver`; no microphone; the Microphone grant not
    /// `.authorized` (read, never asked); a device id nothing connected
    /// carries; a folder that cannot be made; a session that will not run.
    /// Otherwise the first segment is minted, named by this call's time,
    /// the state is `.recording` and the writer is asked to start; its
    /// did-start is stamped where it lands.
    func startVoiceOver(
        choice: RecordingChoice,
        onFinish: @escaping (Result<RecordingResult, Error>) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        guard state == .idle else { return completion(RecorderError.busy) }
        guard choice.source == .voiceOver else {
            return refuseVoiceOver(
                .startFailed("A voice-over takes the Microphone Only source; this choice names a screen."),
                completion)
        }
        guard let id = choice.microphone else {
            return refuseVoiceOver(.startFailed(Self.voiceOverNeedsMicrophoneSentence), completion)
        }
        let status = RecordingGrant.microphoneStatus
        guard status == .authorized else {
            return refuseVoiceOver(.startFailed(RecordingGrant.microphoneRefusal(status)), completion)
        }
        guard let device = Self.microphone(withID: id) else {
            return refuseVoiceOver(
                .microphoneDevice("No microphone with the id \(id) is connected."), completion)
        }
        do {
            try RecordingFiles.create(choice.folder)
        } catch {
            return refuseVoiceOver(
                .startFailed(
                    "The recordings folder \(choice.folder.path) could not be created: "
                        + error.localizedDescription), completion)
        }
        let capture: (session: AVCaptureSession, output: AVCaptureAudioFileOutput)
        do {
            capture = try adoptMicrophone(for: device)
        } catch let failure as RecorderError {
            return refuseVoiceOver(failure, completion)
        } catch {
            return refuseVoiceOver(.microphoneDevice(error.localizedDescription), completion)
        }
        if !capture.session.isRunning { capture.session.startRunning() }
        guard capture.session.isRunning else {
            capture.session.stopRunning()
            return refuseVoiceOver(
                .microphoneDevice("The microphone session did not start."), completion)
        }
        microphoneProblem = nil
        let calledAt = Date()
        let url = Self.nextVoiceOverURL(in: choice.folder, at: calledAt, holding: [])
        let delegate = VoiceOverFileDelegate(recorder: self)
        voiceSession = VoiceSession(
            choice: choice, micSession: capture.session, micOutput: capture.output,
            fileDelegate: delegate, onFinish: onFinish,
            segments: [VoiceSegment(url: url, calledAt: calledAt)])
        state = .recording
        capture.output.startRecording(to: url, outputFileType: .m4a, recordingDelegate: delegate)
        completion(nil)
    }

    /// A refusal before anything was made: a prepared microphone is let go
    /// so the input does not stay open, `start`'s own rule.
    private func refuseVoiceOver(_ error: RecorderError, _ completion: (Error?) -> Void) {
        discardPreparedMicrophone()
        completion(error)
    }

    // MARK: - Pause and resume

    /// MAIN THREAD, synchronous; `pause()` forwards here. `.recording` →
    /// `.paused`; `.paused` throws `.alreadyPaused`, anything else
    /// `.notRecording`. Stamps the open segment's `stoppedAt`, counts the
    /// pause, asks the writer to stop (its did-finish lands on THAT segment),
    /// silences the meter and posts `pauseDidChangeNotification`.
    func pauseVoiceOver() throws {
        guard state != .paused else { throw RecorderError.alreadyPaused }
        guard state == .recording, let current = voiceSession else {
            throw RecorderError.notRecording
        }
        voiceSession?.segments[current.segments.count - 1].stoppedAt = Date()
        voiceSession?.pauses += 1
        current.micOutput.stopRecording()
        state = .paused
        meter.publish(.silent, from: ObjectIdentifier(self))
        NotificationCenter.default.post(name: Self.pauseDidChangeNotification, object: self)
    }

    /// MAIN THREAD, synchronous; `resume()` forwards here. `.paused` →
    /// `.recording`; anything else throws `.notPaused`. Mints the next
    /// segment, named by THIS moment and skipping every name the session
    /// holds, appends it BEFORE the writer is asked (so the callback finds
    /// it), and restarts the writer to it — never waiting for the paused
    /// segment's did-finish.
    func resumeVoiceOver() throws {
        guard state == .paused, let current = voiceSession else { throw RecorderError.notPaused }
        let at = Date()
        let url = Self.nextVoiceOverURL(
            in: current.choice.folder, at: at, holding: Set(current.segments.map(\.url.path)))
        voiceSession?.segments.append(VoiceSegment(url: url, calledAt: at))
        state = .recording
        current.micOutput.startRecording(
            to: url, outputFileType: .m4a, recordingDelegate: current.fileDelegate)
        NotificationCenter.default.post(name: Self.pauseDidChangeNotification, object: self)
    }

    // MARK: - Stop

    /// MAIN THREAD; `stop()` forwards here while a voice-over is held.
    /// Idle → `.notRecording`, synchronously; recording or paused →
    /// finishing begins now; finishing → JOINED: the completion receives
    /// the one outcome beside `onFinish`, `stop()`'s own rule.
    func stopVoiceOver(completion: ((Result<RecordingResult, Error>) -> Void)?) {
        switch state {
        case .idle, .arming:
            completion?(.failure(RecorderError.notRecording))
        case .recording, .paused:
            if let completion { stopCompletions.append(completion) }
            beginVoiceFinishing()
        case .finishing:
            if let completion { stopCompletions.append(completion) }
        }
    }

    // MARK: - What is held

    /// Seconds recorded: each segment from its did-start (else its call) to
    /// its `stoppedAt` (else now), each floored at 0, so it freezes while
    /// paused; 0 idle.
    var voiceElapsed: TimeInterval {
        guard state != .idle, let current = voiceSession else { return 0 }
        let now = Date()
        return current.segments.reduce(0) { total, segment in
            total
                + max(
                    0,
                    (segment.stoppedAt ?? now).timeIntervalSince(
                        segment.startedAt ?? segment.calledAt))
        }
    }

    /// Segments the recorder holds — a screen recording's or a voice-over's
    /// — 0 idle.
    var heldSegmentCount: Int {
        if let voiceSession { return voiceSession.segments.count }
        return session?.segments.count ?? 0
    }

    /// The files the recorder holds, in order: a screen recording's movies,
    /// or a voice-over's `.m4a` files; empty idle.
    var heldFilePaths: [String] {
        if let voiceSession { return voiceSession.segments.map(\.url.path) }
        return session?.segments.map(\.movieURL.path) ?? []
    }

    /// The next voice-over file: `RecordingFiles.uniqueURL`'s rule —
    /// `<stem>.m4a`, then `<stem> (2).m4a`, `(3)`… — over the files on DISK
    /// and the paths in `held`, because a segment's file does not exist
    /// until its writer's did-start, so a pause and resume inside one second
    /// would otherwise mint one name twice.
    static func nextVoiceOverURL(in folder: URL, at date: Date, holding held: Set<String>) -> URL {
        let stem = RecordingFiles.voiceOverStem(at: date)
        let manager = FileManager.default
        var candidate = folder.appendingPathComponent(stem).appendingPathExtension("m4a")
        var counter = 2
        while manager.fileExists(atPath: candidate.path) || held.contains(candidate.path) {
            candidate = folder.appendingPathComponent("\(stem) (\(counter))")
                .appendingPathExtension("m4a")
            counter += 1
        }
        return candidate
    }
}

extension ScreenRecorder.VoiceSession {
    /// The segment whose file is `url`, compared by path; nil for a file no
    /// segment asked for.
    func index(of url: URL) -> Int? {
        segments.firstIndex { $0.url.path == url.path }
    }
}

/// The voice-over writer's delegate. Each callback is stamped where it lands
/// (a private queue, R0 q6b) and hopped to main, where the recorder finds
/// the segment; a late callback from a session that has ended finds none.
final class VoiceOverFileDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private weak var recorder: ScreenRecorder?

    init(recorder: ScreenRecorder) {
        self.recorder = recorder
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("VoiceOverFileDelegate does not support NSCoder")
    }

    func fileOutput(
        _ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        let at = Date()
        DispatchQueue.main.async { [weak self] in
            self?.recorder?.voiceFileStarted(fileURL, output: output, at: at)
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection], error: (any Error)?
    ) {
        // A non-nil error can still mean a usable file: the key says so.
        let finishedWell =
            error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool)
                == true
        DispatchQueue.main.async { [weak self] in
            self?.recorder?.voiceFileFinished(
                outputFileURL, output: output, finishedWell: finishedWell, error: error)
        }
    }
}
