// Road map "audio" AP11 — the Ducking section's rows on a PASTED spanless
// Speech duck (spec §11 AU-111; the AP11 review's finding 1). The probe
// `audio_ap11_proof.py --probe` builds and runs.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`, on
// `swift_build.py`'s line, so the row it drives is `AudioPane.duckSection`'s
// own.
//
//   audio_ap11_probe <request.json> <answer.json>
//
// `request.json` names the package the proof wrote:
//   duck  clip 2 over media 91 at 0 and clip 3 over media 92 at 6 s, one
//         track, both media movies with sound and no `speech`
// One JSON object out: `rows`, each a name, ok and detail.
//
// Each row opens the package, saves media 91's spans and turns Speech
// ducking on for clip 2, then Paste Attributes (audio) from clip 2 onto clip
// 3 — clip 3 now has a Speech duck and media 92 no spans. With clip 3
// selected, Level 40 % is committed through the row's own field and the ops
// the inspector hears are applied to the document's project.
//
// P1: media 92's voice cache is written first (one run of 0.9 among
//     zeros). The row sends `set_media_speech` for media 92 with
//     `DuckSpeech.spans` of that cache, then the `set_audio`; together they
//     APPLY (the level is 0.4, the mode still speech, media 92 has the
//     spans) — as `set_audio` over MCP applies the same patch.
// P2: no cache for media 92. The row sends the `set_audio` alone and the
//     core refuses it in its own sentence, rather than the row sending
//     nothing.
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

let second: Ticks = 600_000

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func row(_ section: InspectorSection?, _ label: String) -> InspectorRowView? {
    guard let section else { return nil }
    return walk(section).compactMap { $0 as? InspectorRowView }.first { row in
        row.arrangedSubviews.contains { ($0 as? InspectorRowLabel)?.stringValue == label }
    }
}

func stored<T>(_ object: Any?, _ name: String, as: T.Type) -> T? {
    guard let object else { return nil }
    return Mirror(reflecting: object).children.first { $0.label == name }?.value as? T
}

/// Commits `text` through a field the way a click-away does.
func commit(_ section: InspectorSection?, _ label: String, _ text: String) -> Bool {
    guard let control = row(section, label).flatMap({
        walk($0).compactMap { $0 as? OptionFieldControl }.first
    }), let field = stored(control, "field", as: NSTextField.self) else { return false }
    field.stringValue = text
    control.controlTextDidEndEditing(
        Notification(name: NSControl.textDidEndEditingNotification, object: field))
    return true
}

/// The package opened, media 91's spans saved, Speech on for clip 2, and its
/// audio pasted onto clip 3; nil (with a failed row) when any step fails.
func seeded(_ title: String) -> ProjectDocument? {
    guard let path = request["duck"] as? String else {
        check(title, false, "the duck fixture is not named")
        return nil
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        check(title, false, "the duck fixture did not open: \(error)")
        return nil
    }
    let speech: [ReelOp] = [
        .setMediaSpeech(media: 91, spans: [[0, second]]),
        .setAudioRaw(clips: [2], patch: ["duck": ["mode": "speech", "level": 0.5]]),
    ]
    guard case .applied(let voiced)? = try? document.project.applying(speech),
          let data = voiced.json.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          var clip = (root["clips"] as? [[String: Any]])?.first(where: {
              ($0["id"] as? NSNumber)?.uint32Value == 2
          })
    else {
        check(title, false, "clip 2's Speech duck did not apply")
        return nil
    }
    clip["track"] = 0
    document.applyEdit("Seed", speech + [
        .pasteAttributes(clips: [3], payload: ["clips": [clip], "media": []], groups: ["audio"]),
    ])
    let snapshot = document.project.snapshot
    guard snapshot.clip(3)?.audio?.duck?.mode == .speech, snapshot.media(92)?.speech == nil,
          snapshot.media(91)?.speech != nil
    else {
        check(title, false, "the paste did not leave clip 3 a spanless Speech duck")
        return nil
    }
    return document
}

