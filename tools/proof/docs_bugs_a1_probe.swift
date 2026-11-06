// Docs-bugs batch a1: #464, #465 and #507 through the app's own sources on real .framejob packages
// the app made and saved (`docs_bugs_a1_proof.py` makes them and scores what this prints). Compiled
// AS main.swift over every file of app/Sources but the app's main.swift, -D FRAMEJOB_DEV_TOOLS,
// against libframejob_core.a, through swift_build.py.
//
// Runs: docs_bugs_a1_probe <fixtures dir> <ids.json> [464|465|507|all]
//
// **The owner's clipboard is never written.** The process's +[NSPasteboard generalPasteboard] is
// replaced with a private named pasteboard BEFORE anything runs, and the probe exits unless
// `NSPasteboard.general` then answers that private board. So `controller.copy(nil)`, `cut(nil)` and
// `paste(nil)`, the @objc actions ⌘C, ⌘X and ⌘V send, run whole, default parameters and all, against
// private bytes. The real general board's changeCount is read at the start and the end (row PB).
//
// **Nothing reaches the screen or takes focus.** Activation policy .prohibited; each window's frame
// is 20,000 pt off every display, held there by constrainFrameRect, because an alert sheet needs a
// window that is ordered in.
//
// #465's events are NSEvents handed straight to `TimelineContentView.mouseDown/Dragged/Up`, never
// posted. #507 calls `performDragOperation` with a stub NSDraggingInfo and the same session and
// closure `MediaRowView.mouseDragged` makes: no real drag starts.
import AppKit
import ObjectiveC

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let realGeneral = NSPasteboard.general
let realCount = realGeneral.changeCount
let board = NSPasteboard(name: NSPasteboard.Name("com.kgalligan.framejob.proof.a1.\(getpid())"))
board.clearContents()
do {
    let selector = NSSelectorFromString("generalPasteboard")
    guard let method = class_getClassMethod(NSPasteboard.self, selector) else {
        print("{\"abort\": \"no generalPasteboard method\"}")
        exit(2)
    }
    let replacement: @convention(block) (AnyObject) -> NSPasteboard = { _ in board }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
}
guard NSPasteboard.general === board, NSPasteboard.general.name == board.name,
    NSPasteboard.general.name != realGeneral.name
else {
    print("{\"abort\": \"NSPasteboard.general still answers the real board\"}")
    exit(2)
}

let arguments = CommandLine.arguments
let fixtures = URL(fileURLWithPath: arguments[1])
let ids = (try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: arguments[2]))))
    as! [String: [String: Any]]
let second: Ticks = 600_000

