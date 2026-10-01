// app/Sources/RecordingLanding+Placing.swift — one clip on the grid, asked
// of the core (road map 3, R2's toll): a PURE MOVE out of
// `RecordingLanding.swift` at the 400-line cap, holding `placeBackToBack`
// (a sequence of clips, each at the previous END as read back), `placeClip`
// (one `add_clip`, read back and stepped a frame up when the core snapped
// it under its floor — the inexact-rate rule the base file's header
// argues), `tooShortNote` (a file with no WHOLE frame inside it),
// `mediaEntry` and `milliseconds`. Every "what will the core snap this to"
// here is put to the core over the FFI — `ReelTime.snapToFrame` is
// `rc_time_snap_to_frame` — or read off a purely-applied result; nothing
// re-derives a frame in Swift, which is what makes the answers exact at
// 24981/1000 as at 30. Internal, not private, because the microphone file
// calls all of them and `private` does not cross a file.

import AppKit

extension RecordingLanding {
    /// `media` as touching clips on `track`: the first at `at`, each later
    /// one at the previous clip's END as read off the trial after its
    /// `add_clip` — never computed here, because a sum over descriptor
    /// durations would be off-grid. Each is placed by `placeClip`, which
    /// reads the landed clip back and steps a frame up when the core snapped
    /// it under the previous end (an inexact rate; the header says why), so
    /// two clips meet at one tick or leave a sub-frame gap and never overlap
    /// (`core/src/transition.rs`: `overlap_of` answers none at zero length).
    /// A picture too short for a frame — the core's `whole_media_length`
    /// answers an `Err` for it, and that `Err` used to take the whole list
    /// down — lands as media alone, with its sentence in `notes`, and
    /// the sequence carries on from the same point. nil when any `add_clip`
    /// refuses — the caller decides what a refusal means — and a throw is
    /// the core's own sentence. A `.gap` (a left-out segment's voice, #181
    /// item 2) places nothing: its `Landed` has no clip and starts where the
    /// sequence had reached, and the next picture starts the gap's length
    /// later. Answers one `Landed` per stretch, in order.
    static func placeBackToBack(
        _ stretches: [PictureStretch], on track: UInt32, from at: Ticks, scope: UInt32?,
        to trial: inout ReelProject, ops: inout [ReelOp], notes: inout [String]
    ) throws -> [Landed]? {
        var placed: [Landed] = []
        var at = at
        for stretch in stretches {
            let id: UInt32
            switch stretch {
            case .gap(let length):
                placed.append(Landed(clip: nil, at: at))
                at += length
                continue
            case .picture(let media):
                id = media
            }
            let file = try mediaEntry(id, in: trial, scope: scope)
            let fps = try view(of: trial, scope: scope).snapshot.canvas.fps
            if let note = tooShortNote(file, at: fps) {
                notes.append(note)
                placed.append(Landed(clip: nil, at: at))
                continue
            }
            guard
                let landed = try placeClip(
                    id, on: track, at: at, notBelow: at, scope: scope, to: &trial, ops: &ops)
            else { return nil }
            placed.append(Landed(clip: landed, at: landed.start))
            at = landed.end
        }
        return placed
    }

    /// `add_clip` of `media` on `track` at `at`, applied purely and READ
    /// BACK, and never landed below `floor` (≤ `at`): the core snaps the
    /// start to the nearest frame, and at an inexact canvas rate the
    /// nearest frame to a clip's end can be UNDER it — the end is a sum of
    /// two grid points, which is not one — so a landing under the floor is
    /// discarded whole and the add is made again at `floor` plus a frame,
    /// whose nearest frame is at or above the floor and within a frame of
    /// it. What comes back therefore satisfies `floor ≤ start ≤ at + frame`:
    /// touching, or a sub-frame gap at an inexact rate, never an overlap
    /// (which the rule would accept and dress as a transition). A landing
    /// outside that band after the second try is a throw, not a guess. nil
    /// is the core's refusal — an overlap the rule will not accept — and
    /// the op is appended and the trial advanced only for the clip returned.
    static func placeClip(
        _ media: UInt32, on track: UInt32, at: Ticks, notBelow floor: Ticks, scope: UInt32?,
        to trial: inout ReelProject, ops: inout [ReelOp]
    ) throws -> ClipSnapshot? {
        precondition(at >= floor, "a clip is asked for at or above its floor")
        let frame = try view(of: trial, scope: scope).snapshot.canvas.fps.frameDuration
        for requested in [at, floor + frame] {
            let op = ReelOp.addClip(track: track, media: media, at: requested)
            let id = trial.snapshot.nextId
            guard let next = try trial.applying(op.scoped(scope)).project else { return nil }
            let landed = try clip(id, in: next, scope: scope)
            if landed.start < floor { continue }
            guard landed.start <= at + frame else {
                throw ReelCoreError(
                    message: "Clip \(id) landed at \(landed.start), more than a frame past \(at).")
            }
            trial = next
            ops.append(op)
            return landed
        }
        throw ReelCoreError(
            message: "Clip \(trial.snapshot.nextId) could not be placed at or after \(floor).")
    }

    /// The sentence for a media the core cannot make a clip of, or nil: a
    /// timed media with no WHOLE frame inside it is an `Err` to
    /// `whole_media_length` (`core/src/edit_clip.rs`) — "no duration" at
    /// zero, "shorter than a frame" above it — and not a refusal, and R0 q7
    /// measured a real 2 ms microphone file. The test IS the core's: a clip
    /// takes the media's length snapped DOWN (spec §11), so the threshold
    /// here is `SilenceDetector.snapDownToFrame`, the one Swift spelling of
    /// that snap and itself `rc_time_snap_to_frame` over the FFI — exact at
    /// every rate, and nothing here re-derives a frame. An image has no such
    /// bound and gets the default length instead, which is why it is exempt.
    static func tooShortNote(_ file: MediaSnapshot, at fps: Fps) -> String? {
        guard file.kind != .image,
            SilenceDetector.snapDownToFrame(file.duration, fps: fps) <= 0
        else {
            return nil
        }
        return "\(file.path) is too short for a frame (\(milliseconds(file.duration)) ms) "
            + "and was added to the media list without a clip."
    }

    /// The media entry `id` names in `trial` — the document's one list, which
    /// a nest's view shares (`core/src/scope.rs`). An id the trial's own
    /// `add_media` answered and does not list is a throw.
    static func mediaEntry(_ id: UInt32, in trial: ReelProject, scope: UInt32?) throws
        -> MediaSnapshot
    {
        let container = try view(of: trial, scope: scope).snapshot
        guard let media = container.media.first(where: { $0.id == id }) else {
            throw ReelCoreError(message: "Media \(id) was added and is not listed.")
        }
        return media
    }

    /// A tick count as milliseconds to a tenth, for a note about a length
    /// under a frame — where `ReelTime.format`'s timecode would read
    /// `00:00:00:00` and say nothing.
    static func milliseconds(_ ticks: Ticks) -> String {
        String(format: "%.1f", Double(ticks) / (Double(ReelTime.perSecond) / 1000))
    }
}
