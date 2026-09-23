// Road map 9, phase 1 — the selected action's probe (`clip_inspector_proof.py`
// builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — so every row drives the
// app's own `ProjectDocument`, `EditorViewController`, `InspectorBinding`,
// `TimelineView` and `ActionLaneView`. Nothing private is widened.
//
//   clip_inspector_probe <request.json> <answer.json>
//
// `request.json` names three packages the proof wrote: `shapes` (A 0–6 s on
// track 1 with actions 10 [1, 2) and 11 [3, 4); B 0–6 s on track 2 with 12
// [1, 2.5); E 6–12 s on track 1, no actions), `move` (A at 2–8 s with the
// same two actions) and `media` (an audio-only C and a video-with-sound D).
// One JSON object out: `rows`, each a name, ok and detail. Row names start
// with their S-number, which is what the mutant mode reads.
import AppKit

// `--convert <png> <out.json>`: the action ink and the shape tint in the
// PNG's OWN colour space. The harness writes at the display's colour space
// (Display P3 on this machine), not sRGB, so an sRGB literal is compared
// there only after ColorSync has converted it — the same conversion the
// render's fills went through.
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--convert" {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])),
          let rep = NSBitmapImageRep(data: data)
    else { exit(4) }
    func converted(_ r: Int, _ g: Int, _ b: Int) -> [Double] {
        let color = NSColor(
            srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        guard let there = color.usingColorSpace(rep.colorSpace) else { return [] }
        return [there.redComponent, there.greenComponent, there.blueComponent].map {
            Double($0) * 255
        }
    }
    let answer: [String: Any] = [
        "space": rep.colorSpace.localizedName ?? "?",
        "mint": converted(0x5C, 0xD6, 0xB0), "clipShape": converted(0x24, 0x76, 0x86),
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: answer) else { exit(5) }
    try? json.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    exit(0)
}

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

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

let second: Ticks = 600_000
func at(_ seconds: Double) -> Ticks { Ticks(seconds * Double(second)) }

func opened(_ key: String) -> ProjectDocument? {
    guard let path = request[key] as? String else { return nil }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        check("S0 the \(key) fixture opens", false, "\(error)")
        return nil
    }
    return document
}

func editor(_ key: String, select ids: Set<UInt32>) -> (ProjectDocument, EditorViewController)? {
    guard let document = opened(key) else { return nil }
    document.selection = ids
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.0)
    guard let controller = document.windowControllers.first?.contentViewController
        as? EditorViewController
    else { return nil }
    return (document, controller)
}

func describe(_ id: UInt32?) -> String { id.map { String($0) } ?? "nil" }

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

// MARK: - S1 entry

if let (document, controller) = editor("shapes", select: [2]) {
    var trail: [String] = []
    func step(_ label: String, _ want: UInt32?) -> Bool {
        let got = document.selectedAction
        trail.append("\(label): \(describe(got))")
        return got == want
    }
    var ok = true
    controller.setPlayhead(at(0.5))
    ok = step("outside", nil) && ok
    check("S1 outside every span → nil", ok, trail.joined(separator: "; "))
    controller.setPlayhead(at(1.5))
    check("S1 into action 1 → 1", step("into 1", 10), trail.joined(separator: "; "))
    controller.setPlayhead(at(2.5))
    check("S1 out of it → still 1", step("out", 10), trail.joined(separator: "; "))
    controller.setPlayhead(at(1.5))
    _ = step("back in", 10)
    let consumed = controller.deselectActionCommand()
    controller.setPlayhead(at(1.6))
    let stays = step("esc, then a move inside", nil)
    check("S1 esc inside → nil, and a move within the span stays nil",
          consumed && stays, trail.joined(separator: "; "))
    check("S1 esc with nothing selected falls through (false)",
          !controller.deselectActionCommand())
    controller.setPlayhead(at(2.5))
    controller.setPlayhead(at(1.5))
    check("S1 leave and re-enter → 1", step("re-enter", 10), trail.joined(separator: "; "))
    controller.setPlayhead(at(3.5))
    check("S1 into action 2 → 2", step("into 2", 11), trail.joined(separator: "; "))

    // ⌥⌘K under a stationary playhead, esc, ⌘Z, ⌘⇧Z.
    controller.setPlayhead(at(5.0))
    let before = document.editedProject.snapshot.clip(2)?.actions.count ?? 0
    controller.addActionAtPlayheadCommand()
    spin(0.3)
    let added = document.editedProject.snapshot.clip(2)?.actions
        .first { $0.start <= at(5.0) && at(5.0) < $0.endTime }
    check("S1 ⌥⌘K selects the action it added",
          added != nil && document.selectedAction == added?.id,
          "count \(before) → \(document.editedProject.snapshot.clip(2)?.actions.count ?? 0), "
            + "selected \(describe(document.selectedAction)), added \(describe(added?.id))")
    controller.deselectActionCommand()
    document.undoManager?.undo()
    spin(0.3)
    let undone = document.editedProject.snapshot.clip(2)?.actions.count ?? 0
    document.undoManager?.redo()
    spin(0.3)
    let redone = document.editedProject.snapshot.clip(2)?.actions.count ?? 0
    check("S1 ⌥⌘K, esc, ⌘Z, ⌘⇧Z under a stationary playhead → nil after the redo",
          undone == before && redone == before + 1 && document.selectedAction == nil,
          "counts \(undone), \(redone); selected \(describe(document.selectedAction))")
}

