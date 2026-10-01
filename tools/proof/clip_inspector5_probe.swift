// Road map 9, phase 4 — retiming by drag; the probe (`clip_inspector5_proof.py`
// builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — so every row drives the
// app's own `ActionDragSession`, `TimelineView`, `TimelineContentView`,
// `ActionLaneView` and `ProjectDocument`, the D2–D6 rows in a real
// `EditorViewController` in a window. Nothing private is widened: the
// timeline is driven through `beginGesture` / `continueGesture` /
// `endGesture`, the lane through synthesized mouse events into its own
// `mouseDown` / `mouseDragged` / `mouseUp`.
//
//   clip_inspector5_probe <request.json> <answer.json>
//
// `request.json` names the packages the proof wrote:
//   chrome  one shape card of 6 s, clip 2, with action 3 at 0.5–1.5 s and
//           action 4 at 2.5–4.0 s
//   av      a video with sound, clip 2 at 0–6 s with `fade_in` 1 s and a
//           `motion.in` fade of 0.5 s, and clip 3 at 5–11 s over it with a
//           cross dissolve (`transition_in`)
//   zero    the card, plus action 5 of length ZERO at 0.5 s — a project the
//           core REFUSES to open (`model_query.rs` `check_clips`: every action
//           has a positive duration), which D3's last row reads back
// One JSON object out: `rows`, each a name, ok and detail. Row names start
// with their D-number, which is what the mutant mode reads.
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
func secs(_ t: Ticks?) -> String { t.map { String(format: "%.4f s", Double($0) / 600_000) } ?? "nil" }

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func opened(_ key: String) -> ProjectDocument? {
    guard let path = request[key] as? String else {
        check("D0 the \(key) fixture is named", false)
        return nil
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        check("D0 the \(key) fixture opens", false, "\(error)")
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
    else {
        check("D0 the \(key) editor opens", false)
        return nil
    }
    return (document, controller)
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func action(_ document: ProjectDocument, _ clip: UInt32, _ id: UInt32) -> ActionSnapshot? {
    document.editedProject.snapshot.clip(clip)?.actions.first { $0.id == id }
}

func span(_ a: ActionSnapshot?) -> String {
    a.map { "\(secs($0.start)) – \(secs($0.endTime))" } ?? "no action"
}

func undoName(_ document: ProjectDocument) -> String { document.undoManager?.undoActionName ?? "" }

// MARK: - D1 the session's arithmetic

func sessionFixture(_ key: String) -> (ClipSnapshot, Fps)? {
    guard let document = opened(key), let clip = document.project.snapshot.clip(2) else {
        return nil
    }
    return (clip, document.project.snapshot.canvas.fps)
}

if let (clip, fps) = sessionFixture("chrome"),
   let three = clip.actions.first(where: { $0.id == 3 })
{
    let frame = fps.frameDuration
    var move = ActionDragSession(clip: clip, action: three, mode: .move, grabAt: at(1.0), fps: fps)
    move.update(clipTime: at(1.51) + 7)
    check("D1 frame snap: a move by 0.51 s + 7 ticks lands on the grid (start 1.0 s)",
          move.start == at(1.0) && move.start % frame == 0 && move.duration == at(1.0),
          "start \(move.start), duration \(move.duration)")

    var left = move
    left.update(clipTime: at(-5))
    var right = move
    right.update(clipTime: at(20))
    check("D1 walls: a move stops at 0 on the left and abuts action 4 (start 1.5 s) on the right",
          left.start == 0 && right.start == at(1.5) && right.endTime == at(2.5)
            && left.duration == at(1.0) && right.duration == at(1.0),
          "left \(secs(left.start)), right \(secs(right.start)) – \(secs(right.endTime))")

    var head = ActionDragSession(
        clip: clip, action: three, mode: .resize(.start), grabAt: at(0.5), fps: fps)
    head.update(clipTime: at(0.3))
    let early = (head.start, head.endTime)
    head.update(clipTime: at(3))
    check("D1 resize(.start) keeps the end (1.5 s) and floors at one frame",
          early == (at(0.3), at(1.5)) && head.start == at(1.5) - frame
            && head.duration == frame && head.endTime == at(1.5),
          "at 0.3 s: \(secs(early.0)) – \(secs(early.1)); at 3 s: \(secs(head.start)) – "
            + "\(secs(head.endTime))")

    var tail = ActionDragSession(
        clip: clip, action: three, mode: .resize(.end), grabAt: at(1.5), fps: fps)
    tail.update(clipTime: at(2.0))
    let longer = (tail.start, tail.endTime)
    tail.update(clipTime: at(5.0))
    check("D1 walls: resize(.end) keeps the start and caps at the upper wall (2.5 s)",
          longer == (at(0.5), at(2.0)) && tail.start == at(0.5) && tail.endTime == at(2.5),
          "at 2 s: \(secs(longer.0)) – \(secs(longer.1)); at 5 s: \(secs(tail.start)) – "
            + "\(secs(tail.endTime))")

    let ops = [move.op, head.op, tail.op]
    check("D1 op: set_action on clip 2, action 3, carrying start AND duration in every mode",
          ops.allSatisfy {
              $0.name == "set_action" && $0.args["start"] != nil && $0.args["duration"] != nil
                  && ($0.args["clip"] as? UInt32) == 2 && ($0.args["action"] as? UInt32) == 3
          },
          ops.map { "\($0.name) \($0.args.keys.sorted())" }.joined(separator: "; "))
    check("D1 undo names: Move Action, Resize Action, Resize Action",
          [move.undoName, head.undoName, tail.undoName]
            == ["Move Action", "Resize Action", "Resize Action"],
          "\([move.undoName, head.undoName, tail.undoName])")

    var plus = ActionDragSession(clip: clip, action: three, mode: .move, grabAt: at(1.0), fps: fps)
    plus.update(clipTime: at(2.0))
    var minus = ActionDragSession(
        clip: clip, action: three, mode: .resize(.start), grabAt: at(0.5), fps: fps)
    minus.update(clipTime: at(0.3))
    var len = ActionDragSession(
        clip: clip, action: three, mode: .resize(.end), grabAt: at(1.5), fps: fps)
    len.update(clipTime: at(2.0))
    let huds = [plus.hud(base: 0, frames: true), minus.hud(base: 0, frames: true),
                len.hud(base: 0, frames: true)]
    let want = ["00:00:01:15 → 00:00:02:15  +1:00", "00:00:00:09 → 00:00:01:15  −0:06",
                "len +15f"]
    check("D1 hud: \(want.map { "\"\($0)\"" }.joined(separator: ", "))", huds == want,
          "\(huds)")
} else {
    check("D1 the chrome session fixture", false)
}

