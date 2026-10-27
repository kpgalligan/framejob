import AVFoundation
import AppKit

/// One popup row as a hot-plug compares it: the id it carries (nil for
/// "None connected" and "Off") and its title.
struct HotPlugRow: Equatable {
    let id: String?
    let title: String
}

/// Hot-plug (camera-recording CR2c, spec §11 CAM-8) —
/// `RecorderPanelController.swift`'s twelfth file, NEW rather than cut, as
/// `+Camera.swift` and `+CameraPreview.swift` were: the device observers,
/// the pending mark, the rebuild it applies, the selection rule and the
/// microphone list.
///
/// **The observers** are `AVCaptureDevice`'s connected and disconnected
/// notifications for any device, on main. `show()` adds the pair (one at
/// most) and adding it marks the lists pending, so a change made while the
/// panel was closed is caught up; `panelWillClose` removes them. A panel
/// ordered out for a recording keeps them.
///
/// **Pending until idle.** A notification marks the lists pending and steps
/// the preview (`syncCameraPreview`), whose FIRST act is
/// `applyPendingDevices`: it applies only while the panel's phase and the
/// recorder are both idle, so a change during a countdown, a recording or a
/// landing waits for the first step that finds both idle — the return to
/// idle draws the phase, which steps. It never steps the preview itself (no
/// recursion) and never persists.
///
/// **The rebuild** compares each popup's rows (id, title) with the devices
/// connected now and rebuilds only a popup that differs, so a menu the
/// person has open is not rebuilt for an unrelated device. The selection is
/// `hotPlugSelection` over the id held BEFORE the rebuild; the camera is
/// selected again — which rebuilds the Format popup, the stored format else
/// Best (CAM-6 (2)) — only when its popup was rebuilt or the id changed.
/// **No key is written**, so a camera that goes and comes back is selected
/// again with its stored format; the next control change writes what the
/// popups then show (CAM-5 (2)).
extension RecorderPanelController {

    /// CAM-8 (3): `stored` when `listed` holds it, else `current` when
    /// listed, else nil (the default). `""` counts as nil for both.
    static func hotPlugSelection(listed: [String], stored: String?, current: String?) -> String? {
        let stored = stored.flatMap { $0.isEmpty ? nil : $0 }
        let current = current.flatMap { $0.isEmpty ? nil : $0 }
        if let stored, listed.contains(stored) { return stored }
        if let current, listed.contains(current) { return current }
        return nil
    }

    /// The microphones connected now: the discovery session
    /// `ScreenRecorder.microphone(withID:)` asks, keeping only those whose
    /// `isConnected` is true (CAM-8 (5)).
    static func connectedMicrophones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices.filter(\.isConnected)
    }

    /// `popup`'s rows as a hot-plug compares them.
    static func hotPlugRows(of popup: NSPopUpButton) -> [HotPlugRow] {
        popup.itemArray.map { HotPlugRow(id: $0.representedObject as? String, title: $0.title) }
    }

    // MARK: - The observers

    /// Idempotent: one pair at most. Adding the pair marks the lists
    /// pending, so the sync that follows catches up a change made while the
    /// panel was closed.
    func observeDevices() {
        guard deviceObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let names = [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification]
        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                self?.devicesDidChange()
            }
            deviceObservers.append(observer)
        }
        devicesPending = true
    }

    /// Removes both observers.
    func stopObservingDevices() {
        deviceObservers.forEach(NotificationCenter.default.removeObserver)
        deviceObservers = []
    }

    /// A device came or went: the lists are pending, and the preview's step
    /// applies them first when the panel and the recorder are idle.
    func devicesDidChange() {
        devicesPending = true
        syncCameraPreview()
    }

    // MARK: - The rebuild

    /// CAM-8 (2)–(4): nothing unless pending and both idle; then each popup
    /// rebuilt only when its rows differ from the devices connected now, the
    /// selection `hotPlugSelection`'s, and the size note refreshed. Writes
    /// no key and never steps the preview.
    func applyPendingDevices() {
        guard devicesPending else { return }
        guard phase == .idle, recorder.state == .idle else { return }
        devicesPending = false
        let defaults = UserDefaults.standard

        let cameras = CameraDevices.connected()
        let cameraRows =
            cameras.isEmpty
            ? [HotPlugRow(id: nil, title: Self.noCameraTitle)]
            : cameras.map {
                HotPlugRow(id: $0.uniqueID, title: CameraDevices.popupTitle(CameraDevices.facts(of: $0)))
            }
        let currentCamera = selectedCameraID
        let cameraRebuilt = Self.hotPlugRows(of: cameraPopup) != cameraRows
        if cameraRebuilt { rebuildCameras() }
        let camera = Self.hotPlugSelection(
            listed: cameras.map(\.uniqueID), stored: defaults.string(forKey: Self.cameraKey),
            current: currentCamera)
        if cameraRebuilt || camera != selectedCameraID { selectCamera(camera) }

        let microphones = Self.connectedMicrophones()
        let microphoneRows =
            [HotPlugRow(id: nil, title: "Off")]
            + microphones.map { HotPlugRow(id: $0.uniqueID, title: $0.localizedName) }
        let currentMicrophone = microphonePopup.selectedItem?.representedObject as? String
        if Self.hotPlugRows(of: microphonePopup) != microphoneRows { rebuildMicrophones() }
        selectMicrophone(
            Self.hotPlugSelection(
                listed: microphones.map(\.uniqueID),
                stored: defaults.string(forKey: Self.microphoneKey), current: currentMicrophone))
        refreshSizeNote()
    }
}
