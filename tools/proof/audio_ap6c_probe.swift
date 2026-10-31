import AVFoundation
import AppKit
import Foundation

// "Enhance the microphone when it lands" — the probe (road map "audio" AP6
// part 3, spec §11 AU-68, AU-69), compiled with app/Sources through
// swift_build. Argument: a scratch folder. Prints one "ok"/"FAIL" line per
// check, the row's name first (P1–P5), for audio_ap6c_probe.py to score.
// The panel is `RecorderPanelController.shared`, never shown, under grant
// doors that read and ask nothing; the eleven `FrameJobRecording…` values are
// put back as they were at the end.

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.prohibited)

let scratch = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func check(_ row: String, _ name: String, _ good: Bool, _ detail: String = "") {
    print((good ? "  ok   " : "  FAIL ") + row + " " + name + (detail.isEmpty ? "" : ": " + detail))
}

let panelKeys = [
    RecorderPanelController.displayKey, RecorderPanelController.microphoneKey,
    RecorderPanelController.systemAudioKey, RecorderPanelController.showClicksKey,
    RecorderPanelController.rateKey, RecorderPanelController.sizeKey,
    RecorderPanelController.includeFrameJobWindowsKey, RecorderPanelController.cameraKey,
    RecorderPanelController.cameraFormatKey, RecorderPanelController.cameraBesideKey,
    RecorderPanelController.enhanceMicrophoneKey,
]
let originals = panelKeys.map { UserDefaults.standard.object(forKey: $0) }
func putBack() {
    for (key, value) in zip(panelKeys, originals) {
        if let value { UserDefaults.standard.set(value, forKey: key) } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

// MARK: - P1 the panel's box

RecorderPanelController.grantDoors = RecorderGrantDoors(
    screenGranted: { false }, launchedByLaunchd: { true }, requestScreen: {},
    screenAsked: { true }, rememberScreenAsked: {}, microphoneStatus: { .denied },
    requestMicrophone: { _ in }, openSettings: { _ in true }, cameraStatus: { .denied },
    requestCamera: { _ in })
for key in panelKeys { UserDefaults.standard.removeObject(forKey: key) }
UserDefaults.standard.set(false, forKey: RecorderPanelController.cameraBesideKey)
let panel = RecorderPanelController.shared
let box = panel.enhanceMicrophoneCheckbox
let key = RecorderPanelController.enhanceMicrophoneKey
do {
    check("P1", "the box's title", box.title == "Enhance the microphone when it lands", box.title)
    check("P1", "the key is FrameJobRecordingEnhanceMicrophone",
          key == "FrameJobRecordingEnhanceMicrophone", key)
    let grid = box.superview as? NSGridView
    let boxRow = grid?.cell(for: box)?.row.map { grid!.index(of: $0) } ?? -1
    let micRow = panel.microphonePopup.superview.flatMap { stack in
        grid?.cell(for: stack)?.row.map { grid!.index(of: $0) }
    } ?? -2
    let label = grid.flatMap { boxRow >= 0 ? $0.cell(atColumnIndex: 0, rowIndex: boxRow).contentView : nil }
    check("P1", "its row is directly under Microphone, with no label",
          grid != nil && boxRow == micRow + 1 && !(label is NSTextField),
          "box row \(boxRow), microphone row \(micRow), label \(String(describing: label))")
    check("P1", "the box's tooltip names the step Enhance Voice",
          (box.toolTip ?? "").contains("\"Enhance Voice\""), box.toolTip ?? "nil")

    // Absent → off.
    box.state = .on
    UserDefaults.standard.removeObject(forKey: key)
    panel.restoreChoices()
    check("P1", "an absent key restores off", box.state == .off, "\(box.state.rawValue)")
    // Persist and restore.
    box.state = .on
    panel.persistChoices()
    let wroteOn = UserDefaults.standard.object(forKey: key) as? Bool
    box.state = .off
    panel.restoreChoices()
    let restoredOn = box.state == .on
    box.state = .off
    panel.persistChoices()
    let wroteOff = UserDefaults.standard.object(forKey: key) as? Bool
    box.state = .on
    panel.restoreChoices()
    check("P1", "persistChoices writes the box and restoreChoices reads it back",
          wroteOn == true && restoredOn && wroteOff == false && box.state == .off,
          "wrote \(String(describing: wroteOn)), restored on \(restoredOn), wrote "
            + "\(String(describing: wroteOff)), restored \(box.state.rawValue)")

    // Greyed with Off, its value kept; live with a microphone on any source.
    let fakeMic = NSMenuItem(title: "Probe Microphone", action: nil, keyEquivalent: "")
    fakeMic.representedObject = "probe-mic"
    panel.microphonePopup.menu?.addItem(fakeMic)
    let fakeCamera = NSMenuItem(title: "Probe Camera", action: nil, keyEquivalent: "")
    fakeCamera.representedObject = "probe-camera"
    panel.cameraPopup.menu?.addItem(fakeCamera)
    panel.cameraPopup.select(fakeCamera)
    func source(_ tag: Int?) {
        if let tag, let row = panel.sourcePopup.menu?.item(withTag: tag) {
            panel.sourcePopup.select(row)
        } else {
            panel.sourcePopup.selectItem(at: 0)
        }
        panel.controlChanged(panel.sourcePopup)
    }
    func microphone(_ on: Bool) {
        if on { panel.microphonePopup.select(fakeMic) } else { panel.microphonePopup.selectItem(at: 0) }
        panel.controlChanged(panel.microphonePopup)
    }
    source(nil)
    box.state = .on
    microphone(false)
    let offEnabled = box.isEnabled
    let offChoice = panel.currentChoice()
    check("P1", "Microphone Off greys the box, its value kept, and the choice is false",
          !offEnabled && box.state == .on && !offChoice.enhanceMicrophone,
          "enabled \(offEnabled), state \(box.state.rawValue), choice \(offChoice.enhanceMicrophone)")
    microphone(true)
    var live: [String: Bool] = [:]
    var chosen: [String: Bool] = [:]
    for (name, tag) in [("display", nil), ("voice-over", RecorderPanelController.voiceOverTag),
                        ("camera", RecorderPanelController.cameraTag)] as [(String, Int?)] {
        source(tag)
        live[name] = box.isEnabled
        chosen[name] = panel.currentChoice().enhanceMicrophone
    }
    check("P1", "a microphone makes the box live on every source, and the choice true",
          live.values.allSatisfy { $0 } && chosen.values.allSatisfy { $0 } && live.count == 3,
          "live \(live), choice \(chosen)")
    source(nil)
    box.state = .off
    panel.controlChanged(box)
    let unticked = panel.currentChoice().enhanceMicrophone
    check("P1", "unticked with a microphone, the choice is false", !unticked, "\(unticked)")
    box.state = .on
    panel.phase = .countdown(3)
    let countdownEnabled = box.isEnabled
    panel.phase = .recording
    let recordingEnabled = box.isEnabled
    panel.phase = .idle
    check("P1", "greyed while not idle, live again at idle",
          !countdownEnabled && !recordingEnabled && box.isEnabled && box.state == .on,
          "countdown \(countdownEnabled), recording \(recordingEnabled), idle \(box.isEnabled)")
}

// MARK: - P2 the voice's paths

let second: Ticks = 600_000
func file(_ name: String, video: Bool = false) -> MediaDescriptor {
    MediaDescriptor(path: "/nowhere/\(name)", kind: video ? .video : .audio, duration: 5 * second,
                    width: video ? 640 : 0, height: video ? 360 : 0, hasVideo: video, hasAudio: true)
}
func choice(_ source: RecordingSource, mic: Bool, enhance: Bool = true) -> RecordingChoice {
    var c = RecordingChoice()
    c.source = source
    c.microphone = mic ? "probe-mic" : nil
    c.enhanceMicrophone = enhance
    return c
}
do {
    let voiceOver = RecordingResult(
        segments: [file("a.m4a"), file("b.m4a")].map {
            RecordingSegment(descriptor: $0, micDescriptor: nil, micOffset: 0, startedAt: Date())
        }, choice: choice(.voiceOver, mic: true), stoppedBy: .stopped, pauses: 1)
    let vo = RecordingEnhance.voicePaths(of: voiceOver)
    check("P2", "a voice-over's files", vo == ["/nowhere/a.m4a", "/nowhere/b.m4a"], "\(vo)")

    let screen = RecordingResult(
        segments: [
            RecordingSegment(descriptor: file("m1.mov", video: true), micDescriptor: file("m1 (Microphone).m4a"),
                             micOffset: 0, startedAt: Date(),
                             cameraDescriptor: file("m1 (Camera).mov", video: true)),
            RecordingSegment(descriptor: file("m2.mov", video: true), micDescriptor: nil, micOffset: 0,
                             startedAt: Date(), micProblem: "it stopped"),
        ],
        choice: choice(.display(CGMainDisplayID()), mic: true), stoppedBy: .stopped, pauses: 2,
        unreadable: [UnreadableSegment(moviePath: "/nowhere/m3.mov", keptFiles: [],
                                       error: .timedOut, micDescriptor: file("m3 (Microphone).m4a"),
                                       position: 2)])
    let sp = RecordingEnhance.voicePaths(of: screen)
    check("P2", "a screen recording's microphone files and a left-out segment's, never a movie or "
            + "the camera",
          sp == ["/nowhere/m1 (Microphone).m4a", "/nowhere/m3 (Microphone).m4a"], "\(sp)")

    let silent = RecordingResult(
        segments: [RecordingSegment(descriptor: file("q.mov", video: true), micDescriptor: nil,
                                    micOffset: 0, startedAt: Date())],
        choice: choice(.display(CGMainDisplayID()), mic: false), stoppedBy: .stopped, pauses: 0)
    let np = RecordingEnhance.voicePaths(of: silent)
    check("P2", "none without a microphone", np.isEmpty, "\(np)")
}

// MARK: - P3 decide

do {
    typealias Row = (clips: [UInt32], analysed: Bool, busy: Bool, elapsed: Double,
                     want: RecordingEnhance.Step)
    let rows: [Row] = [
        ([], true, false, 0, .drop),
        ([], false, true, 400, .drop),
        ([7], true, false, 0, .enhance([7])),
        ([7, 9], true, false, 400, .enhance([7, 9])),
        ([7], true, true, 0, .wait),
        ([7], true, true, 299, .wait),
        ([7], true, true, 300, .giveUp),
        ([7], false, false, 0, .wait),
        ([7], false, false, 299, .wait),
        ([7], false, false, 300, .giveUp),
    ]
    var wrong: [String] = []
    for row in rows {
        let got = RecordingEnhance.decide(
            clips: row.clips, analysed: row.analysed, busy: row.busy, elapsed: row.elapsed)
        if got != row.want { wrong.append("\(row) → \(got)") }
    }
    check("P3", "decide's table: drop, then enhance, then give up at 300 s, else wait",
          wrong.isEmpty && RecordingEnhance.waitLimit == 300, wrong.joined(separator: "; "))
}

// MARK: - P4 record_screen's enhance

do {
    let server = AgentServer.shared
    func run(_ a: [String: Any], mic: Bool, place: Bool) -> String {
        do {
            return "\(try server.recordingEnhance(a, microphone: mic, place: place))"
        } catch let error as AgentServer.ToolError {
            return error.message
        } catch {
            return "\(error)"
        }
    }
    let micSentence = "enhance: true enhances the microphone's clip, so it needs microphone: true "
        + "(or source voice_over)."
    let placeSentence = "enhance: true needs place: true — with place: false the microphone lands "
        + "as media with no clip to enhance."
    let rows: [(String, [String: Any], Bool, Bool, String)] = [
        ("absent", [:], false, false, "false"),
        ("false", ["enhance": false], true, true, "false"),
        ("null", ["enhance": NSNull()], true, true, "false"),
        ("\"yes\"", ["enhance": "yes"], true, true, "enhance must be true or false."),
        ("true, no microphone", ["enhance": true], false, true, micSentence),
        ("true, place false", ["enhance": true], true, false, placeSentence),
        ("true, both wrong", ["enhance": true], false, false, micSentence),
        ("true", ["enhance": true], true, true, "true"),
    ]
    for (name, a, mic, place, want) in rows {
        let got = run(a, mic: mic, place: place)
        check("P4", "recordingEnhance \(name)", got == want, got)
    }
}

// MARK: - P5 the follow's end

/// A silent mono 48 kHz WAV of `seconds`.
func silentWAV(_ url: URL, seconds: Double) -> Bool {
    try? FileManager.default.removeItem(at: url)
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    guard let out = try? AVAudioFile(forWriting: url, settings: format.settings),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(48_000 * seconds))
    else { return false }
    buffer.frameLength = buffer.frameCapacity
    return (try? out.write(from: buffer)) != nil
}

final class ResultBox: @unchecked Sendable { var value = false }

do {
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let wav = scratch.appendingPathComponent("silent voice.wav")
    guard silentWAV(wav, seconds: 5) else {
        check("P5", "the silent fixture is written", false)
        putBack()
        exit(1)
    }
    let package = scratch.appendingPathComponent("follow.framejob", isDirectory: true)
    try? FileManager.default.removeItem(at: package)
    try? FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    let ticks = Int(5 * second)
    let project: [String: Any] = [
        "version": Int(RC_FORMAT_VERSION),
        "canvas": ["width": 320, "height": 180, "fps": [30, 1], "background": [0, 0, 0, 1],
                   "fit_new_clips": true, "timecode_frames": true],
        "media": [["id": 1, "path": wav.path, "kind": "audio", "duration": ticks,
                   "has_video": false, "has_audio": true, "speech": [[0, ticks]]]],
        "tracks": [["id": 2, "name": "Microphone"]],
        "clips": [["id": 3, "track": 2, "start": 0, "duration": ticks,
                   "source": ["kind": "media", "media": 1, "in": 0], "audio": [:]]],
        "markers": [], "next_id": 100, "nests": []]
    try! JSONSerialization.data(withJSONObject: project)
        .write(to: package.appendingPathComponent("project.json"))
    let document = ProjectDocument()
    do {
        try document.read(from: package, ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        check("P5", "the probe document opens", false, "\(error)")
        putBack()
        exit(1)
    }
    let media = document.project.snapshot.media[0]
    let cache = document.cacheDirectory!
    let done = DispatchSemaphore(value: 0)
    let measured = ResultBox()
    Task.detached {
        measured.value = await MediaImporter.loudness(
            for: media, url: wav, stamp: MediaImporter.CacheStamp.stamp(for: media, url: wav),
            into: cache)
        done.signal()
    }
    _ = done.wait(timeout: .now() + 60)

    func voiceOver(_ path: String) -> RecordingResult {
        RecordingResult(
            segments: [RecordingSegment(descriptor: MediaDescriptor(path: path, kind: .audio,
                                                                    duration: 5 * second, hasAudio: true),
                                        micDescriptor: nil, micOffset: 0, startedAt: Date())],
            choice: choice(.voiceOver, mic: true), stoppedBy: .stopped, pauses: 0)
    }

    // (a) `.drop`: a recording whose voice is in no clip.
    RecordingEnhance.follow(voiceOver("/nowhere/gone.m4a"), in: document)
    let dropTimer = RecordingEnhance.timer(of: document)
    let pendingBefore = RecordingEnhance.isPending(document)
    RecordingEnhance.tick(document)
    check("P5", "after .drop the follow has ended: not pending, its timer invalid",
          pendingBefore && !RecordingEnhance.isPending(document) && dropTimer?.isValid == false,
          "pending before \(pendingBefore), after \(RecordingEnhance.isPending(document)), timer "
            + "valid \(String(describing: dropTimer?.isValid))")

    // (b) `.enhance`: the silent voice, measured, in a document with its editor
    // window; Enhance refuses it (under −70 LUFS) at the inspector's foot.
    document.makeWindowControllers()
    var refusals: [String] = []
    let observer = NotificationCenter.default.addObserver(
        forName: .projectDocumentDidRefuse, object: document, queue: nil
    ) { note in
        if let refusal = note.userInfo?["refusal"] as? ReelRefusal {
            refusals.append(refusal.op + ": " + refusal.reason)
        }
    }
    let analysed = RecordingEnhance.isAnalysed([3], in: document)
    RecordingEnhance.follow(voiceOver(wav.path), in: document)
    let enhanceTimer = RecordingEnhance.timer(of: document)
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline, refusals.isEmpty {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    // Two more checks' worth of time: a follow still running would refuse again.
    RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    NotificationCenter.default.removeObserver(observer)
    check("P5", "after .enhance the follow has ended: not pending, its timer invalid, one refusal "
            + "of enhance_voice naming −70 LUFS",
          measured.value && analysed && !RecordingEnhance.isPending(document)
            && enhanceTimer?.isValid == false && refusals.count == 1
            && refusals.first?.hasPrefix("enhance_voice: Nothing could be enhanced.") == true
            && refusals.first?.contains("−70 LUFS") == true,
          "measured \(measured.value), analysed \(analysed), pending "
            + "\(RecordingEnhance.isPending(document)), timer valid "
            + "\(String(describing: enhanceTimer?.isValid)), refusals \(refusals)")
}

putBack()
exit(0)
