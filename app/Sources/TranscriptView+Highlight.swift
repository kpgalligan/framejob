import AppKit

/// `TranscriptView`'s marks: the highlighted word (an accent-tinted rect
/// behind it), the selection, the follow (TX-22: the highlight kept in sight
/// unless a person scrolled within the last 3 s), and the dim words'
/// tooltips — one per contiguous run, on the visible line fragments only.
extension TranscriptView {

    /// Moves the highlight, invalidating only the old and the new word's
    /// rects; with `follow`, scrolls it into sight unless a person scrolled
    /// within `followPause` seconds.
    func setHighlight(_ index: Int?, follow: Bool) {
        let valid = index.flatMap { tokenStarts.indices.contains($0) ? $0 : nil }
        if valid != highlighted {
            let old = highlighted
            highlighted = valid
            if let old { invalidate(old...old) }
            if let valid { invalidate(valid...valid) }
        }
        guard follow, let valid, !personScrolledRecently else { return }
        guard let rect = rects(forToken: valid).first else { return }
        let shown = visibleRect
        let margin = min(shown.height / 4, 48)
        if rect.minY < shown.minY + margin / 2 || rect.maxY > shown.maxY - margin {
            scroll(to: rect.minY - shown.height / 3)
        }
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
