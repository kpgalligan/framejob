import Foundation

/// The Transcript tab's model (road map "creator-jobs" TX2a, spec §11 TX-22):
/// TX1's timeline words as tokens in paragraphs, the highlight search and the
/// pause sets that break a paragraph inside one instance. Pure: it is handed
/// the words and each media's pause set, and reads no file, no cache and no
/// window.
///
/// **Paragraphs (TX-22).** Consecutive tokens a and b are in different
/// paragraphs when the track or the speaker label changes; across instances
/// (clip or nest path) on one track when b.start − a.end ≥ 1.5 s; within one
/// instance when the media's pause set holds a's source tick.
///
/// `struck` and `collapsedBefore` are reserved for TX4 and TX5: always false
/// and 0 here, set only by TX-S2's fixture.
struct TranscriptTokens {
    struct Token {
        let index: Int
        let word: TimelineTranscript.Word
        let paragraph: Int
        let struck: Bool
        let collapsedBefore: Int
    }

    struct Paragraph {
        let index: Int
        let start: Ticks
        let firstToken: Int
        /// One past the paragraph's last token.
        let endToken: Int
        let track: UInt32
    }

    let tokens: [Token]
    let paragraphs: [Paragraph]

    static let empty = TranscriptTokens(tokens: [], paragraphs: [])

    /// The pause that breaks a paragraph (TX-22): 1.5 s.
    static let paragraphPause: Ticks = ReelTime.perSecond * 3 / 2

    init(tokens: [Token], paragraphs: [Paragraph]) {
        self.tokens = tokens
        self.paragraphs = paragraphs
    }

    /// The tokens of `words` (TX-10's order, kept) in TX-22's paragraphs.
    /// `pauses` is each media's pause set (`pauses(_:speech:confidence:)`);
    /// a media with none breaks only across instances.
    static func build(
        _ words: [TimelineTranscript.Word], pauses: [UInt32: Set<Ticks>]
    ) -> TranscriptTokens {
        build(words, pauses: pauses, struck: [], collapsed: [:])
    }

    /// `build` with the reserved marks set — TX-S2's fixture only.
    static func build(
        _ words: [TimelineTranscript.Word], pauses: [UInt32: Set<Ticks>],
        struck: Set<Int>, collapsed: [Int: Int]
    ) -> TranscriptTokens {
        var tokens: [Token] = []
        var paragraphs: [Paragraph] = []
        tokens.reserveCapacity(words.count)
        var first = 0
        for (index, word) in words.enumerated() {
            if index > 0, breaks(words[index - 1], word, pauses: pauses) {
                paragraphs.append(paragraph(paragraphs.count, words, first, index))
                first = index
            }
            tokens.append(
                Token(
                    index: index, word: word, paragraph: paragraphs.count,
                    struck: struck.contains(index), collapsedBefore: collapsed[index] ?? 0))
        }
        if !words.isEmpty { paragraphs.append(paragraph(paragraphs.count, words, first, words.count)) }
        return TranscriptTokens(tokens: tokens, paragraphs: paragraphs)
    }

    private static func paragraph(
        _ index: Int, _ words: [TimelineTranscript.Word], _ first: Int, _ end: Int
    ) -> Paragraph {
        Paragraph(
            index: index, start: words[first].start, firstToken: first, endToken: end,
            track: words[first].track)
    }

    /// TX-22's break between consecutive words `a` and `b`.
    static func breaks(
        _ a: TimelineTranscript.Word, _ b: TimelineTranscript.Word, pauses: [UInt32: Set<Ticks>]
    ) -> Bool {
        if a.track != b.track || a.speaker != b.speaker { return true }
        if a.clip != b.clip || a.id.nestPath != b.id.nestPath {
            return b.start - a.end >= paragraphPause
        }
        return pauses[a.media]?.contains(a.id.source) == true
    }

    /// One media's pause set (TX-22): the identity tick (TX-17) of each word
    /// w after which the speaker paused. With the voice cache, w is in it when the
    /// cache has a run of chunks inside [w.source, w′.sourceEnd), w′ the next
    /// source word, all below `confidence` and lasting ≥ 1.5 s of SOURCE
    /// time; with none, when w′.source − w.sourceEnd ≥ 1.5 s. Off main: it
    /// walks every word of the media once.
    static func pauses(
        _ words: [TimelineTranscript.SourceWord], speech: [Float]?, confidence: Float
    ) -> Set<Ticks> {
        var out = Set<Ticks>()
        guard words.count > 1 else { return out }
        let chunk = MediaSpeech.chunkTicks
        let needed = Int((paragraphPause + chunk - 1) / chunk)
        for index in 0..<(words.count - 1) {
            let w = words[index]
            let next = words[index + 1]
            guard let speech else {
                if next.source - w.sourceEnd >= paragraphPause { out.insert(w.identityTick) }
                continue
            }
            // The chunks wholly inside [w.source, w′.sourceEnd).
            let firstChunk = Int((w.source + chunk - 1) / chunk)
            let pastChunk = min(Int(max(next.sourceEnd, 0) / chunk), speech.count)
            guard pastChunk - firstChunk >= needed else { continue }
            var run = 0
            for k in max(firstChunk, 0)..<pastChunk {
                run = speech[k] < confidence ? run + 1 : 0
                if run >= needed {
                    out.insert(w.identityTick)
                    break
                }
            }
        }
        return out
    }

    /// The highlighted token at `playhead` (TX-22): the LATEST token whose
    /// start is at or before it, so a word stays lit through the pause after
    /// it; nil before the first. A binary search: the tokens are in start
    /// order (TX-10).
    func highlight(at playhead: Ticks) -> Int? {
        var low = 0
        var high = tokens.count
        while low < high {
            let mid = (low + high) / 2
            if tokens[mid].word.start <= playhead { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    /// The token carrying `id`, if any.
    func index(of id: TimelineTranscript.Identity) -> Int? {
        tokens.firstIndex { $0.word.id == id }
    }

    /// The first token at or after `start`, else the last one.
    func firstIndex(atOrAfter start: Ticks) -> Int? {
        guard !tokens.isEmpty else { return nil }
        var low = 0
        var high = tokens.count
        while low < high {
            let mid = (low + high) / 2
            if tokens[mid].word.start < start { low = mid + 1 } else { high = mid }
        }
        return min(low, tokens.count - 1)
    }
}