// No opened project can hold a zero-length action (D3's last row), so the
// wall is asked of the chrome card IN MEMORY, with action 5 of length zero
// added at action 3's start — the arithmetic, not a state the app reaches.
if let (card, fps) = sessionFixture("chrome"),
   let three = card.actions.first(where: { $0.id == 3 })
{
    let clip = ClipSnapshot(
        id: card.id, track: card.track, start: card.start, duration: card.duration,
        source: card.source, actions: card.actions + [ActionSnapshot(id: 5, start: at(0.5),
                                                                     duration: 0)])
    var session = ActionDragSession(
        clip: clip, action: three, mode: .move, grabAt: at(1.0), fps: fps)
    session.update(clipTime: at(0.0))
    check("D1 walls: a zero-length action at the band's start (0.5 s) is a wall — a move left "
            + "stops there",
          session.lowerWall == at(0.5) && session.start == at(0.5),
          "lower wall \(secs(session.lowerWall)), start \(secs(session.start))")
} else {
    check("D1 the zero session fixture", false)
}

// Added 2026-09-24 (road map 9 phase 5, §10's first nit): a clip whose length
// is OFF the frame grid — 3 310 000 ticks at 30 fps, half a frame past
// 3 300 000 — floors its upper wall to the grid, so a far end resize stops on
// a frame the core's nearest-snap cannot round past the clip's end.
if let (card, fps) = sessionFixture("chrome") {
    let three = ActionSnapshot(id: 3, start: at(0.5), duration: at(1.0))
    let clip = ClipSnapshot(
        id: card.id, track: card.track, start: 0, duration: 3_310_000, source: card.source,
        actions: [three])
    var session = ActionDragSession(
        clip: clip, action: three, mode: .resize(.end), grabAt: at(1.5), fps: fps)
    session.update(clipTime: at(20))
    check("D1 walls: a 3 310 000-tick clip at 30 fps floors its upper wall to the grid — an "
            + "end resize far right answers end 3 300 000",
          session.upperWall == 3_300_000 && session.endTime == 3_300_000,
          "upper wall \(session.upperWall), end \(session.endTime)")
    // Added 2026-09-24 (phase 5 review, finding 1): an action ENDING at that
    // off-grid clip end keeps its own end as the wall — a move right leaves it
    // where it is and registers nothing.
    let tail = ActionSnapshot(id: 3, start: at(4.5), duration: 3_310_000 - at(4.5))
    let tailClip = ClipSnapshot(
        id: card.id, track: card.track, start: 0, duration: 3_310_000, source: card.source,
        actions: [tail])
    var move = ActionDragSession(
        clip: tailClip, action: tail, mode: .move, grabAt: at(5.0), fps: fps)
    move.update(clipTime: at(20))
    check("D1 walls: an action ending at a 3 310 000-tick clip's off-grid end, moved right, "
            + "stays put — its own end is the wall, and nothing changed",
          move.upperWall == 3_310_000 && move.start == at(4.5) && move.endTime == 3_310_000
            && !move.changed,
          "upper wall \(move.upperWall), start \(move.start), end \(move.endTime), "
            + "changed \(move.changed)")
} else {
    check("D1 the off-grid session fixture", false)
}

