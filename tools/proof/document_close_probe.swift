// tools/proof/document_close_probe.swift — the in-process instrument behind
// `document_close_probe.py` (#568, #592). Compiled with every file in `app/Sources`
// but `main.swift`, copied in as `main.swift`, with the app's `Fonts`,
// `Blank.mp4` and a `default.metallib` of the app's own shader beside it —
// `scope_playhead_probe.swift`'s build.
//
//     document_close_probe <a> <b> <c> <d> <e> <f>   (six .framejob packages)
//
// Each package is opened as a document with its editor window made and never
// shown, given one shape clip so its player has an item, and closed through a
// door of its own. For every row but P6 the probe HOLDS each editor and its
// `Playback` strongly across the close, which is the case #568's fix is for:
// AppKit keeps a closed window alive for as long as it likes, so nothing there
// may depend on a deinit. P6 holds the WINDOW strongly, as AppKit does, and the
// editor only weakly: what the window still owns after the close is #592's
// question. The rebuild in flight is FORCED through `Playback.rebuildHop`, never
// waited for. The answer is one line, `ANSWER <json>`.
import AppKit
import AVFoundation

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.accessory)
UserDefaults.standard.setVolatileDomain(
    ["FrameJobPreviewQuality": 0], forName: UserDefaults.argumentDomain)

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// Spins until `done()` or `limit` seconds; answers whether it came true.
func wait(_ limit: Double, _ done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(limit)
    while !done() && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return done()
}

let args = CommandLine.arguments
guard args.count == 7 else {
    print("usage: document_close_probe <a> <b> <c> <d> <e> <f> (six .framejob packages)")
    exit(2)
}
let second = ReelTime.ticks(seconds: 1)

struct Opened {
    let document: ProjectDocument
    let editor: EditorViewController
    let playback: Playback
    let window: NSWindow
    let key: Int
    let hadItem: Bool
    let editors: Int
}

/// A document on `path` with its window made (not shown), one shape clip, its
/// player's item built, and its change count cleared so no door asks to save.
func open(_ path: String) -> Opened {
    let url = URL(fileURLWithPath: path)
    let document = ProjectDocument()
    try! document.read(from: url, ofType: ProjectDocument.projectTypeIdentifier)
    document.fileURL = url
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    let controller = document.windowControllers.first!
    let editor = controller.contentViewController as! EditorViewController
    // The editor's alert is app-modal and would stall the probe.
    editor.playback.onError = { _ in }
    document.applyEdit(
        "Probe", .addShapeClip(track: 1, at: 0, duration: 2 * second, shape: .rectangle))
    let hadItem = wait(10) { editor.playback.currentItem != nil }
    spin(0.3)
    document.updateChangeCount(.changeCleared)
    return Opened(
        document: document, editor: editor, playback: editor.playback,
        window: controller.window!, key: document.recipeKey, hadItem: hadItem,
        editors: document.editors.allObjects.count)
}

/// What the row reads the moment a door has returned, before any run-loop turn.
func shut(_ o: Opened) -> [String: Any] {
    [
        "hadItem": o.hadItem,
        "editors": o.editors,
        "isShutDown": o.playback.isShutDown,
        "hasItem": o.playback.currentItem != nil,
        "built": o.playback.built != nil,
        "registered": RecipeSource.shared.project(for: o.key) != nil,
        "open": NSDocumentController.shared.documents.contains { $0 === o.document },
    ]
}

/// What the close left of the editor in its window (#592): read once a door has
/// returned. The window must hold no content view controller, the editor's root
/// view must be out of the window, and the first responder must not be in it.
func detached(_ o: Opened) -> [String: Any] {
    let root = o.editor.view
    let first = o.window.firstResponder
    let inTree = (first as? NSView).map { $0 === root || $0.isDescendant(of: root) } ?? false
    return [
        "controller": o.window.contentViewController != nil,
        "contentIsRoot": o.window.contentView === root,
        "rootInWindow": root.window != nil,
        "rootHasSuperview": root.superview != nil,
        "firstResponderInTree": inTree,
        "firstResponder": first.map { String(describing: type(of: $0)) } ?? "nil",
    ]
}

var answer: [String: Any] = [:]

// P1 — the document's own close(), which `close_project` calls.
let a = open(args[1])
let heldProject = a.document.project
a.document.close()
answer["P1"] = shut(a)
var p5: [String: Any] = ["close": detached(a)]

// P3 — a shut player stays shut: `update` called on it directly, as a late
// change notice would through an editor that outlived its window.
a.playback.update(project: heldProject, urls: [:], isLive: false)
let registeredAtOnce = RecipeSource.shared.project(for: a.key) != nil
spin(2)
answer["P3"] = [
    "registeredAtOnce": registeredAtOnce,
    "registered": RecipeSource.shared.project(for: a.key) != nil,
    "hasItem": a.playback.currentItem != nil,
    "isShutDown": a.playback.isShutDown,
] as [String: Any]
RecipeSource.shared.unregister(a.key)   // a mutant's entry must not outlive its row

// P2 — the window's close button. `performClose(_:)` is what the button
// sends; a window AppKit will not close that way is closed through the
// question the button asks the document, and the row says which ran.
let b = open(args[2])
var door = "performClose"
b.window.performClose(nil)
_ = wait(3) { !NSDocumentController.shared.documents.contains { $0 === b.document } }
if NSDocumentController.shared.documents.contains(where: { $0 === b.document }) {
    door = "shouldCloseWindowController"
    b.document.shouldCloseWindowController(
        b.document.windowControllers.first ?? NSWindowController(window: b.window),
        delegate: nil, shouldClose: nil, contextInfo: nil)
    _ = wait(3) { !NSDocumentController.shared.documents.contains { $0 === b.document } }
}
var p2 = shut(b)
p2["door"] = door
p2["controllersLeft"] = b.document.windowControllers.count
answer["P2"] = p2
p5["button"] = detached(b)
answer["P5"] = p5