/// Level 40 % through the row on clip 3; the ops heard, or nil.
func level(_ document: ProjectDocument) -> (found: Bool, heard: [(String, [ReelOp])]) {
    let inspector = InspectorViewController()
    inspector.document = document
    var heard: [(String, [ReelOp])] = []
    inspector.onEdit = { name, ops in heard.append((name, ops)) }
    document.selection = [3]
    document.selectAction(nil)
    inspector.binding.invalidate()
    let pane = ClipPane(inspector: inspector)
    pane.binding.invalidate()
    pane.choose(.sound)
    pane.rebuild()
    pane.refresh()
    let found = commit(pane.sections.first { $0.id == "audio.duck" }, "Level", "40")
    withExtendedLifetime((inspector, pane)) {}
    return (found, heard)
}

func describe(_ edit: ReelEdit?) -> String {
    switch edit {
    case .applied?: return "applied"
    case .identity?: return "identity"
    case .refused(let refusal)?: return "refused (\(refusal.op)): \(refusal.reason)"
    case nil: return "threw"
    }
}

// MARK: - P1 with a voice cache

if let document = seeded("P1 Level on a pasted spanless Speech duck saves the spans and applies"),
   let directory = document.cacheDirectory, let media = document.project.snapshot.media(92)
{
    var p = [Float](repeating: 0, count: MediaSpeech.chunkCount(duration: media.duration))
    for i in 20..<60 where i < p.count { p[i] = 0.9 }
    let file = MediaImporter.speechURL(for: 92, in: directory)
    try? FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let wrote = (try? p.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: file)) != nil
        && MediaImporter.writeStamp(
            MediaImporter.SpeechStamp(
                MediaImporter.CacheStamp(
                    size: 0, modified: 0, duration: media.duration, width: 1920, height: 1080,
                    hasVideo: true, hasAudio: true, thumbnailHeight: 0, maxThumbnails: 0,
                    peakBucketsPerSecond: 0)),
            to: MediaImporter.speechMarkerURL(for: 92, in: directory))
    let want = DuckSpeech.spans(p, duration: media.duration)
    let (found, heard) = level(document)
    let ops = heard.flatMap(\.1)
    let edit = try? document.project.applying(ops)
    var after = "not applied"
    var ok = wrote && found && heard.count == 1 && heard.first?.0 == "Duck Level"
        && ops.map(\.name) == ["set_media_speech", "set_audio"]
    if case .applied(let updated)? = edit {
        let s = updated.snapshot
        let duck = s.clip(3)?.audio?.duck
        after = "clip 3 duck \(String(describing: duck)), media 92 speech "
            + "\(String(describing: s.media(92)?.speech))"
        ok = ok && duck?.mode == .speech && abs((duck?.level ?? 0) - 0.4) < 1e-9
            && s.media(92)?.speech == want && !want.isEmpty
    } else {
        ok = false
    }
    check("P1 Level on a pasted spanless Speech duck saves the spans and applies", ok,
          "cache written \(wrote), field \(found), heard \(heard.map(\.0)) "
            + "\(ops.map(\.json)); \(describe(edit)); \(after); want spans \(want)")
    try? FileManager.default.removeItem(at: directory)
}

// MARK: - P2 without one

if let document = seeded("P2 Level with no voice cache is the core's refusal, not nothing") {
    let (found, heard) = level(document)
    let ops = heard.flatMap(\.1)
    let edit = try? document.project.applying(ops)
    var refused = false
    if case .refused(let refusal)? = edit {
        refused = refusal.op == "set_audio" && refusal.reason.contains("speech spans")
    }
    check("P2 Level with no voice cache is the core's refusal, not nothing",
          found && heard.count == 1 && ops.map(\.name) == ["set_audio"] && refused,
          "field \(found), heard \(heard.map(\.0)) \(ops.map(\.json)); \(describe(edit))")
    if let directory = document.cacheDirectory { try? FileManager.default.removeItem(at: directory) }
}

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
