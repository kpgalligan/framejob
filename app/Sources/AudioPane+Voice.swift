import AppKit

/// The Sound tab's Voice Effect section (spec §11 AU-146): one of sixteen
/// fixed chains of Apple's units, rendered offline per clip window and
/// played in place of the clip's sound — after Voice Isolation, before every
/// live stage (AU-143). Base-only: with an action selected it still writes
/// the clip (AU-140). `set_audio`'s `voice` is its MCP mirror; Clip ▸ Voice ▸
/// (`VoiceMenu.swift`, AU-158) is its menu half, built from the same
/// `VoiceKind` list and writing through the same `VoiceProps.choosing`.
extension AudioPane {
    /// The popup's kinds after "None", in E8's order.
    static let voiceKinds = VoiceKind.allCases

    /// What choosing popup item `index` writes over `current` (AU-146):
    /// `VoiceProps.choosing` for the item's kind, None for item 0.
    static func voiceChoice(_ index: Int, current: VoiceProps?) -> VoiceProps? {
        guard index > 0, index <= voiceKinds.count else { return nil }
        return VoiceProps.choosing(voiceKinds[index - 1], over: current)
    }

    func voiceSection() -> InspectorSection {
        let binding = self.binding
        let memo = voiceMemo
        let kinds = AudioPane.voiceKinds
        func current() -> VoiceProps? { binding.audioProps.voice }
        func ops(_ next: VoiceProps?) -> [ReelOp] {
            binding.ops(audio: AudioPatch(voice: .some(next)))
        }
        return InspectorSection(
            id: "audio.voice", title: "Voice Effect",
            summary: {
                guard let voice = current() else { return "off" }
                return String(format: "%@ %.0f%%", voice.kind.title, voice.amount * 100)
            },
            reset: { binding.apply("Voice Effect", audio: AudioPatch(voice: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorPopupRow(
                    "Effect", binding, name: "Voice Effect",
                    items: ["None"] + kinds.map(\.title), width: 170,
                    read: {
                        guard let kind = current()?.kind else { return 0 }
                        return (kinds.firstIndex(of: kind) ?? -1) + 1
                    },
                    ops: { index in ops(AudioPane.voiceChoice(index, current: current())) },
                    mixed: { binding.mixedAudio { $0.voice?.kind } }),
                inspectorValueRow(
                    "Amount", binding, name: "Voice Effect Amount", unit: "%",
                    decimals: 0, min: 0, max: 100, quick: [25, 50, 100],
                    read: { (current()?.amount ?? 1) * 100 },
                    ops: { value in
                        guard var voice = current() else { return [] }
                        voice.amount = value / 100
                        return ops(voice)
                    },
                    mixed: { binding.mixedAudio { $0.voice?.amount } },
                    enabled: { current() != nil }),
                inspectorValueRow(
                    "Pitch", binding, name: "Voice Effect Pitch", unit: "st",
                    decimals: 1, min: -12, max: 12, quick: [-12, -5, 0, 5, 12],
                    read: { current()?.semitones ?? 0 },
                    ops: { value in
                        guard var voice = current(), voice.kind.usesPitch else { return [] }
                        voice.pitch = value
                        return ops(voice)
                    },
                    mixed: { binding.mixedAudio { $0.voice?.semitones } },
                    enabled: { current()?.kind.usesPitch ?? false }),
                inspectorRow(
                    "Status",
                    [
                        inspectorReadout(width: 170) {
                            guard binding.audioClips.count == 1, let clip = binding.primary,
                                let document = binding.document
                            else { return "—" }
                            return AudioPane.isolationWords(
                                memo.status(of: clip.id, in: document))
                        }
                    ]),
            ])
    }
}
