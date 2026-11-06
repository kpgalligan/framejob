// Docs-bugs batch a2: #463, #474 and #475 through the app's own sources on a real .framejob package
// the app made and saved (`docs_bugs_a2_proof.py` makes it and scores what this prints). Compiled AS
// main.swift over every file of app/Sources but the app's main.swift, -D FRAMEJOB_DEV_TOOLS, against
// libframejob_core.a, through swift_build.py. It names no symbol the base lacks, so the same source
// builds against the base tree.
//
// Runs: docs_bugs_a2_probe <fixture.framejob> <scratch folder> <ids.json> [N1,K3,…]
//
// So what runs is the real EditorWindow, EditorViewController and PreviewCanvasView. **No event is
// posted and nothing takes focus:** the app is `.prohibited`, so it cannot activate, and its window
// has alpha 0.
//
// **Keys** go in through `EditorWindow.sendEvent`, the real door. Arrows carry
// [.numericPad, .function], keypad Enter .numericPad, as real keys do; what a real keyboard sends is
// TL-18 in docs/manual-checks.md.
//
// **The mouse does not.** A `.prohibited` app's window is never key and `sendEvent` eats its first
// click, so a press goes by `mouseDown(with:)` to the view `hitTest` picks, the drag and the release
// to that same view. The handlers are real; AppKit's dispatch of a mouse event is not. F1 and F2 are
// the exception: they test what `sendEvent` does BEFORE dispatch, so the eaten click doesn't matter.
//
// `noResponder(for:)`, the end of the responder chain, is replaced with a counter, which keeps a key
// nobody takes silent. `NSSound.beep()` is not: S1 to S5 are what it is for, and a person may hear it.
import AppKit
import ObjectiveC

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

let arguments = CommandLine.arguments
let fixture = URL(fileURLWithPath: arguments[1])
let scratch = URL(fileURLWithPath: arguments[2])
let ids = (try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: arguments[3]))))
    as! [String: Int]
let wanted = Set(arguments.count > 4 ? arguments[4].split(separator: ",").map(String.init) : [])

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

var chainEnd = 0
do {
    let selector = #selector(NSResponder.noResponder(for:))
    guard let method = class_getInstanceMethod(NSWindow.self, selector) else {
        print("{\"abort\": \"noResponder(for:) not found\"}")
        exit(2)
    }
    let block: @convention(block) (AnyObject, Selector) -> Void = { _, _ in chainEnd += 1 }
    method_setImplementation(method, imp_implementationWithBlock(block))
}

