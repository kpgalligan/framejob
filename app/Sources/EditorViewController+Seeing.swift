import AppKit

/// Seeing the grade (grading GR3, grading-2 G2-1, spec §11 GR-4, GR-5 and
/// GR-10): View ▸ Show Ungraded and View ▸ Scopes, both checkmark toggles in
/// the preview group.
///
/// **Both are view state, per window, and neither persists**: no
/// `UserDefaults` key, so a new window starts with both off (and the scopes'
/// slots at Waveform over Vectorscope) and a proof can drive them through
/// `perform_menu_item` without moving the defaults. No MCP tool mirrors them
/// or the slot picks (§7.9's Preview Quality exemption); `render_frame
/// {ungraded, waveform, parade, vectorscope, histogram}` is the capability.
///
/// **Show Ungraded is an option on the document's KEY** (`RecipeSource`,
/// spec §7.3), so it reaches exactly what composes through that key: the
/// editor's preview and the Preview Window, one player. An export, Save
/// Frame…, the eyedropper and `render_frame` mint keys of their own
/// (`Exporter`), which is why the switch cannot reach them.
///
/// The panel and the tag are found by kind among `canvasContainer`'s
/// subviews, as `previewCanvas` is: the frozen base file holds no property
/// for them.
extension EditorViewController {
    var scopesPanel: ScopesPanelView? {
        canvasContainer.subviews.compactMap { $0 as? ScopesPanelView }.first
    }

    var ungradedTag: UngradedTagView? {
        canvasContainer.subviews.compactMap { $0 as? UngradedTagView }.first
    }

    /// The panel at the pane's right edge, the canvas's trailing edge pinned
    /// to its leading one, and the tag in the void's top-left corner. Called
    /// once, from `installCanvas`. A slot the panel reveals or re-picks asks
    /// for a frame through `refreshSeeing`.
    func installSeeing(beside canvas: PreviewCanvasView) {
        let panel = ScopesPanelView()
        panel.onNeedsFrame = { [weak self] in self?.refreshSeeing() }
        let tag = UngradedTagView()
        for view in [panel, tag] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            canvasContainer.addSubview(view)
        }
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            panel.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor),
            panel.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor),
            canvas.trailingAnchor.constraint(equalTo: panel.leadingAnchor),
            tag.topAnchor.constraint(equalTo: canvasContainer.topAnchor, constant: 4),
            tag.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor, constant: 8),
        ])
    }

    // MARK: - Commands

    /// View ▸ Show Ungraded (⌃⌘U): every grade off in this window's preview.
    @objc func toggleShowUngraded(_ sender: Any?) {
        guard let document = document else { return }
        var options = RecipeSource.shared.options(for: document.recipeKey)
        options.ungraded.toggle()
        RecipeSource.shared.setOptions(options, for: document.recipeKey)
        ungradedTag?.isHidden = !options.ungraded
        refreshSeeing()
    }

    /// View ▸ Scopes (⌃⌘W): the panel beside the preview, on or off.
    @objc func toggleScopes(_ sender: Any?) {
        guard let document = document, let panel = scopesPanel else { return }
        panel.setShown(!panel.isShown, key: document.recipeKey)
        refreshSeeing()
    }

    /// The paused frame composed again: the preview shows the switch at once,
    /// and a panel just shown gets a frame to analyse (a playing preview
    /// composes on its own).
    private func refreshSeeing() {
        playback.refreshPausedFrame()
    }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns; nil means "not
    /// one of mine". Always enabled, like Preview Window: both are about the
    /// preview, not the timeline. The checkmark is the state.
    func validateSeeingAction(
        _ action: Selector, item: any NSValidatedUserInterfaceItem
    ) -> Bool? {
        switch action {
        case #selector(toggleShowUngraded(_:)):
            let on = document.map { RecipeSource.shared.options(for: $0.recipeKey).ungraded }
            (item as? NSMenuItem)?.state = on == true ? .on : .off
            return true
        case #selector(toggleScopes(_:)):
            (item as? NSMenuItem)?.state = scopesPanel?.isShown == true ? .on : .off
            return true
        default:
            return nil
        }
    }
}
