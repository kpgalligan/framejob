// Road map creator-jobs CU3c — the recorder stops burning the pointer, the rows no grant is needed
// for (spec §11 CU-31, CU-36): the recorder panel's Cursor row (P1), its default, Separate for
// every source (CU0d), and the Window row's early return (P2), its key (P3), its greying (P4),
// `RecordingCursor`'s table, Separate throughout (P5), the no-file sentences of a Separate
// segment (P6) and when a landing writes ripples and what a new project's remainder step is
// called then (P7).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// against `libframejob_core.a`, through `swift_build.py`:
//
//   cu3c_probe <work dir>
//
// The panel is `RecorderPanelController.shared`, NEVER shown, under doors that read nothing true
// and ask nothing: no prompt, no System Settings, no camera or microphone opens. The eighteen
// `FrameJobRecording…` values are put back as they were. The answer is one JSON object on stdout,
// `{"rows": [...]}`, each row `{"id", "pass", "detail"}`; `cu3c_probe.py` prints and scores them.
import AppKit
import AVFoundation
import ScreenCaptureKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: cu3c_probe <work dir>\n".utf8))
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

// MARK: - P5: the table, before the panel exists

do {
    var problems: [String] = []
    let table: [(String, RecordingSource, RecordingCursor)] = [
        ("display", .display(CGMainDisplayID()), .separate),
        ("window", .window(5), .separate),
        ("picked", .picked, .separate),
        ("voiceOver", .voiceOver, .separate),
        ("camera", .camera, .separate),
    ]
    for (name, source, want) in table {
        expect(&problems, "defaultFor(\(name))", RecordingCursor.defaultFor(source), want)
        var choice = RecordingChoice()
        choice.source = source
        expect(&problems, "effectiveCursor(\(name))", choice.effectiveCursor, want)
        choice.cursor = want == .separate ? .inPicture : .separate
        expect(&problems, "a choice beats the default (\(name))", choice.effectiveCursor,
               choice.cursor!)
    }
    expect(&problems, "windowDefault", RecordingCursor.windowDefault, RecordingCursor.separate)
    expect(&problems, "RecordingChoice().cursor", RecordingChoice().cursor.map { "\($0)" } ?? "nil",
           "nil")
    expect(&problems, "raw values", RecordingCursor.allCases.map(\.rawValue),
           ["separate", "in_picture"])
    row("P5", problems, "defaultFor: display, window, picked, voice-over and camera separate; "
        + "windowDefault separate; RecordingChoice().cursor nil; a choice beats the default")
}

// MARK: - P6: a Separate segment's no-file sentences

do {
    var problems: [String] = []
    let lost = " The pointer is not in the movie either: it was recorded Separate."
    expect(&problems, "cursorSeparateLost", ScreenRecorder.cursorSeparateLost, lost)
    let anchor = "The cursor file for M.mov was not written: the screen never reported its start, "
        + "so its times have nothing to count from."
    expect(&problems, "no anchor, in the picture",
           ScreenRecorder.cursorNoAnchorProblem(movieName: "M.mov", separate: false), anchor)
    expect(&problems, "no anchor, default", ScreenRecorder.cursorNoAnchorProblem(movieName: "M.mov"),
           anchor)
    expect(&problems, "no anchor, separate",
           ScreenRecorder.cursorNoAnchorProblem(movieName: "M.mov", separate: true), anchor + lost)
    let writer = "The cursor file for M.mov was not written: no cursor was captured for it."
    expect(&problems, "writer, in the picture",
           ScreenRecorder.cursorProblem(writer: writer, watchLost: "R", movieName: "M.mov",
                                        separate: false) ?? "nil", writer)
    expect(&problems, "writer, separate",
           ScreenRecorder.cursorProblem(writer: writer, watchLost: "R", movieName: "M.mov",
                                        separate: true) ?? "nil", writer + lost)
    let watch = ScreenRecorder.cursorProblem(writer: nil, watchLost: "R", movieName: "M.mov") ?? "nil"
    if !watch.hasPrefix("The cursor file for M.mov has only the geometry") {
        problems.append("watch-lost sentence: \(watch)")
    }
    expect(&problems, "watch lost, separate",
           ScreenRecorder.cursorProblem(writer: nil, watchLost: "R", movieName: "M.mov",
                                        separate: true) ?? "nil", watch)
    for separate in [false, true] {
        expect(&problems, "nil arm (\(separate))",
               ScreenRecorder.cursorProblem(writer: nil, watchLost: nil, movieName: "M.mov",
                                            separate: separate) ?? "nil", "nil")
    }
    row("P6", problems, "no anchor and the writer arm end with cursorSeparateLost for Separate and "
        + "are today's sentences In the picture; the watch-lost and nil arms unchanged")
}

// MARK: - P7: when the landing writes ripples, and the remainder step's name

