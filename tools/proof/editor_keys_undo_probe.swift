// Issue batch B3 — editor keys, undo steps, the transition ring (#59 #60 #61
// #66 #68 #69); the probe (`editor_keys_undo_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line. It names nothing the fix
// added, so the SAME source builds over the untouched tree (the proof's
// `--baseline`, `-D HARNESS_REFERENCE_BUILD`), where the fixed rows fail.
//
//   editor_keys_undo_probe <request.json> <answer.json>
//
// `request.json` names the packages the proof wrote:
//   card       a grey shape card 0–6 s (clip 2), then media/A.mov (media 20)
//              as clip 3 at 6–12 s; one track
//   ringPair   shape cards A (clip 2, 0–6 s) and B (clip 3, 4–10 s, a linear
//              cross dissolve in)
//   ringAlone  A only
//   ringAbut   A, and B at 6–12 s with no transition
// One JSON object out: `rows`, each a name (its ID, a space, the claim), ok
// and detail.
//
// U drives a windowless document. F, C, R and M each open their OWN fresh
// `card` editor through `ProjectDocument.makeWindowControllers()`, so no
// group's undo stack — or an implicit undo group left open — reaches
// another; keys are synthesized `NSEvent`s through `NSWindow.sendEvent`. D
// `cacheDisplay`s the timeline's content and compares device-pixel columns.
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

let SEC = ReelTime.perSecond

/// A key-down as the keyboard would deliver it to `window`.
func key(
    _ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = [], window: NSWindow
) -> NSEvent? {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
}

func function(_ scalar: UInt32) -> String { String(Character(UnicodeScalar(scalar)!)) }
let escape = "\u{1b}"

func opened(_ key: String) -> ProjectDocument? {
    guard let path = request[key] as? String else {
        check("X0 the \(key) fixture is named", false)
        return nil
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        check("X0 the \(key) fixture opens", false, "\(error)")
        return nil
    }
    return document
}

func openEditor(
    _ key: String, select ids: Set<UInt32> = []
) -> (ProjectDocument, EditorViewController, NSWindow)? {
    guard let document = opened(key) else { return nil }
    document.selection = ids
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.5)
    guard let window = document.windowControllers.first?.window,
          let editor = window.contentViewController as? EditorViewController
    else {
        check("X0 the \(key) editor opens", false)
        return nil
    }
    return (document, editor, window)
}

func seconds(_ ticks: Ticks?) -> String {
    ticks.map { String(format: "%.3f s", Double($0) / Double(SEC)) } ?? "nil"
}

func range(_ document: ProjectDocument) -> String {
    document.inOutRange.map { "(\(seconds($0.start)), \(seconds($0.end)))" } ?? "nil"
}

// MARK: - U performGroupedEdit's answers that are not an undo step (#59)

/// Undo and redo, as a person's Edit menu would read them.
func stacks(_ document: ProjectDocument) -> [String] {
    let manager = document.undoManager
    return [
        "undo \(manager?.canUndo ?? false) \"\(manager?.undoActionName ?? "")\"",
        "redo \(manager?.canRedo ?? false) \"\(manager?.redoActionName ?? "")\"",
    ]
}

