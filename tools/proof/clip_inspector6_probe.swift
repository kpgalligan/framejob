// Road map 9, phase 5 — the rest of the mode: canvas gestures follow the
// selected action (CI-13), a switch keyed OFF (CI-14), `mixed` on every
// sub-row and the animated collapse (CI-15); the probe
// (`clip_inspector6_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — so every row drives the
// app's own `CanvasEditTarget`, the canvas sessions, `ProjectDocument`'s live
// edit, `InspectorBinding`, `ClipPane`, `InspectorSection`, `ActionLaneView`
// and, for the nudge, a real `EditorViewController` in a window.
//
//   clip_inspector6_probe <request.json> <answer.json>
//
// `request.json` names the packages the proof wrote:
//   chrome  one shape card of 6 s, clip 2, with a base shadow, action 3 at
//           0.5–1.5 s {video: {opacity: 0.5}} and action 4 at 2.5–4.0 s
//           {video: {x: 100}}
//   pair    the card and a second card, clip 5, whose shadow's blur differs
//   text    a text clip, clip 2, wrap width 300, action 3 at 0.5–1.5 s
//           {text: {width: 600}}
//   duo     two media clips, 2 and 3, whose compressors differ in ratio
// One JSON object out: `rows`, each a name, ok and detail. Row names start
// with their K-number, which is what the mutant mode reads.
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

let second: Ticks = 600_000
func at(_ seconds: Double) -> Ticks { Ticks((seconds * Double(second)).rounded()) }

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// Every section key this probe pins, dropped at the start and at the end so
/// a run leaves the probe's defaults domain as it found it.
let pinnedIDs = ["video.shadow", "audio.compressor", "text.box"]
func key(_ id: String) -> String { InspectorSection.collapsedKeyPrefix + id }
func unpin() { for id in pinnedIDs { UserDefaults.standard.removeObject(forKey: key(id)) } }
unpin()
for id in pinnedIDs { UserDefaults.standard.set(false, forKey: key(id)) }

func opened(_ name: String) -> ProjectDocument? {
    guard let path = request[name] as? String else {
        check("K0 the \(name) fixture is named", false)
        return nil
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        check("K0 the \(name) fixture opens", false, "\(error)")
        return nil
    }
    return document
}

/// A Clip pane over a document with `selection` selected, the playhead at
/// `seconds` and `action` selected, no window, the inspector's two intents
/// wired as `installInspector()` wires them.
var kept: [AnyObject] = []
func clipPane(
    _ name: String, select selection: Set<UInt32> = [2], playhead seconds: Double,
    action: UInt32?
) -> (ProjectDocument, InspectorViewController, ClipPane)? {
    guard let document = opened(name) else { return nil }
    let inspector = InspectorViewController()
    inspector.document = document
    inspector.onEdit = { [weak document] name, ops in document?.applyEdit(name, ops) }
    inspector.onSelectAction = { [weak document] id in document?.selectAction(id) }
    document.selection = selection
    document.playhead = at(seconds)
    document.selectAction(action)
    inspector.binding.invalidate()
    kept += [document, inspector]
    return (document, inspector, ClipPane(inspector: inspector))
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func sections(_ pane: ClipPane, _ tab: ClipSubTab) -> [InspectorSection] {
    pane.binding.invalidate()
    pane.choose(tab)
    pane.rebuild()
    pane.refresh()
    return pane.sections
}

func section(_ list: [InspectorSection], _ id: String) -> InspectorSection? {
    list.first { $0.id == id }
}

/// The row whose label reads `label`, inside `section`.
func row(_ section: InspectorSection?, _ label: String) -> InspectorRowView? {
    guard let section else { return nil }
    return walk(section).compactMap { $0 as? InspectorRowView }.first { row in
        row.arrangedSubviews.contains { ($0 as? InspectorRowLabel)?.stringValue == label }
    }
}

/// Whether `row`'s mixed badge is showing; nil when the row has none.
func badgeShown(_ row: InspectorRowView?) -> Bool? {
    guard let badge = row?.arrangedSubviews.compactMap({ $0 as? InspectorMixedBadge }).first
    else { return nil }
    return !badge.isHidden
}

/// The stored end state of `action` on `clip`, read from the project's JSON
/// — so a `null` and an absent key stay two different answers.
func storedEnd(_ document: ProjectDocument, _ clip: UInt32, _ action: UInt32) -> [String: Any]? {
    guard let data = document.project.json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let clips = object["clips"] as? [[String: Any]],
          let found = clips.first(where: { ($0["id"] as? NSNumber)?.uint32Value == clip }),
          let actions = found["actions"] as? [[String: Any]],
          let entry = actions.first(where: { ($0["id"] as? NSNumber)?.uint32Value == action })
    else { return nil }
    return entry["end"] as? [String: Any]
}

func group(_ end: [String: Any]?, _ name: String) -> [String: Any]? {
    end?[name] as? [String: Any]
}

func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

func describe(_ value: Any?) -> String {
    guard let value else { return "nil" }
    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8)
    {
        return text
    }
    return "\(value)"
}

