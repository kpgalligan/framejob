// Road map 9, phase 3b — Reset/Clear, the row ×, the row menus and the
// refusal strip; the probe (`clip_inspector4_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — so every row drives the
// app's own `ProjectDocument`, `InspectorViewController`, `ClipPane`,
// `InspectorSection`, `InspectorSectionHeader`, `InspectorRowView` and
// `InspectorMarkGutter`, and R7 a real `EditorViewController` in a window.
// Nothing private is widened: a row is found by what it HOLDS (its label's
// text), a section by its id, and a header's Reset by the one visible
// button among its subviews, clicked through its own `mouseDown`.
//
//   clip_inspector4_probe <request.json> <answer.json>
//
// `request.json` names the packages the proof wrote:
//   chrome   one shape card of 6 s, clip 2, with action 3 at 0.5–1.5 s
//            {video: {opacity: 0.5}} and action 4 at 2.5–4.0 s {video: {x: 100}}
//   av       a video with sound, clip 2, action 10 at 1–2 s {audio: {volume: 0.5}}
//   text     a text clip, clip 2, at scale 2 in the face Menlo-Regular
//   filters  the card with one blur at amount 0
//   ellipse  a 500 × 500 ellipse, radius 0, no stroke
//   stroke   the card with a stroke of width 12
// One JSON object out: `rows`, each a name, ok and detail. Row names start
// with their R-number, which is what the mutant mode reads.
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

let ticks: Ticks = 600_000
func at(_ seconds: Double) -> Ticks { Ticks(seconds * Double(ticks)) }

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// Every section key this probe pins, dropped at the start and at the end so
/// a run leaves the probe's defaults domain as it found it.
let pinnedIDs = ["video.transform", "video.shadow", "video.motion", "clip.timing",
                 "video.filters", "video.speed", "shape.kind", "shape.stroke", "audio.volume"]
func key(_ id: String) -> String { InspectorSection.collapsedKeyPrefix + id }
func unpin() { for id in pinnedIDs { UserDefaults.standard.removeObject(forKey: key(id)) } }
unpin()
for id in pinnedIDs { UserDefaults.standard.set(false, forKey: key(id)) }

func opened(_ name: String) -> ProjectDocument? {
    guard let path = request[name] as? String else {
        check("R0 the \(name) fixture is named", false)
        return nil
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        check("R0 the \(name) fixture opens", false, "\(error)")
        return nil
    }
    return document
}

