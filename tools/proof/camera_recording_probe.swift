// camera-recording CR1a (spec §11 CAM-3): the camera recorder's pure values,
// a camera result through the landing, and a real recording under the
// terminal's grant; CR1b (CAM-4): `record_screen`'s camera through the
// server's own functions (`tool`); CR1c (CAM-5): the recorder panel's Camera
// source (`panel`) and the countdown's prepared capture (granted G7–G9);
// CR2a (CAM-6): the camera's formats — the rows, the choice, the tool's
// `camera_format`, the panel's Format popup, and a recording at a chosen
// format (granted G10); CR2b (CAM-7): the preview's step, row and well
// (panel P13, P14), the preview layer on the prepared capture, #373's
// rebuilds, a tool start beside a prepared capture and a thrown prepare
// (granted G8 re-aimed, G11–G15); CR2c (CAM-8): hot-plug — the selection
// rule (V22), the observers and the pending rebuild on the hidden panel
// (panel P16a–e, P17).
// Compiled AS `main.swift` beside every file of
// app/Sources (but its own main.swift) through `swift_build.build`, with an
// Info.plist section holding the camera's and the microphone's usage strings;
// `camera_recording_probe.py` builds it, runs one section per process and
// scores the rows. Usage: camera-recording-probe <section> <request.json>.
// Prints one JSON line: {"rows": [{id, pass, detail}], "facts": {...}}.
// Never asks for a grant: a section that needs one reads it and skips.

import AVFoundation
import AppKit

var probeRows: [[String: Any]] = []
var probeFacts: [String: Any] = [:]

func probeRow(_ id: String, _ pass: Bool, _ detail: String) {
    probeRows.append(["id": id, "pass": pass, "detail": detail])
}

/// A row skipped by name: scored neither pass nor fail.
func probeSkip(_ id: String, _ detail: String) {
    probeRows.append(["id": id, "pass": "skip", "detail": detail])
}

func probeEmit() -> Never {
    let object: [String: Any] = ["rows": probeRows, "facts": probeFacts]
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

/// Runs the main run loop until `done` or `seconds` pass; answers `done()`.
@discardableResult
func probeSpin(_ seconds: Double, until done: () -> Bool = { false }) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !done(), Date() < end {
        _ = RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.01)))
    }
    return done()
}

func fmt(_ w: Int, _ h: Int, _ r: Double) -> CameraFormatFacts {
    CameraFormatFacts(width: w, height: h, maxRate: r)
}

// MARK: - values

/// CR0's D1 lists (tools/proof/work/camera-spike/results-full-2026-10-26-150454.json).
let faceTime: [CameraFormatFacts] = [
    fmt(1920, 1080, 30), fmt(1280, 720, 30), fmt(1080, 1920, 30), fmt(1760, 1328, 30),
    fmt(640, 480, 30), fmt(1328, 1760, 30), fmt(1552, 1552, 30),
]
let obs: [CameraFormatFacts] = [fmt(1920, 1080, 60)]
let iPhone: [CameraFormatFacts] = [
    fmt(640, 480, 30), fmt(640, 480, 60), fmt(1280, 720, 30), fmt(1280, 720, 60),
    fmt(1920, 1080, 30), fmt(1920, 1080, 60), fmt(1920, 1440, 30), fmt(1920, 1440, 60),
]

func values(_ request: [String: Any]) {
    func pick(_ id: String, _ list: [CameraFormatFacts], active: Int?, want: Int?, _ what: String) {
        let got = CameraDevices.bestFormat(list, active: active)
        let spelled = got.map { CameraDevices.spelled(list[$0]) } ?? "none"
        probeRow(id, got == want, "\(what): picked \(got.map(String.init) ?? "nil") (\(spelled)), want \(want.map(String.init) ?? "nil")")
    }
    pick("V1", faceTime, active: 1, want: 3, "FaceTime HD's 7 formats")
    pick("V2", obs, active: 0, want: 0, "OBS's one format")
    pick("V3", iPhone, active: 0, want: 7, "the iPhone's 8 formats (7 over 6 on rate)")
    pick("V4", [fmt(1080, 1920, 30), fmt(720, 1280, 60), fmt(1328, 1760, 30)], active: 0,
         want: 2, "portrait only: CAM-2 over every format")
    let slow = [fmt(1920, 1080, 15), fmt(1280, 720, 24)]
    let slowActive = CameraDevices.bestFormat(slow, active: 1)
    let slowNone = CameraDevices.bestFormat(slow, active: nil)
    probeRow("V5", slowActive == 1 && slowNone == nil,
             "all under 30: active 1 → \(slowActive.map(String.init) ?? "nil"), no active → \(slowNone.map(String.init) ?? "nil")")

    let rates: [(CameraFormatFacts, Int, String)] = [
        (fmt(1760, 1328, 30), 30, "1760x1328@30"), (fmt(1920, 1080, 60), 60, "1920x1080@60"),
        (fmt(1920, 1080, 29.97), 30, "1920x1080@29.97"), (fmt(640, 480, 0), 1, "640x480@0"),
        (fmt(1280, 720, 59.94), 60, "1280x720@59.94"),
    ]
    let rateFacts = rates.map { (CameraDevices.canvasRate($0.0), CameraDevices.spelled($0.0)) }
    probeRow("V6", zip(rates, rateFacts).allSatisfy { $0.0.1 == $0.1.0 && $0.0.2 == $0.1.1 },
             "canvasRate, spelled: " + rateFacts.map { "\($0.1)→\($0.0)" }.joined(separator: ", "))

    let epoch = request["stemEpoch"] as? Double ?? 0
    let stem = RecordingFiles.cameraStem(at: Date(timeIntervalSince1970: epoch))
    let wantStem = request["stemWant"] as? String ?? "?"
    probeRow("V7", stem == wantStem, "cameraStem(\(Int(epoch))) = \(stem), want \(wantStem)")

    let folder = URL(fileURLWithPath: request["work"] as? String ?? NSTemporaryDirectory())
        .appendingPathComponent("names", isDirectory: true)
    try? FileManager.default.removeItem(at: folder)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let at = Date(timeIntervalSince1970: epoch)
    let free = ScreenRecorder.nextCameraURL(in: folder, at: at, holding: [])
    let held = ScreenRecorder.nextCameraURL(in: folder, at: at, holding: [free.path])
    let micHeld = ScreenRecorder.nextCameraURL(
        in: folder, at: at, holding: [RecordingFiles.microphoneURL(beside: free).path])
    FileManager.default.createFile(atPath: free.path, contents: Data())
    let onDisk = ScreenRecorder.nextCameraURL(in: folder, at: at, holding: [held.path])
    let names = [free, held, micHeld, onDisk].map(\.lastPathComponent)
    let wantNames = [
        "\(wantStem).mov", "\(wantStem) (2).mov", "\(wantStem) (2).mov", "\(wantStem) (3).mov",
    ]
    probeRow("V8", names == wantNames,
             "free, movie held, microphone held, on disk + (2) held: " + names.joined(separator: " | "))

    let cams = [
        CameraDeviceFacts(uniqueID: "OBS-ID", name: "OBS Virtual Camera", isBuiltIn: false,
                          formats: obs, activeFormat: 0),
        CameraDeviceFacts(uniqueID: "FT-ID", name: "FaceTime HD Camera", isBuiltIn: true,
                          formats: faceTime, activeFormat: 1),
        CameraDeviceFacts(uniqueID: "PHONE-ID", name: "Owner iPhone Camera", isBuiltIn: false,
                          formats: iPhone, activeFormat: 0),
    ]
    let matches = ["FT-ID", "facetime hd camera", "FaceTime", "OBS-ID", "obs virtual CAMERA", "Zed"]
        .map { CameraDevices.match($0, in: cams) }
    probeRow("V9", matches == [1, 1, nil, 0, 0, nil],
             "match id, name any case, a prefix, id, name, unknown → \(matches.map { $0.map(String.init) ?? "nil" })")

    let defaults = [
        CameraDevices.defaultIndex(in: cams, preferredID: "PHONE-ID"),
        CameraDevices.defaultIndex(in: cams, preferredID: "gone"),
        CameraDevices.defaultIndex(in: cams, preferredID: nil),
        CameraDevices.defaultIndex(in: [cams[0], cams[2]], preferredID: nil),
        CameraDevices.defaultIndex(in: [], preferredID: "FT-ID"),
    ]
    probeRow("V10", defaults == [2, 1, 1, 0, nil],
             "preferred, preferred gone, none, no built-in, empty → \(defaults.map { $0.map(String.init) ?? "nil" })")

    let unknown = CameraDevices.noSuchCameraSentence("Zed", cameras: cams)
    let namesAll = cams.allSatisfy { unknown.contains($0.name) && unknown.contains($0.uniqueID) }
    probeRow("V11",
             CameraDevices.noCameraSentence == "No camera is connected." && namesAll
                && unknown.contains("Zed")
                && CameraDevices.noSuchCameraSentence("Zed", cameras: []) == "No camera is connected.",
             "\(CameraDevices.noCameraSentence) | \(unknown)")

    let t0 = Date(timeIntervalSince1970: 1000)
    let pts = ScreenRecorder.cameraMicOffset(
        cameraPTS: 100.25, micPTS: 100.2, cameraArrived: t0, micArrived: t0.addingTimeInterval(1))
    probeRow("V12a", pts == 30_000, "PTS 100.25 − 100.2 (arrivals say −1 s) → \(pts), want 30000")
    let fallback = ScreenRecorder.cameraMicOffset(
        cameraPTS: nil, micPTS: 100.2, cameraArrived: t0.addingTimeInterval(0.1), micArrived: t0)
    probeRow("V12b", fallback == 60_000, "no camera PTS: arrivals +0.1 s → \(fallback), want 60000")
    let early = ScreenRecorder.cameraMicOffset(
        cameraPTS: 10.0, micPTS: 10.02, cameraArrived: nil, micArrived: nil)
    probeRow("V12c", early == -12_000, "picture 20 ms before the microphone → \(early), want −12000")
    let none = ScreenRecorder.cameraMicOffset(
        cameraPTS: 5, micPTS: nil, cameraArrived: t0, micArrived: nil)
    probeRow("V12d", none == 0, "neither pair whole → \(none), want 0")

    let clause = RecordingGrant.launchClause
    let ask = "Press Record with the Camera source in File ▸ New Recording… once to grant it."
    let pane = "Turn it on in System Settings ▸ Privacy & Security ▸ Camera, then relaunch."
    let statuses: [(AVAuthorizationStatus, String, String)] = [
        (.notDetermined, "notDetermined", ask), (.restricted, "restricted", pane),
        (.denied, "denied", pane), (.authorized, "authorized", pane),
    ]
    let refusals = statuses.map { RecordingGrant.cameraRefusal($0.0) }
    let refusalsOK = zip(statuses, refusals).allSatisfy {
        $0.1 == "The camera is not granted to Frame Job (status: \($0.0.1)). " + $0.0.2 + clause
    }
    probeRow("V13", refusalsOK, refusals.joined(separator: " | "))

    let error = RecorderError.cameraDevice("No camera with the id X is connected.")
    probeRow("V14", error.localizedDescription == "No camera with the id X is connected.",
             "cameraDevice: \(error.localizedDescription)")

    // CAM-3's warm-up: the cold start's intervals against the frame, and the bound's note.
    let frame = 1.0 / 30
    let steady = [0.0333, 0.0350, 0.0433, 0.0300].map { CameraCapture.isSteady($0, frame: frame) }
    func warm(_ steady: Bool, _ rate: Double) -> CameraCapture.WarmUp {
        CameraCapture.WarmUp(
            seconds: 1, buffers: 24, steady: steady, rate: rate, wanted: 30, intervals: [])
    }
    let notes = [warm(true, 30).note, warm(false, 23.14).note, warm(false, 0).note]
    let want: [String?] = [
        nil,
        "The camera ran at 23.1 fps, not its 30, in the 1 s it was given to settle; "
            + "the recording began anyway.",
        "The camera delivered no steady frames in the 1 s it was given to settle; "
            + "the recording began anyway.",
    ]
    probeRow("V17", steady == [true, true, false, true] && notes == want
                 && CameraCapture.warmUpRun == 5 && CameraCapture.warmUpBound == 1,
             "isSteady 33.3, 35.0, 43.3, 30.0 ms at 30 fps → \(steady); run "
                 + "\(CameraCapture.warmUpRun), bound \(CameraCapture.warmUpBound) s; notes "
                 + notes.map { $0 ?? "nil" }.joined(separator: " | "))
    formatValues()
    hotPlugValues()
}

