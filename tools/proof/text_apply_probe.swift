// kpgalligan/framejob#37 — Return applies in the canvas text editor, and Esc
// asks before dropping a change; the probe (`text_apply_proof.py` builds and
// runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line. Under `-D
// HARNESS_REFERENCE_BUILD` it builds over an OLDER `app/Sources` (the proof's
// `--baseline`), where `TextEditKey` does not exist, so K1 is compiled out
// there; every A row calls only what the baseline already had.
//
//   text_apply_probe <request.json> <answer.json>
//
// `request.json` names the package the proof wrote:
//   auto  ONE text clip "Hello" (id 2, 0–6 s, auto-sized, centred)
// One JSON object out: `rows`, each a name, ok and detail.
//
// K1 asks `TextEditKey.route` directly (pure). A drives the app's OWN window
// (`ProjectDocument.makeWindowControllers()`): each row opens its own
// `beginTextEditing(2)` session, puts the caret at the end, sends keys
// through `NSWindow.sendEvent`, and reads the clip's content back from the
// canvas's snapshot, the editor from the view tree, the sheet from
// `window.attachedSheet` and the undo stack from `document.undoManager`.
// Between rows the harness resets: any sheet ended, the editor cancelled,
// every undo step undone.
//
// The sheet never becomes key under `.prohibited` — measured: a Return sent to
// it through its `sendEvent`, `NSApp.sendEvent`, `performKeyEquivalent` or
// `keyDown` pressed nothing — so its buttons are pressed with `performClick`,
// and which button Return and Esc press is READ: Apply as the panel's
// `defaultButtonCell`, Cancel by its `keyEquivalent`.
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

/// A key as the keyboard would deliver it; `windowNumber` 0 for the pure rows.
func key(
    _ type: NSEvent.EventType = .keyDown, flags: NSEvent.ModifierFlags = [],
    keyCode: UInt16, characters: String, windowNumber: Int = 0
) -> NSEvent? {
    NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
}

func visible(_ string: String) -> String {
    string.unicodeScalars.map { scalar -> String in
        switch scalar {
        case "\n": return "\\n"
        case "\r": return "\\r"
        case "\u{2028}": return "\\u2028"
        case "\u{1b}": return "\\e"
        default: return String(scalar)
        }
    }.joined()
}

// MARK: - K1 the route, pure

#if !HARNESS_REFERENCE_BUILD
let routes: [(String, NSEvent?, Bool, TextEditKeyRoute?)] = [
    ("bare Return applies", key(keyCode: 36, characters: "\r"), false, .apply),
    ("keypad Enter applies", key(flags: [.numericPad], keyCode: 76, characters: "\u{3}"),
     false, .apply),
    ("⇪Return applies", key(flags: [.capsLock], keyCode: 36, characters: "\r"), false, .apply),
    ("fn Return applies", key(flags: [.function], keyCode: 36, characters: "\r"), false,
     .apply),
    ("⇧Return is a new line", key(flags: [.shift], keyCode: 36, characters: "\r"), false,
     .newline),
    ("⌘Return is a new line", key(flags: [.command], keyCode: 36, characters: "\r"), false,
     .newline),
    ("⌥Return is a new line", key(flags: [.option], keyCode: 36, characters: "\r"), false,
     .newline),
    ("⌃Return is a new line", key(flags: [.control], keyCode: 36, characters: "\r"), false,
     .newline),
    ("Esc escapes", key(keyCode: 53, characters: "\u{1b}"), false, .escape),
    ("Return with marked text is not routed", key(keyCode: 36, characters: "\r"), true, nil),
    ("Esc with marked text is not routed", key(keyCode: 53, characters: "\u{1b}"), true, nil),
    ("a Return key-up is not routed", key(.keyUp, keyCode: 36, characters: "\r"), false, nil),
    ("a letter is not routed", key(keyCode: 0, characters: "a"), false, nil),
]
for (name, event, marked, want) in routes {
    guard let event = event else {
        check("K1 \(name)", false, "the event could not be made")
        continue
    }
    let got = TextEditKey.route(event, hasMarkedText: marked)
    check("K1 \(name)", got == want,
          "route \(String(describing: got)), want \(String(describing: want))")
}
#endif

// MARK: - A the app's own window

