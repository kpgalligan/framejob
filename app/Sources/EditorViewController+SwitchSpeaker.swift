import AppKit

/// Clip ▸ Switch by Speaker… (road map "creator-jobs" SW2b, spec §11 SW-23 (g), SW-26 (a)): the
/// selected cameras and microphones of the container being edited — the timeline, or the open
/// nest — put up in `SwitchSpeakerSheetController`, whose Switch writes a Program track as one
/// undo step "Switch by Speaker". `switch_by_speaker` mirrors it (`AgentServer+Switch.swift`).
extension EditorViewController {

    /// SW-23 (g) over the document's selection.
    private func switchSpeakerOffered(_ document: ProjectDocument) -> Bool {
        let snapshot = document.editedProject.snapshot
        let clips = document.selection.sorted().compactMap { snapshot.clip($0) }
        return SpeakerSwitch.canOffer(clips, in: snapshot)
    }

    @objc func showSwitchBySpeakerSheet(_ sender: Any?) {
        guard let document, view.window?.attachedSheet == nil, switchSpeakerOffered(document)
        else {
            NSSound.beep()
            return
        }
        presentAsSheet(SwitchSpeakerSheetController(document: document))
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case; nil for any
    /// other action. On when the selection holds two or more angles and a clip with sound
    /// (SW-23 (g)) and no sheet is on the window; allowed inside a nest.
    func validateSwitchSpeakerAction(_ action: Selector) -> Bool? {
        guard action == #selector(showSwitchBySpeakerSheet(_:)) else { return nil }
        guard let document, view.window?.attachedSheet == nil else { return false }
        return switchSpeakerOffered(document)
    }
}
