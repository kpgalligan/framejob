import AppKit

/// `TranscriptView`'s marks: the highlighted word (an accent-tinted rect
/// behind it), the selection, the follow (TX-22: the highlight kept in sight
/// unless a person scrolled within the last 3 s), and the dim words'
/// tooltips — one per contiguous run, on the visible line fragments only.
extension TranscriptView {

    /// Moves the highlight, invalidating only the old and the new word's
    /// rects; with `follow`, scrolls it into sight unless a person scrolled
    /// within `followPause` seconds. A word out of sight is placed before the
    /// scroll (`layOut(through:)`, #558): after a far jump its rect is an
    /// estimate, and six ticks of scrolling onto estimates never showed it.
    /// With the text above laid out already that costs 1.4 ms (measured at
    /// word 18,000 of 27,000), and it is paid only on a tick that scrolls:
    /// at the first and the last lines, where the word sits inside the
    /// margins of a view that cannot scroll further, the tick ends before
    /// the step (`followIsAtAnEnd`, #584).
    func setHighlight(_ index: Int?, follow: Bool) {
        let valid = index.flatMap { tokenStarts.indices.contains($0) ? $0 : nil }
        if valid != highlighted {
            let old = highlighted
            highlighted = valid
            if let old { invalidate(old...old) }
            if let valid { invalidate(valid...valid) }
        }
        guard follow, let valid, !personScrolledRecently else { return }
        guard outOfSight(valid) else { return }
        if followIsAtAnEnd(valid) { return }
        layOut(through: tokenRange(valid))
        guard outOfSight(valid), let rect = rects(forToken: valid).first else { return }
        scroll(to: rect.minY - visibleRect.height / 3)
    }

    /// Whether `index`'s first line is outside the follow's margins, where
    /// the layout now puts it.
    private func outOfSight(_ index: Int) -> Bool {
        guard let rect = rects(forToken: index).first else { return false }
        let shown = visibleRect
        let margin = min(shown.height / 4, 48)
        return rect.minY < shown.minY + margin / 2 || rect.maxY > shown.maxY - margin
    }

    /// Whether the follow's scroll to `index` would be clamped to where the
    /// view already is, at a real end of the text: the top, or the bottom
    /// once the whole text is laid out. Before that the view's bottom is only
    /// the end of what is laid out, and a word below it must still be
    /// followed.
    private func followIsAtAnEnd(_ index: Int) -> Bool {
        guard let rect = rects(forToken: index).first,
            let current = enclosingScrollView?.contentView.bounds.minY
        else { return false }
        let wanted = rect.minY - visibleRect.height / 3
        guard let target = clampedScroll(wanted), abs(target - current) <= 0.5 else { return false }
        // Held short by the view's bottom, which is the text's only when whole.
        return wanted <= target || laidOutWhole
    }

    var personScrolledRecently: Bool {
        guard let last = lastPersonScroll else { return false }
        return now() - last < Self.followPause
    }

    /// Selects `range` of tokens, or clears the selection — a pause's too.
    func select(_ range: ClosedRange<Int>?) {
        let valid = range.flatMap { r -> ClosedRange<Int>? in
            guard r.lowerBound >= 0, r.upperBound < tokenStarts.count else { return nil }
            return r
        }
        if valid == nil { setPauseSelection(nil) }
        selectionAnchor = valid?.lowerBound
        setSelection(valid)
        onSelect?(valid)
    }

    /// Marks the rects of `tokens` dirty.
    func invalidate(_ tokens: ClosedRange<Int>?) {
        guard let tokens, tokens.upperBound < tokenStarts.count else { return }
        for rect in rects(for: tokenRange(tokens)) { setNeedsDisplay(rect.insetBy(dx: -3, dy: -2)) }
    }

    /// Find's matches, then the selection, a selected pause and the
    /// highlight, behind the text.
    func drawMarks(in dirtyRect: NSRect) {
        drawFindMarks(in: dirtyRect)
        drawPauseMark(in: dirtyRect)
        if let selection {
            DS.selectionFill.setFill()
            for rect in rects(for: tokenRange(selection)) where rect.intersects(dirtyRect) {
                rect.fill()
            }
        }
        if let highlighted {
            DS.accent.withAlphaComponent(0.3).setFill()
            for rect in rects(forToken: highlighted) where rect.intersects(dirtyRect) {
                NSBezierPath(rect: rect.insetBy(dx: -2, dy: 0)).fill()
            }
        }
    }

    /// One tooltip per contiguous dim run, over the line fragments in sight.
    func refreshToolTips() {
        removeAllToolTips()
        guard !dimRuns.isEmpty, let first = fragments.first, let last = fragments.last else {
            return
        }
        let from = offset(of: first.rangeInElement.location)
        let to = offset(of: last.rangeInElement.endLocation)
        let shown = visibleRect
        for run in dimRuns where NSMaxRange(run.range) > from && run.range.location < to {
            for rect in rects(for: run.range) {
                let visible = rect.intersection(shown)
                if !visible.isEmpty { addToolTip(visible, owner: run.why as NSString, userData: nil) }
            }
        }
    }
}