do {
    let document = ProjectDocument()
    if let track = document.project.snapshot.tracks.first?.id {
        // Two abutting ten-second text clips, refusal_probe.py's fixture.
        document.performGroupedEdit(
            "Add", [.addTextClip(track: track, at: 0, duration: 10 * SEC),
                    .addTextClip(track: track, at: 10 * SEC, duration: 10 * SEC)])
        let clips = document.project.snapshot.clips.sorted { $0.start < $1.start }
        if clips.count == 2 {
            let a = clips[0].id
            let b = clips[1].id
            document.performGroupedEdit(
                "Name", [.setClip(clips: [a], patch: ClipPatch(name: "Named"))])
            let named = document.undoManager?.undoActionName ?? ""
            document.undoManager?.undo()
            let underIt = document.undoManager?.undoActionName ?? ""
            let redo = document.undoManager?.redoActionName ?? ""
            check("U3 a real grouped edit registers ONE step named for it (control)",
                  named == "Name" && underIt == "Add" && redo == "Name",
                  "after the edit \"\(named)\"; after one undo \"\(underIt)\", redo \"\(redo)\"")

            let before = stacks(document)
            document.performGroupedEdit(
                "Opacity", [.setVideo(clips: [a], patch: VideoPatch(opacity: 1))])
            let afterIdentity = stacks(document)
            check("U1 an identity through performGroupedEdit leaves undo and redo as they were",
                  afterIdentity == before, "before \(before); after \(afterIdentity)")

            // Half of the shorter clip is the overlap rule's limit; ten frames
            // past it is refused.
            // Re-armed first — a real edit, then undo — so U2 starts from a
            // redo of its own, whatever U1 left.
            let over = 10 * SEC / 2 + 10 * (SEC / 30)
            document.performGroupedEdit(
                "Name", [.setClip(clips: [a], patch: ClipPatch(name: "Named"))])
            document.undoManager?.undo()
            let before2 = stacks(document)
            document.performGroupedEdit("Move", [.moveClip(clips: [b], delta: -over)])
            let afterRefusal = stacks(document)
            check("U2 a refused move through performGroupedEdit leaves undo and redo as they were",
                  afterRefusal == before2, "before \(before2); after \(afterRefusal)")
        } else {
            check("U0 the fixture has two clips", false, "\(clips.count)")
        }
    } else {
        check("U0 the blank project has a track", false)
    }
}

// MARK: - F bare keys after an inspector field (#60)

if let (document, editor, window) = openEditor("card", select: [2]) {
    editor.inspector?.select(.clip)
    editor.inspector?.selectClipSubTab(.picture)
    spin(0.5)
    let section = walk(editor.view).compactMap { $0 as? InspectorSection }
        .first { $0.id == "video.transform" }
    let control = section.flatMap { walk($0).compactMap { $0 as? OptionFieldControl }.first }
    let field = control.flatMap { walk($0).compactMap { $0 as? NSTextField }.first }
    if let field {
        let shown = field.stringValue
        let focused = window.makeFirstResponder(field)
        let editorView = field.currentEditor() as? NSTextView
        editorView?.selectAll(nil)
        if let e = key("5", code: 23, window: window) { window.sendEvent(e) }
        if let e = key("0", code: 29, window: window) { window.sendEvent(e) }
        let typed = editorView?.string ?? "(no field editor)"
        if let e = key("\r", code: 36, window: window) { window.sendEvent(e) }
        spin(0.2)
        let scale = document.project.snapshot.clip(2)?.videoProps.scale
        let responder = window.firstResponder
        check("F1 Scale 100 % → typed 50, Return: the commit applied and the editor's root view "
                + "is first responder",
              focused && scale == 0.5 && responder === editor.view,
              "field showed \"\(shown)\"; focused \(focused); typed \"\(typed)\"; scale "
                + "\(scale.map { "\($0)" } ?? "nil"); firstResponder "
                + "\(responder.map { "\(type(of: $0))" } ?? "nil"), is the window "
                + "\(responder === window)")

        editor.setPlayhead(2 * SEC)
        if let e = key("i", code: 34, window: window) { window.sendEvent(e) }
        check("F2 then a bare I sets the in point at the playhead (2 s)",
              document.inOutRange?.start == 2 * SEC && document.playhead == 2 * SEC,
              "range \(range(document)); playhead \(seconds(document.playhead))")

        let again = window.makeFirstResponder(field)
        let editing = field.currentEditor() != nil
        if let e = key(escape, code: 53, window: window) { window.sendEvent(e) }
        spin(0.1)
        editor.setPlayhead(4 * SEC)
        if let e = key("o", code: 31, window: window) { window.sendEvent(e) }
        check("F3 focus the field again, Esc, then a bare O sets the out point at the "
                + "playhead (4 s)",
              again && editing && document.inOutRange?.end == 4 * SEC,
              "focused \(again), editing \(editing); range \(range(document)); firstResponder "
                + "after Esc \(window.firstResponder.map { "\(type(of: $0))" } ?? "nil")")
    } else {
        check("F0 the Picture tab's Transform section has a Scale field", false,
              "section \(section != nil); control \(control != nil)")
    }
}

