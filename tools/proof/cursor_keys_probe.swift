// Road map creator-jobs CU6 — record shortcuts, the rows no grant is needed for (spec §11
// CU-60…CU-63): Input Monitoring's step table, URL and sentences (Y1), the status item's
// titles, menus and lengths with and without the keyboard mark (Y2), `CursorKeyFilter` over
// synthetic key-downs (Y6), `CursorSegments` fed keys into a file the core accepts (Y7), and
// the recorder panel's Record shortcuts box and press under a spy (Y8).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// against `libframejob_core.a`, through `swift_build.py`:
//
//   cursor_keys_probe <work dir>
//
// The panel is `RecorderPanelController.shared`, NEVER shown, under a spy's grant doors: no
// prompt, no System Settings, no camera or microphone opens (the fake microphone id finds no
// device), and the twelve `FrameJobRecording…` values and `FrameJobInputMonitoringAsked` are
// put back as they were. The answer is one JSON object on stdout, `{"rows": [...]}`, each row
// `{"id", "pass", "detail"}`; `cursor_keys_probe.py` prints and scores them (Y9 is its own,
// read from the sources).
import AppKit
import AVFoundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: cursor_keys_probe <work dir>\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

var rows: [[String: Any]] = []
func row(_ id: String, _ problems: [String], _ detail: String) {
    rows.append(["id": id, "pass": problems.isEmpty,
                 "detail": problems.isEmpty ? detail : problems.joined(separator: "; ")])
}

func expect(_ problems: inout [String], _ what: String, _ got: Any, _ want: Any) {
    if "\(got)" != "\(want)" { problems.append("\(what): got \(got), want \(want)") }
}

// MARK: - Y1: Input Monitoring's step table, URL and sentences

do {
    var problems: [String] = []
    for granted in [false, true] {
        for asked in [false, true] {
            for launchd in [false, true] {
                let im = RecordingGrant.inputMonitoringStep(
                    granted: granted, asked: asked, launchedByLaunchd: launchd)
                let screen = RecordingGrant.screenStep(
                    granted: granted, asked: asked, launchedByLaunchd: launchd)
                expect(&problems, "step(\(granted), \(asked), \(launchd))", im, screen)
            }
        }
    }
    let url = RecordingGrant.inputMonitoringPaneURL?.absoluteString ?? "nil"
    if !url.hasSuffix("Privacy_ListenEvent") || !url.hasPrefix("x-apple.systempreferences:") {
        problems.append("pane URL \(url)")
    }
    let cu3 = "Input Monitoring is not granted to Frame Job. Turn it on in System Settings ▸ "
        + "Privacy & Security ▸ Input Monitoring."
    expect(&problems, "pane sentence", RecordingGrant.inputMonitoringPaneSentence, cu3)
    expect(&problems, "refusal", RecordingGrant.inputMonitoringRefusal,
           cu3 + RecordingGrant.launchClause)
    if RecordingGrant.inputMonitoringRefusal.contains("relaunch Frame Job") {
        problems.append("the refusal says relaunch (CU0b: not needed)")
    }
    let add = " If Frame Job is not in its list, add it with +."
    expect(&problems, "add sentence", RecordingGrant.inputMonitoringAddSentence, add)
    expect(&problems, "note opened", RecordingGrant.inputMonitoringNote(opened: true),
           cu3 + add + RecordingGrant.paneOpenedSentence + RecordingGrant.launchClause)
    expect(&problems, "note not opened", RecordingGrant.inputMonitoringNote(opened: false),
           cu3 + add + RecordingGrant.launchClause)
    row("Y1", problems, "inputMonitoringStep is screenStep over 8 inputs; \(url); CU-3's sentence")
}

// MARK: - Y2: the status item's titles, menus and lengths

func attributes(_ title: NSAttributedString) -> [[String: String]] {
    var out: [[String: String]] = []
    title.enumerateAttributes(in: NSRange(location: 0, length: title.length)) { attrs, range, _ in
        let text = (title.string as NSString).substring(with: range)
        let color = (attrs[.foregroundColor] as? NSColor).map { "\($0)" } ?? "none"
        let font = (attrs[.font] as? NSFont)?.fontName ?? "none"
        out.append(["text": text, "color": color, "font": font])
    }
    return out
}

