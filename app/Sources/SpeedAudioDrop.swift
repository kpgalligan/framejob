import AppKit

/// The question a person is asked before a speed change takes a clip with
/// sound above the core's audio ceiling (#212, spec §11 #190's "The
/// question"), and the sentence an agent reads instead.
///
/// **A crossing is read off the core's answer, never predicted.** The ops are
/// applied to the immutable handle (the trial the Speed sheet's readout
/// already runs, spec §11 D4-6) and the two snapshots are compared: a clip
/// that plays at or below `audio_max` before and above it after, with its
/// audio enabled and media that has sound. No rate is computed here (D2-1),
/// and no Swift file types the ceiling — it is `ReelSpeed.limits.audioMax`.
///
/// A clip that is new in the answer (a split's half, a duplicate, a detach)
/// never counts, and one already above the ceiling is not asked about again.
/// A clip's rate here is its PEAK (`peakSpeed`): a speed ramp (spec §11
/// SR-10) leaves the audio out when any rate it names is above the
/// ceiling, as the core's plan does (SR-19 (d)).
/// Nothing here is a refusal: Set Speed applies the edit exactly as it would
/// have been applied without the question.
enum SpeedAudioDrop {
    /// A clip the edit takes above the ceiling. `name` is the after
    /// snapshot's `name(of:)`; `speed` is the clip's NEW peak rate as the
    /// core answered it.
    struct Clip: Equatable {
        let id: UInt32
        let name: String
        let speed: Double
    }

    /// True when any op is one that can change a speed.
    static func mayCross(_ ops: [ReelOp]) -> Bool {
        ops.contains { $0.name == "set_speed" || $0.name == "rate_stretch" }
    }

    /// Every clip, on the timeline or in a nest, whose audio `after` leaves
    /// out and `before` did not. Sorted by id.
    static func crossing(
        from before: ProjectSnapshot, to after: ProjectSnapshot,
        limits: SpeedLimits = ReelSpeed.limits
    ) -> [Clip] {
        var earlier: [UInt32: Double] = [:]
        for clip in before.clips + before.nests.flatMap(\.clips) {
            earlier[clip.id] = peakSpeed(of: clip, limits: limits)
        }
        var found: [Clip] = []
        for clip in after.clips + after.nests.flatMap(\.clips) {
            let peak = peakSpeed(of: clip, limits: limits)
            guard clip.source.hasSourceBound, clip.enabled.audio,
                after.media(for: clip)?.hasAudio == true,
                peak > limits.audioMax,
                let was = earlier[clip.id], was <= limits.audioMax
            else { continue }
            found.append(Clip(id: clip.id, name: after.name(of: clip), speed: peak))
        }
        return found.sorted { $0.id < $1.id }
    }

    /// The greatest rate a clip names: its speed, or any action's end
    /// rate (spec §11 SR-10, SR-19 (d)), never computed. As the core's plan reads it,
    /// only a `media` clip ramps, and an end rate is clamped to the speed
    /// limits (a hand-written one may lie outside them).
    static func peakSpeed(
        of clip: ClipSnapshot, limits: SpeedLimits = ReelSpeed.limits
    ) -> Double {
        guard clip.source.hasSourceBound else { return clip.speed }
        return clip.actions.compactMap(\.end.speed)
            .filter(\.isFinite)
            .map { Swift.min(Swift.max($0, limits.min), limits.max) }
            .reduce(clip.speed, Swift.max)
    }

    /// The crossing `ops` would make on `project`: [] unless the core answers
    /// `.applied` (an identity, a refusal and a throw all change nothing).
    static func crossing(
        applying ops: [ReelOp], to project: ReelProject,
        limits: SpeedLimits = ReelSpeed.limits
    ) -> [Clip] {
        guard case .applied(let after)? = try? project.applying(ops) else { return [] }
        return crossing(from: project.snapshot, to: after.snapshot, limits: limits)
    }

    /// "×12": the ceiling as the inspector's note spells it.
    static func ceiling(_ limits: SpeedLimits) -> String {
        rate(limits.audioMax)
    }

    private static func rate(_ value: Double) -> String {
        "×" + String(format: "%g", value)
    }

    /// The alert's message and detail.
    static func question(
        _ clips: [Clip], limits: SpeedLimits = ReelSpeed.limits
    ) -> (message: String, detail: String) {
        let ceiling = Self.ceiling(limits)
        guard clips.count > 1 else {
            let name = clips.first?.name ?? ""
            let speed = clips.first.map { rate($0.speed) } ?? ceiling
            return (
                "“\(name)” will be silent at \(speed).",
                "Frame Job leaves a clip’s audio out above \(ceiling). The picture still plays."
            )
        }
        let speeds = Set(clips.map { rate($0.speed) })
        let at = speeds.count == 1 ? (speeds.first ?? "") : "their new speeds"
        return (
            "\(clips.count) clips will be silent at \(at).",
            "Frame Job leaves a clip’s audio out above \(ceiling). The pictures still play."
        )
    }

    /// The sentence an agent's answer carries in place of the question.
    static func note(_ clips: [Clip], limits: SpeedLimits = ReelSpeed.limits) -> String {
        let ceiling = Self.ceiling(limits)
        guard clips.count > 1 else {
            let id = clips.first.map { String($0.id) } ?? ""
            let name = clips.first?.name ?? ""
            return "Clip \(id) (“\(name)”) now plays above \(ceiling), so its audio is left "
                + "out: it is silent in the preview and the export."
        }
        let ids = clips.map { String($0.id) }
        let listed = ids.dropLast().joined(separator: ", ") + " and " + (ids.last ?? "")
        return "Clips \(listed) now play above \(ceiling), so their audio is left out: they "
            + "are silent in the preview and the export."
    }

    /// The keys an op tool's answer gains: none when nothing crossed.
    static func answerFields(
        from before: ProjectSnapshot, to after: ProjectSnapshot,
        limits: SpeedLimits = ReelSpeed.limits
    ) -> [String: Any] {
        let clips = crossing(from: before, to: after, limits: limits)
        guard !clips.isEmpty else { return [:] }
        return [
            "audio_left_out": clips.map { Int($0.id) },
            "audio_note": note(clips, limits: limits),
        ]
    }

    /// The question, as an alert sheet on `window`: "Set Speed" (the
    /// default) or "Cancel". `answer(true)` only for Set Speed. A sheet's
    /// completion is not an AppKit event, so a caller commits through
    /// `performGroupedEdit` (app/CLAUDE.md's undo pitfall).
    static func ask(
        _ clips: [Clip], on window: NSWindow, limits: SpeedLimits = ReelSpeed.limits,
        answer: @escaping (Bool) -> Void
    ) {
        let text = question(clips, limits: limits)
        let alert = NSAlert()
        alert.messageText = text.message
        alert.informativeText = text.detail
        alert.addButton(withTitle: "Set Speed")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            answer(response == .alertFirstButtonReturn)
        }
    }
}
