// Road map 8, W3 — the word-caption picture's app-side probe.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — so it measures the
// renderer's own code: `measuredSize`, `layout(for:)`, `drawWords`,
// `renderTextBitmap`, `wordHeadroom`, `laidContent`, `contentEdit` and
// `InspectorBinding.contentOps`. It MEASURES and prints one JSON object;
// `words_picture_probe.py` scores it.
//
//   words_picture_probe <app_fonts_dir>
//
// Fonts are registered at `.process` scope first (`text_probe.swift`'s loop):
// a bare Mach-O has no `ATSApplicationFontsPath`.
import AppKit
import CoreText
import Metal

func wpRegister(_ directory: String) -> Int {
    let url = URL(fileURLWithPath: directory)
    let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    var count = 0
    for name in names.sorted() where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
        var error: Unmanaged<CFError>?
        let one = url.appendingPathComponent(name) as CFURL
        if CTFontManagerRegisterFontsForURL(one, .process, &error) { count += 1 }
    }
    return count
}

/// Ink bounds of a premultiplied BGRA context — `text_probe.swift`'s — over
/// the pixels `keep` accepts (b, g, r, a). x is CoreGraphics x; rows are the
/// context's memory rows.
func wpInk(_ context: CGContext, _ keep: (UInt8, UInt8, UInt8, UInt8) -> Bool) -> CGRect? {
    guard let data = context.data else { return nil }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    for y in 0..<context.height {
        let row = bytes + y * context.bytesPerRow
        for x in 0..<context.width {
            let p = row + x * 4
            guard keep(p[0], p[1], p[2], p[3]) else { continue }
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func wpAny(_ b: UInt8, _ g: UInt8, _ r: UInt8, _ a: UInt8) -> Bool { a > 0 }
/// Red ink: a strongly red, nearly opaque pixel. The base colour is white and
/// the outline black, so neither passes.
func wpRed(_ b: UInt8, _ g: UInt8, _ r: UInt8, _ a: UInt8) -> Bool {
    a > 200 && r > 160 && g < 70 && b < 70
}

func wpBytes(_ context: CGContext?) -> Data? {
    guard let context, let data = context.data else { return nil }
    return Data(bytes: data, count: context.bytesPerRow * context.height)
}

func wpRect(_ rect: CGRect?) -> Any {
    guard let rect else { return NSNull() }
    return [Double(rect.minX), Double(rect.minY), Double(rect.maxX), Double(rect.maxY)]
}

let wpPill = ActivePill()
let wpRedColor: RGBA = [1, 0, 0, 1]

func wpPage(
    _ content: String, face: String, size: Double, style: WordStyle?, width: Double? = nil,
    words: Int? = nil, textCase: TextCase = .upper, valign: String = "middle"
) -> TextProps {
    let timed = (0..<(words ?? 0)).map { TextWord(start: Ticks($0) * 60_000, end: 0) }
    return TextProps(
        content: content, font: face, size: size, color: [1, 1, 1, 1], valign: valign,
        outline: OutlineProps(width: size * 0.08, color: [0, 0, 0, 1]), width: width,
        textCase: textCase, words: timed, wordStyle: style)
}

guard CommandLine.arguments.count >= 2, let device = MTLCreateSystemDefaultDevice() else {
    print(#"{"ok":false,"error":"usage: words_picture_probe <app_fonts_dir>, and a Metal device"}"#)
    exit(1)
}
let registered = wpRegister(CommandLine.arguments[1])
let renderers = LayerRenderers(device: device)
var out: [String: Any] = ["registered": registered]
let faces = ["Montserrat-ExtraBold", "Montserrat-Black", "Anton-Regular", "BebasNeue-Regular"]
let pops: [Double] = [0, 0.3, 0.58, 1]
let pageText = "this is how it looks, extraordinary"

// MARK: P1, P2 — the box at every word and pop, and no ink outside it

var boxes: [[String: Any]] = []
/// One page of the P1/P2 loop, drawn at every word and pop in six layouts
/// (one line and wrapped, valign middle, top and bottom).
func wpMeasure(
    _ base: TextProps, style: WordStyle, canvas: (Int, Int), label: String, scale: Double
) {
    let (canvasW, canvasH) = canvas
    let size = base.size
    for (width, valign) in [nil, Double(canvasW) * 0.5].flatMap({ w in
        ["middle", "top", "bottom"].map { (w, $0) } }) as [(Double?, String)] {
        let props = TextProps(
            content: base.content, font: base.font, size: base.size, color: base.color,
            valign: valign, outline: base.outline, width: width, textCase: base.textCase,
            words: base.words, wordStyle: style)
        let box = LayerRenderers.measuredSize(for: props)
        let layout = LayerRenderers.layout(for: props)
        let count = props.tokenCount
        var sizes: Set<String> = []
        var worst: [String: Double] = ["l": 0, "r": 0, "b": 0, "t": 0]
        let margin = CGFloat(size) * 2
        for word in 0...count {
            for pop in pops {
                let reveal = RecipeReveal(word: word, wordPop: word == 0 ? nil : pop)
                if let bitmap = renderers.renderTextBitmap(props, reveal: reveal) {
                    sizes.insert("\(bitmap.width)x\(bitmap.height)")
                }
                guard word > 0, let big = LayerRenderers.bitmap(CGSize(
                    width: box.width + margin * 2, height: box.height + margin * 2))
                else { continue }
                big.translateBy(x: margin, y: margin)
                LayerRenderers.drawWords(
                    layout, of: props, style: style, word: word, pop: pop, in: big)
                guard let ink = wpInk(big, wpAny) else { continue }
                // Memory row 0 is the TOP; CG y is up, so rows map to t/b.
                worst["l"] = max(worst["l"] ?? 0, Double(margin - ink.minX))
                worst["r"] = max(worst["r"] ?? 0, Double(ink.maxX - (margin + box.width)))
                worst["t"] = max(worst["t"] ?? 0, Double(margin - ink.minY))
                worst["b"] = max(worst["b"] ?? 0, Double(ink.maxY - (margin + box.height)))
            }
        }
        boxes.append([
            "canvas": "\(canvasW)x\(canvasH)", "face": base.font, "scale": scale,
            "config": label, "wrapped": width != nil, "valign": valign,
            "lines": layout.lines.count, "measured": "\(Int(box.width))x\(Int(box.height))",
            "bitmap_sizes": Array(sizes).sorted(), "overflow_px": worst,
        ])
    }
}

for (canvasW, canvasH) in [(1080, 1920), (1920, 1080)] {
    let size = (0.075 * Double(min(canvasW, canvasH))).rounded()
    for face in faces {
        // (1.15, pill), (1.5, pill) and — W4a, the review's nit 3 — (1.5, NO
        // pill): without a pill the width term is `(peak − 1) × widest / 2 −
        // outline`, and every word style of §5h but Pill pops without one.
        for (scale, pill, label) in [
            (1.15, wpPill, "pill"), (1.5, wpPill, "pill"), (1.5, nil, "no pill"),
        ] as [(Double, ActivePill?, String)] {
            let style = WordStyle(activeColor: [1, 0.85, 0, 1], activeScale: scale, activePill: pill)
            wpMeasure(
                wpPage(pageText, face: face, size: size, style: style), style: style,
                canvas: (canvasW, canvasH), label: label, scale: scale)
        }
    }
    // Each §5h word style's OWN face, case, outline, scale and pill, at its
    // own size (`CaptionStyle`, W4a).
    for caption in CaptionStyle.allCases where caption.isWordStyle {
        guard let style = caption.wordStyle else { continue }
        let canvas = CGSize(width: canvasW, height: canvasH)
        wpMeasure(
            caption.textProps(content: pageText, size: caption.size(for: canvas), width: nil),
            style: style, canvas: (canvasW, canvasH), label: caption.rawValue,
            scale: style.activeScale)
    }
}
out["boxes"] = boxes

// MARK: P3 — the word changes the picture; build word 0 has no ink

let highlight = wpPage(
    pageText, face: "Montserrat-Black", size: 81,
    style: WordStyle(activeColor: [1, 0.85, 0, 1], activeScale: 1.15, activePill: wpPill))
let one = wpBytes(renderers.renderTextBitmap(highlight, reveal: RecipeReveal(word: 1, wordPop: 1)))
let two = wpBytes(renderers.renderTextBitmap(highlight, reveal: RecipeReveal(word: 2, wordPop: 1)))
let build = wpPage(
    pageText, face: "Montserrat-Black", size: 81,
    style: WordStyle(mode: .build, activeScale: 1.15, activePill: wpPill))
let buildZero = renderers.renderTextBitmap(build, reveal: RecipeReveal(word: 0))
out["p3"] = [
    "word1_ne_word2": one != nil && two != nil && one != two,
    "build_word0_ink": buildZero.map { wpRect(wpInk($0, wpAny)) } ?? "no bitmap",
    "build_word1_ink": renderers.renderTextBitmap(build, reveal: RecipeReveal(word: 1, wordPop: 1))
        .map { wpRect(wpInk($0, wpAny)) } ?? "no bitmap",
]

// MARK: P4 — case, and the red word's extents on the LAID line

let strasse = wpPage(
    "straße ist", face: "Montserrat-Black", size: 81, style: WordStyle(activeColor: wpRedColor))
let laid = LayerRenderers.layout(for: strasse)
let laidTokens = LayerRenderers.tokens(of: "STRASSE IST")
var p4: [String: Any] = [
    "laid_upper": strasse.laidContent,
    "laid_as_written": wpPage("straße ist", face: "x", size: 1, style: nil, textCase: .asWritten)
        .laidContent,
]
if let line = laid.lines.first, laidTokens.count == 2 {
    p4["midpoint"] = Double(
        LayerRenderers.midpoint(line, laidTokens[0].upperBound, laidTokens[1].lowerBound))
    // The reference width is the probe's OWN "STRASSE", never `laidContent`.
    var reference = LayerRenderers.attributedString(strasse).attributes(at: 0, effectiveRange: nil)
    reference.removeValue(forKey: .paragraphStyle)
    let ctLine = CTLineCreateWithAttributedString(
        NSAttributedString(string: "STRASSE", attributes: reference))
    p4["strasse_width"] = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
}
for word in [1, 2] {
    let bitmap = renderers.renderTextBitmap(strasse, reveal: RecipeReveal(word: word))
    p4["red_word\(word)"] = bitmap.map { wpRect(wpInk($0, wpRed)) } ?? "no bitmap"
}
out["p4"] = p4

// MARK: P5 — each face resolves to itself, not the fallback, and names its file

let fallback = CTFontCopyPostScriptName(
    CTFontCreateWithName("NoSuchFont-Black" as CFString, 81, nil)) as String
out["p5"] = faces.map { face -> [String: Any] in
    let font = CTFontCreateWithName(face as CFString, 81, nil)
    let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL
    return [
        "face": face, "postscript": CTFontCopyPostScriptName(font) as String,
        "fallback": fallback, "file": url?.path ?? "",
    ]
}

// MARK: P6 — the Content write, per clip

func wpTimed(_ n: Int) -> TextProps {
    TextProps(
        content: Array(repeating: "w", count: n).joined(separator: " "),
        words: (0..<n).map { TextWord(start: Ticks($0), end: Ticks($0)) })
}
func wpOps(_ ops: [ReelOp]) -> [[String: Any]] {
    ops.map { ["name": $0.name, "json": $0.json] }
}
let three = "a b c"
out["p6"] = [
    "untimed_keeps": TextPatch.contentEdit(three, over: TextProps(content: "x")).words == nil,
    "agree_keeps": TextPatch.contentEdit(three, over: wpTimed(3)).words == nil,
    "mismatch_clears": TextPatch.contentEdit(three, over: wpTimed(5)).words == [],
    "a": wpOps(InspectorBinding.contentOps(three, over: [
        .init(id: 1, props: wpTimed(3), action: nil), .init(id: 2, props: wpTimed(5), action: nil),
    ])),
    "b": wpOps(InspectorBinding.contentOps(three, over: [
        .init(id: 1, props: wpTimed(5), action: 7),
    ])),
    "c": wpOps(InspectorBinding.contentOps(three, over: [
        .init(id: 1, props: wpTimed(5), action: nil), .init(id: 2, props: wpTimed(5), action: 7),
    ])),
]

// MARK: P7, P8 — the headroom rule, and `words` out of the box

let em = 81.0
let colourOnly = wpPage(pageText, face: "Montserrat-Black", size: em,
                        style: WordStyle(activeColor: wpRedColor))
let pop115 = wpPage(pageText, face: "Montserrat-Black", size: em,
                    style: WordStyle(activeScale: 1.15, activePill: wpPill))
let pop150 = wpPage(pageText, face: "Montserrat-Black", size: em,
                    style: WordStyle(activeScale: 1.5, activePill: wpPill))
let metrics = LayerRenderers.wordMetrics(pop150)
let peak = 1 + 0.5 * 1.1
let outline = em * 0.08
let edge = Double(LayerRenderers.wordHeadroomEdgePx)
let edgeV = Double(LayerRenderers.wordHeadroomVerticalEdgePx)
let formulaW = peak * 0.2 * em + (peak - 1) * Double(metrics.widest) / 2 - outline + edge
let formulaH = peak * 0.2 * em + (peak - 1) * Double(metrics.ascent + metrics.descent) / 2
    - outline + edgeV
func wpSize(_ s: CGSize) -> [Double] { [Double(s.width), Double(s.height)] }
out["p7"] = [
    "em": em, "colour_only": wpSize(LayerRenderers.wordHeadroom(for: colourOnly)),
    "pop115": wpSize(LayerRenderers.wordHeadroom(for: pop115)),
    "pop150": wpSize(LayerRenderers.wordHeadroom(for: pop150)),
    "formula150": [formulaW, formulaH],
]
let untimedPop = wpPage(pageText, face: "Montserrat-Black", size: em,
                        style: WordStyle(activeScale: 1.5, activePill: wpPill), words: 0)
let timedPop = wpPage(pageText, face: "Montserrat-Black", size: em,
                      style: WordStyle(activeScale: 1.5, activePill: wpPill),
                      words: untimedPop.tokenCount)
out["p8"] = [
    "with": wpSize(LayerRenderers.measuredSize(for: timedPop)),
    "without": wpSize(LayerRenderers.measuredSize(for: untimedPop)),
]

// MARK: P9 — the pop scales the clip with the token

let long = wpPage(
    "a extraordinarily b", face: "Montserrat-Black", size: em,
    style: WordStyle(activeColor: wpRedColor, activeScale: 1.5))
var p9: [String: Any] = [:]
for pop in [0.0, 1.0] {
    let bitmap = renderers.renderTextBitmap(long, reveal: RecipeReveal(word: 2, wordPop: pop))
    p9["red_pop\(Int(pop))"] = bitmap.map { wpRect(wpInk($0, wpRed)) } ?? "no bitmap"
}
p9["word_em"] = Double(LayerRenderers.wordMetrics(long).widest) / em
out["p9"] = p9

out["ok"] = true
let data = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
exit(0)