do {
    var problems: [String] = []
    expect(&problems, "keysGlyph", RecorderStatusItem.keysGlyph, "⌨\u{FE0E}")
    expect(&problems, "keysRow", RecorderStatusItem.keysRow, "Recording keyboard shortcuts")
    for paused in [false, true] {
        let mark = paused ? RecorderStatusItem.pauseGlyph : "●"
        let plain = RecorderStatusItem.title(elapsed: 61.9, paused: paused)
        let off = RecorderStatusItem.title(elapsed: 61.9, paused: paused, keys: false)
        let on = RecorderStatusItem.title(elapsed: 61.9, paused: paused, keys: true)
        expect(&problems, "keys false = the old title (paused \(paused))", off.isEqual(plain), true)
        expect(&problems, "old string (paused \(paused))", plain.string, "\(mark) 1:01")
        expect(&problems, "keyed string (paused \(paused))", on.string,
               "\(mark) \(RecorderStatusItem.keysGlyph) 1:01")
        let runs = attributes(on)
        let glyph = runs.first { $0["text"]?.contains(RecorderStatusItem.keysGlyph) == true }
        expect(&problems, "glyph colour (paused \(paused))", glyph?["color"] ?? "missing", "none")
        let markRun = attributes(plain).first?["color"] ?? "none"
        expect(&problems, "mark colour kept (paused \(paused))", runs.first?["color"] ?? "none",
               markRun)
    }
    expect(&problems, "menuTitles(paused: false)", RecorderStatusItem.menuTitles(paused: false),
           ["Pause Recording", "Stop Recording"])
    expect(&problems, "menuTitles(paused: true)", RecorderStatusItem.menuTitles(paused: true),
           ["Resume Recording", "Stop Recording"])
    expect(&problems, "menuTitles(paused: false, keys: true)",
           RecorderStatusItem.menuTitles(paused: false, keys: true),
           ["Recording keyboard shortcuts", "Pause Recording", "Stop Recording"])
    expect(&problems, "menuTitles(paused: true, keys: true)",
           RecorderStatusItem.menuTitles(paused: true, keys: true),
           ["Recording keyboard shortcuts", "Resume Recording", "Stop Recording"])
    let inset = RecorderStatusItem.titleInset
    for keys in [false, true] {
        let length = RecorderStatusItem.itemLength(keys: keys)
        var widest: CGFloat = 0
        for paused in [false, true] {
            for elapsed in [0, 59, 61.9, 599, 3599, 3661, 35_999] as [TimeInterval] {
                let width = RecorderStatusItem.title(elapsed: elapsed, paused: paused, keys: keys)
                    .size().width
                if ceil(width) + 2 * inset > length + 1e-9 {
                    problems.append("keys \(keys) paused \(paused) \(elapsed) s needs "
                                    + "\(ceil(width) + 2 * inset) > \(length)")
                }
            }
            widest = max(widest, ceil(RecorderStatusItem.title(
                elapsed: RecorderStatusItem.widestElapsed, paused: paused, keys: keys)
                .size().width))
        }
        expect(&problems, "itemLength(keys: \(keys)) formula", length, widest + 2 * inset)
    }
    expect(&problems, "itemLength = itemLength(keys: false)", RecorderStatusItem.itemLength,
           RecorderStatusItem.itemLength(keys: false))
    if RecorderStatusItem.itemLength(keys: true) <= RecorderStatusItem.itemLength {
        problems.append("the keyed length is not wider than the plain one")
    }
    row("Y2", problems, "titles with and without ⌨︎, the menus, itemLength(keys:) "
        + "\(RecorderStatusItem.itemLength(keys: false)) / \(RecorderStatusItem.itemLength(keys: true))")
}

// MARK: - Y6: CursorKeyFilter over synthetic key-downs