func base(_ document: ProjectDocument, _ clip: UInt32) -> ClipSnapshot? {
    document.project.snapshot.clip(clip)
}

func names(_ ops: [ReelOp]) -> [String] { ops.map(\.name) }

// MARK: - K1 the canvas follows the mode (CI-13)

let selected = CanvasEditTarget(
    selected: .init(clip: 2, action: 4, endTime: at(4.0)))
do {
    let mine = selected.op(video: VideoPatch(x: 5), clip: 2)
    let other = selected.op(video: VideoPatch(x: 5), clip: 7)
    let plain = CanvasEditTarget.base.op(video: VideoPatch(x: 5), clip: 2)
    check("K1 op(video:): the selected action's clip → set_action_end on action 4; another "
            + "clip → set_video; .base → set_video",
          mine.name == "set_action_end" && (mine.args["action"] as? UInt32) == 4
            && other.name == "set_video" && plain.name == "set_video",
          "\(mine.name) \(describe(mine.args["action"])), \(other.name), \(plain.name)")
}

if let (document, _, _) = clipPane("chrome", playhead: 3.0, action: 4),
   let clip = document.editedProject.snapshot.clip(2)
{
    let target = CanvasEditTarget.current(document)
    let end = target.start(of: clip, in: document.editedProject).video.x
    let held = CanvasEditTarget.base.start(of: clip, in: document.editedProject).video.x
    check("K1 start(of:in:): action 4 selected → x 100 (its end state); .base → x 0",
          target == selected && end == 100 && held == 0,
          "target \(target), end x \(end), base x \(held)")

    document.beginLiveEdit()
    var move = CanvasMoveSession(
        bases: [2: CGPoint(
            x: target.start(of: clip, in: document.editedProject).video.x,
            y: target.start(of: clip, in: document.editedProject).video.y)],
        anchor: 2, anchorBounds: CGRect(x: 0, y: 0, width: 10, height: 10), grab: .zero)
    let snapper = CanvasSnapper(xs: [], ys: [], threshold: 0, enabled: false)
    move.update(point: CGPoint(x: 15, y: 10), snapper: snapper)
    document.updateLiveEdit(move.ops(to: target))
    move.update(point: CGPoint(x: 30, y: 20), snapper: snapper)
    document.updateLiveEdit(move.ops(to: target))
    document.endLiveEdit("Move")
    let moved = group(storedEnd(document, 2, 4), "video")
    let still = base(document, 2)?.videoProps
    let undo = document.undoManager
    let name = undo?.undoActionName ?? ""
    undo?.undo()
    let back = group(storedEnd(document, 2, 4), "video")
    check("K1 a CanvasMoveSession's ops(to:) through the live edit moves action 4's END x by the "
            + "delta (100 → 130, y 0 → 20) and leaves the base at 0 — ONE undo step",
          number(moved?["x"]) == 130 && number(moved?["y"]) == 20 && still?.x == 0
            && still?.y == 0 && name == "Move" && number(back?["x"]) == 100
            && back?["y"] == nil && undo?.canUndo == false,
          "end \(describe(moved)), base (\(still.map { "\($0.x), \($0.y)" } ?? "nil")), undo "
            + "'\(name)', after undo \(describe(back)), canUndo \(undo?.canUndo ?? true)")
}

if let (document, _, _) = clipPane("pair", select: [2], playhead: 3.0, action: 4) {
    let one = CanvasEditTarget.current(document)
    document.selection = [2, 5]
    let two = CanvasEditTarget.current(document)
    check("K1 action 4 selected on clip 2, then clips 2 and 5 selected → the target is .base",
          one == selected && two == .base, "one clip \(one), two clips \(two)")
}

