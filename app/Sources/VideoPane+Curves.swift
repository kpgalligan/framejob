import AppKit

/// The Color sub-tab's **Curves** section (spec §11 GR-12, grading-2 G2-3):
/// the channel picker, the curve plot and the selected point's In and Out
/// fields with its Delete button, in one row (`CurvesView`). The picker's
/// Hue and Sat cells edit the hue curves (spec §11 GR-32) in the same plot,
/// in their own units.
///
/// Every write sends the edited channel's WHOLE list (a list replaces, GR-12)
/// to every selected clip through `binding.ops(video:)`, so it lands on an
/// action's end when one is selected, a count change included (spec §11
/// GR-34: two curves of different counts blend). A drag is the live trio and
/// every other edit one commit, each one undo step named "Curves". The row
/// never depends on a value, so a live drag never rebuilds the pane, and it
/// has one row mark and one mixed badge for the whole `video.curves` key
/// (CI-7, CI-9).
extension VideoPane {
    // MARK: Curves

    func curvesSection(_ state: CurveEditorState) -> InspectorSection {
        let binding = self.binding
        func curves() -> ColorCurves { binding.videoProps.curves }
        func ops(_ patch: ColorCurvesPatch) -> [ReelOp] {
            binding.ops(video: VideoPatch(curves: patch))
        }
        let view = CurvesView(binding: binding, state: state, curves: curves, ops: ops)
        let row = inspectorRow(
            nil, [view], mixed: { binding.mixedVideo { $0.curves } }, binding: binding,
            writes: ops(.reset),
            default: InspectorRowDefault(
                name: "Curves", differs: { !curves().isIdentity },
                ops: { [weak binding] in binding?.curvesReset(CurveChannel.allCases) ?? [] }))
        let gutter = row.gutter
        view.editor.keyed = { [weak gutter] in gutter?.isKeyed == true }
        return InspectorSection(
            id: "video.curves", title: "Curves",
            summary: { curves().isIdentity ? "neutral" : "adjusted" },
            reset: { [weak view] in view?.reset(CurveChannel.allCases) },
            defaultExpanded: false,
            rows: [row])
    }
}

extension InspectorBinding {
    /// Reset's ops for `channels` (GR-12, GR-32): a clip outside an action
    /// has them removed from its base (`null`); a clip inside one has each
    /// channel whose edited curve is not its domain's identity written to the
    /// end AS that identity, which an end keeps as "animate to neutral" — a
    /// `null` there would only stop animating it. None when nothing would
    /// change.
    func curvesReset(_ channels: [CurveChannel]) -> [ReelOp] {
        var ops: [ReelOp] = []
        var bases: [UInt32] = []
        for clip in videoClips {
            guard action(clip) != nil else {
                bases.append(clip.id)
                continue
            }
            let named = channels.filter { !$0.domain.isIdentity(editedCurve(clip, $0)) }
            if !named.isEmpty {
                ops += self.ops(video: VideoPatch(curves: .neutral(named)), for: clip)
            }
        }
        if !bases.isEmpty {
            var removed = ColorCurvesPatch()
            for channel in channels { removed = removed.setting(channel, .some(nil)) }
            ops.insert(.setVideo(clips: bases, patch: VideoPatch(curves: removed)), at: 0)
        }
        return ops
    }
}

/// What the Curves section remembers between rebuilds, per window (owned by
/// `ClipPane`, never saved): the channel being edited (Master when a window
/// opens), the selected point's index, and `working` — an edited list not
/// yet written, held while the channel reads back as the identity of a
/// different count (a point just added to a straight channel, which writes
/// nothing until it first moves).
final class CurveEditorState {
    var channel: CurveChannel = .master
    var selected: Int?
    var working: [CurvePoint]?

    /// A channel change, Esc, a selection change: no point, no working list.
    func clear() {
        selected = nil
        working = nil
    }
}

/// The Curves row: the channel picker over the plot, square, the row's width
/// less nothing (the row's gutter is already off it) and never past
/// `maxPlot` — about 254 pt at the default pane, 230 at the narrowest — then
/// the selected point's In and Out (on a tone curve 3 decimals, 0–1; on a
/// hue curve In in degrees and Out in degrees or ×; blank and disabled with
/// no point) and Delete. Hugging 1: the row's stretchy element
/// (`inspectorRow` gives it no trailing spacer).
final class CurvesView: NSView {
    static let maxPlot: CGFloat = 300
    let editor: CurveEditorView
    let picker: CurveChannelPicker
    private let state: CurveEditorState
    private weak var binding: InspectorBinding?

