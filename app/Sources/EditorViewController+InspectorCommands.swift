import AppKit

/// The two commands the inspector made real — Add Action at the playhead
/// (⌥⌘K) and Clip ▸ Transition ▸ — with the no-footage sheet and its Shift
/// Clips Left, and `transitionPlacement`, which their validator arm in
/// `EditorViewController+Inspector.swift` also reads. A pure move out of that
/// file (road map creator-jobs TX2a's toll).
extension EditorViewController {
    // MARK: - Commands the inspector made real

    /// ⌥⌘K and the action lane's `+`: an action at the playhead on the
    /// selected clip, then selected (spec §11 CI-1). `add_action` takes CLIP
    /// time (§6), and refuses an overlap or a span past the clip end — so the
    /// only check here is that the playhead is actually on a selected clip.
    func addActionAtPlayheadCommand() {
        guard let document = document,
              let clip = selectedClips.first(where: { $0.contains(document.playhead) })
        else {
            NSSound.beep()
            return
        }
        let at = clip.clipTime(document.playhead)
        document.applyEdit("Add Action", .addAction(clip: clip.id, at: at))
        selectAddedAction(on: clip.id, at: at, countBefore: clip.actions.count)
    }

    /// Clip ▸ Transition ▸ — the sender's tag indexes `TransitionKind.allCases`
    /// and −1 is None, the same table the Clip tab's Transition section's popup
    /// offers.
    ///
    /// A kind is sent one of two ways per clip, and the choice is the
    /// clip's own placement: a clip that already OVERLAPS its predecessor
    /// gets `set_transition`, which names the kind and keeps the style; a
    /// clip at a HARD CUT gets `add_transition`, which makes the overlap out
    /// of the two clips' handles first. Anything else — a gap, or the first
    /// clip on a track — is SKIPPED rather than sent, because
    /// `ReelProject.applying` throws on the first `Err` and one clip at a
    /// gap would abort the whole selection.
    ///
    /// **None (tag −1) never reaches `add_transition`.** It is a clear, it
    /// goes to every selected clip whatever its placement, and an absent
    /// kind on `add_transition` would ADD a dissolve rather than remove one.
    func setTransitionKindCommand(_ sender: Any?) {
        guard let document = document, let tag = (sender as? NSMenuItem)?.tag,
              !selectedClips.isEmpty
        else {
            NSSound.beep()
            return
        }
        let kinds = TransitionKind.allCases
        guard tag < 0 || kinds.indices.contains(tag) else {
            NSSound.beep()
            return
        }
        guard tag >= 0 else {
            document.applyEdit(
                "Set Transition", selectedClips.map { .setTransition(clip: $0.id, kind: nil) })
            return
        }
        let kind = kinds[tag]
        let snapshot = document.editedProject.snapshot
        let half = ReelTime.snapToFrame(
            ReelTime.ticks(seconds: 0.5), fps: snapshot.canvas.fps)
        var ops: [ReelOp] = []
        var requested: [UInt32] = []
        for clip in selectedClips {
            switch transitionPlacement(of: clip, in: snapshot) {
            case .overlap:
                ops.append(.setTransition(clip: clip.id, kind: kind))
            case .hardCut:
                ops.append(
                    .addTransition(clip: clip.id, kind: kind, duration: half, align: .center))
                requested.append(clip.id)
            case .neither:
                continue
            }
        }
        guard !ops.isEmpty else {
            NSSound.beep()
            return
        }
        // Every `add_transition` in the batch can come back REFUSED —
        // neither side of the cut had a frame to spare, which is EVERY cut
        // between two clips that each use their whole file, and since
        // deepening D2·3 the core says so in its own sentence. `.project` is
        // nil for that arm as it is for an identity, so the trial below
        // reads the same either way. That has to be
        // SAID (road map 5 §3g): a bare beep is all `applyEdit` gives a
        // batch that changed nothing, and a person placing whole recordings
        // back to back has no way to guess that a transition is built from
        // footage beyond the cut. So TRY the batch first, on the container
        // the edit lands in (`inspectorProbe`'s trial), and ask the clips
        // themselves — a landed `add_transition` leaves its clip overlapping
        // its predecessor. A throw is left to `applyEdit`, which presents
        // the core's own sentence.
        let trial: ProjectSnapshot?
        do {
            trial = try document.editedProject.applying(ops).project?.snapshot
        } catch {
            document.applyEdit("Set Transition", ops)
            return
        }
        let added = requested.contains { id in
            guard let after = trial, let clip = after.clips.first(where: { $0.id == id })
            else { return false }
            return transitionPlacement(of: clip, in: after) == .overlap
        }
        // Applied whenever something changes — a MIXED batch keeps the
        // `set_transition`s that landed — and whenever there was no add to
        // explain, so an all-`set_transition` identity still beeps.
        if trial != nil || requested.isEmpty {
            document.applyEdit("Set Transition", ops)
        }
        if !requested.isEmpty && !added {
            presentNoFootageForTransition(clips: requested, kind: kind, duration: half)
        }
    }

