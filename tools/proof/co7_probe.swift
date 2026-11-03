// Road map "creator-jobs" CO7 (spec §11 CO-71, CO-72, CO-73): the probe of `co7_proof.py`,
// compiled as `main.swift` over `app/Sources` through `swift_build.build()` with
// `FRAMEJOB_DEV_TOOLS`, so every row drives the app's own `ClipPane`, `VideoPane+Layout`,
// `CameraLayoutCommand`, `LayoutOfferSheet`, `EditorViewController` and `ProjectDocument`.
//
//   co7-probe <request.json>
//
// The request names `work` (this run's folder), `camera` and `screen` (the proof's 1280 × 720
// and 1920 × 1080 testsrc movies, 6 s at 30 fps). Every fixture is one document: the screen at 0
// on the back track, the camera at 0 on the front track trimmed to [0, 4 s). One JSON object on
// stdout, `{"rows": [{"id", "pass", "detail"}]}`.
//
// - P1 (a windowless `ClipPane`, as `co3_probe`'s): `video.layout` after `video.transform` (and
//   `video.behind_subject` when present) and before `video.crop` with the camera selected, absent
//   with both clips selected; Circle + Top Left and Switch at Playhead at 2 s give a project
//   byte-equal to the editor's `switchCameraLayout` with Circle ▸ Top Left's `menuRows` tag on a
//   twin, each one undo step "Camera Layout" that one undo takes back; Duration 1.00 writes a
//   600000-tick layout action; with the playhead moved off the clip (5 s) and back (no other
//   refresh) Switch at Playhead is enabled both times, and pressed off the clip the project is
//   unchanged, there is no undo step and `projectDocumentDidRefuse` carries "does not play at".
// - P4 (an editor in an `NSWindow`): the screen holds a zoom at 3 s, the camera is selected, the
//   playhead at 1 s, Clip ▸ Camera Layout ▸ Side by Side: the sheet is attached, the project is
//   unchanged and no undo step made; its text holds the core's sentence and its buttons are
//   "Nest and Switch" and "Cancel"; Cancel (`window.endSheet(_:returnCode:)`) changes nothing;
//   Nest and Switch equals `switch_layout {nest: true}` on a twin, one undo "Camera Layout"
//   restores the project byte for byte.

import AppKit

var rows: [[String: Any]] = []

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": String(detail.prefix(1500))])
}

func printJSON(_ object: Any) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
}

guard CommandLine.arguments.count == 2,
    let requestData = FileManager.default.contents(atPath: CommandLine.arguments[1]),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let cameraPath = request["camera"] as? String, let screenPath = request["screen"] as? String
else {
    for id in ["P1", "P4"] { row(id, false, "the request could not be read") }
    printJSON(["rows": rows])
    exit(0)
}

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let second: Ticks = 600_000
var documents: [ProjectDocument] = []
var kept: [AnyObject] = []

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func finish() -> Never {
    for document in documents { document.removeTemporaryCacheDirectory() }
    printJSON(["rows": rows])
    exit(0)
}

/// The fixture: (document, screen clip, camera clip), or nil.
func makeDocument(zoomAt: Ticks? = nil) -> (ProjectDocument, UInt32, UInt32)? {
    let document = ProjectDocument()
    documents.append(document)
    for (path, w, h) in [(screenPath, 1920, 1080), (cameraPath, 1280, 720)] {
        document.performGroupedEdit("Media", [.addMedia(descriptor: MediaDescriptor(
            path: path, kind: .video, duration: 6 * second, width: w, height: h, fps: .thirty,
            hasVideo: true, hasAudio: false))])
    }
    let media = document.project.snapshot.media.map(\.id)
    guard media.count == 2 else { return nil }
    var ids: [UInt32] = []
    for index in 0..<2 {
        while document.project.snapshot.tracks.count <= index {
            document.performGroupedEdit(
                "Track", [.addTrack(index: document.project.snapshot.tracks.count)])
        }
        let track = document.project.snapshot.tracks[index].id
        document.performGroupedEdit("Clip", [.addClip(track: track, media: media[index], at: 0)])
        guard let clip = document.project.snapshot.clips.first(where: { $0.track == track })
        else { return nil }
        ids.append(clip.id)
    }
    document.performGroupedEdit("Trim", [.trimEnd(clip: ids[1], to: 4 * second)])
    if let zoomAt {
        document.performGroupedEdit("Zoom", [.addZoomAction(
            clip: ids[0], at: zoomAt,
            region: ZoomRegion(x: 0, y: 0, width: 960, height: 540))])
    }
    return (document, ids[0], ids[1])
}

/// An editor window over a fresh fixture.
func editor(zoomAt: Ticks? = nil) -> (ProjectDocument, EditorViewController, UInt32, UInt32)? {
    guard let (document, screen, camera) = makeDocument(zoomAt: zoomAt) else { return nil }
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.2)
    guard let controller = document.windowControllers.first?.contentViewController
        as? EditorViewController
    else { return nil }
    return (document, controller, screen, camera)
}

