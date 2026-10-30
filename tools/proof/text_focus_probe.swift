// Spec §11 K-4 — typing in the editor window is focus-averse; the probe
// (`text_focus_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` —
// `swift_build.py`'s line. Under `-D HARNESS_REFERENCE_BUILD` it builds over
// an OLDER `app/Sources` (the proof's `--baseline`), where `TextFocus` does
// not exist, so F1 is compiled out there.
//
//   text_focus_probe <request.json> <answer.json>
//
// `request.json` names the package the proof wrote (`space_key_proof.py`'s
// card: a grey shape card of 6 s, clip 2, then 6 s of media/A.mov).
// One JSON object out: `rows`, each a name, ok and detail.
//
// F1 asks `TextFocus` directly (pure). F2 drives the app's OWN window —
// `ProjectDocument.makeWindowControllers()` — with synthesized key and mouse
// events through `NSWindow.sendEvent`, and reads the first responder, what
// each field committed and `editor.playback.isPlaying`. A mouse-down is sent
// with its mouse-up already queued, so a view that tracks the mouse in a
// loop of its own (a field editor) finds its end. F3 is the Assistant
// composer's Return in a window of its own whose root takes first responder,
// as the editor's does, so no turn starts.
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

/// A key as the keyboard would deliver it to `window`.
func key(
    _ keyCode: UInt16, _ characters: String, flags: NSEvent.ModifierFlags = [],
    type: NSEvent.EventType = .keyDown, window: NSWindow
) -> NSEvent? {
    NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
}

func returnKey(_ window: NSWindow, flags: NSEvent.ModifierFlags = []) -> NSEvent? {
    key(36, "\r", flags: flags, window: window)
}

func tabKey(_ window: NSWindow, flags: NSEvent.ModifierFlags = []) -> NSEvent? {
    key(48, flags.contains(.shift) ? "\u{19}" : "\t", flags: flags, window: window)
}

func spaceKey(_ window: NSWindow) -> NSEvent? { key(49, " ", window: window) }

/// What the first responder is, for a detail.
func describe(_ responder: NSResponder?, root: NSView) -> String {
    guard let responder else { return "nil" }
    if responder === root { return "the content view" }
    if let text = responder as? NSTextView, text.isFieldEditor {
        return "a field editor of \(text.delegate.map { "\(type(of: $0))" } ?? "nothing")"
    }
    return "\(type(of: responder))"
}

// MARK: - F1 the rule, pure