// MARK: - C bare keys with Caps Lock and the arrows' own flags (#61)

if let (document, editor, window) = openEditor("card") {
    let took = window.makeFirstResponder(editor.view)
    if let e = key("I", code: 34, flags: .capsLock, window: window) { window.sendEvent(e) }
    check("C1 I with Caps Lock sets the in point at the playhead (0 s)",
          took && document.inOutRange?.start == 0,
          "root view first responder \(took); range \(range(document))")

    if let e = key(function(0xF701), code: 125, flags: [.numericPad, .function], window: window) {
        window.sendEvent(e)
    }
    check("C2 ↓ with [.numericPad, .function] steps to the next edit point (6 s)",
          document.playhead == 6 * SEC, "playhead \(seconds(document.playhead))")

    if let e = key(function(0xF72B), code: 119, flags: [.function], window: window) {
        window.sendEvent(e)
    }
    check("C3 End with [.function] goes to the end (12 s)",
          document.playhead == 12 * SEC, "playhead \(seconds(document.playhead))")

    let rangeBefore = range(document)
    let playheadBefore = document.playhead
    var answers: [String] = []
    let modified: [(String, String, UInt16, NSEvent.ModifierFlags)] = [
        ("⌘I", "i", 34, .command), ("⌥I", "i", 34, .option), ("⌃I", "i", 34, .control),
        ("⌥↓", function(0xF701), 125, [.option, .numericPad, .function]),
    ]
    var anyTrue = false
    for (label, characters, code, flags) in modified {
        guard let e = key(characters, code: code, flags: flags, window: window) else { continue }
        let answered = editor.handleEditorKey(e)
        anyTrue = anyTrue || answered
        answers.append("\(label) \(answered)")
    }
    check("C4 handleEditorKey answers false for ⌘I, ⌥I, ⌃I and ⌥↓, and none moved the range "
            + "or the playhead (control)",
          answers.count == 4 && !anyTrue && range(document) == rangeBefore
            && document.playhead == playheadBefore,
          "\(answers.joined(separator: ", ")); range \(rangeBefore) → \(range(document)); "
            + "playhead \(seconds(playheadBefore)) → \(seconds(document.playhead))")
}

// MARK: - R the rename field: Escape, and its own undo step (#69)