/// A Clip pane over a document with clip 2 selected, the playhead at
/// `seconds` and `action` selected, no window, and the inspector's two
/// intents wired as `installInspector()` wires them — so `binding.apply`
/// reaches `applyEdit` and a row's "Go to action" reaches `selectAction`.
var kept: [AnyObject] = []
func clipPane(
    _ name: String, playhead seconds: Double, action: UInt32?
) -> (ProjectDocument, InspectorViewController, ClipPane)? {
    guard let document = opened(name) else { return nil }
    let inspector = InspectorViewController()
    inspector.document = document
    inspector.onEdit = { [weak document] name, ops in document?.applyEdit(name, ops) }
    inspector.onSelectAction = { [weak document] id in document?.selectAction(id) }
    document.selection = [2]
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

func title(_ section: InspectorSection?) -> String {
    guard let section else { return "no section" }
    return section.header.buttonTitle ?? "nil"
}

func titles(_ menu: NSMenu?) -> [String]? { menu?.items.map(\.title) }

func describe(_ list: [String]?) -> String { list.map { "\($0)" } ?? "nil" }

func ink(_ color: NSColor) -> String {
    color == DS.action ? "DS.action" : color == DS.textMuted ? "DS.textMuted"
        : color == DS.textFaint ? "DS.textFaint" : "\(color)"
}

func clip2(_ document: ProjectDocument) -> ClipSnapshot? {
    document.project.snapshot.clips.first { $0.id == 2 }
}

func endPatch(_ document: ProjectDocument, _ action: UInt32) -> ActionPatch? {
    clip2(document)?.actions.first { $0.id == action }?.end
}

func undoName(_ document: ProjectDocument) -> String { document.undoManager?.undoActionName ?? "" }

/// The header's visible button, clicked the way AppKit clicks it.
func clickHeaderButton(_ section: InspectorSection?) -> Bool {
    guard let button = section?.header.subviews
        .compactMap({ $0 as? OptionButtonControl }).first(where: { !$0.isHidden }),
          let event = NSEvent.mouseEvent(
              with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
              windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    else { return false }
    button.mouseDown(with: event)
    return true
}

// MARK: - R1 Reset shown only when a section differs, R2 the summary's tiers

if let (document, inspector, pane) = clipPane("chrome", playhead: 5, action: nil) {
    var picture = sections(pane, .picture)
    let transform = section(picture, "video.transform")
    check("R1 no action: Transform at its default shows no button (Reset hidden)",
          transform?.header.buttonTitle == nil, title(transform))
    let shadow = section(picture, "video.shadow")
    check("R1 … Shadow, off, shows no button (Reset hidden)",
          shadow?.header.buttonTitle == nil, title(shadow))
    let faint = transform.map { ink($0.header.summaryInk) } ?? "no section"
    check("R2 … Transform's summary at its default is DS.textFaint", faint == "DS.textFaint",
          faint)
    let timing = section(sections(pane, .clip), "clip.timing")
    check("R1 … Timing, which has no Reset, shows no button", timing != nil
            && timing?.header.buttonTitle == nil, title(timing))

    document.applyEdit("Scale", inspector.binding.ops(video: VideoPatch(scale: 2)))
    spin(0.1)
    picture = sections(pane, .picture)
    let scaled = section(picture, "video.transform")
    check("R1 at scale 2 Transform shows Reset", scaled?.header.buttonTitle == "Reset",
          title(scaled))
    let muted = scaled.map { ink($0.header.summaryInk) } ?? "no section"
    check("R2 … and its summary is the body tier, DS.textMuted", muted == "DS.textMuted", muted)
}

// MARK: - R2 the keyed tier, R3 Clear

if let (document, _, pane) = clipPane("chrome", playhead: 1.0, action: 3) {
    var picture = sections(pane, .picture)
    let transform = section(picture, "video.transform")
    let keyedInk = transform.map { ink($0.header.summaryInk) } ?? "no section"
    check("R2 action 1 selected (it keys opacity): Transform's summary is DS.action",
          keyedInk == "DS.action", keyedInk)
    check("R3 … Transform shows Clear, tooltip \"Remove this section from action 1\"",
          transform?.header.buttonTitle == "Clear" && transform?.header.subviews.contains {
              !$0.isHidden && $0.toolTip == "Remove this section from action 1"
          } == true,
          title(transform))
    let shadow = section(picture, "video.shadow")
    check("R3 … Shadow, which action 1 does not key, shows no button", shadow != nil
            && shadow?.header.buttonTitle == nil, title(shadow))
    transform?.clear()
    spin(0.1)
    let end = endPatch(document, 3)
    check("R3 Transform's clear() removes video.opacity from action 1's end patch, and the "
            + "action stays",
          end != nil && end?.video?.opacity == nil,
          "end \(end.map { "\($0.dictionary)" } ?? "no action")")
    check("R3 … as ONE undo step named Clear", undoName(document) == "Clear", undoName(document))
    picture = sections(pane, .picture)
    let after = section(picture, "video.transform")
    check("R3 … and Transform's ◆ count is 0 after it", after?.marks.keyed == 0,
          "\(after.map { "\($0.marks)" } ?? "no section")")
}

// MARK: - R4 the row's × on hover

if let (document, _, pane) = clipPane("chrome", playhead: 1.0, action: 3) {
    let transform = section(sections(pane, .picture), "video.transform")
    let scale = row(transform, "Scale")
    scale?.setHovered(true)
    check("R4 action 1 selected: the Scale row hovered shows no × (it is not keyed)",
          scale != nil && scale?.gutter.showsRemove == false,
          "\(scale.map { "hovered \($0.gutter.hovered), keyed \($0.gutter.isKeyed)" } ?? "no row")")
    scale?.setHovered(false)
    let opacity = row(transform, "Opacity")
    opacity?.setHovered(true)
    check("R4 … the Opacity row hovered shows the × with the tooltip \"Remove from action 1\"",
          opacity?.gutter.showsRemove == true
            && opacity?.gutter.toolTip == "Remove from action 1",
          "\(opacity.map { "× \($0.gutter.showsRemove), tip \($0.gutter.toolTip ?? "nil")" } ?? "no row")")
    opacity?.setHovered(false)
    check("R4 … un-hovered the × goes and the row stays keyed",
          opacity?.gutter.showsRemove == false && opacity?.gutter.isKeyed == true,
          "\(opacity.map { "× \($0.gutter.showsRemove), keyed \($0.gutter.isKeyed)" } ?? "no row")")
    opacity?.setHovered(true)
    opacity?.gutter.removeFromAction()
    spin(0.1)
    let end = endPatch(document, 3)
    let again = row(section(sections(pane, .picture), "video.transform"), "Opacity")
    check("R4 … removeFromAction() un-keys it: opacity leaves the end patch, undo name "
            + "\"Remove from Action\", the rebuilt row is not keyed",
          end != nil && end?.video?.opacity == nil && undoName(document) == "Remove from Action"
            && again?.gutter.isKeyed == false,
          "end \(end.map { "\($0.dictionary)" } ?? "none"), undo '\(undoName(document))', "
            + "mark \(again.map { "\($0.gutter.mark)" } ?? "no row")")
}

// MARK: - R5 the row menus, never after a hover

if let (document, _, pane) = clipPane("chrome", playhead: 1.0, action: 3) {
    let transform = section(sections(pane, .picture), "video.transform")
    let opacity = row(transform, "Opacity")
    let keyedMenu = titles(opacity?.contextMenu())
    check("R5 action 1, never hovered: Opacity (◆) → [Remove from action 1, Set end value to "
            + "default]",
          opacity?.gutter.hovered == false
            && keyedMenu == ["Remove from action 1", "Set end value to default"],
          describe(keyedMenu))
    let x = row(transform, "Position X")
    let otherMenu = x?.contextMenu()
    check("R5 … Position X (◇2) → [Go to action 2, Set end value to default]",
          titles(otherMenu) == ["Go to action 2", "Set end value to default"],
          describe(titles(otherMenu)))
    if let otherMenu, otherMenu.items.count > 0 { otherMenu.performActionForItem(at: 0) }
    check("R5 … performing Go to action 2 selects action 2 (id 4)",
          document.selectedAction == 4, "\(document.selectedAction.map { "\($0)" } ?? "nil")")

    let clip = sections(pane, .clip)
    let motionIn = row(section(clip, "video.motion"), "In")
    let motionMenu = titles(motionIn?.contextMenu())
    check("R5 … a Motion presets row (⊘) with an action → [Reset to default]",
          motionMenu == ["Reset to default"], describe(motionMenu))
    let duration = row(section(clip, "clip.timing"), "Duration")
    check("R5 … Timing's Duration readout → no menu", duration != nil
            && duration?.contextMenu() == nil, describe(titles(duration?.contextMenu())))
}

if let (_, _, pane) = clipPane("av", playhead: 5, action: nil) {
    let rate = row(section(sections(pane, .clip), "video.speed"), "Rate")
    check("R5 Speed's Rate (resets: false) → no menu", rate != nil && rate?.contextMenu() == nil,
          describe(titles(rate?.contextMenu())))
}

if let (document, inspector, pane) = clipPane("chrome", playhead: 5, action: nil) {
    document.applyEdit("Scale", inspector.binding.ops(video: VideoPatch(scale: 2)))
    spin(0.1)
    let scale = row(section(sections(pane, .picture), "video.transform"), "Scale")
    let menu = scale?.contextMenu()
    check("R5 no action, Scale 200% → [Reset to default], enabled",
          titles(menu) == ["Reset to default"] && menu?.items.first?.isEnabled == true
            && menu?.autoenablesItems == false,
          describe(titles(menu)))
    if let menu, menu.items.count > 0 { menu.performActionForItem(at: 0) }
    spin(0.1)
    let now = clip2(document)?.videoProps.scale
    check("R5 … performed, the scale is 1 under the undo name \"Scale\"",
          now == 1 && undoName(document) == "Scale",
          "scale \(now.map { "\($0)" } ?? "nil"), undo '\(undoName(document))'")
    let back = row(section(sections(pane, .picture), "video.transform"), "Scale")
    let item = back?.contextMenu()?.items.first
    check("R5 … at 100% the item is there and disabled",
          item?.title == "Reset to default" && item?.isEnabled == false,
          "\(item.map { "\($0.title) enabled \($0.isEnabled)" } ?? "no item")")
}

// MARK: - R6 the defaults read mode

if let (_, inspector, _) = clipPane("text", playhead: 5, action: nil) {
    let binding = inspector.binding
    let scale = (binding.videoProps.scale, binding.at(.defaults) { binding.videoProps.scale })
    let font = (binding.textProps.font, binding.at(.defaults) { binding.textProps.font })
    check("R6 at(.defaults): scale 2 reads 1, the face Menlo-Regular reads TextProps().font, "
            + "and the mode is restored",
          scale == (2, 1) && font.0 == "Menlo-Regular" && font.1 == TextProps().font
            && binding.mode == .end,
          "scale \(scale), font \(font), mode \(binding.mode)")
}

if let (_, inspector, _) = clipPane("av", playhead: 1.5, action: 10) {
    let binding = inspector.binding
    let volume = (binding.audioProps.volume, binding.at(.defaults) { binding.audioProps.volume })
    check("R6 … action 1 keys volume 0.5: .end reads 0.5, at(.defaults) reads 1",
          volume == (0.5, 1), "volume \(volume)")
}

// MARK: - R7 the refusal strip, in a real editor

if let document = opened("chrome") {
    document.selection = [2]
    document.playhead = at(1.0)
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(1.2)
    let controller = document.windowControllers.first?.contentViewController
        as? EditorViewController
    let strip = controller?.inspector?.refusalStrip
    var heard: [String] = []
    let token = NotificationCenter.default.addObserver(
        forName: .projectDocumentDidRefuse, object: document, queue: nil
    ) { note in
        if let refusal = note.userInfo?["refusal"] as? ReelRefusal { heard.append(refusal.reason) }
    }
    let before = document.project
    controller?.addActionAtPlayheadCommand()
    spin(0.3)
    let reason = heard.first ?? ""
    check("R7 Add Action inside action 1's span is refused: projectDocumentDidRefuse carries a "
            + "non-empty reason, and the project is the same handle",
          controller != nil && heard.count == 1 && !reason.isEmpty && document.project === before,
          "heard \(heard)")
    check("R7 … the editor's strip reads \"Refused: \" + that reason, and shows",
          strip?.text == "Refused: " + reason && strip?.isHidden == false,
          "strip '\(strip?.text ?? "nil")', hidden \(strip?.isHidden ?? true)")
    // Review 3b #1, 2026-09-23: a hidden arranged view is detached, so the
    // strip's width is pinned on each show; read back what it spans.
    let inspectorView = controller?.inspector?.view
    inspectorView?.layoutSubtreeIfNeeded()
    let spans = (strip?.frame.width, inspectorView?.bounds.width)
    // Re-measured 2026-09-24 (road map 9 phase 5, §8's second nit): the row
    // passed on the tree before that fix too, so it now shows the strip,
    // clears it, widens the inspector 40 pt through the editor's split view
    // and shows it again — the width must follow to the NEW inspector width.
    strip?.clear()
    let widthKey = EditorViewController.inspectorWidthKey
    let storedWidth = UserDefaults.standard.object(forKey: widthKey)
    // The vertical split whose trailing pane holds the inspector.
    let split = controller.map { walk($0.view) }?.compactMap { $0 as? NSSplitView }.first { split in
        guard split.isVertical, let pane = split.subviews.last, let inspectorView else {
            return false
        }
        return inspectorView.isDescendant(of: pane)
    }
    if let split, let leading = split.subviews.first {
        split.setPosition(leading.frame.width - 40, ofDividerAt: 0)
        split.layoutSubtreeIfNeeded()
    }
    controller?.addActionAtPlayheadCommand()
    spin(0.3)
    inspectorView?.layoutSubtreeIfNeeded()
    let wider = (strip?.frame.width, inspectorView?.bounds.width)
    if let storedWidth {
        UserDefaults.standard.set(storedWidth, forKey: widthKey)
    } else {
        UserDefaults.standard.removeObject(forKey: widthKey)
    }
    check("R7 … the shown strip spans the inspector's width; cleared, the inspector widened "
            + "40 pt and shown again, it spans the new width",
          strip?.superview != nil && spans.0 != nil && spans.0 == spans.1 && (spans.1 ?? 0) > 0
            && strip?.isHidden == false && wider.0 != nil && wider.0 == wider.1
            && wider.1 == (spans.1 ?? 0) + 40,
          "strip \(spans.0.map { "\($0)" } ?? "nil") pt, inspector \(spans.1.map { "\($0)" } ?? "nil") pt; "
            + "after: strip \(wider.0.map { "\($0)" } ?? "nil") pt, inspector "
            + "\(wider.1.map { "\($0)" } ?? "nil") pt, split \(split != nil)")
    controller?.refreshInspector(isLive: false)
    check("R7 … a refresh under the same project keeps it", strip?.text == "Refused: " + reason,
          "strip '\(strip?.text ?? "nil")'")
    let scale2 = ReelOp.setVideo(clips: [2], patch: VideoPatch(scale: 2))
    document.applyEdit("Scale", [scale2])
    spin(0.3)
    check("R7 … an applied edit clears it", strip?.text == nil && strip?.isHidden == true,
          "strip '\(strip?.text ?? "nil")', hidden \(strip?.isHidden ?? false)")
    document.applyEdit("Scale", [scale2])
    spin(0.3)
    // 2026-09-24: two refusals were heard now, the re-show's included.
    check("R7 … an identity edit (scale 2 again) posts nothing and leaves it hidden",
          heard.count == 2 && strip?.text == nil && strip?.isHidden == true,
          "heard \(heard.count), strip '\(strip?.text ?? "nil")'")
    NotificationCenter.default.removeObserver(token)
}

// MARK: - R8 the explicit differs

if let (document, _, pane) = clipPane("av", playhead: 5, action: nil) {
    let still = section(sections(pane, .clip), "video.speed")
    check("R8 Speed at 1× shows no button", still != nil && still?.header.buttonTitle == nil,
          title(still))
    document.applyEdit("Set Speed", [.setSpeed(clip: 2, rate: 2, keepPitch: nil)])
    spin(0.1)
    let fast = section(sections(pane, .clip), "video.speed")
    check("R8 … at 2× shows Reset", fast?.header.buttonTitle == "Reset", title(fast))
}

if let (_, _, pane) = clipPane("filters", playhead: 5, action: nil) {
    let filters = section(sections(pane, .picture), "video.filters")
    check("R8 Filters with one blur at amount 0 shows Reset", filters?.header.buttonTitle == "Reset",
          title(filters))
}

if let (_, _, pane) = clipPane("chrome", playhead: 5, action: nil) {
    let filters = section(sections(pane, .picture), "video.filters")
    check("R8 Filters with no filter shows no button", filters != nil
            && filters?.header.buttonTitle == nil, title(filters))
}

if let (_, _, pane) = clipPane("ellipse", playhead: 5, action: nil) {
    let shape = sections(pane, .shape)
    let kind = section(shape, "shape.kind")
    check("R8 a 500 × 500 ellipse at radius 0: Shape shows no button", kind != nil
            && kind?.header.buttonTitle == nil, title(kind))
    let stroke = section(shape, "shape.stroke")
    check("R8 … and with no stroke, Stroke shows no button", stroke != nil
            && stroke?.header.buttonTitle == nil, title(stroke))
}

if let (document, _, pane) = clipPane("stroke", playhead: 5, action: nil) {
    let stroke = section(sections(pane, .shape), "shape.stroke")
    check("R8 a stroke of width 12 shows Reset", stroke?.header.buttonTitle == "Reset",
          title(stroke))
    let clicked = clickHeaderButton(stroke)
    spin(0.1)
    let after = section(sections(pane, .shape), "shape.stroke")
    let stored = clip2(document)?.shape?.stroke
    check("R8 … and after its Reset (StrokeProps()) shows no button",
          clicked && stored == StrokeProps() && after?.header.buttonTitle == nil,
          "clicked \(clicked), stroke \(stored.map { "\($0)" } ?? "nil"), \(title(after))")
}

unpin()
let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
