// Issue batch B25 (#85, spec §11 CI-16) — a selected clip's obscure regions
// drawn and dragged on the canvas, and Esc cancelling any canvas drag; the
// probe (`obscure_handles_probe.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line, `-D REELCUT_DEV_TOOLS`
// included — with the app's `Compositor.metal` built beside it. It calls ONLY
// what HEAD0 (ffae505) already had — the grips are found from the regions'
// own boxes through `CanvasLayerBox.canvasPoint(source:)` and `canvasToView`,
// never through the new code — so the proof's `--baseline` builds the same
// source over the unfixed tree, where the fixed rows fail.
//
//   obscure_handles_probe <request.json>
//
// `request.json` names four packages (clip 2: an 800 × 450 grey rectangle,
// video x 120, y −60, scale 0.6, rotation 30, crop l 40 b 30):
//   regions  R0 (rect (−150, −60) 300 × 180) and R1 (ellipse (180, 90)
//            200 × 140); played at 1 s
//   action   the same, plus action 3 at 2–4 s ending `{video: {x: 200}}`;
//            played at 3 s with the action selected
//   short    `action` with the end `{video: {obscure: [R0]}}` instead
//   cover    one rect region (0, 0) 760 × 420 — the cropped rect itself
// Every row opens its own editor in the app's window (content 1600 × 1000)
// and closes it. Gestures go through `beginGesture` / `continueGesture` /
// `endGesture` at view points; Esc is a keyCode-53 `NSEvent` through
// `handleKey`. The answer is ONE line on stdout, `ANSWER {"rows": [...]}`,
// each row an ID, ok and detail.
import AppKit

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
AgentLane.prepareAtLaunch()

let request = (try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))) as? [String: Any]
    ?? [:]
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

var rows: [[String: Any]] = []
func row(_ id: String, _ ok: Bool, _ detail: String) {
    rows.append(["id": id, "ok": ok, "detail": String(detail.prefix(1500))])
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

let SEC = Double(ReelTime.perSecond)
let clipID: UInt32 = 2
let theta = 30.0 * Double.pi / 180
let videoScale = 0.6
let tolerance = 0.01

func f(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "nil" }
func f(_ point: CGPoint) -> String { "(\(f(Double(point.x))), \(f(Double(point.y))))" }

// MARK: - The editor

struct Editor {
    let document: ProjectDocument
    let window: NSWindow
    let controller: EditorViewController
    let canvas: PreviewCanvasView
    let fixture: String

    var box: CanvasLayerBox? { canvas.box(for: clipID) }
    var json: String { document.editedProject.json }
}

func open(_ key: String, playhead: Double, action: UInt32? = nil) -> (Editor?, String) {
    guard let path = request[key] as? String else { return (nil, "\(key): not named") }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        return (nil, "\(key): \(error)")
    }
    document.selection = [clipID]
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.0)
    guard let window = document.windowControllers.first?.window,
          let controller = window.contentViewController as? EditorViewController
    else { return (nil, "\(key): no editor window") }
    window.setContentSize(NSSize(width: 1600, height: 1000))
    spin(0.5)
    controller.setPlayhead(Ticks(playhead * SEC))
    if let action { document.selectAction(action) }
    controller.viewStateDidChange()
    spin(0.5)
    guard let canvas = controller.previewCanvas, canvas.canvasFrame.width > 2 else {
        return (nil, "\(key): no canvas")
    }
    canvas.overlay.needsDisplay = true
    spin(0.2)
    return (Editor(document: document, window: window, controller: controller, canvas: canvas,
                   fixture: document.editedProject.json), "")
}

func close(_ editor: Editor) {
    editor.window.orderOut(nil)
    editor.document.close()
    spin(0.3)
}

/// The view point of a source point on `box`.
func view(_ editor: Editor, _ box: CanvasLayerBox, _ source: CGPoint) -> CGPoint {
    editor.canvas.canvasToView(box.canvasPoint(source: source))
}

