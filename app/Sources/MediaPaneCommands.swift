import AppKit

/// The seven commands a media row calls back into, and the one question it
/// asks: `drop`, `select`, `place`, `revealInTimeline`, `reveal` (in Finder),
/// `relink` and `remove`, plus `canRevealInTimeline`.
///
/// **Why they are a file of their own.** Every one of them applies an edit
/// through `binding`, or writes the document's view state, or puts a panel or
/// an alert up — which is the pane's business and never a row's
/// (`MediaRowView.swift` argues that half) — and none of them touches the
/// list's views except `select`, which redraws them. So they are a seam, not
/// an amputation: what is left in `MediaPane.swift` is the LIST — its one
/// section, its three chrome bands, the find band's arrangement and the Finder
/// drop onto the panel.
///
/// The cut is road map 2's phase 8c paying the ~600-line rule a second time
/// for this pane. The first payment (commit d69de99) moved the row and its
/// drag out at 822 lines, precisely so this phase's four additions would have
/// room; the additions cost more than the room left, as phase 6 warned they
/// would ("budget the cut against the pessimistic number"). It costs ONE
/// widening — `MediaPane.rows`, which `select` redraws — which is the toll
/// `ExporterLoudness.swift` records for splitting a type across files, and it
/// is the whole of it, because everything else here was already internal for
/// the row to call.
extension MediaPane {
    /// Where a dragged row landed. Returns false when the drop is refused, so
    /// the drag springs back rather than silently doing nothing.
    func drop(_ media: UInt32, on destination: NSView, target: MediaDropTarget) -> Bool {
        // A drag started in ANOTHER document's panel must not edit this one:
        // the session carries the source row, and the two windows differ.
        guard destination.window === window, window != nil else { return false }
        guard binding.snapshot.media(media) != nil else { return false }
        let fps = binding.canvas.fps
        switch target {
        case .track(let track, let at, let mode):
            let when = ReelTime.snapToFrame(max(at, 0), fps: fps)
            switch mode {
            case .add:
                binding.apply("Add Clip", [.addClip(track: track, media: media, at: when)])
            case .insert:
                binding.apply("Insert", [.insertClip(track: track, media: media, at: when)])
            case .overwrite:
                binding.apply(
                    "Overwrite", [.overwriteClip(track: track, media: media, at: when)])
            }
        case .canvas:
            let at = ReelTime.snapToFrame(max(binding.playhead, 0), fps: fps)
            let index = binding.snapshot.tracks.count
            // `add_track` returns a project, not an id (§11's one entry
            // point), so the id is learned from a PURE trial application
            // before the real edit runs.
            let existing = Set(binding.snapshot.tracks.map { $0.id })
            let probed = inspector?.onProbe?([.addTrack(index: index)])
            guard let track = probed?.tracks.first(where: { !existing.contains($0.id) })?.id else {
                guard let top = binding.snapshot.tracks.last?.id else { return false }
                binding.apply("Add Clip", [.addClip(track: top, media: media, at: at)])
                return true
            }
            binding.apply(
                "Add Clip",
                [.addTrack(index: index), .addClip(track: track, media: media, at: at)])
        }
        return true
    }

    /// A row was clicked: it becomes the document's selected media, which is
    /// what Edit ▸ Insert / Overwrite at Playhead act on. View state, so it
    /// neither dirties the document nor registers an undo step.
    func select(_ media: UInt32) {
        guard let document = binding.document, document.selectedMedia != media else { return }
        document.selectedMedia = media
        // Only the rows draw the selection, and the Edit menu asks for it
        // when it validates, so a redraw is the whole of the update.
        rows.forEach { $0.view.needsDisplay = true }
    }

    /// The row menu's Insert / Overwrite at Playhead. The same two ops the
    /// Edit menu runs, on the row that was right-clicked.
    func place(_ media: UInt32, insert: Bool) {
        select(media)
        guard binding.snapshot.media(media) != nil,
              let track = binding.document?.targetTrack
        else {
            NSSound.beep()
            return
        }
        let at = ReelTime.snapToFrame(max(binding.playhead, 0), fps: binding.canvas.fps)
        binding.apply(
            insert ? "Insert" : "Overwrite",
            [
                insert
                    ? .insertClip(track: track, media: media, at: at)
                    : .overwriteClip(track: track, media: media, at: at)
            ])
    }

    /// Whether the row menu's Reveal in Timeline has anything to reveal —
    /// asked by the row as it builds the menu, so the item is dead rather
    /// than silently doing nothing.
    ///
    /// It is `timelineClipsUsing` and not `clipsUsing` deliberately: media
    /// used only INSIDE a nest has users the selection cannot hold
    /// (`MediaUsage.swift`), and this is the case the pane's old
    /// top-level-only usage test could not tell apart from "used by nothing".
    func canRevealInTimeline(_ media: UInt32) -> Bool {
        !binding.snapshot.timelineClipsUsing(media).isEmpty
    }

