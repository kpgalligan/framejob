// kpgalligan/reelcut#36 — the canvas text editor grows as you type; the probe
// (`text_edit_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line. Everything it calls exists in
// the baseline tree too, so the proof's `--baseline` builds the same source.
//
//   text_edit_probe <request.json> <answer.json>
//
// `request.json` names `fonts`, the app's `app/Resources/Fonts` (the app
// bundle registers them through `ATSApplicationFontsPath`; a bare binary has
// no bundle, so the probe registers them itself, as `harness/main.swift`
// does — without them the editor and CoreText fall back to DIFFERENT fonts
// and their line breaks part), and the three packages the proof wrote, each
// ONE text clip (id 2, 0–6 s, the playhead on it):
//   auto   auto-sized (`width` null), centred, no backdrop
//   fixed  a fixed `width`, left-aligned, with a backdrop whose padding
//          widens the box beyond the wrap width
//   short  auto-sized, left-aligned, 12 px — a box under the editor's floor
// One JSON object out: `rows`, each a name, ok and detail.
//
// Per fixture: the app's OWN window (`ProjectDocument.makeWindowControllers()`)
// opens the clip's in-canvas editor with `beginTextEditing`, puts the caret
// at the end, and types the fixture's string one key event at a time through
// `NSWindow.sendEvent`, recording after each key the editor's frame and how
// many lines the editor laid the string out in. The edit is then cancelled
// and each typed prefix is APPLIED through the canvas's own `onEdit` (the
// `set_text` a commit sends); the box the canvas then draws for the clip,
// grown by the editor's 2 canvas-pixel margin and mapped to view points, is
// the frame the editor should have had, within `tolerance` — and CoreText's line
// count for the applied text (`LayerRenderers.layout(for:)`, what the
// compositor draws) is the line count it should have shown.
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
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

/// Points, per edge, between the editor's frame and the applied box grown by
/// the editor's 2 canvas-pixel margin.
let tolerance: CGFloat = 1

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}

let fonts = URL(fileURLWithPath: request["fonts"] as? String ?? "/nonexistent")
for name in (try? FileManager.default.contentsOfDirectory(atPath: fonts.path)) ?? []
where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
    CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent(name) as CFURL, .process, nil)
}
check("T0 the fixtures' font SourceSans3-SemiBold resolves (a CONTROL)",
      NSFont(name: "SourceSans3-SemiBold", size: 12) != nil, fonts.path)

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func typed(_ character: Character, window: NSWindow) -> NSEvent? {
    let text = String(character)
    return NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: text,
        charactersIgnoringModifiers: text, isARepeat: false,
        keyCode: character == " " ? 49 : 0)
}

/// How many line fragments the editor laid its string out in.
func editorLines(_ editor: NSTextView) -> Int {
    guard let manager = editor.layoutManager, let container = editor.textContainer else {
        return -1
    }
    manager.ensureLayout(for: container)
    var count = 0
    manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) {
        _, _, _, _, _ in count += 1
    }
    return count
}

func text(_ rect: CGRect) -> String {
    String(format: "(%.1f, %.1f, %.1f × %.1f)", rect.minX, rect.minY, rect.width, rect.height)
}

func deviation(_ a: CGRect, _ b: CGRect) -> CGFloat {
    max(abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.maxX - b.maxX), abs(a.maxY - b.maxY))
}

func opened(_ key: String) -> ProjectDocument? {
    guard let path = request[key] as? String else {
        check("T0 \(key): the fixture is named", false)
        return nil
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        check("T0 \(key): the fixture opens", false, "\(error)")
        return nil
    }
    return document
}

struct Keystroke {
    let string: String
    let frame: CGRect
    let lines: Int
}

