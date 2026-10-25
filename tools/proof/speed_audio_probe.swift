// Issue batch B62 (#212) — a speed change that takes a clip with sound above
// the core's audio ceiling asks first, at every UI door that can set a speed
// (the Speed sheet, the inspector's Speed section, the timeline's rate
// stretch), and an agent's answer names the clips instead. Driven through the
// app's own `EditorViewController`, `SpeedSheetController`, `ProjectDocument`
// and `AgentServer`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` — the swiftc
// line `sheet_queue_probe.py` uses. One process:
//
//   speed_audio_probe <request.json>
//
// The request names `work` (this run's directory). The answer is one JSON
// object on stdout, `{"rows": [...]}`, each row `{"id", "pass", "detail",
// "instrument"}`; `speed_audio_probe.py` prints and scores them. Every wait
// pumps `RunLoop.main` and is bounded.
//
// The fixture, fresh per row: an untitled `ProjectDocument` whose one track
// holds A ("Alpha", 60 s, sound, at 0), B ("Bravo", 90 s, sound, at 60 s),
// N ("November", 60 s, no sound, at 150 s), M ("Mike", sound but its audio
// turned off, at 210 s) and H ("Hotel", sound, already ×20, at 270 s), every
// clip at ×1 but H. The media files are written under `work`, so no Relink
// sheet is offered. Its `EditorViewController` is the content of a 1440×900
// window owned by the document's window controller, and the document is the
// one `NSDocumentController` holds, so `AgentServer.shared.execute` edits it.
//
// No line here spells the ceiling: rates above it are literals like 20 or
// read from the core's trial answer, and every expected sentence is built
// from the batch's literal templates around `ReelSpeed.limits.audioMax`,
// never from `SpeedAudioDrop`.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2,
    let requestData = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let workPath = request["work"] as? String
