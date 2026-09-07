import AppKit

/// The inline clip rename — a double-click on a clip, or Clip ▸ Rename…
/// (⇧⌘R) — over the one editor `TimelineView` already keeps for a track
/// header and a marker (`beginRename`).
///
/// It is an extension because `TimelineView.swift` is frozen at wiring
/// (app/CLAUDE.md). The frozen file keeps two hooks: the `clicks == 2` branch
/// of `beginGesture`'s `.clip` case, placed BEFORE `selectClip` for the reason
/// the ⌥⇧ slip branch is (⇧ would otherwise be read as "toggle membership"),
/// and `relocateRename()` at the end of `rebuildLayout`, which moves the open
/// field to the NEW layout's rect through the `relocate` closure given here.
/// So the field survives a zoom, a resize and any document change while its
/// clip exists — an agent's edit, a save's clean/dirty crossing, another
/// track's solo — instead of being ended, which would COMMIT whatever was
/// typed so far (removing the field ends its editing), and under an agent's
/// grouped edit would fold that half-typed rename into the agent's undo step.
/// When the clip is GONE (a delete under the open field, from ⌘⌫, the
/// timeline bar or an MCP `delete_clips`) the relocator answers nil and the
/// frozen file ends the field with its commit dropped, so no `set_clip` is
/// sent to a dead id — which the core would refuse, and the document would
/// put in a sheet after a delete that succeeded.
///
/// The field sits over the clip's name strip in `content` coordinates — the
/// space `TimelineLayout.clipRect` answers in, so there is nothing to
/// convert — clamped to the visible lanes (`clipRenameFrame`), and it opens
/// showing the name the strip shows (`ProjectSnapshot.name(of:)`), own name
/// or fallback, because what you double-clicked is what you expect to be
/// editing. What it COMMITS is the clip's own name: one `set_clip`, whose
/// core trims the text. Two commits are dropped by the shared editor itself:
///
/// * **An unchanged one.** The field opened on the fallback; sending that
///   back would pin it as the clip's OWN name — an undo step and a dirty
///   document for nothing, and a text clip's strip frozen at the words it
///   had. Every exit commits (Return, Tab, a click elsewhere; there is no
///   Escape), so an accidental double-click has to have a harmless way out.
/// * **An empty one** — right for a track and a marker, whose names cannot
///   be cleared. So the strip cannot clear a name back to the fallback. That
///   is the Clip tab's job: the header field in `ClipSelectionHeaderView`
///   (`ClipPane.swift`) sends `null` for an emptied field.
///
/// Whatever else was being typed into — that header field, a timecode —
/// commits BEFORE the name is read, so the field opens on the name that
/// commit produced (the shared editor blurs too, for the responder handoff).
///
/// The second half of the file is the following-the-layout mechanism for
/// ALL THREE renames: `relocateRename` and the track's and the marker's
/// frames and relocators, which the frozen file's `renameTrack` and
/// `renameMarker` hand to `beginRename` exactly as `beginClipRename` does.
extension TimelineView {

    // MARK: - Following the layout

    /// After a layout rebuild the open field follows its target; when the
    /// target is gone it is ended with its commit DROPPED, so a delete under
    /// an open field never sends a rename to a dead id. Called at the end of
    /// the frozen file's `rebuildLayout`, after the new layout and the
    /// content frame are in place.
    func relocateRename() {
        guard let field = renameField else { return }
        guard let frame = renameRelocate?() else {
            renameCommit = nil
            endRename()
            return
        }
        if field.frame != frame { field.frame = frame }
    }

    /// The track header's field: 20 pt over the row's 13 pt name label.
    func trackRenameFrame(row: Int) -> NSRect {
        NSRect(
            x: 6, y: layout.rowTop(row) - TimelineLayout.rulerHeight + 3,
            width: TimelineLayout.headerWidth - 12, height: 20)
    }

    func trackRenameRelocator(_ track: UInt32) -> () -> NSRect? {
        { [weak self] in
            guard let self, let index = self.snapshot.trackIndex(of: track) else { return nil }
            return self.trackRenameFrame(row: self.layout.row(forTrackIndex: index))
        }
    }

    /// The marker's field in the ruler, 40 pt left of its flag and never past
    /// the ruler's left edge.
    func markerRenameFrame(_ marker: MarkerSnapshot) -> NSRect {
        NSRect(x: max(layout.x(for: marker.time) - 40, 0), y: 3, width: 110, height: 20)
    }

