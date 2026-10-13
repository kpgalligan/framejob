// Road map 8, spike W0 — the app-side probe: q4's Swift tokenizer, q5's
// headroom, cost and two-thread stress, and q6's font registry reading.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` — the root
// `CLAUDE.md`'s rule for app ARITHMETIC and app STRUCTURE no script can reach.
// `tools/proof/peaks_probe.py:101-117` is the swiftc line it is built with.
//
//   text_probe tokens <corpus.json> <out.json>
//   text_probe raster <app_fonts_dir> <fonts_dir|-> <out.json>
//   text_probe stress <app_fonts_dir> <out.json>
//   text_probe fonts  <fonts_dir> <out.json>
//
// **Fonts are registered before anything asks for one.** A bare Mach-O has no
// `ATSApplicationFontsPath` — `project.yml:61` is the BUNDLE's key and nothing
// else reads the folder — and `LayerRenderersText.swift:124`'s
// `CTFontCreateWithName` never answers nil, so an unregistered face measures
// as Helvetica and says nothing. Registration is `.process` scope, the
// harness's own loop (`tools/proof/harness/main.swift:246-252`); nothing is
// installed to `~/Library/Fonts`. Every face reports the PostScript name of
// the font that actually came back, and `text_rows.py` scores a mismatch as a
// FAILURE rather than a measurement.
import AppKit
import CoreText
import Metal

// MARK: - The one JSON object

func emit(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data(#"{"ok":false,"error":"the answer would not serialise"}"#.utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func write(_ object: [String: Any], to path: String) {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
    emit(object)
}

func usage(_ message: String) -> Never {
    emit(["ok": false, "error": message])
    exit(1)
}

// MARK: - Font registration, `.process` scope only

/// `tools/proof/harness/main.swift:246-252`'s loop, with its answer kept:
/// which files went in, and what CoreText said about the ones that did not.
func registerFonts(_ directory: String) -> [String: Any] {
    let url = URL(fileURLWithPath: directory)
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
        return ["dir": directory, "files": 0, "errors": ["the directory could not be read"]]
    }
    var files = 0
    var errors: [String] = []
    for name in names.sorted() where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
        var error: Unmanaged<CFError>?
        let one = url.appendingPathComponent(name)
        if CTFontManagerRegisterFontsForURL(one as CFURL, .process, &error) {
            files += 1
        } else {
            let text = error?.takeRetainedValue().localizedDescription ?? "unknown"
            // "already registered" is not a failure: two directories may hold
            // one face, and the second call is the one that says so.
            if text.contains("already") {
                files += 1
            } else {
                errors.append("\(name): \(text)")
            }
        }
    }
    return ["dir": directory, "files": files, "errors": errors]
}

// MARK: - The CONTROL copy of the renderer's tokenizer

/// A VERBATIM copy of `LayerRenderersText.swift:470-484`'s `tokens(of:)`,
/// which is `private` and so unreachable even from inside the module.
///
/// `text_rows.py` asserts this copy is character-for-character the tree's, so
/// q4 measures the renderer's rule and not a paraphrase of it. That assertion
/// is the CONTROL: without it a drifted copy would agree with Rust and the row
/// would report agreement that the app does not have.
func tokens(of content: String) -> [Range<Int>] {
    var tokens: [Range<Int>] = []
    var start: Int?
    for index in content.indices {
        let offset = index.utf16Offset(in: content)
        if content[index].isWhitespace {
            if let from = start { tokens.append(from..<offset) }
            start = nil
        } else if start == nil {
            start = offset
        }
    }
    if let from = start { tokens.append(from..<content.utf16.count) }
    return tokens
}

