import AppKit

/// The Clip tab's AUDIO sections (spec §4.3): volume with its dB read-out,
/// Normalize and mute, the two fades, ducking, noise reduction, the
/// compressor, pan, mix-to-mono and Detach Audio.
///
/// **This pane is never shown**: since the six tabs became three it is a
/// factory `ClipPane` holds and calls, last in the Clip tab, whenever at least
/// one selected clip carries audio (`InspectorTab.hasAudio`).
///
/// Everything here is one `set_audio` patch over the selection, except Detach
/// Audio, which is a clip-level op the editor already owns (⌥⌘D) — the pane
/// hands it back through `onCommand` rather than re-implementing it — and
/// Normalize, which is a `set_audio` PER CLIP because each clip gets its own
/// measured gain (`normalize()` says why it cannot go through
/// `InspectorBinding.ops(audio:)`).
///
/// The last three sections are in SIGNAL ORDER rather than in order of
/// familiarity: noise reduction, then the compressor, then the pan in Mix, is
/// the order `AudioDSPChain` actually runs them in, and the order matters to
/// what the numbers mean (the compressor's threshold is read against a signal
/// the reducer has already cleaned). Volume, the fades and ducking come first
/// in the pane and LAST in the signal, being the fader the core folds into the
/// plan's envelope. `ClipPane` keeps them in that order.
final class AudioPane: InspectorPaneView {
    // MARK: Volume

