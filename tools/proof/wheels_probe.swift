// Road map "grading-2", phase G2-2 — the wheels' probe (`wheels_proof.py`
// builds it through `swift_build.build` and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, against `libreelcut_core.a`, so every row drives the app's own
// types: `ClipPane`, `VideoPane.wheelsSection()`, `ColorWheelsView`,
// `ColorWheelControl`, `WheelStripControl`, `InspectorBinding`, a
// `ProjectDocument`'s live trio, undo stack and `applyEdit(_:_:amending:)`
// (#272), `LayerUniforms.apply(wheels:)`
// and `ClipSubTab.keyedCount`. The controls' gestures are driven through
// their `press` / `drag` / `release`, the mouse handlers' own bodies. Nothing
// private is widened.
//
//   wheels_probe <request.json> <answer.json>
//
// `request.json` names `package`, a project the proof saved over MCP with two
// CARD clips at lift masters 0.2 and −0.2, and `clips`, their ids. One JSON
// object out: `rows`, each a name, ok and detail, the name starting with its
// P-number.
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

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func parsed(_ op: ReelOp) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(op.json.utf8))) as? [String: Any] ?? [:]
}

// MARK: - P2 the flag, P3 the block

do {
    var negative = LayerUniforms()
    negative.apply(wheels: ColorWheels(gain: ColorWheel(master: -0.5)))
    var neutral = LayerUniforms()
    neutral.apply(wheels: .neutral)
    var pushed = LayerUniforms()
    pushed.apply(wheels: ColorWheels(lift: ColorWheel(x: -0.3, y: -0.4)))
    check(
        "P2 apply(wheels:) sets wheelsEnabled 1 for gain master -0.5 alone and 0 for neutral",
        negative.wheelsEnabled == 1 && negative.gainMaster == -0.5 && neutral.wheelsEnabled == 0
            && pushed.wheelsEnabled == 1 && pushed.liftX == -0.3 && pushed.liftY == -0.4
            && negative.curvesEnabled == 0,
        "gain -0.5: flag \(negative.wheelsEnabled), master \(negative.gainMaster); neutral: "
            + "flag \(neutral.wheelsEnabled); lift (-0.3, -0.4): flag \(pushed.wheelsEnabled)")
    let stride = MemoryLayout<LayerUniforms>.stride
    let lift = MemoryLayout<LayerUniforms>.offset(of: \LayerUniforms.liftX) ?? -1
    let flag = MemoryLayout<LayerUniforms>.offset(of: \LayerUniforms.wheelsEnabled) ?? -1
    let reserved = MemoryLayout<LayerUniforms>.offset(of: \LayerUniforms.gradeReserved0) ?? -1
    check(
        "P3 LayerUniforms is 512 bytes (128 floats, 32 × 16) with liftX at 464 and "
            + "wheelsEnabled at 500",
        stride == 512 && lift == 464 && flag == 500 && reserved == 508,
        "stride \(stride), liftX at \(lift), wheelsEnabled at \(flag), gradeReserved0 at "
            + "\(reserved)")
}

// MARK: - P4 the badge

do {
    let json = #"{"video": {"wheels": {"lift": {"x": 0.2}, "gain": {"master": 1}}, "x": 3}}"#
    if let end = try? JSONDecoder().decode(ActionPatch.self, from: Data(json.utf8)) {
        let color = ClipSubTab.color.keyedCount(in: end)
        let picture = ClipSubTab.picture.keyedCount(in: end)
        check(
            "P4 keyedCount for {video: {wheels: {lift, gain}, x: 3}}: Color 1, Picture 1",
            color == 1 && picture == 1, "color \(color), picture \(picture)")
    } else {
        check("P4 the end decodes as an ActionPatch", false, json)
    }
}

// MARK: - P5 ⌥ moves a tenth (its document part below), P7 the rim

/// P5's standalone half — its name, verdict and detail — scored together with
/// its document half (`p5Strip`) as ONE row, since the proof keys rows by
/// their first word.
var p5Standalone: (name: String, ok: Bool, detail: String) = ("P5", false, "not run")

/// A disc of `side` points whose push reads (0, 0) and whose writes land in
/// `written`.
final class Recorder {
    var written: [(Double, Double)] = []
    var values: [Double] = []
    var begins = 0, ends = 0, resets = 0
}

