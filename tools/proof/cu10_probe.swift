// Road map creator-jobs CU10 — the recorder polishes on landing, the rows no grant and no media
// are needed for (spec §11 CU-100…CU-103): the recorder panel's "When it lands:" rows (Q1), their
// keys' absent readings, persist and restore (Q2), their enabling and `applyPolish`'s gates (Q3),
// `RecordingPolish.commands(of:)`'s order (Q4), `decide`'s arms (Q5), `record_screen`'s
// polish refusals and stranger lists (Q6), and the follow-ups' clips read in the landing's
// container while a nest is open (Q7, #458).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// against `libframejob_core.a`, through `swift_build.py`:
//
//   cu10_probe <work dir>
//
// The panel is `RecorderPanelController.shared`, NEVER shown, under doors that read nothing true
// and ask nothing: no prompt, no System Settings, no camera or microphone opens. The eighteen
// `FrameJobRecording…` values are put back as they were. The answer is one JSON object on
// stdout, `{"rows": [...]}`, each row `{"id", "pass", "detail"}`; `cu10_probe.py` scores them.
import AppKit
import AVFoundation
import ScreenCaptureKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: cu10_probe <work dir>\n".utf8))
    exit(2)
}

var rows: [[String: Any]] = []
func row(_ id: String, _ problems: [String], _ detail: String) {
    rows.append(["id": id, "pass": problems.isEmpty,
                 "detail": problems.isEmpty ? detail : problems.joined(separator: "; ")])
}

func expect(_ problems: inout [String], _ what: String, _ got: Any, _ want: Any) {
    if "\(got)" != "\(want)" { problems.append("\(what): got \(got), want \(want)") }
}

// MARK: - Q4: the commands, in order

do {
    var problems: [String] = []
    var choice = RecordingChoice()
    expect(&problems, "none", RecordingPolish.commands(of: choice).map(\.rawValue), [String]())
    choice.speedUpTyping = true
    choice.autoZoom = true
    expect(&problems, "speed-up and zoom", RecordingPolish.commands(of: choice).map(\.rawValue),
           ["auto_zoom", "speed_up_typing"])
    choice.shortcutOverlays = true
    expect(&problems, "all three", RecordingPolish.commands(of: choice).map(\.rawValue),
           ["auto_zoom", "shortcut_overlays", "speed_up_typing"])
    expect(&problems, "titles", RecordingPolish.Command.allCases.map(\.title),
           ["Auto Zoom", "Add Shortcut Overlays", "Speed Up Typing"])
    expect(&problems, "RecordingChoice() asks nothing",
           [RecordingChoice().autoZoom, RecordingChoice().shortcutOverlays,
            RecordingChoice().speedUpTyping], [false, false, false])
    row("Q4", problems, "commands(of:) in allCases order: auto_zoom, shortcut_overlays, "
        + "speed_up_typing; titles their undo steps")
}

// MARK: - Q5: decide

do {
    var problems: [String] = []
    func d(_ clips: [UInt32], enhancing: Bool = false, ready: Bool = true, busy: Bool = false,
           elapsed: TimeInterval = 0) -> String {
        let step = RecordingPolish.decide(
            command: .speedUpTyping, clips: clips, enhancing: enhancing, ready: ready, busy: busy,
            elapsed: elapsed)
        return "\(step)"
    }
    let run = "\(RecordingPolish.Step.run(.speedUpTyping, [4]))"
    let give = "\(RecordingPolish.Step.giveUp(.speedUpTyping))"
    expect(&problems, "no clips → drop", d([]), "\(RecordingPolish.Step.drop)")
    expect(&problems, "no clips, enhancing → drop", d([], enhancing: true),
           "\(RecordingPolish.Step.drop)")
    expect(&problems, "enhancing, ready → wait", d([4], enhancing: true),
           "\(RecordingPolish.Step.wait)")
    expect(&problems, "enhancing past the limit → wait", d([4], enhancing: true, elapsed: 400),
           "\(RecordingPolish.Step.wait)")
    expect(&problems, "ready, not busy → run", d([4]), run)
    expect(&problems, "not ready → wait", d([4], ready: false), "\(RecordingPolish.Step.wait)")
    expect(&problems, "busy → wait", d([4], busy: true), "\(RecordingPolish.Step.wait)")
    expect(&problems, "not ready at 299 s → wait", d([4], ready: false, elapsed: 299),
           "\(RecordingPolish.Step.wait)")
    expect(&problems, "not ready at 300 s → give up", d([4], ready: false, elapsed: 300), give)
    expect(&problems, "busy at 300 s → give up", d([4], busy: true, elapsed: 300), give)
    expect(&problems, "waitLimit", RecordingPolish.waitLimit, 300.0)
    expect(&problems, "checkInterval", RecordingPolish.checkInterval, 0.5)
    row("Q5", problems, "decide: drop with no clips, wait while enhancing, run when ready and not "
        + "busy, wait at 299 s, give up at 300 s")
}

