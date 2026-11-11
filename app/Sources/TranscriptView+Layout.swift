import AppKit

/// `TranscriptView`'s geometry: a UTF-16 range's rects, the token or the
/// paragraph timecode under a point, the top visible token, the layout a far
/// scroll needs first, and the scroll that brings a token to the top. Every
/// rect is in the view's (flipped) coordinates: the text container's offset
/// by `TranscriptView.inset`.
extension TranscriptView {

    /// The text location `offset` UTF-16 units into the document.
    func location(_ offset: Int) -> NSTextLocation? {
        contentStorage.location(contentStorage.documentRange.location, offsetBy: offset)
    }

    func offset(of location: NSTextLocation) -> Int {
        contentStorage.offset(from: contentStorage.documentRange.location, to: location)
    }

    func textRange(_ range: NSRange) -> NSTextRange? {
        guard let start = location(range.location), let end = location(NSMaxRange(range)) else {
            return nil
        }
        return NSTextRange(location: start, end: end)
    }

    /// The line-height rects `range` covers, laid out first where needed.
    func rects(for range: NSRange) -> [CGRect] {
        guard range.location >= 0, let text = textRange(range) else { return [] }
        layoutManager.ensureLayout(for: text)
        var out: [CGRect] = []
        layoutManager.enumerateTextSegments(in: text, type: .highlight, options: []) {
            _, frame, _, _ in
            out.append(frame.offsetBy(dx: Self.inset.width, dy: Self.inset.height))
            return true
        }
        return out
    }

