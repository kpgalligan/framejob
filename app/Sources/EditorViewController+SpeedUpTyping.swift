import AppKit

/// Clip ▸ Speed Up Typing… (road map "creator-jobs" CU9b, spec §11 CU-93): the selected clips of
/// the container being edited — the timeline, or the open nest — put up in
/// `SpeedUpTypingSheetController`, whose Apply commits the speech ops and `plan_typing`'s
/// `retime_range` ops through `SpeedAudioDrop.commit` as one undo step. `speed_up_typing`
/// mirrors it (`AgentServer+SpeedUpTyping.swift`). On-device, so no `ModelKeys` row (CJ-3).
extension EditorViewController {

    /// The selected clips the menu offers Speed Up Typing on, in id order; empty when any of
    /// them is not a media clip whose media has a cursor file (`AutoZoom.canOffer`).
    private func speedUpTypingClips(_ document: ProjectDocument) -> [UInt32] {
        let snapshot = document.editedProject.snapshot
        let clips = document.selection.sorted().compactMap { snapshot.clip($0) }
        guard clips.count == document.selection.count,
            AutoZoom.canOffer(clips, in: snapshot)
        else { return [] }
        return clips.map(\.id)
    }

    @objc func showSpeedUpTypingSheet(_ sender: Any?) {
        guard let document, view.window?.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        let clips = speedUpTypingClips(document)
        guard !clips.isEmpty else {
            NSSound.beep()
            return
        }
        presentAsSheet(SpeedUpTypingSheetController(document: document, clips: clips))
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case; nil for any
    /// other action. On with at least one selected clip, each a media clip whose media has a
    /// cursor file, and no sheet on the window; allowed inside a nest.
    func validateSpeedUpTypingAction(_ action: Selector) -> Bool? {
        guard action == #selector(showSpeedUpTypingSheet(_:)) else { return nil }
        guard let document, view.window?.attachedSheet == nil else { return false }
        return !speedUpTypingClips(document).isEmpty
    }
}