// MARK: - Q6: record_screen's refusals

do {
    var problems: [String] = []
    let server = AgentServer.shared
    func polish(_ a: [String: Any], place: Bool, keys: RecordingKeys) -> String {
        do {
            return "ok: " + (try server.recordingPolish(a, place: place, keys: keys))
                .map(\.rawValue).joined(separator: ",")
        } catch let error as AgentServer.ToolError {
            return error.message
        } catch {
            return "\(error)"
        }
    }
    func kind(_ a: [String: Any]) -> String {
        do {
            return "ok: " + (try server.recordingSourceKind(a)).rawValue
        } catch let error as AgentServer.ToolError {
            return error.message
        } catch {
            return "\(error)"
        }
    }
    let zoomPlace = "auto_zoom: true plans on the landed screen clips, so it needs place: true."
    let overlayPlace = "shortcut_overlays: true places overlays over the landed screen clips, so "
        + "it needs place: true."
    let overlayKeys = "shortcut_overlays: true needs keys: \"shortcuts\" — without it the cursor "
        + "file records no shortcut to show."
    let speedPlace = "speed_up_typing: true speeds up the landed screen clips' typing, so it needs "
        + "place: true."
    let speedKeys = "speed_up_typing: true needs keys: \"shortcuts\" — without it the cursor file "
        + "records no typing to speed up."
    let cases: [(String, [String: Any], Bool, RecordingKeys, String)] = [
        ("none", [:], true, .off, "ok: "),
        ("all false", ["auto_zoom": false, "shortcut_overlays": false, "speed_up_typing": false],
         false, .off, "ok: "),
        ("auto_zoom, keys off", ["auto_zoom": true], true, .off, "ok: auto_zoom"),
        ("auto_zoom, place false", ["auto_zoom": true], false, .shortcuts, zoomPlace),
        ("overlays, place false", ["shortcut_overlays": true], false, .shortcuts, overlayPlace),
        ("overlays, keys off", ["shortcut_overlays": true], true, .off, overlayKeys),
        ("overlays, place false and keys off (place first)", ["shortcut_overlays": true], false,
         .off, overlayPlace),
        ("speed-up, place false", ["speed_up_typing": true], false, .shortcuts, speedPlace),
        ("speed-up, keys off", ["speed_up_typing": true], true, .off, speedKeys),
        ("all three, keys off (auto_zoom passes, overlays refused first)",
         ["auto_zoom": true, "shortcut_overlays": true, "speed_up_typing": true], true, .off,
         overlayKeys),
        ("all three, place false (auto_zoom first)",
         ["auto_zoom": true, "shortcut_overlays": true, "speed_up_typing": true], false,
         .shortcuts, zoomPlace),
        ("all three, place and shortcuts",
         ["auto_zoom": true, "shortcut_overlays": true, "speed_up_typing": true], true,
         .shortcuts, "ok: auto_zoom,shortcut_overlays,speed_up_typing"),
        ("auto_zoom \"yes\"", ["auto_zoom": "yes"], true, .off, "auto_zoom must be a boolean"),
    ]
    for (name, a, place, keys, want) in cases {
        let got = polish(a, place: place, keys: keys)
        if want == "auto_zoom must be a boolean" {
            if got.hasPrefix("ok") { problems.append("\(name): admitted (\(got))") }
        } else {
            expect(&problems, name, got, want)
        }
    }
    let voice = " cannot be given — a voice-over records the microphone alone."
    expect(&problems, "voice_over with auto_zoom", kind(["source": "voice_over", "auto_zoom": true]),
           "With source voice_over, auto_zoom" + voice)
    expect(&problems, "voice_over with all three and keys",
           kind(["source": "voice_over", "auto_zoom": true, "shortcut_overlays": true,
                 "speed_up_typing": false, "keys": "shortcuts"]),
           "With source voice_over, auto_zoom, shortcut_overlays, speed_up_typing, keys" + voice)
    expect(&problems, "voice_over with auto_zoom null",
           kind(["source": "voice_over", "auto_zoom": NSNull()]), "ok: voice_over")
    let camera = kind(["source": "camera", "speed_up_typing": true])
    if !camera.contains("speed_up_typing") || camera.hasPrefix("ok") {
        problems.append("camera with speed_up_typing: \(camera)")
    }
    expect(&problems, "screen with auto_zoom", kind(["auto_zoom": true]), "ok: screen")
    row("Q6", problems, "recordingPolish refuses place then keys, in the order auto_zoom, "
        + "shortcut_overlays, speed_up_typing, in CU-102 (b)'s sentences; voice_over and camera "
        + "refuse the three by name")
}

