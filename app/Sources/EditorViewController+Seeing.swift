import AppKit

/// Seeing the grade (grading GR3, grading-2 G2-1 and G2-4, spec §11 GR-4,
/// GR-5, GR-10 and GR-13): View ▸ Show Ungraded, View ▸ Show Selection,
/// View ▸ Show SDR Version (hdr H-3, spec §11 HD-7, HD-14 (g)) and View ▸
/// Scopes, checkmark toggles in the preview group.
///
/// **All four are view state, per window, and none persists**: no
/// `UserDefaults` key, so a new window starts with each off (and the scopes'
/// slots at Waveform over Vectorscope) and a proof can drive them through
/// `perform_menu_item` without moving the defaults. No MCP tool mirrors them
/// or the slot picks (§7.9's Preview Quality exemption); `render_frame
/// {ungraded, selection, sdr_version, waveform, parade, vectorscope,
/// histogram}` is the capability.
///
/// **Show Ungraded, Show Selection and Show SDR Version are options on the
/// document's KEY** (`RecipeSource`,
/// spec §7.3), so it reaches exactly what composes through that key: the
/// editor's preview and the Preview Window, one player. An export, Save
/// Frame…, the eyedropper and `render_frame` mint keys of their own
/// (`Exporter`), which is why the switch cannot reach them.
///
/// **Show Selection is bound to ONE adjustment clip** (`selection` holds its
/// id): turned on for the first selected adjustment clip, rebound when the
/// selection changes to another (`syncShowSelection`, from `refreshCanvas`),
/// and turned off when no adjustment clip is selected; disabled while off
/// with none selected.
///
/// The panel and the tag stack are found by kind among `canvasContainer`'s
/// subviews, as `previewCanvas` is: the frozen base file holds no property
/// for them. The tags sit in one horizontal stack (spacing 4, hidden tags
/// detached), so "Selection" moves into the corner when "Ungraded" is off.
extension EditorViewController {
    var scopesPanel: ScopesPanelView? {
        canvasContainer.subviews.compactMap { $0 as? ScopesPanelView }.first
    }

    var seeingTags: SeeingTagStack? {
        canvasContainer.subviews.compactMap { $0 as? SeeingTagStack }.first
    }

    func previewTag(_ kind: PreviewTag) -> PreviewTagView? {
        seeingTags?.arrangedSubviews.compactMap { $0 as? PreviewTagView }.first { $0.kind == kind }
    }

    var ungradedTag: PreviewTagView? { previewTag(.ungraded) }

    var selectionTag: PreviewTagView? { previewTag(.selection) }

    var sdrVersionTag: PreviewTagView? { previewTag(.sdrVersion) }

    /// The panel at the pane's right edge, the canvas's trailing edge pinned
    /// to its leading one, and the tags in the void's top-left corner. Called
    /// once, from `installCanvas`. A slot the panel reveals or re-picks asks
    /// for a frame through `refreshSeeing`.
    func installSeeing(beside canvas: PreviewCanvasView) {
        let panel = ScopesPanelView()
        panel.onNeedsFrame = { [weak self] in self?.refreshSeeing() }
        let tag = SeeingTagStack(
            views: [.ungraded, .selection, .sdrVersion].map(PreviewTagView.init))
        tag.orientation = .horizontal
        tag.spacing = 4
        tag.detachesHiddenViews = true
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

    /// View ▸ Show Selection (no shortcut, spec §11 GR-13): on, bound to the
    /// first selected adjustment clip; off. The Qualifier section's switch
    /// sends the same command, and the inspector is refreshed so it follows.
    @objc func toggleShowSelection(_ sender: Any?) {
        guard let document = document else { return }
        var options = RecipeSource.shared.options(for: document.recipeKey)
        if options.selection != nil {
            options.selection = nil
        } else if let clip = firstSelectedAdjustment {
            options.selection = clip
        } else {
            NSSound.beep()
            return
        }
        showSelection(options, for: document)
    }

    /// View ▸ Show SDR Version (no shortcut, spec §11 HD-7, HD-14 (g)): this
    /// window's preview drawn as the project's SDR version — `dynamicRange`
    /// `.sdr` on the document's key, the composition recoloured BT.709 with
    /// no rebuild (`Playback.recompose`). In an SDR project no pixel changes
    /// and the tag still shows.
    @objc func toggleShowSDRVersion(_ sender: Any?) {
        guard let document = document else { return }
        var options = RecipeSource.shared.options(for: document.recipeKey)
        options.dynamicRange = options.dynamicRange == .sdr ? nil : .sdr
        RecipeSource.shared.setOptions(options, for: document.recipeKey)
        sdrVersionTag?.isHidden = options.dynamicRange != .sdr
        playback.recompose()
    }

    /// Called from `refreshCanvas`: while Show Selection is on, a selection
    /// change rebinds it to the first selected adjustment clip, or turns it
    /// off when none is selected. Nothing while it is off.
    func syncShowSelection() {
        guard let document = document else { return }
        var options = RecipeSource.shared.options(for: document.recipeKey)
        guard let bound = options.selection else { return }
        let next = firstSelectedAdjustment
        guard next != bound else { return }
        options.selection = next
        showSelection(options, for: document)
    }

    /// The first selected adjustment clip's id, or nil.
    private var firstSelectedAdjustment: UInt32? {
        (inspector?.selectedClips ?? []).first { InspectorTab.isAdjustment($0) }?.id
    }

    /// Publishes `options` on the document's key, the tag and the switch
    /// following.
    private func showSelection(_ options: RecipeOptions, for document: ProjectDocument) {
        RecipeSource.shared.setOptions(options, for: document.recipeKey)
        selectionTag?.isHidden = options.selection == nil
        refreshSeeing()
        inspector?.refresh(isLive: false)
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
    /// one of mine". Show Ungraded, Show SDR Version and Scopes are always
    /// enabled, like Preview Window: each is about the preview, not the
    /// timeline; Show Selection is disabled while off with no adjustment clip
    /// selected. The checkmark is the state.
    func validateSeeingAction(
        _ action: Selector, item: any NSValidatedUserInterfaceItem
    ) -> Bool? {
        switch action {
        case #selector(toggleShowUngraded(_:)):
            let on = document.map { RecipeSource.shared.options(for: $0.recipeKey).ungraded }
            (item as? NSMenuItem)?.state = on == true ? .on : .off
            return true
        case #selector(toggleShowSDRVersion(_:)):
            let on = document.map {
                RecipeSource.shared.options(for: $0.recipeKey).dynamicRange == .sdr
            }
            (item as? NSMenuItem)?.state = on == true ? .on : .off
            return true
        case #selector(toggleShowSelection(_:)):
            let on = document.flatMap {
                RecipeSource.shared.options(for: $0.recipeKey).selection
            } != nil
            (item as? NSMenuItem)?.state = on ? .on : .off
            return on || firstSelectedAdjustment != nil
        case #selector(toggleScopes(_:)):
            (item as? NSMenuItem)?.state = scopesPanel?.isShown == true ? .on : .off
            return true
        default:
            return nil
        }
    }
}

/// The preview's tag stack (spec §11 GR-4, GR-13, HD-14 (g)): "Ungraded",
/// "Selection", then "SDR Version", hidden tags detached. Like the tags, it
/// takes no clicks, so a gesture in the void beneath it is the canvas's.
final class SeeingTagStack: NSStackView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
