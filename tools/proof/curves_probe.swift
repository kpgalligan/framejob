// Road map "grading-2", phase G2-3 — the curves' probe (`curves_proof.py`
// builds it through `swift_build.build` and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, against `libframejob_core.a`, so every row drives the app's own
// types: `ClipPane`, `VideoPane.curvesSection(_:)`, `CurvesView`,
// `CurveEditorView`, `InspectorBinding`'s ops and `curvesReset`, a
// `ProjectDocument`'s live trio and undo stack, `LayerUniforms.apply(curves:)`,
// `CurveTable`, `CurveTextures`, `ClipSubTab.keyedCount` and the editor's
// Delete validator. The plot's gestures are driven through its `press` /
// `drag` / `release` / `key`, the event handlers' own bodies. Nothing private
// is widened.
//
//   curves_probe <request.json> <answer.json>
//
// `request.json` names `package`, a project the proof saved over MCP with two
// CARD clips whose master curves are [[0,0],[0.5,0.6],[1,1]] and
// [[0,0],[0.5,0.4],[1,1]], `clips`, their ids, and `oracle`, 200 seeded
// curves with the proof's own Fritsch–Carlson values at 64 inputs each. One
// JSON object out: `rows`, each a name, ok and detail, the name starting
// with its P-number.
import AppKit
import Metal

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

func pts(_ list: [[Double]]) -> [CurvePoint] { list.map { CurvePoint(x: $0[0], y: $0[1]) } }
func pairs(_ list: [CurvePoint]) -> [[Double]] { list.map { [$0.x, $0.y] } }

/// A key-down as the keyboard delivers it.
func keyEvent(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
        context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: code)!
}
func function(_ scalar: Int) -> String { String(Character(UnicodeScalar(UInt32(scalar))!)) }
let up = keyEvent(function(NSUpArrowFunctionKey), code: 126, flags: [.numericPad, .function])
let right = keyEvent(function(NSRightArrowFunctionKey), code: 124, flags: [.numericPad, .function])
let shiftRight = keyEvent(
    function(NSRightArrowFunctionKey), code: 124, flags: [.shift, .numericPad, .function])
let backspace = keyEvent("\u{7f}", code: 51)
let escape = keyEvent("\u{1b}", code: 53)

// MARK: - P5 the flag, P6 the spline, P7 the strip, P8 the badge

do {
    var red = LayerUniforms()
    red.apply(curves: ColorCurves(red: pts([[0, 0], [0.5, 0.7], [1, 1]])))
    var identity = LayerUniforms()
    identity.apply(curves: .identity)
    var diagonal = LayerUniforms()
    diagonal.apply(curves: ColorCurves(master: pts([[0, 0], [0.5, 0.5], [1, 1]])))
    check(
        "P5 apply(curves:) sets curvesEnabled 1 for a red curve alone, 0 for the identity and "
            + "for a 3-point diagonal",
        red.curvesEnabled == 1 && identity.curvesEnabled == 0 && diagonal.curvesEnabled == 0
            && red.wheelsEnabled == 0,
        "red \(red.curvesEnabled), identity \(identity.curvesEnabled), diagonal "
            + "\(diagonal.curvesEnabled)")
}

do {
    let oracle = request["oracle"] as? [[String: Any]] ?? []
    var worst = 0.0
    var outside: [String] = []
    for (index, entry) in oracle.enumerated() {
        let points = pts((entry["points"] as? [[Double]]) ?? [])
        let inputs = entry["inputs"] as? [Double] ?? []
        let values = entry["values"] as? [Double] ?? []
        for (x, want) in zip(inputs, values) {
            worst = max(worst, abs(CurveTable.value(points, at: x) - want))
        }
        for k in 0..<max(points.count - 1, 0) {
            let low = min(max(min(points[k].y, points[k + 1].y), 0), 1)
            let high = min(max(max(points[k].y, points[k + 1].y), 0), 1)
            for step in 0...50 {
                let x = points[k].x + (points[k + 1].x - points[k].x) * Double(step) / 50
                let y = CurveTable.value(points, at: x)
                if y < low - 1e-12 || y > high + 1e-12 {
                    outside.append("curve \(index) segment \(k): \(y) outside [\(low), \(high)]")
                    break
                }
            }
        }
    }
    check(
        "P6 CurveTable.value equals the proof's Fritsch–Carlson within 1e-9 on \(oracle.count) "
            + "seeded curves (worst \(worst)) and never leaves a segment's y span",
        oracle.count == 200 && worst <= 1e-9 && outside.isEmpty,
        "worst \(worst); outside \(outside.count): \(outside.prefix(3))")
}