if let (document, _, _) = clipPane("text", playhead: 1.0, action: 3),
   let clip = document.editedProject.snapshot.clip(2)
{
    let target = CanvasEditTarget.current(document)
    let route = target.forScale(of: clip)
    let start = route.start(of: clip, in: document.editedProject)
    let width = start.text?.width ?? 0
    // Seeded exactly as `PreviewCanvasView.beginScale` seeds a text clip.
    var scale = CanvasScaleSession(
        clip: 2, handle: .right, target: .textWidth(width), base: start.video,
        startRect: CGRect(x: 0, y: 0, width: 600, height: 100), rotation: start.video.rotation,
        scale: start.video.scale, boxSize: .zero, textWidth: width)
    scale.update(point: CGPoint(x: 612, y: 50), aspectFree: false, aboutCentre: false)
    let ops = scale.ops(to: route)
    document.applyEdit("Scale", ops)
    let end = number(group(storedEnd(document, 2, 3), "text")?["width"]) ?? 0
    let held = base(document, 2)?.text?.width
    check("K1 a text clip whose action 3 ends at width 600 over a base 300: start(of:in:) reads "
            + "600, and a 2 % right-edge drag writes set_action_end with width ≈ 612, base 300",
          width == 600 && route == target && names(ops) == ["set_action_end"]
            && abs(end - 612) <= 612 * 0.02 && held == 300,
          "start width \(width), ops \(names(ops)), end width \(end), base "
            + "\(held.map { "\($0)" } ?? "nil")")
}

if let (document, _, _) = clipPane("chrome", playhead: 3.0, action: 4),
   let clip = document.editedProject.snapshot.clip(2)
{
    let target = CanvasEditTarget.current(document)
    var box = CanvasScaleSession(
        clip: 2, handle: .bottomRight, target: .box(CGSize(width: 640, height: 360)),
        base: clip.videoProps, startRect: CGRect(x: 0, y: 0, width: 640, height: 360),
        rotation: 0, scale: 1, boxSize: CGSize(width: 640, height: 360), textWidth: 0)
    box.update(point: CGPoint(x: 704, y: 396), aspectFree: false, aboutCentre: false)
    let ops = box.ops(to: target)
    check("K1 a shape with action 4 selected: forScale(of:) is .base, and a box drag's "
            + "ops(to: the selected target) are [set_shape, set_video] — no set_action_end",
          target == selected && target.forScale(of: clip) == .base
            && names(ops) == ["set_shape", "set_video"],
          "forScale \(target.forScale(of: clip)), ops \(names(ops))")
}

// The nudge, in a real editor: the target reaches the canvas only through
// `refreshCanvas`, which the editor's own selection intents already fire
// (`selectAction(_:)`, the lane's and the chip's). The playhead starts
// outside every span, so nothing is selected until the editor selects it.
if let document = opened("chrome") {
    document.selection = [2]
    document.playhead = at(5.0)
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.0)
    let controller = document.windowControllers.first?.contentViewController
        as? EditorViewController
    controller?.selectAction(4)
    spin(0.3)
    let keyed = controller?.previewCanvas?.nudge(dx: 10, dy: 0) ?? false
    spin(0.2)
    let afterKeyed = (number(group(storedEnd(document, 2, 4), "video")?["x"]),
                      base(document, 2)?.videoProps.x)
    controller?.selectAction(nil)
    spin(0.3)
    let plain = controller?.previewCanvas?.nudge(dx: 10, dy: 0) ?? false
    spin(0.2)
    let afterPlain = (number(group(storedEnd(document, 2, 4), "video")?["x"]),
                      base(document, 2)?.videoProps.x)
    check("K1 nudge in a real editor: with action 4 selected its END x goes 100 → 110 (base 0); "
            + "with none the BASE x goes 0 → 10 (end 110)",
          keyed && plain && afterKeyed.0 == 110 && afterKeyed.1 == 0 && afterPlain.0 == 110
            && afterPlain.1 == 10,
          "editor \(controller != nil), selected \(describe(document.selectedAction)): end \(describe(afterKeyed.0)), base "
            + "\(describe(afterKeyed.1)); none: end \(describe(afterPlain.0)), base "
            + "\(describe(afterPlain.1))")
    document.close()
}

