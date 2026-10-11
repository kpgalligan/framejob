import AppKit

// MARK: - Row builders

/// One labelled row: the mark gutter, the leading label column, then the
/// controls, then the mixed badge when the selection disagrees. Every pane
/// builds rows through here so the label column lines up down the whole
/// inspector.
///
/// The gutter (spec §11 CI-7) is on EVERY row, blank when the row has
/// nothing to say, and no spacing follows it, so every control column sits
/// exactly `InspectorMetrics.markGutter` right of where it was. `writes` and
/// `follows` are the ops the row writes and the ones whose keys it only
/// follows; `binding` is what the gutter asks about the selected action. A
/// popup, a checkbox or a segmented control is DISCRETE: keyed, it switches
/// at the action's end, and the row says "at end"; `discrete: true` says so
/// for a row whose control is none of those (a string field or text area,
/// which switches at the end too). `default` is the row's
/// reset (spec §11 CI-9): a row without one has no reset item in its menu
/// and counts nothing toward its section's `differs`.
func inspectorRow(
    _ label: String?, _ controls: [NSView], mixed: (() -> Bool)? = nil,
    binding: InspectorBinding? = nil, writes: [ReelOp] = [], follows: [ReelOp] = [],
    discrete forced: Bool = false, default rowDefault: InspectorRowDefault? = nil
) -> InspectorRowView {
    let field = label.map { InspectorRowLabel($0) }
    let discrete = forced || controls.contains {
        $0 is OptionPopupControl || $0 is OptionCheckboxControl || $0 is OptionSegmentedControl
    }
    let gutter = InspectorMarkGutter(
        binding: binding, writes: writes, follows: follows, label: field, controls: controls,
        discrete: discrete, default: rowDefault)
    // The CONTROL gives way, never the tag (G-34 (l), O8): the row's widest
    // popup keeps its width only below the one-line tag's compression
    // resistance (750), so a keyed row short of room — Font ▸ Family's 150,
    // a filter's kind — narrows that popup to show "at end" whole. With no
    // tag showing the row has room and the popup is its full width. A row
    // with no popup gives its widest checkbox the same 749, so a module's
    // boolean with a long label narrows and the tag stays whole; the checkbox
    // draws its title from a point, so it is clipped to its own bounds rather
    // than drawing on under the tag.
    let popups: [NSView] = controls.compactMap { $0 as? OptionPopupControl }
    let checks: [NSView] = controls.compactMap { $0 as? OptionCheckboxControl }
    if let narrowing = (popups.isEmpty ? checks : popups)
        .max(by: { $0.intrinsicContentSize.width < $1.intrinsicContentSize.width })
    {
        narrowing.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(749), for: .horizontal)
        if narrowing is OptionCheckboxControl { narrowing.clipsToBounds = true }
    }
    var views: [NSView] = [gutter]
    if let field {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: InspectorMetrics.labelWidth).isActive = true
        views.append(field)
    }
    views.append(contentsOf: controls)
    views.append(
        InspectorRowTag(
            text: { [weak gutter] in gutter?.mark == .keyedAtEnd ? "at end" : nil },
            color: DS.action))
    if let mixed = mixed { views.append(InspectorMixedBadge(mixed: mixed)) }
    // A slider is the row's stretchy element, so a row that has one gets NO
    // trailing spacer — two views hugging at the same priority would split
    // the free space and leave the slider half as wide as it should be. The
    // Content area, the Wheels row (GR-11), the Curves row (GR-12) and a
    // qualifier range's strip (GR-13) stretch the same way.
    if !controls.contains(where: {
        $0 is InspectorSliderControl || $0 is InspectorTextArea || $0 is ColorWheelsView
            || $0 is CurvesView || $0 is RangeStripControl
    }) {
        let trailing = NSView()
        trailing.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        trailing.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)
        views.append(trailing)
    }
    return InspectorRowView(views: views, gutter: gutter)
}

/// A row of buttons with no label column — "Fit to Canvas / Fill Canvas",
/// the text presets, the Add Action footer.
func inspectorButtonRow(_ buttons: [NSView]) -> NSView {
    let trailing = NSView()
    trailing.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
    let row = NSStackView(views: buttons + [trailing])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 6
    return row
}

/// A read-only value at the end of a row ("−6.0 dB", "00:00:04:12").
func inspectorReadout(width: CGFloat = 96, _ read: @escaping () -> String) -> OptionDisplayControl {
    OptionDisplayControl(width: width, read: read, enabled: { true })
}

