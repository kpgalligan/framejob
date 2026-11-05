// Docs-bugs batch a3: #469, #476, #471, #481 and #485 (and batch a5's CI-19 rows, D7, D11 and
// D14–D27) through the app's own sources on real
// .framejob packages the app made and saved (`docs_bugs_a3_proof.py` makes them and scores what
// this prints). Compiled AS main.swift over every file of app/Sources but the app's main.swift,
// -D FRAMEJOB_DEV_TOOLS, against libframejob_core.a, through swift_build.py. It names no symbol the
// base lacks, so the same source builds against the base tree.
//
// Runs: docs_bugs_a3_probe <fixtures.json> <scratch folder> [D1,N3,…]
//
// So what runs is the real EditorViewController, PreviewCanvasView, TimelineView,
// InspectorViewController and PaneSplitView. **No event is posted to the system and nothing takes
// focus:** the app is `.prohibited`, so it cannot activate, and its windows have alpha 0.
//
// **Keys** go in through `EditorWindow.sendEvent`, the real door.
//
// **The mouse does not.** A `.prohibited` app's window is never key and `sendEvent` eats its first
// click, so a press goes by `mouseDown(with:)` to the view `hitTest` picks, the drag and the release
// to that same view. The handlers are real; AppKit's dispatch of a mouse event is not. The divider
// drag is the exception: NSSplitView's own tracking loop runs, fed by `NSApp.postEvent`, which is
// this process's own queue. What a real hand does is TL-19…TL-22 in docs/manual-checks.md.
//
// It prints what it reads and decides nothing; the proof scores.
import AppKit
import ObjectiveC

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

let arguments = CommandLine.arguments
let fixtures = (try! JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: arguments[1])))) as! [String: [String: Any]]
let scratch = URL(fileURLWithPath: arguments[2])
let wanted = Set(arguments.count > 3 ? arguments[3].split(separator: ",").map(String.init) : [])

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

