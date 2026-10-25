import AppKit

/// The selected clip's actions as a mini timeline (spec §11 CI-1, CI-4):
/// a header row (ACTIONS, the count, "· editing N", and Zoom to Region, Zoom
/// Back and Add Action), a lane row (the Clip chip, then the whole clip with
/// its bands by fraction, numbered in time order, and the playhead), and —
/// only while an action is selected — a detail row: Start (clip-relative),
/// Length, Curve and Remove, each an ordinary `set_action` / `remove_action`.
///
/// Built once per pane build; the pane rebuilds whenever the selected clip or
/// the selected action changes (the default `structureSignature` keys on
/// `InspectorBinding.action(_:)`), so the ids captured here are the ones on
/// screen, and every read goes fresh through them.
///
/// A band is dragged here as on the timeline (spec §11 CI-11,
/// `ActionLaneView+Drag.swift`), and the well carries the clip's hatch, fades
/// and wedges under the bands (CI-12, `ActionLaneDecor.swift`).
final class ActionLaneView: NSView, OptionControl {
    static let headerRow: CGFloat = 18, laneRow: CGFloat = 28, detailRow: CGFloat = 22
    static let chipWidth: CGFloat = 40
    static let top: CGFloat = 8
    private static let bottom: CGFloat = 9, gap: CGFloat = 6
    static let side = InspectorMetrics.inset

    let binding: InspectorBinding
    private weak var inspector: InspectorViewController?
    /// The single selected clip at build time; nil for a multi-selection.
    let clipID: UInt32?
    /// The selected action at build time.
    let actionID: UInt32?
    private let detail = NSView()
    private var controls: [any OptionControl] = []

    /// The live band drag; nil for a zero-length band, which is never dragged.
    var drag: ActionDragSession?
    /// The band under the mouse-down — what `releaseBand` selects.
    var pressed: UInt32?
    /// The band under the pointer while nothing is pressed.
    var hover: ActionBandHover? { didSet { if hover != oldValue { needsDisplay = true } } }
    /// What the cursor rects were last built from: `refresh()` invalidates
    /// them only when this changes, never on a playhead-only refresh.
    private var cursorKey:
        (clip: UInt32?, bands: [(UInt32, Ticks, Ticks)], frame: Ticks, length: Ticks)?

