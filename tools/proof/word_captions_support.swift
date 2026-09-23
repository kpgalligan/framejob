// Road map 8, W4a — the pager probe's support file, compiled beside
// `word_captions_probe.swift` (the `main.swift`) over `app/Sources` by
// `word_captions_probe.py`: the probe's OWN width measurement, which never
// goes through `CaptionPages.fits`, the rules' forced breaks read off two
// pages, and P10's pause measurement on the engine itself.
import AVFoundation
import AppKit
import CoreText

func register(_ directory: String) -> Int {
    let url = URL(fileURLWithPath: directory)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    var count = 0
    for name in names.sorted() where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(
            url.appendingPathComponent(name) as CFURL, .process, &error)
        {
            count += 1
        }
    }
    return count
}

// MARK: - The probe's OWN measurement

func measured(_ line: String, _ style: CaptionStyle, _ size: Double) -> Double {
    Double(LayerRenderers.measuredSize(
        for: style.textProps(content: line, size: size, width: nil)).width)
}

/// The greedy lines the style allows, by the probe's own measurement: nil
/// when a multi-word page does not lay within `budget`.
func layLines(_ tokens: [String], _ style: CaptionStyle, _ size: Double, _ budget: Double)
    -> [String]?
{
    var lines: [[String]] = []
    for token in tokens {
        if var last = lines.last {
            last.append(token)
            if measured(last.joined(separator: " "), style, size) <= budget {
                lines[lines.count - 1] = last
                continue
            }
            guard lines.count < style.maxLines else { return nil }
        }
        if tokens.count > 1, measured(token, style, size) > budget { return nil }
        lines.append([token])
    }
    return lines.map { $0.joined(separator: " ") }
}

func pageWidth(_ tokens: [String], _ style: CaptionStyle, _ size: Double, _ budget: Double)
    -> Double
{
    (layLines(tokens, style, size, budget) ?? [tokens.joined(separator: " ")])
        .map { measured($0, style, size) }.max() ?? 0
}

func endsWith(_ text: String, _ marks: String) -> Bool {
    guard let last = text.last else { return false }
    return marks.contains(last)
}

/// The rules' own forced breaks between page A and the page B after it.
func forced(_ a: [CaptionCues.Word], _ b: [CaptionCues.Word], _ style: CaptionStyle) -> Bool {
    let rules = CaptionPages.Rules.standard
    guard let last = a.last, let first = b.first, let head = a.first else { return true }
    return first.speaker != last.speaker || first.start - last.end >= rules.breakGap
        || endsWith(last.text, ".?!…") || first.end - head.start > rules.maxLength
        || a.count >= (style.maxWords ?? Int.max)
}

/// One style's pages on one canvas, with the base size and the budget.
struct Built {
    let style: CaptionStyle
    let canvas: CGSize
    let cues: [CaptionLayout.Cue]
    var base: Double { style.size(for: canvas) }
    var budget: Double { CaptionPages.Rules.standard.widthBudget * Double(canvas.width) }
    var pages: [[CaptionCues.Word]] { cues.map { $0.words ?? [] } }
    var label: String { "\(style.rawValue)@\(Int(canvas.width))x\(Int(canvas.height))" }
}

// MARK: - P10 the pause measurement, on the engine itself

/// `body` on a thread of its own — `SpeechEngine.transcribe` refuses main.
func offMain<T>(_ bound: Double, _ body: @escaping () -> T) -> T? {
    let lock = NSLock()
    var answer: T?
    var done = false
    let thread = Thread {
        let value = body()
        lock.lock()
        answer = value
        done = true
        lock.unlock()
    }
    thread.stackSize = 8 << 20
    thread.start()
    let deadline = Date().addingTimeInterval(bound)
    while Date() < deadline {
        lock.lock()
        let finished = done
        let value = answer
        lock.unlock()
        if finished { return value }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return nil
}

/// P10: the pangram through `SpeechEngine`, paged (a) by gap and punctuation
/// and (b) with road map 4's two detector pauses as forced breaks. Nil for
/// the row when en-US is not installed or the pangram will not open.
func pauseMeasurement(_ pangram: URL, frame: Ticks, canvas: CGSize)
    -> (row: (ok: Bool, detail: String)?, p10: [String: Any])
{
    let pauses: [(Double, Double)] = [(2.72, 4.29), (6.68, 7.81)]
    let english = Locale(identifier: "en-US")
    guard let file = try? AVAudioFile(forReading: pangram),
          SpeechEngine.isInstalled(english) == true
    else {
        return (nil, ["ran": false,
                      "skip": "en-US is not installed on this host, or the pangram would not open"])
    }
    let seconds = Double(file.length) / file.processingFormat.sampleRate
    let runs = offMain(120) {
        try? SpeechEngine.transcribe(
            file: pangram, locale: english, seconds: seconds, name: "pangram",
            cancel: Transcriber.CancelToken(), progress: { _ in })
    } ?? nil
    let words = (runs ?? []).map {
        CaptionCues.Word(text: $0.text, start: ReelTime.ticks(seconds: $0.start),
                         end: ReelTime.ticks(seconds: $0.end))
    }
    let whole: Range<Ticks> = 0 ..< ReelTime.ticks(seconds: seconds)
    let request = CaptionPages.Request(style: .highlight, canvas: canvas)
    func texts(_ cues: [CaptionLayout.Cue]) -> [String] { cues.map(\.text) }
    func boundaries(_ cues: [CaptionLayout.Cue]) -> Set<Int> {
        var total = 0
        var out: Set<Int> = []
        for cue in cues {
            total += cue.words?.count ?? 0
            out.insert(total)
        }
        return out
    }
    // (a) gap + punctuation, as built.
    let plain = CaptionPages.build(
        from: words, span: whole, frame: frame, request: request, engine: .apple)
    // (b) road map 4's two detector pauses injected as forced breaks: the
    // words split before the first one starting inside each pause.
    let cuts = pauses.map { pause in
        words.firstIndex { $0.start >= ReelTime.ticks(seconds: pause.0) } ?? words.count
    }
    var segments: [[CaptionCues.Word]] = []
    var from = 0
    for index in cuts + [words.count] where index >= from {
        segments.append(Array(words[from..<index]))
        from = index
    }
    let detected = segments.flatMap {
        CaptionPages.build(from: $0, span: whole, frame: frame, request: request, engine: .apple)
    }
    let plainBreaks = boundaries(plain)
    let gaps = cuts.map { index -> Double in
        guard index > 0, index < words.count else { return -1 }
        return ReelTime.seconds(words[index].start - words[index - 1].end)
    }
    let context = cuts.map { index -> String in
        guard index > 0, index < words.count else { return "" }
        return "\(words[index - 1].text) | \(words[index].text)"
    }
    let brokeBoth = !words.isEmpty && cuts.allSatisfy { plainBreaks.contains($0) }
    let p10: [String: Any] = [
        "ran": true, "words": words.count, "gaps_s": gaps, "at": context,
        "plain": texts(plain), "detector": texts(detected),
        "detector_changes_pages": texts(plain) != texts(detected),
        "largest_gap_s": zip(words, words.dropFirst())
            .map { ReelTime.seconds($1.start - $0.end) }.max() ?? 0,
    ]
    return ((brokeBoth, "\(words.count) words; the gaps at the pauses \(gaps) s at \(context); "
            + "the detector's breaks change the pages: \(texts(plain) != texts(detected))"), p10)
}
