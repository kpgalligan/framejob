// Road map 10, G5a — the Graphic sub-tab; the probe
// (`graphics_inspector_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — with the app's `Fonts`
// copied beside the binary (its `resourceURL`, where `GraphicStore` finds
// the bundled faces). Every row drives the app's own `ProjectDocument`,
// `GraphicStore`, `GraphicRegistry`, `InspectorViewController`, `ClipPane`,
// `GraphicPane` and `GraphicSchemaRows`. Nothing private is widened: a row
// is found by its label's text, a section by its id, and the two values a
// control keeps private (a readout's text, a popup's items) are read by
// reflection.
//
//   graphics_inspector_probe <request.json> <answer.json>
//
// `request.json` names `package`, a COPY of the fixture the proof made over
// MCP (the probe rewrites its modules): one graphic clip drawn by `six.js`,
// size 90 set by the TOOL, `old` and `zzz` injected into its props on disk.
// One JSON object out: `rows`, each a name, ok and detail; a row's name
// starts with its I- or K-number (K: issue batch B87 phase 3, the tab under a
// selected action), which is what the mutant mode reads.
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

let second: Ticks = 600_000
let sectionIDs = ["graphic.source", "graphic.properties", "graphic.size", "graphic.timeline"]
/// K18's sections, collapsed by default: expanded for the probe like the four above.
let expandedIDs = sectionIDs + ["text.font", "video.filters", "video.obscure"]
func key(_ id: String) -> String { InspectorSection.collapsedKeyPrefix + id }

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}
func finish() -> Never {
    for id in expandedIDs { UserDefaults.standard.removeObject(forKey: key(id)) }
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    try? data.write(to: out)
    exit(0)
}

for id in expandedIDs { UserDefaults.standard.set(false, forKey: key(id)) }

// MARK: - The document

guard let path = request["package"] as? String else {
    check("I0 the request names the package", false)
    finish()
}
let url = URL(fileURLWithPath: path)
let document = ProjectDocument()
do {
    try document.read(from: url, ofType: ProjectDocument.projectTypeIdentifier)
    document.fileURL = url
} catch {
    check("I0 the fixture opens", false, "\(error)")
    finish()
}
document.startGraphicStore()
guard let store = document.graphicStore,
      let clipID = document.project.snapshot.clips.first(where: { $0.graphic?.name == "six" })?.id
else {
    check("I0 the fixture holds a store and a clip drawn by six", false)
    finish()
}
let inspector = InspectorViewController()
inspector.document = document
inspector.onEdit = { [weak document] name, ops in document?.applyEdit(name, ops) }
document.selection = [clipID]
let binding = inspector.binding
let pane = ClipPane(inspector: inspector)
let graphic = GraphicPane(inspector: inspector)
let sixSource = String(decoding: store.module(named: "six")?.bytes ?? Data(), as: UTF8.self)

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func sections(_ tab: ClipSubTab = .graphic) -> [InspectorSection] {
    binding.invalidate()
    pane.choose(tab)
    pane.rebuild()
    pane.refresh()
    return pane.sections
}

func section(_ id: String) -> InspectorSection? { sections().first { $0.id == id } }

/// The row holding a label reading `label` — the row's own or, for a stale
/// row, the dimmed one among its controls.
func row(_ section: InspectorSection?, _ label: String) -> InspectorRowView? {
    guard let section else { return nil }
    return walk(section).compactMap { $0 as? InspectorRowView }.first { row in
        row.arrangedSubviews.contains { ($0 as? InspectorRowLabel)?.stringValue == label }
    }
}

func classes(_ row: NSView?) -> [String] {
    guard let row else { return ["no row"] }
    return walk(row).compactMap { view -> String? in
        let name = String(describing: type(of: view))
        return ["InspectorNameField", "InspectorTextArea", "InspectorSliderControl",
                "OptionFieldControl", "OptionCheckboxControl", "OptionSwatchControl",
                "OptionPopupControl"].contains(name) ? name : nil
    }
}

/// A private stored property, by reflection.
func reflected<T>(_ object: Any, _ name: String, as: T.Type) -> T? {
    Mirror(reflecting: object).children.first { $0.label == name }?.value as? T
}

func props() -> [String: GraphicPropValue] {
    document.project.snapshot.clip(clipID)?.graphic?.props ?? [:]
}

func propsPatch(_ op: ReelOp?) -> [String: Any]? {
    ((op?.args["patch"] as? [String: Any])?["props"]) as? [String: Any]
}

func describe(_ ops: [ReelOp]) -> String { ops.map { "\($0.name) \($0.args)" }.joined(separator: "; ") }

func rewrite(_ name: String, _ source: String) {
    do { try store.write(name: name, source: source) } catch {
        check("I0 \(name).js is written", false, "\(error)")
    }
    store.rescan()
}

func click(_ view: NSView?) -> Bool {
    guard let view, let event = NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    else { return false }
    view.mouseDown(with: event)
    return true
}

func compiled(_ name: String) -> GraphicModule? {
    if case .compiled(let module, _, _, _)? = GraphicRegistry.shared.entry(
        named: name, for: document.recipeKey)
    {
        return module
    }
    return nil
}

func clip() -> ClipSnapshot? { document.project.snapshot.clip(clipID) }

// MARK: - I1 the module's order

let moduleOrder = ["title", "size", "offset", "showBox", "color", "align", "logo"]
let ordered = compiled("six").map { GraphicSchema.orderedKeys(describeJSON: $0.describeJSON()) }
check("I1 orderedKeys over six's describeJSON() is the module's order "
        + "(title's default holds {\"}: ) — not the dictionary's",
      ordered == moduleOrder, "\(ordered ?? [])")
let parsed = graphic.schema(graphic.shared())?.schema
check("I1 … and GraphicSchema's entries follow it", parsed?.keys == moduleOrder,
      "\(parsed?.keys ?? [])")

// MARK: - I9 the tool's edit, read back

var properties = section("graphic.properties")
let sizeField = row(properties, "Size").flatMap {
    walk($0).first { $0 is OptionFieldControl }
}.flatMap { walk($0).compactMap { $0 as? NSTextField }.first }
check("I9 the tool's set_graphic {props: {size: 90}} shows: the Size field reads \"90\"",
      sizeField?.stringValue == "90", "\(sizeField?.stringValue ?? "no field")")

// MARK: - I2 one row per type

let want: [(String, [String])] = [
    ("Title", ["InspectorNameField"]),
    ("Size", ["InspectorSliderControl", "OptionFieldControl"]),
    ("Offset", ["OptionFieldControl"]),
    ("Color", ["OptionSwatchControl"]),
    ("Align", ["OptionPopupControl"]),
    ("Logo", ["OptionPopupControl"]),
]
for (label, expected) in want {
    let got = classes(row(properties, label))
    check("I2 \(label) row holds \(expected.joined(separator: " + "))", got == expected, "\(got)")
}
let checkboxes = properties.map { walk($0).filter { $0 is OptionCheckboxControl } } ?? []
check("I2 the boolean is one OptionCheckboxControl", checkboxes.count == 1, "\(checkboxes.count)")
let logoPopup = row(properties, "Logo").flatMap { walk($0).first { $0 is OptionPopupControl } }
let logoItems = logoPopup.flatMap { reflected($0, "items", as: [String].self) }
check("I2 the asset popup lists None and red.png", logoItems == ["None", "red.png"],
      "\(logoItems ?? [])")

// MARK: - I3 Reset against the schema's default

let sizeDefault = row(properties, "Size")?.gutter.default
let sizeOps = sizeDefault?.ops() ?? []
check("I3 size 90 vs default 64: the gutter's default differs",
      sizeDefault?.differs() == true, "\(String(describing: sizeDefault?.differs()))")
check("I3 … and its ops are set_graphic {props: {size: null}}",
      sizeOps.count == 1 && sizeOps.first?.name == "set_graphic"
        && propsPatch(sizeOps.first)?.keys.sorted() == ["size"]
        && propsPatch(sizeOps.first)?["size"] is NSNull,
      describe(sizeOps))
let colorDefault = row(properties, "Color")?.gutter.default
let colorOps = colorDefault?.ops() ?? []
check("I3 the colour row, unstored, default \"#FF5A36\": differs() false",
      colorDefault?.differs() == false, "\(String(describing: colorDefault?.differs()))")
check("I3 … and its Reset's ops are {color: null}",
      colorOps.count == 1 && propsPatch(colorOps.first)?["color"] is NSNull, describe(colorOps))
document.applyEdit("probe", [GraphicSchemaRows.op(
    clips: clip().map { [$0] } ?? [], props: ["size": NSNull()],
    schema: graphic.schema(graphic.shared())?.raw)])
properties = section("graphic.properties")
let unstored = row(properties, "Size")?.gutter.default?.differs()
check("I3 with no stored size the gutter's default does not differ", unstored == false,
      "\(String(describing: unstored)), stored \(props()["size"].map { "\($0)" } ?? "nil")")
document.applyEdit("probe", [GraphicSchemaRows.op(
    clips: clip().map { [$0] } ?? [], props: ["size": 90], schema: nil)])

// MARK: - I4 the colour arithmetic and the null rule

func entry(_ type: String, _ value: GraphicPropValue) -> GraphicSchemaEntry {
    GraphicSchemaEntry(
        key: "k", type: type, default: value, label: "K", help: nil, min: nil, max: nil,
        step: nil, multiline: false, options: [])
}
check("I4 patchValue of a number equal to its default is NSNull; unequal is the number",
      GraphicSchemaRows.patchValue(.number(64), for: entry("number", .number(64))) is NSNull
        && (GraphicSchemaRows.patchValue(.number(65), for: entry("number", .number(64)))
            as? Double) == 65)
check("I4 .string(\"#ff5a36\") against the default \"#FF5A36\" is NSNull",
      GraphicSchemaRows.patchValue(
          .string("#ff5a36"), for: entry("color", .string("#FF5A36"))) is NSNull)
let forms = ["#abc": "#aabbcc", "#abcd": "#aabbccdd", "#A1B2C3": "#a1b2c3",
             "#a1b2c380": "#a1b2c380"]
let trips = forms.map { form, back -> String in
    let color = GraphicSchemaRows.rgba(css: form)
    return "\(form) → \(color.map(GraphicSchemaRows.css) ?? "nil") (want \(back))"
}
check("I4 css(rgba(css:)) round-trips #rgb, #rgba, #rrggbb and #rrggbbaa",
      forms.allSatisfy { GraphicSchemaRows.rgba(css: $0.key).map(GraphicSchemaRows.css) == $0.value },
      trips.sorted().joined(separator: ", "))
check("I4 css([1, 0.353, 0.212, 1]) == \"#ff5a36\"",
      GraphicSchemaRows.css([1, 0.353, 0.212, 1]) == "#ff5a36",
      GraphicSchemaRows.css([1, 0.353, 0.212, 1]))

// MARK: - I9 a write through a row

