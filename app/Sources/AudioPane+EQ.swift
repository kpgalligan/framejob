import AppKit

/// The EQ section (spec §11 AU-31, AU-32, AU-36, AU-38): the clip's EQ, after
/// the channel pick and before the hum notch and noise reduction, so the
/// Sound sub-tab's sections read in the signal's order. `set_audio`'s `eq`
/// is its MCP mirror.
///
/// The drawn response (`AudioEQCurveView`), Bypass, the three presets, then
/// per slot a checkbox writing that slot's default and its Frequency, Gain,
/// Q and Slope. Every control writes a whole `EqProps`, the compressor's way
/// (`EqProps.dictionary` writes every slot, so a patch that merges per key
/// still turns one off). Base-only (`structural(audio:)`): with an action
/// selected it still writes the clip.
extension AudioPane {

    func eqSection() -> InspectorSection {
        let binding = self.binding
        func current() -> EqProps { binding.audioProps.eq ?? EqProps() }
        func on() -> Bool { binding.audioProps.eq != nil }
        func ops(_ next: EqProps) -> [ReelOp] { binding.ops(audio: AudioPatch(eq: .some(next))) }
        let curve = AudioEQCurveView(read: {
            guard !binding.mixedAudio({ $0.eq }), !binding.mixedAudio({ $0.hum }) else {
                return nil
            }
            return (binding.audioProps.eq, binding.audioProps.hum)
        })
        let presets = EqPreset.allCases.map { preset in
            inspectorButton(
                preset.title, binding, name: "EQ \(preset.title)",
                ops: { ops(preset.applied(to: current())) })
        }
        var rows: [NSView] = [
            inspectorRow(nil, [curve], mixed: { binding.mixedAudio { $0.eq } }),
            inspectorCheckRow(
                "Bypass", binding, name: "EQ Bypass",
                read: { current().bypass },
                ops: { value in
                    var next = current()
                    next.bypass = value
                    return ops(next)
                },
                mixed: { binding.mixedAudio { $0.eq?.bypass } }, enabled: on),
            inspectorButtonRow(presets),
        ]
        rows += passRows(
            "High-pass", \.highPass, fallback: .highPass, quick: [40, 60, 80, 100, 120],
            current: current, ops: ops)
        rows += shelfRows(
            "Low shelf", \.lowShelf, fallback: .lowShelf, quick: [80, 100, 150, 200],
            current: current, ops: ops)
        rows += bandRows("Band 1", \.band1, at: 300, current: current, ops: ops)
        rows += bandRows("Band 2", \.band2, at: 1000, current: current, ops: ops)
        rows += bandRows("Band 3", \.band3, at: 4000, current: current, ops: ops)
        rows += shelfRows(
            "High shelf", \.highShelf, fallback: .highShelf, quick: [6000, 8000, 10_000, 12_000],
            current: current, ops: ops)
        rows += passRows(
            "Low-pass", \.lowPass, fallback: .lowPass, quick: [8000, 10_000, 12_000, 16_000],
            current: current, ops: ops)
        return InspectorSection(
            id: "audio.eq", title: "EQ",
            summary: {
                guard let eq = binding.audioProps.eq else { return "off" }
                return eq.bypass ? "bypassed" : "\(eq.activeCount) on"
            },
            reset: { binding.apply("EQ", audio: AudioPatch(eq: .some(nil))) },
            defaultExpanded: false,
            rows: rows)
    }

    /// A slot's checkbox: on writes `fallback` into the slot (the EQ made if
    /// there was none), off clears the slot.
    private func slotCheck<Slot: Equatable>(
        _ title: String, _ path: WritableKeyPath<EqProps, Slot?>, fallback: Slot,
        current: @escaping () -> EqProps, ops: @escaping (EqProps) -> [ReelOp]
    ) -> NSView {
        let binding = self.binding
        return inspectorCheckRow(
            title, binding, name: "EQ \(title)",
            read: { current()[keyPath: path] != nil },
            ops: { value in
                var next = current()
                next[keyPath: path] = value ? fallback : nil
                return ops(next)
            },
            mixed: { binding.mixedAudio { $0.eq?[keyPath: path] != nil } })
    }