    init(binding: InspectorBinding, inspector: InspectorViewController?) {
        self.binding = binding
        self.inspector = inspector
        let single = binding.isSingle ? binding.primary?.id : nil
        clipID = single
        actionID = single == nil ? nil : binding.selectedAction?.id
        super.init(frame: .zero)
        wantsLayer = true
        buildButtons()
        buildDetail()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ActionLaneView does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        var height = Self.top + Self.headerRow + Self.gap + Self.laneRow + Self.bottom
        if isDetailRowVisible { height += Self.gap + Self.detailRow }
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    // MARK: Reads

    var clip: ClipSnapshot? { clipID.flatMap { binding.snapshot.clip($0) } }

    /// The captured action, while it is still the selected one.
    var action: ActionSnapshot? {
        guard let id = actionID, binding.selectedAction?.id == id else { return nil }
        return clip?.actions.first { $0.id == id }
    }

    var isDetailRowVisible: Bool { !detail.isHidden }

    /// The Clip chip is the active target when no action is selected.
    var isClipChipActive: Bool { clipID != nil && action == nil }

    // MARK: Geometry

    var laneTop: CGFloat { Self.top + Self.headerRow + Self.gap }

    var chipRect: CGRect {
        CGRect(x: Self.side, y: laneTop, width: Self.chipWidth, height: Self.laneRow)
    }

    /// The whole clip, from its start to its end.
    var laneRect: CGRect {
        let x = chipRect.maxX + 4
        return CGRect(
            x: x, y: laneTop, width: max(bounds.width - Self.side - x, 0), height: Self.laneRow)
    }

    /// Every band, in time order, by fraction of the clip — inset 4 pt top
    /// and bottom, at least 2 pt wide.
    func bandRects() -> [(id: UInt32, rect: CGRect)] {
        guard let clip = clip, clip.duration > 0 else { return [] }
        let lane = laneRect
        let span = CGFloat(clip.duration)
        return ActionBands.ordered(clip).map { action in
            let from = lane.minX + lane.width * CGFloat(action.start) / span
            let to = lane.minX + lane.width * CGFloat(action.endTime) / span
            return (
                action.id,
                CGRect(x: from, y: lane.minY + 4, width: max(to - from, 2), height: lane.height - 8)
            )
        }
    }

    // MARK: Building

    private func buildButtons() {
        let specs: [(String, String, String, Selector)] = [
            ("plus.magnifyingglass", "+", "Zoom to Region (Z)",
             #selector(EditorViewController.zoomToRegion(_:))),
            ("minus.magnifyingglass", "−", "Zoom Back",
             #selector(EditorViewController.zoomBack(_:))),
            ("plus", "+", "Add Action (⌥⌘K)",
             #selector(EditorViewController.addActionAtPlayhead(_:))),
        ]
        var trailing = trailingAnchor
        var constant = -Self.side
        for (index, spec) in specs.enumerated().reversed() {
            let button = GhostButton(
                symbol: spec.0, fallback: spec.1, caption: nil, tooltip: spec.2,
                action: #selector(buttonPressed(_:)), size: NSSize(width: 20, height: 18),
                pointSize: 13)
            button.target = self
            button.tag = index
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: topAnchor, constant: Self.top),
                button.trailingAnchor.constraint(equalTo: trailing, constant: constant),
            ])
            trailing = button.leadingAnchor
            constant = -2
        }
        commands = specs.map { $0.3 }
    }

    private var commands: [Selector] = []

    @objc private func buttonPressed(_ sender: NSButton) {
        guard commands.indices.contains(sender.tag) else { return }
        inspector?.onCommand?(commands[sender.tag])
    }

    /// Start · Length · Curve · Remove. Built only for a clip with an action
    /// selected; otherwise the row stays empty and hidden.
    private func buildDetail() {
        detail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detail)
        NSLayoutConstraint.activate([
            detail.topAnchor.constraint(
                equalTo: topAnchor, constant: laneTop + Self.laneRow + Self.gap),
            detail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.side),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.side),
            detail.heightAnchor.constraint(equalToConstant: Self.detailRow),
        ])
        guard let clipID, let actionID else { return }
        let binding = self.binding
        func current() -> ActionSnapshot? {
            binding.snapshot.clip(clipID)?.actions.first { $0.id == actionID }
        }
        func length() -> Ticks { binding.snapshot.clip(clipID)?.duration ?? 0 }
        let start = InspectorTimecodeField(
            read: { current()?.start ?? 0 },
            write: { value in
                binding.apply(
                    "Move Action",
                    [.setAction(clip: clipID, action: actionID, start: min(value, length()))])
            },
            fps: { binding.canvas.fps }, frames: { binding.canvas.timecodeFrames },
            onEdit: { binding.edited() })
        start.toolTip = "Where the action starts, from the clip's own start"
        let duration = OptionFieldControl(
            width: 58, unit: " s", decimals: 2, min: 0.01, max: 36000, quick: [0.25, 0.5, 1, 2],
            read: { ReelTime.seconds(current()?.duration ?? 0) },
            write: { value in
                let seconds = min(value, max(ReelTime.seconds(length()), 0.01))
                binding.apply(
                    "Resize Action",
                    [
                        .setAction(
                            clip: clipID, action: actionID,
                            duration: binding.frameTicks(seconds: seconds))
                    ])
            },
            enabled: { true }, onEdit: { binding.edited() })
        duration.toolTip = "How long the action takes"
        let glyph = CurveGlyphView(read: { current()?.curve ?? .linear })
        let curve = OptionPopupControl(
            width: 70, choices: Curve.allCases.map { ($0.laneName, $0) },
            read: { current()?.curve ?? .linear },
            write: { value in
                binding.apply(
                    "Action Curve", [.setAction(clip: clipID, action: actionID, curve: value)])
            },
            enabled: { true }, onEdit: { binding.edited() })
        curve.toolTip = "How the action eases from its start to its end state"
        let remove = GhostButton(
            symbol: "trash", fallback: "×", caption: nil, tooltip: "Remove this action",
            action: #selector(removePressed(_:)), size: NSSize(width: 22, height: 22),
            pointSize: 13)
        remove.target = self
        let views: [NSView] = [start, duration, glyph, curve, remove]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            detail.addSubview(view)
            view.centerYAnchor.constraint(equalTo: detail.centerYAnchor).isActive = true
        }
        curve.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            start.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            duration.leadingAnchor.constraint(equalTo: start.trailingAnchor, constant: 5),
            glyph.leadingAnchor.constraint(equalTo: duration.trailingAnchor, constant: 5),
            curve.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 3),
            curve.trailingAnchor.constraint(lessThanOrEqualTo: remove.leadingAnchor, constant: -5),
            remove.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
        ])
        controls = [start, duration, glyph, curve]
    }

    @objc private func removePressed(_ sender: Any?) {
        inspector?.onCommand?(#selector(EditorViewController.removeSelectedAction(_:)))
    }

    // MARK: Refresh

    func refresh() {
        for control in controls { control.refresh() }
        let hidden = action == nil
        if detail.isHidden != hidden {
            detail.isHidden = hidden
            invalidateIntrinsicContentSize()
        }
        needsDisplay = true
        let shown = clip  // one snapshot lookup for the two reads below
        let key = (
            clip: clipID, bands: (shown?.actions ?? []).map { ($0.id, $0.start, $0.duration) },
            frame: binding.canvas.fps.frameDuration, length: shown?.duration ?? 0)
        if let old = cursorKey, old.clip == key.clip, old.frame == key.frame,
           old.length == key.length, old.bands.elementsEqual(key.bands, by: ==) { return }
        cursorKey = key
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Mouse — the bodies are `ActionLaneView+Drag.swift`'s

    override func mouseDown(with event: NSEvent) {
        guard clipID != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if chipRect.contains(point) {
            binding.selectAction(nil)
            return
        }
        guard laneRect.contains(point) else { return }
        _ = pressBand(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        dragBand(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) { releaseBand() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        installLaneTracking()
    }

    override func mouseMoved(with event: NSEvent) { hoverMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hoverExited() }
    override func resetCursorRects() { addBandCursorRects() }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        if action != nil {
            DS.action.withAlphaComponent(0.07).setFill()
            bounds.fill()
        }
        DS.border.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        drawHeaderRow()
        guard let clip = clip else {
            TimelineDraw.label(
                "Select one clip to edit its actions.",
                in: CGRect(x: Self.side, y: laneTop + 7, width: bounds.width - 2 * Self.side,
                           height: 14),
                font: DS.sans(11), color: DS.textFaint)
            return
        }
        drawChip()
        let lane = laneRect
        DS.timelineLane.setFill()
        lane.fill()
        DS.border.setStroke()
        NSBezierPath(rect: lane.insetBy(dx: 0.5, dy: 0.5)).stroke()
        drawDecor(clip, in: lane)
        let ordered = ActionBands.ordered(clip)
        if ordered.isEmpty {
            TimelineDraw.label(
                "no actions · ⌥⌘K adds one",
                in: CGRect(x: lane.minX, y: lane.midY - 7, width: lane.width, height: 14),
                font: DS.mono(10), color: DS.textFaint, centered: true)
        }
        for (index, band) in bandRects().enumerated() where ordered.indices.contains(index) {
            let a = ordered[index]
            ActionBands.draw(
                band: band.rect, number: index + 1, label: nil, curve: a.curve,
                zoom: ActionBands.isZoom(a), selected: a.id == action?.id,
                hovered: hover?.action == a.id, level: .number)
        }
        drawDragOverlay()
        if clip.contains(binding.playhead), clip.duration > 0 {
            let fraction = CGFloat(clip.clipTime(binding.playhead)) / CGFloat(clip.duration)
            DS.playhead.setFill()
            NSRect(
                x: (lane.minX + lane.width * fraction - 0.5).rounded(), y: lane.minY + 1,
                width: 1, height: lane.height - 2
            ).fill()
        }
    }

    /// ACTIONS, the count and "· editing N" — or nothing while a drag has
    /// moved, when the HUD takes the text's place (`drawDragOverlay`).
    private func drawHeaderRow() {
        guard drag?.didMove != true else { return }
        let row = CGRect(x: Self.side, y: Self.top, width: bounds.width, height: Self.headerRow)
        let title = DS.microLabel("Actions")
        let titleSize = title.size()
        title.draw(at: NSPoint(x: row.minX, y: row.midY - titleSize.height / 2))
        var x = row.minX + ceil(titleSize.width) + 6
        guard let clip = clip else { return }
        let count = clip.actions.isEmpty ? "none" : "\(clip.actions.count)"
        x = drawMono(count, at: x, row: row, color: DS.textFaint)
        if let action = action,
            let index = ActionBands.ordered(clip).firstIndex(where: { $0.id == action.id })
        {
            _ = drawMono("· editing \(index + 1)", at: x + 4, row: row, color: DS.action)
        }
    }

    private func drawMono(_ text: String, at x: CGFloat, row: CGRect, color: NSColor) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: DS.mono(10), .foregroundColor: color,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: x, y: row.midY - size.height / 2), withAttributes: attributes)
        return x + ceil(size.width)
    }

    private func drawChip() {
        let chip = chipRect
        let active = isClipChipActive
        (active ? DS.selectionFill : NSColor.controlBackgroundColor).setFill()
        chip.fill()
        (active ? DS.accent : DS.border).setStroke()
        NSBezierPath(rect: chip.insetBy(dx: 0.5, dy: 0.5)).stroke()
        TimelineDraw.label(
            "Clip", in: CGRect(x: chip.minX, y: chip.midY - 7, width: chip.width, height: 14),
            font: DS.sans(11, weight: .semibold),
            color: active ? DS.textStrong : DS.textMuted, centered: true)
    }
}
