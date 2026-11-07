// ai-docs b2's probe (#531 #525): the real app/Sources code on a real `.framejob` package the app
// under test saved, compiled AS main.swift over every file of app/Sources but the app's
// main.swift, through tools/proof/swift_build.py (`ai_docs_b2_proof.py` builds it, and runs the
// same source on the base and the fix).
//
//   ai-docs-b2-probe <mode> <package> <scratch folder>
//
// sheet   P1: a real ExportProgressSheetController exporting `h264` (0–20 s at 640 × 360) over an
//         existing file; once it reads "Writing" past 3 %, Cancel gets `performClick`, and once the
//         sheet is gone the file's bytes and the folder are read.
// queue   Q1, Q2: three jobs to one path through the real ExportQueueController.shared.enqueue.
//         A completes; B is cancelled while it writes; C completes. Q1 reads A's row and the file
//         after B; Q2 reads A's row while C writes and after it, and C's message.
// submit  A1: the real AgentLane.shared.submit of `get_project` whose arguments hold
//         FRAMEJOB_RAISE_525, pinned to the opened document. Run under lldb with
//         `ai_docs_b2_inject.m` loaded, so the arguments' parse raises on the document's queue.
//
// Nothing reaches the screen or takes focus: activation policy .prohibited, a window 20,000 pt
// off every display that never becomes key. The probe never touches a pasteboard and names only
// symbols the base tree has; it finds the progress sheet's labels and button by a view walk.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
DecoderSupport.enable()

let mode = CommandLine.arguments[1]
let package = URL(fileURLWithPath: CommandLine.arguments[2])
let scratch = URL(fileURLWithPath: CommandLine.arguments[3])
let clock = Date()
let second = 600_000

