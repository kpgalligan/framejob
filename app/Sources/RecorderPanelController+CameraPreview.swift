import AVFoundation
import AppKit

/// What the camera preview's well does at one sync (spec §11 CAM-7 (3)).
enum CameraPreviewStep: Equatable {
    case off
    case message(String)
    case failed(String)
    case prepare
    case prepared
    case recording
    case blank
}

/// The camera's live preview in the panel (camera-recording CR2b, spec §11
/// CAM-7) — `RecorderPanelController.swift`'s eleventh file, NEW rather than
/// cut, as `+Camera.swift` was: the rule that says what the well shows, and
/// the one sync that acts on it. The well is `CameraPreviewWell`, a grid row
/// of its own right under Format (`+Rows.swift`), shown only while a camera
/// is wanted: Source Camera, or "Record the camera too" beside a screen
/// source (spec §11 CAM-11 (4)).
///
/// **The step** (`cameraPreviewStep`, pure, first match wins): a panel not
/// visible or closing, or no camera wanted → off; a camera recording, or a
/// screen recording's camera beside it → its layer; the countdown or
/// starting → the prepared layer, never a build; any other phase, or a
/// busy recorder → blank; no camera → "No camera is connected."; the
/// Camera grant not authorized → a sentence; a prepared capture that
/// failed, or a build that threw → its sentence, never retried; else
/// prepare. The grant is read only at its own step, through
/// `grantDoors.cameraStatus`, so showing the panel never prompts and a
/// hidden panel reads nothing.
///
/// **The sync** runs at the end of `show()`, of every control change, of
/// `syncPhase()`, at the one-second tick while the panel is visible, and at
/// each device notification. Its first act applies a pending hot-plug
/// (`+Devices.swift`, CAM-8 (2)), so the step sees the new selection. It
/// keeps the row's visibility (refitting the window when it changes), lets
/// the prepared capture go when the well is off or shows a sentence while
/// everything is idle, stops a failed prepared capture once (not at every
/// tick, CAM-8 (6)), and otherwise hosts the layer the step names. The
/// capture is the recorder's (`ScreenRecorder+CameraPrepare.swift`): the
/// countdown's `prepareCamera` keeps it, the panel's start adopts it, and a
/// tool's start never does (CAM-7 (7)), so through a tool's recording the
/// well reads "The camera is recording."
extension RecorderPanelController {
    static let previewGrantSentence = "The preview shows once Frame Job may use the camera."
    static let previewRecordingSentence = "The camera is recording."

    /// CAM-7 (3)'s rule. `grant` and `failure` are called only at their own
    /// steps.
    static func cameraPreviewStep(
        visible: Bool, cameraSource: Bool, phase: Phase, recorderIdle: Bool,
        recordingCamera: Bool, cameraChosen: Bool, grant: () -> AVAuthorizationStatus,
        failure: () -> String?
    ) -> CameraPreviewStep {
        guard visible, cameraSource else { return .off }
        if recordingCamera { return .recording }
        switch phase {
        case .countdown, .starting: return .prepared
        case .idle: break
        case .recording, .paused, .stopping, .landing: return .blank
        }
        guard recorderIdle else { return .blank }
        guard cameraChosen else { return .message(CameraDevices.noCameraSentence) }
        guard grant() == .authorized else { return .message(Self.previewGrantSentence) }
        if let failure = failure() { return .failed(failure) }
        return .prepare
    }

    /// The well's grid row.
    var cameraPreviewRow: NSGridRow? {
        (cameraPreview.superview as? NSGridView)?.cell(for: cameraPreview)?.row
    }

    /// For the chosen camera at its resolved format (CAM-6 (3)): the
    /// prepared capture's stop on its own, else its failed start, else a
    /// failed build's record; nil when there is none.
    var previewFailure: String? {
        guard let id = selectedCameraID, let device = CameraDevices.device(withID: id) else {
            return nil
        }
        let facts = CameraDevices.facts(of: device)
        guard
            let format = CameraDevices.chosenFormat(
                selectedCameraFormat, in: facts.formats, active: facts.activeFormat)
        else { return nil }
        if let prepared = recorder.preparedCamera, prepared.deviceID == id, prepared.format == format,
            let sentence = prepared.stoppedOnItsOwn ?? prepared.startError?.localizedDescription
        {
            return sentence
        }
        guard let failure = recorder.preparedCameraFailure, failure.deviceID == id,
            failure.format == format
        else { return nil }
        return failure.sentence
    }

    /// A pending hot-plug applied (CAM-8 (2)), the row's visibility, then the
    /// step acted on (the type doc).
    func syncCameraPreview() {
        applyPendingDevices()
        let hidden = !cameraWanted
        if let row = cameraPreviewRow, row.isHidden != hidden {
            row.isHidden = hidden
            fitWindowToContent()
        }
        let step = Self.cameraPreviewStep(
            visible: window?.isVisible == true && !panelClosing, cameraSource: cameraWanted,
            phase: phase, recorderIdle: recorder.state == .idle,
            recordingCamera: recorder.cameraSession != nil || recorder.session?.cameraCapture != nil,
            cameraChosen: selectedCameraID != nil,
            grant: { Self.grantDoors.cameraStatus() }, failure: { self.previewFailure })
        switch step {
        case .off, .message:
            if phase == .idle, recorder.state == .idle { recorder.discardPreparedCamera() }
            if case .message(let sentence) = step {
                cameraPreview.showMessage(sentence)
            } else {
                cameraPreview.showMessage(nil)
            }
        case .failed(let sentence):
            if let capture = recorder.preparedCamera?.capture, !capture.stopped { capture.stop() }
            cameraPreview.showMessage(sentence)
        case .prepare:
            recorder.prepareCamera(for: currentChoice())
            hostPreview(recorder.preparedCamera?.capture.previewLayer, else: nil)
        case .prepared:
            hostPreview(recorder.preparedCamera?.capture.previewLayer, else: nil)
        case .recording:
            hostPreview(
                (recorder.cameraSession?.capture ?? recorder.session?.cameraCapture)?.previewLayer,
                else: Self.previewRecordingSentence)
        case .blank:
            cameraPreview.showMessage(nil)
        }
    }

    /// `layer` in the well, else `sentence` (nil a blank well).
    private func hostPreview(_ layer: AVCaptureVideoPreviewLayer?, else sentence: String?) {
        if let layer {
            cameraPreview.show(layer)
        } else {
            cameraPreview.showMessage(sentence)
        }
    }
}
