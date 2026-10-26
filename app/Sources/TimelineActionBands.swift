import AppKit

/// The timeline's half of the selected action (spec §11 CI-1, CI-4): each
/// clip's ACTION LANE directly under its name strip, the band hit, the
/// selected span's wash down the clip body, and its shade on the ruler.
///
/// Extensions rather than lines in `TimelineView.swift`, which is frozen at
/// wiring (app/CLAUDE.md): the frozen file keeps one call in `hit(at:)`, one
/// in the ruler's `draw`, and `TimelineClipDrawing.swift` the two calls in a
/// clip's paint order — the wash before the name strip, the bands after it.
extension TimelineContentView {
    /// The lane: the top of the clip's content rect (under the name strip),
    /// full clip width, `DS.actionLaneHeights` tall at S/M/L — never taller
    /// than the content it sits in.
    static func actionLane(content: CGRect, sizeIndex: Int) -> CGRect {
        let heights = DS.actionLaneHeights
        let height = heights[min(max(sizeIndex, 0), heights.count - 1)]
        return CGRect(
            x: content.minX, y: content.minY, width: content.width,
            height: min(height, content.height))
    }

    /// One action's band in the lane: its span, by CLIP time mapped back
    /// through the clip's own start, at least 2 pt wide.
    static func bandRect(
        _ a: ActionSnapshot, clip: ClipSnapshot, lane: CGRect, layout: TimelineLayout
    ) -> CGRect {
        let from = layout.x(for: clip.start + a.start)
        let to = layout.x(for: clip.start + a.endTime)
        return CGRect(x: from, y: lane.minY, width: max(to - from, 2), height: lane.height)
    }

    /// The action whose band holds `point` — the LANE only, so a press on the
    /// clip body below it is still the clip. `hit(at:)` asks after the fade
    /// handles, which on an audio-only clip sit inside this lane and are
    /// painted over it, and before the edge grabs. Where bands overlap (the
    /// 2 pt minimum width, or a hand-written project) the LAST holding the
    /// point in `ActionBands.ordered` order wins, because bands paint in that
    /// order and it is the one on top — the Clip tab lane's `bandHit` rule. A
    /// zero-length band is never painted here, so unlike the lane it is never
    /// hit.
    func actionBandHit(_ clip: ClipSnapshot, rect: CGRect, at point: CGPoint) -> UInt32? {
        guard let owner = timeline else { return nil }
        let lane = Self.actionLane(
            content: Self.contentRect(rect), sizeIndex: owner.trackHeightIndex)
        guard lane.height > 0, lane.contains(point) else { return nil }
        return ActionBands.ordered(clip).last { action in
            action.duration > 0
                && Self.bandRect(action, clip: clip, lane: lane, layout: owner.layout)
                    .contains(point)
        }?.id
    }

    /// What a press at `point` grabs on the clip's action lane: a band's grip
    /// (`.actionEdge`) or its body (`.action`), or nil off every band. The
    /// band is `actionBandHit`'s, unchanged; the grip is asked of that band's
    /// own rect (spec §11 CI-11).
    func actionHit(_ clip: ClipSnapshot, rect: CGRect, at point: CGPoint) -> TimelineHit? {
        guard let owner = timeline, let id = actionBandHit(clip, rect: rect, at: point),
              let action = clip.actions.first(where: { $0.id == id })
        else { return nil }
        let lane = Self.actionLane(
            content: Self.contentRect(rect), sizeIndex: owner.trackHeightIndex)
        let band = Self.bandRect(action, clip: clip, lane: lane, layout: owner.layout)
        if let edge = ActionBands.gripEdge(in: band, at: point.x) {
            return .actionEdge(clip: clip.id, action: id, edge)
        }
        return .action(clip: clip.id, action: id)
    }

    /// The selected span down the whole clip body: the action ink at 12 %
    /// with 1 pt ends at 55 %. Drawn before the name strip, so the strip
    /// still reads over it.
    func drawActionWash(_ clip: ClipSnapshot, body: CGRect, owner: TimelineView) {
        guard let id = owner.selectedAction,
              let action = clip.actions.first(where: { $0.id == id })
        else { return }
        let layout = owner.layout
        let from = layout.x(for: clip.start + action.start)
        let to = layout.x(for: clip.start + action.endTime)
        let span = CGRect(x: from, y: body.minY, width: max(to - from, 2), height: body.height)
        DS.action.withAlphaComponent(0.12).setFill()
        span.fill()
        DS.action.withAlphaComponent(0.55).setFill()
        NSRect(x: span.minX, y: span.minY, width: 1, height: span.height).fill()
        NSRect(x: span.maxX - 1, y: span.minY, width: 1, height: span.height).fill()
    }

    /// The lane's black-22 % backing and every band on it, numbered in time
    /// order, then — from M, on a clip whose rate moves — the rate line over
    /// them, inset 2 pt top and bottom (spec §11 SR-26). The backing is drawn
    /// only on a clip that has an action with a length (road map 9 §2's
    /// deviation: the handoff draws it on every clip).
    func drawActionBands(_ clip: ClipSnapshot, rect: CGRect, owner: TimelineView) {
        guard clip.actions.contains(where: { $0.duration > 0 }) else { return }
        let lane = Self.actionLane(
            content: Self.contentRect(rect), sizeIndex: owner.trackHeightIndex)
        guard lane.height > 0 else { return }
        NSColor.black.withAlphaComponent(0.22).setFill()
        lane.fill()
        let level = ActionBands.Level(sizeIndex: owner.trackHeightIndex)
        let graph = level == .bars ? nil : RateGraph.points(
            owner.sourceMaps(clip.id), in: lane.insetBy(dx: 0, dy: 2),
            x: { owner.layout.x(for: clip.start + $0) })
        for (index, action) in ActionBands.ordered(clip).enumerated() where action.duration > 0 {
            ActionBands.draw(
                band: Self.bandRect(action, clip: clip, lane: lane, layout: owner.layout),
                number: index + 1,
                label: ActionBands.keys(of: action.end).joined(separator: ", "),
                curve: RateGraph.bandCurve(action, graphed: graph != nil),
                zoom: ActionBands.isZoom(action),
                selected: owner.selectedAction == action.id,
                hovered: owner.bandHover?.clip == clip.id && owner.bandHover?.action == action.id,
                level: level)
        }
        if let graph { RateGraph.draw(graph, in: lane) }
    }
}

extension TimelineRulerView {
    /// The selected span on the ruler: the action ink at 20 % over the
    /// ruler's height and a 2 pt rule of it along the bottom, above the
    /// ruler's own 1 pt border line.
    func drawSelectedActionSpan(owner: TimelineView, layout: TimelineLayout) {
        guard let id = owner.selectedAction else { return }
        for clip in owner.snapshot.clips where owner.selection.contains(clip.id) {
            guard let action = clip.actions.first(where: { $0.id == id }) else { continue }
            let from = layout.x(for: clip.start + action.start)
            let to = layout.x(for: clip.start + action.endTime)
            let width = max(to - from, 2)
            DS.action.withAlphaComponent(0.2).setFill()
            NSRect(x: from, y: 0, width: width, height: bounds.height).fill()
            DS.action.setFill()
            NSRect(x: from, y: bounds.height - 3, width: width, height: 2).fill()
            return
        }
    }
}
