import AppKit

/// The Volume section's loudness half (spec §11 AU-15): the Loudness and At
/// volume readouts and the Normalize row's mode and target. The readout reads
/// through the pane's `loudnessMemo` (`ClipLoudness.Memo`), so a live Volume
/// or Pan drag reads no file and decodes no plan per tick; At volume is the
/// held answer plus the current base volume, through `AudioLimiterModel` while
/// the clip's limiter is on (AU-26) — on a clip with a stage the cache leaves
/// out, the last processed R0 or "≈" the cache figure (AU-64 (g)). Mode and
/// target are app-wide (`NormalizeChoice`), never an edit, so neither writes
/// the document.
extension AudioPane {

    /// The one clip the readout is about: exactly one selected clip Normalize
    /// is offered for, else nothing ("—").
    private var readoutClip: UInt32? { readoutSnapshot?.id }

    private var readoutSnapshot: ClipSnapshot? {
        let clips = AudioPane.normalizable(binding)
        return clips.count == 1 && binding.clips.count == 1 ? clips[0] : nil
    }

    private func loudnessAnswer() -> ClipLoudness.Answer {
        guard let clip = readoutClip, let document = binding.document else { return .unavailable }
        return loudnessMemo.answer(for: clip, in: document)
    }

    /// "−41.7 LUFS · −18.5 dBTP", "measuring…" or "—"; `gain` in dB is added
    /// to both (At volume). With `limiter`, the loudness is the model's at that
    /// gain and the peak is held at the limiter's ceiling (AU-24, AU-26).
    private func loudnessText(gain: Double, limiter: LimiterProps? = nil) -> String {
        switch loudnessAnswer() {
        case .pending: return "measuring…"
        case .unavailable: return "—"
        case .reading(let reading):
            return levelText(
                lufs: reading.lufs, truePeak: reading.truePeak, steps: reading.steps,
                peaks: reading.stepPeaks, gain: gain, limiter: limiter)
        }
    }

    /// One reading's figures at `gain` dB, through `limiter` when there is one.
    private func levelText(
        lufs measured: Double?, truePeak: Double, steps: [Double], peaks: [Double], gain: Double,
        limiter: LimiterProps?
    ) -> String {
        guard gain.isFinite else { return "silent" }
        var peak = truePeak > 0 ? 20 * log10(truePeak) + gain : -.infinity
        var lufs = measured.map { $0 + gain }
        if let limiter, measured != nil {
            let ceiling = pow(10, limiter.ceilingDb / 20)
            peak = min(peak, limiter.ceilingDb)
            lufs = AudioLimiterModel.integrated(
                steps: steps, peaks: peaks, gain: pow(10, gain / 20), ceiling: ceiling,
                releaseSeconds: Double(limiter.release) / Double(ReelTime.perSecond))
        }
        let peakText = peak.isFinite ? String(format: "%.1f dBTP", peak) : "−∞ dBTP"
        guard let lufs else { return "— LUFS · " + minus(peakText) }
        return minus(String(format: "%.1f LUFS · ", lufs) + peakText)
    }