    func volumeSection() -> InspectorSection {
        let binding = self.binding
        // The button lives in Volume rather than in a section of its own: it
        // writes the clip's volume and nothing else, and `ClipPane.makeSections`
        // would need editing for a seventh section — which is the omission
        // nothing type-checks and which has now bitten two phases in a row.
        let normalize = OptionButtonControl(
            title: "Normalize",
            action: { [weak self] in self?.normalize() },
            enabled: { !AudioPane.normalizable(binding).isEmpty }, onEdit: {})
        // Two of the three sentences are the limits, and they are here because
        // this is where somebody meets them: the tool's description says the
        // same three things (road map 2 phase 5c, D-C3). The level is spelled
        // with the typographic minus the sheets use, and read off the constant
        // so that changing the target changes the sentence. The nest clause is
        // a fourth limit and is here for the same reason turned around: a nest
        // alone leaves the button disabled, but a nest picked BESIDE an
        // ordinary clip leaves it enabled and the nest quietly not asked
        // about, which is the one thing about the press the others do not say.
        let level = String(format: "%.0f dBFS", AudioNormalize.defaultPeakDB)
            .replacingOccurrences(of: "-", with: "−")
        let tip: String =
            "Set each selected clip's volume so its loudest moment reaches " + level
            + ". It REPLACES the volume rather than adding to it, so pressing it twice "
            + "changes nothing; it writes the clip's base level even while the playhead "
            + "is inside an action; and it leaves Mute alone. A nest is skipped: its "
            + "level lives in the clips inside it, not in the nest."
        normalize.toolTip = tip
        return InspectorSection(
            id: "audio.volume", title: "Volume",
            summary: {
                let props = binding.audioProps
                if props.muted { return "muted" }
                guard props.decibels.isFinite else { return "silent" }
                return String(format: "%+.1f dB", props.decibels)
            },
            reset: { binding.apply("Volume", audio: AudioPatch(volume: 1, muted: false)) },
            defaultExpanded: false,
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
                    ], binding: binding,
                    follows: binding.ops(audio: AudioPatch(volume: binding.audioProps.volume))),
                inspectorCheckRow(
                    "Mute", binding, name: "Mute",
                    read: { binding.audioProps.muted },
                    ops: { binding.ops(audio: AudioPatch(muted: $0)) },
                    mixed: { binding.mixedAudio { $0.muted } }),
                inspectorButtonRow([normalize]),
            ])
    }

    /// Normalize Clip's UI half: measure, then commit as ONE undo step.
    ///
    /// All of the arithmetic is `AudioNormalize`'s, which is the point — the
    /// agent's `normalize_clip` calls the same two functions, so the button and
    /// the tool cannot drift apart, and the gains are testable with no window
    /// open.
    ///
    /// It does NOT go through `binding.ops(audio:)`, and that is deliberate.
    /// `InspectorBinding.split` does two things every other control here wants
    /// and this one must not inherit: it folds every clip outside an action
    /// into ONE `set_audio` with many ids and one shared patch — but each clip
    /// gets its own measured gain — and it re-routes a clip the playhead is
    /// inside an action of into `set_action_end`, where Normalize means the
    /// clip's BASE level and never an action's end state. So the ops are built
    /// per clip, the shape `SpeedSheetController` already uses for a per-clip
    /// computed result.
    ///
    /// The scope is `normalizable` rather than the raw selection, so a shape,
    /// a silent movie or a nest picked alongside is simply not asked about
    /// instead of coming back as a refusal the user did not cause.
    ///
    /// **A run that can normalise nothing beeps**, and so does a second press
    /// on an already-normalised selection: `apply` refuses an empty op list,
    /// and `ProjectDocument.applyEdit` refuses an identity edit — the recorded
    /// consequence `SpeedSheetController` carries for the same reason. The
    /// button is not the place that explains WHY a clip was skipped; the tool
    /// reports each reason by name under `skipped`.
    /// The selected clips Normalize is offered for, which is `audioClips`
    /// minus the ones `AudioNormalize` could only refuse.
    ///
    /// It is not `audioClips` because a NEST is in that list and must not be
    /// in this one: a nest clip carrying anything audible has audio properties
    /// of its own, so every other control in this section is right to be live
    /// on it, but the plan flattens a nest and the clip has no segment — so
    /// Normalize on a nest can only beep. `AudioNormalize.canOffer` is the one
    /// home of that rule; the Clip menu's validator asks it the same question,
    /// or the two would disagree about the same selection.
    static func normalizable(_ binding: InspectorBinding) -> [ClipSnapshot] {
        binding.audioClips.filter { AudioNormalize.canOffer($0, in: binding.snapshot) }
    }

    private func normalize() {
        guard let document = binding.document,
              let input = AudioNormalize.read(
                from: document, clips: AudioPane.normalizable(binding).map { $0.id })
        else {
            NSSound.beep()
            return
        }
        binding.apply("Normalize", AudioNormalize.plan(input).ops)
    }

    // MARK: Fades

    /// Fades are also the corner handles on the clip (§4.4), so the numbers
    /// here and the drag there write the same two fields.
    func fadeSection() -> InspectorSection {
        let binding = self.binding
        func ticks(_ seconds: Double) -> Ticks {
            ReelTime.snapToFrame(ReelTime.ticks(seconds: max(seconds, 0)), fps: binding.canvas.fps)
        }
        return InspectorSection(
            id: "audio.fades", title: "Fades",
            summary: {
                let props = binding.audioProps
                guard props.fadeIn > 0 || props.fadeOut > 0 else { return "none" }
                return String(
                    format: "%.2f · %.2f s", ReelTime.seconds(props.fadeIn),
                    ReelTime.seconds(props.fadeOut))
            },
            reset: { binding.apply("Fades", audio: AudioPatch(fadeIn: 0, fadeOut: 0)) },
            defaultExpanded: false,
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
    func duckSection() -> InspectorSection {
        let binding = self.binding
        func current() -> DuckProps { binding.audioProps.duck ?? DuckProps() }
        func ops(_ next: DuckProps) -> [ReelOp] { binding.ops(audio: AudioPatch(duck: .some(next))) }
        func on() -> Bool { binding.audioProps.duck != nil }
        func ticks(_ seconds: Double) -> Ticks {
            ReelTime.snapToFrame(ReelTime.ticks(seconds: max(seconds, 0)), fps: binding.canvas.fps)
        }
        return InspectorSection(
            id: "audio.duck", title: "Ducking",
            summary: { on() ? String(format: "%.0f%%", current().level * 100) : "off" },
            reset: { binding.apply("Ducking", audio: AudioPatch(duck: .some(nil))) },
            defaultExpanded: false,
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

    // MARK: Noise reduction

    /// "Remove background noise" (spec §4.2's M3 line).
    ///
    /// The read-out states the strongest attenuation any part of the spectrum
    /// can receive, which is the one number that describes this honestly: the
    /// filter is a spectral attenuator over a noise floor it measures from the
    /// clip itself, so it never removes MORE than the floor it found, and the
    /// amount sets how far a bin may be pushed down. It is not a gate and does
    /// not silence anything between words; see
    /// `AudioNoiseReductionStage` for what it does, sample by sample.
    func noiseSection() -> InspectorSection {
        let binding = self.binding
        return InspectorSection(
            id: "audio.noise", title: "Noise Reduction",
            summary: {
                let amount = binding.audioProps.noiseReduction
                return amount <= 0 ? "off" : String(format: "%.0f%%", amount * 100)
            },
            reset: { binding.apply("Noise Reduction", audio: AudioPatch(noiseReduction: 0)) },
            defaultExpanded: false,
            rows: [
                inspectorValueRow(
                    "Remove noise", binding, name: "Remove Background Noise", unit: "%",
                    decimals: 0, min: 0, max: 100, quick: [0, 25, 50, 75, 100],
                    read: { binding.audioProps.noiseReduction * 100 },
                    ops: { binding.ops(audio: AudioPatch(noiseReduction: $0 / 100)) },
                    mixed: { binding.mixedAudio { $0.noiseReduction } }),
                inspectorRow(
                    "Depth",
                    [
                        inspectorReadout {
                            let amount = binding.audioProps.noiseReduction
                            if amount <= 0 { return "off" }
                            if amount >= 1 { return "floor removed" }
                            return String(format: "%.0f dB at most", -20 * log10(1 - amount))
                        }
                    ]),
            ])
    }

    // MARK: Compressor

    /// "Smooth volume levels" (spec §4.2's M3 line): a downward compressor
    /// across the clip.
    ///
    /// Every control writes a whole `CompressorProps`, the way Ducking writes
    /// a whole `DuckProps` — the patch replaces the object, so each edit
    /// re-sends the other four values as they stand.
    ///
    /// The two times are in MILLISECONDS and are not snapped to the frame
    /// grid, unlike every other time in this pane. A compressor's attack is
    /// 10 ms where a frame is 33; snapping it would round the default to
    /// nothing. The core agrees — `check_audio` asks only that they are
    /// positive.
    func compressorSection() -> InspectorSection {
        let binding = self.binding
        func current() -> CompressorProps { binding.audioProps.compressor ?? CompressorProps() }
        func ops(_ next: CompressorProps) -> [ReelOp] {
            binding.ops(audio: AudioPatch(compressor: .some(next)))
        }
        func on() -> Bool { binding.audioProps.compressor != nil }
        func ticks(_ milliseconds: Double) -> Ticks {
            Ticks((max(milliseconds, 0) / 1000 * Double(ReelTime.perSecond)).rounded())
        }
        func milliseconds(_ ticks: Ticks) -> Double {
            Double(ticks) / Double(ReelTime.perSecond) * 1000
        }
        return InspectorSection(
            id: "audio.compressor", title: "Compressor",
            summary: { on() ? String(format: "%.1f:1", current().ratio) : "off" },
            reset: { binding.apply("Compressor", audio: AudioPatch(compressor: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Smooth volume levels", binding, name: "Compressor",
                    read: on,
                    ops: { value in
                        binding.ops(
                            audio: AudioPatch(
                                compressor: value ? .some(CompressorProps()) : .some(nil)))
                    },
                    mixed: { binding.mixedAudio { $0.compressor != nil } }),
                inspectorValueRow(
                    "Threshold", binding, name: "Compressor Threshold", unit: " dB", decimals: 1,
                    min: -60, max: 0, quick: [-30, -24, -18, -12, -6],
                    read: { current().thresholdDb },
                    ops: { value in
                        ops(
                            CompressorProps(
                                thresholdDb: value, ratio: current().ratio,
                                attack: current().attack, release: current().release,
                                makeupDb: current().makeupDb))
                    },
                    enabled: on),
                inspectorValueRow(
                    "Ratio", binding, name: "Compressor Ratio", unit: ":1", decimals: 1, min: 1,
                    max: 20, quick: [1.5, 2, 3, 4, 8, 20],
                    read: { current().ratio },
                    ops: { value in
                        ops(
                            CompressorProps(
                                thresholdDb: current().thresholdDb, ratio: value,
                                attack: current().attack, release: current().release,
                                makeupDb: current().makeupDb))
                    },
                    enabled: on),
                inspectorValueRow(
                    "Attack", binding, name: "Compressor Attack", unit: " ms", decimals: 0, min: 0,
                    max: 200, quick: [1, 5, 10, 30, 100],
                    read: { milliseconds(current().attack) },
                    ops: { value in
                        ops(
                            CompressorProps(
                                thresholdDb: current().thresholdDb, ratio: current().ratio,
                                attack: ticks(value), release: current().release,
                                makeupDb: current().makeupDb))
                    },
                    enabled: on),
                inspectorValueRow(
                    "Release", binding, name: "Compressor Release", unit: " ms", decimals: 0,
                    min: 10, max: 2000, quick: [50, 100, 200, 500, 1000],
                    read: { milliseconds(current().release) },
                    ops: { value in
                        ops(
                            CompressorProps(
                                thresholdDb: current().thresholdDb, ratio: current().ratio,
                                attack: current().attack, release: ticks(value),
                                makeupDb: current().makeupDb))
                    },
                    enabled: on),
                inspectorValueRow(
                    "Makeup", binding, name: "Compressor Makeup", unit: " dB", decimals: 1, min: 0,
                    max: 24, quick: [0, 3, 6, 12],
                    read: { current().makeupDb },
                    ops: { value in
                        ops(
                            CompressorProps(
                                thresholdDb: current().thresholdDb, ratio: current().ratio,
                                attack: current().attack, release: current().release,
                                makeupDb: value))
                    },
                    enabled: on),
            ])
    }

    // MARK: Mix

    /// Pan lives here rather than in a section of its own because it is a
    /// placement control, next to the other one.
    ///
    /// It is a BALANCE on a stereo clip — one gain per channel, unity at the
    /// centre, constant power across the sweep (`AudioPanLaw`) — and it is
    /// inaudible on a clip whose source is mono, because the widening to
    /// stereo happens after the point where the pan is applied. The read-out
    /// says which side, so "0" is never ambiguous.
    func mixSection() -> InspectorSection {
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
            summary: {
                let pan = binding.audioProps.pan
                if abs(pan) < 0.005 { return binding.audioProps.mono ? "mono" : "centre" }
                return String(format: "%@ %.0f", pan < 0 ? "left" : "right", abs(pan) * 100)
            },
            reset: { binding.apply("Mix", audio: AudioPatch(mono: false, pan: 0)) },
            defaultExpanded: false,
            rows: [
                inspectorValueRow(
                    "Pan", binding, name: "Pan", unit: "", decimals: 0, min: -100, max: 100,
                    quick: [-100, -50, 0, 50, 100],
                    read: { binding.audioProps.pan * 100 },
                    ops: { binding.ops(audio: AudioPatch(pan: $0 / 100)) },
                    mixed: { binding.mixedAudio { $0.pan } }),
                inspectorRow(
                    "Position",
                    [
                        inspectorReadout {
                            let pan = binding.audioProps.pan
                            if abs(pan) < 0.005 { return "centre" }
                            return String(
                                format: "%@ %.0f", pan < 0 ? "left" : "right", abs(pan) * 100)
                        }
                    ]),
                inspectorCheckRow(
                    "Mix to mono", binding, name: "Mix to Mono",
                    read: { binding.audioProps.mono },
                    ops: { binding.ops(audio: AudioPatch(mono: $0)) },
                    mixed: { binding.mixedAudio { $0.mono } }),
                inspectorButtonRow([detach]),
            ])
    }
}
