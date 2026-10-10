import AppKit

extension VideoPane {
    // MARK: Light

    /// The Color sub-tab's first section (spec §11 GR-2): tone's nine keys in
    /// the model's order, a slider and a field each. Every row sends only its
    /// own key (`ColorPatch`), so a write over several clips keeps each one's
    /// other values; the summary and Reset are about these nine alone.
    func lightSection() -> InspectorSection {
        let binding = self.binding
        func color() -> ColorAdjust { binding.videoProps.color }
        func ops(_ patch: ColorPatch) -> [ReelOp] { binding.ops(video: VideoPatch(color: patch)) }
        func row(
            _ label: String, unit: String = "", min lower: Double = -1, max upper: Double = 1,
            _ key: WritableKeyPath<ColorPatch, Double?>, _ read: @escaping (ColorAdjust) -> Double
        ) -> NSView {
            inspectorValueRow(
                label, binding, name: label, unit: unit, decimals: 2, min: lower, max: upper,
                read: { read(color()) },
                ops: { value in
                    var patch = ColorPatch()
                    patch[keyPath: key] = value
                    return ops(patch)
                },
                mixed: { binding.mixedVideo { read($0.color) } })
        }
        return InspectorSection(
            id: "video.light", title: "Light",
            summary: { color().isLightNeutral ? "neutral" : "adjusted" },
            reset: { binding.apply("Light", video: VideoPatch(color: .neutralLight)) },
            defaultExpanded: false,
            rows: [
                row("Exposure", unit: " EV", min: -3, max: 3, \.exposure) { $0.exposure },
                row("Temperature", \.temperature) { $0.temperature },
                row("Tint", \.tint) { $0.tint },
                row("Highlights", \.highlights) { $0.highlights },
                row("Shadows", \.shadows) { $0.shadows },
                row("Whites", \.whites) { $0.whites },
                row("Blacks", \.blacks) { $0.blacks },
                row("Vibrance", \.vibrance) { $0.vibrance },
                row("Fade", min: 0, \.fade) { $0.fade },
            ])
    }
}
