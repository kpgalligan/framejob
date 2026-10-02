// app/Sources/RecordingLanding+VoiceOver.swift — where a finished VOICE-OVER
// goes (spec §11 recording, "A voice-over is a recording with no picture",
// #99).
//
// A voice-over is an ordinary `RecordingResult` whose every segment's
// `descriptor` is an `.m4a` (`isVoiceOver`). `placement(_:in:place:)` forwards
// it here after its live-edit guard, and the rule is not the picture rule:
// every file lands on ONE new BACK track named "Microphone" — where a screen
// recording's microphone lands — touching, from the playhead, in the one
// grouped edit both doors commit as "Add Recording". Never the front track,
// and never an existing Microphone track: no rule says which track is "the"
// voice track. The placing is `placeBackToBack`'s (`+Placing`), so every clip
// is read back and a file under a frame lands as media with its
// `tooShortNote`; the track is kept only when at least one clip landed on it.
//
// A NEW project needs nothing here: `ProjectDocument.untitled(around:)` makes
// the first file the document (audio-only, 1920×1080 at the chosen rate) and
// `remainderPlacement` puts the later files touching it on its one track.

import AppKit

extension RecordingLanding {
    /// PURE, main thread: the voice-over's ops and predicted ids. Every
    /// file's `add_media` in order (document-level, unscoped); then, with
    /// `place`, on a trial copy, `add_track` at index 0 named
    /// `microphoneTrackName` and every file back to back from the playhead
    /// on it. A refusal on that new, empty track is thrown by name. The
    /// track and its clips are kept only when at least one clip landed —
    /// every file under a frame adds media and notes alone. `clipIds` has
    /// one entry per segment; the two `mic…` lists are all nil (a
    /// voice-over's voice IS its descriptor); the two left-out lists have
    /// one nil per `unreadable` entry. The ops come back unscoped, the
    /// container ops stamped by the caller's door as for any landing.
    static func voiceOverPlacement(
        _ result: RecordingResult, in document: ProjectDocument, place: Bool
    ) throws -> Placement {
        assert(Thread.isMainThread)
        let scope = document.scope
        var trial = document.project
        var ops: [ReelOp] = []
        var notes: [String] = []
        var mediaIds: [UInt32] = []
        for segment in result.segments {
            mediaIds.append(try addMedia(segment.descriptor, to: &trial, ops: &ops))
        }
        var clipIds: [UInt32?] = mediaIds.map { _ in nil }
        if place {
            var attempt = trial
            let track = attempt.snapshot.nextId
            let addTrack = ReelOp.addTrack(index: 0, name: microphoneTrackName)
            guard let withTrack = try attempt.applying(addTrack.scoped(scope)).project else {
                throw ReelCoreError(message: "A track for the voice-over could not be added.")
            }
            attempt = withTrack
            var attemptOps: [ReelOp] = [addTrack]
            guard
                let placed = try placeBackToBack(
                    mediaIds.map { PictureStretch.picture($0) }, on: track,
                    from: document.playhead, scope: scope, to: &attempt, ops: &attemptOps,
                    notes: &notes)
            else {
                throw ReelCoreError(
                    message: "The voice-over could not be placed on its new Microphone track.")
            }
            if placed.contains(where: { $0.clip != nil }) {
                trial = attempt
                ops += attemptOps
                clipIds = placed.map { $0.clip?.id }
            }
        }
        let none: [UInt32?] = mediaIds.map { _ in nil }
        let leftOut: [UInt32?] = result.unreadable.map { _ in nil }
        return Placement(
            ops: ops, mediaIds: mediaIds, clipIds: clipIds, micMediaIds: none, micClipIds: none,
            notes: notes, leftOutMicMediaIds: leftOut, leftOutMicClipIds: leftOut)
    }
}