    init(
        binding: InspectorBinding, state: CurveEditorState,
        curves: @escaping () -> ColorCurves, ops: @escaping (ColorCurvesPatch) -> [ReelOp]
    ) {
        self.state = state
        self.binding = binding
        editor = CurveEditorView(
            state: state, read: { curves().points($0) },
            start: { [weak binding] channel in
                guard let binding, binding.selectedAction != nil else { return nil }
                return binding.at(.start) { curves().points(channel) }
            },
            write: { [weak binding] list in
                binding?.liveUpdate(ops(.channel(state.channel, list)))
            },
            begin: { [weak binding] in binding?.liveBegin() },
            end: { [weak binding] in binding?.liveEnd("Curves") },
            commit: { [weak binding] list in
                binding?.apply("Curves", ops(.channel(state.channel, list)))
            })
        picker = CurveChannelPicker(state: state, curves: curves)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        picker.onSelect = { [weak self] channel in self?.choose(channel) }
        picker.onReset = { [weak self] channel in self?.reset([channel]) }

        let editor = self.editor
        let inField = CurvePointField(
            axis: .x, domain: { state.channel.domain },
            read: { [weak editor] in editor?.selectedPoint?.x },
            write: { [weak editor] value in editor?.place(x: value) },
            onEdit: { [weak binding] in binding?.edited() })
        let outField = CurvePointField(
            axis: .y, domain: { state.channel.domain },
            read: { [weak editor] in editor?.selectedPoint?.y },
            write: { [weak editor] value in editor?.place(y: value) },
            onEdit: { [weak binding] in binding?.edited() })
        let delete = OptionButtonControl(
            title: "Delete", action: { [weak editor] in editor?.deleteSelected() },
            enabled: { [weak editor] in editor?.canDelete == true },
            onEdit: { [weak binding] in binding?.edited() })
        let fields = NSStackView(views: [
            InspectorRowLabel("In"), inField, InspectorRowLabel("Out"), outField, NSView(), delete,
        ])
        fields.orientation = .horizontal
        fields.spacing = 6
        editor.onSelection = { [weak fields, weak picker] in
            if let fields { refreshOptionControls(in: fields) }
            picker?.needsDisplay = true
        }

        for view in [picker, editor, fields] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // The plot is the row's width, square, never past `maxPlot`; the fill
        // is a lower priority than the cap so a wide pane stops at 300.
        let fill = editor.widthAnchor.constraint(equalTo: widthAnchor)
        fill.priority = NSLayoutConstraint.Priority(750)
        NSLayoutConstraint.activate([
            // The picker and the point row line up with the plot's frame,
            // drawn `inset` − 0.5 inside the editor's bounds.
            picker.topAnchor.constraint(equalTo: topAnchor),
            picker.leadingAnchor.constraint(equalTo: editor.leadingAnchor, constant: 3),
            picker.trailingAnchor.constraint(equalTo: editor.trailingAnchor, constant: -3),
            picker.heightAnchor.constraint(equalToConstant: CurveChannelPicker.height),
            editor.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 6),
            editor.leadingAnchor.constraint(equalTo: leadingAnchor),
            editor.heightAnchor.constraint(equalTo: editor.widthAnchor),
            editor.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxPlot),
            editor.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            fill,
            fields.topAnchor.constraint(equalTo: editor.bottomAnchor, constant: 6),
            fields.leadingAnchor.constraint(equalTo: editor.leadingAnchor, constant: 3),
            fields.trailingAnchor.constraint(equalTo: editor.trailingAnchor, constant: -3),
            fields.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CurvesView does not support NSCoder")
    }

    /// A picker cell: the channel is edited from now on, with no point.
    func choose(_ channel: CurveChannel) {
        guard channel != state.channel else { return }
        editor.deselect()
        state.channel = channel
        binding?.edited()
    }

    /// The section's Reset (all six) or a cell's "Reset <Channel>": one
    /// commit "Curves" of `InspectorBinding.curvesReset`, nothing when it
    /// would change nothing.
    func reset(_ channels: [CurveChannel]) {
        editor.deselect()
        guard let binding else { return }
        let ops = binding.curvesReset(channels)
        guard !ops.isEmpty else { return }
        binding.apply("Curves", ops)
    }
}

/// A point's axis: In is x, Out is y.
enum CurveAxis { case x, y }

/// One of the point's two fields: an `OptionFieldControl` per domain (spec
/// §11 GR-32), each fixed at its build with that domain's unit, decimals and
/// range for its axis — tone 3 decimals 0–1; In on a hue curve "°" 1 decimal
/// 0–359.9; Out "°" 1 decimal −180…180 on Hue, "×" 2 decimals 0–2 on Sat —
/// the one matching `domain()` shown while a point is selected, and a blank,
/// disabled box of the same size while none is.
final class CurvePointField: NSView, OptionControl {
    private let fields: [(domain: CurveDomain, control: OptionFieldControl)]
    private let blank = NSView()
    private let read: () -> Double?
    private let domain: () -> CurveDomain