func say(_ id: String, _ fields: [String: Any]) {
    var row = fields
    row["row"] = id
    let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
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

func open(_ name: String) -> Open {
    let url = fixtures.appendingPathComponent("\(name).framejob")
    let doc = ProjectDocument()
    do {
        try doc.read(from: url, ofType: ProjectDocument.projectTypeIdentifier)
        doc.fileURL = url
    } catch {
        print("{\"abort\": \"read \(name): \(error)\"}")
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
        print("{\"abort\": \"windowForSheet is not the probe's window: an alert would be app-modal\"}")
        exit(2)
    }
    return Open(doc: doc, controller: controller, window: window, keep: keep)
}

func sheetTexts(_ sheet: NSWindow) -> [String] {
    (sheet.contentView.map(walk) ?? []).compactMap { ($0 as? NSTextField)?.stringValue }
        .filter { !$0.isEmpty }
}

/// The alert a step put up, its texts, and ends it; NSNull when none came.
func settle(_ o: Open, wait: Double = 0.4) -> Any {
    guard waitUntil(wait, { o.window.attachedSheet != nil }), let sheet = o.window.attachedSheet
    else { return NSNull() }
    let shown = sheetTexts(sheet)
    o.window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
    _ = waitUntil(3) { o.window.attachedSheet == nil }
    return shown
}

func parsed(_ text: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
}

/// What the scoring reads, off the core's own JSON: the top level's clips with each one's track
/// index, the nests with what their clips show, the track ids and the media file names.
func facts(_ text: String) -> [String: Any] {
    let root = parsed(text)
    let tracks = (root["tracks"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? Int }
    func row(_ clip: [String: Any]) -> [String: Any] {
        [
            "id": clip["id"] ?? NSNull(), "track": clip["track"] ?? NSNull(),
            "index": tracks.firstIndex(of: clip["track"] as? Int ?? -1) ?? -1,
            "start": clip["start"] ?? NSNull(), "duration": clip["duration"] ?? NSNull(),
            "source": clip["source"] ?? NSNull(), "linked": clip["linked"] ?? NSNull(),
            "transition": (clip["transition_in"] as? [String: Any])?["kind"] ?? NSNull(),
        ]
    }
    return [
        "clips": (root["clips"] as? [[String: Any]] ?? []).map(row),
        "nests": (root["nests"] as? [[String: Any]] ?? []).map {
            ["id": $0["id"] ?? NSNull(), "clips": ($0["clips"] as? [[String: Any]] ?? []).map(row)]
        },
        "tracks": tracks,
        "media": (root["media"] as? [[String: Any]] ?? []).compactMap {
            ($0["path"] as? String).map { ($0 as NSString).lastPathComponent }
        },
    ]
}

func undoName(_ o: Open) -> String {
    let m = o.doc.undoManager
    return m?.canUndo == true ? (m?.undoActionName ?? "") : "<nothing to undo>"
}

func strip(_ o: Open) -> String { o.controller.inspector?.refusalStrip.text ?? "" }

func select(_ o: Open, _ clips: [UInt32]) {
    o.doc.selection = Set(clips)
    o.controller.refreshFromDocument(isLive: false)
    spin(0.05)
}

/// What a menu event around the action gives it: its undo, if any, one group.
func action(_ o: Open, _ body: () -> Void) {
    o.doc.inUndoGroupIfRegistered(body)
    spin(0.2)
}

func undo(_ o: Open) { action(o) { o.doc.undoManager?.undo() } }

/// Undoes back to `text`; how many steps that took, and whether it got there.
func undoBack(_ o: Open, to text: String) -> [String: Any] {
    var steps = 0
    while o.doc.project.json != text, o.doc.undoManager?.canUndo == true, steps < 6 {
        undo(o)
        steps += 1
    }
    return ["undo_steps": steps, "restored": o.doc.project.json == text]
}

func payload() -> [String: Any] {
    guard let data = board.data(forType: EditorViewController.clipsPasteboardType),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return root
}

func playhead(_ o: Open, _ seconds: Ticks) {
    o.controller.setPlayhead(seconds * second)
    spin(0.1)
}

func u32(_ value: Any?) -> UInt32 { (value as? NSNumber)?.uint32Value ?? 0 }

func payloadFields() -> [String: Any] {
    let root = payload()
    return [
        "payload_keys": root.keys.sorted(),
        "payload_clips": (root["clips"] as? [Any])?.count ?? -1,
        "payload_media": (root["media"] as? [Any])?.count ?? -1,
        "payload_nests": (root["nests"] as? [Any])?.count ?? -1,
    ]
}

// MARK: - #464

/// Copy the selection, paste it at `at`, and answer the row with the project as it landed.
func copyPaste(_ id: String, _ o: Open, _ clips: [UInt32], at: Ticks) {
    let before = o.doc.project.json
    select(o, clips)
    action(o) { o.controller.copy(nil) }
    let copied = payloadFields()
    playhead(o, at)
    action(o) { o.controller.paste(nil) }
    let alert = settle(o)
    var row = copied
    row["alert"] = alert
    row["undo"] = undoName(o)
    row["before"] = facts(before)
    row["after"] = facts(o.doc.project.json)
    say(id, row.merging(undoBack(o, to: before)) { a, _ in a })
}

func run464() {
    let nest = ids["nest"]!
    let nestClip = u32(nest["nest_clip"]), plain = u32(nest["plain_clip"])
    let o = open("nest")
    copyPaste("N9", o, [plain], at: 40)
    copyPaste("N1", o, [nestClip], at: 40)
    copyPaste("N2", o, [nestClip, plain], at: 40)

    // N3 and N4: Cut, Paste, the two undo names; then the same board into another project.
    let text = o.doc.project.json
    select(o, [nestClip])
    action(o) { o.controller.cut(nil) }
    let cutAlert = settle(o, wait: 0.2)
    let undoCut = undoName(o)
    playhead(o, 40)
    action(o) { o.controller.paste(nil) }
    let pasteAlert = settle(o)
    let undoPaste = undoName(o)
    let landed = facts(o.doc.project.json)
    var undoAfterFirst = "<none>"
    if undoPaste == "Paste" {
        undo(o)
        undoAfterFirst = undoName(o)
    }
    let other = open("other")
    action(other) { other.controller.paste(nil) }
    say("N4", ["alert": settle(other), "after": facts(other.doc.project.json), "undo": undoName(other)])
    other.window.orderOut(nil)
    say("N3", ["cut_alert": cutAlert, "undo_after_cut": undoCut, "alert": pasteAlert,
               "undo": undoPaste, "undo_after_paste_undone": undoAfterFirst, "after": landed,
               "before": facts(text)].merging(undoBack(o, to: text)) { a, _ in a })
    o.window.orderOut(nil)

    let deep = ids["deep"]!
    let outer = u32(deep["outer_clip"]), inner = u32(deep["inner_clip"])
    let d = open("deep")
    copyPaste("N5", d, [outer], at: 60)

    // N8: inside the open nest, the nest clip that sits there.
    let opened = d.doc.project.json
    d.controller.openNest(clipID: outer)
    spin(0.2)
    select(d, [inner])
    action(d) { d.controller.copy(nil) }
    let copied = payloadFields()
    playhead(d, 60)
    action(d) { d.controller.paste(nil) }
    var row = copied
    row["alert"] = settle(d)
    row["undo"] = undoName(d)
    row["scope"] = d.doc.scope.map { Int($0) } ?? -1
    row["before"] = facts(opened)
    row["after"] = facts(d.doc.project.json)
    row["view"] = facts(d.doc.editedProject.json)
    let backed = undoBack(d, to: opened)
    d.controller.leaveAllNests(to: 0)
    say("N8", row.merging(backed) { a, _ in a })
    d.window.orderOut(nil)

    let shared = ids["shared"]!
    let s = open("shared")
    copyPaste("N6", s, [u32(shared["first"]), u32(shared["second"])], at: 60)
    s.window.orderOut(nil)
}

// MARK: - #465

func mouse(_ type: NSEvent.EventType, _ o: Open, _ point: CGPoint, _ flags: NSEvent.ModifierFlags) -> NSEvent {
    let content = o.controller.timeline!.content
    return NSEvent.mouseEvent(
        with: type, location: content.convert(point, to: nil), modifierFlags: flags,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: o.window.windowNumber,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}

/// The drag, and whether the timeline's refusal flash is up the moment mouse-up returns (it runs
/// 0.22 s). `steps` 1 is a jump: no tick lands on a spot the drop then leaves. `via` is a list of
/// points the drag passes first, `steps` ticks to each in turn, every leg ending on its point.
func drag(
    _ o: Open, from: CGPoint, to: CGPoint, flags: NSEvent.ModifierFlags, steps: Int,
    via: [CGPoint] = []
) -> Bool {
    let content = o.controller.timeline!.content
    content.mouseDown(with: mouse(.leftMouseDown, o, from, flags))
    spin(0.05)
    var leg = from
    for end in via + [to] {
        for step in 1...steps {
            let f = CGFloat(step) / CGFloat(steps)
            let p = step == steps
                ? end : CGPoint(x: leg.x + (end.x - leg.x) * f, y: leg.y + (end.y - leg.y) * f)
            content.mouseDragged(with: mouse(.leftMouseDragged, o, p, flags))
            spin(0.05)
        }
        leg = end
    }
    content.mouseUp(with: mouse(.leftMouseUp, o, to, flags))
    let flashed = o.controller.timeline!.refusal != nil
    spin(0.3)
    return flashed
}

func clipPoint(_ o: Open, _ id: UInt32) -> CGPoint {
    let t = o.controller.timeline!
    let clip = t.snapshot.clip(id)!
    let row = t.layout.row(forTrackIndex: t.snapshot.trackIndex(of: clip.track)!)
    let rect = t.layout.clipRect(clip, row: row)
    return CGPoint(x: rect.midX, y: rect.midY)
}

/// Where a drag must end for `grabbed`'s start to land at `seconds` on display `row`: a row past
/// either end of the stack is a point past that end.
func dropPoint(_ o: Open, row: Int, seconds: Double, grabbed: UInt32, from: CGPoint) -> CGPoint {
    let t = o.controller.timeline!
    let last = t.snapshot.tracks.count - 1
    let y: CGFloat
    if row < 0 {
        y = t.layout.rowRect(0, width: 100).minY - 10
    } else if row > last {
        y = t.layout.rowRect(last, width: 100).maxY + 10
    } else {
        y = t.layout.rowRect(row, width: 100).midY
    }
    let clip = t.snapshot.clip(grabbed)!
    return CGPoint(x: t.layout.x(for: Ticks(seconds * 600_000)) + from.x - t.layout.x(for: clip.start), y: y)
}

/// One drag: `grab` is pressed, with `clips` selected first, and dropped on display row `row`
/// (track index `index` when given) at `seconds`, through the display row and seconds of `via`
/// first when it is given.
func trial(
    _ id: String, _ o: Open, grab: UInt32, clips: [UInt32], index: Int? = nil, row: Int? = nil,
    seconds: Double, flags: NSEvent.ModifierFlags, steps: Int = 4,
    via: (row: Int, seconds: Double)? = nil
) {
    let before = o.doc.project.json
    select(o, clips)
    let t = o.controller.timeline!
    let display = row ?? t.layout.row(forTrackIndex: index!)
    let from = clipPoint(o, grab)
    let to = dropPoint(o, row: display, seconds: seconds, grabbed: grab, from: from)
    let stops = via.map {
        [dropPoint(o, row: $0.row, seconds: $0.seconds, grabbed: grab, from: from)]
    } ?? []
    let flashed = drag(o, from: from, to: to, flags: flags, steps: steps, via: stops)
    var answer: [String: Any] = [
        "flash": flashed, "undo": undoName(o), "strip": strip(o), "alert": settle(o, wait: 0.1),
        "before": facts(before), "after": facts(o.doc.project.json),
    ]
    answer.merge(undoBack(o, to: before)) { a, _ in a }
    say(id, answer)
    select(o, [])
}

func run465() {
    let info = ids["drag"]!
    let first = u32(info["first"]), last = u32(info["second"])
    let o = open("drag")
    let lane = o.doc.project.snapshot.trackIndex(of: u32(info["track"]))!
    let free = o.doc.project.snapshot.trackIndex(of: u32(info["empty_track"]))!
    trial("D1", o, grab: first, clips: [first], index: free, seconds: 12, flags: [.option])
    trial("D2", o, grab: first, clips: [first], index: lane, seconds: 20, flags: [.option])
    trial("D3", o, grab: last, clips: [last], index: free, seconds: 12, flags: [.option])
    trial("D4", o, grab: first, clips: [first], index: free, seconds: 12, flags: [])
    trial("D5", o, grab: last, clips: [last], index: lane, seconds: 0, flags: [.option], steps: 1)
    trial("D6", o, grab: first, clips: [first], row: -1, seconds: 12, flags: [.option])
    o.window.orderOut(nil)

    let link = ids["link"]!
    let picture = u32(link["picture"])
    let l = open("link")
    trial("D9", l, grab: picture, clips: [picture], index: 2, seconds: 12, flags: [.option])
    trial("D10", l, grab: picture, clips: [picture], row: -1, seconds: 12, flags: [.option])
    trial("D11", l, grab: picture, clips: [picture], index: 2, seconds: 0, flags: [.option], steps: 1)
    // A good tick past the top lane at 12 s, then a refused one there at 0 s.
    trial("D17", l, grab: picture, clips: [picture], row: -1, seconds: 0, flags: [.option], steps: 1,
          via: (row: -1, seconds: 12))
    l.window.orderOut(nil)

    let lanes = ids["lanes"]!
    let back = u32(lanes["back"]), front = u32(lanes["front"])
    let two = open("lanes")
    let pair = [back, front]
    trial("D12", two, grab: front, clips: pair, row: -1, seconds: 30, flags: [.option], steps: 1)
    trial("D13", two, grab: front, clips: pair, row: -1, seconds: 30, flags: [], steps: 1)
    trial("D14", two, grab: back, clips: pair, row: 2, seconds: 30, flags: [.option])
    // The back clip straight up a row: the front one would leave the track list.
    trial("D19", two, grab: back, clips: pair, row: 0, seconds: 0, flags: [])
    // A good tick on the back clip's own row at 30 s, then a refused one a row up.
    trial("D20", two, grab: back, clips: pair, row: 0, seconds: 30, flags: [.option], steps: 1,
          via: (row: 1, seconds: 30))
    two.window.orderOut(nil)

    // Staggered: the back clip on index 0 at 0 s, the front one on index 1 at 2 s, two free
    // tracks above. The front clip is grabbed.
    let staggered = ids["staggered"]!
    let lower = u32(staggered["back"]), upper = u32(staggered["front"])
    let st = open("staggered")
    let both = [lower, upper]
    trial("D15", st, grab: upper, clips: both, index: 2, seconds: 30, flags: [.option])
    trial("D16", st, grab: upper, clips: both, index: 2, seconds: 30, flags: [])
    trial("D18", st, grab: upper, clips: both, row: 4, seconds: 30, flags: [.option])
    trial("D21", st, grab: upper, clips: both, index: 1, seconds: 30, flags: [])
    st.window.orderOut(nil)
}

// MARK: - #507

final class StubDrag: NSObject, NSDraggingInfo {
    let location: NSPoint
    let target: NSWindow
    init(location: NSPoint, target: NSWindow) {
        self.location = location
        self.target = target
    }
    var draggingDestinationWindow: NSWindow? { target }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
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

func run507() {
    let info = ids["drop"]!
    let free = u32(info["free_media"]), clip = u32(info["clip"]), track = u32(info["track"])
    let o = open("drop")
    o.controller.inspector?.select(.media)
    spin(0.2)
    guard let inspectorView = o.controller.inspector?.view,
        let pane = walk(inspectorView).compactMap({ $0 as? MediaPane }).first,
        let timeline = o.controller.timeline,
        let canvas = walk(o.controller.view).compactMap({ $0 as? PreviewCanvasView }).first
    else {
        print("{\"abort\": \"no MediaPane, timeline or canvas\"}")
        exit(2)
    }
    // The session and closure MediaRowView.mouseDragged makes.
    MediaDragSession.current = MediaDragSession(
        media: free, source: pane,
        drop: { [weak pane, free] destination, target in
            pane?.drop(free, on: destination, target: target) ?? false
        })

    func perform(_ id: String, _ answerOf: () -> Bool) {
        let before = o.doc.project.json
        let undoBefore = undoName(o)
        let answer = answerOf()
        spin(0.3)
        var row: [String: Any] = [
            "performDragOperation": answer, "undo_before": undoBefore, "undo": undoName(o),
            "strip": strip(o), "alert": settle(o, wait: 0.1), "before": facts(before),
            "after": facts(o.doc.project.json),
        ]
        row.merge(undoBack(o, to: before)) { a, _ in a }
        say(id, row)
    }

    func drop(_ id: String, at point: CGPoint) {
        let stub = StubDrag(location: timeline.content.convert(point, to: nil), target: o.window)
        perform(id) {
            _ = timeline.draggingEntered(stub)
            _ = timeline.draggingUpdated(stub)
            return timeline.performDragOperation(stub)
        }
    }

    let row = timeline.layout.row(forTrackIndex: timeline.snapshot.trackIndex(of: track)!)
    let y = timeline.layout.rowRect(row, width: 100).midY
    let target = timeline.snapshot.clip(clip)!
    func x(_ seconds: Double) -> CGFloat { timeline.layout.x(for: Ticks(seconds * 600_000)) }
    drop("M1", at: CGPoint(x: x(1), y: y))
    drop("M2", at: CGPoint(x: x(1), y: timeline.layout.rowRect(row, width: 100).maxY + 200))
    drop("M3", at: CGPoint(x: x(12), y: y))
    drop("M4", at: CGPoint(x: x(Double(target.end) / 600_000 - 2), y: y))
    playhead(o, 40)
    let stub = StubDrag(location: .zero, target: o.window)
    perform("M6") { canvas.performDragOperation(stub) }
    MediaDragSession.current = nil
    o.window.orderOut(nil)
}

switch arguments.count > 3 ? arguments[3] : "all" {
case "464": run464()
case "465": run465()
case "507": run507()
default:
    run464()
    run465()
    run507()
}
say("PB", ["start": realCount, "end": realGeneral.changeCount])
board.releaseGlobally()
exit(0)