func standaloneDisc(_ recorder: Recorder, side: CGFloat = 80) -> ColorWheelControl {
    let disc = ColorWheelControl(
        read: { (0, 0) }, write: { recorder.written.append(($0, $1)) },
        begin: { recorder.begins += 1 }, end: { recorder.ends += 1 },
        reset: { recorder.resets += 1 }, enabled: { true }, start: { nil }, now: { nil })
    disc.frame = NSRect(x: 0, y: 0, width: side, height: side)
    return disc
}

do {
    let recorder = Recorder()
    let disc = standaloneDisc(recorder)
    let centre = NSPoint(x: 40, y: 40)
    let step = disc.radius / 2
    disc.press(at: centre)
    disc.drag(to: NSPoint(x: centre.x + step, y: centre.y), fine: false)
    disc.release()
    let plain = recorder.written.last.map { hypot($0.0, $0.1) } ?? -1
    disc.press(at: centre)
    disc.drag(to: NSPoint(x: centre.x + step, y: centre.y), fine: true)
    disc.release()
    let fine = recorder.written.last.map { hypot($0.0, $0.1) } ?? -1

    let strip = WheelStripControl(
        read: { 0 }, write: { recorder.values.append($0) }, begin: {}, end: {}, reset: {},
        enabled: { true }, start: { nil }, now: { nil })
    strip.frame = NSRect(x: 0, y: 0, width: 107, height: 13)
    let middle = strip.bounds.width / 2
    strip.press(atX: middle, fine: true)
    let jumped = !recorder.values.isEmpty
    strip.drag(toX: middle + 25, fine: true)
    strip.release()
    let stripFine = recorder.values.last ?? -1
    strip.press(atX: middle, fine: false)
    strip.drag(toX: middle + 25, fine: false)
    strip.release()
    let stripPlain = recorder.values.last ?? -1
    // A plain press ON the knob grabs it: no write, and the drag keeps the
    // pointer's offset; a double-click there is the reset alone.
    let grabbed = Recorder()
    let knobbed = WheelStripControl(
        read: { 0 }, write: { grabbed.values.append($0) }, begin: {}, end: {},
        reset: { grabbed.resets += 1 }, enabled: { true }, start: { nil }, now: { nil })
    knobbed.frame = strip.frame
    knobbed.press(atX: middle + 2, fine: false)
    let grabWrote = !grabbed.values.isEmpty
    knobbed.drag(toX: middle + 27, fine: false)
    knobbed.release()
    let grabValue = grabbed.values.last ?? -1
    grabbed.values.removeAll()
    knobbed.press(atX: middle, fine: false, clickCount: 1)
    knobbed.release()
    knobbed.press(atX: middle, fine: false, clickCount: 2)
    let doubleWrites = grabbed.values.count
    p5Standalone = (
        "P5 an ⌥ drag moves the puck a tenth of a plain one (\(plain) → \(fine)) and the "
            + "strip a tenth with no jump on the press (\(stripPlain) → \(stripFine)); a "
            + "press on the strip's knob writes nothing and its drag keeps the grab "
            + "(\(grabValue)), so a double-click there is the reset alone",
        abs(plain - 0.5) < 1e-9 && abs(fine - 0.05) < 1e-9 && !jumped
            && abs(stripFine - stripPlain * ColorWheelControl.fine) < 1e-9 && stripPlain > 0
            && !grabWrote && abs(grabValue - stripPlain) < 1e-9
            && doubleWrites == 0 && grabbed.resets == 1,
        "disc plain \(plain), fine \(fine); strip jumped \(jumped), fine \(stripFine), plain "
            + "\(stripPlain); knob press wrote \(grabWrote), grab drag \(grabValue), "
            + "double-click writes \(doubleWrites), resets \(grabbed.resets)")
}

