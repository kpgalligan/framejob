import AppKit

/// A matte track on the timeline (spec §11 MT-7): the header's accent-tinted
/// tag by the name, the lane's clips at half opacity with dashed outlines, and an
/// accent bracket joining the lane to the track it cuts.
///
/// What a matte cuts is the core's (`recipe_matte.rs`); the chrome asks
/// `TrackMatte.target(of:in:)` — the same rule over the SHOWN container's
/// tracks (the timeline, or the open nest's) — only to say so. Nothing here
/// edits: the mode is set by Track ▸ Matte (`EditorViewController+Matte.swift`)
/// and the context menu's Matte submenu (`TimelineView+TrackMenu.swift`).
enum TimelineMatteTag {
    /// The tag's words, and whether it is dimmed: nil for an ordinary track,
    /// "Matte · <mode>" for a matte track with a target, and a dimmed
    /// "Matte · nothing behind" for one with none — a back-most matte track,
    /// or one in front of another matte track (MT-2).
    static func text(
        for track: TrackSnapshot, in tracks: [TrackSnapshot]
    ) -> (text: String, dimmed: Bool)? {
        guard track.matte != .none else { return nil }
        guard TrackMatte.target(of: track.id, in: tracks) != nil else {
            return ("Matte · nothing behind", true)
        }
        return ("Matte · \(track.matte.displayName)", false)
    }

    static let font = DS.sans(9, weight: .semibold)
    /// The tag's box: its text plus `padding` a side, `height` tall.
    static let padding: CGFloat = 3
    static let height: CGFloat = 11
    /// The name label's box ends 15 pt down the row (`TimelineHeaderView.draw`:
    /// y + 2, 13 tall); the tag's own line starts there.
    static let ownLineTop: CGFloat = 15
    /// The room between the tag on the name's line and the name it clips.
    static let gap: CGFloat = 4
    /// A matte lane's clips (MT-7): half opacity, the whole body passes as
    /// one transparency layer so overlapping strokes do not double up.
    static let laneOpacity: CGFloat = 0.5

    static func width(of text: String) -> CGFloat {
        ceil(text.size(withAttributes: [.font: font]).width) + 2 * padding
    }

    /// The least the name keeps beside a tag on its line (MT-7).
    static let minimumNameWidth: CGFloat = 40
    /// The tag's words on the name's line of a row `rowWidth` wide: "Matte"
    /// alone when the full words would leave the name less than
    /// `minimumNameWidth` (MT-7).
    static func fitted(_ text: String, rowWidth: CGFloat) -> String {
        rowWidth - 14 - width(of: text) - gap < minimumNameWidth ? "Matte" : text
    }

    /// The tag's text colour: the primary label colour, or for a dimmed tag
    /// the muted one — never the accent, so its legibility does not depend
    /// on the accent the owner picked (MT-7).
    static func textColor(dimmed: Bool) -> NSColor { dimmed ? DS.textMuted : DS.textStrong }
    /// The tag's box: the selection fill (the accent tint), fainter when dimmed.
    static func fillColor(dimmed: Bool) -> NSColor {
        DS.selectionFill.withAlphaComponent(0.22 * (dimmed ? 0.45 : 1))
    }
}

extension TimelineHeaderView {
    /// Whether a row of `rowHeight` leaves room for the tag on a line of its
    /// own between the name and the toggles — Medium and Large, and the
    /// Small video lane; else the tag shares the name's line.
    static func matteTagOnOwnLine(rowHeight: CGFloat) -> Bool {
        buttonRect(0, height: rowHeight).minY - TimelineMatteTag.ownLineTop
            >= TimelineMatteTag.height - 1
    }

    /// How much of the name's line the tag takes: 0 for an ordinary track
    /// and for a tag on its own line, else its width and the gap before it.
    func matteTagWidth(_ track: TrackSnapshot, rowHeight: CGFloat) -> CGFloat {
        guard let tag = TimelineMatteTag.text(for: track, in: timeline?.snapshot.tracks ?? []),
              !Self.matteTagOnOwnLine(rowHeight: rowHeight)
        else { return 0 }
        let text = TimelineMatteTag.fitted(tag.text, rowWidth: TimelineLayout.headerWidth)
        return TimelineMatteTag.width(of: text) + TimelineMatteTag.gap
    }