/// Entry `i` of the list drawn on `box`; a stand-in far off the layer when
/// there is none, so a missing entry fails its row instead of the probe.
func region(_ box: CanvasLayerBox, _ i: Int) -> ObscureProps {
    let regions = box.video.obscure
    return regions.indices.contains(i) ? regions[i] : ObscureProps(x: 1e6, y: 1e6)
}

func centre(_ region: ObscureProps) -> CGPoint { CGPoint(x: region.x, y: region.y) }

func handle(_ h: CanvasHandle, _ region: ObscureProps) -> CGPoint { h.point(in: region.box) }

func offset(_ p: CGPoint, _ d: CGVector, _ fraction: CGFloat = 1) -> CGPoint {
    CGPoint(x: p.x + d.dx * fraction, y: p.y + d.dy * fraction)
}

/// A press at `from`, `ticks` drags to `from + by`, then (when `release`) the
/// mouse-up there.
func drag(
    _ editor: Editor, from: CGPoint, by: CGVector, ticks: Int,
    flags: NSEvent.ModifierFlags = [], release: Bool = true
) {
    editor.canvas.beginGesture(at: from, flags: flags, clicks: 1)
    for tick in 1...ticks {
        editor.canvas.continueGesture(
            at: offset(from, by, CGFloat(tick) / CGFloat(ticks)), flags: flags)
    }
    if release { editor.canvas.endGesture(at: offset(from, by), flags: flags) }
    spin(0.2)
}

/// `ds = R(−θ)(dv / k) / s` — the travel in source pixels a view-point travel
/// `dv` is, computed from the fixture's rotation and scale and the canvas's
/// points per pixel, never through the code under test.
struct Travel {
    let x: Double
    let y: Double
}

func travel(_ editor: Editor, _ dv: CGVector) -> Travel {
    let k = Double(editor.canvas.canvasScale)
    let a = Double(dv.dx) / k
    let b = Double(dv.dy) / k
    return Travel(
        x: (a * cos(theta) + b * sin(theta)) / videoScale,
        y: (-a * sin(theta) + b * cos(theta)) / videoScale)
}

func esc(_ editor: Editor) -> Bool {
    guard let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: editor.window.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)
    else { return false }
    return editor.canvas.handleKey(event)
}

// MARK: - JSON

func parse(_ json: String) -> NSMutableDictionary {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.mutableContainers]))
        as? NSMutableDictionary ?? NSMutableDictionary()
}

func clip(_ project: NSMutableDictionary) -> NSMutableDictionary? {
    (project["clips"] as? [NSMutableDictionary])?.first {
        ($0["id"] as? NSNumber)?.uint32Value == clipID
    }
}

func video(_ project: NSMutableDictionary) -> NSMutableDictionary? {
    clip(project)?["video"] as? NSMutableDictionary
}

func endVideo(_ project: NSMutableDictionary) -> NSMutableDictionary? {
    let actions = clip(project)?["actions"] as? [NSMutableDictionary]
    return (actions?.first?["end"] as? NSMutableDictionary)?["video"] as? NSMutableDictionary
}

func list(_ group: NSMutableDictionary?) -> [NSDictionary]? {
    group?["obscure"] as? [NSDictionary]
}

func num(_ entry: NSDictionary?, _ key: String) -> Double? {
    (entry?[key] as? NSNumber)?.doubleValue
}

