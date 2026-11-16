import AppKit

/// The inspector's half of the editor: installing `InspectorViewController` in
/// the right-hand pane, turning its `on*` intents into `ProjectDocument`
/// edits, and the validator arm of the two commands the panel made real —
/// Add Action at the playhead (⌥⌘K) and Clip ▸ Transition ▸ — whose bodies
/// are `EditorViewController+InspectorCommands.swift`'s.
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
        inspector.onEdit = { [weak self] name, ops in self?.inspectorEdit(name, ops) }
        inspector.onGroupedEdit = { [weak self] name, ops in
            self?.document?.performGroupedEdit(name, ops)
        }
        inspector.onAmendEdit = { [weak self] name, ops, step in
            self?.document?.applyEdit(name, ops, amending: step)
        }
        inspector.onLiveBegin = { [weak self] in self?.document?.beginLiveEdit() }
        inspector.onLiveUpdate = { [weak self] ops in self?.timelineLiveUpdated(ops) }
        inspector.onLiveEnd = { [weak self] name in self?.timelineLiveEnded(name) }
        inspector.onImportFiles = { [weak self] urls in self?.document?.importMedia(urls) }
        inspector.onProbe = { [weak self] ops in self?.inspectorProbe(ops) }
        inspector.onSeek = { [weak self] time in self?.inspectorSeek(time) }
        inspector.onCommand = { [weak self] selector in self?.inspectorCommand(selector) }
        inspector.onSelectAction = { [weak self] id in self?.selectAction(id) }
        installAssistant(on: inspector)
        NotificationCenter.default.addObserver(
            self, selector: #selector(documentDidRefuse(_:)),
            name: .projectDocumentDidRefuse, object: document)
        NotificationCenter.default.addObserver(
            self, selector: #selector(documentDidNote(_:)),
            name: .projectDocumentDidNote, object: document)

        timeline?.registerForDraggedTypes([.frameJobMedia])
        previewCanvas?.registerForDraggedTypes([.frameJobMedia])
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

    /// A measured press's notice (spec §11 AU-169): the clips Normalize,
    /// Enhance Voice or Match Audio left away from the target or skipped,
    /// at the inspector's foot. Nothing beeps for it.
    @objc func documentDidNote(_ note: Notification) {
        guard let document, note.object as? ProjectDocument === document,
              let notice = note.userInfo?["notice"] as? AudioMeasureNotice
        else { return }
        inspector?.showNotice(notice)
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
        if let inspector { TranscriptPane.pane(in: inspector)?.playheadMoved() }
        // The Look gallery's thumbnail time follows the playhead whatever the
        // clips hold, so it is poked before the guard (spec §11 GR-7 [b]).
        if let document = document { LookGallery.playheadMoved(in: document) }
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
