import Foundation

/// Word-caption PAGES (road map 8 §5c, W4a): recognised words in, one
/// `CaptionLayout.Cue` per page out, each carrying its `words` — for every
/// caption style but Subtitles, whose cues stay `CaptionCues.build`'s,
/// unchanged and byte-identical (spec §11 W-7).
///
/// **A page is filled to a MEASURED width, not a count.** The width test is
/// `LayerRenderers.measuredSize(for:)` of the page exactly as it will be
/// placed — the style's face, size, case, outline and word-style headroom —
/// against `widthBudget` of the canvas width. That function is static and
/// lock-guarded, so this runs on whatever thread the engine runs on
/// (`Transcriber.work`, `CloudTranscriber.work`, the server thread).
///
/// **A page is confined to its job's span** (spec §11 W-7). `lead` shifts a
/// word and `hold` extends a page, and neither may carry a page past
/// `span.upperBound`: every word is clamped into the span after `lead`, a
/// word pushed off the end sits on the clip's LAST FRAME (`upper − frame`,
/// because the core snaps to the NEAREST frame and one tick short of the
/// bound would land on the next clip's first frame), and the last page ends
/// at or before the bound. So pages of two abutting clips abut at most, and
/// `CaptionLayout.place`'s trim pass never fires on a transcript —
/// `CaptionCues`' promise, kept here too.
///
/// **The row never blinks.** A page ends at `min(next.start, last.end +
/// hold)`, and where the gap to the next page is under `breakGap` it ends AT
/// the next page's start. That is `CaptionCues`' one-frame gap deliberately
/// not applied: abutting clips place cleanly (`b.start == a.end` is not an
/// overlap).
///
/// **Pauses are word gaps and punctuation** (W4a's decision, spec §11
/// W-7): a gap of `breakGap` or more, or a word ending `.?!…`, closes a
/// page. `SilenceDetector`/`MediaSpeech` are not consulted — this is pure
/// arithmetic over the words, testable with no audio (road map 8 §10.9).
enum CaptionPages {

    /// Road map 8 §8's numbers, in ticks where they are times.
    struct Rules: Equatable {
        /// Of the canvas width.
        var widthBudget = 0.86
        /// Of the style's size: where a lone word stops shrinking and wraps.
        var shrinkFloor = 0.80
        /// A width break within this many words after a `,;:` moves back.
        var clauseWindow = 2
        /// …if the page before the mark is at least this much of the budget.
        var clauseMinimum = 0.5
        /// 3 s on screen, to the last word's end.
        var maxLength: Ticks = 1_800_000
        /// 0.25 s: a gap this long closes a page (W0 q1's measurement).
        var breakGap: Ticks = 150_000
        /// 0.5 s a page stays up after its last word.
        var hold: Ticks = 300_000

        static let standard = Rules()
    }

    /// What a run asks the pager for: the style and the canvas it measures
    /// against. A DISPLAY choice — never part of a transcript's cache key
    /// (spec §11 R6-15).
    struct Request: Equatable {
        let style: CaptionStyle
        let canvas: CGSize
    }

    /// Where each engine's word starts sit against the voice, as a shift
    /// applied in `normalize` — road map 8 §8, MEASURED by W0 q2: on-device
    /// runs 270 ms EARLY (+162 000 ticks), AssemblyAI 60 ms LATE (−36 000).
    /// It lives here and nowhere else; `CaptionCues` never shifts a word.
    static func lead(for engine: TranscriptionEngine) -> Ticks {
        switch engine {
        case .apple: return 162_000
        case .assemblyai: return -36_000
        }
    }

    /// The words the pager reads: trimmed, empties dropped, a word with
    /// internal whitespace split into tokens sharing its timing, sorted by
    /// start (ties in arrival order), shifted by `lead`, then clamped into
    /// `span` — start into `[lower, upper − frame]`, end into `[start,
    /// upper]`.
    static func normalize(
        _ words: [CaptionCues.Word], lead: Ticks, span: Range<Ticks>, frame: Ticks
    ) -> [CaptionCues.Word] {
        var tokens: [(order: Int, word: CaptionCues.Word)] = []
        for word in words {
            for piece in word.text.split(whereSeparator: \.isWhitespace) {
                tokens.append((
                    tokens.count,
                    CaptionCues.Word(
                        text: String(piece), start: word.start, end: word.end,
                        speaker: word.speaker)
                ))
            }
        }
        tokens.sort {
            $0.word.start == $1.word.start ? $0.order < $1.order : $0.word.start < $1.word.start
        }
        let lower = span.lowerBound
        let upper = span.upperBound
        let lastFrame = max(lower, upper - frame)
        return tokens.map { entry in
            let word = entry.word
            let start = min(max(word.start + lead, lower), lastFrame)
            let end = min(max(word.end + lead, start), upper)
            return CaptionCues.Word(text: word.text, start: start, end: end, speaker: word.speaker)
        }
    }