// Added 2026-09-24 (phase 5 review, finding 2): the OTHER writer of the
// selected action, the entry rule on a playhead move (`syncSelectedAction`),
// fires no `viewStateDidChange`, so the canvas must learn the target on the
// playhead's own path. Clip 2 selected, nothing selected at 5.0 s; the
// editor's `setPlayhead` scrubs INTO action 4's span (it becomes selected)
// and a nudge must key its end; scrubbed back OUT (the selection is kept), a
// second nudge keys the end again.
if let document = opened("chrome") {
    document.selection = [2]
    document.playhead = at(5.0)
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.0)
    let controller = document.windowControllers.first?.contentViewController
        as? EditorViewController
    let before = document.selectedAction
    controller?.setPlayhead(at(3.0))
    spin(0.3)
    let entered = document.selectedAction
    let inside = controller?.previewCanvas?.nudge(dx: 10, dy: 0) ?? false
    spin(0.2)
    let afterInside = (number(group(storedEnd(document, 2, 4), "video")?["x"]),
                       base(document, 2)?.videoProps.x)
    controller?.setPlayhead(at(5.0))
    spin(0.3)
    let outside = controller?.previewCanvas?.nudge(dx: 10, dy: 0) ?? false
    spin(0.2)
    let afterOutside = (number(group(storedEnd(document, 2, 4), "video")?["x"]),
                        base(document, 2)?.videoProps.x)
    check("K1 scrubbing the playhead into action 4's span selects it and a nudge keys its END x "
            + "100 → 110 (base 0); scrubbed back out, a nudge keys it again 110 → 120 (base 0)",
          before == nil && entered == 4 && inside && outside && afterInside.0 == 110
            && afterInside.1 == 0 && afterOutside.0 == 120 && afterOutside.1 == 0,
          "selected \(describe(before)) → \(describe(entered)); inside: end "
            + "\(describe(afterInside.0)), base \(describe(afterInside.1)); outside: end "
            + "\(describe(afterOutside.0)), base \(describe(afterOutside.1))")
    document.close()
}

// MARK: - K2 a switch keyed OFF inside an action (CI-14)

if let (document, inspector, pane) = clipPane("chrome", playhead: 1.0, action: 3) {
    let binding = inspector.binding
    // The Drop shadow row's `ops(false)`: the same expression its closure is.
    let ops = binding.ops(video: VideoPatch(shadow: .some(nil)))
    let patch = ops.first?.args["patch"] as? [String: Any]
    let video = patch?["video"] as? [String: Any]
    let off = ops.first?.args["off"] as? [String]
    check("K2 action 1 selected: the Drop shadow row's ops(false) is ONE set_action_end with "
            + "off == [video.shadow] and no shadow in its patch",
          names(ops) == ["set_action_end"] && off == ["video.shadow"]
            && video?["shadow"] == nil,
          "ops \(names(ops)), off \(describe(off)), patch \(describe(patch))")
    let paths = InspectorBinding.paths(of: ops)
    document.applyEdit("Shadow", ops)
    spin(0.1)
    let end = group(storedEnd(document, 2, 3), "video")
    let shadow = section(sections(pane, .picture), "video.shadow")
    let toggle = shadow.flatMap { list in
        walk(list).compactMap { $0 as? InspectorRowView }.first { row in
            row.arrangedSubviews.contains { $0 is OptionCheckboxControl }
        }
    }
    binding.invalidate()
    let reads = binding.videoProps.shadow
    check("K2 … applied: end.video.shadow is null, the row is ◆ at end, the checkbox reads off "
            + "(its read, binding.videoProps.shadow, is nil) and paths(of:) names video.shadow",
          end?.keys.contains("shadow") == true && end?["shadow"] is NSNull
            && toggle?.gutter.mark == .keyedAtEnd && reads == nil
            && paths.contains("video.shadow"),
          "end \(describe(end)), mark \(toggle.map { "\($0.gutter.mark)" } ?? "no row"), "
            + "read \(reads.map { "\($0)" } ?? "nil"), paths \(paths)")
    let clear = binding.clearOps(["video.shadow"])
    let clearPatch = (clear.first?.args["patch"] as? [String: [String: Any]])?["video"]
    document.applyEdit("Clear", clear)
    spin(0.1)
    let cleared = group(storedEnd(document, 2, 3), "video")
    check("K2 … Clear still sends a RAW null (no off) and the key goes",
          names(clear) == ["set_action_end"] && clear.first?.args["off"] == nil
            && clearPatch?["shadow"] is NSNull && cleared?.keys.contains("shadow") == false,
          "clear \(names(clear)) patch \(describe(clearPatch)), end after \(describe(cleared))")
}

