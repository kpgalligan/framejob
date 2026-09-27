// Road map 12 A1 — the agent lane's probe (spec §11 AI-2, AI-3, AI-5, AI-7,
// AI-12; #144).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line, `-D REELCUT_DEV_TOOLS` — by
// `assistant_lane_proof.py`. Because it cannot see `app/Sources/main.swift`,
// the launch path itself is the proof's L0, not a row here.
//
//   assistant_lane_probe <work-dir> [--no-prepare] [--rows L1,L2,…]
//
// Prints exactly one stdout line:
//   ANSWER {"rows":[{"id","ok","detail"}],"measure":{…}}
//
// Nothing here calls `AgentServer.start()`: the gate is filled only by
// `AgentLane.prepareAtLaunch()`, called at the top as `main.swift` calls it,
// and skipped under `--no-prepare` (the made-to-fail run: L1 must then fail,
// because the gate refuses `at` and `name` as arguments no tool published).
// No media is used; every clip is a text clip. Every row makes its own
// documents after closing the last row's.
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

let argv = CommandLine.arguments
let work = argv.count > 1 ? argv[1] : NSTemporaryDirectory()
let noPrepare = argv.contains("--no-prepare")
let onlyRows: Set<String>? = argv.firstIndex(of: "--rows").flatMap { index in
    index + 1 < argv.count ? Set(argv[index + 1].split(separator: ",").map(String.init)) : nil
}

if !noPrepare {
    AgentLane.prepareAtLaunch()
}

var rows: [[String: Any]] = []
var measure: [String: Any] = ["no_prepare": noPrepare]

func row(_ id: String, _ ok: Bool, _ detail: String) {
    rows.append(["id": id, "ok": ok, "detail": String(detail.prefix(1500))])
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
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

func json(_ object: [String: Any]) -> String {
    String(data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8),
           encoding: .utf8) ?? "{}"
}

/// A result crossing from the lane (or a background thread) to main.
final class Pending {
    private let lock = NSLock()
    private var stored: String?

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ result: String) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}

/// The ask-first hook, scripted: each question is recorded (main only) and
/// answered with the next scripted answer, Deny when none is left.
final class Hook {
    var questions: [String] = []
    var answers: [Bool]

    init(_ answers: [Bool] = []) {
        self.answers = answers
    }

    var closure: AssistantAskFirst {
        { [self] question, reply in
            questions.append(question.sentence)
            reply(answers.isEmpty ? false : answers.removeFirst())
        }
    }
}

/// `serve`, from a background thread, as the MCP server thread calls it.
func serve(_ tool: String, _ arguments: [String: Any]) -> Pending {
    let pending = Pending()
    let body = json(arguments)
    DispatchQueue.global().async {
        pending.set(AgentLane.shared.serve(tool: tool, argumentsJSON: body))
    }
    return pending
}

/// `submit`, pinned to `document`, from main, as the session will call it.
func submit(_ tool: String, _ arguments: [String: Any], _ document: ProjectDocument,
            _ hook: Hook) -> Pending {
    let pending = Pending()
    AgentLane.shared.submit(
        tool: tool, argumentsJSON: json(arguments), document: document,
        askFirst: hook.closure, completion: { pending.set($0) })
    return pending
}

func wait(_ pending: Pending, _ seconds: Double = 30) -> String? {
    let deadline = Date().addingTimeInterval(seconds)
    while pending.value == nil && Date() < deadline { spin(0.02) }
    return pending.value
}

func parsed(_ result: String?) -> [String: Any] {
    guard let result = result else { return [:] }
    return (try? JSONSerialization.jsonObject(with: Data(result.utf8))) as? [String: Any] ?? [:]
}

func isError(_ result: String?) -> Bool {
    guard result != nil else { return true }
    return parsed(result)["isError"] as? Bool == true
}

