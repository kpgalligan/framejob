// kpgalligan/framejob#117 — the canvas text editor breaks lines where the
// render does; the probe (`text_break_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line, `-D FRAMEJOB_DEV_TOOLS`
// included. Everything it calls exists in the baseline tree too (it reads the
// render's attributes through `LayerRenderers.attributedString` at scale 1 and
// scales them itself, never through `textAttributes`), so the proof's
// `--baseline` builds the same source.
//
//   text_break_probe <request.json> <answer.json>
//
// `request.json` names `fonts` (the app's `app/Resources/Fonts`, registered
// here: a bare binary has no bundle) and one package per fixture, each ONE
// text clip (id 2, 0–6 s, the playhead on it) in `SourceSans3-SemiBold`:
//   plain    left-aligned, fixed width, three lines or more
//   tracking plain at `tracking` 24
//   spacing  plain at `line_spacing` 1.8
//   small    size 12, left-aligned, fixed width, many lines
//   upper    `case: upper`, left-aligned, fixed width
//   auto     auto-sized (`width` null), centred, one line, `tracking` 24
// The answer is `rows` (name, ok, detail), REWRITTEN after every row, so a
// probe that dies leaves the rows it did score and the proof scores the rest
// as FAIL.
//
// The split is pinned before `AppDelegate()` (B32, #188 item 1): an
// argument-domain `FrameJobInspectorWidth` 304, `FrameJobTimelineHeight` 300
// and `FrameJobInspectorCollapsed` false, so the canvas's scale does not
// follow whatever this user's defaults last saved; and every window is set
// to content 1600 × 1000 before its editor opens.
//
// A line START is the UTF-16 offset a laid-out line begins at. The editor's
// are read from `textLayoutManager` when the view has one (TextKit 2 —
// reading `layoutManager` would switch the view to TextKit 1), else from
// `layoutManager`, and each detail names which. The render's are
// `LayerRenderers.layout(for:).lines`' `range.location`, what the compositor
// draws. A line PITCH is the distance between two successive lines' origins:
// the editor's in view points, the render's in source pixels × the box's view
// scale (`video.scale × canvasScale`).
import AppKit

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

let request = (try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))) as? [String: Any]
    ?? [:]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
UserDefaults.standard.setVolatileDomain(
    [EditorViewController.inspectorWidthKey: 304.0, EditorViewController.timelineHeightKey: 300.0,
     EditorViewController.inspectorCollapsedKey: false],
    forName: UserDefaults.argumentDomain)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
    if let data = try? JSONSerialization.data(
        withJSONObject: ["rows": rows], options: [.prettyPrinted, .sortedKeys])
    {
        try? data.write(to: out)
    }
}

let fonts = URL(fileURLWithPath: request["fonts"] as? String ?? "/nonexistent")
for name in (try? FileManager.default.contentsOfDirectory(atPath: fonts.path)) ?? []
where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
    CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent(name) as CFURL, .process, nil)
}
check("E0 the fixtures' font SourceSans3-SemiBold resolves (a CONTROL)",
      NSFont(name: "SourceSans3-SemiBold", size: 12) != nil, fonts.path)

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func keyEvent(_ text: String, keyCode: UInt16, window: NSWindow) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: text,
        charactersIgnoringModifiers: text, isARepeat: false, keyCode: keyCode)
}

func type(_ keys: String, into window: NSWindow) {
    for character in keys {
        let text = String(character)
        if let event = keyEvent(text, keyCode: character == " " ? 49 : 0, window: window) {
            window.sendEvent(event)
        }
        spin(0.03)
    }
}

/// The editor's laid-out lines: each line's start and its origin's y, in
/// view points, and which layout manager answered.
struct EditorLines {
    let starts: [Int]
    let ys: [CGFloat]
    let via: String
}

func editorLines(_ editor: NSTextView) -> EditorLines {
    if let manager = editor.textLayoutManager {
        manager.ensureLayout(for: manager.documentRange)
        var starts: [Int] = []
        var ys: [CGFloat] = []
        let origin = manager.documentRange.location
        manager.enumerateTextLayoutFragments(from: origin, options: [.ensuresLayout]) {
            fragment in
            let base = manager.offset(from: origin, to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments where line.characterRange.length > 0 {
                starts.append(base + line.characterRange.location)
                ys.append(fragment.layoutFragmentFrame.minY + line.typographicBounds.minY)
            }
            return true
        }
        return EditorLines(starts: starts, ys: ys, via: "textLayoutManager")
    }
    guard let manager = editor.layoutManager, let container = editor.textContainer else {
        return EditorLines(starts: [], ys: [], via: "no layout manager")
    }
    manager.ensureLayout(for: container)
    var starts: [Int] = []
    var ys: [CGFloat] = []
    manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) {
        rect, _, _, glyphs, _ in
        starts.append(manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil).location)
        ys.append(rect.minY)
    }
    return EditorLines(starts: starts, ys: ys, via: "layoutManager")
}