if let box = checkboxes.first {
    _ = click(box)
    let stored = props()["showBox"]
    check("I9 the checkbox's write lands in document.project under the module's spelling "
            + "(showBox: false)",
          stored == .bool(false),
          "\(props().keys.sorted())")
    document.applyEdit("probe", [GraphicSchemaRows.op(
        clips: clip().map { [$0] } ?? [], props: ["showBox": NSNull()], schema: nil)])
} else {
    check("I9 the checkbox's write lands in document.project under the module's spelling "
            + "(showBox: false)", false, "no checkbox")
}

// MARK: - I10 Fit to Canvas, I11 sourceSize

if let clip = clip() {
    let fit = GraphicPane.fitToCanvasOps(clips: [clip], canvas: document.project.snapshot.canvas)
    let graphicPatch = fit.first?.args["patch"] as? [String: Any]
    let videoPatch = fit.last?.args["patch"] as? [String: Any]
    check("I10 fitToCanvasOps = set_graphic {width 1920, height 1080} + set_video "
            + "{x 0, y 0, scale 1}",
          fit.count == 2 && fit[0].name == "set_graphic" && fit[1].name == "set_video"
            && graphicPatch?["width"] as? Int == 1920 && graphicPatch?["height"] as? Int == 1080
            && videoPatch?["x"] as? Double == 0 && videoPatch?["y"] as? Double == 0
            && videoPatch?["scale"] as? Double == 1 && videoPatch?.count == 3,
          describe(fit))
    let size = document.project.snapshot.sourceSize(of: clip)
    check("I11 sourceSize(of:) answers the graphic's 1920 × 1080",
          size == CGSize(width: 1920, height: 1080), "\(String(describing: size))")
}

// MARK: - I7 the tab and its sections

check("I7 the clip's subTabs are [graphic, picture, clip]",
      pane.subTabs == [.graphic, .picture, .clip], "\(pane.subTabs.map(\.rawValue))")
let ids = sections().map(\.id)
check("I7 .graphic's sections are [source, properties, size, timeline]", ids == sectionIDs,
      "\(ids)")
let keyed = ClipSubTab.graphic.keyedCount(
    in: ActionPatch(video: VideoPatch(x: 10, opacity: 0.5)))
check("I7 ClipSubTab.graphic.keyedCount of a video-only end patch is 0",
      keyed == 0 && ClipSubTab.graphic.title == "Graphic",
      "\(keyed)")

// MARK: - I8 the report

let version = GraphicRegistry.shared.snapshot(for: document.recipeKey)?.libraryVersion ?? ""
let families = GraphicRegistry.shared.snapshot(for: document.recipeKey)?.library.families() ?? []
if let clip = clip(), let shared = graphic.shared() {
    let report = graphic.report(for: clip, shared, libraryVersion: version)
    let text = report.render.map(\.message).joined(separator: " ¶ ")
    check("I8 the report names Nope Sans and the set's families (\(families.first ?? "none"))",
          text.contains("Nope Sans") && !families.isEmpty
            && families.allSatisfy { text.contains($0) }, text)
    check("I8 … and carries NO \"the SVG is\" warning (the raster ran at the clip's 1920×1080)",
          !text.contains("the SVG is") && report.compile.isEmpty, text)
    rewrite("fixed", "export function render(frame, props, ctx) {\n  return "
        + "`<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\"></svg>`;\n}\n")
    rewrite("throws", "export function render(frame, props, ctx) {\n  if (frame === 0) "
        + "throw new Error(\"boom at zero\");\n  return svg(ctx, ``);\n}\n")
    func other(_ name: String) -> GraphicClipReport {
        graphic.report(
            for: clip,
            GraphicPane.Shared(
                name: name, file: store.module(named: name),
                entry: GraphicRegistry.shared.entry(named: name, for: document.recipeKey)),
            libraryVersion: version)
    }
    let fixed = other("fixed").render.filter { $0.message.contains("the SVG is") }
    check("I8 a module drawing a fixed 100×100 <svg> gets exactly one size warning, naming "
            + "1920×1080",
          fixed.count == 1 && fixed[0].message.contains("1920×1080"),
          fixed.map(\.message).joined(separator: " ¶ "))
    let thrown = other("throws")
    check("I8 a module throwing at frame 0 reports an error with frame == 0",
          thrown.frame == 0 && thrown.render.contains {
              $0.level == "error" && $0.message.contains("boom at zero")
          },
          "frame \(String(describing: thrown.frame)), "
            + thrown.render.map { "\($0.level): \($0.message)" }.joined(separator: " ¶ "))
} else {
    check("I8 the report names Nope Sans and the set's families", false, "no clip or module")
}

// MARK: - I6 the signature

let before = graphic.structureSignature
rewrite("six", sixSource.replacingOccurrences(
    of: "  logo:", with: "  extra: { type: \"number\", default: 1 },\n  logo:"))
let added = graphic.structureSignature
rewrite("six", sixSource)
let restored = graphic.structureSignature
rewrite("six", sixSource.replacingOccurrences(of: "default: 64", with: "default: 65"))
let defaultMoved = graphic.structureSignature
rewrite("six", sixSource.replacingOccurrences(of: "max: 200", with: "max: 250"))
let maxMoved = graphic.structureSignature
let upper = row(section("graphic.properties"), "Size")
    .flatMap { walk($0).first { $0 is InspectorSliderControl } }
    .flatMap { reflected($0, "upper", as: Double.self) }
rewrite("six", sixSource.replacingOccurrences(
    of: "options: [\"left\", \"center\", \"right\"]",
    with: "options: [\"left\", \"center\", \"right\", \"justify\"]"))
let optionsMoved = graphic.structureSignature
rewrite("six", sixSource)
document.applyEdit("probe", [GraphicSchemaRows.op(
    clips: clip().map { [$0] } ?? [], props: ["size": 91], schema: nil)])
binding.invalidate()
let valueMoved = graphic.structureSignature
document.applyEdit("probe", [GraphicSchemaRows.op(
    clips: clip().map { [$0] } ?? [], props: ["size": 90], schema: nil)])
check("I6 one more schema key (store.rescan()) changes structureSignature",
      added != before && restored == before, "before \(before)\nadded \(added)")
check("I6 a default 64 → 65 changes it", defaultMoved != before, defaultMoved)
check("I6 max 200 → 250 changes it, and the rebuilt Size slider's upper is 250",
      maxMoved != before && upper == 250, "upper \(String(describing: upper))\n\(maxMoved)")
check("I6 align's options gaining \"justify\" changes it", optionsMoved != before, optionsMoved)
check("I6 changing only a stored value does not", valueMoved == before, valueMoved)

// MARK: - I13 a number's decimals

func numberEntry(step: Double? = nil, value: Double = 0, max: Double? = nil) -> GraphicSchemaEntry {
    GraphicSchemaEntry(
        key: "k", type: "number", default: .number(value), label: "K", help: nil, min: nil,
        max: max, step: step, multiline: false, options: [])
}
let decimalCases: [(String, GraphicSchemaEntry, Int)] = [
    ("no step, default 0.5", numberEntry(value: 0.5), 2),
    ("step 0.1", numberEntry(step: 0.1), 2),
    ("step 1, default 0.5", numberEntry(step: 1, value: 0.5), 0),
    ("no step, default 3", numberEntry(value: 3), 0),
    ("no step, max 1.5", numberEntry(max: 1.5), 2),
]
let decimalAnswers = decimalCases.map { "\($0.0) → \(GraphicSchemaRows.decimals(for: $0.1))" }
check("I13 decimals(for:): no step default 0.5 → 2, step 0.1 → 2, step 1 default 0.5 → 0, "
        + "no step default 3 → 0, no step max 1.5 → 2",
      decimalCases.allSatisfy { GraphicSchemaRows.decimals(for: $0.1) == $0.2 },
      decimalAnswers.joined(separator: ", "))
rewrite("six", sixSource.replacingOccurrences(
    of: "offset: { type: \"number\", default: 0,", with: "offset: { type: \"number\", default: 0.5,"))
let offsetField = row(section("graphic.properties"), "Offset").flatMap {
    walk($0).first { $0 is OptionFieldControl }
}.flatMap { walk($0).compactMap { $0 as? NSTextField }.first }
check("I13 six's offset default rewritten to 0.5 (no step): the Offset field reads \"0.50\"",
      offsetField?.stringValue == "0.50", "\(offsetField?.stringValue ?? "no field")")
rewrite("six", sixSource)

// MARK: - I14 the Title field's height

properties = section("graphic.properties")
let titleRow = row(properties, "Title")
let offsetRow = row(properties, "Offset")
let titleField = titleRow.flatMap { walk($0).first { $0 is InspectorNameField } }
let titleHeights = titleField.map { field in
    field.constraints.filter { $0.firstItem === field && $0.firstAttribute == .height }
        .map(\.constant)
} ?? []
let titleFit = titleRow?.fittingSize.height ?? -1
let offsetFit = offsetRow?.fittingSize.height ?? -2
check("I14 the Title InspectorNameField's height constraint is DS.controlHeight, and the Title "
        + "row's fittingSize.height equals the Offset row's",
      titleHeights == [DS.controlHeight] && titleFit == offsetFit,
      "heights \(titleHeights), title row \(titleFit), offset row \(offsetFit)")

// MARK: - I5 stale keys

var reversed: [String: GraphicPropValue] = [:]
reversed["zzz"] = .number(2)
reversed["old"] = .number(1)
check("I5 staleKeys is [old, zzz] from a dictionary built in the reverse order",
      GraphicSchemaRows.staleKeys(stored: reversed, schema: parsed) == ["old", "zzz"],
      "\(GraphicSchemaRows.staleKeys(stored: reversed, schema: parsed))")

func staleLabels(_ section: InspectorSection?) -> [String] {
    guard let section else { return [] }
    return walk(section).compactMap { view -> String? in
        guard let label = view as? InspectorRowLabel, label.textColor == DS.textFaint
        else { return nil }
        return label.stringValue
    }
}
properties = section("graphic.properties")
check("I5 the Properties section lists the stale rows old then zzz, under the schema's",
      staleLabels(properties) == ["old", "zzz"], "\(staleLabels(properties))")

rewrite("six", sixSource.replacingOccurrences(
    of: "export const schema = {", with: "export const schema = { broken: ;"))
let failedSections = sections()
properties = failedSections.first { $0.id == "graphic.properties" }
let lineRows = failedSections.first { $0.id == "graphic.source" }.map {
    walk($0).compactMap { $0 as? GraphicDiagnosticRow }
} ?? []
let storedKeys = props().keys.sorted()
check("I5 six rewritten to a syntax error: every stored key is a stale row, sorted",
      staleLabels(properties) == storedKeys && storedKeys.contains("old"),
      "rows \(staleLabels(properties)), stored \(storedKeys)")
check("I5 … and the Source section's compile row names line 2",
      lineRows.contains { $0.diagnostic.level == "error" && $0.diagnostic.line == 2 },
      lineRows.map { "\($0.label.stringValue)" }.joined(separator: " ¶ "))
