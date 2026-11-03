import AppKit

/// Clip ▸ Camera Layout ▸ (road map "creator-jobs" CO6, spec §11 CO-66): the
/// chosen row's `switch_layout` at the playhead in the container being
/// edited, its roles by `CameraLayoutRoles`, through `CameraLayoutCommand.run`
/// (CO7, CO-70, CO-72) — the camera's focus from its cached person masks,
/// then one undo step "Camera Layout" through `performGroupedEdit`, whose
/// refusal reaches the inspector's refusal strip, or, for a switch refused
/// because a clip zooms, the nest offer's sheet. `switch_layout`'s tool
/// mirrors it (`AgentServer+Layout.swift`).
extension EditorViewController {

    /// The camera and screen the menu would lay out, or nil.
    private var cameraLayoutRoles: (camera: UInt32, screen: UInt32?)? {
        guard let document else { return nil }
        return CameraLayoutRoles.roles(
            selected: selectedClips, playhead: document.playhead,
            in: document.editedProject.snapshot)
    }

    @objc func switchCameraLayout(_ sender: Any?) {
        guard let document, view.window?.attachedSheet == nil,
            let tag = (sender as? NSMenuItem)?.tag,
            CameraLayoutChoice.menuRows.indices.contains(tag),
            let roles = cameraLayoutRoles
        else {
            NSSound.beep()
            return
        }
        CameraLayoutCommand.run(
            CameraLayoutChoice.menuRows[tag], camera: roles.camera, screen: roles.screen,
            duration: nil, document: document, window: view.window)
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case;
    /// nil for any other action. On when the roles yield a camera containing
    /// the playhead and no sheet is on the window; allowed inside a nest.
    func validateCameraLayoutAction(_ action: Selector) -> Bool? {
        guard action == #selector(switchCameraLayout(_:)) else { return nil }
        return cameraLayoutRoles != nil && view.window?.attachedSheet == nil
    }
}
