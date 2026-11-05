// Docs-bugs batch a4: #478 (File ▸ New Recording…'s title while the panel's attempt starts) and
// #495 (the Document tab's Rate popup on a rate it does not list), through the app's own sources
// on real .framejob packages the app made and saved (`docs_bugs_a4_proof.py` makes them and scores
// what this prints). Compiled AS main.swift over every file of app/Sources but the app's
// main.swift, against libframejob_core.a, through swift_build.py. It names no symbol the base
// lacks, so the same source builds against the base tree.
//
// Runs: docs_bugs_a4_probe <fixtures.json> <scratch folder> [N1,P1,…]
//
// The N rows write the panel's `phase` and `launched` and `ScreenRecorder.shared.state` by hand,
// as `recording_probe.py`'s chrome mode does, under sealed grant doors, and put each back to idle.
// Nothing records: `record(_:)` is never called, and `newRecording(nil)` is called only while the
// panel is `.starting` and not launched, where it abandons the attempt. The P rows open each
// package's editor in a window of alpha 0, select the Document tab and `cacheDisplay` the Rate
// row's popup into a PNG. **No event is posted to the system and nothing takes focus:** the app is
// `.prohibited`, so it cannot activate.
//
// It prints what it reads, one JSON line a row, and decides nothing; the proof scores.
import AppKit
import AVFoundation

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

let arguments = CommandLine.arguments
let fixtures = (try! JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: arguments[1])))) as! [String: String]
let scratch = URL(fileURLWithPath: arguments[2])
let wanted = Set(arguments.count > 3 ? arguments[3].split(separator: ",").map(String.init) : [])

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
UserDefaults.standard.setVolatileDomain([
    RecorderPanelController.displayKey: 0, RecorderPanelController.microphoneKey: "",
    RecorderPanelController.systemAudioKey: true, RecorderPanelController.showClicksKey: false,
    RecorderPanelController.rateKey: 60, RecorderPanelController.sizeKey: "nominal",
    RecorderPanelController.includeFrameJobWindowsKey: false,
], forName: UserDefaults.argumentDomain)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

