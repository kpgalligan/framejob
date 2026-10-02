import AppKit

/// The timeline's half of the editor: installing `TimelineView` in the
/// bottom pane, turning its `on*` intents into `ProjectDocument` edits, and
/// the clip/track/marker menu commands the shell stage stubbed.
///
/// Nothing here holds state — an extension cannot — which is deliberate: the
/// gesture sessions live on the timeline view and the model lives on the
/// document, so this file is only ever the seam between them.
extension EditorViewController {
    /// The installed timeline, found by kind rather than kept in a stored
    /// property: `EditorViewController.swift` is frozen at wiring, and the
    /// pane container is the seam it publishes.
    var timeline: TimelineView? {
        timelineContainer.subviews.compactMap { $0 as? TimelineView }.first
    }

    // MARK: - Installation

    /// Replaces the timeline pane's placeholder. Called once from
    /// `viewDidLoad`, before the first `refreshFromDocument`.
    func installTimeline() {
        let timeline = TimelineView()
        timeline.translatesAutoresizingMaskIntoConstraints = false
        for existing in timelineContainer.subviews {
            existing.removeFromSuperview()
        }
        timelineContainer.addSubview(timeline)
        NSLayoutConstraint.activate([
            timeline.topAnchor.constraint(equalTo: timelineContainer.topAnchor),
            timeline.bottomAnchor.constraint(equalTo: timelineContainer.bottomAnchor),
            timeline.leadingAnchor.constraint(equalTo: timelineContainer.leadingAnchor),
            timeline.trailingAnchor.constraint(equalTo: timelineContainer.trailingAnchor),
        ])

        // One-line forwards only (app/CLAUDE.md): every body is a named
        // method on this controller.
        timeline.onSelectionChanged = { [weak self] ids in self?.timelineSelected(ids) }
        timeline.onScrub = { [weak self] time in self?.timelineScrubbed(time) }
        timeline.onLiveBegin = { [weak self] in self?.document?.beginLiveEdit() }
        timeline.onLiveUpdate = { [weak self] ops in self?.timelineLiveUpdated(ops) }
        timeline.onLiveEnd = { [weak self] name in self?.timelineLiveEnded(name) }
        timeline.onEdit = { [weak self] name, ops in self?.document?.applyEdit(name, ops) }
        timeline.onGroupedEdit = { [weak self] name, ops in self?.document?.performGroupedEdit(name, ops) }
        timeline.onRemoveTrack = { [weak self] id in self?.removeTrackCommand(id) }
        timeline.onProbe = { [weak self] ops in self?.timelineProbe(ops) }
        timeline.onSnapCandidates = { [weak self] clips in self?.timelineCandidates(clips) ?? [] }
        timeline.onSnappingToggled = { [weak self] in self?.toggleSnapping(nil) }
        timeline.onTrackHeightChanged = { [weak self] index in self?.applyTrackHeight(index) }
        timeline.onBreadcrumb = { [weak self] level in self?.leaveAllNests(to: level) }
        timeline.onOpenNest = { [weak self] id in self?.openNest(clipID: id) }
        timeline.onActionSelected = { [weak self] clip, id in self?.selectAction(id, on: clip) }

        timeline.snappingEnabled = snappingEnabled
        timeline.trackHeightIndex = trackHeight
        refreshTimeline(isLive: false)
    }

    /// Project → timeline, from `refreshFromDocument`. Snap candidates are
    /// deliberately NOT pushed here: they are an FFI round-trip and this runs
    /// on every live tick, so the timeline asks for them once per gesture
    /// through `onSnapCandidates` instead.
    func refreshTimeline(isLive: Bool) {
        guard let document = document, let timeline = timeline else { return }
        // The EDITED project (road map 2's phase 9): with a nest open the
        // timeline shows the NEST's tracks and clips, at its own zero, and
        // every op it builds out of that snapshot is stamped with the scope
        // on its way through `ProjectDocument.applyEdit`. At the top level
        // this is `document.project` and nothing about the push changed.
        timeline.update(
            snapshot: document.editedProject.snapshot,
            selection: document.selection,
            playhead: document.playhead,
            inOutRange: document.inOutRange,
            cacheDirectory: document.cacheDirectory)
        // The trail is NOT part of `update(...)`: it describes where the
        // snapshot came FROM, which the snapshot itself cannot say.
        timeline.breadcrumb = nestBreadcrumb()
        timeline.selectedAction = document.selectedAction
    }

