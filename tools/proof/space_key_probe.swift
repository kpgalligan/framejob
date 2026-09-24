// kpgalligan/reelcut#35 — Space toggles play wherever nothing is typing; the
// probe (`space_key_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line. Under `-D
// HARNESS_REFERENCE_BUILD` it builds over an OLDER `app/Sources` (the proof's
// `--baseline`), where `SpaceKey` and `EditorWindow` do not exist, so S1 and
// S2g are compiled out there.
//
//   space_key_probe <request.json> <answer.json>
//
// `request.json` names the package the proof wrote:
//   card  one grey shape card of 6 s, clip 2, then 6 s of media/A.mov
//         (clip 3, media 20)
// One JSON object out: `rows`, each a name, ok and detail.
//
// S1 asks `SpaceKey.route` directly (pure). S2 drives the app's OWN window —
// `ProjectDocument.makeWindowControllers()` — with synthesized key events
// through `NSWindow.sendEvent`, and reads `editor.playback.isPlaying`. The
// beep itself is not observable; S2a and S2b together are the claim: the
// window returned before `super.sendEvent`, the only path that beeps.
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

/// A Space (or another key) as the keyboard would deliver it to `window`.
func key(
    _ type: NSEvent.EventType = .keyDown, flags: NSEvent.ModifierFlags = [],
    repeating: Bool = false, keyCode: UInt16 = 49, characters: String = " ",
    window: NSWindow
) -> NSEvent? {
    NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: repeating, keyCode: keyCode)
}

// MARK: - S1 the route, pure

#if !HARNESS_REFERENCE_BUILD
let bare = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled],
    backing: .buffered, defer: true)

func routed(
    _ event: NSEvent?, _ responder: NSResponder?, sheet: Bool = false
) -> SpaceKeyRoute? {
    guard let event else { return nil }
    return SpaceKey.route(event, firstResponder: responder, sheetAttached: sheet)
}

func describe(_ route: SpaceKeyRoute?) -> String {
    route.map { "\($0)" } ?? "nil"
}

func row(_ name: String, _ got: SpaceKeyRoute?, _ want: SpaceKeyRoute?) {
    check("S1 \(name) → \(describe(want))", got == want, "got \(describe(got))")
}

let space = key(window: bare)
let editable = NSTextView()
let selectable = NSTextView()
selectable.isEditable = false
row("the window itself", routed(space, bare), .transport)
row("a plain NSView", routed(space, NSView()), .transport)
row("an NSSlider", routed(space, NSSlider()), .transport)
row("an editable NSTextView", routed(space, editable), .responder)
row("an NSTextView with isEditable = false", routed(space, selectable), .transport)
row("an NSButton", routed(space, NSButton()), .responder)
row("an NSPopUpButton", routed(space, NSPopUpButton()), .responder)
row("an NSSegmentedControl", routed(space, NSSegmentedControl()), .responder)
row("a CanvasOverlayView", routed(space, CanvasOverlayView()), .responder)
row("the window with a sheet attached", routed(space, bare, sheet: true), .responder)
row("an auto-repeat (isARepeat)", routed(key(repeating: true, window: bare), bare), .held)
row("⌘Space", routed(key(flags: .command, window: bare), bare), nil)
row("⌥Space", routed(key(flags: .option, window: bare), bare), nil)
row("⌃Space", routed(key(flags: .control, window: bare), bare), nil)
row("⇧Space", routed(key(flags: .shift, window: bare), bare), .transport)
row("⇪Space (.capsLock)", routed(key(flags: .capsLock, window: bare), bare), .transport)
row("keyCode 38 (\"j\")", routed(key(keyCode: 38, characters: "j", window: bare), bare), nil)
row("a Space key-UP", routed(key(.keyUp, window: bare), bare), nil)
#endif

// MARK: - S2 the app's own window

func opened(_ key: String) -> ProjectDocument? {
    guard let path = request[key] as? String else {
        check("S0 the \(key) fixture is named", false)
        return nil
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        check("S0 the \(key) fixture opens", false, "\(error)")
        return nil
    }
    return document
}

final class CountingView: NSView {
    var keyDowns = 0
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        keyDowns += 1
        super.keyDown(with: event)
    }
}

final class CountingButton: NSButton {
    var presses = 0
    var keyDowns = 0
    override var acceptsFirstResponder: Bool { true }
    @objc func pressed(_ sender: Any?) { presses += 1 }
    override func keyDown(with event: NSEvent) {
        keyDowns += 1
        super.keyDown(with: event)
    }
}

func openEditor() -> (ProjectDocument, EditorViewController, NSWindow)? {
    guard let document = opened("card") else { return nil }
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.5)
    guard let window = document.windowControllers.first?.window,
          let editor = window.contentViewController as? EditorViewController
    else {
        check("S0 the card editor opens", false)
        return nil
    }
    return (document, editor, window)
}