    /// Why Clip ▸ Transition ▸ <kind> did nothing at a hard cut, as a sheet
    /// rather than a beep — and the way to get the transition anyway.
    ///
    /// **Shift Clips Left** re-sends the same cuts as `add_transition` with
    /// `ripple` (spec §11, R5-3's amendment): each incoming clip, and every
    /// clip at or after its cut on an unlocked track, slides left by the
    /// same half second, so the overlap is made of footage the clips already
    /// show and the project gets shorter. It is offered only here, where the
    /// handle form found nothing at all, because a cut with ANY footage to
    /// spare got a shorter transition and never reaches this sheet. The
    /// MCP tool's refusal says the same thing in the op's words
    /// (`AgentServer+Transitions.swift`).
    ///
    /// The sheet's completion is not an AppKit event, so the edit goes
    /// through `performGroupedEdit` (app/CLAUDE.md's undo pitfall), and it is
    /// one undo step whatever the number of cuts.
    private func presentNoFootageForTransition(
        clips: [UInt32], kind: TransitionKind, duration: Ticks
    ) {
        guard let window = view.window else {
            NSSound.beep()
            return
        }
        let one = clips.count == 1
        let alert = NSAlert()
        alert.messageText =
            one
            ? "There’s no extra footage at this cut for a transition."
            : "There’s no extra footage at these cuts for a transition."
        alert.informativeText =
            "A transition overlaps two clips, so it needs footage past the end of the "
            + "first clip or before the start of the second. A clip that uses its whole "
            + "file has none.\n\nShift Clips Left makes the overlap by sliding "
            + (one ? "the second clip" : "the second clip at each cut")
            + " — and everything after it on unlocked tracks — left by half a second. "
            + "The project gets shorter by the same amount."
        alert.addButton(withTitle: "Shift Clips Left")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self, weak document] response in
            guard response == .alertFirstButtonReturn, let self = self, let document = document
            else { return }
            document.performGroupedEdit(
                "Add Transition", self.shiftingOps(clips, kind: kind, duration: duration))
        }
    }

    /// Shift Clips Left's ops, each decided against the project the EARLIER
    /// ones leave behind rather than against the snapshot the sheet was
    /// built from.
    ///
    /// One ripple slides every clip at or after its cut on every unlocked
    /// track, and a clip whose PREDECESSOR began before that cut does not
    /// slide with it — so a second chosen cut can already be an overlap by
    /// the time its own op runs. `add_transition` answers that with an
    /// `Err` ("not at a hard cut"), `ReelProject.applying` THROWS on an
    /// `Err`, and the throw takes the whole batch with it: the first
    /// shift — which had already made the second cut's overlap — is lost,
    /// and the person is shown a sentence about a clip they did not point
    /// at. Re-deciding sends `set_transition` for a cut that is now an
    /// overlap, which is what Clip ▸ Transition ▸ sends for an overlap
    /// anyway, so every cut chosen ends up carrying the kind.
    ///
    /// An op the running project declines is dropped rather than carried:
    /// what `performGroupedEdit` is handed has already been shown to apply,
    /// one op at a time, to the project it will be replayed against.
    private func shiftingOps(
        _ clips: [UInt32], kind: TransitionKind, duration: Ticks
    ) -> [ReelOp] {
        guard let document = document else { return [] }
        var project = document.editedProject
        var ops: [ReelOp] = []
        for id in clips {
            guard let clip = project.snapshot.clips.first(where: { $0.id == id }) else { continue }
            let op: ReelOp
            switch transitionPlacement(of: clip, in: project.snapshot) {
            case .overlap:
                op = .setTransition(clip: id, kind: kind)
            case .hardCut:
                op = .addTransition(
                    clip: id, kind: kind, duration: duration, align: .center, ripple: true)
            case .neither:
                continue
            }
            guard let next = (try? project.applying(op))?.project else { continue }
            ops.append(op)
            project = next
        }
        return ops
    }

    /// Where a clip sits relative to the clip before it on its track, which
    /// is what decides how Clip ▸ Transition ▸ writes a kind onto it.
    enum TransitionPlacement {
        case overlap
        case hardCut
        case neither
    }

    /// `roll`'s test, in Swift: the predecessor is whatever ends EXACTLY
    /// where this clip begins (`EditorViewController+Edge.swift`), and an
    /// overlap is a predecessor that ends after it.
    func transitionPlacement(of clip: ClipSnapshot) -> TransitionPlacement {
        guard let document = document else { return .neither }
        return transitionPlacement(of: clip, in: document.editedProject.snapshot)
    }

    func transitionPlacement(
        of clip: ClipSnapshot, in snapshot: ProjectSnapshot
    ) -> TransitionPlacement {
        let neighbours = snapshot.clips.filter { $0.track == clip.track && $0.id != clip.id }
        if neighbours.contains(where: { $0.start < clip.start && $0.end > clip.start }) {
            return .overlap
        }
        if neighbours.contains(where: { $0.end == clip.start }) {
            return .hardCut
        }
        return .neither
    }
}
