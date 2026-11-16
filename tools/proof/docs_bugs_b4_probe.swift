// Docs bugs, batch b4's probe (#477 #492 #500 #508 #509): the real app/Sources code on real
// `.framejob` packages the app under test saved, compiled AS main.swift over every file of
// app/Sources but the app's main.swift, through tools/proof/swift_build.py
// (`docs_bugs_b4_proof.py` builds it, and runs the same source on the base and the fix).
//
//   docs-bugs-b4-probe <mode> <package> <scratch folder> [preset] [-RCDevRampRenderHold <s>]
//
// sheet    P1–P4, H1: a real ExportSheetController, its view loaded and never shown. A preset
//          "Master" is put in the controller's in-memory list (never written) and selected with
//          `rebuildPresetPopup`, then one popup is moved and its own action sent. H1 reads the
//          sheet's hint.
// stop     S1: a real ExportProgressSheetController exporting <preset>; once it reads "Writing"
//          past 3 %, Cancel gets `performClick`, and the status line is sampled every 10 ms until
//          the button is live again.
// queue    R1, R2: one job through the real ExportQueueController.shared.enqueue, sampled
//          straight after it returns and every 20 ms: its state, `ExportQueueRowView.status` and
//          whether the destination or the hidden `.framejob-export-*` sibling an export writes
//          until it lands (spec §11 #531) exists.
// quit     T1 (and T2 when it survives): an H.264 sheet past 40 % "Writing", then the real
//          AppDelegate's applicationShouldTerminate; on .terminateNow the probe exits as
//          NSApplication.terminate would. Otherwise it waits for the finish and asks again.
// quitdone T2: the same sheet, asked once it has finished.
//
// Every mode ends with PB, the general pasteboard's change count against its start. Nothing
// reaches the screen or takes focus: activation policy .prohibited, a window 20,000 pt off every
// display that never becomes key. The probe names only symbols the base tree has, and finds the
// progress sheet's labels and button by a view walk.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
DecoderSupport.enable()

let mode = CommandLine.arguments[1]
let package = URL(fileURLWithPath: CommandLine.arguments[2])
let scratch = URL(fileURLWithPath: CommandLine.arguments[3])
let presetArg = CommandLine.arguments.count > 4 && !CommandLine.arguments[4].hasPrefix("-")
    ? CommandLine.arguments[4] : nil
let clock = Date()
let pasteboardAtStart = NSPasteboard.general.changeCount

