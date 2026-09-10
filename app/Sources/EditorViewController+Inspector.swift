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

        timeline?.registerForDraggedTypes([.reelcutMedia])
        previewCanvas?.registerForDraggedTypes([.reelcutMedia])
        refreshInspector(isLive: false)
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
            probed = try document.editedProject.applying(ops)
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

    /// ⌥⌘K and the Actions section's button: an action at the playhead on the
    /// selected clip. `add_action` takes CLIP time (§6), and refuses an
    /// overlap or a span past the clip end — so the only check here is that
    /// the playhead is actually on a selected clip.
    func addActionAtPlayheadCommand() {
        guard let document = document,
              let clip = selectedClips.first(where: { $0.contains(document.playhead) })
        else {
            NSSound.beep()
            return
        }
        document.applyEdit(
            "Add Action", .addAction(clip: clip.id, at: clip.clipTime(document.playhead)))
    }

    /// Clip ▸ Transition ▸ — the sender's tag indexes `TransitionKind.allCases`
    /// and −1 is None, the same table the Video tab's popup offers.
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
        let kind: TransitionKind? = tag < 0 ? nil : kinds[tag]
        document.applyEdit(
            "Set Transition", selectedClips.map { .setTransition(clip: $0.id, kind: kind) })
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
            }
            return !document.selection.isEmpty
        default:
            return nil
        }
    }
}
