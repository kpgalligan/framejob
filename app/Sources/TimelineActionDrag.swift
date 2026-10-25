import AppKit

/// Retiming an action by dragging its band on the timeline (spec §11
/// CI-11): the begin/continue/end bodies, the hover, the cursors and the
/// ghost with its HUD. `TimelineView.swift` is frozen at wiring
/// (app/CLAUDE.md), so it keeps the stored `actionDrag` and `bandHover`, one
/// arm per gesture phase, a draw call, a cursor call and three one-line
/// overrides; the bodies are here.
extension TimelineView {
    /// Mouse-down on a band, after the press has selected the clip and the
    /// action (the timeline selects at mouse-DOWN). A zero-length action is
    /// never dragged — `duration: 0` is invalid input to the core, not a
    /// refusal — and neither is one on a locked track.
    func beginActionDrag(clip id: UInt32, action: UInt32, mode: ActionDragMode, at point: CGPoint) {
        guard let clip = snapshot.clip(id),
              let index = snapshot.trackIndex(of: clip.track),
              !snapshot.tracks[index].locked,
              let found = clip.actions.first(where: { $0.id == action }),
              found.duration > 0
        else { return }
        bandHover = nil
        actionDrag = ActionDragSession(
            clip: clip, action: found, mode: mode,
            grabAt: layout.time(atX: point.x) - clip.start, fps: snapshot.canvas.fps)
        onLiveBegin?()
    }

    /// Mouse-dragged: one `set_action` per tick. A tick the core refuses is
    /// swallowed by `updateLiveEdit` (spec §11 CI-10's last sentence).
    func continueActionDrag(at point: CGPoint) {
        guard var session = actionDrag, let clip = snapshot.clip(session.clip) else { return }
        session.update(clipTime: layout.time(atX: point.x) - clip.start)
        actionDrag = session
        onLiveUpdate?([session.op])
    }

    /// Mouse-up: the gesture as ONE undo step (none when nothing applied),
    /// then — after a real drag — the action selected again, which parks the
    /// playhead at its NEW end.
    func endActionDrag() {
        guard let session = actionDrag else { return }
        actionDrag = nil
        onLiveEnd?(session.undoName)
        if session.didMove { onActionSelected?(session.clip, session.action) }
    }
}

extension TimelineContentView {
    /// One area of this view's own for the band hover; only areas it OWNS are
    /// removed (app/CLAUDE.md "Tracking areas"), and `.inVisibleRect` means a
    /// scroll needs no reinstall.
    func installBandTracking() {
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil))
    }

    /// The band under the pointer, from the one hit test — nil while a drag
    /// is live.
    func bandHoverMoved(with event: NSEvent) {
        guard let owner = timeline else { return }
        guard owner.actionDrag == nil else {
            owner.bandHover = nil
            return
        }
        switch hit(at: convert(event.locationInWindow, from: nil)) {
        case .action(let clip, let action):
            owner.bandHover = ActionBandHover(clip: clip, action: action, edge: nil)
        case .actionEdge(let clip, let action, let edge):
            owner.bandHover = ActionBandHover(clip: clip, action: action, edge: edge)
        default:
            owner.bandHover = nil
        }
    }

    func bandHoverExited() { timeline?.bandHover = nil }

    /// `.openHand` over a band's body and `.resizeLeftRight` over its grips,
    /// for the bands a press can drag: unlocked tracks, positive lengths.
    func addActionBandCursorRects(owner: TimelineView, layout: TimelineLayout, visible: CGRect) {
        for (index, track) in owner.snapshot.tracks.enumerated() where !track.locked {
            let row = layout.row(forTrackIndex: index)
            for clip in owner.snapshot.clips(onTrack: track.id) {
                let rect = layout.clipRect(clip, row: row)
                guard rect.intersects(visible) else { continue }
                let lane = Self.actionLane(
                    content: Self.contentRect(rect), sizeIndex: owner.trackHeightIndex)
                guard lane.height > 0 else { continue }
                for action in clip.actions where action.duration > 0 {
                    addGripCursorRects(
                        Self.bandRect(action, clip: clip, lane: lane, layout: layout))
                }
            }
        }
    }

    /// While a drag has moved: the original band as a dashed ghost, and the
    /// HUD at the band's left, 18 pt above the clip, kept inside the lanes
    /// and the visible rect.
    func drawActionDragOverlay(owner: TimelineView, layout: TimelineLayout) {
        guard let session = owner.actionDrag, session.didMove,
              let clip = owner.snapshot.clip(session.clip),
              let index = owner.snapshot.trackIndex(of: clip.track)
        else { return }
        let rect = layout.clipRect(clip, row: layout.row(forTrackIndex: index))
        let lane = Self.actionLane(
            content: Self.contentRect(rect), sizeIndex: owner.trackHeightIndex)
        let original = ActionSnapshot(
            id: session.action, start: session.originalStart, duration: session.originalDuration)
        ActionDragSession.drawGhost(
            Self.bandRect(original, clip: clip, lane: lane, layout: layout))
        let text = session.hud(base: clip.start, frames: owner.snapshot.canvas.timecodeFrames)
        let width = ActionDragSession.hudWidth(text)
        let visible = visibleRect
        var x = layout.x(for: clip.start + session.start)
        x = min(max(x, visible.minX + TimelineLayout.headerWidth), visible.maxX - width)
        var y = max(rect.minY - 18, visible.minY + layout.lanesTop)
        y = min(y, visible.maxY - ActionDragSession.hudHeight)
        ActionDragSession.drawHUD(text, at: CGPoint(x: x, y: y))
    }
}