func say(_ id: String, _ fields: [String: Any]) {
    var row = fields
    row["row"] = id
    let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

let SEC = ReelTime.perSecond
func id(_ name: String) -> UInt32 { UInt32(ids[name]!) }
let VIDEO = id("video")
let SHAPE = id("shape")
let TEXT = id("text")
let GRAPHIC = id("graphic")
let ACTION = id("action")
let MATTE = id("matte")
// Each one alone over the video, and the matte rectangle in front of the graphic.
let AT_SHAPE = 4.0
let AT_TEXT = 6.0
let AT_GRAPHIC = 8.0
let AT_MATTE = 9.25

// MARK: - The editor

struct Editor {
    let document: ProjectDocument
    let controller: EditorViewController
    let window: NSWindow
    var canvas: PreviewCanvasView { controller.previewCanvas! }
    var overlay: CanvasOverlayView { canvas.overlay }
}

func open(_ tag: String, playhead seconds: Double) -> Editor? {
    let copy = scratch.appendingPathComponent("run-\(tag).framejob")
    try? FileManager.default.removeItem(at: copy)
    do {
        try FileManager.default.copyItem(at: fixture, to: copy)
        let document = ProjectDocument()
        try document.read(from: copy, ofType: ProjectDocument.projectTypeIdentifier)
        document.fileURL = copy
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let window = document.windowControllers.first?.window,
              let controller = window.contentViewController as? EditorViewController
        else { return nil }
        window.alphaValue = 0
        document.showWindows()
        spin(1.2)
        var tries = 0
        repeat {
            controller.setPlayhead(Ticks(seconds * Double(SEC)))
            spin(0.4)
            tries += 1
        } while document.playhead != Ticks(seconds * Double(SEC)) && tries < 4
        return Editor(document: document, controller: controller, window: window)
    } catch {
        return nil
    }
}

func close(_ editor: Editor) {
    editor.controller.playback.pause()
    editor.document.close()
    spin(0.2)
}

/// One row: its own editor at `seconds`, and what `body` read.
func row(_ name: String, at seconds: Double = 2, _ body: (Editor) -> [String: Any]) {
    guard wanted.isEmpty || wanted.contains(name) else { return }
    guard let editor = open(name, playhead: seconds) else {
        say(name, ["failed": "no editor"])
        return
    }
    say(name, body(editor))
    close(editor)
}

func responder(_ editor: Editor) -> String {
    guard let first = editor.window.firstResponder else { return "nil" }
    if first === editor.window.contentView { return "content" }
    if first === editor.overlay { return "overlay" }
    return "\(type(of: first))"
}

func clip(_ editor: Editor, _ id: UInt32) -> ClipSnapshot? {
    editor.document.editedProject.snapshot.clip(id)
}

func x(_ editor: Editor, _ id: UInt32) -> Double { clip(editor, id)?.video?.x ?? .nan }
func y(_ editor: Editor, _ id: UInt32) -> Double { clip(editor, id)?.video?.y ?? .nan }
func left(_ editor: Editor, _ id: UInt32) -> Double { clip(editor, id)?.video?.crop.l ?? -1 }

func frame(_ editor: Editor) -> Double { Double(editor.document.playhead) / (Double(SEC) / 30) }

func undo(_ editor: Editor) -> String {
    let manager = editor.document.undoManager
    return manager?.canUndo == true ? manager?.undoActionName ?? "" : ""
}

func playing(_ editor: Editor) -> Bool { editor.controller.playback.isPlaying }

func select(_ editor: Editor, _ clips: Set<UInt32>) {
    editor.document.selection = clips
    editor.controller.viewStateDidChange()
    spin(0.2)
}

func toRoot(_ editor: Editor) {
    editor.window.makeFirstResponder(editor.window.contentView)
    spin(0.1)
}

// MARK: - Keys

let ARROW: NSEvent.ModifierFlags = [.numericPad, .function]
let CAPS: NSEvent.ModifierFlags = [.capsLock]
func scalar(_ value: Int) -> String { String(Character(UnicodeScalar(UInt32(value))!)) }
let LEFT = scalar(NSLeftArrowFunctionKey)
let RIGHT = scalar(NSRightArrowFunctionKey)
let UP = scalar(NSUpArrowFunctionKey)
let DOWN = scalar(NSDownArrowFunctionKey)
let ESC = "\u{1b}"
let ENTER = "\u{3}"

func keyEvent(
    _ editor: Editor, _ text: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags,
    type: NSEvent.EventType, isRepeat: Bool
) -> NSEvent {
    NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: editor.window.windowNumber, context: nil, characters: text,
        charactersIgnoringModifiers: text, isARepeat: isRepeat, keyCode: code)!
}

func press(
    _ editor: Editor, _ text: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = [],
    isRepeat: Bool = false
) {
    editor.window.sendEvent(
        keyEvent(editor, text, code, flags, type: .keyDown, isRepeat: isRepeat))
    spin(0.12)
}

func release(_ editor: Editor, _ text: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
    editor.window.sendEvent(keyEvent(editor, text, code, flags, type: .keyUp, isRepeat: false))
    spin(0.12)
}

func pressC(_ editor: Editor) { press(editor, "c", 8) }

// MARK: - The mouse

var mouseTarget: NSView?