func clipPane(_ document: ProjectDocument, _ selection: Set<UInt32>) -> ClipPane {
    let inspector = InspectorViewController()
    inspector.document = document
    inspector.onEdit = { [weak document] name, ops in document?.applyEdit(name, ops) }
    document.selection = selection
    inspector.binding.invalidate()
    let pane = ClipPane(inspector: inspector)
    kept += [inspector, pane]
    pane.binding.invalidate()
    pane.choose(.picture)
    pane.rebuild()
    pane.refresh()
    return pane
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

let click = NSEvent.mouseEvent(
    with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)

func menuItem(_ choice: CameraLayoutChoice) -> NSMenuItem {
    let item = NSMenuItem(
        title: choice.title, action: #selector(EditorViewController.switchCameraLayout(_:)),
        keyEquivalent: "")
    item.tag = CameraLayoutChoice.menuRows.firstIndex(of: choice) ?? -1
    return item
}

func undoName(_ document: ProjectDocument) -> String {
    document.undoManager?.canUndo == true ? document.undoManager?.undoActionName ?? "" : ""
}

/// Undoes one step; whether it was `name` and gave back `json`.
func undoesTo(_ document: ProjectDocument, _ json: String, name: String) -> Bool {
    let named = undoName(document) == name
    document.undoManager?.undo()
    spin(0.1)
    return named && document.project.json == json
}

// ---- P1 -------------------------------------------------------------------------------------

let circleTopLeft = CameraLayoutChoice(kind: .corner, shape: .circle, corner: .topLeft)
if let (a, screenA, cameraA) = makeDocument(), let event = click,
    let (b, controller, _, cameraB) = editor()
{
    var problems: [String] = []
    let pane = clipPane(a, [cameraA])
    let order = pane.sections.map(\.id)
    let layout = order.firstIndex(of: "video.layout")
    let transform = order.firstIndex(of: "video.transform")
    let behind = order.firstIndex(of: "video.behind_subject")
    let crop = order.firstIndex(of: "video.crop")
    if layout == nil || transform == nil || crop == nil || layout! <= transform!
        || (behind != nil && layout! <= behind!) || layout! >= crop!
    {
        problems.append("one clip's sections \(order)")
    }
    let both = clipPane(a, [screenA, cameraA]).sections.map(\.id)
    if both.contains("video.layout") { problems.append("two clips' sections hold video.layout") }
    let single = clipPane(a, [cameraA])
    let section = single.sections.first { $0.id == "video.layout" }
    let button = section.flatMap {
        walk($0).compactMap { $0 as? OptionButtonControl }.first {
            $0.toolTip?.hasPrefix("Lay out this clip as the camera") == true
        }
    }
    if button == nil { problems.append("no Switch at Playhead button") }
    // Circle + Top Left, Switch at Playhead at 2 s, against the menu's item on twin B.
    single.layoutState.kind = .corner
    single.layoutState.shape = .circle
    single.layoutState.corner = .topLeft
    single.layoutState.seconds = 0.5
    a.playhead = 2 * second
    let beforeA = a.project.json
    button?.mouseDown(with: event)
    spin(0.2)
    let afterA = a.project.json
    let undoA = undoName(a)
    b.selection = [cameraB]
    b.playhead = 2 * second
    let beforeB = b.project.json
    let menuOn = controller.validateUserInterfaceItem(menuItem(circleTopLeft))
    controller.switchCameraLayout(menuItem(circleTopLeft))
    spin(0.2)
    let afterB = b.project.json
    let undoB = undoName(b)
    if afterA == beforeA { problems.append("Switch at Playhead changed nothing") }
    if afterA != afterB {
        problems.append("the section's project differs from the menu's (menu enabled \(menuOn))")
    }
    if beforeA != beforeB { problems.append("the twins differ before the switch") }
    if !undoesTo(a, beforeA, name: "Camera Layout") {
        problems.append("the section's undo step is \(undoA.debugDescription), not one undo")
    }
    if !undoesTo(b, beforeB, name: "Camera Layout") {
        problems.append("the menu's undo step is \(undoB.debugDescription), not one undo")
    }
    // Duration 1.00.
    single.layoutState.seconds = 1.0
    button?.mouseDown(with: event)
    spin(0.2)
    let action = a.project.snapshot.clip(cameraA)?.actions.first { $0.start == 2 * second }
    if action?.duration != 600_000 {
        problems.append("Duration 1.00 wrote \(String(describing: action?.duration)) ticks")
    }
    _ = undoesTo(a, beforeA, name: "Camera Layout")
    single.layoutState.seconds = 0.5
    // The playhead off the clip and back, with no other refresh; then a press off the clip.
    a.playhead = 5 * second
    let offEnabled = button?.alphaValue == 1
    a.playhead = 2 * second
    let backEnabled = button?.alphaValue == 1
    a.playhead = 5 * second
    var refusals: [String] = []
    let observer = NotificationCenter.default.addObserver(
        forName: .projectDocumentDidRefuse, object: a, queue: nil
    ) { note in
        if let refusal = note.userInfo?["refusal"] as? ReelRefusal {
            refusals.append(refusal.reason)
        }
    }
    let stepBefore = undoName(a)
    let canUndoBefore = a.undoManager?.canUndo == true
    button?.mouseDown(with: event)
    spin(0.2)
    NotificationCenter.default.removeObserver(observer)
    if !offEnabled || !backEnabled {
        problems.append("Switch at Playhead enabled off the clip \(offEnabled), back \(backEnabled)")
    }
    if a.project.json != beforeA { problems.append("the press off the clip changed the project") }
    if undoName(a) != stepBefore || (a.undoManager?.canUndo == true) != canUndoBefore {
        problems.append("the press off the clip made an undo step")
    }
    if !refusals.contains(where: { $0.contains("does not play at") }) {
        problems.append("the refusal strip was told \(refusals)")
    }
    row("P1", problems.isEmpty,
        problems.isEmpty
            ? "sections \(order); the section's Circle ▸ Top Left equals the menu's on a twin, "
                + "one undo step each; Duration 1.00 a 600000-tick action; enabled off the clip "
                + "and back; the press off the clip refused: \(refusals)"
            : problems.joined(separator: "; "))
} else {
    row("P1", false, "the fixture could not be made")
}

// ---- P4 -------------------------------------------------------------------------------------

/// The attached sheet's texts and buttons, or nil when there is none.
func sheet(_ controller: EditorViewController) -> (texts: [String], buttons: [String])? {
    guard let sheet = controller.view.window?.attachedSheet else { return nil }
    let views = sheet.contentView.map(walk) ?? []
    return (
        views.compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty },
        views.compactMap { ($0 as? NSButton)?.title }.filter { !$0.isEmpty }
    )
}