    /// Playhead → timeline. Separate from `refreshTimeline` because playback
    /// moves it thirty times a second and nothing else changes.
    func timelinePlayheadMoved() {
        timeline?.setPlayhead(document?.playhead ?? 0)
        // Entering a span selects it (spec §11 CI-1), so a moved playhead can
        // change the selected action; pushed only on a change, since the
        // setter redraws the lanes and the ruler.
        if timeline?.selectedAction != document?.selectedAction {
            timeline?.selectedAction = document?.selectedAction
        }
    }

    /// `View ▸ Timeline Track Height` and the timeline bar's S/M/L, in one
    /// place.
    ///
    /// The control was visual-only until the redesign; it now picks a ROW of
    /// `DS.trackHeights`, and which COLUMN of that row a lane takes is its
    /// kind — text, video or audio (`TimelineLayout.trackKind`). Nothing more
    /// is needed here: `trackHeightIndex`'s `didSet` rebuilds the layout, and
    /// the rebuild is what re-classifies every track. The index is still
    /// clamped to 0...2 before it is persisted, because a stale default from
    /// an older build must not index past the table.
    func applyTrackHeight(_ index: Int) {
        trackHeight = min(max(index, 0), 2)
        UserDefaults.standard.set(trackHeight, forKey: Self.trackHeightKey)
        timeline?.trackHeightIndex = trackHeight
    }

    // MARK: - Intents from the view

    /// A PICK, which is not the same thing as a selection change: the
    /// inspector is told first and unconditionally, because clicking a clip
    /// means "show me this one" even when it was already selected (the design
    /// handoff's interaction list, and the reason `clipPicked()` exists rather
    /// than the panel inferring it from `ids != lastSelection`). The guard
    /// below still stops an unchanged selection from posting a refresh.
    private func timelineSelected(_ ids: Set<UInt32>) {
        guard let document = document else { return }
        if !ids.isEmpty { inspector?.clipPicked() }
        guard document.selection != ids else { return }
        document.selection = ids
        viewStateDidChange()
    }

    private func timelineScrubbed(_ time: Ticks) {
        playback.pause()
        setPlayhead(time)
    }

    /// Applies ops to the current handle PURELY so a gesture can learn the
    /// ids the core is about to mint (`duplicate`, `add_track`). This is not
    /// an edit: nothing is published, no undo step is registered, and the
    /// handle it produces is dropped. `applying` is pure (spec §5.5), which
    /// is the only reason asking is legitimate.
    private func timelineProbe(_ ops: [ReelOp]) -> ProjectSnapshot? {
        guard let document = document else { return nil }
        let probed: ReelProject?
        do {
            // The SCOPED handle with PLAIN ops, which is the shape a probe
            // wants inside a nest and the only one that answers correctly:
            // the view carries the document's own `next_id`, so the ids it
            // mints are the ids the real scoped edit will mint, and they come
            // back at the view's top level where the gesture looks for them.
            // Probing the parent with scoped ops would answer a parent
            // project whose top level is the timeline's clips.
            probed = try document.editedProject.applying(ops).project
        } catch {
            return nil
        }
        return probed?.snapshot
    }

    private func timelineCandidates(_ clips: [UInt32]) -> [Ticks] {
        document?.editedProject.snapCandidates(excluding: clips) ?? []
    }

    // MARK: - Selection helpers

    /// The selected clips, in timeline order.
    var selectedClips: [ClipSnapshot] {
        guard let document = document else { return [] }
        let ids = document.selection
        return document.editedProject.snapshot.clips.filter { ids.contains($0.id) }
            .sorted { $0.start < $1.start }
    }

    /// The track a track command acts on: the one holding the first selected
    /// clip, else the front-most (spec §4.4 puts that on top).
    var currentTrack: TrackSnapshot? {
        guard let document = document else { return nil }
        let snapshot = document.editedProject.snapshot
        if let clip = selectedClips.first, let track = snapshot.track(clip.track) { return track }
        return snapshot.tracks.last
    }

    /// Clips that both are selected and cross the playhead — what a
    /// playhead-relative op (freeze frame, trim to playhead) can act on.
    private var clipsUnderPlayhead: [ClipSnapshot] {
        guard let document = document else { return [] }
        let now = document.playhead
        return selectedClips.filter { $0.contains(now) }
    }

    // MARK: - Clip commands (spec §6, the keys of §9)

    /// ⌘T. With nothing selected the core splits every unlocked clip under
    /// the playhead, which is what `clips: nil` means.
    func splitAtPlayheadCommand() {
        guard let document = document else { return }
        let ids = document.selection
        document.applyEdit(
            "Split", .split(clips: ids.isEmpty ? nil : Array(ids), at: document.playhead))
    }