#if !HARNESS_REFERENCE_BUILD
do {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
        backing: .buffered, defer: false)
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    window.contentView = root
    let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 120, height: 22))
    root.addSubview(field)
    var number = 5.0
    let framed = OptionFieldControl(
        width: 60, unit: " px", decimals: 0, min: 0, max: 100,
        read: { number }, write: { number = $0 }, enabled: { true }, onEdit: {})
    framed.frame = NSRect(x: 10, y: 50, width: 60, height: DS.controlHeight)
    root.addSubview(framed)
    let scroll = NSScrollView(frame: NSRect(x: 150, y: 10, width: 200, height: 80))
    scroll.hasVerticalScroller = true
    let area = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
    scroll.documentView = area
    root.addSubview(scroll)
    let bare = NSTextView(frame: NSRect(x: 150, y: 120, width: 120, height: 40))
    root.addSubview(bare)
    let sibling = NSView(frame: NSRect(x: 300, y: 200, width: 40, height: 40))
    root.addSubview(sibling)
    let selectable = NSTextView()
    selectable.isEditable = false

    func row(_ name: String, _ got: Bool, _ want: Bool, _ detail: String = "") {
        check("F1 \(name) → \(want)", got == want, "got \(got)\(detail.isEmpty ? "" : "; " + detail)")
    }

    check("F1 typing: nil, a plain NSView and a non-editable NSTextView are not typing",
          TextFocus.typing(nil) == nil && TextFocus.typing(NSView()) == nil
            && TextFocus.typing(selectable) == nil)
    check("F1 typing: an editable NSTextView is itself", TextFocus.typing(area) === area)

    let fieldTook = window.makeFirstResponder(field)
    let editor = window.firstResponder as? NSTextView
    check("F1 a field's field editor is first responder (the rows below need it)",
          fieldTook && editor?.isFieldEditor == true,
          "made first responder \(fieldTook); first responder \(describe(window.firstResponder, root: root))")
    if let editor {
        func leaves(_ event: NSEvent?, fullKeyboardAccess: Bool = false) -> Bool {
            event.map {
                TextFocus.leavesOnKey($0, in: editor, fullKeyboardAccess: fullKeyboardAccess)
            } ?? false
        }
        row("Return in a field editor", leaves(returnKey(window)), true)
        row("keypad Enter (76, .numericPad) in a field editor",
            leaves(key(76, "\u{3}", flags: .numericPad, window: window)), true)
        row("⇧Return in a field editor", leaves(returnKey(window, flags: .shift)), true)
        row("⇪Return in a field editor", leaves(returnKey(window, flags: .capsLock)), true)
        row("⌥Return in a field editor", leaves(returnKey(window, flags: .option)), false)
        row("⌘Return in a field editor", leaves(returnKey(window, flags: .command)), false)
        row("⌃Return in a field editor", leaves(returnKey(window, flags: .control)), false)
        row("Tab in a field editor", leaves(tabKey(window)), true)
        row("⇧Tab in a field editor", leaves(tabKey(window, flags: .shift)), true)
        row("⌃Tab in a field editor", leaves(tabKey(window, flags: .control)), false)
        row("⌥Tab in a field editor", leaves(tabKey(window, flags: .option)), false)
        row("Tab in a field editor with Full Keyboard Access on (AppKit's key-view loop)",
            leaves(tabKey(window), fullKeyboardAccess: true), false)
        row("⇧Tab in a field editor with Full Keyboard Access on",
            leaves(tabKey(window, flags: .shift), fullKeyboardAccess: true), false)
        row("Return in a field editor with Full Keyboard Access on",
            leaves(returnKey(window), fullKeyboardAccess: true), true)
        row("Space in a field editor", leaves(spaceKey(window)), false)
        row("\"a\" in a field editor", leaves(key(0, "a", window: window)), false)
        row("a Return key-UP in a field editor",
            leaves(key(36, "\r", type: .keyUp, window: window)), false)
        editor.setMarkedText(
            "か", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = editor.hasMarkedText()
        row("Return in a field editor with marked text", leaves(returnKey(window)), false,
            "hasMarkedText \(marked)")
        row("Tab in a field editor with marked text", leaves(tabKey(window)), false,
            "hasMarkedText \(marked)")
        editor.unmarkText()

        check("F1 host: a field editor's host is its field",
              TextFocus.host(of: editor) === field,
              "host \(type(of: TextFocus.host(of: editor)))")
        row("a click on the field itself", TextFocus.leavesOnClick(hit: field, in: editor), false)
        row("a click on the field editor", TextFocus.leavesOnClick(hit: editor, in: editor), false)
        row("a click on a sibling view", TextFocus.leavesOnClick(hit: sibling, in: editor), true)
        row("a click on the content view", TextFocus.leavesOnClick(hit: root, in: editor), true)
        row("a click outside the content view (hit nil)",
            TextFocus.leavesOnClick(hit: nil, in: editor), false)
    }

    let inner = walk(framed).first { $0 is NSTextField } as? NSTextField
    let framedTook = inner.map { window.makeFirstResponder($0) } ?? false
    if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor, framedTook {
        check("F1 host: an OptionFieldControl's field editor's host is the control",
              TextFocus.host(of: editor) === framed,
              "host \(type(of: TextFocus.host(of: editor)))")
        row("a click on the OptionFieldControl's margin",
            TextFocus.leavesOnClick(hit: framed, in: editor), false)
    } else {
        check("F1 the OptionFieldControl's field takes first responder", false,
              "inner field \(inner != nil); made first responder \(framedTook)")
    }

    window.makeFirstResponder(area)
    check("F1 host: a scrolled text view's host is its scroll view",
          TextFocus.host(of: area) === scroll)
    func areaLeaves(_ event: NSEvent?, fullKeyboardAccess: Bool = false) -> Bool {
        event.map {
            TextFocus.leavesOnKey($0, in: area, fullKeyboardAccess: fullKeyboardAccess)
        } ?? false
    }
    row("Return in a text view that is not a field editor", areaLeaves(returnKey(window)), false)
    row("keypad Enter in a text view that is not a field editor",
        areaLeaves(key(76, "\u{3}", flags: .numericPad, window: window)), false)
    row("Tab in a text view that is not a field editor", areaLeaves(tabKey(window)), true)
    row("Tab in a text view that is not a field editor, Full Keyboard Access on",
        areaLeaves(tabKey(window), fullKeyboardAccess: true), false)
    row("a click on the scroll view's scroller",
        TextFocus.leavesOnClick(hit: scroll.verticalScroller, in: area), false,
        "scroller \(scroll.verticalScroller != nil)")
    row("a click beside the scrolled text view",
        TextFocus.leavesOnClick(hit: sibling, in: area), true)

    check("F1 host: a text view in no scroll view is its own host",
          TextFocus.host(of: bare) === bare)
    row("a click on that text view", TextFocus.leavesOnClick(hit: bare, in: bare), false)
    row("a click beside it", TextFocus.leavesOnClick(hit: sibling, in: bare), true)
}
#endif

