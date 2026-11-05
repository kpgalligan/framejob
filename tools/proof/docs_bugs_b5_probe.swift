// Docs bugs b5: a folder dropped on the Media tab (#497), the step MCP cannot send, through the app's
// own sources on a real `.framejob` package an app saved. Compiled AS main.swift over every file of
// app/Sources but the app's main.swift, through swift_build.py, by `docs_bugs_b5_proof.py`.
//
//   docs-bugs-b5-probe <fixtures> <good.framejob> [-RCFFmpegPath /nonexistent/ffmpeg]
//
// A drop: MediaPane.draggingEntered/performDragOperation with a stub NSDraggingInfo over a PRIVATE
//   uniquely named pasteboard; the general pasteboard is never touched. No drag starts.
// ffmpeg's consent: NSAlert.runModal is replaced in this process only: it records the alert and
//   answers Cancel, so no modal window appears.
// A copy's progress window: `ProjectDocument.copyWatch` is a no-op that counts its calls for each
//   drop and is restored after it, so a Matroska copy never orders a panel front.
//
// Nothing reaches the screen or takes focus: activation policy .prohibited, a window 20,000 pt off
// every display, held there by constrainFrameRect (docs_bugs_b2_probe.swift's pattern). The alert
// sheets are the real ones, read back from the window.
//
// It names only symbols present before the fix, and compares nothing itself, so it builds over the
// base's sources and `docs_bugs_b5_proof.py` scores the same rows on both. One JSON line a row.
import AppKit
import ObjectiveC

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
DecoderSupport.enable()

let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
let package = URL(fileURLWithPath: CommandLine.arguments[2])
let realGeneralCount = NSPasteboard.general.changeCount

