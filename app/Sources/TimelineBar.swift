import AppKit

/// The 36 pt bar over the lanes (the redesign's §4): a fixed selection block
/// at the left edge that never moves, then the tools.
///
/// It mirrors Rasterize's options bar — identity first, then what acts on it.
/// Duplicate, Add Text and Add Shape came DOWN from the window toolbar in the
/// same change: they act on a clip, so they belong next to blade and ripple
/// delete rather than beside Export. Built here rather than in
/// `TimelineView.swift`, which is frozen at wiring (app/CLAUDE.md); the view
/// keeps only the three handles it later refreshes.
enum TimelineBar {
    /// What `TimelineView` has to hold on to after the bar is built: the
    /// block it pushes a selection into and the two option controls it asks
    /// to re-read themselves.
    ///
    /// The level meter is deliberately NOT here. It subscribes to
    /// `LevelMeter.shared` itself, so nothing has to push into it and the
    /// frozen `TimelineView` and `EditorViewController` gain neither a stored
    /// handle nor a fan-out line for it.
    struct Parts {
        let view: NSView
        let selection: TimelineSelectionBlock
        let snap: OptionCheckboxControl
        let size: OptionSegmentedControl
    }

    /// The design's 12 pt edge padding and 12 pt between clusters.
    private static let padding: CGFloat = 12
    /// Edit-action buttons: 28 × 24 at 17 pt, on the 4 pt button radius.
    private static let actionSize = NSSize(width: 28, height: 24)
    private static let actionPointSize: CGFloat = 17

    static func build(owner: TimelineView) -> Parts {
        let bar = BarView(border: .both)

        let selection = TimelineSelectionBlock()

        let actions = NSStackView(views: editActions())
        actions.orientation = .horizontal
        actions.spacing = 2

        let snap = OptionCheckboxControl(
            label: "Snap",
            read: { [weak owner] in owner?.snappingEnabled ?? false },
            write: { [weak owner] _ in owner?.onSnappingToggled?() },
            enabled: { true },
            onEdit: { [weak owner] in owner?.snapToggle?.refresh() })

        let size = OptionSegmentedControl(
            segments: [
                (symbol: "reelcut.small", fallback: "S", tooltip: "Small tracks"),
                (symbol: "reelcut.medium", fallback: "M", tooltip: "Medium tracks"),
                (symbol: "reelcut.large", fallback: "L", tooltip: "Large tracks"),
            ],
            read: { [weak owner] in owner?.trackHeightIndex ?? 1 },
            write: { [weak owner] index in owner?.onTrackHeightChanged?(index) },
            segmentEnabled: nil, enabled: { true },
            onEdit: { [weak owner] in owner?.heightControl?.refresh() })

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)

