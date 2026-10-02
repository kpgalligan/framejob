// Road map 10, G5a — the Graphic sub-tab; the probe
// (`graphics_inspector_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
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
// starts with its I-number, which is what the mutant mode reads.
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
func key(_ id: String) -> String { InspectorSection.collapsedKeyPrefix + id }

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}
func finish() -> Never {
    for id in sectionIDs { UserDefaults.standard.removeObject(forKey: key(id)) }
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    try? data.write(to: out)
    exit(0)
}

for id in sectionIDs { UserDefaults.standard.set(false, forKey: key(id)) }

// MARK: - The document

guard let path = request["package"] as? String else {
    check("I0 the request names the package", false)
    finish()
}
let url = URL(fileURLWithPath: path)
let document = ProjectDocument()
do {
    try document.read(from: url, ofType: "com.kgalligan.reelcut-project")
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
let unparsed = GraphicSchemaRows.css(GraphicSchemaRows.unparsedColor)
check("I4 .string(css(unparsedColor)) against the default \"white\" is NSNull",
      GraphicSchemaRows.patchValue(.string(unparsed), for: entry("color", .string("white")))
        is NSNull, unparsed)
check("I4 defaultColor of \"white\" is [0, 0, 0, 0]",
      GraphicSchemaRows.defaultColor(entry("color", .string("white"))) == [0, 0, 0, 0])
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
check("I7 ClipSubTab.graphic.keyedCount is 0", keyed == 0 && ClipSubTab.graphic.title == "Graphic",
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
}

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
