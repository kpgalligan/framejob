import AppKit

/// Reveal in Timeline's other half (road map 2's phase 8c): the Media tab
/// picks the clips, and these two put them on screen.
///
/// The split is the usual one and it is not optional. A pane cannot reach the
/// timeline — `EditorViewController`'s views are its own, and the inspector
/// talks to the editor through `onCommand`, a bare `Selector` — so the pane
/// writes the SELECTION (view state, the way it writes `selectedMedia`) and
/// sends a command; the editor publishes it on the one document channel and
/// asks the timeline to scroll. Nothing here is an op, nothing registers an
/// undo step, and there is no MCP mirror to owe: `set_selection` has been the
/// mirror of "the selection changed" since M2, and an agent that wants these
/// clips selected already asks for them by id.
extension EditorViewController {
    /// The selection the Media tab just wrote, published and scrolled to.
    ///
    /// It publishes FIRST: `viewStateDidChange` is what pushes the new
    /// selection into `TimelineView.update`, and scrolling to a clip the view
    /// has not been told about yet would work by luck (the x mapping does not
    /// depend on the selection today) and stop working the day it does.
    ///
    /// The clip it reveals is the EARLIEST — the first one the eye would look
    /// for — with the lower id breaking a tie so that two clips starting
    /// together always reveal the same one. `Array.min(by:)` is not
    /// documented stable, which is exactly why the tiebreak is written down:
    /// with it the answer is a total order and cannot depend on the sort.
    /// (`paste_attributes` answers the same "several clips, one of them
    /// first" question with a third term, the front-most track — it is
    /// choosing a clip to COPY FROM, where the choice changes the result;
    /// here two clips at one start are equally good to look at.)
    @objc func revealSelectionInTimeline(_ sender: Any?) {
        viewStateDidChange()
        guard let document = document, let timeline = timeline else { return }
        let selected = document.editedProject.snapshot.clips.filter {
            document.selection.contains($0.id)
        }
        guard let first = selected.min(by: { ($0.start, $0.id) < ($1.start, $1.id) }) else {
            return
        }
        timeline.reveal(first)
    }
}

extension TimelineView {
    /// Scrolls `clip` into view, in both directions, leaving the scroll
    /// position alone on whichever axis already shows it.
    ///
    /// **Horizontally this is `revealPlayhead`'s rule, deliberately**: the
    /// same 24 pt margins and the same "put it 35 % in" landing, so a clip
    /// found through the Media tab arrives where a clip the playhead ran onto
    /// arrives. That is what `scroll(toX:)` had to widen from private for — a
    /// widening this change forces, in the shape phase 1 set when
    /// `dragSnapper` and `makeSnapper` widened for
    /// `EditorViewController+Edge.swift`. The BODY stays out of the frozen
    /// file; only the one word changed there.
    ///
    /// **Vertically it is `scrollToVisible`**, which needed no widening at
    /// all: `content` is already internal (the media drop target in
    /// `MediaRowView.swift` reaches it), and the minimum scroll that shows a
    /// lane is the right answer for lanes — there is no "35 % down" to want.
    /// The rect is grown UPWARD by the ruler's height because the ruler is a
    /// floating subview pinned to the top of the visible rectangle: a lane
    /// scrolled to sit flush with the top edge would sit UNDER it. The x range
    /// asked for is exactly the one already visible, so this call can only
    /// move the view vertically, and it goes first for that reason — the
    /// horizontal step below then reads a `pinnedX` nothing has moved.
    ///
    /// A clip on a track this view has not been told about yet, or a viewport
    /// with no size (before the first layout), is nothing to scroll to.
    func reveal(_ clip: ClipSnapshot) {
        guard let index = snapshot.tracks.firstIndex(where: { $0.id == clip.track }),
              layout.viewport.width > 0
        else { return }
        let rect = layout.clipRect(clip, row: layout.row(forTrackIndex: index))

        content.scrollToVisible(
            CGRect(
                x: pinnedX, y: rect.minY - TimelineLayout.rulerHeight,
                width: layout.viewport.width, height: rect.height + TimelineLayout.rulerHeight))

        let left = pinnedX + TimelineLayout.headerWidth + 24
        let right = pinnedX + layout.viewport.width - 24
        guard rect.minX < left || rect.minX > right else { return }
        scroll(toX: rect.minX - TimelineLayout.headerWidth - layout.viewport.width * 0.35)
    }
}