if let (document, controller) = editor("move", select: [2]) {
    controller.setPlayhead(at(2.5))
    let outside = document.selectedAction
    guard let clip = document.editedProject.snapshot.clip(2) else { exit(3) }
    document.beginLiveEdit()
    document.updateLiveEdit(.moveClip(clips: [2], delta: at(1.0) - clip.start))
    document.endLiveEdit("Move")
    spin(0.3)
    let moved = document.editedProject.snapshot.clip(2)
    let under = moved.map { $0.clipTime(document.playhead) } ?? -1
    check("S1 a moveClip that slides a span under the stationary playhead → nil",
          outside == nil && under >= at(1.0) && under < at(2.0)
            && document.selectedAction == nil,
          "before \(describe(outside)), clip time under the playhead \(under), "
            + "selected \(describe(document.selectedAction))")
}

// MARK: - S2 a selection change

if let (document, controller) = editor("shapes", select: [2]) {
    controller.setPlayhead(at(1.5))
    let first = document.selectedAction
    document.selection = [4]
    let cleared = document.selectedAction
    document.selection = [3]
    let other = document.selectedAction
    check("S2 a selection change clears (E has none under the playhead)",
          first == 10 && cleared == nil, "A \(describe(first)), E \(describe(cleared))")
    check("S2 … and auto-selects the new clip's action under the playhead",
          other == 12, "B \(describe(other))")
    controller.viewStateDidChange()
}

// MARK: - S3 removal, ⌫, and a two-clip selection

if let (document, controller) = editor("shapes", select: [2]) {
    controller.setPlayhead(at(1.5))
    let picked = document.selectedAction
    controller.removeSelectedActionCommand()
    spin(0.3)
    let ids = document.editedProject.snapshot.clip(2)?.actions.map { $0.id } ?? []
    check("S3 removing the selected action clears it with no re-select",
          picked == 10 && !ids.contains(10) && document.selectedAction == nil,
          "picked \(describe(picked)), left \(ids), selected \(describe(document.selectedAction))")
    controller.setPlayhead(at(3.5))
    controller.deleteSelection()
    spin(0.3)
    let clip = document.editedProject.snapshot.clip(2)
    check("S3 ⌫ with an action selected removes the action, not its clip",
          clip != nil && !(clip?.actions.contains { $0.id == 11 } ?? true)
            && document.selectedAction == nil,
          "clip \(clip != nil), actions \(clip?.actions.map { $0.id } ?? [])")
}

if let (document, controller) = editor("shapes", select: [2, 3]) {
    controller.setPlayhead(at(5.0))
    let before = document.editedProject.snapshot.clips.reduce(0) { $0 + $1.actions.count }
    controller.addActionAtPlayheadCommand()
    spin(0.3)
    let after = document.editedProject.snapshot.clips.reduce(0) { $0 + $1.actions.count }
    check("S3 two clips selected: ⌥⌘K adds and selects nothing",
          after == before + 1 && document.selectedAction == nil,
          "actions \(before) → \(after), selected \(describe(document.selectedAction))")
    controller.deleteSelection()
    spin(0.3)
    let left = document.editedProject.snapshot.clips.map { $0.id }
    check("S3 … then ⌫ deletes both clips", !left.contains(2) && !left.contains(3), "\(left)")
}