func runWindow() {
    guard let path = request["auto"] as? String else {
        check("A0 the fixture is named", false)
        return
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        check("A0 the fixture opens", false, "\(error)")
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
        check("A0 the window, its canvas and the undo manager open (a CONTROL)", false)
        return
    }
    let id: UInt32 = 2

    func content() -> String { canvas.snapshot.clip(id)?.text?.content ?? "<no clip>" }
    func field() -> CanvasTextView? {
        walk(canvas).first(where: { $0 is CanvasTextView }) as? CanvasTextView
    }
    func send(_ event: NSEvent?) {
        if let event = event { window.sendEvent(event) }
        spin(0.1)
    }
    func typed(_ character: Character) {
        let text = String(character)
        send(key(keyCode: 0, characters: text, windowNumber: window.windowNumber))
    }
    func ret(_ flags: NSEvent.ModifierFlags = []) {
        send(key(flags: flags, keyCode: 36, characters: "\r", windowNumber: window.windowNumber))
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
        "content \"\(visible(content()))\", editor "
            + (field().map { "open \"\(visible($0.string))\"" } ?? "gone")
            + ", sheet \(window.attachedSheet != nil), canUndo \(undo.canUndo)"
    }
    func buttons(_ sheet: NSWindow) -> [String: NSButton] {
        var found: [String: NSButton] = [:]
        for case let button as NSButton in sheet.contentView.map(walk) ?? [] {
            found[button.title] = button
        }
        return found
    }

    // A0 — CONTROL
    let first = session()
    check("A0 the window opens and the editor is first responder (a CONTROL)",
          first != nil && window.firstResponder === first && content() == "Hello",
          state())

    // A1 — Return after typing "!"
    if session() != nil {
        let before = undo.canUndo
        typed("!")
        ret()
        let applied = content() == "Hello!" && field() == nil && !before && undo.canUndo
        let after = state()
        if undo.canUndo { undo.undo() }
        spin(0.1)
        check("A1 Return after typing \"!\" applies it as one undo step and leaves the editor",
              applied && content() == "Hello" && !undo.canUndo,
              "canUndo before \(before); after Return: \(after); after one undo: \(state())")
    } else {
        check("A1 Return after typing \"!\" applies it as one undo step and leaves the editor",
              false, "no session: \(state())")
    }

    // A2 — Return with the string unchanged
    if session() != nil {
        ret()
        check("A2 Return with the string unchanged leaves the editor and sends nothing",
              field() == nil && content() == "Hello" && !undo.canUndo, state())
    } else {
        check("A2 Return with the string unchanged leaves the editor and sends nothing",
              false, "no session: \(state())")
    }

    // A3–A6 — a modified Return is a new line
    let modified: [(String, String, NSEvent.ModifierFlags)] = [
        ("A3", "⇧Return", [.shift]), ("A4", "⌘Return", [.command]),
        ("A5", "⌥Return", [.option]), ("A6", "⌃Return", [.control]),
    ]
    for (label, name, flags) in modified {
        let title = "\(label) \(name) inserts \"\\n\" and the editor stays open"
        guard let editing = session() else {
            check(title, false, "no session: \(state())")
            continue
        }
        ret(flags)
        check(title, field() === editing && editing.string == "Hello\n", state())
        canvas.cancelTextEditing()
        spin(0.1)
    }

    // A7 — CONTROL: Esc on an unchanged string
    if session() != nil {
        esc()
        check("A7 Esc on an unchanged string leaves the editor with no sheet (a CONTROL)",
              field() == nil && window.attachedSheet == nil && content() == "Hello"
                && !undo.canUndo, state())
    } else {
        check("A7 Esc on an unchanged string leaves the editor with no sheet (a CONTROL)",
              false, "no session: \(state())")
    }

    // A8 — Esc after "!" asks; A9 — its Cancel goes back to typing
    let a8 = "A8 Esc after \"!\" attaches a sheet: Cancel · Revert · Apply, Apply on Return, "
        + "Cancel on Esc"
    let a9 = "A9 Cancel on that sheet returns to typing with the text kept"
    if let editing = session() {
        typed("!")
        esc()
        if let sheet = window.attachedSheet {
            let found = buttons(sheet)
            let apply = found["Apply"], revert = found["Revert"], cancel = found["Cancel"]
            // Return is the sheet's default button — on macOS 26 `NSAlert` marks
            // its first button as the panel's `defaultButtonCell` and leaves the
            // button's own `keyEquivalent` empty (measured), so the default cell
            // is what is read; Esc is the Cancel button's own key equivalent.
            let isDefault = apply.map { sheet.defaultButtonCell === $0.cell } ?? false
            check(a8,
                  apply != nil && revert != nil && cancel != nil
                    && isDefault && cancel?.keyEquivalent == "\u{1b}",
                  "buttons \(found.keys.sorted()); Apply is the default button \(isDefault), "
                    + "Cancel key \"\(visible(cancel?.keyEquivalent ?? "-"))\"; \(state())")
            if let cancel = cancel {
                cancel.performClick(nil)
                spin(0.5)
                let back = window.attachedSheet == nil && field() === editing
                    && editing.string == "Hello!" && window.firstResponder === editing
                let backState = state() + ", first responder is the field "
                    + "\(window.firstResponder === editing)"
                typed("?")
                check(a9, back && editing.string == "Hello!?",
                      "after Cancel: \(backState); after \"?\": \(state())")
            } else {
                check(a9, false, "no Cancel button: \(state())")
            }
        } else {
            check(a8, false, "no sheet attached: \(state())")
            check(a9, false, "no sheet to cancel: \(state())")
        }
        canvas.cancelTextEditing()
        spin(0.1)
    } else {
        check(a8, false, "no session: \(state())")
        check(a9, false, "no session: \(state())")
    }

    // A10 — Revert; A11 — Apply
    for (label, button) in [("A10", "Revert"), ("A11", "Apply")] {
        let title = button == "Revert"
            ? "A10 Revert on the sheet closes the editor and leaves the clip untouched"
            : "A11 Apply on the sheet closes the editor and applies \"Hello!\" as one undo step"
        guard session() != nil else {
            check(title, false, "no session: \(state())")
            continue
        }
        typed("!")
        esc()
        guard let sheet = window.attachedSheet, let press = buttons(sheet)[button] else {
            check(title, false, "no sheet attached or no \(button) button: \(state())")
            continue
        }
        press.performClick(nil)
        spin(0.5)
        if button == "Revert" {
            check(title,
                  window.attachedSheet == nil && field() == nil && content() == "Hello"
                    && !undo.canUndo, state())
        } else {
            let applied = window.attachedSheet == nil && field() == nil
                && content() == "Hello!" && undo.canUndo
            let after = state()
            if undo.canUndo { undo.undo() }
            spin(0.1)
            check(title, applied && content() == "Hello" && !undo.canUndo,
                  "after Apply: \(after); after one undo: \(state())")
        }
    }
    reset()
}

runWindow()

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