// MARK: - D2 the timeline, D4 its hover, D5 its hit test

func timelineBand(_ timeline: TimelineView, clip id: UInt32, action: UInt32) -> CGRect? {
    let snapshot = timeline.snapshot
    let layout = timeline.layout
    guard let clip = snapshot.clip(id), let index = snapshot.trackIndex(of: clip.track),
          let found = clip.actions.first(where: { $0.id == action })
    else { return nil }
    let rect = layout.clipRect(clip, row: layout.row(forTrackIndex: index))
    let lane = TimelineContentView.actionLane(
        content: TimelineContentView.contentRect(rect), sizeIndex: timeline.trackHeightIndex)
    return TimelineContentView.bandRect(found, clip: clip, lane: lane, layout: layout)
}

if let (document, controller) = editor("chrome", select: [2]), let timeline = controller.timeline,
   let band = timelineBand(timeline, clip: 2, action: 3)
{
    let perSecond = timeline.layout.width(of: second)
    let press = CGPoint(x: band.midX, y: band.midY)
    func drag(_ hit: TimelineHit, from: CGPoint, steps: [CGFloat]) {
        timeline.beginGesture(hit: hit, at: from, flags: [], clicks: 1)
        for dx in steps {
            timeline.continueGesture(at: CGPoint(x: from.x + dx, y: from.y), flags: [])
        }
        let last = steps.last ?? 0
        timeline.endGesture(at: CGPoint(x: from.x + last, y: from.y), flags: [])
        spin(0.3)
    }

    // D5 and D4 first, on the untouched band.
    let edgeHit = timeline.content.hit(at: CGPoint(x: band.maxX - 1.5, y: band.midY))
    let bodyHit = timeline.content.hit(at: press)
    check("D5 hit(at:) 1.5 pt inside the band's right end → .actionEdge(2, 3, .end)",
          edgeHit == .actionEdge(clip: 2, action: 3, .end), "\(edgeHit), band \(band)")
    check("D5 … and at its centre → .action(2, 3)", bodyHit == .action(clip: 2, action: 3),
          "\(bodyHit)")
    func moved(_ point: CGPoint) -> NSEvent? {
        let location = timeline.content.convert(point, to: nil)
        return NSEvent.mouseEvent(
            with: .mouseMoved, location: location, modifierFlags: [], timestamp: 0,
            windowNumber: timeline.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
            clickCount: 0, pressure: 0)
    }
    var hovers: [ActionBandHover?] = []
    for point in [press, CGPoint(x: band.maxX - 2, y: band.midY)] {
        if let event = moved(point) { timeline.content.bandHoverMoved(with: event) }
        hovers.append(timeline.bandHover)
    }
    timeline.content.bandHoverExited()
    check("D4 timeline bandHoverMoved at the band's centre → (2, 3, edge nil)",
          hovers.first == ActionBandHover(clip: 2, action: 3, edge: nil), "\(hovers)")
    check("D4 … 2 pt from its right end → (2, 3, .end), and an exit clears it",
          hovers.count == 2 && hovers[1] == ActionBandHover(clip: 2, action: 3, edge: .end)
            && timeline.bandHover == nil,
          "\(hovers), after exit \(String(describing: timeline.bandHover))")

    // The report trail (#204, #209; B53): every tick the editor's playback carries from
    // here on, with whether a seek was in flight and the player's own tick, then forwarded.
    var reports: [String] = []
    let playback = controller.playback
    let forward = playback.onTimeChanged
    playback.onTimeChanged = { [weak playback] t in
        let seeking = playback?.isSeeking ?? false
        let tick = playback?.playerLayer.player.map { CompositionBuilder.ticks($0.currentTime()) }
        reports.append("\(secs(t)) seeking \(seeking) player \(secs(tick))")
        forward?(t)
    }

    // D2: move +1 s in three ticks.
    drag(.action(clip: 2, action: 3), from: press,
         steps: [perSecond * 0.3, perSecond * 0.6, perSecond])
    let landed = action(document, 2, 3)
    check("D2 timeline: action 3 dragged +1 s lands at 1.5 – 2.5 s",
          landed?.start == at(1.5) && landed?.endTime == at(2.5), span(landed))
    check("D2 … selected after the drop, the playhead parked at clip start + 2.5 s",
          document.selectedAction == 3 && document.playhead == at(2.5),
          "selected \(document.selectedAction.map { "\($0)" } ?? "nil"), playhead "
            + secs(document.playhead) + "; reports: " + reports.joined(separator: "; "))
    let name = undoName(document)
    document.undoManager?.undo()
    spin(0.3)
    let undone = action(document, 2, 3)
    check("D2 … as ONE step named \"Move Action\": one undo restores 0.5 s and leaves nothing "
            + "to undo",
          name == "Move Action" && undone?.start == at(0.5)
            && document.undoManager?.canUndo == false,
          "undo name '\(name)', after one undo \(span(undone)), canUndo "
            + "\(document.undoManager?.canUndo ?? true)")

    // A single far drag: one tick 5 s to the right.
    if let from = timelineBand(timeline, clip: 2, action: 3) {
        drag(.action(clip: 2, action: 3), from: CGPoint(x: from.midX, y: from.midY),
             steps: [perSecond * 5])
    }
    let far = action(document, 2, 3)
    check("D2 walls: one far tick (+5 s) lands abutting action 4 (start 1.5 s)",
          far?.start == at(1.5) && far?.endTime == at(2.5), span(far))

    // The end grip, 0.5 s to the left.
    let before = action(document, 2, 3)
    if let from = timelineBand(timeline, clip: 2, action: 3) {
        drag(.actionEdge(clip: 2, action: 3, .end), from: CGPoint(x: from.maxX - 2, y: from.midY),
             steps: [-perSecond * 0.5])
    }
    let resized = action(document, 2, 3)
    check("D2 .actionEdge(.end) dragged −0.5 s resizes under \"Resize Action\", the start kept",
          before != nil && resized?.start == before?.start
            && resized?.duration == (before?.duration ?? 0) - at(0.5)
            && undoName(document) == "Resize Action",
          "before \(span(before)), after \(span(resized)), undo '\(undoName(document))'")

    // A press without movement.
    let handle = document.project
    let nameBefore = undoName(document)
    if let from = timelineBand(timeline, clip: 2, action: 3) {
        drag(.action(clip: 2, action: 3), from: CGPoint(x: from.midX, y: from.midY), steps: [])
    }
    check("D2 a press without movement registers no step (same handle, same undo name)",
          document.project === handle && undoName(document) == nameBefore,
          "same handle \(document.project === handle), undo '\(undoName(document))'")

    // A band press inside a multi-selection.
    document.applyEdit("Duplicate", [.duplicate(clips: [2])])
    spin(0.3)
    let copy = document.editedProject.snapshot.clips.first { $0.id != 2 }?.id
    if let copy {
        document.selection = [2, copy]
        controller.viewStateDidChange()
        spin(0.3)
    }
    let multi = document.selection
    if let from = timelineBand(timeline, clip: 2, action: 3) {
        drag(.action(clip: 2, action: 3), from: CGPoint(x: from.midX, y: from.midY), steps: [])
    }
    check("D2 a band press inside a multi-selection collapses it to the band's clip",
          multi.count == 2 && document.selection == [2] && document.selectedAction == 3,
          "before \(multi.sorted()), after \(document.selection.sorted()), selected "
            + "\(document.selectedAction.map { "\($0)" } ?? "nil")")
} else {
    check("D2 the chrome editor and its timeline band", false)
}