do {
    let curves = ColorCurves(
        master: pts([[0, 0.05], [0.3, 0.2], [0.7, 0.85], [1, 0.95]]),
        red: pts([[0, 0], [0.5, 0.7], [1, 1]]), blue: pts([[0, 0.1], [1, 1]]))
    if let device = MTLCreateSystemDefaultDevice(), let textures = CurveTextures(device: device) {
        let strip = textures.texture(for: curves)
        let want = CurveTable.strip(curves)
        var got = [Float](repeating: -1, count: want.count)
        if strip.pixelFormat == .rgba32Float {
            got.withUnsafeMutableBytes { bytes in
                strip.getBytes(bytes.baseAddress!, bytesPerRow: strip.width * 16,
                               from: MTLRegionMake2D(0, 0, strip.width, 1), mipmapLevel: 0)
            }
        }
        var holder = [Float](repeating: -1, count: 8)
        let placeholder = textures.placeholder
        if placeholder.pixelFormat == .rgba32Float {
            holder.withUnsafeMutableBytes { bytes in
                placeholder.getBytes(bytes.baseAddress!, bytesPerRow: 32,
                                     from: MTLRegionMake2D(0, 0, 2, 1), mipmapLevel: 0)
            }
        }
        let same = textures.texture(for: curves) === strip
        let identity = textures.texture(for: .identity) === placeholder
        check(
            "P7 the strip is rgba32Float \(CurveTable.stripSize)×1 on a 32-bit-filtering device "
                + "and reads back CurveTable.strip exactly; the placeholder is the 2×1 identity",
            device.supports32BitFloatFiltering && strip.pixelFormat == .rgba32Float
                && strip.width == CurveTable.stripSize && strip.height == 1 && got == want
                && placeholder.width == 2 && placeholder.height == 1
                && holder == [0, 0, 0, 1, 1, 1, 1, 1] && same && identity,
            "filtering \(device.supports32BitFloatFiltering), format \(strip.pixelFormat.rawValue), "
                + "\(strip.width)×\(strip.height), equal \(got == want), placeholder "
                + "\(placeholder.width)×\(placeholder.height) \(holder), cached \(same), identity "
                + "→ placeholder \(identity)")
    } else {
        check("P7 a Metal device and the strip cache exist", false)
    }
}

do {
    let json = #"{"video": {"curves": {"master": [[0, 0], [0.5, 0.7], [1, 1]], "red": null}}}"#
    if let end = try? JSONDecoder().decode(ActionPatch.self, from: Data(json.utf8)) {
        let color = ClipSubTab.color.keyedCount(in: end)
        let picture = ClipSubTab.picture.keyedCount(in: end)
        check("P8 keyedCount for {video: {curves: {master, red}}}: Color 1, Picture 0",
              color == 1 && picture == 0, "color \(color), picture \(picture)")
    } else {
        check("P8 the end decodes as an ActionPatch", false, json)
    }
}

// MARK: - The inspector over project P

func master(_ document: ProjectDocument, _ id: UInt32, _ channel: CurveChannel = .master)
    -> [CurvePoint]
{
    document.project.snapshot.clips.first { $0.id == id }?.videoProps.curves.points(channel) ?? []
}