func renderStarts(_ props: TextProps) -> [Int] {
    LayerRenderers.layout(for: props).lines.map { $0.range.location }
}

func renderPitches(_ props: TextProps, scale: CGFloat) -> [CGFloat] {
    let lines = LayerRenderers.layout(for: props).lines
    guard lines.count > 1 else { return [] }
    return (1..<lines.count).map { abs(lines[$0 - 1].origin.y - lines[$0].origin.y) * scale }
}

func pitches(_ ys: [CGFloat]) -> [CGFloat] {
    guard ys.count > 1 else { return [] }
    return (1..<ys.count).map { abs(ys[$0] - ys[$0 - 1]) }
}

func list(_ values: [CGFloat]) -> String {
    "[" + values.map { String(format: "%.2f", $0) }.joined(separator: ", ") + "]"
}

func text(_ rect: CGRect) -> String {
    String(format: "(%.1f, %.1f, %.1f × %.1f)", rect.minX, rect.minY, rect.width, rect.height)
}

/// One fixture open in the app's own window with the clip's editor up and the
/// caret at the end.
struct Session {
    let document: ProjectDocument
    let window: NSWindow
    let canvas: PreviewCanvasView
    let field: CanvasTextView
    var box: CanvasLayerBox
    var scale: CGFloat { CGFloat(box.video.scale) * canvas.canvasScale }
}

let clipID: UInt32 = 2

func open(_ key: String, label: String) -> Session? {
    guard let path = request[key] as? String else {
        check("\(label) the fixture is named", false)
        return nil
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        check("\(label) the fixture opens", false, "\(error)")
        return nil
    }
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.5)
    guard let window = document.windowControllers.first?.window,
          let editor = window.contentViewController as? EditorViewController,
          let canvas = walk(editor.view).first(where: { $0 is PreviewCanvasView })
            as? PreviewCanvasView
    else {
        check("\(label) the editor window, its canvas and the clip's box open", false)
        return nil
    }
    window.setContentSize(NSSize(width: 1600, height: 1000))
    spin(0.5)
    guard let box = canvas.box(for: clipID) else {
        check("\(label) the editor window, its canvas and the clip's box open", false)
        return nil
    }
    canvas.beginTextEditing(clipID)
    spin(0.2)
    guard let field = walk(canvas).first(where: { $0 is CanvasTextView }) as? CanvasTextView,
          window.firstResponder === field
    else {
        check("\(label) the in-canvas editor opens and takes the keys", false,
              "first responder \(String(describing: window.firstResponder))")
        return nil
    }
    return Session(document: document, window: window, canvas: canvas, field: field, box: box)
}

func close(_ session: Session) {
    session.canvas.cancelTextEditing()
    spin(0.1)
    session.window.orderOut(nil)
    session.document.close()
}

func caretToEnd(_ field: NSTextView) {
    field.setSelectedRange(NSRange(location: (field.string as NSString).length, length: 0))
}

/// Applies `content` through the canvas's own `onEdit` (the `set_text` a
/// commit sends) and answers the clip's text as the canvas then holds it.
func apply(_ content: String, in session: Session) -> TextProps? {
    session.canvas.onEdit?(
        "Edit Text", [.setText(clips: [clipID], patch: TextPatch(content: content))])
    spin(0.1)
    guard let props = session.canvas.box(for: clipID)?.clip.text, props.content == content
    else { return nil }
    return props
}

func startsRow(_ name: String, editor lines: EditorLines, render: [Int], extra: String = "") {
    check(name, !render.isEmpty && lines.starts == render,
          "editor \(lines.starts) (\(lines.via)), render \(render)" + extra)
}

// E1 — plain: the control that the comparison itself agrees on a plain text.
if let s = open("plain", label: "E1 plain:"), let props = s.box.clip.text {
    let render = renderStarts(props)
    check("E1 plain: the render lays out 3 lines or more (a CONTROL)", render.count >= 3,
          "\(render.count) lines; scale \(String(format: "%.4f", s.scale))")
    startsRow("E1 plain: the editor's line starts equal the render's (a CONTROL)",
              editor: editorLines(s.field), render: render)
    close(s)
}

