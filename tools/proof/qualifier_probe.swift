// Road map "grading-2", phase G2-4 — the qualifier's probe (`qualifier_proof.py`
// builds it through `swift_build.build` and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, against `libframejob_core.a`, so every row drives the app's own
// types: `QualifierSample`, `ColorQualifier.picked`, `QualifierPick.sample`
// (`Exporter.renderFrame` with `behind`), `ClipPane` and the Qualifier
// section's checkbox, strip and Reset, `InspectorBinding`'s ops, a
// `ProjectDocument`'s live trio and undo stack, `EditorViewController`'s
// `toggleShowSelection` and `syncShowSelection`, `QualifierUniforms` and
// `ClipSubTab.keyedCount`. The strip's gesture is driven through its `press`
// / `drag` / `release`, the event handlers' own bodies. Nothing private is
// widened.
//
//   qualifier_probe <request.json> <answer.json>
//
// `request.json` names `package`, a project the proof saved over MCP — HUE on
// track 1, adjustment clip A (hue {120, 40, 20}) and adjustment clip B on
// tracks 2 and 3, a red 200 × 200 rectangle in front at the centre — `ids`
// (media, adjustment, second, shape), `shader` (the tree's Compositor.metal),
// `point` and `pixel` (the HUE fixture's bytes there), and `samples`, the
// proof's own GR-13 readings of ten colours. One JSON object out: `rows`,
// each a name, ok and detail, the name starting with its K-number.
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

func finish() -> Never {
    let answer: [String: Any] = ["rows": rows]
    if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
        try? data.write(to: out)
    }
    exit(0)
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

func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

func click() -> NSEvent {
    NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}

// MARK: - K1 the reading, K2 the pick, K7 the block, K8 the badge

do {
    let samples = request["samples"] as? [[String: Any]] ?? []
    var misses: [String] = []
    for sample in samples {
        let rgb = (sample["rgb"] as? [Double]) ?? []
        let got = QualifierSample(rgb.map { $0 / 255 })
        let want = (sample["hue"] as? Double ?? -1, sample["chroma"] as? Double ?? -1,
                    sample["saturation"] as? Double ?? -1, sample["luma"] as? Double ?? -1)
        if !(near(got.hue, want.0) && near(got.chroma, want.1) && near(got.saturation, want.2)
            && near(got.luma, want.3))
        {
            misses.append("\(rgb): \(got.hue) \(got.chroma) \(got.saturation) \(got.luma) vs \(want)")
        }
    }
    let rust = QualifierSample([102.0 / 255, 26.0 / 255, 26.0 / 255])
    let dark = QualifierSample([5.0 / 255, 2.0 / 255, 2.0 / 255])
    check(
        "K1 QualifierSample of \(samples.count) colours (R, G, B, C, M, Y, grey, skin, "
            + "(102, 26, 26), (5, 2, 2)) equals the proof's GR-13 readings to 1e-9; (102, 26, "
            + "26) reads S 0.745, C 0.298 and (5, 2, 2) S′ 0",
        samples.count == 10 && misses.isEmpty && near(rust.saturation, 0.745, 5e-4)
            && near(rust.chroma, 0.298, 5e-4) && dark.saturation == 0,
        "\(misses.prefix(4)); (102,26,26) S \(rust.saturation) C \(rust.chroma); (5,2,2) "
            + "S′ \(dark.saturation)")
}

