import AVFoundation
import AppKit

/// Everything that ENDS a camera recording (camera-recording CR1a, spec §11
/// CAM-3) — `+VoiceOverFinishing.swift`'s shape for a machine with a camera:
/// what the capture and the microphone report, the one finishing path, the
/// settle, the probe walk, the conclude and the microphone's offset.
///
/// **What the reports do.** A segment's writer answers its close with
/// whether it took a buffer and the writer's failure; that segment is then
/// finished. A microphone did-start is stamped with its arrival and its
/// `startPTS` on the host clock. A microphone did-finish nobody asked for —
/// one that ARRIVED before its segment's `stoppedAt`, or with none, the
/// voice-over's test — or one that did not finish well is that SEGMENT's
/// `micProblem` and the session's `microphoneProblem` once, and it NEVER
/// ends the recording: the picture records on (the screen recording's rule,
/// CAM-3). A camera that stops on its own does end it
/// (`+Camera.swift`'s `cameraStoppedOnItsOwn`).
///
/// **One finishing path**, from `.recording` or `.paused`: the open segment
/// stamped and its writer and microphone file closed, `.finishing`, the meter
/// silent, `finishingDidBeginNotification` posted, the wait bounded at
/// `finishCeiling` (in `.common`), and the wait's question asked once here.
/// **The settle runs once**: the capture and the microphone session
/// stopped, then each segment in order — dropped when its writer took no
/// buffer; left out (`UnreadableSegment`, its readable voice kept for the
/// slot) when its writer failed or its movie will not probe; otherwise its
/// microphone file probed and the segment landed with `cameraMicOffset`.
/// No segment with a frame is "The camera delivered no frame."; none
/// readable is the first left-out segment's failure; both name the files on
/// disk.
extension ScreenRecorder {
    // MARK: - The reports

    /// Asks the capture to close `url`'s writer; its answer lands on that
    /// segment (`cameraSegmentEnded`).
    func closeCameraSegment(_ url: URL, in current: CameraSession) {
        current.capture.endSegment { [weak self, weak capture = current.capture] wrote, failure in
            guard let self, let capture else { return }
            self.cameraSegmentEnded(url, capture: capture, wrote: wrote, failure: failure)
        }
    }

    /// A segment's writer closed (`closeCameraSegment`).
    func cameraSegmentEnded(_ url: URL, capture: CameraCapture, wrote: Bool, failure: String?) {
        guard let current = cameraSession, current.capture === capture,
            let index = current.index(ofMovie: url)
        else { return }
        cameraSession?.segments[index].movieFinished = true
        cameraSession?.segments[index].wrote = wrote
        cameraSession?.segments[index].movieFailure = failure
        checkCameraFinished()
    }

    func cameraMicStarted(_ url: URL, output: AVCaptureFileOutput, startPTS: CMTime, at: Date) {
        guard let current = cameraSession, current.micOutput === output,
            let index = current.index(ofMicrophoneFile: url),
            current.segments[index].micStartedAt == nil
        else { return }
        cameraSession?.segments[index].micStartedAt = at
        cameraSession?.segments[index].micPTS = CameraCapture.hostSeconds(
            startPTS, from: current.micSession?.synchronizationClock)
    }

    func cameraMicFinished(
        _ url: URL, output: AVCaptureFileOutput, finishedWell: Bool, error: (any Error)?,
        at arrived: Date
    ) {
        guard let current = cameraSession, current.micOutput === output,
            let index = current.index(ofMicrophoneFile: url)
        else { return }
        cameraSession?.segments[index].micFinished = true
        let unasked = current.segments[index].stoppedAt.map { arrived < $0 } ?? true
        var sentence: String?
        if unasked {
            sentence =
                "The microphone stopped recording on its own: "
                + (error?.localizedDescription ?? "It reported no error.")
                + " The picture was recorded on without it."
        } else if !finishedWell {
            sentence =
                "The microphone recording failed: "
                + (error?.localizedDescription ?? "it reported no error.")
        }
        if let sentence, current.segments[index].micProblem == nil {
            cameraSession?.segments[index].micProblem = sentence
            if unasked, microphoneProblem == nil { microphoneProblem = sentence }
            if index == current.segments.count - 1 {
                meter.publish(.silent, from: ObjectIdentifier(self))
            }
        }
        // The picture records on: a microphone never ends a camera recording (CAM-3).
        checkCameraFinished()
    }

    // MARK: - The finishing path

