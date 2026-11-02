import AppKit

/// Insert ▸ Text Behind Subject (road map creator-jobs CO5, spec §11 CO-53):
/// a title on a new "Behind Subject" track above the cut-out clip at the
/// playhead, already behind the person, in one undo step "Text Behind
/// Subject" — `BehindSubjectPlan`'s ops, the ones `text_behind_subject`
/// (`AgentServer+BehindSubject.swift`) applies too. The new title is
/// selected. The menu runs inside its own event, so `applyEdit`
/// (`EditorViewController+Adjustment.swift`'s pattern). Top-level only: off
/// with a nest open.
extension EditorViewController {

    /// Insert ▸ Text Behind Subject.
    @objc func insertTextBehindSubject(_ sender: Any?) {
        guard let document = document, document.scope == nil else {
            NSSound.beep()
            return
        }
        let before = document.editedProject.snapshot
        guard
            case .success(let plan) = BehindSubjectPlan.plan(
                in: before, at: document.playhead, selection: document.selection, clip: nil)
        else {
            NSSound.beep()
            return
        }
        document.applyEdit(
            BehindSubjectPlan.actionName, BehindSubjectPlan.ops(plan, content: nil))
        guard document.editedProject.snapshot.clips.count > before.clips.count else { return }
        selectClips(addedSince: before, in: document)
        inspector?.clipPicked()
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default
    /// case: on with no nest open and a plan at the playhead; nil for any
    /// other action.
    func validateBehindSubjectAction(_ action: Selector) -> Bool? {
        guard action == #selector(insertTextBehindSubject(_:)) else { return nil }
        guard let document = document, document.scope == nil else { return false }
        if case .success = BehindSubjectPlan.plan(
            in: document.editedProject.snapshot, at: document.playhead,
            selection: document.selection, clip: nil)
        {
            return true
        }
        return false
    }
}
