import AppKit

/// Clip ▸ Auto Zoom… (road map "creator-jobs" CU7, spec §11 CU-76): the selected clips of the
/// container being edited — the timeline, or the open nest — put up in
/// `AutoZoomSheetController`, whose Zoom applies `plan_zooms`' ops as one undo step. `auto_zoom`
/// mirrors it (`AgentServer+AutoZoom.swift`).
extension EditorViewController {

    /// The selected clips the menu offers Auto Zoom on, in id order; empty when any of them
    /// is not a media clip whose media has a cursor file.
    private func autoZoomClips(_ document: ProjectDocument) -> [UInt32] {
        let snapshot = document.editedProject.snapshot
        let clips = document.selection.sorted().compactMap { snapshot.clip($0) }
        guard clips.count == document.selection.count,
            AutoZoom.canOffer(clips, in: snapshot)
        else { return [] }
        return clips.map(\.id)
    }

    @objc func showAutoZoomSheet(_ sender: Any?) {
        guard let document, view.window?.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        let clips = autoZoomClips(document)
        guard !clips.isEmpty else {
            NSSound.beep()
            return
        }
        presentAsSheet(AutoZoomSheetController(document: document, clips: clips))
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case; nil for any
    /// other action. On with at least one selected clip, each a media clip whose media has a
    /// cursor file, and no sheet on the window; allowed inside a nest.
    func validateAutoZoomAction(_ action: Selector) -> Bool? {
        guard action == #selector(showAutoZoomSheet(_:)) else { return nil }
        guard let document, view.window?.attachedSheet == nil else { return false }
        return !autoZoomClips(document).isEmpty
    }
}