do {
    let selector = #selector(NSResponder.noResponder(for:))
    guard let method = class_getInstanceMethod(NSWindow.self, selector) else {
        print("{\"abort\": \"noResponder(for:) not found\"}")
        exit(2)
    }
    let block: @convention(block) (AnyObject, Selector) -> Void = { _, _ in }
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

func until(_ seconds: Double, _ done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !done(), Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return done()
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
func id(_ fixture: String, _ key: String) -> UInt32 { UInt32(fixtures[fixture]![key] as! Int) }

let SEC = ReelTime.perSecond
let FRAME = SEC / 30
func T(_ seconds: Double) -> Ticks { Ticks(seconds * Double(SEC)) }

// MARK: - The editor

struct Editor {
    let document: ProjectDocument
    let controller: EditorViewController
    let window: NSWindow
    let copy: URL
    var canvas: PreviewCanvasView { controller.previewCanvas! }
    var overlay: CanvasOverlayView { canvas.overlay }
    var inspector: InspectorViewController { controller.inspector! }
}

func open(_ tag: String, _ fixture: String, playhead seconds: Double) -> Editor? {
    let source = URL(fileURLWithPath: fixtures[fixture]!["path"] as! String)
    let copy = scratch.appendingPathComponent("run-\(tag).framejob")
    try? FileManager.default.removeItem(at: copy)
    do {
        try FileManager.default.copyItem(at: source, to: copy)
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
            controller.setPlayhead(T(seconds))
            spin(0.4)
            tries += 1
        } while document.playhead != T(seconds) && tries < 4
        return Editor(document: document, controller: controller, window: window, copy: copy)
    } catch {
        return nil
    }
}

func close(_ editor: Editor) {
    editor.controller.playback.pause()
    editor.document.close()
    spin(0.2)
}

/// One row: its own editor on `fixture` at `seconds`, and what `body` read.
func row(_ name: String, _ fixture: String, at seconds: Double, _ body: (Editor) -> [String: Any]) {
    guard wanted.isEmpty || wanted.contains(name) else { return }
    guard let editor = open(name, fixture, playhead: seconds) else {
        say(name, ["failed": "no editor"])
        return
    }
    say(name, body(editor))
    close(editor)
}

func save(_ editor: Editor) {
    var finished = false
    editor.document.save(
        to: editor.copy, ofType: ProjectDocument.projectTypeIdentifier, for: .saveOperation
    ) { _ in finished = true }
    _ = until(5) { finished }
}

func undoName(_ editor: Editor) -> String {
    let manager = editor.document.undoManager
    return manager?.canUndo == true ? manager?.undoActionName ?? "" : ""
}

func undo(_ editor: Editor) {
    editor.document.undoManager?.undo()
    spin(0.3)
}

func clip(_ editor: Editor, _ id: UInt32) -> ClipSnapshot? {
    editor.document.editedProject.snapshot.clip(id)
}

func select(_ editor: Editor, _ clips: Set<UInt32>) {
    editor.document.selection = clips
    editor.controller.viewStateDidChange()
    spin(0.2)
}

func goTo(_ editor: Editor, _ time: Ticks) {
    editor.controller.setPlayhead(time)
    spin(0.3)
}

/// `clip_state`'s video at `time`, one number.
func stateAt(_ editor: Editor, _ id: UInt32, _ time: Ticks, _ key: String) -> Double {
    let video = editor.document.editedProject.clipState(id, at: time)?["video"] as? [String: Any]
    return (video?[key] as? NSNumber)?.doubleValue ?? .nan
}

/// A JSON value: NaN has no spelling there.
func J(_ value: Double?) -> Any {
    guard let value, value.isFinite else { return NSNull() }
    return value
}

func boxRect(_ editor: Editor, _ id: UInt32) -> [Double] {
    guard let box = editor.canvas.box(for: id) else { return [] }
    return [box.rect.minX, box.rect.minY, box.rect.width, box.rect.height].map { Double($0) }
}

/// What the three frames say: `state_x` and `state_y` at frame 0, frame 1 and 4 s.
func frames(_ editor: Editor, _ id: UInt32) -> [String: Any] {
    let times = [Ticks(0), FRAME, T(4)]
    return [
        "xs": times.map { J(stateAt(editor, id, $0, "x")) },
        "ys": times.map { J(stateAt(editor, id, $0, "y")) },
    ]
}

/// A clip's first action's end `video`, as stored.
func endVideo(_ editor: Editor, _ id: UInt32) -> VideoPatch? { clip(editor, id)?.actions.first?.end.video }

// MARK: - Keys

let ARROW: NSEvent.ModifierFlags = [.numericPad, .function]
func scalar(_ value: Int) -> String { String(Character(UnicodeScalar(UInt32(value))!)) }

func press(_ editor: Editor, _ text: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
    let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: editor.window.windowNumber, context: nil, characters: text,
        charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    editor.window.sendEvent(event)
    spin(0.15)
}

// MARK: - The mouse

var mouseTarget: NSView?

func mouse(_ editor: Editor, _ type: NSEvent.EventType, at location: NSPoint) {
    let event = NSEvent.mouseEvent(
        with: type, location: location, modifierFlags: [], timestamp: 0,
        windowNumber: editor.window.windowNumber, context: nil, eventNumber: 0,
        clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
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

func onCanvas(_ editor: Editor, _ point: CGPoint) -> NSPoint { editor.overlay.convert(point, to: nil) }

/// A canvas point in the overlay's view space.
func view(_ editor: Editor, _ point: CGPoint) -> CGPoint { editor.canvas.canvasToView(point) }

func centre(_ editor: Editor, _ id: UInt32) -> CGPoint? {
    guard let box = editor.canvas.box(for: id) else { return nil }
    return view(editor, CGPoint(x: box.rect.midX, y: box.rect.midY))
}

func clickAt(_ editor: Editor, view point: CGPoint) {
    let at = onCanvas(editor, point)
    mouse(editor, .leftMouseDown, at: at)
    mouse(editor, .leftMouseUp, at: at)
    spin(0.25)
}

/// Press at `from`, eight steps to `to`, release.
func drag(_ editor: Editor, from: CGPoint, to: CGPoint) {
    mouse(editor, .leftMouseDown, at: onCanvas(editor, from))
    for step in 1...8 {
        let f = CGFloat(step) / 8
        let p = CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)
        mouse(editor, .leftMouseDragged, at: onCanvas(editor, p))
    }
    mouse(editor, .leftMouseUp, at: onCanvas(editor, to))
    spin(0.4)
}

/// `from` moved by a distance in canvas pixels.
func offset(_ editor: Editor, _ from: CGPoint, dx: CGFloat, dy: CGFloat) -> CGPoint {
    let a = view(editor, .zero)
    let b = view(editor, CGPoint(x: dx, y: dy))
    return CGPoint(x: from.x + b.x - a.x, y: from.y + b.y - a.y)
}

func timelineContent(_ editor: Editor) -> TimelineContentView? {
    walk(editor.window.contentView!).compactMap { $0 as? TimelineContentView }.first
}

/// Where `id` answers `.clip` on the timeline, with room to its right.
func timelinePoint(_ editor: Editor, _ id: UInt32) -> CGPoint? {
    guard let content = timelineContent(editor) else { return nil }
    let bounds = content.bounds
    var y = bounds.minY
    while y < bounds.maxY {
        var x = bounds.minX
        while x < bounds.maxX {
            if content.hit(at: CGPoint(x: x, y: y)) == .clip(id) {
                let point = CGPoint(x: x + 30, y: y + 12)
                if content.hit(at: point) == .clip(id) { return point }
            }
            x += 8
        }
        y += 4
    }
    return nil
}

func clickTimeline(_ editor: Editor, _ id: UInt32) {
    guard let content = timelineContent(editor), let point = timelinePoint(editor, id) else { return }
    let at = content.convert(point, to: nil)
    mouse(editor, .leftMouseDown, at: at)
    mouse(editor, .leftMouseUp, at: at)
    spin(0.3)
}

// MARK: - #469, CI-17

let CAM = id("cam", "camera")
let SCREEN = id("cam", "screen")
let CAM_DX: CGFloat = -1124
let CAM_DY: CGFloat = -651

/// The camera dragged to the top left; what the box, the state and the undo step read.
func dragCamera(_ e: Editor) -> [String: Any] {
    guard let from = centre(e, CAM) else { return ["failed": "no box for the camera"] }
    let before = boxRect(e, CAM)
    drag(e, from: from, to: offset(e, from, dx: CAM_DX, dy: CAM_DY))
    var out = frames(e, CAM)
    out["before"] = before
    out["after"] = boxRect(e, CAM)
    out["undo"] = undoName(e)
    out["selected"] = J(e.document.selectedAction.map { Double($0) })
    out["base_x"] = J(clip(e, CAM)?.videoProps.x)
    return out
}

row("D1", "cam", at: 4) { e in
    guard let from = centre(e, CAM) else { return ["failed": "no box"] }
    clickAt(e, view: from)
    var out = dragCamera(e)
    let frame0 = { () -> [Double] in goTo(e, 0); return boxRect(e, CAM) }()
    let frame1 = { () -> [Double] in goTo(e, FRAME); return boxRect(e, CAM) }()
    out["box_frame0"] = frame0
    out["box_frame1"] = frame1
    goTo(e, T(4))
    save(e)
    undo(e)
    out["undone"] = frames(e, CAM)
    out["undone_end_x"] = J(endVideo(e, CAM)?.x)
    out["more_undo"] = undoName(e)
    return out
}
row("D2", "cam", at: 4) { e in
    guard let from = centre(e, CAM) else { return ["failed": "no box"] }
    clickAt(e, view: from)
    guard let box = e.canvas.box(for: CAM) else { return ["failed": "no box"] }
    let before = boxRect(e, CAM)
    let corner = view(e, box.handlePoint(.topLeft))
    drag(e, from: corner, to: offset(e, corner, dx: -200, dy: -112))
    var out = frames(e, CAM)
    out["before"] = before
    out["after"] = boxRect(e, CAM)
    out["scales"] = [Ticks(0), FRAME, T(4)].map { J(stateAt(e, CAM, $0, "scale")) }
    out["undo"] = undoName(e)
    return out
}
row("D3", "cam", at: 4) { e in
    guard let from = centre(e, CAM) else { return ["failed": "no box"] }
    clickAt(e, view: from)
    e.window.makeFirstResponder(e.overlay)
    press(e, scalar(NSLeftArrowFunctionKey), 123, ARROW)
    var out = frames(e, CAM)
    out["undo"] = undoName(e)
    return out
}
row("D4", "cam", at: 4) { e in
    clickTimeline(e, CAM)
    return dragCamera(e)
}
row("D5", "cam", at: 0) { e in
    guard let from = centre(e, CAM) else { return ["failed": "no box"] }
    clickAt(e, view: from)
    let held = e.document.selectedAction != nil
    var out = dragCamera(e)
    out["held"] = held
    return out
}
row("D6", "cam", at: 0) { e in
    guard let from = centre(e, CAM) else { return ["failed": "no box"] }
    clickAt(e, view: from)
    let held = e.document.selectedAction != nil
    e.window.makeFirstResponder(e.overlay)
    press(e, "\u{1b}", 53)
    let cleared = e.document.selectedAction == nil
    var out = dragCamera(e)
    out["held"] = held
    out["cleared"] = cleared
    return out
}

// MARK: - #469's second half, CI-19 (batch a5)

func encoded<T: Encodable>(_ value: T?) -> Any {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let value, let data = try? encoder.encode(value) else { return NSNull() }
    return String(decoding: data, as: UTF8.self)
}

/// What a refusal leaves alone: the clip's base and every action's end as stored, in lane order.
func stored(_ e: Editor, _ id: UInt32) -> [String: Any] {
    guard let c = clip(e, id) else { return [:] }
    return [
        "video": encoded(c.videoProps), "text": encoded(c.text), "shape": encoded(c.shape),
        "ends": ActionBands.ordered(c).map { encoded($0.end) },
    ]
}

func strip(_ e: Editor) -> Any { e.inspector.refusalStrip.text ?? NSNull() }

/// `act` on `id`, after a click on it unless `click` is false: the stored state before and after,
/// the box, the strip at the inspector's foot, the undo step and the selection.
func gesture(_ e: Editor, _ id: UInt32, click: Bool = true, _ act: () -> [String: Any] = { [:] })
    -> [String: Any]
{
    if click, let from = centre(e, id) { clickAt(e, view: from) }
    let before = stored(e, id)
    let box = boxRect(e, id)
    let selectedBefore = J(e.document.selectedAction.map { Double($0) })
    var out = act()
    out["before"] = before
    out["after"] = stored(e, id)
    out["box_before"] = box
    out["box_after"] = boxRect(e, id)
    out["strip"] = strip(e)
    out["undo"] = undoName(e)
    out["selection"] = e.document.selection.sorted().map { Int($0) }
    out["selected_before"] = selectedBefore
    out["selected"] = J(e.document.selectedAction.map { Double($0) })
    return out
}

func dragBy(_ e: Editor, _ id: UInt32, dx: CGFloat, dy: CGFloat = 0) -> [String: Any] {
    guard let from = centre(e, id) else { return ["no_box": true] }
    drag(e, from: from, to: offset(e, from, dx: dx, dy: dy))
    return [:]
}

/// A drag from a grip: through `hitTest` when the grip is inside the overlay's bounds, as `drag`
/// does; otherwise straight to the overlay's own `mouseDown(with:)`, `mouseDragged(with:)` and
/// `mouseUp(with:)`, because a grip off the pane (a box zoomed past the canvas) is one `hitTest`
/// answers with another view, though the canvas's own `hit(at:)` takes it. The door is printed.
func gripDrag(_ e: Editor, from grip: CGPoint, to end: CGPoint) -> [String: Any] {
    let hit = e.canvas.hit(at: grip)
    guard !e.overlay.bounds.contains(grip) else {
        drag(e, from: grip, to: end)
        return ["hit": "\(hit)", "door": "hitTest"]
    }
    mouseTarget = e.overlay
    func send(_ type: NSEvent.EventType, _ point: CGPoint) {
        let event = NSEvent.mouseEvent(
            with: type, location: onCanvas(e, point), modifierFlags: [], timestamp: 0,
            windowNumber: e.window.windowNumber, context: nil, eventNumber: 0,
            clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        switch type {
        case .leftMouseDown: e.overlay.mouseDown(with: event)
        case .leftMouseDragged: e.overlay.mouseDragged(with: event)
        default: e.overlay.mouseUp(with: event)
        }
        spin(0.05)
    }
    send(.leftMouseDown, grip)
    for step in 1...8 {
        let f = CGFloat(step) / 8
        send(.leftMouseDragged, CGPoint(x: grip.x + (end.x - grip.x) * f, y: grip.y + (end.y - grip.y) * f))
    }
    send(.leftMouseUp, end)
    spin(0.4)
    return ["hit": "\(hit)", "door": "overlay"]
}

func handleDrag(_ e: Editor, _ id: UInt32, _ handle: CanvasHandle, dx: CGFloat, dy: CGFloat)
    -> [String: Any]
{
    guard let box = e.canvas.box(for: id) else { return ["no_box": true] }
    let grip = view(e, box.handlePoint(handle))
    return gripDrag(e, from: grip, to: offset(e, grip, dx: dx, dy: dy))
}

func rotateGrip(_ e: Editor, _ id: UInt32) -> [String: Any] {
    guard let box = e.canvas.box(for: id) else { return ["no_box": true] }
    let grip = view(
        e, box.rotationHandlePoint(offset: e.canvas.canvasDistance(PreviewCanvasView.rotationOffset)))
    return gripDrag(e, from: grip, to: offset(e, grip, dx: 160, dy: 60))
}

/// A plain drag of `id` by 400 canvas pixels left: the base and the clip's first action's end.
func dragLeft(_ e: Editor, _ id: UInt32) -> [String: Any] {
    guard let from = centre(e, id) else { return ["failed": "no box"] }
    clickAt(e, view: from)
    let before = boxRect(e, id)
    let endBefore = endVideo(e, id)?.x
    let baseBefore = clip(e, id)?.videoProps.x
    drag(e, from: from, to: offset(e, from, dx: -400, dy: 0))
    return [
        "before": before, "after": boxRect(e, id), "base_before": J(baseBefore),
        "base": J(clip(e, id)?.videoProps.x), "end_before": J(endBefore),
        "end": J(endVideo(e, id)?.x), "undo": undoName(e),
        "selected": J(e.document.selectedAction.map { Double($0) }),
    ]
}

let ZOOM = id("zoom", "clip")
row("D7", "zoom", at: 5) { e in gesture(e, ZOOM) { dragBy(e, ZOOM, dx: -400) } }
row("D8", "zoom", at: 1) { e in dragLeft(e, ZOOM) }
row("D9", "plain", at: 2) { e in dragLeft(e, id("plain", "clip")) }
row("D10", "cam", at: 4) { e in
    guard let from = centre(e, CAM) else { return ["failed": "no box"] }
    clickAt(e, view: from)
    guard let box = e.canvas.box(for: CAM) else { return ["failed": "no box"] }
    let grip = view(
        e, box.rotationHandlePoint(offset: e.canvas.canvasDistance(PreviewCanvasView.rotationOffset)))
    drag(e, from: grip, to: offset(e, grip, dx: 160, dy: 60))
    return [
        "base": J(clip(e, CAM)?.videoProps.rotation),
        "states": [Ticks(0), FRAME, T(4)].map { J(stateAt(e, CAM, $0, "rotation")) },
        "end_rotation": J(endVideo(e, CAM)?.rotation),
        "undo": undoName(e),
    ]
}
row("D11", "late", at: 4) { e in
    gesture(e, id("late", "clip")) { dragBy(e, id("late", "clip"), dx: -400) }
}
row("D12", "cam", at: 4) { e in
    select(e, [CAM, SCREEN])
    var out = dragCamera(e)
    out["end_x"] = J(endVideo(e, CAM)?.x)
    return out
}
row("D13", "shapecut", at: 4) { e in
    let shape = id("shapecut", "clip")
    guard let from = centre(e, shape) else { return ["failed": "no box"] }
    clickAt(e, view: from)
    guard let box = e.canvas.box(for: shape) else { return ["failed": "no box"] }
    let widthBefore = clip(e, shape)?.shape?.width
    let endScale = endVideo(e, shape)?.scale
    let endX = endVideo(e, shape)?.x
    let corner = view(e, box.handlePoint(.bottomRight))
    drag(e, from: corner, to: offset(e, corner, dx: 120, dy: 80))
    return [
        "width_before": J(widthBefore), "width": J(clip(e, shape)?.shape?.width),
        "end_scale_before": J(endScale), "end_scale": J(endVideo(e, shape)?.scale),
        "end_x_before": J(endX), "end_x": J(endVideo(e, shape)?.x), "undo": undoName(e),
    ]
}

// MARK: - CI-19's rows (batch a5)

row("D14", "zoom", at: 5) { e in
    gesture(e, ZOOM) { handleDrag(e, ZOOM, .topLeft, dx: -200, dy: -112) }
}
row("D15", "zoom", at: 5) { e in
    gesture(e, ZOOM) {
        e.window.makeFirstResponder(e.overlay)
        press(e, scalar(NSLeftArrowFunctionKey), 123, ARROW)
        return [:]
    }
}
row("D16", "late", at: 4) { e in
    let late = id("late", "clip")
    return gesture(e, late) {
        e.window.makeFirstResponder(e.overlay)
        press(e, "c", 8)
        let crop = e.canvas.cropMode
        guard let box = e.canvas.box(for: late) else { return ["crop": crop, "no_box": true] }
        let grip = view(e, box.cropHandlePoint(.topLeft))
        let hit = e.canvas.hit(at: grip)
        drag(e, from: grip, to: offset(e, grip, dx: 120, dy: 60))
        return ["crop": crop, "hit": "\(hit)"]
    }
}
row("D17", "zoom", at: 5) { e in gesture(e, ZOOM) { rotateGrip(e, ZOOM) } }
row("D18", "zoom", at: 5) { e in
    gesture(e, ZOOM, click: false) {
        guard let from = centre(e, ZOOM) else { return ["no_box": true] }
        clickAt(e, view: from)
        return [:]
    }
}
row("D19", "twozoom", at: 5) { e in
    gesture(e, id("twozoom", "clip")) { dragBy(e, id("twozoom", "clip"), dx: -400) }
}
let CAMZOOM = id("camzoom", "camera")
row("D20", "camzoom", at: 5) { e in gesture(e, CAMZOOM) { dragBy(e, CAMZOOM, dx: -400) } }
row("D21", "camzoom", at: 1) { e in gesture(e, CAMZOOM) { dragBy(e, CAMZOOM, dx: -400) } }
row("D22", "zoom", at: 5) { e in
    select(e, [ZOOM])
    guard let action = clip(e, ZOOM)?.actions.first?.id else { return ["failed": "no action"] }
    e.controller.selectAction(action)
    spin(0.3)
    return gesture(e, ZOOM, click: false) { dragBy(e, ZOOM, dx: -400) }
}
row("D23", "zoom", at: 2.5) { e in
    gesture(e, ZOOM) {
        let held = e.document.selectedAction != nil
        e.window.makeFirstResponder(e.overlay)
        press(e, "\u{1b}", 53)
        let cleared = e.document.selectedAction == nil
        var out = dragBy(e, ZOOM, dx: -400)
        out["held"] = held
        out["cleared"] = cleared
        return out
    }
}
let SHAPEZOOM = id("shapezoom", "clip")
row("D24", "shapezoom", at: 5) { e in
    gesture(e, SHAPEZOOM) { handleDrag(e, SHAPEZOOM, .bottomRight, dx: 120, dy: 80) }
}
let TEXTZOOM = id("textzoom", "clip")
row("D25", "textzoom", at: 5) { e in
    gesture(e, TEXTZOOM) { handleDrag(e, TEXTZOOM, .right, dx: 150, dy: 0) }
}
row("D26", "textzoom", at: 5) { e in
    gesture(e, TEXTZOOM) { handleDrag(e, TEXTZOOM, .bottomRight, dx: 120, dy: 60) }
}
row("D27", "pairzoom", at: 5) { e in
    let a = id("pairzoom", "a")
    let b = id("pairzoom", "b")
    select(e, [a, b])
    let otherBefore = stored(e, b)
    var out = gesture(e, a, click: false) {
        guard let from = centre(e, a) else { return ["no_box": true] }
        let hit = e.canvas.hit(at: from)
        e.canvas.beginGesture(at: from, flags: .shift, clicks: 1)
        let pressed = e.document.selection.sorted().map { Int($0) }
        for step in 1...8 {
            let to = offset(e, from, dx: 20 * CGFloat(step), dy: 0)
            e.canvas.continueGesture(at: to, flags: [])
            spin(0.05)
        }
        e.canvas.endGesture(at: offset(e, from, dx: 160, dy: 0), flags: [])
        spin(0.4)
        return ["hit": "\(hit)", "pressed": pressed]
    }
    out["other_before"] = otherBefore
    out["other_after"] = stored(e, b)
    return out
}

// MARK: - #476, the nest's box

let NEST = id("nest", "nest")
let BEHIND = id("nest", "behind")
/// The picture's centre: the nest sits at x 300, y 100 at half size.
func nestCentre(_ e: Editor) -> CGPoint { view(e, CGPoint(x: 960 + 300, y: 540 + 100)) }

row("N1", "nest", at: 2) { e in
    clickAt(e, view: nestCentre(e))
    return ["selection": e.document.selection.sorted().map { Int($0) }]
}
row("N2", "nest", at: 6.5) { e in
    clickAt(e, view: nestCentre(e))
    return ["selection": e.document.selection.sorted().map { Int($0) }]
}
row("N3", "nest", at: 2) { e in
    clickTimeline(e, NEST)
    guard let box = e.canvas.primaryBox else { return ["failed": "no primary box"] }
    let handle = e.canvas.hit(at: view(e, box.handlePoint(.topLeft)))
    return [
        "primary": Int(box.id), "rect": boxRect(e, box.id),
        "handle": handle == .handle(NEST, .topLeft),
    ]
}
row("N4", "nest", at: 2) { e in
    clickTimeline(e, NEST)
    let from = nestCentre(e)
    let baseBefore = clip(e, NEST)?.videoProps.x
    drag(e, from: from, to: offset(e, from, dx: -100, dy: -50))
    return [
        "selection": e.document.selection.sorted().map { Int($0) },
        "before": J(baseBefore), "nest_x": J(clip(e, NEST)?.videoProps.x),
        "nest_y": J(clip(e, NEST)?.videoProps.y), "behind_x": J(clip(e, BEHIND)?.videoProps.x),
        "undo": undoName(e),
    ]
}
row("N5", "nest", at: 2) { e in
    clickTimeline(e, NEST)
    guard let box = e.canvas.primaryBox else { return ["failed": "no primary box"] }
    let corner = view(e, box.handlePoint(.topLeft))
    drag(e, from: corner, to: offset(e, corner, dx: -120, dy: -68))
    let scale = clip(e, NEST)?.videoProps.scale
    let scaled = undoName(e)
    guard let next = e.canvas.primaryBox else { return ["failed": "no box after the scale"] }
    let grip = view(
        e, next.rotationHandlePoint(offset: e.canvas.canvasDistance(PreviewCanvasView.rotationOffset)))
    drag(e, from: grip, to: offset(e, grip, dx: 200, dy: 80))
    return [
        "scale": J(scale), "scaled": scaled, "rotation": J(clip(e, NEST)?.videoProps.rotation),
        "rotated": undoName(e),
    ]
}
row("N6", "nest", at: 2) { e in
    clickTimeline(e, NEST)
    e.window.makeFirstResponder(e.overlay)
    press(e, "z", 6)
    let armed = e.controller.canvasRegion != nil
    let from = view(e, CGPoint(x: 900, y: 460))
    drag(e, from: from, to: view(e, CGPoint(x: 1300, y: 690)))
    let end = endVideo(e, NEST)
    return [
        "armed": armed, "actions": clip(e, NEST)?.actions.count ?? -1, "undo": undoName(e),
        "end_x": J(end?.x), "end_y": J(end?.y), "end_scale": J(end?.scale),
    ]
}
row("N7", "nestact", at: 3) { e in
    let nest = id("nestact", "nest")
    select(e, [nest])
    let box = e.canvas.primaryBox
    return ["primary": box.map { Int($0.id) } ?? -1, "mid_x": J(box.map { Double($0.rect.midX) }),
            "base_x": J(clip(e, nest)?.videoProps.x)]
}
row("N8", "nest", at: 2) { e in
    clickTimeline(e, NEST)
    e.window.makeFirstResponder(e.overlay)
    press(e, "c", 8)
    return ["crop": e.canvas.cropMode, "selection": e.document.selection.sorted().map { Int($0) }]
}
row("N9", "nest", at: 2) { e in
    clickTimeline(e, NEST)
    e.controller.placeObscureRegion(nil)
    spin(0.1)
    return ["armed": e.controller.canvasRegion != nil,
            "selection": e.document.selection.sorted().map { Int($0) }]
}
row("N10", "nest", at: 2) { e in
    let off = view(e, CGPoint(x: 200, y: 200))
    let found = e.canvas.hit(at: off)
    return ["rect": boxRect(e, BEHIND), "hit": found == .body(BEHIND)]
}
row("N11", "nestmotion", at: 0.25) { e in
    let nest = id("nestmotion", "nest")
    select(e, [nest])
    let layer = e.document.editedProject.recipe(at: e.document.playhead)?.layers
        .first { $0.clipRect != nil }
    let rest = e.document.editedProject.clipState(nest, at: e.document.playhead)
    let video = rest?["video"] as? [String: Any]
    let box = e.canvas.primaryBox
    return [
        "primary": box.map { Int($0.id) } ?? -1, "mid_x": J(box.map { Double($0.rect.midX) }),
        "mid_y": J(box.map { Double($0.rect.midY) }), "width": J(box.map { Double($0.rect.width) }),
        "clip_rect": layer?.clipRect.map { [J($0.x), J($0.y), J($0.w)] } ?? [],
        "rest_x": J((video?["x"] as? NSNumber)?.doubleValue),
    ]
}
let CORNER_NEST = id("corner", "nest")
let CORNER_BEHIND = id("corner", "behind")
row("N12", "corner", at: 2) { e in
    clickAt(e, view: view(e, CGPoint(x: 1584, y: 891)))
    return ["selection": e.document.selection.sorted().map { Int($0) },
            "rect": e.canvas.primaryBox.map { _ in boxRect(e, CORNER_NEST) } ?? []]
}
row("N13", "corner", at: 2) { e in
    clickAt(e, view: view(e, CGPoint(x: 960, y: 540)))
    return ["selection": e.document.selection.sorted().map { Int($0) }]
}

// MARK: - #471, the first click

let FIRST = id("pick", "first")
let SECOND = id("pick", "second")
func tab(_ e: Editor) -> String { e.inspector.tab.title }

row("P1", "pick", at: 2) { e in
    e.controller.showAssistant(nil)
    spin(0.3)
    let start = tab(e)
    clickTimeline(e, FIRST)
    return ["start": start, "tab": tab(e), "selection": e.document.selection.sorted().map { Int($0) }]
}
row("P2", "pick", at: 2) { e in
    e.controller.showAssistant(nil)
    spin(0.3)
    let start = tab(e)
    if let point = centre(e, FIRST) { clickAt(e, view: point) }
    return ["start": start, "tab": tab(e), "selection": e.document.selection.sorted().map { Int($0) }]
}

/// The Transcript rows: the project and the click are real, the words are preloaded (nothing
/// recognised), as transcript_tab_probe.swift does. A read of the silent file may be in flight and
/// answer "no words" over a preload, so the words go in once the source has settled, and again if
/// a late answer dropped them.
func transcript(_ name: String, _ body: (Editor, TranscriptPane) -> [String: Any]) {
    row(name, "words", at: 1) { e in
        e.controller.showTranscript(nil)
        spin(0.3)
        guard let pane = TranscriptPane.pane(in: e.inspector) else { return ["failed": "no pane"] }
        let words = (0..<300).map { index in
            TimelineTranscript.SourceWord(
                text: "word\(index)", source: T(Double(index) * 0.19),
                sourceEnd: T(Double(index) * 0.19 + 0.15), speaker: nil)
        }
        let media = id("words", "media")
        let heard = TimelineTranscript.MediaWords(
            media: media, engine: .apple, language: "en-US", fillersReported: false, words: words)
        for _ in 1...3 {
            _ = until(8) { pane.source.settled }
            pane.source.preload([media: heard], pauses: [media: []])
            spin(0.5)
            if !pane.source.model.tokens.isEmpty { break }
        }
        e.controller.fitTimeline(nil)
        spin(0.4)
        return body(e, pane)
    }
}
func firstToken(_ pane: TranscriptPane, _ clip: UInt32) -> Int {
    pane.source.model.tokens.firstIndex { $0.word.clip == clip } ?? -1
}
let WORDS_A = id("words", "clip_a")
let WORDS_B = id("words", "clip_b")
transcript("P3") { e, pane in
    clickTimeline(e, WORDS_A)
    pane.transcriptView.scrollToToken(150)
    spin(0.2)
    clickTimeline(e, WORDS_B)
    return ["tab": tab(e), "top": pane.transcriptView.topVisibleToken() ?? -1,
            "b_first": firstToken(pane, WORDS_B)]
}
transcript("P4") { e, pane in
    pane.transcriptView.scrollToToken(150)
    spin(0.2)
    clickTimeline(e, WORDS_B)
    return ["tab": tab(e), "top": pane.transcriptView.topVisibleToken() ?? -1,
            "b_first": firstToken(pane, WORDS_B)]
}
row("P5", "pick", at: 2) { e in
    e.controller.fitTimeline(nil)
    spin(0.4)
    e.controller.showAssistant(nil)
    spin(0.3)
    guard let content = timelineContent(e), let onClip = timelinePoint(e, SECOND) else {
        return ["failed": "no timeline point"]
    }
    // Empty space on screen, straight below the clip.
    var y = onClip.y
    var start: CGPoint?
    while y < content.visibleRect.maxY - 2, start == nil {
        let point = CGPoint(x: onClip.x, y: y)
        switch content.hit(at: point) {
        case .lane, .outside: start = point
        default: y += 4
        }
    }
    guard let start else { return ["failed": "no empty space"] }
    let begin = tab(e)
    mouse(e, .leftMouseDown, at: content.convert(start, to: nil))
    var seen: [[Int]] = []
    for step in 0..<4 {
        let point = CGPoint(x: onClip.x + CGFloat(step) * 6, y: onClip.y)
        mouse(e, .leftMouseDragged, at: content.convert(point, to: nil))
        spin(0.05)
        seen.append(e.document.selection.sorted().map { Int($0) })
    }
    mouse(e, .leftMouseUp, at: content.convert(onClip, to: nil))
    spin(0.2)
    return ["start": begin, "tab": tab(e), "ticks": seen]
}
row("P6", "pick", at: 2) { e in
    clickTimeline(e, FIRST)
    e.inspector.select(.media)
    spin(0.3)
    let start = tab(e)
    clickTimeline(e, FIRST)
    return ["start": start, "tab": tab(e)]
}

// MARK: - #481, the marks

let MARKS_SHAPE = id("marks", "shape")
let MARKS_VIDEO = id("marks", "video")

func sections(_ e: Editor) -> [InspectorSection] {
    walk(e.window.contentView!).compactMap { $0 as? InspectorSection }
}

func revealAll(_ e: Editor) {
    for section in sections(e) { section.reveal() }
    spin(0.3)
}

func rowLabel(_ gutter: InspectorMarkGutter) -> String {
    guard let row = gutter.superview else { return "" }
    return walk(row).compactMap { ($0 as? InspectorRowLabel)?.stringValue }.first ?? ""
}

/// Whether a row has anything to press: the rows that only say something have no control.
func hasControl(_ gutter: InspectorMarkGutter) -> Bool {
    guard let row = gutter.superview else { return false }
    return walk(row).contains {
        $0 is OptionButtonControl || $0 is OptionPopupControl || $0 is OptionCheckboxControl
            || $0 is OptionFieldControl || $0 is OptionSwatchControl
    }
}

/// Every row with a control on the sections showing: `"label: mark"`.
func marks(_ e: Editor) -> [String] {
    sections(e).flatMap { section in
        walk(section).compactMap { $0 as? InspectorMarkGutter }.filter(hasControl).map {
            "\(section.title)/\(rowLabel($0)): \($0.mark)"
        }
    }
}

/// The shape selected with a new action on it, on the Shape sub-tab.
func shapeWithAction(_ e: Editor) {
    clickTimeline(e, MARKS_SHAPE)
    e.inspector.select(.clip)
    e.controller.addActionAtPlayhead(nil)
    spin(0.4)
    e.inspector.selectClipSubTab(.shape)
    spin(0.4)
    revealAll(e)
}

row("M1", "marks", at: 6) { e in
    shapeWithAction(e)
    let off = marks(e)
    e.document.applyEdit(
        "Gradient", .setShape(clips: [MARKS_SHAPE], patch: ShapePatch(gradient: .some(Gradient()))))
    spin(0.5)
    revealAll(e)
    let on = marks(e)
    return ["selected": e.document.selectedAction != nil, "off": off, "on": on]
}
row("M2", "marks", at: 6) { e in
    shapeWithAction(e)
    let shown = sections(e)
    return [
        "sections": shown.map { $0.title },
        "all": shown.map { $0.marks.allNotAnimatable },
        "notes": shown.map { section in
            walk(section).compactMap { $0 as? InspectorNoteLabel }.contains {
                !$0.isHidden && $0.stringValue.hasPrefix("Actions don't animate this")
            }
        },
        "shape_button": shown.first { $0.title == "Shape" }?.header.buttonTitle ?? "",
    ]
}

func videoPicture(_ e: Editor) {
    clickTimeline(e, MARKS_VIDEO)
    e.inspector.select(.clip)
    e.inspector.selectClipSubTab(.picture)
    spin(0.4)
    revealAll(e)
}

let LIST_BUTTONS = [
    "add_filter": "Append a half-strength", "add_region": "Add a 480",
    "place": "Drag a rectangle on the canvas", "remove_filter": "Take this filter off",
    "remove_region": "Take this region off",
]

func button(_ e: Editor, _ tip: String) -> OptionButtonControl? {
    walk(e.inspector.view).compactMap { $0 as? OptionButtonControl }
        .first { ($0.toolTip ?? "").hasPrefix(tip) }
}

/// Each list button's row: 1 when a clip tag shows there, 0 when none does.
func tags(_ e: Editor) -> [String: Int] {
    LIST_BUTTONS.mapValues { tip in
        let siblings = button(e, tip)?.superview?.subviews ?? []
        return siblings.contains { $0 is InspectorClipTag && !$0.isHidden } ? 1 : 0
    }
}

row("M3", "marks", at: 2.5) { e in
    videoPicture(e)
    let clipped = walk(e.inspector.view).compactMap { $0 as? InspectorClipTag }.filter { tag in
        !tag.isHidden && tag.frame.maxX > (tag.superview?.bounds.maxX ?? 0) + 0.5
    }
    return ["selected": e.document.selectedAction != nil, "tags": tags(e), "clipped": clipped.count]
}
row("M4", "marks", at: 1) { e in
    videoPicture(e)
    let video = (e.document.selectedAction == nil, tags(e), marks(e))
    goTo(e, T(6))
    clickTimeline(e, MARKS_SHAPE)
    e.inspector.selectClipSubTab(.shape)
    spin(0.4)
    revealAll(e)
    return [
        "none_selected": video.0 && e.document.selectedAction == nil, "tags": video.1,
        "video_marks": video.2, "shape_marks": marks(e),
    ]
}
row("M5", "marks", at: 2.5) { e in
    videoPicture(e)
    let filters = sections(e).first { $0.title == "Filters" }
    let amount = filters.map { walk($0).compactMap { $0 as? InspectorMarkGutter } }?
        .first { rowLabel($0) == "Amount" }
    return [
        "selected": e.document.selectedAction != nil, "animates": amount?.animates ?? false,
        "mark": amount.map { "\($0.mark)" } ?? "", "section_all": filters?.marks.allNotAnimatable ?? true,
    ]
}

// MARK: - #485, the divider

let collapsedKey = EditorViewController.inspectorCollapsedKey

func upperSplit(_ e: Editor) -> PaneSplitView? {
    walk(e.window.contentView!).compactMap { $0 as? PaneSplitView }.first { $0.isVertical }
}

func splitFacts(_ e: Editor) -> [String: Any] {
    let inspector = e.controller.inspectorContainer
    let item = NSMenuItem(
        title: "?", action: #selector(EditorViewController.toggleInspector(_:)), keyEquivalent: "")
    _ = e.controller.validateUserInterfaceItem(item)
    return [
        "width": Double(inspector.frame.width), "hidden": inspector.isHidden, "menu": item.title,
        "key": UserDefaults.standard.bool(forKey: collapsedKey),
    ]
}

func dragDivider(_ e: Editor, to x: CGFloat) {
    guard let split = upperSplit(e) else { return }
    let canvas = split.arrangedSubviews[0]
    let startX = e.controller.inspectorContainer.isHidden
        ? split.bounds.width - split.dividerThickness / 2
        : canvas.frame.maxX + split.dividerThickness / 2
    let midY = split.bounds.midY
    func event(_ type: NSEvent.EventType, _ px: CGFloat) -> NSEvent {
        let at = split.convert(NSPoint(x: px, y: midY), to: nil)
        return NSEvent.mouseEvent(
            with: type, location: at, modifierFlags: [], timestamp: 0,
            windowNumber: e.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1)!
    }
    let steps = 12
    for i in 1...steps {
        let px = startX + (x - startX) * CGFloat(i) / CGFloat(steps)
        NSApp.postEvent(event(.leftMouseDragged, px), atStart: false)
    }
    NSApp.postEvent(event(.leftMouseUp, x), atStart: false)
    split.mouseDown(with: event(.leftMouseDown, startX))
    spin(0.3)
}

func resetKeys() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: collapsedKey)
    defaults.removeObject(forKey: EditorViewController.inspectorWidthKey)
    defaults.synchronize()
}

func paneRow(_ name: String, _ body: () -> [String: Any]) {
    guard wanted.isEmpty || wanted.contains(name) else { return }
    resetKeys()
    say(name, body())
    resetKeys()
}

paneRow("S1") {
    var seen: [[String: Any]] = []
    for edge in [138.0, 60.0, 4.0] {
        resetKeys()
        guard let e = open("S1", "pick", playhead: 2), let split = upperSplit(e) else {
            return ["failed": "no editor"]
        }
        dragDivider(e, to: split.bounds.width - CGFloat(edge))
        seen.append(splitFacts(e))
        close(e)
    }
    return ["seen": seen]
}
paneRow("S2") {
    guard let e = open("S2", "pick", playhead: 2) else { return ["failed": "no editor"] }
    e.controller.toggleInspector(nil)
    spin(0.2)
    let hidden = splitFacts(e)
    var frame = e.window.frame
    frame.size.width += 120
    frame.size.height += 60
    e.window.setFrame(frame, display: true)
    spin(0.4)
    let resized = splitFacts(e)
    e.controller.toggleInspector(nil)
    spin(0.3)
    let shown = splitFacts(e)
    close(e)
    return ["hidden": hidden, "resized": resized, "shown": shown]
}
paneRow("S3") {
    guard let e = open("S3", "pick", playhead: 2), let split = upperSplit(e) else {
        return ["failed": "no editor"]
    }
    e.controller.toggleInspector(nil)
    spin(0.2)
    let hidden = splitFacts(e)
    dragDivider(e, to: split.bounds.width - 320)
    let out = splitFacts(e)
    var next: [String: Any] = [:]
    if let other = open("S3b", "pick", playhead: 2) {
        next = splitFacts(other)
        close(other)
    }
    close(e)
    return ["hidden": hidden, "out": out, "next": next]
}
paneRow("S4") {
    guard let e = open("S4", "pick", playhead: 2) else { return ["failed": "no editor"] }
    e.controller.toggleInspector(nil)
    spin(0.2)
    let hidden = splitFacts(e)
    var next: [String: Any] = [:]
    if let other = open("S4b", "pick", playhead: 2) {
        next = splitFacts(other)
        close(other)
    }
    close(e)
    return ["hidden": hidden, "next": next]
}

say("END", [:])
exit(0)
