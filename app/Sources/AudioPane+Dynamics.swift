import AppKit

/// The Gate and De-esser sections (spec §11 AU-48): after Noise Reduction
/// and before Compressor, the signal's order (AU-47). `set_audio`'s `gate`
/// and `de_esser` are their MCP mirror.
///
/// Every control writes a whole `GateProps` or `DeEsserProps`, the
/// limiter's way; with an action selected both write the action's end (spec
/// §11 AU-88), a stage turned off there keyed off. Both thresholds are dB
/// relative to the clip's measured loudness (AU-41): the Status read-out says
/// where that puts the threshold in dBFS, or why the stage is not acting
/// (AU-42), and the Loudness read-out the level it is relative to — both
/// through the pane's `loudnessMemo`, the Volume section's own reading. The
/// times are in milliseconds and not snapped to the frame grid, for the
/// compressor's reason.
extension AudioPane {

    /// "Gate pauses", Threshold, Ratio, Range, Attack, Hold, Release, Status,
    /// Loudness.
    func gateSection() -> InspectorSection {
        let binding = self.binding
        func current() -> GateProps { binding.audioProps.gate ?? GateProps() }
        func ops(_ next: GateProps) -> [ReelOp] {
            binding.ops(audio: AudioPatch(gate: .some(next)))
        }
        func on() -> Bool { binding.audioProps.gate != nil }
        func row(
            _ title: String, _ name: String, unit: String, decimals: Int, min: Double,
            max: Double, quick: [Double], width: CGFloat = InspectorMetrics.fieldWidth,
            read: @escaping (GateProps) -> Double,
            write: @escaping (inout GateProps, Double) -> Void
        ) -> NSView {
            inspectorValueRow(
                title, binding, name: name, unit: unit, decimals: decimals, min: min, max: max,
                quick: quick, width: width, read: { read(current()) },
                ops: { value in
                    var g = current()
                    write(&g, value)
                    return ops(g)
                },
                mixed: { binding.mixedAudio { $0.gate.map(read) } }, enabled: on)
        }
        return InspectorSection(
            id: "audio.gate", title: "Gate",
            summary: { on() ? AudioPane.decibels(current().thresholdDb, "%.0f dB") : "off" },
            reset: { binding.apply("Gate", audio: AudioPatch(gate: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Gate pauses", binding, name: "Gate",
                    read: on,
                    ops: { value in
                        binding.ops(audio: AudioPatch(gate: value ? .some(GateProps()) : .some(nil)))
                    },
                    mixed: { binding.mixedAudio { $0.gate != nil } }),
                row(
                    "Threshold", "Gate Threshold", unit: " dB", decimals: 0, min: -40, max: 0,
                    quick: [-20, -15, -10, -6], read: { $0.thresholdDb },
                    write: { $0.thresholdDb = $1 }),
                row(
                    "Ratio", "Gate Ratio", unit: ":1", decimals: 1, min: 1, max: 20,
                    quick: [2, 4, 10, 20], read: { $0.ratio }, write: { $0.ratio = $1 }),
                row(
                    "Range", "Gate Range", unit: " dB", decimals: 0, min: 1, max: 80,
                    quick: [10, 20, 40, 80], read: { $0.rangeDb }, write: { $0.rangeDb = $1 }),
                row(
                    "Attack", "Gate Attack", unit: " ms", decimals: 0, min: 0, max: 100,
                    quick: [1, 5, 10], read: { AudioPane.milliseconds($0.attack) },
                    write: { $0.attack = AudioPane.ticks($1) }),
                row(
                    "Hold", "Gate Hold", unit: " ms", decimals: 0, min: 0, max: 500,
                    quick: [0, 50, 100, 200], read: { AudioPane.milliseconds($0.hold) },
                    write: { $0.hold = AudioPane.ticks($1) }),
                row(
                    "Release", "Gate Release", unit: " ms", decimals: 0, min: 1, max: 2000,
                    quick: [50, 100, 250, 500], width: InspectorMetrics.wideFieldWidth,
                    read: { AudioPane.milliseconds($0.release) },
                    write: { $0.release = AudioPane.ticks($1) }),
                inspectorRow(
                    "Status",
                    [
                        inspectorReadout(width: 170) { [weak self] in
                            guard on() else { return "off" }
                            return self?.dynamicsStatus(
                                relative: current().thresholdDb, acting: "Opens above",
                                idle: "Not gating") ?? "—"
                        }
                    ]),
                inspectorRow(
                    "Loudness",
                    [
                        inspectorReadout(width: 170) { [weak self] in
                            self?.dynamicsLoudness() ?? "—"
                        }
                    ]),
            ])
    }

    /// "Reduce sibilance", Frequency, Threshold, Range, Status, Loudness.
    func deEsserSection() -> InspectorSection {
        let binding = self.binding
        func current() -> DeEsserProps { binding.audioProps.deEsser ?? DeEsserProps() }
        func ops(_ next: DeEsserProps) -> [ReelOp] {
            binding.ops(audio: AudioPatch(deEsser: .some(next)))
        }
        func on() -> Bool { binding.audioProps.deEsser != nil }
        func row(
            _ title: String, _ name: String, unit: String, decimals: Int, min: Double,
            max: Double, quick: [Double], width: CGFloat = InspectorMetrics.fieldWidth,
            read: @escaping (DeEsserProps) -> Double,
            write: @escaping (inout DeEsserProps, Double) -> Void
        ) -> NSView {
            inspectorValueRow(
                title, binding, name: name, unit: unit, decimals: decimals, min: min, max: max,
                quick: quick, width: width, read: { read(current()) },
                ops: { value in
                    var d = current()
                    write(&d, value)
                    return ops(d)
                },
                mixed: { binding.mixedAudio { $0.deEsser.map(read) } }, enabled: on)
        }
        return InspectorSection(
            id: "audio.de_esser", title: "De-esser",
            summary: { on() ? String(format: "%.1f kHz", current().frequency / 1000) : "off" },
            reset: { binding.apply("De-esser", audio: AudioPatch(deEsser: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Reduce sibilance", binding, name: "De-esser",
                    read: on,
                    ops: { value in
                        binding.ops(
                            audio: AudioPatch(deEsser: value ? .some(DeEsserProps()) : .some(nil)))
                    },
                    mixed: { binding.mixedAudio { $0.deEsser != nil } }),
                row(
                    "Frequency", "De-esser Frequency", unit: " Hz", decimals: 0, min: 2000,
                    max: 12_000, quick: [4000, 5000, 6000, 8000],
                    width: InspectorMetrics.wideFieldWidth, read: { $0.frequency },
                    write: { $0.frequency = $1 }),
                row(
                    "Threshold", "De-esser Threshold", unit: " dB", decimals: 0, min: -30, max: 20,
                    quick: [-6, -3, 0, 3], read: { $0.thresholdDb },
                    write: { $0.thresholdDb = $1 }),
                row(
                    "Range", "De-esser Range", unit: " dB", decimals: 0, min: 1, max: 24,
                    quick: [3, 6, 10], read: { $0.rangeDb }, write: { $0.rangeDb = $1 }),
                inspectorRow(
                    "Status",
                    [
                        inspectorReadout(width: 170) { [weak self] in
                            guard on() else { return "off" }
                            return self?.dynamicsStatus(
                                relative: current().thresholdDb, acting: "Acts above",
                                idle: "Not de-essing") ?? "—"
                        }
                    ]),
                inspectorRow(
                    "Loudness",
                    [
                        inspectorReadout(width: 170) { [weak self] in
                            self?.dynamicsLoudness() ?? "—"
                        }
                    ]),
            ])
    }

    /// The one selected clip's loudness answer; nil for a selection of
    /// several.
    private func dynamicsAnswer() -> ClipLoudness.Answer? {
        guard binding.isSingle, let clip = binding.primary, let document = binding.document
        else { return nil }
        return loudnessMemo.answer(for: clip.id, in: document)
    }

    /// Where a relative threshold lands for the one selected clip (AU-41), or
    /// why the stage is not acting (AU-42); "—" for a selection of several.
    /// Short enough for the read-out: "Opens above −51.7 dBFS".
    private func dynamicsStatus(relative: Double, acting: String, idle: String) -> String {
        switch dynamicsAnswer() {
        case nil: return "—"
        case .pending: return "Waits for its loudness"
        case .unavailable: return "\(idle): no sound"
        case .reading(let reading):
            guard let lufs = reading.lufs else {
                return reading.playedTicks < ClipLoudness.minimumPlayedTicks
                    ? "\(idle): too short" : "\(idle): too quiet"
            }
            return "\(acting) \(AudioPane.decibels(lufs + relative, "%.1f dBFS"))"
        }
    }

    /// The level the thresholds are relative to: "−41.7 LUFS", "measuring…"
    /// (the Volume section's word) or "—".
    private func dynamicsLoudness() -> String {
        guard case .reading(let reading) = dynamicsAnswer() else {
            return dynamicsAnswer() == .pending ? "measuring…" : "—"
        }
        return reading.lufs.map { AudioPane.decibels($0, "%.1f LUFS") } ?? "—"
    }

    private static func decibels(_ value: Double, _ format: String) -> String {
        String(format: format, value).replacingOccurrences(of: "-", with: "−")
    }

    private static func ticks(_ milliseconds: Double) -> Ticks {
        Ticks((max(milliseconds, 0) / 1000 * Double(ReelTime.perSecond)).rounded())
    }

    private static func milliseconds(_ ticks: Ticks) -> Double {
        Double(ticks) / Double(ReelTime.perSecond) * 1000
    }
}
