import Foundation

/// Find in the Transcript tab (spec §11 TX-37): what is searched and what a
/// match is. Pure, `MediaListFilter`'s shape: tokens in, matches out; it
/// reads no view, no window and no document.
///
/// **What is searched (TX-37 (a)).** The WORDS, not the view's string: each
/// paragraph's token texts joined by one space, paragraphs separated by a line
/// break, and a line break rather than a space before a token with
/// `collapsedBefore > 0`. So a timecode, "⋯" and a pause label are never
/// matched, a phrase is found across a pause label, and no match spans a
/// paragraph break or a collapse.
///
/// **How (TX-37 (b)).** The query verbatim, compared ignoring case, diacritics
/// and width (the three things `localizedStandardContains` ignores, which the
/// Media tab's search uses), left to right, never overlapping. A match is its
/// token range and, per token, the part of that token's text it covers; one
/// that covers no token character (a query of spaces) is dropped, and an
/// empty query or one holding a line break has no matches.
enum TranscriptFind {
    /// The part of one token's text a match covers, UTF-16, within the text.
    struct Piece: Equatable {
        let token: Int
        let range: NSRange
    }

    struct Match: Equatable {
        let tokens: ClosedRange<Int>
        let pieces: [Piece]
    }

    static let options: NSString.CompareOptions = [
        .caseInsensitive, .diacriticInsensitive, .widthInsensitive,
    ]

    struct Index {
        /// (a)'s text.
        let text: NSString
        /// Each token's UTF-16 offset in `text`, ascending, and its length.
        let offsets: [Int]
        let lengths: [Int]

        init(model: TranscriptTokens) {
            let plain = NSMutableString()
            var offsets: [Int] = []
            var lengths: [Int] = []
            offsets.reserveCapacity(model.tokens.count)
            lengths.reserveCapacity(model.tokens.count)
            for paragraph in model.paragraphs {
                if paragraph.firstToken > 0 { plain.append("\n") }
                for index in paragraph.firstToken..<paragraph.endToken {
                    let token = model.tokens[index]
                    if index > paragraph.firstToken {
                        plain.append(token.collapsedBefore > 0 ? "\n" : " ")
                    }
                    let length = (token.word.text as NSString).length
                    offsets.append(plain.length)
                    lengths.append(length)
                    plain.append(token.word.text)
                }
            }
            self.text = plain
            self.offsets = offsets
            self.lengths = lengths
        }

        /// The first token whose text ends after `offset`, by binary search.
        private func token(endingAfter offset: Int) -> Int {
            var low = 0
            var high = offsets.count
            while low < high {
                let mid = (low + high) / 2
                if offsets[mid] + lengths[mid] > offset { high = mid } else { low = mid + 1 }
            }
            return low
        }

        /// Every match of `query`, in text order (TX-37 (b)).
        func matches(_ query: String) -> [Match] {
            guard !query.isEmpty, query.rangeOfCharacter(from: .newlines) == nil else { return [] }
            var out: [Match] = []
            var from = 0
            while from < text.length {
                let found = text.range(
                    of: query, options: TranscriptFind.options,
                    range: NSRange(location: from, length: text.length - from))
                guard found.location != NSNotFound else { break }
                from = max(NSMaxRange(found), found.location + 1)
                var pieces: [Piece] = []
                var index = token(endingAfter: found.location)
                while index < offsets.count, offsets[index] < NSMaxRange(found) {
                    let own = NSRange(location: offsets[index], length: lengths[index])
                    let part = NSIntersectionRange(own, found)
                    if part.length > 0 {
                        pieces.append(
                            Piece(
                                token: index,
                                range: NSRange(
                                    location: part.location - own.location, length: part.length)))
                    }
                    index += 1
                }
                if let first = pieces.first, let last = pieces.last {
                    out.append(Match(tokens: first.token...last.token, pieces: pieces))
                }
            }
            return out
        }
    }

    /// The current match while typing (TX-37 (c)): the first one starting at
    /// or after token `anchor`, else the first; nil with none.
    static func current(in matches: [Match], atOrAfter anchor: Int) -> Int? {
        guard !matches.isEmpty else { return nil }
        var low = 0
        var high = matches.count
        while low < high {
            let mid = (low + high) / 2
            if matches[mid].tokens.lowerBound < anchor { low = mid + 1 } else { high = mid }
        }
        return low < matches.count ? low : 0
    }

    /// Return's and ⇧Return's move (TX-37 (c)): `delta` matches on from
    /// `current`, wrapping; from none, the first or the last.
    static func step(_ current: Int?, by delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return delta < 0 ? count - 1 : 0 }
        return ((current + delta) % count + count) % count
    }

    /// The bar's count: nothing for an empty query, "No matches", "3 of 12".
    static func label(query: String, current: Int?, count: Int) -> String {
        if query.isEmpty { return "" }
        guard count > 0, let current else { return "No matches" }
        return "\(current + 1) of \(count)"
    }
}
