import AppKit

/// The Audio tab (spec §4.3): volume with its dB read-out, mute, the two
/// fades, ducking, mix-to-mono and Detach Audio.
///
/// Everything here is one `set_audio` patch over the selection, except Detach
/// Audio, which is a clip-level op the editor already owns (⌥⌘D) — the pane
/// hands it back through `onCommand` rather than re-implementing it.
final class AudioPane: InspectorPaneView {
    override var tab: InspectorTab { .audio }

    override func makeSections() -> [InspectorSection] {
        [volumeSection(), fadeSection(), duckSection(), mixSection()]
    }

    // MARK: Volume

    private func volumeSection() -> InspectorSection {
        let binding = self.binding
        return InspectorSection(
            id: "audio.volume", title: "Volume",
            note: { binding.actionNote },
            reset: { binding.apply("Volume", audio: AudioPatch(volume: 1, muted: false)) },
            rows: [
                inspectorValueRow(
                    "Volume", binding, name: "Volume", unit: "%", decimals: 0, min: 0, max: 400,
                    quick: [0, 50, 100, 150, 200, 400],
                    read: { binding.audioProps.volume * 100 },
                    ops: { binding.ops(audio: AudioPatch(volume: $0 / 100)) },
                    mixed: { binding.mixedAudio { $0.volume } }),
                inspectorRow(
                    "Gain",
                    [
                        inspectorReadout {
                            let decibels = binding.audioProps.decibels
                            guard decibels.isFinite else { return "silent" }
                            return String(format: "%+.1f dB", decibels)
                        }
                    ]),
                inspectorCheckRow(
                    "Mute", binding, name: "Mute",
                    read: { binding.audioProps.muted },
                    ops: { binding.ops(audio: AudioPatch(muted: $0)) },
                    mixed: { binding.mixedAudio { $0.muted } }),
            ])
    }

    // MARK: Fades

    /// Fades are also the corner handles on the clip (§4.4), so the numbers
    /// here and the drag there write the same two fields.
    private func fadeSection() -> InspectorSection {
        let binding = self.binding
        func ticks(_ seconds: Double) -> Ticks {
            ReelTime.snapToFrame(ReelTime.ticks(seconds: max(seconds, 0)), fps: binding.canvas.fps)
        }
        return InspectorSection(
            id: "audio.fades", title: "Fades",
            reset: { binding.apply("Fades", audio: AudioPatch(fadeIn: 0, fadeOut: 0)) },
            rows: [
                inspectorValueRow(
                    "Fade in", binding, name: "Fade In", unit: " s", decimals: 2, min: 0, max: 10,
                    quick: [0, 0.25, 0.5, 1, 2],
                    read: { ReelTime.seconds(binding.audioProps.fadeIn) },
                    ops: { binding.ops(audio: AudioPatch(fadeIn: ticks($0))) },
                    mixed: { binding.mixedAudio { $0.fadeIn } }),
                inspectorValueRow(
                    "Fade out", binding, name: "Fade Out", unit: " s", decimals: 2, min: 0,
                    max: 10, quick: [0, 0.25, 0.5, 1, 2],
                    read: { ReelTime.seconds(binding.audioProps.fadeOut) },
                    ops: { binding.ops(audio: AudioPatch(fadeOut: ticks($0))) },
                    mixed: { binding.mixedAudio { $0.fadeOut } }),
            ])
    }

    // MARK: Ducking

    /// "Lower other audio to N % while this clip plays" — by clip EXTENT, not
    /// voice activity (§11), which is why there is nothing to analyse and the
    /// core can fold it into the other clips' envelopes.
    ///
    /// Every control writes a whole `DuckProps`: the patch replaces the
    /// object, so each edit re-sends the other two values as they stand.
    private func duckSection() -> InspectorSection {
        let binding = self.binding
        func current() -> DuckProps { binding.audioProps.duck ?? DuckProps() }
        func ops(_ next: DuckProps) -> [ReelOp] { binding.ops(audio: AudioPatch(duck: .some(next))) }
        func on() -> Bool { binding.audioProps.duck != nil }
        func ticks(_ seconds: Double) -> Ticks {
            ReelTime.snapToFrame(ReelTime.ticks(seconds: max(seconds, 0)), fps: binding.canvas.fps)
        }
        return InspectorSection(
            id: "audio.duck", title: "Ducking",
            reset: { binding.apply("Ducking", audio: AudioPatch(duck: .some(nil))) },
            rows: [
                inspectorCheckRow(
                    "Duck other audio", binding, name: "Ducking",
                    read: on,
                    ops: { value in
                        binding.ops(
                            audio: AudioPatch(duck: value ? .some(DuckProps()) : .some(nil)))
                    },
                    mixed: { binding.mixedAudio { $0.duck != nil } }),
                inspectorValueRow(
                    "Level", binding, name: "Duck Level", unit: "%", decimals: 0, min: 0, max: 100,
                    quick: [0, 10, 20, 30, 50],
                    read: { current().level * 100 },
                    ops: { value in
                        ops(
                            DuckProps(
                                level: value / 100, attack: current().attack,
                                release: current().release))
                    },
                    enabled: on),
                inspectorValueRow(
                    "Attack", binding, name: "Duck Attack", unit: " s", decimals: 2, min: 0,
                    max: 5, quick: [0.1, 0.25, 0.5, 1],
                    read: { ReelTime.seconds(current().attack) },
                    ops: { value in
                        ops(
                            DuckProps(
                                level: current().level, attack: ticks(value),
                                release: current().release))
                    },
                    enabled: on),
                inspectorValueRow(
                    "Release", binding, name: "Duck Release", unit: " s", decimals: 2, min: 0,
                    max: 5, quick: [0.25, 0.5, 1, 2],
                    read: { ReelTime.seconds(current().release) },
                    ops: { value in
                        ops(
                            DuckProps(
                                level: current().level, attack: current().attack,
                                release: ticks(value)))
                    },
                    enabled: on),
            ])
    }

    // MARK: Mix

    private func mixSection() -> InspectorSection {
        let binding = self.binding
        let detach = OptionButtonControl(
            title: "Detach Audio",
            action: { [weak self] in
                self?.inspector?.onCommand?(#selector(EditorViewController.detachAudio(_:)))
            },
            enabled: { true }, onEdit: {})
        detach.toolTip = "Move the audio to its own clip on the track below (⌥⌘D)"
        return InspectorSection(
            id: "audio.mix", title: "Mix",
            rows: [
                inspectorCheckRow(
                    "Mix to mono", binding, name: "Mix to Mono",
                    read: { binding.audioProps.mono },
                    ops: { binding.ops(audio: AudioPatch(mono: $0)) },
                    mixed: { binding.mixedAudio { $0.mono } }),
                inspectorButtonRow([detach]),
            ])
    }
}
