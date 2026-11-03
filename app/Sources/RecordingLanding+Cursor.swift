// app/Sources/RecordingLanding+Cursor.swift — the ripples a Separate
// recording with Show Clicks lands with (road map creator-jobs CU3c, spec §11
// CU-31 (c), CU-42).
//
// With Cursor Separate the stream draws no click ring, so Show Clicks means
// "land the screen clips with ripples on": ONE `set_video {cursor: {clicks:
// "ripple"}}` over the placed screen clips whose media's cursor file is not in
// the picture, inside the landing's one step. `placement` calls it right after
// `addSequence`, and `remainderPlacement` after the later pictures, with clip
// 1 among the clips. Like every step here the op is applied to the trial
// scoped, as the commit will, and comes back unscoped for the door to stamp.

import AppKit

extension RecordingLanding {
    /// The undo step's name for `untitled(around:)`'s remainder when the
    /// ripples are all it holds — the Cursor section's Clicks row's name.
    static let ripplesActionName = "Cursor Clicks"

    /// Whether the landing writes ripples: Show Clicks was on, the cursor was
    /// recorded Separate, and the recording has a picture.
    static func wantsRipples(_ result: RecordingResult) -> Bool {
        result.choice.showClicks && result.choice.effectiveCursor == .separate
            && !result.isVoiceOver
    }

    /// When `wantsRipples`, one `set_video` over those of `clips` whose media
    /// in `trial` has a cursor file not in the picture, applied to `trial` and
    /// appended to `ops`; nothing when none qualifies (a segment whose cursor
    /// file was not written has no cursor to ripple). A refusal adds nothing:
    /// the ripples never take the recording down with them.
    static func addRipples(
        _ clips: [UInt32], of result: RecordingResult, scope: UInt32?,
        to trial: inout ReelProject, ops: inout [ReelOp]
    ) throws {
        guard wantsRipples(result), !clips.isEmpty else { return }
        let media = trial.snapshot.media
        var rippled: [UInt32] = []
        for id in clips {
            let placed = try clip(id, in: trial, scope: scope)
            guard case .media(let source, _, _) = placed.source,
                let cursor = media.first(where: { $0.id == source })?.cursor,
                !cursor.inPicture
            else { continue }
            rippled.append(id)
        }
        guard !rippled.isEmpty else { return }
        let op = ReelOp.setVideo(
            clips: rippled, patch: VideoPatch(cursorPart: CursorPatch(clicks: .ripple)))
        guard let next = try trial.applying(op.scoped(scope)).project else { return }
        trial = next
        ops.append(op)
    }
}