/// V22 (CR2c, spec §11 CAM-8 (3)): `hotPlugSelection` — the stored id when
/// listed (over a different listed current), else the current when listed,
/// else nil; `""` counts as nil.
func hotPlugValues() {
    let cases: [(String, [String], String?, String?, String?)] = [
        ("stored listed, a different current listed", ["a", "b"], "a", "b", "a"),
        ("stored gone, current listed", ["b"], "a", "b", "b"),
        ("neither listed", ["c"], "a", "b", nil),
        ("\"\" stored, current listed", ["b"], "", "b", "b"),
        ("both nil", ["a"], nil, nil, nil),
    ]
    var shown: [String] = []
    var ok = true
    for (name, listed, stored, current, want) in cases {
        let got = RecorderPanelController.hotPlugSelection(
            listed: listed, stored: stored, current: current)
        ok = ok && got == want
        shown.append("\(name) → \(got ?? "nil") (want \(want ?? "nil"))")
    }
    probeRow("V22", ok, shown.joined(separator: "; "))
}

/// V18–V21 (CR2a, spec §11 CAM-6): the Format rows, the choice, the titles
/// and the tool's spelling, on CR0's three lists.
func formatValues() {
    func rows(_ list: [CameraFormatFacts]) -> [String] {
        CameraDevices.formatRows(list).map { "\($0):" + CameraDevices.spelled(list[$0]) }
    }
    let duplicated = [fmt(1280, 720, 30), fmt(1920, 1080, 30), fmt(1280, 720, 30)]
    let zeroRate = [fmt(640, 480, 0), fmt(320, 240, 30)]
    let got = [rows(faceTime), rows(iPhone), rows(obs), rows(duplicated), rows(zeroRate)]
    let want = [
        ["3:1760x1328@30", "0:1920x1080@30", "1:1280x720@30", "4:640x480@30", "6:1552x1552@30",
         "5:1328x1760@30", "2:1080x1920@30"],
        ["7:1920x1440@60", "6:1920x1440@30", "5:1920x1080@60", "4:1920x1080@30", "3:1280x720@60",
         "2:1280x720@30", "1:640x480@60", "0:640x480@30"],
        ["0:1920x1080@60"], ["1:1920x1080@30", "0:1280x720@30"], ["1:320x240@30"],
    ]
    probeRow("V18", got == want,
             "FaceTime, iPhone, OBS, a duplicate, a 0-rate format → "
                 + got.map { $0.joined(separator: " ") }.joined(separator: " | "))

    let chosen = [
        CameraDevices.chosenFormat(nil, in: faceTime, active: 1),
        CameraDevices.chosenFormat("1920x1080@30", in: faceTime, active: 1),
        CameraDevices.chosenFormat("9x9@1", in: faceTime, active: 1),
        CameraDevices.chosenFormat("1280x720@30", in: duplicated, active: nil),
    ]
    probeRow("V19", chosen == [3, 0, 3, 0],
             "nil, listed, stale, a duplicate → \(chosen.map { $0.map(String.init) ?? "nil" }) "
                 + "(want [3, 0, 3, 0])")

    let ft = CameraDeviceFacts(uniqueID: "FT-ID", name: "FaceTime HD Camera", isBuiltIn: true,
                               formats: faceTime, activeFormat: 1)
    let phone = CameraDeviceFacts(uniqueID: "PHONE-ID", name: "Owner iPhone Camera",
                                  isBuiltIn: false, formats: iPhone, activeFormat: 0,
                                  isContinuityCamera: true)
    let titles = [
        CameraDevices.formatTitle(fmt(1920, 1080, 30)), CameraDevices.formatTitle(fmt(1280, 720, 59.94)),
        CameraDevices.popupTitle(ft), CameraDevices.popupTitle(phone),
        RecorderPanelController.cameraSizeNote(ft),
        RecorderPanelController.cameraSizeNote(ft, format: "1920x1080@30"),
        RecorderPanelController.cameraSizeNote(ft, format: "9x9@1"),
        RecorderPanelController.cameraSizeNote(nil, format: "1920x1080@30"),
    ]
    let wantTitles = [
        "1920×1080 at 30 fps", "1280×720 at 59.94 fps", "FaceTime HD Camera",
        "Owner iPhone Camera (Continuity Camera)", "1760×1328 at 30 fps — the camera's best format",
        "1920×1080 at 30 fps — the chosen format", "1760×1328 at 30 fps — the camera's best format",
        "no camera connected",
    ]
    probeRow("V20", titles == wantTitles, titles.joined(separator: " | "))

    let matches = [
        CameraDevices.formatMatch("1920x1080@30", in: faceTime),
        CameraDevices.formatMatch("1920X1080@30", in: faceTime),
        CameraDevices.formatMatch("1920x1440", in: iPhone),
        CameraDevices.formatMatch("1920X1080", in: iPhone),
        CameraDevices.formatMatch("1920x1080@60", in: faceTime),
        CameraDevices.formatMatch("4k", in: faceTime),
    ]
    let wantMatches: [String?] = [
        "1920x1080@30", "1920x1080@30", "1920x1440@60", "1920x1080@60", nil, nil,
    ]
    let sentence = CameraDevices.noSuchFormatSentence("4k", camera: ft)
    let wantSentence = "The camera FaceTime HD Camera has no format 4k. Its formats are best, "
        + "1760x1328@30, 1920x1080@30, 1280x720@30, 640x480@30, 1552x1552@30, 1328x1760@30, "
        + "1080x1920@30."
    probeRow("V21", matches == wantMatches && sentence == wantSentence,
             "exact, upper-case, 1920x1440 and 1920X1080 on the iPhone, a rate not listed, "
                 + "unknown → \(matches.map { $0 ?? "nil" }); \(sentence)")
}

// MARK: - landing

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let document = ProjectDocument()
        document.fileType = typeName
        return document
    }
}

func landing(_ request: [String: Any]) {
    let controller = ProbeDocumentController()
    NSApplication.shared.setActivationPolicy(.prohibited)
    UserDefaults.standard.setVolatileDomain(
        ["ApplePersistenceIgnoreState": true], forName: UserDefaults.argumentDomain)
    probeFacts["controllerIsProbe"] = NSDocumentController.shared === controller
    func probed(_ path: String) -> MediaDescriptor? {
        var answer: MediaDescriptor?
        var done = false
        MediaImporter.probe(url: URL(fileURLWithPath: path), mayAsk: false) { outcome in
            answer = try? outcome.get()
            done = true
        }
        probeSpin(30) { done }
        return answer
    }
    guard let movie = probed(request["movie"] as? String ?? ""),
        let voice = probed(request["voice"] as? String ?? "")
    else {
        probeRow("L1", false, "a fixture did not probe")
        return
    }
    var choice = RecordingChoice()
    choice.source = .camera
    choice.camera = "PROBE-ID"
    choice.microphone = "PROBE-MIC"
    choice.rate = CameraDevices.canvasRate(fmt(1920, 1080, 30))
    let camera = RecordingCamera(name: "Probe Camera", format: "1920x1080@30")
    let result = RecordingResult(
        segments: [
            RecordingSegment(
                descriptor: movie, micDescriptor: voice, micOffset: 12_000, startedAt: Date())
        ], choice: choice, stoppedBy: .stopped, pauses: 0, camera: camera)
    probeRow("L3", result.isCamera && !result.isVoiceOver && result.camera == camera,
             "isCamera \(result.isCamera), isVoiceOver \(result.isVoiceOver), camera \(String(describing: result.camera))")

    do {
        let d = ProjectDocument()
        let placement = try RecordingLanding.placement(result, in: d, place: true)
        d.performGroupedEdit(RecordingLanding.actionName, placement.ops)
        let s = d.project.snapshot
        let back = s.tracks.first
        let pictureMedia = s.media.first { $0.path == movie.path }?.id
        let voiceMedia = s.media.first { $0.path == voice.path }?.id
        func clip(of media: UInt32?) -> ClipSnapshot? {
            s.clips.first {
                if case .media(let m, _, _) = $0.source { return m == media }
                return false
            }
        }
        let picture = clip(of: pictureMedia)
        let spoken = clip(of: voiceMedia)
        let pictureTrack = s.tracks.first { $0.id == picture?.track }
        let ok =
            back?.name == "Microphone" && spoken?.track == back?.id && picture != nil
            && pictureTrack?.name != "Microphone" && s.clips.count == 2
        probeRow("L1", ok,
                 "ops \(placement.ops.map(\.name)); tracks \(s.tracks.map(\.name)); picture on "
                    + "\(pictureTrack?.name ?? "none"), voice on the back track "
                    + "\(spoken?.track == back?.id) (\(back?.name ?? "none"))")
    } catch {
        probeRow("L1", false, "placement threw: \(error.localizedDescription)")
    }

    do {
        let (d, notes) = try ProjectDocument.untitled(around: result)
        let s = d.project.snapshot
        let ok =
            s.canvas.width == 1920 && s.canvas.height == 1080 && s.canvas.fps.num == 30
            && s.canvas.fps.den == 1 && s.clips.count == 2 && s.tracks.first?.name == "Microphone"
        probeRow("L2", ok,
                 "canvas \(s.canvas.width)×\(s.canvas.height) at \(s.canvas.fps.num)/\(s.canvas.fps.den); "
                    + "clips \(s.clips.count); tracks \(s.tracks.map(\.name)); notes \(notes)")
        d.close()
    } catch {
        probeRow("L2", false, "untitled(around:) threw: \(error.localizedDescription)")
    }
}

