import AppKit

/// The Sound tab's Voice Isolation section (spec §11 AU-56): Apple's
/// on-device voice model, rendered offline per clip window and crossfaded
/// with the clip's own sound by Amount before every other stage (AU-53,
/// AU-54). It also reduces room echo (B4's verdict), so there is no separate
/// de-reverb control. With an action selected it writes the action's end,
/// and the Amount animates, from 0 when the base has none (AU-88).
extension AudioPane {
    func isolationSection() -> InspectorSection {
        let binding = self.binding
        let memo = isolationMemo
        func on() -> Bool { binding.audioProps.isolation > 0 }
        return InspectorSection(
            id: "audio.isolation", title: "Voice Isolation",
            summary: {
                let amount = binding.audioProps.isolation
                return amount <= 0 ? "off" : String(format: "%.0f%%", amount * 100)
            },
            reset: { binding.apply("Voice Isolation", audio: AudioPatch(isolation: 0)) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Isolate voice", binding, name: "Isolate Voice", read: on,
                    ops: { value in
                        binding.ops(
                            audio: AudioPatch(
                                isolation: value ? IsolationCache.defaultAmount : 0))
                    },
                    mixed: { binding.mixedAudio { $0.isolation > 0 } }),
                inspectorValueRow(
                    "Amount", binding, name: "Voice Isolation Amount", unit: "%",
                    decimals: 0, min: 0, max: 100, quick: [50, 80, 100],
                    read: { binding.audioProps.isolation * 100 },
                    ops: { binding.ops(audio: AudioPatch(isolation: $0 / 100)) },
                    mixed: { binding.mixedAudio { $0.isolation } }),
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
                inspectorRow(
                    nil,
                    [
                        inspectorReadout(width: 170) { "Also reduces room echo" }
                    ]),
            ])
    }

    /// The Status read-out's words for each state (AU-56).
    static func isolationWords(_ status: IsolationStatus) -> String {
        switch status {
        case .off: return "Off"
        case .unsupported: return "Plays without it at this speed"
        case .waitingForReverse: return "Waits for the reversed copy"
        case .rendering: return "Rendering…"
        case .ready: return "Ready"
        case .failed(let why): return "Not rendered: \(why)"
        }
    }
}
