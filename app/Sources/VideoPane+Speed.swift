import AppKit

extension VideoPane {
    // MARK: Speed

    /// Speed is a clip-level op, not a patch: `set_speed` takes one clip and
    /// re-times its actions (§6), so the selection becomes one op each and the
    /// whole batch is a single undo step.
    ///
    /// Reverse used to sit here, next to Rate, because both re-time the same
    /// source. It now sits in the Clip tab's Timing section with In, Out and
    /// Duration, which is what the redesign asks for and reads better anyway:
    /// Rate is how fast, Reverse is which way, and the duration readout the
    /// two of them share belongs with the edges it is measured between.
    func speedSection() -> InspectorSection {
        let binding = self.binding
        func rate() -> Double {
            let value = binding.primary?.speed ?? 1
            return value > 0 ? value : 1
        }
        func speedOps(_ next: Double, keepPitch: Bool?) -> [ReelOp] {
            binding.clips.filter { $0.source.hasSourceBound }
                .map { .setSpeed(clip: $0.id, rate: next, keepPitch: keepPitch) }
        }
        return InspectorSection(
            id: "video.speed", title: "Speed",
            summary: { String(format: "%.2f×", rate()) },
            reset: { binding.apply("Set Speed", speedOps(1, keepPitch: nil)) },
            differs: { rate() != 1 },
            defaultExpanded: false,
            rows: [
                inspectorValueRow(
                    "Rate", binding, name: "Set Speed", unit: "×", decimals: 2,
                    min: ReelSpeed.limits.min, max: ReelSpeed.limits.max,
                    quick: [0.5, 1, 2, 4], slider: false,
                    read: rate,
                    ops: { speedOps($0, keepPitch: nil) },
                    mixed: { binding.mixed { $0.speed } }, resets: false),
                inspectorCheckRow(
                    "Keep pitch", binding, name: "Keep Pitch",
                    read: { binding.audioProps.keepPitch },
                    ops: { value in speedOps(rate(), keepPitch: value) },
                    mixed: { binding.mixedAudio { $0.keepPitch } }),
                fitRow(),
                MotionInactiveNote(note: {
                    Self.silentAudioNote(
                        for: binding.clips, in: binding.snapshot, limits: ReelSpeed.limits)
                }),
            ])
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
        return inspectorRow(
            "Fit to", [field],
            mixed: { binding.mixed(ids.compactMap { binding.snapshot.clip($0) }) { $0.duration } })
    }

    /// The Speed section's note when a selected clip's audio has been left out
    /// of the mix: the first media clip with sound, its audio enabled, whose
    /// speed is above the audio ceiling, in either pitch mode (spec §11 #190).
    /// Nil otherwise.
    static func silentAudioNote(
        for clips: [ClipSnapshot], in snapshot: ProjectSnapshot, limits: SpeedLimits
    ) -> String? {
        for clip in clips where clip.source.hasSourceBound && clip.enabled.audio {
            guard snapshot.media(for: clip)?.hasAudio == true else { continue }
            if clip.speed > limits.audioMax {
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