func press(_ controller: EditorViewController, _ code: NSApplication.ModalResponse) {
    if let window = controller.view.window, let attached = window.attachedSheet {
        window.endSheet(attached, returnCode: code)
    }
    spin(0.6)
}

let sideBySide = CameraLayoutChoice(kind: .sideBySide, shape: nil, corner: nil)
if let (document, controller, _, camera) = editor(zoomAt: 3 * second),
    let (twin, _, twinCamera) = makeDocument(zoomAt: 3 * second)
{
    var problems: [String] = []
    document.selection = [camera]
    document.playhead = second
    let before = document.project.json
    let stepBefore = undoName(document)
    let core: String? = {
        let op = sideBySide.op(camera: twinCamera, screen: nil, at: second)
        if case .refused(let refusal)? = try? twin.project.applying([op]) { return refusal.reason }
        return nil
    }()
    controller.switchCameraLayout(menuItem(sideBySide))
    spin(0.6)
    let shown = sheet(controller)
    if shown == nil { problems.append("no sheet attached") }
    if document.project.json != before || undoName(document) != stepBefore {
        problems.append("the project or the undo stack moved with the sheet up")
    }
    if let core, let shown {
        if !shown.texts.contains(where: { $0.contains(core) }) {
            problems.append("the sheet's texts \(shown.texts) lack the core's \(core.debugDescription)")
        }
        if shown.buttons != ["Nest and Switch", "Cancel"] {
            problems.append("the sheet's buttons are \(shown.buttons)")
        }
    } else if core == nil {
        problems.append("the twin's switch was not refused")
    }
    press(controller, .alertSecondButtonReturn)
    if document.project.json != before || undoName(document) != stepBefore {
        problems.append("Cancel changed the project or the undo stack")
    }
    if controller.view.window?.attachedSheet != nil { problems.append("Cancel left a sheet") }
    controller.switchCameraLayout(menuItem(sideBySide))
    spin(0.6)
    press(controller, .alertFirstButtonReturn)
    twin.performGroupedEdit(
        "Camera Layout", [sideBySide.op(camera: twinCamera, screen: nil, at: second, nest: true)])
    let nested = document.project.json
    if nested == before { problems.append("Nest and Switch changed nothing") }
    if nested != twin.project.json {
        problems.append("Nest and Switch differs from switch_layout {nest: true} on a twin")
    }
    if !undoesTo(document, before, name: "Camera Layout") {
        problems.append("one undo named \"Camera Layout\" did not restore the project")
    }
    row("P4", problems.isEmpty,
        problems.isEmpty
            ? "the sheet \(shown.map { "\($0.buttons)" } ?? "-") over the core's "
                + "\(core ?? "-"); Cancel changed nothing; Nest and Switch equals "
                + "switch_layout {nest: true} on a twin, one undo \"Camera Layout\" restores it"
            : problems.joined(separator: "; "))
} else {
    row("P4", false, "the fixture could not be made")
}

finish()