func mouseEvent(
    _ editor: Editor, _ type: NSEvent.EventType, at location: NSPoint, clicks: Int,
    flags: NSEvent.ModifierFlags
) -> NSEvent {
    NSEvent.mouseEvent(
        with: type, location: location, modifierFlags: flags, timestamp: 0,
        windowNumber: editor.window.windowNumber, context: nil, eventNumber: 0,
        clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1)!
}

func mouse(
    _ editor: Editor, _ type: NSEvent.EventType, at location: NSPoint, clicks: Int = 1,
    flags: NSEvent.ModifierFlags = []
) {
    let event = mouseEvent(editor, type, at: location, clicks: clicks, flags: flags)
    switch type {
    case .leftMouseDown:
        let content = editor.window.contentView!
        mouseTarget = (content.superview ?? content).hitTest(location)
        mouseTarget?.mouseDown(with: event)
    case .leftMouseDragged:
        mouseTarget?.mouseDragged(with: event)
    default:
        mouseTarget?.mouseUp(with: event)
    }
    spin(0.05)
}

/// A press and release through `EditorWindow.sendEvent`, for what it does before dispatch.
func sendClick(_ editor: Editor, at location: NSPoint) {
    editor.window.sendEvent(mouseEvent(editor, .leftMouseDown, at: location, clicks: 1, flags: []))
    editor.window.sendEvent(mouseEvent(editor, .leftMouseUp, at: location, clicks: 1, flags: []))
    spin(0.1)
}

func onCanvas(_ editor: Editor, _ point: CGPoint) -> NSPoint {
    editor.overlay.convert(point, to: nil)
}

func centre(_ editor: Editor, _ id: UInt32) -> CGPoint {
    guard let box = editor.canvas.box(for: id) else { return .zero }
    return editor.canvas.canvasToView(CGPoint(x: box.rect.midX, y: box.rect.midY))
}

func clickCanvas(
    _ editor: Editor, _ id: UInt32, clicks: Int = 1, flags: NSEvent.ModifierFlags = []
) {
    let at = onCanvas(editor, centre(editor, id))
    for count in 1...clicks {
        mouse(editor, .leftMouseDown, at: at, clicks: count, flags: flags)
        mouse(editor, .leftMouseUp, at: at, clicks: count, flags: flags)
    }
    spin(0.2)
}

func timeline(_ editor: Editor) -> TimelineContentView? {
    walk(editor.window.contentView!).compactMap { $0 as? TimelineContentView }.first
}

func clickTimeline(_ editor: Editor, _ id: UInt32) {
    guard let view = timeline(editor) else { return }
    let bounds = view.bounds
    var y = bounds.minY
    while y < bounds.maxY {
        var x = bounds.minX
        while x < bounds.maxX {
            let point = CGPoint(x: x + 30, y: y + 12)
            if view.hit(at: CGPoint(x: x, y: y)) == .clip(id), view.hit(at: point) == .clip(id) {
                let at = view.convert(point, to: nil)
                mouse(editor, .leftMouseDown, at: at)
                mouse(editor, .leftMouseUp, at: at)
                spin(0.3)
                return
            }
            x += 8
        }
        y += 4
    }
}

func sections(_ editor: Editor) -> [InspectorSection] {
    walk(editor.window.contentView!).compactMap { $0 as? InspectorSection }
}

func transformField(_ editor: Editor) -> NSTextField? {
    editor.controller.inspector?.selectClipSubTab(.picture)
    spin(0.3)
    return sections(editor).first { $0.id == "video.transform" }
        .flatMap { walk($0).compactMap { $0 as? NSTextField }.first { $0.isEditable } }
}

/// Counts `onCropModeChanged`, keeping the closure it finds.
func counted(_ editor: Editor) -> () -> Int {
    var count = 0
    let inner = editor.canvas.onCropModeChanged
    editor.canvas.onCropModeChanged = { on in
        count += 1
        inner?(on)
    }
    return { count }
}

