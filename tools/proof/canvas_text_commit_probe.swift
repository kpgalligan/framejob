// kpgalligan/framejob#345 — both canvas text commits send their `set_text`
// through `TextPatch.contentEdit` (spec §11 W-2); the probe
// (`canvas_text_commit_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`, on
// `swift_build.py`'s line. Under `-D HARNESS_REFERENCE_BUILD` it builds over
// an OLDER `app/Sources` (the proof's `--baseline`), where
// `PreviewCanvasView.textCommitOp` does not exist, so P1 is compiled out
// there; every C and W row calls only what the baseline already had.
//
//   canvas_text_commit_probe <request.json> <answer.json>
//
// `request.json` names the package the proof wrote:
//   page  ONE text clip "so here's the thing" (id 2, 0–6 s, auto-sized)
// One JSON object out: `rows`, each a name, ok and detail.
//
// The probe times the page itself — one `set_text` carrying four word
// timings, half a second each — and then empties the undo stack, so undoing
// every step returns to the TIMED page. W1–W5 drive the app's OWN window
// (`ProjectDocument.makeWindowControllers()`): each row opens its own
// `beginTextEditing(2)` session, puts the caret at the end, sends keys through
// `NSWindow.sendEvent`, commits by Return, by the Esc sheet's Apply or by a
// blur, and reads the page back from the canvas's snapshot (its content and
// its number of word timings), the sheet from `window.attachedSheet` and the
// undo stack from `document.undoManager`. A failing commit is an error sheet
// (`ProjectDocument+Alerts.swift`), so "no sheet attached" is part of each
// W row. Between rows the harness resets: any sheet ended, the editor
// cancelled, every undo step undone. P1 asks `textCommitOp` directly (pure).
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

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

/// A key as the keyboard would deliver it.
func key(
    _ type: NSEvent.EventType = .keyDown, flags: NSEvent.ModifierFlags = [],
    keyCode: UInt16, characters: String, windowNumber: Int = 0
) -> NSEvent? {
    NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
}

let page = "so here's the thing"
let half = ReelTime.perSecond / 2
let timings = (0..<4).map { TextWord(start: Ticks($0) * half, end: Ticks($0 + 1) * half) }

