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

    /// A filter that hides the selected row clears the selection, so Insert /
    /// Overwrite at Playhead cannot place a row nobody can see (#68). No work
    /// when nothing selected is hidden: `arrange()` calls it on every refresh.
    func dropHiddenSelection() {
        guard let document = binding.document, let media = document.selectedMedia,
              let row = rows.first(where: { $0.media == media }), row.view.isHidden
        else { return }
        document.selectedMedia = nil
        row.view.needsDisplay = true
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

    /// The row menu's Reveal in Finder: a copy's original, else the file.
    func reveal(_ media: UInt32) {
        guard let entry = binding.snapshot.media(media), let url = revealURL(for: entry) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Relink… — the offer a project whose media has moved opens with (§5.6).
    ///
    /// **One of three relink paths, and all three probe the new file and
    /// owe the cache pass** (spec §11, #63). The chosen file goes to
    /// `ProjectDocument.relinkMedia`, the body this path shares with the
    /// missing-media sheet: import's own probe, so the entry takes the file's
    /// duration, size, rate and flags, a file of another kind is refused in
    /// the core's sentence and a clip past a shorter file's end is held to
    /// it; one grouped undo step; then `ProjectDocument.generateCaches`, the
    /// app's one spelling of "make what is missing", because a relinked file
    /// may be one this project has never read — no filmstrip, thumbnail or
    /// peaks on disk — and nothing downstream of an edit makes them. The
    /// agent's `relink_media` (`AgentServer.relinkMedia`) probes and passes
    /// the same way. What the pass costs is its own doc's: a stat, a marker
    /// read per half and a `fileExists` per media whose marker still matches,
    /// and a rebuild for the one whose file just changed.
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
            binding.document?.relinkMedia([(media: media, url: url)])
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
    /// plain `remove_media`, came back refused, and reached the user as a
    /// beep with the alert never shown (`MediaUsage.swift`).
    func remove(_ media: UInt32) {
        guard let entry = binding.snapshot.media(media) else {
            NSSound.beep()
            return
        }
        // The DOCUMENT's clips, never the scoped view's: `remove_media` is a
        // document-level op (`ReelOp.isDocumentLevel`) and is sent unscoped
        // even with a nest open, so the "and its clips" count has to be the
        // whole file's — the timeline's clips chained with every nest's —
        // or the alert would under-count and the op would refuse.
        let users = binding.documentSnapshot.clipsUsing(media)
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