// MARK: - granted

func granted(_ request: [String: Any]) {
    let devices = CameraDevices.connected()
    let facts = devices.map(CameraDevices.facts(of:))
    probeFacts["cameras"] = facts.count
    guard
        let index = CameraDevices.defaultIndex(
            in: facts, preferredID: AVCaptureDevice.systemPreferredCamera?.uniqueID)
    else {
        probeFacts["skip"] = "no camera is connected"
        return
    }
    let status = RecordingGrant.cameraStatus
    guard status == .authorized else {
        probeFacts["skip"] =
            "the Camera grant is \(RecordingGrant.name(of: status)); nothing was recorded"
        return
    }
    let camera = facts[index]
    grantedRun(request, camera: camera)
    // G7–G9 (CR1c): after G0–G6's stop has answered, plus 1 s.
    probeSpin(1)
    var prepared = RecordingChoice()
    prepared.source = .camera
    prepared.camera = camera.uniqueID
    prepared.folder = URL(fileURLWithPath: request["folder"] as? String ?? NSTemporaryDirectory())
    probeFacts["G7"] = preparedStart(prepared)
    probeFacts["G8"] = preparedDiscard(prepared)
    probeSpin(1)
    probeFacts["G9"] = preparedJoin(prepared)
    // G10 (CR2a): a prepared capture at a chosen format, adopted and recorded.
    probeSpin(1)
    probeFacts["G10"] = chosenFormatStart(prepared, camera: camera)
    // G11, G12, G14, G15 (CR2b, CAM-7): #373's two rebuilds, a tool start
    // beside a prepared capture, a thrown prepare.
    probeSpin(1)
    probeFacts["G11"] = formatChangeStart(prepared, camera: camera)
    probeSpin(1)
    probeFacts["G12"] = fallbackStart(prepared)
    probeSpin(1)
    probeFacts["G14"] = toolBesidePrepared(prepared)
    probeSpin(1)
    probeFacts["G15"] = thrownPrepare(prepared)
}

/// The camera's first Format row whose spelling is not the best format's,
/// and the best's spelling; a nil row when there is none.
func nonBestRow(_ camera: CameraDeviceFacts) -> (row: String?, best: String?) {
    let best = CameraDevices.bestFormat(camera.formats, active: camera.activeFormat)
        .map { CameraDevices.spelled(camera.formats[$0]) }
    let rows = CameraDevices.formatRows(camera.formats).map { CameraDevices.spelled(camera.formats[$0]) }
    return (rows.first(where: { $0 != best }), best)
}

/// Waits up to 5 s for `recorder`'s prepared start to answer.
@discardableResult
func awaitPrepared(_ recorder: ScreenRecorder) -> Bool {
    probeSpin(5) { recorder.preparedCamera?.answered == true }
}

/// `startCamera` for `choice` on `recorder` (answered within the arm
/// ceiling), then `seconds` recorded and stopped: whether it adopted the
/// capture prepared before the call, the slot right after the call and after
/// the answer, and whether the session's capture has a preview layer.
func startAndRecord(
    _ recorder: ScreenRecorder, _ choice: RecordingChoice, mayAsk: Bool, seconds: Double = 2
) -> [String: Any] {
    var out: [String: Any] = [:]
    let prepared = recorder.preparedCamera?.capture
    var started: Error??
    let called = Date()
    var startSeconds: Double?
    recorder.startCamera(choice: choice, mayAsk: mayAsk, onFinish: { _ in }) {
        startSeconds = Date().timeIntervalSince(called)
        started = .some($0)
    }
    out["preparedAtCall"] = recorder.preparedCamera != nil
    out["adopted"] = prepared != nil && recorder.cameraSession?.capture === prepared
    out["sessionLayer"] = recorder.cameraSession.map { $0.capture.previewLayer != nil } ?? NSNull()
    probeSpin(ScreenRecorder.armCeiling + 2) { started != nil }
    out["startSeconds"] = startSeconds ?? NSNull()
    out["preparedAfter"] = recorder.preparedCamera != nil
    guard let answer = started else {
        out["error"] = "the start did not answer"
        return out
    }
    if let answer {
        out["error"] = "the start failed: \(answer.localizedDescription)"
        return out
    }
    return out.merging(recordAndStop(recorder, seconds)) { $1 }
}

/// G11 (#373, a format change): prepared at best and answered, then in one
/// main turn prepared again at the first non-best row — the first capture let
/// go and the second built and started in the same turn — then the
/// countdown's 3 s and the panel's start, which adopts the second.
func formatChangeStart(_ base: RecordingChoice, camera: CameraDeviceFacts) -> [String: Any] {
    let (found, best) = nonBestRow(camera)
    guard let row = found else {
        return ["skip": "the camera \(camera.name) lists no format but its best (\(best ?? "none"))"]
    }
    let recorder = ScreenRecorder()
    var out: [String: Any] = ["row": row, "best": best ?? NSNull()]
    recorder.prepareCamera(for: base)
    out["firstAnswered"] = awaitPrepared(recorder)
    let first = recorder.preparedCamera?.capture
    var choice = base
    choice.cameraFormat = row
    recorder.prepareCamera(for: choice)
    out["rebuilt"] = first != nil && recorder.preparedCamera != nil
        && recorder.preparedCamera?.capture !== first
    probeSpin(Double(RecorderPanelController.countdownSeconds))
    return out.merging(startAndRecord(recorder, choice, mayAsk: true)) { $1 }
}

/// G12 (#373, the fallback): a prepared capture marked stopped on its own,
/// so the panel's start lets it go and builds a fresh one in the same turn.
func fallbackStart(_ choice: RecordingChoice) -> [String: Any] {
    let recorder = ScreenRecorder()
    recorder.prepareCamera(for: choice)
    var out: [String: Any] = ["answered": awaitPrepared(recorder)]
    out["prepared"] = recorder.preparedCamera != nil
    recorder.preparedCamera?.stoppedOnItsOwn = "probe"
    return out.merging(startAndRecord(recorder, choice, mayAsk: true)) { $1 }
}

/// G14 (CAM-7 (7)): a tool's start (`mayAsk` false) beside a prepared
/// capture builds its own, with no layer, and lets the prepared one go.
func toolBesidePrepared(_ choice: RecordingChoice) -> [String: Any] {
    let recorder = ScreenRecorder()
    recorder.prepareCamera(for: choice)
    var out: [String: Any] = ["answered": awaitPrepared(recorder)]
    out["prepared"] = recorder.preparedCamera != nil
    return out.merging(startAndRecord(recorder, choice, mayAsk: false)) { $1 }
}

/// G15 (CAM-7 (8)): a failed build's record for the camera at best blocks
/// `prepareCamera` until `discardPreparedCamera` clears it.
func thrownPrepare(_ choice: RecordingChoice) -> [String: Any] {
    guard let id = choice.camera, let device = CameraDevices.device(withID: id) else {
        return ["error": "the camera is gone"]
    }
    let facts = CameraDevices.facts(of: device)
    guard let best = CameraDevices.chosenFormat(nil, in: facts.formats, active: facts.activeFormat)
    else { return ["error": "the camera lists no format"] }
    let recorder = ScreenRecorder()
    recorder.preparedCameraFailure = ScreenRecorder.PreparedCameraFailure(
        deviceID: id, format: best, sentence: "probe")
    recorder.prepareCamera(for: choice)
    var out: [String: Any] = [
        "blocked": recorder.preparedCamera == nil,
        "kept": recorder.preparedCameraFailure?.sentence == "probe",
    ]
    recorder.discardPreparedCamera()
    out["cleared"] = recorder.preparedCameraFailure == nil
    recorder.prepareCamera(for: choice)
    out["built"] = recorder.preparedCamera != nil
    let capture = recorder.preparedCamera?.capture
    recorder.discardPreparedCamera()
    var stopped = false
    capture?.stop { stopped = true }
    out["stopped"] = probeSpin(5) { stopped }
    return out
}

/// G10 (CAM-6 (3)): G7's prepared start at `camera`'s first Format row whose
/// spelling is not the best format's; a skip by name when there is none.
func chosenFormatStart(_ base: RecordingChoice, camera: CameraDeviceFacts) -> [String: Any] {
    let (found, best) = nonBestRow(camera)
    guard let row = found else {
        return ["skip": "the camera \(camera.name) lists no format but its best (\(best ?? "none"))"]
    }
    var choice = base
    choice.cameraFormat = row
    return preparedStart(choice).merging(["row": row, "best": best ?? NSNull()]) { $1 }
}

