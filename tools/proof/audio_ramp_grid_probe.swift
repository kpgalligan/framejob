// kpgalligan/framejob#355 — the Audio inspector's fades and the duck's attack
// and release store the length typed, off the frame grid; the fade handle's
// drag and the Reveal rows still snap. The probe (`audio_ramp_grid_proof.py`
// builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`, on
// `swift_build.py`'s line. It uses ONLY what the tree had before #355 —
// memberwise initialisers, `InspectorBinding.ops`, the `ReelOp.set*`
// builders, the option controls and `FadeHandleSession` — never
// `frameTicks` or `rampTicks`, so the proof's `--baseline <commit>` builds
// this same source over the old `app/Sources` unchanged.
//
//   audio_ramp_grid_probe <request.json> <answer.json>
//
// `request.json` names the packages the proof wrote:
//   av     a video with sound, clip 2 (media 91), canvas 30 fps
//   text   a text clip, clip 2, "Hello", canvas 30 fps
// One JSON object out: `rows`, each a name, ok and detail.
//
// At 30 fps a frame is 20 000 ticks and 0.01 s is 6 000. A1–A5 and G3 each
// seed clip 2 in one `applyEdit` with a value that differs from the one the
// row commits, find the row by its label inside its section, commit one value
// through the row's OWN field (its text and `controlTextDidEndEditing`), and
// pass only when exactly one edit is heard, under the row's undo name, whose
// ops are `binding.ops` of the whole object at the LITERAL tick value; then
// the heard ops are applied and the stored value is read back from the
// document. G1 and G2 drive `FadeHandleSession.update` directly.
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

func audio(_ patch: AudioPatch) -> ReelOp { .setAudio(clips: [2], patch: patch) }
func text(_ patch: TextPatch) -> ReelOp { .setText(clips: [2], patch: patch) }

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

