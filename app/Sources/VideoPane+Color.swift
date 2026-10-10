import AppKit

extension VideoPane {
    // MARK: Colour

    /// The Color sub-tab's second section (spec §11 GR-2; it was Picture's).
    /// Each row sends only its own key (`ColorPatch`), so a multi-selection
    /// keeps every clip's other values; the summary and Reset are about the
    /// four alone, Light's nine being `lightSection()`'s.
    func colorSection() -> InspectorSection {
        let binding = self.binding
        func color() -> ColorAdjust { binding.videoProps.color }
        func ops(_ next: ColorPatch) -> [ReelOp] { binding.ops(video: VideoPatch(color: next)) }
        return InspectorSection(
            id: "video.color", title: "Color",
            summary: { color().isColorNeutral ? "neutral" : "adjusted" },
            reset: { binding.apply("Color", video: VideoPatch(color: .neutralColor)) },
            defaultExpanded: false,
            rows: [
                inspectorValueRow(
                    "Brightness", binding, name: "Brightness", decimals: 2, min: -1, max: 1,
                    read: { color().brightness },
                    ops: { ops(ColorPatch(brightness: $0)) },
                    mixed: { binding.mixedVideo { $0.color.brightness } }),
                inspectorValueRow(
                    "Contrast", binding, name: "Contrast", decimals: 2, min: -1, max: 1,
                    read: { color().contrast },
                    ops: { ops(ColorPatch(contrast: $0)) },
                    mixed: { binding.mixedVideo { $0.color.contrast } }),
                inspectorValueRow(
                    "Saturation", binding, name: "Saturation", decimals: 2, min: -1, max: 1,
                    read: { color().saturation },
                    ops: { ops(ColorPatch(saturation: $0)) },
                    mixed: { binding.mixedVideo { $0.color.saturation } }),
                inspectorValueRow(
                    "Hue", binding, name: "Hue", unit: "°", decimals: 0, min: -180, max: 180,
                    read: { color().hue },
                    ops: { ops(ColorPatch(hue: $0)) },
                    mixed: { binding.mixedVideo { $0.color.hue } }),
            ])
    }
}
