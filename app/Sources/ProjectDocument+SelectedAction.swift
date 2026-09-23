import AppKit

/// The selected action — the sixth piece of view state (spec §11 CI-1): nil,
/// or ONE action of the SINGLE selected clip. Like the other five it is not
/// undoable, not persisted and has no MCP mirror; agents address actions by
/// id through the action ops, which is the whole capability.
///
/// Three writers and no others: `selectAction(_:)` below (the lane, the
/// timeline's bands, esc, the Clip chip, an add), `syncSelectedAction()`
/// (the playhead ENTERING a span), and `clampViewState`, which drops an id
/// the edited project no longer has on the selected clip.
///
/// **Entry, not presence.** `lastInsideAction` is the span the playhead was
/// last inside, so a sync selects only on a CHANGE of span: after esc the
/// playhead can sit inside one without re-selecting it until it leaves and
/// comes back, and leaving a span keeps the selection. An edit never enters
/// one — `clampViewState` re-reads `lastInsideAction` before its own
/// playhead write, so a redo, a live drag or an add that puts a span under a
/// stationary playhead selects nothing.
///
/// The stored pair lives in `ProjectDocument.swift` because an extension
/// cannot add stored properties (`+DisplayStem`'s precedent for the split);
/// the queries and the entry rule live here, where the size rule wants them.
extension ProjectDocument {
    /// The edited project's clip when exactly one clip is selected.
    var singleSelectedClip: ClipSnapshot? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return editedProject.snapshot.clip(id)
    }

    /// The single selected clip's action with `start ≤ clipTime(playhead) <
    /// endTime`. Actions on one clip never overlap, so there is at most one.
    var actionUnderPlayhead: ActionSnapshot? {
        guard let clip = singleSelectedClip else { return nil }
        let t = clip.clipTime(playhead)
        return clip.actions.first { $0.start <= t && t < $0.endTime }
    }

    /// The selected action's snapshot, read fresh from the edited project —
    /// nil when nothing is selected or the id is no longer the clip's.
    var selectedActionSnapshot: ActionSnapshot? {
        guard let id = selectedAction else { return nil }
        return singleSelectedClip?.actions.first { $0.id == id }
    }

    /// The entry rule. Called from `playhead`'s and `selection`'s `didSet`.
    func syncSelectedAction() {
        let under = actionUnderPlayhead?.id
        guard under != lastInsideAction else { return }
        lastInsideAction = under
        if let under { selectedAction = under }
    }

    /// The one deliberate writer. An id that is not the single selected
    /// clip's is stored as nil, so a multi-selection never holds one; the
    /// span under the playhead is recorded as already entered, so the next
    /// sync does not overrule the choice.
    func selectAction(_ id: UInt32?) {
        let owned = singleSelectedClip?.actions.contains { $0.id == id } == true
        selectedAction = owned ? id : nil
        lastInsideAction = actionUnderPlayhead?.id
    }
}