struct Case {
    let name: String
    let event: CursorKeyEvent
    let want: CursorKeyEntry
}

func key(_ code: Int, _ mods: CursorKeyModifiers, _ character: String?, repeat r: Bool = false)
    -> CursorKeyEvent
{
    CursorKeyEvent(keyCode: code, modifiers: mods, isRepeat: r, character: character)
}

let cases: [Case] = [
    Case(name: "⌘⇧4", event: key(21, [.cmd, .shift], "4"), want: .shortcut(keys: "cmd+shift+4", code: 21)),
    Case(name: "⌃⌘Q", event: key(12, [.cmd, .ctrl], "q"), want: .shortcut(keys: "cmd+ctrl+q", code: 12)),
    Case(name: "⌥←", event: key(123, [.opt], "\u{F702}"), want: .shortcut(keys: "opt+left", code: 123)),
    Case(name: "⌥→", event: key(124, [.opt], "\u{F703}"), want: .shortcut(keys: "opt+right", code: 124)),
    Case(name: "⌥↓", event: key(125, [.opt], nil), want: .shortcut(keys: "opt+down", code: 125)),
    Case(name: "⌥↑", event: key(126, [.opt], nil), want: .shortcut(keys: "opt+up", code: 126)),
    Case(name: "⌥⇧Tab", event: key(48, [.opt, .shift], "\t"), want: .shortcut(keys: "opt+shift+tab", code: 48)),
    Case(name: "⌥⌫", event: key(51, [.opt], "\u{7F}"), want: .shortcut(keys: "opt+delete", code: 51)),
    Case(name: "⌥⌦", event: key(117, [.opt], nil), want: .shortcut(keys: "opt+forwarddelete", code: 117)),
    Case(name: "⌥Return", event: key(36, [.opt], "\r"), want: .shortcut(keys: "opt+return", code: 36)),
    Case(name: "⌥Enter", event: key(76, [.opt], "\u{3}"), want: .shortcut(keys: "opt+enter", code: 76)),
    Case(name: "⌥Esc", event: key(53, [.opt], "\u{1B}"), want: .shortcut(keys: "opt+esc", code: 53)),
    Case(name: "⌘+", event: key(69, [.cmd], "+"), want: .shortcut(keys: "cmd+plus", code: 69)),
    Case(name: "⌘F5", event: key(96, [.cmd], "\u{F708}"), want: .shortcut(keys: "cmd+f5", code: 96)),
    Case(name: "⌘S", event: key(1, [.cmd], "s"), want: .shortcut(keys: "cmd+s", code: 1)),
    Case(name: "⌘⇧Z (character Z)", event: key(6, [.cmd, .shift], "Z"), want: .shortcut(keys: "cmd+shift+z", code: 6)),
    Case(name: "⌃C", event: key(8, [.ctrl], "c"), want: .shortcut(keys: "ctrl+c", code: 8)),
    Case(name: "⌘⌥⌃⇧K", event: key(40, [.cmd, .ctrl, .opt, .shift], "k"), want: .shortcut(keys: "cmd+ctrl+opt+shift+k", code: 40)),
    Case(name: "⌘Space", event: key(49, [.cmd], " "), want: .shortcut(keys: "cmd+space", code: 49)),
    Case(name: "⌘ with no character", event: key(50, [.cmd], ""), want: .shortcut(keys: "cmd+key50", code: 50)),
    Case(name: "⌘ with a no-break space", event: key(10, [.cmd], "\u{A0}"), want: .shortcut(keys: "cmd+key10", code: 10)),
    Case(name: "⌘ with a control character", event: key(93, [.cmd], "\u{1C}"), want: .shortcut(keys: "cmd+key93", code: 93)),
    Case(name: "⌘⇧F19", event: key(80, [.cmd, .shift], nil), want: .shortcut(keys: "cmd+shift+f19", code: 80)),
    Case(name: "⇧A", event: key(0, [.shift], "a"), want: .typed),
    Case(name: "⌥E", event: key(14, [.opt], "e"), want: .typed),
    Case(name: "⌥⇧E", event: key(14, [.opt, .shift], "e"), want: .typed),
    Case(name: "⌥Space", event: key(49, [.opt], " "), want: .typed),
    Case(name: "bare a", event: key(0, [], "a"), want: .typed),
    Case(name: "bare 1", event: key(18, [], "1"), want: .typed),
    Case(name: "Return", event: key(36, [], "\r"), want: .typed),
    Case(name: "Tab", event: key(48, [], "\t"), want: .typed),
    Case(name: "← alone", event: key(123, [], nil), want: .typed),
    Case(name: "F5 alone", event: key(96, [], "\u{F708}"), want: .typed),
    Case(name: "⇧Return", event: key(36, [.shift], "\r"), want: .typed),
    Case(name: "repeat ⌘Z", event: key(6, [.cmd], "z", repeat: true), want: .typed),
    Case(name: "repeat ⌥←", event: key(123, [.opt], nil, repeat: true), want: .typed),
    Case(name: "repeat a", event: key(0, [], "a", repeat: true), want: .typed),
]