/// `label` is the row prefix; `keys` the string typed after the content.
func run(_ key: String, label: String, keys: String) {
    guard let document = opened(key) else { return }
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.5)
    guard let window = document.windowControllers.first?.window,
          let editor = window.contentViewController as? EditorViewController,
          let canvas = walk(editor.view).first(where: { $0 is PreviewCanvasView })
            as? PreviewCanvasView
    else {
        check("\(label) the editor window and its canvas open", false)
        return
    }
    let id: UInt32 = 2
    guard let before = canvas.box(for: id) else {
        check("\(label) the text clip has a box on the canvas", false)
        return
    }
    canvas.beginTextEditing(id)
    spin(0.2)
    guard let field = walk(canvas).first(where: { $0 is CanvasTextView }) as? CanvasTextView,
          window.firstResponder === field
    else {
        check("\(label) the in-canvas editor opens and takes the keys", false,
              "first responder \(String(describing: window.firstResponder))")
        return
    }
    field.setSelectedRange(NSRange(location: (field.string as NSString).length, length: 0))
    let start = field.string
    var strokes: [Keystroke] = []
    for character in keys {
        if let event = typed(character, window: window) { window.sendEvent(event) }
        spin(0.03)
        strokes.append(Keystroke(string: field.string, frame: field.frame,
                                 lines: editorLines(field)))
    }
    let reached = strokes.last?.string ?? ""
    check("\(label) every key was typed into the editor (a CONTROL)",
          reached == start + keys, "typed \"\(reached)\"")
    canvas.cancelTextEditing()
    spin(0.1)

    var worst: (CGFloat, String) = (0, "")
    var mismatchedLines: [String] = []
    var applied: [CanvasLayerBox] = []
    var appliedOK = true
    for stroke in strokes {
        canvas.onEdit?(
            "Edit Text", [.setText(clips: [id], patch: TextPatch(content: stroke.string))])
        spin(0.05)
        guard let box = canvas.box(for: id), let props = box.clip.text,
              props.content == stroke.string
        else {
            appliedOK = false
            break
        }
        applied.append(box)
        let want = canvas.canvasToView(box.uncroppedRect.insetBy(dx: -2, dy: -2))
        let off = deviation(stroke.frame, want)
        if off > worst.0 {
            worst = (off, "after \"\(stroke.string)\": editor \(text(stroke.frame)), "
                        + "applied box + 2 px \(text(want))")
        }
        let rendered = LayerRenderers.layout(for: props).lines.count
        if stroke.lines != rendered {
            mismatchedLines.append("\"\(stroke.string)\": editor \(stroke.lines), "
                                   + "rendered \(rendered)")
        }
    }
    check("\(label) each typed prefix applies and the canvas redraws its box (a CONTROL)",
          appliedOK && applied.count == strokes.count,
          "\(applied.count) of \(strokes.count) applied")
    guard appliedOK, let last = applied.last else { return }
    let lastLines = last.clip.text.map { LayerRenderers.layout(for: $0).lines.count } ?? 0
    check("\(label) typing changes the applied box (a CONTROL): width or height moved",
          abs(last.uncroppedRect.width - before.uncroppedRect.width) > 1
            || abs(last.uncroppedRect.height - before.uncroppedRect.height) > 1,
          "box before \(text(before.uncroppedRect)), after \(text(last.uncroppedRect)) "
            + "canvas px; the applied text lays out in \(lastLines) line(s)")
    check("\(label) after EVERY key the editor's frame is the applied box + 2 px, "
            + "within \(tolerance) pt",
          worst.0 <= tolerance,
          String(format: "worst deviation %.2f pt over %d keys", worst.0, strokes.count)
            + (worst.1.isEmpty ? "" : "; \(worst.1)"))
    check("\(label) after EVERY key the editor shows as many lines as the applied text "
            + "renders",
          mismatchedLines.isEmpty,
          mismatchedLines.isEmpty
            ? "\(strokes.count) keys, all equal"
            : "\(mismatchedLines.count) of \(strokes.count) differ: "
                + mismatchedLines.prefix(4).joined(separator: "; "))
}

/// T3: a string shorter than the editor's 60 × 24 pt floor, left-aligned. The
/// floor widens the frame past the box, so the frame cannot BE the box; what
/// must hold is that the text starts where it renders — the frame hung from
/// the box's top-left corner (a floor centred on the box would start a
/// left-aligned string (60 − w) / 2 pt early). Nothing is typed: the box the
/// clip has is the box its string has, and the fit is the one every key runs.
func runFloor(_ key: String, label: String) {
    guard let document = opened(key) else { return }
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.5)
    guard let window = document.windowControllers.first?.window,
          let editor = window.contentViewController as? EditorViewController,
          let canvas = walk(editor.view).first(where: { $0 is PreviewCanvasView })
            as? PreviewCanvasView
    else {
        check("\(label) the editor window and its canvas open", false)
        return
    }
    let id: UInt32 = 2
    guard let box = canvas.box(for: id) else {
        check("\(label) the text clip has a box on the canvas", false)
        return
    }
    canvas.beginTextEditing(id)
    spin(0.2)
    guard let field = walk(canvas).first(where: { $0 is CanvasTextView }) as? CanvasTextView
    else {
        check("\(label) the in-canvas editor opens", false)
        return
    }
    let frame = field.frame
    canvas.cancelTextEditing()
    spin(0.1)
    let want = canvas.canvasToView(box.uncroppedRect.insetBy(dx: -2, dy: -2))
    check("\(label) the box is under the 60 × 24 pt floor (a CONTROL)",
          want.width < 60 && want.height < 24,
          "\"\(box.clip.text?.content ?? "")\": box + 2 px \(text(want))")
    let off = max(abs(frame.minX - want.minX), abs(frame.minY - want.minY))
    check("\(label) the editor hangs from the box's top-left, within \(tolerance) pt",
          off <= tolerance,
          String(format: "off by %.2f pt; editor ", off) + text(frame)
            + ", box + 2 px " + text(want))
}

run("auto", label: "T1 auto-sized:", keys: " world, and more")
run("fixed", label: "T2 fixed width:", keys: " a longer sentence that must wrap twice")
runFloor("short", label: "T3 under the floor, left-aligned:")

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
