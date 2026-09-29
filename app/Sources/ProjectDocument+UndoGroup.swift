import AppKit

/// An undo group opened LAZILY, at the first undo registration inside a
/// body, for `perform_menu_item` (`UIMenu.perform`, #167).
///
/// The menu tool runs an item outside an AppKit event, so an edit it makes
/// needs an explicit group (app/CLAUDE.md "Undo and dirty tracking"). An
/// EAGER group — begun before the item runs — is a step on the stack even
/// when the item registers nothing, and closing it clears redo: View ▸ Zoom
/// In after an undo made the next redo impossible. Here the group opens only
/// when `registerUndo(restoring:actionName:)`, still the ONE registrar,
/// calls `openPendingUndoGroup()` first; an item that edits nothing leaves
/// undo and redo as they were (`v2_menu.py` U2).
///
/// The discipline is `performGroupedEdit`'s: event grouping off for the
/// group's life, close exactly what was opened, restore `groupsByEvent`,
/// never a flush.
struct PendingUndoGroup {
    let level: Int             // manager.groupingLevel when the body began
    var opened = false         // the first registration opened the group
    var groupsByEvent = false  // manager.groupsByEvent as the opening found it
}

extension ProjectDocument {

    /// Runs `body` with a group pending: its first undo registration opens
    /// the group, and it is closed here. With no undo manager, or with a
    /// group already pending, `body` runs as it would anyway.
    func inUndoGroupIfRegistered<T>(_ body: () -> T) -> T {
        guard let manager = undoManager, pendingUndoGroup == nil else { return body() }
        pendingUndoGroup = PendingUndoGroup(level: manager.groupingLevel)
        let value = body()
        if let pending = pendingUndoGroup, pending.opened {
            // Close exactly what the opening began — never a group it did not.
            while manager.groupingLevel > pending.level { manager.endUndoGrouping() }
            if pending.groupsByEvent { manager.groupsByEvent = true }
        }
        pendingUndoGroup = nil
        return value
    }

    /// The hook `registerUndo(restoring:actionName:)` calls first. It opens
    /// the pending group once, at the level the body began at — a
    /// registration inside `commitEdit(grouped: true)`'s own group is that
    /// group's step and opens nothing — and never while undoing or redoing,
    /// whose inverse registrations the manager groups itself.
    func openPendingUndoGroup() {
        guard let manager = undoManager, var pending = pendingUndoGroup, !pending.opened,
            manager.groupingLevel == pending.level,
            !manager.isUndoing, !manager.isRedoing
        else { return }
        pending.groupsByEvent = manager.groupsByEvent
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        pending.opened = true
        pendingUndoGroup = pending
    }
}