do {
    var problems: [String] = []
    func result(_ source: RecordingSource, clicks: Bool, cursor: RecordingCursor?, mic: Bool)
        -> RecordingResult
    {
        var c = RecordingChoice()
        c.source = source
        c.showClicks = clicks
        c.cursor = cursor
        let movie = MediaDescriptor(path: "/nowhere/s.mov", kind: .video, duration: 600_000,
                                    hasAudio: false)
        let voice = MediaDescriptor(path: "/nowhere/s (Microphone).m4a", kind: .audio,
                                    duration: 600_000, hasAudio: true)
        return RecordingResult(
            segments: [RecordingSegment(descriptor: movie, micDescriptor: mic ? voice : nil,
                                        micOffset: 0, startedAt: Date())],
            choice: c, stoppedBy: .stopped, pauses: 0)
    }
    let display = RecordingSource.display(CGMainDisplayID())
    let cases: [(String, RecordingResult, Bool)] = [
        ("display, Show Clicks, default", result(display, clicks: true, cursor: nil, mic: false), true),
        ("display, Show Clicks, Separate", result(display, clicks: true, cursor: .separate, mic: false), true),
        ("display, Show Clicks, In the picture",
         result(display, clicks: true, cursor: .inPicture, mic: false), false),
        ("display, no Show Clicks", result(display, clicks: false, cursor: .separate, mic: false), false),
        ("picked, Show Clicks, default", result(.picked, clicks: true, cursor: nil, mic: false), true),
        ("voice-over, Show Clicks", result(.voiceOver, clicks: true, cursor: .separate, mic: false), false),
    ]
    for (name, r, want) in cases {
        expect(&problems, "wantsRipples(\(name))", RecordingLanding.wantsRipples(r), want)
    }
    expect(&problems, "ripplesActionName", RecordingLanding.ripplesActionName, "Cursor Clicks")
    expect(&problems, "one segment, no voice, no camera",
           RecordingLanding.remainderActionName(for: cases[0].1), "Cursor Clicks")
    expect(&problems, "one segment with a voice",
           RecordingLanding.remainderActionName(
               for: result(display, clicks: true, cursor: nil, mic: true)), "Add Microphone")
    row("P7", problems, "wantsRipples only with Show Clicks, Separate and a picture, a picked "
        + "window's default Separate included; a new project's remainder of ripples alone is \"Cursor Clicks\", with a voice \"Add Microphone\"")
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
let originals = keys.map { UserDefaults.standard.object(forKey: $0) }
UserDefaults.standard.set("", forKey: RecorderPanelController.cursorKey)
UserDefaults.standard.set(false, forKey: RecorderPanelController.cameraBesideKey)
let panel = RecorderPanelController.shared
let popup = panel.cursorPopup
func shown() -> String { popup.selectedItem?.representedObject as? String ?? "nil" }
func stored() -> String {
    UserDefaults.standard.string(forKey: RecorderPanelController.cursorKey) ?? "absent"
}
func choose(_ cursor: RecordingCursor) {
    if let item = popup.itemArray.first(where: { $0.representedObject as? String == cursor.rawValue }) {
        popup.select(item)
    }
    panel.controlChanged(popup)
}
func pick(_ item: NSMenuItem?) {
    guard let item else { return }
    panel.sourcePopup.select(item)
    panel.controlChanged(panel.sourcePopup)
}
func displayRow() -> NSMenuItem? { panel.sourcePopup.item(at: 0) }

// MARK: - P1: the row and its items

do {
    var problems: [String] = []
    expect(&problems, "visible", panel.window?.isVisible ?? false, false)
    expect(&problems, "titles", popup.itemArray.map(\.title), ["Separate", "In the picture"])
    expect(&problems, "represented", popup.itemArray.map { $0.representedObject as? String ?? "nil" },
           ["separate", "in_picture"])
    let clicks = gridRow(of: panel.showClicksSwitch)
    let audio = gridRow(of: panel.systemAudioSwitch)
    expect(&problems, "Cursor row", gridRow(of: popup).map { "\($0)" } ?? "nil",
           clicks.map { "\($0 - 1)" } ?? "show clicks not in the grid")
    expect(&problems, "after System Audio", audio.map { "\($0 + 1)" } ?? "nil",
           gridRow(of: popup).map { "\($0)" } ?? "nil")
    if let grid = popup.superview as? NSGridView, let r = gridRow(of: popup) {
        let label = grid.cell(atColumnIndex: 0, rowIndex: r).contentView as? NSTextField
        expect(&problems, "label", label?.stringValue ?? "nil", "Cursor:")
    } else {
        problems.append("the popup is not a grid cell")
    }
    expect(&problems, "popup's action", popup.action.map { NSStringFromSelector($0) } ?? "nil",
           "controlChanged:")
    row("P1", problems, "\"Cursor:\" with Separate and In the picture, between System Audio and "
        + "Show Clicks")
}

// MARK: - P2: never chosen, the popup follows the source

do {
    var problems: [String] = []
    UserDefaults.standard.set("", forKey: RecorderPanelController.cursorKey)
    panel.restoreChoices()
    pick(displayRow())
    expect(&problems, "display: chosen", panel.cursorChosen.map { "\($0)" } ?? "nil", "nil")
    expect(&problems, "display: shown", shown(), "separate")
    expect(&problems, "display: choice.cursor",
           panel.currentChoice().cursor.map { "\($0)" } ?? "nil", "nil")
    expect(&problems, "display: effective", panel.currentChoice().effectiveCursor,
           RecordingCursor.separate)
    // The Window row with a pick: `.picked`, whose default is Separate (CU0d). The popup is set to
    // In the picture by hand first, so only `refreshSizeNote()`'s sync puts it back.
    let window = panel.sourcePopup.menu?.item(withTag: RecorderPanelController.windowTag)
    panel.sourcePopup.select(window)
    panel.pickedFilter = SCContentFilter()
    if let item = popup.itemArray.first(where: { $0.representedObject as? String == "in_picture" }) {
        popup.select(item)
    }
    panel.refreshSizeNote()
    expect(&problems, "picked: source", "\(panel.currentChoice().source)", "\(RecordingSource.picked)")
    expect(&problems, "picked: shown", shown(), "separate")
    expect(&problems, "picked: effective", panel.currentChoice().effectiveCursor,
           RecordingCursor.separate)
    var tool = RecordingChoice()
    tool.source = .window(5)
    expect(&problems, "window: effective", tool.effectiveCursor, RecordingCursor.separate)
    // The Window row with no pick: `selectedScreen` nil, the source the main display.
    panel.pickedFilter = nil
    if let item = popup.itemArray.first(where: { $0.representedObject as? String == "in_picture" }) {
        popup.select(item)
    }
    panel.refreshSizeNote()
    expect(&problems, "Window row, no pick: selectedScreen",
           panel.selectedScreen == nil ? "nil" : "a screen", "nil")
    expect(&problems, "Window row, no pick: shown", shown(), "separate")
    pick(displayRow())
    expect(&problems, "back on a display: shown", shown(), "separate")
    row("P2", problems, "never chosen: a display, a picked window and a window show and record "
        + "Separate; refreshSizeNote() resyncs the picked row and the Window row's early return")
}

// MARK: - P3: the key

do {
    var problems: [String] = []
    pick(displayRow())
    panel.persistChoices()
    expect(&problems, "never chosen: key", stored(), "")
    choose(.inPicture)
    expect(&problems, "chosen: cursorChosen", panel.cursorChosen.map { "\($0)" } ?? "nil",
           "\(RecordingCursor.inPicture)")
    expect(&problems, "chosen: key", stored(), "in_picture")
    expect(&problems, "chosen: choice", panel.currentChoice().effectiveCursor, RecordingCursor.inPicture)
    pick(panel.sourcePopup.menu?.item(withTag: RecorderPanelController.voiceOverTag))
    pick(displayRow())
    expect(&problems, "after a source change: key", stored(), "in_picture")
    expect(&problems, "after a source change: shown", shown(), "in_picture")
    choose(.separate)
    expect(&problems, "separate chosen: key", stored(), "separate")
    UserDefaults.standard.set("in_picture", forKey: RecorderPanelController.cursorKey)
    panel.restoreChoices()
    expect(&problems, "restored in_picture", panel.cursorChosen.map { "\($0)" } ?? "nil",
           "\(RecordingCursor.inPicture)")
    for value in ["", "bogus"] {
        UserDefaults.standard.set(value, forKey: RecorderPanelController.cursorKey)
        panel.restoreChoices()
        expect(&problems, "restored \"\(value)\"", panel.cursorChosen.map { "\($0)" } ?? "nil", "nil")
    }
    panel.refreshSizeNote()
    panel.persistChoices()
    expect(&problems, "restored then persisted: key", stored(), "")
    row("P3", problems, "a pick writes FrameJobRecordingCursor and survives a source change; "
        + "never chosen writes \"\"; \"\" and \"bogus\" restore to nil")
}

// MARK: - P4: greyed for Microphone Only and Camera, the value kept

do {
    var problems: [String] = []
    pick(displayRow())
    choose(.inPicture)
    for (name, tag) in [("Microphone Only", RecorderPanelController.voiceOverTag),
                        ("Camera", RecorderPanelController.cameraTag)] {
        panel.sourcePopup.selectItem(withTag: tag)
        panel.refreshSizeNote()
        panel.syncControlsEnabled()
        expect(&problems, "\(name): enabled", popup.isEnabled, false)
        expect(&problems, "\(name): kept", shown(), "in_picture")
        expect(&problems, "\(name): choice.cursor",
               panel.currentChoice().cursor.map { "\($0)" } ?? "nil", "nil")
    }
    pick(displayRow())
    panel.syncControlsEnabled()
    expect(&problems, "display: enabled", popup.isEnabled, true)
    expect(&problems, "display: shown", shown(), "in_picture")
    expect(&problems, "display: choice", panel.currentChoice().effectiveCursor, RecordingCursor.inPicture)
    UserDefaults.standard.set("", forKey: RecorderPanelController.cursorKey)
    panel.restoreChoices()
    row("P4", problems, "greyed for Microphone Only and Camera with its value kept, nil in their "
        + "choice; live again on a display")
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
