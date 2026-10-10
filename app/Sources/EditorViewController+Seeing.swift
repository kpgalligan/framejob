import AppKit

/// Seeing the grade (grading GR3, spec §11 GR-4 and GR-5): View ▸ Show
/// Ungraded and View ▸ Waveform, both checkmark toggles in the preview group.
///
/// **Both are view state, per window, and neither persists**: no
/// `UserDefaults` key, so a new window starts with both off and a proof can
/// drive them through `perform_menu_item` without moving the defaults. No MCP
/// tool mirrors them (§7.9's Preview Quality exemption); `render_frame
/// {ungraded, waveform}` is the capability.
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
    var waveformPanel: WaveformPanelView? {
        canvasContainer.subviews.compactMap { $0 as? WaveformPanelView }.first
    }

    var ungradedTag: UngradedTagView? {
        canvasContainer.subviews.compactMap { $0 as? UngradedTagView }.first
    }

    /// The panel at the pane's right edge, the canvas's trailing edge pinned
    /// to its leading one, and the tag in the void's top-left corner. Called
    /// once, from `installCanvas`.
    func installSeeing(beside canvas: PreviewCanvasView) {
        let panel = WaveformPanelView()
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

    /// View ▸ Waveform (⌃⌘W): the panel beside the preview, on or off.
    @objc func toggleWaveform(_ sender: Any?) {
        guard let document = document, let panel = waveformPanel else { return }
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
        case #selector(toggleWaveform(_:)):
            (item as? NSMenuItem)?.state = waveformPanel?.isShown == true ? .on : .off
            return true
        default:
            return nil
        }
    }
}