// P4 — a rebuild in flight at the close: the build is held on the seam, the
// document closes, and the held block is then run.
final class Hold {
    let lock = NSLock()
    var block: (((any Error)?) -> Void)?
}
let hold = Hold()
let c = open(args[3])
c.playback.rebuildHop = { block in
    hold.lock.lock()
    hold.block = block
    hold.lock.unlock()
}
c.document.applyEdit(
    "Probe", .addShapeClip(track: 1, at: 3 * second, duration: second, shape: .ellipse))
var heldBlock: (((any Error)?) -> Void)?
_ = wait(10) {
    hold.lock.lock()
    heldBlock = hold.block
    hold.lock.unlock()
    return heldBlock != nil
}
c.document.updateChangeCount(.changeCleared)
c.document.close()
var p4 = shut(c)
p4["held"] = heldBlock != nil
heldBlock?(nil)
c.playback.rebuildHop = nil
spin(1)
p4["hasItemAfterLanding"] = c.playback.currentItem != nil
p4["builtAfterLanding"] = c.playback.built != nil
answer["P4"] = p4

// P6 — the window held strongly, as AppKit holds a closed one (the main thread's
// autorelease pool and `NSApplication.currentEvent`, #592), and the editor, its
// `Playback` and its root view held only weakly; the document opened and closed
// inside an `autoreleasepool`, so no local of the probe's owns any of them.
final class Weakly {
    weak var editor: EditorViewController?
    weak var playback: Playback?
    weak var root: NSView?
    var gone: Bool { editor == nil && playback == nil && root == nil }
}
let weakly = Weakly()
var heldWindow: NSWindow?
var p6HadItem = false
autoreleasepool {
    let d = open(args[4])
    weakly.editor = d.editor
    weakly.playback = d.playback
    weakly.root = d.editor.view
    heldWindow = d.window
    p6HadItem = d.hadItem
    d.document.close()
}
let freedAtOnce = weakly.gone
let freed = wait(5) { weakly.gone }
answer["P6"] = [
    "hadItem": p6HadItem,
    "freedAtOnce": freedAtOnce,
    "freed": freed,
    "editorAlive": weakly.editor != nil,
    "playbackAlive": weakly.playback != nil,
    "rootAlive": weakly.root != nil,
    "windowHeld": heldWindow != nil,
] as [String: Any]

// P7 — text being typed at the close: the close ends no editing, so no commit
// reaches the closed document. Two of the probe's own views, each added to an
// editor's root view and made first responder: a field (`NSTextField`, the field
// editor; every inspector field, the timeline's rename, the timecode) and a text
// view (`NSTextView`, as the Text tab's area and the canvas's inline editor are).
// The field's delegate counts `controlTextDidEndEditing`; the text view counts its
// own `resignFirstResponder` (where the canvas editor commits) and its delegate's
// `textDidEndEditing` (where the Text tab's area commits).
final class EndWatch: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
    var ended = 0
    func controlTextDidEndEditing(_ obj: Notification) { ended += 1 }
    func textDidEndEditing(_ notification: Notification) { ended += 1 }
}
final class CountingTextView: NSTextView {
    var resigned = 0
    override func resignFirstResponder() -> Bool {
        resigned += 1
        return super.resignFirstResponder()
    }
}
let fieldWatch = EndWatch()
let e = open(args[5])
let field = NSTextField(frame: NSRect(x: 8, y: 8, width: 120, height: 22))
field.delegate = fieldWatch
e.editor.view.addSubview(field)
let fieldBegan = e.window.makeFirstResponder(field)
(field.currentEditor() as? NSTextView)?.insertText(
    "typed", replacementRange: NSRange(location: NSNotFound, length: 0))
let fieldEditing = field.currentEditor() != nil
e.document.close()
let fieldEndedAtClose = fieldWatch.ended
spin(0.5)
let textWatch = EndWatch()
let f = open(args[6])
let text = CountingTextView(frame: NSRect(x: 8, y: 8, width: 200, height: 60))
text.delegate = textWatch
f.editor.view.addSubview(text)
let textBegan = f.window.makeFirstResponder(text)
text.insertText("typed", replacementRange: NSRange(location: NSNotFound, length: 0))
let textFirst = f.window.firstResponder === text
f.document.close()
let textEndedAtClose = textWatch.ended
let textResignedAtClose = text.resigned
spin(0.5)
answer["P7"] = [
    "field": [
        "began": fieldBegan, "editing": fieldEditing, "endedAtClose": fieldEndedAtClose,
        "endedAfter": fieldWatch.ended, "detached": detached(e),
    ] as [String: Any],
    "text": [
        "began": textBegan, "editing": textFirst, "endedAtClose": textEndedAtClose,
        "endedAfter": textWatch.ended, "resignedAtClose": textResignedAtClose,
        "resignedAfter": text.resigned, "detached": detached(f),
    ] as [String: Any],
] as [String: Any]

let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
FileHandle.standardOutput.write("ANSWER ".data(using: .utf8)! + data + "\n".data(using: .utf8)!)
exit(0)