do {
    let recorder = Recorder()
    let disc = standaloneDisc(recorder)
    let centre = NSPoint(x: 40, y: 40)
    var misses: [String] = []
    var onRim = 0
    let count = 10_000
    for k in 0..<count {
        let theta = 2 * Double.pi * Double(k) / Double(count)
        disc.press(at: centre)
        for reach in [0.8, 1.3, 1.7] {
            let r = Double(disc.radius) * reach
            disc.drag(
                to: NSPoint(x: centre.x + CGFloat(r * cos(theta)), y: centre.y + CGFloat(r * sin(theta))),
                fine: false)
        }
        disc.release()
        guard let (x, y) = recorder.written.last else {
            misses.append("θ \(theta): nothing written")
            continue
        }
        if x * x + y * y > 1 + 1e-9 { misses.append("θ \(theta): (\(x), \(y))") }
        if abs(hypot(x, y) - 1) < 1e-9 { onRim += 1 }
    }
    check(
        "P7 \(count) drags past the rim at even angles each land with x² + y² ≤ 1 + 1e-9 "
            + "(\(onRim) on the rim)",
        misses.isEmpty && onRim == count && recorder.begins == count && recorder.ends == count,
        "\(misses.prefix(4)); on the rim \(onRim); begins \(recorder.begins), ends "
            + "\(recorder.ends)")
}

// MARK: - P1 a puck drag over two clips, P6 a double-click

func lift(_ document: ProjectDocument, _ id: UInt32) -> ColorWheel? {
    document.project.snapshot.clips.first { $0.id == id }?.videoProps.wheels.lift
}