func say(_ row: String, _ fields: [String: Any]) {
    var line = fields
    line["row"] = row
    line["t"] = (Date().timeIntervalSince(clock) * 1000).rounded() / 1000
    let data = try! JSONSerialization.data(
        withJSONObject: line, options: [.sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

/// Each moment the general pasteboard's change count moved, read every 0.25 s (read only), so a
/// change can be set beside what the probe was doing then.
var pasteboardChanges: [[Double]] = []
var pasteboardLast = pasteboardAtStart
let pasteboardWatch = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
    let now = NSPasteboard.general.changeCount
    guard now != pasteboardLast else { return }
    pasteboardLast = now
    pasteboardChanges.append([(Date().timeIntervalSince(clock) * 1000).rounded() / 1000, Double(now)])
}

func pasteboardRow() {
    say("PB", ["unchanged": NSPasteboard.general.changeCount == pasteboardAtStart, "mode": mode,
               "changes": pasteboardChanges])
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

// MARK: - P1–P4 (#492) and H1 (#509)

func sheetRows(_ o: Open) {
    let sheet = ExportSheetController(editor: o.controller)
    _ = sheet.view
    func arm() {
        var choice = sheet.currentChoice
        choice.name = "Master"
        sheet.userPresets = sheet.userPresets.saving(choice)
        sheet.rebuildPresetPopup(selecting: "Master")
    }
    let cases: [(String, String, String, NSPopUpButton)] = [
        ("P1", "av1", "Speed", sheet.speedPopup),
        ("P2", "audio_wav", "Bit depth", sheet.audioBitsPopup),
        ("P3", "audio_wav", "Stems", sheet.stemsPopup),
        ("P4", "av1", "Quality", sheet.qualityPopup),
        ("P4", "audio_wav", "Loudness", sheet.loudnessPopup),
    ]
    for (row, format, name, popup) in cases {
        sheet.apply(ExportChoice(presetID: format))
        sheet.resolveCard()
        arm()
        let armed = sheet.presetPopup.titleOfSelectedItem ?? ""
        let from = popup.titleOfSelectedItem ?? ""
        let target = popup.indexOfSelectedItem == popup.numberOfItems - 1 ? 0 : popup.numberOfItems - 1
        popup.selectItem(at: target)
        _ = popup.sendAction(popup.action, to: popup.target)
        say(row, ["format": format, "moved": name, "armed": armed, "from": from,
                  "to": popup.titleOfSelectedItem ?? "", "enabled": popup.isEnabled,
                  "preset_popup": sheet.presetPopup.titleOfSelectedItem ?? ""])
    }
    let texts = allViews(sheet.view).compactMap { ($0 as? NSTextField)?.stringValue }
    let hint = texts.first { $0.contains("master limiter") } ?? ""
    let at = hint.range(of: "master limiter").map { hint[$0.lowerBound...].prefix(80) } ?? ""
    say("H1", ["found": !hint.isEmpty, "text": String(at)])
}

// MARK: - S1 (#508), T1 and T2 (#477): a progress sheet's export

final class Sheet {
    let controller: ExportProgressSheetController
    let destination: URL
    var status: NSTextField!
    var percent: NSTextField!
    var button: NSButton!

    init(_ o: Open, preset: String, name: String) {
        let settings = try! ReelExport.settings(o.doc.project, preset: preset, overrides: nil)
        destination = scratch.appendingPathComponent("\(name).\(settings.container)")
        try? FileManager.default.removeItem(at: destination)
        controller = ExportProgressSheetController(
            project: o.doc.project, urls: o.doc.mediaURLs(), settings: settings, to: destination)
        let views = allViews(controller.view)
        let fields = views.compactMap { $0 as? NSTextField }
        status = fields.first { $0.stringValue.hasPrefix("Preparing") }
        percent = fields.first { $0.stringValue.hasSuffix(" %") }
        button = views.compactMap { $0 as? NSButton }.first { $0.title == "Cancel" }
        guard status != nil, percent != nil, button != nil else {
            say("abort", ["sheet": "labels or button not found"])
            exit(2)
        }
        // Presented as beginExport presents it, on the off-screen window, so its dismiss has a
        // presenter; viewDidAppear (guarded by didStart) starts the export.
        o.controller.presentAsSheet(controller)
        spin(0.2)
        controller.viewDidAppear()
    }

    var reading: [String: Any] {
        ["status": status.stringValue, "percent": percent.stringValue, "button": button.title,
         "enabled": button.isEnabled]
    }

    var percentValue: Double {
        Double(percent.stringValue.replacingOccurrences(of: " %", with: "")) ?? 0
    }

    func waitWriting(above floor: Double, limit: Double) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < limit {
            if status.stringValue.hasPrefix("Writing"), percentValue >= floor { return true }
            spin(0.01)
        }
        return false
    }

    func waitFinished(limit: Double) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < limit {
            if button.title == "Close", button.isEnabled { return true }
            spin(0.05)
        }
        return false
    }
}

func stopRow(_ o: Open) {
    let preset = presetArg ?? "av1"
    let s = Sheet(o, preset: preset, name: "stop-\(preset)")
    guard s.waitWriting(above: 3, limit: 900) else {
        say("S1", ["preset": preset, "error": "never wrote past 3 %", "reading": s.reading])
        return
    }
    let before = s.reading
    s.button.performClick(nil)
    var samples = 0
    var others: [String: Int] = [:]
    let start = Date()
    while Date().timeIntervalSince(start) < 300 {
        samples += 1
        let status = s.status.stringValue
        if status != "Stopping…" { others[status, default: 0] += 1 }
        if s.button.isEnabled { break }
        spin(0.01)
    }
    say("S1", ["preset": preset, "before": before, "samples": samples, "others": others,
               "stopped": s.button.isEnabled, "after": s.reading,
               "stopping_ms": (Date().timeIntervalSince(start) * 1000).rounded()])
}

func reply(_ answer: NSApplication.TerminateReply) -> String {
    [.terminateCancel: "terminateCancel", .terminateNow: "terminateNow",
     .terminateLater: "terminateLater"][answer] ?? "\(answer.rawValue)"
}

func quitRows(_ o: Open, done: Bool) {
    let s = Sheet(o, preset: "h264", name: done ? "quitdone" : "quit")
    if done {
        guard s.waitFinished(limit: 900) else {
            say("T2", ["error": "the export never finished", "reading": s.reading])
            return
        }
    } else {
        guard s.waitWriting(above: 40, limit: 900) else {
            say("T1", ["error": "never wrote past 40 %", "reading": s.reading])
            return
        }
    }
    let frameBefore = o.window.frame
    let activeBefore = NSApp.isActive
    let answer = AppDelegate().applicationShouldTerminate(NSApp)
    let fields: [String: Any] = [
        "reply": reply(answer), "reading": s.reading, "destination": s.destination.path,
        "frame_same": o.window.frame == frameBefore, "active_same": NSApp.isActive == activeBefore,
        "hidden": NSApp.isHidden, "miniaturized": o.window.isMiniaturized,
        "queue_idle": ExportQueueController.shared.isIdle,
    ]
    if done {
        say("T2", fields)
        return
    }
    var first = fields
    first["exited"] = answer == .terminateNow
    say("T1", first)
    if answer == .terminateNow {
        pasteboardRow()
        exit(0)
    }
    let finished = s.waitFinished(limit: 900)
    say("T1-finish", ["finished": finished, "reading": s.reading])
    let again = AppDelegate().applicationShouldTerminate(NSApp)
    say("T2", ["reply": reply(again), "reading": s.reading, "destination": s.destination.path])
}

// MARK: - R1, R2 (#500)

func queueRows(_ o: Open) {
    // The document published its reverse resolution while it was read, before the probe gave it
    // its file URL; publish again, as it does after every edit, so the ramp's cache folder is named.
    o.doc.publishReverseResolution()
    let settings = try! ReelExport.settings(o.doc.project, preset: "h264", overrides: nil)
    let destination = scratch.appendingPathComponent("queued.mp4")
    try? FileManager.default.removeItem(at: destination)
    let q = ExportQueueController.shared
    let id = q.enqueue(
        project: o.doc.project, urls: o.doc.mediaURLs(), settings: settings, to: destination)
    var samples: [[String: Any]] = []
    var last = ""
    var final = "gone"
    let start = Date()
    while Date().timeIntervalSince(start) < 600 {
        guard let job = q.jobs.first(where: { $0.id == id }) else { break }
        let row = ExportQueueRowView.status(job)
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []
        let onDisk = FileManager.default.fileExists(atPath: destination.path)
            || siblings.contains { $0.hasPrefix(".framejob-export-") }
        let word = row.components(separatedBy: " · ").first ?? row
        let key = "\(job.state)|\(word)|\(onDisk)"
        if key != last {
            last = key
            samples.append(["state": "\(job.state)", "row_status": row, "file_on_disk": onDisk,
                            "t": (Date().timeIntervalSince(start) * 1000).rounded() / 1000])
        }
        final = "\(job.state)"
        if job.state.isFinished { break }
        spin(0.02)
    }
    say("R", ["samples": samples, "final": final])
}

let o = open(package)
switch mode {
case "sheet": sheetRows(o)
case "stop": stopRow(o)
case "queue": queueRows(o)
case "quit": quitRows(o, done: false)
case "quitdone": quitRows(o, done: true)
default: say("abort", ["mode": mode])
}
pasteboardRow()
exit(0)