func near(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

/// `after` with clip 2's base list (and, when `end`, its first action's end
/// list) put back as `before` had them, compared with `before`: every other
/// key of the project unchanged.
func restEqual(_ before: String, _ after: String, end: Bool = false) -> Bool {
    let old = parse(before)
    let new = parse(after)
    guard let oldVideo = video(old), let newVideo = video(new) else { return false }
    newVideo["obscure"] = oldVideo["obscure"]
    if end {
        guard let newEnd = endVideo(new) else { return false }
        if let oldEnd = endVideo(old), let kept = oldEnd["obscure"] {
            newEnd["obscure"] = kept
        } else {
            newEnd.removeObject(forKey: "obscure")
        }
    }
    return new.isEqual(old)
}

/// The fields other than the centre and size are the fixture's.
func sameKind(_ a: NSDictionary?, _ b: NSDictionary?) -> Bool {
    guard let a, let b else { return false }
    return ["shape", "feather", "kind", "amount"].allSatisfy {
        (a[$0] as? NSObject)?.isEqual(b[$0]) == true
    }
}

func describe(_ entry: NSDictionary?) -> String {
    guard let entry else { return "nil" }
    return "(\(f(num(entry, "x"))), \(f(num(entry, "y")))) \(f(num(entry, "width"))) × "
        + "\(f(num(entry, "height")))"
}

/// ONE undo step: named `name`, no live edit after the release, one undo
/// back to the fixture's JSON exactly, and nothing more to undo.
func oneStep(_ editor: Editor, _ name: String) -> (Bool, String) {
    let manager = editor.document.undoManager
    let got = manager?.undoActionName ?? ""
    let live = editor.document.isLiveEditing
    manager?.undo()
    spin(0.2)
    let restored = editor.json == editor.fixture
    let more = manager?.canUndo ?? true
    return (got == name && !live && restored && !more,
            "step \"\(got)\", live after release \(live), one undo restores the fixture "
            + "\(restored), canUndo after \(more)")
}

// MARK: - Pixels

/// The overlay's own drawing, captured.
func capture(_ editor: Editor) -> NSBitmapImageRep? {
    let overlay = editor.canvas.overlay
    overlay.needsDisplay = true
    spin(0.1)
    guard let rep = overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds) else { return nil }
    overlay.cacheDisplay(in: overlay.bounds, to: rep)
    return rep
}