spin(0.2)
if let (document, editor, window) = openEditor("card"), let timeline = editor.timeline {
    func name() -> String { document.project.snapshot.clip(2)?.name ?? "nil" }
    func muted() -> Bool { document.project.snapshot.tracks.first?.muted ?? false }
    func enter(_ text: String) -> Bool {
        guard let editorView = window.firstResponder as? NSTextView else { return false }
        editorView.selectAll(nil)
        editorView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        return editorView.string == text
    }
    spin(0.2)
    let original = name()
    let undoBefore = stacks(document)
    timeline.beginClipRename(2)
    let opened1 = timeline.renameField != nil
    let typed1 = enter("Renamed")
    if let e = key(escape, code: 53, window: window) { window.sendEvent(e) }
    spin(0.2)
    let undoAfter = stacks(document)
    check("R1 Esc closes the field, keeps the old name, makes no undo step, and gives the "
            + "root view first responder",
          opened1 && typed1 && timeline.renameField == nil && name() == original
            && undoAfter == undoBefore && window.firstResponder === editor.view,
          "opened \(opened1), typed \(typed1); field still open \(timeline.renameField != nil); "
            + "name \"\(original)\" → \"\(name())\"; \(undoBefore) → \(undoAfter); "
            + "firstResponder \(window.firstResponder.map { "\(type(of: $0))" } ?? "nil")")

    spin(0.2)
    timeline.beginClipRename(2)
    let typed2 = enter("Renamed")
    timeline.beginGesture(
        hit: .headerButton(row: timeline.layout.row(forTrackIndex: 0), button: .muted),
        at: .zero, flags: [], clicks: 1)
    spin(0.2)
    let afterClick = "name \"\(name())\", muted \(muted())"
    document.undoManager?.undo()
    spin(0.1)
    let firstUndo = (name(), muted())
    document.undoManager?.undo()
    spin(0.1)
    let secondUndo = (name(), muted())
    check("R2 rename, then a click on the track's M: the first undo unmutes and keeps "
            + "\"Renamed\", the second restores the name",
          typed2 && firstUndo == ("Renamed", false) && secondUndo == (original, false),
          "typed \(typed2); after the click \(afterClick); after one undo \(firstUndo); "
            + "after two \(secondUndo)")

    spin(0.2)
    let before3 = name()
    let canUndo3 = document.undoManager?.canUndo ?? false
    timeline.beginClipRename(2)
    let typed3 = enter("Again")
    if let e = key("\r", code: 36, window: window) { window.sendEvent(e) }
    spin(0.2)
    let committed = name()
    let action = document.undoManager?.undoActionName ?? ""
    document.undoManager?.undo()
    spin(0.1)
    let undone = name()
    let canUndoAfter = document.undoManager?.canUndo ?? false
    check("R3 Return commits ONE \"Rename Clip\" step (control)",
          typed3 && committed == "Again" && action == "Rename Clip" && undone == before3
            && canUndoAfter == canUndo3,
          "typed \(typed3); name \"\(before3)\" → \"\(committed)\", step \"\(action)\"; one "
            + "undo → \"\(undone)\", canUndo \(canUndo3) → \(canUndoAfter)")
}

// MARK: - M a filter that hides the selected media row (#68)