rewrite("six", sixSource)

for name in ["old", "zzz"] {
    properties = section("graphic.properties")
    let remove = row(properties, name).flatMap { walk($0).first { $0 is OptionButtonControl } }
    let clicked = click(remove)
    check("I5 \(name)'s ⌫ nulls it: the key leaves the stored props",
          clicked && props()[name] == nil && props()["size"] == .number(90),
          "clicked \(clicked), stored \(props().keys.sorted())")
}

// MARK: - I7 two modules

if let clip = clip() {
    document.applyEdit("probe", [.addGraphicClipRaw(
        track: clip.track, at: 20 * second, duration: 2 * second, name: "fixed")])
    let other = document.project.snapshot.clips.first { $0.graphic?.name == "fixed" }
    document.selection = Set([clipID] + (other.map { [$0.id] } ?? []))
    let mixedIDs = sections().map(\.id)
    check("I7 two clips of different modules: [graphic.source, graphic.size]",
          other != nil && mixedIDs == ["graphic.source", "graphic.size"], "\(mixedIDs)")
    document.selection = [clipID]
}

// MARK: - I12 the graphic's own in point

if let start = clip()?.start {
    binding.apply("Trim Start", [.trimStart(clip: clipID, to: start + 2 * second)])
    let moved = clip()?.graphic?.sourceIn
    let timeline = section("graphic.timeline")
    let readout = row(timeline, "In").flatMap { walk($0).first { $0 is OptionDisplayControl } }
    let shown = readout.flatMap { reflected($0, "text", as: String.self) }
    let canvas = document.project.snapshot.canvas
    let want = ReelTime.format(2 * second, fps: canvas.fps, frames: canvas.timecodeFrames)
    check("I12 after trim_start by 2 s, graphic.sourceIn is 2 s in ticks",
          moved == 2 * second, "\(String(describing: moved))")
    check("I12 … and the In readout shows it (\(want)), not the source's 0",
          shown == want && shown != ReelTime.format(0, fps: canvas.fps,
                                                    frames: canvas.timecodeFrames),
          "\(shown ?? "no readout")")

    // #346 (G-9·c): with Follow Clip on, a null length is in + duration — the
    // clip's 5 s, not the trimmed 3 s — in the field, the summary and the
    // write that unticking Follow Clip makes.
    let lengthField = row(timeline, "Length").flatMap {
        walk($0).first { $0 is InspectorTimecodeField } as? InspectorTimecodeField
    }
    let summary = timeline.flatMap {
        Mirror(reflecting: $0.header).children.first { $0.label == "lastSummary" }?.value
            as? String
    }
    let trimmed = clip()
    let whole = (trimmed?.graphic?.sourceIn ?? 0) + (trimmed?.duration ?? 0)
    let wantLength = ReelTime.format(whole, fps: canvas.fps, frames: canvas.timecodeFrames)
    let shortLength = ReelTime.format(trimmed?.duration ?? 0, fps: canvas.fps,
                                      frames: canvas.timecodeFrames)
    check("I12b (#346, G-9·c) with Follow Clip on (length null) the Length field and the "
            + "Timeline summary read in + duration, not the clip's duration",
          trimmed?.graphic?.length == nil && trimmed?.graphic?.sourceIn == 2 * second
            && lengthField?.stringValue == wantLength && summary == wantLength
            && wantLength != shortLength,
          "field \(lengthField?.stringValue ?? "no field"), summary \(summary ?? "none"), "
            + "want \(wantLength), short \(shortLength)")
    let follow = timeline.flatMap { section in
        walk(section).first {
            $0 is OptionCheckboxControl && reflected($0, "label", as: String.self) == "Follow Clip"
        }
    }
    _ = click(follow)
    let pinned = clip()?.graphic?.length
    check("I12c (#346) unticking Follow Clip writes length = in + duration",
          follow != nil && pinned == whole,
          "follow \(follow != nil), length \(String(describing: pinned)), want \(whole)")
    document.applyEdit("probe", [.setGraphicRaw(clips: [clipID], patch: ["length": NSNull()])])
}

// The same rule as arithmetic (#346): ClipSnapshot.graphicEffectiveLength
// against recipe_graphic.rs's effective_length — length when set, else
// in + duration, saturating; nil without a graphic.
let effective: [Ticks?] = [
    ClipSnapshot(id: 1, track: 1, duration: 3 * second,
                 graphic: GraphicSnapshot(sourceIn: 2 * second)).graphicEffectiveLength,
    ClipSnapshot(id: 1, track: 1, duration: 3 * second,
                 graphic: GraphicSnapshot(sourceIn: 2 * second, length: 4 * second))
        .graphicEffectiveLength,
    ClipSnapshot(id: 1, track: 1, duration: 3 * second).graphicEffectiveLength,
    ClipSnapshot(id: 1, track: 1, duration: 5,
                 graphic: GraphicSnapshot(sourceIn: .max - 1)).graphicEffectiveLength,
]
check("I12d (#346) graphicEffectiveLength: in 2 s + duration 3 s → 5 s; length 4 s → 4 s; no graphic "
        + "→ nil; in Ticks.max − 1 + 5 saturates to Ticks.max",
      effective == [5 * second, 4 * second, nil, .max], "\(effective)")

// MARK: - I16 the memos

func sixRevision() -> String? {
    if case .compiled(_, let revision, _, _)? = GraphicRegistry.shared.entry(
        named: "six", for: document.recipeKey)
    {
        return revision
    }
    return nil
}
binding.invalidate()
_ = graphic.structureSignature
_ = graphic.structureSignature
let memoKey = graphic.schemaMemo?.key
let revision16 = sixRevision()
let layerHeld = graphic.layerMemo[clipID] != nil
let layerHandle = graphic.layerProject === document.editedProject
rewrite("six", sixSource + "// rewritten for I16\n")
_ = graphic.structureSignature
let rewrittenKey = graphic.schemaMemo?.key
let revision16b = sixRevision()
rewrite("six", sixSource)
check("I16 after two signature reads schemaMemo.key is \"six|<registry revision>\" and "
        + "layerMemo holds the clip under document.editedProject; after a rewrite of six the "
        + "key names the new revision",
      revision16 != nil && memoKey == "six|\(revision16 ?? "")" && layerHeld && layerHandle
        && revision16b != nil && revision16b != revision16
        && rewrittenKey == "six|\(revision16b ?? "")",
      "key \(memoKey ?? "nil"), revision \(revision16 ?? "nil"), layer \(layerHeld), handle "
        + "\(layerHandle), rewritten key \(rewrittenKey ?? "nil"), revision "
        + "\(revision16b ?? "nil")")

// MARK: - I17 the marker name field's height

document.applyEdit("probe", [.addMarker(at: second)])
let documentPane = DocumentPane(inspector: inspector)
documentPane.rebuild()
documentPane.refresh()
let markerField = walk(documentPane).compactMap { $0 as? InspectorNameField }
    .first { $0.placeholderString == "Marker" }
let markerHeights = markerField.map { field in
    field.constraints.filter { $0.firstItem === field && $0.firstAttribute == .height }
        .map(\.constant)
} ?? []
check("I17 the Document tab's marker InspectorNameField has exactly one height constraint of "
        + "its own, DS.controlHeight",
      markerField != nil && markerHeights == [DS.controlHeight],
      "field \(markerField != nil), heights \(markerHeights)")

// MARK: - I18 a top-level warning in the Source section (B68, G-24 (a))

func sourceRows() -> [GraphicDiagnosticRow] {
    section("graphic.source").map { walk($0).compactMap { $0 as? GraphicDiagnosticRow } } ?? []
}
let assetHead = "asset(\"x\") is not in graphics/assets/"
rewrite("six", "const logo = asset(\"x\");\n" + sixSource)
let warnedRows = sourceRows().filter {
    $0.diagnostic.level == "warning" && $0.label.stringValue.hasPrefix(assetHead)
}
let warnedLabels = sourceRows().map { $0.label.stringValue }
rewrite("six", sixSource)
let quietRows = sourceRows().filter { $0.label.stringValue.hasPrefix(assetHead) }
check("I18 six rewritten with const logo = asset(\"x\") first: the Source section has a warning "
        + "row naming the asset; restored, none (CONTROL)",
      warnedRows.count == 1 && quietRows.isEmpty,
      "rewritten \(warnedLabels.joined(separator: " ¶ ")); restored "
        + "\(sourceRows().map { $0.label.stringValue }.joined(separator: " ¶ "))")

// MARK: - I19 the folder's warnings in the Source section (B68, G-24 (b))

let badHead = "graphics/Bad.js is not a module name"
func folderRows() -> (note: Int?, row: Int?, button: String?) {
    guard let source = section("graphic.source") else { return (nil, nil, nil) }
    let views = walk(source)
    let note = views.firstIndex { ($0 as? InspectorNoteLabel)?.stringValue == "In the graphics folder" }
    let row = views.firstIndex {
        ($0 as? GraphicDiagnosticRow)?.label.stringValue.hasPrefix(badHead) == true
    }
    let button = row.flatMap { index in
        walk(views[index]).first { $0 is OptionButtonControl }
            .flatMap { reflected($0, "title", as: String.self) }
    }
    return (note, row, button)
}
binding.invalidate()
let signatureBefore = graphic.structureSignature
let bad = store.folderURL.appendingPathComponent("Bad.js")
let badWritten = (try? Data(sixSource.utf8).write(to: bad)) != nil
store.rescan()
binding.invalidate()
let shown = folderRows()
let signatureWith = graphic.structureSignature
try? FileManager.default.removeItem(at: bad)
store.rescan()
binding.invalidate()
let gone = folderRows()
let signatureAfter = graphic.structureSignature
check("I19 Bad.js in graphics/ and store.rescan(): the Source section holds \"In the graphics "
        + "folder\" then a row naming graphics/Bad.js whose button is Reveal, and the signature "
        + "changed; removed and rescanned, neither, and the signature is back (CONTROL)",
      badWritten && shown.note != nil && shown.row != nil && (shown.note ?? 0) < (shown.row ?? 0)
        && shown.button == "Reveal" && signatureWith != signatureBefore
        && gone.note == nil && gone.row == nil && signatureAfter == signatureBefore,
      "written \(badWritten), shown \(shown), gone \(gone), signature changed "
        + "\(signatureWith != signatureBefore), back \(signatureAfter == signatureBefore)")

// MARK: - I20 each Source group under a true heading (B69, #221)