/// The most alpha within ±1 device pixel of `point` (view space; the overlay
/// is flipped, so row 0 is its top).
func alpha(_ rep: NSBitmapImageRep, _ bounds: CGRect, _ point: CGPoint) -> CGFloat {
    let scale = CGFloat(rep.pixelsWide) / max(bounds.width, 1)
    let px = Int((point.x * scale).rounded())
    let py = Int((point.y * scale).rounded())
    var most: CGFloat = 0
    for y in (py - 1)...(py + 1) {
        for x in (px - 1)...(px + 1) where x >= 0 && y >= 0 && x < rep.pixelsWide
            && y < rep.pixelsHigh {
            most = max(most, rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
        }
    }
    return most
}

/// Each edge's ¼ and ¾ points of `region`, in view space.
func edgePoints(_ editor: Editor, _ box: CanvasLayerBox, _ region: ObscureProps) -> [CGPoint] {
    let quad = box.canvasQuad(ofSource: region.box).map { editor.canvas.canvasToView($0) }
    var points: [CGPoint] = []
    for i in 0..<quad.count {
        let a = quad[i]
        let b = quad[(i + 1) % quad.count]
        for t in [0.25, 0.75] as [CGFloat] {
            points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
    }
    return points
}

func inked(_ rep: NSBitmapImageRep, _ editor: Editor, _ points: [CGPoint]) -> [CGFloat] {
    points.map { alpha(rep, editor.canvas.overlay.bounds, $0) }
}

func alphas(_ values: [CGFloat]) -> String {
    "[" + values.map { String(format: "%.2f", $0) }.joined(separator: " ") + "]"
}

// MARK: - F0 (control) every package, its box and its lists

do {
    var ok = true
    var details: [String] = []
    for (key, playhead, action) in [("regions", 1.0, nil), ("action", 3.0, UInt32(3)),
                                    ("short", 3.0, UInt32(3)), ("cover", 1.0, nil)]
        as [(String, Double, UInt32?)] {
        let (opened, why) = open(key, playhead: playhead, action: action)
        guard let editor = opened, let box = editor.box else {
            ok = false
            details.append(why.isEmpty ? "\(key): no box" : why)
            continue
        }
        let regions = box.video.obscure
        let lengths = regions.flatMap { region -> [CGFloat] in
            let quad = box.canvasQuad(ofSource: region.box).map { editor.canvas.canvasToView($0) }
            return (0..<quad.count).map { i in
                let a = quad[i]
                let b = quad[(i + 1) % quad.count]
                return hypot(b.x - a.x, b.y - a.y)
            }
        }
        let project = parse(editor.json)
        let base = list(video(project))?.count ?? -1
        let end = list(endVideo(project))?.count
        var good = abs(box.rotation - 30) < 1e-9 && abs(box.video.scale - videoScale) < 1e-9
            && !lengths.isEmpty && lengths.allSatisfy { $0 >= 24 }
        var extra = ""
        switch key {
        case "regions":
            good = good && base == 2 && regions.count == 2 && editor.canvas.editTarget == .base
        case "action":
            good = good && base == 2 && end == nil && regions.count == 2
                && editor.canvas.editTarget.selected?.action == 3
        case "short":
            good = good && base == 2 && end == 1 && regions.count == 2
                && editor.canvas.editTarget.selected?.action == 3
        default:
            if let region = regions.first {
                let grip = view(editor, box, handle(.topRight, region))
                let layer = editor.canvas.canvasToView(box.handlePoint(.topRight))
                let gap = max(abs(grip.x - layer.x), abs(grip.y - layer.y))
                good = good && base == 1 && gap <= 0.5
                extra = String(format: "; topRight grip %.3f pt from the layer's handle", gap)
            } else {
                good = false
            }
        }
        ok = ok && good
        details.append(
            "\(key): rotation \(f(box.rotation)), scale \(f(box.video.scale)), drawn "
                + "\(regions.count), base \(base), end \(end.map(String.init) ?? "none"), "
                + "target \(editor.canvas.editTarget.selected.map { "action \($0.action)" } ?? "base"), "
                + "shortest edge \(String(format: "%.1f", Double(lengths.min() ?? 0))) pt at "
                + "\(String(format: "%.4f", Double(editor.canvas.canvasScale))) pt/px, window "
                + "\(editor.window.contentLayoutRect.size)"
                + extra)
        close(editor)
    }
    row("F0", ok, details.joined(separator: "; "))
}

// MARK: - D0 / D1 the outlines are drawn only while the clip is selected

do {
    let (opened, why) = open("regions", playhead: 1)
    if let editor = opened, let box = editor.box {
        let regions = box.video.obscure
        let points = regions.flatMap { edgePoints(editor, box, $0) }
            + regions.map { view(editor, box, centre($0)) }
        let selected = capture(editor).map { inked($0, editor, points) } ?? []
        editor.document.selection = []
        editor.controller.viewStateDidChange()
        spin(0.3)
        let cleared = capture(editor).map { inked($0, editor, points) } ?? []
        row("D0", cleared.count == points.count && cleared.allSatisfy { $0 == 0 },
            "nothing selected: the most alpha within ±1 px of \(points.count) points "
                + alphas(cleared))
        row("D1", selected.count == points.count && selected.allSatisfy { $0 > 0 },
            "clip selected: the most alpha within ±1 px of each region edge's ¼ and ¾ points "
                + "and each centre " + alphas(selected))
        close(editor)
    } else {
        row("D0", false, why)
        row("D1", false, why)
    }
}

// MARK: - M1 M2 M3 a move, a resize and a ⌥ resize

/// Opens `regions`, drags, and hands the before and after to `judge`.
func regionRow(
    _ id: String, key: String = "regions", playhead: Double = 1, action: UInt32? = nil,
    press: (Editor, CanvasLayerBox) -> CGPoint, by: CGVector, ticks: Int,
    flags: NSEvent.ModifierFlags = [],
    judge: (Editor, CanvasLayerBox, Travel) -> (Bool, String)
) {
    let (opened, why) = open(key, playhead: playhead, action: action)
    guard let editor = opened, let box = editor.box else {
        row(id, false, why)
        return
    }
    let at = press(editor, box)
    let hit = editor.canvas.hit(at: at)
    drag(editor, from: at, by: by, ticks: ticks, flags: flags)
    let (ok, detail) = judge(editor, box, travel(editor, by))
    let ds = travel(editor, by)
    row(id, ok, "press \(f(at)) hit \(hit); ds (\(f(ds.x)), \(f(ds.y))); " + detail)
    close(editor)
}

regionRow(
    "M1", press: { e, b in view(e, b, centre(region(b, 0))) },
    by: CGVector(dx: 30, dy: 20), ticks: 3
) { editor, _, ds in
    let before = parse(editor.fixture)
    let after = parse(editor.json)
    let r0 = list(video(after))?.first
    let old = list(video(before))?.first
    let moved = near(num(r0, "x"), -150 + ds.x) && near(num(r0, "y"), -60 + ds.y)
        && near(num(r0, "width"), 300) && near(num(r0, "height"), 180)
    let kind = sameKind(r0, old)
    let rest = list(video(after))?.count == 2
        && list(video(after))?[1].isEqual(list(video(before))?[1]) == true
        && restEqual(editor.fixture, editor.json)
    let (step, stepDetail) = oneStep(editor, "Move Region")
    return (moved && kind && rest && step,
            "R0 \(describe(old)) → \(describe(r0)); moved by ds \(moved), its other fields "
            + "kept \(kind), R1 and the rest unchanged \(rest); " + stepDetail)
}

regionRow(
    "M2", press: { e, b in view(e, b, handle(.bottomRight, region(b, 1))) },
    by: CGVector(dx: 24, dy: 12), ticks: 3
) { editor, _, ds in
    let after = parse(editor.json)
    let r1 = list(video(after))?.dropFirst().first
    let x = num(r1, "x") ?? .nan
    let y = num(r1, "y") ?? .nan
    let w = num(r1, "width") ?? .nan
    let h = num(r1, "height") ?? .nan
    let topLeft = near(x - w / 2, 80) && near(y - h / 2, 20)
    let bottomRight = near(x + w / 2, 280 + ds.x) && near(y + h / 2, 160 + ds.y)
    let rest = restEqual(editor.fixture, editor.json)
    let r0 = list(video(after))?.first?.isEqual(list(video(parse(editor.fixture)))?.first)
        == true
    let (step, stepDetail) = oneStep(editor, "Resize Region")
    return (topLeft && bottomRight && rest && r0 && step,
            "R1 → \(describe(r1)); top-left kept \(topLeft), bottom-right moved by ds "
            + "\(bottomRight), R0 and the rest unchanged \(rest && r0); " + stepDetail)
}

regionRow(
    "M3", press: { e, b in view(e, b, handle(.right, region(b, 0))) },
    by: CGVector(dx: 20, dy: 0), ticks: 2, flags: [.option]
) { editor, _, ds in
    let after = parse(editor.json)
    let r0 = list(video(after))?.first
    let ok = near(num(r0, "x"), -150) && near(num(r0, "y"), -60)
        && near(num(r0, "height"), 180) && near(num(r0, "width"), 300 + 2 * ds.x)
    let rest = restEqual(editor.fixture, editor.json)
    let (step, stepDetail) = oneStep(editor, "Resize Region")
    return (ok && rest && step,
            "R0 → \(describe(r0)); centre and height kept, width 300 + 2 × ds.x "
            + "(\(f(300 + 2 * ds.x))) \(ok), the rest unchanged \(rest); " + stepDetail)
}

// MARK: - X0 X1 Esc mid-drag restores the press's state with no step

func escRow(
    _ id: String, press: (Editor, CanvasLayerBox) -> CGPoint, by: CGVector, ticks: Int,
    moved: (Editor) -> (Bool, String)
) {
    let (opened, why) = open("regions", playhead: 1)
    guard let editor = opened, let box = editor.box else {
        row(id, false, why)
        return
    }
    let at = press(editor, box)
    let hit = editor.canvas.hit(at: at)
    drag(editor, from: at, by: by, ticks: ticks, release: false)
    let (changed, mid) = moved(editor)
    let liveMid = editor.document.isLiveEditing
    let took = esc(editor)
    spin(0.2)
    let restored = editor.json == editor.fixture
    let more = editor.document.undoManager?.canUndo ?? true
    let live = editor.document.isLiveEditing
    let session = editor.canvas.moving != nil
    let name = editor.document.undoManager?.undoActionName ?? ""
    editor.canvas.endGesture(at: offset(at, by), flags: [])
    spin(0.1)
    row(id, changed && liveMid && took && restored && !more && !live && !session,
        "press \(f(at)) hit \(hit); mid-drag \(mid), live \(liveMid); Esc taken \(took): "
            + "the fixture's JSON \(restored), canUndo \(more) (\"\(name)\"), live \(live), "
            + "moving \(session)")
    close(editor)
}

escRow(
    "X0", press: { e, b in view(e, b, CGPoint(x: -300, y: 150)) },
    by: CGVector(dx: 20, dy: 0), ticks: 2
) { editor in
    let x = num(video(parse(editor.json)), "x")
    return (x != nil && !near(x, 120), "x 120 → \(f(x))")
}

escRow(
    "X1", press: { e, b in view(e, b, centre(region(b, 1))) },
    by: CGVector(dx: 15, dy: 0), ticks: 2
) { editor in
    let r1 = list(video(parse(editor.document.project.json)))?.dropFirst().first
    let x = num(r1, "x")
    return (x != nil && !near(x, 180), "R1 x 180 → \(f(x))")
}

// MARK: - T1 with the action selected the drag writes its END list

regionRow(
    "T1", key: "action", playhead: 3, action: 3,
    press: { e, b in view(e, b, centre(region(b, 0))) },
    by: CGVector(dx: 30, dy: 20), ticks: 3
) { editor, _, ds in
    let before = parse(editor.fixture)
    let after = parse(editor.json)
    let end = list(endVideo(after))
    let r0 = end?.first
    let moved = end?.count == 2 && near(num(r0, "x"), -150 + ds.x)
        && near(num(r0, "y"), -60 + ds.y) && near(num(r0, "width"), 300)
        && near(num(r0, "height"), 180) && sameKind(r0, list(video(before))?.first)
        && end?[1].isEqual(list(video(before))?[1]) == true
    let base = (list(video(after)) as NSArray?)?.isEqual(list(video(before))) == true
    let rest = restEqual(editor.fixture, editor.json, end: true)
    let (step, stepDetail) = oneStep(editor, "Move Region")
    return (moved && base && rest && step,
            "end list \(end.map { $0.map(describe) } ?? []): [R0 + ds, R1] \(moved); base list "
            + "unchanged \(base), the rest unchanged \(rest); " + stepDetail)
}

// MARK: - G1 a shorter end list: outlines, no grips, and the press moves the clip

do {
    let (opened, why) = open("short", playhead: 3, action: 3)
    if let editor = opened, let box = editor.box {
        let regions = box.video.obscure
        let edges = regions.flatMap { edgePoints(editor, box, $0) }
        let centres = regions.map { view(editor, box, centre($0)) }
        let rep = capture(editor)
        let edgeInk = rep.map { inked($0, editor, edges) } ?? []
        let centreInk = rep.map { inked($0, editor, centres) } ?? []
        let drawn = edgeInk.count == edges.count && edgeInk.allSatisfy { $0 > 0 }
            && centreInk.count == centres.count && centreInk.allSatisfy { $0 == 0 }
        let at = centres.first ?? .zero
        let hit = editor.canvas.hit(at: at)
        drag(editor, from: at, by: CGVector(dx: 20, dy: 0), ticks: 2)
        let before = parse(editor.fixture)
        let after = parse(editor.json)
        let base = (list(video(after)) as NSArray?)?.isEqual(list(video(before))) == true
        let end = (list(endVideo(after)) as NSArray?)?.isEqual(list(endVideo(before))) == true
        let (step, stepDetail) = oneStep(editor, "Move")
        row("G1", drawn && base && end && step,
            "edges \(alphas(edgeInk)), centres \(alphas(centreInk)); press \(f(at)) hit \(hit): "
                + "base list unchanged \(base), end list unchanged \(end); " + stepDetail)
        close(editor)
    } else {
        row("G1", false, why)
    }
}

// MARK: - C1 C2 (controls) the body still moves; the layer's handle still scales

regionRow(
    "C1", press: { e, b in view(e, b, CGPoint(x: -300, y: 150)) },
    by: CGVector(dx: 20, dy: 0), ticks: 2
) { editor, _, _ in
    let after = parse(editor.json)
    let x = num(video(after), "x")
    let kept = (list(video(after)) as NSArray?)?.isEqual(list(video(parse(editor.fixture))))
        == true
    let (step, stepDetail) = oneStep(editor, "Move")
    return (x != nil && !near(x, 120) && kept && step,
            "x 120 → \(f(x)), list unchanged \(kept); " + stepDetail)
}

do {
    let (opened, why) = open("cover", playhead: 1)
    if let editor = opened, let box = editor.box {
        let at = editor.canvas.canvasToView(box.handlePoint(.topRight))
        let hit = editor.canvas.hit(at: at)
        let by = CGVector(dx: 12, dy: -8)
        editor.canvas.beginGesture(at: at, flags: [], clicks: 1)
        let scaling = editor.canvas.scaling != nil
        editor.canvas.continueGesture(at: offset(at, by, 0.5), flags: [])
        editor.canvas.continueGesture(at: offset(at, by), flags: [])
        editor.canvas.endGesture(at: offset(at, by), flags: [])
        spin(0.2)
        let name = editor.document.undoManager?.undoActionName ?? ""
        let kept = (list(video(parse(editor.json))) as NSArray?)?
            .isEqual(list(video(parse(editor.fixture)))) == true
        row("C2", scaling && name == "Scale" && kept,
            "press \(f(at)) hit \(hit): scaling \(scaling); step \"\(name)\", list unchanged \(kept)")
        close(editor)
    } else {
        row("C2", false, why)
    }
}

// MARK: - L1 a get_project submitted mid-drag waits for the release (AI-12)

final class Pending {
    private let lock = NSLock()
    private var stored: String?
    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
    func set(_ result: String) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}

do {
    let (opened, why) = open("regions", playhead: 1)
    if let editor = opened, let box = editor.box {
        let at = view(editor, box, centre(region(box, 0)))
        let by = CGVector(dx: 30, dy: 20)
        editor.canvas.beginGesture(at: at, flags: [], clicks: 1)
        editor.canvas.continueGesture(at: offset(at, by), flags: [])
        let pending = Pending()
        AgentLane.shared.submit(
            tool: "get_project", argumentsJSON: "{}", document: editor.document,
            askFirst: { _, reply in reply(false) }, completion: { pending.set($0) })
        spin(0.5)
        let held = pending.value
        editor.canvas.endGesture(at: offset(at, by), flags: [])
        let deadline = Date().addingTimeInterval(10)
        while pending.value == nil && Date() < deadline { spin(0.05) }
        let result = pending.value
        let envelope = result.flatMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        let text = ((envelope?["content"] as? [[String: Any]]) ?? [])
            .compactMap { $0["text"] as? String }.joined()
        let body = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        let projectJSON = (body?["project"]).flatMap {
            try? JSONSerialization.data(withJSONObject: $0)
        }.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let r0 = list(video(parse(projectJSON)))?.first
        let ds = travel(editor, by)
        let moved = near(num(r0, "x"), -150 + ds.x) && near(num(r0, "y"), -60 + ds.y)
        row("L1", held == nil && result != nil && moved,
            "answered during the 0.5 s hold \(held != nil); answered within 10 s of the release "
                + "\(result != nil); R0 in the answer \(describe(r0)), want x "
                + "\(f(-150 + ds.x)) y \(f(-60 + ds.y))")
        close(editor)
    } else {
        row("L1", false, why)
    }
}

let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
    ?? Data("{}".utf8)
print("ANSWER " + String(decoding: data, as: UTF8.self))
fflush(stdout)
exit(0)