    init(axis: CurveAxis, domain: @escaping () -> CurveDomain,
         read: @escaping () -> Double?, write: @escaping (Double) -> Void,
         onEdit: @escaping () -> Void) {
        self.read = read
        self.domain = domain
        fields = [CurveDomain.tone, .hueShift, .hueGain].map { d in
            let (unit, decimals) = Self.format(d, axis)
            let low = axis == .x ? d.lower.x : d.lower.y
            let high = axis == .x ? d.upper.x : d.upper.y
            let control = OptionFieldControl(
                width: InspectorMetrics.fieldWidth, unit: unit, decimals: decimals, min: low,
                max: high, read: { read() ?? 0 }, write: write,
                enabled: { read() != nil && domain() == d }, onEdit: onEdit)
            return (d, control)
        }
        super.init(frame: .zero)
        blank.wantsLayer = true
        blank.layer?.borderWidth = 1
        blank.alphaValue = 0.42
        for view in fields.map(\.control) + [blank] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CurvePointField does not support NSCoder")
    }

    /// A domain's unit and decimals on `axis`.
    private static func format(_ domain: CurveDomain, _ axis: CurveAxis) -> (String, Int) {
        switch (domain, axis) {
        case (.tone, _): return ("", 3)
        case (_, .x), (.hueShift, .y): return ("°", 1)
        case (.hueGain, .y): return ("×", 2)
        }
    }

    override var intrinsicContentSize: NSSize { fields[0].control.intrinsicContentSize }

    func refresh() {
        let active = read() != nil
        let shown = domain()
        for (d, control) in fields {
            control.isHidden = !(active && d == shown)
            control.refresh()
        }
        blank.isHidden = active
        effectiveAppearance.performAsCurrentDrawingAppearance {
            blank.layer?.borderColor = DS.border.cgColor
            blank.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }
}

/// The channel picker (owner choice 5): six equal text cells, Master · Red
/// · Green · Blue · Hue · Sat (spec §11 GR-32), the chosen one framed and
/// labelled in its channel's tint, a 3 pt dot under each channel that is not
/// its domain's identity, and "Reset <Channel>" in each cell's context menu
/// (choice 7). The labels are 10 pt (`labelSize`).
final class CurveChannelPicker: NSView, OptionControl {
    static let height: CGFloat = 24
    /// The cells' label size (GR-32 owner choice 3: 11 pt while every label
    /// fits its cell less 2 pt at the 230 pt plot, else 10). Six cells at 11
    /// pt leave "Master" 37.9 pt of a 38 pt cell (`curves_probe.swift` P19,
    /// T4-2), so 10.
    static let labelSize: CGFloat = 10
    private let state: CurveEditorState
    private let curves: () -> ColorCurves
    var onSelect: (CurveChannel) -> Void = { _ in }
    var onReset: (CurveChannel) -> Void = { _ in }

    init(state: CurveEditorState, curves: @escaping () -> ColorCurves) {
        self.state = state
        self.curves = curves
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CurveChannelPicker does not support NSCoder")
    }

    func refresh() { needsDisplay = true }

    /// Equal cells sharing their 1 pt borders.
    func cellRect(_ index: Int) -> NSRect {
        let count = CGFloat(CurveChannel.allCases.count)
        let step = (bounds.width - 1) / count
        let left = (CGFloat(index) * step).rounded()
        let right = (CGFloat(index + 1) * step).rounded() + 1
        return NSRect(x: left, y: 0, width: right - left, height: bounds.height)
    }

    private func channel(at event: NSEvent) -> CurveChannel? {
        let point = convert(event.locationInWindow, from: nil)
        return CurveChannel.allCases.indices.first { cellRect($0).contains(point) }
            .map { CurveChannel.allCases[$0] }
    }

    override func mouseDown(with event: NSEvent) {
        if let channel = channel(at: event) { onSelect(channel) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let channel = channel(at: event) else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Reset \(channel.title)", action: #selector(resetPicked(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = channel.rawValue
        item.isEnabled = !channel.domain.isIdentity(curves().points(channel))
        menu.autoenablesItems = false
        menu.addItem(item)
        return menu
    }

    @objc private func resetPicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let channel = CurveChannel(rawValue: raw)
        else { return }
        onReset(channel)
    }

    override func draw(_ dirtyRect: NSRect) {
        let all = CurveChannel.allCases
        let order = all.indices.filter { all[$0] != state.channel }
            + all.indices.filter { all[$0] == state.channel }
        let current = curves()
        for index in order {
            let channel = all[index]
            let rect = cellRect(index)
            let chosen = channel == state.channel
            NSColor.controlBackgroundColor.setFill()
            rect.fill()
            (chosen ? channel.tint : DS.border).setStroke()
            NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
            let label = NSAttributedString(
                string: channel.title,
                attributes: [
                    .font: DS.sans(Self.labelSize, weight: .semibold),
                    .foregroundColor: chosen ? channel.tint : DS.textMuted,
                ])
            let size = label.size()
            label.draw(at: NSPoint(x: (rect.midX - size.width / 2).rounded(),
                                   y: rect.midY - size.height / 2 + 2))
            if !channel.domain.isIdentity(current.points(channel)) {
                channel.tint.setFill()
                NSRect(x: (rect.midX - 1.5).rounded(), y: rect.minY + 3, width: 3, height: 3).fill()
            }
        }
    }
}
