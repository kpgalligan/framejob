// Issue batch B51 (#184 item 2) — `UIMenu.perform` (the dev tools'
// `perform_menu_item`) and the document's undo stack when the target is a
// text view with an undo manager of its own (the Assistant composer), and
// the vetoed-field case recorded.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, with `-D FRAMEJOB_DEV_TOOLS` (`UIMenu` exists
// only there), against `libframejob_core.a`. One process:
//
//   menu_undo_probe
//
// The answer is one JSON object on stdout, `{"rows": [...], "pasteboard":
// "restored" | "left: <why>"}`, each row `{"id", "pass", "detail"}`;
// `menu_undo_probe.py` prints and scores them.
//
// The fixture is `relink_sheet_probe`'s window with no media: an untitled
// `ProjectDocument`, a bare host view controller's window added as its
// window controller's. Rows:
//   M1 CONTROL: the window's `undoManager` is the document's; an editable
//      `NSTextField`'s field editor answers a manager of its own (AppKit's
//      `NSCellUndoManager`, measured) and so does the composer's text view
//      (neither is the document's); with the composer first responder,
//      `UIMenu.target` of a `cut:` item is that text view; one applied edit
//      undone leaves canUndo false, canRedo true.
//   M2 Cut then Paste through `UIMenu.perform` on the composer: its text goes
//      "" then "hello", its own manager can undo, and the document's
//      canUndo, canRedo, redoActionName and groupingLevel are as before.
//   V1 RECORD: a field whose delegate vetoes editing, Cut then Paste: passes
//      when the field still reads "hello"; the detail prints the document's
//      undo state before and after each.
//   F1 a field whose delegate commits two ungrouped document edits
//      (`applyEdit`) in `controlTextDidChange`; Paste through `UIMenu.perform`
//      on its field editor (a manager of its own), then one grouped edit: the
//      grouping level is back where it began after the Paste, one undo takes
//      back only the later edit, and a second takes back both of the field's.
//
// The pasteboard is the owner's: every item of `NSPasteboard.general` is
// copied before M2 and put back at the end only if `changeCount` is still
// what the probe's own last write or Cut left.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": String(detail.prefix(1500))])
}

// MARK: - The pasteboard, saved

let board = NSPasteboard.general
let saved: [[(NSPasteboard.PasteboardType, Data)]] = (board.pasteboardItems ?? []).map { item in
    item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
}
var ours: Int?
func markOurs() { ours = board.changeCount }