// MARK: - Q7: the follow-ups read the landing's container (#458)

do {
    var problems: [String] = []
    let second: Ticks = 600_000
    // A screen recording at P with a cursor file, landed at the top level as clip `landed`; a
    // nest holding a clip of another media; the open container the nest.
    let screen = "/nowhere/cu10-q7-screen.mov"
    let doc = ProjectDocument()
    let track = doc.project.snapshot.tracks.first?.id ?? 0
    doc.performGroupedEdit("Media", [
        .addMedia(descriptor: MediaDescriptor(
            path: screen, kind: .video, duration: 5 * second, width: 1920, height: 1080,
            fps: .thirty, hasVideo: true, hasAudio: false,
            cursor: MediaCursor(path: "/nowhere/cu10-q7-screen.cursor", inPicture: true))),
        .addMedia(descriptor: MediaDescriptor(
            path: "/nowhere/cu10-q7-other.mov", kind: .video, duration: 5 * second, width: 1920,
            height: 1080, fps: .thirty, hasVideo: true, hasAudio: false)),
    ])
    let media = doc.project.snapshot.media
    let screenID = media.first { $0.path == screen }?.id ?? 0
    let otherID = media.first { $0.path != screen }?.id ?? 0
    doc.performGroupedEdit("Clips", [
        .addClip(track: track, media: screenID, at: 0),
        .addClip(track: track, media: otherID, at: 10 * second),
    ])
    let clips = doc.project.snapshot.clips
    let landed = clips.first { $0.source.mediaID == screenID }?.id ?? 0
    let inner = clips.first { $0.source.mediaID == otherID }?.id ?? 0
    doc.performGroupedEdit("Nest", [.nest(clips: [inner])])
    let after = doc.project.snapshot
    let nestClip = after.clips.first { $0.source.nestID != nil }
    if let nestClip, let nest = nestClip.source.nestID {
        doc.setNestPath([NestScopeStep(nest: nest, clip: nestClip.id)], playhead: 0, selection: [])
    }
    expect(&problems, "the open container is the nest", doc.scope != nil, true)
    expect(&problems, "the landed clip is not in the open container",
           doc.editedProject.snapshot.clip(landed) == nil, true)
    let found = RecordingPolish.screenClips([screen], in: doc, scope: nil)
    expect(&problems, "screenClips in the landing's container", found, [landed])
    expect(&problems, "present in the landing's container",
           RecordingEnhance.present([landed], in: doc, scope: nil), [landed])
    let busy = RecordingEnhance.isBusy(doc, scope: nil)
    expect(&problems, "busy while the nest is open", busy, true)
    let step = RecordingPolish.decide(
        command: .autoZoom, clips: found, enhancing: false, ready: true, busy: busy, elapsed: 0)
    expect(&problems, "decide waits, not drops", "\(step)", "\(RecordingPolish.Step.wait)")
    let enhance = RecordingEnhance.decide(
        clips: RecordingEnhance.present([landed], in: doc, scope: nil), analysed: true,
        busy: busy, elapsed: 0)
    expect(&problems, "Enhance waits, not drops", "\(enhance)", "\(RecordingEnhance.Step.wait)")
    row("Q7", problems, "with a nest open, the landed screen clip \(landed) is still found in the "
        + "landing's (top-level) container; busy, so both follow-ups wait rather than drop")
}

// MARK: - The panel

/// Doors that read nothing true and ask nothing.
func sealed() -> RecorderGrantDoors {
    RecorderGrantDoors(
        screenGranted: { false }, launchedByLaunchd: { true }, requestScreen: {},
        screenAsked: { true }, rememberScreenAsked: {}, microphoneStatus: { .denied },
        requestMicrophone: { _ in }, openSettings: { _ in false },
        cameraStatus: { .denied }, requestCamera: { _ in })
}

