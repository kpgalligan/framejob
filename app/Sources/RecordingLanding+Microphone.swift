// app/Sources/RecordingLanding+Microphone.swift — the microphone half of
// the landing (road map 3, R1b; per segment since R2b), a PURE MOVE out of
// `RecordingLanding.swift` landed alone at the 400-line cap (R2's toll) and
// then grown here: the name the microphone's track carries,
// `addMicrophones` (every stretch's voice on ONE back track,
// by the floor rule — a left-out segment's readable voice, #181 item 2,
// among them, its stretches in `+LeftOut`) and `addMicrophoneClip`, the
// head-trim dance with every step of it READ BACK. `remainderPlacement`
// (everything a fresh untitled document does not already hold) and the two
// undo steps' names are `+Remainder`'s since camera-recording CR3-0.
// `addMedia`, `view`, `clip(_:in:scope:)` and `trimmed` are internal in
// the base file for this one, and `placeBackToBack`, `placeClip`,
// `mediaEntry`, `tooShortNote` and `milliseconds` in `+Placing`, because
// `private` does not cross a file. `headTrimmed` is internal for the same
// reason since camera-recording CR3b: `+Camera`'s clips take the same dance
// (spec §11 CAM-10 (2)).

import AppKit

extension RecordingLanding {
    /// The new back track every microphone clip lands on — ONE track for the
    /// whole recording, added once, before the first voice that takes a
    /// frame, so a paused recording's voices sit in a row under its pictures
    /// as its pictures do, and a recording none of whose voices can be
    /// placed adds no empty track.
    static let microphoneTrackName = "Microphone"

    /// Every stretch's microphone (`voices(of:)`, one per segment and per
    /// left-out voice): each file's `add_media` in order, then — when
    /// `pictureStarts` is given, one per voice — ONE new back track and each
    /// voice's clip by the floor rule, in the same order. A nil
    /// `pictureStarts` is `place: false`: the media land and no clip does,
    /// R1's rule; a nil ENTRY lands that voice as media only. Answers one
    /// media id and one clip id PER VOICE, nil where it has no file, or
    /// where it minted no clip — too short for a frame, or wholly under the
    /// previous voice, each with its sentence in `notes`.
    ///
    /// **The floor.** Segment `k`'s voice belongs at `pictureStart_k −
    /// micOffset_k`, and with one voice that is R1's rule exactly, floored at
    /// 0. With several, two voices on one track can neither overlap — a
    /// refusal, or worse a sub-frame overlap the rule ACCEPTS as a
    /// transition, minting a cross dissolve between two halves of one
    /// recording — nor be placed late (the same wrong sound as R1's negative
    /// start put at 0), so the floor for voice `k` is the previous voice's
    /// END, and a start below it is head-trimmed to it by the same dance.
    /// The floor is READ off the trial, never computed: the previous clip's
    /// end is on the frame grid because the core snapped its start and its
    /// length, and a sum over descriptor durations would not be. (At an
    /// inexact rate even that end is not a grid point, and `placeClip` steps
    /// the add up a frame when the core snaps under it.)
    ///
    /// The track is added on the attempt of the FIRST voice that takes a
    /// frame, and kept only when that voice lands: a voice that mints no
    /// clip discards its attempt whole, so a recording with no placeable
    /// voice adds no empty track. Its id is `next_id` off the trial at that
    /// moment, unchanged by a discarded attempt.
    static func addMicrophones(
        _ voices: [Voice], pictureStarts: [Ticks?]?, scope: UInt32?,
        to trial: inout ReelProject, ops: inout [ReelOp], notes: inout [String]
    ) throws -> (media: [UInt32?], clips: [UInt32?]) {
        precondition(
            pictureStarts.map { $0.count == voices.count } ?? true,
            "one picture start per voice")
        var media: [UInt32?] = []
        for voice in voices {
            if let mic = voice.descriptor {
                media.append(try addMedia(mic, to: &trial, ops: &ops))
            } else {
                media.append(nil)
            }
        }
        let none: [UInt32?] = voices.map { _ in nil }
        guard let starts = pictureStarts else { return (media, none) }
        var track: UInt32?
        var clips: [UInt32?] = []
        var floor: Ticks = 0
        for (k, voice) in voices.enumerated() {
            guard let id = media[k], let start = starts[k] else {
                clips.append(nil)
                continue
            }
            var attempt = trial
            var attemptOps: [ReelOp] = []
            let on: UInt32
            if let added = track {
                on = added
            } else {
                on = attempt.snapshot.nextId
                let addTrack = ReelOp.addTrack(index: 0, name: microphoneTrackName)
                guard let withTrack = try attempt.applying(addTrack.scoped(scope)).project
                else {
                    throw ReelCoreError(message: "A track for the microphone could not be added.")
                }
                attempt = withTrack
                attemptOps.append(addTrack)
            }
            guard
                let placed = try addMicrophoneClip(
                    id, on: on, pictureAt: start, offset: voice.offset, floor: floor,
                    scope: scope, to: &attempt, ops: &attemptOps, notes: &notes)
            else {
                clips.append(nil)
                continue
            }
            trial = attempt
            ops += attemptOps
            track = on
            clips.append(placed.id)
            floor = placed.end
        }
        return (media, clips)
    }