/// A number bound to one property: a slider that drags LIVE beside a field
/// that commits once (spec §4.3). `ops` turns a value into the edit — the
/// binding decides whether that is a `set_video` or an action's end patch, so
/// no pane repeats that rule.
///
/// The four typed builders derive the row's default from `read` and `ops`
/// (spec §11 CI-9); `resets: false` is for a row whose `read` bypasses the
/// props readers, where a derived default could never differ.
func inspectorValueRow(
    _ label: String, _ binding: InspectorBinding, name: String, unit: String = "",
    decimals: Int = 0, min lower: Double, max upper: Double, quick: [Double] = [],
    slider: Bool = true, width: CGFloat = InspectorMetrics.fieldWidth,
    read: @escaping () -> Double, ops: @escaping (Double) -> [ReelOp],
    mixed: (() -> Bool)? = nil, enabled: @escaping () -> Bool = { true },
    resets: Bool = true
) -> NSView {
    var controls: [NSView] = []
    let track = slider ? InspectorSliderControl(
        min: lower, max: upper, read: read,
        write: { [weak binding] value in binding?.liveUpdate(ops(value)) },
        begin: { [weak binding] in binding?.liveBegin() },
        end: { [weak binding] in binding?.liveEnd(name) },
        enabled: enabled,
        start: { [weak binding] in binding?.startValue(read) },
        now: { [weak binding] in binding?.nowValue(read) }) : nil
    if let track { controls.append(track) }
    controls.append(
        OptionFieldControl(
            width: width, unit: unit, decimals: decimals, min: lower, max: upper, quick: quick,
            read: read,
            write: { [weak binding] value in binding?.apply(name, ops(value)) },
            enabled: enabled,
            onEdit: { [weak binding] in binding?.edited() }))
    // A field-only row has no rail to put the playhead's tick on, so it says
    // the value in words when it differs by more than half a display unit.
    if !slider {
        controls.append(
            InspectorRowTag(
                text: { [weak binding] in
                    guard let value = binding?.nowValue(read),
                          abs(value - read()) > 0.5 * pow(10, -Double(decimals))
                    else { return nil }
                    return "now " + String(format: "%.\(decimals)f", value) + unit
                },
                color: DS.playhead))
    }
    let row = inspectorRow(
        label, controls, mixed: mixed, binding: binding, writes: ops(read()),
        default: resets ? .derived(binding, name: name, read: read, ops: ops) : nil)
    let gutter = row.gutter
    track?.keyed = { [weak gutter] in gutter?.isKeyed == true }
    return row
}

/// A boolean bound to one property. The checkbox carries its own label, so
/// the row's label column stays empty and the controls line up under the
/// numbers above them.
func inspectorCheckRow(
    _ label: String, _ binding: InspectorBinding, name: String, read: @escaping () -> Bool,
    ops: @escaping (Bool) -> [ReelOp], mixed: (() -> Bool)? = nil,
    enabled: @escaping () -> Bool = { true }, resets: Bool = true
) -> NSView {
    let check = OptionCheckboxControl(
        label: label, read: read,
        write: { [weak binding] value in binding?.apply(name, ops(value)) },
        enabled: enabled,
        onEdit: { [weak binding] in binding?.edited() })
    return inspectorRow(
        nil, [check], mixed: mixed, binding: binding, writes: ops(read()),
        default: resets ? .derived(binding, name: name, read: read, ops: ops) : nil)
}

/// A colour well bound to one property, with the unchanged-colour guard the
/// continuous colour panel needs (`changedRGBA`).
func inspectorColorRow(
    _ label: String, _ binding: InspectorBinding, name: String, read: @escaping () -> RGBA,
    ops: @escaping (RGBA) -> [ReelOp], mixed: (() -> Bool)? = nil,
    enabled: @escaping () -> Bool = { true }, resets: Bool = true
) -> NSView {
    let swatch = OptionSwatchControl(
        read: { read().nsColor },
        write: { [weak binding] color in
            guard let next = changedRGBA(color, from: read()) else { return }
            binding?.apply(name, ops(next))
        },
        enabled: enabled,
        onEdit: {})
    return inspectorRow(
        label, [swatch], mixed: mixed, binding: binding, writes: ops(read()),
        default: resets ? .derived(binding, name: name, read: read, ops: ops) : nil)
}

/// A popup bound to one property.
func inspectorPopupRow(
    _ label: String, _ binding: InspectorBinding, name: String, items: [String],
    width: CGFloat = InspectorMetrics.popupWidth, read: @escaping () -> Int,
    ops: @escaping (Int) -> [ReelOp], mixed: (() -> Bool)? = nil,
    enabled: @escaping () -> Bool = { true }, resets: Bool = true
) -> NSView {
    let popup = OptionPopupControl(
        width: width, items: items, read: read,
        write: { [weak binding] index in binding?.apply(name, ops(index)) },
        enabled: enabled,
        onEdit: { [weak binding] in binding?.edited() })
    return inspectorRow(
        label, [popup], mixed: mixed, binding: binding, writes: ops(read()),
        default: resets ? .derived(binding, name: name, read: read, ops: ops) : nil)
}

