// Road map 8, W3 — the word-caption picture's app-side probe.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — so it measures the
// renderer's own code: `measuredSize`, `layout(for:)`, `drawWords`,
// `renderTextBitmap`, `wordHeadroom`, `laidContent`, `contentEdit` and
// `InspectorBinding.contentOps`, and (issue batch B86, P10) `text(_:hash:reveal:)`
// timed on a cache miss. It MEASURES and prints one JSON object;
// `words_picture_probe.py` scores it.
//
//   words_picture_probe <app_fonts_dir> [--quick]
//
// `--quick` stops after P10, the looks' geometry (P11–P17), where the dim is
// drawn (P18, P19) and the backdrop's bytes (P20), which are measured first:
// before the P1/P2 sweep, ten minutes of pixel scans. It is how P10 is run
// alone.
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
func wpInk(
    _ context: CGContext, rows: Range<Int>? = nil, _ keep: (UInt8, UInt8, UInt8, UInt8) -> Bool
) -> CGRect? {
    guard let data = context.data else { return nil }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    for y in (rows ?? 0..<context.height).clamped(to: 0..<context.height) {
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
/// Blue ink, as `wpRed` is red.
func wpBlue(_ b: UInt8, _ g: UInt8, _ r: UInt8, _ a: UInt8) -> Bool {
    a > 200 && b > 160 && r < 70 && g < 70
}
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
let wpQuick = CommandLine.arguments.dropFirst(2).contains("--quick")
var out: [String: Any] = ["registered": registered, "quick": wpQuick]

/// Prints the one JSON object and ends the probe.
func wpFinish(_ out: [String: Any]) -> Never {
    var answer = out
    answer["ok"] = true
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data()
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

/// The host's power state, which a millisecond budget depends on: macOS
/// slows the processor in Low Power Mode and under thermal pressure, so
/// `words_picture_probe.py` does not JUDGE P10's medians when either holds.
func wpPower() -> [String: Any] {
    let info = ProcessInfo.processInfo
    let names = ["nominal", "fair", "serious", "critical"]
    let state = info.thermalState.rawValue
    return [
        "low_power": info.isLowPowerModeEnabled, "thermal_state": state,
        "thermal": names.indices.contains(state) ? names[state] : "unknown (\(state))",
    ]
}
let faces = ["Montserrat-ExtraBold", "Montserrat-Black", "Anton-Regular", "BebasNeue-Regular"]
let pops: [Double] = [0, 0.3, 0.58, 1]
let pageText = "this is how it looks, extraordinary"

// MARK: P10 — what a fill, a dim and a glide cost on a cache miss

/// The spike's q5 method (`words_spike/text_probe.swift`): `text(_:hash:reveal:)`
/// under a hash no call has used — a cache miss, so a raster and an upload —
/// one untimed warm-up (it pays the face's first raster and the layout,
/// which IS cached), then the median of 20. Measured FIRST, before the P1/P2
/// sweep has run the machine hot for ten minutes: a budget is about a frame
/// of playback, not about the end of this probe.
///
/// The page is the HIGHLIGHT preset's own (`CaptionStyle.highlight`:
/// Montserrat-Black at 0.075 × min(w, h), upper case, its outline, its pop),
/// so `pop` is a shipped picture; the glide adds the default pill, which
/// Highlight does not have. A look's reveal carries `wordPop` 1, as the
/// recipe does once the pop has settled. Every page is ONE line (`width`
/// nil), where a generated page is cut to its style's width. The host's
/// power state is read before the first raster and after the last.
func wpMedian(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return .nan }
    let middle = sorted.count / 2
    return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

/// One of P10's rasters: a preset's page of `content` on one line, the look
/// laid over the preset's own word style, and whether the scorer holds its
/// median to the budget.
struct WpRaster {
    let label: String
    let caption: CaptionStyle
    let content: String
    let word: Int
    let pop: Double
    let pill: ActivePill?
    let fill: Bool
    let dim: Bool
    let glide: Bool
    let scored: Bool
    /// The page is the PAGER's own first page of `content`
    /// (`CaptionPages.samplePage`): its text, its size and its wrap `width`,
    /// the active word its last. False lays `content` on one line.
    var paged = false
    /// The page's backdrop, which no caption style writes: nil for a preset's
    /// own page. With one, the dim is the bitmap's (spec §11 W-16).
    var backdrop: BackdropProps? = nil
}

/// The paged case's words: `karaokeText`'s tokens, one every 0.12 s and 0.1 s
/// long — no pause, no sentence mark and 3 s away from the page's time limit,
/// so the WIDTH is what closes the page, on Karaoke's second line.
let karaokeText = "this is how it looks when a karaoke page runs onto its second line and keeps "
    + "going until the pager closes it for good measure"
func wpPagerPage(_ caption: CaptionStyle, _ content: String, _ canvas: CGSize) -> CaptionLayout.Cue? {
    let words = content.split(separator: " ").enumerated().map { index, token in
        CaptionCues.Word(
            text: String(token), start: Ticks(index) * 72_000, end: Ticks(index) * 72_000 + 60_000)
    }
    return CaptionPages.samplePage(
        words, request: CaptionPages.Request(style: caption, canvas: canvas), frame: 20_000)
}

/// Highlight's four are the page P10 has always timed. One Word's (size
/// 0.12 × min(w, h), where Highlight's is 0.075) is the largest type a
/// preset ships. `oneword-page fill+dim` is the page One Word generates —
/// ONE word (`CaptionStyle.maxWords`), the text's longest — and it is scored.
/// `oneword-line fill+dim (hand-made)` is the same six words on one line in
/// that style: a page no preset makes and `set_text` can write, P10's largest
/// box, and SCORED since issue batch B86 phase 3 — with no backdrop its dim
/// is the compositor's (spec §11 W-16), so it is a page like the others.
/// `karaoke-2line fill+dim` (issue batch B86 phase 2, where the sheet's Dim
/// first reaches every word style) is the page Karaoke's PAGER makes — the
/// one preset page of two lines, with partial-alpha upcoming ink — its last
/// word half filled and the page half-way into its dim, which is a generated
/// page's tail. Scored, under the same budgets.
///
/// Phase 3's five, after those seven so the seven keep their order. Three
/// TWINS, printed and never scored: `oneword-page fill`, `oneword-line fill
/// (hand-made)` and `karaoke-2line fill` are their pages with `dim` false,
/// what a `… fill+dim` median is read against on the same run (Highlight's
/// `fill` is `fill+dim`'s). And the page with a BACKDROP, where the dim is
/// still the bitmap's: `karaoke-2line-backdrop fill (hand-made)` and
/// `karaoke-2line-backdrop fill+dim (hand-made)` are the pager's Karaoke page
/// with `BackdropProps()` — what the inspector's Backdrop switch writes; no
/// caption style writes one — SCORED since issue batch B93 phase 3, which
/// drew its words first, its dim as one multiply and its backdrop under them
/// (spec §11 W-17).
let wpRasters: [WpRaster] = [
    WpRaster(
        label: "pop", caption: .highlight, content: pageText, word: 3, pop: 0.5, pill: nil,
        fill: false, dim: false, glide: false, scored: false),
    WpRaster(
        label: "fill", caption: .highlight, content: pageText, word: 3, pop: 1, pill: nil,
        fill: true, dim: false, glide: false, scored: true),
    WpRaster(
        label: "fill+dim", caption: .highlight, content: pageText, word: 3, pop: 1, pill: nil,
        fill: true, dim: true, glide: false, scored: true),
    WpRaster(
        label: "glide", caption: .highlight, content: pageText, word: 3, pop: 1,
        pill: ActivePill(glide: true), fill: false, dim: false, glide: true, scored: true),
    WpRaster(
        label: "oneword-page fill+dim", caption: .oneWord, content: "extraordinary", word: 1,
        pop: 1, pill: nil, fill: true, dim: true, glide: false, scored: true),
    WpRaster(
        label: "oneword-line fill+dim (hand-made)", caption: .oneWord, content: pageText,
        word: 3, pop: 1, pill: nil, fill: true, dim: true, glide: false, scored: true),
    WpRaster(
        label: "karaoke-2line fill+dim", caption: .karaoke, content: karaokeText, word: 0,
        pop: 1, pill: nil, fill: true, dim: true, glide: false, scored: true, paged: true),
    WpRaster(
        label: "oneword-page fill", caption: .oneWord, content: "extraordinary", word: 1,
        pop: 1, pill: nil, fill: true, dim: false, glide: false, scored: false),
    WpRaster(
        label: "oneword-line fill (hand-made)", caption: .oneWord, content: pageText,
        word: 3, pop: 1, pill: nil, fill: true, dim: false, glide: false, scored: false),
    WpRaster(
        label: "karaoke-2line fill", caption: .karaoke, content: karaokeText, word: 0,
        pop: 1, pill: nil, fill: true, dim: false, glide: false, scored: false, paged: true),
    WpRaster(
        label: "karaoke-2line-backdrop fill (hand-made)", caption: .karaoke,
        content: karaokeText, word: 0, pop: 1, pill: nil, fill: true, dim: false, glide: false,
        scored: true, paged: true, backdrop: BackdropProps()),
    WpRaster(
        label: "karaoke-2line-backdrop fill+dim (hand-made)", caption: .karaoke,
        content: karaokeText, word: 0, pop: 1, pill: nil, fill: true, dim: true, glide: false,
        scored: true, paged: true, backdrop: BackdropProps()),
]

var p10: [[String: Any]] = []
let wpPowerBefore = wpPower()
for (canvasW, canvasH) in [(1080, 1920), (3840, 2160)] {
    let canvas = CGSize(width: canvasW, height: canvasH)
    for raster in wpRasters {
        let caption = raster.caption
        let shipped = caption.wordStyle ?? WordStyle()
        let wordStyle = WordStyle(
            mode: shipped.mode, activeColor: shipped.activeColor,
            activeScale: shipped.activeScale, activePill: raster.pill,
            spokenColor: shipped.spokenColor, upcomingColor: shipped.upcomingColor,
            activeFill: raster.fill, pauseDim: raster.dim ? 0.5 : 0)
        var page = caption.textProps(
            content: raster.content, size: caption.size(for: canvas), width: nil)
        var active = raster.word
        if raster.paged, let cue = wpPagerPage(caption, raster.content, canvas) {
            page = caption.textProps(
                content: cue.text, size: cue.size ?? caption.size(for: canvas), width: cue.width)
            active = page.tokenCount
        }
        let reveal = RecipeReveal(
            word: active, wordPop: raster.pop, wordGlide: raster.glide ? 0.5 : nil,
            wordFill: raster.fill ? 0.5 : nil, wordDim: raster.dim ? 0.5 : nil)
        let props = TextProps(
            content: page.content, font: page.font, size: page.size, color: page.color,
            align: page.align, valign: page.valign, outline: page.outline,
            backdrop: raster.backdrop, width: page.width, textCase: page.textCase,
            wordStyle: wordStyle)
        let key = "p10-\(canvasW)-\(raster.label)"
        let warm = renderers.text(props, hash: key + "-warm", reveal: reveal)
        var milliseconds: [Double] = []
        for step in 0..<20 {
            let began = Date()
            _ = renderers.text(props, hash: key + "-\(step)", reveal: reveal)
            milliseconds.append(Date().timeIntervalSince(began) * 1000)
        }
        let box = LayerRenderers.measuredSize(for: props)
        // How many lines the page was laid on: its box against one line's in
        // the same style and size, under the same backdrop.
        let single = caption.textProps(content: "x", size: page.size, width: nil)
        let oneLine = LayerRenderers.measuredSize(
            for: TextProps(
                content: single.content, font: single.font, size: single.size,
                color: single.color, align: single.align, valign: single.valign,
                outline: single.outline, backdrop: raster.backdrop, width: single.width,
                textCase: single.textCase))
        let lines = oneLine.height > 0 ? Int((box.height / oneLine.height).rounded()) : 0
        p10.append([
            "canvas": "\(canvasW)x\(canvasH)", "case": raster.label, "drew": warm != nil,
            "scored": raster.scored, "box": "\(Int(box.width))x\(Int(box.height))",
            "lines": lines, "tokens": props.tokenCount, "word": active,
            "median_ms": wpMedian(milliseconds), "min_ms": milliseconds.min() ?? .nan,
            "max_ms": milliseconds.max() ?? .nan,
        ])
    }
}
out["p10"] = p10
out["power"] = ["before": wpPowerBefore, "after": wpPower()]

// MARK: P11–P16 — the looks' geometry (issue batch B86, spec §11 W-14)

// Every value the recipe would carry is set HERE, exactly, and the picture
// is `textBitmap`'s — the bitmap `renderText` uploads. Saturated inks and no
// outline (P15 aside), so a pixel names what drew it: the plate red, and in
// the fill rows the active ink red and the upcoming ink blue.
let wpGreenColor: RGBA = [0, 1, 0, 1]
let wpBlueColor: RGBA = [0, 0, 1, 1]
let wpGlidingPill = ActivePill(color: wpRedColor, glide: true)

func wpLookPage(
    _ content: String, style: WordStyle, width: Double? = nil, outline: OutlineProps? = nil
) -> TextProps {
    TextProps(
        content: content, font: "Montserrat-Black", size: 80, color: [1, 1, 1, 1],
        outline: outline, width: width, textCase: .upper, wordStyle: style)
}
func wpDraw(_ props: TextProps, _ reveal: RecipeReveal) -> CGContext? {
    LayerRenderers.textBitmap(props, reveal: reveal)
}
func wpRedRect(_ props: TextProps, _ reveal: RecipeReveal) -> Any {
    wpDraw(props, reveal).map { wpRect(wpInk($0, wpRed)) } ?? "no bitmap"
}
/// Whether two drawings are the same bytes.
func wpSame(_ a: CGContext?, _ b: CGContext?) -> Any {
    guard let first = wpBytes(a), let second = wpBytes(b) else { return "no bitmap" }
    return first == second
}
/// The lines token `index` of `props` has glyphs on.
func wpLines(_ props: TextProps, token index: Int) -> [Int] {
    let tokens = LayerRenderers.tokens(of: props.laidContent)
    guard tokens.indices.contains(index) else { return [] }
    let token = tokens[index]
    return LayerRenderers.layout(for: props).lines.enumerated().compactMap { place, laid in
        let line = laid.range.location..<(laid.range.location + laid.range.length)
        return token.lowerBound < line.upperBound && token.upperBound > line.lowerBound
            ? place : nil
    }
}

// P11 — the plate between two LINES: x, y and width all travel.
let wpTwoLines = wpLookPage("sun\nmoon", style: WordStyle(activePill: wpGlidingPill))
out["p11"] = [
    "lines": LayerRenderers.layout(for: wpTwoLines).lines.count,
    "from": wpRedRect(wpTwoLines, RecipeReveal(word: 1)),
    "to": wpRedRect(wpTwoLines, RecipeReveal(word: 2, wordGlide: 1)),
    "start": wpRedRect(wpTwoLines, RecipeReveal(word: 2, wordGlide: 0)),
    "half": wpRedRect(wpTwoLines, RecipeReveal(word: 2, wordGlide: 0.5)),
]

// P12 — the plate pops about its OWN centre.
let wpPopping = wpLookPage(
    "sun moon", style: WordStyle(activeScale: 1.5, activePill: wpGlidingPill))
out["p12"] = [
    "scale": 1.5,
    "flat": wpRedRect(wpPopping, RecipeReveal(word: 2, wordGlide: 0.5)),
    "popped": wpRedRect(wpPopping, RecipeReveal(word: 2, wordPop: 1, wordGlide: 0.5)),
]

// P13 — the one-piece condition: a token that wraps over two lines.
let wpWrapContent = "go mmmmmmmmmmmm on"
let wpWrapWidth = 500.0
let wpWrapped = wpLookPage(
    wpWrapContent, style: WordStyle(activePill: wpGlidingPill), width: wpWrapWidth)
out["p13"] = [
    "token_lines": wpLines(wpWrapped, token: 1).count,
    "onto_wrapped_same": wpSame(
        wpDraw(wpWrapped, RecipeReveal(word: 2, wordGlide: 0.5)),
        wpDraw(wpWrapped, RecipeReveal(word: 2, wordGlide: 1))),
    "off_wrapped_same": wpSame(
        wpDraw(wpWrapped, RecipeReveal(word: 3, wordGlide: 0.5)),
        wpDraw(wpWrapped, RecipeReveal(word: 3, wordGlide: 1))),
    "plate_on_wrapped": wpRedRect(wpWrapped, RecipeReveal(word: 2, wordGlide: 0.5)),
    "line_height": Double(LayerRenderers.layout(for: wpWrapped).lines.first?.height ?? 0),
    // The control: between two one-piece tokens the same two instants differ.
    "one_piece_same": wpSame(
        wpDraw(wpTwoLines, RecipeReveal(word: 2, wordGlide: 0.5)),
        wpDraw(wpTwoLines, RecipeReveal(word: 2, wordGlide: 1))),
]

// P14 — a wrapped token fills each piece by the same fraction.
let wpFilling = wpLookPage(
    wpWrapContent,
    style: WordStyle(activeColor: wpRedColor, upcomingColor: wpBlueColor, activeFill: true),
    width: wpWrapWidth)
var wpPieces: [[String: Any]] = []
if let full = wpDraw(wpFilling, RecipeReveal(word: 2, wordFill: 1)),
    let half = wpDraw(wpFilling, RecipeReveal(word: 2, wordFill: 0.5)) {
    let lines = LayerRenderers.layout(for: wpFilling).lines
    for index in wpLines(wpFilling, token: 1) {
        // The line's rows from its baseline up: memory row 0 is the TOP.
        let line = lines[index]
        let top = Int((CGFloat(full.height) - (line.origin.y + line.ascent)).rounded(.down))
        let bottom = Int((CGFloat(full.height) - line.origin.y).rounded(.up))
        let rows = max(top, 0)..<max(bottom, max(top, 0) + 1)
        wpPieces.append([
            "line": index, "full_red": wpRect(wpInk(full, rows: rows, wpRed)),
            "half_red": wpRect(wpInk(half, rows: rows, wpRed)),
            "half_blue": wpRect(wpInk(half, rows: rows, wpBlue)),
        ])
    }
}
out["p14"] = ["token_lines": wpLines(wpFilling, token: 1).count, "pieces": wpPieces]

// P15 — a FULL word is drawn whole: its outline's stroke reaches past the
// glyph range, and a build page draws nothing right of the fill's edge.
let wpOutlined = wpLookPage(
    "go mmmm", style: WordStyle(mode: .build, activeColor: wpRedColor, activeFill: true),
    outline: OutlineProps(width: 20, color: wpBlueColor))
let wpWhole = wpDraw(wpOutlined, RecipeReveal(word: 2))
let wpFullWord = wpDraw(wpOutlined, RecipeReveal(word: 2, wordFill: 1))
out["p15"] = [
    "full_same_as_unfilled": wpSame(wpFullWord, wpWhole),
    "half_same_as_unfilled": wpSame(
        wpDraw(wpOutlined, RecipeReveal(word: 2, wordFill: 0.5)), wpWhole),
    "ink_full": wpFullWord.map { wpRect(wpInk($0, wpAny)) } ?? "no bitmap",
    "ink_nearly": wpDraw(wpOutlined, RecipeReveal(word: 2, wordFill: 0.999))
        .map { wpRect(wpInk($0, wpAny)) } ?? "no bitmap",
]

// P16 — a value outside 0…1 draws as the nearest one inside (an action's end
// patch is not range-checked), and a full dim at `pause_dim` 1 draws nothing.
// Drawn through `drawWords` itself, the routine that clamps, into a bitmap of
// the page's own size: since spec §11 W-16 `textBitmap` hands a page with no
// backdrop no dim at all (P18), so it could not show the dim's clamp.
func wpClampStyle(_ pauseDim: Double) -> WordStyle {
    WordStyle(
        activeColor: wpRedColor, activePill: ActivePill(color: [1, 0, 1, 1], glide: true),
        spokenColor: wpGreenColor, upcomingColor: wpBlueColor, activeFill: true,
        pauseDim: pauseDim)
}
func wpClamped(
    pauseDim: Double = 0.5, fill: Double? = nil, glide: Double? = nil, dim: Double? = nil
) -> CGContext? {
    let style = wpClampStyle(pauseDim)
    let props = wpLookPage("sun moon star", style: style)
    let layout = LayerRenderers.layout(for: props)
    guard let context = LayerRenderers.bitmap(layout.size) else { return nil }
    LayerRenderers.drawWords(
        layout, of: props, style: style, word: 2, pop: nil, glide: glide, fill: fill, dim: dim,
        in: context)
    return context
}
let wpEqual: [(String, CGContext?, CGContext?)] = [
    ("fill -0.5 as 0", wpClamped(fill: -0.5), wpClamped(fill: 0)),
    ("fill 1.5 as 1", wpClamped(fill: 1.5), wpClamped(fill: 1)),
    ("glide -0.5 as 0", wpClamped(glide: -0.5), wpClamped(glide: 0)),
    ("glide 1.5 as 1", wpClamped(glide: 1.5), wpClamped(glide: 1)),
    ("dim 2 as 1", wpClamped(dim: 2), wpClamped(dim: 1)),
    ("dim -1 as 0", wpClamped(dim: -1), wpClamped(dim: 0)),
    ("pause_dim 2 as 1", wpClamped(pauseDim: 2, dim: 0.5), wpClamped(pauseDim: 1, dim: 0.5)),
    ("pause_dim -1 as 0", wpClamped(pauseDim: -1, dim: 0.5), wpClamped(pauseDim: 0, dim: 0.5)),
]
// The controls: inside the range the two ends of each are two pictures.
let wpDiffer: [(String, CGContext?, CGContext?)] = [
    ("fill 0 as 1", wpClamped(fill: 0), wpClamped(fill: 1)),
    ("glide 0 as 1", wpClamped(glide: 0), wpClamped(glide: 1)),
    ("dim 0 as 1", wpClamped(dim: 0), wpClamped(dim: 1)),
    ("pause_dim 0 as 1", wpClamped(pauseDim: 0, dim: 0.5), wpClamped(pauseDim: 1, dim: 0.5)),
]
out["p16"] = [
    "same": Dictionary(uniqueKeysWithValues: wpEqual.map { ($0.0, wpSame($0.1, $0.2)) }),
    "control_same": Dictionary(
        uniqueKeysWithValues: wpDiffer.map { ($0.0, wpSame($0.1, $0.2)) }),
    "lit_ink": wpClamped(dim: 0).map { wpRect(wpInk($0, wpAny)) } ?? "no bitmap",
    "invisible_ink": wpClamped(pauseDim: 1, dim: 1).map { wpRect(wpInk($0, wpAny)) }
        ?? "no bitmap",
]

// P17 — the plate's HEIGHT travels too (issue batch B86 phase 2). On a page
// in one face every line has the same ascent and descent, so P11's two pills
// are equally tall; here the second line holds glyphs the face does not have,
// so a fallback face's metrics make that line and its pill. `word_glide`
// 0.2063 eases to one half, where a height that jumped is furthest off.
let wpMixed = TextProps(
    content: "sun\n月見", font: "Montserrat-Black", size: 160, color: [1, 1, 1, 1],
    textCase: .upper, wordStyle: WordStyle(activePill: wpGlidingPill))
out["p17"] = [
    "lines": LayerRenderers.layout(for: wpMixed).lines.map {
        Double($0.ascent + $0.descent)
    },
    "glide": 0.2063,
    "from": wpRedRect(wpMixed, RecipeReveal(word: 1)),
    "to": wpRedRect(wpMixed, RecipeReveal(word: 2, wordGlide: 1)),
    "half": wpRedRect(wpMixed, RecipeReveal(word: 2, wordGlide: 0.2063)),
]

// MARK: P18, P19 — where the dim is drawn (issue batch B86 phase 3, spec §11 W-16)

let wpYellow: RGBA = [1, 1, 0, 1]
/// P16's page under `backdrop`, as `TextProps`.
func wpDimPage(_ pauseDim: Double, backdrop: BackdropProps? = nil) -> TextProps {
    let page = wpLookPage("sun moon star", style: wpClampStyle(pauseDim))
    return TextProps(
        content: page.content, font: page.font, size: page.size, color: page.color,
        outline: page.outline, backdrop: backdrop, width: page.width, textCase: page.textCase,
        wordStyle: page.wordStyle)
}
func wpDimAnswer(_ props: TextProps, _ reveal: RecipeReveal) -> [String: Any] {
    let answer = LayerRenderers.wordDim(of: props, reveal: reveal)
    return ["amount": answer.amount, "on_layer": answer.onLayer]
}

// P18 — the rule. No backdrop: `textBitmap` holds none of the dim. A backdrop
// (opaque yellow, which is no ink of this page: white, red, magenta, green,
// blue): the bitmap holds it, and the bare backdrop is untouched.
let wpBare = wpDimPage(0.5)
let wpPlated = wpDimPage(0.5, backdrop: BackdropProps(color: wpYellow, radius: 0))
let wpPlatedLit = wpDraw(wpPlated, RecipeReveal(word: 2))
let wpPlatedDim = wpDraw(wpPlated, RecipeReveal(word: 2, wordDim: 0.5))
/// Of the pixels that are exactly the opaque yellow backdrop in `lit`: how
/// many there are, and how many are other bytes in `dimmed`.
func wpBareBackdrop(_ lit: CGContext?, _ dimmed: CGContext?) -> [String: Any] {
    guard let lit, let dimmed, let a = lit.data, let b = dimmed.data,
        lit.width == dimmed.width, lit.height == dimmed.height,
        lit.bytesPerRow == dimmed.bytesPerRow
    else { return ["pixels": 0, "moved": -1] }
    let one = a.assumingMemoryBound(to: UInt8.self)
    let two = b.assumingMemoryBound(to: UInt8.self)
    var pixels = 0
    var moved = 0
    for y in 0..<lit.height {
        for x in 0..<lit.width {
            let at = y * lit.bytesPerRow + x * 4
            // BGRA, premultiplied: opaque yellow is (0, 255, 255, 255).
            guard one[at] == 0, one[at + 1] == 255, one[at + 2] == 255, one[at + 3] == 255
            else { continue }
            pixels += 1
            if (0..<4).contains(where: { two[at + $0] != one[at + $0] }) { moved += 1 }
        }
    }
    return ["pixels": pixels, "moved": moved]
}
let wpUnstyled = TextProps(content: "sun moon star", font: "Montserrat-Black", size: 80)
out["p18"] = [
    "bare_half_same_as_nil": wpSame(
        wpDraw(wpBare, RecipeReveal(word: 2, wordDim: 0.5)), wpDraw(wpBare, RecipeReveal(word: 2))),
    "bare_full_same_as_nil": wpSame(
        wpDraw(wpDimPage(1), RecipeReveal(word: 2, wordDim: 1)),
        wpDraw(wpBare, RecipeReveal(word: 2))),
    "bare_ink": wpDraw(wpBare, RecipeReveal(word: 2, wordDim: 0.5))
        .map { wpRect(wpInk($0, wpAny)) } ?? "no bitmap",
    "bare_answer": wpDimAnswer(wpBare, RecipeReveal(word: 2, wordDim: 0.5)),
    "plated_same_as_nil": wpSame(wpPlatedDim, wpPlatedLit),
    "plated_backdrop": wpBareBackdrop(wpPlatedLit, wpPlatedDim),
    "plated_answer": wpDimAnswer(wpPlated, RecipeReveal(word: 2, wordDim: 0.5)),
    "amounts": [
        "word nil": wpDimAnswer(wpBare, RecipeReveal(wordDim: 0.5)),
        "no style": wpDimAnswer(wpUnstyled, RecipeReveal(word: 2, wordDim: 0.5)),
        "word_dim nil": wpDimAnswer(wpBare, RecipeReveal(word: 2)),
        "word_dim 2": wpDimAnswer(wpBare, RecipeReveal(word: 2, wordDim: 2)),
        "pause_dim 2": wpDimAnswer(wpDimPage(2), RecipeReveal(word: 2, wordDim: 0.5)),
        "word_dim -1": wpDimAnswer(wpBare, RecipeReveal(word: 2, wordDim: -1)),
        "pause_dim -1": wpDimAnswer(wpDimPage(-1), RecipeReveal(word: 2, wordDim: 0.5)),
    ],
]

// P19 — a dimmed page WITH a backdrop is the lit page at one opacity over an
// untouched backdrop. `highlight-word0` (issue batch B93 phase 3) is a page
// with no active token — `highlight` at word 0, every token upcoming — which
// `drawWords` leaves by its early return after the base pass: its dim must
// still be applied. Three `textBitmap`s a page: D, the dimmed page; U, the
// same page with its backdrop's alpha 0 and no dim (the words and the pill
// alone, in the same box); B, the same page in `build` at word 0 (the
// backdrop alone). The reference is this probe's own arithmetic per
// premultiplied byte, `U·(1 − a) + B·(1 − U_alpha·(1 − a))`, unrounded.
struct WpDimCase {
    let label: String
    let style: WordStyle
    let backdrop: BackdropProps
    let outline: OutlineProps?
    let reveal: RecipeReveal
    let amount: Double
}
func wpDimStyle(_ style: WordStyle, mode: WordMode) -> WordStyle {
    WordStyle(
        mode: mode, activeColor: style.activeColor, activeScale: style.activeScale,
        activePill: style.activePill, spokenColor: style.spokenColor,
        upcomingColor: style.upcomingColor, activeFill: style.activeFill,
        pauseDim: style.pauseDim)
}
func wpDimProps(_ one: WpDimCase, style: WordStyle, backdrop: BackdropProps) -> TextProps {
    TextProps(
        content: "sun moon star", font: "Montserrat-Black", size: 80, color: [1, 1, 1, 1],
        outline: one.outline, backdrop: backdrop, textCase: .upper, wordStyle: style)
}
let wpPlate = BackdropProps(color: wpYellow, radius: 0)
let wpDimCases: [WpDimCase] = [
    WpDimCase(
        label: "opaque", style: wpClampStyle(0.5), backdrop: wpPlate, outline: nil,
        reveal: RecipeReveal(word: 2, wordGlide: 0.5, wordFill: 0.5, wordDim: 0.5), amount: 0.25),
    WpDimCase(
        label: "default",
        style: WordStyle(
            activeColor: wpRedColor, activeScale: 1.5, spokenColor: [0, 1, 0, 0.5],
            upcomingColor: wpBlueColor, pauseDim: 0.5),
        backdrop: BackdropProps(), outline: OutlineProps(width: 8, color: [0, 0, 0, 1]),
        reveal: RecipeReveal(word: 2, wordPop: 0.5, wordDim: 1), amount: 0.5),
    WpDimCase(
        label: "full", style: wpClampStyle(1), backdrop: wpPlate, outline: nil,
        reveal: RecipeReveal(word: 2, wordGlide: 0.5, wordFill: 0.5, wordDim: 1), amount: 1),
    WpDimCase(
        label: "highlight-word0", style: wpDimStyle(wpClampStyle(0.5), mode: .highlight),
        backdrop: BackdropProps(color: [0.2, 0.5, 0.9, 0.37], radius: 30), outline: nil,
        reveal: RecipeReveal(word: 0, wordDim: 0.5), amount: 0.25),
]
var p19: [[String: Any]] = []
for one in wpDimCases {
    let page = wpDimProps(one, style: one.style, backdrop: one.backdrop)
    var clear = one.backdrop.color
    if clear.count > 3 { clear[3] = 0 }
    let alone = wpDimProps(
        one, style: one.style,
        backdrop: BackdropProps(
            color: clear, padding: one.backdrop.padding, radius: one.backdrop.radius))
    let lit = RecipeReveal(
        word: one.reveal.word, wordPop: one.reveal.wordPop, wordGlide: one.reveal.wordGlide,
        wordFill: one.reveal.wordFill)
    let plate = wpDimProps(one, style: wpDimStyle(one.style, mode: .build), backdrop: one.backdrop)
    var row: [String: Any] = [
        "page": one.label, "amount": one.amount,
        "answer": wpDimAnswer(page, one.reveal), "drew": false,
    ]
    if let d = wpDraw(page, one.reveal), let u = wpDraw(alone, lit),
        let b = wpDraw(plate, RecipeReveal(word: 0)),
        let dData = d.data, let uData = u.data, let bData = b.data,
        d.width == u.width, d.height == u.height, d.width == b.width, d.height == b.height,
        d.bytesPerRow == u.bytesPerRow, d.bytesPerRow == b.bytesPerRow {
        let dp = dData.assumingMemoryBound(to: UInt8.self)
        let up = uData.assumingMemoryBound(to: UInt8.self)
        let bp = bData.assumingMemoryBound(to: UInt8.self)
        let keep = 1 - one.amount
        var worst = 0.0
        var worstAt: [String: Any] = [:]
        var over1 = 0
        var over3 = 0
        var inked = 0
        var empty = 0
        var emptyMoved = 0
        // The largest distance per pixel class: U's alpha 255 (full ink), 1…254
        // (an antialiased edge or a partial-alpha ink) — where a difference
        // sits says what made it.
        var worstFull = 0.0
        var worstEdge = 0.0
        for y in 0..<d.height {
            for x in 0..<d.width {
                let at = y * d.bytesPerRow + x * 4
                let alpha = Double(up[at + 3])
                if alpha == 0 {
                    empty += 1
                    if (0..<4).contains(where: { dp[at + $0] != bp[at + $0] }) { emptyMoved += 1 }
                } else {
                    inked += 1
                }
                for channel in 0..<4 {
                    let reference = Double(up[at + channel]) * keep
                        + Double(bp[at + channel]) * (1 - alpha / 255 * keep)
                    let distance = abs(Double(dp[at + channel]) - reference)
                    if distance > 1 { over1 += 1 }
                    if distance > 3 { over3 += 1 }
                    if alpha == 255 { worstFull = max(worstFull, distance) }
                    if alpha > 0, alpha < 255 { worstEdge = max(worstEdge, distance) }
                    if distance > worst {
                        worst = distance
                        worstAt = [
                            "x": x, "y": y, "channel": ["b", "g", "r", "a"][channel],
                            "d": (0..<4).map { Int(dp[at + $0]) },
                            "u": (0..<4).map { Int(up[at + $0]) },
                            "b": (0..<4).map { Int(bp[at + $0]) }, "reference": reference,
                        ]
                    }
                }
            }
        }
        row["drew"] = true
        row["size"] = "\(d.width)x\(d.height)"
        row["distance"] = worst
        row["worst_at"] = worstAt
        row["distance_full_ink"] = worstFull
        row["distance_partial_ink"] = worstEdge
        row["bytes_over_1"] = over1
        row["bytes_over_3"] = over3
        row["ink_pixels"] = inked
        row["empty_pixels"] = empty
        row["empty_moved"] = emptyMoved
        row["same_as_backdrop"] = wpSame(d, b)
    }
    p19.append(row)
}
out["p19"] = p19

// MARK: P20 — a backdrop's bytes (issue batch B93 phase 3, spec §11 W-17)

// The reference is HEAD's `textBitmap` before W-17: the whole rounded path
// filled by CoreGraphics, then — on a static page — `CTFrameDraw`.
func wpReferenceBackdrop(_ backdrop: BackdropProps, size: CGSize, in context: CGContext) {
    let rect = CGRect(origin: .zero, size: size)
    let radius = min(CGFloat(backdrop.radius), min(size.width, size.height) / 2)
    context.addPath(
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(backdrop.color.nsColor.cgColor)
    context.fillPath()
}
func wpReferencePage(_ props: TextProps, text: Bool) -> CGContext? {
    let layout = LayerRenderers.layout(for: props)
    guard let context = LayerRenderers.bitmap(layout.size) else { return nil }
    if let backdrop = props.backdrop {
        wpReferenceBackdrop(backdrop, size: layout.size, in: context)
    }
    if text, let frame = layout.frame { CTFrameDraw(frame, context) }
    return context
}
let wpRadii: [Double] = [0, 8, 30, 10_000]
let wpBackdropColors: [RGBA] = [[0, 0, 0, 0.6], [1, 1, 0, 1], [0.2, 0.5, 0.9, 0.37]]
/// Two pages, each laid at a fractional width, font size and padding; the
/// box `measuredSize` rounds is printed beside each.
struct WpBackdropPage {
    let label: String
    let content: String
    let size: Double
    let width: Double?
    let padding: Double
}
let wpBackdropPages = [
    WpBackdropPage(
        label: "three words", content: "sun moon star", size: 80.5, width: 401.37,
        padding: 12.25),
    WpBackdropPage(label: "two words", content: "a b", size: 33.3, width: nil, padding: 7.5),
]
var p20Static: [[String: Any]] = []
var p20Timed: [[String: Any]] = []
var p20Direct: [[String: Any]] = []
for page in wpBackdropPages {
    for radius in wpRadii {
        for color in wpBackdropColors {
            let backdrop = BackdropProps(color: color, padding: page.padding, radius: radius)
            let still = TextProps(
                content: page.content, font: "Montserrat-Black", size: page.size,
                color: [1, 1, 1, 1], outline: OutlineProps(width: 4, color: [0, 0, 0, 1]),
                backdrop: backdrop, width: page.width, textCase: .upper)
            let timed = TextProps(
                content: page.content, font: "Montserrat-Black", size: page.size,
                color: [1, 1, 1, 1], outline: OutlineProps(width: 4, color: [0, 0, 0, 1]),
                backdrop: backdrop, width: page.width, textCase: .upper,
                wordStyle: WordStyle(mode: .build, activeColor: wpRedColor))
            let box = LayerRenderers.measuredSize(for: still)
            let timedBox = LayerRenderers.measuredSize(for: timed)
            p20Static.append([
                "page": page.label, "radius": radius, "color": color,
                "box": [Double(box.width), Double(box.height)],
                "same": wpSame(
                    LayerRenderers.textBitmap(still, reveal: RecipeReveal()),
                    wpReferencePage(still, text: true)),
            ])
            p20Timed.append([
                "page": page.label, "radius": radius, "color": color,
                "box": [Double(timedBox.width), Double(timedBox.height)],
                "same": wpSame(
                    LayerRenderers.textBitmap(timed, reveal: RecipeReveal(word: 0)),
                    wpReferencePage(timed, text: false)),
            ])
        }
    }
}
// `drawBackdrop` itself at sizes `measuredSize` never makes — fractional on
// both axes, so the clamped radius and the box's last row and column are
// fractional too — over and under, into an empty bitmap of the rounded size.
for size in [CGSize(width: 301.4, height: 97.6), CGSize(width: 120.5, height: 63)] {
    for radius in wpRadii {
        for color in wpBackdropColors {
            let backdrop = BackdropProps(color: color, radius: radius)
            for under in [false, true] {
                guard let drawn = LayerRenderers.bitmap(size),
                    let reference = LayerRenderers.bitmap(size)
                else { continue }
                LayerRenderers.drawBackdrop(backdrop, size: size, under: under, in: drawn)
                wpReferenceBackdrop(backdrop, size: size, in: reference)
                p20Direct.append([
                    "size": [Double(size.width), Double(size.height)], "radius": radius,
                    "color": color, "under": under, "same": wpSame(drawn, reference),
                ])
            }
        }
    }
}
out["p20"] = ["static": p20Static, "timed": p20Timed, "direct": p20Direct]

if wpQuick { wpFinish(out) }

// MARK: P1, P2 — the box at every word and pop, and no ink outside it

var boxes: [[String: Any]] = []
/// One page of the P1/P2 loop, drawn at every word and pop in six layouts
/// (one line and wrapped, valign middle, top and bottom). Since issue batch
/// B86 each is also drawn half FILLED, and a config with a pill also with
/// the pill GLIDING at `glide` 0 and 0.5 (word ≥ 2), over the same bitmap
/// and so into the same `overflow_px`: neither look may put ink outside
/// the box.
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
        let gliding = style.activePill.map {
            WordStyle(
                mode: style.mode, activeColor: style.activeColor, activeScale: style.activeScale,
                activePill: ActivePill(
                    color: $0.color, padding: $0.padding, radius: $0.radius, glide: true),
                spokenColor: style.spokenColor, upcomingColor: style.upcomingColor)
        }
        /// One more drawing of the page into a margin-wide bitmap, folded
        /// into `worst`.
        func fold(_ draw: (CGContext) -> Void) {
            guard let big = LayerRenderers.bitmap(CGSize(
                width: box.width + margin * 2, height: box.height + margin * 2))
            else { return }
            big.translateBy(x: margin, y: margin)
            draw(big)
            guard let ink = wpInk(big, wpAny) else { return }
            // Memory row 0 is the TOP; CG y is up, so rows map to t/b.
            worst["l"] = max(worst["l"] ?? 0, Double(margin - ink.minX))
            worst["r"] = max(worst["r"] ?? 0, Double(ink.maxX - (margin + box.width)))
            worst["t"] = max(worst["t"] ?? 0, Double(margin - ink.minY))
            worst["b"] = max(worst["b"] ?? 0, Double(ink.maxY - (margin + box.height)))
        }
        for word in 0...count {
            for pop in pops {
                let reveal = RecipeReveal(word: word, wordPop: word == 0 ? nil : pop)
                if let bitmap = renderers.renderTextBitmap(props, reveal: reveal) {
                    sizes.insert("\(bitmap.width)x\(bitmap.height)")
                }
                guard word > 0 else { continue }
                // One bitmap takes every drawing of this word and pop — the
                // ink of their UNION is the worst of each, and the pixel
                // scan, which is what this loop costs, runs once.
                fold {
                    LayerRenderers.drawWords(
                        layout, of: props, style: style, word: word, pop: pop, in: $0)
                    LayerRenderers.drawWords(
                        layout, of: props, style: style, word: word, pop: pop, fill: 0.5, in: $0)
                    guard let gliding, word >= 2 else { return }
                    for glide in [0, 0.5] {
                        LayerRenderers.drawWords(
                            layout, of: props, style: gliding, word: word, pop: pop,
                            glide: glide, in: $0)
                    }
                }
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

wpFinish(out)
