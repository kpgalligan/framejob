// app/Sources/RecordingLanding+Camera.swift — the camera half of the landing
// (camera-recording CR3b, spec §11 CAM-10): a screen recording's
// `(Camera).mov` files, one per segment (CAM-9), on ONE new FRONT track
// named "Camera", each clip lined up with its screen segment by the
// segment's measured `cameraOffset` and placed in the bottom-right corner.
//
// `addCameras` is `addMicrophones`' shape, attempt for attempt: every file's
// `add_media` in segment order, then — with the screen's starts — the track
// added on the attempt of the first camera clip that takes a frame and kept
// only when that clip lands, and each clip by the floor rule. The floor is
// `max(screenStart_k, previous camera clip's end)`, so a camera never starts
// before its own screen clip and never overlaps the camera before it, and a
// start below the floor is head-trimmed by the microphone's own dance
// (`headTrimmed`, `+Microphone`, internal for this file). CR3a measured
// every offset NEGATIVE — the camera begins 32–146 ms before the screen — so
// the trim is the ordinary path here, not the exception it is for a voice.
//
// The corner is `cornerPatch`, arithmetic over the container's canvas and
// the file's size, the precedent `CaptionStyle.size(for:)` set for a
// Swift-side placement: a quarter of the canvas wide, a third of it tall,
// inside the 90 % ring of View ▸ Safe Areas (`SafeGuidesView`), as
// one `set_video {x, y, scale}` right after the clip's placement and read
// back. Nothing else is set: the clip stays an ordinary clip a person moves.
//
// The ops come back UNSCOPED, as every landing op does; the trial applies
// them scoped exactly as the commit will (the base file's header).

import AppKit

extension RecordingLanding {
    /// The new front track every camera clip lands on — ONE for the whole
    /// recording, added with the first camera clip that takes a frame, so a
    /// recording none of whose camera files can be placed adds no track.
    static let cameraTrackName = "Camera"
    /// The corner box is a quarter of the canvas wide…
    static let cornerWidthFraction: Double = 0.25
    /// …and a third of it tall; the picture is scaled to fit inside both.
    static let cornerHeightFraction: Double = 1.0 / 3.0
    /// The inset from the canvas's right and bottom edges, as a fraction of
    /// each: the 90 % ring of View ▸ Safe Areas (`SafeGuidesView`, spec §4.1's
    /// title-safe guide; the industry calls 90 % action-safe).
    static let cornerInsetFraction: Double = 0.05

    /// The bottom-right corner patch for a `sourceWidth × sourceHeight`
    /// camera picture on a `canvasWidth × canvasHeight` canvas (CAM-10 (3)):
    /// the scale that fits the picture inside the corner box, clamped to the
    /// core's scale range (`props_check.rs`' `SCALE_MIN`, `SCALE_MAX`), and
    /// the `x`, `y` that put its bottom-right corner on the 90 % safe-area
    /// ring — an offset of the layer's centre from the canvas centre, y
    /// down (`core/src/edit_zoom.rs`'s C frame), rounded to whole pixels.
    /// nil when any dimension is not positive.
    static func cornerPatch(
        canvasWidth: Int, canvasHeight: Int, sourceWidth: Int, sourceHeight: Int
    ) -> VideoPatch? {
        guard canvasWidth > 0, canvasHeight > 0, sourceWidth > 0, sourceHeight > 0 else {
            return nil
        }
        let cw = Double(canvasWidth)
        let ch = Double(canvasHeight)
        let sw = Double(sourceWidth)
        let sh = Double(sourceHeight)
        let fit = min(cornerWidthFraction * cw / sw, cornerHeightFraction * ch / sh)
        let scale = min(max(fit, 0.01), 10)
        let x = (cw / 2 - cornerInsetFraction * cw - sw * scale / 2).rounded()
        let y = (ch / 2 - cornerInsetFraction * ch - sh * scale / 2).rounded()
        return VideoPatch(x: x, y: y, scale: scale)
    }

    /// One entry per SEGMENT from a per-stretch list (`result.stretches`'
    /// order): the `.segment(k)` positions only. A left-out segment's voice
    /// is a stretch of its own and has no camera to place (CAM-10 (2)).
    static func segmentStarts(_ perStretch: [Ticks?], of result: RecordingResult) -> [Ticks?] {
        var starts: [Ticks?] = result.segments.map { _ in nil }
        for (stretch, at) in zip(result.stretches, perStretch) {
            if case .segment(let k) = stretch { starts[k] = at }
        }
        return starts
    }

