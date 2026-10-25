// kpgalligan/framejob#357 — the inspector's props are edited by copy-and-
// mutate and the tri-state (`T??`) patch keys are written by one helper; the
// probe (`props_mutate_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`, on
// `swift_build.py`'s line. It uses ONLY what the tree had before #357 —
// memberwise initialisers, `InspectorBinding.ops`, the `ReelOp.set*`
// builders and the option controls — so the proof's `--baseline <commit>`
// builds this same source over the old `app/Sources` unchanged.
//
//   props_mutate_probe <request.json> <answer.json>
//
// `request.json` names the packages the proof wrote:
//   av     a video with sound, clip 2 (media 91)
//   text   a text clip, clip 2, "Hello"
//   shape  a grey shape card, clip 2
// One JSON object out: `rows`, each a name, ok and detail.
//
// N1–N17: one per tri-state key. Each builds its patch at `.none`,
// `.some(nil)` and `.some(v)` — `v` with every field away from its default —
// wraps it in its op on clip 2 and compares the ops' `json` to the LITERAL
// strings below, which are this probe's output on the tree before #357.
// `motion` also at `.some(MotionProps())`, which must still write null.
//
// W1–W9: one inspector row write each. The clip's object is seeded with every
// field away from its default in one `applyEdit`; the row is found by its
// label inside its section, as `clip_inspector4_probe.swift`'s `row(_:_:)`
// finds one; one new value is committed through the row's OWN control (a
// field's text and `controlTextDidEndEditing`, or a popup's item action);
// and the ops `inspector.onEdit` hears are compared to `binding.ops` of the
// whole object rebuilt the OLD way — the memberwise initialiser with every
// field spelled out and only the edited one changed. A row that dropped a
// field would send that field's default instead.
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
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(2400))])
}

// MARK: - N1–N17 the tri-state keys' op bytes

/// The three states of one key, each as its op's JSON.
func tri<T>(_ make: (T??) -> ReelOp, _ value: T) -> [String] {
    [make(.none).json, make(.some(nil)).json, make(.some(value)).json]
}

func compare(_ name: String, _ got: [String], _ want: [String]) {
    check(name, got == want,
          zip(got.indices, got).map { i, json in
              (i < want.count && want[i] == json ? "same " : "DIFFERS ") + json
          }.joined(separator: "\n       "))
}

let none = #"{"clips":[2],"op":"set_video","patch":{}}"#
let noneAudio = #"{"clips":[2],"op":"set_audio","patch":{}}"#
let noneClip = #"{"clips":[2],"op":"set_clip","patch":{}}"#
let noneText = #"{"clips":[2],"op":"set_text","patch":{}}"#
let noneShape = #"{"clips":[2],"op":"set_shape","patch":{}}"#

func video(_ patch: VideoPatch) -> ReelOp { .setVideo(clips: [2], patch: patch) }
func audio(_ patch: AudioPatch) -> ReelOp { .setAudio(clips: [2], patch: patch) }
func clipOp(_ patch: ClipPatch) -> ReelOp { .setClip(clips: [2], patch: patch) }
func text(_ patch: TextPatch) -> ReelOp { .setText(clips: [2], patch: patch) }
func shape(_ patch: ShapePatch) -> ReelOp { .setShape(clips: [2], patch: patch) }

