// tools/proof/document_close_probe.swift — the in-process instrument behind
// `document_close_probe.py` (#568). Compiled with every file in `app/Sources`
// but `main.swift`, copied in as `main.swift`, with the app's `Fonts`,
// `Blank.mp4` and a `default.metallib` of the app's own shader beside it —
// `scope_playhead_probe.swift`'s build.
//
//     document_close_probe <a.framejob> <b.framejob> <c.framejob>
//
// Each package is opened as a document with its editor window made and never
// shown, given one shape clip so its player has an item, and closed through a
// door of its own. The probe HOLDS each editor and its `Playback` strongly
// across the close, which is the case the fix is for: AppKit keeps a closed
// window alive for as long as it likes, so nothing here may depend on a deinit.
// The rebuild in flight is FORCED through `Playback.rebuildHop`, never waited
// for. The answer is one line, `ANSWER <json>`.
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
guard args.count == 4 else {
    print("usage: document_close_probe <a.framejob> <b.framejob> <c.framejob>")
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

var answer: [String: Any] = [:]

// P1 — the document's own close(), which `close_project` calls.
let a = open(args[1])
let heldProject = a.document.project
a.document.close()
answer["P1"] = shut(a)

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

let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
FileHandle.standardOutput.write("ANSWER ".data(using: .utf8)! + data + "\n".data(using: .utf8)!)
exit(0)