// E2, E3 — tracking 24, before and after typing.
if let s = open("tracking", label: "E2 tracking 24:"), let props = s.box.clip.text {
    startsRow("E2 tracking 24: the editor's line starts equal the render's",
              editor: editorLines(s.field), render: renderStarts(props),
              extra: "; scale \(String(format: "%.4f", s.scale))")
    caretToEnd(s.field)
    let keys = " and more"
    let before = s.field.string
    type(keys, into: s.window)
    let typed = s.field.string
    let lines = editorLines(s.field)
    check("E3 tracking 24: every key of \" and more\" was typed into the editor (a CONTROL)",
          typed == before + keys, "typed \"\(typed)\"")
    s.canvas.cancelTextEditing()
    spin(0.1)
    if let applied = apply(typed, in: s) {
        startsRow("E3 tracking 24, after typing \" and more\": the editor's line starts equal "
                    + "the applied render's",
                  editor: lines, render: renderStarts(applied))
    } else {
        check("E3 tracking 24, after typing \" and more\": the editor's line starts equal "
                + "the applied render's", false, "the typed string did not apply")
    }
    close(s)
}

// E4 — tracking 24 after the window shrinks: the editor restyles at the new scale.
if let s = open("tracking", label: "E4 tracking 24, window at 75 %:"),
   let props = s.box.clip.text
{
    let scaleBefore = s.canvas.canvasScale
    var frame = s.window.frame
    frame.size = NSSize(width: frame.width * 0.75, height: frame.height * 0.75)
    s.window.setFrame(frame, display: true)
    spin(0.5)
    let scaleAfter = s.canvas.canvasScale
    let moved = abs(scaleAfter - scaleBefore) / max(scaleBefore, 0.0001)
    check("E4 tracking 24, window at 75 %: the canvas scale moved by more than 5 % (a CONTROL)",
          moved > 0.05 && s.window.firstResponder === s.field,
          String(format: "canvasScale %.4f → %.4f (%.1f %%); editor still first responder %@",
                 scaleBefore, scaleAfter, moved * 100,
                 s.window.firstResponder === s.field ? "yes" : "no"))
    startsRow("E4 tracking 24, window at 75 %: the editor's line starts equal the render's",
              editor: editorLines(s.field), render: renderStarts(props))
    close(s)
}

// E5 — line spacing 1.8: the breaks, and the pitch.
if let s = open("spacing", label: "E5 line spacing 1.8:"), let props = s.box.clip.text {
    let lines = editorLines(s.field)
    let render = renderStarts(props)
    startsRow("E5 line spacing 1.8: the editor's line starts equal the render's (a CONTROL)",
              editor: lines, render: render)
    let want = renderPitches(props, scale: s.scale)
    let have = pitches(lines.ys)
    let worst = zip(have, want).map { abs($0 - $1) }.max() ?? .infinity
    check("E5 line spacing 1.8: each line pitch is within 1 pt of the render's × scale",
          !want.isEmpty && have.count == want.count && worst <= 1,
          "editor \(list(have)) pt (\(lines.via)), render × scale \(list(want)) pt; worst "
            + String(format: "%.2f", worst))
    close(s)
}

// E6 — size 12: under the old 8 pt clamp, and unfloored.
if let s = open("small", label: "E6 size 12:"), let props = s.box.clip.text {
    let viewSize = CGFloat(props.size) * s.scale
    check("E6 size 12: size × scale is under 8 pt (a CONTROL)", viewSize < 8,
          String(format: "%.2f pt", viewSize))
    let want = s.canvas.canvasToView(s.box.uncroppedRect.insetBy(dx: -2, dy: -2))
    let frame = s.field.frame
    let off = max(abs(frame.minX - want.minX), abs(frame.minY - want.minY),
                  abs(frame.maxX - want.maxX), abs(frame.maxY - want.maxY))
    check("E6 size 12: the editor is not floored — its frame is the box + 2 px within 1 pt "
            + "(a CONTROL)", off <= 1,
          String(format: "off by %.2f pt; editor ", off) + text(frame) + ", box + 2 px "
            + text(want))
    // The wrap width the editor lays out in, against the box's own width in
    // view points (#186 item 1): what E6 compares at 240 px.
    let container = s.field.textContainer
    let wrap = (container?.size.width ?? 0) - 2 * (container?.lineFragmentPadding ?? 0)
    let boxWidth = CGFloat(props.width ?? 0) * s.scale
    startsRow("E6 size 12: the editor's line starts equal the render's",
              editor: editorLines(s.field), render: renderStarts(props),
              extra: String(format: "; the editor's wrap width %.3f pt, width × scale %.3f pt",
                            wrap, boxWidth))
    close(s)
}