/// G0–G6: 2 s, a 1 s pause, 2 s more, on `camera`.
func grantedRun(_ request: [String: Any], camera: CameraDeviceFacts) {
    let best = CameraDevices.bestFormat(camera.formats, active: camera.activeFormat)
    probeFacts["isBuiltIn"] = camera.isBuiltIn
    probeFacts["best"] = best.map { CameraDevices.spelled(camera.formats[$0]) } ?? "none"
    probeFacts["bestRate"] = best.map { CameraDevices.canvasRate(camera.formats[$0]) } ?? 0
    var choice = RecordingChoice()
    choice.source = .camera
    choice.camera = camera.uniqueID
    choice.folder = URL(fileURLWithPath: request["folder"] as? String ?? NSTemporaryDirectory())
    let micStatus = RecordingGrant.microphoneStatus
    probeFacts["micGrant"] = RecordingGrant.name(of: micStatus)
    if micStatus == .authorized { choice.microphone = AVCaptureDevice.default(for: .audio)?.uniqueID }
    probeFacts["microphone"] = choice.microphone != nil

    let recorder = ScreenRecorder()
    var started: Error??
    var finished: Result<RecordingResult, Error>?
    var onFinishCalls = 0
    let called = Date()
    var startSeconds: Double?
    recorder.startCamera(
        choice: choice, mayAsk: false, onFinish: { _ in onFinishCalls += 1 },
        completion: {
            startSeconds = Date().timeIntervalSince(called)
            started = .some($0)
        })
    probeSpin(25) { started != nil }
    guard let startError = started else {
        probeFacts["error"] = "the start did not answer in 25 s"
        return
    }
    if let startError {
        probeFacts["error"] = "the start failed: \(startError.localizedDescription)"
        return
    }
    probeFacts["startSeconds"] = startSeconds ?? NSNull()
    // G13: a tool's start, with nothing prepared, has no preview layer.
    probeFacts["toolLayer"] = recorder.cameraSession.map { $0.capture.previewLayer != nil } ?? NSNull()
    if let warm = recorder.cameraSession?.capture.warmUp {
        probeFacts["warmUp"] = [
            "seconds": warm.seconds, "buffers": warm.buffers, "steady": warm.steady,
            "rate": warm.rate, "wanted": warm.wanted, "intervals": warm.intervals,
            "note": warm.note ?? NSNull(),
        ] as [String: Any]
    }
    probeFacts["firstStarted"] = probeSpin(5) { recorder.heldFirstStartedAt != nil }
    var steps: [String] = []
    probeSpin(2)
    do { try recorder.pause() } catch { steps.append("pause: \(error.localizedDescription)") }
    probeFacts["elapsedAtPause"] = recorder.elapsed
    probeSpin(1)
    probeFacts["elapsedPaused"] = recorder.elapsed
    do { try recorder.resume() } catch { steps.append("resume: \(error.localizedDescription)") }
    probeSpin(2)
    recorder.stop { finished = $0 }
    probeSpin(30) { finished != nil }
    probeFacts["steps"] = steps
    probeFacts["onFinishCalls"] = onFinishCalls
    probeFacts["idle"] = recorder.state == .idle && recorder.cameraSession == nil
    switch finished {
    case nil:
        probeFacts["error"] = "the stop did not answer in 30 s"
    case .failure(let error):
        probeFacts["error"] = "the recording failed: \(error.localizedDescription)"
    case .success(let result):
        probeFacts["pauses"] = result.pauses
        probeFacts["stoppedBy"] = "\(result.stoppedBy)"
        probeFacts["isCamera"] = result.isCamera
        probeFacts["format"] = result.camera?.format ?? "none"
        probeFacts["problem"] = result.camera?.problem ?? NSNull()
        probeFacts["note"] = result.camera?.note ?? NSNull()
        probeFacts["nameIsDevice"] = result.camera?.name == camera.name
        probeFacts["rate"] = result.choice.rate
        probeFacts["unreadable"] = result.unreadable.map(\.sentence)
        probeFacts["segments"] = result.segments.map { segment -> [String: Any] in
            [
                "movie": segment.descriptor.path, "width": segment.descriptor.width,
                "height": segment.descriptor.height,
                "mic": segment.micDescriptor?.path ?? NSNull(),
                "micOffset": Double(segment.micOffset) / Double(ReelTime.perSecond),
                "micProblem": segment.micProblem ?? NSNull(),
            ]
        }
    }
}

/// The recorder's state, for a fact.
func stateName(_ state: ScreenRecorder.State) -> String { "\(state)" }

/// A started recorder recorded for `seconds` and stopped: the stop's facts.
func recordAndStop(_ recorder: ScreenRecorder, _ seconds: Double) -> [String: Any] {
    var out: [String: Any] = [:]
    var finished: Result<RecordingResult, Error>?
    probeSpin(seconds)
    recorder.stop { finished = $0 }
    probeSpin(30) { finished != nil }
    switch finished {
    case nil:
        out["stopError"] = "the stop did not answer in 30 s"
    case .failure(let error):
        out["stopError"] = "the recording failed: \(error.localizedDescription)"
    case .success(let result):
        out["segments"] = result.segments.map { $0.descriptor.path }
        out["note"] = result.camera?.note ?? NSNull()
        out["problem"] = result.camera?.problem ?? NSNull()
        out["format"] = result.camera?.format ?? "none"
    }
    return out
}

/// G7 (CAM-5 (5)): the countdown's prepared capture adopted by the panel's
/// `startCamera` (`mayAsk` true, CAM-7 (7)); G13 (CAM-7 (2)): its preview
/// layer, read before the start.
func preparedStart(_ choice: RecordingChoice) -> [String: Any] {
    let recorder = ScreenRecorder()
    var out: [String: Any] = [:]
    let held = Date()
    recorder.prepareCamera(for: choice)
    out["prepareSeconds"] = Date().timeIntervalSince(held)
    out["prepared"] = recorder.preparedCamera != nil
    probeSpin(Double(RecorderPanelController.countdownSeconds))
    out["answeredAtStart"] = recorder.preparedCamera?.answered ?? false
    if let capture = recorder.preparedCamera?.capture {
        let layer = capture.previewLayer
        out["layer"] = layer != nil
        out["layerSession"] = layer?.session === capture.session
        out["connection"] = layer?.connection != nil
        out["mirrored"] = layer?.connection?.isVideoMirrored ?? NSNull()
    }
    return out.merging(startAndRecord(recorder, choice, mayAsk: true)) { $1 }
}

