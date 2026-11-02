// Road map "creator-jobs" CU9a (spec §11 CU-90 (c), (d)) — Clip ▸ Retime
// Range…'s door, driven through the app's own `EditorViewController`,
// `RetimeSheetController`, `SpeedAudioDrop` and `ProjectDocument`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, through `swift_build.py`'s one line. One process:
//
//   retime_probe <request.json>
//
// The request names `work` (this run's directory). The answer is one JSON
// object on stdout, `{"rows": [...]}`, each row `{"id", "pass", "detail",
// "instrument"}`; `retime_proof.py` prints and scores them. Every wait pumps
// `RunLoop.main` and is bounded.
//
// Rows:
//   R8a  the sheet over [5 s, 10 s), inside A (60 s of sound at ×4), at ×4:
//        the question ("“Alpha” will be silent at ×16.") is on the SHEET's
//        window and nothing is applied; Cancel leaves the same handle, the
//        sheet up and no step; Apply again and Set Speed makes one step,
//        "Retime Range", the sheet closed.
//   R8b  CONTROL: ×2 over a ×1 clip asks nothing within 1 s and makes one step
//        "Retime Range".
//   R9p  the sheet over a Keep-pitch-off clip (first) and a Keep-pitch-on clip:
//        Preserve pitch opens off, and Apply at ×2 gives exactly the project
//        `retime_range {rate: 2, keep_pitch: false}` gives on the handle
//        before (byte-equal JSON).
//
// Every expected sentence is built from the batch's literal template, never
// from `SpeedAudioDrop`.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2,
    let requestData = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let workPath = request["work"] as? String
