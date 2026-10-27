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
/// A Continuity Camera's row reads "<name> (Continuity Camera)" (CAM-6 (5)).
///
/// **The Format popup** (CR2a, spec §11 CAM-6) lists "Best (<CAM-3's pick>)"
/// first, then `CameraDevices.formatRows` titled "W×H at R fps", each row
/// carrying its spelling (`1920x1080@30`). It is rebuilt on EVERY exit of
/// `selectCamera` — init, `show()` and a change of camera — selecting the
/// stored `FrameJobRecordingCameraFormat` when the camera lists it, else
/// Best, and follows the Camera popup's live rule.
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
    static let bestFormatTitle = "Best"

    var cameraSelected: Bool { sourcePopup.selectedItem?.tag == Self.cameraTag }

    /// The Camera popup's chosen `uniqueID`; nil for "None connected".
    var selectedCameraID: String? { cameraPopup.selectedItem?.representedObject as? String }

    /// The Format popup's chosen spelling; nil for Best.
    var selectedCameraFormat: String? { formatPopup.selectedItem?.representedObject as? String }

    // MARK: - The popup

    /// Every connected camera by name, carrying its `uniqueID`, or the one
    /// row "None connected"; the selection kept when it is still listed,
    /// else the default (`selectCamera`).
    func rebuildCameras() {
        let current = selectedCameraID
        cameraPopup.removeAllItems()
        let cameras = CameraDevices.connected()
        for camera in cameras {
            let item = NSMenuItem(
                title: CameraDevices.popupTitle(CameraDevices.facts(of: camera)), action: nil,
                keyEquivalent: "")
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
    /// the first built-in, else the first), else the first row. The Format
    /// popup is rebuilt on every exit, the early one included (CAM-6 (2)).
    func selectCamera(_ id: String?) {
        defer { rebuildCameraFormats() }
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

    // MARK: - The Format popup (CAM-6)

    /// "Best (<the best format>)" — or "Best" when `camera` has none — then
    /// one row per `CameraDevices.formatRows` row, carrying its spelling;
    /// `stored` selected when a row carries it, else Best.
    func fillCameraFormats(_ camera: CameraDeviceFacts?, stored: String?) {
        formatPopup.removeAllItems()
        let formats = camera?.formats ?? []
        let best = camera.flatMap { CameraDevices.bestFormat($0.formats, active: $0.activeFormat) }
        let bestTitle =
            best.map { "\(Self.bestFormatTitle) (\(CameraDevices.formatTitle(formats[$0])))" }
            ?? Self.bestFormatTitle
        formatPopup.menu?.addItem(NSMenuItem(title: bestTitle, action: nil, keyEquivalent: ""))
        for index in CameraDevices.formatRows(formats) {
            let item = NSMenuItem(
                title: CameraDevices.formatTitle(formats[index]), action: nil, keyEquivalent: "")
            item.representedObject = CameraDevices.spelled(formats[index])
            formatPopup.menu?.addItem(item)
        }
        let index =
            stored.flatMap { stored in
                formatPopup.itemArray.firstIndex { $0.representedObject as? String == stored }
            } ?? 0
        formatPopup.selectItem(at: index)
    }

    /// `fillCameraFormats` for the Camera popup's camera, read off the
    /// device now, and the stored format (`""` is Best).
    func rebuildCameraFormats() {
        let stored = UserDefaults.standard.string(forKey: Self.cameraFormatKey) ?? ""
        fillCameraFormats(
            selectedCameraID.flatMap(CameraDevices.device(withID:)).map(CameraDevices.facts(of:)),
            stored: stored.isEmpty ? nil : stored)
    }

    // MARK: - The locks

    /// Called last by `syncControlsEnabled`: the Camera and Format popups
    /// are live only while idle with Source Camera; with Source Camera the
    /// four screen-only controls and Rate are greyed, their values kept.
    func syncCameraControls() {
        cameraPopup.isEnabled = phase == .idle && cameraSelected
        formatPopup.isEnabled = phase == .idle && cameraSelected
        guard cameraSelected else { return }
        let screenAndRate: [NSControl] = [
            systemAudioSwitch, showClicksSwitch, sizePopup, includeFrameJobCheckbox, ratePopup,
        ]
        for control in screenAndRate { control.isEnabled = false }
    }

    // MARK: - The size note

    /// `1760×1328 at 30 fps — the camera's best format` (CAM-3's pick, the
    /// rate written `%g`) for Best, `1920×1080 at 30 fps — the chosen
    /// format` for a row the camera lists (CAM-6 (4)); "no camera connected"
    /// for nil or a camera with no format.
    static func cameraSizeNote(_ camera: CameraDeviceFacts?, format: String? = nil) -> String {
        guard let camera else { return "no camera connected" }
        if let format,
            let chosen = camera.formats.first(where: { CameraDevices.spelled($0) == format })
        {
            return CameraDevices.formatTitle(chosen) + " — the chosen format"
        }
        guard let index = CameraDevices.bestFormat(camera.formats, active: camera.activeFormat)
        else { return "no camera connected" }
        return CameraDevices.formatTitle(camera.formats[index]) + " — the camera's best format"
    }

    /// The size note for the chosen camera and format, read off the device
    /// now.
    var selectedCameraSizeNote: String {
        Self.cameraSizeNote(
            selectedCameraID.flatMap(CameraDevices.device(withID:)).map(CameraDevices.facts(of:)),
            format: selectedCameraFormat)
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
