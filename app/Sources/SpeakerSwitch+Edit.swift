import Foundation

/// What Switch by Speaker writes (spec §11 SW-23): the planned shots as one undo step "Switch by
/// Speaker" on a Program track — a new one directly in front of the front-most angle, or the
/// named track cleared over the range (Replace the shots on) — with the angles hidden, or their
/// pictures switched off, inside the range only. Clip ▸ Switch by Speaker…
/// (`SwitchSpeakerSheetController`) and `switch_by_speaker` (`AgentServer+Switch.swift`) both
/// write through `edit`.
///
/// Every op is tried ONE at a time on the container's handle through `SwitchAngle.Trial`
/// (`applying([ReelOp])` does not stop at a refusal), so the ids a later op names — the Program
/// track's, a split's second half — are the ones the commit will mint, and the first refusal
/// refuses the whole switch with nothing committed. Names no `rc_*`.
extension SpeakerSwitch {
    static let programName = "Program"

    /// The ops, the Program track they write to, how many `copy_pieces` they hold, and the
    /// selection to set after them (SW-23 (f)).
    struct Edit {
        let ops: [ReelOp]
        let track: UInt32
        let copies: Int
        let selection: Set<UInt32>
    }

    enum EditAnswer {
        case edit(Edit)
        case refused(String)
    }

    /// SW-23 (g): two or more angles in SW-20's defaults, and a selected media clip whose sound
    /// is on and whose media has audio.
    static func canOffer(_ selection: [ClipSnapshot], in snapshot: ProjectSnapshot) -> Bool {
        guard defaults(selection: selection, in: snapshot).angles.count >= 2 else { return false }
        return selection.contains { clip in
            guard case .media = clip.source, clip.enabled.audio else { return false }
            return snapshot.media(for: clip)?.hasAudio == true
        }
    }

    /// SW-23 (d): "Mute the cameras' own sound" is on by default when no microphone is an angle.
    static func muteDefault(_ input: Input) -> Bool {
        let angles = Set(input.angles.map(\.track))
        return !input.microphones.contains { angles.contains($0.track) }
    }

    /// SW-23 (e): the tracks Replace the shots on may name, front first.
    static func replaceable(_ input: Input, selection: Set<UInt32>, in snapshot: ProjectSnapshot)
        -> [UInt32]
    {
        snapshot.tracks.reversed().map(\.id).filter {
            replaceRefusal($0, input: input, selection: selection, in: snapshot) == nil
        }
    }

    /// The first of SW-23 (e)'s tests `track` fails, in its sentence; nil when it qualifies.
    static func replaceRefusal(
        _ track: UInt32, input: Input, selection: Set<UInt32>, in snapshot: ProjectSnapshot
    ) -> String? {
        let lead = "Track \(track) cannot take the shots: "
        guard let found = snapshot.track(track) else { return "no track with id \(track)" }
        if found.locked { return lead + "it is locked." }
        let clips = snapshot.clips(onTrack: track)
        if clips.contains(where: { selection.contains($0.id) }) {
            return lead + "it holds a selected clip."
        }
        guard let front = input.angles.first?.track,
            let frontIndex = snapshot.trackIndex(of: front),
            let index = snapshot.trackIndex(of: track), index > frontIndex
        else { return lead + "it is not in front of the angles." }
        let over = clips.filter { $0.end > input.from && $0.start < input.to }
        if over.isEmpty {
            let a = ReelTime.format(input.from, fps: input.fps, frames: true)
            let b = ReelTime.format(input.to, fps: input.fps, frames: true)
            return lead + "it has nothing between \(a) and \(b) to replace."
        }
        let played = Set(
            input.angles.flatMap(\.clips).compactMap { snapshot.clip($0.clip)?.source.mediaID })
        if let stranger = over.first(where: { clip in
            guard case .media = clip.source, let media = clip.source.mediaID else { return true }
            return !played.contains(media)
        }) {
            return lead + "clip \(stranger.id) is not a piece of an angle."
        }
        return nil
    }