    /// W / E. Every selected clip is offered to the core; the ones the
    /// playhead is not inside are refused, and a wholly refused batch beeps.
    func trimToPlayhead(_ edge: TimelineEdge) {
        guard let document = document else { return }
        let now = document.playhead
        let ops = clipsUnderPlayhead.map { clip in
            edge == .start
                ? ReelOp.trimStart(clip: clip.id, to: now) : ReelOp.trimEnd(clip: clip.id, to: now)
        }
        guard !ops.isEmpty else {
            NSSound.beep()
            return
        }
        document.applyEdit(edge == .start ? "Trim Start" : "Trim End", ops)
    }

    /// ⌫ — removes the selection and leaves the gap, or LIFTS the in/out
    /// range when nothing is selected (spec §9).
    ///
    /// The pairing with ⌘⌫ below is deliberate and complete: each key does
    /// the same thing to a selection and to a range, and the difference
    /// between the two keys is only whether the hole closes.
    func deleteSelection() {
        guard let document = document else { return }
        // With an action selected ⌫ removes IT, not its clip (spec §9).
        if document.selectedActionSnapshot != nil {
            removeSelectedActionCommand()
            return
        }
        if document.selection.isEmpty {
            guard let range = document.inOutRange, range.end > range.start else {
                NSSound.beep()
                return
            }
            document.applyEdit("Lift", .liftRange(from: range.start, to: range.end))
            return
        }
        document.applyEdit("Delete", .delete(clips: Array(document.selection)))
    }

    /// ⌘⌫ — the selection, or the in/out range when nothing is selected
    /// (spec §9).
    func rippleDeleteSelection() {
        guard let document = document else { return }
        if document.selection.isEmpty {
            guard let range = document.inOutRange, range.end > range.start else {
                NSSound.beep()
                return
            }
            document.applyEdit(
                "Ripple Delete", .rippleDeleteRange(from: range.start, to: range.end))
            return
        }
        document.applyEdit("Ripple Delete", .rippleDelete(clips: Array(document.selection)))
    }

    /// ⌘D — copies land after the originals' span; ⌥-dragging then moves
    /// them, which is the same op with a `move_clip` behind it.
    func duplicateSelection() {
        guard let document = document, !document.selection.isEmpty else {
            NSSound.beep()
            return
        }
        document.applyEdit("Duplicate", .duplicate(clips: Array(document.selection)))
    }

    /// ⇧⌘F — one still clip filling a gap opened at the playhead.
    func freezeSelection() {
        guard let document = document, let clip = clipsUnderPlayhead.first else {
            NSSound.beep()
            return
        }
        document.applyEdit("Freeze Frame", .freezeFrame(clip: clip.id, at: document.playhead))
    }

    /// ⌥⌘D — the audio moves to its own clip on the track below.
    func detachSelectionAudio() {
        guard let document = document, !selectedClips.isEmpty else {
            NSSound.beep()
            return
        }
        document.applyEdit("Detach Audio", selectedClips.map { .detachAudio(clip: $0.id) })
    }

    // Clip ▸ Speed… is a sheet, not a menu: `SpeedSheetController`, put up by
    // `EditorViewController+Export.swift`.

    // MARK: - Track commands

    /// ⇧⌘N — a new track at the front, which is the top lane.
    func newTrackCommand() {
        guard let document = document else { return }
        document.applyEdit(
            "New Track", .addTrack(index: document.editedProject.snapshot.tracks.count))
    }

