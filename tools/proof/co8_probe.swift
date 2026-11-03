// Road map creator-jobs CO8 — the camera's layout and cutout at record time, the rows no grant
// and no media are needed for (spec §11 CO-80…CO-84): the recorder panel's Layout and
// Remove-background rows (Q1), their keys' absent, stale and changed readings (Q2), their
// enabling and `applyCameraLanding`'s gates (Q3), the tools' CO-83 refusals, exact (Q4), a write
// run then a read run (Q5), and the landing over built `RecordingResult`s — two segments, the
// second without a camera (Q6), a +3 frame camera offset and an overrun screen's fallback (Q7).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// with `FRAMEJOB_DEV_TOOLS`, against `libframejob_core.a`, through `swift_build.py`:
//
//   co8_probe <work dir> main|write|read
//
// The panel is `RecorderPanelController.shared`, NEVER shown, under doors that read nothing true
// and ask nothing: no prompt, no System Settings, no camera or microphone opens. `main` puts the
// eighteen `FrameJobRecording…` values back as they were; `write` saves them to
// `<work dir>/originals.json`, changes the two keys through the panel and exits; `read` (a new
// process) restores the panel, reads the two, and puts every saved value back. The answer is one
// JSON object on stdout, `{"rows": [...]}`, each row `{"id", "pass", "detail"}`; `co8_probe.py`
// scores them. The landing's media are descriptors only: the core reads no file.
import AppKit
import AVFoundation
import ScreenCaptureKit

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: co8_probe <work dir> main|write|read\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments[2]
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

var rows: [[String: Any]] = []
func row(_ id: String, _ problems: [String], _ detail: String) {
    rows.append(["id": id, "pass": problems.isEmpty,
                 "detail": problems.isEmpty ? detail : problems.joined(separator: "; ")])
}

func expect(_ problems: inout [String], _ what: String, _ got: Any, _ want: Any) {
    if "\(got)" != "\(want)" { problems.append("\(what): got \(got), want \(want)") }
}