/// A move drag on the video, held at 40, 25 pt: the release point.
func heldDrag(_ editor: Editor, flags: NSEvent.ModifierFlags) -> NSPoint {
    let start = centre(editor, VIDEO)
    mouse(editor, .leftMouseDown, at: onCanvas(editor, start), flags: flags)
    let held = onCanvas(editor, CGPoint(x: start.x + 40, y: start.y + 25))
    mouse(editor, .leftMouseDragged, at: held, flags: flags)
    spin(0.1)
    return held
}

// MARK: - #463: the arrows

row("N1") { e in
    clickCanvas(e, VIDEO)
    let (x0, f0, first) = (x(e, VIDEO), frame(e), responder(e))
    press(e, LEFT, 123, ARROW)
    return ["first": first, "dx": x(e, VIDEO) - x0, "frames": frame(e) - f0, "undo": undo(e)]
}
row("N2") { e in
    clickCanvas(e, VIDEO)
    let (x0, f0) = (x(e, VIDEO), frame(e))
    press(e, RIGHT, 124, ARROW.union(.shift))
    return ["dx": x(e, VIDEO) - x0, "frames": frame(e) - f0, "undo": undo(e)]
}
row("N3") { e in
    clickCanvas(e, VIDEO)
    let (y0, f0) = (y(e, VIDEO), frame(e))
    press(e, UP, 126, ARROW)
    let up = y(e, VIDEO) - y0
    let upFrames = frame(e) - f0
    press(e, DOWN, 125, ARROW)
    return ["up": up, "down": y(e, VIDEO) - y0 - up, "up_frames": upFrames,
            "frames": frame(e) - f0]
}
row("N4") { e in
    clickCanvas(e, VIDEO)
    select(e, [SHAPE])
    let (x0, f0) = (x(e, SHAPE), frame(e))
    let shown = e.canvas.primaryBox != nil
    press(e, LEFT, 123, ARROW)
    return ["first": responder(e), "shown": shown, "dx": x(e, SHAPE) - x0,
            "frames": frame(e) - f0, "undo": undo(e)]
}
row("N5") { e in
    clickCanvas(e, VIDEO)
    let (x0, f0) = (x(e, VIDEO), frame(e))
    press(e, LEFT, 123, ARROW.union(.option))
    return ["dx": x(e, VIDEO) - x0, "frames": frame(e) - f0, "undo": undo(e)]
}
row("N6") { e in
    clickCanvas(e, VIDEO)
    toRoot(e)
    let (x0, f0) = (x(e, VIDEO), frame(e))
    press(e, LEFT, 123, ARROW)
    return ["first": responder(e), "dx": x(e, VIDEO) - x0, "frames": frame(e) - f0,
            "undo": undo(e)]
}
row("N7") { e in
    clickCanvas(e, VIDEO)
    let (x0, y0, f0) = (x(e, VIDEO), y(e, VIDEO), frame(e))
    let held = heldDrag(e, flags: [])
    let dragged = x(e, VIDEO)
    press(e, LEFT, 123, ARROW)
    let frames = frame(e) - f0
    let mid = x(e, VIDEO) - dragged
    press(e, ESC, 53)
    let (xEnd, yEnd, session) = (x(e, VIDEO) - x0, y(e, VIDEO) - y0, e.canvas.moving != nil)
    mouse(e, .leftMouseUp, at: held)
    spin(0.2)
    return ["moved": dragged - x0, "frames": frames, "mid": mid, "back_x": xEnd, "back_y": yEnd,
            "session": session, "undo": undo(e)]
}

// MARK: - #463: Enter, Caps Lock, Space

