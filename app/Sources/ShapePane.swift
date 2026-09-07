import AppKit

/// The Clip tab's SHAPE sections (spec §4.3): kind, stroke, fill, arrowheads
/// and corner radius.
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
    /// box has no endpoints), so it belongs in the rebuild signature.
    override var structureSignature: String {
        super.structureSignature + "|" + binding.shapeProps.kind.rawValue
    }

    // MARK: Kind and box

    func shapeSection() -> InspectorSection {
        let binding = self.binding
        let kinds = ShapeKind.allCases
        return InspectorSection(
            id: "shape.kind", title: "Shape",
            summary: { binding.shapeProps.kind.displayName.lowercased() },
            reset: { binding.apply("Shape", shape: ShapePatch(radius: 0)) },
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