else {
    FileHandle.standardError.write(Data("usage: retime_probe <request.json>\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: workPath, isDirectory: true)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
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
func texts(_ sheet: NSWindow) -> [String] {
    views(sheet).compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
}

let ceiling = "×" + String(format: "%g", ReelSpeed.limits.audioMax)
func oneMessage(_ name: String, _ speed: String) -> String {
    "“\(name)” will be silent at \(speed)."
}

// MARK: - The fixture

let second: Ticks = 600_000
let range = (from: 5 * second, to: 10 * second)
var doc: ProjectDocument!
var controller: EditorViewController!
var window: NSWindow!
var windowControllers: [NSWindowController] = []

func mediaFile(_ name: String) -> String {
    let url = work.appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: url.path) {
        try? Data("retime probe".utf8).write(to: url)
    }
    return url.path
}

/// A fresh document: one clip per entry of `clips` (name, speed, keep pitch),
/// each on its own track from 0, every one showing 60 s of picture and sound,
/// the In–Out range [5 s, 10 s), in a 1440×900 window. The clip ids, or why
/// the fixture could not be built.
func fresh(_ clips: [(String, Double, Bool)]) -> Result<[UInt32], ProbeFailure> {
    window?.orderOut(nil)
    if let old = doc { NSDocumentController.shared.removeDocument(old) }
    doc = ProjectDocument()
    documents.append(doc)
    let path = mediaFile("sixty.mov")
    doc.performGroupedEdit("Media", [.addMedia(descriptor: MediaDescriptor(
        path: path, kind: .video, duration: 60 * second, width: 1920, height: 1080,
        fps: .thirty, hasVideo: true, hasAudio: true))])
    guard let media = doc.project.snapshot.media.first(where: { $0.path == path })?.id else {
        return .failure(ProbeFailure("add_media added nothing"))
    }
    var ids: [UInt32] = []
    for (index, (name, rate, keep)) in clips.enumerated() {
        while doc.project.snapshot.tracks.count <= index {
            doc.performGroupedEdit(
                "Track", [.addTrack(index: doc.project.snapshot.tracks.count)])
        }
        let track = doc.project.snapshot.tracks[index].id
        doc.performGroupedEdit("Clip", [.addClip(track: track, media: media, at: 0)])
        guard let clip = doc.project.snapshot.clips.first(where: { $0.track == track }) else {
            return .failure(ProbeFailure("add_clip on track \(track) added nothing"))
        }
        doc.performGroupedEdit("Name", [.setClip(clips: [clip.id], patch: ClipPatch(name: name))])
        doc.performGroupedEdit("Speed", [.setSpeed(clip: clip.id, rate: rate, keepPitch: keep)])
        ids.append(clip.id)
    }
    let snapshot = doc.project.snapshot
    for (id, (_, rate, keep)) in zip(ids, clips) {
        guard let clip = snapshot.clip(id), clip.speed == rate,
            clip.audioProps.keepPitch == keep
        else { return .failure(ProbeFailure("the fixture's set_speed did not take on \(id)")) }
    }
    doc.inOutRange = (start: range.from, end: range.to)
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
    guard window.attachedSheet == nil else {
        return .failure(ProbeFailure("a sheet was attached after set-up"))
    }
    return .success(ids)
}

struct ProbeFailure: Error {
    let why: String
    init(_ why: String) { self.why = why }
}

var canUndo: Bool { doc.undoManager?.canUndo ?? false }
var undoName: String { doc.undoManager?.undoActionName ?? "" }

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

/// Clip ▸ Retime Range… (the editor's own action) with `rate` typed into the
/// sheet's field; nil when it did not attach.
func retimeSheet(rate: Double) -> (NSWindow, RetimeSheetController)? {
    guard controller.validateRetimeAction(#selector(EditorViewController.showRetimeSheet(_:)))
        == true
    else { return nil }
    controller.showRetimeSheet(nil)
    guard waitUntil(3, { window.attachedSheet != nil }) != nil,
        let sheet = window.attachedSheet,
        let retime = sheet.contentViewController as? RetimeSheetController,
        let field = views(sheet).compactMap({ $0 as? NSTextField })
            .first(where: { $0.delegate === retime })
    else { return nil }
    field.doubleValue = rate
    retime.controlTextDidEndEditing(
        Notification(name: NSControl.textDidEndEditingNotification, object: field))
    return (sheet, retime)
}

func apply(_ sheet: NSWindow) -> Bool {
    let click = NSSelectorFromString("applyClicked:")
    guard let button = views(sheet).compactMap({ $0 as? NSButton })
        .first(where: { $0.action == click })
    else { return false }
    return NSApp.sendAction(click, to: button.target, from: button)
}

func pitchBox(_ sheet: NSWindow) -> NSButton? {
    views(sheet).compactMap { $0 as? NSButton }.first { $0.title == "Preserve pitch" }
}

/// A question attached to `host` within `limit` s.
func question(on host: NSWindow, within limit: Double) -> NSWindow? {
    var found: NSWindow?
    _ = waitUntil(limit) {
        found = host.attachedSheet
        return found != nil
    }
    return found
}

/// The clip on A's track that starts at the range's start once applied.
func piece(on track: UInt32) -> ClipSnapshot? {
    doc.project.snapshot.clips.first { $0.track == track && $0.start == range.from }
}

// MARK: - R8a — the question on the sheet, Cancel, then Set Speed

switch fresh([("Alpha", 4, true)]) {
case .failure(let failure):
    row("R8a", false, "instrument: fixture: \(failure.why)", instrument: true)
case .success(let ids):
    let track = doc.project.snapshot.clip(ids[0])?.track ?? 0
    let before = doc.project
    if let (sheet, _) = retimeSheet(rate: 4), apply(sheet) {
        if let asked = question(on: sheet, within: 3) {
            let expected = oneMessage("Alpha", "×16")
            let shown = texts(asked)
            let text = shown.contains(expected)
            let untouched = doc.project === before
            sheet.endSheet(asked, returnCode: .alertSecondButtonReturn)
            pause(0.5)
            let same = doc.project === before
            let still = window.attachedSheet === sheet
            let noStep = !canUndo
            var after = "Apply again was not reached"
            var confirmed = false
            if apply(sheet), let again = question(on: sheet, within: 3) {
                sheet.endSheet(again, returnCode: .alertFirstButtonReturn)
                let closed = waitUntil(3) { window.attachedSheet == nil } != nil
                let speed = piece(on: track)?.speed ?? -1
                confirmed = closed && canUndo && undoName == "Retime Range" && speed == 16
                after = "after Set Speed the sheet closed \(closed), canUndo \(canUndo), undo "
                    + "name \"\(undoName)\", the piece at ×\(speed)"
            }
            row("R8a", text && untouched && same && still && noStep && confirmed,
                "question \(shown) holds \"\(expected)\": \(text) (ceiling \(ceiling)); "
                    + "nothing applied while asked \(untouched); after Cancel the same handle "
                    + "\(same), the sheet still up \(still), no step \(noStep); \(after)")
        } else {
            row("R8a", false, "no question on the Retime Range sheet within 3 s; the "
                + "project changed: \(doc.project !== before), undo \"\(undoName)\"")
        }
    } else {
        row("R8a", false, "instrument: the Retime Range sheet or its Apply was not reached",
            instrument: true)
    }
}
settle()

// MARK: - R8b — CONTROL: ×2 over a ×1 clip asks nothing

switch fresh([("Bravo", 1, true)]) {
case .failure(let failure):
    row("R8b", false, "instrument: fixture: \(failure.why)", instrument: true)
case .success(let ids):
    let track = doc.project.snapshot.clip(ids[0])?.track ?? 0
    if let (sheet, _) = retimeSheet(rate: 2), apply(sheet) {
        let asked = waitUntil(1) { sheet.attachedSheet != nil } != nil
        let closed = waitUntil(3) { window.attachedSheet == nil } != nil
        let speed = piece(on: track)?.speed ?? -1
        row("R8b", !asked && closed && canUndo && undoName == "Retime Range" && speed == 2,
            "a question within 1 s: \(asked); the sheet closed \(closed); undo "
                + "\"\(undoName)\"; the piece at ×\(speed)")
    } else {
        row("R8b", false, "instrument: the Retime Range sheet or its Apply was not reached",
            instrument: true)
    }
}
settle()

// MARK: - R9p — the sheet's Keep pitch is the op's keep_pitch: false

switch fresh([("Off", 1, false), ("On", 1, true)]) {
case .failure(let failure):
    row("R9p", false, "instrument: fixture: \(failure.why)", instrument: true)
case .success:
    let before = doc.project
    let oracle: ReelProject?
    if case .applied(let next)? = try? before.applying(
        [.retimeRange(from: range.from, to: range.to, rate: 2, keepPitch: false)])
    {
        oracle = next
    } else {
        oracle = nil
    }
    if let oracle, let (sheet, _) = retimeSheet(rate: 2) {
        let opensOff = pitchBox(sheet)?.state == .off
        let pressed = apply(sheet)
        let closed = waitUntil(3) { window.attachedSheet == nil } != nil
        let equal = doc.project.json == oracle.json
        row("R9p", opensOff && pressed && closed && equal && undoName == "Retime Range",
            "Preserve pitch opened off: \(opensOff); Apply \(pressed), closed \(closed); the "
                + "document equals retime_range {rate: 2, keep_pitch: false} on the handle "
                + "before: \(equal) (\(doc.project.json.count) vs \(oracle.json.count) bytes); "
                + "undo \"\(undoName)\"")
    } else {
        row("R9p", false, "instrument: the oracle or the sheet was not reached",
            instrument: true)
    }
}
settle()

finish()