func gridRow(of view: NSView) -> Int? {
    var parent = view.superview
    while let p = parent, !(p is NSGridView) { parent = p.superview }
    guard let grid = parent as? NSGridView, let cell = grid.cell(for: view), let r = cell.row
    else { return nil }
    return grid.index(of: r)
}

NSApplication.shared.setActivationPolicy(.prohibited)
RecorderPanelController.grantDoors = sealed()
let keys = [
    RecorderPanelController.displayKey, RecorderPanelController.microphoneKey,
    RecorderPanelController.systemAudioKey, RecorderPanelController.showClicksKey,
    RecorderPanelController.rateKey, RecorderPanelController.sizeKey,
    RecorderPanelController.includeFrameJobWindowsKey, RecorderPanelController.cameraKey,
    RecorderPanelController.cameraFormatKey, RecorderPanelController.cameraBesideKey,
    RecorderPanelController.enhanceMicrophoneKey, RecorderPanelController.keysKey,
    RecorderPanelController.cursorKey, RecorderPanelController.autoZoomKey,
    RecorderPanelController.shortcutOverlaysKey, RecorderPanelController.speedUpTypingKey,
    RecorderPanelController.cameraLayoutKey, RecorderPanelController.cameraCutoutKey,
]
let polishKeys = [
    RecorderPanelController.autoZoomKey, RecorderPanelController.shortcutOverlaysKey,
    RecorderPanelController.speedUpTypingKey,
]
let originals = keys.map { UserDefaults.standard.object(forKey: $0) }
UserDefaults.standard.set(false, forKey: RecorderPanelController.cameraBesideKey)
UserDefaults.standard.set(false, forKey: RecorderPanelController.keysKey)
let panel = RecorderPanelController.shared
let boxes = panel.polishBoxes
func states() -> [Bool] { boxes.all.map { $0.state == .on } }
func stored() -> [String] {
    polishKeys.map { key in
        UserDefaults.standard.object(forKey: key) == nil
            ? "absent" : "\(UserDefaults.standard.bool(forKey: key))"
    }
}
func pick(_ item: NSMenuItem?) {
    guard let item else { return }
    panel.sourcePopup.select(item)
    panel.controlChanged(panel.sourcePopup)
}
func displayRow() -> NSMenuItem? { panel.sourcePopup.item(at: 0) }
func setShortcuts(_ on: Bool) {
    panel.recordShortcutsCheckbox.state = on ? .on : .off
    panel.controlChanged(panel.recordShortcutsCheckbox)
}
func tick(_ box: NSButton, _ on: Bool) {
    box.state = on ? .on : .off
    panel.controlChanged(box)
}

// MARK: - Q1: the rows

do {
    var problems: [String] = []
    expect(&problems, "visible", panel.window?.isVisible ?? false, false)
    expect(&problems, "titles", boxes.all.map(\.title),
           ["Zoom in on clicks", "Show shortcuts", "Speed up typing"])
    let note = gridRow(of: panel.recordShortcutsNote)
    let rate = gridRow(of: panel.ratePopup)
    let rowsOf = boxes.all.map { gridRow(of: $0).map { "\($0)" } ?? "nil" }
    expect(&problems, "rows after the note",
           rowsOf, note.map { n in [n + 1, n + 2, n + 3].map { "\($0)" } } ?? ["no note row"])
    expect(&problems, "Rate after them", rate.map { "\($0)" } ?? "nil",
           note.map { "\($0 + 4)" } ?? "no note row")
    if let grid = boxes.autoZoom.superview as? NSGridView, let r = gridRow(of: boxes.autoZoom) {
        let label = grid.cell(atColumnIndex: 0, rowIndex: r).contentView as? NSTextField
        expect(&problems, "label", label?.stringValue ?? "nil", "When it lands:")
        for box in [boxes.shortcutOverlays, boxes.speedUpTyping] {
            if let br = gridRow(of: box),
                grid.cell(atColumnIndex: 0, rowIndex: br).contentView is NSTextField
            {
                problems.append("\(box.title) has a label")
            }
        }
    } else {
        problems.append("the boxes are not grid cells")
    }
    for box in boxes.all {
        expect(&problems, "\(box.title) action", box.action.map { NSStringFromSelector($0) } ?? "nil",
               "controlChanged:")
        if (box.target as AnyObject?) !== panel { problems.append("\(box.title) target") }
        if !(box.toolTip ?? "").contains(box === boxes.autoZoom ? "Auto Zoom"
            : box === boxes.shortcutOverlays ? "Add Shortcut Overlays" : "Speed Up Typing")
        {
            problems.append("\(box.title) tooltip: \(box.toolTip ?? "nil")")
        }
    }
    row("Q1", problems, "\"When it lands:\" with Zoom in on clicks, Show shortcuts and Speed up "
        + "typing after the Record shortcuts note and before Rate, each controlChanged:")
}