// MARK: - K4 mixed on sub-rows (CI-15)

if let (_, _, pane) = clipPane("pair", select: [2, 5], playhead: 3.0, action: nil) {
    let shadow = section(sections(pane, .picture), "video.shadow")
    let blur = badgeShown(row(shadow, "Blur"))
    let opacity = badgeShown(row(shadow, "Opacity"))
    check("K4 two clips whose shadows differ in blur: Shadow ▸ Blur's mixed badge shows, "
            + "Opacity's is hidden",
          blur == true && opacity == false,
          "blur \(describe(blur)), opacity \(describe(opacity))")
}

if let (_, _, pane) = clipPane("duo", select: [2, 3], playhead: 3.0, action: nil) {
    let compressor = section(sections(pane, .sound), "audio.compressor")
    let ratio = badgeShown(row(compressor, "Ratio"))
    let threshold = badgeShown(row(compressor, "Threshold"))
    check("K4 two audio clips whose compressors differ in ratio: Compressor ▸ Ratio's badge "
            + "shows, Threshold's is hidden",
          ratio == true && threshold == false,
          "ratio \(describe(ratio)), threshold \(describe(threshold))")
}

// MARK: - K5 the collapse animates through DS.animate, and its STATE is at once

if let (_, _, pane) = clipPane("chrome", playhead: 3.0, action: nil),
   let shadow = section(sections(pane, .picture), "video.shadow"),
   let stack = shadow.subviews.first as? NSStackView,
   let content = stack.arrangedSubviews.last,
   let event = NSEvent.mouseEvent(
       with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
{
    let before = (shadow.isExpanded, content.isHidden)
    shadow.header.mouseDown(with: event)
    let after = (shadow.isExpanded, content.isHidden)
    shadow.header.mouseDown(with: event)
    let again = (shadow.isExpanded, content.isHidden)
    check("K5 a header click flips isExpanded and content.isHidden synchronously, and a second "
            + "click flips them back",
          after.0 == !before.0 && after.1 == !after.0 && again.0 == before.0
            && again.1 == !again.0,
          "before \(before), after \(after), again \(again), reduce motion \(DS.reduceMotion)")
} else {
    check("K5 the Shadow section and its content stack", false)
}

// MARK: - K6 the three nits

if let (_, _, pane) = clipPane("text", playhead: 3.0, action: nil) {
    let width = row(section(sections(pane, .text), "text.box"), "Width")
    check("K6 Box ▸ Width's gutter has no default (resets: false): no Reset to default",
          width != nil && width?.gutter.default == nil,
          "row \(width != nil), default \(width?.gutter.default == nil ? "nil" : "set")")
}

final class CountingWindow: NSWindow {
    weak var watched: NSView?
    var invalidations = 0
    override func invalidateCursorRects(for view: NSView) {
        if view === watched { invalidations += 1 }
        super.invalidateCursorRects(for: view)
    }
}

if let (document, inspector, _) = clipPane("chrome", playhead: 1.0, action: 3) {
    let window = CountingWindow(
        contentRect: NSRect(x: 0, y: 0, width: 304, height: 120), styleMask: [.titled],
        backing: .buffered, defer: false)
    let lane = ActionLaneView(binding: inspector.binding, inspector: inspector)
    lane.frame = NSRect(x: 0, y: 0, width: 304, height: 100)
    window.contentView?.addSubview(lane)
    window.watched = lane
    kept += [window, lane]
    spin(0.1)
    window.invalidations = 0
    document.applyEdit("Move Action", [.setAction(clip: 2, action: 4, start: at(2.6))])
    inspector.binding.invalidate()
    lane.refresh()
    document.playhead = at(1.2)
    inspector.binding.invalidate()
    lane.refresh()
    check("K6 ActionLaneView.refresh() twice — after action 4 moved, then under a playhead move "
            + "— invalidates its cursor rects ONCE",
          window.invalidations == 1, "invalidations \(window.invalidations)")
}

unpin()
let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
