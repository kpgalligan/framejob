import AppKit

/// The Channels and Hum sections (spec §11 AU-33, AU-34, AU-38): the channel
/// pick heads the clip's chain, so Channels comes first after Ducking; the
/// hum notch follows the EQ. `set_audio`'s `channels` and `hum` are their MCP
/// mirrors. Both are base-only (`structural(audio:)`).
extension AudioPane {

    /// One popup: Both, Left Only, Right Only, Swap Left and Right. A
    /// one-channel (mono) track ignores it, as it ignores pan.
    func channelsSection() -> InspectorSection {
        let binding = self.binding
        let choices = AudioChannelChoice.allCases
        return InspectorSection(
            id: "audio.channels", title: "Channels",
            summary: { binding.audioProps.channels.title },
            reset: { binding.apply("Channels", audio: AudioPatch(channels: .both)) },
            defaultExpanded: false,
            rows: [
                inspectorPopupRow(
                    "Play", binding, name: "Channels", items: choices.map(\.title),
                    width: 160,
                    read: { choices.firstIndex(of: binding.audioProps.channels) ?? 0 },
                    ops: { index in
                        binding.ops(audio: AudioPatch(channels: choices[index]))
                    },
                    mixed: { binding.mixedAudio { $0.channels } }),
            ])
    }

    /// "Remove hum" (on writes the defaults), Mains (50 or 60 Hz), Depth (dB,
    /// 6…60) and Harmonics (1…8). Every control writes a whole `HumProps`.
    func humSection() -> InspectorSection {
        let binding = self.binding
        func current() -> HumProps { binding.audioProps.hum ?? HumProps() }
        func on() -> Bool { binding.audioProps.hum != nil }
        func ops(_ next: HumProps) -> [ReelOp] {
            binding.ops(audio: AudioPatch(hum: .some(next)))
        }
        return InspectorSection(
            id: "audio.hum", title: "Hum",
            summary: {
                guard let hum = binding.audioProps.hum else { return "off" }
                return "\(hum.frequency) Hz · \(hum.harmonics)"
            },
            reset: { binding.apply("Hum", audio: AudioPatch(hum: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Remove hum", binding, name: "Remove Hum",
                    read: on,
                    ops: { value in
                        binding.ops(audio: AudioPatch(hum: value ? .some(HumProps()) : .some(nil)))
                    },
                    mixed: { binding.mixedAudio { $0.hum != nil } }),
                inspectorPopupRow(
                    "Mains", binding, name: "Hum Mains", items: ["50 Hz", "60 Hz"],
                    read: { current().frequency >= 55 ? 1 : 0 },
                    ops: { index in
                        var h = current()
                        h.frequency = index == 1 ? 60 : 50
                        return ops(h)
                    },
                    mixed: { binding.mixedAudio { $0.hum?.frequency } },
                    enabled: on),
                inspectorValueRow(
                    "Depth", binding, name: "Hum Depth", unit: " dB", decimals: 0,
                    min: 6, max: 60, quick: [12, 24, 30, 48],
                    read: { current().depthDb },
                    ops: { value in
                        var h = current()
                        h.depthDb = value
                        return ops(h)
                    },
                    mixed: { binding.mixedAudio { $0.hum?.depthDb } },
                    enabled: on),
                inspectorValueRow(
                    "Harmonics", binding, name: "Hum Harmonics", decimals: 0,
                    min: 1, max: 8, quick: [1, 2, 4, 8],
                    read: { Double(current().harmonics) },
                    ops: { value in
                        var h = current()
                        h.harmonics = Int(value.rounded())
                        return ops(h)
                    },
                    mixed: { binding.mixedAudio { $0.hum?.harmonics } },
                    enabled: on),
            ])
    }
}
