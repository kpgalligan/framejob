import AppKit

/// The nest-scope breadcrumb: the trail drawn in the corner where the track
/// header column and the ruler cross, and the click that walks back out of a
/// nest (road map 2's phase 9; the gestures and the path arithmetic are
/// `EditorViewController+NestScope.swift`'s).
///
/// The split is `TimelineView+Candidates.swift`'s exactly, for the same
/// reason: `TimelineRulerView.draw` opens by filling its whole bounds
/// opaquely and then paints the corner LAST, over the ticks that would
/// otherwise slide under the header column, so anything in that square has to
/// be drawn from inside that method. `TimelineView.swift` keeps one stored
/// property, one closure, one draw call, one hit-test token and one gesture
/// case; every body is here.
///
/// **The corner had to grow a hit case rather than a flag.** The frozen file's
/// `hit(at:)` answered `.corner` for the whole square and `beginGesture` did
/// `case .none, .corner: break` — the click was swallowed twice, deliberately,
/// because an inert square should not start a scrub. A second case keeps that
/// sentence exactly true at the top level and gives the square a meaning only
/// while there is somewhere to go.
///
/// ## What fits in 131 × 21 points
///
/// The corner is `DS.trackHeaderWidth` (132) by `DS.rulerHeight` (22), less a
/// one-point border down its right edge and one along the ruler's bottom. One
/// short level fits comfortably; two do not, and three never will. So the
/// trail draws its **last two components** — the container you would return
/// to and the one you are in — middle-truncated, with the whole path as the
/// tooltip. Middle truncation rather than tail, because two nests called
/// "Lower Third 1" and "Lower Third 2" differ at the END and a tail ellipsis
/// would render them identical.
///
/// **The whole cell is one target and it means "out one level"** — the same
/// command as ⌘↑ and as Clip ▸ Close Nest. Splitting 131 points into two
/// click regions so the left component could jump out several levels at once
/// was considered and refused: the regions would be under 60 points wide,
/// their boundary would move with the text, and the same journey is two
/// presses of a key that is already bound. The hit case carries the level all
/// the same (`level: Int`, counted as `ProjectDocument.nestPath` counts, 0
/// being the timeline), so a later design can widen the meaning without
/// touching the frozen file again.
///
/// ## The corner is the RULER's, so the ruler floats above the headers
///
/// The two floating bands are pinned to different edges — the ruler to the
/// top of the visible rectangle, the header column to its left — and they
/// overlap in exactly one square, this corner, and only once the pane has
/// been scrolled VERTICALLY: at rest the header column begins at the ruler's
/// own height and the two never meet. The frozen file's `init` therefore adds
/// the headers FIRST and the ruler second, and that order is load-bearing.
/// The other way round, `TimelineHeaderView.draw`'s opening `bounds.fill()`
/// painted the corner out the moment the pane scrolled by a point: the
/// breadcrumb was invisible exactly where the way out of a nest is supposed
/// to be, while `cornerHit` went on answering `.breadcrumb` there — a live
/// click target under what drew as a track header.
///
/// Measured rather than reasoned, because it is a z-order change in a file
/// that had been drawing correctly for eight phases. Offscreen, a bare
/// `TimelineView` is rendered with a two-level trail set, at rest and
/// scrolled (`tools/proof/phase9_chrome.py`, over ten text tracks — 490 pt
/// of content against a 324 pt viewport, so its 62 pt scroll is one the app
/// can reach): with the headers on top the scrolled corner came out
/// BYTE-IDENTICAL to the same corner with no trail at all, and with the ruler
/// on top it comes out byte-identical to the corner AT REST — which is also
/// what says the swap moves nothing else, since at rest the two bands do not
/// meet and every render the offscreen harness makes is at rest. The
/// six-track probe this was first measured with OVER-SCROLLED — its 306 pt
/// of content was shorter than the pane, and `NSClipView.scroll(to:)` does
/// not clamp — while its z-order pictures held; the tracked script's
/// `init-order` mutant is what gates the claim now.
///
/// **What the swap does move is an open rename field**, which is a real
/// subview of the band it edits, and a track's field sits at its ROW's top —
/// so on the top, partly scrolled row it lands in this square. `beginRename`
/// answers that by raising whichever band holds the field to the front for
/// as long as it is open, and `endRename` puts the ruler back. It is
/// deliberately unconditional: "raise it only when the field would actually
/// be covered" is a geometric test taken once, at open time, that the next
/// scroll makes false, while "the band being typed into is the front-most
/// band" has no geometry in it and cannot rot. What that costs is the
/// breadcrumb while a track name is being typed — which is the corner this
/// app drew for eight phases — and the offscreen render of a field open on
/// that row is byte-identical before and after the swap, which is the point.
///
/// ## One gesture, one level
///
/// The frozen file's `.breadcrumb` case acts on the FIRST press only
/// (`clicks < 2`), and that guard is load-bearing rather than tidy. AppKit
/// delivers a double-click as two mouse-downs — clickCount 1, then 2 — and
/// this cell is not a scrub or a selection a second press can merely repeat:
/// it is a BUTTON that has already acted. By the time the second down
/// arrives the trail is one component shorter, `cornerHit` reads the NEW
/// trail and answers a new level, so the pair walked out TWO nests for one
/// gesture — inconsistently at that, since from one level down the second
/// press landed on a corner that had gone inert and did nothing at all. A
/// deliberate journey of several levels is several separate clicks, or two
/// presses of ⌘↑, which is the key this cell duplicates.
extension TimelineView {
    /// What a click in the corner means: nothing at the top level, and one
    /// level out while a nest is open.
    ///
    /// Read by `TimelineContentView.hit(at:)`, which is the one line of this
    /// the frozen file carries.
    var cornerHit: TimelineHit {
        guard breadcrumb.count > 1 else { return .corner }
        return .breadcrumb(level: breadcrumb.count - 2)
    }