do {
    var problems: [String] = []
    var events = 0
    for c in cases {
        events += 1
        let got = CursorKeyFilter.entry(for: c.event, secure: false)
        expect(&problems, c.name, got, c.want)
        let shortcut: Bool
        if case .shortcut = c.want { shortcut = true } else { shortcut = false }
        expect(&problems, "\(c.name) isShortcut", CursorKeyFilter.isShortcut(c.event), shortcut)
        events += 1
        expect(&problems, "\(c.name) under secure input",
               CursorKeyFilter.entry(for: c.event, secure: true), CursorKeyEntry.none)
    }
    if events < 40 { problems.append("only \(events) events") }
    // The flags' four modifiers, and a real key-down read with no character.
    let flags: CGEventFlags = [.maskCommand, .maskShift, .maskAlphaShift, .maskSecondaryFn]
    expect(&problems, "modifiers from flags", CursorKeyModifiers(flags: flags), [.cmd, .shift] as CursorKeyModifiers)
    expect(&problems, "⌃⌥ from flags", CursorKeyModifiers(flags: [.maskControl, .maskAlternate]),
           [.ctrl, .opt] as CursorKeyModifiers)
    if let cg = CGEvent(keyboardEventSource: nil, virtualKey: 21, keyDown: true) {
        cg.flags = [.maskCommand, .maskShift]
        let read = CursorCapture.keyEvent(from: cg)
        expect(&problems, "keyEvent(from:)", read,
               CursorKeyEvent(keyCode: 21, modifiers: [.cmd, .shift], isRepeat: false, character: nil))
        cg.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        expect(&problems, "keyEvent(from:) repeat", CursorCapture.keyEvent(from: cg).isRepeat, true)
    } else {
        problems.append("no keyboard CGEvent")
    }
    row("Y6", problems, "\(events) events: \(cases.count) spelled or typed as CU-60 says, each "
        + "nothing under secure input")
}

// MARK: - Y7: CursorSegments fed keys, a body the core accepts

func start() -> CursorSegmentStart {
    CursorSegmentStart(inPicture: true, source: .display, displayID: 1,
                       sourceFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                       pointSize: CGSize(width: 1512, height: 982), pixelsPerPoint: 2,
                       contentSize: CursorPixelSize(width: 3024, height: 1964), cursorImage: .none,
                       geometry: CursorGeometry(
                           screenRect: CGRect(x: 0, y: 0, width: 1512, height: 982),
                           contentRect: CGRect(x: 0, y: 0, width: 1512, height: 982),
                           contentScale: 1, scaleFactor: 2))
}

func object(_ data: Data?) -> [String: Any]? {
    data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
}

func column(_ body: [String: Any]?, _ path: [String]) -> [String] {
    var value: Any? = body
    for key in path { value = (value as? [String: Any])?[key] }
    return (value as? [Any])?.map { "\($0)" } ?? []
}