    /// One voice's clip on `track`, at `pictureAt − offset` and never below
    /// `floor` — 0 for the first voice, the previous voice's end after it.
    /// nil, with a sentence in `notes`, for a voice that gets no clip; the
    /// trial and the ops are advanced only for a clip returned.
    ///
    /// **The sign.** `offset` is the screen's did-start minus the
    /// microphone's, in ticks; positive means the picture began AFTER the
    /// microphone, so the microphone's content LEADS and its clip starts
    /// that much earlier than the picture's. R0 measured it centred near
    /// zero with a 35 ms scatter (road map 3, R0 q6b) and a different number
    /// at every resume (q7), and the landing applies each segment's measured
    /// number — never a constant, never the first segment's.
    ///
    /// **When that start is below the floor** — the picture at 0 with the
    /// microphone ahead of it, or a later voice whose picture began less
    /// than its offset after the previous voice ended — the clip cannot
    /// start there: below 0 there is no timeline, below the previous voice's
    /// end there is a clip, and placing it AT the floor would leave the
    /// voice LATE by the difference. So the head is trimmed off instead, and
    /// it stays one grouped edit: `add_clip` at the floor, `trim_start` to
    /// the landed start + head (the core sets the start there and advances
    /// `in` by the same amount — `core/src/edit_clip.rs`), `move_clip` back
    /// by what the trim advanced, read off the trimmed clip (the head, at
    /// an exact rate; at an inexact one the grid point nearest it). A
    /// `slip` would be the one-op spelling and cannot be used: the clip
    /// covers its whole media, so the slip's clamp reduces it to nothing.
    /// The head is the core's own snap of the shortfall
    /// (`ReelTime.snapToFrame`, the rounding every time argument gets), so a
    /// start within half a frame of the floor makes no trim and the two ops
    /// are not sent — the core's snap of that start lands it on the floor —
    /// while a start further below is trimmed rather than left to the snap,
    /// because the core would snap it to the frame BELOW the floor: at 0
    /// clamped up and late by a frame, above 0 a one-frame overlap the rule
    /// accepts as a transition. Limit: the grid is the picture's frame — at
    /// 60 fps 16.7 ms — so the alignment is exact to half a frame and no
    /// finer.
    ///
    /// **Every step is read back, and two things are decided by what comes
    /// back** (the R2 review). `trim_start` clamps its `to` at a frame
    /// before the clip's end, so a voice no longer than its head — an 80 ms
    /// file whose picture began 100 ms after it — used to be trimmed to a
    /// one-frame sliver and then moved back INTO the previous voice, which
    /// `move_clips` refused: `applying(_ ops:)` still answered non-nil (the
    /// add and the trim had changed something), the trial "succeeded", and
    /// the commit ran a refused op inside its undo step with the sliver
    /// sitting late. Now the trimmed clip's start is compared with the
    /// core's own snap of the requested `to`, and a start that is not it is
    /// the clamp: the voice is wholly under its head, mints NO clip, and its
    /// sentence names the file. And the moved clip must land exactly where
    /// the core's snap of the delta says, at or above the floor, or the
    /// throw names the file — a refused op can never ride a committed list.
    /// At an INEXACT rate the move's landing can be a tick under a floor
    /// that is a grid point (the delta and the trim round separately; grid
    /// points are not closed under addition), which the rule would accept
    /// and dress as a transition, so that one case is done once more a
    /// frame up with a frame more head: the content stays aligned to the
    /// tick, the voice starts a sub-frame gap after the previous one, and
    /// its first frame past the head is the price — the documented limit of
    /// such a rate, beside the pictures' own sub-frame gap.
    static func addMicrophoneClip(
        _ media: UInt32, on track: UInt32, pictureAt: Ticks, offset: Ticks, floor: Ticks,
        scope: UInt32?, to trial: inout ReelProject, ops: inout [ReelOp], notes: inout [String]
    ) throws -> ClipSnapshot? {
        let file = try mediaEntry(media, in: trial, scope: scope)
        let fps = try view(of: trial, scope: scope).snapshot.canvas.fps
        if let note = tooShortNote(file, at: fps) {
            notes.append(note)
            return nil
        }
        let start = pictureAt - offset
        let head = start < floor ? ReelTime.snapToFrame(floor - start, fps: fps) : 0
        guard head > 0 else {
            guard
                let placed = try placeClip(
                    media, on: track, at: max(start, floor), notBelow: floor, scope: scope,
                    to: &trial, ops: &ops)
            else {
                throw ReelCoreError(message: "\(file.path) could not be placed on its track.")
            }
            return placed
        }
        let frame = fps.frameDuration
        for (at, head) in [(floor, head), (floor + frame, head + frame)] {
            var attempt = trial
            var attemptOps: [ReelOp] = []
            guard
                let placed = try headTrimmed(
                    media, file: file, on: track, at: at, head: head, floor: floor, fps: fps,
                    scope: scope, to: &attempt, ops: &attemptOps)
            else {
                notes.append(underNote(file, head: head, floor: floor))
                return nil
            }
            if placed.start >= floor {
                trial = attempt
                ops += attemptOps
                return placed
            }
        }
        throw ReelCoreError(
            message: "\(file.path) could not be placed clear of the previous microphone clip.")
    }