/// The Source section's note labels in view order, and the index (among
/// the same views) of each, plus the first row whose label starts `head`.
func sourceNotes(rowStarting head: String = "\u{0}") -> (notes: [String], at: [Int], row: Int?) {
    guard let source = section("graphic.source") else { return ([], [], nil) }
    let views = walk(source)
    let found = views.enumerated().compactMap { index, view -> (String, Int)? in
        guard let note = view as? InspectorNoteLabel, !note.isHidden else { return nil }
        return (note.stringValue, index)
    }
    let row = views.firstIndex {
        ($0 as? GraphicDiagnosticRow)?.label.stringValue.hasPrefix(head) == true
    }
    return (found.map(\.0), found.map(\.1), row)
}
let fontAnchor = " font-family=\"'Nope Sans'\""
let fontAnchorCount = sixSource.components(separatedBy: fontAnchor).count - 1
let cleanSix = sixSource.replacingOccurrences(
    of: fontAnchor, with: " font-family=\"sans-serif\"")
let compileHeading = "Compiling the module"
let quietFrame = "No errors or warnings at the clip's first frame"
// I5 removes the injected stale keys through their rows; nulled here too, so
// a frame that warns about them cannot stand in for these rows' own claims.
document.applyEdit("probe", [GraphicSchemaRows.op(
    clips: clip().map { [$0] } ?? [], props: ["old": NSNull(), "zzz": NSNull()], schema: nil)])

rewrite("six", "const logo = asset(\"x\");\n" + cleanSix)
let warnedNotes = sourceNotes(rowStarting: assetHead)
rewrite("six", sixSource)
let assetBetween = warnedNotes.at.count == 2 && warnedNotes.row.map {
    warnedNotes.at[0] < $0 && $0 < warnedNotes.at[1]
} == true
check("I20 a six with const logo = asset(\"x\") first and its font sans-serif: the Source "
        + "section's notes are [Compiling the module, No errors or warnings at the clip's first "
        + "frame], with the asset row between them",
      fontAnchorCount == 1 && warnedNotes.notes == [compileHeading, quietFrame] && assetBetween,
      "anchor \(fontAnchorCount)×, notes \(warnedNotes.notes), at \(warnedNotes.at), "
        + "asset row \(warnedNotes.row.map(String.init) ?? "none")")

rewrite("six", sixSource.replacingOccurrences(
    of: "export const schema = {", with: "export const schema = { broken: ;"))
let brokenNotes = sourceNotes()
rewrite("six", sixSource)
check("I20 b six rewritten to a syntax error: the Source section's notes are [Compiling the "
        + "module]",
      brokenNotes.notes == [compileHeading], "notes \(brokenNotes.notes)")

let badAgain = (try? Data(sixSource.utf8).write(to: bad)) != nil
rewrite("six", cleanSix)
binding.invalidate()
let folderNotes = sourceNotes()
try? FileManager.default.removeItem(at: bad)
rewrite("six", sixSource)
binding.invalidate()
check("I20 c Bad.js in graphics/ and six clean (sans-serif): the Source section's notes are "
        + "[No errors or warnings at the clip's first frame, In the graphics folder]",
      badAgain && folderNotes.notes == [quietFrame, "In the graphics folder"],
      "written \(badAgain), notes \(folderNotes.notes)")

// MARK: - I21 a colour default through the core's G-12 (B69, #219, G-25)

let named = [("white", "#ffffff"), ("steelblue", "#4682b4"), ("hsl(120, 50%, 50%)", "#40bf40")]
let drawnAs = named.map { text, hex -> String in
    let color = GraphicSchemaRows.defaultColor(entry("color", .string(text)))
    return "\(text) → \(GraphicSchemaRows.css(color)) (want \(hex))"
}
check("I21 a defaultColor of \"white\", \"steelblue\" and \"hsl(120, 50%, 50%)\" is "
        + "rgba(css:) of #ffffff, #4682b4 and #40bf40",
      named.allSatisfy { text, hex in
          GraphicSchemaRows.defaultColor(entry("color", .string(text)))
              == GraphicSchemaRows.rgba(css: hex)
      },
      drawnAs.joined(separator: ", "))
let nulled = named.map { text, hex in
    GraphicSchemaRows.patchValue(.string(hex), for: entry("color", .string(text))) is NSNull
}
let control = GraphicSchemaRows.patchValue(
    .string("#000000"), for: entry("color", .string("steelblue"))) as? String
check("I21 b patchValue of #ffffff, #4682b4 and #40bf40 against those defaults is NSNull; "
        + "#000000 against steelblue is the string itself (CONTROL)",
      nulled == [true, true, true] && control == "#000000",
      "nulled \(nulled), control \(control ?? "nil")")
check("I21 c defaultColor of \"bluish\" is unparsedColor",
      GraphicSchemaRows.defaultColor(entry("color", .string("bluish")))
        == GraphicSchemaRows.unparsedColor)

// MARK: - K the Graphic tab under a selected action (issue batch B87 phase 3, #239, G-34 (l))
//
// After I12 the six clip spans PROJECT 2–5 s; the action is CLIP 1–3 s, linear.
// Every write goes through a control's own reflected `write` (never the
// slider's live update); `recorded` is every op the inspector sent.

var recorded: [ReelOp] = []
// Applied only when the core APPLIES the list: a mutant's write the core
// rejects as invalid input would otherwise reach `present(_:)`'s app-modal
// alert and hang the probe (measured, `asset-to-end`), and a refused or
// identity one would beep. Either way the end is left as the core left it.
inspector.onEdit = { [weak document] name, ops in
    recorded.append(contentsOf: ops)
    guard let document, case .applied? = try? document.editedProject.applying(ops) else { return }
    document.applyEdit(name, ops)
}
/// `document.applyEdit` only when the core applies the list (no alert, no beep).
func probeApply(_ ops: [ReelOp]) {
    guard case .applied? = try? document.editedProject.applying(ops) else { return }
    document.applyEdit("probe", ops)
}
func recording(_ body: () -> Void) -> [ReelOp] {
    recorded = []
    body()
    return recorded
}

// A private stored CLOSURE, by reflection. `Mirror` boxes a closure field as
// `Any` at the wrong abstraction — cast back, it is called with garbage
// arguments (measured: `write(false)` wrote true) — so its bytes are read
// through a one-field struct of the closure's own concrete type, whose field
// is laid out as the control's stored property is.
struct DoubleWrite { let call: (Double) -> Void }
struct BoolWrite { let call: (Bool) -> Void }
struct IntWrite { let call: (Int) -> Void }
struct IntRead { let call: () -> Int }
struct OptionalRead { let call: () -> Double? }
struct TabCount { let call: (ClipSubTab) -> Int }
func closure<Box>(_ object: Any?, _ name: String, as: Box.Type) -> Box? {
    guard let object,
          var value = Mirror(reflecting: object).children.first(where: { $0.label == name })?.value
    else { return nil }
    return withUnsafeBytes(of: &value) { $0.baseAddress?.assumingMemoryBound(to: Box.self).pointee }
}
probeApply([.addAction(clip: clipID, at: second, duration: 2 * second)])
let actionID = clip()?.actions.first?.id ?? 0
probeApply([.setAction(clip: clipID, action: actionID, curve: .linear)])
document.selection = [clipID]
document.selectAction(actionID)

func end() -> ActionGraphicPatch? {
    clip()?.actions.first { $0.id == actionID }?.end.graphic
}
func endPatch() -> ActionPatch { clip()?.actions.first { $0.id == actionID }?.end ?? ActionPatch() }
func raw() -> [String: Any]? { graphic.schema(graphic.shared())?.raw }
func key(_ props: [String: Any]) {
    probeApply([.setActionEndRaw(
        clip: clipID, action: actionID, patch: ["graphic": ["props": props]], schema: raw())])
}
/// The end's graphic group removed — only when there is one, so no identity beeps.
func resetEnd() {
    guard end() != nil else { return }
    probeApply([.setActionEndRaw(
        clip: clipID, action: actionID, patch: ["graphic": NSNull()])])
}
func fresh(_ props: [String: Any]) {
    resetEnd()
    key(props)
}
func base(_ props: [String: Any]) {
    probeApply([GraphicSchemaRows.op(
        clips: clip().map { [$0] } ?? [], props: props, schema: nil)])
}
func gutterMark(_ row: InspectorRowView?) -> String { row.map { "\($0.gutter.mark)" } ?? "no row" }
func fieldText(_ row: InspectorRowView?) -> String? {
    row.flatMap { walk($0).first { $0 is OptionFieldControl } }
        .flatMap { walk($0).compactMap { $0 as? NSTextField }.first }?.stringValue
}
func fieldWrite(_ row: InspectorRowView?) -> ((Double) -> Void)? {
    row.flatMap { walk($0).first { $0 is OptionFieldControl } }
        .flatMap { closure($0, "write", as: DoubleWrite.self)?.call }
}
func checkboxRow(_ section: InspectorSection?, _ label: String) -> InspectorRowView? {
    guard let section else { return nil }
    return walk(section).compactMap { $0 as? InspectorRowView }.first { row in
        row.arrangedSubviews.contains {
            $0 is OptionCheckboxControl && reflected($0, "label", as: String.self) == label
        }
    }
}
func atEndShown(_ row: InspectorRowView?) -> Bool {
    guard let row else { return false }
    return walk(row).contains {
        ($0 as? InspectorRowTag).map { $0.stringValue == "at end" && !$0.isHidden } == true
    }
}
func badge(_ tab: ClipSubTab) -> Int? {
    guard let block = pane.pinnedBlock,
          let strip = walk(block).first(where: { $0 is ClipSubTabsView }),
          let read = closure(strip, "badge", as: TabCount.self)?.call
    else { return nil }
    return read(tab)
}
func onlyOp(_ ops: [ReelOp], _ name: String) -> ReelOp? {
    ops.count == 1 && ops[0].name == name ? ops[0] : nil
}
func endProps(_ op: ReelOp?) -> [String: Any]? {
    (((op?.args["patch"] as? [String: Any])?["graphic"]) as? [String: Any])?["props"]
        as? [String: Any]
}

// K1 CONTROL: no action selected.
document.selectAction(nil)
properties = section("graphic.properties")
let k1 = recording { fieldWrite(row(properties, "Size"))?(120) }
check("K1 no action selected: Size write(120) is exactly one set_graphic {props: {size: 120}} "
        + "(CONTROL)",
      onlyOp(k1, "set_graphic") != nil && propsPatch(k1.first)?.count == 1
        && propsPatch(k1.first)?["size"] as? Double == 120,
      describe(k1))
base(["size": 90])
document.selectAction(actionID)

// K2 the end's first write.
properties = section("graphic.properties")
let k2 = recording { fieldWrite(row(properties, "Size"))?(150) }
let k2op = onlyOp(k2, "set_action_end")
let k2schema = k2op?.args["schema"] as? [String: Any]
let k2patch = k2op?.args["patch"] as? [String: Any]
check("K2 action selected, end empty: Size write(150) is exactly one set_action_end naming the "
        + "clip and action, patch {graphic: {props: {size: 150}}}, schema a dictionary holding "
        + "size; the end reads size 150 and kinds.size \"number\", the base 90",
      k2op != nil && k2op?.args["clip"] as? UInt32 == clipID
        && k2op?.args["action"] as? UInt32 == actionID && k2patch?.keys.sorted() == ["graphic"]
        && endProps(k2op)?.count == 1 && endProps(k2op)?["size"] as? Double == 150
        && k2schema?["size"] != nil && k2op?.args["off"] == nil
        && end()?.props["size"] == .number(150) && end()?.kinds["size"] == "number"
        && props()["size"] == .number(90),
      describe(k2) + " | end \(String(describing: end())) | base \(String(describing: props()["size"]))")