do {
    func levels(_ write: QualifierWrite<QualifierLevels>?) -> QualifierLevels? {
        if case .set(let l) = write { return l }
        return nil
    }
    func hue(_ write: QualifierWrite<QualifierHue>?) -> QualifierHue? {
        if case .set(let h) = write { return h }
        return nil
    }
    let orange = QualifierSample([1, 0.5, 0])
    let held = ColorQualifier(
        hue: QualifierHue(center: 200, width: 60, softness: 12),
        saturation: QualifierLevels(low: 0.2, high: 0.6, softness: 0.05))
    let repick = held.picked(orange)
    let kept = hue(repick.hue).map { near($0.center, 30) && $0.width == 60 && $0.softness == 12 }
        == true
        && levels(repick.saturation).map {
            near($0.high - $0.low, 0.4) && $0.softness == 0.05 && near($0.high, 1)
        } == true
        && repick.luma == nil && repick.invert == nil
    let grey = held.picked(QualifierSample([0.5, 0.5, 0.5]))
    let greyOff = grey.hue == .off
    let red = ColorQualifier.none.picked(QualifierSample([1, 0, 0]))
    let redSat = levels(red.saturation)
    let redOk = redSat.map { near($0.low, 0.7) && near($0.high, 1) && $0.softness == 0.1 } == true
        && hue(red.hue).map { near($0.center, 0) && $0.width == 30 && $0.softness == 15 } == true
        && red.luma == nil
    let luma = ColorQualifier(luma: QualifierLevels(low: 0.25, high: 0.75, softness: 0.2))
    let bright = levels(luma.picked(QualifierSample([0.9, 0.9, 0.9])).luma)
    let deep = levels(luma.picked(QualifierSample([0.02, 0.02, 0.02])).luma)
    let lumaOk = bright.map { near($0.low, 0.5) && near($0.high, 1) && $0.softness == 0.2 } == true
        && deep.map { near($0.low, 0) && near($0.high, 0.5) && $0.softness == 0.2 } == true
    // Every written level range lies inside 0…1 with low ≤ high and holds the
    // pixel, over a sweep of colours and held ranges.
    var outside: [String] = []
    var seed: UInt64 = 0x5eed_9a11
    func next() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(seed >> 11) / Double(1 << 53)
    }
    for _ in 0..<500 {
        let s = QualifierSample([next(), next(), next()])
        let low = next() * 0.9
        let held = ColorQualifier(
            saturation: next() < 0.5 ? nil : QualifierLevels(
                low: low, high: low + next() * (1 - low), softness: next()),
            luma: QualifierLevels(low: low * 0.5, high: 0.5 + low * 0.5, softness: 0.1))
        let patch = held.picked(s)
        for (value, l) in [(s.saturation, levels(patch.saturation)), (s.luma, levels(patch.luma))] {
            guard let l else { continue }
            if !(l.low >= 0 && l.high <= 1 && l.low <= l.high && l.low <= value + 1e-12
                && value <= l.high + 1e-12)
            {
                outside.append("\(l) for \(value)")
            }
        }
    }
    check(
        "K2 picked: a re-pick keeps the widths and softness (hue 60/12, saturation 0.4/0.05, "
            + "shifted to end at 1); a grey turns hue off; pure red with saturation off writes "
            + "saturation {0.7, 1, 0.1} and hue {0, 30, 15}; luma {0.25, 0.75} re-picked at "
            + "Y′ 0.9 is {0.5, 1} and at 0.02 {0, 0.5}; 500 picks write every level range "
            + "inside 0–1, low ≤ high, holding the pixel; luma off and Invert untouched",
        kept && greyOff && redOk && lumaOk && outside.isEmpty,
        "re-pick \(repick); grey \(String(describing: grey.hue)); red \(red); luma \(bright as Any) "
            + "/ \(deep as Any); outside \(outside.prefix(3))")
}

do {
    let shader = (try? String(contentsOfFile: request["shader"] as? String ?? "")) ?? ""
    var fields: [String] = []
    if let start = shader.range(of: "struct QualifierUniforms {"),
        let end = shader.range(of: "};", range: start.upperBound..<shader.endIndex)
    {
        for line in shader[start.upperBound..<end.lowerBound].split(separator: "\n") {
            let words = line.split(separator: " ")
            if words.count == 2, words[0] == "float" {
                fields.append(String(words[1].dropLast()))
            }
        }
    }
    let block = QualifierUniforms(
        ColorQualifier(hue: QualifierHue(center: 120, width: 40, softness: 20)), selection: true)
    let swift = Mirror(reflecting: block).children.compactMap(\.label)
    let neutral = QualifierUniforms(.none, selection: false)
    check(
        "K7 QualifierUniforms is 64 bytes (stride) and its sixteen fields are the shader's "
            + "struct's, in order; enabled is 1 for a range and 0 for none",
        MemoryLayout<QualifierUniforms>.stride == 64 && swift == fields && fields.count == 16
            && block.enabled == 1 && block.selection == 1 && block.hueEnabled == 1
            && block.hueCenter == 120 && neutral.enabled == 0,
        "stride \(MemoryLayout<QualifierUniforms>.stride); swift \(swift); shader \(fields)")
}

do {
    let json = #"{"video": {"qualifier": {"hue": {"center": 10}, "invert": true}}}"#
    if let end = try? JSONDecoder().decode(ActionPatch.self, from: Data(json.utf8)) {
        let color = ClipSubTab.color.keyedCount(in: end)
        let adjusted = ClipSubTab.color.keyedCount(in: end, adjustment: true)
        let picture = ClipSubTab.picture.keyedCount(in: end)
        check("K8 keyedCount for {video: {qualifier: {hue, invert}}}: Color 1, Picture 0",
              color == 1 && adjusted == 1 && picture == 0,
              "color \(color), adjustment \(adjusted), picture \(picture)")
    } else {
        check("K8 the end decodes as an ActionPatch", false, json)
    }
}

