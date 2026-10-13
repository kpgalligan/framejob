// Road map 12, A0 — the D probe: what an agent edit does to a timeline drag
// that is in progress (road map 12 §5's fifth A0 question).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line, `-D FRAMEJOB_DEV_TOOLS` —
// by `assistant_spike.py`.
//
//   drag_probe <out-dir>
//
// Prints exactly one stdout line:
//   ANSWER {"rows":[{"id","ok","detail"}],"measure":{…}}
//
// D1: `add_marker` with no gesture in flight. D2: the same tool, run on main
// between two `continueGesture` ticks of a clip-body drag — which is where
// the MCP trampoline's `main.sync` (AgentServer.swift) would run it. The drag
// is driven through `TimelineView`'s three gesture methods, which the
// content view's mouse overrides forward to (TimelineView.swift, "Mouse"):
// no NSEvent is synthesised.
import AppKit

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

var rows: [[String: Any]] = []
var measure: [String: Any] = [:]

func row(_ id: String, _ ok: Bool, _ detail: String) {
    rows.append(["id": id, "ok": ok, "detail": String(detail.prefix(1200))])
}

func answer() -> Never {
    let body: [String: Any] = ["rows": rows, "measure": measure]
    let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print("ANSWER " + (String(data: data, encoding: .utf8) ?? "{}"))
    fflush(stdout)
    exit(0)
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func call(_ tool: String, _ arguments: [String: Any]) -> [String: Any] {
    let json = String(
        data: (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8),
        encoding: .utf8) ?? "{}"
    let result = AgentServer.shared.execute(tool: tool, argumentsJSON: json)
    return (try? JSONSerialization.jsonObject(with: Data(result.utf8))) as? [String: Any] ?? [:]
}

func isError(_ result: [String: Any]) -> Bool { result["isError"] as? Bool == true }

func text(_ result: [String: Any]) -> String {
    ((result["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }
        .joined(separator: " ")
}

/// The project as `get_project` answers it.
func project() -> [String: Any] {
    let result = call("get_project", [:])
    let body = (try? JSONSerialization.jsonObject(with: Data(text(result).utf8)))
        as? [String: Any] ?? [:]
    return body["project"] as? [String: Any] ?? [:]
}

func markers(named name: String) -> [[String: Any]] {
    ((project()["markers"] as? [[String: Any]]) ?? []).filter { $0["name"] as? String == name }
}

func clipStart(_ id: Int) -> Int? {
    let clips = (project()["clips"] as? [[String: Any]]) ?? []
    return clips.first { ($0["id"] as? Int) == id }?["start"] as? Int
}

func state(_ clip: Int) -> [String: Any] {
    ["mid_drag_marker": !markers(named: "mid-drag").isEmpty,
     "no_gesture_marker": !markers(named: "no-gesture").isEmpty,
     "clip_start": clipStart(clip) as Any? ?? NSNull()]
}

// §3c: the gate is filled only by `start()`; the probe fills it the way
// AI-3's `prepareCatalog()` will.
do {
    AgentServer.noteArguments(in: try AgentServer.shared.catalogJSON())
} catch {
    row("D1", false, "the catalog did not build: \(error)")
    row("D2", false, "the catalog did not build: \(error)")
    answer()
}

let document = ProjectDocument()
NSDocumentController.shared.addDocument(document)
document.makeWindowControllers()
document.showWindows()
spin(1.0)

let added = call("add_text_clip", ["track": 1, "at": 0, "duration": 1_200_000])
spin(0.3)
let clips = (project()["clips"] as? [[String: Any]]) ?? []
guard !isError(added), let clipID = clips.first?["id"] as? Int else {
    row("D1", false, "add_text_clip failed: \(text(added).prefix(300))")
    row("D2", false, "add_text_clip failed: \(text(added).prefix(300))")
    answer()
}
measure["clip"] = clipID
measure["clip_start_before"] = clipStart(clipID) as Any? ?? NSNull()

// D1 — no gesture.
let noGesture = call("add_marker", ["at": 1_800_000, "name": "no-gesture"])
spin(0.3)
let d1Present = !markers(named: "no-gesture").isEmpty
let d1Undo = document.undoManager?.undoActionName ?? ""
measure["d1"] = ["error": isError(noGesture), "present": d1Present, "undo_name": d1Undo]
row("D1", !isError(noGesture) && d1Present,
    "add_marker with no gesture: present \(d1Present), undo name \"\(d1Undo)\""
        + (isError(noGesture) ? ", error \(text(noGesture).prefix(200))" : ""))

// D2 — mid-drag.
guard
    let controller = AgentServer.shared.editor(document),
    let timeline = controller.timeline,
    let snapshotTrack = timeline.snapshot.trackIndex(of: 1),
    let clip = timeline.snapshot.clips(onTrack: 1).first(where: { Int($0.id) == clipID })
else {
    row("D2", false, "no editor, timeline or clip snapshot to drag")
    answer()
}
let rowIndex = timeline.layout.row(forTrackIndex: snapshotTrack)
let rect = timeline.layout.clipRect(clip, row: rowIndex)
let p = CGPoint(x: rect.midX, y: rect.midY)
let hit = timeline.content.hit(at: p)
measure["drag"] = ["rect": [rect.minX, rect.minY, rect.width, rect.height],
                   "hit": "\(hit)"]

timeline.beginGesture(hit: hit, at: p, flags: [], clicks: 1)
spin(0.1)
timeline.continueGesture(at: CGPoint(x: p.x + 40, y: p.y), flags: [])
spin(0.1)
let startAfterTick1 = clipStart(clipID)
let midDrag = call("add_marker", ["at": 600_000, "name": "mid-drag"])
spin(0.1)
let presentAfterAdd = !markers(named: "mid-drag").isEmpty
let undoAfterAdd = document.undoManager?.undoActionName ?? ""
timeline.continueGesture(at: CGPoint(x: p.x + 80, y: p.y), flags: [])
spin(0.1)
let presentAfterTick2 = !markers(named: "mid-drag").isEmpty
timeline.endGesture(at: CGPoint(x: p.x + 80, y: p.y), flags: [])
spin(0.5)
let presentAfterUp = !markers(named: "mid-drag").isEmpty
let startAfterUp = clipStart(clipID)

var undos: [[String: Any]] = []
for _ in 0..<6 {
    guard let undo = document.undoManager, undo.canUndo else { break }
    let name = undo.undoActionName
    undo.undo()
    spin(0.2)
    var entry = state(clipID)
    entry["undid"] = name
    undos.append(entry)
}

measure["d2"] = [
    "error": isError(midDrag), "result": String(text(midDrag).prefix(300)),
    "clip_start_after_tick1": startAfterTick1 as Any? ?? NSNull(),
    "present_after_add": presentAfterAdd, "undo_name_after_add": undoAfterAdd,
    "present_after_tick2": presentAfterTick2, "present_after_mouse_up": presentAfterUp,
    "clip_start_after_mouse_up": startAfterUp as Any? ?? NSNull(), "undos": undos,
]
let undoText = undos.map {
    "\"\($0["undid"] ?? "")\" → marker \($0["mid_drag_marker"] ?? "?"), clip start \($0["clip_start"] ?? "?")"
}.joined(separator: "; ")
row("D2", !isError(midDrag) && presentAfterTick2 && presentAfterUp,
    "add_marker mid-drag: error \(isError(midDrag)), present after add \(presentAfterAdd), "
        + "after tick 2 \(presentAfterTick2), after mouse-up \(presentAfterUp); clip start "
        + "\(measure["clip_start_before"] ?? "?") → \(startAfterUp.map(String.init) ?? "nil"); "
        + "undos: \(undoText)")
answer()
