import AVFoundation
import AppKit

/// A CAMERA recording (camera-recording CR1a, spec §11 CAM-1, CAM-3): the
/// same machine with a camera where the stream was. `CameraCapture` writes
/// the picture, one `AVAssetWriter` per segment on one running session
/// (CAM-2's verdict); the microphone, when one is chosen, is the second file
/// a screen recording writes — its session adopted from `prepareMicrophone`
/// when the countdown made it — one `.m4a` per segment beside the movie.
/// `ScreenRecorder.cameraSession` is set instead of `session` or
/// `voiceSession`, never beside either, and `stop()`, `elapsed`, `pause()`
/// and `resume()` forward here when it is. `state` is the one machine:
/// `idle → arming → recording ⇄ paused → finishing → idle`, arming while the
/// capture session starts on its own queue. This file is the start, the two
/// transitions, the stop and what is held; `+CameraSession.swift` the two
/// types it holds; `+CameraFinishing.swift` is what the capture and the
/// microphone report and everything that ends one.
///
/// **Segments are minted when the picture can begin.** The first is minted
/// by the capture's start completion, named by `startCamera`'s own call
/// time; each later one by `resumeCamera`, named by that moment and unique
/// against every name the session holds. A segment's picture begins at its
/// writer's first buffer (`startedAt`, `firstPTS` on the host clock), which
/// is what its microphone offset is measured from (`cameraMicOffset`).
///
/// **No prompt**: the Camera grant is read before any `CameraCapture` (whose
/// `AVCaptureDeviceInput` prompts on `.notDetermined`) and the Microphone
/// grant before the microphone's session; nothing here asks for either.
extension ScreenRecorder {
    static let cameraNeedsCameraSentence =
        "A camera recording records a camera; none is chosen."

    // MARK: - Start

    /// MAIN THREAD. `completion` on main, nil once the picture can begin. A
    /// refusal completes BEFORE this returns and touches nothing — `.busy`
    /// not even a prepared microphone; every other refusal lets a prepared
    /// one go — in this order: `.busy` when not idle; a choice that is not
    /// `.camera`; no camera named; the Camera grant not `.authorized` (read,
    /// never asked); an id no connected camera carries (`.cameraDevice`);
    /// the Microphone grant and device, as `start` checks them; a folder
    /// that cannot be made; a capture that throws (`takeCameraCapture`: the
    /// panel's prepared capture adopted only when `mayAsk`, CAM-5; the tool
    /// never adopts it, CAM-7 (7)). Then the microphone's session is adopted
    /// and run on main, the state is `.arming`, and the capture starts (or
    /// joins its prepared start) under `armCeiling`. `onFinish` is the
    /// session's, never called for a start that fails.
    func startCamera(
        choice: RecordingChoice, mayAsk: Bool,
        onFinish: @escaping (Result<RecordingResult, Error>) -> Void,
        completion: @escaping (Error?) -> Void
    ) {
        guard state == .idle else { return completion(RecorderError.busy) }
        guard choice.source == .camera else {
            return refuseCamera(
                .startFailed("A camera recording takes the Camera source; this choice names another."),
                completion)
        }
        guard let cameraID = choice.camera else {
            return refuseCamera(.startFailed(Self.cameraNeedsCameraSentence), completion)
        }
        let cameraGrant = RecordingGrant.cameraStatus
        guard cameraGrant == .authorized else {
            return refuseCamera(.startFailed(RecordingGrant.cameraRefusal(cameraGrant)), completion)
        }
        guard let device = CameraDevices.device(withID: cameraID) else {
            return refuseCamera(
                .cameraDevice("No camera with the id \(cameraID) is connected."), completion)
        }
        var microphone: AVCaptureDevice?
        if let micID = choice.microphone {
            let micGrant = RecordingGrant.microphoneStatus
            guard micGrant == .authorized else {
                return refuseCamera(.startFailed(RecordingGrant.microphoneRefusal(micGrant)), completion)
            }
            guard let found = Self.microphone(withID: micID) else {
                return refuseCamera(
                    .microphoneDevice("No microphone with the id \(micID) is connected."), completion)
            }
            microphone = found
        }
        do {
            try RecordingFiles.create(choice.folder)
        } catch {
            return refuseCamera(
                .startFailed(
                    "The recordings folder \(choice.folder.path) could not be created: "
                        + error.localizedDescription), completion)
        }
        let facts = CameraDevices.facts(of: device)
        guard
            let index = CameraDevices.chosenFormat(
                choice.cameraFormat, in: facts.formats, active: facts.activeFormat)
        else {
            return refuseCamera(
                .cameraDevice("The camera \(device.localizedName) lists no format."), completion)
        }
        let capture: CameraCapture
        do {
            capture = try takeCameraCapture(device: device, format: index, adopting: mayAsk)
        } catch let failure as RecorderError {
            return refuseCamera(failure, completion)
        } catch {
            return refuseCamera(.cameraDevice(error.localizedDescription), completion)
        }
        var mic: (session: AVCaptureSession, output: AVCaptureAudioFileOutput)?
        if let microphone {
            do {
                mic = try adoptMicrophone(for: microphone)
            } catch {
                capture.stop()
                return refuseCamera(
                    error as? RecorderError ?? .microphoneDevice(error.localizedDescription),
                    completion)
            }
            if let running = mic?.session, !running.isRunning { running.startRunning() }
            guard mic?.session.isRunning == true else {
                capture.stop()
                mic?.session.stopRunning()
                return refuseCamera(
                    .microphoneDevice("The microphone session did not start."), completion)
            }
        }
        var recorded = choice
        recorded.rate = CameraDevices.canvasRate(capture.applied)
        microphoneProblem = nil
        cameraSession = CameraSession(
            choice: recorded, mayAsk: mayAsk, capture: capture, calledAt: Date(),
            micSession: mic?.session, micOutput: mic?.output,
            micDelegate: mic == nil ? nil : CameraMicrophoneDelegate(recorder: self),
            onFinish: onFinish,
            camera: RecordingCamera(
                name: device.localizedName, format: CameraDevices.spelled(capture.applied)))
        state = .arming
        startCompletion = completion
        capture.onSegmentStarted = { [weak self, weak capture] url, pts, arrived in
            guard let self, let current = self.cameraSession, current.capture === capture,
                let index = current.segments.firstIndex(where: { $0.movieURL.path == url.path }),
                current.segments[index].startedAt == nil
            else { return }
            self.cameraSession?.segments[index].startedAt = arrived
            self.cameraSession?.segments[index].firstPTS = pts.isFinite ? pts : nil
        }
        capture.onStoppedOnItsOwn = { [weak self, weak capture] sentence in
            guard let self, let current = self.cameraSession, current.capture === capture else {
                return
            }
            self.cameraStoppedOnItsOwn(sentence)
        }
        startCameraCapture(capture) { [weak self, weak capture] error in
            guard let self, let capture else { return }
            self.cameraCaptureStarted(capture, error: error)
        }
        // `.common`, the panel's rule (`start`'s ceiling).
        let ceiling = Timer(timeInterval: Self.armCeiling, repeats: false) { [weak self] _ in
            guard let self, self.state == .arming, self.cameraSession != nil else { return }
            self.failCameraStart(.startTimedOut)
        }
        RunLoop.main.add(ceiling, forMode: .common)
        timer = ceiling
    }