func tokensMode(corpus: String, out: String) {
    guard let data = FileManager.default.contents(atPath: corpus),
          let parsed = try? JSONSerialization.jsonObject(with: data),
          let object = parsed as? [String: Any],
          let rows = object["rows"] as? [[String: Any]]
    else { usage("the corpus at \(corpus) is not {\"rows\": [{id, text}, …]}") }
    var answer: [[String: Any]] = []
    for row in rows {
        let id = row["id"] as? String ?? "?"
        let text = row["text"] as? String ?? ""
        // The length is reported beside the tokens so a disagreement can be
        // told apart from a TRANSPORT difference: if the two sides did not
        // receive the same string, nothing about the two rules follows.
        answer.append([
            "id": id, "utf16_length": text.utf16.count,
            "characters": text.count,
            "tokens": tokens(of: text).map { [$0.lowerBound, $0.upperBound] }])
    }
    write(["ok": true, "rows": answer], to: out)
}

// MARK: - The shared page

let PAGE = "THIS IS HOW IT LOOKS"

/// The same 120 words `fixtures.py`'s `TALK_TEXT` renders through `say`.
/// `text_rows.py` compares this string to that one before the stress row runs
/// and scores a difference as a FAILURE, so there is one spelling in effect
/// even though the two languages each need their own.
let TALK_TEXT = """
So here's the thing about editing video on a laptop in 2026: you open a \
project, you scrub through forty minutes of footage, and you find the one \
take that actually works. That take is maybe ninety seconds long; everything \
else is a warm-up. The hard part isn't cutting — it's finding. Can you see \
what I mean? I have three cameras, two microphones, and one very patient \
dog. She sits off-camera and waits. When I say the word "treat" she stands \
up and ruins the shot, every time! So we renamed it. Now we call it a \
reward, and she hasn't worked that out yet… but she will, because she is \
smarter than the software.
"""

/// The style sheet q5 measures, from road map 8 §5h and §8: the size is
/// 0.075 of the canvas's short side and the outline is 0.08 em.
func props(face: String, size: Double, content: String = PAGE) -> TextProps {
    TextProps(
        content: content, font: face, size: size, color: [1, 1, 1, 1], align: "center",
        valign: "middle", lineSpacing: 1, tracking: 0,
        outline: OutlineProps(width: size * 0.08, color: [0, 0, 0, 1]), backdrop: nil,
        width: nil, animation: nil)
}

func postScriptName(of face: String, size: Double) -> String {
    let font = CTFontCreateWithName(face as CFString, CGFloat(size), nil)
    return CTFontCopyPostScriptName(font) as String
}

func familyName(of face: String, size: Double) -> String {
    let font = CTFontCreateWithName(face as CFString, CGFloat(size), nil)
    return CTFontCopyFamilyName(font) as String
}

/// The name a face that is not installed resolves to. `CTFontCreateWithName`
/// never answers nil (`LayerRenderersText.swift:124`), so this is the ONE way
/// to tell "the registry gave me the face I asked for under another name"
/// from "the registry gave me the system fallback and said nothing".
let FALLBACK_CONTROL = "NoSuchFont-Black"

/// The probe's OWN layout of a page, over the same attributes
/// `LayerRenderersText.attributedString` builds (which is private).
struct Laid {
    let attributed: NSAttributedString
    let lines: [CTLine]
    let origins: [CGPoint]
    let ascents: [CGFloat]
    let descents: [CGFloat]
    let leadings: [CGFloat]
    let inset: CGFloat
    let box: CGSize
}

func attributes(_ props: TextProps) -> [NSAttributedString.Key: Any] {
    let size = max(1, CGFloat(props.size))
    let font = CTFontCreateWithName(props.font as CFString, size, nil)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    var attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: props.color.nsColor, .paragraphStyle: paragraph,
    ]
    if let outline = props.outline {
        attributes[.strokeWidth] = -CGFloat(outline.width) / size * 100
        attributes[.strokeColor] = outline.color.nsColor
    }
    return attributes
}

