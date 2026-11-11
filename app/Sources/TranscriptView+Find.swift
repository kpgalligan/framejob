import AppKit

/// `TranscriptView`'s Find marks (spec §11 TX-37 (d)): every match marked
/// behind its text, the current one more strongly and outlined, and the
/// scroll that brings the current match into sight. Find moves nothing else:
/// not the selection, the range or the playhead.
///
/// Matches are kept token-relative and turned into text ranges at draw time,
/// so a restyle (an appearance change) keeps them. **Only the matches whose
/// tokens meet the dirty rect are measured**: `rects(for:)` lays out the text
/// it is asked about, and a find with a match in every word would otherwise
/// lay the whole transcript out on each draw (TX-21's viewport layout).
extension TranscriptView {

    /// Sets the matches (in text order) and the current one, and redraws.
    func setFind(_ matches: [TranscriptFind.Match], current: Int?) {
        if matches.isEmpty, findMatches.isEmpty { return }
        findMatches = matches
        findCurrent = current.flatMap { matches.indices.contains($0) ? $0 : nil }
        needsDisplay = true
    }

    /// A match's runs in the view's string: its pieces, neighbours one space
    /// apart joined, so a phrase is one mark and a pause label between two of
    /// its words is not marked.
    func findRuns(_ match: TranscriptFind.Match) -> [NSRange] {
        var out: [NSRange] = []
        for piece in match.pieces where tokenStarts.indices.contains(piece.token) {
            let range = NSRange(
                location: tokenStarts[piece.token] + piece.range.location,
                length: min(piece.range.length, tokenLengths[piece.token] - piece.range.location))
            guard range.length > 0 else { continue }
            if let last = out.last, NSMaxRange(last) + 1 == range.location {
                out[out.count - 1] = NSUnionRange(last, range)
            } else {
                out.append(range)
            }
        }
        return out
    }

    /// The tokens whose text meets `dirtyRect`, from the fragments there (the
    /// ones `draw` lays out anyway); nil when none does.
    private func tokens(in dirtyRect: NSRect) -> ClosedRange<Int>? {
        let top = CGPoint(x: 0, y: max(dirtyRect.minY - Self.inset.height, 0))
        guard let start = layoutManager.textLayoutFragment(for: top)?.rangeInElement.location
            ?? fragments.first?.rangeInElement.location
        else { return nil }
        let from = offset(of: start)
        var to = from
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) {
            fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(
                dx: Self.inset.width, dy: Self.inset.height)
            guard frame.minY <= dirtyRect.maxY else { return false }
            to = self.offset(of: fragment.rangeInElement.endLocation)
            return true
        }
        // The first token ending after `from`, the last starting before `to`.
        var low = 0
        var high = tokenStarts.count
        while low < high {
            let mid = (low + high) / 2
            if tokenStarts[mid] + tokenLengths[mid] > from { high = mid } else { low = mid + 1 }
        }
        guard let last = token(atOrBefore: max(to - 1, 0)), low <= last else { return nil }
        return low...last
    }

    /// The matches' marks inside `dirtyRect`, under every other mark.
    func drawFindMarks(in dirtyRect: NSRect) {
        guard !findMatches.isEmpty, let shown = tokens(in: dirtyRect) else { return }
        // The first match ending at or after the first token shown.
        var low = 0
        var high = findMatches.count
        while low < high {
            let mid = (low + high) / 2
            if findMatches[mid].tokens.upperBound < shown.lowerBound { low = mid + 1 } else { high = mid }
        }
        let ink = NSColor.findHighlightColor
        var index = low
        while index < findMatches.count, findMatches[index].tokens.lowerBound <= shown.upperBound {
            let current = index == findCurrent
            for run in findRuns(findMatches[index]) {
                for rect in rects(for: run) where rect.intersects(dirtyRect) {
                    let box = rect.insetBy(dx: -1, dy: 0)
                    ink.withAlphaComponent(current ? 0.65 : 0.3).setFill()
                    box.fill()
                    if current {
                        ink.setStroke()
                        let outline = NSBezierPath(rect: box.insetBy(dx: -0.5, dy: 0.5))
                        outline.lineWidth = 1.5
                        outline.stroke()
                    }
                }
            }
            index += 1
        }
    }

    /// The current match's first rect, laid out where needed.
    var findCurrentRect: CGRect? {
        guard let current = findCurrent, findMatches.indices.contains(current),
            let run = findRuns(findMatches[current]).first
        else { return nil }
        return rects(for: run).first
    }

    /// Whether the current match's first line is in sight.
    var findCurrentVisible: Bool {
        guard let rect = findCurrentRect else { return false }
        let shown = visibleRect
        return rect.minY >= shown.minY && rect.maxY <= shown.maxY
    }

    /// Scrolls the current match into sight by `setHighlight`'s rule (a third
    /// from the top when it is outside the margins). The text from the top
    /// through the match is laid out first: a far word's rect, and the view's
    /// own height, are estimates until the text above is laid out (measured on
    /// 900 paragraphs: the last word estimated at 88,601 pt, laid out at
    /// 130,078 pt, in a view 979 pt tall), so one scroll onto an estimate
    /// lands short. Laying out 27,000 words whole took 0.06 s. The match's own
    /// paragraph is invalidated first: one measured earlier keeps the place
    /// its estimate gave it until it is laid out again.
    func revealFind() {
        guard let current = findCurrent, findMatches.indices.contains(current),
            let run = findRuns(findMatches[current]).first
        else { return }
        if let end = location(NSMaxRange(run)),
            let above = NSTextRange(location: contentStorage.documentRange.location, end: end)
        {
            if let own = textRange(run) { layoutManager.invalidateLayout(for: own) }
            layoutManager.ensureLayout(for: above)
            layoutViewport()  // the view grows to the height laid out
        }
        guard let rect = rects(for: run).first else { return }
        let shown = visibleRect
        let margin = min(shown.height / 4, 48)
        if rect.minY < shown.minY + margin / 2 || rect.maxY > shown.maxY - margin {
            scroll(to: rect.minY - shown.height / 3)
        }
    }
}
