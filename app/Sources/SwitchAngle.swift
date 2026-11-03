import Foundation

/// Switch Angle (road map "creator-jobs" SW1, spec §11 SW-13…SW-15): which
/// tracks are angles for a shot, and the sequence that re-picks the shot from
/// one. Clip ▸ Switch Angle ▸ (`EditorViewController+SwitchAngle.swift`) and
/// `switch_angle` (`AgentServer+Switch.swift`) both run it. It names no
/// `rc_*`: every op is tried through `ReelProject.applying(_:)`.
///
/// **Covering (SW-13, SW-15 (d)).** A track covers a span when its media
/// clips with a picture (`sourceSize(of:) != nil`) leave no tick of it
/// uncovered; a clip with its picture switched off, or on a hidden track,
/// still counts.
///
/// **The re-pick (SW-14, SW-15 (e)).** With B the shot between A and C on its
/// track: `delete` B, trim A's end to B's start and C's start to B's end
/// (each `alone`), one `copy_pieces` per angle clip the span crosses (B's
/// switches), then A and C trimmed back to their old edges and the two
/// transitions put back. The ops are tried one at a time on the container's
/// handle, because `applying([ReelOp])` does not stop at a refusal: a refusal
/// before the trim-backs, or a trim away held short of its target, refuses
/// the whole plan and nothing is committed; a trim-back that is refused or
/// held short is left out with its edge's transition, and the step is named
/// "Switch Angle (transition removed)".
enum SwitchAngle {
    /// One row of Clip ▸ Switch Angle ▸.
    struct Angle: Equatable {
        let track: UInt32
        let title: String
    }

    /// The most rows the submenu lists.
    static let menuLimit = 9
    static let actionName = "Switch Angle"
    static let removedName = "Switch Angle (transition removed)"

    /// The ops of a re-pick, its step's name, the new pieces' ids in time
    /// order, and how many of the shot's two transitions were dropped.
    struct Plan {
        let ops: [ReelOp]
        let actionName: String
        let pieces: [UInt32]
        let transitionsRemoved: Int
    }

    enum Answer {
        case plan(Plan)
        case refused(String)
    }

    /// The media clips with a picture on `track`, by start.
    static func pictureClips(on track: UInt32, in snapshot: ProjectSnapshot) -> [ClipSnapshot] {
        snapshot.clips(onTrack: track).filter { clip in
            guard case .media = clip.source else { return false }
            return snapshot.sourceSize(of: clip) != nil
        }
    }

    /// The first tick of `[from, to)` no picture clip on `track` covers, or
    /// nil when the track covers the whole span.
    static func firstUncovered(
        track: UInt32, from: Ticks, to: Ticks, in snapshot: ProjectSnapshot
    ) -> Ticks? {
        var reached = from
        for clip in pictureClips(on: track, in: snapshot) where clip.end > reached {
            if clip.start > reached { return reached }
            reached = clip.end
            if reached >= to { return nil }
        }
        return reached < to ? reached : nil
    }

