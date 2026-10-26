import AVFoundation
import AppKit

/// The Source row "Camera" — a CAMERA recording from the panel
/// (camera-recording CR1c, spec §11 CAM-5) — `RecorderPanelController.swift`'s
/// tenth file, NEW rather than cut, as `+VoiceOver.swift` was: it is the whole
/// of what the panel adds for a camera, and the base file, `+Rows.swift`,
/// `+Grants.swift`, `+Recording.swift` and `+Landing.swift` learn it by a line
/// or two each.
///
/// **The row** sits between "Window…" (tag 1) and "Microphone Only" (tag 2),
/// by tag 3. It persists for the session only, as Microphone Only does: the
/// display key is left alone while it is chosen. Chosen, it greys System
/// Audio, Show Clicks, Size, Include Frame Job windows and Rate with their
/// values KEPT — a camera records at its own format's rate — and enables the
/// Camera popup; Microphone and Record Into stay live.
///
/// **The Camera popup** lists `CameraDevices.connected()` by name, each row
/// carrying its `uniqueID` (app/CLAUDE.md "Popups"), or one row "None
/// connected" with no id. Its selection is the stored `FrameJobRecordingCamera`
/// when that camera is listed, else CAM-3 (7)'s default. It is rebuilt on
/// `show()` while idle; a camera plugged in while the panel is up is CR2's.
///
/// **The press** never reads or asks the Screen Recording grant: no camera
/// refuses with a note, then the Camera grant (`+Grants.swift`), then the
/// Microphone grant, then the same 3-2-1 — during which `beginCountdown`
/// prepares the camera's capture, so CAM-3's warm-up is spent there
/// (`ScreenRecorder+CameraPrepare.swift`). The start is `startCamera`.
///
/// **The panel STAYS UP while a camera records** (the voice-over's
/// precedent, `hidesForRecording`): nothing on screen is filmed, so the rows
/// lock, the meter is live, and Record reads Stop with the Pause / Resume
/// button beside it.
extension RecorderPanelController {
    static let cameraTag = 3
    static let cameraTitle = "Camera"
    static let noCameraTitle = "None connected"

    var cameraSelected: Bool { sourcePopup.selectedItem?.tag == Self.cameraTag }

    /// The Camera popup's chosen `uniqueID`; nil for "None connected".
    var selectedCameraID: String? { cameraPopup.selectedItem?.representedObject as? String }

    // MARK: - The popup

    /// Every connected camera by name, carrying its `uniqueID`, or the one
    /// row "None connected"; the selection kept when it is still listed,
    /// else the default (`selectCamera`).
    func rebuildCameras() {
        let current = selectedCameraID
        cameraPopup.removeAllItems()
        let cameras = CameraDevices.connected()
        for camera in cameras {
            let item = NSMenuItem(title: camera.localizedName, action: nil, keyEquivalent: "")
            item.representedObject = camera.uniqueID
            cameraPopup.menu?.addItem(item)
        }
        if cameras.isEmpty {
            cameraPopup.menu?.addItem(
                NSMenuItem(title: Self.noCameraTitle, action: nil, keyEquivalent: ""))
        }
        selectCamera(current)
    }

    /// The row carrying `id`; nil, or an id no row carries, selects the
    /// default camera's row (CAM-3 (7): the system's preferred camera, else
    /// the first built-in, else the first), else the first row.
    func selectCamera(_ id: String?) {
        let rows = cameraPopup.itemArray
        if let id, let index = rows.firstIndex(where: { $0.representedObject as? String == id }) {
            cameraPopup.selectItem(at: index)
            return
        }
        let cameras = CameraDevices.connected().map(CameraDevices.facts(of:))
        let preferred = AVCaptureDevice.systemPreferredCamera?.uniqueID
        let wanted = CameraDevices.defaultIndex(in: cameras, preferredID: preferred).map {
            cameras[$0].uniqueID
        }
        let index =
            wanted.flatMap { wanted in
                rows.firstIndex { $0.representedObject as? String == wanted }
            } ?? 0
        if rows.indices.contains(index) { cameraPopup.selectItem(at: index) }
    }

    // MARK: - The locks

    /// Called last by `syncControlsEnabled`: the Camera popup is live only
    /// while idle with Source Camera; with Source Camera the four
    /// screen-only controls and Rate are greyed, their values kept.
    func syncCameraControls() {
        cameraPopup.isEnabled = phase == .idle && cameraSelected
        guard cameraSelected else { return }
        let screenAndRate: [NSControl] = [
            systemAudioSwitch, showClicksSwitch, sizePopup, includeFrameJobCheckbox, ratePopup,
        ]
        for control in screenAndRate { control.isEnabled = false }
    }

    // MARK: - The size note

    /// `1760×1328 at 30 fps — the camera's best format` (CAM-3's pick, the
    /// rate written `%g`); "no camera connected" for nil or a camera with no
    /// format.
    static func cameraSizeNote(_ camera: CameraDeviceFacts?) -> String {
        guard let camera,
            let index = CameraDevices.bestFormat(camera.formats, active: camera.activeFormat)
        else { return "no camera connected" }
        let format = camera.formats[index]
        return "\(format.width)×\(format.height) at "
            + String(format: "%g", format.maxRate) + " fps — the camera's best format"
    }

    /// The size note for the chosen camera, read off the device now.
    var selectedCameraSizeNote: String {
        Self.cameraSizeNote(
            selectedCameraID.flatMap(CameraDevices.device(withID:)).map(CameraDevices.facts(of:)))
    }

    // MARK: - The press and the launch

    /// Record with Source Camera: no camera refuses with a note; otherwise
    /// the Camera grant, then the Microphone grant, then the countdown.
    /// Screen Recording is neither read nor asked.
    func beginCameraIfGranted() {
        guard selectedCameraID != nil else {
            setNote(CameraDevices.noCameraSentence)
            return
        }
        floatAgain()
        guard checkCameraGrant(), checkMicrophoneGrant() else { return }
        setNote("")
        beginCountdown()
    }

    /// The countdown's end for a camera: handed to the recorder, which
    /// adopts the capture the countdown prepared and answers once the
    /// picture can begin, under its own arm ceiling.
    func launchCamera(_ choice: RecordingChoice) {
        launched = true
        recorder.startCamera(
            choice: choice, mayAsk: true,
            onFinish: { [weak self] outcome in self?.recordingEnded(outcome) }
        ) { [weak self] error in
            guard let self else { return }
            if let error {
                self.startFailed(error)
                return
            }
            self.recordingDidStart()
        }
    }
}