// K3 the mark, the field and the three counts.
fresh(["size": 150])
properties = section("graphic.properties")
let k3size = row(properties, "Size"), k3offset = row(properties, "Offset")
check("K3a key({size: 150}): Size is ◆ (.keyed), Offset blank (.none), the Size field reads 150",
      k3size?.gutter.mark == .keyed && k3offset?.gutter.mark == RowMark.none
        && fieldText(k3size) == "150",
      "size \(gutterMark(k3size)), offset \(gutterMark(k3offset)), field "
        + "\(fieldText(k3size) ?? "none")")
let k3count = ClipSubTab.graphic.keyedCount(in: endPatch())
check("K3b … Properties' marks.keyed, ClipSubTab.graphic.keyedCount(in: end) and the strip's "
        + "graphic badge are all 1",
      properties?.marks.keyed == 1 && k3count == 1 && badge(.graphic) == 1,
      "section \(properties?.marks.keyed ?? -1), count \(k3count), badge "
        + "\(badge(.graphic).map(String.init) ?? "none")")

// K4 the slider's segment and tick at the playhead.
let k4playhead = (clip()?.start ?? 0) + 2 * second
document.playhead = k4playhead
properties = section("graphic.properties")
let k4slider = row(properties, "Size").flatMap { walk($0).first { $0 is InspectorSliderControl } }
    as? InspectorSliderControl
let k4start = closure(k4slider, "start", as: OptionalRead.self)?.call()
let k4now = closure(k4slider, "now", as: OptionalRead.self)?.call()
let k4keyed = k4slider?.keyed() ?? false
check("K4 the playhead at clip.start + 2 s: the Size slider's start() is 90, now() 120 (±1e-9) "
        + "and keyed() true",
      k4start.map { abs($0 - 90) < 1e-9 } == true && k4now.map { abs($0 - 120) < 1e-9 } == true
        && k4keyed,
      "start \(String(describing: k4start)), now \(String(describing: k4now)), keyed \(k4keyed)")
document.playhead = 0

// K5 a checkbox and a pop-up switch at the end.
resetEnd()
properties = section("graphic.properties")
let k5box = recording {
    checkboxRow(properties, "Show box").flatMap { walk($0).first { $0 is OptionCheckboxControl } }
        .flatMap { closure($0, "write", as: BoolWrite.self)?.call }?(false)
}
properties = section("graphic.properties")
let k5align = recording {
    row(properties, "Align").flatMap { walk($0).first { $0 is OptionPopupControl } }
        .flatMap { closure($0, "write", as: IntWrite.self)?.call }?(1)
}
properties = section("graphic.properties")
let k5boxRow = checkboxRow(properties, "Show box"), k5alignRow = row(properties, "Align")
check("K5 Show box write(false) and Align write(1) are each one set_action_end; both rows are "
        + "then ◆ at end (.keyedAtEnd) with their \"at end\" tags visible",
      endProps(onlyOp(k5box, "set_action_end"))?["showBox"] as? Bool == false
        && endProps(onlyOp(k5align, "set_action_end"))?["align"] as? String == "center"
        && k5boxRow?.gutter.mark == .keyedAtEnd && k5alignRow?.gutter.mark == .keyedAtEnd
        && atEndShown(k5boxRow) && atEndShown(k5alignRow),
      describe(k5box + k5align) + " | box \(gutterMark(k5boxRow)) \(atEndShown(k5boxRow)), align "
        + "\(gutterMark(k5alignRow)) \(atEndShown(k5alignRow))")

// K6 the string row is discrete, and its field gives way to the tag.
fresh(["title": "Hello"])
properties = section("graphic.properties")
let k6title = row(properties, "Title")
check("K6a key({title: \"Hello\"}): Title is ◆ at end (.keyedAtEnd) and its tag reads \"at end\", "
        + "visible",
      k6title?.gutter.mark == .keyedAtEnd && atEndShown(k6title), gutterMark(k6title))

/// Properties laid out at `DS.panelWidth`: (tag whole, row inside the section, field width).
func titleLayout() -> (tagWhole: Bool, inside: Bool, field: CGFloat, detail: String) {
    guard let section = section("graphic.properties") else { return (false, false, -1, "none") }
    let host = NSView(frame: NSRect(x: 0, y: 0, width: DS.panelWidth, height: 3000))
    section.removeFromSuperview()
    section.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(section)
    NSLayoutConstraint.activate([
        section.leadingAnchor.constraint(equalTo: host.leadingAnchor),
        section.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        section.topAnchor.constraint(equalTo: host.topAnchor),
    ])
    host.layoutSubtreeIfNeeded()
    guard let title = row(section, "Title"),
          let field = walk(title).first(where: { $0 is InspectorNameField })
    else { return (false, false, -1, "no Title row") }
    let tag = walk(title).compactMap { $0 as? InspectorRowTag }.first { !$0.isHidden }
    let tagWhole = tag.map { $0.frame.width + 0.5 >= $0.fittingSize.width } ?? true
    let maxX = title.convert(title.bounds, to: section).maxX
    let inside = maxX <= section.bounds.width + 0.5
    return (tagWhole, inside, field.frame.width,
            "tag \(tag.map { "\($0.frame.width)/\($0.fittingSize.width)" } ?? "hidden"), row maxX "
              + "\(maxX) in \(section.bounds.width), field \(field.frame.width)")
}
let longTitle = "The Long Road to a Motion Graphic"
let k6short = titleLayout()
key(["title": longTitle])
let k6long = titleLayout()
document.selectAction(nil)
base(["title": "Hello"])
let k6baseShort = titleLayout()
base(["title": longTitle])
let k6baseLong = titleLayout()
base(["title": NSNull()])
document.selectAction(actionID)
check("K6b laid out at DS.panelWidth, keyed with a short and with title-card's long title: the "
        + "tag is whole, the row inside the section, the field narrower than 170; CONTROL, nothing "
        + "selected: both titles leave the field at exactly 170, the row inside",
      k6short.tagWhole && k6short.inside && k6short.field < 170 && k6short.field > 0
        && k6long.tagWhole && k6long.inside && k6long.field < 170 && k6long.field > 0
        && k6baseShort.inside && k6baseShort.field == 170
        && k6baseLong.inside && k6baseLong.field == 170,
      [k6short.detail, k6long.detail, k6baseShort.detail, k6baseLong.detail]
        .joined(separator: " ¶ "))

// K7 a colour is ◆ with no tag.
fresh(["color": "#2d7ff9"])
properties = section("graphic.properties")
let k7color = row(properties, "Color")
check("K7 key({color: \"#2d7ff9\"}): Color is ◆ (.keyed) with no visible tag",
      k7color?.gutter.mark == .keyed && !atEndShown(k7color), gutterMark(k7color))

// K8 an asset is the end's, switching at its end, "" no image there (G-42).
func logoPopup(_ section: InspectorSection?) -> NSView? {
    row(section, "Logo").flatMap { walk($0).first { $0 is OptionPopupControl } }
}
func popupItems(_ popup: NSView?) -> [String]? {
    popup.flatMap { reflected($0, "items", as: [String].self) }
}
func popupWrite(_ popup: NSView?) -> ((Int) -> Void)? {
    closure(popup, "write", as: IntWrite.self)?.call
}
func popupRead(_ popup: NSView?) -> Int? {
    closure(popup, "read", as: IntRead.self)?.call()
}

// K8a an image picked with an action selected is one set_action_end.
properties = section("graphic.properties")
let k8logo = row(properties, "Logo")
let k8mark = k8logo?.gutter.mark
let k8a = recording { popupWrite(logoPopup(properties))?(1) }
let k8aOp = onlyOp(k8a, "set_action_end")
let k8aEnd = end()?.props["logo"], k8aBase = props()["logo"]
properties = section("graphic.properties")
let k8aItems = popupItems(logoPopup(properties))
check("K8a action selected: Logo is not ⊘; its popup's write(1) is exactly one set_action_end "
        + "{graphic: {props: {logo: \"red.png\"}}} with a schema; the end's logo is red.png, the "
        + "base's \"\", and the popup is then [None, red.png]",
      k8mark != nil && k8mark != .notAnimatable && k8aOp != nil
        && endProps(k8aOp)?.count == 1 && endProps(k8aOp)?["logo"] as? String == "red.png"
        && k8aOp?.args["schema"] is [String: Any]
        && k8aEnd == .string("red.png") && k8aBase == .string("") && k8aItems == ["None", "red.png"],
      "mark \(k8mark.map { "\($0)" } ?? "none"), " + describe(k8a) + " | end "
        + "\(String(describing: k8aEnd)), base \(String(describing: k8aBase)), items "
        + "\(k8aItems ?? [])")

// K8b "None" with an action selected writes "" into the end, and reads as None.
let k8b = recording { popupWrite(logoPopup(properties))?(0) }
let k8bOp = onlyOp(k8b, "set_action_end")
let k8bEnd = end()?.props["logo"]
properties = section("graphic.properties")
let k8bRead = popupRead(logoPopup(properties))
check("K8b … its write(0) is exactly one set_action_end {graphic: {props: {logo: \"\"}}}; the "
        + "end's logo is \"\", and the popup's read answers 0 (None)",
      k8bOp != nil && endProps(k8bOp)?.count == 1 && endProps(k8bOp)?["logo"] as? String == ""
        && k8bEnd == .string("") && k8bRead == 0,
      describe(k8b) + " | end \(String(describing: k8bEnd)), read "
        + "\(k8bRead.map(String.init) ?? "none")")
resetEnd()
base(["logo": NSNull()])

// K8c a string default: "None" is still first, and writes "" to the base.
let logoAnchor = "logo: { type: \"asset\", default: null,"
let logoAnchors = sixSource.components(separatedBy: logoAnchor).count - 1
rewrite("six", sixSource.replacingOccurrences(
    of: logoAnchor, with: "logo: { type: \"asset\", default: \"red.png\","))