func say(_ row: String, _ fields: [String: Any]) {
    var line = fields
    line["row"] = row
    line["t"] = (Date().timeIntervalSince(clock) * 1000).rounded() / 1000
    let data = try! JSONSerialization.data(
        withJSONObject: line, options: [.sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

final class OffWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct Open {
    let doc: ProjectDocument
    let controller: EditorViewController
    let window: NSWindow
    let keep: NSWindowController
}

func open(_ package: URL) -> Open {
    let copy = scratch.appendingPathComponent("open-\(mode)-\(package.lastPathComponent)")
    try? FileManager.default.removeItem(at: copy)
    try! FileManager.default.copyItem(at: package, to: copy)
    let doc = ProjectDocument()
    do {
        try doc.read(from: copy, ofType: ProjectDocument.projectTypeIdentifier)
        doc.fileURL = copy
    } catch {
        say("abort", ["read": "\(error)"])
        exit(2)
    }
    doc.startGraphicStore()
    let controller = EditorViewController(document: doc)
    let frame = NSRect(x: -20000, y: -20000, width: 1440, height: 900)
    let window = OffWindow(
        contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered, defer: false)
    window.contentViewController = controller
    window.setFrame(frame, display: false)
    controller.viewWillAppear()
    controller.viewDidAppear()
    controller.refreshFromDocument(isLive: false)
    let keep = NSWindowController(window: window)
    doc.addWindowController(keep)
    window.orderBack(nil)
    for _ in 0..<12 {
        spin(0.05)
        controller.view.layoutSubtreeIfNeeded()
    }
    return Open(doc: doc, controller: controller, window: window, keep: keep)
}

func allViews(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap { allViews($0) } }

/// `h264`, 0–20 s, 640 × 360: what every export here writes.
func settings(_ o: Open) -> ExportSettings {
    try! ReelExport.settings(
        o.doc.project, preset: "h264",
        overrides: ["range": ["start": 0, "duration": 20 * second], "width": 640, "height": 360])
}

/// A folder of its own, so its listing is the row's.
func folder(_ name: String) -> URL {
    let url = scratch.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func listing(_ url: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
}

func bytes(_ url: URL) -> Data? { try? Data(contentsOf: url) }

// MARK: - P1: the Export… progress sheet's Cancel

func sheetRow(_ o: Open) {
    let place = folder("p1")
    let destination = place.appendingPathComponent("over.mp4")
    let old = Data("the file the person already had\n".utf8)
    try! old.write(to: destination)
    let controller = ExportProgressSheetController(
        project: o.doc.project, urls: o.doc.mediaURLs(), settings: settings(o), to: destination)
    let views = allViews(controller.view)
    let fields = views.compactMap { $0 as? NSTextField }
    guard let status = fields.first(where: { $0.stringValue.hasPrefix("Preparing") }),
        let percent = fields.first(where: { $0.stringValue.hasSuffix(" %") }),
        let button = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Cancel" })
    else {
        say("P1", ["error": "the sheet's labels or button were not found"])
        return
    }
    // Presented as beginExport presents it, on the off-screen window, so its dismiss has a
    // presenter; viewDidAppear (guarded by didStart) starts the export.
    o.controller.presentAsSheet(controller)
    spin(0.2)
    controller.viewDidAppear()
    var wrote = false
    let start = Date()
    while Date().timeIntervalSince(start) < 900 {
        let value = Double(percent.stringValue.replacingOccurrences(of: " %", with: "")) ?? 0
        if status.stringValue.hasPrefix("Writing"), value >= 3 {
            wrote = true
            break
        }
        spin(0.01)
    }
    guard wrote else {
        say("P1", ["error": "never wrote past 3 %", "status": status.stringValue])
        return
    }
    let at = percent.stringValue
    button.performClick(nil)
    let stop = Date()
    while Date().timeIntervalSince(stop) < 300, o.window.attachedSheet != nil { spin(0.05) }
    spin(0.5)
    say("P1", ["cancelled_at": at, "dismissed": o.window.attachedSheet == nil,
               "exists": FileManager.default.fileExists(atPath: destination.path),
               "same": bytes(destination) == old, "listing": listing(place)])
}

// MARK: - Q1, Q2: the queue's superseded mark

func queueRows(_ o: Open) {
    o.doc.publishReverseResolution()
    let place = folder("q")
    let destination = place.appendingPathComponent("same.mp4")
    let q = ExportQueueController.shared
    let made = settings(o)

    /// Waits for job `id` to finish, calling `during` on each 20 ms sample while it runs.
    func wait(_ id: UInt64, during: (ExportQueueController.Job) -> Void = { _ in }) -> String {
        let start = Date()
        while Date().timeIntervalSince(start) < 900 {
            guard let job = q.jobs.first(where: { $0.id == id }) else { return "gone" }
            if job.state.isFinished { return "\(job.state)" }
            during(job)
            spin(0.02)
        }
        return "timed out"
    }
    func row(_ id: UInt64) -> ExportQueueController.Job? { q.jobs.first { $0.id == id } }
    func writing(_ job: ExportQueueController.Job) -> Bool {
        job.state == .running && job.phase == nil && job.progress > 0.15
    }

    let a = q.enqueue(project: o.doc.project, urls: o.doc.mediaURLs(), settings: made, to: destination)
    let aEnded = wait(a)
    let aBytes = bytes(destination)

    let b = q.enqueue(project: o.doc.project, urls: o.doc.mediaURLs(), settings: made, to: destination)
    var cancelledWhileWriting = false
    var aSupersededDuringB = false
    let bEnded = wait(b) { job in
        if writing(job), !cancelledWhileWriting {
            aSupersededDuringB = row(a)?.superseded ?? true
            q.cancel(b)
            cancelledWhileWriting = true
        }
    }
    spin(0.5)
    say("Q1", ["a": aEnded, "b": bEnded, "b_cancelled_while_writing": cancelledWhileWriting,
               "a_superseded_during_b": aSupersededDuringB,
               "a_superseded_after_b": row(a)?.superseded ?? true,
               "a_message": row(a)?.message ?? "", "same": aBytes != nil && bytes(destination) == aBytes,
               "listing": listing(place)])

    let c = q.enqueue(project: o.doc.project, urls: o.doc.mediaURLs(), settings: made, to: destination)
    var supersededWhileCWrote: [Bool] = []
    let cEnded = wait(c) { job in
        if writing(job) { supersededWhileCWrote.append(row(a)?.superseded ?? true) }
    }
    say("Q2", ["c": cEnded, "a_superseded_while_c_wrote": Array(Set(supersededWhileCWrote)),
               "samples": supersededWhileCWrote.count,
               "a_superseded_after_c": row(a)?.superseded ?? false,
               "c_message": row(c)?.message ?? "", "listing": listing(place)])
}

// MARK: - A1: an assistant call that raises

func submitRow(_ o: Open) {
    var answer: String?
    AgentLane.shared.submit(
        tool: "get_project", argumentsJSON: #"{"project":"FRAMEJOB_RAISE_525"}"#, document: o.doc,
        askFirst: { _, reply in reply(true) },
        completion: { result in DispatchQueue.main.async { answer = result } })
    let start = Date()
    while answer == nil, Date().timeIntervalSince(start) < 120 { spin(0.05) }
    // Handed back raw: parsing it here would go through the wrapped JSON reader, and an answer
    // that echoed the token would raise in the probe itself. The proof parses it.
    say("A1", ["answered": answer != nil, "raw": answer ?? "", "alive": true])
}

let o = open(package)
switch mode {
case "sheet": sheetRow(o)
case "queue": queueRows(o)
case "submit": submitRow(o)
default: say("abort", ["mode": mode])
}
exit(0)
