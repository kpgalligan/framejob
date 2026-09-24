import AppKit

/// The Clip tab's SHAPE sections (spec §4.3): kind, stroke, fill, gradient,
/// arrowheads and corner radius.
///
/// **This pane is never shown**: since the six tabs became three it is a
/// factory `ClipPane` holds and calls, right after Transform, when EVERY
/// selected clip is a shape clip. The shared Shadow group is not in the list
/// any more — it writes `video.shadow`, so the Clip tab carries it once, in
/// the effects group.
///
/// Shapes are described, never rasterized, in the model (§11), so every
/// control here is one `set_shape` patch — and unlike Video/Audio/Text there
/// is no action form, because §5.4's patch covers those three only.
final class ShapePane: InspectorPaneView {
    /// Whether the shape sections apply: they write `set_shape`, which errors
    /// on any other kind, so a mixed selection gets none of them.
    var allShape: Bool {
        !binding.clips.isEmpty && binding.shapeClips.count == binding.clips.count
    }

    /// The kind decides which controls mean anything (a line has no fill, a
    /// box has no endpoints), so it belongs in the rebuild signature — and so
    /// does the number of gradient stops, because that is a number of ROWS.
    /// `-1` for "no gradient at all" rather than 0: a gradient the core would
    /// refuse for having no stops is still a different panel from none.
    override var structureSignature: String {
        super.structureSignature + "|" + binding.shapeProps.kind.rawValue + "|"
            + "\(binding.shapeProps.gradient?.stops.count ?? -1)"
    }

    // MARK: Kind and box

    func shapeSection() -> InspectorSection {
        let binding = self.binding
        let kinds = ShapeKind.allCases
        return InspectorSection(
            id: "shape.kind", title: "Shape",
            summary: { binding.shapeProps.kind.displayName.lowercased() },
            reset: { binding.apply("Shape", shape: ShapePatch(radius: 0)) },
            differs: { binding.shapeProps.radius != 0 },
            rows: [
                inspectorPopupRow(
                    "Kind", binding, name: "Shape Kind", items: kinds.map { $0.displayName },
                    read: { kinds.firstIndex(of: binding.shapeProps.kind) ?? 0 },
                    ops: { index in
                        guard kinds.indices.contains(index) else { return [] }
                        return binding.ops(shape: ShapePatch(kind: kinds[index]))
                    },
                    mixed: { binding.mixedShape { $0.kind } }),
                inspectorValueRow(
                    "Width", binding, name: "Shape Size", unit: " px", decimals: 0, min: 1,
                    max: 20000, slider: false,
                    read: { binding.shapeProps.width },
                    ops: { binding.ops(shape: ShapePatch(width: $0)) },
                    mixed: { binding.mixedShape { $0.width } }),
                inspectorValueRow(
                    "Height", binding, name: "Shape Size", unit: " px", decimals: 0, min: 1,
                    max: 20000, slider: false,
                    read: { binding.shapeProps.height },
                    ops: { binding.ops(shape: ShapePatch(height: $0)) },
                    mixed: { binding.mixedShape { $0.height } }),
                inspectorValueRow(
                    "Corner radius", binding, name: "Shape Radius", unit: " px", decimals: 0,
                    min: 0, max: 2000, quick: [0, 4, 8, 16, 32, 64],
                    read: { binding.shapeProps.radius },
                    ops: { binding.ops(shape: ShapePatch(radius: $0)) },
                    mixed: { binding.mixedShape { $0.radius } },
                    // A radius only rounds a rectangle (§5.2).
                    enabled: { binding.shapeProps.kind == .rectangle }),
            ])
    }

    // MARK: Stroke

