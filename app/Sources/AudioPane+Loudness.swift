import AppKit

/// The Volume section's loudness half (spec §11 AU-15): the Loudness and At
/// volume readouts and the Normalize row's mode and target. The readout reads
/// through the pane's `loudnessMemo` (`ClipLoudness.Memo`), so a live Volume
/// or Pan drag reads no file and decodes no plan per tick; At volume is the
/// held answer plus the current base volume. Mode and target are app-wide
/// (`NormalizeChoice`), never an edit, so neither writes the document.
extension AudioPane {

    /// The one clip the readout is about: exactly one selected clip Normalize
    /// is offered for, else nothing ("—").
    private var readoutClip: UInt32? {
        let clips = AudioPane.normalizable(binding)
        return clips.count == 1 && binding.clips.count == 1 ? clips[0].id : nil
    }

    private func loudnessAnswer() -> ClipLoudness.Answer {
        guard let clip = readoutClip, let document = binding.document else { return .unavailable }
        return loudnessMemo.answer(for: clip, in: document)
    }

    /// "−41.7 LUFS · −18.5 dBTP", "measuring…" or "—"; `gain` in dB is added
    /// to both (At volume).
    private func loudnessText(gain: Double) -> String {
        switch loudnessAnswer() {
        case .pending: return "measuring…"
        case .unavailable: return "—"
        case .reading(let reading):
            guard gain.isFinite else { return "silent" }
            let peak = reading.truePeak > 0 ? 20 * log10(reading.truePeak) + gain : -.infinity
            let peakText = peak.isFinite ? String(format: "%.1f dBTP", peak) : "−∞ dBTP"
            guard let lufs = reading.lufs else { return "— LUFS · " + minus(peakText) }
            return minus(String(format: "%.1f LUFS · ", lufs + gain) + peakText)
        }
    }

    private func minus(_ text: String) -> String {
        text.replacingOccurrences(of: "-", with: "−")
    }

    /// The Loudness row (the clip's material at volume 1, pre-fader) and the
    /// At volume row (the same with the base volume's gain).
    func loudnessRows() -> [NSView] {
        let binding = self.binding
        return [
            inspectorRow(
                "Loudness", [inspectorReadout(width: 160) { [weak self] in
                    self?.loudnessText(gain: 0) ?? "—"
                }]),
            inspectorRow(
                "At volume", [inspectorReadout(width: 160) { [weak self] in
                    self?.loudnessText(gain: binding.audioProps.decibels) ?? "—"
                }]),
        ]
    }

    /// The Normalize row: Mode (Peak | Loudness) and Target (LUFS, −50…−5,
    /// quick −14, −16, −23; live only in Loudness). A change re-titles
    /// `button`'s tooltip and refreshes the pane.
    func normalizeRow(updating button: OptionButtonControl) -> NSView {
        button.toolTip = AudioPane.normalizeTip()
        let modes = AudioNormalize.Mode.allCases
        let popup = OptionPopupControl(
            width: 96, items: ["Peak", "Loudness"],
            read: { modes.firstIndex(of: NormalizeChoice.mode) ?? 0 },
            write: { [weak self, weak button] index in
                NormalizeChoice.mode = modes[max(0, min(index, modes.count - 1))]
                button?.toolTip = AudioPane.normalizeTip()
                self?.inspector?.refresh(isLive: false)
            },
            enabled: { true }, onEdit: {})
        let range = AudioNormalize.targetLUFSRange
        let target = OptionFieldControl(
            width: InspectorMetrics.fieldWidth, unit: "LUFS", decimals: 1,
            min: range.lowerBound, max: range.upperBound,
            quick: AudioNormalize.targetLUFSQuickPicks,
            read: { NormalizeChoice.targetLUFS },
            write: { [weak self, weak button] value in
                NormalizeChoice.targetLUFS = min(max(value, range.lowerBound), range.upperBound)
                button?.toolTip = AudioPane.normalizeTip()
                self?.inspector?.refresh(isLive: false)
            },
            enabled: { NormalizeChoice.mode == .loudness }, onEdit: {})
        return inspectorRow("Normalize", [popup, target])
    }

    /// The button's tooltip in the chosen mode. Two of the sentences are the
    /// limits, and they are here because this is where somebody meets them:
    /// the tool's description says the same things (road map 2 phase 5c,
    /// D-C3). The nest clause is a limit turned around: a nest alone leaves
    /// the button disabled, but a nest picked BESIDE an ordinary clip leaves it
    /// enabled and the nest quietly not asked about.
    static func normalizeTip() -> String {
        let rest =
            ". It REPLACES the volume rather than adding to it, so pressing it twice "
            + "changes nothing; it writes the clip's base level even while the playhead "
            + "is inside an action; and it leaves Mute alone. A nest is skipped: its "
            + "level lives in the clips inside it, not in the nest."
        switch NormalizeChoice.mode {
        case .peak:
            let level = String(format: "%.0f dBFS", AudioNormalize.defaultPeakDB)
            return "Set each selected clip's volume so its loudest moment reaches "
                + level.replacingOccurrences(of: "-", with: "−") + rest
        case .loudness:
            let target = String(format: "%.1f LUFS", NormalizeChoice.targetLUFS)
            let ceiling = String(format: "%.0f dBTP", AudioNormalize.ceilingDBTP)
            return ("Set each selected clip's volume so its integrated loudness reaches " + target
                + ", stopping short where its true peak would pass " + ceiling + " or the "
                + "volume would pass " + AudioNormalize.maxGainName)
                .replacingOccurrences(of: "-", with: "−") + rest
        }
    }
}