    private func frequencyRow<Slot>(
        _ title: String, _ path: WritableKeyPath<EqProps, Slot?>,
        _ frequency: WritableKeyPath<Slot, Double>, quick: [Double], off: Double,
        current: @escaping () -> EqProps, ops: @escaping (EqProps) -> [ReelOp]
    ) -> NSView where Slot: Equatable {
        let binding = self.binding
        return inspectorValueRow(
            "Frequency", binding, name: "EQ \(title) Frequency", unit: " Hz", decimals: 0,
            min: 20, max: 20_000, quick: quick, slider: false,
            width: InspectorMetrics.wideFieldWidth,
            read: { current()[keyPath: path]?[keyPath: frequency] ?? off },
            ops: { value in
                var next = current()
                next[keyPath: path]?[keyPath: frequency] = value
                return ops(next)
            },
            mixed: { binding.mixedAudio { $0.eq?[keyPath: path]?[keyPath: frequency] } },
            enabled: { current()[keyPath: path] != nil })
    }

    private func gainRow<Slot>(
        _ title: String, _ path: WritableKeyPath<EqProps, Slot?>,
        _ gain: WritableKeyPath<Slot, Double>,
        current: @escaping () -> EqProps, ops: @escaping (EqProps) -> [ReelOp]
    ) -> NSView where Slot: Equatable {
        let binding = self.binding
        return inspectorValueRow(
            "Gain", binding, name: "EQ \(title) Gain", unit: " dB", decimals: 1,
            min: -24, max: 24, quick: [-6, -3, 0, 3, 6],
            read: { current()[keyPath: path]?[keyPath: gain] ?? 0 },
            ops: { value in
                var next = current()
                next[keyPath: path]?[keyPath: gain] = value
                return ops(next)
            },
            mixed: { binding.mixedAudio { $0.eq?[keyPath: path]?[keyPath: gain] } },
            enabled: { current()[keyPath: path] != nil })
    }

    private func passRows(
        _ title: String, _ path: WritableKeyPath<EqProps, EqPassProps?>, fallback: EqPassProps,
        quick: [Double], current: @escaping () -> EqProps, ops: @escaping (EqProps) -> [ReelOp]
    ) -> [NSView] {
        let binding = self.binding
        return [
            slotCheck(title, path, fallback: fallback, current: current, ops: ops),
            frequencyRow(
                title, path, \.frequency, quick: quick, off: fallback.frequency,
                current: current, ops: ops),
            inspectorPopupRow(
                "Slope", binding, name: "EQ \(title) Slope", items: ["12 dB/oct", "24 dB/oct"],
                read: { (current()[keyPath: path]?.slope ?? 12) >= 18 ? 1 : 0 },
                ops: { index in
                    var next = current()
                    next[keyPath: path]?.slope = index == 1 ? 24 : 12
                    return ops(next)
                },
                mixed: { binding.mixedAudio { $0.eq?[keyPath: path]?.slope } },
                enabled: { current()[keyPath: path] != nil }),
        ]
    }

    private func shelfRows(
        _ title: String, _ path: WritableKeyPath<EqProps, EqShelfProps?>,
        fallback: EqShelfProps, quick: [Double], current: @escaping () -> EqProps,
        ops: @escaping (EqProps) -> [ReelOp]
    ) -> [NSView] {
        [
            slotCheck(title, path, fallback: fallback, current: current, ops: ops),
            frequencyRow(
                title, path, \.frequency, quick: quick, off: fallback.frequency,
                current: current, ops: ops),
            gainRow(title, path, \.gainDb, current: current, ops: ops),
        ]
    }

    /// A bell's rows; its checkbox writes `{at, 0 dB, Q 1}` (AU-38: bands 1,
    /// 2 and 3 at 300, 1000 and 4000 Hz).
    private func bandRows(
        _ title: String, _ path: WritableKeyPath<EqProps, EqBandProps?>, at frequency: Double,
        current: @escaping () -> EqProps, ops: @escaping (EqProps) -> [ReelOp]
    ) -> [NSView] {
        let binding = self.binding
        return [
            slotCheck(
                title, path, fallback: EqBandProps(frequency: frequency), current: current,
                ops: ops),
            frequencyRow(
                title, path, \.frequency, quick: [100, 300, 1000, 2500, 4000, 8000],
                off: frequency, current: current, ops: ops),
            gainRow(title, path, \.gainDb, current: current, ops: ops),
            inspectorValueRow(
                "Q", binding, name: "EQ \(title) Q", decimals: 2, min: 0.1, max: 10,
                quick: [0.5, 0.7, 1, 2, 4],
                read: { current()[keyPath: path]?.q ?? 1 },
                ops: { value in
                    var next = current()
                    next[keyPath: path]?.q = value
                    return ops(next)
                },
                mixed: { binding.mixedAudio { $0.eq?[keyPath: path]?.q } },
                enabled: { current()[keyPath: path] != nil }),
        ]
    }
}