/// G8 (CAM-7 (6)): a prepared capture let go, then `stop`'s completion asked
/// for: it answers, its session has stopped by then, and the session's
/// did-stop notification (posted by `stopRunning`, on the queue) came first
/// — `isRunning` alone reads false as soon as the stop begins.
func preparedDiscard(_ choice: RecordingChoice) -> [String: Any] {
    let recorder = ScreenRecorder()
    recorder.prepareCamera(for: choice)
    probeSpin(1)
    let capture = recorder.preparedCamera?.capture
    let lock = NSLock()
    var didStop: Date?
    let observer = NotificationCenter.default.addObserver(
        forName: AVCaptureSession.didStopRunningNotification, object: capture?.session, queue: nil
    ) { _ in
        lock.lock()
        didStop = didStop ?? Date()
        lock.unlock()
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    let asked = Date()
    recorder.discardPreparedCamera()
    var answered: Date?
    var running: Bool?
    capture?.stop {
        answered = Date()
        running = capture?.session.isRunning
    }
    probeSpin(5) { answered != nil }
    lock.lock()
    let stoppedAt = didStop
    lock.unlock()
    return [
        "held": capture != nil, "slotNil": recorder.preparedCamera == nil,
        "seconds": answered.map { $0.timeIntervalSince(asked) } ?? NSNull(),
        "running": running ?? NSNull(),
        "didStopSeconds": stoppedAt.map { $0.timeIntervalSince(asked) } ?? NSNull(),
        "didStopFirst": answered.flatMap { a in stoppedAt.map { $0 <= a } } ?? false,
    ]
}

/// G9: `startCamera` straight after `prepareCamera`, before the prepared
/// start can have answered — the join.
func preparedJoin(_ choice: RecordingChoice) -> [String: Any] {
    let recorder = ScreenRecorder()
    var out: [String: Any] = [:]
    recorder.prepareCamera(for: choice)
    out["prepared"] = recorder.preparedCamera != nil
    out["answeredAtStart"] = recorder.preparedCamera?.answered ?? false
    var started: Error??
    let called = Date()
    var startSeconds: Double?
    recorder.startCamera(choice: choice, mayAsk: true, onFinish: { _ in }) {
        startSeconds = Date().timeIntervalSince(called)
        started = .some($0)
    }
    probeSpin(ScreenRecorder.armCeiling + 5) { started != nil }
    out["startSeconds"] = startSeconds ?? NSNull()
    out["ceiling"] = ScreenRecorder.armCeiling
    out["state"] = stateName(recorder.state)
    out["preparedAfter"] = recorder.preparedCamera != nil
    guard let answer = started else {
        out["error"] = "the start did not answer"
        return out
    }
    if let answer {
        out["error"] = "the start failed: \(answer.localizedDescription)"
        recorder.stop { _ in }
        return out
    }
    return out.merging(recordAndStop(recorder, 1)) { $1 }
}

// MARK: - panel

/// The panel's grant doors as a spy: every read counted, the prompts held,
/// nothing opened. Sealed in before `RecorderPanelController.shared` exists.
final class PanelGrantSpy {
    var camera: AVAuthorizationStatus = .authorized
    var mic: AVAuthorizationStatus = .authorized
    var screenReads = 0
    var screenRequests = 0
    var cameraReads = 0
    var cameraRequests = 0
    var micRequests = 0
    var opened: [String] = []
    var heldCamera: (() -> Void)?

    var doors: RecorderGrantDoors {
        RecorderGrantDoors(
            screenGranted: {
                self.screenReads += 1
                return false
            },
            launchedByLaunchd: { true },
            requestScreen: { self.screenRequests += 1 },
            screenAsked: { true },
            rememberScreenAsked: {},
            microphoneStatus: { self.mic },
            requestMicrophone: { _ in self.micRequests += 1 },
            openSettings: { url in
                self.opened.append(url.absoluteString)
                return true
            },
            cameraStatus: {
                self.cameraReads += 1
                return self.camera
            },
            requestCamera: { answered in
                self.cameraRequests += 1
                self.heldCamera = answered
            })
    }
}

/// CR1c (spec §11 CAM-5): `RecorderPanelController.shared`, never shown,
/// under `PanelGrantSpy`, with the nine `FrameJobRecording…` values put back
/// as they were at the end. Neither fake id finds a device, so no camera or
/// microphone opens.
func panelRows(_ request: [String: Any]) {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let spy = PanelGrantSpy()
    RecorderPanelController.grantDoors = spy.doors
    let keys = [
        RecorderPanelController.displayKey, RecorderPanelController.microphoneKey,
        RecorderPanelController.systemAudioKey, RecorderPanelController.showClicksKey,
        RecorderPanelController.rateKey, RecorderPanelController.sizeKey,
        RecorderPanelController.includeFrameJobWindowsKey, RecorderPanelController.cameraKey,
        RecorderPanelController.cameraFormatKey,
    ]
    let originals = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer {
        for (key, value) in zip(keys, originals) {
            if let value { UserDefaults.standard.set(value, forKey: key) } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
    let panel = RecorderPanelController.shared
    probeFacts["visible"] = panel.window?.isVisible ?? true

    // P1 — the rows, before any fake.
    let items = panel.sourcePopup.itemArray
    let screens = NSScreen.screens.count
    let tail = items.suffix(3)
    let separator = items.firstIndex { $0.isSeparatorItem } ?? -1
    let connected = CameraDevices.connected().map {
        CameraDevices.popupTitle(CameraDevices.facts(of: $0))
    }
    let cameraTitles = panel.cameraPopup.itemArray.map(\.title)
    let wantTitles = connected.isEmpty ? [RecorderPanelController.noCameraTitle] : connected
    probeRow("P1",
             tail.map(\.title) == ["Window…", "Camera", "Microphone Only"]
                && tail.map(\.tag) == [1, 3, 2] && separator == screens && items.count == screens + 4
                && cameraTitles == wantTitles,
             "last three \(tail.map(\.title)) tags \(tail.map(\.tag)); separator at \(separator), "
                + "\(items.count) rows for \(screens) screen(s); Camera popup \(cameraTitles), "
                + "connected \(connected)")

    let fakeCamera = NSMenuItem(title: "Probe Camera", action: nil, keyEquivalent: "")
    fakeCamera.representedObject = "probe-camera"
    panel.cameraPopup.menu?.addItem(fakeCamera)
    let noCamera = NSMenuItem(
        title: RecorderPanelController.noCameraTitle, action: nil, keyEquivalent: "")
    panel.cameraPopup.menu?.addItem(noCamera)
    let fakeMic = NSMenuItem(title: "Probe Microphone", action: nil, keyEquivalent: "")
    fakeMic.representedObject = "probe-mic"
    panel.microphonePopup.menu?.addItem(fakeMic)
    func cameraRow() -> NSMenuItem? {
        panel.sourcePopup.menu?.item(withTag: RecorderPanelController.cameraTag)
    }
    func choose(_ item: NSMenuItem?) {
        if let item { panel.sourcePopup.select(item) }
        panel.controlChanged(panel.sourcePopup)
    }
    func reset() {
        panel.cancelCountdown()
        panel.phase = .idle
        panel.setNote("")
        panel.recordButton.isEnabled = true
    }
    func five() -> [String: Any] {
        [
            "enabled": [
                panel.systemAudioSwitch.isEnabled, panel.showClicksSwitch.isEnabled,
                panel.sizePopup.isEnabled, panel.includeFrameJobCheckbox.isEnabled,
                panel.ratePopup.isEnabled,
            ],
            "values": [
                panel.systemAudioSwitch.state == .on ? 1 : 0, panel.showClicksSwitch.state == .on ? 1 : 0,
                panel.sizePopup.indexOfSelectedItem, panel.includeFrameJobCheckbox.state == .on ? 1 : 0,
                panel.ratePopup.selectedTag(),
            ],
        ]
    }
    func recordingKeys() -> [String] {
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("FrameJobRecording") }.sorted()
    }

    // P2 — choosing Camera. A display row first, its values off their
    // defaults, so "kept" means something.
    reset()
    choose(panel.sourcePopup.item(at: 0))
    panel.systemAudioSwitch.state = .off
    panel.showClicksSwitch.state = .on
    panel.sizePopup.selectItem(at: 1)
    panel.includeFrameJobCheckbox.state = .on
    _ = panel.ratePopup.selectItem(withTag: 30)
    panel.cameraPopup.select(fakeCamera)
    panel.controlChanged(panel.cameraPopup)
    let before = five()
    UserDefaults.standard.set(777, forKey: RecorderPanelController.displayKey)
    choose(cameraRow())
    let choice = panel.currentChoice()
    let after = five()
    let others = [
        panel.cameraPopup.isEnabled, panel.microphonePopup.isEnabled,
        panel.destinationPopup.isEnabled, panel.sourcePopup.isEnabled,
    ]
    let note = panel.sizeNote.stringValue
    let wantNote = RecorderPanelController.cameraSizeNote(nil)
    let p2a = choice.source == .camera && choice.camera == "probe-camera"
        && (after["enabled"] as? [Bool]) == [false, false, false, false, false]
        && (after["values"] as? [Int]) == (before["values"] as? [Int])
        && (before["values"] as? [Int]) == [0, 1, 1, 1, 30]
        && others == [true, true, true, true] && note == wantNote

    // P3 — session only, read before the display row is chosen again.
    let display = UserDefaults.standard.integer(forKey: RecorderPanelController.displayKey)
    let stored = UserDefaults.standard.string(forKey: RecorderPanelController.cameraKey)
    let keysNow = recordingKeys()
    panel.rebuildSources()
    panel.restoreChoices()
    let kept = panel.cameraSelected && panel.currentChoice().source == .camera
        && panel.selectedCameraID == "probe-camera"
    probeRow("P3", display == 777 && stored == "probe-camera" && keysNow.count == 9 && kept,
             "display key \(display) (sentinel 777), camera key \(stored ?? "nil"), \(keysNow.count) "
                + "keys \(keysNow), the row and the camera kept through rebuildSources + "
                + "restoreChoices \(kept)")

    choose(panel.sourcePopup.item(at: 0))
    let back = five()
    let displayChoice = panel.currentChoice()
    let p2b = (back["enabled"] as? [Bool]) == [true, true, true, true, true]
        && !panel.cameraPopup.isEnabled && displayChoice.camera == nil
        && displayChoice.source == .display(panel.selectedDisplayID)
    probeRow("P2", p2a && p2b,
             "camera: source \(choice.source), camera \(choice.camera ?? "nil"); five before "
                + "\(before), after \(after); Camera, Microphone, Record Into, Source enabled "
                + "\(others); size note \(note) (want \(wantNote)) | a display row: five \(back), "
                + "Camera enabled \(panel.cameraPopup.isEnabled), camera \(displayChoice.camera ?? "nil")")

    // P4 — the step, the pane, the opened note.
    let steps = [AVAuthorizationStatus.authorized, .notDetermined, .denied, .restricted].map {
        RecordingGrant.cameraStep($0)
    }
    let pane = RecordingGrant.cameraPaneURL?.absoluteString ?? ""
    let opened = RecordingGrant.cameraOpenedNote(.denied)
    let wantOpened = "The camera is not granted to Frame Job (status: denied). Turn it on in System "
        + "Settings ▸ Privacy & Security ▸ Camera, then relaunch." + RecordingGrant.paneOpenedSentence
        + RecordingGrant.launchClause
    probeRow("P4", steps == [.proceed, .ask, .openPane, .openPane]
                 && pane.hasSuffix("Privacy_Camera") && opened == wantOpened,
             "authorized, notDetermined, denied, restricted → \(steps); pane \(pane); opened note "
                 + "exact \(opened == wantOpened)")

    // P5 — the press.
    var press: [String] = []
    var pressOK = true
    func expect(_ what: String, _ ok: Bool) {
        press.append("\(what) \(ok ? "ok" : "WRONG")")
        pressOK = pressOK && ok
    }
    reset()
    choose(cameraRow())
    panel.microphonePopup.selectItem(at: 0)
    panel.cameraPopup.select(noCamera)
    var reads = spy.cameraReads
    panel.record(nil)
    expect("no camera: idle, noCameraSentence, 0 camera reads (\(panel.noteLabel.stringValue))",
           panel.phase == .idle && panel.noteLabel.stringValue == CameraDevices.noCameraSentence
               && spy.cameraReads == reads)
    reset()
    panel.cameraPopup.select(fakeCamera)
    spy.camera = .notDetermined
    panel.record(nil)
    expect("notDetermined: 1 camera request (\(spy.cameraRequests)), idle, Record disabled",
           spy.cameraRequests == 1 && panel.phase == .idle && !panel.recordButton.isEnabled)
    spy.heldCamera?()
    spy.heldCamera = nil
    expect("the held answer on the hidden panel: Record enabled, idle",
           panel.recordButton.isEnabled && panel.phase == .idle)
    for status in [AVAuthorizationStatus.denied, .restricted] {
        reset()
        spy.camera = status
        spy.opened = []
        panel.record(nil)
        expect("\(RecordingGrant.name(of: status)): opened \(spy.opened)",
               spy.opened == [pane] && panel.noteLabel.stringValue
                   == RecordingGrant.cameraOpenedNote(status) && panel.phase == .idle)
    }
    reset()
    spy.camera = .authorized
    spy.mic = .notDetermined
    panel.microphonePopup.select(fakeMic)
    let micBefore = spy.micRequests
    panel.record(nil)
    expect("authorized, probe-mic notDetermined: 1 microphone request (\(spy.micRequests - micBefore))",
           spy.micRequests - micBefore == 1 && panel.phase == .idle)
    reset()
    spy.mic = .authorized
    panel.microphonePopup.selectItem(at: 0)
    reads = spy.cameraReads
    panel.record(nil)
    expect("authorized, Microphone Off: \(panel.phase)",
           panel.phase == .countdown(RecorderPanelController.countdownSeconds)
               && spy.cameraReads == reads + 1)
    panel.cancelCountdown()
    expect("cancelCountdown: idle, nothing prepared",
           panel.phase == .idle && ScreenRecorder.shared.preparedCamera == nil)
    expect("screen reads \(spy.screenReads), requests \(spy.screenRequests)",
           spy.screenReads == 0 && spy.screenRequests == 0)
    probeRow("P5", pressOK, press.joined(separator: "; "))
    reset()

    // P6 — the panel stays up, its Pause / Resume button.
    choose(cameraRow())
    panel.phase = .recording
    let recording = (panel.voiceOverPauseButton.isHidden, panel.voiceOverPauseButton.title)
    panel.phase = .paused
    let paused = (panel.voiceOverPauseButton.isHidden, panel.voiceOverPauseButton.title)
    panel.phase = .idle
    let hides = (
        RecorderPanelController.hidesForRecording(.camera),
        RecorderPanelController.hidesForRecording(.display(CGMainDisplayID()))
    )
    probeRow("P6", !hides.0 && hides.1 && recording == (false, "Pause") && paused == (false, "Resume"),
             "hidesForRecording camera \(hides.0), display \(hides.1); recording \(recording), "
                + "paused \(paused)")
    choose(panel.sourcePopup.item(at: 0))
    reset()

    // P7 — the landing note.
    let problem = "The camera Probe Camera stopped on its own: it was disconnected."
    let warm = "The camera ran at 23.1 fps, not its 30, in the 1 s it was given to settle; "
        + "the recording began anyway."
    let mic = "The microphone stopped on its own."
    func cam(_ problem: String?, _ note: String?) -> RecordingCamera {
        var camera = RecordingCamera(name: "Probe Camera", format: "1920x1080@30")
        camera.problem = problem
        camera.note = note
        return camera
    }
    func landing(_ stopped: StopReason, _ micProblem: String?, _ camera: RecordingCamera?) -> String {
        RecorderPanelController.landingNote(
            stoppedBy: stopped, chosen: .newProject, landedAsNewProject: true,
            micProblem: micProblem, camera: camera)
    }
    let notes = [
        landing(.systemStopped, nil, cam(problem, nil)), landing(.systemStopped, nil, cam(nil, nil)),
        landing(.stopped, mic, cam(nil, warm)), landing(.systemStopped, nil, nil),
    ]
    let wantNotes = [
        problem + " What was captured was added.",
        "The camera stopped on its own. What was captured was added.",
        mic + " " + warm,
        "The system stopped the recording (the display slept or went away); what was captured was added.",
    ]
    probeRow("P7", notes == wantNotes, notes.joined(separator: " | "))

    // P8 — the size note on CR0's lists.
    let sizes = [
        RecorderPanelController.cameraSizeNote(
            CameraDeviceFacts(uniqueID: "FT-ID", name: "FaceTime HD Camera", isBuiltIn: true,
                              formats: faceTime, activeFormat: 1)),
        RecorderPanelController.cameraSizeNote(
            CameraDeviceFacts(uniqueID: "PHONE-ID", name: "Owner iPhone Camera", isBuiltIn: false,
                              formats: iPhone, activeFormat: 0)),
        RecorderPanelController.cameraSizeNote(nil),
    ]
    probeRow("P8", sizes == [
        "1760×1328 at 30 fps — the camera's best format",
        "1920×1440 at 60 fps — the camera's best format", "no camera connected",
    ], sizes.joined(separator: " | "))
    formatPanelRows(panel, fakeCamera: fakeCamera, cameraRow: cameraRow(), choose: choose, reset: reset)
    previewStepRows()
    previewPanelRows(panel, cameraRow: cameraRow(), choose: choose, reset: reset)
    hotPlugPanelRows(panel, reset: reset)
    probeFacts["visibleAtEnd"] = panel.window?.isVisible ?? true
}

/// P16a–e and P17 (CR2c, spec §11 CAM-8) on the hidden panel, never shown:
/// `observeDevices()` called directly, each notification posted with object
/// nil and the main run loop run 0.2 s before reading. P17 closes the panel,
/// so it runs last.
func hotPlugPanelRows(_ panel: RecorderPanelController, reset: () -> Void) {
    let defaults = UserDefaults.standard
    let cameraKey = RecorderPanelController.cameraKey
    let formatKey = RecorderPanelController.cameraFormatKey
    let micKey = RecorderPanelController.microphoneKey
    func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
        probeSpin(0.2)
    }
    func ids(_ popup: NSPopUpButton) -> [String?] {
        popup.itemArray.map { $0.representedObject as? String }
    }
    @discardableResult
    func fake(_ popup: NSPopUpButton, _ id: String) -> NSMenuItem {
        let item = NSMenuItem(title: "Probe \(id)", action: nil, keyEquivalent: "")
        item.representedObject = id
        popup.menu?.addItem(item)
        return item
    }
    func keys() -> [String?] { [cameraKey, formatKey, micKey].map { defaults.string(forKey: $0) } }
    let connected = CameraDevices.connected().map(\.uniqueID)
    let first = connected.first

    // P16a — the pair added once, marking the lists pending.
    reset()
    let pendingBefore = panel.devicesPending
    panel.observeDevices()
    let pendingAfter = panel.devicesPending
    panel.observeDevices()
    let observers = panel.deviceObservers.count
    probeRow("P16a", !pendingBefore && pendingAfter && observers == 2,
             "devicesPending \(pendingBefore) → \(pendingAfter) after observeDevices(); "
                + "\(observers) observers after a second call (want 2)")

    // P16b — a post applies: the fakes gone, the stored camera, Off, no key written.
    defaults.set("probe-mic-stored-gone", forKey: micKey)
    defaults.set(first ?? "probe-stored", forKey: cameraKey)
    panel.cameraPopup.select(fake(panel.cameraPopup, "probe-gone"))
    panel.microphonePopup.select(fake(panel.microphonePopup, "probe-mic-gone"))
    let keysBefore = keys()
    post(AVCaptureDevice.wasConnectedNotification)
    let cameraIDs = ids(panel.cameraPopup)
    let wantIDs: [String?] = connected.isEmpty ? [nil] : connected.map(Optional.some)
    let fakesGone = !cameraIDs.contains("probe-gone")
        && !ids(panel.microphonePopup).contains("probe-mic-gone")
    let selection = panel.selectedCameraID
    let selectionOK = first == nil || selection == first
    let off = panel.microphonePopup.indexOfSelectedItem == 0
        && panel.microphonePopup.selectedItem?.representedObject == nil
    let keysAfter = keys()
    probeRow("P16b",
             fakesGone && cameraIDs == wantIDs && selectionOK && off && keysAfter == keysBefore
                && keysAfter[2] == "probe-mic-stored-gone" && !panel.devicesPending,
             "fakes gone \(fakesGone); Camera ids \(cameraIDs.map { $0 ?? "nil" }) (connected "
                + "\(connected)); "
                + (first == nil ? "the stored camera's selection skipped by name: no camera connected"
                    : "selected \(selection ?? "nil") (stored \(first ?? "nil"))")
                + "; Microphone Off \(off); keys \(keysBefore.map { $0 ?? "nil" }) → "
                + "\(keysAfter.map { $0 ?? "nil" }); pending \(panel.devicesPending)")

    // P16c — an unchanged list rebuilds nothing; a swapped id is rebuilt.
    let popups = [panel.cameraPopup, panel.formatPopup, panel.microphonePopup]
    let itemsBefore = popups.map(\.itemArray)
    post(AVCaptureDevice.wasConnectedNotification)
    let itemsAfter = popups.map(\.itemArray)
    let same = zip(itemsBefore, itemsAfter).allSatisfy { before, after in
        before.count == after.count && zip(before, after).allSatisfy { $0 === $1 }
    }
    var swap = "the swapped id skipped by name: no microphone connected"
    var swapOK = true
    let microphones = RecorderPanelController.connectedMicrophones()
    if let device = microphones.first,
        let index = panel.microphonePopup.itemArray.firstIndex(where: {
            $0.representedObject as? String == device.uniqueID
        })
    {
        let row = panel.microphonePopup.itemArray[index]
        row.representedObject = "probe-mic-swapped"
        post(AVCaptureDevice.wasConnectedNotification)
        let carried = panel.microphonePopup.item(at: index)?.representedObject as? String
        swapOK = carried == device.uniqueID
        swap = "row \(index) (\(row.title)) given probe-mic-swapped carries \(carried ?? "nil") "
            + "after a post (want \(device.uniqueID))"
    }
    probeRow("P16c", same && swapOK,
             "every Camera, Format and Microphone item identical after a post \(same) "
                + "(\(itemsBefore.map(\.count)) items); \(swap)")

    // P16d — the stored camera gone: the selection held before stays, no key written.
    if let first,
        let index = panel.cameraPopup.itemArray.firstIndex(where: {
            $0.representedObject as? String == first
        })
    {
        defaults.set("probe-stored-gone", forKey: cameraKey)
        panel.cameraPopup.selectItem(at: index)
        fake(panel.cameraPopup, "probe-extra")
        post(AVCaptureDevice.wasConnectedNotification)
        let selected = panel.selectedCameraID
        let key = defaults.string(forKey: cameraKey)
        probeRow("P16d",
                 selected == first && key == "probe-stored-gone"
                    && !ids(panel.cameraPopup).contains("probe-extra"),
                 "stored probe-stored-gone, \(first) selected, a fake row: after a post selected "
                    + "\(selected ?? "nil"), the camera key \(key ?? "nil"), the fake gone "
                    + "\(!ids(panel.cameraPopup).contains("probe-extra"))")
    } else {
        probeSkip("P16d", "no camera connected")
    }

    // P16e — busy: the change waits for idle.
    panel.phase = .landing
    fake(panel.cameraPopup, "probe-busy")
    post(AVCaptureDevice.wasDisconnectedNotification)
    let keptBusy = ids(panel.cameraPopup).contains("probe-busy")
    let pendingBusy = panel.devicesPending
    panel.phase = .idle
    let goneIdle = !ids(panel.cameraPopup).contains("probe-busy")
    let pendingIdle = panel.devicesPending
    probeRow("P16e", keptBusy && pendingBusy && goneIdle && !pendingIdle,
             "landing: the fake kept \(keptBusy), pending \(pendingBusy); idle: the fake gone "
                + "\(goneIdle), pending \(pendingIdle)")
    reset()

    // P17 — the close removes the observers.
    NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: panel.window)
    probeSpin(0.2)
    let emptied = panel.deviceObservers.isEmpty
    fake(panel.cameraPopup, "probe-closed")
    post(AVCaptureDevice.wasConnectedNotification)
    let stays = ids(panel.cameraPopup).contains("probe-closed")
    probeRow("P17", emptied && stays && !panel.devicesPending,
             "after willClose: observers \(panel.deviceObservers.count); a fake row after a post "
                + "stays \(stays), pending \(panel.devicesPending)")
}

