import AppKit

/// The editor's half of the selected action (spec §11 CI-1): selecting one
/// from the timeline's bands or the Clip tab's lane, leaving the mode (esc,
/// the Clip chip), removing the selected one (⌫), and selecting an action
/// the three add paths just made (⌥⌘K, Zoom to Region, Zoom Back).
///
/// View state only: nothing here registers an undo step except the removal,
/// which is an ordinary `remove_action` through `applyEdit`.
extension EditorViewController {
    /// A band was clicked: park the playhead at the action's end so the
    /// preview shows the state the fields show (CI-2) — one frame short when
    /// the action ends with the clip, whose end tick composes nothing — and
    /// THEN select it. The order matters: the playhead write syncs, and an
    /// end that abuts the next action lands inside THAT one, which the
    /// document's `selectAction` then overrules.
    func selectAction(_ id: UInt32, on clip: UInt32) {
        guard let document = document,
              let snapshot = document.editedProject.snapshot.clip(clip),
              let action = snapshot.actions.first(where: { $0.id == id })
        else {
            NSSound.beep()
            return
        }
        // A band on a clip inside a multi-selection: the timeline's click
        // keeps the selection, so collapse it here or nothing is selected.
        if document.singleSelectedClip?.id != clip { document.selection = [clip] }
        let frame = max(document.editedProject.snapshot.canvas.fps.frameDuration, 1)
        setPlayhead(snapshot.start + min(action.endTime, snapshot.duration - frame))
        document.selectAction(id)
        viewStateDidChange()
    }

    /// The inspector's `onSelectAction`: a lane band, or nil from the Clip
    /// chip. A band in the lane belongs to the single selected clip.
    func selectAction(_ id: UInt32?) {
        guard let document = document else { return }
        guard let id else {
            document.selectAction(nil)
            viewStateDidChange()
            return
        }
        guard let clip = document.singleSelectedClip else {
            NSSound.beep()
            return
        }
        selectAction(id, on: clip.id)
    }

    /// esc. False when nothing was selected, so the key falls through to
    /// whatever else wants it.
    @discardableResult func deselectActionCommand() -> Bool {
        guard let document = document, document.selectedAction != nil else { return false }
        document.selectAction(nil)
        viewStateDidChange()
        return true
    }

    /// ⌫ with an action selected, and the lane's trash button. The document
    /// clamps the id away once the action is gone, and no sync re-selects:
    /// the playhead did not move.
    func removeSelectedActionCommand() {
        guard let document = document, let clip = document.singleSelectedClip,
              let action = document.selectedActionSnapshot
        else {
            NSSound.beep()
            return
        }
        document.applyEdit("Remove Action", .removeAction(clip: clip.id, action: action.id))
    }

    /// After an add: the new action — the one at `start` — when the clip's
    /// count grew. Under a multi-selection the document's own guard stores
    /// nil, which is the rule (CI-1).
    func selectAddedAction(on clip: UInt32, at start: Ticks, countBefore: Int) {
        guard let document = document,
              let snapshot = document.editedProject.snapshot.clip(clip),
              snapshot.actions.count > countBefore,
              let added = snapshot.actions.first(where: { $0.start <= start && start < $0.endTime })
        else { return }
        document.selectAction(added.id)
        viewStateDidChange()
    }

    /// The Clip tab's button that removes the selected action.
    @objc func removeSelectedAction(_ sender: Any?) { removeSelectedActionCommand() }
}
