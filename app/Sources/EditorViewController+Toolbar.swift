import AppKit

/// The window toolbar — the chrome cleanup's §1, and the whole of it.
///
/// **One job instead of four.** The 44 pt row keeps only what applies to the
/// document at all times: *where you are in it* (transport, timecode), *how
/// you are looking at it* (canvas zoom, safe guides) and *getting it out*
/// (Export). Everything that acts on a clip went down to the timeline bar,
/// next to blade and ripple-delete where it belongs — Add Text and Add Shape
/// moved, and the toolbar's Add Marker was a second copy of the one the
/// timeline bar already had, so it is simply gone. The `@objc` forwards for
/// all three stay in `EditorViewController.swift`: the menus still use them.
///
/// Split out of `EditorViewController` because that file is frozen at wiring
/// (app/CLAUDE.md). The seven stored views have to stay there — an extension
/// cannot add stored properties — which is exactly the case that file's header
/// makes for their being internal rather than private; everything that is only
/// behaviour is here.
extension EditorViewController {
    // MARK: - Metrics

    /// The transport cluster's shared button geometry. Read from the frozen
    /// file's `playButton` / `pauseButton` / `loopButton` initialisers as well
    /// as from `buildToolbar`, so the six buttons cannot drift apart.
    ///
    /// **34, not the design's 30.** The handoff asks for 30 × 26 buttons AND a
    /// 19 pt symbol, and the two cannot both hold: `backward` and `forward` at
    /// pointSize 19 weight `.medium` measure exactly 30 × 18 pt (measured), so
    /// `GhostButton.drawIcon` centres them at x = 0 spanning the whole button
    /// — no side padding at all, and the glyph touches the hover fill's
    /// corners. 34 leaves 2 pt each side, which is what the narrower five
    /// (`backward.end`/`forward.end` 21, `play.fill` 18, `repeat` 26) already
    /// had, so all six keep one optical rhythm.
    static let transportButtonSize = NSSize(width: 34, height: 26)
    static let transportSymbolPointSize: CGFloat = 19

    /// 12 pt of padding at both ends and 12 pt between clusters; 2 pt inside
    /// the transport, which reads as one control rather than six.
    private static let toolbarPadding: CGFloat = 12
    private static let toolbarClusterGap: CGFloat = 12
    private static let transportGap: CGFloat = 2
    /// The rule between clusters, and the timecode field's width — wide enough
    /// for `HH:MM:SS:FF` in mono 12.
    private static let toolbarDividerLength: CGFloat = 20
    private static let timecodeWidth: CGFloat = 112

    // MARK: - Construction

    /// Transport · timecode ——— view · Export. Called once, from `loadView`.
    func buildToolbar() -> NSView {
        let bar = BarView(border: .bottom)

        // 24 pt on the button radius rather than the 26/7 field default: the
        // timecode sits in a row of 26 pt buttons and a taller, rounder field
        // would be the only soft shape in it.
        DSField.style(
            timecodeField, height: 24, radius: DS.buttonRadius,
            font: DS.mono(12, weight: .medium))
        timecodeField.alignment = .center
        timecodeField.delegate = self
        timecodeField.toolTip = "Current time — click to type one (1:23, 83.5, 1:23:04)"
        timecodeField.widthAnchor.constraint(equalToConstant: Self.timecodeWidth).isActive = true

        durationLabel.font = DS.mono(11)
        durationLabel.textColor = DS.textFaint

        zoomPopup = OptionPopupControl(
            width: 74, items: Self.canvasZoomTitles,
            read: { [weak self] in self?.canvasZoomIndex ?? 0 },
            write: { [weak self] index in self?.setCanvasZoom(index) },
            enabled: { true },
            onEdit: { [weak self] in self?.refreshToolbarControls() })

        safeToggle = OptionCheckboxControl(
            label: "Safe",
            read: { [weak self] in self?.safeGuidesVisible ?? false },
            write: { [weak self] value in self?.setSafeGuides(value) },
            enabled: { true },
            onEdit: { [weak self] in self?.refreshToolbarControls() })

        let row = NSStackView(views: [
            transportCluster(),
            DividerView(length: Self.toolbarDividerLength),
            timecodeCluster(),
            flexibleSpace(),
            viewCluster(),
            DividerView(length: Self.toolbarDividerLength),
            AccentButton(
                title: "Export…", symbol: "square.and.arrow.up", fallback: "⤴",
                tooltip: "Export… (⌘E)", action: #selector(exportProject(_:))),
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Self.toolbarClusterGap
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(
                equalTo: bar.leadingAnchor, constant: Self.toolbarPadding),
            row.trailingAnchor.constraint(
                equalTo: bar.trailingAnchor, constant: -Self.toolbarPadding),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    /// Six buttons, one of which is the play/pause pair swapping on `isHidden`
    /// (`playbackRateChanged`) — so the cluster is always six wide and the
    /// timecode beside it never shifts when playback starts.
    private func transportCluster() -> NSStackView {
        let cluster = NSStackView(views: [
            transportButton(
                symbol: "backward.end", fallback: "⏮", tooltip: "Go to Start (Home)",
                action: #selector(goToStart(_:))),
            transportButton(
                symbol: "backward", fallback: "◀◀", tooltip: "Previous Edit Point (↑)",
                action: #selector(previousEditPoint(_:))),
            playButton, pauseButton,
            transportButton(
                symbol: "forward", fallback: "▶▶", tooltip: "Next Edit Point (↓)",
                action: #selector(nextEditPoint(_:))),
            transportButton(
                symbol: "forward.end", fallback: "⏭", tooltip: "Go to End (End)",
                action: #selector(goToEnd(_:))),
            loopButton,
        ])
        cluster.orientation = .horizontal
        cluster.spacing = Self.transportGap
        return cluster
    }

    private func transportButton(
        symbol: String, fallback: String, tooltip: String, action: Selector
    ) -> GhostButton {
        GhostButton(
            symbol: symbol, fallback: fallback, caption: nil, tooltip: tooltip, action: action,
            size: Self.transportButtonSize, pointSize: Self.transportSymbolPointSize,
            cornerRadius: DS.buttonRadius)
    }

    /// The position field and the document's duration after it. One cluster,
    /// because "83:04 of 00:00:37:05" is one fact.
    private func timecodeCluster() -> NSStackView {
        let cluster = NSStackView(views: [timecodeField, durationLabel])
        cluster.orientation = .horizontal
        cluster.alignment = .centerY
        cluster.spacing = 6
        return cluster
    }

    private func viewCluster() -> NSStackView {
        let cluster = NSStackView(views: [zoomPopup, safeToggle])
        cluster.orientation = .horizontal
        cluster.alignment = .centerY
        cluster.spacing = 10
        return cluster
    }

    /// The gap that pushes View and Export to the trailing edge. Priority 1 on
    /// both axes of resistance so the stack takes every spare point out of this
    /// view and none out of a control.
    private func flexibleSpace() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)
        return spacer
    }

    // MARK: - Refresh

    /// Pulls the two option controls back into agreement with the flags they
    /// read, and dims Loop when it is off — `GhostButton` has no on-state, and
    /// alpha is the whole of the toggle's state model here.
    func refreshToolbarControls() {
        zoomPopup?.refresh()
        safeToggle?.refresh()
        loopButton.alphaValue = loopEnabled ? 1 : 0.55
    }
}
