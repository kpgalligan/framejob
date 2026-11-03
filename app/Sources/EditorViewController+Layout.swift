import AppKit

/// Clip ▸ Camera Layout ▸ (road map "creator-jobs" CO6, spec §11 CO-66): the
/// chosen row's `switch_layout` at the playhead in the container being
/// edited, its roles by `CameraLayoutRoles`, as one undo step "Camera
/// Layout" through `applyEdit`, whose refusal reaches the inspector's
/// refusal strip. The nest is offered, not made: a refusal's sentence says
/// how (CO7's sheet makes the offer). `switch_layout`'s tool mirrors it
/// (`AgentServer+Layout.swift`).
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
        let op = CameraLayoutChoice.menuRows[tag].op(
            camera: roles.camera, screen: roles.screen, at: document.playhead)
        document.applyEdit("Camera Layout", [op])
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case;
    /// nil for any other action. On when the roles yield a camera containing
    /// the playhead and no sheet is on the window; allowed inside a nest.
    func validateCameraLayoutAction(_ action: Selector) -> Bool? {
        guard action == #selector(switchCameraLayout(_:)) else { return nil }
        return cameraLayoutRoles != nil && view.window?.attachedSheet == nil
    }
}