        // The meter goes in the flexible gap, immediately left of the zoom
        // cluster, rather than last: placing it after S/M/L would shift the
        // zoom cluster and the size control 130-odd points left, and both are
        // two phases of muscle memory old. Here nothing that shipped moves at
        // any window width, because the meter carries the spacer's own
        // priority-1 hugging and compression resistance and absorbs slack up
        // to its own cap.
        //
        // It gets NO divider before it, and that is arithmetic rather than
        // taste: the row's fixed content measures 880 pt against a 900 pt
        // minimum window, one more stack gap for the meter makes 892, and a
        // divider's second gap plus its hairline would make 905 — broken
        // constraints at the minimum window, which nothing in this project
        // asserts on and no proof would catch. The meter compresses to
        // nothing and stops drawing instead (`LevelMeterView.draw`).
        let row = NSStackView(views: [
            selection, DividerView(length: 18), actions, DividerView(length: 18), snap, spacer,
            LevelMeterView(), zoomCluster(owner: owner), DividerView(length: 18), size,
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = padding
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: padding),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -padding),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return Parts(view: bar, selection: selection, snap: snap, size: size)
    }

    /// The eight actions, in the design's order. Every selector already exists
    /// on `EditorViewController` and every button dispatches through the
    /// responder chain, exactly as the old timeline toolbar did.
    ///
    /// The design lists seven; **Add Shape is the eighth and is deliberate**.
    /// Shape has no menu item anywhere in the app, so its toolbar button was
    /// the only way to reach the feature — dropping it with the rest of the
    /// window toolbar would have deleted a command, not moved one.
    private static func editActions() -> [NSView] {
        let items: [(String, String, String, Selector)] = [
            (
                "scissors", "✂", "Split (⌘T)",
                #selector(EditorViewController.splitAtPlayhead(_:))
            ),
            (
                "arrow.right.to.line", "⇥", "Trim Start to Playhead (W)",
                #selector(EditorViewController.trimStartToPlayhead(_:))
            ),
            (
                "arrow.left.to.line", "⇤", "Trim End to Playhead (E)",
                #selector(EditorViewController.trimEndToPlayhead(_:))
            ),
            (
                "delete.left", "⌫", "Ripple Delete (⌘⌫)",
                #selector(EditorViewController.rippleDeleteClips(_:))
            ),
            ("bookmark", "◆", "Add Marker (M)", #selector(EditorViewController.addMarker(_:))),
            (
                "doc.on.doc", "⧉", "Duplicate (⌘D)",
                #selector(EditorViewController.duplicateClips(_:))
            ),
            ("textformat", "Aa", "Add Text (T)", #selector(EditorViewController.addTextClip(_:))),
            (
                "square.on.circle", "▭", "Add Shape",
                #selector(EditorViewController.showAddShapeMenu(_:))
            ),
        ]
        return items.map { symbol, fallback, tooltip, action in
            GhostButton(
                symbol: symbol, fallback: fallback, caption: nil, tooltip: tooltip,
                action: action, size: actionSize, pointSize: actionPointSize,
                cornerRadius: DS.buttonRadius)
        }
    }

    /// − · slider · + · Fit. The magnifiers target the timeline directly
    /// because `EditorViewController.zoomIn(_:)` is the CANVAS zoom and the
    /// responder chain would hand them that one.
    ///
    /// Fit is not in the design's cluster, and is kept anyway: it is a real
    /// command with a menu item (⇧Z) and this button is its only one-click
    /// path.
    private static func zoomCluster(owner: TimelineView) -> NSView {
        let out = GhostButton(
            symbol: "minus.magnifyingglass", fallback: "−", caption: nil,
            tooltip: "Zoom Out", action: #selector(TimelineView.timelineZoomOut(_:)),
            size: actionSize, pointSize: 15, cornerRadius: DS.buttonRadius)
        out.target = owner
        let into = GhostButton(
            symbol: "plus.magnifyingglass", fallback: "+", caption: nil,
            tooltip: "Zoom In", action: #selector(TimelineView.timelineZoomIn(_:)),
            size: actionSize, pointSize: 15, cornerRadius: DS.buttonRadius)
        into.target = owner

        // The one raw AppKit control in the app's chrome: spec §4.4 asks for
        // a zoom SLIDER and `OptionControls.swift` (which is Rasterize's, and
        // stays in sync with it) has no slider to borrow.
        let slider = owner.zoomSlider
        slider.target = owner
        slider.action = #selector(TimelineView.zoomSliderChanged(_:))
        slider.isContinuous = true
        slider.controlSize = .small
        slider.toolTip = "Timeline Zoom"
        slider.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let fit = GhostButton(
            symbol: "arrow.left.and.right", fallback: "⇔", caption: nil,
            tooltip: "Fit Timeline (⇧Z)",
            action: #selector(EditorViewController.fitTimeline(_:)),
            size: actionSize, pointSize: 15, cornerRadius: DS.buttonRadius)

        let cluster = NSStackView(views: [out, slider, into, fit])
        cluster.orientation = .horizontal
        cluster.alignment = .centerY
        cluster.spacing = 8
        return cluster
    }
}

// MARK: - Zoom stepping

extension TimelineView {
    /// One click of the bar's magnifiers, as a fraction of the slider's whole
    /// travel — so a click and a drag move the zoom on the same log scale and
    /// the knob lands where the click left it.
    private static var zoomStep: CGFloat { 0.05 }

    @objc func timelineZoomOut(_ sender: Any?) { stepZoom(by: -Self.zoomStep) }
    @objc func timelineZoomIn(_ sender: Any?) { stepZoom(by: Self.zoomStep) }

    /// Anchored at the middle of what is on screen, which is where the slider
    /// anchors too: a zoom that kept time zero fixed would throw the visible
    /// edit off the right of the window.
    private func stepZoom(by delta: CGFloat) {
        let value = Self.sliderValue(for: layout.zoom) + delta
        setZoom(Self.zoom(forSlider: value), anchoredAt: content.visibleRect.midX)
    }
}

// MARK: - Selection block

/// The bar's left-edge identity block: a kind-tinted chip, the selected clip's
/// name, and the track and kind under it.
///
/// It is one of three views of one selection — the timeline's own outline and
/// the inspector's header are the others — so its chip, its word for a kind
/// and its tint all come from `ClipKindStyle` rather than being spelled again
/// here.
///
/// Its width is FIXED at the design's 176 pt minimum rather than growing with
/// the name: the point of the block is that the divider after it never moves,
/// so a long name truncates instead of pushing the tools sideways.
final class TimelineSelectionBlock: NSView {
    private var snapshot = ProjectSnapshot.empty
    private var selection: Set<UInt32> = []

    private static let width: CGFloat = 176
    private static let chip = NSSize(width: 8, height: 20)
    private static let gap: CGFloat = 8

    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TimelineSelectionBlock does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width, height: 30)
    }

    func update(snapshot: ProjectSnapshot, selection: Set<UInt32>) {
        self.snapshot = snapshot
        self.selection = selection
        needsDisplay = true
    }

    /// The clips the block is describing, in timeline order.
    private var clips: [ClipSnapshot] {
        snapshot.clips.filter { selection.contains($0.id) }.sorted { $0.start < $1.start }
    }

    /// Chip tint, headline and meta line for the current selection.
    ///
    /// The design covers none and one. For MANY the honest thing is the count
    /// plus whatever the clips still agree on: a shared track keeps its name
    /// and a shared kind keeps its word, and where they disagree the line says
    /// so ("3 tracks", "mixed") rather than naming one clip's and implying it
    /// holds for the rest.
    private func description() -> (tint: NSColor, name: String, meta: String) {
        let clips = self.clips
        guard let first = clips.first else {
            return (DS.borderStrong, "No selection", "")
        }
        let kinds = Set(clips.map { ClipKindStyle.name(for: $0, in: snapshot) })
        let tracks = Set(clips.map { $0.track })
        let kind = kinds.count == 1 ? ClipKindStyle.name(for: first, in: snapshot) : "mixed"
        let track =
            tracks.count == 1 ? trackName(first.track) : "\(tracks.count) tracks"
        guard clips.count > 1 else {
            return (
                ClipKindStyle.tint(for: first, in: snapshot), snapshot.name(of: first),
                "\(track) · \(kind)")
        }
        let tint = kinds.count == 1
            ? ClipKindStyle.tint(for: first, in: snapshot) : DS.borderStrong
        return (tint, "\(clips.count) clips", "\(track) · \(kind)")
    }

    /// The label a track wears in the timeline — the header column's spelling,
    /// not a second one.
    ///
    /// `set_track` accepts an EMPTY name, so `track(_:)?.name` is not enough:
    /// an unnamed track would print as nothing at all here while
    /// `TimelineHeaderView.draw` shows it as "Track 3", and the block would be
    /// naming a row the user cannot find. The number is the MODEL index + 1,
    /// which is what the header counts (0 = back), never the display row.
    private func trackName(_ id: UInt32) -> String {
        guard let index = snapshot.trackIndex(of: id) else { return "Track" }
        let name = snapshot.tracks[index].name
        return name.isEmpty ? "Track \(index + 1)" : name
    }

    override func draw(_ dirtyRect: NSRect) {
        let content = description()
        let chip = NSRect(
            x: 0, y: (bounds.height - Self.chip.height) / 2,
            width: Self.chip.width, height: Self.chip.height)
        content.tint.setFill()
        NSBezierPath(roundedRect: chip, xRadius: 2, yRadius: 2).fill()

        let textX = chip.maxX + Self.gap
        let textWidth = max(bounds.width - textX, 0)
        guard textWidth > 8 else { return }
        // The two lines are centred as a PAIR — 13 pt of name, 2 pt, 11 pt of
        // meta — so the block sits on the bar's centre line whatever height
        // the stack view hands it, and an empty meta line does not leave the
        // name floating high.
        let hasMeta = !content.meta.isEmpty
        let block: CGFloat = hasMeta ? 26 : 13
        let top = ((bounds.height - block) / 2).rounded()
        TimelineDraw.truncated(
            content.name,
            in: CGRect(x: textX, y: top, width: textWidth, height: 13),
            font: DS.sans(11, weight: .semibold), color: DS.textStrong)
        guard hasMeta else { return }
        TimelineDraw.truncated(
            content.meta,
            in: CGRect(x: textX, y: top + 15, width: textWidth, height: 11),
            font: DS.mono(9), color: DS.textFaint)
    }
}