/// A button that runs one edit.
func inspectorButton(
    _ title: String, _ binding: InspectorBinding, name: String,
    ops: @escaping () -> [ReelOp], enabled: @escaping () -> Bool = { true }
) -> OptionButtonControl {
    OptionButtonControl(
        title: title, action: { [weak binding] in binding?.apply(name, ops()) },
        enabled: enabled, onEdit: {})
}

/// The Shadow group, shared by the Video, Text and Shape panes because all
/// three write the SAME field — `video.shadow` (§4.3 lists it once under
/// Video and refers to it from the other two).
///
/// Every control writes a WHOLE `ShadowProps`: the patch replaces the object,
/// so each edit re-sends the other four values as they stand.
func inspectorShadowSection(_ binding: InspectorBinding) -> InspectorSection {
    func current() -> ShadowProps { binding.videoProps.shadow ?? ShadowProps() }
    func ops(_ next: ShadowProps) -> [ReelOp] { binding.ops(video: VideoPatch(shadow: .some(next))) }
    func on() -> Bool { binding.videoProps.shadow != nil }

    let toggle = inspectorCheckRow(
        "Drop shadow", binding, name: "Shadow",
        read: on,
        ops: { value in
            binding.ops(video: VideoPatch(shadow: value ? .some(ShadowProps()) : .some(nil)))
        },
        mixed: { binding.mixedVideo { $0.shadow != nil } })

    return InspectorSection(
        id: "video.shadow", title: "Shadow",
        summary: { on() ? String(format: "%.0f px", current().blur) : "off" },
        reset: { binding.apply("Shadow", video: VideoPatch(shadow: .some(nil))) },
        defaultExpanded: false,
        rows: [
            toggle,
            inspectorColorRow(
                "Color", binding, name: "Shadow Color", read: { current().color },
                ops: { color in
                    let s = current()
                    return ops(
                        ShadowProps(
                            color: color, opacity: s.opacity, blur: s.blur, angle: s.angle,
                            distance: s.distance))
                },
                mixed: { binding.mixedVideo { $0.shadow?.color } },
                enabled: on),
            inspectorValueRow(
                "Opacity", binding, name: "Shadow Opacity", unit: "%", decimals: 0, min: 0,
                max: 100, quick: [0, 25, 50, 75, 100],
                read: { current().opacity * 100 },
                ops: { value in
                    let s = current()
                    return ops(
                        ShadowProps(
                            color: s.color, opacity: value / 100, blur: s.blur, angle: s.angle,
                            distance: s.distance))
                },
                mixed: { binding.mixedVideo { $0.shadow?.opacity } },
                enabled: on),
            inspectorValueRow(
                "Blur", binding, name: "Shadow Blur", unit: " px", decimals: 0, min: 0, max: 200,
                quick: [0, 4, 8, 12, 24, 48],
                read: { current().blur },
                ops: { value in
                    let s = current()
                    return ops(
                        ShadowProps(
                            color: s.color, opacity: s.opacity, blur: value, angle: s.angle,
                            distance: s.distance))
                },
                mixed: { binding.mixedVideo { $0.shadow?.blur } },
                enabled: on),
            inspectorValueRow(
                "Angle", binding, name: "Shadow Angle", unit: "°", decimals: 0, min: 0, max: 360,
                quick: [0, 45, 90, 135, 180, 225, 270, 315],
                read: { current().angle },
                ops: { value in
                    let s = current()
                    return ops(
                        ShadowProps(
                            color: s.color, opacity: s.opacity, blur: s.blur, angle: value,
                            distance: s.distance))
                },
                mixed: { binding.mixedVideo { $0.shadow?.angle } },
                enabled: on),
            inspectorValueRow(
                "Distance", binding, name: "Shadow Distance", unit: " px", decimals: 0, min: 0,
                max: 200, quick: [0, 4, 8, 16, 32],
                read: { current().distance },
                ops: { value in
                    let s = current()
                    return ops(
                        ShadowProps(
                            color: s.color, opacity: s.opacity, blur: s.blur, angle: s.angle,
                            distance: value))
                },
                mixed: { binding.mixedVideo { $0.shadow?.distance } },
                enabled: on),
        ])
}

/// The colour as the model's RGBA, or nil when it already matches `current`.
///
/// **Pitfall:** the shared colour panel is continuous, so a drag inside it
/// calls a swatch's writer on every mouse-moved event — including with the
/// colour it already has. Without this guard the document would answer an
/// unchanged edit with a refusal beep on every one of them.
func changedRGBA(_ color: NSColor, from current: RGBA) -> RGBA? {
    let next = color.rgbaComponents
    guard next.count == current.count else { return next }
    for (a, b) in zip(next, current) where abs(a - b) > 0.001 { return next }
    return nil
}