    /// At volume (spec §11 AU-64 (g), AU-159 (g)): on a clip that plays
    /// through a stage the loudness cache leaves out, on the clip or at an
    /// action's end (`ProcessedLoudness.needsRender`, read from the clip and
    /// so the same whatever action is selected), the last R0 measured for
    /// its plan and chain (`ProcessedLoudness.Memo`) at the clip's BASE
    /// volume and limiter, else the cache figure at them marked approximate;
    /// any other clip, the cache figure at the props the fields show. On a
    /// clip an action's end sets a limiter on (AU-165 (c)), R0 is not how
    /// that limiter bites at the base volume: the last verify render that
    /// answered a press while the clip is at its volume and limiter, else R0
    /// marked approximate with `endLimiterTip`.
    private func atVolumeText(_ audio: AudioProps) -> (text: String, tip: String?) {
        guard let snapshot = readoutSnapshot, ProcessedLoudness.needsRender(snapshot),
            let document = binding.document, case .reading = loudnessAnswer()
        else { return (loudnessText(gain: audio.decibels, limiter: audio.limiter), nil) }
        let base = snapshot.audioProps
        guard let processed = ProcessedLoudness.Memo.shared.reading(for: snapshot.id, in: document)
        else {
            let text = "≈ " + loudnessText(gain: base.decibels, limiter: base.limiter)
            return (text, AudioPane.approximateTip)
        }
        let endLimiter = ProcessedLoudness.endSetsLimiter(snapshot)
        if endLimiter, let verified = processed.verified,
            verified.holds(volume: base.volume, limiter: base.limiter)
        {
            let text = levelText(
                lufs: verified.lufs, truePeak: verified.truePeak, steps: [], peaks: [], gain: 0,
                limiter: nil)
            return (text, nil)
        }
        let text = levelText(
            lufs: StepLoudness.integrated(processed.steps), truePeak: processed.peaks.max() ?? 0,
            steps: processed.steps, peaks: processed.peaks, gain: base.decibels,
            limiter: base.limiter)
        return endLimiter ? ("≈ " + text, AudioPane.endLimiterTip) : (text, nil)
    }

    static let approximateTip =
        "≈ before the clip's processing; Normalize or Enhance Voice measures through it."
    static let endLimiterTip =
        "≈ an action's limiter has not been measured at this volume; Normalize or Enhance Voice "
        + "measures through it."

    private func minus(_ text: String) -> String {
        text.replacingOccurrences(of: "-", with: "−")
    }

    /// The Loudness row (the clip's material at volume 1, pre-fader) and the
    /// At volume row (the same with the base volume's gain, through the
    /// clip's limiter when it has one).
    func loudnessRows() -> [NSView] {
        let binding = self.binding
        weak var atVolume: OptionDisplayControl?
        let readout = inspectorReadout(width: 160) { [weak self] in
            guard let self else { return "—" }
            let answer = self.atVolumeText(binding.audioProps)
            atVolume?.toolTip = answer.tip
            return answer.text
        }
        atVolume = readout
        return [
            inspectorRow(
                "Loudness", [inspectorReadout(width: 160) { [weak self] in
                    self?.loudnessText(gain: 0) ?? "—"
                }]),
            inspectorRow("At volume", [readout]),
        ]
    }

    /// The Normalize row: Mode (Peak | Loudness) and Target (LUFS, −50…−5,
    /// quick −14, −16, −23; live only in Loudness). A change only stores:
    /// `NormalizeChoice`'s post re-titles `button`'s tooltip and refreshes
    /// every open pane (`normalizeChoiceChanged`, #406).
    func normalizeRow(updating button: OptionButtonControl) -> NSView {
        normalizeButton = button
        button.toolTip = AudioPane.normalizeTip()
        let modes = AudioNormalize.Mode.allCases
        let popup = OptionPopupControl(
            width: 96, items: ["Peak", "Loudness"],
            read: { modes.firstIndex(of: NormalizeChoice.mode) ?? 0 },
            write: { index in
                NormalizeChoice.mode = modes[max(0, min(index, modes.count - 1))]
            },
            enabled: { true }, onEdit: {})
        let range = AudioNormalize.targetLUFSRange
        let target = OptionFieldControl(
            width: InspectorMetrics.fieldWidth, unit: "LUFS", decimals: 1,
            min: range.lowerBound, max: range.upperBound,
            quick: AudioNormalize.targetLUFSQuickPicks,
            read: { NormalizeChoice.targetLUFS },
            write: { value in
                NormalizeChoice.targetLUFS = min(max(value, range.lowerBound), range.upperBound)
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
                + ", turning the clip's limiter on at " + ceiling + " where its true peak would "
                + "pass it, and stopping short where the volume would pass "
                + AudioNormalize.maxGainName)
                .replacingOccurrences(of: "-", with: "−") + rest
        }
    }
}
