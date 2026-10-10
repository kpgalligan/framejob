import AppKit

/// Insert ▸ Adjustment Clip (spec §11 GR-6): one adjustment clip over the
/// In/Out range, else the selection's span, else the whole timeline, on the
/// front track when it takes it, else on a new front track named
/// "Adjustment" — in one undo step, "Add Adjustment Clip", the name
/// `add_adjustment_clip` (its MCP mirror, `AgentServer+Grading.swift`) uses.
/// The new clip is selected and the inspector shows Clip, whose first
/// sub-tab for an adjustment clip is Color.
///
/// The menu runs inside its own event, so `applyEdit` (app/CLAUDE.md's undo
/// pitfall). A matte front track is never used: an adjustment clip there has
/// no effect. Adjustment clips are refused in a nest, so the item is off
/// while one is open.
extension EditorViewController {

    /// Insert ▸ Adjustment Clip.
    @objc func insertAdjustmentClip(_ sender: Any?) {
        guard let document = document, document.scope == nil else {
            NSSound.beep()
            return
        }
        let before = document.editedProject.snapshot
        guard
            let span = Self.adjustmentSpan(
                range: document.inOutRange, selection: document.selection, in: before)
        else {
            NSSound.beep()
            return
        }
        document.applyEdit("Add Adjustment Clip", adjustmentOps(start: span.start, end: span.end))
        // A refused edit (the track cap, say) adds nothing and leaves the inspector alone.
        guard document.editedProject.snapshot.clips.count > before.clips.count else { return }
        selectClips(addedSince: before, in: document)
        inspector?.clipPicked()
    }

    /// The span the clip covers: the In/Out range when it is one
    /// (`end > start`), else the first start to the last end of the selected
    /// clips present in `snapshot`, else the whole timeline; nil when that
    /// is empty too.
    static func adjustmentSpan(
        range: (start: Ticks, end: Ticks)?, selection: Set<UInt32>,
        in snapshot: ProjectSnapshot
    ) -> (start: Ticks, end: Ticks)? {
        if let range, range.end > range.start { return range }
        let selected = snapshot.clips.filter { selection.contains($0.id) }
        if let start = selected.map(\.start).min(), let end = selected.map(\.end).max(),
            end > start
        {
            return (start, end)
        }
        let duration = snapshot.duration
        return duration > 0 ? (0, duration) : nil
    }

    /// The ops that place it: on the front track when that track is not a
    /// matte and a PURE trial of the op answers a project (the overlap rule
    /// is what refuses it), else a new front track named "Adjustment" and
    /// the clip on it. A new track's id is `nextId` from before the op
    /// (`addGeneratedClip`'s contract).
    func adjustmentOps(start: Ticks, end: Ticks) -> [ReelOp] {
        guard let document = document else { return [] }
        let snapshot = document.editedProject.snapshot
        let duration = end - start
        if let front = snapshot.tracks.last, front.matte == .none {
            let op = ReelOp.addAdjustmentClip(track: front.id, at: start, duration: duration)
            if (try? document.editedProject.applying(op)).project != nil { return [op] }
        }
        return [
            .addTrack(index: snapshot.tracks.count, name: "Adjustment"),
            .addAdjustmentClip(track: snapshot.nextId, at: start, duration: duration),
        ]
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default
    /// case: on with no nest open and a span to cover; nil for any other
    /// action.
    func validateAdjustmentAction(_ action: Selector) -> Bool? {
        guard action == #selector(insertAdjustmentClip(_:)) else { return nil }
        guard let document = document, document.scope == nil else { return false }
        return Self.adjustmentSpan(
            range: document.inOutRange, selection: document.selection,
            in: document.editedProject.snapshot) != nil
    }
}
