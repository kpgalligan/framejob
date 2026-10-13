// Road map 9, phase 2 — the sub-tabs and the pinned block's probe
// (`clip_inspector2_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — so every row drives the
// app's own `ProjectDocument`, `EditorViewController`, `InspectorViewController`
// and `ClipPane`. Nothing private is widened.
//
//   clip_inspector2_probe <request.json> <answer.json>
//   clip_inspector2_probe --convert <png> <answer.json>
//
// `request.json` names the packages the proof wrote: `av` (clip 2, a video
// with sound on track 1 carrying action 10; clip 3, the same media on track
// 7), `video` (a video with no sound), `audio` (an audio-only file), `text`,
// `shape`, and `park` (a shape clip at 2 s whose duration, 1 000 ticks, is
// under one 30 fps frame, with one action as long as the clip). One JSON
// object out: `rows`, each a name, ok and detail. Row names start with their
// T-number, which is what the mutant mode reads.
import AppKit

// `--convert <png> <out.json>`: the action ink in the PNG's OWN colour space
// (`clip_inspector_probe.swift`'s mode, carried over).
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--convert" {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])),
          let rep = NSBitmapImageRep(data: data)
    else { exit(4) }
    let color = NSColor(srgbRed: 0x5C / 255.0, green: 0xD6 / 255.0, blue: 0xB0 / 255.0, alpha: 1)
    guard let there = color.usingColorSpace(rep.colorSpace) else { exit(5) }
    let answer: [String: Any] = [
        "space": rep.colorSpace.localizedName ?? "?",
        "mint": [there.redComponent, there.greenComponent, there.blueComponent].map {
            Double($0) * 255
        },
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

func opened(_ key: String) -> ProjectDocument? {
    guard let path = request[key] as? String else { return nil }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        check("T0 the \(key) fixture opens", false, "\(error)")
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

/// A Clip pane over a document, with no window: the rows T1, T2 and T4 read.
/// The pane's inspector and the inspector's document are both weak, so each
/// pair is kept here for the probe's life.
var kept: [AnyObject] = []
func clipPane(_ key: String, select ids: Set<UInt32>) -> ClipPane? {
    guard let document = opened(key) else { return nil }
    let inspector = InspectorViewController()
    inspector.document = document
    document.selection = ids
    inspector.binding.invalidate()
    kept += [document, inspector]
    return ClipPane(inspector: inspector)
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func names(_ tabs: [ClipSubTab]) -> String { tabs.map(\.rawValue).joined(separator: ", ") }

/// The ids of one tab's sections, after a rebuild.
func sectionIDs(_ pane: ClipPane, _ tab: ClipSubTab) -> [String] {
    pane.choose(tab)
    pane.rebuild()
    return pane.sections.map(\.id)
}

// MARK: - T1 tabs per kind, and the default

// Grading GR2 (spec §11 GR-2): Color after Picture for a clip with source
// pixels; an audio-only file's clip draws nothing, so it gets neither.
let kinds: [(String, [ClipSubTab])] = [
    ("av", [.picture, .color, .sound, .clip]), ("video", [.picture, .color, .clip]),
    ("audio", [.sound, .clip]), ("text", [.text, .picture, .clip]),
    ("shape", [.shape, .picture, .clip]),
]
for (key, want) in kinds {
    let name = "T1 \(key): tabs [\(names(want))], default \(want[0].rawValue)"
    guard let pane = clipPane(key, select: [2]) else {
        check(name, false, "no pane")
        continue
    }
    check(name, pane.subTabs == want && pane.activeSubTab == want[0],
          "tabs [\(names(pane.subTabs))], active \(pane.activeSubTab.rawValue)")
}

// MARK: - T2 section ids per tab, in the handoff's order

let picture = ["video.shadow", "video.filters", "video.reflection", "video.spotlight",
               "video.obscure"]
let expected: [(String, ClipSubTab, [String])] = [
    ("text", .text, ["text.content", "text.font", "text.style", "text.outline",
                     "text.backdrop", "text.box", "text.animation", "text.presets"]),
    ("text", .picture, ["video.transform"] + picture),
    ("text", .clip, ["clip.timing", "video.motion"]),
    ("av", .picture, ["video.transform", "video.crop", "video.corner", "video.chroma"]
        + picture),
    ("av", .color, ["video.light", "video.color", "video.wheels", "video.curves", "video.look"]),
    ("av", .sound, ["audio.volume", "audio.fades", "audio.duck", "audio.noise",
                    "audio.compressor", "audio.mix"]),
    ("av", .clip, ["clip.timing", "video.speed", "video.motion"]),
]
var t2Panes: [String: ClipPane] = [:]
for (key, tab, want) in expected {
    let name = "T2 \(key) clip, \(tab.rawValue) tab: \(want.count) sections in order"
    guard let pane = t2Panes[key] ?? clipPane(key, select: [2]) else {
        check(name, false, "no pane")
        continue
    }
    t2Panes[key] = pane
    let got = sectionIDs(pane, tab)
    check(name, got == want, "got \(got)")
}

// MARK: - T3 the choice: kept, and forgotten on a selection change

if let (document, controller) = editor("av", select: [2]) {
    func active() -> ClipSubTab? {
        walk(controller.view).compactMap { $0 as? ClipPane }.first?.activeSubTab
    }
    func reselect(_ ids: Set<UInt32>) {
        document.selection = ids
        controller.viewStateDidChange()
        spin(0.4)
    }
    controller.inspector?.selectClipSubTab(.sound)
    spin(0.4)
    let picked = active()
    check("T3 selectClipSubTab(.sound) → Sound", picked == .sound,
          "\(picked?.rawValue ?? "nil")")
    reselect([3])
    let other = active()
    check("T3 selecting clip B → the default (Picture)", other == .picture,
          "\(other?.rawValue ?? "nil")")
    reselect([2])
    let back = active()
    check("T3 selecting A AGAIN → the default (Picture), not Sound", back == .picture,
          "\(back?.rawValue ?? "nil")")
    controller.inspector?.selectClipSubTab(.sound)
    spin(0.4)
    controller.selectAction(10, on: 2)
    spin(0.4)
    let kept = active()
    check("T3 selecting an action on A keeps a fresh Sound choice",
          kept == .sound && document.selectedAction == 10,
          "\(kept?.rawValue ?? "nil"), selected action "
            + "\(document.selectedAction.map { "\($0)" } ?? "nil")")
}

// MARK: - T4 the two renamed titles

func title(_ key: String, _ tab: ClipSubTab, _ id: String) -> String? {
    guard let pane = clipPane(key, select: [2]) else { return nil }
    pane.choose(tab)
    pane.rebuild()
    return pane.sections.first { $0.id == id }?.title
}
let motion = title("av", .clip, "video.motion")
check("T4 video.motion is titled \"Motion presets\"", motion == "Motion presets",
      "\(motion ?? "nil")")
let reveal = title("text", .text, "text.animation")
check("T4 text.animation is titled \"Reveal\"", reveal == "Reveal", "\(reveal ?? "nil")")

// MARK: - T5 the badge count

let end = ActionPatch(video: VideoPatch(x: 10, opacity: 0.5), text: TextPatch(size: 40))
let counts = Dictionary(uniqueKeysWithValues: ClipSubTab.allCases.map {
    ($0.rawValue, $0.keyedCount(in: end))
})
check("T5 keyedCount of {video: {opacity, x}, text: {size}}: picture 2, text 1, sound 0, clip 0",
      counts["picture"] == 2 && counts["text"] == 1 && counts["sound"] == 0
        && counts["clip"] == 0,
      "\(counts.sorted { $0.key < $1.key })")

// MARK: - T6 the block is pinned, outside the scroll view

if let (_, controller) = editor("av", select: [2]) {
    let blocks = walk(controller.view).compactMap { $0 as? ClipHeaderBlock }
    func scrolled(_ view: NSView) -> Bool {
        var next = view.superview
        while let parent = next {
            if parent is NSScrollView { return true }
            next = parent.superview
        }
        return false
    }
    let strips = blocks.first.map { walk($0).compactMap { $0 as? ClipSubTabsView } } ?? []
    check("T6 one ClipHeaderBlock with no NSScrollView ancestor, holding a ClipSubTabsView",
          blocks.count == 1 && !blocks.contains(where: scrolled) && strips.count == 1
            && blocks.first?.subTabsView === strips.first,
          "\(blocks.count) block(s), scrolled \(blocks.map(scrolled)), \(strips.count) strip(s)")
    controller.inspector?.select(.media)
    spin(0.4)
    let media = walk(controller.view).compactMap { $0 as? ClipHeaderBlock }
    check("T6 on the Media tab there is none", media.isEmpty, "\(media.count) block(s)")
}

// MARK: - T7 the park clamp on a clip shorter than a frame

if let (document, controller) = editor("park", select: [2]) {
    controller.selectAction(3, on: 2)
    spin(0.4)
    check("T7 selecting the action parks at the clip's start (1200000), not before it",
          document.playhead == 1_200_000 && document.selectedAction == 3,
          "playhead \(document.playhead), selected "
            + "\(document.selectedAction.map { "\($0)" } ?? "nil")")
}

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
