import AppKit

/// Clip ▸ Switch Angle ▸ (road map "creator-jobs" SW1, spec §11 SW-13…SW-15):
/// the one selected clip re-picked from the chosen covering track by
/// `SwitchAngle.plan`, as one undo step through `applyEdit`, then the new
/// pieces selected. A plan's refusal beeps and reaches the inspector's
/// refusal strip. `switch_angle`'s tool mirrors it (`AgentServer+Switch.swift`).
/// The rows are `SwitchAngleMenuFiller`'s (`AppDelegate+ClipMenus.swift`).
extension EditorViewController {

    /// The one selected clip when the menu may re-pick it: exactly one clip
    /// selected, its track unlocked, no link (SW-15 (b)).
    var switchAngleClip: ClipSnapshot? {
        guard let document, selectedClips.count == 1, let clip = selectedClips.first,
            clip.linked == nil,
            document.editedProject.snapshot.track(clip.track)?.locked == false
        else { return nil }
        return clip
    }

    @objc func switchAngle(_ sender: Any?) {
        guard let document, view.window?.attachedSheet == nil,
            let track = ((sender as? NSMenuItem)?.representedObject as? NSNumber)?.uint32Value,
            let clip = switchAngleClip
        else {
            NSSound.beep()
            return
        }
        let answer: SwitchAngle.Answer
        do {
            answer = try SwitchAngle.plan(
                clip: clip.id, angle: track, in: document.editedProject)
        } catch {
            NSSound.beep()
            return
        }
        switch answer {
        case .plan(let plan):
            document.applyEdit(plan.actionName, plan.ops)
            document.selection = Set(plan.pieces)
        case .refused(let reason):
            NSSound.beep()
            NotificationCenter.default.post(
                name: .projectDocumentDidRefuse, object: document,
                userInfo: ["refusal": ReelRefusal(op: "switch_angle", reason: reason)])
        }
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case;
    /// nil for any other action. On when `switchAngleClip` exists, the item's
    /// track is still one of its angles and no sheet is up; allowed inside a
    /// nest.
    func validateSwitchAngleAction(
        _ action: Selector, item: any NSValidatedUserInterfaceItem
    ) -> Bool? {
        guard action == #selector(switchAngle(_:)) else { return nil }
        guard let document, view.window?.attachedSheet == nil, let clip = switchAngleClip,
            let track = ((item as? NSMenuItem)?.representedObject as? NSNumber)?.uint32Value
        else { return false }
        return SwitchAngle.angles(for: clip, in: document.editedProject.snapshot)
            .contains { $0.track == track }
    }
}