func text(_ result: String?) -> String {
    ((parsed(result)["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }
        .joined(separator: " ")
}

func brief(_ result: String?) -> String {
    guard let result = result else { return "no answer" }
    return (isError(result) ? "error: " : "ok: ") + String(text(result).prefix(240))
}

func closeAll() {
    for document in AgentServer.shared.openProjects() { document.close() }
    spin(0.2)
}

func newDocument() -> ProjectDocument {
    let document = ProjectDocument()
    NSDocumentController.shared.addDocument(document)
    document.makeWindowControllers()
    document.showWindows()
    spin(0.5)
    return document
}

func markerNames(_ document: ProjectDocument) -> [String] {
    document.project.snapshot.markers.map { $0.name }
}

func clipStart(_ document: ProjectDocument, _ id: UInt32) -> Int? {
    document.project.snapshot.clips.first { $0.id == id }.map { Int($0.start) }
}

func path(_ name: String) -> String {
    (work as NSString).appendingPathComponent(name)
}

func remove(_ file: String) {
    try? FileManager.default.removeItem(atPath: file)
}

func wanted(_ id: String) -> Bool { onlyRows?.contains(id) ?? true }

// MARK: - L1 (AI-3): a call with arguments after prepareAtLaunch() alone

func rowL1() {
    closeAll()
    let a = newDocument()
    let hook = Hook()
    let added = wait(submit("add_marker", ["at": 600_000, "name": "L1"], a, hook))
    let got = wait(submit("get_project", [:], a, hook))
    let body = (try? JSONSerialization.jsonObject(with: Data(text(got).utf8))) as? [String: Any]
    let listed = (((body?["project"] as? [String: Any])?["markers"] as? [[String: Any]]) ?? [])
        .compactMap { $0["name"] as? String }
    let ok = !isError(added) && !isError(got) && listed.contains("L1") && hook.questions.isEmpty
    row("L1", ok, "submit add_marker {at, name}: \(brief(added)); get_project markers \(listed)")
}

// MARK: - L2 (AI-2): 20 concurrent calls, serve and submit alternating

func rowL2() {
    closeAll()
    let a = newDocument()
    let b = newDocument()
    let bPath = path("L2-B.reelcut")
    remove(bPath)
    let saved = wait(submit("save_project", ["path": bPath], b, Hook([true])), 60)
    guard !isError(saved), b.fileURL != nil else {
        row("L2", false, "B did not save: \(brief(saved))")
        return
    }
    var pendings: [(Int, Pending)] = []
    for i in 0..<20 {
        let name = "L2-\(i)"
        let at = (i + 1) * 600_000
        if i % 2 == 0 {
            pendings.append((i, serve("add_marker", ["at": at, "name": name, "project": bPath])))
        } else {
            pendings.append((i, submit("add_marker", ["at": at, "name": name], a, Hook())))
        }
    }
    let deadline = Date().addingTimeInterval(60)
    while pendings.contains(where: { $0.1.value == nil }) && Date() < deadline { spin(0.05) }
    let errors = pendings.filter { isError($0.1.value) }.map { "\($0.0): \(brief($0.1.value))" }
    let onA = Set(markerNames(a).filter { $0.hasPrefix("L2-") })
    let onB = Set(markerNames(b).filter { $0.hasPrefix("L2-") })
    let wantA = Set((0..<20).filter { $0 % 2 == 1 }.map { "L2-\($0)" })
    let wantB = Set((0..<20).filter { $0 % 2 == 0 }.map { "L2-\($0)" })
    measure["l2"] = ["a": onA.sorted(), "b": onB.sorted(), "errors": errors]
    row("L2", errors.isEmpty && onA == wantA && onB == wantB,
        "errors \(errors.count)\(errors.isEmpty ? "" : " \(errors.prefix(3))"); A holds "
            + "\(onA.count) (the 10 submits: \(onA == wantA)), B holds \(onB.count) (the 10 "
            + "serves: \(onB == wantB))")
}

// MARK: - L3 (AI-5): the pinned document

func rowL3() {
    closeAll()
    let a = newDocument()
    let b = newDocument()
    let bPath = path("L3-B.reelcut")
    remove(bPath)
    let saved = wait(submit("save_project", ["path": bPath], b, Hook([true])), 60)
    b.showWindows()
    spin(0.3)
    let bFront = NSApp.orderedDocuments.first === b
    let hook = Hook()
    let pinned = wait(submit("add_marker", ["at": 600_000, "name": "L3-pinned"], a, hook))
    let landed = markerNames(a).contains("L3-pinned") && !markerNames(b).contains("L3-pinned")
    let aBefore = markerNames(a)
    let bBefore = markerNames(b)
    let other = wait(submit(
        "add_marker", ["at": 1_200_000, "name": "L3-other", "project": bPath], a, hook))
    let name = a.displayName ?? "Untitled"
    let expected = "The assistant edits its own window's project, \(name); \(bPath) is a "
        + "different project."
    let unchanged = markerNames(a) == aBefore && markerNames(b) == bBefore
    a.close()
    spin(0.2)
    let closed = wait(submit("add_marker", ["at": 1_800_000, "name": "L3-closed"], a, hook))
    let closedExpected = "The assistant's project, \(name), is no longer open."
    measure["l3"] = ["b_frontmost": bFront, "saved": brief(saved), "other": text(other),
                     "closed": text(closed)]
    row("L3", !isError(saved) && bFront && !isError(pinned) && landed && isError(other)
            && text(other) == expected && unchanged && isError(closed)
            && text(closed) == closedExpected && hook.questions.isEmpty,
        "B frontmost \(bFront); pinned to A: \(brief(pinned)), landed on A only \(landed); "
            + "project = B: \(brief(other)) (the AI-5 sentence: \(text(other) == expected)), "
            + "neither changed \(unchanged); A closed: \(brief(closed))")
}

// MARK: - L4 (AI-7): withheld tools

func rowL4() {
    closeAll()
    let d = newDocument()
    let hook = Hook([true, true, true])
    let cases: [(String, [String: Any], String)] = [
        ("record_screen", [:],
         "record_screen is not available to the assistant: Recording is a person at the "
            + "Record button (File ▸ New Recording…)."),
        ("transcribe", ["engine": "assemblyai"],
         "transcribe with engine \"assemblyai\" is not available to the assistant: Audio "
            + "leaves the machine only by name, with the price in front of the person (spec "
            + "§11 R6-2). Use File ▸ Generate Captions…, which shows what is uploaded and what "
            + "it costs."),
        ("snapshot_ui", [:],
         "snapshot_ui is not available to the assistant: a developer tool (spec §11 V-1): "
            + "Distribution has none, and the assistant sees one catalog in both builds."),
    ]
    var ok = true
    var details: [String] = []
    for (tool, arguments, expected) in cases {
        let result = wait(submit(tool, arguments, d, hook))
        let same = isError(result) && text(result) == expected
        ok = ok && same
        details.append("\(tool): refused as written \(same)")
    }
    let served = wait(serve("snapshot_ui", [:]), 60)
    let notLane = served != nil && !text(served).contains("is not available to the assistant")
    measure["l4"] = ["serve_snapshot_ui_error": isError(served),
                     "serve_snapshot_ui": String(text(served).prefix(200))]
    row("L4", ok && hook.questions.isEmpty && notLane,
        details.joined(separator: "; ") + "; hook called \(hook.questions.count) times; "
            + "serve snapshot_ui not refused by the lane \(notLane) (isError "
            + "\(isError(served)))")
}

// MARK: - L5 (AI-7): ask first

func rowL5() {
    closeAll()
    let e = newDocument()
    let p = path("L5-fresh.mp4")
    let s = path("L5-sentinel.mp4")
    let q = path("L5-Q.reelcut")
    let r = path("L5-R.reelcut")
    for file in [p, s, q, r] { remove(file) }
    let sentinel = Data("L5-SENTINEL\n".utf8)
    FileManager.default.createFile(atPath: s, contents: sentinel)
    let files = FileManager.default
    var checks: [(String, Bool)] = []

    let h1 = Hook([false])
    let fresh = wait(submit("export", ["preset": "h264", "path": p], e, h1))
    checks.append(("fresh: asked \"export writes P\"", h1.questions == ["export writes \(p)"]))
    checks.append(("fresh: declined as written",
                   isError(fresh) && text(fresh) == "The person declined: export writes \(p).")
    )
    checks.append(("fresh: no file at P", !files.fileExists(atPath: p)))

    let h2 = Hook([false])
    let onto = wait(submit("export", ["preset": "h264", "path": s], e, h2))
    checks.append(("sentinel: asked \"export REPLACES S\"",
                   h2.questions == ["export REPLACES \(s)"]))
    checks.append(("sentinel: declined", isError(onto)))
    checks.append(("sentinel: S unchanged", files.contents(atPath: s) == sentinel))

    let h3 = Hook([true])
    let allowed = wait(submit("save_project", ["path": q], e, h3), 60)
    checks.append(("save Allow: asked \"save_project writes Q\"",
                   h3.questions == ["save_project writes \(q)"]))
    checks.append(("save Allow: ok and Q exists", !isError(allowed) && files.fileExists(atPath: q)))

    let h4 = Hook([false])
    let again = wait(submit("save_project", ["path": q], e, h4), 60)
    checks.append(("save again Deny: asked \"save_project REPLACES Q\"",
                   h4.questions == ["save_project REPLACES \(q)"]))
    checks.append(("save again Deny: declined", isError(again)
                    && text(again) == "The person declined: save_project REPLACES \(q)."))

    let asked = h1.questions.count + h2.questions.count + h3.questions.count
        + h4.questions.count
    let served = wait(serve("save_project", ["path": r, "project": q]), 60)
    let askedAfter = h1.questions.count + h2.questions.count + h3.questions.count
        + h4.questions.count
    checks.append(("serve save_project: no hook, R written",
                   asked == askedAfter && !isError(served) && files.fileExists(atPath: r)))

    measure["l5"] = ["questions": h1.questions + h2.questions + h3.questions + h4.questions,
                     "fresh": text(fresh), "allowed": brief(allowed), "served": brief(served)]
    let failed = checks.filter { !$0.1 }.map { $0.0 }
    row("L5", failed.isEmpty,
        "\(checks.count - failed.count)/\(checks.count) checks"
            + (failed.isEmpty ? "" : "; failed: \(failed.joined(separator: ", "))"))
}

// MARK: - L6: the assistant's catalog

func rowL6() {
    var tools: [[String: Any]] = []
    do {
        let catalog = try AgentServer.shared.catalogJSON()
        tools = (try? JSONSerialization.jsonObject(with: Data(catalog.utf8)))
            as? [[String: Any]] ?? []
    } catch {
        row("L6", false, "the catalog did not build: \(error)")
        return
    }
    let names = Set(AssistantToolTable.assistantCatalog(tools).compactMap {
        $0["name"] as? String
    })
    let dev = AgentServer.devToolNames
    // Every core tool (loaded up front, not deferred) must be one the
    // assistant is handed, or the helper would be told to load a stranger.
    let missingCore = AssistantPrompt.coreTools.filter { !names.contains($0) }
    let ok = !dev.isEmpty && !names.contains("record_screen") && names.isDisjoint(with: dev)
        && names.contains("transcribe") && names.contains("export") && missingCore.isEmpty
    measure["l6"] = ["catalog": tools.count, "assistant": names.count, "dev": dev.sorted(),
                     "core_tools": AssistantPrompt.coreTools]
    row("L6", ok,
        "\(tools.count) tools → \(names.count) for the assistant; record_screen "
            + "\(names.contains("record_screen")), dev tools \(dev.sorted()) present "
            + "\(!names.isDisjoint(with: dev)), transcribe \(names.contains("transcribe")), "
            + "export \(names.contains("export")), core tools \(AssistantPrompt.coreTools) "
            + "missing \(missingCore)")
}

// MARK: - The drag rows: L7, L8 (#144, AI-12), L9 and C1

struct Drag {
    let document: ProjectDocument
    let timeline: TimelineView
    let clip: UInt32
    let point: CGPoint
}

/// A new document holding one text clip at 0, with a clip-body drag ready.
func dragFixture(_ call: (String, [String: Any], ProjectDocument) -> Pending) -> Drag? {
    closeAll()
    let document = newDocument()
    let added = wait(call("add_text_clip", ["track": 1, "at": 0, "duration": 1_200_000],
                          document))
    spin(0.3)
    guard !isError(added),
        let clipID = document.project.snapshot.clips.first?.id,
        let controller = AgentServer.shared.editor(document),
        let timeline = controller.timeline,
        let trackIndex = timeline.snapshot.trackIndex(of: 1),
        let clip = timeline.snapshot.clips(onTrack: 1).first(where: { $0.id == clipID })
    else { return nil }
    let rect = timeline.layout.clipRect(clip, row: timeline.layout.row(forTrackIndex: trackIndex))
    return Drag(document: document, timeline: timeline, clip: clipID,
                point: CGPoint(x: rect.midX, y: rect.midY))
}

func tick(_ drag: Drag, _ dx: CGFloat) {
    drag.timeline.continueGesture(at: CGPoint(x: drag.point.x + dx, y: drag.point.y), flags: [])
    spin(0.1)
}

func begin(_ drag: Drag) {
    let hit = drag.timeline.content.hit(at: drag.point)
    drag.timeline.beginGesture(hit: hit, at: drag.point, flags: [], clicks: 1)
    spin(0.1)
}

func end(_ drag: Drag, _ dx: CGFloat) {
    drag.timeline.endGesture(at: CGPoint(x: drag.point.x + dx, y: drag.point.y), flags: [])
    spin(0.3)
}

/// L7 and L8: the call arrives between two ticks, waits out two more, and
/// runs after mouse-up above the gesture's own undo step.
func waitRow(_ id: String, _ call: @escaping (String, [String: Any], ProjectDocument) -> Pending) {
    guard let drag = dragFixture(call) else {
        row(id, false, "no document, clip or timeline to drag")
        return
    }
    let document = drag.document
    begin(drag)
    tick(drag, 40)
    let live = document.isLiveEditing
    let pending = call("add_marker", ["at": 600_000, "name": id], document)
    spin(0.1)
    tick(drag, 60)
    tick(drag, 80)
    let returnedMidDrag = pending.value != nil
    end(drag, 80)
    let result = wait(pending, 10)
    spin(0.2)
    let present = markerNames(document).contains(id)
    let startAfterUp = clipStart(document, drag.clip)
    let undo1 = document.undoManager?.undoActionName ?? ""
    document.undoManager?.undo()
    spin(0.2)
    let presentAfterUndo1 = markerNames(document).contains(id)
    let startAfterUndo1 = clipStart(document, drag.clip)
    let undo2 = document.undoManager?.undoActionName ?? ""
    document.undoManager?.undo()
    spin(0.2)
    let startAfterUndo2 = clipStart(document, drag.clip)
    let moved = (startAfterUp ?? 0) != 0
    let ok = live && !returnedMidDrag && !isError(result) && present && moved
        && undo1 == "Add Marker" && !presentAfterUndo1 && startAfterUndo1 == startAfterUp
        && undo2 == "Move Clips" && startAfterUndo2 == 0
    measure[id.lowercased()] = [
        "live": live, "returned_mid_drag": returnedMidDrag, "result": brief(result),
        "present": present, "start_after_up": startAfterUp as Any? ?? NSNull(),
        "undo1": undo1, "present_after_undo1": presentAfterUndo1,
        "start_after_undo1": startAfterUndo1 as Any? ?? NSNull(), "undo2": undo2,
        "start_after_undo2": startAfterUndo2 as Any? ?? NSNull(),
    ]
    let startText = startAfterUp.map(String.init) ?? "nil"
    row(id, ok,
        "live \(live); returned during two more ticks \(returnedMidDrag); after mouse-up "
            + "\(brief(result)), marker present \(present), clip 0 → \(startText); undo "
            + "\"\(undo1)\" → marker \(presentAfterUndo1), clip "
            + "\(startAfterUndo1.map(String.init) ?? "nil"); undo \"\(undo2)\" → clip "
            + "\(startAfterUndo2.map(String.init) ?? "nil")")
}

func rowL9() {
    guard let drag = dragFixture({ tool, arguments, _ in serve(tool, arguments) }) else {
        row("L9", false, "no document, clip or timeline to drag")
        return
    }
    begin(drag)
    tick(drag, 40)
    let live = drag.document.isLiveEditing
    let started = Date()
    let value = AgentLane.shared.onMainWhenIdle { 42 }
    let elapsed = Date().timeIntervalSince(started)
    end(drag, 40)
    measure["l9"] = ["live": live, "value": value, "seconds": elapsed]
    row("L9", live && value == 42 && elapsed < 0.1,
        "gesture live \(live); onMainWhenIdle on main answered \(value) in "
            + String(format: "%.4f", elapsed) + " s")
}

func rowC1() {
    guard let drag = dragFixture({ tool, arguments, _ in serve(tool, arguments) }) else {
        row("C1", false, "no document, clip or timeline to drag")
        return
    }
    let document = drag.document
    begin(drag)
    tick(drag, 40)
    let live = document.isLiveEditing
    // A0's D2: `execute` run on main between two ticks, as the old trampoline
    // ran it — no lane, no wait.
    let result = AgentServer.shared.execute(
        tool: "add_marker", argumentsJSON: json(["at": 600_000, "name": "C1"]))
    let presentAfterAdd = markerNames(document).contains("C1")
    tick(drag, 80)
    end(drag, 80)
    let presentAfterUp = markerNames(document).contains("C1")
    measure["c1"] = ["live": live, "result": brief(result), "present_after_add": presentAfterAdd,
                     "present_after_up": presentAfterUp]
    row("C1", live && !isError(result) && presentAfterAdd && !presentAfterUp,
        "execute on main mid-drag: \(brief(result)); present after add \(presentAfterAdd), "
            + "after mouse-up \(presentAfterUp) (the loss #144 names: \(!presentAfterUp))")
}

try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
let steps: [(String, () -> Void)] = [
    ("L1", rowL1), ("L2", rowL2), ("L3", rowL3), ("L4", rowL4), ("L5", rowL5), ("L6", rowL6),
    ("L7", { waitRow("L7", { tool, arguments, _ in serve(tool, arguments) }) }),
    ("L8", { waitRow("L8", { tool, arguments, document in
        submit(tool, arguments, document, Hook()) }) }),
    ("L9", rowL9), ("C1", rowC1),
]
for (id, step) in steps where wanted(id) {
    step()
}
closeAll()
answer()
