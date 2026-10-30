import AppKit

/// The Limiter section (spec §11 AU-26): the clip's true-peak limiter, last
/// in its chain, so the section comes after Mix — the Sound sub-tab's
/// sections read in the signal's order. `set_audio`'s `limiter` is its MCP
/// mirror.
extension AudioPane {

    /// "Limit peaks", Ceiling (dBTP, −24…0) and Release (ms, 1…1000).
    ///
    /// Every control writes a whole `LimiterProps`, the compressor's way: the
    /// patch replaces the object, so each edit re-sends the other value as it
    /// stands. Base-only (`structural(audio:)`): with an action selected it
    /// still writes the clip.
    ///
    /// The ceiling holds AFTER the clip's fader at its base volume (AU-22):
    /// fades and ducks only lower it, so it is what the clip sends the mix at
    /// most. The release is in milliseconds and not snapped to the frame
    /// grid, for the compressor's reason.
    func limiterSection() -> InspectorSection {
        let binding = self.binding
        func current() -> LimiterProps { binding.audioProps.limiter ?? LimiterProps() }
        func ops(_ next: LimiterProps) -> [ReelOp] {
            binding.ops(audio: AudioPatch(limiter: .some(next)))
        }
        func on() -> Bool { binding.audioProps.limiter != nil }
        func ticks(_ milliseconds: Double) -> Ticks {
            Ticks((max(milliseconds, 0) / 1000 * Double(ReelTime.perSecond)).rounded())
        }
        func milliseconds(_ ticks: Ticks) -> Double {
            Double(ticks) / Double(ReelTime.perSecond) * 1000
        }
        return InspectorSection(
            id: "audio.limiter", title: "Limiter",
            summary: {
                guard on() else { return "off" }
                return String(format: "%.1f dBTP", current().ceilingDb)
                    .replacingOccurrences(of: "-", with: "−")
            },
            reset: { binding.apply("Limiter", audio: AudioPatch(limiter: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Limit peaks", binding, name: "Limiter",
                    read: on,
                    ops: { value in
                        binding.ops(
                            audio: AudioPatch(limiter: value ? .some(LimiterProps()) : .some(nil)))
                    },
                    mixed: { binding.mixedAudio { $0.limiter != nil } }),
                inspectorValueRow(
                    "Ceiling", binding, name: "Limiter Ceiling", unit: " dBTP", decimals: 1,
                    min: -24, max: 0, quick: [-1, -2, -3, -6],
                    read: { current().ceilingDb },
                    ops: { value in
                        var l = current()
                        l.ceilingDb = value
                        return ops(l)
                    },
                    mixed: { binding.mixedAudio { $0.limiter?.ceilingDb } },
                    enabled: on),
                inspectorValueRow(
                    "Release", binding, name: "Limiter Release", unit: " ms", decimals: 0,
                    min: 1, max: 1000, quick: [50, 100, 200, 500],
                    read: { milliseconds(current().release) },
                    ops: { value in
                        var l = current()
                        l.release = ticks(value)
                        return ops(l)
                    },
                    mixed: { binding.mixedAudio { $0.limiter?.release } },
                    enabled: on),
            ])
    }
}