// MARK: - F2 the app's own window

func opened(_ key: String) -> ProjectDocument? {
    guard let path = request[key] as? String else {
        check("F0 the \(key) fixture is named", false)
        return nil
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        check("F0 the \(key) fixture opens", false, "\(error)")
        return nil
    }
    return document
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
        check("F0 the card editor opens", false)
        return nil
    }
    return (document, editor, window)
}

if let (document, editor, window) = openEditor() {
    let root = editor.view
    func send(_ event: NSEvent?) { if let event { window.sendEvent(event) } }
    func first() -> String { describe(window.firstResponder, root: root) }
    func atRoot() -> Bool { window.firstResponder === root }
    /// Polls up to 2 s for `want`; answers what `isPlaying` last read.
    func settle(_ want: Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while editor.playback.isPlaying != want && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return editor.playback.isPlaying
    }
    func paused() {
        editor.playback.pause()
        spin(0.2)
    }
    /// Space plays from here, and the pause after it is undone.
    func spacePlays() -> Bool {
        send(spaceKey(window))
        let playing = settle(true)
        paused()
        return playing
    }
    /// Replaces whatever the first responder holds with `text`, as typing.
    func type(_ text: String) -> Bool {
        guard let editor = window.firstResponder as? NSTextView else { return false }
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        return true
    }
    /// A mouse-down at `point` (window coordinates), its mouse-up queued first.
    func click(at point: NSPoint, type: NSEvent.EventType = .leftMouseDown) {
        let up: NSEvent.EventType = type == .rightMouseDown ? .rightMouseUp : .leftMouseUp
        if let release = NSEvent.mouseEvent(
            with: up, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: 0)
        {
            NSApp.postEvent(release, atStart: false)
        }
        send(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: 1))
        spin(0.3)
    }
    func center(of view: NSView) -> NSPoint {
        view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    }
    let fps = document.editedProject.snapshot.canvas.fps
    // The Tab rows below (F2b, F2c, F2g, F2j, F2k) are K-4's Tab, which the
    // window applies only with Full Keyboard Access off — a host setting.
    let fullKeyboardAccess = NSApp.isFullKeyboardAccessEnabled
    check("F2z Full Keyboard Access is off on this host (the Tab rows' premise; with it on, "
            + "Tab is AppKit's key-view loop by K-4's exception)",
          !fullKeyboardAccess, "NSApp.isFullKeyboardAccessEnabled \(fullKeyboardAccess)")

    // a. The toolbar's timecode: Return commits and leaves; Space then plays.
    window.makeFirstResponder(root)
    let typedA = window.makeFirstResponder(editor.timecodeField) && type("00:00:01:00")
    send(returnKey(window))
    spin(0.2)
    let wantA = ReelTime.parse("00:00:01:00", fps: fps)
    let leftA = atRoot()
    let firstA = first()
    let movedA = document.playhead == wantA
    let playsA = leftA && spacePlays()
    check("F2a the toolbar timecode: Return commits (the playhead moves), first responder is "
            + "the content view, and Space then plays",
          typedA && leftA && movedA && playsA,
          "typed \(typedA); first responder \(firstA); playhead \(document.playhead) "
            + "(want \(wantA.map { "\($0)" } ?? "nil")); Space played \(playsA)")

    // b. The same field: Tab commits and leaves; no other field takes it.
    window.makeFirstResponder(root)
    let typedB = window.makeFirstResponder(editor.timecodeField) && type("00:00:02:00")
    send(tabKey(window))
    spin(0.2)
    let wantB = ReelTime.parse("00:00:02:00", fps: fps)
    let leftB = atRoot()
    check("F2b the toolbar timecode: Tab commits and first responder is the content view",
          typedB && leftB && document.playhead == wantB,
          "typed \(typedB); first responder \(first()); playhead \(document.playhead) "
            + "(want \(wantB.map { "\($0)" } ?? "nil"))")

    // c. ⇧Tab the same.
    window.makeFirstResponder(root)
    let typedC = window.makeFirstResponder(editor.timecodeField) && type("00:00:03:00")
    send(tabKey(window, flags: .shift))
    spin(0.2)
    let wantC = ReelTime.parse("00:00:03:00", fps: fps)
    check("F2c the toolbar timecode: ⇧Tab commits and first responder is the content view",
          typedC && atRoot() && document.playhead == wantC,
          "typed \(typedC); first responder \(first()); playhead \(document.playhead)")

    // d. The clip header's name field, the inspector's own: Return commits the
    // name and leaves; Space then plays.
    document.selection = [2]
    editor.refreshFromDocument(isLive: false)
    spin(0.5)
    let inspectorRoot = editor.inspector?.view
    let nameField = inspectorRoot.flatMap { view in
        walk(view).compactMap { $0 as? InspectorNameField }.first { !$0.isHiddenOrHasHiddenAncestor }
    }
    if let nameField {
        window.makeFirstResponder(root)
        let typedD = window.makeFirstResponder(nameField) && type("Renamed")
        send(returnKey(window))
        spin(0.3)
        let nameD = document.editedProject.snapshot.clip(2)?.name
        let leftD = atRoot()
        let firstD = first()
        let playsD = leftD && spacePlays()
        check("F2d the clip header's name field: Return commits the name, first responder is "
                + "the content view, and Space then plays",
              typedD && nameD == "Renamed" && leftD && playsD,
              "typed \(typedD); clip 2 name \(nameD ?? "nil"); first responder \(firstD); "
                + "Space played \(playsD)")

        // e. A click on the timeline — which refuses first responder — ends
        // the typing; the name commits and Space plays.
        window.makeFirstResponder(root)
        let typedE = window.makeFirstResponder(nameField) && type("Clicked away")
        let lane = editor.timelineContainer
        let point = lane.convert(NSPoint(x: lane.bounds.maxX - 30, y: lane.bounds.midY), to: nil)
        click(at: point)
        let nameE = document.editedProject.snapshot.clip(2)?.name
        let editingE = (window.firstResponder as? NSTextView)?.isFieldEditor == true
        let firstE = first()
        let playsE = !editingE && spacePlays()
        check("F2e a click on the timeline while the name is typed: the name commits, no field "
                + "editor is first responder, and Space then plays",
              typedE && nameE == "Clicked away" && !editingE && playsE,
              "typed \(typedE); clip 2 name \(nameE ?? "nil"); first responder \(firstE); "
                + "Space played \(playsE)")
    } else {
        check("F2d the clip header's name field is in the inspector", false,
              "inspector \(inspectorRoot != nil); no visible InspectorNameField")
        check("F2e (needs F2d's name field)", false)
    }

    // f. A click INSIDE the field being typed into keeps the typing.
    window.makeFirstResponder(root)
    let focusedF = window.makeFirstResponder(editor.timecodeField)
    click(at: center(of: editor.timecodeField))
    let keptF = (window.firstResponder as? NSTextView).map {
        $0.isFieldEditor && ($0.delegate as AnyObject?) === editor.timecodeField
    } ?? false
    check("F2f a click inside the timecode field being typed into: its field editor stays "
            + "first responder",
          focusedF && keptF, "made first responder \(focusedF); first responder \(first())")
    window.makeFirstResponder(root)

    // g. An OptionFieldControl in the content: Tab commits its number and
    // leaves; a click on its own margin keeps the typing.
    var number = 5.0
    let framed = OptionFieldControl(
        width: 60, unit: " px", decimals: 0, min: 0, max: 100,
        read: { number }, write: { number = $0 }, enabled: { true }, onEdit: {})
    framed.frame = NSRect(x: 20, y: 20, width: 60, height: DS.controlHeight)
    root.addSubview(framed)
    let inner = walk(framed).first { $0 is NSTextField } as? NSTextField
    let typedG = inner.map { window.makeFirstResponder($0) } == true && type("42")
    send(tabKey(window))
    spin(0.2)
    check("F2g an OptionFieldControl: Tab commits the number and first responder is the "
            + "content view",
          typedG && number == 42 && atRoot(),
          "typed \(typedG); number \(number); first responder \(first())")
    window.makeFirstResponder(root)
    let focusedG = inner.map { window.makeFirstResponder($0) } == true
    click(at: framed.convert(NSPoint(x: 2, y: framed.bounds.midY), to: nil))
    let keptG = (window.firstResponder as? NSTextView).map {
        $0.isFieldEditor && ($0.delegate as AnyObject?) === inner
    } ?? false
    check("F2h an OptionFieldControl: a click on its own margin keeps its field editor first "
            + "responder",
          focusedG && keptG, "made first responder \(focusedG); first responder \(first())")
    window.makeFirstResponder(root)
    framed.removeFromSuperview()

    // i. The Text tab's area: ⇧Return types a new line and stays; a bare
    // Return applies and leaves; Tab applies and leaves.
    var content = "first"
    var writes: [String] = []
    let area = InspectorTextArea(
        read: { content }, write: { content = $0; writes.append($0) }, enabled: { true },
        onEdit: {})
    area.frame = NSRect(x: 20, y: 60, width: 200, height: 72)
    root.addSubview(area)
    area.layoutSubtreeIfNeeded()
    let areaText = walk(area).first { $0 is NSTextView } as? NSTextView
    let focusedI = areaText.map { window.makeFirstResponder($0) } == true
    areaText?.setSelectedRange(NSRange(location: (areaText?.string as NSString?)?.length ?? 0,
                                       length: 0))
    send(returnKey(window, flags: .shift))
    areaText?.insertText("second", replacementRange: areaText?.selectedRange() ?? NSRange())
    let stayedI = window.firstResponder === areaText
    let typedI = areaText?.string ?? "(none)"
    send(returnKey(window))
    spin(0.2)
    check("F2i the Text tab's area: ⇧Return types a new line and keeps the keys; a bare Return "
            + "applies it once and first responder is the content view",
          focusedI && stayedI && typedI == "first\nsecond" && writes == ["first\nsecond"]
            && atRoot(),
          "made first responder \(focusedI); after ⇧Return first responder was the area "
            + "\(stayedI), string \(typedI.debugDescription); writes \(writes); first "
            + "responder \(first())")
    let focusedJ = areaText.map { window.makeFirstResponder($0) } == true
    areaText?.insertText(" third", replacementRange: NSRange(
        location: (areaText?.string as NSString?)?.length ?? 0, length: 0))
    send(tabKey(window))
    spin(0.2)
    check("F2j the Text tab's area: Tab applies and first responder is the content view, with "
            + "no tab typed",
          focusedJ && content == "first\nsecond third" && atRoot(),
          "made first responder \(focusedJ); content \(content.debugDescription); first "
            + "responder \(first())")
    window.makeFirstResponder(root)
    area.removeFromSuperview()

    // k. The Assistant composer, shown by View ▸ Assistant's own method (a
    // command that exists to type): Tab hands the keys back. The proof gives
    // the probe a dummy key, so the composer shows.
    editor.showAssistant(nil)
    spin(0.3)
    let composer = editor.assistantView?.composer
    let composing = composer.map { window.firstResponder === $0 } ?? false
    send(tabKey(window))
    spin(0.1)
    check("F2k the Assistant composer: View ▸ Assistant gives it the keys, and Tab hands them "
            + "to the content view, typing nothing",
          composing && atRoot() && composer?.string == "",
          "composer first responder after showAssistant \(composing); first responder "
            + "\(first()); composer string \((composer?.string ?? "(none)").debugDescription)")
    window.makeFirstResponder(root)
    paused()
}

