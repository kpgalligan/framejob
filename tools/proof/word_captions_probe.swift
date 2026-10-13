// Road map 8, W4a — the pager's app-side probe (`word_captions_probe.py`
// builds and runs it).
//
// Compiled AS `main.swift`, with `word_captions_support.swift` beside it, over
// every file in `app/Sources` but the app's own `main.swift`, module
// `FrameJob`, against `libframejob_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — so every row calls the
// app's own `CaptionPages`, `CaptionStyle` and `CaptionCues`. The WIDTH
// checks measure through `LayerRenderers.measuredSize(for:)` of
// `CaptionStyle.textProps` DIRECTLY, never through `CaptionPages.fits`, so a
// mutant of the pager's width test cannot mark its own homework.
//
//   word_captions_probe <app_fonts_dir> <words.json> <pangram.wav>
//
// `words.json` is the fixed list `word_captions_probe.py` writes: fixtures'
// `talk_text` tiled at 0.3 s from 1.0 s plus one 40-letter compound. One
// JSON object out: `rows` (name, ok, detail) and `p10`.
import AVFoundation
import AppKit
import CoreText

_ = NSApplication.shared
var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String) {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1500))])
}

guard CommandLine.arguments.count >= 4 else {
    print(#"{"ok":false,"error":"usage: word_captions_probe <fonts> <words.json> <pangram.wav>"}"#)
    exit(1)
}
let registered = register(CommandLine.arguments[1])
let listData = (try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) ?? Data()
let listJSON = (try? JSONSerialization.jsonObject(with: listData)) as? [[String: Any]] ?? []
let fixed = listJSON.map {
    CaptionCues.Word(
        text: $0["text"] as? String ?? "", start: ($0["start"] as? NSNumber)?.int64Value ?? 0,
        end: ($0["end"] as? NSNumber)?.int64Value ?? 0)
}

let rules = CaptionPages.Rules.standard
let frame: Ticks = 20_000
let span: Range<Ticks> = 0 ..< ((fixed.map(\.end).max() ?? 0) + 1_200_000)
let canvases = [CGSize(width: 1080, height: 1920), CGSize(width: 1920, height: 1080)]
let wordStyles = CaptionStyle.allCases.filter(\.isWordStyle)

var built: [Built] = []
for canvas in canvases {
    for style in wordStyles {
        built.append(Built(
            style: style, canvas: canvas,
            cues: CaptionPages.build(
                from: fixed, span: span, frame: frame,
                request: CaptionPages.Request(style: style, canvas: canvas), engine: .apple)))
    }
}
func label(_ b: Built) -> String { b.label }

// MARK: - P0 the shape every placed page must have

var bad0: [String] = []
for b in built {
    var previous: Ticks = .min
    for cue in b.cues {
        let words = cue.words ?? []
        let tokens = cue.text.split(whereSeparator: \.isWhitespace).count
        if tokens != words.count || words.isEmpty { bad0.append("\(label(b)) \(cue.text): count") }
        if zip(words, words.dropFirst()).contains(where: { $0.start > $1.start })
            || words.contains(where: { $0.end < $0.start })
        {
            bad0.append("\(label(b)) \(cue.text): order")
        }
        if cue.start < span.lowerBound || cue.end > span.upperBound || cue.end < cue.start
            || cue.start < previous
        {
            bad0.append("\(label(b)) \(cue.text): time \(cue.start)…\(cue.end)")
        }
        previous = cue.start
    }
}
check("P0 every page: one timing per token, starts non-decreasing, end ≥ start, in the span",
      !built.isEmpty && built.allSatisfy { !$0.cues.isEmpty } && bad0.isEmpty,
      "\(built.map { "\(label($0)) \($0.cues.count) pages" }) \(bad0.prefix(6))")

// MARK: - P1 every multi-word page within the budget

var over: [String] = []
var worstFill = 0.0
for b in built {
    for cue in b.cues where (cue.words?.count ?? 0) > 1 {
        for line in cue.text.split(separator: "\n") {
            let width = measured(String(line), b.style, cue.size ?? b.base)
            worstFill = max(worstFill, width / b.budget)
            if width > b.budget { over.append("\(label(b)) \"\(line)\" \(Int(width)) > \(Int(b.budget))") }
        }
    }
}
check("P1 every multi-word page measures within 0.86 of the canvas width",
      over.isEmpty, "fullest line \(String(format: "%.3f", worstFill)) of the budget; \(over.prefix(4))")

// MARK: - P2 width-only breaks are maximal (or one balance move from it)

var widthBreaks = 0
var balanced = 0
var clauses = 0
var slack: [String] = []
for b in built {
    let pages = b.pages
    for index in pages.indices.dropLast() {
        let a = pages[index]
        let next = pages[index + 1]
        guard !forced(a, next, b.style) else { continue }
        let tokens = a.map(\.text)
        let first = next[0].text
        // One balance move: A + B0 was the page, A + B0 + B1 did not lay,
        // and moving B0 back would make the pair LESS even.
        let rest = next.dropFirst().map(\.text)
        let oneMove = layLines(tokens + [first], b.style, b.base, b.budget) != nil
            && rest.first.map { second in
                layLines(tokens + [first, second], b.style, b.base, b.budget) == nil
                    && abs(pageWidth(tokens, b.style, b.base, b.budget)
                        - pageWidth(next.map(\.text), b.style, b.base, b.budget))
                    < abs(pageWidth(tokens + [first], b.style, b.base, b.budget)
                        - pageWidth(Array(rest), b.style, b.base, b.budget))
            } == true
        // A clause break only where `clauseMark`'s own conditions held and a
        // balance move does not explain the page: at least `clauseMinimum` of
        // the budget, and it plus the next m words (m ≤ `clauseWindow`) laid
        // where one more did not.
        if endsWith(tokens.last ?? "", ",;:"), !oneMove,
           pageWidth(tokens, b.style, b.base, b.budget) >= rules.clauseMinimum * b.budget,
           (1...rules.clauseWindow).contains(where: { m in
               m < next.count
                   && layLines(tokens + next[..<m].map(\.text), b.style, b.base, b.budget) != nil
                   && layLines(tokens + next[...m].map(\.text), b.style, b.base, b.budget) == nil
           })
        {
            clauses += 1
            continue
        }
        widthBreaks += 1
        if layLines(tokens + [first], b.style, b.base, b.budget) == nil { continue }
        if oneMove {
            balanced += 1
            continue
        }
        slack.append("\(label(b)) \"\(tokens.joined(separator: " "))\" + \"\(first)\" still fits")
    }
}
check("P2 every page closed only by width would pass the budget with its next word "
      + "(or is one balance move from such a page); a ,;: page only where the clause rule held",
      widthBreaks > 0 && clauses > 0 && slack.isEmpty,
      "\(widthBreaks) width breaks, \(balanced) balanced, \(clauses) at a clause mark; "
        + "\(slack.prefix(4))")

// MARK: - P3 no lone word unless forced, or at least half the budget

var lone = 0
var unmoved = 0
var orphans: [String] = []
for b in built {
    let pages = b.pages
    for (index, page) in pages.enumerated() where page.count == 1 {
        lone += 1
        let word = page[0]
        if measured(word.text, b.style, b.base) >= 0.5 * b.budget { continue }
        if index == 0 || forced(pages[index - 1], page, b.style) { continue }
        let before = pages[index - 1]
        if before.count == 1 { continue }
        if word.end - before[before.count - 1].start > rules.maxLength { continue }
        // The balance step's own test, read off the pages: a lone word a
        // width break left behind stays alone only when moving the word
        // before it across would not lay, or would not bring the pair's
        // widths closer ("that actually | works.", highlight at 1080 wide).
        let kept = before.dropLast().map(\.text)
        let grown = [before[before.count - 1].text, word.text]
        if layLines(grown, b.style, b.base, b.budget) == nil
            || abs(pageWidth(kept, b.style, b.base, b.budget)
                   - pageWidth(grown, b.style, b.base, b.budget))
            >= abs(pageWidth(before.map(\.text), b.style, b.base, b.budget)
                   - pageWidth([word.text], b.style, b.base, b.budget))
        {
            unmoved += 1
            continue
        }
        orphans.append("\(label(b)) \"\(before.map(\.text).joined(separator: " "))\" | "
            + "\"\(word.text)\"")
    }
}
check("P3 no page is a lone word unless its break was forced, no balance move improves it, "
      + "or it is ≥ half the budget",
      orphans.isEmpty,
      "\(lone) lone-word pages, \(unmoved) after a width break no balance move improves; "
        + "orphans \(orphans.prefix(4))")

// MARK: - P4 a lone over-wide word shrinks before it wraps

var shrunk = 0
var wrapped = 0
var p4: [String] = []
for b in built {
    for cue in b.cues where (cue.words?.count ?? 0) == 1 {
        let text = cue.text
        let atBase = measured(text, b.style, b.base)
        let floor = b.base * rules.shrinkFloor
        if let width = cue.width {
            wrapped += 1
            if abs((cue.size ?? 0) - floor) > 1e-9 || abs(width - b.budget) > 1e-9
                || measured(text, b.style, floor) <= b.budget
            {
                p4.append("\(label(b)) wrapped \(text) at \(cue.size ?? 0)")
            }
        } else if let size = cue.size {
            shrunk += 1
            let larger = size + 0.05 * b.base
            if measured(text, b.style, size) > b.budget || atBase <= b.budget
                || (larger < b.base - 1e-9 && measured(text, b.style, larger) <= b.budget)
            {
                p4.append("\(label(b)) shrunk \(text) to \(size)")
            }
        } else if atBase > b.budget {
            p4.append("\(label(b)) \(text) is over-wide at its base size and was left")
        }
    }
    if b.cues.contains(where: { $0.width != nil && ($0.words?.count ?? 0) != 1 }) {
        p4.append("\(label(b)) a wrap width on a multi-word page")
    }
}
check("P4 a lone over-wide word shrinks in 5 % steps to the floor before it wraps",
      wrapped > 0 && p4.isEmpty, "\(shrunk) shrunk, \(wrapped) wrapped; \(p4.prefix(4))")

// MARK: - P5 no two-line page but Karaoke or a wrapped lone word

var twoLine: [String] = []
var karaokeTwo = 0
for b in built {
    for cue in b.cues {
        let props = b.style.textProps(content: cue.text, size: cue.size ?? b.base, width: cue.width)
        let lines = LayerRenderers.layout(for: props).lines.count
        guard lines > 1 else { continue }
        if b.style == .karaoke, lines <= 2, cue.width == nil {
            karaokeTwo += 1
            continue
        }
        if cue.width != nil, (cue.words?.count ?? 0) == 1 { continue }
        twoLine.append("\(label(b)) \(lines) lines: \(cue.text)")
    }
}
check("P5 no page lays on two lines but Karaoke (≤ 2) or a wrapped lone word",
      twoLine.isEmpty, "\(karaokeTwo) two-line karaoke pages; \(twoLine.prefix(4))")

// MARK: - P6 the row never blinks: abutment where the gap is under breakGap

func abutment(_ cues: [CaptionLayout.Cue]) -> (pairs: Int, bad: [String]) {
    var pairs = 0
    var bad: [String] = []
    for (a, b) in zip(cues, cues.dropFirst()) {
        guard let last = a.words?.last, let first = b.words?.first else { continue }
        guard first.start - last.end < rules.breakGap else { continue }
        pairs += 1
        if a.end != b.start { bad.append("\(a.text) ends \(a.end), next starts \(b.start)") }
    }
    return (pairs, bad)
}
// A second rules set whose `hold` (0.1 s) is SHORTER than every gap in the
// list (0.12 s): under §8's own numbers `hold` (0.5 s) outlasts `breakGap`
// (0.25 s), so `min(next.start, last.end + hold)` reaches the next page by
// itself and only this variant sees the no-blink rule do anything.
var shortHold = CaptionPages.Rules.standard
shortHold.hold = 60_000
var p6Pairs = 0
var p6Bad: [String] = []
for b in built {
    for set in [rules, shortHold] {
        let cues = set == rules ? b.cues : CaptionPages.build(
            from: fixed, span: span, frame: frame,
            request: CaptionPages.Request(style: b.style, canvas: b.canvas), engine: .apple,
            rules: set)
        let (pairs, bad) = abutment(cues)
        p6Pairs += pairs
        p6Bad += bad.map { "\(label(b)) hold \(set.hold): \($0)" }
    }
}
check("P6 page N ends at page N+1's start wherever the gap is under breakGap "
      + "(the standard rules, and a hold of 0.1 s)",
      p6Pairs > 0 && p6Bad.isEmpty, "\(p6Pairs) pairs; \(p6Bad.prefix(4))")

// MARK: - P7 the two canvases page differently

var p7: [String] = []
for style in wordStyles where style.maxWords == nil {
    let pages = canvases.map { canvas in
        built.first { $0.style == style && $0.canvas == canvas }?.cues.map(\.text) ?? []
    }
    if pages[0] == pages[1] { p7.append("\(style.rawValue) pages alike") }
    if pages[0].count <= pages[1].count {
        p7.append("\(style.rawValue): vertical \(pages[0].count) ≤ horizontal \(pages[1].count)")
    }
}
check("P7 the same words page differently on 1080×1920 and 1920×1080 (more pages vertical, "
      + "each within its own budget by P1)", p7.isEmpty,
      "\(built.map { "\(label($0)) \($0.cues.count)" }) \(p7)")

// MARK: - P8 lead, per engine

var p8: [String] = []
for engine in TranscriptionEngine.allCases {
    let cues = CaptionPages.build(
        from: fixed, span: span, frame: frame,
        request: CaptionPages.Request(style: .highlight, canvas: canvases[0]), engine: engine)
    let want = fixed[0].start + CaptionPages.lead(for: engine)
    let expected: Ticks = engine == .apple ? 162_000 : -36_000
    if cues.first?.start != want || cues.first?.words?.first?.start != want
        || CaptionPages.lead(for: engine) != expected
    {
        p8.append("\(engine.rawValue): first page at \(cues.first?.start ?? -1), want \(want)")
    }
}
check("P8 the first page starts at the raw start + lead (apple +162000, assemblyai −36000)",
      p8.isEmpty, "raw \(fixed.first?.start ?? -1); \(p8)")

// MARK: - P9 Subtitles is CaptionCues.build, untouched

var p9 = true
for engine in TranscriptionEngine.allCases {
    for canvas in canvases {
        let paged = CaptionPages.cues(
            from: fixed, span: span, frame: frame,
            request: CaptionPages.Request(style: .subtitles, canvas: canvas), engine: engine,
            clip: 7)
        if paged != CaptionCues.build(from: fixed, frame: frame, clip: 7) || paged.isEmpty
            || paged.contains(where: { $0.words != nil || $0.size != nil || $0.width != nil })
        {
            p9 = false
        }
    }
}
check("P9 cues(.subtitles) equals CaptionCues.build, with no words, for both engines",
      p9, "\(CaptionCues.build(from: fixed, frame: frame, clip: 7).count) cues")

// MARK: - P11 two abutting spans

let middle = fixed.count / 2
let cut = fixed[middle].start + 160_000
var p11: [String] = []
for engine in TranscriptionEngine.allCases {
    for style in wordStyles {
        let request = CaptionPages.Request(style: style, canvas: canvases[0])
        let before = CaptionPages.build(
            from: fixed.filter { $0.start < cut }, span: 0 ..< cut, frame: frame,
            request: request, engine: engine)
        let after = CaptionPages.build(
            from: fixed.filter { $0.start >= cut }, span: cut ..< span.upperBound, frame: frame,
            request: request, engine: engine)
        let name = "\(engine.rawValue)/\(style.rawValue)"
        if before.contains(where: { $0.start < 0 || $0.end > cut }) {
            p11.append("\(name): a page of A leaves [0, T]: \(before.last.map { "\($0.start)…\($0.end)" } ?? "")")
        }
        if after.contains(where: { $0.start < cut || $0.end > span.upperBound }) {
            p11.append("\(name): a page of B leaves [T, end]")
        }
        if let a = before.last, let b = after.first, a.end > b.start {
            p11.append("\(name): A ends \(a.end) after B starts \(b.start)")
        }
        let crossed = before.last?.words?.last
        let enters = after.first?.words?.first
        switch engine {
        case .apple:
            if crossed?.start != cut - frame || crossed?.end != cut {
                p11.append("\(name): the word that crossed T is \(String(describing: crossed))")
            }
        case .assemblyai:
            if enters?.start != cut {
                p11.append("\(name): B's first word is \(String(describing: enters))")
            }
        }
    }
}
check("P11 two abutting spans: every page within its own, A ends by B's start, the crossing "
      + "word on A's last frame (apple) and B's first word at T (assemblyai)",
      p11.isEmpty, "T = \(cut) (word \(middle) raw \(fixed[middle].start)…\(fixed[middle].end)); "
        + "\(p11.prefix(4))")

// MARK: - P12 an unpunctuated gap of breakGap or more closes a page

let lead = CaptionPages.lead(for: .apple)
let gap = zip(fixed, fixed.dropFirst()).first {
    $1.start - $0.end >= rules.breakGap && !endsWith($0.text, ".?!…")
}
var p12: [String] = []
for b in built {
    for page in b.pages {
        let starts = Set(page.map(\.start))
        if let (before, after) = gap, starts.contains(before.start + lead),
           starts.contains(after.start + lead)
        {
            p12.append("\(label(b)) \"\(page.map(\.text).joined(separator: " "))\"")
        }
    }
}
check("P12 a ≥ 0.25 s unpunctuated gap closes a page (no page holds both of its words)",
      gap != nil && p12.isEmpty,
      "gap \(gap.map { "\"\($0.0.text) | \($0.1.text)\" \($0.1.start - $0.0.end)" } ?? "none"); "
        + "\(p12.prefix(4))")

// MARK: - P10 the pause measurement, on the engine itself

let pause = pauseMeasurement(
    URL(fileURLWithPath: CommandLine.arguments[3]), frame: frame, canvas: canvases[0])
if let row = pause.row {
    check("P10 gap + punctuation pages break at both of the pangram's pauses", row.ok, row.detail)
}
let p10 = pause.p10

let out: [String: Any] = [
    "ok": true, "registered": registered, "fixed_words": fixed.count, "rows": rows, "p10": p10,
    "pages": built.map { ["label": label($0), "texts": $0.cues.map(\.text)] },
]
let data = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
exit(0)
