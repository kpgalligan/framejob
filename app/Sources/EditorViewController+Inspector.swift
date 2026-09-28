import AppKit

/// The inspector's half of the editor: installing `InspectorViewController` in
/// the right-hand pane, turning its `on*` intents into `ProjectDocument`
/// edits, and the two commands the panel made real — Add Action at the
/// playhead (⌥⌘K) and Clip ▸ Transition ▸.
///
/// Nothing here holds state — an extension cannot — which is deliberate: the
/// panel's state lives on the inspector controller and the model lives on the
/// document, so this file is only ever the seam between them.
extension EditorViewController {
    /// The installed inspector, found among the children rather than kept in
    /// a stored property: `EditorViewController.swift` is frozen at wiring,
    /// and the pane container is the seam it publishes.
    var inspector: InspectorViewController? {
        children.compactMap { $0 as? InspectorViewController }.first
    }

    // MARK: - Installation

    /// Fills the inspector pane. Called from `viewDidLoad` AFTER the canvas
    /// and the timeline, because it registers those two views as drop targets
    /// for a dragged media row (`MediaPane.swift` owns the handlers).
    func installInspector() {
        let inspector = InspectorViewController()
        inspector.document = document
        addChild(inspector)
        let panel = inspector.view
        panel.translatesAutoresizingMaskIntoConstraints = false
        for existing in inspectorContainer.subviews where existing !== panel {
            existing.removeFromSuperview()
        }
        inspectorContainer.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: inspectorContainer.topAnchor),
            panel.bottomAnchor.constraint(equalTo: inspectorContainer.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: inspectorContainer.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: inspectorContainer.trailingAnchor),
        ])

        // One-line forwards only (app/CLAUDE.md): every body is a named method
        // on this controller or on the document.
        inspector.onEdit = { [weak self] name, ops in self?.document?.applyEdit(name, ops) }
        inspector.onGroupedEdit = { [weak self] name, ops in
            self?.document?.performGroupedEdit(name, ops)
        }
        inspector.onLiveBegin = { [weak self] in self?.document?.beginLiveEdit() }
        inspector.onLiveUpdate = { [weak self] ops in self?.document?.updateLiveEdit(ops) }
        inspector.onLiveEnd = { [weak self] name in self?.document?.endLiveEdit(name) }
        inspector.onImportFiles = { [weak self] urls in self?.document?.importMedia(urls) }
        inspector.onProbe = { [weak self] ops in self?.inspectorProbe(ops) }
        inspector.onSeek = { [weak self] time in self?.inspectorSeek(time) }
        inspector.onCommand = { [weak self] selector in self?.inspectorCommand(selector) }
        inspector.onSelectAction = { [weak self] id in self?.selectAction(id) }
        installAssistant(on: inspector)
        NotificationCenter.default.addObserver(
            self, selector: #selector(documentDidRefuse(_:)),
            name: .projectDocumentDidRefuse, object: document)

        timeline?.registerForDraggedTypes([.reelcutMedia])
        previewCanvas?.registerForDraggedTypes([.reelcutMedia])
        refreshInspector(isLive: false)
    }

    /// A person's edit the core refused (spec §11 CI-10): its sentence goes
    /// to the inspector's foot. `applyEdit` has already beeped.
    @objc func documentDidRefuse(_ note: Notification) {
        guard let document, note.object as? ProjectDocument === document,
              let refusal = note.userInfo?["refusal"] as? ReelRefusal
        else { return }
        inspector?.showRefusal(refusal)
    }

    /// Project → inspector, from `refreshFromDocument`. `isLive` rides
    /// through: mid-gesture the values change but the panel's shape does not,
    /// so the panel refreshes its fields and never rebuilds them.
    ///
    /// **This is also how clicking a clip shows the Clip tab.** A timeline or
    /// canvas pick writes `document.selection` and calls `viewStateDidChange`,
    /// which posts `.projectDocumentDidChange` and lands here; the inspector
    /// compares the incoming selection with the one it last drew and switches
    /// tabs when it changed. The rule lives there rather than at the two pick
    /// sites because the panel is the thing that has to know which tab it is
    /// on — and because ⌘A, ⌥⌘A, paste and an agent's `set_selection` all
    /// arrive by this same path and mean the same thing.
    func refreshInspector(isLive: Bool) {
        inspector?.refresh(isLive: isLive)
    }

    /// Playhead → inspector, from `playbackTimeChanged` and `setPlayhead`.
    ///
    /// Guarded rather than unconditional: the panel's values depend on the
    /// playhead only when a selected clip HAS actions (§4.3 — the fields then
    /// show the evaluated state and edits set that action's end patch), and
    /// refreshing forty controls thirty times a second for a clip with no
    /// actions would be pure waste.
    func inspectorPlayheadMoved() {
        guard let inspector = inspector,
              inspector.selectedClips.contains(where: { !$0.actions.isEmpty })
        else { return }
        inspector.refresh(isLive: false)
    }

    // MARK: - Intents from the panel

    /// Applies ops to the current handle PURELY so the Media tab can learn
    /// the id of the track a canvas drop is about to create. This is not an
    /// edit: nothing is published and no undo step is registered.
    private func inspectorProbe(_ ops: [ReelOp]) -> ProjectSnapshot? {
        guard let document = document else { return nil }
        let probed: ReelProject?
        do {
            probed = try document.editedProject.applying(ops).project
        } catch {
            return nil
        }
        return probed?.snapshot
    }

    private func inspectorSeek(_ time: Ticks) {
        playback.pause()
        setPlayhead(time)
    }

    /// A pane button that mirrors a menu command (Crop on Canvas, Detach
    /// Audio, Add Media…). Sending the selector rather than duplicating the
    /// body keeps one implementation per command.
    private func inspectorCommand(_ selector: Selector) {
        guard responds(to: selector) else {
            NSSound.beep()
            return
        }
        _ = perform(selector, with: nil)
    }

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
    /// and −1 is None, the same table the Video tab's popup offers.
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

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// mine" and leaves the other answers alone.
    func validateInspectorAction(
        _ action: Selector, item: any NSValidatedUserInterfaceItem
    ) -> Bool? {
        guard let document = document else { return false }
        switch action {
        case #selector(addActionAtPlayhead(_:)):
            return selectedClips.contains { $0.contains(document.playhead) }
        case #selector(setTransitionKind(_:)):
            if let menuItem = item as? NSMenuItem {
                let kinds = TransitionKind.allCases
                let current = selectedClips.first?.transitionIn?.kind
                let tagged = kinds.indices.contains(menuItem.tag) ? kinds[menuItem.tag] : nil
                menuItem.state = tagged == current ? .on : .off
                // None stays enabled for ANY selection, as it always has:
                // a clip can carry a stored transition the timeline does not
                // draw — set at a hard cut, or left behind when the overlap
                // was dragged away — and clearing it must stay reachable.
                // A KIND is only enabled where there is somewhere to put
                // one, since the command skips every other clip.
                if menuItem.tag >= 0 {
                    return selectedClips.contains { transitionPlacement(of: $0) != .neither }
                }
            }
            return !document.selection.isEmpty
        default:
            return nil
        }
    }
}
