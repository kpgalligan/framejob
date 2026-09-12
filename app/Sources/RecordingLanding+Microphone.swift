// app/Sources/RecordingLanding+Microphone.swift — the microphone half of
// the landing (road map 3, R1b), a PURE MOVE out of `RecordingLanding.swift`
// landed alone at the 400-line cap (R2's toll): the names the microphone's
// track and undo step carry, `microphonePlacement` (the microphone ALONE,
// for a document that already holds the picture) and `addMicrophoneClip`
// with the `snapped` helper only it calls. Every body is byte for byte what
// it was; `addMicrophoneClip` is internal now because `placement` in the
// base file calls it, and `addMedia`, `view` and `trimmed` were widened
// there for the same reason.

import AppKit

extension RecordingLanding {
    /// The undo step's name for `ProjectDocument.untitled(around:)`'s
    /// microphone edit ALONE. There the picture is the document — undoing
    /// the step removes the voice and keeps the picture — so a step called
    /// "Add Recording" would promise to take back what it cannot, and the
    /// Edit menu would read "Undo Add Recording" over a project the undo
    /// leaves with the recording in it. The `.document` landing keeps
    /// `actionName`: its one step really does add and remove both.
    static let microphoneActionName = "Add Microphone"

    /// The new back track a microphone clip lands on.
    static let microphoneTrackName = "Microphone"

    /// The microphone half ALONE, for a document that already holds the
    /// picture: `ProjectDocument.untitled(around:)`, whose `makeProject`
    /// placed the picture at 0 on track 1 before anything else could run.
    /// `placement(_:in:place:)` cannot serve it — the picture's `add_media`
    /// would be the documented identity and its `add_clip` at 0 would meet
    /// its own clip on the front track, refuse, and put a SECOND copy on a
    /// new track. nil when the result carries no microphone. `mediaId` and
    /// `clipId` name the picture the document holds, so the answer reads as
    /// a whole landing.
    ///
    /// `clipId` is the FIRST clip whose source is the picture's media, and
    /// `pictureAt` is that clip's start. That is exact for the one caller:
    /// `makeProject` places exactly one clip, at 0. A document holding the
    /// same media in several clips has no single answer here, and this
    /// method does not pretend to one — it is `untitled(around:)`'s, not a
    /// general "add a microphone to a document" op.
    static func microphonePlacement(
        _ result: RecordingResult, in document: ProjectDocument
    ) throws -> Placement? {
        assert(Thread.isMainThread)
        guard let mic = result.micDescriptor else { return nil }
        let path = trimmed(result.descriptor.path)
        let snapshot = document.editedProject.snapshot
        guard let mediaId = snapshot.media.first(where: { $0.path == path })?.id else {
            throw ReelCoreError(message: "\(path) is not in the document's media list.")
        }
        let clipId = snapshot.clips.first { clip in
            if case .media(let id, _, _) = clip.source { return id == mediaId }
            return false
        }?.id
        var trial = document.project
        var ops: [ReelOp] = []
        let micMediaId = try addMedia(mic, to: &trial, ops: &ops)
        let micClipId = try addMicrophoneClip(
            micMediaId, pictureAt: clipId.flatMap { id in snapshot.clips.first { $0.id == id } }?
                .start ?? 0,
            offset: result.micOffset, scope: document.scope, to: &trial, ops: &ops)
        return Placement(
            ops: ops, mediaId: mediaId, clipId: clipId, micMediaId: micMediaId,
            micClipId: micClipId)
    }

    /// The microphone's clip: a new BACK track (index 0, named
    /// "Microphone"), so the voice sits under the picture as a detached
    /// audio twin does, and the clip at `pictureAt − offset`.
    ///
    /// **The sign.** `offset` is the screen's did-start minus the
    /// microphone's, in ticks; positive means the picture began AFTER the
    /// microphone, so the microphone's content LEADS and its clip starts
    /// that much earlier than the picture's. R0 measured it centred near
    /// zero with a 35 ms scatter (road map 3, R0 q6b), and the landing
    /// applies the measured number per recording, never a constant.
    ///
    /// **When that start is negative** — the picture at 0, the microphone
    /// ahead of it — the clip cannot start before the timeline, and placing
    /// it at 0 would leave the voice LATE by the offset. So the head is
    /// trimmed off instead, and it stays one grouped edit: `add_clip` at 0,
    /// `trim_start` to the head (start and `in` both advance), `move_clip`
    /// back by the same amount (start returns to 0, `in` keeps the trim). A
    /// `slip` would be the one-op spelling and cannot be used: the clip
    /// covers its whole media, so the slip's clamp reduces it to nothing.
    /// The head is snapped to the canvas frame grid HERE, the same rounding
    /// the core applies to every time argument, so a sub-frame offset makes
    /// no trim and the two ops are not sent; a head the core still snaps to
    /// zero would be an identity the list carries on past, not a failure.
    /// Limit: the grid is the picture's frame — at 60 fps 16.7 ms — so the
    /// alignment is exact to half a frame and no finer.
    static func addMicrophoneClip(
        _ media: UInt32, pictureAt: Ticks, offset: Ticks, scope: UInt32?,
        to trial: inout ReelProject, ops: inout [ReelOp]
    ) throws -> UInt32 {
        let addTrack = ReelOp.addTrack(index: 0, name: microphoneTrackName)
        let track = trial.snapshot.nextId
        guard let withTrack = try trial.applying(addTrack.scoped(scope)) else {
            throw ReelCoreError(message: "A track for the microphone could not be added.")
        }
        let clip = withTrack.snapshot.nextId
        let start = pictureAt - offset
        var clipOps: [ReelOp]
        if start >= 0 {
            clipOps = [.addClip(track: track, media: media, at: start)]
        } else {
            let head = snapped(-start, to: trial.snapshot.canvas.fps.frameDuration)
            clipOps = [.addClip(track: track, media: media, at: 0)]
            if head > 0 {
                clipOps += [
                    .trimStart(clip: clip, to: head), .moveClip(clips: [clip], delta: -head),
                ]
            }
        }
        guard let placed = try withTrack.applying(clipOps.map { $0.scoped(scope) }) else {
            throw ReelCoreError(message: "The microphone could not be placed on its track.")
        }
        trial = placed
        ops += [addTrack] + clipOps
        return clip
    }

    /// A non-negative length rounded to the nearest frame — the core's own
    /// snap for a time argument, applied before the ops are built so a
    /// sub-frame head sends no trim at all. A degenerate frame (0) snaps
    /// nothing.
    private static func snapped(_ length: Ticks, to frame: Ticks) -> Ticks {
        guard frame > 0 else { return length }
        return (length + frame / 2) / frame * frame
    }
}