compare(
    "N1 shadow: absent, null, and the whole object",
    tri({ video(VideoPatch(shadow: $0)) },
        ShadowProps(color: [0.125, 0.25, 0.375, 0.5], opacity: 0.75, blur: 20, angle: 45, distance: 16)),
    [none, #"{"clips":[2],"op":"set_video","patch":{"shadow":null}}"#, #"{"clips":[2],"op":"set_video","patch":{"shadow":{"angle":45,"blur":20,"color":[0.125,0.25,0.375,0.5],"distance":16,"opacity":0.75}}}"#])
compare(
    "N2 chroma: absent, null, and the whole object",
    tri({ video(VideoPatch(chroma: $0)) },
        ChromaProps(key: [0.25, 0.5, 0.75], tolerance: 0.375, softness: 0.25, spill: 0.875)),
    [none, #"{"clips":[2],"op":"set_video","patch":{"chroma":null}}"#, #"{"clips":[2],"op":"set_video","patch":{"chroma":{"key":[0.25,0.5,0.75],"softness":0.25,"spill":0.875,"tolerance":0.375}}}"#])
compare(
    "N3 reflection: absent, null, and the whole object",
    tri({ video(VideoPatch(reflection: $0)) },
        ReflectionProps(opacity: 0.625, height: 0.75, gap: 10, falloff: 0.375)),
    [none, #"{"clips":[2],"op":"set_video","patch":{"reflection":null}}"#, #"{"clips":[2],"op":"set_video","patch":{"reflection":{"falloff":0.375,"gap":10,"height":0.75,"opacity":0.625}}}"#])
compare(
    "N4 spotlight: absent, null, and the whole object",
    tri({ video(VideoPatch(spotlight: $0)) },
        SpotlightProps(
            shape: .ellipse, x: 100, y: -50, width: 300, height: 200, feather: 15, dim: 0.25,
            zoom: 1.5)),
    [none, #"{"clips":[2],"op":"set_video","patch":{"spotlight":null}}"#, #"{"clips":[2],"op":"set_video","patch":{"spotlight":{"dim":0.25,"feather":15,"height":200,"shape":"ellipse","width":300,"x":100,"y":-50,"zoom":1.5}}}"#])
compare(
    "N5 motion: absent, null, the whole object, and an EMPTY object (written as null)",
    tri({ video(VideoPatch(motion: $0)) },
        MotionProps(
            inEdge: MotionEdge(kind: .zoomIn, duration: 120_000),
            out: MotionEdge(kind: .spin, duration: 240_000),
            during: MotionDuring(kind: .shake, amount: 0.25, period: 300_000)))
        + [video(VideoPatch(motion: .some(MotionProps()))).json],
    [none, #"{"clips":[2],"op":"set_video","patch":{"motion":null}}"#, #"{"clips":[2],"op":"set_video","patch":{"motion":{"during":{"amount":0.25,"kind":"shake","period":300000},"in":{"duration":120000,"kind":"zoom_in"},"out":{"duration":240000,"kind":"spin"}}}}"#, #"{"clips":[2],"op":"set_video","patch":{"motion":null}}"#])
compare(
    "N6 look: absent, null, and the whole patch",
    tri({ video(VideoPatch(look: $0)) }, LookPatch(kind: .vivid, amount: 0.625, media: 7)),
    [none, #"{"clips":[2],"op":"set_video","patch":{"look":null}}"#, #"{"clips":[2],"op":"set_video","patch":{"look":{"amount":0.625,"kind":"vivid","media":7}}}"#])
compare(
    "N7 duck: absent, null, and the whole object",
    tri({ audio(AudioPatch(duck: $0)) },
        DuckProps(level: 0.375, attack: 120_000, release: 540_000)),
    [noneAudio, #"{"clips":[2],"op":"set_audio","patch":{"duck":null}}"#, #"{"clips":[2],"op":"set_audio","patch":{"duck":{"attack":120000,"level":0.375,"release":540000}}}"#])
compare(
    "N8 compressor: absent, null, and the whole object",
    tri({ audio(AudioPatch(compressor: $0)) },
        CompressorProps(thresholdDb: -24, ratio: 4, attack: 12_000, release: 240_000, makeupDb: 3)),
    [noneAudio, #"{"clips":[2],"op":"set_audio","patch":{"compressor":null}}"#, #"{"clips":[2],"op":"set_audio","patch":{"compressor":{"attack":12000,"makeup_db":3,"ratio":4,"release":240000,"threshold_db":-24}}}"#])
compare(
    "N9 name: absent, null, and a string",
    tri({ clipOp(ClipPatch(name: $0)) }, "Interview"),
    [noneClip, #"{"clips":[2],"op":"set_clip","patch":{"name":null}}"#, #"{"clips":[2],"op":"set_clip","patch":{"name":"Interview"}}"#])
compare(
    "N10 label: absent, null, and a string",
    tri({ clipOp(ClipPatch(label: $0)) }, "red"),
    [noneClip, #"{"clips":[2],"op":"set_clip","patch":{"label":null}}"#, #"{"clips":[2],"op":"set_clip","patch":{"label":"red"}}"#])
compare(
    "N11 outline: absent, null, and the whole object",
    tri({ text(TextPatch(outline: $0)) }, OutlineProps(width: 3, color: [1, 0, 0, 1])),
    [noneText, #"{"clips":[2],"op":"set_text","patch":{"outline":null}}"#, #"{"clips":[2],"op":"set_text","patch":{"outline":{"color":[1,0,0,1],"width":3}}}"#])
compare(
    "N12 backdrop: absent, null, and the whole object",
    tri({ text(TextPatch(backdrop: $0)) },
        BackdropProps(color: [0.25, 0.5, 0.75, 0.5], padding: 20, radius: 4)),
    [noneText, #"{"clips":[2],"op":"set_text","patch":{"backdrop":null}}"#, #"{"clips":[2],"op":"set_text","patch":{"backdrop":{"color":[0.25,0.5,0.75,0.5],"padding":20,"radius":4}}}"#])
compare(
    "N13 width: absent, null, and a number",
    tri({ text(TextPatch(width: $0)) }, 640.0),
    [noneText, #"{"clips":[2],"op":"set_text","patch":{"width":null}}"#, #"{"clips":[2],"op":"set_text","patch":{"width":640}}"#])
compare(
    "N14 animation: absent, null, and the whole object",
    tri({ text(TextPatch(animation: $0)) },
        TextAnimation(kind: .lineRise, inDuration: 240_000, outDuration: 360_000)),
    [noneText, #"{"clips":[2],"op":"set_text","patch":{"animation":null}}"#, #"{"clips":[2],"op":"set_text","patch":{"animation":{"in":240000,"kind":"line_rise","out":360000}}}"#])
compare(
    "N15 stroke: absent, null, and the whole object",
    tri({ shape(ShapePatch(stroke: $0)) }, StrokeProps(width: 9, color: [0, 1, 0, 1])),
    [noneShape, #"{"clips":[2],"op":"set_shape","patch":{"stroke":null}}"#, #"{"clips":[2],"op":"set_shape","patch":{"stroke":{"color":[0,1,0,1],"width":9}}}"#])
compare(
    "N16 fill: absent, null, and a colour",
    tri({ shape(ShapePatch(fill: $0)) }, [0.5, 0.25, 0.75, 1] as RGBA),
    [noneShape, #"{"clips":[2],"op":"set_shape","patch":{"fill":null}}"#, #"{"clips":[2],"op":"set_shape","patch":{"fill":[0.5,0.25,0.75,1]}}"#])
compare(
    "N17 gradient: absent, null, and the whole object",
    tri({ shape(ShapePatch(gradient: $0)) },
        Gradient(
            kind: .radial,
            stops: [
                GradientStop(at: 0.125, color: [1, 0, 0, 1]),
                GradientStop(at: 0.625, color: [0, 0, 1, 1]),
                GradientStop(at: 0.875, color: [0, 1, 0, 0.5]),
            ],
            angle: 30)),
    [noneShape, #"{"clips":[2],"op":"set_shape","patch":{"gradient":null}}"#, #"{"clips":[2],"op":"set_shape","patch":{"gradient":{"angle":30,"kind":"radial","stops":[{"at":0.125,"color":[1,0,0,1]},{"at":0.625,"color":[0,0,1,1]},{"at":0.875,"color":[0,1,0,0.5]}]}}}"#])

// MARK: - W1–W9 one row write each

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func opened(_ name: String) -> ProjectDocument? {
    guard let path = request[name] as? String else { return nil }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        return nil
    }
    return document
}

/// The row whose label reads `label`, inside `section`.
func row(_ section: InspectorSection?, _ label: String) -> InspectorRowView? {
    guard let section else { return nil }
    return walk(section).compactMap { $0 as? InspectorRowView }.first { row in
        row.arrangedSubviews.contains { ($0 as? InspectorRowLabel)?.stringValue == label }
    }
}

/// A stored property read out of a control by its name.
func stored<T>(_ object: Any?, _ name: String, as: T.Type) -> T? {
    guard let object else { return nil }
    return Mirror(reflecting: object).children.first { $0.label == name }?.value as? T
}

/// Commits `text` through a field the way a click-away does: the text in
/// the control's own `NSTextField`, then `controlTextDidEndEditing`.
func commit(_ control: OptionFieldControl?, _ text: String) -> Bool {
    guard let control, let field = stored(control, "field", as: NSTextField.self) else {
        return false
    }
    field.stringValue = text
    control.controlTextDidEndEditing(
        Notification(name: NSControl.textDidEndEditingNotification, object: field))
    return true
}

/// Picks item `index` of a popup the way its menu does: the item's action,
/// sent to the control with the item's tag.
func pick(_ control: OptionPopupControl?, _ index: Int) -> Bool {
    guard let control else { return false }
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    item.tag = index
    control.perform(NSSelectorFromString("itemPicked:"), with: item)
    return true
}

/// One W row: `seed` lands on clip 2 of package `name`; the pane shows `tab`;
/// `act` commits through the section's row and answers whether it found the
/// control; `want` is the whole object rebuilt the old way.
func write(
    _ title: String, package name: String, seed: ReelOp, tab: ClipSubTab, section id: String,
    undo: String, act: (InspectorSection?) -> Bool, want: (InspectorBinding) -> [ReelOp]
) {
    guard let document = opened(name) else {
        check(title, false, "the \(name) fixture did not open")
        return
    }
    let inspector = InspectorViewController()
    inspector.document = document
    var heard: [(String, [ReelOp])] = []
    inspector.onEdit = { name, ops in heard.append((name, ops)) }
    document.selection = [2]
    document.selectAction(nil)
    document.applyEdit("Seed", [seed])
    inspector.binding.invalidate()
    let pane = ClipPane(inspector: inspector)
    pane.binding.invalidate()
    pane.choose(tab)
    pane.rebuild()
    pane.refresh()
    let section = pane.sections.first { $0.id == id }
    let found = act(section)
    let expected = want(inspector.binding).map(\.json)
    let got = heard.flatMap(\.1).map(\.json)
    check(title,
          section != nil && found && heard.count == 1 && heard.first?.0 == undo
            && got == expected,
          "section \(section != nil), control \(found), heard \(heard.map(\.0)) (want \"\(undo)\")"
            + "\n       got  \(got)\n       want \(expected)")
    withExtendedLifetime((document, inspector, pane)) {}
}

func field(_ section: InspectorSection?, _ label: String) -> OptionFieldControl? {
    row(section, label).flatMap { walk($0).compactMap { $0 as? OptionFieldControl }.first }
}

func popup(_ section: InspectorSection?, _ label: String) -> OptionPopupControl? {
    row(section, label).flatMap { walk($0).compactMap { $0 as? OptionPopupControl }.first }
}

let chroma = ChromaProps(key: [0.25, 0.5, 0.75], tolerance: 0.375, softness: 0.25, spill: 0.875)
write(
    "W1 Chroma Key ▸ Tolerance 30% keeps the key, softness and spill",
    package: "av", seed: video(VideoPatch(chroma: .some(chroma))), tab: .picture,
    section: "video.chroma", undo: "Chroma Tolerance",
    act: { commit(field($0, "Tolerance"), "30") },
    want: { binding in
        binding.ops(
            video: VideoPatch(
                chroma: .some(
                    ChromaProps(
                        key: chroma.key, tolerance: 30.0 / 100, softness: chroma.softness,
                        spill: chroma.spill))))
    })

let reflection = ReflectionProps(opacity: 0.625, height: 0.75, gap: 10, falloff: 0.375)
write(
    "W2 Reflection ▸ Gap 24 px keeps the opacity, height and falloff",
    package: "av", seed: video(VideoPatch(reflection: .some(reflection))), tab: .picture,
    section: "video.reflection", undo: "Reflection Gap",
    act: { commit(field($0, "Gap"), "24") },
    want: { binding in
        binding.ops(
            video: VideoPatch(
                reflection: .some(
                    ReflectionProps(
                        opacity: reflection.opacity, height: reflection.height, gap: 24,
                        falloff: reflection.falloff))))
    })

let spotlight = SpotlightProps(
    shape: .ellipse, x: 100, y: -50, width: 300, height: 200, feather: 15, dim: 0.25, zoom: 1.5)
write(
    "W3 Spotlight ▸ Shape Rectangle keeps the other seven fields",
    package: "av", seed: video(VideoPatch(spotlight: .some(spotlight))), tab: .picture,
    section: "video.spotlight", undo: "Spotlight Shape",
    act: { pick(popup($0, "Shape"), SpotShape.allCases.firstIndex(of: .rect) ?? -1) },
    want: { binding in
        binding.ops(
            video: VideoPatch(
                spotlight: .some(
                    SpotlightProps(
                        shape: .rect, x: spotlight.x, y: spotlight.y, width: spotlight.width,
                        height: spotlight.height, feather: spotlight.feather, dim: spotlight.dim,
                        zoom: spotlight.zoom))))
    })

let region = ObscureProps(
    shape: .ellipse, x: 50, y: 60, width: 200, height: 100, feather: 5, kind: .blur, amount: 0.75)
write(
    "W4 Obscure ▸ Region 1's Center X 75 px keeps the region's other seven fields",
    package: "av", seed: video(VideoPatch(obscure: [region])), tab: .picture,
    section: "video.obscure", undo: "Obscure Center",
    act: { commit(field($0, "Center"), "75") },
    want: { binding in
        binding.ops(
            video: VideoPatch(
                obscure: [
                    ObscureProps(
                        shape: region.shape, x: 75, y: region.y, width: region.width,
                        height: region.height, feather: region.feather, kind: region.kind,
                        amount: region.amount)
                ]))
    })

let gradient = Gradient(
    kind: .radial,
    stops: [
        GradientStop(at: 0.125, color: [1, 0, 0, 1]),
        GradientStop(at: 0.625, color: [0, 0, 1, 1]),
        GradientStop(at: 0.875, color: [0, 1, 0, 0.5]),
    ],
    angle: 30)
write(
    "W5 Gradient ▸ Kind Linear keeps the three stops and the angle",
    package: "shape", seed: shape(ShapePatch(gradient: .some(gradient))), tab: .shape,
    section: "shape.gradient", undo: "Gradient Kind",
    act: { pick(popup($0, "Kind"), GradientKind.allCases.firstIndex(of: .linear) ?? -1) },
    want: { binding in
        binding.ops(
            shape: ShapePatch(
                gradient: .some(
                    Gradient(kind: .linear, stops: gradient.stops, angle: gradient.angle))))
    })

let outline = OutlineProps(width: 3, color: [1, 0, 0, 1])
write(
    "W6 Outline ▸ Width 5 px keeps the colour",
    package: "text", seed: text(TextPatch(outline: .some(outline))), tab: .text,
    section: "text.outline", undo: "Outline Width",
    act: { commit(field($0, "Width"), "5") },
    want: { binding in
        binding.ops(text: TextPatch(outline: .some(OutlineProps(width: 5, color: outline.color))))
    })

let backdrop = BackdropProps(color: [0.25, 0.5, 0.75, 0.5], padding: 20, radius: 4)
write(
    "W7 Backdrop ▸ Padding 30 px keeps the colour and radius",
    package: "text", seed: text(TextPatch(backdrop: .some(backdrop))), tab: .text,
    section: "text.backdrop", undo: "Backdrop Padding",
    act: { commit(field($0, "Padding"), "30") },
    want: { binding in
        binding.ops(
            text: TextPatch(
                backdrop: .some(
                    BackdropProps(color: backdrop.color, padding: 30, radius: backdrop.radius))))
    })

let animation = TextAnimation(kind: .lineRise, inDuration: 240_000, outDuration: 360_000)
write(
    "W8 Reveal ▸ In 1.5 s keeps the kind and the out duration",
    package: "text", seed: text(TextPatch(animation: .some(animation))), tab: .text,
    section: "text.animation", undo: "Animation In",
    act: { commit(field($0, "In"), "1.5") },
    want: { binding in
        binding.ops(
            text: TextPatch(
                animation: .some(
                    TextAnimation(
                        kind: animation.kind,
                        inDuration: ReelTime.snapToFrame(
                            ReelTime.ticks(seconds: 1.5), fps: binding.canvas.fps),
                        outDuration: animation.outDuration))))
    })

let duck = DuckProps(level: 0.375, attack: 120_000, release: 540_000)
write(
    "W9 Ducking ▸ Attack 0.5 s keeps the level and release",
    package: "av", seed: audio(AudioPatch(duck: .some(duck))), tab: .sound,
    section: "audio.duck", undo: "Duck Attack",
    act: { commit(field($0, "Attack"), "0.5") },
    want: { binding in
        binding.ops(
            audio: AudioPatch(
                duck: .some(
                    DuckProps(
                        level: duck.level,
                        attack: ReelTime.snapToFrame(
                            ReelTime.ticks(seconds: 0.5), fps: binding.canvas.fps),
                        release: duck.release))))
    })

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
