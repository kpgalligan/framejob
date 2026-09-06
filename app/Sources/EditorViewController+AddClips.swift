import AppKit

/// Add Text (T) and the Add Shape menu — the two toolbar buttons and Clip-menu
/// items that create a clip out of nothing rather than out of a file.
///
/// Placement follows the spec §4.1 wording, "at the playhead": the clip goes on
/// the FRONT-MOST track if it fits there, and onto a new track above everything
/// if it does not. Trying the front track first is what keeps a title sequence
/// from growing a track per title; falling back to a new one is what keeps the
/// button from ever beeping at a playhead that happens to sit over a clip.
/// Both are one undo step either way, because `applyEdit` takes the whole op
/// list (`ProjectDocument`).
extension EditorViewController {

    /// T, the toolbar's Add Text button, and Clip > Add Text.
    @objc func addTextClipAtPlayhead(_ sender: Any?) {
        addGeneratedClip(named: "Add Text") { track, at in
            .addTextClip(track: track, at: at)
        }
    }

    /// One item of the Add Shape menu. The sender's tag indexes
    /// `ShapeKind.allCases` — the same tagging `showAddShapeMenu` writes, so
    /// the menu and the enum cannot drift.
    @objc func addShapeClipAtPlayhead(_ sender: Any?) {
        let kinds = ShapeKind.allCases
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        let kind = tag >= 0 && tag < kinds.count ? kinds[tag] : .rectangle
        addGeneratedClip(named: "Add \(kind.displayName)") { track, at in
            .addShapeClip(track: track, at: at, shape: kind)
        }
    }

    /// The shared body: place `make` on the front track, and if the core
    /// refuses it there — the overlap rule (§6) is the only reason it can —
    /// insert a track above everything and place it there instead.
    ///
    /// The refusal is detected by applying the op PURELY first, against the
    /// document's own handle. That costs one throwaway project value and keeps
    /// the fallback out of the undo stack: nothing is registered until the
    /// version that works is the one applied.
    private func addGeneratedClip(named name: String, _ make: (UInt32, Ticks) -> ReelOp) {
        guard let document = document else { return }
        let before = document.project.snapshot
        let at = document.playhead

        var ops: [ReelOp] = []
        // `try?` collapses both failures into one nil: a thrown error and the
        // `None` of a documented refusal. Either way the front track will not
        // take this clip, so both take the new-track path.
        if let front = before.tracks.last?.id,
            (try? document.project.applying(make(front, at))) != nil
        {
            ops = [make(front, at)]
        } else {
            // The id of a newly added track is `next_id` from BEFORE the op —
            // the documented contract of the one JSON op entry point, since
            // `rc_project_apply` returns a project rather than an id.
            // Index 0 is the BACK of the stack (§6), so the count is the front.
            ops = [.addTrack(index: before.tracks.count), make(before.nextId, at)]
        }
        document.applyEdit(name, ops)

        // Select whatever appeared, so the inspector opens on the new clip's
        // own tab and the canvas draws its handles. Comparing id sets rather
        // than trusting an id we predicted keeps this correct even if the core
        // ever allocates differently.
        let existing = Set(before.clips.map { $0.id })
        let added = document.project.snapshot.clips.map { $0.id }.filter { !existing.contains($0) }
        guard !added.isEmpty else { return }
        document.selection = Set(added)
        viewStateDidChange()
    }
}