func lay(_ props: TextProps) -> Laid {
    let box = LayerRenderers.measuredSize(for: props)
    let attributed = NSAttributedString(string: props.content, attributes: attributes(props))
    let inset = CGFloat(props.outline?.width ?? 0)
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    var fitRange = CFRange()
    let constraint = CGSize(width: box.width - inset * 2, height: 100_000)
    let laid = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter, CFRange(location: 0, length: 0), nil, constraint, &fitRange)
    let height = min(box.height - inset * 2, laid.height) + 2
    let rect = CGRect(
        x: inset, y: (box.height - height) / 2, width: box.width - inset * 2, height: height)
    let frame = CTFramesetterCreateFrame(
        framesetter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
    let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
    var origins = [CGPoint](repeating: .zero, count: max(lines.count, 1))
    CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
    var ascents: [CGFloat] = []
    var descents: [CGFloat] = []
    var leadings: [CGFloat] = []
    for line in lines {
        var a: CGFloat = 0
        var d: CGFloat = 0
        var l: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &a, &d, &l)
        ascents.append(a)
        descents.append(d)
        leadings.append(l)
    }
    let moved = zip(lines.indices, origins.prefix(lines.count)).map { index, origin in
        CGPoint(x: rect.minX + origin.x, y: rect.minY + origins[index].y)
    }
    return Laid(
        attributed: attributed, lines: lines, origins: Array(moved), ascents: ascents,
        descents: descents, leadings: leadings, inset: inset, box: box)
}