    /// The dance once, on `trial`: the add at `at` (never under `floor`),
    /// the trim to the landed start + `head`, the move back by what the trim
    /// advanced. nil when the trim clamped — the voice is wholly under its
    /// head — with the trial left as it was; every other surprise is a
    /// throw naming the file. The clip returned may still sit a tick under
    /// the floor at an inexact rate, which the caller reads.
    static func headTrimmed(
        _ media: UInt32, file: MediaSnapshot, on track: UInt32, at: Ticks, head: Ticks,
        floor: Ticks, fps: Fps, scope: UInt32?, to trial: inout ReelProject, ops: inout [ReelOp]
    ) throws -> ClipSnapshot? {
        guard
            let added = try placeClip(
                media, on: track, at: at, notBelow: floor, scope: scope, to: &trial, ops: &ops)
        else {
            throw ReelCoreError(message: "\(file.path) could not be placed on its track.")
        }
        let trim = ReelOp.trimStart(clip: added.id, to: added.start + head)
        let promisedTrim = ReelTime.snapToFrame(added.start + head, fps: fps)
        guard let trimmed = try trial.applying(trim.scoped(scope)).project,
            try clip(added.id, in: trimmed, scope: scope).start == promisedTrim
        else { return nil }
        let advanced = promisedTrim - added.start
        let move = ReelOp.moveClip(clips: [added.id], delta: -advanced)
        let promisedStart = promisedTrim + ReelTime.snapToFrame(-advanced, fps: fps)
        guard let moved = try trimmed.applying(move.scoped(scope)).project else {
            throw ReelCoreError(
                message: "\(file.path) could not be moved back by its \(milliseconds(advanced)) ms head.")
        }
        let landed = try clip(added.id, in: moved, scope: scope)
        guard landed.start == promisedStart, landed.source.sourceIn == advanced else {
            throw ReelCoreError(
                message: "\(file.path) landed at \(landed.start) with \(landed.source.sourceIn) "
                    + "trimmed, not at \(promisedStart) with \(advanced).")
        }
        trial = moved
        ops += [trim, move]
        return landed
    }

    /// The sentence for a voice wholly under its head.
    private static func underNote(_ file: MediaSnapshot, head: Ticks, floor: Ticks) -> String {
        let clear = floor == 0 ? "the start of the timeline" : "the previous microphone clip"
        return "\(file.path) was added to the media list without a clip: less than a frame of "
            + "it would remain after the \(milliseconds(head)) ms head that keeps it clear of "
            + "\(clear)."
    }
}
