import AppKit

/// The cutting moves — slip, roll, lift, close gap, insert and overwrite, and
/// the frame nudge (spec §6, §9).
///
/// What they have in common is that none of them is a *placement* in the sense
/// the timeline already knew about. A drag moves a clip and everything else
/// stays; these six all keep something fixed on purpose — the clip's position
/// (slip), the pair's outer edges (roll), the timing of everything after the
/// cut (lift), the timing of everything before it (close gap), or the whole of
/// every other track (overwrite). Each is one core op, so each is one undo
/// step, and the refusals are all the core's: this file computes what to ask
/// for and never decides whether it is allowed.
///
/// The two drags are begun here rather than in `TimelineView.swift`, which is
/// frozen at wiring — the same split `TimelineClipDrawing.swift` and
/// `MediaPane.swift`'s drop targets already use — so the view keeps one stored
/// property per session and one line per dispatcher.
extension TimelineView {

    /// ⌥⇧ on a clip body: slip. Locked tracks are not draggable at all, so
    /// this refuses there exactly as `beginClipDrag` does.
    ///
    /// Deliberately does NOT touch the selection. ⌥⇧ arrives at `selectClip`
    /// as "toggle membership", and a slip is a gesture on the clip under the
    /// pointer whatever else is selected — so `beginGesture` routes here
    /// before the selection is consulted.
    func beginSlip(_ id: UInt32, at point: CGPoint, flags: NSEvent.ModifierFlags) {
        guard let clip = snapshot.clip(id),
              let index = snapshot.trackIndex(of: clip.track),
              !snapshot.tracks[index].locked
        else { return }
        slip = SlipSession(clip: id, grabTime: layout.time(atX: point.x))
        onLiveBegin?()
    }

    /// ⌥⇧ on a clip edge: roll the cut that edge sits on.
    ///
    /// Which cut that is depends on which edge was grabbed, and the op always
    /// names the clip on the cut's RIGHT: the start edge rolls this clip
    /// against its predecessor, the end edge rolls this clip's successor
    /// against it. With no clip on the other side of the edge — a gap, or an
    /// overlap, which is a transition — there is no cut here and no session
    /// starts, so the drag is inert rather than quietly doing a trim.
    func beginRoll(_ id: UInt32, edge: TimelineEdge, flags: NSEvent.ModifierFlags) {
        guard let clip = snapshot.clip(id),
              let index = snapshot.trackIndex(of: clip.track),
              !snapshot.tracks[index].locked
        else { return }
        let neighbours = snapshot.clips.filter { $0.track == clip.track && $0.id != id }
        let (left, right): (ClipSnapshot, ClipSnapshot)
        switch edge {
        case .start:
            guard let previous = neighbours.first(where: { $0.end == clip.start }) else { return }
            (left, right) = (previous, clip)
        case .end:
            guard let next = neighbours.first(where: { $0.start == clip.end }) else { return }
            (left, right) = (clip, next)
        }
        let frame = max(snapshot.canvas.fps.frameDuration, 1)
        dragSnapper = makeSnapper(excluding: [left.id, right.id], suppressed: flags.contains(.command))
        roll = RollSession(
            clip: right.id,
            earliest: left.start + frame, latest: right.end - frame,
            time: right.start)
        onLiveBegin?()
    }

    /// Double-click in empty lane space: close the gap it landed in. The core
    /// finds the gap's bounds and beeps through `applyEdit` when there is
    /// none to close, so the view only has to name the track.
    func closeGap(row: Int, at time: Ticks) {
        guard let track = track(atRow: row) else { return }
        onEdit?("Close Gap", [.closeGap(track: track.id, at: max(time, 0))])
    }

}

extension EditorViewController {

    // MARK: - Nudging

    /// `,` and `.`, ×10 with ⇧ — the selection moved by whole frames.
    ///
    /// A plain `move_clip`, so the overlap rule refuses it exactly as a drag
    /// to the same place would, and `applyEdit` beeps for us.
    func nudgeSelection(frames: Int) {
        guard let document = document, !document.selection.isEmpty else {
            NSSound.beep()
            return
        }
        let frame = max(document.editedProject.snapshot.canvas.fps.frameDuration, 1)
        document.applyEdit(
            "Nudge Clips",
            .moveClip(clips: Array(document.selection), delta: Ticks(frames) * frame))
    }

    // MARK: - Closing a gap

    /// Clip ▸ Close Gap: the gap under the playhead, on the selected clip's
    /// track — or, with nothing selected, the front-most track, which is
    /// where the eye goes and where `EditorViewController+AddClips` puts a
    /// new clip for the same reason.
    func closeGapAtPlayheadCommand() {
        guard let document = document, let track = targetTrack else {
            NSSound.beep()
            return
        }
        document.applyEdit("Close Gap", .closeGap(track: track, at: document.playhead))
    }

    // MARK: - Insert and overwrite

    /// Edit ▸ Insert at Playhead and Edit ▸ Overwrite at Playhead, for the
    /// Media tab's selected file.
    ///
    /// The destination is `targetTrack` and the time is the playhead, so the
    /// two commands read exactly as their names do. Everything else — the
    /// split, the room, the clearing — is one core op.
    func placeSelectedMedia(insert: Bool) {
        guard let document = document, let media = document.selectedMedia,
              document.project.snapshot.media(media) != nil, let track = targetTrack
        else {
            NSSound.beep()
            return
        }
        let at = document.playhead
        document.applyEdit(
            insert ? "Insert" : "Overwrite",
            insert
                ? .insertClip(track: track, media: media, at: at)
                : .overwriteClip(track: track, media: media, at: at))
    }

    // MARK: - Selecting a whole track

    /// Edit ▸ Select All on Track: every clip on the selected clip's track,
    /// or on the front-most track when nothing is selected.
    func selectAllOnTrack() {
        guard let document = document, let track = targetTrack else {
            NSSound.beep()
            return
        }
        let ids = document.editedProject.snapshot.clips.filter { $0.track == track }.map { $0.id }
        guard !ids.isEmpty else {
            NSSound.beep()
            return
        }
        document.selection = Set(ids)
        viewStateDidChange()
    }

    /// The track these commands act on — `ProjectDocument.targetTrack`, so
    /// the Edit menu and the media row's context menu cannot disagree.
    var targetTrack: UInt32? { document?.targetTrack }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns; nil means "not
    /// mine".
    func validateEdgeAction(_ action: Selector) -> Bool? {
        guard let document = document else { return false }
        switch action {
        case #selector(closeGapAtPlayhead(_:)), #selector(selectAllClipsOnTrack(_:)):
            return targetTrack != nil && !document.editedProject.snapshot.clips.isEmpty
        case #selector(insertMediaAtPlayhead(_:)), #selector(overwriteMediaAtPlayhead(_:)):
            // Live only when the Media tab has a row selected: without one
            // there is nothing to place, and a live item that always beeps
            // is worse than a dead one.
            guard let media = document.selectedMedia else { return false }
            return document.project.snapshot.media(media) != nil && targetTrack != nil
        default:
            return nil
        }
    }
}