    /// Every other track of the container covering `clip`'s whole span, front
    /// first, at most `menuLimit`. A name two listed tracks share gets " (n)",
    /// n the track's 1-based position from the back.
    static func angles(for clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> [Angle] {
        let covering = snapshot.tracks.reversed()
            .filter {
                $0.id != clip.track
                    && firstUncovered(track: $0.id, from: clip.start, to: clip.end, in: snapshot)
                        == nil
            }
            .prefix(menuLimit)
        let names = covering.map(\.name)
        return covering.map { track in
            guard names.filter({ $0 == track.name }).count > 1 else {
                return Angle(track: track.id, title: track.name)
            }
            let position = (snapshot.trackIndex(of: track.id) ?? 0) + 1
            return Angle(track: track.id, title: "\(track.name) (\(position))")
        }
    }

    /// Re-picks clip `id` from track `angle` in `container` (the handle of
    /// the container being edited). Throws for an unknown clip or track.
    static func plan(clip id: UInt32, angle: UInt32, in container: ReelProject) throws -> Answer {
        let snapshot = container.snapshot
        guard let shot = snapshot.clip(id) else {
            throw ReelCoreError(message: "no clip with id \(id)")
        }
        guard snapshot.track(angle) != nil else {
            throw ReelCoreError(message: "no track with id \(angle)")
        }
        if let why = refusal(shot, angle: angle, in: snapshot) { return .refused(why) }

        let (s, e) = (shot.start, shot.end)
        let neighbours = snapshot.clips(onTrack: shot.track).filter { $0.id != shot.id }
        let before = neighbours.last { $0.start < s && $0.end > s }
        let after = neighbours.first { $0.start > s && $0.start < e }
        var trial = Trial(project: container)

        if let why = try trial.require(.delete(clips: [id])) { return .refused(why) }
        if let a = before {
            if let why = try trial.require(.trimEnd(clip: a.id, to: s, alone: true)) {
                return .refused(why)
            }
            let reached = trial.project.snapshot.clip(a.id)?.end ?? a.end
            if reached != s { return .refused(held(a.id, reached, s, shot: id)) }
        }
        if let c = after {
            if let why = try trial.require(.trimStart(clip: c.id, to: e, alone: true)) {
                return .refused(why)
            }
            let reached = trial.project.snapshot.clip(c.id)?.start ?? c.start
            if reached != e { return .refused(held(c.id, reached, e, shot: id)) }
        }
        for range in pieceRanges(angle: angle, from: s, to: e, in: snapshot) {
            let op = ReelOp.copyPieces(
                clip: range.clip, track: shot.track, ranges: [(range.from, range.to)],
                video: shot.enabled.video, audio: shot.enabled.audio)
            if let why = try trial.require(op) { return .refused(why) }
        }
        let known = Set(snapshot.clips.map(\.id))
        let pieces = trial.project.snapshot.clips(onTrack: shot.track)
            .filter { !known.contains($0.id) }.map(\.id)

        var removed = 0
        if let a = before, let first = pieces.first {
            let back = ReelOp.trimEnd(clip: a.id, to: a.end, alone: true)
            if try trial.attempt(back, holds: { $0.clip(a.id)?.end == a.end }) {
                try trial.putBack(shot.transitionIn, on: first)
            } else {
                removed += 1
                try trial.clearTransition(on: first)
            }
        }
        if let c = after, !pieces.isEmpty {
            let back = ReelOp.trimStart(clip: c.id, to: c.start, alone: true)
            if try trial.attempt(back, holds: { $0.clip(c.id)?.start == c.start }) {
                try trial.putBack(c.transitionIn, on: c.id)
            } else {
                removed += 1
                try trial.clearTransition(on: c.id)
            }
        }
        return .plan(
            Plan(
                ops: trial.ops, actionName: removed > 0 ? removedName : actionName,
                pieces: pieces, transitionsRemoved: removed))
    }

    /// SW-15 (c)'s refusals, in order.
    private static func refusal(
        _ shot: ClipSnapshot, angle: UInt32, in snapshot: ProjectSnapshot
    ) -> String? {
        if angle == shot.track {
            return "track \(angle) is clip \(shot.id)'s own track; an angle is another track"
        }
        if snapshot.track(shot.track)?.locked == true {
            return "track \(shot.track) is locked, so clip \(shot.id) cannot be re-picked"
        }
        if let partner = shot.linked {
            return "clip \(shot.id) is linked to clip \(partner) (Detach Audio's pair); "
                + "Switch Angle re-picks a clip with no link"
        }
        if let tick = firstUncovered(track: angle, from: shot.start, to: shot.end, in: snapshot) {
            return "track \(angle) does not cover clip \(shot.id): nothing with a picture "
                + "plays on it at tick \(tick)"
        }
        return nil
    }

    /// The held-trim sentence (SW-15 (e)).
    private static func held(_ clip: UInt32, _ reached: Ticks, _ target: Ticks, shot: UInt32)
        -> String
    {
        "clip \(clip)'s edge is held at tick \(reached), short of tick \(target), so clip "
            + "\(shot) cannot be re-picked"
    }

    /// Each angle clip crossing `[from, to)` and the part of it a piece takes:
    /// `[max(start, from), min(end, the next one's start, to))`, empty ones
    /// skipped (SW-15 (d)).
    static func pieceRanges(
        angle: UInt32, from: Ticks, to: Ticks, in snapshot: ProjectSnapshot
    ) -> [(clip: UInt32, from: Ticks, to: Ticks)] {
        let crossing = pictureClips(on: angle, in: snapshot)
            .filter { $0.end > from && $0.start < to }
        var out: [(clip: UInt32, from: Ticks, to: Ticks)] = []
        for (index, clip) in crossing.enumerated() {
            let next = index + 1 < crossing.count ? crossing[index + 1].start : to
            let low = max(clip.start, from)
            let high = min(clip.end, next, to)
            if high > low { out.append((clip.id, low, high)) }
        }
        return out
    }

    /// The handle the plan has reached and the ops that reached it.
    struct Trial {
        var project: ReelProject
        var ops: [ReelOp] = []

        /// Applies `op`; nil when it applied or changed nothing, else the
        /// rule's sentence (nothing kept).
        mutating func require(_ op: ReelOp) throws -> String? {
            switch try project.applying(op) {
            case .applied(let next):
                project = next
                ops.append(op)
                return nil
            case .identity:
                ops.append(op)
                return nil
            case .refused(let refusal):
                return refusal.reason
            }
        }

        /// Keeps `op` only when it applied and the result `holds`.
        mutating func attempt(_ op: ReelOp, holds: (ProjectSnapshot) -> Bool) throws -> Bool {
            guard case .applied(let next) = try project.applying(op), holds(next.snapshot)
            else { return false }
            project = next
            ops.append(op)
            return true
        }

        /// The kind and style of `transition` on `clip`, when there was one.
        mutating func putBack(_ transition: TransitionSnapshot?, on clip: UInt32) throws {
            guard let transition else { return }
            _ = try require(.setTransition(clip: clip, kind: transition.kind))
            _ = try require(
                .setTransitionStyle(
                    clip: clip, curve: transition.curve, audio: transition.audio,
                    audioShape: transition.audioShape))
        }

        /// A left-out edge's clip keeps no transition.
        mutating func clearTransition(on clip: UInt32) throws {
            guard project.snapshot.clip(clip)?.transitionIn != nil else { return }
            _ = try require(.setTransition(clip: clip, kind: nil))
        }
    }
}