func leaveRow(_ tag: String, _ text: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags) {
    row(tag) { e in
        clickCanvas(e, VIDEO)
        pressC(e)
        let on = e.canvas.cropMode
        press(e, text, code, flags)
        return ["on": on, "crop": e.canvas.cropMode, "first": responder(e)]
    }
}
leaveRow("K1", ENTER, 76, [.numericPad])
row("K2") { e in
    clickCanvas(e, VIDEO)
    pressC(e)
    let on = e.canvas.cropMode
    press(e, ENTER, 76, [.numericPad, .function])
    let first = e.canvas.cropMode
    if first { pressC(e) }
    pressC(e)
    let again = e.canvas.cropMode
    press(e, "\r", 36, [.function])
    return ["on": on, "keypad_form": first, "again": again, "return_form": e.canvas.cropMode]
}
leaveRow("K3", ESC, 53, CAPS)
leaveRow("K4", "\r", 36, CAPS)
row("K5") { e in
    clickCanvas(e, VIDEO, flags: CAPS)
    let (x0, y0) = (x(e, VIDEO), y(e, VIDEO))
    let held = heldDrag(e, flags: CAPS)
    let moved = x(e, VIDEO) - x0
    press(e, ESC, 53, CAPS)
    let (xEnd, yEnd, session) = (x(e, VIDEO) - x0, y(e, VIDEO) - y0, e.canvas.moving != nil)
    mouse(e, .leftMouseUp, at: held, flags: CAPS)
    spin(0.2)
    return ["moved": moved, "back_x": xEnd, "back_y": yEnd, "session": session, "undo": undo(e)]
}
row("K6") { e in
    clickCanvas(e, VIDEO, flags: CAPS)
    press(e, " ", 49, CAPS)
    let down = playing(e)
    release(e, " ", 49, CAPS)
    return ["down": down, "up": playing(e)]
}
row("K7") { e in
    clickCanvas(e, VIDEO, flags: CAPS)
    var states: [Bool] = []
    press(e, " ", 49, CAPS)
    states.append(playing(e))
    for _ in 0..<3 {
        press(e, " ", 49, CAPS, isRepeat: true)
        states.append(playing(e))
    }
    release(e, " ", 49, CAPS)
    states.append(playing(e))
    return ["states": states]
}
row("K8") { e in
    clickCanvas(e, VIDEO, flags: CAPS)
    e.canvas.setZoom(2)
    spin(0.3)
    let canPan = e.canvas.canPan
    press(e, " ", 49, CAPS)
    let from = CGPoint(x: e.canvas.bounds.midX, y: e.canvas.bounds.midY)
    let to = CGPoint(x: from.x + 50, y: from.y + 30)
    let (x0, y0) = (x(e, VIDEO), y(e, VIDEO))
    mouse(e, .leftMouseDown, at: onCanvas(e, from), flags: CAPS)
    let session = e.canvas.panning != nil
    mouse(e, .leftMouseDragged, at: onCanvas(e, to), flags: CAPS)
    spin(0.1)
    mouse(e, .leftMouseUp, at: onCanvas(e, to), flags: CAPS)
    spin(0.2)
    let pan = e.canvas.panOffset
    release(e, " ", 49, CAPS)
    return ["can_pan": canPan, "session": session, "pan": [pan.x, pan.y],
            "dx": x(e, VIDEO) - x0, "dy": y(e, VIDEO) - y0, "undo": undo(e),
            "playing": playing(e)]
}
row("K9") { e in
    clickCanvas(e, VIDEO)
    press(e, " ", 49, [.option])
    let down = playing(e)
    release(e, " ", 49, [.option])
    return ["down": down, "up": playing(e)]
}
row("K10") { e in
    clickCanvas(e, VIDEO)
    toRoot(e)
    press(e, " ", 49)
    let down = playing(e)
    e.window.makeFirstResponder(e.overlay)
    spin(0.1)
    let first = responder(e)
    release(e, " ", 49)
    return ["down": down, "first": first, "up": playing(e)]
}
row("K11") { e in
    clickCanvas(e, VIDEO)
    press(e, " ", 49, [.function])
    let down = playing(e)
    release(e, " ", 49, [.function])
    return ["down": down, "up": playing(e)]
}

// MARK: - K-5: a press outside the canvas

func overTimeline(_ editor: Editor) -> NSPoint {
    guard let view = timeline(editor) else { return .zero }
    let rect = view.visibleRect
    return view.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil)
}