func runWindow() {
    guard let path = request["page"] as? String else {
        check("C0 the fixture is named", false)
        return
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        check("C0 the fixture opens", false, "\(error)")
        return
    }
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.5)
    guard let window = document.windowControllers.first?.window,
          let editor = window.contentViewController as? EditorViewController,
          let canvas = walk(editor.view).first(where: { $0 is PreviewCanvasView })
            as? PreviewCanvasView,
          let undo = document.undoManager
    else {
        check("C0 the window, its canvas and the undo manager open (a CONTROL)", false)
        return
    }
    let id: UInt32 = 2

    // The page timed, as a transcript would leave it; then no undo step, so
    // `reset()` comes back here.
    document.applyEdit("Time Words", [.setText(
        clips: [id], patch: TextPatch(content: page, words: timings))])
    spin(0.2)
    undo.removeAllActions()

    func content() -> String { canvas.snapshot.clip(id)?.text?.content ?? "<no clip>" }
    func words() -> Int { canvas.snapshot.clip(id)?.text?.words.count ?? -1 }
    func field() -> CanvasTextView? {
        walk(canvas).first(where: { $0 is CanvasTextView }) as? CanvasTextView
    }
    func send(_ event: NSEvent?) {
        if let event = event { window.sendEvent(event) }
        spin(0.1)
    }
    func typed(_ text: String) {
        for character in text {
            let code: UInt16 = character == " " ? 49 : 0
            send(key(keyCode: code, characters: String(character),
                     windowNumber: window.windowNumber))
        }
    }
    func ret() {
        send(key(keyCode: 36, characters: "\r", windowNumber: window.windowNumber))
    }
    func esc() {
        send(key(keyCode: 53, characters: "\u{1b}", windowNumber: window.windowNumber))
    }
    func reset() {
        if let sheet = window.attachedSheet {
            window.endSheet(sheet, returnCode: .alertThirdButtonReturn)
            spin(0.3)
        }
        canvas.cancelTextEditing()
        if let sheet = window.attachedSheet {
            window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
            spin(0.3)
        }
        while undo.canUndo { undo.undo() }
        spin(0.1)
    }
    /// A new session over the clip, the caret at the end of its string.
    func session() -> CanvasTextView? {
        reset()
        canvas.beginTextEditing(id)
        spin(0.2)
        guard let editing = field() else { return nil }
        editing.setSelectedRange(
            NSRange(location: (editing.string as NSString).length, length: 0))
        return editing
    }
    func state() -> String {
        "content \"\(content())\", \(words()) words, editor "
            + (field().map { "open \"\($0.string)\"" } ?? "gone")
            + ", sheet \(window.attachedSheet != nil), canUndo \(undo.canUndo), "
            + "undo name \"\(undo.undoActionName)\""
    }
    /// One "Edit Text" step left `want` with `count` timings, no sheet and no
    /// editor; one undo brings the timed page back.
    func landed(_ title: String, _ want: String, _ count: Int, before: Bool) {
        let applied = content() == want && words() == count && field() == nil
            && window.attachedSheet == nil && !before && undo.canUndo
            && undo.undoActionName == "Edit Text"
        let after = state()
        if undo.canUndo, window.attachedSheet == nil { undo.undo() }
        spin(0.1)
        let back = content() == page && words() == 4 && !undo.canUndo
        check(title, applied && back,
              "canUndo before \(before); after the commit: \(after); after one undo: \(state())")
    }

    // C0 — CONTROL
    let first = session()
    check("C0 the window, canvas and editor open over the timed page (a CONTROL)",
          first != nil && window.firstResponder === first && content() == page
            && words() == 4 && !undo.canUndo,
          state())

    // W1 — Return after a word is added
    let w1 = "W1 Return after typing \" now\" lands the page untimed as one \"Edit Text\" step"
    if session() != nil {
        let before = undo.canUndo
        typed(" now")
        ret()
        landed(w1, page + " now", 0, before: before)
    } else {
        check(w1, false, "no session: \(state())")
    }

    // W2 — Return with the word count unchanged
    let w2 = "W2 Return after typing \"!\" keeps the 4 timings, one \"Edit Text\" step"
    if session() != nil {
        let before = undo.canUndo
        typed("!")
        ret()
        landed(w2, page + "!", 4, before: before)
    } else {
        check(w2, false, "no session: \(state())")
    }

    // W3 — the Esc sheet's Apply after a word is added
    let w3 = "W3 Esc, then Apply, after typing \" now\" lands the page untimed as one "
        + "\"Edit Text\" step"
    if session() != nil {
        let before = undo.canUndo
        typed(" now")
        esc()
        var pressed = false
        if let sheet = window.attachedSheet {
            for case let button as NSButton in sheet.contentView.map(walk) ?? []
            where button.title == "Apply" {
                button.performClick(nil)
                pressed = true
            }
        }
        spin(0.5)
        if pressed {
            landed(w3, page + " now", 0, before: before)
        } else {
            check(w3, false, "no sheet with an Apply button: \(state())")
        }
    } else {
        check(w3, false, "no session: \(state())")
    }

    // W4 — Return with the string unchanged
    let w4 = "W4 Return with the string unchanged sends nothing and keeps the 4 timings"
    if session() != nil {
        ret()
        check(w4, field() == nil && window.attachedSheet == nil && content() == page
                && words() == 4 && !undo.canUndo, state())
    } else {
        check(w4, false, "no session: \(state())")
    }

    // W5 — the blur commit after a word is added
    let w5 = "W5 a blur after typing \" now\" lands the page untimed as one \"Edit Text\" step"
    if session() != nil {
        let before = undo.canUndo
        typed(" now")
        window.makeFirstResponder(canvas.overlay)
        spin(0.3)
        landed(w5, page + " now", 0, before: before)
    } else {
        check(w5, false, "no session: \(state())")
    }

    reset()

    // P1 — the helper itself, pure, over the timed page
    #if !HARNESS_REFERENCE_BUILD
    let snapshot = canvas.snapshot
    let same = PreviewCanvasView.textCommitOp(clip: id, value: page, in: snapshot)
    check("P1 textCommitOp answers nil for the unchanged string", same == nil,
          same?.json ?? "nil")
    let missing = PreviewCanvasView.textCommitOp(clip: 99, value: "x", in: snapshot)
    check("P1 textCommitOp answers nil for a clip not in the snapshot", missing == nil,
          missing?.json ?? "nil")
    func patch(_ op: ReelOp?) -> [String: Any]? {
        guard let text = op?.json, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["patch"] as? [String: Any]
    }
    let grown = PreviewCanvasView.textCommitOp(clip: id, value: page + " now", in: snapshot)
    let grownPatch = patch(grown)
    check("P1 textCommitOp for \" now\" carries words: [] beside the content",
          (grownPatch?["words"] as? [Any])?.isEmpty == true
            && grownPatch?["content"] as? String == page + " now",
          grown?.json ?? "nil")
    let kept = PreviewCanvasView.textCommitOp(clip: id, value: page + "!", in: snapshot)
    let keptPatch = patch(kept)
    check("P1 textCommitOp for \"!\" has no words key",
          keptPatch != nil && keptPatch?["words"] == nil
            && keptPatch?["content"] as? String == page + "!",
          kept?.json ?? "nil")
    #endif
}

runWindow()

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