    /// A refusal before the arm: a prepared microphone is let go so the input
    /// does not stay open, `start`'s own rule.
    private func refuseCamera(_ error: RecorderError, _ completion: (Error?) -> Void) {
        discardPreparedMicrophone()
        completion(error)
    }

    /// The capture runs on a warm stream (or did not): the warm-up's note,
    /// then segment 0 is minted now, named by the call's time, its writer armed
    /// and its microphone file started; then `.recording`, the completion,
    /// and a held stop.
    private func cameraCaptureStarted(_ capture: CameraCapture, error: (any Error)?) {
        guard state == .arming, let current = cameraSession, current.capture === capture else {
            return
        }
        if let error {
            return failCameraStart(
                error as? RecorderError ?? .cameraDevice(error.localizedDescription))
        }
        timer?.invalidate()
        timer = nil
        cameraSession?.camera.note = capture.warmUp?.note
        openCameraSegment(named: current.calledAt, in: current)
        state = .recording
        let completion = startCompletion
        startCompletion = nil
        completion?(nil)
        if pendingStop, state == .recording || state == .paused {
            pendingStop = false
            beginCameraFinishing()
        }
    }

    /// Mints the next segment NOW (its `calledAt`), named by `named`, appends
    /// it BEFORE anything is asked of it (so a report finds it), arms its
    /// writer and starts its microphone file.
    private func openCameraSegment(named: Date, in current: CameraSession) {
        var held = Set(current.segments.map(\.movieURL.path))
        held.formUnion(current.segments.compactMap { $0.micURL?.path })
        let movie = Self.nextCameraURL(in: current.choice.folder, at: named, holding: held)
        let micURL = current.micOutput == nil ? nil : RecordingFiles.microphoneURL(beside: movie)
        cameraSession?.segments.append(
            CameraSegment(movieURL: movie, micURL: micURL, calledAt: Date()))
        current.capture.beginSegment(movie)
        if let output = current.micOutput, let micURL, let delegate = current.micDelegate {
            output.startRecording(to: micURL, outputFileType: .m4a, recordingDelegate: delegate)
        }
    }

    /// A start that failed: everything stopped, nothing on disk (no segment
    /// was minted), every completion answered with the error.
    private func failCameraStart(_ error: RecorderError) {
        timer?.invalidate()
        timer = nil
        if let current = cameraSession {
            current.capture.stop()
            current.micSession?.stopRunning()
        }
        cameraSession = nil
        state = .idle
        microphoneProblem = nil
        pendingStop = false
        discardPreparedMicrophone()
        let completion = startCompletion
        startCompletion = nil
        completion?(error)
        let stops = stopCompletions
        stopCompletions = []
        stops.forEach { $0(.failure(error)) }
    }