    /// The row menu's Reveal in Timeline: select every top-level clip that
    /// shows this file, and scroll the first one into view.
    ///
    /// The selection is VIEW state, so this writes it on the document the way
    /// `select(_:)` writes `selectedMedia` — no op, no undo step — and then
    /// asks the editor to publish it, because the notification and the scroll
    /// both belong to the editor (`MediaReveal.swift`).
    ///
    /// **It throws the panel off this tab, and that is accepted rather than
    /// fought.** `InspectorViewController.refresh(isLive:)` switches to the
    /// Clip tab whenever a non-empty selection changes, which is the panel's
    /// rule for ⌘A, paste and the agent's `set_selection` alike; a command
    /// whose whole point is "here are the clips" has no business being the
    /// one exception, and the Media tab is one click away.
    func revealInTimeline(_ media: UInt32) {
        select(media)
        let clips = binding.snapshot.timelineClipsUsing(media)
        guard !clips.isEmpty, let document = binding.document else {
            NSSound.beep()
            return
        }
        document.selection = Set(clips.map { $0.id })
        inspector?.onCommand?(#selector(EditorViewController.revealSelectionInTimeline(_:)))
    }

    /// The row menu's Reveal in Finder.
    func reveal(_ media: UInt32) {
        guard let entry = binding.snapshot.media(media), let url = mediaURL(for: entry) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Relink… — the offer a project whose media has moved opens with (§5.6).
    ///
    /// **This is the THIRD of three relink paths, and every one of them owes
    /// the cache pass.** A relinked file is a file this project has never
    /// read: there is no filmstrip, no thumbnail and no peaks on disk for it,
    /// and nothing downstream of an edit makes them — neither `applyEdit` nor
    /// `performGroupedEdit` touches `generateCaches()`, and only the open path
    /// and the import path otherwise call it. So the row would come back with
    /// a name and no picture, the timeline clip with a blank body, and Remove
    /// Silences with no peaks to read. `RelinkSheetController.applyClicked`
    /// has always called it and `AgentServer.relinkMedia` calls it on the line
    /// after its edit; this path is the one that did not, from the day the row
    /// menu got the item. A fourth inherits the duty.
    ///
    /// It is the WHOLE pass rather than this one file, which is the other two
    /// paths' shape and is deliberate here: `ProjectDocument.generateCaches`
    /// is the app's one spelling of "make what is missing", the relink SHEET
    /// relinks several files in a single step and so could use nothing
    /// narrower, and a per-media entry point invented for this one call site
    /// would be a second answer to that question. What it costs
    /// is worth saying, because the function's own doc understates it and this
    /// phase measured otherwise: the pass re-decodes every media that has a
    /// file rather than skipping the ones already cached (a filmstrip frame's
    /// modification date moves on a second pass), all of it in a detached
    /// utility-priority task. A relink is a rare, deliberate act — one panel,
    /// one file — so a few background decodes on it buy the guarantee that
    /// every one of the three paths leaves the same caches behind.
    func relink(_ media: UInt32) {
        guard let entry = binding.snapshot.media(media), let window = window else {
            NSSound.beep()
            return
        }
        let binding = self.binding
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the file for “\(entry.name)”."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            // A sheet's completion is not an AppKit event: the grouped entry
            // point is mandatory here (app/CLAUDE.md's undo pitfall).
            binding.applyGrouped(
                "Relink Media",
                [
                    .relinkMedia(
                        media: media, path: url.path, bookmark: bookmarkString(for: url))
                ])
            // The edit is synchronous all the way down (`onGroupedEdit` →
            // `ProjectDocument.performGroupedEdit` → `applyEdit`), so the
            // document is already holding the new path by this line and the
            // pass generates against the file that was just chosen.
            binding.document?.generateCaches()
        }
    }

    /// Remove — refused while the media is in use, with the "and its clips"
    /// offer §4.3 asks for.
    ///
    /// The users are counted through `clipsUsing`, which walks the NESTS as
    /// well as the timeline, because that is the set `remove_media` refuses
    /// against and the set `with_clips: true` deletes. Filtering
    /// `snapshot.clips` here — what this line used to do — meant that media
    /// used only inside a compound clip looked unused, went to the core as a
    /// plain `remove_media`, came back `Ok(None)`, and reached the user as a
    /// beep with the alert never shown (`MediaUsage.swift`).
    func remove(_ media: UInt32) {
        guard let entry = binding.snapshot.media(media) else {
            NSSound.beep()
            return
        }
        let users = binding.snapshot.clipsUsing(media)
        guard !users.isEmpty else {
            binding.apply("Remove Media", [.removeMedia(media: media)])
            return
        }
        guard let window = window else {
            NSSound.beep()
            return
        }
        let binding = self.binding
        let alert = NSAlert()
        alert.messageText = "Remove “\(entry.name)”?"
        alert.informativeText =
            users.count == 1
            ? "It is used by 1 clip, which will be removed with it."
            : "It is used by \(users.count) clips, which will be removed with it."
        alert.addButton(withTitle: "Remove and Delete Clips")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            binding.applyGrouped(
                "Remove Media", [.removeMedia(media: media, withClips: true)])
        }
    }
}