    /// Registers (or clears) the tooltip that carries the FULL path, since
    /// the drawn trail is two components and middle-truncated at that.
    ///
    /// It is a rect tooltip on the CONTENT view rather than a `toolTip` on
    /// the ruler, and both halves of that matter. The ruler refuses hits
    /// (`hitTest` answers nil unless a real subview is under the point) so
    /// that `TimelineContentView` can own every mouse event in the pane; and
    /// a whole-view `toolTip` would pop up over the ruler's entire width,
    /// where what has a tooltip is one 132-point square. The rect is in
    /// content coordinates and so moves with the scroll, which is why
    /// `pinFloatingBands` calls this as well as the `didSet` above.
    ///
    /// `removeAllToolTips()` is safe here for the reason app/CLAUDE.md's
    /// tracking-area rule makes it unsafe elsewhere: the blanket form is
    /// wrong when it takes `NSToolTipManager`'s areas out from under a view
    /// that has OTHER tooltips, and the timeline's content view has none —
    /// this is its only one, added and removed together.
    func syncBreadcrumbTooltip() {
        content.removeAllToolTips()
        guard breadcrumb.count > 1 else { return }
        let corner = NSRect(
            x: pinnedX, y: pinnedY, width: TimelineLayout.headerWidth,
            height: TimelineLayout.rulerHeight)
        _ = content.addToolTip(
            corner, owner: breadcrumb.joined(separator: " › ") as NSString, userData: nil)
    }
}

// MARK: - The corner

extension TimelineRulerView {
    /// Called from `draw(_:)` after the corner's own opaque fill and its two
    /// border strokes, and before the playhead's head — so the trail sits ON
    /// the corner and the playhead still crosses everything.
    ///
    /// Draws nothing at the top level, which is what leaves the shipped
    /// corner byte for byte what it was for every project that never enters a
    /// nest.
    func drawBreadcrumb(owner: TimelineView, in corner: NSRect) {
        let trail = owner.breadcrumb
        guard trail.count > 1 else { return }

        // The last two components. `count > 1` is guaranteed above, so this
        // is always exactly two.
        let parent = trail[trail.count - 2]
        let here = trail[trail.count - 1]

        // A back chevron at the left edge says the cell is a way OUT before a
        // word of it is read, which is the whole job of the first glance.
        let chevronX = corner.minX + 5
        let midY = corner.midY - 1
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: chevronX + 3.5, y: midY - 3.5))
        chevron.line(to: NSPoint(x: chevronX, y: midY))
        chevron.line(to: NSPoint(x: chevronX + 3.5, y: midY + 3.5))
        chevron.lineWidth = 1.5
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        DS.textMuted.setStroke()
        chevron.stroke()

        // Inside the corner's right-hand border, past the chevron.
        let box = NSRect(
            x: chevronX + 8, y: 3, width: max(corner.maxX - 3 - (chevronX + 8), 0),
            height: corner.height - 5)
        guard box.width > 8 else { return }

        // The parent muted and the current level strong: the pair reads as
        // "where you came from › where you are" without a legend. Middle
        // truncation, not tail, because two nests called "Lower Third 1" and
        // "Lower Third 2" differ at the END.
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        let muted: [NSAttributedString.Key: Any] = [
            .font: DS.sans(10), .foregroundColor: DS.textMuted, .paragraphStyle: style,
        ]
        let strong: [NSAttributedString.Key: Any] = [
            .font: DS.sans(10, weight: .semibold), .foregroundColor: DS.textStrong,
            .paragraphStyle: style,
        ]
        let line = NSMutableAttributedString(string: parent, attributes: muted)
        line.append(NSAttributedString(string: " › ", attributes: muted))
        line.append(NSAttributedString(string: here, attributes: strong))
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: box).addClip()
        line.draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