if let (document, editor, window) = openEditor() {
    /// Polls up to 2 s for `want`; answers what `isPlaying` last read.
    func settle(_ want: Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while editor.playback.isPlaying != want && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return editor.playback.isPlaying
    }
    /// Spins a moment, for a state that must NOT change.
    func held() -> Bool {
        spin(0.4)
        return editor.playback.isPlaying
    }
    func send(_ event: NSEvent?) { if let event { window.sendEvent(event) } }
    /// Whether `Playback` has swapped an item in — `play()` beeps without one.
    func ready() -> String {
        "plan built \(editor.playback.builtPlanJSON != nil), rate \(editor.playback.rate)"
    }
    func paused() {
        editor.playback.pause()
        spin(0.2)
    }

    // a. The state `OptionFieldControl.finishEditing` leaves.
    window.makeFirstResponder(nil)
    let windowFirst = window.firstResponder === window
    send(key(window: window))
    let first = settle(true)
    send(key(window: window))
    let second = settle(false)
    check("S2a the window as first responder (a committed inspector field): Space plays, "
            + "Space again pauses",
          windowFirst && first && !second,
          "firstResponder === window \(windowFirst); isPlaying after the first Space \(first), "
            + "after the second \(second); \(ready())")
    paused()

    // b. A custom responder in the content: the window takes the key first.
    let counting = CountingView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    editor.view.addSubview(counting)
    let took = window.makeFirstResponder(counting)
    send(key(window: window))
    let playing = settle(true)
    check("S2b a custom NSView first responder: the view sees no keyDown and play toggles",
          took && counting.keyDowns == 0 && playing,
          "made first responder \(took); keyDowns \(counting.keyDowns); isPlaying \(playing); "
            + ready())
    counting.removeFromSuperview()
    paused()

    // c. The timecode field's field editor: the Space is typed.
    let editing = window.makeFirstResponder(editor.timecodeField)
    send(key(window: window))
    let typed = (window.firstResponder as? NSTextView)?.string ?? "(not a text view)"
    let playingC = held()
    check("S2c the timecode field being typed into: the Space is typed, play stays paused",
          editing && typed.contains(" ") && !playingC,
          "made first responder \(editing); field editor string \"\(typed)\"; "
            + "isPlaying \(playingC)")
    window.makeFirstResponder(editor.view)
    paused()

    // d. The canvas overlay: its own key-down arms, its key-up toggles.
    if let overlay = walk(editor.view).first(where: { $0 is CanvasOverlayView }) {
        let focused = window.makeFirstResponder(overlay)
        send(key(window: window))
        let afterDown = held()
        send(key(.keyUp, window: window))
        let afterUp = settle(true)
        send(key(window: window))
        send(key(.keyUp, window: window))
        let again = settle(false)
        check("S2d the canvas overlay: Space down leaves play alone, Space up toggles it, "
                + "down + up again pauses",
              focused && !afterDown && afterUp && !again,
              "made first responder \(focused); isPlaying after down \(afterDown), after up "
                + "\(afterUp), after down + up \(again)")
    } else {
        check("S2d the canvas overlay is in the editor", false, "no CanvasOverlayView")
    }
    window.makeFirstResponder(editor.view)
    paused()

    // e. A button keeps the key: the window hands it the Space. Whether AppKit
    // then PRESSES it depends on Full Keyboard Access, a host setting, so the
    // press is reported, not scored — remaining §4's hands-on check owns it.
    let button = CountingButton(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
    button.title = "Probe"
    button.target = button
    button.action = #selector(CountingButton.pressed(_:))
    editor.view.addSubview(button)
    let buttonFirst = window.makeFirstResponder(button)
    send(key(window: window))
    let playingE = held()
    check("S2e an NSButton first responder: the window hands it the Space "
            + "(its keyDown sees it once)",
          buttonFirst && button.keyDowns == 1,
          "made first responder \(buttonFirst); keyDowns \(button.keyDowns); "
            + "full keyboard access \(NSApp.isFullKeyboardAccessEnabled); "
            + "presses \(button.presses); isPlaying \(playingE)")
    button.removeFromSuperview()
    window.makeFirstResponder(editor.view)
    paused()

    // f. An auto-repeat is swallowed.
    window.makeFirstResponder(nil)
    send(key(repeating: true, window: window))
    let playingF = held()
    check("S2f the window as first responder: an auto-repeated Space leaves play alone",
          window.firstResponder === window && !playingF, "isPlaying \(playingF)")
    paused()

    #if !HARNESS_REFERENCE_BUILD
    check("S2g the document's window is an EditorWindow",
          document.windowControllers.first?.window is EditorWindow,
          "\(type(of: window))")
    #endif
}

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
