import AVFoundation
import AppKit

/// A camera BESIDE the screen (camera-recording CR3a, spec §11 CAM-9): a
/// screen recording — a display, a window or a picked source — whose choice
/// names a camera records it too, one `<movie stem> (Camera).mov` per
/// segment, written by `CameraCapture` (one `AVAssetWriter` per segment on
/// one running session, CAM-3) and paused and resumed with the screen's
/// output. This file is the camera's lookup, its arming, the one launch turn,
/// each writer's open and close, the capture's reports and the camera that
/// stops on its own; `+CameraBesideFinishing.swift` is each landed segment's
/// camera half and the offset; `ScreenFrameWatch.swift` is E2.
///
/// **The warm-up comes before the stream** (CAM-9 (2)). The recorder stays
/// `.arming` while the capture starts or joins its prepared start, so CAM-3's
/// warm-up is spent before the screen begins; on its answer ONE main turn,
/// `launchScreen`, starts the microphone's file, the stream and segment 0's
/// camera writer (CR0: the order of the starts made no measurable
/// difference). A start without a camera calls `launchScreen` in its own
/// turn, so road map 3's order is unchanged.
///
/// **A camera failure is never the recording's** (CAM-9 (7)): a camera that
/// stops on its own while recording or paused is the result's
/// `camera.problem`, its open writer closed and no later segment given one;
/// only while arming does it fail the start. Every report hops to main (the
/// capture does it) and finds its segment by the camera file's URL, never
/// "the current one".
extension ScreenRecorder {
    /// One segment's camera writer and the stamps its offset is read from:
    /// the first buffer's arrival and its PTS on the host clock (CAM-3); the
    /// screen's did-start on the host clock (E1) and the first complete frame
    /// at or after it (E2, `ScreenFrameWatch`); and the writer's close —
    /// `finished` once it answered, `wrote` false for a writer that took no
    /// buffer (its file removed), `failure` a writer that did not complete;
    /// `watchFailure`, the frame watch's re-add at this segment's resume
    /// that threw (CAM-9 (6)), so E1 places it.
    struct CameraBesideSegment {
        let url: URL
        var startedAt: Date?
        var pts: Double?
        var screenHost: Double?
        var firstFrame: Double?
        var finished = false
        var wrote = false
        var failure: String?
        var watchFailure: String?
    }

    // MARK: - The start

    /// `start`'s camera, after the Camera grant was read: nil without
    /// `choice.camera`; else the connected device that id names and its
    /// format (`chosenFormat`, CAM-6 (3)). Throws `.cameraDevice` for an id no
    /// connected camera carries or a camera that lists no format.
    func cameraBesideDevice(for choice: RecordingChoice) throws
        -> (device: AVCaptureDevice, format: Int)?
    {
        guard let id = choice.camera else { return nil }
        guard let device = CameraDevices.device(withID: id) else {
            throw RecorderError.cameraDevice("No camera with the id \(id) is connected.")
        }
        let facts = CameraDevices.facts(of: device)
        guard
            let format = CameraDevices.chosenFormat(
                choice.cameraFormat, in: facts.formats, active: facts.activeFormat)
        else {
            throw RecorderError.cameraDevice("The camera \(device.localizedName) lists no format.")
        }
        return (device, format)
    }

    /// MAIN THREAD, while `.arming`: the capture's reports installed, then
    /// the capture started (or its prepared start joined,
    /// `startCameraCapture`). Its answer is the launch turn, or — a capture
    /// that did not start — the start's failure.
    func armCameraBeside(_ capture: CameraCapture) {
        capture.onSegmentStarted = { [weak self, weak capture] url, pts, arrived in
            guard let self, let capture, let current = self.session,
                current.cameraCapture === capture,
                let index = current.segments.firstIndex(where: { $0.camera?.url.path == url.path }),
                current.segments[index].camera?.startedAt == nil
            else { return }
            self.session?.segments[index].camera?.startedAt = arrived
            self.session?.segments[index].camera?.pts = pts.isFinite ? pts : nil
        }
        capture.onStoppedOnItsOwn = { [weak self, weak capture] sentence in
            guard let self, let capture, self.session?.cameraCapture === capture else { return }
            self.cameraBesideStoppedOnItsOwn(sentence)
        }
        startCameraCapture(capture) { [weak self, weak capture] error in
            guard let self, let capture, self.state == .arming,
                self.session?.cameraCapture === capture
            else { return }
            if let error {
                return self.failStart(
                    error as? RecorderError ?? .cameraDevice(error.localizedDescription))
            }
            self.session?.camera?.note = capture.warmUp?.note
            self.launchScreen()
        }
    }