func finish() -> Never {
    let answer =
        (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(answer)
    exit(0)
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
let landingKeys = [RecorderPanelController.cameraLayoutKey, RecorderPanelController.cameraCutoutKey]
let saved = work.appendingPathComponent("originals.json")
func putBack(_ originals: [Any?]) {
    for (key, value) in zip(keys, originals) {
        if let value { UserDefaults.standard.set(value, forKey: key) } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
func storedLanding() -> [String] {
    landingKeys.map { key in
        UserDefaults.standard.object(forKey: key).map { "\($0)" } ?? "absent"
    }
}

// MARK: - Q5's write run and read run

if mode == "write" {
    // Every value as it is, saved for the read run; `NSNull` for an absent key.
    let originals = keys.map { UserDefaults.standard.object(forKey: $0) ?? NSNull() }
    guard let data = try? JSONSerialization.data(withJSONObject: originals),
        (try? data.write(to: saved)) != nil
    else {
        row("Q5w", ["the originals could not be saved; nothing was changed"], "")
        finish()
    }
    UserDefaults.standard.set(true, forKey: RecorderPanelController.cameraBesideKey)
    let panel = RecorderPanelController.shared
    panel.restoreChoices()
    panel.cameraLanding.select(.sideBySide)
    panel.controlChanged(panel.cameraLanding.layoutPopup)
    panel.cameraLanding.cutoutCheckbox.state = .on
    panel.controlChanged(panel.cameraLanding.cutoutCheckbox)
    UserDefaults.standard.synchronize()
    var problems: [String] = []
    expect(&problems, "written", storedLanding(), ["side_by_side", "1"])
    row("Q5w", problems, "the write run changed the two through the panel: \(storedLanding())")
    finish()
}
if mode == "read" {
    var problems: [String] = []
    let panel = RecorderPanelController.shared
    panel.restoreChoices()
    expect(&problems, "restored layout", panel.cameraLanding.layout.rawValue, "side_by_side")
    expect(&problems, "restored cutout", panel.cameraLanding.cutoutCheckbox.state == .on, true)
    if let data = try? Data(contentsOf: saved),
        let originals = (try? JSONSerialization.jsonObject(with: data)) as? [Any],
        originals.count == keys.count
    {
        putBack(originals.map { $0 is NSNull ? nil : $0 })
        UserDefaults.standard.synchronize()
        let now = keys.map { UserDefaults.standard.object(forKey: $0) ?? NSNull() }
        expect(&problems, "put back", (now as NSArray).isEqual(to: originals), true)
    } else {
        problems.append("no originals saved by the write run")
    }
    row("Q5r", problems, "a relaunch restored side_by_side and on, and every saved value was put "
        + "back")
    finish()
}

let originals = keys.map { UserDefaults.standard.object(forKey: $0) }
UserDefaults.standard.set(false, forKey: RecorderPanelController.cameraBesideKey)
let panel = RecorderPanelController.shared
let controls = panel.cameraLanding
func pick(_ item: NSMenuItem?) {
    guard let item else { return }
    panel.sourcePopup.select(item)
    panel.controlChanged(panel.sourcePopup)
}
func displayRow() -> NSMenuItem? { panel.sourcePopup.item(at: 0) }
func tickBeside(_ on: Bool) {
    panel.cameraBesideCheckbox.state = on ? .on : .off
    panel.controlChanged(panel.cameraBesideCheckbox)
}
func choose(_ layout: RecordingCameraLayout) {
    controls.select(layout)
    panel.controlChanged(controls.layoutPopup)
}
func cutout(_ on: Bool) {
    controls.cutoutCheckbox.state = on ? .on : .off
    panel.controlChanged(controls.cutoutCheckbox)
}

// MARK: - Q1: the rows

do {
    var problems: [String] = []
    expect(&problems, "visible", panel.window?.isVisible ?? false, false)
    expect(&problems, "titles", controls.layoutPopup.itemArray.map(\.title),
           ["Corner", "Rounded Corner", "Circle", "Side by Side", "Camera Full"])
    expect(&problems, "represented objects",
           controls.layoutPopup.itemArray.map { $0.representedObject as? String ?? "nil" },
           RecordingCameraLayout.allCases.map(\.rawValue))
    expect(&problems, "box title", controls.cutoutCheckbox.title,
           "Remove the camera's background when it lands")
    let preview = gridRow(of: panel.cameraPreview)
    let microphone = gridRow(of: panel.microphonePopup)
    expect(&problems, "Layout after the preview",
           gridRow(of: controls.layoutPopup).map { "\($0)" } ?? "nil",
           preview.map { "\($0 + 1)" } ?? "no preview row")
    expect(&problems, "the box after Layout",
           gridRow(of: controls.cutoutCheckbox).map { "\($0)" } ?? "nil",
           preview.map { "\($0 + 2)" } ?? "no preview row")
    expect(&problems, "Microphone after them", microphone.map { "\($0)" } ?? "nil",
           preview.map { "\($0 + 3)" } ?? "no preview row")
    if let grid = controls.layoutPopup.superview as? NSGridView,
        let r = gridRow(of: controls.layoutPopup), let b = gridRow(of: controls.cutoutCheckbox)
    {
        let label = grid.cell(atColumnIndex: 0, rowIndex: r).contentView as? NSTextField
        expect(&problems, "label", label?.stringValue ?? "nil", "Layout:")
        if grid.cell(atColumnIndex: 0, rowIndex: b).contentView is NSTextField {
            problems.append("the box has a label")
        }
    } else {
        problems.append("the controls are not grid cells")
    }
    for control in [controls.layoutPopup, controls.cutoutCheckbox] as [NSControl] {
        expect(&problems, "action", control.action.map { NSStringFromSelector($0) } ?? "nil",
               "controlChanged:")
        if (control.target as AnyObject?) !== panel { problems.append("target") }
    }
    row("Q1", problems, "\"Layout:\" (Corner, Rounded Corner, Circle, Side by Side, Camera Full) "
        + "and the Remove-background box after the preview and before Microphone, each "
        + "controlChanged:")
}

// MARK: - Q2: the keys

do {
    var problems: [String] = []
    for key in landingKeys { UserDefaults.standard.removeObject(forKey: key) }
    choose(.cameraFull)
    cutout(true)
    for key in landingKeys { UserDefaults.standard.removeObject(forKey: key) }
    panel.restoreChoices()
    expect(&problems, "absent keys read", [controls.layout.rawValue,
                                            "\(controls.cutoutCheckbox.state == .on)"],
           ["corner_square", "false"])
    UserDefaults.standard.set("corner_square_and_more", forKey: RecorderPanelController.cameraLayoutKey)
    choose(.cornerCircle)
    UserDefaults.standard.set("corner_square_and_more", forKey: RecorderPanelController.cameraLayoutKey)
    panel.restoreChoices()
    expect(&problems, "a stale layout reads", controls.layout.rawValue, "corner_square")
    choose(.sideBySide)
    expect(&problems, "a layout change writes", storedLanding()[0], "side_by_side")
    cutout(true)
    expect(&problems, "a cutout change writes", storedLanding()[1], "1")
    pick(displayRow())
    expect(&problems, "another control's change keeps them", storedLanding(), ["side_by_side", "1"])
    UserDefaults.standard.set("corner_rounded", forKey: RecorderPanelController.cameraLayoutKey)
    UserDefaults.standard.set(false, forKey: RecorderPanelController.cameraCutoutKey)
    panel.restoreChoices()
    expect(&problems, "stored values restore",
           [controls.layout.rawValue, "\(controls.cutoutCheckbox.state == .on)"],
           ["corner_rounded", "false"])
    for key in landingKeys { UserDefaults.standard.removeObject(forKey: key) }
    panel.restoreChoices()
    row("Q2", problems, "absent keys read corner_square and off, a stale layout corner_square; "
        + "each change writes; stored values restore")
}

// MARK: - Q3: the enabling and the choice's gates

do {
    var problems: [String] = []
    pick(displayRow())
    tickBeside(false)
    choose(.sideBySide)
    cutout(true)
    panel.syncControlsEnabled()
    expect(&problems, "display, no camera: enabled",
           [controls.layoutPopup.isEnabled, controls.cutoutCheckbox.isEnabled], [false, false])
    var choice = panel.currentChoice()
    expect(&problems, "display, no camera: choice",
           [choice.cameraLayout.rawValue, "\(choice.cameraCutout)"], ["corner_square", "false"])
    expect(&problems, "greyed keep their values",
           [controls.layout.rawValue, "\(controls.cutoutCheckbox.state == .on)"],
           ["side_by_side", "true"])
    tickBeside(true)
    expect(&problems, "display, camera too: enabled",
           [controls.layoutPopup.isEnabled, controls.cutoutCheckbox.isEnabled], [true, true])
    choice = panel.currentChoice()
    expect(&problems, "display, camera too: choice",
           [choice.cameraLayout.rawValue, "\(choice.cameraCutout)"], ["side_by_side", "true"])
    cutout(false)
    choice = panel.currentChoice()
    expect(&problems, "the box off: choice", "\(choice.cameraCutout)", "false")
    cutout(true)
    for (name, tag) in [("Microphone Only", RecorderPanelController.voiceOverTag),
                        ("Camera", RecorderPanelController.cameraTag)] {
        panel.sourcePopup.selectItem(withTag: tag)
        panel.refreshSizeNote()
        panel.syncControlsEnabled()
        expect(&problems, "\(name): enabled",
               [controls.layoutPopup.isEnabled, controls.cutoutCheckbox.isEnabled],
               [false, false])
        choice = panel.currentChoice()
        expect(&problems, "\(name): choice",
               [choice.cameraLayout.rawValue, "\(choice.cameraCutout)"],
               ["corner_square", "false"])
    }
    pick(displayRow())
    panel.phase = .countdown(3)
    panel.syncControlsEnabled()
    expect(&problems, "counting down: enabled",
           [controls.layoutPopup.isEnabled, controls.cutoutCheckbox.isEnabled], [false, false])
    panel.phase = .idle
    panel.syncControlsEnabled()
    expect(&problems, "idle again: enabled",
           [controls.layoutPopup.isEnabled, controls.cutoutCheckbox.isEnabled], [true, true])
    tickBeside(false)
    row("Q3", problems, "live only idle with Record the camera too beside a screen source; "
        + "greyed keep their values; applyCameraLanding gives corner_square and off otherwise")
}
putBack(originals)

// MARK: - Q4: the tools' refusals

do {
    var problems: [String] = []
    let server = AgentServer.shared
    func said(_ body: () throws -> String) -> String {
        do {
            return "ok: " + (try body())
        } catch let error as AgentServer.ToolError {
            return error.message
        } catch {
            return "\(error)"
        }
    }
    func kind(_ a: [String: Any]) -> String { said { try server.recordingSourceKind(a).rawValue } }
    func landing(_ a: [String: Any], place: Bool) -> String {
        said {
            let got = try server.recordingCameraLanding(a, place: place)
            return "\(got.layout.rawValue),\(got.cutout)"
        }
    }
    let voice = " cannot be given — a voice-over records the microphone alone."
    let beside = " needs camera — name the camera to record beside the screen."
    let alone = " cannot be given — a camera recording records the camera alone, at the camera's "
        + "own format."
    let kinds: [(String, [String: Any], String)] = [
        ("voice_over, camera_layout", ["source": "voice_over", "camera_layout": "side_by_side"],
         "With source voice_over, camera_layout" + voice),
        ("voice_over, all four",
         ["source": "voice_over", "camera": "x", "camera_format": "best",
          "camera_layout": "corner_square", "camera_cutout": false],
         "With source voice_over, camera, camera_format, camera_layout, camera_cutout" + voice),
        ("voice_over, null layout", ["source": "voice_over", "camera_layout": NSNull()],
         "ok: voice_over"),
        ("screen, camera_layout alone", ["camera_layout": "side_by_side"],
         "With source screen, camera_layout" + beside),
        ("screen, camera_cutout alone", ["camera_cutout": true],
         "With source screen, camera_cutout" + beside),
        ("screen, camera_cutout false alone", ["camera_cutout": false],
         "With source screen, camera_cutout" + beside),
        ("screen, format and layout alone", ["camera_format": "best", "camera_layout": "camera_full"],
         "With source screen, camera_format" + beside),
        ("screen with camera", ["camera": "x", "camera_layout": "camera_full", "camera_cutout": true],
         "ok: screen"),
        ("camera, camera_layout", ["source": "camera", "camera_layout": "side_by_side"],
         "With source camera, camera_layout" + alone),
        ("camera, cutout and rate", ["source": "camera", "rate": 30, "camera_cutout": true],
         "With source camera, camera_cutout, rate" + alone),
        ("camera, speed_up_typing before both",
         ["source": "camera", "camera_cutout": true, "speed_up_typing": true,
          "camera_layout": "corner_circle"],
         "With source camera, speed_up_typing, camera_layout, camera_cutout" + alone),
    ]
    for (name, a, want) in kinds { expect(&problems, name, kind(a), want) }
    let layoutPlace = "camera_layout lays out the landed camera clips, so it needs place: true."
    let cutoutPlace =
        "camera_cutout: true removes the landed camera clips' background, so it needs place: true."
    let landings: [(String, [String: Any], Bool, String)] = [
        ("none", [:], true, "ok: corner_square,false"),
        ("none, place false", [:], false, "ok: corner_square,false"),
        ("both, place true", ["camera_layout": "camera_full", "camera_cutout": true], true,
         "ok: camera_full,true"),
        ("layout, place false", ["camera_layout": "corner_square"], false, layoutPlace),
        ("cutout true, place false", ["camera_cutout": true], false, cutoutPlace),
        ("cutout false, place false", ["camera_cutout": false], false, "ok: corner_square,false"),
        ("both, place false (layout first)",
         ["camera_layout": "side_by_side", "camera_cutout": true], false, layoutPlace),
    ]
    for (name, a, place, want) in landings { expect(&problems, name, landing(a, place: place), want) }
    let unknown = landing(["camera_layout": "stacked"], place: true)
    if unknown.hasPrefix("ok") || !unknown.contains("corner_square") || !unknown.contains("camera_full") {
        problems.append("an unknown layout: \(unknown)")
    }
    #if FRAMEJOB_DEV_TOOLS
    func land(_ a: [String: Any], movie: String?, place: Bool = true) -> String {
        said {
            let got = try server.landRecordingCamera(a, movie: movie, place: place)
            return got == nil ? "none" : "camera"
        }
    }
    let without = " cannot be given without camera — it applies to the camera's clips."
    let lands: [(String, [String: Any], String?, Bool, String)] = [
        ("camera without movie", ["camera": "/no/camera.mov"], nil, true,
         "camera cannot be given without movie — a camera lands beside the screen segment's "
            + "movie."),
        ("camera_offset without camera", ["camera_offset": 2], "/no/movie.mov", true,
         "camera_offset" + without),
        ("camera_layout without camera", ["camera_layout": "side_by_side"], "/no/movie.mov", true,
         "camera_layout" + without),
        ("camera_cutout without camera", ["camera_cutout": false], "/no/movie.mov", true,
         "camera_cutout" + without),
        ("no camera", [:], "/no/movie.mov", true, "ok: none"),
        ("cutout with place false, before the probe",
         ["camera": "/no/camera.mov", "camera_cutout": true], "/no/movie.mov", false, cutoutPlace),
    ]
    for (name, a, movie, place, want) in lands {
        expect(&problems, "land_recording: " + name, land(a, movie: movie, place: place), want)
    }
    #else
    problems.append("built without FRAMEJOB_DEV_TOOLS: land_recording's refusals not reached")
    #endif
    row("Q4", problems, "CO-83's sentences, exact: the strangers with voice_over, screen without "
        + "camera and camera; the enum and the place sentences; land_recording's four")
}

// MARK: - The landing (Q6, Q7)

let second = Ticks(ReelTime.perSecond)
func media(_ name: String, seconds: Double, width: Int, height: Int) -> MediaDescriptor {
    MediaDescriptor(
        path: work.appendingPathComponent(name).path, kind: .video,
        duration: Ticks(Double(second) * seconds), width: width, height: height, fps: .thirty,
        hasVideo: true)
}
func segment(_ screen: MediaDescriptor, camera: MediaDescriptor?, offset: Ticks = 0)
    -> RecordingSegment
{
    RecordingSegment(
        descriptor: screen, micDescriptor: nil, micOffset: 0, startedAt: Date(),
        cameraDescriptor: camera, cameraOffset: offset)
}
func result(_ segments: [RecordingSegment], layout: RecordingCameraLayout) -> RecordingResult {
    var choice = RecordingChoice()
    choice.rate = 30
    choice.camera = "PROBE-ID"
    choice.cameraLayout = layout
    return RecordingResult(
        segments: segments, choice: choice, stoppedBy: .stopped, pauses: segments.count - 1,
        camera: RecordingCamera(name: "Probe Camera", format: "640x360@30"))
}
func landed(_ r: RecordingResult) throws -> ProjectSnapshot {
    let d = ProjectDocument()
    let p = try RecordingLanding.placement(r, in: d, place: true)
    d.performGroupedEdit(RecordingLanding.actionName, p.ops)
    let s = d.project.snapshot
    d.close()
    return s
}
func clip(_ s: ProjectSnapshot, _ file: MediaDescriptor) -> ClipSnapshot? {
    guard let id = s.media.first(where: { $0.path == file.path })?.id else { return nil }
    return s.clips.first {
        if case .media(let m, _, _) = $0.source { return m == id }
        return false
    }
}
func json(_ v: VideoProps?) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return v.flatMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        ?? "nil"
}
/// The `video` an `add_clip` of `file` alone gets on a fresh project's new track.
func twin(_ file: MediaDescriptor) -> String {
    var p = ProjectDocument().project
    guard let withMedia = try? p.applying(ReelOp.addMedia(descriptor: file)).project,
        let id = withMedia.snapshot.media.last?.id
    else { return "no media" }
    p = withMedia
    let track = p.snapshot.nextId
    guard let withTrack = try? p.applying(ReelOp.addTrack(index: 0)).project,
        let placed = try? withTrack.applying(ReelOp.addClip(track: track, media: id, at: 0)).project
    else { return "no clip" }
    return json(placed.snapshot.clips.first?.video)
}
func actions(_ c: ClipSnapshot?) -> [String] {
    c?.actions.map { "\($0.start)+\($0.duration)" } ?? ["no clip"]
}
let frame = Fps.thirty.frameDuration

// Q6: two segments in side_by_side, the second with no camera file.
do {
    var problems: [String] = []
    let (screen1, screen2) = (
        media("q6-screen1.mov", seconds: 2, width: 1920, height: 1080),
        media("q6-screen2.mov", seconds: 2, width: 1920, height: 1080)
    )
    let camera1 = media("q6-camera1.mov", seconds: 1, width: 640, height: 360)
    let s = try landed(result(
        [segment(screen1, camera: camera1), segment(screen2, camera: nil)], layout: .sideBySide))
    let (pic1, pic2, cam1) = (clip(s, screen1), clip(s, screen2), clip(s, camera1))
    expect(&problems, "camera 1's actions", actions(cam1), ["0+\(frame)"])
    expect(&problems, "screen 1's actions", actions(pic1), ["0+\(frame)"])
    if json(pic1?.video) == twin(screen1) { problems.append("screen 1 was not laid out") }
    expect(&problems, "screen 2's actions", actions(pic2), [String]())
    expect(&problems, "screen 2's video", json(pic2?.video), twin(screen2))
    row("Q6", problems, "segment 1's camera and screen laid out with one one-frame action each; "
        + "segment 2's screen, with no camera, kept an add_clip twin's video and no action")
} catch {
    row("Q6", ["the landing threw: \(error.localizedDescription)"], "")
}

// Q7: a +3 frame offset, then a screen the previous camera overruns.
do {
    var problems: [String] = []
    let screen = media("q7-screen.mov", seconds: 2, width: 1920, height: 1080)
    let camera = media("q7-camera.mov", seconds: 1, width: 640, height: 360)
    let s = try landed(result([segment(screen, camera: camera, offset: 3 * frame)],
                              layout: .sideBySide))
    let (pic, cam) = (clip(s, screen), clip(s, camera))
    expect(&problems, "+3 frames: the camera's start", (cam?.start ?? -1) - (pic?.start ?? 0),
           3 * frame)
    expect(&problems, "+3 frames: the screen's video", json(pic?.video), twin(screen))
    expect(&problems, "+3 frames: the screen's actions", actions(pic), ["\(3 * frame)+\(frame)"])
    expect(&problems, "+3 frames: the camera's actions", actions(cam), ["0+\(frame)"])
    row("Q7a", problems, "")
} catch {
    row("Q7a", ["the +3 frame landing threw: \(error.localizedDescription)"], "")
}
do {
    var problems: [String] = []
    let screen1 = media("q7-screen1.mov", seconds: 2, width: 1920, height: 1080)
    let screen2 = media("q7-screen2.mov", seconds: 1, width: 1920, height: 1080)
    let camera1 = media("q7-camera1.mov", seconds: 4, width: 640, height: 360)
    let camera2 = media("q7-camera2.mov", seconds: 4, width: 640, height: 360)
    let s = try landed(result(
        [segment(screen1, camera: camera1), segment(screen2, camera: camera2)],
        layout: .cornerSquare))
    let (pic2, cam1, cam2) = (clip(s, screen2), clip(s, camera1), clip(s, camera2))
    let (cw, ch) = (Double(s.canvas.width), Double(s.canvas.height))
    // CAM-10 (3)'s corner, written out here from the decision's own formula.
    let scale = min(max(min(0.25 * cw / 640, ch / (3 * 360)), 0.01), 10)
    let want = [(cw / 2 - 0.05 * cw - 640 * scale / 2).rounded(),
                (ch / 2 - 0.05 * ch - 360 * scale / 2).rounded(), scale]
    if !((cam2?.start ?? 0) >= (pic2?.end ?? .max)) {
        problems.append("camera 2 at \(cam2?.start ?? -1) is not past screen 2's end \(pic2?.end ?? -1)")
    }
    expect(&problems, "the fallback's x, y, scale",
           cam2?.video.map { [$0.x, $0.y, $0.scale] } ?? [], want)
    expect(&problems, "the fallback's actions", actions(cam2), [String]())
    expect(&problems, "camera 1's actions", actions(cam1), ["0+\(frame)"])
    row("Q7b", problems, "")
} catch {
    row("Q7b", ["the overrun landing threw: \(error.localizedDescription)"], "")
}
if let a = rows.firstIndex(where: { $0["id"] as? String == "Q7a" }),
    let b = rows.firstIndex(where: { $0["id"] as? String == "Q7b" })
{
    let both = [rows[a], rows[b]]
    let problems = both.compactMap { ($0["pass"] as? Bool) == true ? nil : $0["detail"] as? String }
    rows.removeAll { ["Q7a", "Q7b"].contains($0["id"] as? String ?? "") }
    row("Q7", problems, "+3 frames: the screen kept its twin's video with one one-frame action at "
        + "3 frames, the camera one at 0; an overrun screen's camera landed at cornerPatch's x, y "
        + "and scale with no action, and the landing did not throw")
}

putBack(originals)
finish()
