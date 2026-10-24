import AppKit

extension VideoPane {
    // MARK: Speed

    /// Speed is a clip-level op, not a patch: `set_speed` takes one clip and
    /// re-times its actions (§6), so the selection becomes one op each and the
    /// whole batch is a single undo step. The one exception is Rate (and the
    /// section's Reset) with an action selected, which writes that action's
    /// `end.speed`, a speed ramp (spec §11 SR-21 (a)); Keep pitch and Fit to
    /// stay the clip's.
    ///
    /// Reverse used to sit here, next to Rate, because both re-time the same
    /// source. It now sits in the Clip tab's Timing section with In, Out and
    /// Duration, which is what the redesign asks for and reads better anyway:
    /// Rate is how fast, Reverse is which way, and the duration readout the
    /// two of them share belongs with the edges it is measured between.
    func speedSection() -> InspectorSection {
        let binding = self.binding
        return InspectorSection(
            id: "video.speed", title: "Speed",
            summary: { String(format: "%.2f×", Self.rateRead(binding)) },
            reset: { binding.apply("Set Speed", Self.rateOps(binding, rate: 1)) },
            differs: { Self.rateRead(binding) != 1 },
            defaultExpanded: false,
            rows: [
                inspectorValueRow(
                    "Rate", binding, name: "Set Speed", unit: "×", decimals: 2,
                    min: ReelSpeed.limits.min, max: ReelSpeed.limits.max,
                    quick: [0.5, 1, 2, 4], slider: false,
                    read: { Self.rateRead(binding) },
                    ops: { Self.rateOps(binding, rate: $0) },
                    mixed: { binding.mixed { $0.speed } }, resets: false),
                inspectorCheckRow(
                    "Keep pitch", binding, name: "Keep Pitch",
                    read: { binding.audioProps.keepPitch },
                    ops: { value in
                        Self.speedOps(binding, Self.baseRate(binding), keepPitch: value)
                    },
                    mixed: { binding.mixedAudio { $0.keepPitch } }),
                fitRow(),
                MotionInactiveNote(note: {
                    Self.silentAudioNote(
                        for: binding.clips, in: binding.snapshot, limits: ReelSpeed.limits)
                }),
            ])
    }

    /// The first selected clip's BASE rate, ×1 when it is not positive: what
    /// Keep pitch re-sends with its switch, so a click inside an action never
    /// writes the action's rate onto the clip (spec §11 SR-21 (a)).
    static func baseRate(_ binding: InspectorBinding) -> Double {
        let value = binding.primary?.speed ?? 1
        return value > 0 ? value : 1
    }

    /// What Rate shows: the first selected clip's `speed(_:)` in the
    /// binding's mode — the selected action's end rate, else the core's rate
    /// in force there, else the base (spec §11 SR-21 (b)); ×1 when it is not
    /// positive.
    static func rateRead(_ binding: InspectorBinding) -> Double {
        let value = binding.primary.map { binding.speed($0) } ?? 1
        return value > 0 ? value : 1
    }

    /// Rate's write (spec §11 SR-21 (a)): with an action selected on the one
    /// selected media clip, that action's `end.speed` — one `set_action_end`;
    /// otherwise one `set_speed` per selected media clip, as before.
    static func rateOps(_ binding: InspectorBinding, rate: Double) -> [ReelOp] {
        if binding.isSingle, let clip = binding.primary, clip.source.hasSourceBound,
            let action = binding.action(clip)
        {
            return [.setActionEnd(clip: clip.id, action: action.id, patch: ActionPatch(speed: rate))]
        }
        return speedOps(binding, rate, keepPitch: nil)
    }

    /// One `set_speed` per selected media clip: the clip's own rate, whatever
    /// action is selected.
    private static func speedOps(
        _ binding: InspectorBinding, _ next: Double, keepPitch: Bool?
    ) -> [ReelOp] {
        binding.clips.filter { $0.source.hasSourceBound }
            .map { .setSpeed(clip: $0.id, rate: next, keepPitch: keepPitch) }
    }

    /// "Fit to": type a length and the rate changes so each selected media
    /// clip plays in it (`set_speed`'s duration arm, spec §11 #190).
    ///
    /// **It binds by the ids captured here**, `ClipPane+Timing.swift`'s rule:
    /// the field commits on blur, and a blur the rebuild causes would
    /// otherwise write to whichever clip was clicked next.
    private func fitRow() -> NSView {
        let binding = self.binding
        let ids = binding.clips.filter { $0.source.hasSourceBound }.map(\.id)
        let field = InspectorTimecodeField(
            read: { ids.first.flatMap { binding.snapshot.clip($0) }?.duration ?? 0 },
            write: { binding.apply("Fit to Duration", Self.fitOps(ids, duration: $0)) },
            fps: { binding.canvas.fps }, frames: { binding.canvas.timecodeFrames },
            onEdit: { binding.edited() })
        field.toolTip = "Type a length: the rate changes so the clip plays in it"
        // Its writes are the clip's (`set_speed`), so the row is ⊘ while an
        // action is selected (spec §11 SR-21 (a), CI-7).
        let length = ids.first.flatMap { binding.snapshot.clip($0) }?.duration ?? 0
        return inspectorRow(
            "Fit to", [field],
            mixed: { binding.mixed(ids.compactMap { binding.snapshot.clip($0) }) { $0.duration } },
            binding: binding, writes: Self.fitOps(ids, duration: length))
    }

    /// The Speed section's note when a selected clip's audio has been left out
    /// of the mix: the first media clip with sound, its audio enabled, whose
    /// speed is above the audio ceiling, in either pitch mode (spec §11 #190).
    /// A clip's speed here is the greatest rate it names (`peakSpeed`, spec
    /// §11 SR-19 (d), SR-21 (e)), the figure the plan leaves its audio out by.
    /// Nil otherwise.
    static func silentAudioNote(
        for clips: [ClipSnapshot], in snapshot: ProjectSnapshot, limits: SpeedLimits
    ) -> String? {
        for clip in clips where clip.source.hasSourceBound && clip.enabled.audio {
            guard snapshot.media(for: clip)?.hasAudio == true else { continue }
            if SpeedAudioDrop.peakSpeed(of: clip, limits: limits) > limits.audioMax {
                return "Audio is silent above ×" + String(format: "%g", limits.audioMax)
            }
        }
        return nil
    }

    /// One `set_speed` duration arm per clip, so a multi-clip Fit is one undo
    /// step.
    static func fitOps(_ clips: [UInt32], duration: Ticks) -> [ReelOp] {
        clips.map { .setSpeed(clip: $0, duration: duration) }
    }
}