// MARK: - F3 the composer's Return

do {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 304, height: 520), styleMask: [.titled],
        backing: .buffered, defer: false)
    let root = FileDropView(frame: NSRect(x: 0, y: 0, width: 304, height: 520))
    window.contentView = root
    let view = AssistantView()
    view.frame = root.bounds
    view.autoresizingMask = [.width, .height]
    root.addSubview(view)
    var accept = true
    var sends: [String] = []
    view.onSend = { text in
        sends.append(text)
        return accept
    }
    view.show(hasKey: true)
    view.show(phase: .idle, question: nil)
    window.layoutIfNeeded()

    view.composer.string = "taken"
    window.makeFirstResponder(view.composer)
    if let event = returnKey(window) { window.sendEvent(event) }
    check("F3a the composer: a Return that sends empties it and first responder is the content "
            + "view",
          sends == ["taken"] && view.composer.string.isEmpty && window.firstResponder === root,
          "sends \(sends); composer \(view.composer.string.debugDescription); first responder "
            + describe(window.firstResponder, root: root))

    accept = false
    view.composer.string = "refused"
    window.makeFirstResponder(view.composer)
    if let event = returnKey(window) { window.sendEvent(event) }
    check("F3b the composer: a Return whose message is refused keeps the text and the keys",
          sends == ["taken", "refused"] && view.composer.string == "refused"
            && window.firstResponder === view.composer,
          "sends \(sends); composer \(view.composer.string.debugDescription); first responder "
            + describe(window.firstResponder, root: root))
}

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