    func markerRenameRelocator(_ marker: UInt32) -> () -> NSRect? {
        { [weak self] in
            guard let self, let now = self.snapshot.marker(marker) else { return nil }
            return self.markerRenameFrame(now)
        }
    }

    // MARK: - The clip's field

    /// The field is never narrower than this: a clip two frames long is a
    /// 2 pt bar at a low zoom, and a 2 pt field cannot be typed into.
    private static var renameMinWidth: CGFloat { 120 }

    /// The strip's 16 pt plus 2: a bezeled `NSTextField` needs a point above
    /// and below an 11 pt line, the same reason the track field is 20 pt
    /// over a 13 pt label. The extra 2 pt lie over the filmstrip's top edge,
    /// which is under the field either way.
    private static var renameHeight: CGFloat { DS.clipHeaderHeight + 2 }

    /// The field's rect over `id`'s name strip under the current layout, or
    /// nil when the clip is gone.
    ///
    /// Clamped to the visible lanes — from the header column's right edge
    /// (the column paints OVER the content's left edge) to the viewport's —
    /// because AppKit does not scroll a timeline to a field editor's caret:
    /// a double-click on the visible part of a long clip whose start is
    /// scrolled off would otherwise open a field whose left-aligned text and
    /// caret are thousands of points away, and the user would type blind
    /// into a bezel. A zoom's relocation reads the viewport BEFORE `setZoom`
    /// re-scrolls, so a clip pushed out of view by the zoom can leave its
    /// field at the old edge; the clip still visible after it, which is the
    /// case, is placed exactly.
    func clipRenameFrame(_ id: UInt32) -> CGRect? {
        guard let clip = snapshot.clip(id), let index = snapshot.trackIndex(of: clip.track)
        else { return nil }
        let row = layout.row(forTrackIndex: index)
        let body = TimelineContentView.bodyRect(layout.clipRect(clip, row: row))
        let visibleMinX = pinnedX + TimelineLayout.headerWidth
        let visibleMaxX = pinnedX + layout.viewport.width
        let x = max(body.minX, visibleMinX)
        let width = max(Self.renameMinWidth, min(body.maxX, visibleMaxX) - x)
        return CGRect(x: x, y: body.minY, width: width, height: Self.renameHeight)
    }

    /// Opens the field over `id`'s name strip.
    ///
    /// A clip on a locked track can still be renamed: a lock protects
    /// placement, a name is not placement, and the core's `set_clip`
    /// consults no lock — refusing here would invent a rule the op does not
    /// have.
    func beginClipRename(_ id: UInt32) {
        // Another editor's commit first (the module doc), so the name read
        // below is the one it produced.
        _ = window?.makeFirstResponder(nil)
        guard let clip = snapshot.clip(id), let frame = clipRenameFrame(id) else { return }
        let relocate: () -> NSRect? = { [weak self] in self?.clipRenameFrame(id) }
        beginRename(in: content, frame: frame, text: snapshot.name(of: clip), relocate: relocate) {
            [weak self] name in
            self?.onEdit?(
                "Rename Clip", [.setClip(clips: [id], patch: ClipPatch(name: .some(name)))])
        }
    }

    /// Clip ▸ Rename…: the field over the first selected clip in timeline
    /// order — the clip the Clip tab's header and the timeline bar's block
    /// speak for — scrolled into view first so it opens where the eye can
    /// find it. Nothing selected is a beep.
    func renameSelectedClip() {
        // Before the rect is read: a timecode field's commit can trim the clip.
        _ = window?.makeFirstResponder(nil)
        guard let clip = snapshot.clips.filter({ selection.contains($0.id) })
                .min(by: { $0.start < $1.start }),
              let index = snapshot.trackIndex(of: clip.track)
        else {
            NSSound.beep()
            return
        }
        var reveal = layout.clipRect(clip, row: layout.row(forTrackIndex: index))
        // Only the field's own width of a long clip, and grown by the two
        // floating bands: the header column and the ruler paint OVER the
        // content's left and top edges, so a rect that is merely inside the
        // clip view can still be under one of them.
        reveal.size.width = min(reveal.width, Self.renameMinWidth) + TimelineLayout.headerWidth
        reveal.origin.x -= TimelineLayout.headerWidth
        reveal.size.height += TimelineLayout.rulerHeight
        reveal.origin.y -= TimelineLayout.rulerHeight
        content.scrollToVisible(reveal)
        beginClipRename(clip.id)
    }
}