document.selectAction(nil)
properties = section("graphic.properties")
let k8cItems = popupItems(logoPopup(properties))
let k8cRead = popupRead(logoPopup(properties))
let k8c = recording { popupWrite(logoPopup(properties))?(0) }
let k8cBase = props()["logo"]
properties = section("graphic.properties")
let k8cNone = popupRead(logoPopup(properties))
let k8cControl = recording { popupWrite(logoPopup(properties))?(1) }
check("K8c six's logo default rewritten to \"red.png\", no action selected: the popup is "
        + "[None, red.png] reading 1; write(0) is exactly one set_graphic {props: {logo: \"\"}}, "
        + "the base's logo \"\" reading 0; CONTROL: write(1) is one set_graphic {props: {logo: "
        + "null}} (G-15 (b))",
      logoAnchors == 1 && k8cItems == ["None", "red.png"] && k8cRead == 1
        && onlyOp(k8c, "set_graphic") != nil && propsPatch(k8c.first)?.count == 1
        && propsPatch(k8c.first)?["logo"] as? String == ""
        && k8cBase == .string("") && k8cNone == 0
        && onlyOp(k8cControl, "set_graphic") != nil && propsPatch(k8cControl.first)?.count == 1
        && propsPatch(k8cControl.first)?["logo"] is NSNull,
      "anchor \(logoAnchors)×, items \(k8cItems ?? []), read \(k8cRead.map(String.init) ?? "none"), "
        + describe(k8c) + " | base \(String(describing: k8cBase)), read "
        + "\(k8cNone.map(String.init) ?? "none") | " + describe(k8cControl))
base(["logo": NSNull()])
rewrite("six", sixSource)
document.selectAction(actionID)

// K8d a name the end holds that the folder lacks is listed, as a clip's is.
fresh(["logo": "elsewhere.png"])
properties = section("graphic.properties")
let k8dItems = popupItems(logoPopup(properties))
let k8dRead = popupRead(logoPopup(properties))
let k8dEntry = graphic.schema(graphic.shared())?.schema.entries.first { $0.key == "logo" }
let k8dControl = k8dEntry.map {
    GraphicSchemaRows.assetNames(for: $0, files: ["red.png"], clips: [], end: [:])
}
check("K8d key({logo: \"elsewhere.png\"}): the popup is [None, red.png, elsewhere.png] reading 2; "
        + "CONTROL: assetNames with no clips and no end is [red.png]",
      k8dItems == ["None", "red.png", "elsewhere.png"] && k8dRead == 2
        && k8dControl == ["red.png"],
      "items \(k8dItems ?? []), read \(k8dRead.map(String.init) ?? "none"), control "
        + "\(k8dControl ?? [])")
resetEnd()
base(["logo": NSNull()])

// K19 a prop its module marks `animate: false` is the clip's (G-41).
let offsetAnchor = "offset: { type: \"number\", default: 0,"
let offsetAnchors = sixSource.components(separatedBy: offsetAnchor).count - 1
let heldSource = sixSource.replacingOccurrences(
    of: offsetAnchor, with: "offset: { type: \"number\", default: 0, animate: false,")
resetEnd()
binding.invalidate()
let k19before = graphic.structureSignature
rewrite("six", heldSource)
binding.invalidate()
let k19after = graphic.structureSignature
let k19entry = graphic.schema(graphic.shared())?.schema.entries.first { $0.key == "offset" }
check("K19a six with offset marked animate: false: the parsed entry's animate and animatable are "
        + "false, and structureSignature changes",
      offsetAnchors == 1 && k19entry?.animate == false && k19entry?.animatable == false
        && k19before != k19after,
      "anchor \(offsetAnchors)×, entry \(k19entry.map { "\($0)" } ?? "none")")

// K19b its row is ⊘ and writes the clip; Size still writes the end (CONTROL).
properties = section("graphic.properties")
let k19offset = row(properties, "Offset")
let k19offsetMark = k19offset?.gutter.mark
let k19b = recording { fieldWrite(k19offset)?(5) }
let k19bEnd = end()?.props["offset"], k19bBase = props()["offset"]
properties = section("graphic.properties")
let k19size = row(properties, "Size")
let k19sizeMark = k19size?.gutter.mark
let k19control = recording { fieldWrite(k19size)?(150) }
check("K19b action selected, end empty, offset animate: false: Offset is ⊘ (.notAnimatable); its "
        + "write(5) is exactly one set_graphic {props: {offset: 5}}, and the end holds no offset; "
        + "CONTROL: Size is not ⊘ and its write(150) is one set_action_end",
      k19offsetMark == .notAnimatable && onlyOp(k19b, "set_graphic") != nil
        && propsPatch(k19b.first)?.count == 1 && propsPatch(k19b.first)?["offset"] as? Double == 5
        && k19bEnd == nil && k19bBase == .number(5)
        && k19sizeMark != nil && k19sizeMark != .notAnimatable
        && endProps(onlyOp(k19control, "set_action_end"))?["size"] as? Double == 150,
      "offset \(k19offsetMark.map { "\($0)" } ?? "none"), " + describe(k19b) + " | end offset "
        + "\(String(describing: k19bEnd)), base \(String(describing: k19bBase)) | size "
        + "\(k19sizeMark.map { "\($0)" } ?? "none"), " + describe(k19control))
base(["offset": NSNull()])
resetEnd()

// K19c an end that named offset before the mark lists it as the end's own stale row.
let k19tip = "The module does not let offset be animated — remove it from action 1"
func heldRows() -> [InspectorRowView] {
    (properties.map { walk($0).compactMap { $0 as? InspectorRowView } } ?? []).filter { row in
        row.arrangedSubviews.contains { ($0 as? InspectorRowLabel)?.stringValue == "offset" }
            && walk(row).compactMap { $0 as? OptionButtonControl }.first?.toolTip == k19tip
    }
}
rewrite("six", sixSource)
key(["offset": 3])
rewrite("six", heldSource)
properties = section("graphic.properties")
let k19heldRow = heldRows().first
let k19heldMark = k19heldRow?.gutter.mark
let k19c = recording {
    _ = click(k19heldRow.flatMap { walk($0).compactMap { $0 as? OptionButtonControl }.first })
}
let k19cOp = onlyOp(k19c, "set_action_end")
let k19cAfter = end()?.props["offset"]
rewrite("six", sixSource)
key(["offset": 3])
properties = section("graphic.properties")
let k19controlRows = heldRows().count
check("K19c key({offset: 3}) under six, then offset marked animate: false: a row labelled "
        + "\"offset\" whose ⌫ reads \"\(k19tip)\", ◆ (.keyed); its ⌫ is one set_action_end "
        + "{graphic: {props: {offset: null}}} with no schema, and after it the end has no offset; "
        + "CONTROL: under six as written, keyed again, no such row",
      k19heldRow != nil && k19heldMark == .keyed && endProps(k19cOp)?.count == 1
        && endProps(k19cOp)?["offset"] is NSNull && k19cOp?.args["schema"] == nil
        && k19cAfter == nil && k19controlRows == 0,
      "row \(k19heldMark.map { "\($0)" } ?? "none"), " + describe(k19c) + " | end offset "
        + "\(String(describing: k19cAfter)), control rows \(k19controlRows)")
resetEnd()
rewrite("six", sixSource)

// K9 "Set end value to default".
fresh(["size": 150])
properties = section("graphic.properties")
let k9ops = row(properties, "Size")?.gutter.default?.ops() ?? []
let k9size = endProps(onlyOp(k9ops, "set_action_end"))?["size"]
if !k9ops.isEmpty { probeApply(k9ops) }
check("K9 key({size: 150}): the gutter's default.ops() is one set_action_end with size 64, a "
        + "number; applied, the end holds 64",
      (k9size as? Double) == 64 && !(k9size is NSNull) && end()?.props["size"] == .number(64),
      describe(k9ops) + " | end \(String(describing: end()?.props["size"]))")

// K10 × / "Remove from action".
fresh(["size": 150, "color": "#2d7ff9"])
properties = section("graphic.properties")
let k10 = recording { row(properties, "Size")?.gutter.removeFromAction() }
let k10props = endProps(onlyOp(k10, "set_action_end"))
check("K10 key({size, color}): Size's removeFromAction() is one set_action_end {graphic: {props: "
        + "{size: null}}}; after it the end names only color",
      k10props?.count == 1 && k10props?["size"] is NSNull
        && end()?.props.keys.sorted() == ["color"],
      describe(k10) + " | end \(end()?.props.keys.sorted() ?? [])")

// K11 the section's Clear.
fresh(["size": 150, "color": "#2d7ff9", "showBox": false])
properties = section("graphic.properties")
let k11title = properties?.header.buttonTitle
let k11 = recording { properties?.clear() }
let k11props = endProps(onlyOp(k11, "set_action_end"))
properties = section("graphic.properties")
let k11counts = [ClipSubTab.graphic.keyedCount(in: endPatch()), properties?.marks.keyed ?? -1,
                 badge(.graphic) ?? -1]
let k11size = row(properties, "Size")
check("K11 key({size, color, showBox}): the header reads Clear; clear() is one op whose "
        + "graphic.props is {color: null, showBox: null, size: null}; after it the end has no "
        + "props, every count is 0, Size is blank and the header no longer reads Clear",
      k11title == "Clear" && k11props?.keys.sorted() == ["color", "showBox", "size"]
        && k11props?.values.allSatisfy { $0 is NSNull } == true
        && (end()?.props.isEmpty ?? true) && k11counts == [0, 0, 0]
        && k11size?.gutter.mark == RowMark.none && properties?.header.buttonTitle != "Clear",
      "title \(k11title ?? "nil"), " + describe(k11) + " | counts \(k11counts), size "
        + gutterMark(k11size))

// K12 a stale key in the end (O2, O4).
fresh(["size": 150])
let sizeLine = "  size: { type: \"number\", default: 64, min: 12, max: 200, step: 1, label: \"Size\" },\n"
let sizeLines = sixSource.components(separatedBy: sizeLine).count - 1
rewrite("six", sixSource.replacingOccurrences(of: sizeLine, with: ""))
properties = section("graphic.properties")
let sizeRows = properties.map { walk($0).compactMap { $0 as? InspectorRowView } }?.filter { row in
    row.arrangedSubviews.contains { ($0 as? InspectorRowLabel)?.stringValue == "size" }
} ?? []
func removeButton(_ row: InspectorRowView) -> OptionButtonControl? {
    walk(row).compactMap { $0 as? OptionButtonControl }.first
}
let actionRow = sizeRows.first { removeButton($0)?.toolTip?.hasSuffix("remove it from action 1") == true }
let clipRow = sizeRows.first { removeButton($0)?.toolTip?.hasSuffix("remove the stored value") == true }
let k12count = ClipSubTab.graphic.keyedCount(in: endPatch())
let k12keyed = properties?.marks.keyed
let k12 = recording { _ = click(actionRow.flatMap(removeButton)) }
let k12op = onlyOp(k12, "set_action_end")
let k12after = end()?.props["size"]
let clipRowMark = clipRow?.gutter.mark
rewrite("six", sixSource)
check("K12 key({size: 150}), six without its size line: a \"size\" stale row whose ⌫ names "
        + "action 1, ◆ (.keyed); keyedCount and Properties' marks.keyed both 1 (O4); its ⌫ is one "
        + "set_action_end {graphic: {props: {size: null}}} with no schema, and after it the end has "
        + "no size; the clip's own size stale row stays, unmarked",
      sizeLines == 1 && actionRow != nil && actionRow?.gutter.mark == .keyed && k12count == 1
        && k12keyed == 1 && endProps(k12op)?.count == 1 && endProps(k12op)?["size"] is NSNull
        && k12op?.args["schema"] == nil && k12after == nil
        && clipRow != nil && clipRowMark == RowMark.none,
      "anchor \(sizeLines)×, size rows \(sizeRows.count), action row "
        + "\(actionRow.map { "\($0.gutter.mark)" } ?? "none"), count \(k12count), keyed "
        + "\(k12keyed ?? -1), " + describe(k12) + " | end size \(String(describing: k12after)), "
        + "clip row \(clipRowMark.map { "\($0)" } ?? "none")")