// MARK: - D3 the Clip tab's lane, D4 its hit, D6 the decor

func lane(_ controller: EditorViewController) -> ActionLaneView? {
    walk(controller.view).compactMap { $0 as? ClipHeaderBlock }.first?.actionLane
}

func mouse(_ type: NSEvent.EventType, _ view: NSView, _ point: CGPoint) -> NSEvent? {
    NSEvent.mouseEvent(
        with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
        windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
        clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
}

/// Press at `from`, drag through `steps` (points along x), release.
func laneDrag(_ view: ActionLaneView, from: CGPoint, steps: [CGFloat]) -> ActionDragSession?? {
    guard let down = mouse(.leftMouseDown, view, from) else { return nil }
    view.mouseDown(with: down)
    let afterPress = view.drag
    var last = from
    for dx in steps {
        last = CGPoint(x: from.x + dx, y: from.y)
        if let event = mouse(.leftMouseDragged, view, last) { view.mouseDragged(with: event) }
    }
    if let up = mouse(.leftMouseUp, view, last) { view.mouseUp(with: up) }
    spin(0.3)
    return .some(afterPress)
}

if let (document, controller) = editor("chrome", select: [2]), let view = lane(controller),
   let clip = document.editedProject.snapshot.clip(2)
{
    let rects = view.bandRects()
    let lanePerSecond = view.laneRect.width * CGFloat(second) / CGFloat(clip.duration)
    if let three = rects.first(where: { $0.id == 3 })?.rect {
        let hits = [view.bandHit(at: CGPoint(x: three.midX, y: three.midY)),
                    view.bandHit(at: CGPoint(x: three.maxX - 2, y: three.midY))]
        check("D4 lane bandHit(at:): centre → (2, 3, edge nil), 2 pt from the right end → .end",
              hits == [ActionBandHover(clip: 2, action: 3, edge: nil),
                       ActionBandHover(clip: 2, action: 3, edge: .end)],
              "\(hits), band \(three)")
        check("D6 chrome: the card has no transition, fade or motion — every decor slot nil",
              view.decor(clip, in: view.laneRect) == ActionLaneDecor(),
              "\(view.decor(clip, in: view.laneRect))")

        _ = laneDrag(view, from: CGPoint(x: three.midX, y: three.midY),
                     steps: [lanePerSecond * 0.5, lanePerSecond])
        let landed = action(document, 2, 3)
        check("D3 lane: action 3 dragged +1 s lands at 1.5 – 2.5 s",
              landed?.start == at(1.5) && landed?.endTime == at(2.5), span(landed))
        check("D3 … and the dragged action is selected after the drop",
              document.selectedAction == 3,
              "selected \(document.selectedAction.map { "\($0)" } ?? "nil")")
        let name = undoName(document)
        document.undoManager?.undo()
        spin(0.3)
        let undone = action(document, 2, 3)
        check("D3 … as ONE \"Move Action\" step: one undo restores 0.5 s, nothing left to undo",
              name == "Move Action" && undone?.start == at(0.5)
                && document.undoManager?.canUndo == false,
              "undo name '\(name)', after one undo \(span(undone))")
    } else {
        check("D3 lane: the chrome lane has action 3's band", false, "\(rects)")
    }
    if let view = lane(controller), let four = view.bandRects().first(where: { $0.id == 4 })?.rect {
        let handle = document.project
        _ = laneDrag(view, from: CGPoint(x: four.midX, y: four.midY), steps: [])
        check("D3 a bare click on action 4's band selects it and edits nothing",
              document.selectedAction == 4 && document.project === handle,
              "selected \(document.selectedAction.map { "\($0)" } ?? "nil")")
    } else {
        check("D3 a bare click on action 4's band selects it and edits nothing", false, "no lane")
    }
} else {
    check("D3 the chrome editor and its lane", false)
}

// DEVIATION (road map 9 §10): the spec's row pressed a zero-length band in a
// real lane. No lane can show one: the core refuses the project that holds it,
// so the lane's `duration > 0` guard is defensive. The row reads that refusal.
if let path = request["zero"] as? String {
    var refusal = ""
    do {
        try ProjectDocument().read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        refusal = "\(error)"
    }
    check("D3 zero: a zero-length action cannot reach a lane — the core refuses to open the "
            + "project that holds one (\"non-positive duration\")",
          refusal.contains("action 5 on clip 2 has non-positive duration 0"), refusal)
} else {
    check("D3 zero: the zero fixture is named", false)
}

if let (document, controller) = editor("av", select: [2]), let view = lane(controller),
   let two = document.editedProject.snapshot.clip(2),
   let three = document.editedProject.snapshot.clip(3)
{
    let box = view.laneRect
    let decor = view.decor(two, in: box)
    let fade = decor.fadeIn
    check("D6 av: fadeIn is lane × 1/6 wide (1 s of 6), 10 pt tall, at the bottom-left",
          fade.map {
              abs($0.width - box.width / 6) < 0.01 && $0.height == 10 && $0.minX == box.minX
                  && $0.maxY == box.maxY
          } == true && decor.fadeOut == nil,
          "lane \(box), fadeIn \(String(describing: fade)), fadeOut "
            + "\(String(describing: decor.fadeOut))")
    let hatch = view.decor(three, in: box).hatch
    let overlap = CGFloat(two.end - three.start) / CGFloat(three.duration)
    check("D6 av: the overlapping clip's hatch is the overlap's fraction (1 s of its 6), "
            + "full height, at the left; clip 2 itself has none",
          hatch.map {
              abs($0.width - box.width * overlap) < 0.01 && $0.height == box.height
                  && $0.minX == box.minX
          } == true && decor.hatch == nil,
          "hatch \(String(describing: hatch)), overlap fraction \(overlap)")
    let wedge = decor.wedgeIn
    check("D6 av: wedgeIn is the edge's length (0.5 s of 6), 8 pt tall, at the top-left",
          wedge.map {
              abs($0.width - box.width / 12) < 0.01 && $0.height == 8 && $0.minX == box.minX
                  && $0.minY == box.minY
          } == true && decor.wedgeOut == nil,
          "wedgeIn \(String(describing: wedge)), wedgeOut \(String(describing: decor.wedgeOut))")
} else {
    check("D6 the av editor and its lane", false)
}

// MARK: - D4 the grip rule

let narrow = CGRect(x: 0, y: 0, width: 15, height: 10)
let wide = CGRect(x: 0, y: 0, width: 16, height: 10)
check("D4 a band ≤ 15 pt answers no edge anywhere; at 16 pt its outer 5 pt are grips",
      [0, 1, 5, 7.5, 10, 14, 15].allSatisfy { ActionBands.gripEdge(in: narrow, at: $0) == nil }
        && ActionBands.gripEdge(in: wide, at: 1) == .start
        && ActionBands.gripEdge(in: wide, at: 15) == .end
        && ActionBands.gripEdge(in: wide, at: 8) == nil,
      "16 pt: \(String(describing: ActionBands.gripEdge(in: wide, at: 1))), "
        + "\(String(describing: ActionBands.gripEdge(in: wide, at: 15)))")

let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
