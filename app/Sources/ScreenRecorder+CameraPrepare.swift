import AVFoundation
import AppKit

/// A camera's capture PREPARED during the panel's countdown (camera-recording
/// CR1c, spec §11 CAM-5): `prepareMicrophone`'s precedent for the camera.
/// CAM-3's warm-up holds `startCamera` until the stream runs at the format's
/// rate — about 0.5 s on the built-in camera, on top of the session's own
/// start — so the countdown builds and starts the capture at its first
/// second, and `startCamera` ADOPTS it when it is the same device at the same
/// format, not adopted before, with no failed start and no stop on its own.
/// Otherwise it is let go and a fresh one is built, as before. The tool never
/// prepares, so its start still pays the hold.
///
/// **A start never calls `CameraCapture.start` twice.** The prepared
/// capture's start completion is recorded on its `PreparedCamera`
/// (`answered`, `startError`); an adopting start that comes after it is
/// answered on the next main turn, and one that comes BEFORE it — a countdown
/// shorter than the warm-up — is held in `waiting` and JOINS it. That
/// completion holds its `PreparedCamera` STRONGLY, the one retained closure
/// here without `[weak …]`: the slot is cleared at the join, so a weak
/// reference would drop the waiting start, which would then sit in `.arming`
/// until the arm ceiling. It is released when it fires, and it always fires:
/// the capture's warm-up ends at `warmUpBound` even after `stop()`.
///
/// **No prompt**: `RecordingGrant.cameraStatus` is read before any
/// `CameraCapture` (whose `AVCaptureDeviceInput` prompts on
/// `.notDetermined`); nothing here asks.
extension ScreenRecorder {
    /// One prepared capture: what it was made for, and what its start has
    /// answered so far. Main thread only.
    final class PreparedCamera {
        let deviceID: String
        let format: Int
        let capture: CameraCapture
        /// `takeCameraCapture` handed it to a start.
        var adopted = false
        /// The capture's `onStoppedOnItsOwn` sentence, while prepared.
        var stoppedOnItsOwn: String?
        /// The capture's start completion has fired, with `startError`.
        var answered = false
        var startError: (any Error)?
        /// An adopting start's completion, held until the prepared start
        /// answers (the join).
        var waiting: ((Error?) -> Void)?

        init(deviceID: String, format: Int, capture: CameraCapture) {
            self.deviceID = deviceID
            self.format = format
            self.capture = capture
        }
    }

    // MARK: - Prepare and discard

    /// MAIN THREAD, idle only. Acts only for a `.camera` choice naming a
    /// camera, with the Camera grant `.authorized`, the camera connected and
    /// a best format (CAM-3); otherwise it does nothing and leaves nothing
    /// behind. A prepared capture that `startCamera` could still adopt for
    /// the same device and format is kept; any other is let go first. Blocks
    /// main for the capture's construction; the session starts on its own
    /// queue.
    func prepareCamera(for choice: RecordingChoice) {
        guard state == .idle, choice.source == .camera, let id = choice.camera,
            RecordingGrant.cameraStatus == .authorized,
            let device = CameraDevices.device(withID: id)
        else { return }
        let facts = CameraDevices.facts(of: device)
        guard let format = CameraDevices.bestFormat(facts.formats, active: facts.activeFormat)
        else { return }
        if let prepared = preparedCamera, Self.adoptable(prepared, device: id, format: format) {
            return
        }
        discardPreparedCamera()
        guard let capture = try? CameraCapture(device: device, format: format) else { return }
        let prepared = PreparedCamera(deviceID: id, format: format, capture: capture)
        capture.onStoppedOnItsOwn = { [weak prepared] sentence in
            prepared?.stoppedOnItsOwn = sentence
        }
        preparedCamera = prepared
        // Strong on purpose (the type doc): a join after the slot is cleared
        // still fires `waiting`.
        capture.start { error in
            prepared.answered = true
            prepared.startError = error
            let waiting = prepared.waiting
            prepared.waiting = nil
            waiting?(error)
        }
    }

    /// MAIN THREAD. Stops and forgets the prepared capture, if there is one;
    /// idempotent.
    func discardPreparedCamera() {
        preparedCamera?.capture.stop()
        preparedCamera = nil
    }

    /// Whether a start for `device` at `format` may adopt `prepared` (CAM-5
    /// (5)): the same device and format, not adopted before, no failed
    /// start, no stop on its own.
    static func adoptable(_ prepared: PreparedCamera, device: String, format: Int) -> Bool {
        prepared.deviceID == device && prepared.format == format && !prepared.adopted
            && prepared.startError == nil && prepared.stoppedOnItsOwn == nil
    }

    // MARK: - Take and start

    /// `startCamera`'s capture: the prepared one, marked adopted, when it is
    /// adoptable for `device` at `format`; else the prepared one is let go
    /// and a fresh `CameraCapture` built (throwing as its `init` does).
    func takeCameraCapture(device: AVCaptureDevice, format: Int) throws -> CameraCapture {
        if let prepared = preparedCamera,
            Self.adoptable(prepared, device: device.uniqueID, format: format)
        {
            prepared.adopted = true
            return prepared.capture
        }
        discardPreparedCamera()
        return try CameraCapture(device: device, format: format)
    }

    /// `startCamera`'s start. The ADOPTED capture: the slot is cleared, and
    /// the start joins the prepared one — answered already, `completion` on
    /// the next main turn with its error; not yet, held in `waiting`. Any
    /// other capture is started here. `CameraCapture.start` is never called
    /// twice on one capture.
    func startCameraCapture(_ capture: CameraCapture, completion: @escaping (Error?) -> Void) {
        guard let prepared = preparedCamera, prepared.capture === capture, prepared.adopted else {
            return capture.start(completion: completion)
        }
        preparedCamera = nil
        if prepared.answered {
            let error = prepared.startError
            DispatchQueue.main.async { completion(error) }
        } else {
            prepared.waiting = completion
        }
    }
}
