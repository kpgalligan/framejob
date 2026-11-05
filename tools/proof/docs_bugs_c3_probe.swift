// Docs bugs c3: the presses MCP cannot send, on the real `EditorViewController`, inspector rows, row
// menus and media list, compiled AS main.swift over every file of app/Sources but the app's own
// main.swift, through `swift_build.py`, and run over real `.framejob` packages the app saved
// (`docs_bugs_c3_proof.py` makes them and scores what this prints).
//
// It names only symbols present before the fix, and compares nothing itself, so it builds over the
// base's sources and the proof scores the same rows on both.
//
// **Nothing reaches the screen or takes focus.** Activation policy .prohibited; each window sits
// 20,000 pt off every display and can never become key or main; an NSAlert's sheet is replaced in
// this process by a recorder, so the alert the real handler built is read and none is shown. No
// event is posted: a control's own mouseDown runs on a synthesised event, a menu item's own action
// is performed. No pasteboard. Sections open through `register(defaults:)`, which is never written.
//
//   docs_bugs_c3_probe <fixtures dir> <ids.json> <qualifier|remove|hints>
//
// Prints one JSON line per stage, `{"row": <stage>, …}`.
import AppKit
import ObjectiveC

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
UserDefaults.standard.register(defaults: [
    "FrameJobInspectorCollapsed": false,
    "FrameJobInspectorSection.video.qualifier": false,
    "FrameJobInspectorSection.video.chroma": false,
])

let arguments = CommandLine.arguments
let fixtures = URL(fileURLWithPath: arguments[1])
let ids = (try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: arguments[2]))))
    as! [String: Int]
let which = arguments[3]
let second: Double = Double(ReelTime.perSecond)

