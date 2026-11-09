import AppKit

/// The volume line's model (road map "audio" AP8a, spec §11 AU-80…AU-84): the
/// dB scale it is drawn on, the plan's envelope per clip, what a press on it
/// edits, the ops a point is made of, and the drag's session. The drawing and
/// the gesture's wiring are `TimelineView+VolumeLine.swift`.
///
/// **The line is a view of actions** (AU-80): a point is an action's END
/// (`end.audio.volume`), a drag writes `set_audio {volume}` or that end, and
/// nothing is persisted that actions do not already persist.

/// The line's dB scale (AU-81): +30.103 dB (`AudioNormalize.maxGain`, ×32) at
/// the top of `rect`, −60 dB at its bottom. A gain at or under 0.001 draws at
/// the bottom, one above 32 (a track's volume can carry the plan there,
/// AU-103) at the top. `rect` is the line's rect inset 1 pt top and bottom,
/// in the timeline content view's flipped space (its top is `minY`).
struct VolumeScale: Equatable {
    static let topDB: Double = 20 * log10(AudioNormalize.maxGain)
    static let floorDB: Double = -60
    let rect: CGRect

    /// The y of `gain` (linear).
    func y(gain: Double) -> CGFloat {
        let db = gain > 0.001 ? 20 * log10(gain) : Self.floorDB
        let clamped = min(max(db, Self.floorDB), Self.topDB)
        let fraction = (Self.topDB - clamped) / (Self.topDB - Self.floorDB)
        return rect.minY + CGFloat(fraction) * rect.height
    }

    /// The dB a pointer travel of `deltaY` (press y minus pointer y, so
    /// positive is UP) spans on this scale.
    func decibels(deltaY: CGFloat) -> Double {
        guard rect.height > 0 else { return 0 }
        return Double(deltaY / rect.height) * (Self.topDB - Self.floorDB)
    }
}

/// One handle's plan, read for the line (AU-81): clip id → the ramps of the
/// plan audio track holding that clip's audio segment, cut to the segment.
/// Decoded lazily, at most once, as `DuckCurves` is (`DuckSpeech.swift`), so
/// a refresh that draws no line never pays for the plan.
final class VolumeLines {
    /// The handle the lines were read from — the timeline's own
    /// (`ProjectDocument.editedProject`), which a point's evaluated volume is
    /// read from too.
    let project: ReelProject
    private var byClip: [UInt32: [PlanRamp]]?

    init(_ project: ReelProject) {
        self.project = project
    }

    /// The clip's envelope in the handle's time, or nil when the plan has no
    /// audio segment for it.
    func ramps(for clip: UInt32) -> [PlanRamp]? {
        if byClip == nil { byClip = Self.read(project.plan) }
        return byClip?[clip]
    }

    private static func read(_ plan: CompositionPlan?) -> [UInt32: [PlanRamp]] {
        var found: [UInt32: [PlanRamp]] = [:]
        for track in plan?.audioTracks ?? [] {
            let ramps = track.ramps ?? []
            var spans: [UInt32: (start: Ticks, end: Ticks)] = [:]
            for segment in track.segments where segment.duration > 0 {
                let end = segment.start + segment.duration
                if let span = spans[segment.clip] {
                    spans[segment.clip] = (min(span.start, segment.start), max(span.end, end))
                } else {
                    spans[segment.clip] = (segment.start, end)
                }
            }
            for (clip, span) in spans where found[clip] == nil {
                found[clip] = cut(ramps, from: span.start, to: span.end)
            }
        }
        return found
    }

    /// `ramps` cut to `[from, to)`, each leg interpolated where it is cut.
    static func cut(_ ramps: [PlanRamp], from: Ticks, to: Ticks) -> [PlanRamp] {
        ramps.compactMap { ramp in
            let end = ramp.start + ramp.duration
            let start = max(ramp.start, from)
            let stop = min(end, to)
            guard stop > start else { return nil }
            func value(_ t: Ticks) -> Double {
                guard ramp.duration > 0 else { return ramp.to }
                let f = Double(t - ramp.start) / Double(ramp.duration)
                return ramp.from + (ramp.to - ramp.from) * f
            }
            return PlanRamp(start: start, duration: stop - start, from: value(start), to: value(stop))
        }
    }

    /// The gain the ramps give at `t`, or nil where none covers it. A ramp's
    /// end belongs to the next one; the last one's end is its own.
    static func gain(at t: Ticks, in ramps: [PlanRamp]) -> Double? {
        for ramp in ramps where ramp.start <= t && t < ramp.start + ramp.duration {
            let f = Double(t - ramp.start) / Double(max(ramp.duration, 1))
            return ramp.from + (ramp.to - ramp.from) * f
        }
        if let last = ramps.last, t == last.start + last.duration { return last.to }
        return nil
    }
}

extension PlanRamp {
    init(start: Ticks, duration: Ticks, from: Double, to: Double) {
        self.start = start
        self.duration = duration
        self.from = from
        self.to = to
    }
}

/// What a drag on the line edits (AU-82): the clip's base volume, or an
/// action's end; each with the value it starts from.
enum VolumeLineTarget: Equatable {
    case base(volume: Double)
    case end(action: UInt32, volume: Double)

    var volume: Double {
        switch self {
        case .base(let volume), .end(_, let volume): return volume
        }
    }
}