// K13 with no action selected the row names the other action and writes the clip.
fresh(["size": 150])
document.selectAction(nil)
properties = section("graphic.properties")
let k13row = row(properties, "Size")
let k13 = recording { fieldWrite(k13row)?(100) }
check("K13 key({size: 150}), then no action selected: Size is ◇1 (.other(1)) and write(100) is "
        + "one set_graphic",
      k13row?.gutter.mark == .other(1) && onlyOp(k13, "set_graphic") != nil,
      gutterMark(k13row) + " | " + describe(k13))
base(["size": 90])

// K14 Width, Height and Follow Clip are the clip's (O6).
func layerMarks() -> [RowMark?] {
    let size = section("graphic.size"), timeline = section("graphic.timeline")
    return [row(size, "Width")?.gutter.mark, row(size, "Height")?.gutter.mark,
            checkboxRow(timeline, "Follow Clip")?.gutter.mark]
}
document.selectAction(actionID)
let k14 = layerMarks()
let k14size = section("graphic.size")?.marks.allNotAnimatable
let k14timeline = section("graphic.timeline")?.marks.allNotAnimatable
document.selectAction(nil)
let k14control = layerMarks()
document.selectAction(actionID)
check("K14 action reselected: Width, Height and Follow Clip are ⊘ (.notAnimatable), and "
        + "graphic.size and graphic.timeline have marks.allNotAnimatable; CONTROL, no action "
        + "selected: all three blank",
      k14 == [.notAnimatable, .notAnimatable, .notAnimatable] && k14size == true
        && k14timeline == true && k14control == [RowMark.none, RowMark.none, RowMark.none],
      "selected \(k14), size \(String(describing: k14size)), timeline "
        + "\(String(describing: k14timeline)), control \(k14control)")

// K15 the band's label and the zoom test (O3).
let k15patch = ActionPatch(graphic: ActionGraphicPatch(props: ["size": .number(1), "accent": .string("#2d7ff9")]))
let k15keys = ActionBands.keys(of: k15patch)
var k15mixed = k15patch
k15mixed.video = VideoPatch(opacity: 0.5)
check("K15a ActionBands.keys(of:) of a graphic end {size, accent} joined is \"accent, size\"; "
        + "with video opacity added, [accent, opacity, size]",
      k15keys.joined(separator: ", ") == "accent, size"
        && ActionBands.keys(of: k15mixed) == ["accent", "opacity", "size"],
      "\(k15keys), \(ActionBands.keys(of: k15mixed))")
let zoomEnd = ActionPatch(video: VideoPatch(x: 0, y: 0, scale: 2), graphic: ActionGraphicPatch())
let zoomKeyed = ActionPatch(
    video: VideoPatch(x: 0, y: 0, scale: 2), graphic: ActionGraphicPatch(props: ["size": .number(1)]))
check("K15b isZoom of {video: {x 0, y 0, scale 2}, graphic: {}} is true; with props {size: 1} "
        + "false",
      ActionBands.isZoom(ActionSnapshot(id: 1, end: zoomEnd))
        && !ActionBands.isZoom(ActionSnapshot(id: 1, end: zoomKeyed)))

// K16 the Text tab's keyed Content row reads "at end" (O5).
if let track = clip()?.track {
    probeApply([.addTextClipRaw(
        track: track, at: 40 * second, duration: 2 * second, text: ["content": "One"])])
}
let textClip = document.project.snapshot.clips.first {
    if case .text = $0.source { return $0.start == 40 * second }
    return false
}
var k16mark: RowMark?, k16tag = false
if let textClip {
    probeApply([.addAction(clip: textClip.id, at: 0, duration: second)])
    let textAction = document.project.snapshot.clip(textClip.id)?.actions.first?.id ?? 0
    probeApply([.setActionEndRaw(
        clip: textClip.id, action: textAction, patch: ["text": ["content": "Two"]])])
    document.selection = [textClip.id]
    document.selectAction(textAction)
    let content = sections(.text).first { $0.id == "text.content" }
    let contentRow = content.map { walk($0).compactMap { $0 as? InspectorRowView } }?.first {
        $0.arrangedSubviews.contains { $0 is InspectorTextArea }
    }
    k16mark = contentRow?.gutter.mark
    k16tag = atEndShown(contentRow)
}

// K18 the CONTROL gives way, never the tag (O8): Font ▸ Family's 150 pt popup
// narrows while the selected action keys the font, so "at end" is whole and
// inside the panel's inset; with the font not keyed it is 150.
/// The Font section laid out at `DS.panelWidth`: the Family row's popup width,
/// its visible tag's width against its fitting width, and the tag's maxX
/// against the section's width less the inset.
/// Section `id` of `tab`, freshly built and laid out alone at `DS.panelWidth`, HELD
/// there as the app holds a pane (`InspectorViewController.showPane`: the pane's width
/// equals the clip view's, required) — a free host would grow instead of a control
/// giving way.
func laidOut(_ id: String, _ tab: ClipSubTab) -> InspectorSection? {
    guard let section = sections(tab).first(where: { $0.id == id }) else { return nil }
    let host = NSView(frame: NSRect(x: 0, y: 0, width: DS.panelWidth, height: 3000))
    section.removeFromSuperview()
    section.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(section)
    NSLayoutConstraint.activate([
        section.leadingAnchor.constraint(equalTo: host.leadingAnchor),
        section.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        section.topAnchor.constraint(equalTo: host.topAnchor),
        section.widthAnchor.constraint(equalToConstant: DS.panelWidth),
    ])
    host.layoutSubtreeIfNeeded()
    return section
}
func familyLayout() -> (popup: CGFloat, tag: CGFloat?, fitting: CGFloat, inside: Bool,
                        detail: String) {
    guard let font = laidOut("text.font", .text)
    else { return (-1, nil, 0, false, "no text.font section") }
    guard let family = row(font, "Family"),
          let popup = walk(family).first(where: { $0 is OptionPopupControl })
    else { return (-1, nil, 0, false, "no Family row") }
    let tag = walk(family).compactMap { $0 as? InspectorRowTag }.first { !$0.isHidden }
    let limit = font.bounds.width - InspectorMetrics.inset
    let tagMaxX = tag.map { $0.convert($0.bounds, to: font).maxX }
    let rowMaxX = family.convert(family.bounds, to: font).maxX
    let inside = (tagMaxX ?? rowMaxX) <= limit + 0.5 && rowMaxX <= limit + 0.5
    return (popup.frame.width, tag?.frame.width, tag?.fittingSize.width ?? 0, inside,
            "popup \(popup.frame.width), tag \(tag.map { "\($0.stringValue) \($0.frame.width)" } ?? "hidden")"
              + "/\(tag?.fittingSize.width ?? 0), tag maxX \(tagMaxX.map { "\($0)" } ?? "-"), row maxX "
              + "\(rowMaxX), limit \(limit)")
}
var k18keyed: (popup: CGFloat, tag: CGFloat?, fitting: CGFloat, inside: Bool, detail: String)?
var k18plain: (popup: CGFloat, tag: CGFloat?, fitting: CGFloat, inside: Bool, detail: String)?
var k18b: [(ok: Bool, detail: String)] = []
if let textClip {
    let textAction = document.project.snapshot.clip(textClip.id)?.actions.first?.id ?? 0
    probeApply([.setActionEndRaw(
        clip: textClip.id, action: textAction, patch: ["text": ["font": "Helvetica-Bold"]])])
    k18keyed = familyLayout()
    probeApply([.setActionEndRaw(
        clip: textClip.id, action: textAction, patch: ["text": ["font": NSNull()]])])
    k18plain = familyLayout()

    // K18b the rows with more than one control: a filter (order, kind, Remove)
    // and an obscure region (kind, Remove). Base and end each hold one, so the
    // lists are the same length and the end keys them.
    probeApply([.setVideoRaw(clips: [textClip.id], patch: [
        "filters": [FilterProps(kind: .blur, amount: 0.2).dictionary],
        "obscure": [ObscureProps(amount: 0.2).dictionary],
    ])])
    probeApply([.setActionEndRaw(clip: textClip.id, action: textAction, patch: ["video": [
        "filters": [FilterProps(kind: .blur, amount: 0.9).dictionary],
        "obscure": [ObscureProps(amount: 0.9).dictionary],
    ]])])
    func multi(_ id: String, _ pick: (InspectorRowView) -> Bool) -> (ok: Bool, detail: String) {
        guard let section = laidOut(id, .picture),
              let found = walk(section).compactMap({ $0 as? InspectorRowView }).first(where: pick)
        else { return (false, "\(id): no row") }
        let limit = section.bounds.width - InspectorMetrics.inset
        let tag = walk(found).compactMap { $0 as? InspectorRowTag }.first {
            !$0.isHidden && $0.stringValue == "at end"
        }
        let popups = found.arrangedSubviews.compactMap { $0 as? OptionPopupControl }
        let widest = popups.max { $0.intrinsicContentSize.width < $1.intrinsicContentSize.width }
        let others = found.arrangedSubviews.filter {
            $0 !== widest && !($0 is InspectorRowTag) && !($0 is InspectorMarkGutter)
                && !$0.isHidden && $0.intrinsicContentSize.width != NSView.noIntrinsicMetric
        }
        let othersWhole = others.allSatisfy { $0.frame.width + 0.5 >= $0.intrinsicContentSize.width }
        let tagMaxX = tag.map { $0.convert($0.bounds, to: section).maxX } ?? .infinity
        let ok = tag.map { $0.frame.width + 0.5 >= $0.fittingSize.width } == true
            && tagMaxX <= limit + 0.5 && othersWhole
            && (widest.map { $0.frame.width < $0.intrinsicContentSize.width } ?? false)
        let widths = found.arrangedSubviews.filter { !$0.isHidden }.map { view in
            "\(String(describing: type(of: view))) \(view.frame.width)"
                + (view.intrinsicContentSize.width == NSView.noIntrinsicMetric
                    ? "" : "/\(view.intrinsicContentSize.width)")
        }.joined(separator: ", ")
        return (ok, "\(id): \(widths); tag maxX \(tagMaxX), limit \(limit)")
    }
    k18b = [
        multi("video.filters") { row in
            row.arrangedSubviews.contains {
                $0 is OptionButtonControl && reflected($0, "title", as: String.self) == "Remove"
            }
        },
        multi("video.obscure") { row in
            row.arrangedSubviews.contains { ($0 as? InspectorRowLabel)?.stringValue == "Region 1" }
        },
    ]
}
let k18ok: Bool = {
    guard let keyed = k18keyed, let plain = k18plain, let tag = keyed.tag else { return false }
    return tag + 0.5 >= keyed.fitting && keyed.fitting > 0 && keyed.inside
        && keyed.popup < 150 && keyed.popup > 0
        && plain.tag == nil && plain.popup == 150 && plain.inside
}()
document.selection = [clipID]
document.selectAction(actionID)
check("K16 a text clip whose selected action ends {text: {content: \"Two\"}}: the Content row is "
        + "◆ at end (.keyedAtEnd) and its tag reads \"at end\", visible",
      textClip != nil && k16mark == .keyedAtEnd && k16tag,
      "clip \(textClip != nil), mark \(k16mark.map { "\($0)" } ?? "none"), tag \(k16tag)")
