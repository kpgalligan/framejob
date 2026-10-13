// Road map "grading", phase GR2 — tone's probe (`tone_proof.py` builds it
// through `swift_build.build` and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, against `libframejob_core.a`, so every row drives the app's own
// types: `ClipPane`, `VideoPane.lightSection()`, `InspectorBinding`,
// `LayerUniforms.apply(tone:)`, `ClipSubTab.keyedCount`. Nothing private is
// widened.
//
//   tone_probe <request.json> <answer.json>
//
// `request.json` names `package`, a project the proof saved over MCP with two
// CARD clips at exposures +1 and −1, and `clips`, their ids. One JSON object
// out: `rows`, each a name, ok and detail, the name starting with its P-number.
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

/// A stored closure read out of a control by its property name (the
/// `graphics_inspector_probe.swift` reader).
struct DoubleWrite { let call: (Double) -> Void }
func closure<Box>(_ object: Any?, _ name: String, as: Box.Type) -> Box? {
    guard let object,
          var value = Mirror(reflecting: object).children.first(where: { $0.label == name })?.value
    else { return nil }
    return withUnsafeBytes(of: &value) { $0.baseAddress?.assumingMemoryBound(to: Box.self).pointee }
}

func parsed(_ op: ReelOp) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(op.json.utf8))) as? [String: Any] ?? [:]
}

// MARK: - P2 the flag, P3 the block

do {
    var negative = LayerUniforms()
    negative.apply(tone: ColorAdjust(exposure: -1))
    var neutral = LayerUniforms()
    neutral.apply(tone: ColorAdjust(brightness: 0.5, contrast: -0.25))
    var warm = LayerUniforms()
    warm.apply(tone: ColorAdjust(temperature: 0.5, fade: 1))
    check(
        "P2 apply(tone:) sets toneEnabled 1 for exposure -1 alone and 0 for an untoned colour",
        negative.toneEnabled == 1 && negative.exposure == -1 && neutral.toneEnabled == 0
            && warm.toneEnabled == 1 && warm.temperature == 0.5 && warm.fade == 1,
        "exposure -1: flag \(negative.toneEnabled), exposure \(negative.exposure); untoned: "
            + "flag \(neutral.toneEnabled); warm: flag \(warm.toneEnabled)")
    let stride = MemoryLayout<LayerUniforms>.stride
    let offset = MemoryLayout<LayerUniforms>.offset(of: \LayerUniforms.exposure) ?? -1
    let flag = MemoryLayout<LayerUniforms>.offset(of: \LayerUniforms.toneEnabled) ?? -1
    check(
        "P3 LayerUniforms is 512 bytes (128 floats, 32 × 16, since grading-2 G2-2's wheels) "
            + "with exposure at 416",
        stride == 512 && offset == 416 && flag == 452,
        "stride \(stride), exposure at \(offset), toneEnabled at \(flag)")
}

// MARK: - P4 the badge

do {
    let json = #"{"video": {"color": {"exposure": 1}, "x": 3}}"#
    if let end = try? JSONDecoder().decode(ActionPatch.self, from: Data(json.utf8)) {
        let color = ClipSubTab.color.keyedCount(in: end)
        let picture = ClipSubTab.picture.keyedCount(in: end)
        check(
            "P4 keyedCount for {video: {color: {exposure: 1}, x: 3}}: Color 1, Picture 1",
            color == 1 && picture == 1, "color \(color), picture \(picture)")
    } else {
        check("P4 the end decodes as an ActionPatch", false, json)
    }
}

// MARK: - P1 a Light row's write over two clips

func p1() {
    guard let path = request["package"] as? String,
          let clips = (request["clips"] as? [NSNumber])?.map(\.uint32Value), clips.count == 2
    else {
        check("P1 the request names the package and two clips", false, "\(request)")
        return
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        check("P1 project P opens", false, "\(error)")
        return
    }
    let exposures = clips.compactMap { id in
        document.project.snapshot.clips.first { $0.id == id }?.videoProps.color.exposure
    }
    let inspector = InspectorViewController()
    inspector.document = document
    var sent: [(String, [ReelOp])] = []
    inspector.onEdit = { name, ops in sent.append((name, ops)) }
    document.selection = Set(clips)
    inspector.binding.invalidate()
    let pane = ClipPane(inspector: inspector)
    pane.binding.invalidate()
    let tabs = pane.subTabs
    pane.choose(.color)
    pane.rebuild()
    pane.refresh()
    let light = pane.sections.first { $0.id == "video.light" }
    let row = light.flatMap { section in
        walk(section).compactMap { $0 as? InspectorRowView }.first { row in
            row.arrangedSubviews.contains { ($0 as? InspectorRowLabel)?.stringValue == "Temperature" }
        }
    }
    let write = row.flatMap { walk($0).first { $0 is OptionFieldControl } }
        .flatMap { closure($0, "write", as: DoubleWrite.self)?.call }
    guard let write else {
        check(
            "P1 the Color tab's Light section has a Temperature field", false,
            "tabs \(tabs.map(\.rawValue)); sections \(pane.sections.map(\.id)); row \(row != nil)")
        return
    }
    write(0.5)
    let ops = sent.flatMap(\.1)
    let op = ops.count == 1 ? parsed(ops[0]) : [:]
    let ids = ((op["clips"] as? [NSNumber]) ?? []).map(\.uint32Value).sorted()
    let patch = op["patch"] as? NSDictionary
    let want: NSDictionary = ["color": ["temperature": 0.5]]
    check(
        "P1 Light's Temperature over two clips (exposures \(exposures)) sends one set_video "
            + "naming both whose patch is exactly {color: {temperature: 0.5}}, undo \"Temperature\"",
        Set(exposures) == [1, -1] && tabs.contains(.color) && ops.count == 1
            && op["op"] as? String == "set_video" && ids == clips.sorted() && patch == want
            && sent.first?.0 == "Temperature",
        "tabs \(tabs.map(\.rawValue)); sent \(sent.map { ($0.0, $0.1.map(\.json)) })")
}
p1()

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
    try? data.write(to: out)
}
exit(0)