enum VolumeLine {
    /// AU-82: inside an action naming `end.audio.volume` → that action; else
    /// the latest action ENDED at or before `clipTime` naming it; else the base.
    static func target(of clip: ClipSnapshot, at clipTime: Ticks) -> VolumeLineTarget {
        let naming = clip.actions.filter { $0.end.audio?.volume != nil }
        if let inside = naming.first(where: { $0.start <= clipTime && clipTime < $0.endTime }),
           let volume = inside.end.audio?.volume {
            return .end(action: inside.id, volume: volume)
        }
        if let held = naming.filter({ $0.endTime <= clipTime }).max(by: { $0.endTime < $1.endTime }),
           let volume = held.end.audio?.volume {
            return .end(action: held.id, volume: volume)
        }
        return .base(volume: clip.audioProps.volume)
    }

    /// AU-83: the ops BEFORE the dragged end, the action whose end is
    /// dragged and the value it starts at; nil where a point cannot go (the
    /// caller beeps). `clipTime` is snapped to the frame here.
    static func point(
        on clip: ClipSnapshot, at clipTime: Ticks, project: ReelProject, nextId: UInt32, fps: Fps
    ) -> (prefix: [ReelOp], action: UInt32, volume: Double)? {
        let frame = max(fps.frameDuration, 1)
        guard clipTime >= 0, clipTime < clip.duration else { return nil }
        let t = min(
            ReelTime.snapToFrame(clipTime, fps: fps),
            TimelineTranscript.frameFloor(clip.duration - 1, fps: fps))
        guard let volume = (project.clipState(clip.id, at: clip.start + t)?["audio"]
                  as? [String: Any])?["volume"] as? Double
        else { return nil }
        if let inside = clip.actions.first(where: { $0.start <= t && t < $0.endTime }) {
            // An action a trim left running past the clip's end: `add_action`
            // would refuse its second half (`action_past_end`), silently.
            guard let end = inside.end.audio?.volume, namesOnlyVolume(inside.end),
                  t - inside.start >= frame, inside.endTime <= clip.duration
            else { return nil }
            var prefix: [ReelOp] = [
                .setAction(clip: clip.id, action: inside.id, duration: t - inside.start),
                .addAction(clip: clip.id, at: t, duration: inside.endTime - t),
                .setActionEnd(
                    clip: clip.id, action: nextId,
                    patch: ActionPatch(audio: AudioPatch(volume: end))),
            ]
            if inside.curve != .linear {
                prefix.append(.setAction(clip: clip.id, action: nextId, curve: inside.curve))
            }
            return (prefix, inside.id, volume)
        }
        let prevEnd = clip.actions.map(\.endTime).filter { $0 <= t }.max() ?? 0
        guard t - prevEnd >= frame else { return nil }
        return ([.addAction(clip: clip.id, at: prevEnd, duration: t - prevEnd)], nextId, volume)
    }

    /// An end patch whose only key is `audio.volume`.
    static func namesOnlyVolume(_ end: ActionPatch) -> Bool {
        guard let volume = end.audio?.volume else { return false }
        return end.video == nil && end.text == nil && end.graphic == nil && end.speed == nil
            && end.audio == AudioPatch(volume: volume)
    }

    /// AU-82: 0 at the bottom; else `start` (at least 0.001, so a silent
    /// value can be raised) moved by `decibels`, held to `check_audio`'s
    /// 0…32. `atBottom` is the caller's "pointer below the press and at the
    /// scale's `maxY − 1` or lower".
    static func volume(from start: Double, decibels: Double, atBottom: Bool) -> Double {
        if atBottom { return 0 }
        return min(max(max(start, 0.001) * pow(10, decibels / 20), 0), AudioNormalize.maxGain)
    }

    /// The drag's readout: "+2.5 dB", one decimal, "−∞ dB" at 0.
    static func readout(_ volume: Double) -> String {
        guard volume > 0 else { return "\u{2212}\u{221E} dB" }
        let db = 20 * log10(volume)
        let text = String(format: "%.1f", abs(db))
        if text == "0.0" { return "0.0 dB" }
        return (db < 0 ? "\u{2212}" : "+") + text + " dB"
    }
}

/// One drag on the line (AU-82, AU-83): the ops each tick sends are the
/// point's `prefix` (empty for a plain drag) and the write of `volume` to the
/// target.
struct VolumeLineSession {
    let clip: UInt32
    let target: VolumeLineTarget
    let prefix: [ReelOp]
    let pressY: CGFloat
    let scale: VolumeScale
    var volume: Double
    /// The pointer, for the readout.
    var point: CGPoint

    var ops: [ReelOp] {
        switch target {
        case .base:
            return prefix + [.setAudio(clips: [clip], patch: AudioPatch(volume: volume))]
        case .end(let action, _):
            return prefix + [.setActionEnd(
                clip: clip, action: action, patch: ActionPatch(audio: AudioPatch(volume: volume)))]
        }
    }

    var undoName: String { prefix.isEmpty ? "Set Volume" : "Add Volume Point" }

    mutating func update(y: CGFloat) {
        volume = VolumeLine.volume(
            from: target.volume, decibels: scale.decibels(deltaY: pressY - y),
            atBottom: y > pressY && y >= scale.rect.maxY - 1)
    }
}

extension TimelineHit {
    /// AU-84: a press on the line with ⇧ held (toggle membership, ⌥⇧ slip)
    /// or a double-click (rename) is the clip's own; anything else unchanged.
    func resolvingVolumeLine(flags: NSEvent.ModifierFlags, clicks: Int) -> TimelineHit {
        guard case .volumeLine(let clip, _) = self,
              flags.contains(.shift) || clicks == 2
        else { return self }
        return .clip(clip)
    }
}