    func strokeSection() -> InspectorSection {
        let binding = self.binding
        func current() -> StrokeProps { binding.shapeProps.stroke ?? StrokeProps() }
        func on() -> Bool { binding.shapeProps.stroke != nil }
        return InspectorSection(
            id: "shape.stroke", title: "Stroke",
            summary: { on() ? String(format: "%.1f px", current().width) : "off" },
            reset: { binding.apply("Stroke", shape: ShapePatch(stroke: .some(StrokeProps()))) },
            differs: { binding.shapeProps.stroke.map { $0 != StrokeProps() } ?? false },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Stroke", binding, name: "Stroke", read: on,
                    ops: { value in
                        binding.ops(
                            shape: ShapePatch(stroke: value ? .some(StrokeProps()) : .some(nil)))
                    },
                    mixed: { binding.mixedShape { $0.stroke != nil } }),
                inspectorValueRow(
                    "Width", binding, name: "Stroke Width", unit: " px", decimals: 1, min: 0.5,
                    max: 200, quick: [1, 2, 4, 6, 12, 24],
                    read: { current().width },
                    ops: { value in
                        binding.ops(
                            shape: ShapePatch(
                                stroke: .some(StrokeProps(width: value, color: current().color))))
                    },
                    enabled: on),
                inspectorColorRow(
                    "Color", binding, name: "Stroke Color", read: { current().color },
                    ops: { color in
                        binding.ops(
                            shape: ShapePatch(
                                stroke: .some(StrokeProps(width: current().width, color: color))))
                    },
                    enabled: on),
            ])
    }

    // MARK: Fill

    /// The fill's opacity IS its alpha channel — the model has one colour per
    /// fill, not a colour plus an opacity — so the slider rewrites the fourth
    /// component and leaves the other three alone.
    func fillSection() -> InspectorSection {
        let binding = self.binding
        func current() -> RGBA { binding.shapeProps.fill ?? [1, 1, 1, 1] }
        func on() -> Bool { binding.shapeProps.fill != nil }
        func alpha() -> Double { current().count >= 4 ? current()[3] : 1 }
        return InspectorSection(
            id: "shape.fill", title: "Fill",
            summary: { on() ? String(format: "%.0f%%", alpha() * 100) : "off" },
            reset: { binding.apply("Fill", shape: ShapePatch(fill: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Fill", binding, name: "Fill", read: on,
                    ops: { value in
                        binding.ops(shape: ShapePatch(fill: value ? .some([1, 1, 1, 1]) : .some(nil)))
                    },
                    mixed: { binding.mixedShape { $0.fill != nil } }),
                inspectorColorRow(
                    "Color", binding, name: "Fill Color", read: current,
                    ops: { binding.ops(shape: ShapePatch(fill: .some($0))) },
                    enabled: on),
                inspectorValueRow(
                    "Opacity", binding, name: "Fill Opacity", unit: "%", decimals: 0, min: 0,
                    max: 100, quick: [0, 25, 50, 75, 100],
                    read: { alpha() * 100 },
                    ops: { value in
                        var color = current()
                        while color.count < 4 { color.append(1) }
                        color[3] = value / 100
                        return binding.ops(shape: ShapePatch(fill: .some(color)))
                    },
                    enabled: on),
            ])
    }

    // MARK: Gradient

    /// The gradient fill (§5.2's `shape.gradient`, format version 6): a
    /// geometry, an angle and the stops, all of it one `set_shape` patch.
    ///
    /// Three rules out of the schema show up here as UI, and none of them is
    /// this file's invention:
    ///
    ///  - **Every write sends the WHOLE object.** The core MERGES a nested
    ///    object into a stored one key by key (§5.2), but a stored `null` is
    ///    not an object: `actions::merge` replaces it with what the patch
    ///    carries, and the keys left out then come from `Gradient::default()`
    ///    rather than from what the clip had. This section is where a
    ///    gradient is turned ON from null, so it sends every key and is right
    ///    in both cases. `shadow` has carried that since M3 and `obscure`
    ///    since phase 3; `edited` below is where `gradient` joins them.
    ///  - **The Fill rows above stay live.** A gradient takes precedence over
    ///    `fill` and does not clear it, which is what makes this section's
    ///    Reset — one `{gradient: null}` — an exact inverse rather than a
    ///    shape that goes invisible. Disabling the colour underneath would
    ///    hide the value the Reset is about to bring back, so the note says
    ///    where the fill went instead of the panel pretending it is gone.
    ///  - **`line` and `arrow` get the rows DISABLED, not hidden.** The field
    ///    is stored and range-checked on every kind and read by the two area
    ///    kinds alone — `radius`'s precedent exactly — so flipping the Kind
    ///    popup to Line and back may not lose the ramp.
    func gradientSection() -> InspectorSection {
        let binding = self.binding
        let kinds = GradientKind.allCases
        func current() -> Gradient? { binding.shapeProps.gradient }
        func on() -> Bool { current() != nil }
        /// Whether this kind has an interior to fill at all.
        func area() -> Bool { !binding.shapeProps.kind.isLinear }
        func list() -> [GradientStop] { current()?.stops ?? [] }
        func at(_ index: Int) -> GradientStop? {
            let stops = list()
            return stops.indices.contains(index) ? stops[index] : nil
        }
        func ops(_ next: Gradient?) -> [ReelOp] {
            binding.ops(shape: ShapePatch(gradient: .some(next)))
        }
        /// One key of the gradient changed and the other two as they stand.
        /// This is the "send it whole" rule above, spelled once so that no
        /// row has to remember it.
        func edited(
            kind: GradientKind? = nil, stops next: [GradientStop]? = nil, angle: Double? = nil
        ) -> [ReelOp] {
            guard let gradient = current() else { return [] }
            return ops(
                Gradient(
                    kind: kind ?? gradient.kind, stops: next ?? gradient.stops,
                    angle: angle ?? gradient.angle))
        }
        func edited(replacing index: Int, _ stop: GradientStop) -> [ReelOp] {
            var next = list()
            guard next.indices.contains(index) else { return [] }
            next[index] = stop
            return edited(stops: next)
        }
        /// The mixed badge for one stop's field: a selection where some clip
        /// has no gradient, or none at that index, disagrees — which the
        /// `nil` says, the way `obscureSection`'s `mixedAt` says it.
        func mixedAt<T: Equatable>(_ index: Int, _ read: @escaping (GradientStop) -> T) -> Bool {
            binding.mixedShape { props -> T? in
                guard let stops = props.gradient?.stops, stops.indices.contains(index)
                else { return nil }
                return read(stops[index])
            }
        }
        /// The colour half way between two stops, component by component —
        /// which is exactly what `CGGradient` does between them, in the same
        /// sRGB space, so a handle added here sits ON the ramp rather than
        /// beside it. A three-component colour is an opaque one (`RGBA`'s own
        /// rule), so both are padded the same way before they are mixed.
        func midpoint(_ a: RGBA, _ b: RGBA) -> RGBA {
            func component(_ color: RGBA, _ index: Int) -> Double {
                index < color.count ? color[index] : (index == 3 ? 1 : 0)
            }
            return (0..<4).map { (component(a, $0) + component(b, $0)) / 2 }
        }
        /// A stop dropped into the WIDEST gap and coloured by the ramp that
        /// is already there, so Add changes the picture not at all: it puts a
        /// handle where the ramp already runs, which is what Add means in
        /// every gradient editor. The model cannot do this for you —
        /// `GradientStop`'s own default is black at 0, because serde has to
        /// fill a missing key without knowing which row was clicked.
        ///
        /// It inserts into the list as it is HELD, never into the sorted one.
        /// The rows are drawn in held order and the core deliberately does
        /// not police that order (`props_check.rs` argues the missing check
        /// where it would have gone), so sorting here would make every row
        /// jump the first time somebody pressed Add.
        func added(_ stops: [GradientStop]) -> [GradientStop] {
            guard stops.count >= 2 else { return Gradient.defaultStops }
            let ramp = stops.enumerated().sorted {
                $0.element.at == $1.element.at
                    ? $0.offset < $1.offset : $0.element.at < $1.element.at
            }
            var widest = -1.0
            var left = ramp[0]
            var right = ramp[1]
            for (a, b) in zip(ramp, ramp.dropFirst()) where b.element.at - a.element.at > widest {
                widest = b.element.at - a.element.at
                left = a
                right = b
            }
            var next = stops
            next.insert(
                GradientStop(
                    at: (left.element.at + right.element.at) / 2,
                    color: midpoint(left.element.color, right.element.color)),
                at: left.offset + 1)
            return next
        }

        var rows: [NSView] = [
            inspectorCheckRow(
                "Gradient", binding, name: "Gradient", read: on,
                ops: { value in ops(value ? Gradient() : nil) },
                mixed: { binding.mixedShape { $0.gradient != nil } },
                enabled: area),
            inspectorPopupRow(
                "Kind", binding, name: "Gradient Kind", items: kinds.map { $0.displayName },
                read: { kinds.firstIndex(of: current()?.kind ?? .linear) ?? 0 },
                ops: { index in
                    guard kinds.indices.contains(index) else { return [] }
                    return edited(kind: kinds[index])
                },
                mixed: { binding.mixedShape { $0.gradient?.kind } },
                enabled: { on() && area() }),
            // Degrees from the RIGHT, counter-clockwise, and the same eight
            // quick picks the shadow's angle gets, because it is the same
            // convention and the crate has only the one.
            inspectorValueRow(
                "Angle", binding, name: "Gradient Angle", unit: "°", decimals: 0, min: 0,
                max: 360, quick: [0, 45, 90, 135, 180, 225, 270, 315],
                read: { current()?.angle ?? 0 },
                ops: { edited(angle: $0) },
                mixed: { binding.mixedShape { $0.gradient?.angle } },
                // A radial gradient has no direction to point: the model
                // stores the angle through the flip all the same, so coming
                // back to Linear finds the number where it was left.
                enabled: { on() && area() && current()?.kind == .linear }),
        ]
        for index in 0..<list().count {
            let swatch = OptionSwatchControl(
                read: { at(index)?.color.nsColor ?? .black },
                write: { color in
                    guard let stop = at(index),
                        let next = changedRGBA(color, from: stop.color)
                    else { return }
                    binding.apply(
                        "Gradient Stop",
                        edited(replacing: index, GradientStop(at: stop.at, color: next)))
                },
                enabled: area, onEdit: {})
            // A stop's position is 0–1 in the model and a PERCENTAGE here,
            // for `video.opacity`'s reason: the ramp is a distance across the
            // box, and nobody reads 0.35 of a box as a third of the way.
            let position = OptionFieldControl(
                width: InspectorMetrics.fieldWidth, unit: "%", decimals: 0, min: 0, max: 100,
                quick: [0, 25, 50, 75, 100],
                read: { (at(index)?.at ?? 0) * 100 },
                write: { value in
                    guard let stop = at(index) else { return }
                    binding.apply(
                        "Gradient Stop",
                        edited(replacing: index, GradientStop(at: value / 100, color: stop.color)))
                },
                enabled: area,
                onEdit: { binding.edited() })
            let remove = OptionButtonControl(
                title: "Remove",
                action: {
                    var next = list()
                    guard next.count > 2, next.indices.contains(index) else {
                        NSSound.beep()
                        return
                    }
                    next.remove(at: index)
                    binding.apply("Remove Stop", edited(stops: next))
                },
                enabled: { area() && list().count > 2 }, onEdit: {})
            remove.toolTip =
                "Take this colour off the ramp — two stops is the floor, because one "
                + "colour is a fill and Fill above already spells that"
            rows.append(
                inspectorRow(
                    "Stop \(index + 1)", [swatch, position, remove],
                    mixed: { mixedAt(index) { $0.color } || mixedAt(index) { $0.at } }))
        }
        if !on() {
            rows.append(inspectorRow(nil, [InspectorRowLabel("No gradient.")]))
        }
        let add = OptionButtonControl(
            title: "Add Stop",
            action: {
                let next = added(list())
                guard next.count > list().count else {
                    NSSound.beep()
                    return
                }
                binding.apply("Add Stop", edited(stops: next))
            },
            enabled: { area() && on() && list().count < Gradient.maxStops }, onEdit: {})
        add.toolTip =
            "Put a handle on the ramp where the ramp already is — the widest gap, "
            + "at the colour that is already there"
        rows.append(inspectorButtonRow([add, InspectorRowLabel("\(Gradient.maxStops) at most")]))

        return InspectorSection(
            id: "shape.gradient", title: "Gradient",
            summary: {
                guard let gradient = current() else { return "off" }
                return "\(gradient.kind.displayName.lowercased()), \(gradient.stops.count) stops"
            },
            note: {
                guard area() else {
                    return "Fills the rectangle or ellipse; a line or arrow keeps its "
                        + "stroke colour."
                }
                guard on(), binding.shapeProps.fill != nil else { return nil }
                return "The gradient covers the Fill colour above; Reset brings it back."
            },
            reset: { binding.apply("Gradient", shape: ShapePatch(gradient: .some(nil))) },
            defaultExpanded: false,
            rows: rows)
    }

    // MARK: Arrowheads

    func arrowSection() -> InspectorSection {
        let binding = self.binding
        /// Arrowheads only mean something on the two linear kinds, whose
        /// geometry is the `from`/`to` endpoints (§5.2).
        func linear() -> Bool { binding.shapeProps.kind.isLinear }
        return InspectorSection(
            id: "shape.arrows", title: "Arrowheads",
            summary: {
                let props = binding.shapeProps
                switch (props.arrowStart, props.arrowEnd) {
                case (true, true): return "both"
                case (true, false): return "start"
                case (false, true): return "end"
                case (false, false): return "none"
                }
            },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Arrowhead at start", binding, name: "Arrowhead",
                    read: { binding.shapeProps.arrowStart },
                    ops: { binding.ops(shape: ShapePatch(arrowStart: $0)) },
                    mixed: { binding.mixedShape { $0.arrowStart } },
                    enabled: linear),
                inspectorCheckRow(
                    "Arrowhead at end", binding, name: "Arrowhead",
                    read: { binding.shapeProps.arrowEnd },
                    ops: { binding.ops(shape: ShapePatch(arrowEnd: $0)) },
                    mixed: { binding.mixedShape { $0.arrowEnd } },
                    enabled: linear),
            ])
    }
}
