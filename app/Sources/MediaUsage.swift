import Foundation

/// "Is this media used, and by what?" — the ONE spelling of a question the
/// app asks in three places and used to answer differently in each.
///
/// The core is the authority and the answer is not the obvious one:
/// `remove_media` refuses while `self.every_clip().any(uses_media)`
/// (`core/src/edit_track.rs`), and `every_clip()` is the timeline's clips
/// CHAINED with every nest's (`core/src/nest.rs`) — not a walk from the
/// timeline down. A nest nothing points at is still in the file and its clips
/// still reference media ids, because there is one id space (spec §5.2), so a
/// media used only inside an orphaned nest is used.
///
/// Swift had written the test twice and got it wrong both times: the Media
/// tab's Remove and `AgentServer.removeMedia` each filtered
/// `snapshot.clips` — the TOP LEVEL alone. The live consequence was that
/// removing media used only inside a nest showed no "and its clips" alert at
/// all: the pane saw no users, sent a plain `remove_media`, and the core
/// refused it with `Ok(None)`, which reaches the user as a bare beep. Phase
/// 8c's "unused only" filter would have been a THIRD copy of the same
/// mistake, which is what made it worth one file.
///
/// `ClipSource.mediaID` is the exact mirror of the core's `uses_media`: media,
/// still and image clips carry an id and text, shape and nest clips do not.
extension ProjectSnapshot {
    /// Every clip that SHOWS this media — the timeline's and every nest's, in
    /// that order. What Remove counts and what the "and its clips" alert
    /// promises to delete, since `remove_media { with_clips: true }` retains
    /// against exactly this set at both levels.
    func clipsUsing(_ media: UInt32) -> [ClipSnapshot] {
        var used = clips.filter { $0.source.mediaID == media }
        for nest in nests {
            used.append(contentsOf: nest.clips.filter { $0.source.mediaID == media })
        }
        return used
    }

    /// Whether anything shows it. The question `remove_media` asks before it
    /// refuses, and the one the Media tab's "unused only" filter asks per row.
    func usesMedia(_ media: UInt32) -> Bool {
        clips.contains { $0.source.mediaID == media }
            || nests.contains { nest in nest.clips.contains { $0.source.mediaID == media } }
    }

    /// The users a SELECTION can hold: the timeline's clips only.
    ///
    /// Not a narrower version of the same question — a different question,
    /// and the reason the two are separate methods rather than one with a
    /// flag. `ProjectDocument.clampViewState` intersects the selection with
    /// top-level clip ids, and every op resolves its `clip` argument through
    /// `Project::clip`, which searches `self.clips` alone (spec §4.4), so a
    /// nested clip has no id a selection may carry. Reveal in Timeline
    /// validates FALSE rather than selecting nothing when this is empty and
    /// `clipsUsing` is not.
    func timelineClipsUsing(_ media: UInt32) -> [ClipSnapshot] {
        clips.filter { $0.source.mediaID == media }
    }
}
