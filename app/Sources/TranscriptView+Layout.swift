import AppKit

/// `TranscriptView`'s geometry: a UTF-16 range's rects, the token or the
/// paragraph timecode under a point, the top visible token, and the scroll
/// that brings a token to the top. Every rect is in the view's (flipped)
/// coordinates: the text container's offset by `TranscriptView.inset`.
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

    /// Scrolls `index`'s line to the visible top. Laid out twice: the first
    /// scroll lands on an estimate for text never laid out, which the
    /// viewport layout there settles.
    func scrollToToken(_ index: Int) {
        for _ in 0..<2 {
            guard let rect = rects(forToken: index).first else { return }
            scroll(to: rect.minY - 4)
        }
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