    /// A non-empty track refuses to go without `with_clips`, so the clips it
    /// would take go in the question rather than in a beep. `id` is the
    /// track context menu's clicked track; Track ▸ Remove Track passes none
    /// and acts on `currentTrack`.
    func removeTrackCommand(_ id: UInt32? = nil) {
        let track: TrackSnapshot?
        if let id = id {
            track = document?.editedProject.snapshot.track(id)
        } else {
            track = currentTrack
        }
        guard let document = document, let track = track else {
            NSSound.beep()
            return
        }
        let clips = document.editedProject.snapshot.clips(onTrack: track.id)
        guard !clips.isEmpty else {
            document.applyEdit("Remove Track", .removeTrack(track: track.id))
            return
        }
        guard let window = view.window else {
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Remove “\(track.name)”?"
        alert.informativeText =
            clips.count == 1
            ? "The track still holds 1 clip, which will be removed with it."
            : "The track still holds \(clips.count) clips, which will be removed with it."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak document] response in
            guard response == .alertFirstButtonReturn, let document = document else { return }
            // A sheet's completion is not an AppKit event: the grouped entry
            // point is mandatory here (app/CLAUDE.md's undo pitfall).
            document.performGroupedEdit(
                "Remove Track", [.removeTrack(track: track.id, withClips: true)])
        }
    }

    func removeEmptyTracksCommand() {
        document?.applyEdit("Remove Empty Tracks", .removeEmptyTracks())
    }

    /// Track ▸ Hide Video / Mute Audio / Lock Track / Solo — the same four
    /// toggles the header column draws. Solo is audio only and mute wins over
    /// it (spec §7.2); the core's envelopes apply the rule, so this is one
    /// flag like the other three.
    func toggleTrack(_ button: TimelineHeaderButton) {
        guard let document = document, let track = currentTrack else {
            NSSound.beep()
            return
        }
        switch button {
        case .hidden:
            document.applyEdit("Hide Track", .setTrack(track: track.id, hidden: !track.hidden))
        case .muted:
            document.applyEdit("Mute Track", .setTrack(track: track.id, muted: !track.muted))
        case .locked:
            document.applyEdit("Lock Track", .setTrack(track: track.id, locked: !track.locked))
        case .solo:
            document.applyEdit("Solo Track", .setTrack(track: track.id, solo: !track.solo))
        }
    }

    // MARK: - Markers

    /// M. Markers snap to frames and two may not share a time, so a second
    /// marker on the same frame is the core's refusal (a beep), not ours.
    func addMarkerCommand() {
        guard let document = document else { return }
        // Not inside a nest. A nest has no markers (`core/src/scope.rs`
        // refuses all three marker ops by name), and the playhead here is
        // NEST-local, so the op would have to be sent unscoped at a tick
        // measured from the wrong zero. The menu item validates false
        // (`validateNestScopeAction`); this is the bare-M path's own guard,
        // which no validator covers.
        guard document.scope == nil else {
            NSSound.beep()
            return
        }
        document.applyEdit("Add Marker", .addMarker(at: document.playhead))
    }

    func stepMarker(forward: Bool) {
        guard let document = document else { return }
        let times = document.project.snapshot.markers.map { $0.time }.sorted()
        let now = document.playhead
        guard let target = forward ? times.first(where: { $0 > now })
            : times.last(where: { $0 < now })
        else {
            NSSound.beep()
            return
        }
        playback.pause()
        setPlayhead(target)
    }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// mine" and leaves the base file's answer alone.
    func validateTimelineAction(_ action: Selector) -> Bool? {
        guard let document = document else { return false }
        let hasSelection = !document.selection.isEmpty
        switch action {
        case #selector(duplicateClips(_:)), #selector(detachAudio(_:)):
            return hasSelection
        case #selector(deleteClips(_:)):
            // ⌫ lifts the in/out range with nothing selected, so the item
            // has to be live for that too.
            //
            // And it has to be DEAD while text is being edited, which is
            // the guard AppDelegate's comment on this item asks for and
            // which nothing supplied before: "\u{8}" is a modifier-less key
            // equivalent, AppKit resolves those ahead of the first
            // responder, and a live item therefore eats the Delete key in
            // the timecode field, an inline rename and a text clip alike.
            // The same test `handleEditorKey` opens with.
            if view.window?.firstResponder is NSText { return false }
            return hasSelection || (document.inOutRange.map { $0.end > $0.start } ?? false)
        case #selector(showSpeedSheet(_:)):
            // `set_speed` is an ERROR on a non-media source (spec §6), so the
            // item is live only when the selection holds something it can act
            // on — the same subset `presentSpeedSheet` opens the sheet with.
            return selectedClips.contains { $0.source.hasSourceBound }
        case #selector(rippleDeleteClips(_:)):
            // The same guard as Delete: ⌘⌫ in a field editor is "delete to
            // the start of the line", not a ripple delete of the selection —
            // and the selected clip is the one whose rename field is open.
            if view.window?.firstResponder is NSText { return false }
            return hasSelection || (document.inOutRange.map { $0.end > $0.start } ?? false)
        case #selector(trimStartToPlayhead(_:)), #selector(trimEndToPlayhead(_:)),
            #selector(freezeFrame(_:)):
            return !clipsUnderPlayhead.isEmpty
        case #selector(splitAtPlayhead(_:)):
            return !document.editedProject.snapshot.clips.isEmpty
        case #selector(removeTrack(_:)), #selector(toggleTrackHidden(_:)),
            #selector(toggleTrackMuted(_:)), #selector(toggleTrackLocked(_:)):
            return currentTrack != nil
        case #selector(nextMarker(_:)), #selector(previousMarker(_:)):
            return !document.project.snapshot.markers.isEmpty
        default:
            return nil
        }
    }
}