    /// The tag for `track` in its header row `row` (header-local, the row's
    /// full rect): under the name when the row has room, else right-aligned
    /// on the name's line — "Matte" alone when the full words would crowd
    /// the name (`fitted`) — where `matteTagWidth` has already clipped the
    /// name before it. Answers the words and the box it drew.
    @discardableResult
    func drawMatteTag(
        _ track: TrackSnapshot, row: CGRect, tracks: [TrackSnapshot]
    ) -> (text: String, box: CGRect)? {
        guard let tag = TimelineMatteTag.text(for: track, in: tracks) else { return nil }
        let ownLine = Self.matteTagOnOwnLine(rowHeight: row.height)
        let text = ownLine ? tag.text : TimelineMatteTag.fitted(tag.text, rowWidth: row.width)
        let width = min(TimelineMatteTag.width(of: text), max(row.width - 14, 0))
        let box: CGRect
        if ownLine {
            box = CGRect(
                x: row.minX + 8, y: row.minY + TimelineMatteTag.ownLineTop,
                width: width, height: TimelineMatteTag.height)
        } else {
            box = CGRect(
                x: row.maxX - 6 - width, y: row.minY + 3,
                width: width, height: TimelineMatteTag.height)
        }
        TimelineMatteTag.fillColor(dimmed: tag.dimmed).setFill()
        box.fill()
        TimelineDraw.label(
            text,
            in: box.insetBy(dx: TimelineMatteTag.padding, dy: 0).offsetBy(dx: 0, dy: -0.5),
            font: TimelineMatteTag.font, color: TimelineMatteTag.textColor(dimmed: tag.dimmed))
        return (text, box)
    }
}

extension TimelineContentView {
    /// One track's body passes (`drawClips`), with a matte track's chrome:
    /// `body` runs inside a transparency layer at half opacity, then each of
    /// `rects` (the shown clips' lane rects) gets a dashed accent outline,
    /// and, when the track has a target, the bracket to it. An ordinary track
    /// runs `body` as it is, then draws the bracket again over its own clips
    /// when the track in front of it is a matte that cuts it, so a redraw of
    /// either lane alone repaints the bracket where it crosses that lane.
    func drawMatteLane(
        track: TrackSnapshot, rects: [CGRect], lane: CGRect, owner: TimelineView,
        body: () -> Void
    ) {
        let tracks = owner.snapshot.tracks
        guard track.matte != .none, let context = NSGraphicsContext.current?.cgContext else {
            body()
            if let index = tracks.firstIndex(where: { $0.id == track.id }),
               tracks.indices.contains(index + 1),
               TrackMatte.target(of: tracks[index + 1].id, in: tracks) == track.id {
                drawMatteBracket(from: tracks[index + 1].id, to: track.id, owner: owner)
            }
            return
        }
        context.saveGState()
        context.setAlpha(TimelineMatteTag.laneOpacity)
        // The layer spans the lane alone: every pass draws inside it.
        context.beginTransparencyLayer(in: lane, auxiliaryInfo: nil)
        body()
        context.endTransparencyLayer()
        context.restoreGState()

        DS.accent.setStroke()
        for rect in rects {
            let outline = NSBezierPath(
                roundedRect: Self.bodyRect(rect).insetBy(dx: 0.5, dy: 0.5),
                xRadius: TimelineLayout.clipRadius, yRadius: TimelineLayout.clipRadius)
            outline.lineWidth = 1
            outline.setLineDash([4, 3], count: 2, phase: 0)
            outline.stroke()
        }
        if let target = TrackMatte.target(of: track.id, in: tracks) {
            drawMatteBracket(from: track.id, to: target, owner: owner)
        }
    }

    /// The accent bracket from a matte track's lane to its target's, just
    /// right of the floating header column (`pinnedX + headerWidth + 2`):
    /// a 2 pt line between the two lanes' middles with a tick into each.
    /// `TimelineView.invalidateMatteBrackets` repaints it when a scroll moves
    /// the column, since the content layer scrolls without a redraw.
    private func drawMatteBracket(from matte: UInt32, to target: UInt32, owner: TimelineView) {
        let tracks = owner.snapshot.tracks
        let layout = owner.layout
        guard let top = tracks.firstIndex(where: { $0.id == matte }),
              let bottom = tracks.firstIndex(where: { $0.id == target })
        else { return }
        let upper = layout.rowRect(layout.row(forTrackIndex: top), width: layout.contentWidth)
        let lower = layout.rowRect(layout.row(forTrackIndex: bottom), width: layout.contentWidth)
        let x = owner.pinnedX + TimelineLayout.headerWidth + 2
        DS.accent.setFill()
        NSRect(x: x, y: upper.midY, width: 2, height: max(lower.midY - upper.midY, 0)).fill()
        NSRect(x: x, y: upper.midY - 1, width: 6, height: 2).fill()
        NSRect(x: x, y: lower.midY - 1, width: 6, height: 2).fill()
    }
}

extension TimelineView {
    /// Marks the bracket's strip dirty at the column's old and new place.
    /// `pinFloatingBands` calls it before it moves `pinnedX`: a scroll moves
    /// the content's LAYER and redraws only what it exposes, which would
    /// leave a bracket painted at the old place and none at the new.
    func invalidateMatteBrackets(movingTo x: CGFloat) {
        guard x != pinnedX, snapshot.tracks.contains(where: { $0.matte != .none }) else { return }
        for left in [pinnedX, x] {
            content.setNeedsDisplay(
                NSRect(
                    x: left + TimelineLayout.headerWidth, y: 0, width: 10,
                    height: content.bounds.height))
        }
    }
}