    /// SW-23's ops for `shots` (a `plan`'s, every shot's angle covering its span) over `input`'s
    /// range, tried on `container`, the handle of the container being edited. `replacing` is
    /// Replace's track, already through `replaceRefusal`. Throws only the core's invalid input.
    static func edit(
        _ shots: [Shot], input: Input, muteCameras: Bool, replacing: UInt32?,
        selection: Set<UInt32>, in container: ReelProject
    ) throws -> EditAnswer {
        let snapshot = container.snapshot
        let (from, to) = (input.from, input.to)
        let angles = input.angles.map(\.track)
        guard let front = angles.first, let frontIndex = snapshot.trackIndex(of: front) else {
            return .refused(
                "Switch by Speaker needs at least two angles: tracks holding a selected clip "
                    + "with a picture.")
        }

        // (h): a linked angle clip crossing the range, before any op.
        for track in angles {
            for clip in SwitchAngle.pictureClips(on: track, in: snapshot)
            where clip.end > from && clip.start < to {
                if let partner = clip.linked {
                    return .refused(
                        "clip \(clip.id) on track \(track) is linked to clip \(partner) (Detach "
                            + "Audio's pair); Switch by Speaker cuts between cameras with no link "
                            + "— Attach Audio first")
                }
            }
        }

        var trial = SwitchAngle.Trial(project: container)
        var chosen = selection
        func refusal(_ op: ReelOp) throws -> String? {
            try trial.require(op).map { "Switch by Speaker was refused at \(op.name): \($0)" }
        }
        /// Splits `clip` at `at`, a selected clip's new half joining the selection (f).
        func split(_ clip: ClipSnapshot, at: Ticks) throws -> String? {
            let known = Set(trial.project.snapshot.clips.map(\.id))
            if let why = try refusal(.split(clips: [clip.id], at: at)) { return why }
            if chosen.contains(clip.id) {
                chosen.formUnion(trial.project.snapshot.clips.map(\.id).filter { !known.contains($0) })
            }
            return nil
        }
        func inside(_ clip: ClipSnapshot) -> Bool { clip.start >= from && clip.end <= to }

        // (a) The destination.
        let destination: UInt32
        if let replacing {
            for at in [from, to] {
                for clip in trial.project.snapshot.clips(onTrack: replacing)
                where clip.start < at && at < clip.end {
                    if let why = try split(clip, at: at) { return .refused(why) }
                }
            }
            let cleared = trial.project.snapshot.clips(onTrack: replacing).filter(inside).map(\.id)
            if !cleared.isEmpty, let why = try refusal(.delete(clips: cleared)) {
                return .refused(why)
            }
            destination = replacing
        } else {
            let before = Set(snapshot.tracks.map(\.id))
            let add = ReelOp.addTrack(index: frontIndex + 1, name: programName)
            if let why = try refusal(add) { return .refused(why) }
            guard let made = trial.project.snapshot.tracks.first(where: { !before.contains($0.id) })
            else { return .refused("Switch by Speaker was refused at add_track: no track was added.") }
            destination = made.id
        }

        // (b) One copy_pieces per angle clip, in the order of its first range.
        var ranges: [UInt32: [(from: Ticks, to: Ticks)]] = [:]
        var order: [UInt32] = []
        for shot in shots {
            for piece in SwitchAngle.pieceRanges(
                angle: shot.angle, from: shot.start, to: shot.end, in: snapshot)
            {
                if ranges[piece.clip] == nil { order.append(piece.clip) }
                ranges[piece.clip, default: []].append((piece.from, piece.to))
            }
        }
        order.sort { (ranges[$0]?.first?.from ?? 0) < (ranges[$1]?.first?.from ?? 0) }
        for clip in order {
            let op = ReelOp.copyPieces(
                clip: clip, track: destination, ranges: ranges[clip] ?? [], video: true,
                audio: false)
            if let why = try refusal(op) { return .refused(why) }
        }

        // (c), (d) The angles, front first.
        let microphones = Set(input.microphones.map(\.track))
        for track in angles {
            let mute = muteCameras && !microphones.contains(track)
            let now = trial.project.snapshot
            let pictures = SwitchAngle.pictureClips(on: track, in: now)
            let ids = Set(pictures.map(\.id))
            let all = now.clips(onTrack: track)
            if !all.isEmpty, all.allSatisfy({ ids.contains($0.id) && inside($0) }) {
                if now.track(track)?.hidden != true,
                    let why = try refusal(.setTrack(track: track, hidden: true))
                {
                    return .refused(why)
                }
                for clip in pictures where mute && clip.enabled.audio {
                    if let why = try refusal(.setEnabled(clip: clip.id, audio: false)) {
                        return .refused(why)
                    }
                }
                continue
            }
            for at in [from, to] {
                for clip in SwitchAngle.pictureClips(on: track, in: trial.project.snapshot)
                where clip.start < at && at < clip.end {
                    if let why = try split(clip, at: at) { return .refused(why) }
                }
            }
            for clip in SwitchAngle.pictureClips(on: track, in: trial.project.snapshot)
            where inside(clip) {
                let video: Bool? = clip.enabled.video ? false : nil
                let audio: Bool? = mute && clip.enabled.audio ? false : nil
                guard video != nil || audio != nil else { continue }
                if let why = try refusal(.setEnabled(clip: clip.id, video: video, audio: audio)) {
                    return .refused(why)
                }
            }
        }
        return .edit(
            Edit(ops: trial.ops, track: destination, copies: order.count, selection: chosen))
    }
}