else {
    FileHandle.standardError.write(Data("usage: speed_audio_probe <request.json>\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: workPath, isDirectory: true)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
// As the app's `main.swift` does: the gate learns each tool's arguments here.
AgentLane.prepareAtLaunch()
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String, instrument: Bool = false) {
    rows.append(["id": id, "pass": pass && !instrument, "detail": String(detail.prefix(1500)),
                 "instrument": instrument])
}
var documents: [ProjectDocument] = []
func finish() -> Never {
    for document in documents { document.removeTemporaryCacheDirectory() }
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

/// Pumps until `condition` holds or `limit` seconds pass; the seconds it
/// took, or nil.
func waitUntil(_ limit: Double, _ condition: () -> Bool) -> Double? {
    let start = Date()
    while Date().timeIntervalSince(start) < limit {
        if condition() { return Date().timeIntervalSince(start) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition() ? Date().timeIntervalSince(start) : nil
}

func pause(_ limit: Double) { _ = waitUntil(limit) { false } }

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func views(_ sheet: NSWindow) -> [NSView] { sheet.contentView.map(walk) ?? [] }

/// Every text field's string in a sheet's view tree.
func texts(_ sheet: NSWindow) -> [String] {
    views(sheet).compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
}

func buttons(_ sheet: NSWindow) -> [String] {
    views(sheet).compactMap { ($0 as? NSButton)?.title }.filter { !$0.isEmpty }
}

// MARK: - The copy, from the batch's literal templates

let limits = ReelSpeed.limits
func rateText(_ value: Double) -> String { "×" + String(format: "%g", value) }
let ceilingText = rateText(limits.audioMax)
func oneMessage(_ name: String, _ speed: String) -> String {
    "“\(name)” will be silent at \(speed)."
}
let oneDetail = "Frame Job leaves a clip’s audio out above \(ceilingText). The picture still plays."
func manyMessage(_ count: Int, _ speed: String?) -> String {
    speed.map { "\(count) clips will be silent at \($0)." }
        ?? "\(count) clips will be silent at their new speeds."
}
let manyDetail =
    "Frame Job leaves a clip’s audio out above \(ceilingText). The pictures still play."
func agentNote(_ id: UInt32, _ name: String) -> String {
    "Clip \(id) (“\(name)”) now plays above \(ceilingText), so its audio is left out: it is "
        + "silent in the preview and the export."
}

// MARK: - The fixture

let second: Ticks = 600_000
var doc: ProjectDocument!
var controller: EditorViewController!
var window: NSWindow!
var windowControllers: [NSWindowController] = []
var a: UInt32 = 0, b: UInt32 = 0, n: UInt32 = 0, m: UInt32 = 0, h: UInt32 = 0

func mediaFile(_ name: String) -> String {
    let url = work.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: url.path) {
        try? Data("speed audio probe".utf8).write(to: url)
    }
    return url.path
}

/// A fresh fixture; nil, or why it could not be built.
func fresh() -> String? {
    window?.orderOut(nil)
    if let old = doc { NSDocumentController.shared.removeDocument(old) }
    doc = ProjectDocument()
    documents.append(doc)
    guard let track = doc.project.snapshot.tracks.first?.id else { return "no track" }
    func media(_ file: String, _ seconds: Ticks, sound: Bool) -> UInt32? {
        let path = mediaFile(file)
        doc.performGroupedEdit("Media", [.addMedia(descriptor: MediaDescriptor(
            path: path, kind: .video, duration: seconds * second, width: 1920, height: 1080,
            fps: .thirty, hasVideo: true, hasAudio: sound))])
        return doc.project.snapshot.media.first { $0.path == path }?.id
    }
    guard let sixty = media("sixty.mov", 60, sound: true),
        let ninety = media("ninety.mov", 90, sound: true),
        let mute = media("silent.mov", 60, sound: false)
    else { return "add_media added nothing" }
    let placed: [(UInt32, Ticks, String)] = [
        (sixty, 0, "Alpha"), (ninety, 60, "Bravo"), (mute, 150, "November"),
        (sixty, 210, "Mike"), (sixty, 270, "Hotel"),
    ]
    var ids: [UInt32] = []
    for (media, at, name) in placed {
        doc.performGroupedEdit("Clip", [.addClip(track: track, media: media, at: at * second)])
        guard let clip = doc.project.snapshot.clips.first(where: { $0.start == at * second })
        else { return "add_clip at \(at) s added nothing" }
        doc.performGroupedEdit("Name", [.setClip(clips: [clip.id], patch: ClipPatch(name: name))])
        ids.append(clip.id)
    }
    (a, b, n, m, h) = (ids[0], ids[1], ids[2], ids[3], ids[4])
    doc.performGroupedEdit("Mute", [.setEnabled(clip: m, audio: false)])
    doc.performGroupedEdit("Hotel", [.setSpeed(clip: h, rate: 20)])
    let snapshot = doc.project.snapshot
    guard snapshot.clip(m)?.enabled.audio == false, (snapshot.clip(h)?.speed ?? 0) > 1,
        snapshot.clip(a)?.speed == 1, snapshot.clip(b)?.speed == 1
    else { return "the fixture's set_enabled / set_speed did not take" }
    doc.undoManager?.removeAllActions()

    controller = EditorViewController(document: doc)
    window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentViewController = controller
    controller.viewWillAppear()
    controller.viewDidAppear()
    controller.refreshFromDocument(isLive: false)
    let windowController = NSWindowController(window: window)
    windowControllers.append(windowController)
    doc.addWindowController(windowController)
    NSDocumentController.shared.addDocument(doc)
    windowController.showWindow(nil)
    pause(0.3)
    return window.attachedSheet == nil ? nil : "a sheet was attached after set-up"
}

func speed(_ id: UInt32) -> Double { doc.project.snapshot.clip(id)?.speed ?? -1 }
var canUndo: Bool { doc.undoManager?.canUndo ?? false }
var undoName: String { doc.undoManager?.undoActionName ?? "" }

/// The new rate a clip plays at once `ops` run on the edited project — the
/// core's trial answer.
func trialSpeed(_ ops: [ReelOp], _ id: UInt32, on project: ReelProject? = nil) -> Double? {
    guard case .applied(let after)? = try? (project ?? doc.editedProject).applying(ops) else {
        return nil
    }
    return after.snapshot.clip(id)?.speed
}

/// A sheet attached to `host` within `limit` s that is not `besides`.
func question(on host: NSWindow, within limit: Double, besides: NSWindow? = nil) -> NSWindow? {
    var found: NSWindow?
    _ = waitUntil(limit) {
        if let sheet = host.attachedSheet, sheet !== besides { found = sheet }
        return found != nil
    }
    return found
}

/// No sheet attached, the window settled: up to 3 s, ending whatever stays.
func settle() {
    for _ in 0..<4 {
        if let inner = window.attachedSheet?.attachedSheet {
            window.attachedSheet?.endSheet(inner, returnCode: .alertSecondButtonReturn)
        }
        if waitUntil(1, { window.attachedSheet == nil }) != nil { break }
        if let stuck = window.attachedSheet { window.endSheet(stuck, returnCode: .cancel) }
    }
    pause(0.2)
}

/// The button Return presses: the window's default button cell, else a
/// button whose key equivalent is Return.
func defaultTitle(_ sheet: NSWindow) -> String? {
    if let cell = sheet.defaultButtonCell { return cell.title }
    let all = views(sheet).compactMap { $0 as? NSButton }
    return all.first { $0.keyEquivalent == "\r" }?.title
}

func describe(_ sheet: NSWindow) -> String {
    let keys = views(sheet).compactMap { $0 as? NSButton }.filter { !$0.title.isEmpty }
        .map { "\($0.title)=\($0.keyEquivalent.debugDescription)" }
    let defaults = [defaultTitle(sheet) ?? "none"] + keys
    let shown = texts(sheet).joined(separator: " | ")
    let titles = buttons(sheet).joined(separator: ", ")
    return "[\(shown)] buttons [\(titles)] default \(defaults.joined(separator: ", "))"
}

/// The question's text and buttons are the expected ones: "Set Speed" (the
/// default, Return) and "Cancel".
func reads(_ sheet: NSWindow, _ message: String, _ detail: String) -> Bool {
    let shown = texts(sheet)
    let all = views(sheet).compactMap { $0 as? NSButton }.filter { !$0.title.isEmpty }
    let titles = all.map(\.title).sorted()
    let text = shown.contains(message) && shown.contains(detail)
    let pair = titles == ["Cancel", "Set Speed"]
    return text && pair && defaultTitle(sheet) == "Set Speed"
}

// MARK: - The Speed sheet

/// Clip ▸ Speed… on `clips` (the editor's own `presentSpeedSheet`), with
/// `rate` typed into its field when given.
func speedSheet(_ clips: [UInt32], rate: Double?) -> (NSWindow, SpeedSheetController)? {
    doc.selection = Set(clips)
    controller.presentSpeedSheet()
    guard waitUntil(3, { window.attachedSheet != nil }) != nil,
        let sheet = window.attachedSheet,
        let speed = sheet.contentViewController as? SpeedSheetController
    else { return nil }
    if let rate {
        guard let field = views(sheet).compactMap({ $0 as? NSTextField })
            .first(where: { $0.delegate === speed })
        else { return nil }
        field.doubleValue = rate
        speed.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field))
    }
    return (sheet, speed)
}

/// The sheet's Apply button, clicked through its own target and action.
func apply(_ sheet: NSWindow) -> Bool {
    let click = NSSelectorFromString("applyClicked:")
    guard let button = views(sheet).compactMap({ $0 as? NSButton })
        .first(where: { $0.action == click })
    else { return false }
    return NSApp.sendAction(click, to: button.target, from: button)
}

/// S1 / S2 / S3's shape: the sheet on `clips` at `rate`, Apply, the question
/// on the sheet's window. nil and why when a step could not be performed.
func sheetQuestion(_ clips: [UInt32], rate: Double)
    -> (sheet: NSWindow, question: NSWindow?, why: String?)?
{
    guard let (sheet, _) = speedSheet(clips, rate: rate) else { return nil }
    guard apply(sheet) else { return (sheet, nil, "no Apply button") }
    return (sheet, question(on: sheet, within: 3), nil)
}

// MARK: - C0 — CONTROL

if let why = fresh() {
    row("C0", false, "instrument: fixture: \(why)", instrument: true)
} else {
    let mine = doc.windowForSheet === window
    let clear = window.attachedSheet == nil
    let ceiling = limits.audioMax.isFinite && limits.audioMax > 1 && limits.audioMax < limits.max
    row("C0", mine && clear && ceiling,
        "windowForSheet is the window: \(mine); no sheet attached: \(clear); the core's "
            + "audio_max \(limits.audioMax) (range \(limits.min)–\(limits.max))")
}
settle()

// MARK: - S1, S2 — the Speed sheet on [A] at ×20

for (id, confirm) in [("S1", true), ("S2", false)] {
    if let why = fresh() {
        row(id, false, "instrument: fixture: \(why)", instrument: true)
        continue
    }
    let before = doc.project
    guard let run = sheetQuestion([a], rate: 20) else {
        row(id, false, "instrument: the Speed sheet did not attach", instrument: true)
        settle()
        continue
    }
    if let why = run.why {
        row(id, false, "instrument: \(why)", instrument: true)
        settle()
        continue
    }
    guard let asked = run.question else {
        row(id, false, "no question attached to the Speed sheet within 3 s; A is now "
            + "\(rateText(speed(a))), the sheet attached: \(window.attachedSheet != nil)")
        settle()
        continue
    }
    let expected = oneMessage("Alpha", rateText(20))
    let text = reads(asked, expected, oneDetail)
    let shown = describe(asked)
    let untouched = doc.project === before
    run.sheet.endSheet(asked, returnCode: confirm ? .alertFirstButtonReturn : .alertSecondButtonReturn)
    if confirm {
        let closed = waitUntil(3) { window.attachedSheet == nil } != nil
        let pass = text && untouched && speed(a) == 20 && closed && canUndo
            && undoName == "Set Speed"
        row(id, pass,
            "question \(shown); expected [\(expected) | \(oneDetail)], Set Speed (default) "
                + "and Cancel: \(text); nothing applied while asked: \(untouched); after Set "
                + "Speed A "
                + "\(rateText(speed(a))), the sheet closed \(closed), canUndo \(canUndo), "
                + "undo name \"\(undoName)\"")
    } else {
        pause(0.5)
        let same = doc.project === before
        let still = window.attachedSheet === run.sheet
        row(id, text && same && !canUndo && still,
            "question \(shown): \(text); after Cancel the handle is the same: \(same), "
                + "canUndo \(canUndo), the Speed sheet still attached: \(still)")
    }
    settle()
}

// MARK: - S3 — the Speed sheet on [A, B, N] at ×20: one question, one step

if let why = fresh() {
    row("S3", false, "instrument: fixture: \(why)", instrument: true)
} else if let run = sheetQuestion([a, b, n], rate: 20), run.why == nil {
    if let asked = run.question {
        let expected = manyMessage(2, rateText(20))
        let text = reads(asked, expected, manyDetail)
        let shown = describe(asked)
        run.sheet.endSheet(asked, returnCode: .alertFirstButtonReturn)
        _ = waitUntil(3) { window.attachedSheet == nil }
        let applied = [a, b, n].map(speed)
        doc.undoManager?.undo()
        let undone = [a, b, n].map(speed)
        row("S3", text && applied == [20, 20, 20] && undone == [1, 1, 1],
            "question \(shown); expected [\(expected) | \(manyDetail)]: \(text); after Set "
                + "Speed A, B, N \(applied.map(rateText)); after one undo "
                + "\(undone.map(rateText))")
    } else {
        row("S3", false, "no question attached to the Speed sheet within 3 s; A, B, N are "
            + "\([a, b, n].map(speed).map(rateText))")
    }
} else {
    row("S3", false, "instrument: the Speed sheet or its Apply was not reached", instrument: true)
}
settle()

// MARK: - S5 — CONTROL: an unchanged Apply closes the sheet and asks nothing

/// True when a question attaches to `host`'s sheet, or a sheet other than
/// `besides` to `host`, within `limit` s.
func anyQuestion(_ limit: Double, besides: NSWindow?) -> Bool {
    waitUntil(limit) {
        if let sheet = window.attachedSheet {
            return sheet !== besides || sheet.attachedSheet != nil
        }
        return false
    } != nil
}

if let why = fresh() {
    row("S5", false, "instrument: fixture: \(why)", instrument: true)
} else if let (sheet, _) = speedSheet([a], rate: nil), apply(sheet) {
    let asked = anyQuestion(1, besides: sheet)
    let closed = waitUntil(3) { window.attachedSheet == nil } != nil
    row("S5", !asked && closed && !canUndo,
        "a question attached within 1 s: \(asked); the sheet closed: \(closed); canUndo "
            + "\(canUndo)")
} else {
    row("S5", false, "instrument: the Speed sheet or its Apply was not reached", instrument: true)
}
settle()

// MARK: - S4 — CONTROL: nothing that does not cross asks

if let why = fresh() {
    row("S4", false, "instrument: fixture: \(why)", instrument: true)
} else {
    var lines: [String] = []
    var pass = true
    let runs: [(String, UInt32, Double)] = [
        ("A at the ceiling", a, limits.audioMax), ("N (no sound)", n, 20),
        ("M (audio off)", m, 20), ("H (already above)", h, 30),
    ]
    for (label, id, rate) in runs {
        guard let (sheet, _) = speedSheet([id], rate: rate), apply(sheet) else {
            lines.append("\(label): the sheet or its Apply was not reached")
            pass = false
            settle()
            continue
        }
        let asked = anyQuestion(1, besides: sheet)
        let closed = waitUntil(3) { window.attachedSheet == nil } != nil
        let now = speed(id)
        let good = !asked && closed && abs(now - rate) < 1e-9
        pass = pass && good
        lines.append("\(label) → \(rateText(now)): asked \(asked), closed \(closed)")
        settle()
    }
    row("S4", pass, lines.joined(separator: "; "))
}
settle()

// MARK: - P1, P2 — the Speed Ramp sheet's Apply (`SpeedAudioDrop.commit`)

/// Clip ▸ Speed Ramp… on A over `span` (the call `presentSpeedRampSheet`
/// makes); nil when it did not attach.
func rampSheet(span: (from: Ticks, to: Ticks)?) -> (NSWindow, SpeedRampSheetController)? {
    controller.presentAsSheet(SpeedRampSheetController(document: doc, clip: a, span: span))
    guard waitUntil(3, { window.attachedSheet != nil }) != nil,
        let sheet = window.attachedSheet,
        let ramp = sheet.contentViewController as? SpeedRampSheetController
    else { return nil }
    return (sheet, ramp)
}

/// The sheet's Apply button, or nil.
func applyButton(_ sheet: NSWindow) -> NSButton? {
    let click = NSSelectorFromString("applyClicked:")
    return views(sheet).compactMap { $0 as? NSButton }.first { $0.action == click }
}

// P1: Ramp Up ×20 over A's last 0.2 s, A trimmed to 10 s so the ramp fits.
if let why = fresh() {
    row("P1", false, "instrument: fixture: \(why)", instrument: true)
} else {
    doc.performGroupedEdit("Trim", [.trimEnd(clip: a, to: 10 * second)])
    doc.undoManager?.removeAllActions()
    let trimmed = doc.project.snapshot.clip(a)?.duration == 10 * second
    let span: (from: Ticks, to: Ticks) = (98 * second / 10, 10 * second)
    if !trimmed {
        row("P1", false, "instrument: A was not trimmed to 10 s", instrument: true)
    } else if let (sheet, ramp) = rampSheet(span: span) {
        let popups = views(sheet).compactMap { $0 as? NSPopUpButton }
        let shapePopup = popups.first { popup in
            popup.itemArray.contains { $0.representedObject as? String == "ramp_up" }
        }
        let item = shapePopup?.itemArray.first { $0.representedObject as? String == "ramp_up" }
        let field = views(sheet).compactMap { $0 as? NSTextField }
            .first { $0.delegate === ramp }
        if let shapePopup, let item, let action = shapePopup.action, let field {
            shapePopup.select(item)
            _ = NSApp.sendAction(action, to: shapePopup.target, from: shapePopup)
            field.doubleValue = 20
            ramp.controlTextDidEndEditing(
                Notification(name: NSControl.textDidEndEditingNotification, object: field))
            let before = doc.project
            if let button = applyButton(sheet), button.isEnabled {
                _ = NSApp.sendAction(
                    NSSelectorFromString("applyClicked:"), to: button.target, from: button)
                if let asked = question(on: sheet, within: 3) {
                    let expected = oneMessage("Alpha", rateText(20))
                    let text = reads(asked, expected, oneDetail)
                    let shown = describe(asked)
                    let untouched = doc.project === before
                    sheet.endSheet(asked, returnCode: .alertFirstButtonReturn)
                    let closed = waitUntil(3) { window.attachedSheet == nil } != nil
                    let step = canUndo && undoName == "Ramp Up"
                    let named = undoName
                    doc.undoManager?.undo()
                    let one = doc.project.snapshot.clip(a)?.actions.isEmpty == true && !canUndo
                    row("P1", text && untouched && closed && step && one,
                        "question \(shown); expected [\(expected) | \(oneDetail)] on the Ramp "
                            + "sheet: \(text); nothing applied while asked: \(untouched); after "
                            + "Set Speed the sheet closed \(closed), a step named \"\(named)\" "
                            + "(expected Ramp Up) \(step); one undo removes the ramp and "
                            + "empties the stack: \(one)")
                } else {
                    row("P1", false, "no question attached to the Ramp sheet within 3 s; the "
                        + "handle is the same: \(doc.project === before), the sheet attached: "
                        + "\(window.attachedSheet != nil), canUndo \(canUndo)")
                }
            } else {
                row("P1", false, "instrument: Apply is disabled or missing; the readout "
                    + "[\(texts(sheet).joined(separator: " | "))]", instrument: true)
            }
        } else {
            row("P1", false, "instrument: no shape popup with ramp_up, or no rate field",
                instrument: true)
        }
    } else {
        row("P1", false, "instrument: the Ramp sheet did not attach", instrument: true)
    }
}
settle()

// P2: CONTROL — the opening Speed Dip ×0.5 over the whole clip asks nothing.
if let why = fresh() {
    row("P2", false, "instrument: fixture: \(why)", instrument: true)
} else if let (sheet, _) = rampSheet(span: nil) {
    if let button = applyButton(sheet), button.isEnabled {
        _ = NSApp.sendAction(
            NSSelectorFromString("applyClicked:"), to: button.target, from: button)
        let asked = anyQuestion(1, besides: sheet)
        let closed = waitUntil(3) { window.attachedSheet == nil } != nil
        let step = canUndo && undoName == "Speed Dip"
        let named = undoName
        doc.undoManager?.undo()
        let one = !canUndo
        row("P2", !asked && closed && step && one,
            "a question attached within 1 s: \(asked); the sheet closed: \(closed); a step "
                + "named \"\(named)\" (expected Speed Dip) \(step); one undo empties the "
                + "stack: \(one)")
    } else {
        row("P2", false, "instrument: Apply is disabled or missing; the readout "
            + "[\(texts(sheet).joined(separator: " | "))]", instrument: true)
    }
} else {
    row("P2", false, "instrument: the Ramp sheet did not attach", instrument: true)
}
settle()

// MARK: - I1, I2 — the inspector's Speed section (`inspector.onEdit`)

for (id, confirm) in [("I1", true), ("I2", false)] {
    if let why = fresh() {
        row(id, false, "instrument: fixture: \(why)", instrument: true)
        continue
    }
    guard let inspector = controller.inspector, let onEdit = inspector.onEdit else {
        row(id, false, "instrument: no inspector or no onEdit", instrument: true)
        continue
    }
    let before = doc.project
    onEdit("Set Speed", [.setSpeed(clip: a, rate: 20)])
    guard let asked = question(on: window, within: 3) else {
        row(id, false, "no question attached to the editor window within 3 s; A is now "
            + "\(rateText(speed(a))), canUndo \(canUndo)")
        settle()
        continue
    }
    let expected = oneMessage("Alpha", rateText(20))
    let text = reads(asked, expected, oneDetail)
    let shown = describe(asked)
    let untouched = doc.project === before
    window.endSheet(asked, returnCode: confirm ? .alertFirstButtonReturn : .alertSecondButtonReturn)
    pause(0.3)
    if confirm {
        let applied = speed(a)
        let step = canUndo && undoName == "Set Speed"
        doc.undoManager?.undo()
        let one = speed(a) == 1 && !canUndo
        row(id, text && untouched && applied == 20 && step && one,
            "question \(shown); expected [\(expected) | \(oneDetail)]: \(text); nothing "
                + "applied while asked: \(untouched); after Set Speed A \(rateText(applied)), "
                + "a step named Set Speed \(step); one undo puts it back and empties the "
                + "stack: \(one)")
    } else {
        let same = doc.project === before
        row(id, text && same && !canUndo,
            "question \(shown): \(text); after Cancel the handle is the same: \(same), "
                + "canUndo \(canUndo)")
    }
    settle()
}

// MARK: - I3, I5 — Fit to, on [A] and on [A, B] (two different new rates)

let fitLength = 3 * second
for (id, count) in [("I3", 1), ("I5", 2)] {
    if let why = fresh() {
        row(id, false, "instrument: fixture: \(why)", instrument: true)
        continue
    }
    let ids = Array([a, b].prefix(count))
    let ops = VideoPane.fitOps(ids, duration: fitLength)
    let rates = ids.map { trialSpeed(ops, $0) ?? -1 }
    guard rates.allSatisfy({ $0 > limits.audioMax }),
        let onEdit = controller.inspector?.onEdit
    else {
        row(id, false, "instrument: the trial's rates \(rates.map(rateText)) are not all above "
            + "the ceiling, or there is no onEdit", instrument: true)
        continue
    }
    let expected: String
    let detail: String
    if ids.count == 1 {
        expected = oneMessage("Alpha", rateText(rates[0]))
        detail = oneDetail
    } else {
        let distinct = Set(rates.map(rateText))
        expected = manyMessage(ids.count, distinct.count == 1 ? distinct.first : nil)
        detail = manyDetail
    }
    onEdit("Fit to Duration", ops)
    guard let asked = question(on: window, within: 3) else {
        row(id, false, "no question attached to the editor window within 3 s; now "
            + "\(ids.map(speed).map(rateText))")
        settle()
        continue
    }
    let text = reads(asked, expected, detail)
    let shown = describe(asked)
    window.endSheet(asked, returnCode: .alertFirstButtonReturn)
    pause(0.3)
    let now = ids.map(speed)
    let applied = now.allSatisfy { $0 > limits.audioMax }
    row(id, text && applied && canUndo,
        "trial rates \(rates.map(rateText)); question \(shown); expected [\(expected) | "
            + "\(detail)]: \(text); after Set Speed \(now.map(rateText)), canUndo \(canUndo)")
    settle()
}

// MARK: - I4 — CONTROL: a volume edit never asks

if let why = fresh() {
    row("I4", false, "instrument: fixture: \(why)", instrument: true)
} else if let onEdit = controller.inspector?.onEdit {
    let before = doc.project
    onEdit("Volume", [.setAudio(clips: [a], patch: AudioPatch(volume: 0.5))])
    let asked = anyQuestion(1, besides: nil)
    let volume = doc.project.snapshot.clip(a)?.audioProps.volume
    row("I4", !asked && doc.project !== before && volume == 0.5,
        "a question attached within 1 s: \(asked); the volume is now "
            + "\(volume.map { String($0) } ?? "nil")")
} else {
    row("I4", false, "instrument: no inspector or no onEdit", instrument: true)
}
settle()

// MARK: - R1, R2 — the timeline's ⌥-drag rate stretch

for (id, confirm) in [("R1", true), ("R2", false)] {
    if let why = fresh() {
        row(id, false, "instrument: fixture: \(why)", instrument: true)
        continue
    }
    guard let timeline = controller.timeline, let begin = timeline.onLiveBegin,
        let update = timeline.onLiveUpdate, let end = timeline.onLiveEnd,
        let length = doc.project.snapshot.clip(a)?.duration
    else {
        row(id, false, "instrument: no timeline or no live closures", instrument: true)
        continue
    }
    let base = doc.project
    let ops: [ReelOp] = [.rateStretch(clip: a, toEnd: length / 20)]
    guard let stretched = trialSpeed(ops, a, on: base), stretched > limits.audioMax else {
        row(id, false, "instrument: the trial stretch is not above the ceiling", instrument: true)
        continue
    }
    begin()
    update(ops)
    let ticked = doc.project !== base && doc.isLiveEditing
    end("Rate Stretch")
    guard let asked = question(on: window, within: 3) else {
        row(id, false, "no question attached to the editor window within 3 s; the tick "
            + "applied \(ticked); A is now \(rateText(speed(a))), live \(doc.isLiveEditing)")
        settle()
        continue
    }
    let expected = oneMessage("Alpha", rateText(stretched))
    let text = reads(asked, expected, oneDetail)
    let shown = describe(asked)
    let notLive = !doc.isLiveEditing
    let baseUp = doc.project === base
    window.endSheet(asked, returnCode: confirm ? .alertFirstButtonReturn : .alertSecondButtonReturn)
    pause(0.3)
    if confirm {
        let now = speed(a)
        let pass = ticked && text && notLive && baseUp && now > limits.audioMax && canUndo
            && undoName == "Rate Stretch"
        row(id, pass,
            "the tick applied \(ticked); question \(shown); expected [\(expected) | "
                + "\(oneDetail)]: \(text); while asked: not live \(notLive), the base handle "
                + "\(baseUp); after Set Speed A \(rateText(now)), canUndo \(canUndo), undo "
                + "name \"\(undoName)\"")
    } else {
        let same = doc.project === base
        row(id, ticked && text && notLive && baseUp && same && !doc.isLiveEditing && !canUndo,
            "the tick applied \(ticked); question \(shown): \(text); while asked: not live "
                + "\(notLive), the base handle \(baseUp); after Cancel the base \(same), live "
                + "\(doc.isLiveEditing), canUndo \(canUndo)")
    }
    settle()
}

// MARK: - R3 — CONTROL: a trim's live end never asks

if let why = fresh() {
    row("R3", false, "instrument: fixture: \(why)", instrument: true)
} else if let timeline = controller.timeline, let begin = timeline.onLiveBegin,
    let update = timeline.onLiveUpdate, let end = timeline.onLiveEnd
{
    begin()
    update([.trimEnd(clip: a, to: 30 * second)])
    end("Trim Clip")
    let asked = anyQuestion(1, besides: nil)
    let duration = doc.project.snapshot.clip(a)?.duration
    row("R3", !asked && duration == 30 * second && canUndo && !doc.isLiveEditing,
        "a question attached within 1 s: \(asked); A's duration \(duration.map { String($0) } ?? "nil") "
            + "(expected \(30 * second)); canUndo \(canUndo); live \(doc.isLiveEditing)")
} else {
    row("R3", false, "instrument: no timeline or no live closures", instrument: true)
}
settle()

// MARK: - A1–A3 — MCP: no dialog, the answer names the clips

/// The tool's answer object, or nil and the raw text.
func call(_ tool: String, _ args: [String: Any]) -> ([String: Any]?, String) {
    let json = (try? JSONSerialization.data(withJSONObject: args))
        .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    let raw = AgentServer.shared.execute(tool: tool, argumentsJSON: json)
    guard let envelope = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
        (envelope["isError"] as? Bool) != true,
        let content = envelope["content"] as? [[String: Any]],
        let text = content.first?["text"] as? String,
        let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    else { return (nil, String(raw.prefix(400))) }
    return (object, text)
}

func leftOut(_ answer: [String: Any]?) -> [Int]? { answer?["audio_left_out"] as? [Int] }

if let why = fresh() {
    row("A1", false, "instrument: fixture: \(why)", instrument: true)
} else {
    let (answer, raw) = call("set_speed", ["clip": Int(a), "rate": 20])
    let asked = anyQuestion(1, besides: nil)
    let expected = agentNote(a, "Alpha")
    let note = answer?["audio_note"] as? String
    row("A1", answer != nil && leftOut(answer) == [Int(a)] && note == expected && !asked
            && speed(a) == 20,
        "answer \(raw.prefix(600)); expected audio_left_out [\(a)] and audio_note "
            + "\"\(expected)\"; a sheet attached within 1 s: \(asked)")
}
settle()

if let why = fresh() {
    row("A2", false, "instrument: fixture: \(why)", instrument: true)
} else {
    let (answer, raw) = call("set_speed", ["clip": Int(n), "rate": 20])
    let keys = answer.map { $0.keys.filter { $0.hasPrefix("audio_") } } ?? []
    row("A2", answer != nil && keys.isEmpty && speed(n) == 20,
        "answer \(raw.prefix(400)); audio_ keys \(keys)")
}
settle()

if let why = fresh() {
    row("A3", false, "instrument: fixture: \(why)", instrument: true)
} else if let clip = doc.project.snapshot.clip(b) {
    let toEnd = clip.start + clip.duration / 20
    let (answer, raw) = call("rate_stretch", ["clip": Int(b), "to_end": Int(toEnd)])
    let note = answer?["audio_note"] as? String
    row("A3", answer != nil && leftOut(answer) == [Int(b)] && note == agentNote(b, "Bravo")
            && speed(b) > limits.audioMax,
        "answer \(raw.prefix(600)); B now \(rateText(speed(b)))")
} else {
    row("A3", false, "instrument: no clip B", instrument: true)
}
settle()

finish()