var document: ProjectDocument?
func finish() -> Never {
    let note: String
    if let ours, board.changeCount == ours {
        board.clearContents()
        let items = saved.map { pairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { board.writeObjects(items) }
        note = "restored"
    } else if let ours {
        note = "left: changeCount \(board.changeCount), the probe's last \(ours) (another writer)"
    } else {
        note = "left: the probe never wrote it"
    }
    document?.removeTemporaryCacheDirectory()
    let answer: [String: Any] = ["rows": rows, "pasteboard": note]
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

func waitUntil(_ limit: Double, _ condition: () -> Bool) -> Bool {
    let start = Date()
    while Date().timeIntervalSince(start) < limit {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
}

// MARK: - The fixture

let doc = ProjectDocument()
document = doc
let host = NSViewController()
host.view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
let window = NSWindow(contentViewController: host)
let controller = NSWindowController(window: window)
doc.addWindowController(controller)
controller.showWindow(nil)
guard let manager = doc.undoManager else {
    row("M1", false, "the document has no undo manager")
    finish()
}

func undoState() -> String {
    "canUndo \(manager.canUndo), canRedo \(manager.canRedo), undo \"\(manager.undoActionName)\", "
        + "redo \"\(manager.redoActionName)\", groupingLevel \(manager.groupingLevel)"
}

let cut = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")
let paste = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")

/// One applied edit, undone: the document's redo is armed.
func armRedo() {
    doc.performGroupedEdit("Add Track", [.addTrack(index: 0)])
    manager.undo()
}

// MARK: - M1 — CONTROL

let windowManager = window.undoManager === manager
let plain = NSTextField(string: "plain")
plain.isEditable = true
plain.frame = NSRect(x: 20, y: 400, width: 200, height: 24)
host.view.addSubview(plain)
let plainFirst = window.makeFirstResponder(plain)
let fieldEditor = plain.currentEditor() as? NSTextView
let plainResponder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
let editorManagerKind = fieldEditor?.undoManager.map { $0 === window.undoManager ? "the window's" : "another, \(type(of: $0)), the field's own: \($0 === plain.undoManager)" } ?? "nil"
let editorOwn = fieldEditor?.undoManager.map { $0 !== manager } ?? false
let composer = AssistantComposerField()
composer.frame = NSRect(x: 20, y: 300, width: 300, height: 26)
host.view.addSubview(composer)
let composerFirst = window.makeFirstResponder(composer.textView)
let own = composer.textView.undoManager
let composerOwn = own != nil && own !== manager
let cutTarget = UIMenu.target(for: cut, window: window)
let targetIsComposer = cutTarget === composer.textView
armRedo()
let armed = !manager.canUndo && manager.canRedo
row("M1", windowManager && plainFirst && editorOwn && composerFirst && composerOwn
        && targetIsComposer && armed,
    "window's undoManager is the document's: \(windowManager); the field first responder "
    + "\(plainFirst), its editor \(fieldEditor.map { _ in "present" } ?? "nil") (first "
    + "responder \(plainResponder)), its manager its own: \(editorOwn) "
    + "(\(editorManagerKind)); the composer "
    + "first responder \(composerFirst), its manager another: \(composerOwn); cut:'s target "
    + "the composer: \(targetIsComposer) (\(cutTarget.map { String(describing: type(of: $0)) } ?? "nil")); "
    + "after one edit undone: \(undoState())")

// MARK: - M2 — the composer's Cut and Paste leave the document's stack alone

composer.textView.string = "hello"
_ = window.makeFirstResponder(composer.textView)
composer.textView.selectAll(nil)
let m2Before = (manager.canUndo, manager.canRedo, manager.redoActionName, manager.groupingLevel)
let m2BeforeText = undoState()
var m2Steps: [String] = []
var m2Sent: [Bool] = []
if let target = UIMenu.target(for: cut, window: window) {
    m2Sent.append(UIMenu.perform(cut, target: target, window: window))
    markOurs()
}
m2Steps.append("after Cut: text \"\(composer.textView.string)\"; \(undoState())")
let afterCut = composer.textView.string
if let target = UIMenu.target(for: paste, window: window) {
    m2Sent.append(UIMenu.perform(paste, target: target, window: window))
}
let afterPaste = composer.textView.string
m2Steps.append("after Paste: text \"\(afterPaste)\"; \(undoState())")
let ownCanUndo = composer.textView.undoManager?.canUndo ?? false
let m2After = (manager.canUndo, manager.canRedo, manager.redoActionName, manager.groupingLevel)
let unchanged = m2Before == m2After
row("M2", m2Sent == [true, true] && afterCut.isEmpty && afterPaste == "hello" && ownCanUndo
        && unchanged,
    "sent \(m2Sent); the composer's own manager canUndo \(ownCanUndo); the document's "
    + "state unchanged: \(unchanged); before: \(m2BeforeText); " + m2Steps.joined(separator: "; "))

// MARK: - V1 — RECORD: a field whose delegate vetoes editing

final class Vetoer: NSObject, NSTextFieldDelegate {
    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool {
        false
    }
}
let vetoer = Vetoer()
let vetoed = NSTextField(string: "hello")
vetoed.isEditable = true
vetoed.delegate = vetoer
vetoed.frame = NSRect(x: 20, y: 200, width: 200, height: 24)
host.view.addSubview(vetoed)
armRedo()
let vetoedFirst = window.makeFirstResponder(vetoed)
vetoed.currentEditor()?.selectAll(nil)
func vetoedText() -> String { vetoed.currentEditor()?.string ?? vetoed.stringValue }
var v1Steps = ["before: \(undoState())"]
var v1Sent: [Bool] = []
if let target = UIMenu.target(for: cut, window: window) {
    v1Sent.append(UIMenu.perform(cut, target: target, window: window))
    markOurs()
}
v1Steps.append("after Cut: text \"\(vetoedText())\"; \(undoState())")
board.clearContents()
board.setString("menu_undo_probe", forType: .string)
markOurs()
if let target = UIMenu.target(for: paste, window: window) {
    v1Sent.append(UIMenu.perform(paste, target: target, window: window))
}
v1Steps.append("after Paste: text \"\(vetoedText())\"; \(undoState())")
row("V1", vetoedFirst && vetoedText() == "hello",
    "RECORD: first responder \(vetoedFirst); sent \(v1Sent); " + v1Steps.joined(separator: "; "))

// MARK: - F1 — a document commit during a field-editor action is one step

final class Committer: NSObject, NSTextFieldDelegate {
    var commits = 0
    func controlTextDidChange(_ notification: Notification) {
        commits += 1
        doc.applyEdit("Field Commit", .addTrack(index: 0))
        doc.applyEdit("Field Commit", .addTrack(index: 0))
    }
}
let committer = Committer()
let committing = NSTextField(string: "hello")
committing.isEditable = true
committing.delegate = committer
committing.frame = NSRect(x: 20, y: 100, width: 200, height: 24)
host.view.addSubview(committing)
let committingFirst = window.makeFirstResponder(committing)
let committingOwn = (committing.currentEditor() as? NSTextView)?.undoManager.map { $0 !== manager } ?? false
committing.currentEditor()?.selectAll(nil)
board.clearContents()
board.setString("menu_undo_probe", forType: .string)
markOurs()
let f1Before = (manager.canUndo, manager.undoActionName, manager.groupingLevel)
var f1Steps = ["before: \(undoState())"]
var f1Sent = false
if let target = UIMenu.target(for: paste, window: window) {
    f1Sent = UIMenu.perform(paste, target: target, window: window)
}
let f1Level = manager.groupingLevel
f1Steps.append("after Paste: commits \(committer.commits); \(undoState())")
doc.performGroupedEdit("Later Edit", [.addTrack(index: 0)])
f1Steps.append("after the later edit: \(undoState())")
manager.undo()
let firstUndo = (manager.canUndo, manager.undoActionName)
f1Steps.append("after one undo: \(undoState())")
manager.undo()
let secondUndo = (manager.canUndo, manager.undoActionName, manager.groupingLevel)
f1Steps.append("after two: \(undoState())")
row("F1", committingFirst && committingOwn && f1Sent && committer.commits > 0
        && f1Level == f1Before.2 && firstUndo == (true, "Field Commit")
        && secondUndo == f1Before,
    "first responder \(committingFirst), its editor's manager its own: \(committingOwn); "
    + "sent \(f1Sent); " + f1Steps.joined(separator: "; "))

_ = waitUntil(0.2) { false }
finish()