func say(_ row: String, _ fields: [String: Any]) {
    var line = fields
    line["row"] = row
    let data = try! JSONSerialization.data(
        withJSONObject: line, options: [.sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

func waitUntil(_ limit: Double, _ condition: () -> Bool) -> Bool {
    let start = Date()
    while Date().timeIntervalSince(start) < limit {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

final class OffWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct Open {
    let doc: ProjectDocument
    let controller: EditorViewController
    let window: NSWindow
    let keep: NSWindowController
}

/// Each row reads its OWN copy of the package: a document with a fileURL autosaves in place, so a
/// shared one carries one row's media into the next.
var rowCount = 0

func open() -> Open {
    rowCount += 1
    let copy = package.deletingLastPathComponent()
        .appendingPathComponent("row\(rowCount)-\(package.lastPathComponent)")
    try? FileManager.default.removeItem(at: copy)
    try! FileManager.default.copyItem(at: package, to: copy)
    let doc = ProjectDocument()
    do {
        try doc.read(from: copy, ofType: ProjectDocument.projectTypeIdentifier)
        doc.fileURL = copy
    } catch {
        say("abort", ["read": "\(error)"])
        exit(2)
    }
    doc.startGraphicStore()
    let controller = EditorViewController(document: doc)
    let window = OffWindow(
        contentRect: NSRect(x: -20000, y: -20000, width: 1440, height: 900),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentViewController = controller
    window.setFrame(NSRect(x: -20000, y: -20000, width: 1440, height: 900), display: false)
    controller.viewWillAppear()
    controller.viewDidAppear()
    controller.refreshFromDocument(isLive: false)
    let keep = NSWindowController(window: window)
    doc.addWindowController(keep)
    window.orderBack(nil)
    for _ in 0..<12 {
        spin(0.05)
        controller.view.layoutSubtreeIfNeeded()
    }
    guard doc.windowForSheet === window else {
        say("abort", ["why": "windowForSheet is not the probe's window"])
        exit(2)
    }
    return Open(doc: doc, controller: controller, window: window, keep: keep)
}

func close(_ o: Open) {
    o.window.orderOut(nil)
    o.doc.removeWindowController(o.keep)
}

func sheetTexts(_ sheet: NSWindow) -> [String] {
    (sheet.contentView.map(walk) ?? []).compactMap { ($0 as? NSTextField)?.stringValue }
        .filter { !$0.isEmpty }
}

/// Every alert sheet that arrives within `wait`, in order, each ended.
func alerts(_ o: Open, wait: Double) -> [[String]] {
    var shown: [[String]] = []
    while waitUntil(wait, { o.window.attachedSheet != nil }), let sheet = o.window.attachedSheet {
        shown.append(sheetTexts(sheet))
        o.window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        _ = waitUntil(3) { o.window.attachedSheet == nil }
    }
    return shown
}

// MARK: - The stand-ins

var modalsSeen: [[String: Any]] = []

func replaceRunModal() {
    guard let method = class_getInstanceMethod(NSAlert.self, #selector(NSAlert.runModal)) else {
        say("abort", ["why": "no runModal"])
        exit(2)
    }
    let run: @convention(block) (NSAlert) -> Int = { alert in
        modalsSeen.append(["message": alert.messageText, "informative": alert.informativeText])
        return NSApplication.ModalResponse.alertSecondButtonReturn.rawValue
    }
    method_setImplementation(method, imp_implementationWithBlock(run))
}

final class StubDrag: NSObject, NSDraggingInfo {
    let board: NSPasteboard
    let target: NSWindow
    init(board: NSPasteboard, target: NSWindow) {
        self.board = board
        self.target = target
    }
    var draggingDestinationWindow: NSWindow? { target }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { board }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

// MARK: - The rows

/// Each media entry by the name it shows: a copy's original, else its own file.
func media(_ o: Open) -> [[String: Any]] {
    o.doc.project.snapshot.media.map {
        let path = $0.original?.path ?? $0.path
        return ["name": (path as NSString).lastPathComponent, "kind": "\($0.kind)"]
    }
}

func drop(_ row: String, _ names: [String]) {
    let o = open()
    o.controller.inspector?.select(.media)
    spin(0.2)
    guard let inspectorView = o.controller.inspector?.view,
        let pane = walk(inspectorView).compactMap({ $0 as? MediaPane }).first
    else {
        say(row, ["error": "no MediaPane in the inspector"])
        return
    }
    let board = NSPasteboard.withUniqueName()
    board.clearContents()
    board.writeObjects(names.map { fixtures.appendingPathComponent($0) as NSURL })
    let info = StubDrag(board: board, target: o.window)
    let before = o.doc.project.snapshot.media.count
    modalsSeen = []
    let original = ProjectDocument.copyWatch
    var watched = 0
    ProjectDocument.copyWatch = { _ in watched += 1 }
    let entered = pane.draggingEntered(info)
    let performed = pane.performDragOperation(info)
    // The import is off the main thread: a first read in this process can take seconds, and a
    // Matroska copy more.
    _ = waitUntil(20) { o.window.attachedSheet != nil || o.doc.project.snapshot.media.count > before }
    var shown = alerts(o, wait: 1.5)
    spin(1.0)
    shown += alerts(o, wait: 0.5)
    ProjectDocument.copyWatch = original
    say(row, [
        "draggingEntered": entered == .copy, "performDragOperation": performed, "alerts": shown,
        "modals": modalsSeen, "media_before": before, "media_after": media(o),
        "undo_name": o.doc.undoManager?.undoActionName ?? "", "watched": watched,
    ])
    board.releaseGlobally()
    close(o)
}

replaceRunModal()

say("policy", ["tools_found": FFmpegRewrap.tools() != nil])
drop("D4", ["B.mov"])  // first: the first drop in a process waits on a cold import
drop("D1", ["Shoot"])
drop("D2", ["Shoot", "C.mov"])
drop("D3", ["Broken"])
drop("D5", ["Docs"])
say("PB", ["unchanged": NSPasteboard.general.changeCount == realGeneralCount])
exit(0)