/// P13 (CR2b, spec §11 CAM-7 (3)): `cameraPreviewStep` over every step and
/// each first-match boundary, counting the `grant` and `failure` calls.
func previewStepRows() {
    typealias Phase = RecorderPanelController.Phase
    struct Case {
        let name: String
        var visible = true
        var camera = true
        var phase: Phase = .idle
        var idle = true
        var recording = false
        var chosen = true
        var grant: AVAuthorizationStatus = .authorized
        var failure: String?
        let want: CameraPreviewStep
        let grants: Int
        let failures: Int
    }
    var cases = [
        Case(name: "hidden", visible: false, want: .off, grants: 0, failures: 0),
        Case(name: "a display source", camera: false, want: .off, grants: 0, failures: 0),
    ]
    let phases: [(String, Phase)] = [
        ("idle", .idle), ("countdown(2)", .countdown(2)), ("starting", .starting),
        ("recording", .recording), ("paused", .paused), ("stopping", .stopping), ("landing", .landing),
    ]
    for (name, phase) in phases {
        cases.append(Case(name: "a recording, \(name)", phase: phase, idle: false, recording: true,
                          want: .recording, grants: 0, failures: 0))
    }
    cases += [
        Case(name: "countdown(2)", phase: .countdown(2), want: .prepared, grants: 0, failures: 0),
        Case(name: "starting", phase: .starting, idle: false, want: .prepared, grants: 0, failures: 0),
        Case(name: "landing", phase: .landing, want: .blank, grants: 0, failures: 0),
        Case(name: "stopping without a camera", phase: .stopping, idle: false, want: .blank,
             grants: 0, failures: 0),
        Case(name: "idle, the recorder busy", idle: false, want: .blank, grants: 0, failures: 0),
        Case(name: "no camera", chosen: false,
             want: .message(CameraDevices.noCameraSentence), grants: 0, failures: 0),
    ]
    for status in [AVAuthorizationStatus.notDetermined, .denied, .restricted] {
        cases.append(Case(name: RecordingGrant.name(of: status), grant: status,
                          want: .message(RecorderPanelController.previewGrantSentence),
                          grants: 1, failures: 0))
    }
    cases += [
        Case(name: "authorized, a failure", failure: "x", want: .failed("x"), grants: 1, failures: 1),
        Case(name: "authorized", want: .prepare, grants: 1, failures: 1),
    ]
    var wrong: [String] = []
    for c in cases {
        var grants = 0
        var failures = 0
        let step = RecorderPanelController.cameraPreviewStep(
            visible: c.visible, cameraSource: c.camera, phase: c.phase, recorderIdle: c.idle,
            recordingCamera: c.recording, cameraChosen: c.chosen,
            grant: {
                grants += 1
                return c.grant
            },
            failure: {
                failures += 1
                return c.failure
            })
        if step != c.want || grants != c.grants || failures != c.failures {
            wrong.append("\(c.name) → \(step), grant \(grants)×, failure \(failures)× "
                + "(want \(c.want), \(c.grants)×, \(c.failures)×)")
        }
    }
    probeRow("P13", wrong.isEmpty,
             wrong.isEmpty ? "\(cases.count) cases, each step and its grant and failure calls as wanted"
                : wrong.joined(separator: "; "))
}