if let (document, controller) = editor("shapes", select: [2, 3]) {
    // The timeline's band click: `selectClip(_, flags: [])` keeps a
    // selection that already holds the clip, then `onActionSelected`.
    controller.selectAction(10, on: 2)
    spin(0.3)
    check("S3 a band click under a two-clip selection selects the clip and the action",
          document.selection == [2] && document.selectedAction == 10,
          "selection \(document.selection.sorted()), selected \(describe(document.selectedAction))")
}

// MARK: - S4 the binding writes the END state

if let document = opened("shapes") {
    let inspector = InspectorViewController()
    inspector.document = document
    let binding = inspector.binding
    document.selection = [2]
    document.playhead = at(1.5)
    document.selectAction(10)
    binding.invalidate()
    let opacity = binding.videoProps.opacity
    check("S4 at the span's midpoint the field reads the END opacity (0), not 0.5",
          abs(opacity) < 1e-9, "\(opacity)")
    let inside = binding.ops(video: VideoPatch(opacity: 0.25))
    check("S4 ops(video:) with 1 selected is one set_action_end naming it",
          inside.count == 1 && inside.first?.name == "set_action_end"
            && (inside.first?.args["action"] as? UInt32) == 10,
          inside.map { "\($0.name) \($0.args)" }.joined(separator: "; "))
    document.selectAction(nil)
    binding.invalidate()
    let base = binding.ops(video: VideoPatch(opacity: 0.25))
    check("S4 … with none selected, one set_video (the playhead still inside)",
          base.count == 1 && base.first?.name == "set_video" && document.selectedAction == nil,
          base.map { $0.name }.joined(separator: ", "))
}

if let document = opened("media") {
    let inspector = InspectorViewController()
    inspector.document = document
    let binding = inspector.binding
    document.selection = [4]
    document.playhead = at(0.5)
    let auto = document.selectedAction
    document.selectAction(13)
    binding.invalidate()
    let pan = binding.ops(audio: AudioPatch(pan: 0.5))
    let volume = binding.ops(audio: AudioPatch(volume: 0.8))
    check("S4 audio: pan goes to set_audio with an action selected (CI-3)",
          document.selectedAction == 13 && pan.count == 1 && pan.first?.name == "set_audio",
          "auto \(describe(auto)); " + pan.map { "\($0.name) \($0.args)" }.joined(separator: "; "))
    check("S4 audio: volume goes to set_action_end",
          volume.count == 1 && volume.first?.name == "set_action_end",
          volume.map { "\($0.name) \($0.args)" }.joined(separator: "; "))
}

// MARK: - S5 hits

if let document = opened("shapes"), let clip = document.project.snapshot.clip(2),
    let action = clip.actions.first(where: { $0.id == 10 })
{
    let timeline = TimelineView()
    timeline.frame = NSRect(x: 0, y: 0, width: 1400, height: 400)
    timeline.update(
        snapshot: document.project.snapshot, selection: [2], playhead: 0, inOutRange: nil,
        cacheDirectory: nil)
    for size in 0...2 {
        timeline.trackHeightIndex = size
        let layout = timeline.layout
        let index = document.project.snapshot.tracks.firstIndex { $0.id == clip.track } ?? 0
        let rect = layout.clipRect(clip, row: layout.row(forTrackIndex: index))
        let lane = TimelineContentView.actionLane(
            content: TimelineContentView.contentRect(rect), sizeIndex: size)
        let band = TimelineContentView.bandRect(action, clip: clip, lane: lane, layout: layout)
        let inside = timeline.content.actionBandHit(
            clip, rect: rect, at: CGPoint(x: band.midX, y: band.midY))
        let below = timeline.content.actionBandHit(
            clip, rect: rect, at: CGPoint(x: band.midX, y: lane.maxY + 1))
        check("S5 actionBandHit at \(["S", "M", "L"][size]): inside the lane → 10, 1 pt below → nil",
              inside == 10 && below == nil && lane.height == DS.actionLaneHeights[size],
              "lane \(lane), band \(band), inside \(describe(inside)), below \(describe(below))")
    }
}