if let (document, editor, window) = openEditor("card") {
    _ = window
    editor.inspector?.select(.media)
    spin(0.5)
    let pane = walk(editor.view).compactMap { $0 as? MediaPane }.first
    let search = pane.flatMap { walk($0).compactMap { $0 as? MediaSearchField }.first }
    if let pane, let search {
        pane.select(20)
        func searchFor(_ text: String) {
            search.stringValue = text
            search.controlTextDidChange(
                Notification(name: NSControl.textDidChangeNotification, object: search))
            spin(0.2)
        }
        func placeable() -> (Bool?, Bool?) {
            (editor.validateEdgeAction(#selector(EditorViewController.insertMediaAtPlayhead(_:))),
             editor.validateEdgeAction(
                #selector(EditorViewController.overwriteMediaAtPlayhead(_:))))
        }
        searchFor("A.mov")
        let shown = placeable()
        check("M1 a search the A.mov row matches keeps it selected and Insert / Overwrite live "
                + "(control)",
              document.selectedMedia == 20 && shown == (true, true),
              "selectedMedia \(document.selectedMedia.map { "\($0)" } ?? "nil"); insert, "
                + "overwrite \(shown)")
        searchFor("zzz")
        let hidden = placeable()
        check("M2 a search matching nothing clears the selection and Insert / Overwrite go dead",
              document.selectedMedia == nil && hidden == (false, false),
              "selectedMedia \(document.selectedMedia.map { "\($0)" } ?? "nil"); insert, "
                + "overwrite \(hidden)")
    } else {
        check("M0 the Media tab shows its pane and search field", false,
              "pane \(pane != nil); search \(search != nil)")
    }
}

// MARK: - D the selection ring over a transition zone (#66)

/// The device-pixel columns wholly inside A's ring stroke — `[body.maxX − 2,
/// body.maxX]` — over the run between its corner radii, as raw bytes.
func ringColumns(_ editor: EditorViewController) -> ([UInt8], String) {
    guard let timeline = editor.timeline, let clip = timeline.snapshot.clip(2),
          let index = timeline.snapshot.trackIndex(of: clip.track)
    else { return ([], "no timeline or no clip 2") }
    let content = timeline.content
    let body = TimelineContentView.bodyRect(
        timeline.layout.clipRect(clip, row: timeline.layout.row(forTrackIndex: index)))
    guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)
    else { return ([], "no bitmap") }
    content.cacheDisplay(in: content.bounds, to: rep)
    guard let data = rep.bitmapData, !rep.isPlanar, content.bounds.width > 0
    else { return ([], "no bitmap data") }
    let scale = CGFloat(rep.pixelsWide) / content.bounds.width
    // The ring is `body.insetBy(dx: 1, dy: 1)` stroked 2 pt, so its corner
    // arcs end 1 pt + the radius in from the body's top and bottom.
    let radius = TimelineLayout.clipRadius + 1
    let x0 = Int(((body.maxX - 2) * scale).rounded(.up))
    let x1 = Int((body.maxX * scale).rounded(.down))
    let y0 = Int(((body.minY + radius) * scale).rounded(.up))
    let y1 = Int(((body.maxY - radius) * scale).rounded(.down))
    let bytesPerPixel = rep.bitsPerPixel / 8
    guard x0 < x1, y0 < y1, x1 <= rep.pixelsWide, y1 <= rep.pixelsHigh
    else { return ([], "empty block x \(x0)..<\(x1), y \(y0)..<\(y1)") }
    var bytes: [UInt8] = []
    for y in y0..<y1 {
        for x in x0..<x1 {
            let at = y * rep.bytesPerRow + x * bytesPerPixel
            for b in 0..<bytesPerPixel { bytes.append(data[at + b]) }
        }
    }
    let sample = rep.colorAt(x: x0, y: (y0 + y1) / 2).map { "\($0)" } ?? "?"
    return (bytes, "cols \(x0)..<\(x1), rows \(y0)..<\(y1) at ×\(scale), mid \(sample)")
}

func select(_ document: ProjectDocument, _ editor: EditorViewController, _ ids: Set<UInt32>) {
    document.selection = ids
    editor.viewStateDidChange()
    spin(0.3)
}

var captures: [String: ([UInt8], String)] = [:]
for fixture in ["ringPair", "ringAlone", "ringAbut"] {
    guard let (document, editor, _) = openEditor(fixture, select: [2]) else { continue }
    captures[fixture + " selected"] = ringColumns(editor)
    if fixture != "ringAbut" {
        select(document, editor, [])
        captures[fixture + " none"] = ringColumns(editor)
    }
}
func compare(_ a: String, _ b: String) -> (Bool, Bool, String) {
    guard let x = captures[a], let y = captures[b] else { return (false, false, "missing") }
    let valid = !x.0.isEmpty && !y.0.isEmpty
    let differ = zip(x.0, y.0).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
    let first = differ.first.map { "; \(differ.count) bytes differ, the first at byte \($0)" } ?? ""
    return (valid, x.0 == y.0, "\(a): \(x.1); \(b): \(y.1)\(first)")
}
let d1 = compare("ringPair selected", "ringAlone selected")
check("D1 A selected: ringPair's ring columns are byte-identical to ringAlone's",
      d1.0 && d1.1, d1.2)
let d2 = compare("ringPair none", "ringAlone none")
check("D2 nothing selected: ringPair's columns differ from ringAlone's (control)",
      d2.0 && !d2.1, d2.2)
let d3 = compare("ringAbut selected", "ringAlone selected")
check("D3 ringAbut with A selected is byte-identical to ringAlone (control)",
      d3.0 && d3.1, d3.2)

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