    func tokenRange(_ index: Int) -> NSRange {
        guard tokenStarts.indices.contains(index) else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: tokenStarts[index], length: tokenLengths[index])
    }

    /// From the first token's start to the last one's end.
    func tokenRange(_ tokens: ClosedRange<Int>) -> NSRange {
        let low = tokenRange(tokens.lowerBound)
        let high = tokenRange(tokens.upperBound)
        guard low.location != NSNotFound, high.location != NSNotFound else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: low.location, length: NSMaxRange(high) - low.location)
    }

    func rects(forToken index: Int) -> [CGRect] {
        let range = tokenRange(index)
        return range.location == NSNotFound ? [] : rects(for: range)
    }

    /// The UTF-16 offset nearest `point`, or nil off the text.
    func characterOffset(at point: NSPoint) -> Int? {
        let inner = CGPoint(x: point.x - Self.inset.width, y: point.y - Self.inset.height)
        guard let fragment = layoutManager.textLayoutFragment(for: inner) else { return nil }
        let frame = fragment.layoutFragmentFrame
        let start = offset(of: fragment.rangeInElement.location)
        let lines = fragment.textLineFragments
        guard !lines.isEmpty else { return start }
        let local = CGPoint(x: inner.x - frame.minX, y: inner.y - frame.minY)
        let line = lines.first { $0.typographicBounds.maxY > local.y } ?? lines[lines.count - 1]
        let inLine = CGPoint(x: local.x - line.typographicBounds.minX, y: local.y - line.typographicBounds.minY)
        let range = line.characterRange
        let index = line.characterIndex(for: inLine)
        // Off the line's glyphs (a drag past its end, or before its start) the line answers
        // NSNotFound; the nearest offset is then its last or first character.
        guard index != NSNotFound, index >= 0 else {
            return start + (inLine.x <= 0 || range.length == 0 ? range.location : NSMaxRange(range) - 1)
        }
        return start + max(index, range.location)
    }

    /// The last token starting at or before `offset`, by binary search.
    func token(atOrBefore offset: Int) -> Int? {
        var low = 0
        var high = tokenStarts.count
        while low < high {
            let mid = (low + high) / 2
            if tokenStarts[mid] <= offset { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    /// The token under `point`: the one whose characters (or the space after
    /// them) hold the offset there; nil on a timecode or off the text.
    func tokenIndex(at point: NSPoint) -> Int? {
        guard let offset = characterOffset(at: point), paragraphIndex(atOffset: offset) == nil,
            let index = token(atOrBefore: offset)
        else { return nil }
        let paragraph = model.tokens[index].paragraph
        let end = model.paragraphs[paragraph].endToken
        let limit = index + 1 < end ? tokenStarts[index + 1] : NSMaxRange(tokenRange(index))
        return offset <= limit ? index : nil
    }

    /// The paragraph whose timecode is under `point`.
    func paragraphIndex(at point: NSPoint) -> Int? {
        characterOffset(at: point).flatMap { paragraphIndex(atOffset: $0) }
    }

    private func paragraphIndex(atOffset offset: Int) -> Int? {
        var low = 0
        var high = timecodeRanges.count
        while low < high {
            let mid = (low + high) / 2
            if timecodeRanges[mid].location <= offset { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return nil }
        let range = timecodeRanges[low - 1]
        return offset <= NSMaxRange(range) ? low - 1 : nil
    }

    /// The first token whose line shows at the visible top, else the first
    /// token below it.
    func topVisibleToken() -> Int? {
        guard !tokenStarts.isEmpty else { return nil }
        let top = visibleRect.minY
        let probe = NSPoint(x: Self.inset.width + 1, y: max(top, Self.inset.height) + 1)
        guard let offset = characterOffset(at: probe) else { return nil }
        let index = token(atOrBefore: offset) ?? 0
        if let rect = rects(forToken: index).first, rect.maxY <= top, index + 1 < tokenStarts.count {
            return index + 1
        }
        if paragraphIndex(atOffset: offset) != nil, index + 1 < tokenStarts.count,
            tokenStarts[index] < offset
        {
            return index + 1
        }
        return index
    }

    /// Lays the text out from the top through `range` and for a viewport's
    /// height below it, and sizes the view to it. A scroll to a far word
    /// needs it first: the word's rect is an estimate until the text above is
    /// laid out, and the view is only as tall as what is laid out from the
    /// top (measured on 900 paragraphs: the last word estimated at 88,601 pt,
    /// laid out at 130,078 pt, in a view 979 pt tall), so a scroll onto an
    /// estimate lands short and is clamped shorter. Laying out 27,000 words
    /// whole took 0.06 s. The viewport below is what lets a word reach the
    /// visible top: laid out through the word and no further, the view ends
    /// at its paragraph (#558: token 18,000 of 27,000 came to rest at the
    /// visible bottom). `range`'s own paragraph and those below are
    /// invalidated first: a paragraph laid out on its own, as a measurement
    /// or the walk here does, keeps the place its estimate gave it until it
    /// is laid out again in one run from the top (measured: the paragraph
    /// after one at 86,015 pt placed at 58,837 pt). On a text already laid
    /// out whole (`layOutAll()`) the same run from the top keeps it whole.
    func layOut(through range: NSRange) {
        layoutSteps += 1
        guard range.location != NSNotFound, let start = location(range.location),
            let end = location(NSMaxRange(range))
        else { return }
        // The paragraphs below, a viewport's worth, counted in heights: their
        // places mean nothing yet.
        var below = -(enclosingScrollView?.contentView.bounds.height ?? 0)
        var last: NSTextLocation = end
        var own = true
        layoutManager.enumerateTextLayoutFragments(from: end, options: [.ensuresLayout]) {
            fragment in
            if !own { below += fragment.layoutFragmentFrame.height }
            own = false
            last = fragment.rangeInElement.endLocation
            return below < 0
        }
        if let stale = NSTextRange(location: start, end: last) {
            layoutManager.invalidateLayout(for: stale)
        }
        guard let all = NSTextRange(location: contentStorage.documentRange.location, end: last)
        else { return }
        layoutManager.ensureLayout(for: all)
        layoutViewport()  // the view grows to the height laid out
    }

    /// Asks for the whole text to be laid out when the run loop is next
    /// idle (spec §11 TX-37 (d) as amended by #583): a one-shot observer
    /// before the main loop waits, in the default mode only, so the pass is
    /// never part of the rebuild that asked for it (TX-21's bound) and never
    /// runs under a scroller's or a divider's drag. One pass is pending at
    /// most: asking again drops the one before, which is how the next
    /// rebuild drops a pass that has not run.
    func scheduleWholeLayout() {
        guard laysOutWhenIdle else { return }
        if let pending = wholeLayoutObserver { CFRunLoopObserverInvalidate(pending) }
        wholeLayoutObserver = nil
        guard !tokenStarts.isEmpty else { return }
        // Order 0: meant to run before AppKit's and Core Animation's own
        // before-waiting observers (the paint order is not measured).
        let observer = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, false, 0
        ) { [weak self] _, _ in self?.layOutAll() }
        wholeLayoutObserver = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .defaultMode)
    }

    /// Lays every paragraph out in one run from the top, so the view is as
    /// tall as the text and the scroller's knob reads the true position, and
    /// puts the anchor word back at its offset from the visible top: the
    /// rebuild's own anchor while the view is where the rebuild left it, else
    /// the word at the top now (a scroll since then wins). Nothing is
    /// invalidated first: one layout over the whole document re-places the
    /// paragraphs the viewport or a measurement had placed from estimates
    /// (measured: word 26,000 of 27,000, measured at 95,447 pt before the
    /// pass, at 125,187 pt after it, where a layout from the top puts it).
    func layOutAll() {
        wholeLayoutObserver = nil
        let kept = wholeLayoutAnchor
        wholeLayoutAnchor = nil
        let clipY = enclosingScrollView?.contentView.bounds.minY
        var anchor: (token: Int, offset: CGFloat)?
        if let kept, let clipY, abs(kept.clipY - clipY) <= 0.5 {
            anchor = (kept.token, kept.offset)
        } else if !visibleRect.isEmpty, let top = topVisibleToken(),
            let rect = rects(forToken: top).first
        {
            // Out of sight there is no top word to keep, and no scroll.
            anchor = (top, rect.minY - visibleRect.minY)
        }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        layoutViewport()  // the view grows to the text's height
        if let anchor, let rect = rects(forToken: anchor.token).first {
            scroll(to: rect.minY - anchor.offset)
        }
        laidOutWhole = true
        wholeLayouts += 1
    }

    /// Scrolls `index`'s line to the visible top, the text from the top
    /// through it laid out first (`layOut(through:)`, #558).
    func scrollToToken(_ index: Int) {
        layOut(through: tokenRange(index))
        guard let rect = rects(forToken: index).first else { return }
        scroll(to: rect.minY - 4)
    }

    /// The token nearest in x on the laid-out line above (`up`) or below
    /// `index`'s, skipping a timecode line; nil at either end.
    func tokenOnAdjacentLine(to index: Int, up: Bool) -> Int? {
        guard let rect = rects(forToken: index).first else { return nil }
        var y = up ? rect.minY - 1 : rect.maxY + 1
        for _ in 0..<4 {
            let point = NSPoint(x: rect.midX, y: y)
            guard y > 0, y < bounds.maxY, let offset = characterOffset(at: point) else { return nil }
            if paragraphIndex(atOffset: offset) == nil, let found = token(atOrBefore: offset),
                found != index
            {
                return found
            }
            let line = rects(for: NSRange(location: offset, length: 0)).first?.height ?? 16
            y += up ? -max(line, 4) : max(line, 4)
        }
        return nil
    }
}
