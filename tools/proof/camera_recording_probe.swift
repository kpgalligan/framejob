// camera-recording CR1a (spec §11 CAM-3): the camera recorder's pure values,
// a camera result through the landing, and a real recording under the
// terminal's grant. Compiled AS `main.swift` beside every file of
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
default:
    FileHandle.standardError.write(Data("unknown section \(arguments[1])\n".utf8))
    exit(2)
}
probeEmit()