    /// Whether `content` — one line, or lines split at `"\n"`, each tested
    /// alone — lays within `budget` pixels in `style` at `size`.
    static func fits(_ content: String, style: CaptionStyle, size: Double, budget: Double) -> Bool {
        content.split(separator: "\n").allSatisfy { width(String($0), style, size) <= budget }
    }

    /// The Subtitles-or-pages dispatch both engines call per job.
    /// `.subtitles` is `CaptionCues.build`, untouched: no `lead`, no span.
    static func cues(
        from words: [CaptionCues.Word], span: Range<Ticks>, frame: Ticks, request: Request,
        engine: TranscriptionEngine, clip: UInt32?
    ) -> [CaptionLayout.Cue] {
        guard request.style.isWordStyle else {
            return CaptionCues.build(from: words, frame: frame, clip: clip)
        }
        return build(
            from: words, span: span, frame: frame, request: request, engine: engine, clip: clip)
    }

    /// The first page `cues(...)` makes of `words` — the Generate Captions
    /// sheet's preview sample (road map 8's W4b), a REAL page, so the preview
    /// shows what generation would place. The span runs from 0 to past the
    /// last word's hold, so nothing is clamped.
    static func samplePage(
        _ words: [CaptionCues.Word], request: Request, frame: Ticks
    ) -> CaptionLayout.Cue? {
        let end = (words.last?.end ?? 0) + Rules.standard.hold + 600_000
        return cues(
            from: words, span: 0 ..< end, frame: frame, request: request, engine: .apple,
            clip: nil
        ).first
    }

    // MARK: - The pager

    /// Why a page closed, which decides whether the balance step may touch
    /// it: only a page closed by WIDTH alone is balanced.
    private enum Close {
        case forced, width, clause, end
    }

    private struct Page {
        var words: [CaptionCues.Word]
        var close: Close
    }

    /// Pages for one job's words, each within `span`.
    static func build(
        from words: [CaptionCues.Word], span: Range<Ticks>, frame: Ticks, request: Request,
        engine: TranscriptionEngine, rules: Rules = .standard, clip: UInt32? = nil
    ) -> [CaptionLayout.Cue] {
        let style = request.style
        let tokens = normalize(words, lead: lead(for: engine), span: span, frame: frame)
        guard !tokens.isEmpty else { return [] }
        let base = style.size(for: request.canvas)
        let budget = rules.widthBudget * Double(request.canvas.width)
        let pager = Pager(style: style, size: base, budget: budget, rules: rules)

        var pages: [Page] = []
        var current: [CaptionCues.Word] = []
        func close(_ reason: Close) {
            guard !current.isEmpty else { return }
            pages.append(Page(words: current, close: reason))
            current = []
            pager.balance(&pages)
        }

        for word in tokens {
            guard let previous = current.last, let first = current.first else {
                current = [word]
                continue
            }
            if word.speaker != previous.speaker || word.start - previous.end >= rules.breakGap
                || Pager.endsSentence(previous.text) || word.end - first.start > rules.maxLength
                || current.count >= (style.maxWords ?? Int.max)
            {
                close(.forced)
                current = [word]
            } else if pager.lines(current + [word]) != nil {
                current.append(word)
            } else if let mark = pager.clauseMark(in: current, before: word) {
                let rest = Array(current[(mark + 1)...])
                current = Array(current[...mark])
                close(.clause)
                current = rest + [word]
            } else {
                close(.width)
                current = [word]
            }
        }
        close(.end)

        var cues: [CaptionLayout.Cue] = []
        for (index, page) in pages.enumerated() {
            let first = page.words[0]
            let last = page.words[page.words.count - 1]
            let end: Ticks
            if index + 1 < pages.count {
                let next = pages[index + 1].words[0].start
                end = next - last.end < rules.breakGap ? next : min(next, last.end + rules.hold)
            } else {
                end = min(last.end + rules.hold, span.upperBound)
            }
            let lines = pager.lines(page.words) ?? [page.words]
            let text = lines.map { $0.map(\.text).joined(separator: " ") }
                .joined(separator: "\n")
            var size: Double?
            var width: Double?
            if page.words.count == 1, !fits(text, style: style, size: base, budget: budget) {
                (size, width) = pager.shrink(text)
            }
            cues.append(
                CaptionLayout.Cue(
                    start: first.start, end: max(end, first.start), text: text,
                    tag: tag(at: first.start, clip: clip), words: page.words, size: size,
                    width: width))
        }
        return cues
    }