func field(_ section: InspectorSection?, _ label: String) -> OptionFieldControl? {
    row(section, label).flatMap { walk($0).compactMap { $0 as? OptionFieldControl }.first }
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

/// One A/G3 row: `seed` lands on clip 2 of package `name`; the pane shows
/// `tab`; `label` inside section `id` is committed with `typed`; `want` is the
/// whole object at the literal ticks; `read` is the stored value after the
/// heard ops are applied, which must be `expect`.
func write(
    _ title: String, package name: String, seed: ReelOp, tab: ClipSubTab, section id: String,
    label: String, typed: String, undo: String, want: (InspectorBinding) -> [ReelOp],
    read: (ClipSnapshot) -> Ticks?, expect: Ticks
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
    let fps = inspector.binding.canvas.fps
    let before = document.editedProject.snapshot.clip(2).flatMap(read)
    let section = pane.sections.first { $0.id == id }
    let found = commit(field(section, label), typed)
    let expected = want(inspector.binding).map(\.json)
    let got = heard.flatMap(\.1).map(\.json)
    if let (undoName, ops) = heard.first, heard.count == 1 {
        document.applyEdit(undoName, ops)
    }
    let after = document.editedProject.snapshot.clip(2).flatMap(read)
    check(title,
          section != nil && found && heard.count == 1 && heard.first?.0 == undo
            && got == expected && before != expect && after == expect,
          "canvas \(fps.num)/\(fps.den) fps, section \(section != nil), control \(found), "
            + "heard \(heard.map(\.0)) (want \"\(undo)\")"
            + "\n       got  \(got)\n       want \(expected)"
            + "\n       stored \(before.map(String.init) ?? "nil") → "
            + "\(after.map(String.init) ?? "nil") (want \(expect))")
    withExtendedLifetime((document, inspector, pane)) {}
}

// MARK: - A1–A5 the Audio inspector's ramps

let duck = DuckProps(level: 0.375, attack: 120_000, release: 540_000)
write(
    "A1 Ducking ▸ Attack 0.01 s is stored as 6000 ticks (snapped would be 0)",
    package: "av", seed: audio(AudioPatch(duck: .some(duck))), tab: .sound,
    section: "audio.duck", label: "Attack", typed: "0.01", undo: "Duck Attack",
    want: { binding in
        binding.ops(
            audio: AudioPatch(
                duck: .some(DuckProps(level: duck.level, attack: 6_000, release: duck.release))))
    },
    read: { $0.audioProps.duck?.attack }, expect: 6_000)

write(
    "A2 Ducking ▸ Release 0.11 s is stored as 66000 ticks (snapped would be 60000)",
    package: "av", seed: audio(AudioPatch(duck: .some(duck))), tab: .sound,
    section: "audio.duck", label: "Release", typed: "0.11", undo: "Duck Release",
    want: { binding in
        binding.ops(
            audio: AudioPatch(
                duck: .some(DuckProps(level: duck.level, attack: duck.attack, release: 66_000))))
    },
    read: { $0.audioProps.duck?.release }, expect: 66_000)

let fades = AudioPatch(fadeIn: 120_000, fadeOut: 120_000)
write(
    "A3 Fades ▸ Fade in 0.01 s is stored as 6000 ticks (snapped would be 0)",
    package: "av", seed: audio(fades), tab: .sound,
    section: "audio.fades", label: "Fade in", typed: "0.01", undo: "Fade In",
    want: { binding in binding.ops(audio: AudioPatch(fadeIn: 6_000)) },
    read: { $0.audioProps.fadeIn }, expect: 6_000)

write(
    "A4 Fades ▸ Fade out 0.26 s is stored as 156000 ticks (snapped would be 160000)",
    package: "av", seed: audio(fades), tab: .sound,
    section: "audio.fades", label: "Fade out", typed: "0.26", undo: "Fade Out",
    want: { binding in binding.ops(audio: AudioPatch(fadeOut: 156_000)) },
    read: { $0.audioProps.fadeOut }, expect: 156_000)

let compressor = CompressorProps(
    thresholdDb: -24, ratio: 4, attack: 12_000, release: 240_000, makeupDb: 3)
write(
    "A5 Compressor ▸ Attack 10 ms is stored as 6000 ticks (its own converter, unchanged)",
    package: "av", seed: audio(AudioPatch(compressor: .some(compressor))), tab: .sound,
    section: "audio.compressor", label: "Attack", typed: "10", undo: "Compressor Attack",
    want: { binding in
        binding.ops(
            audio: AudioPatch(
                compressor: .some(
                    CompressorProps(
                        thresholdDb: compressor.thresholdDb, ratio: compressor.ratio,
                        attack: 6_000, release: compressor.release,
                        makeupDb: compressor.makeupDb))))
    },
    read: { $0.audioProps.compressor?.attack }, expect: 6_000)

// MARK: - G1–G2 the fade handle's drag still snaps

let thirty = Fps(num: 30, den: 1)
let clipEnd = ReelTime.ticks(seconds: 6)
for (name, edge) in [("G1", TimelineEdge.start), ("G2", TimelineEdge.end)] {
    var session = FadeHandleSession(
        clip: 2, edge: edge, clipStart: 0, clipEnd: clipEnd, length: 0)
    func pointer(_ length: Ticks) -> Ticks { edge == .start ? length : clipEnd - length }
    session.update(time: pointer(6_000), fps: thirty)
    let short = session.length
    session.update(time: pointer(156_000), fps: thirty)
    let long = session.length
    let op = session.op.json
    let key = edge == .start ? "fade_in" : "fade_out"
    check(
        "\(name) the \(edge == .start ? "fade-in" : "fade-out") handle dragged 6000 / 156000 "
            + "ticks from its edge snaps to 0 / 160000",
        short == 0 && long == 160_000 && op.contains("\"\(key)\":160000"),
        "clip 0…\(clipEnd) at 30/1 fps, lengths \(short) / \(long), op \(op)")
}

// MARK: - G3 Reveal still snaps

let animation = TextAnimation(kind: .lineRise, inDuration: 240_000, outDuration: 360_000)
write(
    "G3 Reveal ▸ In 0.26 s is still snapped to 160000 ticks",
    package: "text", seed: text(TextPatch(animation: .some(animation))), tab: .text,
    section: "text.animation", label: "In", typed: "0.26", undo: "Animation In",
    want: { binding in
        binding.ops(
            text: TextPatch(
                animation: .some(
                    TextAnimation(
                        kind: animation.kind, inDuration: 160_000,
                        outDuration: animation.outDuration))))
    },
    read: { $0.text?.animation?.inDuration }, expect: 160_000)

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