// E7 — case: upper is edited as typed (K-3's premise).
if let s = open("upper", label: "E7 case upper:"), let props = s.box.clip.text {
    let first = s.field.string
    caretToEnd(s.field)
    type("ab", into: s.window)
    let second = s.field.string
    check("E7 case upper: the editor holds content, not laidContent, before and after typing "
            + "\"ab\" (a CONTROL)",
          first == props.content && second == props.content + "ab"
            && props.laidContent != props.content,
          "content \"\(props.content)\", laidContent \"\(props.laidContent)\"; editor "
            + "\"\(first)\" then \"\(second)\"")
    close(s)
}

// E8 — tracking 24, emptied by Delete, then "Wrap" typed.
if let s = open("tracking", label: "E8 emptied:") {
    if let delete = keyEvent("\u{7F}", keyCode: 51, window: s.window) {
        s.window.sendEvent(delete)
    }
    spin(0.1)
    check("E8 emptied: Delete over the select-all leaves the editor empty and first "
            + "responder (a CONTROL)",
          s.field.string.isEmpty && s.window.firstResponder === s.field
            && s.canvas.textEditor === s.field,
          "editor \"\(s.field.string)\"")
    type("Wrap", into: s.window)
    let typed = s.field.string
    check("E8 emptied, then \"Wrap\" typed: the editor holds \"Wrap\" (a CONTROL)",
          typed == "Wrap", "editor \"\(typed)\"")
    let lines = editorLines(s.field)
    var wantFont: CGFloat = -1
    var wantKern: CGFloat = 0
    if let clip = s.box.clip.text {
        // The render's own set at scale 1, scaled here: the same numbers as
        // `textAttributes(typed, scale:)` without calling it.
        let rendered = LayerRenderers.attributedString(clip)
        if rendered.length > 0 {
            let attributes = rendered.attributes(at: 0, effectiveRange: nil)
            wantFont = ((attributes[.font] as? NSFont)?.pointSize ?? -1) * s.scale
            wantKern = ((attributes[.kern] as? CGFloat) ?? 0) * s.scale
        }
    }
    var haveFont: CGFloat = -2
    var haveKern: CGFloat = 0
    if let storage = s.field.textStorage, storage.length > 0 {
        let attributes = storage.attributes(at: 0, effectiveRange: nil)
        haveFont = (attributes[.font] as? NSFont)?.pointSize ?? -2
        haveKern = (attributes[.kern] as? CGFloat) ?? 0
    }
    check("E8 emptied, then \"Wrap\" typed: the storage's font size and kern at index 0 are "
            + "the render's × scale",
          abs(haveFont - wantFont) < 0.01 && abs(haveKern - wantKern) < 0.01 && wantKern > 0,
          String(format: "font %.3f pt (want %.3f), kern %.3f (want %.3f)",
                 haveFont, wantFont, haveKern, wantKern))
    s.canvas.cancelTextEditing()
    spin(0.1)
    if let applied = apply(typed, in: s) {
        startsRow("E8 emptied, then \"Wrap\" typed: the editor's line starts equal the applied "
                    + "render's", editor: lines, render: renderStarts(applied))
    } else {
        check("E8 emptied, then \"Wrap\" typed: the editor's line starts equal the applied "
                + "render's", false, "the typed string did not apply")
    }
    close(s)
}

// E9 — auto-sized, centred, one line, tracking 24: the kern must not wrap it.
if let s = open("auto", label: "E9 auto-sized, tracking 24:"), let props = s.box.clip.text {
    let render = renderStarts(props)
    check("E9 auto-sized, tracking 24: the render lays out exactly one line (a CONTROL)",
          render.count == 1, "\(render.count) lines")
    let lines = editorLines(s.field)
    check("E9 auto-sized, tracking 24: the editor lays out exactly one line",
          lines.starts.count == 1, "editor \(lines.starts) (\(lines.via))")
    caretToEnd(s.field)
    type(" again", into: s.window)
    let typed = s.field.string
    let after = editorLines(s.field)
    s.canvas.cancelTextEditing()
    spin(0.1)
    let applied = apply(typed, in: s)
    let appliedLines = applied.map { renderStarts($0).count } ?? -1
    check("E9 after typing \" again\": the applied render has exactly one line (a CONTROL)",
          appliedLines == 1 && typed == props.content + " again",
          "typed \"\(typed)\"; \(appliedLines) lines")
    check("E9 after typing \" again\": the editor still lays out exactly one line",
          after.starts.count == 1, "editor \(after.starts) (\(after.via))")
    close(s)
}

exit(0)