// MARK: - Q2: the keys

do {
    var problems: [String] = []
    for key in polishKeys { UserDefaults.standard.removeObject(forKey: key) }
    panel.restoreChoices()
    expect(&problems, "absent keys read", states(), [true, true, false])
    pick(displayRow())
    expect(&problems, "persisted after a change", stored(), ["true", "true", "false"])
    tick(boxes.autoZoom, false)
    tick(boxes.speedUpTyping, true)
    expect(&problems, "a change writes", stored(), ["false", "true", "true"])
    tick(boxes.autoZoom, true)
    tick(boxes.shortcutOverlays, false)
    tick(boxes.speedUpTyping, false)
    UserDefaults.standard.set(false, forKey: RecorderPanelController.autoZoomKey)
    UserDefaults.standard.set(true, forKey: RecorderPanelController.speedUpTypingKey)
    UserDefaults.standard.set(false, forKey: RecorderPanelController.shortcutOverlaysKey)
    panel.restoreChoices()
    expect(&problems, "stored values restore", states(), [false, false, true])
    for key in polishKeys { UserDefaults.standard.removeObject(forKey: key) }
    panel.restoreChoices()
    expect(&problems, "absent again", states(), [true, true, false])
    row("Q2", problems, "absent keys read on, on, off; each change writes all three; stored values "
        + "restore")
}

// MARK: - Q3: the enabling and the choice's gates

do {
    var problems: [String] = []
    pick(displayRow())
    for box in boxes.all { box.state = .on }
    setShortcuts(false)
    panel.syncControlsEnabled()
    expect(&problems, "display, no shortcuts: enabled", boxes.all.map(\.isEnabled),
           [true, false, false])
    var choice = panel.currentChoice()
    expect(&problems, "display, no shortcuts: choice",
           [choice.autoZoom, choice.shortcutOverlays, choice.speedUpTyping], [true, false, false])
    expect(&problems, "greyed keep their values", states(), [true, true, true])
    setShortcuts(true)
    expect(&problems, "display, shortcuts: enabled", boxes.all.map(\.isEnabled),
           [true, true, true])
    choice = panel.currentChoice()
    expect(&problems, "display, shortcuts: choice",
           [choice.autoZoom, choice.shortcutOverlays, choice.speedUpTyping], [true, true, true])
    tick(boxes.shortcutOverlays, false)
    choice = panel.currentChoice()
    expect(&problems, "a box off: choice",
           [choice.autoZoom, choice.shortcutOverlays, choice.speedUpTyping], [true, false, true])
    tick(boxes.shortcutOverlays, true)
    for (name, tag) in [("Microphone Only", RecorderPanelController.voiceOverTag),
                        ("Camera", RecorderPanelController.cameraTag)] {
        panel.sourcePopup.selectItem(withTag: tag)
        panel.refreshSizeNote()
        panel.syncControlsEnabled()
        expect(&problems, "\(name): enabled", boxes.all.map(\.isEnabled), [false, false, false])
        choice = panel.currentChoice()
        expect(&problems, "\(name): choice",
               [choice.autoZoom, choice.shortcutOverlays, choice.speedUpTyping],
               [false, false, false])
        expect(&problems, "\(name): kept", states(), [true, true, true])
    }
    pick(displayRow())
    panel.phase = .countdown(3)
    panel.syncControlsEnabled()
    expect(&problems, "counting down: enabled", boxes.all.map(\.isEnabled), [false, false, false])
    panel.phase = .idle
    panel.syncControlsEnabled()
    expect(&problems, "idle again: enabled", boxes.all.map(\.isEnabled), [true, true, true])
    setShortcuts(false)
    for key in polishKeys { UserDefaults.standard.removeObject(forKey: key) }
    panel.restoreChoices()
    row("Q3", problems, "Zoom in on clicks live idle with a screen source, the other two only with "
        + "Record shortcuts too; greyed keep their values; applyPolish gates the choice the same")
}

for (key, value) in zip(keys, originals) {
    if let value { UserDefaults.standard.set(value, forKey: key) } else {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
let answer = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
    ?? Data("{}".utf8)
FileHandle.standardOutput.write(answer)
exit(0)