    /// The capture stopped on its own: while arming the start fails; while
    /// recording or paused the recording ends (`.systemStopped`, the
    /// sentence the result's `camera.problem`) and what was written lands.
    private func cameraStoppedOnItsOwn(_ sentence: String) {
        switch state {
        case .arming:
            failCameraStart(.cameraDevice(sentence))
        case .recording, .paused:
            if cameraSession?.camera.problem == nil { cameraSession?.camera.problem = sentence }
            cameraSession?.stoppedBy = .systemStopped
            beginCameraFinishing()
        case .idle, .finishing:
            break
        }
    }

    // MARK: - Pause and resume

    /// MAIN THREAD, synchronous; `pause()` forwards here. `.recording` →
    /// `.paused`; `.paused` throws `.alreadyPaused`, anything else
    /// `.notRecording`. Stamps the open segment's `stoppedAt`, counts the
    /// pause, closes its writer and its microphone file (their reports land
    /// on THAT segment), silences the meter and posts
    /// `pauseDidChangeNotification`. The capture keeps running.
    func pauseCamera() throws {
        guard state != .paused else { throw RecorderError.alreadyPaused }
        guard state == .recording, let current = cameraSession, !current.segments.isEmpty else {
            throw RecorderError.notRecording
        }
        let last = current.segments.count - 1
        cameraSession?.segments[last].stoppedAt = Date()
        cameraSession?.pauses += 1
        closeCameraSegment(current.segments[last].movieURL, in: current)
        current.micOutput?.stopRecording()
        state = .paused
        meter.publish(.silent, from: ObjectIdentifier(self))
        NotificationCenter.default.post(name: Self.pauseDidChangeNotification, object: self)
    }

    /// MAIN THREAD, synchronous; `resume()` forwards here. `.paused` →
    /// `.recording`; anything else throws `.notPaused`. Mints the next
    /// segment, named by THIS moment, and starts its writer and its
    /// microphone file — a microphone that failed or stopped on its own
    /// before is asked again — never waiting for the paused segment's
    /// reports.
    func resumeCamera() throws {
        guard state == .paused, let current = cameraSession else { throw RecorderError.notPaused }
        openCameraSegment(named: Date(), in: current)
        state = .recording
        NotificationCenter.default.post(name: Self.pauseDidChangeNotification, object: self)
    }

    // MARK: - Stop

    /// MAIN THREAD; `stop()` forwards here while a camera recording is held.
    /// Idle → `.notRecording`; arming → held, finishing begins the moment
    /// the start lands; recording or paused → finishing begins now;
    /// finishing → JOINED, `stop()`'s own rule.
    func stopCamera(completion: ((Result<RecordingResult, Error>) -> Void)?) {
        switch state {
        case .idle:
            completion?(.failure(RecorderError.notRecording))
        case .arming:
            if let completion { stopCompletions.append(completion) }
            pendingStop = true
        case .recording, .paused:
            if let completion { stopCompletions.append(completion) }
            beginCameraFinishing()
        case .finishing:
            if let completion { stopCompletions.append(completion) }
        }
    }

    // MARK: - What is held

    /// Seconds recorded: each segment from its first buffer (else its mint)
    /// to its `stoppedAt` (else now), each floored at 0, so it freezes while
    /// paused; 0 idle and while arming.
    var cameraElapsed: TimeInterval {
        guard state != .idle, let current = cameraSession else { return 0 }
        let now = Date()
        return current.segments.reduce(0) { total, segment in
            total
                + max(
                    0,
                    (segment.stoppedAt ?? now).timeIntervalSince(
                        segment.startedAt ?? segment.calledAt))
        }
    }

    /// The next camera movie: `<stem>.mov`, then `<stem> (2).mov`, `(3)`… —
    /// `nextVoiceOverURL`'s rule over the files on DISK and the paths in
    /// `held`, a candidate whose microphone file is held skipped too
    /// (`nextMovieURL`'s), because a segment's files do not exist until its
    /// first buffer and the microphone's did-start.
    static func nextCameraURL(in folder: URL, at date: Date, holding held: Set<String>) -> URL {
        let stem = RecordingFiles.cameraStem(at: date)
        let manager = FileManager.default
        var candidate = folder.appendingPathComponent(stem).appendingPathExtension("mov")
        var counter = 2
        while manager.fileExists(atPath: candidate.path) || held.contains(candidate.path)
            || held.contains(RecordingFiles.microphoneURL(beside: candidate).path)
        {
            candidate = folder.appendingPathComponent("\(stem) (\(counter))")
                .appendingPathExtension("mov")
            counter += 1
        }
        return candidate
    }
}