do {
    var problems: [String] = []
    var segments = CursorSegments()
    let movie = CursorPixelSize(width: 3024, height: 1964)
    segments.open(0, start: start(), host: 10)
    segments.poll(CGPoint(x: 100, y: 100), host: 10.1)
    // Through the filter, as the tap feeds it: two shortcuts, three typed marks, one secure.
    let fed: [(CursorKeyEvent, Bool, Double)] = [
        (key(21, [.cmd, .shift], "4"), false, 10.5),
        (key(123, [.opt], nil), false, 10.6),
        (key(0, [], nil), false, 10.7),
        (key(14, [.opt], nil), false, 10.8),
        (key(6, [.cmd], "z", repeat: true), false, 10.85),
        (key(1, [], nil), true, 10.9),
    ]
    for (event, secure, host) in fed {
        segments.key(CursorKeyFilter.entry(for: event, secure: secure), host: host)
    }
    segments.key(.none, host: 10.95)
    segments.end(0)
    segments.key(.typed, host: 11.0)
    segments.key(.shortcut(keys: "cmd+s", code: 1), host: 11.1)
    segments.open(1, start: start(), host: 12)
    segments.key(.typed, host: 12.25)
    let first = segments.close(0, movieSize: movie, anchor: CursorAnchor(kind: .e1, host: 10))
    let second = segments.close(1, movieSize: movie, anchor: CursorAnchor(kind: .e1, host: 12))
    for (name, data) in [("segment 0", first), ("segment 1", second)] {
        guard let data else {
            problems.append("\(name): no body")
            continue
        }
        do { _ = try ReelCursor(data: data) } catch {
            problems.append("\(name) refused by the core: "
                            + ((error as? ReelCoreError)?.message ?? "\(error)"))
        }
    }
    let a = object(first)
    expect(&problems, "segment 0 shortcut keys", column(a, ["keys", "shortcut", "keys"]),
           ["cmd+shift+4", "opt+left"])
    expect(&problems, "segment 0 shortcut code", column(a, ["keys", "shortcut", "code"]), ["21", "123"])
    expect(&problems, "segment 0 shortcut t", column(a, ["keys", "shortcut", "t"]), ["500000", "600000"])
    expect(&problems, "segment 0 typed t", column(a, ["keys", "typed", "t"]),
           ["700000", "800000", "850000"])
    let typed = ((a?["keys"] as? [String: Any])?["typed"] as? [String: Any])?.keys.sorted() ?? []
    expect(&problems, "segment 0 typed holds t alone", typed, ["t"])
    let b = object(second)
    expect(&problems, "segment 1 shortcuts (the paused keys dropped)",
           column(b, ["keys", "shortcut", "keys"]), [] as [String])
    expect(&problems, "segment 1 typed t", column(b, ["keys", "typed", "t"]), ["250000"])
    row("Y7", problems, "two shortcuts and three typed marks accepted by the core; the secure key, "
        + ".none and the paused keys wrote nothing")
}

// MARK: - Y8: the panel's box, its note and the press under a spy

final class Spy {
    var screenGranted = true
    var imGranted = false
    var asked = false
    var launchd = true
    var mic: AVAuthorizationStatus = .authorized
    var log: [String] = []
    var imRequests = 0
    var screenRequests = 0
    var remembered = 0
    var opened: [String] = []

    var doors: RecorderGrantDoors {
        RecorderGrantDoors(
            screenGranted: {
                self.log.append("screen")
                return self.screenGranted
            },
            launchedByLaunchd: { self.launchd },
            requestScreen: { self.screenRequests += 1 },
            screenAsked: { true },
            rememberScreenAsked: {},
            microphoneStatus: {
                self.log.append("microphone")
                return self.mic
            },
            requestMicrophone: { _ in },
            openSettings: { url in
                self.opened.append(url.absoluteString)
                return true
            },
            cameraStatus: {
                self.log.append("camera")
                return .authorized
            },
            requestCamera: { _ in },
            inputMonitoringGranted: {
                self.log.append("inputMonitoring")
                return self.imGranted
            },
            requestInputMonitoring: { self.imRequests += 1 },
            inputMonitoringAsked: { self.asked },
            rememberInputMonitoringAsked: {
                self.remembered += 1
                self.asked = true
            })
    }
}

