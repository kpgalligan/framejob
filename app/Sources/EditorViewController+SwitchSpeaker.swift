import AppKit

/// Clip ▸ Switch by Speaker… (road map "creator-jobs" SW2b, spec §11 SW-23 (g), SW-26 (a)): the
/// selected cameras and microphones of the container being edited — the timeline, or the open
/// nest — put up in `SwitchSpeakerSheetController`, whose Switch writes a Program track as one
/// undo step "Switch by Speaker". `switch_by_speaker` mirrors it (`AgentServer+Switch.swift`).
/// With one microphone and faces still to find, the Analyzing sheet comes first (SW8).
extension EditorViewController {

    /// SW-23 (g) over the document's selection.
    private func switchSpeakerOffered(_ document: ProjectDocument) -> Bool {
        let snapshot = document.editedProject.snapshot
        let clips = document.selection.sorted().compactMap { snapshot.clip($0) }
        return SpeakerSwitch.canOffer(clips, in: snapshot)
    }

    /// In the faces mode with faces missing (SW8, spec §11 SW-85), CJ-28's Analyzing sheet first,
    /// `EditorViewController+ShotSplit.swift`'s shape, and the switch sheet once they land.
    @objc func showSwitchBySpeakerSheet(_ sender: Any?) {
        guard let document, view.window?.attachedSheet == nil, switchSpeakerOffered(document)
        else {
            NSSound.beep()
            return
        }
        var wants: [SpeakerSwitch.FacesWant] = []
        if let input = SpeakerSwitch.read(
            from: document, clips: nil, pairing: nil, range: nil, settings: SpeakerSwitch.Settings())
        {
            do {
                wants = try SpeakerSwitch.facesWanted(input, in: document)
            } catch {
                refuseSwitchSpeaker(error.localizedDescription, document: document)
                return
            }
        }
        guard !wants.isEmpty else {
            presentAsSheet(SwitchSpeakerSheetController(document: document))
            return
        }
        let asked = document.project
        let scope = document.scope
        let rows = wants.map { AnalyzingSheetController.Row(name: $0.media.name, request: $0.request) }
        presentAsSheet(
            AnalyzingSheetController(
                document: document, command: SpeakerSwitch.actionName, rows: rows
            ) { [weak self, weak document] outcome in
                guard let self, let document else { return }
                guard document.project === asked, document.scope == scope else {
                    self.refuseSwitchSpeaker(
                        "the project changed while \(SpeakerSwitch.actionName) was analyzing, so "
                            + "nothing was switched. Choose \(SpeakerSwitch.actionName) again.",
                        document: document)
                    return
                }
                switch outcome {
                case .failed(let name, let why):
                    self.refuseSwitchSpeaker(
                        "The faces analysis of “\(name)” failed: \(why).", document: document)
                case .landed:
                    self.presentAsSheet(SwitchSpeakerSheetController(document: document))
                }
            })
    }

    /// A beep and the sentence at the inspector's foot.
    private func refuseSwitchSpeaker(_ reason: String, document: ProjectDocument) {
        NSSound.beep()
        NotificationCenter.default.post(
            name: .projectDocumentDidRefuse, object: document,
            userInfo: ["refusal": ReelRefusal(op: "switch_by_speaker", reason: reason)])
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