row("F1") { e in
    clickCanvas(e, VIDEO)
    let before = responder(e)
    sendClick(e, at: overTimeline(e))
    return ["before": before, "first": responder(e)]
}
row("F2") { e in
    clickCanvas(e, VIDEO)
    let before = responder(e)
    sendClick(e, at: onCanvas(e, centre(e, VIDEO)))
    return ["before": before, "first": responder(e)]
}
row("F3") { e in
    clickCanvas(e, VIDEO)
    sendClick(e, at: overTimeline(e))
    let (x0, f0) = (x(e, VIDEO), frame(e))
    press(e, LEFT, 123, ARROW)
    return ["dx": x(e, VIDEO) - x0, "frames": frame(e) - f0, "undo": undo(e)]
}

// MARK: - #474: from any focus

func fromTimeline(_ tag: String, _ text: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags) {
    row(tag) { e in
        clickTimeline(e, VIDEO)
        pressC(e)
        let (on, first) = (e.canvas.cropMode, responder(e))
        press(e, text, code, flags)
        return ["on": on, "first": first, "crop": e.canvas.cropMode]
    }
}
fromTimeline("C1", ESC, 53, [])
fromTimeline("C2", "\r", 36, [])
row("C3") { e in
    clickTimeline(e, VIDEO)
    e.controller.inspector?.selectClipSubTab(.picture)
    spin(0.3)
    let section = sections(e).first { $0.id == "video.crop" }
    let button = section.flatMap { found in
        walk(found).first { $0.toolTip == "Drag the crop edges on the canvas (C)" }
    }
    let down = NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    button?.mouseDown(with: down)
    spin(0.2)
    let (on, first) = (e.canvas.cropMode, responder(e))
    press(e, ESC, 53)
    return ["on": on, "first": first, "crop": e.canvas.cropMode]
}
row("C4") { e in
    clickCanvas(e, VIDEO)
    guard let field = transformField(e) else { return ["failed": "no field"] }
    e.window.makeFirstResponder(field)
    spin(0.2)
    let typing = responder(e)
    press(e, "\r", 36)
    let left = responder(e)
    pressC(e)
    let on = e.canvas.cropMode
    press(e, ESC, 53)
    return ["typing": typing, "first": left, "on": on, "crop": e.canvas.cropMode]
}
row("C5") { e in
    clickTimeline(e, VIDEO)
    pressC(e)
    let on = e.canvas.cropMode
    e.document.selectAction(ACTION)
    e.controller.viewStateDidChange()
    spin(0.2)
    let selected = e.document.selectedAction != nil
    press(e, ESC, 53)
    let (crop, kept) = (e.canvas.cropMode, e.document.selectedAction != nil)
    press(e, ESC, 53)
    return ["on": on, "selected": selected, "crop": crop, "kept": kept,
            "after": e.document.selectedAction != nil]
}
row("C6") { e in
    clickTimeline(e, VIDEO)
    pressC(e)
    let on = e.canvas.cropMode
    press(e, "\r", 36, [.option])
    let option = e.canvas.cropMode
    press(e, ESC, 53, [.command])
    return ["on": on, "first": responder(e), "option_return": option, "command_esc": e.canvas.cropMode]
}
row("C7") { e in
    clickCanvas(e, VIDEO)
    guard let field = transformField(e) else { return ["failed": "no field"] }
    pressC(e)
    let on = e.canvas.cropMode
    e.window.makeFirstResponder(field)
    spin(0.2)
    let typing = e.window.firstResponder is NSText
    press(e, ESC, 53)
    return ["on": on, "typing": typing, "crop": e.canvas.cropMode]
}
row("C8") { e in
    clickTimeline(e, VIDEO)
    let before = responder(e)
    pressC(e)
    return ["before": before, "on": e.canvas.cropMode, "first": responder(e)]
}
fromTimeline("C9", ENTER, 76, [.numericPad])