func p1p6() {
    guard let path = request["package"] as? String,
          let clips = (request["clips"] as? [NSNumber])?.map(\.uint32Value), clips.count == 2
    else {
        check("P1 the request names the package and two clips", false, "\(request)")
        check("P6 the request names the package and two clips", false, "\(request)")
        return
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        check("P1 project P opens", false, "\(error)")
        check("P6 project P opens", false, "\(error)")
        return
    }
    let masters = clips.compactMap { lift(document, $0)?.master }
    let inspector = InspectorViewController()
    inspector.document = document
    var begins = 0
    var updates: [[ReelOp]] = []
    var ended: [String] = []
    var edits: [(String, [ReelOp])] = []
    inspector.onLiveBegin = { begins += 1; document.beginLiveEdit() }
    inspector.onLiveUpdate = { ops in updates.append(ops); document.updateLiveEdit(ops) }
    inspector.onLiveEnd = { name in ended.append(name); document.endLiveEdit(name) }
    inspector.onEdit = { name, ops in edits.append((name, ops)); document.applyEdit(name, ops) }
    document.selection = Set(clips)
    inspector.binding.invalidate()
    let pane = ClipPane(inspector: inspector)
    pane.binding.invalidate()
    let tabs = pane.subTabs
    pane.choose(.color)
    pane.rebuild()
    pane.refresh()
    let ids = pane.sections.map(\.id)
    let section = pane.sections.first { $0.id == "video.wheels" }
    let view = section.flatMap { walk($0).compactMap { $0 as? ColorWheelsView }.first }
    guard let view, view.discs.count == 3 else {
        let why = "tabs \(tabs); sections \(ids); view \(view != nil)"
        check("P1 the Color tab has a Wheels section with three discs", false, why)
        check("P6 the Color tab has a Wheels section with three discs", false, why)
        return
    }
    // The Color sections from Color on: Curves (grading-2 G2-3) joined
    // between Wheels and Look.
    let order = Array(ids.drop { $0 != "video.color" }.prefix(4))
    let disc = view.discs[0]
    disc.frame = NSRect(x: 0, y: 0, width: 80, height: 80)
    spin(0.1)
    let centre = NSPoint(x: 40, y: 40)
    disc.press(at: centre)
    disc.drag(to: NSPoint(x: 50, y: 40), fine: false)
    disc.drag(to: NSPoint(x: 60, y: 47), fine: false)
    disc.release()
    spin(0.3)
    let name = document.undoManager?.undoActionName ?? "-"
    let moved = clips.compactMap { lift(document, $0) }
    let shapes = updates.map { ops -> String in
        guard ops.count == 1 else { return "\(ops.count) ops" }
        let op = parsed(ops[0])
        let named = ((op["clips"] as? [NSNumber]) ?? []).map(\.uint32Value).sorted()
        let patch = op["patch"] as? [String: Any] ?? [:]
        let wheels = patch["wheels"] as? [String: Any] ?? [:]
        let liftKeys = (wheels["lift"] as? [String: Any]).map { Set($0.keys) } ?? []
        let good = op["op"] as? String == "set_video" && named == clips.sorted()
            && Set(patch.keys) == ["wheels"] && Set(wheels.keys) == ["lift"]
            && liftKeys == ["x", "y"]
        return good ? "ok" : "\(op)"
    }
    document.undoManager?.undo()
    spin(0.3)
    let undone = clips.compactMap { lift(document, $0) }
    let more = document.undoManager?.canUndo ?? true
    check(
        "P1 a Lift puck drag over two clips (masters \(masters)) is ONE undo step \"Lift\" "
            + "whose \(updates.count) updates each send one set_video naming both with "
            + "exactly {wheels: {lift: {x, y}}}; the sections run \(order)",
        Set(masters) == [0.2, -0.2] && tabs.contains(.color) && begins == 1
            && ended == ["Lift"] && updates.count == 2 && shapes.allSatisfy { $0 == "ok" }
            && name == "Lift" && moved.count == 2
            && moved.allSatisfy { $0.x > 0 && $0.x * $0.x + $0.y * $0.y <= 1 + 1e-9 }
            && moved.map(\.master) == masters
            && undone.allSatisfy { $0.x == 0 && $0.y == 0 } && undone.map(\.master) == masters
            && !more && order == ["video.color", "video.wheels", "video.curves", "video.look"],
        "begins \(begins), ended \(ended), updates \(shapes), undo name \(name), moved "
            + "\(moved), undone \(undone), more steps \(more), sections \(ids)")

    // P6: a set push on both, then a double-click on the Lift disc.
    let pushed = ColorWheelsPatch(lift: ColorWheelPatch(x: 0.3, y: 0.2))
    document.applyEdit("Setup", [.setVideo(clips: clips, patch: VideoPatch(wheels: pushed))])
    spin(0.3)
    inspector.binding.invalidate()
    let before = clips.compactMap { lift(document, $0) }
    edits.removeAll()
    disc.press(at: centre, clickCount: 2)
    spin(0.3)
    let reset = clips.compactMap { lift(document, $0) }
    let resetName = document.undoManager?.undoActionName ?? "-"
    let sent = edits.count == 1 && edits[0].1.count == 1 ? parsed(edits[0].1[0]) : [:]
    let patch = sent["patch"] as? NSDictionary
    let want: NSDictionary = ["wheels": ["lift": ["x": 0, "y": 0]]]
    document.undoManager?.undo()
    spin(0.3)
    let back = clips.compactMap { lift(document, $0) }
    check(
        "P6 a double-click on the Lift disc resets x and y only (masters kept), one step "
            + "\"Lift\" sending exactly {wheels: {lift: {x: 0, y: 0}}}",
        before.allSatisfy { $0.x == 0.3 && $0.y == 0.2 } && edits.count == 1
            && edits.first?.0 == "Lift" && patch == want
            && reset.allSatisfy { $0.x == 0 && $0.y == 0 } && reset.map(\.master) == masters
            && resetName == "Lift" && back.allSatisfy { $0.x == 0.3 && $0.y == 0.2 }
            && begins == 1,
        "before \(before), edits \(edits.map { ($0.0, $0.1.map(\.json)) }), after \(reset), "
            + "undo name \(resetName), undone \(back)")
}
p1p6()

// MARK: - P5's document half: a strip double-click off the knob (#272)

/// Both clips' lift masters.
func liftMasters(_ document: ProjectDocument, _ clips: [UInt32]) -> [Double] {
    clips.compactMap { lift(document, $0)?.master }
}