func say(_ id: String, _ fields: [String: Any]) {
    var row = fields
    row["row"] = id
    let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
func wants(_ rows: String...) -> Bool { wanted.isEmpty || rows.contains { wanted.contains($0) } }

// MARK: - #478, File ▸ New Recording…

/// `recording_probe.py`'s `sealedDoors()`: the reads are real, and every door that could prompt,
/// open System Settings or write the asked flag does nothing.
func sealedDoors() -> RecorderGrantDoors {
    RecorderGrantDoors(
        screenGranted: { RecordingGrant.screenRecordingGranted },
        launchedByLaunchd: { RecordingGrant.launchedByLaunchd },
        requestScreen: {},
        screenAsked: { false },
        rememberScreenAsked: {},
        microphoneStatus: { RecordingGrant.microphoneStatus },
        requestMicrophone: { _ in },
        openSettings: { _ in false },
        cameraStatus: { RecordingGrant.cameraStatus },
        requestCamera: { _ in })
}

/// The File menu's item as `validateMenuItem` leaves it: its title and whether it is live.
func newRecordingItem() -> [String: Any] {
    let item = NSMenuItem(
        title: "New Recording…", action: #selector(AppDelegate.newRecording(_:)), keyEquivalent: "")
    let enabled = delegate.validateMenuItem(item)
    return ["title": item.title, "enabled": enabled]
}

func recorderRows() {
    RecorderPanelController.grantDoors = sealedDoors()
    let panel = RecorderPanelController.shared
    let recorder = ScreenRecorder.shared
    func reset() {
        recorder.state = .idle
        panel.launched = false
        panel.phase = .idle
        panel.setNote("")
    }
    reset()

    if wants("N1") {
        panel.phase = .starting
        panel.launched = false
        var fields = newRecordingItem()
        fields["recorderIdle"] = !recorder.isRecording
        say("N1", fields)
        reset()
    }
    if wants("N2") {
        panel.phase = .starting
        panel.launched = true
        recorder.state = .arming
        var fields = newRecordingItem()
        fields["recorder"] = "\(recorder.state)"
        say("N2", fields)
        reset()
    }
    if wants("N3") {
        var fields = newRecordingItem()
        fields["phase"] = "\(panel.phase)"
        say("N3", fields)
    }
    if wants("N4") {
        panel.phase = .starting
        panel.launched = false
        delegate.newRecording(nil)
        say("N4", [
            "phase": "\(panel.phase)", "note": panel.noteLabel.stringValue,
            "abandoned": RecorderPanelController.abandonedSentence,
            "visible": panel.window?.isVisible ?? false,
        ])
        panel.window?.orderOut(nil)
        reset()
    }
    if wants("N5") {
        recorder.state = .recording
        var fields = newRecordingItem()
        fields["phase"] = "\(panel.phase)"
        say("N5", fields)
        reset()
    }
    panel.window?.orderOut(nil)
}

// MARK: - #495, the Rate popup

struct Editor {
    let document: ProjectDocument
    let controller: EditorViewController
    let window: NSWindow
}

func open(_ tag: String, _ fixture: String) -> Editor? {
    guard let path = fixtures[fixture] else { return nil }
    let copy = scratch.appendingPathComponent("run-\(tag).framejob")
    try? FileManager.default.removeItem(at: copy)
    do {
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: copy)
        let document = ProjectDocument()
        try document.read(from: copy, ofType: ProjectDocument.projectTypeIdentifier)
        document.fileURL = copy
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let window = document.windowControllers.first?.window,
              let controller = window.contentViewController as? EditorViewController
        else { return nil }
        window.alphaValue = 0
        document.showWindows()
        spin(1.2)
        return Editor(document: document, controller: controller, window: window)
    } catch {
        return nil
    }
}

func close(_ editor: Editor) {
    editor.controller.playback.pause()
    editor.document.close()
    spin(0.2)
}

/// The Document tab's Rate popup: the first popup in the `doc.rate` section.
func ratePopup(_ editor: Editor) -> OptionPopupControl? {
    editor.controller.inspector?.select(.document)
    spin(0.4)
    let sections = walk(editor.window.contentView!).compactMap { $0 as? InspectorSection }
    guard let section = sections.first(where: { $0.id == "doc.rate" }) else { return nil }
    section.reveal()
    spin(0.3)
    editor.window.contentView?.layoutSubtreeIfNeeded()
    return walk(section).compactMap { $0 as? OptionPopupControl }.first
}

/// The popup drawn into a PNG at `scratch/rate-<fixture>.png`: its path, or why not.
func capture(_ fixture: String) -> [String: Any] {
    guard let editor = open("rate-\(fixture)", fixture) else { return ["failed": "no editor"] }
    defer { close(editor) }
    guard let popup = ratePopup(editor) else { return ["failed": "no Rate popup"] }
    popup.refresh()
    guard let rep = popup.bitmapImageRepForCachingDisplay(in: popup.bounds) else {
        return ["failed": "no bitmap"]
    }
    popup.cacheDisplay(in: popup.bounds, to: rep)
    let png = scratch.appendingPathComponent("rate-\(fixture).png")
    guard let data = rep.representation(using: .png, properties: [:]) else {
        return ["failed": "no PNG"]
    }
    try? data.write(to: png)
    let fps = editor.document.editedProject.snapshot.canvas.fps
    return ["png": png.path, "fps": [fps.num, fps.den], "width": Double(popup.bounds.width)]
}

func rateRows() {
    var captured: [String: [String: Any]] = [:]
    func shot(_ fixture: String) -> [String: Any] {
        if let done = captured[fixture] { return done }
        let done = capture(fixture)
        captured[fixture] = done
        return done
    }
    for (row, fixture) in [("P1", "r5994"), ("P2", "r48"), ("P3", "r30")] where wants(row) {
        say(row, ["rate": shot(fixture), "r24": shot("r24")])
    }
    if wants("P5") {
        guard let editor = open("pick", "r5994clip") else {
            say("P5", ["failed": "no editor"])
            return
        }
        guard let popup = ratePopup(editor) else {
            say("P5", ["failed": "no Rate popup"])
            close(editor)
            return
        }
        let before = editor.document.editedProject.snapshot.canvas.fps
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.tag = Fps.common.count + 1
        popup.perform(NSSelectorFromString("itemPicked:"), with: item)
        spin(0.4)
        let after = editor.document.editedProject.snapshot.canvas.fps
        say("P5", [
            "tag": item.tag, "before": [before.num, before.den], "after": [after.num, after.den],
            "clips": editor.document.editedProject.snapshot.clips.count,
        ])
        close(editor)
    }
}

if wants("N1", "N2", "N3", "N4", "N5") { recorderRows() }
if wants("P1", "P2", "P3", "P5") { rateRows() }
say("done", [:])
exit(0)