// MARK: - #475: what the mode opens on

func refusedByC(_ tag: String, _ clipID: UInt32, _ seconds: Double) {
    row(tag, at: seconds) { e in
        clickCanvas(e, clipID)
        let selected = e.document.selection == [clipID]
        let count = counted(e)
        pressC(e)
        let (crop, changes) = (e.canvas.cropMode, count())
        return ["selected": selected, "crop": crop, "changes": changes,
                "answer": e.canvas.setCropMode(true)]
    }
}
refusedByC("S1", SHAPE, AT_SHAPE)
refusedByC("S2", TEXT, AT_TEXT)
refusedByC("S3", GRAPHIC, AT_GRAPHIC)

func refusedByDoubleClick(_ tag: String, _ clipID: UInt32, _ seconds: Double) {
    row(tag, at: seconds) { e in
        let count = counted(e)
        clickCanvas(e, clipID, clicks: 2)
        return ["selected": e.document.selection == [clipID], "crop": e.canvas.cropMode,
                "changes": count()]
    }
}
refusedByDoubleClick("S4", SHAPE, AT_SHAPE)
refusedByDoubleClick("S5", GRAPHIC, AT_GRAPHIC)

row("S6", at: AT_TEXT) { e in
    clickCanvas(e, TEXT, clicks: 2)
    let editing = e.canvas.editingClip == TEXT
    let crop = e.canvas.cropMode
    e.canvas.cancelTextEditing()
    return ["editing": editing, "crop": crop]
}

func opens(_ tag: String, _ clipID: UInt32, _ seconds: Double) {
    row(tag, at: seconds) { e in
        clickCanvas(e, clipID)
        pressC(e)
        let byKey = e.canvas.cropMode
        pressC(e)
        let off = e.canvas.cropMode
        clickCanvas(e, clipID, clicks: 2)
        return ["selected": e.document.selection == [clipID], "by_key": byKey, "off": off,
                "by_double_click": e.canvas.cropMode]
    }
}
opens("S7", VIDEO, 2)
row("S8", at: AT_SHAPE) { e in
    select(e, [VIDEO])
    pressC(e)
    let on = e.canvas.cropMode
    clickCanvas(e, SHAPE)
    return ["on": on, "selection": e.document.selection == [SHAPE], "crop": e.canvas.cropMode]
}
row("S9", at: AT_SHAPE) { e in
    select(e, [VIDEO])
    pressC(e)
    let on = e.canvas.cropMode
    select(e, [SHAPE])
    return ["on": on, "crop": e.canvas.cropMode]
}
row("S10") { e in
    select(e, [VIDEO, SHAPE])
    pressC(e)
    let on = e.canvas.cropMode
    e.controller.setPlayhead(Ticks(AT_SHAPE * Double(SEC)))
    spin(0.4)
    return ["on": on, "front": e.canvas.primaryBox?.id == SHAPE, "crop": e.canvas.cropMode]
}
row("S11") { e in
    clickCanvas(e, VIDEO)
    pressC(e)
    let on = e.canvas.cropMode
    guard let box = e.canvas.box(for: VIDEO) else { return ["failed": "no box"] }
    let edge = e.canvas.canvasToView(box.cropHandlePoint(.left))
    let inward = CGPoint(x: edge.x + 30, y: edge.y)
    mouse(e, .leftMouseDown, at: onCanvas(e, edge))
    mouse(e, .leftMouseDragged, at: onCanvas(e, inward))
    spin(0.1)
    mouse(e, .leftMouseUp, at: onCanvas(e, inward))
    spin(0.3)
    let (cropped, name) = (left(e, VIDEO), undo(e))
    e.document.undoManager?.undo()
    spin(0.3)
    return ["on": on, "left": cropped, "undo": name, "after_undo": left(e, VIDEO),
            "more": undo(e)]
}
opens("S12", MATTE, AT_MATTE)

say("END", ["chain_end": chainEnd])
exit(0)