guard let path = request["package"] as? String,
      let clips = (request["clips"] as? [NSNumber])?.map(\.uint32Value), clips.count == 2
else {
    for name in ["P1", "P2", "P3", "P4", "P9", "P10", "P11"] {
        check("\(name) the request names the package and two clips", false, "\(request)")
    }
    finish()
}

func finish() -> Never {
    let answer: [String: Any] = ["rows": rows]
    if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
        try? data.write(to: out)
    }
    exit(0)
}

func open() -> ProjectDocument? {
    let document = ProjectDocument()
    do {
        try document.read(from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        return nil
    }
    return document
}

guard let document = open() else {
    for name in ["P1", "P2", "P3", "P4", "P9", "P10", "P11"] {
        check("\(name) project P opens", false)
    }
    finish()
}
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
pane.choose(.color)
pane.rebuild()
pane.refresh()
let ids = pane.sections.map(\.id)
let order = Array(ids.drop { $0 != "video.color" }.prefix(4))
let view = pane.sections.first { $0.id == "video.curves" }
    .flatMap { walk($0).compactMap { $0 as? CurvesView }.first }
guard let view else {
    for name in ["P1", "P2", "P3", "P4", "P9", "P10", "P11"] {
        check("\(name) the Color tab has a Curves section", false, "sections \(ids)")
    }
    finish()
}
let editor = view.editor
editor.frame = NSRect(x: 0, y: 0, width: 254, height: 254)
spin(0.1)

/// The inspector caught up with the document, as its refresh would.
func settle() {
    spin(0.2)
    inspector.binding.invalidate()
    pane.refresh()
}

func reset() {
    begins = 0
    updates.removeAll()
    ended.removeAll()
    edits.removeAll()
}

let start = clips.map { master(document, $0) }

/// Every op in `ops` is one set_video naming both clips whose patch is exactly
/// `{curves: {channel: list}}`; the list.
func shape(_ ops: [ReelOp], _ channel: CurveChannel) -> [[Double]]? {
    guard ops.count == 1 else { return nil }
    let op = parsed(ops[0])
    let named = ((op["clips"] as? [NSNumber]) ?? []).map(\.uint32Value).sorted()
    let patch = op["patch"] as? [String: Any] ?? [:]
    let curves = patch["curves"] as? [String: Any] ?? [:]
    guard op["op"] as? String == "set_video", named == clips.sorted(),
          Set(patch.keys) == ["curves"], Set(curves.keys) == [channel.rawValue]
    else { return nil }
    return curves[channel.rawValue] as? [[Double]]
}

// MARK: - P1 a press adds a point on the curve, one live gesture

do {
    reset()
    let before = master(document, clips[0])
    let at = editor.screen(CurvePoint(x: 0.25, y: 0.9))
    editor.press(at: at)
    editor.release()
    settle()
    let sent = updates.compactMap { shape($0, .master) }
    let name = document.undoManager?.undoActionName ?? "-"
    let after = clips.map { master(document, $0) }
    let x = sent.first?[1][0] ?? -1
    let onCurve = abs((sent.first?[1][1] ?? -1) - CurveTable.value(before, at: x)) < 1e-12
    document.undoManager?.undo()
    settle()
    let undone = clips.map { master(document, $0) }
    check(
        "P1 a press off the points adds ONE point on the curve at the press's x: one live "
            + "gesture \"Curves\" sending {curves: {master: [4 points]}} to both clips (the "
            + "sections run \(order))",
        begins == 1 && ended == ["Curves"] && updates.count == 1 && sent.count == 1
            && sent[0].count == 4 && abs(x - 0.25) < 0.01 && onCurve && name == "Curves"
            && after.allSatisfy { pairs($0) == sent[0] } && undone == start
            && order == ["video.color", "video.wheels", "video.curves", "video.look"],
        "begins \(begins), ended \(ended), updates \(updates.map { $0.map(\.json) }), undo name "
            + "\(name), after \(after.map(pairs)), undone \(undone.map(pairs)), sections \(ids)")
}

// MARK: - P2 a drag is one step, held between its neighbours and in 0…1

do {
    reset()
    editor.state.clear()
    let middle = editor.screen(master(document, clips[0])[1])
    editor.press(at: middle)
    editor.drag(to: NSPoint(x: middle.x + 60, y: middle.y + 30), fine: false)
    editor.drag(to: NSPoint(x: middle.x + 400, y: middle.y + 400), fine: false)
    editor.release()
    settle()
    let held = master(document, clips[0])
    let name = document.undoManager?.undoActionName ?? "-"
    let steps = updates.count
    let gestures = begins
    document.undoManager?.undo()
    settle()
    let undone = clips.map { master(document, $0) }
    // An end point dragged out of the square stays at its corner.
    reset()
    editor.state.clear()
    editor.press(at: editor.screen(CurvePoint(x: 0, y: 0)))
    editor.drag(to: NSPoint(x: -200, y: -200), fine: false)
    editor.release()
    settle()
    let corner = master(document, clips[0])
    let cornerSteps = updates.count
    check(
        "P2 a drag is ONE step \"Curves\" (\(steps) updates), the point held 0.001 inside its "
            + "right neighbour's x and at y 1, and an end point dragged off the square stays "
            + "at (0, 0)",
        gestures == 1 && held.count == 3
            && abs(held[1].x - (1 - CurveEditorView.minGap)) < 1e-12 && held[1].y == 1
            && name == "Curves" && steps >= 1 && undone == start && corner == start[0]
            && cornerSteps == 0,
        "held \(pairs(held)), undo name \(name), steps \(steps), undone \(undone.map(pairs)), "
            + "corner \(pairs(corner)), corner writes \(cornerSteps)")
}

// MARK: - P3 ⌫ and a double-click delete, one step each; never below two

do {
    reset()
    editor.state.clear()
    let middle = editor.screen(master(document, clips[0])[1])
    editor.press(at: middle)
    editor.release()
    let typed = editor.key(backspace)
    settle()
    let afterKey = clips.map { master(document, $0) }
    let keyEdits = edits.map(\.0)
    document.undoManager?.undo()
    settle()
    edits.removeAll()
    editor.press(at: middle, clickCount: 1)
    editor.release()
    editor.press(at: middle, clickCount: 2)
    settle()
    let afterDouble = clips.map { master(document, $0) }
    let doubleEdits = edits.map(\.0)
    document.undoManager?.undo()
    settle()
    // Two points left: nothing.
    edits.removeAll()
    editor.state.clear()
    editor.state.channel = .red
    pane.refresh()
    editor.press(at: editor.screen(CurvePoint(x: 1, y: 1)))
    editor.release()
    _ = editor.key(backspace)
    editor.press(at: editor.screen(CurvePoint(x: 0, y: 0)), clickCount: 2)
    settle()
    let twoEdits = edits.count
    editor.state.clear()
    editor.state.channel = .master
    pane.refresh()
    check(
        "P3 ⌫ on a selected point and a double-click on one each delete it in ONE step "
            + "\"Curves\"; a 2-point curve deletes nothing",
        typed && keyEdits == ["Curves"] && afterKey.allSatisfy(ColorCurves.isIdentity)
            && doubleEdits == ["Curves"] && afterDouble.allSatisfy(ColorCurves.isIdentity)
            && twoEdits == 0 && clips.map { master(document, $0) } == start,
        "key \(typed) \(keyEdits) → \(afterKey.map(pairs)); double \(doubleEdits) → "
            + "\(afterDouble.map(pairs)); at two points \(twoEdits) edits")
}

// MARK: - P4 the arrows nudge, one step each

do {
    reset()
    editor.state.clear()
    let middle = editor.screen(master(document, clips[0])[1])
    editor.press(at: middle)
    editor.release()
    let upped = editor.key(up)
    settle()
    let first = master(document, clips[0])[1]
    let shifted = editor.key(shiftRight)
    settle()
    let second = master(document, clips[0])[1]
    let names = edits.map(\.0)
    document.undoManager?.undo()
    document.undoManager?.undo()
    settle()
    check(
        "P4 ↑ moves the selected point +0.01 and ⇧→ +0.1, one step \"Curves\" each "
            + "(\(first.x), \(first.y)) → (\(second.x), \(second.y))",
        upped && shifted && names == ["Curves", "Curves"] && first.x == 0.5
            && first.y == start[0][1].y + 0.01 && second.x == 0.5 + 0.1 && second.y == first.y
            && clips.map { master(document, $0) } == start,
        "names \(names), first \(first), second \(second), undone "
            + "\(clips.map { pairs(master(document, $0)) })")
}

// MARK: - P11 an identity channel: a click writes nothing, the point waits on y = x

do {
    reset()
    editor.state.clear()
    editor.state.channel = .green
    pane.refresh()
    let canUndo = document.undoManager?.canUndo ?? false
    let undoName = document.undoManager?.undoActionName ?? "-"
    editor.press(at: editor.screen(CurvePoint(x: 0.3, y: 0.7)))
    editor.release()
    settle()
    let quiet = updates.isEmpty && edits.isEmpty
        && (document.undoManager?.canUndo ?? false) == canUndo
        && (document.undoManager?.undoActionName ?? "-") == undoName
    let waiting = editor.points
    let selected = editor.state.selected
    let x = waiting.count == 3 ? waiting[1].x : -1
    let exact = waiting.count == 3 && waiting[1].y == waiting[1].x
    let upped = editor.key(up)
    settle()
    let sent = edits.count == 1 ? shape(edits[0].1, .green) : nil
    let stored = master(document, clips[0], .green)
    let still = editor.state.selected
    document.undoManager?.undo()
    settle()
    editor.state.clear()
    editor.state.channel = .master
    pane.refresh()
    check(
        "P11 on an identity channel a press and release writes nothing, the added point's y "
            + "is its x bit for bit (x \(x)) and stays selected, and ↑ then writes "
            + "[[0,0],[x, x + 0.01],[1,1]] in one step",
        quiet && exact && selected == 1 && upped && edits.count == 1
            && edits.first?.0 == "Curves"
            && sent == [[0, 0], [x, x + 0.01], [1, 1]] && pairs(stored) == sent! && still == 1,
        "quiet \(quiet), points \(pairs(waiting)), selected \(String(describing: selected)), "
            + "sent \(String(describing: sent)), stored \(pairs(stored)), after "
            + "\(String(describing: still))")
}

// MARK: - P10 where a write lands inside an action, and Reset there

func opsJSON(_ ops: [ReelOp]) -> [[String: Any]] { ops.map(parsed) }

do {
    let a = clips[0]
    let binding = inspector.binding
    func setup(_ ops: [ReelOp]) { document.applyEdit("Setup", ops); settle() }
    setup([.setVideo(clips: [a], patch: VideoPatch(curves: .reset))])
    setup([.addAction(clip: a, at: 0, duration: ReelTime.perSecond)])
    let action = document.project.snapshot.clips.first { $0.id == a }?.actions.first?.id ?? 0
    let three = pts([[0, 0], [0.5, 0.7], [1, 1]])
    setup([.setActionEnd(clip: a, action: action,
                         patch: ActionPatch(video: VideoPatch(curves: .channel(.master, three))))])
    document.selection = [a]
    document.selectedAction = action
    settle()
    func where_(_ channel: CurveChannel, _ list: [CurvePoint]) -> String {
        let made = opsJSON(binding.ops(video: VideoPatch(curves: .channel(channel, list))))
        return made.map { $0["op"] as? String ?? "?" }.joined(separator: "+")
    }
    let four = pts([[0, 0], [0.3, 0.4], [0.5, 0.7], [1, 1]])
    let a1 = where_(.master, four)
    let a2 = where_(.master, pts([[0, 0], [0.5, 0.9], [1, 1]]))
    let a3 = where_(.master, ColorCurves.identityCurve)
    let a4 = where_(.red, pts([[0, 0], [0.5, 0.6], [1, 1]]))
    let resetA = opsJSON(binding.curvesReset(CurveChannel.allCases))
    let wantA: [String: Any] = ["video": ["curves": ["master": [[0, 0], [1, 1]]]]]
    let gotA = resetA.count == 1 && resetA[0]["op"] as? String == "set_action_end"
        && (resetA[0]["patch"] as? NSDictionary) == (wantA as NSDictionary)
    // Scenario B: the curve on the base only.
    setup([.setActionEndRaw(clip: a, action: action, patch: ["video": ["curves": NSNull()]])])
    setup([.setVideo(clips: [a], patch: VideoPatch(curves: .channel(.red, three)))])
    document.selectedAction = action
    settle()
    let resetB = opsJSON(binding.curvesReset(CurveChannel.allCases))
    let wantB: [String: Any] = ["video": ["curves": ["red": [[0, 0], [1, 1]]]]]
    let gotB = resetB.count == 1 && resetB[0]["op"] as? String == "set_action_end"
        && (resetB[0]["patch"] as? NSDictionary) == (wantB as NSDictionary)
    // All four the identity: nothing.
    setup([.setVideo(clips: [a], patch: VideoPatch(curves: .reset))])
    document.selectedAction = action
    settle()
    let resetNone = binding.curvesReset(CurveChannel.allCases)
    check(
        "P10 inside an action a count change between two curves lands on the base, the same "
            + "count, an identity new list or an identity edited one on the end; Reset writes "
            + "the identity curve (not null) to the end for exactly the non-identity channels "
            + "(A: end-only master, B: base-only red) and nothing when all four are identity",
        a1 == "set_video" && a2 == "set_action_end" && a3 == "set_action_end"
            && a4 == "set_action_end" && gotA && gotB && resetNone.isEmpty,
        "4 points \(a1), same count \(a2), identity new \(a3), identity edited \(a4); reset A "
            + "\(resetA), B \(resetB), none \(resetNone.map(\.json))")
    document.selectedAction = nil
}

// MARK: - P9 the Delete item is dead while the plot holds a point

do {
    guard let other = open() else {
        check("P9 a second copy of project P opens", false)
        finish()
    }
    other.selection = [clips[0]]
    NSDocumentController.shared.addDocument(other)
    other.makeWindowControllers()
    other.showWindows()
    spin(1.5)
    if let window = other.windowControllers.first?.window,
       let controller = window.contentViewController as? EditorViewController,
       let content = window.contentView
    {
        let state = CurveEditorState()
        let plot = CurveEditorView(
            state: state, read: { _ in pts([[0, 0], [0.5, 0.6], [1, 1]]) }, start: { _ in nil },
            write: { _ in }, begin: {}, end: {}, commit: { _ in })
        plot.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        content.addSubview(plot)
        let action = #selector(EditorViewController.deleteClips(_:))
        let before = controller.validateTimelineAction(action)
        plot.press(at: plot.screen(CurvePoint(x: 0.5, y: 0.6)))
        plot.release()
        let holding = window.firstResponder === plot && plot.holdsDeleteKey
        let during = controller.validateTimelineAction(action)
        _ = plot.key(escape)
        let after = controller.validateTimelineAction(action)
        check(
            "P9 Delete is enabled with a clip selected, disabled while the plot holds a "
                + "selected point, and enabled again after Esc",
            before == true && holding && during == false && after == true
                && state.selected == nil && window.firstResponder !== plot,
            "before \(String(describing: before)), holding \(holding), during "
                + "\(String(describing: during)), after \(String(describing: after))")
        plot.removeFromSuperview()
        other.close()
    } else {
        check("P9 the editor window opens", false)
    }
}

finish()