func say(_ row: String, _ fields: [String: Any]) {
    var line = fields
    line["row"] = row
    let data = try! JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func bail(_ why: String) -> Never {
    say("abort", ["abort": why])
    exit(2)
}

func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

func waitUntil(_ limit: Double, _ condition: () -> Bool) -> Bool {
    let start = Date()
    while Date().timeIntervalSince(start) < limit {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return condition()
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

/// A stored property by name, this class's or a superclass's.
func field(_ value: Any, _ name: String) -> Any? {
    var mirror: Mirror? = Mirror(reflecting: value)
    while let current = mirror {
        if let found = current.children.first(where: { $0.label == name }) { return found.value }
        mirror = current.superclassMirror
    }
    return nil
}

func orNull(_ value: Any?) -> Any { value ?? NSNull() }

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
    var inspector: InspectorViewController { controller.inspector! }
    var root: NSView { window.contentView! }
}

/// A fresh copy of `name`, so each stage starts from what the app saved.
func open(_ name: String, tag: String) -> Open {
    let source = fixtures.appendingPathComponent("\(name).framejob")
    let url = fixtures.appendingPathComponent("run-\(tag).framejob")
    try? FileManager.default.removeItem(at: url)
    let doc = ProjectDocument()
    do {
        try FileManager.default.copyItem(at: source, to: url)
        try doc.read(from: url, ofType: ProjectDocument.projectTypeIdentifier)
        doc.fileURL = url
    } catch {
        bail("read \(name): \(error)")
    }
    doc.startGraphicStore()
    let controller = EditorViewController(document: doc)
    let frame = NSRect(x: -20000, y: -20000, width: 1440, height: 900)
    let window = OffWindow(
        contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered,
        defer: false)
    window.contentViewController = controller
    window.setFrame(frame, display: false)
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
        bail("windowForSheet is not the probe's window: an alert would be app-modal")
    }
    return Open(doc: doc, controller: controller, window: window, keep: keep)
}

func model(_ o: Open) -> [String: Any] {
    let text = o.doc.editedProject.json
    return (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
}

func press(_ view: NSView, in window: NSWindow) {
    let centre = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    func event(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: centre, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: 1)!
    }
    view.mouseDown(with: event(.leftMouseDown))
    view.mouseUp(with: event(.leftMouseUp))
}

func perform(_ item: NSMenuItem?) -> Bool {
    guard let item, let target = item.target, let selector = item.action else { return false }
    _ = (target as AnyObject).perform(selector, with: item)
    return true
}

// MARK: - The qualifier in an action (#480)

let adjust = UInt32(ids["adjust"] ?? 0)
let action = UInt32(ids["action"] ?? 0)

func qualifierRows(_ o: Open) -> [InspectorRowView] {
    walk(o.root).compactMap { $0 as? InspectorRowView }
        .filter { $0.gutter.writes.contains { $0.contains("qualifier") } }
}

func hueCheck(_ o: Open) -> OptionCheckboxControl? {
    walk(o.root).compactMap { $0 as? OptionCheckboxControl }
        .first { field($0, "label") as? String == "Hue" }
}

func hueRow(_ o: Open) -> InspectorRowView? {
    guard let check = hueCheck(o) else { return nil }
    return qualifierRows(o).first { row in walk(row).contains { $0 === check } }
}

/// What a person would read: the box by what its `on()` reads, the marks, the row's menu, the stored
/// end, and the clip's state past the action's end, which is the evaluator's and no row's.
func state(_ o: Open) -> [String: Any] {
    let clips = model(o)["clips"] as? [[String: Any]] ?? []
    let clip = clips.first { ($0["id"] as? Int) == Int(adjust) }
    let actions = clip?["actions"] as? [[String: Any]]
    let box = o.inspector.binding.videoProps.qualifier.isOn(.hue)
    let past = o.doc.editedProject.clipState(adjust, at: Ticks(4.5 * second))
    let qualifier = (past?["video"] as? [String: Any])?["qualifier"] as? [String: Any]
    let items = hueRow(o)?.contextMenu()?.items.map { ["title": $0.title, "enabled": $0.isEnabled] }
    let marks = hueRow(o).map { row -> [String: Any] in
        let label = walk(row).compactMap { $0 as? NSTextField }.map(\.stringValue)
        return ["mark": "\(row.gutter.mark)", "texts": label]
    }
    return [
        "box": box,
        "selected_action": orNull(o.inspector.binding.selectedAction?.id),
        "end": orNull(actions?.first?["end"]),
        "base": orNull((clip?["video"] as? [String: Any])?["qualifier"]),
        "undo": orNull(o.doc.undoManager?.undoMenuItemTitle),
        "row": orNull(marks),
        "marks": qualifierRows(o).map { "\($0.gutter.mark)" },
        "items": orNull(items),
        "past_hue": qualifier.map { !($0["hue"] == nil || $0["hue"] is NSNull) } ?? false,
        "past_saturation": qualifier.map { $0["saturation"] is [String: Any] } ?? false,
    ]
}

func openQualifier(_ name: String, tag: String) -> Open {
    let o = open(name, tag: tag)
    o.doc.selection = [adjust]
    o.controller.viewStateDidChange()
    spin(0.4)
    o.controller.selectAction(action, on: adjust)
    spin(0.4)
    o.inspector.select(.clip)
    o.inspector.selectClipSubTab(.color)
    spin(0.8)
    return o
}

func pressHue(_ o: Open) -> Bool {
    guard let check = hueCheck(o) else { return false }
    press(check, in: o.window)
    spin(0.8)
    return true
}

/// The canvas pixel the stage presses: the black margin of testsrc2, a pixel with no chroma.
func greyPoint(_ o: Open) -> CGPoint? {
    var point: CGPoint?
    var best = CGFloat.infinity
    let bounds = o.root.bounds
    for x in stride(from: bounds.minX, to: bounds.maxX, by: 8) {
        for y in stride(from: bounds.minY, to: bounds.maxY, by: 8) {
            guard let pixel = o.controller.pickedCanvasPixel(atWindow: CGPoint(x: x, y: y))
            else { continue }
            let distance = hypot(pixel.x - 100, pixel.y - 100)
            if distance < best {
                best = distance
                point = CGPoint(x: x, y: y)
            }
        }
    }
    return point
}

func runQualifier() {
    // P1, P2 and P6: the box pressed, then pressed again.
    do {
        let o = openQualifier("qualifier", tag: "press")
        let start = state(o)
        let pressed = pressHue(o)
        let unticked = state(o)
        _ = pressHue(o)
        say("press", ["start": start, "pressed": pressed, "unticked": unticked, "ticked": state(o)])
    }
    // P4: the keyed row's Remove from action.
    do {
        let o = openQualifier("qualifier", tag: "remove-key")
        _ = pressHue(o)
        let item = hueRow(o)?.contextMenu()?.items.first { $0.title.hasPrefix("Remove from action") }
        let performed = perform(item)
        spin(0.8)
        say("remove-key", ["performed": performed, "after": state(o)])
    }
    // P3: the row's Set end value to default.
    do {
        let o = openQualifier("qualifier", tag: "default")
        let item = hueRow(o)?.contextMenu()?.items.first { $0.title == "Set end value to default" }
        let enabled = item?.isEnabled ?? false
        let performed = perform(item)
        spin(0.8)
        say("default", ["enabled_before": enabled, "performed": performed, "after": state(o)])
    }
    // P5: Pick from Canvas on a grey pixel.
    do {
        let o = openQualifier("qualifier", tag: "pick")
        o.controller.pickQualifier(nil)
        spin(0.3)
        let armed = o.controller.qualifierPick != nil
        var landed = false
        if let point = greyPoint(o) {
            o.controller.qualifierPick?.onPick?(point)
            landed = waitUntil(15) {
                (o.doc.undoManager?.undoMenuItemTitle ?? "").contains("Qualifier")
            }
            spin(0.8)
        }
        say("pick", ["armed": armed, "landed": landed, "after": state(o)])
    }
    // P7: a range the end ramps to, unticked.
    do {
        let o = openQualifier("qualifier-ramp", tag: "ramp")
        let before = state(o)
        let pressed = pressHue(o)
        say("ramp", ["before": before, "pressed": pressed, "after": state(o)])
    }
}

// MARK: - The LUT's Remove button (#512)

var recorded: (alert: NSAlert, handler: ((NSApplication.ModalResponse) -> Void)?)?
func recordAlerts() {
    let selector = #selector(NSAlert.beginSheetModal(for:completionHandler:))
    guard let method = class_getInstanceMethod(NSAlert.self, selector) else {
        bail("beginSheetModal not found")
    }
    let block: @convention(block) (
        NSAlert, NSWindow, (@convention(block) (NSApplication.ModalResponse) -> Void)?
    ) -> Void = { alert, _, handler in
        recorded = (alert, handler.map { h in { h($0) } })
    }
    method_setImplementation(method, imp_implementationWithBlock(block))
}

func runRemove() {
    recordAlerts()
    let o = open("remove", tag: "remove")
    o.inspector.select(.media)
    spin(0.8)
    func mediaCount() -> Int { (model(o)["media"] as? [[String: Any]])?.count ?? -1 }
    func remove(_ name: String) {
        let id = ids[name] ?? -1
        let row = walk(o.root).compactMap { $0 as? MediaRowView }.first {
            (field($0, "media") as? UInt32).map(Int.init) == id
        }
        guard let row else {
            say("remove-\(name)", ["found": false])
            return
        }
        let centre = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        let event = NSEvent.mouseEvent(
            with: .rightMouseDown, location: centre, modifierFlags: [], timestamp: 0,
            windowNumber: o.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
            pressure: 1)!
        recorded = nil
        let before = mediaCount()
        let item = row.menu(for: event)?.items.first { $0.title == "Remove" }
        let performed = perform(item)
        spin(0.4)
        say("remove-\(name)", [
            "found": true, "performed": performed, "before": before, "after": mediaCount(),
            "alert": recorded != nil,
            "text": orNull(recorded?.alert.informativeText),
            "buttons": recorded?.alert.buttons.map(\.title) ?? [],
        ])
    }
    remove("tint")
    remove("both")
    remove("video")
    remove("swap")
    // The Camera-Log-only alert's first button: what it clears is what its title says.
    if let handler = recorded?.handler {
        handler(.alertFirstButtonReturn)
        spin(0.6)
        let media = model(o)["media"] as? [[String: Any]] ?? []
        let file = media.first { ($0["id"] as? Int) == ids["file"] }
        say("remove-swap-pressed", ["file_color": orNull(file?["color"]), "media": media.count])
    }
    remove("free")
}

// MARK: - The pick hints (#515)

func runHints() {
    let o = open("qualifier", tag: "hints")
    func button() -> OptionButtonControl? {
        walk(o.root).compactMap { $0 as? OptionButtonControl }
            .first { field($0, "title") as? String == "Pick from Canvas" }
    }
    func hint(_ overlay: CanvasPickOverlay?) -> Any {
        orNull(overlay.flatMap { field($0, "hint") as? String })
    }
    o.doc.selection = [UInt32(ids["clip"] ?? 0)]
    o.controller.viewStateDidChange()
    spin(0.5)
    o.inspector.select(.clip)
    o.inspector.selectClipSubTab(.picture)
    spin(0.5)
    if let found = button() { press(found, in: o.window) }
    spin(0.5)
    let chromaHint = hint(o.controller.chromaEyedropper)
    let chromaTip = orNull(button()?.toolTip)
    o.controller.chromaEyedropper?.onCancel?()
    spin(0.3)
    o.doc.selection = [adjust]
    o.controller.viewStateDidChange()
    spin(0.5)
    o.inspector.select(.clip)
    o.inspector.selectClipSubTab(.color)
    spin(0.5)
    if let found = button() { press(found, in: o.window) }
    spin(0.5)
    say("hints", [
        "chroma_hint": chromaHint, "chroma_tip": chromaTip,
        "qualifier_hint": hint(o.controller.qualifierPick),
        "qualifier_tip": orNull(button()?.toolTip),
    ])
    o.controller.qualifierPick?.onCancel?()
    spin(0.3)
}

switch which {
case "qualifier": runQualifier()
case "remove": runRemove()
case "hints": runHints()
default: bail("no stage \(which)")
}
say("done", [:])
exit(0)