/// P14 (CAM-7 (1)): the well's row on the hidden panel — shown with Source
/// Camera, 200 × 150 after layout, the card taller by at least the well;
/// hidden with a display row — and `CameraPreviewWell`'s two calls.
func previewPanelRows(
    _ panel: RecorderPanelController, cameraRow: NSMenuItem?, choose: (NSMenuItem?) -> Void,
    reset: () -> Void
) {
    reset()
    choose(panel.sourcePopup.item(at: 0))
    panel.card.layoutSubtreeIfNeeded()
    let hiddenFirst = panel.cameraPreviewRow?.isHidden
    let displayHeight = panel.card.fittingSize.height
    choose(cameraRow)
    panel.card.layoutSubtreeIfNeeded()
    let shown = panel.cameraPreviewRow?.isHidden == false
    let size = panel.cameraPreview.frame.size
    let cameraHeight = panel.card.fittingSize.height
    choose(panel.sourcePopup.item(at: 0))
    let hiddenAgain = panel.cameraPreviewRow?.isHidden
    let well = CameraPreviewWell()
    well.showMessage("x")
    let message = well.message
    let messageHosted = well.hostedLayer != nil
    let layer = AVCaptureVideoPreviewLayer()
    well.show(layer)
    let hosted = well.hostedLayer === layer && layer.superlayer === well.layer
    let hostedMessage = well.message
    probeRow("P14",
             hiddenFirst == true && shown && size == CameraPreviewWell.size
                && cameraHeight - displayHeight >= 150 && hiddenAgain == true && message == "x"
                && !messageHosted && hosted && hostedMessage == nil,
             "a display row: hidden \(hiddenFirst.map { "\($0)" } ?? "no row"); Camera: shown \(shown), "
                + "the well \(size.width)×\(size.height), the card \(displayHeight) → \(cameraHeight) "
                + "pt; a display row again: hidden \(hiddenAgain.map { "\($0)" } ?? "no row") | the "
                + "well: showMessage(x) → message \(message ?? "nil"), hosted \(messageHosted); "
                + "show(layer) → hosted \(hosted), message \(hostedMessage ?? "nil")")
    reset()
}

/// P10–P12 (CR2a, spec §11 CAM-6): the Format popup — its fill, its live
/// rule and its key, and its rebuild on `selectCamera`'s early return.
func formatPanelRows(
    _ panel: RecorderPanelController, fakeCamera: NSMenuItem, cameraRow: NSMenuItem?,
    choose: (NSMenuItem?) -> Void, reset: () -> Void
) {
    let ft = CameraDeviceFacts(uniqueID: "FT-ID", name: "FaceTime HD Camera", isBuiltIn: true,
                               formats: faceTime, activeFormat: 1)
    func titles() -> [String] { panel.formatPopup.itemArray.map(\.title) }
    let key = RecorderPanelController.cameraFormatKey

    // P10 — the fill on V1's facts.
    reset()
    choose(cameraRow)
    panel.fillCameraFormats(ft, stored: nil)
    let filled = titles()
    let bestSelected = panel.formatPopup.indexOfSelectedItem == 0 && panel.selectedCameraFormat == nil
    panel.fillCameraFormats(ft, stored: "1920x1080@30")
    let storedTitle = panel.formatPopup.titleOfSelectedItem
    let storedChoice = panel.currentChoice().cameraFormat
    panel.fillCameraFormats(ft, stored: "9x9@1")
    let staleBest = panel.formatPopup.indexOfSelectedItem == 0
    panel.fillCameraFormats(nil, stored: "1920x1080@30")
    let none = titles()
    let wantFilled = [
        "Best (1760×1328 at 30 fps)", "1760×1328 at 30 fps", "1920×1080 at 30 fps",
        "1280×720 at 30 fps", "640×480 at 30 fps", "1552×1552 at 30 fps", "1328×1760 at 30 fps",
        "1080×1920 at 30 fps",
    ]
    probeRow("P10",
             filled == wantFilled && bestSelected && storedTitle == "1920×1080 at 30 fps"
                && storedChoice == "1920x1080@30" && staleBest
                && none == [RecorderPanelController.bestFormatTitle],
             "titles \(filled), Best selected \(bestSelected); stored 1920x1080@30 → "
                + "\(storedTitle ?? "nil"), currentChoice().cameraFormat \(storedChoice ?? "nil"); "
                + "stored 9x9@1 → Best \(staleBest); no camera → \(none)")

    // P11 — the live rule and the key.
    reset()
    choose(panel.sourcePopup.item(at: 0))
    let displayEnabled = panel.formatPopup.isEnabled
    choose(cameraRow)
    let cameraEnabled = panel.formatPopup.isEnabled
    panel.cameraPopup.select(fakeCamera)
    panel.fillCameraFormats(ft, stored: nil)
    UserDefaults.standard.set("sentinel", forKey: key)
    let row = panel.formatPopup.itemArray.firstIndex { $0.representedObject as? String == "1920x1080@30" }
    if let row { panel.formatPopup.selectItem(at: row) }
    panel.controlChanged(panel.formatPopup)
    let written = UserDefaults.standard.string(forKey: key)
    let chosenNote = panel.sizeNote.stringValue
    panel.formatPopup.selectItem(at: 0)
    panel.controlChanged(panel.formatPopup)
    let bestWritten = UserDefaults.standard.string(forKey: key)
    if let row { panel.formatPopup.selectItem(at: row) }
    choose(panel.sourcePopup.item(at: 0))
    let displayFormat = panel.currentChoice().cameraFormat
    let displayAgain = panel.formatPopup.isEnabled
    probeRow("P11",
             !displayEnabled && cameraEnabled && written == "1920x1080@30" && bestWritten == ""
                && displayFormat == nil && !displayAgain,
             "Format enabled with a display \(displayEnabled), with Camera idle \(cameraEnabled); "
                + "the 1920x1080@30 row wrote \(written ?? "nil") (size note \(chosenNote)), Best "
                + "wrote \(bestWritten.map { "\"\($0)\"" } ?? "nil"); a display row: cameraFormat "
                + "\(displayFormat ?? "nil"), Format enabled \(displayAgain)")

    // P12 — `selectCamera`'s early return still rebuilds the Format popup.
    reset()
    panel.formatPopup.removeAllItems()
    panel.selectCamera("probe-camera")
    let selected = panel.selectedCameraID
    let early = titles()
    UserDefaults.standard.set("probe-camera", forKey: RecorderPanelController.cameraKey)
    panel.formatPopup.removeAllItems()
    panel.restoreChoices()
    let restored = titles()
    let best = [RecorderPanelController.bestFormatTitle]
    probeRow("P12", selected == "probe-camera" && early == best && restored == best,
             "selectCamera(probe-camera): selected \(selected ?? "nil"), Format \(early); "
                + "restoreChoices with probe-camera stored: Format \(restored)")
}

// MARK: - tool

