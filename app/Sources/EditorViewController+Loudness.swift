import AppKit

/// View ▸ Loudness Meter (road map "audio" AP7, spec §11 AU-75, AU-76): the
/// live loudness column between the canvas and Scopes, and its Reset.
///
/// **View state, per window, and none of it persists**: no `UserDefaults`
/// key, so a new window starts with the column off and the meter empty. No
/// product MCP tool mirrors the item or Reset (§7.9's Preview Quality
/// exemption, AU-77); the dev tool `loudness_meter` reads and resets the
/// meter for a proof.
///
/// The column is found by kind among `canvasContainer`'s subviews, as the
/// scopes panel is: the frozen base file holds no property for it.
extension EditorViewController {
    var loudnessPanel: LoudnessPanelView? {
        canvasContainer.subviews.compactMap { $0 as? LoudnessPanelView }.first
    }

    /// The column between `canvas` and `scopes`, full height, bound to this
    /// window's transport. Called once, from `installSeeing`.
    func installLoudnessPanel(between canvas: PreviewCanvasView, and scopes: ScopesPanelView) {
        let panel = LoudnessPanelView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        canvasContainer.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            panel.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor),
            canvas.trailingAnchor.constraint(equalTo: panel.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: scopes.leadingAnchor),
        ])
        panel.bind(playback.loudness)
    }

    /// View ▸ Loudness Meter (⌃⌘L): the column on or off. The meter measures
    /// either way; the column only shows it.
    @objc func toggleLoudnessMeter(_ sender: Any?) {
        guard let panel = loudnessPanel else { return }
        panel.setShown(!panel.isShown)
    }

    /// The column's Reset: the measurement starts again (`manual`).
    @objc func resetLoudnessMeter(_ sender: Any?) {
        playback.loudness.reset(.manual)
    }

    /// The half of `validateUserInterfaceItem` this file owns; nil means "not
    /// one of mine". Both are always enabled, like Scopes; the checkmark is
    /// the column's state.
    func validateLoudnessMeterAction(
        _ action: Selector, item: any NSValidatedUserInterfaceItem
    ) -> Bool? {
        switch action {
        case #selector(toggleLoudnessMeter(_:)):
            (item as? NSMenuItem)?.state = loudnessPanel?.isShown == true ? .on : .off
            return true
        case #selector(resetLoudnessMeter(_:)):
            return true
        default:
            return nil
        }
    }
}
