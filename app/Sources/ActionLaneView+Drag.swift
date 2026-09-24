import AppKit

/// Retiming an action by dragging its band in the Clip tab's lane (spec §11
/// CI-11) — the same `ActionDragSession` the timeline drags with, through the
/// binding's live trio, so a drag is ONE undo step.
///
/// The lane selects at mouse-UP, not at the press as the timeline does: a
/// selection rebuilds the pane, and the pane must not rebuild under the
/// pointer (`refresh(isLive:)` skips rebuilds only while a live edit runs).
/// A click and a drop therefore share one path, `releaseBand`.
extension ActionLaneView {
    /// The clip time under `x`: the lane's fraction of the clip's length,
    /// clamped to the clip.
    func clipTime(atX x: CGFloat) -> Ticks {
        guard let clip = clip, clip.duration > 0 else { return 0 }
        let lane = laneRect
        guard lane.width > 0 else { return 0 }
        let fraction = min(max((x - lane.minX) / lane.width, 0), 1)
        return Ticks((Double(fraction) * Double(clip.duration)).rounded())
    }

    /// The band under `point` and the grip it is in, if any. The LAST band
    /// holding the point wins, because bands paint in time order and that is
    /// the one on top — so a zero-length band sitting on another's start is
    /// the one a press takes. A zero-length band answers too (it is
    /// selectable), always with no edge: 2 pt is all body.
    func bandHit(at point: CGPoint) -> ActionBandHover? {
        guard let clipID, let band = bandRects().last(where: { $0.rect.contains(point) })
        else { return nil }
        return ActionBandHover(
            clip: clipID, action: band.id, edge: ActionBands.gripEdge(in: band.rect, at: point.x))
    }

    /// Mouse-down in the lane. True when a band was hit; it is remembered in
    /// `pressed`, and a session starts — with `liveBegin` — ONLY for an action
    /// with a length: `duration: 0` is invalid input to the core (the
    /// `err_out` channel), not a refusal, so a zero-length band is click to
    /// select and nothing else. Nothing is selected here (CI-11).
    func pressBand(at point: CGPoint) -> Bool {
        guard let hit = bandHit(at: point) else { return false }
        pressed = hit.action
        hover = nil
        guard let clip = clip, let action = clip.actions.first(where: { $0.id == hit.action }),
              action.duration > 0
        else { return true }
        drag = ActionDragSession(
            clip: clip, action: action, mode: hit.edge.map { .resize($0) } ?? .move,
            grabAt: clipTime(atX: point.x), fps: binding.canvas.fps)
        binding.liveBegin()
        return true
    }

    /// Mouse-dragged: one `set_action` per tick; a refused tick is swallowed
    /// by `updateLiveEdit`.
    func dragBand(to point: CGPoint) {
        guard var session = drag else { return }
        session.update(clipTime: clipTime(atX: point.x))
        drag = session
        binding.liveUpdate([session.op])
        needsDisplay = true
    }

    /// Mouse-up: the drag's one undo step, if there was a drag, then the
    /// pressed band selected — a click and a drop alike, which parks the
    /// playhead at the action's (new) end.
    func releaseBand() {
        let session = drag
        let id = pressed
        drag = nil
        pressed = nil
        if let session { binding.liveEnd(session.undoName) }
        if let id { binding.selectAction(id) }
        needsDisplay = true
    }

    // MARK: Hover and cursors

    /// One area of the lane's own (only areas it OWNS are removed —
    /// app/CLAUDE.md "Tracking areas").
    func installLaneTracking() {
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil))
    }

    func hoverMoved(with event: NSEvent) {
        guard drag == nil else {
            hover = nil
            return
        }
        hover = bandHit(at: convert(event.locationInWindow, from: nil))
    }

    func hoverExited() { hover = nil }

    /// `.openHand` over a body, `.resizeLeftRight` over a grip — and nothing
    /// over a zero-length band, which a press will not move.
    func addBandCursorRects() {
        guard let clip = clip else { return }
        let grip = ActionBands.grip
        for band in bandRects() {
            guard let action = clip.actions.first(where: { $0.id == band.id }),
                  action.duration > 0
            else { continue }
            let rect = band.rect
            guard rect.width > grip * 3 else {
                addCursorRect(rect, cursor: .openHand)
                continue
            }
            addCursorRect(rect.insetBy(dx: grip, dy: 0), cursor: .openHand)
            addCursorRect(
                CGRect(x: rect.minX, y: rect.minY, width: grip, height: rect.height),
                cursor: .resizeLeftRight)
            addCursorRect(
                CGRect(x: rect.maxX - grip, y: rect.minY, width: grip, height: rect.height),
                cursor: .resizeLeftRight)
        }
    }

    // MARK: Drawing

    /// While a drag has moved: the original band as a dashed ghost in the
    /// lane, and the HUD where the header row's text was (its buttons stay).
    /// The HUD's times are CLIP-relative, the detail row's Start field's.
    func drawDragOverlay() {
        guard let session = drag, session.didMove, let clip = clip, clip.duration > 0 else {
            return
        }
        let lane = laneRect
        let span = CGFloat(clip.duration)
        let from = lane.minX + lane.width * CGFloat(session.originalStart) / span
        let to = lane.minX + lane.width
            * CGFloat(session.originalStart + session.originalDuration) / span
        ActionDragSession.drawGhost(
            CGRect(x: from, y: lane.minY + 4, width: max(to - from, 2), height: lane.height - 8))
        let text = session.hud(base: 0, frames: binding.canvas.timecodeFrames)
        ActionDragSession.drawHUD(
            text,
            at: CGPoint(
                x: Self.side, y: Self.top + (Self.headerRow - ActionDragSession.hudHeight) / 2))
    }
}
