import AppKit

extension VideoPane {
    // MARK: Colour

    func colorSection() -> InspectorSection {
        let binding = self.binding
        func color() -> ColorAdjust { binding.videoProps.color }
        func ops(_ next: ColorAdjust) -> [ReelOp] { binding.ops(video: VideoPatch(color: next)) }
        return InspectorSection(
            id: "video.color", title: "Color",
            summary: { color().isIdentity ? "neutral" : "adjusted" },
            reset: { binding.apply("Color", video: VideoPatch(color: .identity)) },
            defaultExpanded: false,
            rows: [
                inspectorValueRow(
                    "Brightness", binding, name: "Brightness", decimals: 2, min: -1, max: 1,
                    read: { color().brightness },
                    ops: {
                        ops(
                            ColorAdjust(
                                brightness: $0, contrast: color().contrast,
                                saturation: color().saturation, hue: color().hue))
                    },
                    mixed: { binding.mixedVideo { $0.color.brightness } }),
                inspectorValueRow(
                    "Contrast", binding, name: "Contrast", decimals: 2, min: -1, max: 1,
                    read: { color().contrast },
                    ops: {
                        ops(
                            ColorAdjust(
                                brightness: color().brightness, contrast: $0,
                                saturation: color().saturation, hue: color().hue))
                    },
                    mixed: { binding.mixedVideo { $0.color.contrast } }),
                inspectorValueRow(
                    "Saturation", binding, name: "Saturation", decimals: 2, min: -1, max: 1,
                    read: { color().saturation },
                    ops: {
                        ops(
                            ColorAdjust(
                                brightness: color().brightness, contrast: color().contrast,
                                saturation: $0, hue: color().hue))
                    },
                    mixed: { binding.mixedVideo { $0.color.saturation } }),
                inspectorValueRow(
                    "Hue", binding, name: "Hue", unit: "°", decimals: 0, min: -180, max: 180,
                    read: { color().hue },
                    ops: {
                        ops(
                            ColorAdjust(
                                brightness: color().brightness, contrast: color().contrast,
                                saturation: color().saturation, hue: $0))
                    },
                    mixed: { binding.mixedVideo { $0.color.hue } }),
            ])
    }
}