    /// From `.recording` or `.paused`; anything else changes nothing.
    func beginCameraFinishing() {
        guard state == .recording || state == .paused, let current = cameraSession else { return }
        timer?.invalidate()
        let wasRecording = state == .recording
        state = .finishing
        meter.publish(.silent, from: ObjectIdentifier(self))
        if wasRecording, let last = current.segments.indices.last {
            if current.segments[last].stoppedAt == nil {
                cameraSession?.segments[last].stoppedAt = Date()
            }
            closeCameraSegment(current.segments[last].movieURL, in: current)
            current.micOutput?.stopRecording()
        }
        NotificationCenter.default.post(name: Self.finishingDidBeginNotification, object: self)
        let ceiling = Timer(timeInterval: Self.finishCeiling, repeats: false) { [weak self] _ in
            guard let self, self.state == .finishing, self.cameraSession?.settling == false
            else { return }
            self.cameraSession?.timedOut = true
            self.settleCamera()
        }
        RunLoop.main.add(ceiling, forMode: .common)
        timer = ceiling
        // Last, so a synchronous settle finds the timer to invalidate.
        checkCameraFinished()
    }

    /// Every writer closed and, with a microphone, every microphone file's
    /// did-finish landed: settle.
    func checkCameraFinished() {
        guard state == .finishing, let current = cameraSession, !current.settling,
            current.segments.allSatisfy({
                $0.movieFinished && (current.micOutput == nil || $0.micFinished)
            })
        else { return }
        settleCamera()
    }

    /// Once per session: the capture and the microphone stopped, then the walk.
    private func settleCamera() {
        guard let done = cameraSession, !done.settling else { return }
        cameraSession?.settling = true
        timer?.invalidate()
        timer = nil
        done.capture.stop()
        done.micSession?.stopRunning()
        meter.publish(.silent, from: ObjectIdentifier(self))
        probeCameraSegment(done, at: 0, landed: [], skipped: [])
    }

    /// Segment `index`, then the next, in order — each probe's completion is
    /// on main, and the order of `landed` IS the order the landing places
    /// the clips in.
    private func probeCameraSegment(
        _ done: CameraSession, at index: Int, landed: [RecordingSegment],
        skipped: [UnreadableSegment]
    ) {
        guard index < done.segments.count else { return concludeCamera(done, landed, skipped) }
        let segment = done.segments[index]
        let next: ([RecordingSegment], [UnreadableSegment]) -> Void = {
            [weak self] landed, skipped in
            self?.probeCameraSegment(done, at: index + 1, landed: landed, skipped: skipped)
        }
        if segment.movieFinished, !segment.wrote, segment.movieFailure == nil {
            return next(landed, skipped)  // no frame: cancelled and dropped
        }
        if let failure = segment.movieFailure {
            return leftOutCamera(done, at: index, .finishFailed(failure), landed.count) {
                next(landed, skipped + [$0])
            }
        }
        MediaImporter.probe(url: segment.movieURL, mayAsk: done.mayAsk) { [weak self] movie in
            guard let self else { return }
            switch movie {
            case .failure(let error):
                let reason: RecorderError =
                    done.timedOut && !segment.movieFinished
                    ? .timedOut
                    : .finishFailed(
                        "The camera recording could not be read: " + error.localizedDescription)
                self.leftOutCamera(done, at: index, reason, landed.count) {
                    next(landed, skipped + [$0])
                }
            case .success(let descriptor):
                self.probeCameraMicrophone(done, at: index, movie: descriptor) {
                    next(landed + [$0], skipped)
                }
            }
        }
    }