/// Doors that read nothing true and ask nothing, for the time between rows.
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

do {
    var problems: [String] = []
    NSApplication.shared.setActivationPolicy(.prohibited)
    RecorderPanelController.grantDoors = sealed()
    let keys = [
        RecorderPanelController.displayKey, RecorderPanelController.microphoneKey,
        RecorderPanelController.systemAudioKey, RecorderPanelController.showClicksKey,
        RecorderPanelController.rateKey, RecorderPanelController.sizeKey,
        RecorderPanelController.includeFrameJobWindowsKey, RecorderPanelController.cameraKey,
        RecorderPanelController.cameraFormatKey, RecorderPanelController.cameraBesideKey,
        RecorderPanelController.enhanceMicrophoneKey, RecorderPanelController.keysKey,
        RecorderGrantDoors.inputMonitoringAskedKey,
    ]
    let originals = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer {
        for (key, value) in zip(keys, originals) {
            if let value { UserDefaults.standard.set(value, forKey: key) } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    UserDefaults.standard.set(false, forKey: RecorderPanelController.keysKey)
    UserDefaults.standard.set(false, forKey: RecorderPanelController.cameraBesideKey)
    let panel = RecorderPanelController.shared
    let box = panel.recordShortcutsCheckbox
    expect(&problems, "visible", panel.window?.isVisible ?? false, false)
    expect(&problems, "box title", box.title, "Record shortcuts")
    expect(&problems, "box off by default", box.state == .on, false)
    expect(&problems, "note", panel.recordShortcutsNote.stringValue,
           "Records each shortcut you press with ⌘ or ⌃, or ⌥ with an arrow, Delete, Return, "
               + "Tab or Esc, and when you type, never what you type. Nothing is recorded while "
               + "an app holds secure input.")
    expect(&problems, "note sentence", RecorderPanelController.recordShortcutsSentence,
           panel.recordShortcutsNote.stringValue)
    expect(&problems, "note font size", panel.recordShortcutsNote.font?.pointSize ?? 0, 11.0)
    let clicks = gridRow(of: panel.showClicksSwitch)
    expect(&problems, "box row", gridRow(of: box).map { "\($0)" } ?? "nil",
           clicks.map { "\($0 + 1)" } ?? "show clicks not in the grid")
    expect(&problems, "note row", gridRow(of: panel.recordShortcutsNote).map { "\($0)" } ?? "nil",
           clicks.map { "\($0 + 2)" } ?? "show clicks not in the grid")

    // The choice and the persistence.
    panel.selectDisplay(CGMainDisplayID())
    panel.microphonePopup.selectItem(at: 0)
    box.state = .on
    panel.controlChanged(box)
    expect(&problems, "keys with the box on", panel.currentChoice().keys, RecordingKeys.shortcuts)
    expect(&problems, "persisted on",
           UserDefaults.standard.object(forKey: RecorderPanelController.keysKey) as? Bool ?? false,
           true)
    box.state = .off
    panel.restoreChoices()
    expect(&problems, "restored on", box.state == .on, true)
    box.state = .off
    panel.controlChanged(box)
    expect(&problems, "keys with the box off", panel.currentChoice().keys, RecordingKeys.off)
    expect(&problems, "persisted off",
           UserDefaults.standard.object(forKey: RecorderPanelController.keysKey) as? Bool ?? true,
           false)
    box.state = .on
    panel.restoreChoices()
    expect(&problems, "restored off", box.state == .on, false)
    box.state = .on
    // Microphone Only and Camera: `.off`, the box greyed with its value kept.
    for (name, tag) in [("Microphone Only", RecorderPanelController.voiceOverTag),
                        ("Camera", RecorderPanelController.cameraTag)] {
        panel.sourcePopup.selectItem(withTag: tag)
        panel.syncControlsEnabled()
        expect(&problems, "\(name): keys", panel.currentChoice().keys, RecordingKeys.off)
        expect(&problems, "\(name): box enabled", box.isEnabled, false)
        expect(&problems, "\(name): box kept", box.state == .on, true)
    }
    panel.selectDisplay(CGMainDisplayID())
    panel.syncControlsEnabled()
    expect(&problems, "display: box enabled", box.isEnabled, true)
    expect(&problems, "display: keys", panel.currentChoice().keys, RecordingKeys.shortcuts)

    // The press, one spy per row; a fake microphone so its grant is read.
    let fake = NSMenuItem(title: "Probe Microphone", action: nil, keyEquivalent: "")
    fake.representedObject = "probe-mic"
    panel.microphonePopup.menu?.addItem(fake)
    panel.microphonePopup.select(fake)
    func reset() {
        panel.cancelCountdown()
        panel.phase = .idle
        panel.setNote("")
        RecorderPanelController.grantDoors = sealed()
    }
    func press(_ spy: Spy) {
        RecorderPanelController.grantDoors = spy.doors
        panel.record(nil)
    }
    let paneURL = RecordingGrant.inputMonitoringPaneURL?.absoluteString ?? "nil"
    let counting = "\(RecorderPanelController.Phase.countdown(RecorderPanelController.countdownSeconds))"

    // Granted: the order, and the countdown.
    reset()
    let granted = Spy()
    granted.imGranted = true
    press(granted)
    expect(&problems, "granted: order", granted.log, ["screen", "inputMonitoring", "microphone"])
    expect(&problems, "granted: phase", "\(panel.phase)", counting)
    expect(&problems, "granted: nothing asked or opened",
           "\(granted.imRequests) \(granted.opened)", "0 []")

    // Launchd, first press: one request, remembered, the pane opened, the note.
    reset()
    let first = Spy()
    press(first)
    expect(&problems, "first: requests", first.imRequests, 1)
    expect(&problems, "first: remembered", first.remembered, 1)
    expect(&problems, "first: opened", first.opened, [paneURL])
    expect(&problems, "first: note", panel.noteLabel.stringValue,
           RecordingGrant.inputMonitoringNote(opened: true))
    expect(&problems, "first: phase", "\(panel.phase)", "idle")
    expect(&problems, "first: microphone not read", first.log.contains("microphone"), false)
    expect(&problems, "first: order", first.log, ["screen", "inputMonitoring"])
    // The second press: no request, the pane again.
    reset()
    press(first)
    expect(&problems, "second: requests", first.imRequests, 1)
    expect(&problems, "second: opened", first.opened, [paneURL, paneURL])
    expect(&problems, "second: note", panel.noteLabel.stringValue,
           RecordingGrant.inputMonitoringNote(opened: true))
    // Shell-launched: a request every press, never remembered.
    reset()
    let shell = Spy()
    shell.launchd = false
    press(shell)
    reset()
    press(shell)
    expect(&problems, "shell: requests", shell.imRequests, 2)
    expect(&problems, "shell: remembered", shell.remembered, 0)
    expect(&problems, "shell: opened", shell.opened, [paneURL, paneURL])
    // Screen Recording absent: Input Monitoring is not reached.
    reset()
    let noScreen = Spy()
    noScreen.screenGranted = false
    press(noScreen)
    expect(&problems, "no screen grant: order", noScreen.log, ["screen"])
    // The box off: Input Monitoring never read.
    reset()
    box.state = .off
    let off = Spy()
    press(off)
    expect(&problems, "box off: order", off.log, ["screen", "microphone"])
    expect(&problems, "box off: phase", "\(panel.phase)", counting)
    reset()
    panel.microphonePopup.selectItem(at: 0)
    row("Y8", problems, "the box and its note under Show Clicks, persisted and restored, off and "
        + "greyed for Microphone Only and Camera; the press asks Screen → Input Monitoring → "
        + "Microphone, launchd asks once and opens the pane, a shell asks every press")
}

let answer = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
    ?? Data("{}".utf8)
FileHandle.standardOutput.write(answer)
exit(0)