    /// The measured width of one line as it will be placed.
    private static func width(_ line: String, _ style: CaptionStyle, _ size: Double) -> Double {
        Double(
            LayerRenderers.measuredSize(
                for: style.textProps(content: line, size: size, width: nil)
            ).width)
    }

    /// `CaptionCues`' spelling of a cue's name, for the same messages.
    private static func tag(at start: Ticks, clip: UInt32?) -> String {
        let when = String(format: "%.1f s", ReelTime.seconds(start))
        guard let clip = clip else { return "caption at \(when)" }
        return "clip \(clip) at \(when)"
    }

    /// The width arithmetic one run pages with: the style, its base size,
    /// the budget in pixels and the rules.
    private struct Pager {
        let style: CaptionStyle
        let size: Double
        let budget: Double
        let rules: Rules

        static func endsSentence(_ text: String) -> Bool {
            guard let mark = text.last else { return false }
            return ".?!…".contains(mark)
        }

        static func endsClause(_ text: String) -> Bool {
            guard let mark = text.last else { return false }
            return ",;:".contains(mark)
        }

        func line(_ words: ArraySlice<CaptionCues.Word>) -> String {
            words.map(\.text).joined(separator: " ")
        }

        /// The words laid greedily into at most `style.maxLines` lines, each
        /// within the budget — nil when they do not go. A line of one word
        /// wider than the budget is allowed only when it is the whole page:
        /// that is the lone word `shrink` answers for.
        func lines(_ words: [CaptionCues.Word]) -> [[CaptionCues.Word]]? {
            var out: [[CaptionCues.Word]] = []
            for word in words {
                if var last = out.last {
                    last.append(word)
                    if fits(line(last[...]), style: style, size: size, budget: budget) {
                        out[out.count - 1] = last
                        continue
                    }
                    guard out.count < style.maxLines else { return nil }
                }
                if words.count > 1, !fits(word.text, style: style, size: size, budget: budget) {
                    return nil
                }
                out.append([word])
            }
            return out
        }

        /// The widest line of a page that lays, in pixels.
        func measure(_ words: [CaptionCues.Word]) -> Double {
            (lines(words) ?? [words]).map { width(line($0[...]), style, size) }.max() ?? 0
        }

        /// Clause preference: a width break within `clauseWindow` words
        /// after a `,;:` moves back to the mark — when the page before it
        /// is at least `clauseMinimum` of the budget and what moves, with
        /// `word`, still lays. The index of the mark's word, or nil.
        func clauseMark(in page: [CaptionCues.Word], before word: CaptionCues.Word) -> Int? {
            let lowest = max(0, page.count - 1 - rules.clauseWindow)
            for mark in stride(from: page.count - 2, through: lowest, by: -1) {
                guard Self.endsClause(page[mark].text) else { continue }
                let head = Array(page[...mark])
                guard measure(head) >= rules.clauseMinimum * budget,
                      lines(Array(page[(mark + 1)...]) + [word]) != nil
                else { return nil }
                return mark
            }
            return nil
        }

        /// The balance step, once per pair: when the page before the one
        /// just closed was closed by width alone, move its last word onto
        /// the new page if both still lay, no rule is broken, and their
        /// measured widths come closer. What stops a sentence ending on a
        /// one-word orphan while keeping every page within the budget.
        func balance(_ pages: inout [Page]) {
            guard pages.count >= 2 else { return }
            let before = pages[pages.count - 2]
            let after = pages[pages.count - 1]
            guard before.close == .width, before.words.count >= 2 else { return }
            let moved = before.words[before.words.count - 1]
            let kept = Array(before.words.dropLast())
            let grown = [moved] + after.words
            guard grown.count <= (style.maxWords ?? Int.max),
                  grown[grown.count - 1].end - moved.start <= rules.maxLength,
                  grown.allSatisfy({ $0.speaker == moved.speaker }),
                  lines(kept) != nil, lines(grown) != nil,
                  abs(measure(kept) - measure(grown))
                    < abs(measure(before.words) - measure(after.words))
            else { return }
            pages[pages.count - 2].words = kept
            pages[pages.count - 1].words = grown
        }

        /// A lone word too wide for the budget: its size in 5 % steps of the
        /// base down to `shrinkFloor`, the first that fits — and when none
        /// does, the floor with `width = budget`, so CoreText wraps it.
        func shrink(_ text: String) -> (size: Double?, width: Double?) {
            let steps = Int(((1 - rules.shrinkFloor) / 0.05).rounded())
            for step in stride(from: 1, through: steps, by: 1) {
                let smaller = size * (1 - 0.05 * Double(step))
                if fits(text, style: style, size: smaller, budget: budget) {
                    return (smaller, nil)
                }
            }
            return (size * rules.shrinkFloor, budget)
        }
    }
}