// MARK: - The project

let ids = request["ids"] as? [String: NSNumber] ?? [:]
guard let path = request["package"] as? String, let media = ids["media"]?.uint32Value,
      let first = ids["adjustment"]?.uint32Value, let second = ids["second"]?.uint32Value
else {
    for name in ["K3", "K4", "K5", "K6"] {
        check("\(name) the request names the package and its clips", false, "\(request)")
    }
    finish()
}

func open() -> ProjectDocument? {
    let document = ProjectDocument()
    do {
        try document.read(from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
        document.fileURL = URL(fileURLWithPath: path)
    } catch {
        return nil
    }
    return document
}

guard let document = open() else {
    for name in ["K3", "K4", "K5", "K6"] { check("\(name) project P opens", false) }
    finish()
}

// MARK: - K3 the pick samples the picture behind

do {
    let point = (request["point"] as? [Double]) ?? [0, 0]
    let want = ((request["pixel"] as? [Double]) ?? []).map { $0 / 255 }
    let canvas = document.project.snapshot.canvas
    let got = QualifierPick.sample(
        project: document.project, urls: document.mediaURLs(), at: ReelTime.perSecond / 2,
        clip: first, point: CGPoint(x: point[0], y: point[1]), canvas: canvas, graphics: nil)
    let ok = got.map { got in
        got.count == 3 && want.count == 3
            && zip(got, want).allSatisfy { abs($0 - $1) <= 1.0 / 255 + 1e-9 }
    } ?? false
    check(
        "K3 QualifierPick.sample at the centre (under a red rectangle in front of adjustment "
            + "clip A) answers the HUE pixel behind A ±1/255",
        ok, "got \(String(describing: got?.map { $0 * 255 })), want \(want.map { $0 * 255 })")
}

// MARK: - K4 the sections, K5 the controls

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
let pane = ClipPane(inspector: inspector)

func sections(_ clips: Set<UInt32>) -> [String] {
    document.selection = clips
    inspector.binding.invalidate()
    pane.binding.invalidate()
    pane.choose(.color)
    pane.rebuild()
    pane.refresh()
    return pane.sections.map(\.id)
}

let mediaSections = sections([media])
let adjustmentSections = sections([first])
check(
    "K4 the Color sections for an adjustment clip are [adjustment, qualifier, light, color, "
        + "wheels, curves, look]; a media clip's are unchanged [light, color, wheels, curves, look]",
    adjustmentSections == ["video.adjustment", "video.qualifier", "video.light", "video.color",
                           "video.wheels", "video.curves", "video.look"]
        && mediaSections == ["video.light", "video.color", "video.wheels", "video.curves",
                             "video.look"],
    "adjustment \(adjustmentSections); media \(mediaSections)")

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

/// The one set_video naming clip A's patch's `qualifier`, or nil.
func qualifierOf(_ ops: [ReelOp]) -> [String: Any]? {
    guard ops.count == 1 else { return nil }
    let op = parsed(ops[0])
    let named = ((op["clips"] as? [NSNumber]) ?? []).map(\.uint32Value)
    let patch = op["patch"] as? [String: Any] ?? [:]
    guard op["op"] as? String == "set_video", named == [first], Set(patch.keys) == ["qualifier"]
    else { return nil }
    return patch["qualifier"] as? [String: Any]
}

func qualifierNow() -> ColorQualifier {
    document.project.snapshot.clips.first { $0.id == first }?.videoProps.qualifier ?? .none
}

do {
    let section = pane.sections.first { $0.id == "video.qualifier" }
    let views = section.map(walk) ?? []
    let checks = views.compactMap { $0 as? OptionCheckboxControl }
    let strips = views.compactMap { $0 as? RangeStripControl }
    let hueStrip = strips.first { $0.kind == .hue }
    // Off first, through the document, so the Hue checkbox turns it ON.
    document.applyEdit(
        "Setup", [.setVideo(clips: [first], patch: VideoPatch(qualifier: .reset))])
    settle()
    reset()
    // The first checkbox in the section is Hue's (model order).
    checks.first?.mouseDown(with: click())
    settle()
    let tick = edits.count == 1 ? qualifierOf(edits[0].1) : nil
    let tickName = edits.first?.0 ?? "-"
    let tickOk = tick.map { Set($0.keys) == ["hue"] && ($0["hue"] as? [String: Any])?.isEmpty == true }
        == true && tickName == "Hue" && qualifierNow().hue == .initial
        && document.undoManager?.undoActionName == "Hue"
    // A drag on the strip's body: one live gesture "Hue", every write the whole range.
    reset()
    var dragged = false
    if let strip = hueStrip {
        strip.frame = NSRect(x: 0, y: 0, width: 172, height: RangeStripControl.height)
        let body = strip.x(of: 30)
        strip.press(at: NSPoint(x: body, y: 7), clickCount: 1)
        strip.drag(to: NSPoint(x: body + 10, y: 7), fine: false)
        strip.drag(to: NSPoint(x: body + 20, y: 7), fine: false)
        strip.release()
        dragged = true
    }
    settle()
    let whole = updates.compactMap(qualifierOf).allSatisfy { q in
        Set(q.keys) == ["hue"] && Set((q["hue"] as? [String: Any] ?? [:]).keys)
            == ["center", "width", "softness"]
    }
    let moved = qualifierNow().hue
    let stripOk = dragged && begins == 1 && ended == ["Hue"] && updates.count == 2 && whole
        && moved.map { $0.center > 30 && $0.width == 50 && $0.softness == 25 } == true
        && document.undoManager?.undoActionName == "Hue"
    // The section's Reset.
    reset()
    let header = section.map { walk($0.header) } ?? []
    let resetButton = header.compactMap { $0 as? OptionButtonControl }.first { !$0.isHidden }
    resetButton?.mouseDown(with: click())
    settle()
    let cleared = edits.count == 1 ? qualifierOf(edits[0].1) : nil
    let resetOk = edits.first?.0 == "Qualifier" && cleared.map {
        $0["hue"] is NSNull && $0["saturation"] is NSNull && $0["luma"] is NSNull
            && ($0["invert"] as? Bool) == false
    } == true && qualifierNow().isNeutral
    check(
        "K5 the Hue checkbox sends {qualifier: {hue: {}}} named \"Hue\" (one step, the default "
            + "lands); a strip drag is ONE live gesture \"Hue\" whose every write is the whole "
            + "hue range; Reset sends every range null and invert false, named \"Qualifier\"",
        tickOk && stripOk && resetOk,
        "checkboxes \(checks.count), strips \(strips.count); tick \(tickName) "
            + "\(String(describing: tick)); drag begins \(begins) ended \(ended) updates "
            + "\(updates.count) whole \(whole) → \(String(describing: moved)); reset "
            + "\(edits.map(\.0)) \(String(describing: cleared))")
}

// MARK: - K6 Show Selection: no defaults, the document's key, the rebind

do {
    guard let viewed = open() else {
        check("K6 a second copy of project P opens", false)
        finish()
    }
    let controller = EditorViewController(document: viewed)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 862),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentViewController = controller
    controller.viewWillAppear()
    controller.viewDidAppear()
    controller.refreshFromDocument(isLive: false)
    func settleView() {
        for _ in 0..<10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            controller.view.layoutSubtreeIfNeeded()
        }
    }
    settleView()
    let before = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
    let key = viewed.recipeKey
    let other = RecipeSource.shared.register()
    defer { RecipeSource.shared.unregister(other) }
    func bound() -> UInt32? { RecipeSource.shared.options(for: key).selection }
    func select(_ clips: Set<UInt32>) {
        viewed.selection = clips
        controller.syncShowSelection()
    }
    // Off: a selection change does nothing.
    select([first])
    let quietOff = bound() == nil
    controller.toggleShowSelection(nil)
    settleView()
    let onKey = RecipeSource.shared.options(for: key)
    let onOther = RecipeSource.shared.options(for: other)
    let tagShown = controller.selectionTag?.isHidden == false
    select([second])
    let rebound = bound()
    select([media])
    let cleared = bound()
    let tagHidden = controller.selectionTag?.isHidden == true
    select([first])
    controller.toggleShowSelection(nil)
    let again = bound()
    select([])
    let emptied = bound()
    let after = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
    let movedKeys = Set((before.allKeys + after.allKeys).compactMap { $0 as? String }).filter {
        (before[$0] as? NSObject) != (after[$0] as? NSObject)
    }
    check(
        "K6 toggleShowSelection writes no UserDefaults key and sets selection (only) on the "
            + "document's key, bound to the selected adjustment clip, the tag shown; "
            + "syncShowSelection rebinds to another adjustment clip, clears on a media clip "
            + "or an empty selection, and does nothing while off",
        movedKeys.isEmpty && quietOff && onKey == RecipeOptions(selection: first)
            && onOther == .none && tagShown && rebound == second && cleared == nil && tagHidden
            && again == first && emptied == nil,
        "moved \(movedKeys.sorted()); off quiet \(quietOff); on \(onKey), other \(onOther), tag "
            + "\(tagShown); rebound \(String(describing: rebound)), media "
            + "\(String(describing: cleared)), again \(String(describing: again)), empty "
            + "\(String(describing: emptied))")
    window.close()
}

finish()