/// Ink bounds of a premultiplied BGRA context: the first and last row and
/// column holding any alpha at all. `LayerRenderers.bitmap` is the context,
/// so this reads exactly the pixels the compositor would upload.
func inkBounds(_ context: CGContext) -> CGRect? {
    guard let data = context.data else { return nil }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    let stride = context.bytesPerRow
    var minX = context.width
    var maxX = -1
    var minY = context.height
    var maxY = -1
    for y in 0..<context.height {
        let row = bytes + y * stride
        for x in 0..<context.width where row[x * 4 + 3] > 0 {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= 0, maxY >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

// MARK: - raster — the headroom a pop and a pill need, and what one costs

/// The throwaway routine road map 8 §5d proposes, drawn ONCE per active word:
/// the base page, then token `k` again on a 0.2 em pill, scaled 1.15 about its
/// own centre. It draws into a bitmap of the measured box plus a one-em margin
/// on every side, so the ink that a FIXED box would clip is visible instead of
/// gone.
func drawActive(_ props: TextProps, k: Int, scale: Double, padding: Double)
    -> (CGContext, CGSize, CGFloat)?
{
    let laid = lay(props)
    let em = CGFloat(props.size)
    let margin = em
    let canvas = CGSize(width: laid.box.width + margin * 2, height: laid.box.height + margin * 2)
    guard let context = LayerRenderers.bitmap(canvas) else { return nil }
    context.translateBy(x: margin, y: margin)
    context.textMatrix = .identity
    for (index, line) in laid.lines.enumerated() {
        context.textPosition = laid.origins[index]
        CTLineDraw(line, context)
    }
    let ranges = tokens(of: props.content)
    guard k >= 0, k < ranges.count, !laid.lines.isEmpty else {
        return (context, laid.box, laid.ascents.first.map { $0 + laid.descents[0] } ?? em)
    }
    let token = ranges[k]
    var which = 0
    for (index, line) in laid.lines.enumerated() {
        let range = CTLineGetStringRange(line)
        if token.lowerBound >= range.location, token.lowerBound < range.location + range.length {
            which = index
        }
    }
    let line = laid.lines[which]
    let origin = laid.origins[which]
    let left = origin.x + CTLineGetOffsetForStringIndex(line, token.lowerBound, nil)
    let right = origin.x + CTLineGetOffsetForStringIndex(line, token.upperBound, nil)
    let pad = em * CGFloat(padding)
    let pill = CGRect(
        x: left - pad, y: origin.y - laid.descents[which] - pad,
        width: (right - left) + pad * 2,
        height: laid.ascents[which] + laid.descents[which] + pad * 2)
    let centre = CGPoint(x: pill.midX, y: pill.midY)
    context.saveGState()
    context.translateBy(x: centre.x, y: centre.y)
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.translateBy(x: -centre.x, y: -centre.y)
    let radius = min(pill.height * 0.25, pill.height / 2)
    context.addPath(CGPath(
        roundedRect: pill, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(NSColor(red: 0.42, green: 0.25, blue: 0.85, alpha: 1).cgColor)
    context.fillPath()
    context.saveGState()
    context.clip(to: pill)
    context.textMatrix = .identity
    context.textPosition = origin
    CTLineDraw(line, context)
    context.restoreGState()
    context.restoreGState()
    return (context, laid.box, laid.ascents[which] + laid.descents[which] + laid.leadings[which])
}

func rasterMode(appFonts: String, extraFonts: String?, out: String) {
    var registered: [[String: Any]] = [registerFonts(appFonts)]
    if let extraFonts { registered.append(registerFonts(extraFonts)) }
    guard let device = MTLCreateSystemDefaultDevice() else {
        write(["ok": false, "error": "no Metal device", "registered": registered], to: out)
        return
    }
    let renderers = LayerRenderers(device: device)
    var canvases: [String: Any] = [:]
    var allMatched = true
    var anyFallback = false
    for (width, height) in [(1080, 1920), (3840, 2160)] {
        let size = 0.075 * Double(min(width, height))
        var faces: [[String: Any]] = []
        for face in ["SourceSans3-Bold", "Montserrat-Black"] {
            let text = props(face: face, size: size)
            let resolved = postScriptName(of: face, size: size)
            let matched = resolved == face
            allMatched = allMatched && matched
            let fallback = postScriptName(of: FALLBACK_CONTROL, size: size)
            let isFallback = resolved == fallback
            anyFallback = anyFallback || isFallback
            let box = LayerRenderers.measuredSize(for: text)
            var renderMilliseconds: [Double] = []
            for step in 0..<20 {
                let began = Date()
                _ = renderers.text(text, hash: "w0-\(width)-\(face)-\(step)", reveal: .whole)
                renderMilliseconds.append(Date().timeIntervalSince(began) * 1000)
            }
            var active: [[String: Any]] = []
            var boxes: Set<String> = []
            var worst = 0.0
            var lineHeight = size
            for k in 0..<tokens(of: PAGE).count {
                guard let (context, drawn, height) = drawActive(
                    text, k: k, scale: 1.15, padding: 0.2)
                else { continue }
                lineHeight = Double(height)
                boxes.insert("\(drawn.width)x\(drawn.height)")
                let margin = CGFloat(size)
                let inside = CGRect(
                    x: margin, y: margin, width: drawn.width, height: drawn.height)
                let ink = inkBounds(context) ?? inside
                let overflow: [String: Double] = [
                    "l": Double(max(0, inside.minX - ink.minX)),
                    "r": Double(max(0, ink.maxX - inside.maxX)),
                    // The bitmap is y-UP, so "t" is the high edge.
                    "b": Double(max(0, inside.minY - ink.minY)),
                    "t": Double(max(0, ink.maxY - inside.maxY)),
                ]
                worst = max(worst, overflow.values.max() ?? 0)
                active.append(["k": k, "ink_overflow_px": overflow])
            }
            faces.append([
                "requested": face, "postscript_name": resolved, "name_match": matched,
                // The two halves of "did I get the face I asked for": the
                // NAME round-tripping, and the face not being the system's
                // silent fallback. A variable font's named instance fails the
                // first and passes the second, and they are recorded apart.
                "resolved_family": familyName(of: face, size: size),
                "fallback_postscript_name": fallback, "is_fallback": isFallback,
                "size_px": size, "box": ["w": Double(box.width), "h": Double(box.height)],
                "render_ms": renderMilliseconds, "active": active,
                "headroom_em": worst / size,
                "headroom_line_frac": lineHeight > 0 ? worst / lineHeight : 0,
                "line_height_px": lineHeight,
                "box_constant": boxes.count <= 1,
            ])
        }
        canvases["\(width)x\(height)"] = ["faces": faces]
    }
    write([
        "ok": !anyFallback, "registered": registered, "canvases": canvases,
        "page": PAGE, "all_names_matched": allMatched, "any_fallback": anyFallback,
    ], to: out)
}

// MARK: - stress — `measuredSize` under the lock the compositor also takes

func stressMode(appFonts: String, out: String) {
    let registered = registerFonts(appFonts)
    let face = "SourceSans3-Bold"
    let size = 81.0
    let resolved = postScriptName(of: face, size: size)
    guard let device = MTLCreateSystemDefaultDevice() else {
        write(["ok": false, "error": "no Metal device", "registered": registered], to: out)
        return
    }
    let renderers = LayerRenderers(device: device)
    let words = TALK_TEXT.split(separator: " ").map(String.init)
    // A thousand candidate PAGES, each one word longer than the last, cycling
    // through the script: exactly the shape `CaptionPages` would ask for.
    var pages: [String] = []
    // The start walks the script and the LENGTH changes only once the start
    // has been all the way round, so the thousand keys are close to a
    // thousand DISTINCT ones rather than the couple of hundred that two
    // correlated moduli give — which is what makes the size cache's 256-entry
    // flush happen at all.
    let span = max(words.count - 8, 1)
    for index in 0..<1000 {
        let from = index % span
        let count = ((index / span) % 8) + 1
        pages.append(words[from..<min(from + count, words.count)].joined(separator: " "))
    }
    // The single-thread pass runs FIRST and on a COLD cache, so its time is
    // what a page builder pays the first time it asks; the threaded pass that
    // follows re-asks the same thousand keys and is the warm number. Both are
    // recorded, because §5c's cost is the first one and §7.5's budget is the
    // second.
    let coldBegan = Date()
    var single: [Double] = []
    for page in pages {
        single.append(Double(LayerRenderers.measuredSize(
            for: props(face: face, size: size, content: page)).width))
    }
    let coldMilliseconds = Date().timeIntervalSince(coldBegan) * 1000
    var threaded = [Double](repeating: -1, count: pages.count)
    let lock = NSLock()
    var measureMilliseconds = 0.0
    var renderMilliseconds = 0.0
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        let began = Date()
        for (index, page) in pages.enumerated() {
            let width = Double(LayerRenderers.measuredSize(
                for: props(face: face, size: size, content: page)).width)
            lock.lock()
            threaded[index] = width
            lock.unlock()
        }
        measureMilliseconds = Date().timeIntervalSince(began) * 1000
        group.leave()
    }
    group.enter()
    DispatchQueue.global().async {
        let began = Date()
        for step in 0..<200 {
            let amount = Double(step) / 199.0
            _ = renderers.text(
                props(face: face, size: size),
                hash: "w0-stress-\(step)",
                reveal: RecipeReveal(amount: amount, phase: "in", kind: .wordFade))
        }
        renderMilliseconds = Date().timeIntervalSince(began) * 1000
        group.leave()
    }
    group.wait()
    let equal = zip(single, threaded).allSatisfy { $0 == $1 }
    write([
        "ok": equal && resolved != postScriptName(of: FALLBACK_CONTROL, size: size),
        "registered": registered,
        "fallback_postscript_name": postScriptName(of: FALLBACK_CONTROL, size: size),
        "is_fallback": resolved == postScriptName(of: FALLBACK_CONTROL, size: size),
        "resolved_family": familyName(of: face, size: size),
        "measure_ms_cold_single_thread": coldMilliseconds,
        "requested": face, "postscript_name": resolved, "name_match": resolved == face,
        "measure_calls": pages.count, "measure_ms": measureMilliseconds,
        "render_calls": 200, "render_ms": renderMilliseconds,
        "sizes_equal_single_thread": equal,
        "distinct_pages": Set(pages).count,
        // `LayerRenderersText.swift:62` empties the size cache once it passes
        // `cacheLimit * 4` = 256 entries, so a thousand distinct keys flush it
        // this many times.
        "flushes_expected": Set(pages).count / 256,
        "first_render_ms_is_the_cold_one": true,
        "talk_text": TALK_TEXT,
    ], to: out)
}

// MARK: - fonts — what the registry says about each file

func fontsMode(directory: String, out: String) {
    let registered = registerFonts(directory)
    let url = URL(fileURLWithPath: directory)
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
        .filter { $0.hasSuffix(".ttf") || $0.hasSuffix(".otf") }.sorted()
    let size = 81.0
    let control = "NoSuchFont-Black"
    let controlWidth = Double(LayerRenderers.measuredSize(
        for: props(face: control, size: size)).width)
    var rows: [String: Any] = [:]
    for name in names {
        var row: [String: Any] = [:]
        let one = url.appendingPathComponent(name)
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(one as CFURL) as? [CTFontDescriptor]
        guard let descriptor = descriptors?.first else {
            row["registered"] = false
            row["error"] = "no descriptor could be read from the file"
            rows[name] = row
            continue
        }
        let psName = (CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String)
            ?? ""
        let family = (CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute)
            as? String) ?? ""
        let style = (CTFontDescriptorCopyAttribute(
            descriptor, kCTFontStyleNameAttribute) as? String) ?? ""
        let font = CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), nil)
        row["registered"] = (registered["errors"] as? [String] ?? []).isEmpty
        row["error"] = NSNull()
        row["postscript_name"] = psName
        row["family"] = family
        row["style"] = style
        // The `name` table's version string, verbatim — q6 records what the
        // file says about itself beside its sha256, never a re-derived number.
        row["version"] = (CTFontCopyName(font, kCTFontVersionNameKey) as String?) ?? ""
        row["nsfont_resolves"] = NSFont(name: psName, size: CGFloat(size)) != nil
        row["in_available_families"] = TextFace.families.contains(family)
        row["members"] = TextFace.members(of: family).map { ["name": $0.name, "style": $0.style] }
        row["measured_width"] = Double(LayerRenderers.measuredSize(
            for: props(face: psName, size: size)).width)
        row["control_width"] = controlWidth
        row["differs_from_control"] = (row["measured_width"] as? Double ?? 0) != controlWidth
        rows[name] = row
    }
    write([
        "ok": true, "registered": registered, "control": control,
        "control_width": controlWidth, "files": rows,
    ], to: out)
}

// MARK: - main

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    usage("usage: text_probe tokens|raster|stress|fonts …")
}
switch arguments[1] {
case "tokens":
    guard arguments.count >= 4 else { usage("usage: text_probe tokens <corpus.json> <out.json>") }
    tokensMode(corpus: arguments[2], out: arguments[3])
case "raster":
    guard arguments.count >= 5 else {
        usage("usage: text_probe raster <app_fonts_dir> <fonts_dir|-> <out.json>")
    }
    rasterMode(
        appFonts: arguments[2], extraFonts: arguments[3] == "-" ? nil : arguments[3],
        out: arguments[4])
case "stress":
    guard arguments.count >= 4 else { usage("usage: text_probe stress <app_fonts_dir> <out.json>") }
    stressMode(appFonts: arguments[2], out: arguments[3])
case "fonts":
    guard arguments.count >= 4 else { usage("usage: text_probe fonts <fonts_dir> <out.json>") }
    fontsMode(directory: arguments[2], out: arguments[3])
default:
    usage("unknown mode \(arguments[1])")
}
exit(0)