if let document = opened("media") {
    let snapshot = document.project.snapshot
    let timeline = TimelineView()
    timeline.frame = NSRect(x: 0, y: 0, width: 1400, height: 400)
    timeline.update(
        snapshot: snapshot, selection: [], playhead: 0, inOutRange: nil, cacheDirectory: nil)
    timeline.trackHeightIndex = 1
    let layout = timeline.layout
    func geometry(_ id: UInt32) -> (ClipSnapshot, CGRect, CGRect, CGRect)? {
        guard let clip = snapshot.clip(id),
              let index = snapshot.tracks.firstIndex(where: { $0.id == clip.track })
        else { return nil }
        let rect = layout.clipRect(clip, row: layout.row(forTrackIndex: index))
        let content = TimelineContentView.contentRect(rect)
        let audio = TimelineContentView.regions(
            in: content, hasVideo: timeline.hasVideo(clip), hasAudio: true
        ).audio
        let handle = TimelineContentView.fadeRect(clip, edge: .start, audio: audio, layout: layout)
        let lane = TimelineContentView.actionLane(content: content, sizeIndex: 1)
        return (clip, rect, handle, lane)
    }
    if let (clip, _, handle, _) = geometry(5) {
        let hit = timeline.content.hit(at: CGPoint(x: handle.midX, y: handle.midY))
        check("S5 a video clip: hit(at:) at the start fade handle → .fade",
              hit == .fade(clip.id, .start), "\(hit) at \(handle)")
    }
    if let (clip, _, handle, lane) = geometry(4) {
        let onHandle = timeline.content.hit(at: CGPoint(x: handle.midX, y: handle.midY))
        let past = CGPoint(x: handle.maxX + 2 + 3, y: lane.midY)
        let beside = timeline.content.hit(at: past)
        check("S5 an audio-only clip: the start fade handle inside the lane → .fade",
              handle.intersects(lane) && onHandle == .fade(clip.id, .start),
              "\(onHandle) at \(handle), lane \(lane)")
        check("S5 … and 3 pt right of the handle's zone, inside the lane → .action",
              beside == .action(clip: clip.id, action: 13), "\(beside) at \(past)")
    }
}

// MARK: - S6 the Clip tab's lane

if let (document, controller) = editor("shapes", select: [2]) {
    controller.setPlayhead(at(0.5))
    controller.viewStateDidChange()
    spin(0.5)
    func lane() -> ActionLaneView? {
        walk(controller.view).compactMap { $0 as? ActionLaneView }.first
    }
    if let view = lane(), let clip = document.editedProject.snapshot.clip(2) {
        let box = view.laneRect
        let rects = view.bandRects()
        let fractions = rects.map { band -> [Double] in
            [Double((band.rect.minX - box.minX) / box.width),
             Double((band.rect.maxX - box.minX) / box.width)]
        }
        let want = ActionBands.ordered(clip).map {
            [Double($0.start) / Double(clip.duration), Double($0.endTime) / Double(clip.duration)]
        }
        let close = fractions.count == want.count && zip(fractions, want).allSatisfy {
            abs($0[0] - $1[0]) < 1e-6 && abs($0[1] - $1[1]) < 1e-6
        }
        check("S6 bandRects() are the clip fractions, in time order",
              close && rects.map { $0.id } == [10, 11] && box.width > 100,
              "lane \(box), fractions \(fractions), want \(want)")
        check("S6 with nothing selected the Clip chip is active and the detail row hidden",
              view.isClipChipActive && !view.isDetailRowVisible && document.selectedAction == nil,
              "chip \(view.isClipChipActive), detail \(view.isDetailRowVisible)")
    } else {
        check("S6 bandRects() are the clip fractions, in time order", false, "no lane")
        check("S6 with nothing selected the Clip chip is active and the detail row hidden",
              false, "no lane")
    }
    controller.selectAction(10, on: 2)
    spin(0.5)
    if let view = lane() {
        check("S6 with an action selected the detail row shows and the chip is not active",
              view.isDetailRowVisible && !view.isClipChipActive && document.selectedAction == 10,
              "detail \(view.isDetailRowVisible), chip \(view.isClipChipActive), "
                + "playhead \(document.playhead)")
    } else {
        check("S6 with an action selected the detail row shows and the chip is not active",
              false, "no lane")
    }
    check("S6 selecting an action parks the playhead at its end",
          document.playhead == at(2.0), "\(document.playhead)")
}

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