check("K18a the text clip's action keys the font; Font laid out at DS.panelWidth: Family's \"at "
        + "end\" is at its fitting width and inside the panel's inset, the popup narrower than "
        + "150; CONTROL, the font not keyed: no tag, the popup exactly 150 (O8)",
      k18ok, [k18keyed?.detail ?? "not run", k18plain?.detail ?? "not run"].joined(separator: " ¶ "))
check("K18b the same action keys a filter and an obscure region; laid out at DS.panelWidth, each "
        + "row's \"at end\" is at its fitting width and inside the panel's inset, and only the "
        + "row's widest popup (a filter's kind, a region's kind) is narrower than its own width (O8)",
      k18b.count == 2 && k18b.allSatisfy(\.ok), k18b.map(\.detail).joined(separator: " ¶ "))

// K18c a module's boolean with a long label (O8, issue batch B87 phase 4): a row
// with no popup gives its widest checkbox the 749, so keyed its title narrows and
// "at end" is whole inside the inset; not keyed, the checkbox is its full width.
// The label is wider than the keyed row's room and narrower than the unkeyed
// row's in both the app's Source Sans 3 (228 pt with the box) and the system face
// this probe draws in (260 pt); the rooms are 222 and 264. Keyed, the title is cut
// at the checkbox's edge: the row draws nothing between the checkbox and its tag,
// and over the tag no more than the tag draws alone. The checkbox and the tag tie
// at 750 without the rule and this solver happens to narrow the checkbox anyway
// (measured under `checkbox-fixed-width`), so the row also asserts the order of
// the two priorities rather than lean on that pick.
let showBoxLabel = "label: \"Show box\""
let longBoxLabel = "Show the long descriptive label for this toggle"
let showBoxLabels = sixSource.components(separatedBy: showBoxLabel).count - 1
rewrite("six", sixSource.replacingOccurrences(
    of: showBoxLabel, with: "label: \"\(longBoxLabel)\""))
/// Ink (alpha above 0.1) in the columns of `rect` of `view`'s cached drawing.
func ink(_ view: NSView, _ rect: NSRect) -> Int {
    guard rect.width >= 1, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    else { return -1 }
    view.cacheDisplay(in: view.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / view.bounds.width
    var count = 0
    for x in Int(ceil(rect.minX * scale))..<max(Int(ceil(rect.minX * scale)), Int(floor(rect.maxX * scale))) {
        for y in 0..<rep.pixelsHigh where rep.colorAt(x: x, y: y).map({ $0.alphaComponent > 0.1 }) == true {
            count += 1
        }
    }
    return count
}
func checkboxLayout() -> (check: CGFloat, intrinsic: CGFloat, tag: CGFloat?, fitting: CGFloat,
                          inside: Bool, spill: Int, own: Int, below: Bool, detail: String) {
    guard let props = laidOut("graphic.properties", .graphic)
    else { return (-1, 0, nil, 0, false, -1, -1, false, "no graphic.properties section") }
    guard let found = checkboxRow(props, longBoxLabel),
          let box = found.arrangedSubviews.first(where: { $0 is OptionCheckboxControl })
    else { return (-1, 0, nil, 0, false, -1, -1, false, "no long-label checkbox row") }
    let tag = walk(found).compactMap { $0 as? InspectorRowTag }.first { !$0.isHidden }
    let limit = props.bounds.width - InspectorMetrics.inset
    let tagMaxX = tag.map { $0.convert($0.bounds, to: props).maxX }
    let rowMaxX = found.convert(found.bounds, to: props).maxX
    let inside = (tagMaxX ?? rowMaxX) <= limit + 0.5 && rowMaxX <= limit + 0.5
    // The row's ink between the checkbox's right edge and the tag's left (the
    // stack's spacing), and inside the checkbox (a CONTROL that the cache drew).
    let boxFrame = box.frame
    let gapRect = tag.map {
        NSRect(x: boxFrame.maxX + 0.5, y: 0, width: $0.frame.minX - boxFrame.maxX - 1,
               height: found.bounds.height)
    } ?? .zero
    let gap = tag == nil ? 0 : ink(found, gapRect)
    let overTag = tag.map { ink(found, $0.frame) } ?? 0
    let tagAlone = tag.map { ink($0, $0.bounds) } ?? 0
    let spill = gap + max(0, overTag - tagAlone)
    let own = ink(found, boxFrame.insetBy(dx: 1, dy: 0))
    let boxPriority = box.contentCompressionResistancePriority(for: .horizontal).rawValue
    let tagPriority = tag?.contentCompressionResistancePriority(for: .horizontal).rawValue
    let below = tagPriority.map { boxPriority < $0 } ?? false
    return (box.frame.width, box.intrinsicContentSize.width, tag?.frame.width,
            tag?.fittingSize.width ?? 0, inside, spill, own, below,
            "compression resistance checkbox \(boxPriority) tag "
              + "\(tagPriority.map { "\($0)" } ?? "-"); ink: gap \(gap) in \(gapRect.width) pt, "
              + "over the tag \(overTag) against \(tagAlone) alone, checkbox \(own); "
              + "checkbox \(box.frame.width)/\(box.intrinsicContentSize.width), tag "
              + "\(tag.map { "\($0.stringValue) \($0.frame.width)" } ?? "hidden")"
              + "/\(tag?.fittingSize.width ?? 0), tag maxX \(tagMaxX.map { "\($0)" } ?? "-"), "
              + "row maxX \(rowMaxX), limit \(limit)")
}
fresh(["showBox": false])
let k18cKeyed = checkboxLayout()
resetEnd()
let k18cPlain = checkboxLayout()
rewrite("six", sixSource)
let k18cOK: Bool = {
    guard showBoxLabels == 1, let tag = k18cKeyed.tag else { return false }
    return tag + 0.5 >= k18cKeyed.fitting && k18cKeyed.fitting > 0 && k18cKeyed.inside
        && k18cKeyed.check > 0 && k18cKeyed.check < k18cKeyed.intrinsic
        && k18cKeyed.spill <= 20 && k18cKeyed.own > 0 && k18cKeyed.below
        && k18cPlain.tag == nil && k18cPlain.inside && k18cPlain.intrinsic > 0
        && abs(k18cPlain.check - k18cPlain.intrinsic) < 0.5
}()
check("K18c six's showBox labelled \"\(longBoxLabel)\" and keyed: laid out at DS.panelWidth, "
        + "its \"at end\" is at its fitting width and inside the panel's inset, the checkbox "
        + "narrower than its own width at a compression resistance below the tag's, and its "
        + "title drawn neither between it and the tag nor over the tag (the checkbox itself "
        + "inked); CONTROL, not keyed: no tag, the checkbox exactly its own width (O8)",
      k18cOK, "anchor \(showBoxLabels)× ¶ " + k18cKeyed.detail + " ¶ " + k18cPlain.detail)

// K17 Properties' Reset writes the end (O7).
resetEnd()
properties = section("graphic.properties")
let k17title = properties?.header.buttonTitle
let resetButton = properties.flatMap { section in
    walk(section.header).first {
        $0 is OptionButtonControl && reflected($0, "title", as: String.self) == "Reset"
    }
}
let k17 = recording { _ = click(resetButton) }
let k17op = onlyOp(k17, "set_action_end")
let k17end = endProps(k17op)
let wantDefaults: Bool = {
    guard let props = k17end else { return false }
    return props.keys.sorted() == ["align", "color", "logo", "offset", "showBox", "size", "title"]
        && props["logo"] as? String == ""
        && props["title"] as? String == "Hi {\"}: there" && props["size"] as? Double == 64
        && props["offset"] as? Double == 0 && props["showBox"] as? Bool == true
        && props["color"] as? String == "#FF5A36" && props["align"] as? String == "left"
}()
check("K17 resetEnd(): Properties' buttonTitle is nil; its header's Reset clicked records exactly "
        + "one set_action_end, no set_graphic, of six's seven defaults (logo \"\") with a schema; "
        + "applied, the end's size is 64, the end's logo \"\", the base size is 90 (O7, G-42 (d))",
      k17title == nil && resetButton != nil && k17op != nil && wantDefaults
        && k17op?.args["schema"] is [String: Any]
        && end()?.props["size"] == .number(64) && end()?.props["logo"] == .string("")
        && props()["size"] == .number(90),
      "title \(k17title ?? "nil"), button \(resetButton != nil), " + describe(k17) + " | end "
        + "\(String(describing: end()?.props)), base \(String(describing: props()["size"]))")
resetEnd()
base(["logo": NSNull()])
document.selectAction(nil)
inspector.onEdit = { [weak document] name, ops in document?.applyEdit(name, ops) }

// MARK: - I15 (last) two clips' asset names

if let first = clip() {
    document.applyEdit("probe", [.addGraphicClipRaw(
        track: first.track, at: 30 * second, duration: 2 * second, name: "six")])
    let twin = document.project.snapshot.clips.first {
        $0.graphic?.name == "six" && $0.id != clipID
    }
    if let twin {
        document.applyEdit("probe", [
            GraphicSchemaRows.op(clips: [first], props: ["logo": "a.png"], schema: nil),
            GraphicSchemaRows.op(clips: [twin], props: ["logo": "b.png"], schema: nil),
        ])
        document.selection = [clipID, twin.id]
    }
    properties = section("graphic.properties")
    let logo = row(properties, "Logo").flatMap { walk($0).first { $0 is OptionPopupControl } }
    let items = logo.flatMap { reflected($0, "items", as: [String].self) }
    check("I15 two six clips holding logo a.png and b.png, both selected: the Logo popup is "
            + "[None, red.png, a.png, b.png]",
          twin != nil && items == ["None", "red.png", "a.png", "b.png"], "\(items ?? [])")
    let signature = graphic.structureSignature
    check("I15 … and the signature holds red.png,a.png,b.png",
          twin != nil && signature.contains("red.png,a.png,b.png"), signature)
} else {
    check("I15 two six clips holding logo a.png and b.png, both selected: the Logo popup is "
            + "[None, red.png, a.png, b.png]", false, "no clip")
}

finish()