/// One case on a FRESH document read from project P, wired as P1's plus
/// `onAmendEdit`: an optional `setup` master on both clips, a press at `x`
/// and its release, an optional master on both `between` the clicks, then
/// the double-click; the masters after it, its undo name, and the masters
/// and `canUndo` after ONE undo. The spins are 0.1 s, not P1's 0.3, so the
/// release and the double-click stay inside `NSEvent.doubleClickInterval`
/// even with an edit between them (the reset amends only inside it).
func stripCase(
    _ path: String, _ clips: [UInt32], setup: Double? = nil, x: CGFloat, between: Double? = nil
) -> (reset: [Double], name: String, undone: [Double], more: Bool, stepped: Bool, why: String)? {
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        return nil
    }
    let inspector = InspectorViewController()
    inspector.document = document
    inspector.onLiveBegin = { document.beginLiveEdit() }
    inspector.onLiveUpdate = { ops in document.updateLiveEdit(ops) }
    inspector.onLiveEnd = { name in document.endLiveEdit(name) }
    inspector.onEdit = { name, ops in document.applyEdit(name, ops) }
    inspector.onAmendEdit = { name, ops, step in
        document.applyEdit(name, ops, amending: step)
    }
    document.selection = Set(clips)
    inspector.binding.invalidate()
    let pane = ClipPane(inspector: inspector)
    pane.binding.invalidate()
    pane.choose(.color)
    pane.rebuild()
    pane.refresh()
    let section = pane.sections.first { $0.id == "video.wheels" }
    guard let view = section.flatMap({ walk($0).compactMap { $0 as? ColorWheelsView }.first }),
          view.strips.count == 3
    else { return nil }
    let strip = view.strips[0]
    strip.frame = NSRect(x: 0, y: 0, width: 107, height: 13)
    func master(_ value: Double) {
        let patch = ColorWheelsPatch(lift: ColorWheelPatch(master: value))
        document.applyEdit("Lift", [.setVideo(clips: clips, patch: VideoPatch(wheels: patch))])
        spin(0.1)
        inspector.binding.invalidate()
        pane.binding.invalidate()
    }
    if let setup { master(setup) }
    let pressed = document.project
    strip.press(atX: x, fine: false)
    strip.release()
    spin(0.1)
    let stepped = document.project !== pressed
    let jumped = liftMasters(document, clips)
    inspector.binding.invalidate()
    pane.binding.invalidate()
    if let between { master(between) }
    strip.press(atX: x, fine: false, clickCount: 2)
    spin(0.1)
    let reset = liftMasters(document, clips)
    let name = document.undoManager?.undoActionName ?? "-"
    document.undoManager?.undo()
    spin(0.1)
    let undone = liftMasters(document, clips)
    let more = document.undoManager?.canUndo ?? true
    withExtendedLifetime(pane) {}
    return (reset, name, undone, more, stepped, "jumped \(jumped)")
}

/// P5's one row: the standalone half above and the three document cases.
func p5Strip() {
    let (name, standalone, detail) = p5Standalone
    guard let path = request["package"] as? String,
          let clips = (request["clips"] as? [NSNumber])?.map(\.uint32Value), clips.count == 2
    else {
        check(name, false, "the request names no package and two clips: \(request)")
        return
    }
    let a = stripCase(path, clips, x: 10)
    let b = stripCase(path, clips, x: 10, between: 0.5)
    let c = stripCase(path, clips, setup: -1, x: -1)
    func shown(_ got: (reset: [Double], name: String, undone: [Double], more: Bool,
                       stepped: Bool, why: String)?) -> String {
        guard let got else { return "the case could not be built" }
        return "reset \(got.reset) \"\(got.name)\", undone \(got.undone), more steps "
            + "\(got.more), first click stepped \(got.stepped), \(got.why)"
    }
    let goodA = a.map {
        $0.stepped && $0.reset == [0, 0] && $0.name == "Lift" && $0.undone == [0.2, -0.2]
            && !$0.more
    } ?? false
    let goodB = b.map { $0.stepped && $0.reset == [0, 0] && $0.undone == [0.5, 0.5] } ?? false
    let goodC = c.map { !$0.stepped && $0.reset == [0, 0] && $0.undone == [-1, -1] } ?? false
    check(
        name + "; on a document a double-click off the Lift strip's knob is ONE undo step "
            + "\"Lift\" back to (0.2, -0.2), a reset after an edit between the clicks is its "
            + "own step, and an identity jump amends no older step",
        standalone && goodA && goodB && goodC,
        detail + "; (a) \(shown(a)); (b) \(shown(b)); (c) \(shown(c)); double-click interval "
            + "\(NSEvent.doubleClickInterval) s")
}
p5Strip()

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
    try? data.write(to: out)
}
exit(0)