/// CR1b (spec §11 CAM-4): `record_screen`'s camera through `AgentServer.shared`'s
/// own functions — the argument checks, the lookup and grant, the answer —
/// with no camera and no grant.
func toolRows(_ request: [String: Any]) {
    let server = AgentServer.shared
    func kind(_ a: [String: Any]) -> String {
        do {
            return "ok: " + (try server.recordingSourceKind(a)).rawValue
        } catch let error as AgentServer.ToolError {
            return "error: " + error.message
        } catch {
            return "other: \(error)"
        }
    }
    func table(_ id: String, _ cases: [(String, [String: Any], String)]) {
        let got = cases.map { kind($0.1) }
        let wrong = zip(cases, got).filter { $0.0.2 != $0.1 }
        probeRow(id, wrong.isEmpty,
                 wrong.isEmpty
                    ? cases.map { "\($0.0) → \(kind($0.1))" }.joined(separator: " | ")
                    : wrong.map { "\($0.0.0): got \($0.1), want \($0.0.2)" }.joined(separator: " | "))
    }
    let tail = " cannot be given — a camera recording records the camera alone, at the camera's own format."
    table("T1", [
        ("camera", ["source": "camera"], "ok: camera"),
        ("camera named", ["source": "camera", "camera": "FaceTime HD Camera"], "ok: camera"),
        ("one stranger", ["source": "camera", "rate": 30], "error: With source camera, rate" + tail),
        ("all seven", [
            "source": "camera", "rate": 30, "include_framejob_windows": true, "size": "best",
            "show_clicks": true, "system_audio": false, "window": 5, "display": 0,
        ], "error: With source camera, display, window, system_audio, show_clicks, size, "
            + "include_framejob_windows, rate" + tail),
        ("a null size", ["source": "camera", "size": NSNull()], "ok: camera"),
        ("source x", ["source": "x"], "error: source must be one of screen, voice_over, camera (got \"x\")."),
    ])
    let elsewhere = " cannot be given — only source camera records a camera."
    table("T2", [
        ("camera, no source", ["camera": "FaceTime HD Camera"], "error: With source screen, camera" + elsewhere),
        ("camera with screen", ["source": "screen", "camera": "FT-ID"], "error: With source screen, camera" + elsewhere),
        ("camera with voice_over and display", ["source": "voice_over", "camera": "FT-ID", "display": 0],
         "error: With source voice_over, camera" + elsewhere),
        ("a blank camera with screen", ["source": "screen", "camera": "  "], "ok: screen"),
        ("a null camera with voice_over", ["source": "voice_over", "camera": NSNull()], "ok: voice_over"),
    ])

    let cams = [
        CameraDeviceFacts(uniqueID: "OBS-ID", name: "OBS Virtual Camera", isBuiltIn: false,
                          formats: obs, activeFormat: 0),
        CameraDeviceFacts(uniqueID: "FT-ID", name: "FaceTime HD Camera", isBuiltIn: true,
                          formats: faceTime, activeFormat: 1),
        CameraDeviceFacts(uniqueID: "PHONE-ID", name: "Owner iPhone Camera", isBuiltIn: false,
                          formats: iPhone, activeFormat: 0),
    ]
    func lookup(_ wanted: String?, _ list: [CameraDeviceFacts], _ preferred: String?,
                _ status: AVAuthorizationStatus) -> String {
        do {
            return "ok: " + (try AgentServer.recordingCameraPick(
                wanted, format: nil, in: list, preferredID: preferred, status: status)).id
        } catch let error as AgentServer.ToolError {
            return "error: " + error.message
        } catch {
            return "other: \(error)"
        }
    }
    let unknown = "error: " + CameraDevices.noSuchCameraSentence("Zed", cameras: cams)
    let lookups: [(String, String, String)] = [
        ("the default: the built-in", lookup(nil, cams, nil, .authorized), "ok: FT-ID"),
        ("the default: preferredID", lookup(nil, cams, "PHONE-ID", .authorized), "ok: PHONE-ID"),
        ("by name, any case", lookup("owner IPHONE camera", cams, nil, .authorized), "ok: PHONE-ID"),
        ("by id", lookup("OBS-ID", cams, "PHONE-ID", .authorized), "ok: OBS-ID"),
        ("unknown", lookup("Zed", cams, nil, .authorized), unknown),
        ("an empty list", lookup(nil, [], "FT-ID", .authorized), "error: No camera is connected."),
        ("an empty list, named", lookup("Zed", [], nil, .authorized), "error: No camera is connected."),
        ("unknown + denied", lookup("Zed", cams, nil, .denied), unknown),
        ("known + notDetermined", lookup("FT-ID", cams, nil, .notDetermined),
         "error: " + RecordingGrant.cameraRefusal(.notDetermined)),
        ("the default + restricted", lookup(nil, cams, nil, .restricted),
         "error: " + RecordingGrant.cameraRefusal(.restricted)),
        ("known + authorized", lookup("facetime hd camera", cams, nil, .authorized), "ok: FT-ID"),
    ]
    let badLookups = lookups.filter { $0.1 != $0.2 }
    probeRow("T3", badLookups.isEmpty,
             badLookups.isEmpty
                ? lookups.map { "\($0.0) → \($0.1.prefix(60))" }.joined(separator: " | ")
                : badLookups.map { "\($0.0): got \($0.1), want \($0.2)" }.joined(separator: " | "))

    // T7 (CR2a, CAM-6 (6)): `camera_format` beside `camera` in CAM-4 (2)'s step.
    let format = "error: With source screen, camera_format" + elsewhere
    table("T7", [
        ("camera_format with screen", ["source": "screen", "camera_format": "1920x1080@30"], format),
        ("both with voice_over", ["source": "voice_over", "camera": "FT-ID", "camera_format": "best"],
         "error: With source voice_over, camera, camera_format" + elsewhere),
        ("camera_format: 5", ["source": "camera", "camera_format": 5],
         "error: camera_format must be a string."),
        ("camera_format: 5 with screen", ["source": "screen", "camera_format": 5],
         "error: camera_format must be a string."),
        ("a blank camera_format with screen", ["source": "screen", "camera_format": "  "], "ok: screen"),
        ("a null camera_format with screen", ["source": "screen", "camera_format": NSNull()], "ok: screen"),
        ("camera_format with camera", ["source": "camera", "camera_format": "1920x1080@30"],
         "ok: camera"),
    ])

    // T8 (CAM-6 (6)): the format between the lookup and the grant.
    func pick(_ wanted: String?, _ format: String?, _ status: AVAuthorizationStatus) -> String {
        do {
            let got = try AgentServer.recordingCameraPick(
                wanted, format: format, in: cams, preferredID: nil, status: status)
            return "ok: \(got.id) \(got.format ?? "nil")"
        } catch let error as AgentServer.ToolError {
            return "error: " + error.message
        } catch {
            return "other: \(error)"
        }
    }
    let ft = cams[1]
    let noFormat = "error: " + CameraDevices.noSuchFormatSentence("4k", camera: ft)
    let picks: [(String, String, String)] = [
        ("nil", pick(nil, nil, .authorized), "ok: FT-ID nil"),
        ("spelled", pick("FT-ID", "1920x1080@30", .authorized), "ok: FT-ID 1920x1080@30"),
        ("1920X1080 on the iPhone", pick("PHONE-ID", "1920X1080", .authorized),
         "ok: PHONE-ID 1920x1080@60"),
        ("best", pick("FT-ID", "best", .authorized), "ok: FT-ID nil"),
        ("BEST", pick(nil, "BEST", .authorized), "ok: FT-ID nil"),
        ("unknown format", pick("FT-ID", "4k", .authorized), noFormat),
        ("unknown camera + bad format", pick("Zed", "4k", .authorized), unknown),
        ("bad format + denied", pick("FT-ID", "4k", .denied), noFormat),
        ("good format + denied", pick("FT-ID", "1920x1080@30", .denied),
         "error: " + RecordingGrant.cameraRefusal(.denied)),
    ]
    let badPicks = picks.filter { $0.1 != $0.2 }
    probeRow("T8", badPicks.isEmpty,
             badPicks.isEmpty
                ? picks.map { "\($0.0) → \($0.1.prefix(60))" }.joined(separator: " | ")
                : badPicks.map { "\($0.0): got \($0.1), want \($0.2)" }.joined(separator: " | "))

    let plain = RecordingCamera(name: "Probe Camera", format: "1920x1080@30")
    var troubled = plain
    troubled.problem = "The camera Probe Camera stopped on its own: it was disconnected."
    troubled.note = "The camera ran at 23.1 fps, not its 30, in the 1 s it was given to settle; "
        + "the recording began anyway."
    let plainFields = AgentServer.cameraFields(plain, id: "PROBE-ID")
    let troubledFields = AgentServer.cameraFields(troubled, id: "PROBE-ID")
    let plainWant: [String: Any] = ["name": "Probe Camera", "id": "PROBE-ID", "format": "1920x1080@30"]
    var troubledWant = plainWant
    troubledWant["problem"] = troubled.problem
    troubledWant["note"] = troubled.note
    probeRow("T4",
             NSDictionary(dictionary: plainFields).isEqual(to: plainWant)
                && NSDictionary(dictionary: troubledFields).isEqual(to: troubledWant),
             "without: \(plainFields.keys.sorted()); with: \(troubledFields.keys.sorted())")

    let movie = MediaDescriptor(
        path: "/probe/Camera Recording.mov", duration: 1_200_000, width: 1920, height: 1080,
        hasVideo: true)
    var cameraChoice = RecordingChoice()
    cameraChoice.source = .camera
    cameraChoice.camera = "PROBE-ID"
    let micProblem = "The microphone stopped on its own."
    let cameraResult = RecordingResult(
        segments: [
            RecordingSegment(
                descriptor: movie, micDescriptor: nil, micOffset: 0, startedAt: Date(),
                micProblem: micProblem)
        ], choice: cameraChoice, stoppedBy: .systemStopped, pauses: 0, camera: troubled)
    let screenResult = RecordingResult(
        descriptor: movie, micDescriptor: nil, micOffset: 0, choice: RecordingChoice(),
        startedAt: Date(), stoppedBy: .stopped, micProblem: micProblem)
    let cameraAnswer = AgentServer.recordingFields(cameraResult)
    let screenAnswer = AgentServer.recordingFields(screenResult)
    let answered = cameraAnswer["camera"] as? [String: Any]
    probeRow("T5",
             answered.map { NSDictionary(dictionary: $0).isEqual(to: troubledWant) } == true
                && screenAnswer["camera"] == nil
                && cameraAnswer["has_audio"] as? Bool == false
                && cameraAnswer["stopped_by"] as? String == "system_stopped",
             "camera result's camera \(answered.map { $0.keys.sorted() } ?? []); screen result has "
                + "camera \(screenAnswer["camera"] != nil); has_audio \(cameraAnswer["has_audio"] ?? "nil"), "
                + "stopped_by \(cameraAnswer["stopped_by"] ?? "nil")")

    let cameraNotes = AgentServer.resultNotes(cameraResult)
    let screenNotes = AgentServer.resultNotes(screenResult)
    let micNote = AgentServer.microphoneNote(screenResult)
    probeRow("T6",
             cameraNotes == [micNote, troubled.problem, troubled.note].compactMap { $0 }
                && screenNotes == [micNote].compactMap { $0 } && micNote != nil,
             "camera: \(cameraNotes.count) clauses, the last two \(cameraNotes.suffix(2)); screen: "
                + "\(screenNotes)")
}

// MARK: - main

let arguments = CommandLine.arguments
guard arguments.count == 3,
    let data = FileManager.default.contents(atPath: arguments[2]),
    let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
else {
    FileHandle.standardError.write(Data("usage: camera-recording-probe <section> <request.json>\n".utf8))
    exit(2)
}
switch arguments[1] {
case "values": values(request)
case "landing": landing(request)
case "granted": granted(request)
case "tool": toolRows(request)
case "panel": panelRows(request)
default:
    FileHandle.standardError.write(Data("unknown section \(arguments[1])\n".utf8))
    exit(2)
}
probeEmit()