    /// Every segment's camera file: its `add_media` in segment order, then —
    /// when `screenStarts` is given, one per segment — ONE new FRONT track
    /// named "Camera" and each camera clip by the floor rule, cornered. A nil
    /// `screenStarts` is `place: false`: the media land and no clip or track
    /// does; a nil ENTRY lands that camera as media only. Answers one media
    /// id and one clip id PER SEGMENT, nil where the segment has no camera
    /// file or its camera minted no clip — too short for a frame, or wholly
    /// under its head, each with its sentence in `notes`.
    ///
    /// The track's index is the container's track count when it is added,
    /// which — the pictures having landed first — puts it in front of every
    /// track, the pictures' included. Its id is `next_id` off the trial at
    /// that moment, unchanged by a discarded attempt.
    static func addCameras(
        _ result: RecordingResult, screenStarts: [Ticks?]?, scope: UInt32?,
        to trial: inout ReelProject, ops: inout [ReelOp], notes: inout [String]
    ) throws -> (media: [UInt32?], clips: [UInt32?]) {
        precondition(
            screenStarts.map { $0.count == result.segments.count } ?? true,
            "one screen start per segment")
        var media: [UInt32?] = []
        for segment in result.segments {
            if let camera = segment.cameraDescriptor {
                media.append(try addMedia(camera, to: &trial, ops: &ops))
            } else {
                media.append(nil)
            }
        }
        let none: [UInt32?] = result.segments.map { _ in nil }
        guard let starts = screenStarts else { return (media, none) }
        var track: UInt32?
        var clips: [UInt32?] = []
        var previousEnd: Ticks?
        for (k, segment) in result.segments.enumerated() {
            guard let id = media[k], let screenAt = starts[k] else {
                clips.append(nil)
                continue
            }
            var attempt = trial
            var attemptOps: [ReelOp] = []
            let on: UInt32
            if let added = track {
                on = added
            } else {
                let front = try view(of: attempt, scope: scope).snapshot.tracks.count
                on = attempt.snapshot.nextId
                let addTrack = ReelOp.addTrack(index: front, name: cameraTrackName)
                guard let withTrack = try attempt.applying(addTrack.scoped(scope)).project
                else {
                    throw ReelCoreError(message: "A track for the camera could not be added.")
                }
                attempt = withTrack
                attemptOps.append(addTrack)
            }
            let behindCamera = previousEnd.map { $0 > screenAt } ?? false
            let floor = max(screenAt, previousEnd ?? screenAt)
            guard
                let placed = try addCameraClip(
                    id, on: on, screenAt: screenAt, offset: segment.cameraOffset, floor: floor,
                    behindCamera: behindCamera, scope: scope, to: &attempt, ops: &attemptOps,
                    notes: &notes)
            else {
                clips.append(nil)
                continue
            }
            try corner(placed, scope: scope, to: &attempt, ops: &attemptOps)
            trial = attempt
            ops += attemptOps
            track = on
            clips.append(placed.id)
            previousEnd = placed.end
        }
        return (media, clips)
    }

    /// One camera clip on `track`, at `screenAt + offset` and never below
    /// `floor` — its screen clip's start, or the previous camera clip's end
    /// when that is later (`behindCamera`, which the note names). nil, with a
    /// sentence in `notes`, for a camera that gets no clip; the trial and the
    /// ops are advanced only for a clip returned.
    ///
    /// **The sign.** `offset` is the camera's first buffer minus the screen's
    /// start (CAM-9 (4)); positive means the camera began AFTER the screen,
    /// so its clip starts that much later — the opposite of the
    /// microphone's `micOffset`, which is measured the other way round.
    ///
    /// The rest is `addMicrophoneClip`'s, step for step: a start within half
    /// a frame of the floor makes no trim (the core's snap lands it there);
    /// further below, the head is the core's snap of the shortfall and
    /// `headTrimmed` adds at the floor, trims, moves back and reads every
    /// step back, a second try a frame up when an inexact rate lands the
    /// move a tick under the floor; a trim that clamps is a camera wholly
    /// under its head, media only with `cameraUnderNote`.
    static func addCameraClip(
        _ media: UInt32, on track: UInt32, screenAt: Ticks, offset: Ticks, floor: Ticks,
        behindCamera: Bool, scope: UInt32?, to trial: inout ReelProject, ops: inout [ReelOp],
        notes: inout [String]
    ) throws -> ClipSnapshot? {
        let file = try mediaEntry(media, in: trial, scope: scope)
        let fps = try view(of: trial, scope: scope).snapshot.canvas.fps
        if let note = tooShortNote(file, at: fps) {
            notes.append(note)
            return nil
        }
        let start = screenAt + offset
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
                notes.append(cameraUnderNote(file, head: head, behindCamera: behindCamera))
                return nil
            }
            if placed.start >= floor {
                trial = attempt
                ops += attemptOps
                return placed
            }
        }
        throw ReelCoreError(
            message: "\(file.path) could not be placed clear of the previous camera clip.")
    }

    /// The corner (`cornerPatch` over the CONTAINER's canvas — the nest's
    /// inside one — and the camera file's size) as one `set_video` on
    /// `clip`, applied and read back: the clip must report exactly the `x`,
    /// `y` and `scale` asked, or the throw names the clip. A size the patch
    /// cannot be made for (a dimension of 0) sets nothing.
    private static func corner(
        _ clip: ClipSnapshot, scope: UInt32?, to trial: inout ReelProject, ops: inout [ReelOp]
    ) throws {
        guard case .media(let media, _, _) = clip.source else { return }
        let file = try mediaEntry(media, in: trial, scope: scope)
        let canvas = try view(of: trial, scope: scope).snapshot.canvas
        guard
            let patch = cornerPatch(
                canvasWidth: canvas.width, canvasHeight: canvas.height,
                sourceWidth: file.width, sourceHeight: file.height)
        else { return }
        let op = ReelOp.setVideo(clips: [clip.id], patch: patch)
        guard let next = try trial.applying(op.scoped(scope)).project,
            let video = try self.clip(clip.id, in: next, scope: scope).video,
            video.x == patch.x, video.y == patch.y, video.scale == patch.scale
        else {
            throw ReelCoreError(
                message: "Clip \(clip.id) could not be placed in the corner of the canvas.")
        }
        trial = next
        ops.append(op)
    }

    /// The sentence for a camera wholly under its head.
    private static func cameraUnderNote(_ file: MediaSnapshot, head: Ticks, behindCamera: Bool)
        -> String
    {
        let clear = behindCamera ? "the previous camera clip" : "the start of its screen clip"
        return "\(file.path) was added to the media list without a clip: less than a frame of "
            + "it would remain after the \(milliseconds(head)) ms head that keeps it clear of "
            + "\(clear)."
    }
}
