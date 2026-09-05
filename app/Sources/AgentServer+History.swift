import AppKit

/// The agent's mirrors of Edit ▸ Undo (⌘Z) and Edit ▸ Redo (⇧⌘Z).
///
/// Every other agent tool is an edit, and `ProjectDocument.performGroupedEdit`
/// already turns each one into exactly one undo step (app/CLAUDE.md). Without
/// these two the agent could make those steps and never walk them, so the one
/// property the whole undo design rests on — one edit is one step, and undoing
/// it restores the frame — could not be checked by driving the built app,
/// which spec §10 step 7 asks for.
extension AgentServer {

    /// `undo` — Edit ▸ Undo. One step, and the step's action name comes back
    /// so a caller can see what it walked past.
    func undoEdit(_ a: [String: Any]) throws -> String {
        try walkHistory(a, redo: false)
    }

    /// `redo` — Edit ▸ Redo.
    func redoEdit(_ a: [String: Any]) throws -> String {
        try walkHistory(a, redo: true)
    }

    /// **Pitfall** (app/CLAUDE.md, and the same one `performGroupedEdit`
    /// documents): a tool call is not an AppKit event, so with `groupsByEvent`
    /// on, `NSUndoManager` opens an implicit per-event group that nothing ever
    /// closes. `undo()` closes the top-level group before undoing, which
    /// against that phantom group leaves an end with no begin and hangs the
    /// next save inside its file coordinator. Turning event grouping off for
    /// the duration — never "flushing" the level — is the same discipline
    /// every off-event path here follows.
    private func walkHistory(_ a: [String: Any], redo: Bool) throws -> String {
        let document = try target(a)
        guard let manager = document.undoManager else {
            throw ToolError(message: "This project has no undo history.")
        }
        guard redo ? manager.canRedo : manager.canUndo else {
            throw ToolError(
                message: redo
                    ? "There is nothing to redo. Only an undo makes a redo step."
                    : "There is nothing to undo. Only an edit makes an undo step; "
                        + "set_playhead and set_range are view state and make none.")
        }
        let name = (redo ? manager.redoActionName : manager.undoActionName)
        let groupsByEvent = manager.groupsByEvent
        if groupsByEvent { manager.groupsByEvent = false }
        if redo { manager.redo() } else { manager.undo() }
        if groupsByEvent { manager.groupsByEvent = true }
        return try jsonResult([
            "ok": true,
            redo ? "redone" : "undone": name.isEmpty ? "Edit" : name,
            "can_undo": manager.canUndo,
            "can_redo": manager.canRedo,
            "project": summary(document),
        ])
    }
}