    /// Segment `index` left out for `reason`: its files on disk named, and
    /// its microphone file probed so a readable voice lands in its slot
    /// (#181 item 2's rule).
    private func leftOutCamera(
        _ done: CameraSession, at index: Int, _ reason: RecorderError, _ position: Int,
        then: @escaping (UnreadableSegment) -> Void
    ) {
        let segment = done.segments[index]
        let kept = [segment.movieURL.path, segment.micURL?.path].compactMap { $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
        let plain = UnreadableSegment(
            moviePath: segment.movieURL.path, keptFiles: kept, error: reason, position: position)
        guard let micURL = segment.micURL, segment.micProblem == nil,
            FileManager.default.fileExists(atPath: micURL.path)
        else { return then(plain) }
        MediaImporter.probe(url: micURL, mayAsk: done.mayAsk) { mic in
            guard case .success(let descriptor) = mic else { return then(plain) }
            then(
                UnreadableSegment(
                    moviePath: plain.moviePath, keptFiles: kept, error: reason,
                    micDescriptor: descriptor, position: position))
        }
    }

    /// The microphone's half of one segment, then the landed segment.
    private func probeCameraMicrophone(
        _ done: CameraSession, at index: Int, movie: MediaDescriptor,
        then: @escaping (RecordingSegment) -> Void
    ) {
        let segment = done.segments[index]
        func landed(_ mic: MediaDescriptor?, _ problem: String?) -> RecordingSegment {
            let offset =
                mic == nil
                ? 0
                : Self.cameraMicOffset(
                    cameraPTS: segment.firstPTS, micPTS: segment.micPTS,
                    cameraArrived: segment.startedAt, micArrived: segment.micStartedAt)
            return RecordingSegment(
                descriptor: movie, micDescriptor: mic, micOffset: offset,
                startedAt: segment.startedAt ?? segment.calledAt, micProblem: problem)
        }
        guard let micURL = segment.micURL else { return then(landed(nil, nil)) }
        let exists = FileManager.default.fileExists(atPath: micURL.path)
        if let problem = segment.micProblem {
            return then(landed(nil, problem + (exists ? " What it wrote is at \(micURL.path)." : "")))
        }
        MediaImporter.probe(url: micURL, mayAsk: done.mayAsk) { mic in
            switch mic {
            case .success(let descriptor):
                then(landed(descriptor, nil))
            case .failure(let error):
                let problem =
                    segment.micStartedAt == nil
                    ? "The microphone never started recording, so the picture was recorded "
                        + "without it."
                    : "The microphone recording could not be read: " + error.localizedDescription
                then(landed(nil, problem + (exists ? " Its file is at \(micURL.path)." : "")))
            }
        }
    }

    /// The ONE outcome, to `onFinish` and every registered stop completion,
    /// after the recorder is idle again. The capture and the microphone are
    /// stopped here too (idempotent), and a prepared microphone let go.
    private func concludeCamera(
        _ done: CameraSession, _ landed: [RecordingSegment], _ skipped: [UnreadableSegment]
    ) {
        let outcome: Result<RecordingResult, Error>
        if landed.isEmpty {
            let manager = FileManager.default
            let movies = done.segments.map(\.movieURL.path).filter { manager.fileExists(atPath: $0) }
            let mics = done.segments.compactMap { $0.micURL?.path }
                .filter { manager.fileExists(atPath: $0) }
            let first = skipped.first?.error ?? .finishFailed("The camera delivered no frame.")
            outcome = .failure(
                movies.isEmpty && mics.isEmpty
                    ? first
                    : RecorderError.filesKept(
                        first, movie: movies.joined(separator: ", "),
                        microphone: mics.isEmpty ? nil : mics.joined(separator: ", ")))
        } else {
            outcome = .success(
                RecordingResult(
                    segments: landed, choice: done.choice,
                    stoppedBy: cameraSession?.stoppedBy ?? done.stoppedBy, pauses: done.pauses,
                    unreadable: skipped, camera: cameraSession?.camera ?? done.camera))
        }
        done.capture.stop()
        done.micSession?.stopRunning()
        cameraSession = nil
        state = .idle
        timer?.invalidate()
        timer = nil
        microphoneProblem = nil
        pendingStop = false
        discardPreparedMicrophone()
        let stops = stopCompletions
        stopCompletions = []
        done.onFinish(outcome)
        stops.forEach { $0(outcome) }
    }

    // MARK: - The offset (CAM-3)

    /// The picture's start minus the microphone's, in ticks: the two PTSs on
    /// the host clock when both are known, else the two arrival stamps, else
    /// 0. POSITIVE means the picture began after the microphone
    /// (`RecordingSegment.micOffset`'s sign).
    static func cameraMicOffset(
        cameraPTS: Double?, micPTS: Double?, cameraArrived: Date?, micArrived: Date?
    ) -> Ticks {
        var seconds: Double = 0
        if let cameraPTS, let micPTS {
            seconds = cameraPTS - micPTS
        } else if let cameraArrived, let micArrived {
            seconds = cameraArrived.timeIntervalSince(micArrived)
        }
        return Ticks((seconds * Double(ReelTime.perSecond)).rounded())
    }
}

extension ScreenRecorder.CameraSession {
    /// The segment whose movie is `url`, compared by path.
    func index(ofMovie url: URL) -> Int? {
        segments.firstIndex { $0.movieURL.path == url.path }
    }

    /// The segment whose microphone file is `url`, compared by path.
    func index(ofMicrophoneFile url: URL) -> Int? {
        segments.firstIndex { $0.micURL?.path == url.path }
    }
}

/// The camera recording's microphone file delegate. Each callback is stamped
/// where it lands (a private queue) and hopped to main, where the recorder
/// finds the segment by the file's URL; a late callback from a session that
/// has ended finds none. The did-start is the `startPTS` form, whose
/// timestamp the offset is measured by (CAM-3).
final class CameraMicrophoneDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private weak var recorder: ScreenRecorder?

    init(recorder: ScreenRecorder) {
        self.recorder = recorder
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CameraMicrophoneDelegate does not support NSCoder")
    }

    func fileOutput(
        _ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, startPTS: CMTime,
        from connections: [AVCaptureConnection]
    ) {
        let at = Date()
        DispatchQueue.main.async { [weak self] in
            self?.recorder?.cameraMicStarted(fileURL, output: output, startPTS: startPTS, at: at)
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection], error: (any Error)?
    ) {
        // Stamped here: whether the stop was asked for is judged by when this
        // report ARRIVED, not by when main reads it.
        let at = Date()
        let finishedWell =
            error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool)
                == true
        DispatchQueue.main.async { [weak self] in
            self?.recorder?.cameraMicFinished(
                outputFileURL, output: output, finishedWell: finishedWell, error: error, at: at)
        }
    }
}