    /// MAIN THREAD, `.arming`: the one launch turn (CAM-9 (2)) — the
    /// microphone's file (when one was chosen), then the stream, then
    /// segment 0's camera writer (none without a camera). `startCapture`'s
    /// completion is `captureStarted`'s, which leaves `.arming`.
    func launchScreen() {
        guard state == .arming, let current = session else { return }
        if let micOutput = current.micOutput, let micURL = current.segments[0].micURL {
            session?.segments[0].micRecordingCalledAt = Date()
            micOutput.startRecording(to: micURL, outputFileType: .m4a, recordingDelegate: self)
        }
        let stream = current.stream
        stream.startCapture { [weak self] error in
            let at = Date()
            DispatchQueue.main.async { self?.captureStarted(stream, error: error, at: at) }
        }
        openCameraBeside(at: 0)
    }

    // MARK: - The writers

    /// MAIN THREAD. Arms segment `index`'s camera writer beside its movie
    /// (`cameraURL(beside:)`, CAM-9 (5)); nothing without a camera, once it
    /// stopped on its own, or for a segment that has one.
    func openCameraBeside(at index: Int) {
        guard let current = session, let capture = current.cameraCapture,
            current.camera?.problem == nil, current.segments.indices.contains(index),
            current.segments[index].camera == nil
        else { return }
        let url = RecordingFiles.cameraURL(beside: current.segments[index].movieURL)
        session?.segments[index].camera = CameraBesideSegment(url: url)
        capture.beginSegment(url)
    }

    /// MAIN THREAD. Asks segment `index`'s writer to close; its answer lands
    /// on that segment by the file's URL. Called only where the writer is
    /// open — a pause, the finishing from `.recording`, a camera that stopped
    /// on its own while recording (before its `problem` is set) — so a
    /// writer is never asked twice.
    func closeCameraBeside(at index: Int) {
        guard let current = session, let capture = current.cameraCapture,
            current.camera?.problem == nil, current.segments.indices.contains(index),
            let camera = current.segments[index].camera, !camera.finished
        else { return }
        let url = camera.url
        capture.endSegment { [weak self, weak capture] wrote, failure in
            guard let self, let capture, let current = self.session,
                current.cameraCapture === capture,
                let found = current.segments.firstIndex(where: { $0.camera?.url.path == url.path })
            else { return }
            self.session?.segments[found].camera?.finished = true
            self.session?.segments[found].camera?.wrote = wrote
            self.session?.segments[found].camera?.failure = failure
            self.checkFinished()
        }
    }

    /// `failStart`'s camera (CAM-9 (8)): the watch stopped, segment 0's
    /// writer closed — its file removed unless the screen output had begun
    /// writing — and the capture stopped.
    func tearDownCameraBeside(_ current: Session) {
        current.frameWatch?.stop()
        guard let capture = current.cameraCapture else { return }
        if let camera = current.segments[0].camera, !camera.finished {
            let keep = current.segments[0].screenStartedAt != nil
            capture.endSegment { _, _ in
                if !keep { try? FileManager.default.removeItem(at: camera.url) }
            }
        }
        capture.stop()
    }

    // MARK: - The reports

    /// MAIN THREAD. Segment `index`'s screen did-start arrived at `host` on
    /// the host clock (E1): stamped on its camera, and the watch asked for
    /// E2 (CAM-9 (3)), whose answer finds the segment by its output — not
    /// when the watch could not go back on the stream at its resume (E1).
    func screenDidStart(at index: Int, host: Double) {
        guard let current = session, let watch = current.frameWatch,
            current.segments.indices.contains(index), current.segments[index].camera != nil
        else { return }
        session?.segments[index].camera?.screenHost = host
        guard current.segments[index].camera?.watchFailure == nil else { return }
        let output = current.segments[index].output
        watch.firstComplete(for: index, atOrAfter: host) { [weak self] pts in
            guard let self, let found = self.session?.index(of: output) else { return }
            self.session?.segments[found].camera?.firstFrame = pts
        }
    }

    /// The camera stopped on its own (CAM-9 (7)): while arming the start
    /// fails with its sentence; while recording or paused it is the
    /// result's `camera.problem`, once — the open writer closed first, so
    /// what it wrote lands, the capture let go, and no later segment armed —
    /// and the screen records on.
    func cameraBesideStoppedOnItsOwn(_ sentence: String) {
        switch state {
        case .arming:
            failStart(.cameraDevice(sentence))
        case .recording, .paused:
            guard let current = session, current.camera?.problem == nil else { return }
            if state == .recording { closeCameraBeside(at: current.lastIndex) }
            session?.camera?.problem = sentence
            current.cameraCapture?.stop()
        case .idle, .finishing:
            break
        }
    }
}
