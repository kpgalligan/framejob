// Codec export C6a (spec §11 CX-18) — the Export Queue's memory limit on bundled-encoder
// jobs and the sheet's time estimate, in process. `encoder_limit_proof.py` builds it as
// `main.swift` over every file in `app/Sources` but the app's own `main.swift`, on
// `swift_build.py`'s line, beside `Blank.mp4`, `Fonts` and a `default.metallib` of
// `Compositor.metal` and `ExportI010.metal`, and runs it:
//
//   encoder_limit_probe <AV.mov> <out folder> <answer.json>
//
// No app and no instance: the two live projects are built here from AV.mov, as
// `webm_readers_probe.swift` builds A1's — A1 (640 × 360, 30 fps, AV.mov from 0 under a
// two-second text clip) and W9 (1920 × 1080, AV.mov 24 times end to end at scale 3).
//
// The answer is RAW: the tables (P0), what the rule and the estimate answered (R, E), and
// what the live queue did (Q), each event stamped with a sequence number. The proof
// computes every expected value from P0's tables in its own arithmetic and scores the rows.
import AVFoundation
import AppKit
import Foundation

DecoderSupport.enable()
NSApplication.shared.setActivationPolicy(.prohibited)

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("usage: encoder_limit_probe <AV.mov> <out folder> <answer.json>")
    exit(2)
}
let media = URL(fileURLWithPath: arguments[1])
let outFolder = URL(fileURLWithPath: arguments[2], isDirectory: true)
let answerURL = URL(fileURLWithPath: arguments[3])
try? FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)

let binaryDirectory = URL(fileURLWithPath: arguments[0]).deletingLastPathComponent()
    .standardizedFileURL
let fontsDirectory = binaryDirectory.appendingPathComponent("Fonts")
for name in (try? FileManager.default.contentsOfDirectory(atPath: fontsDirectory.path)) ?? []
where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
    CTFontManagerRegisterFontsForURL(
        fontsDirectory.appendingPathComponent(name) as CFURL, .process, nil)
}

var answer: [String: Any] = [:]
func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    try? data.write(to: answerURL)
    exit(0)
}

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

// MARK: - P0: the tables

func keyJSON(_ key: ExportEncoderKey) -> [String: Any] {
    ["preset": key.preset, "speed": key.speed?.rawValue ?? NSNull(), "bits": key.bits]
}
func figureJSON(_ f: ExportEncoderFigure) -> [String: Any] {
    ["at1080": f.at1080, "at2160": f.at2160, "source": f.source]
}
answer["pixels1080"] = ExportEncoderCosts.pixels1080
answer["pixels2160"] = ExportEncoderCosts.pixels2160
answer["memory"] = ExportEncoderCosts.memory.map { key, figure in
    ["key": keyJSON(key), "figure": figureJSON(figure)]
}
answer["time"] = ExportEncoderCosts.time.map { key, entry in
    ["key": keyJSON(key), "perFrame": figureJSON(entry.perFrame),
     "setupSeconds": entry.setupSeconds]
}

// MARK: - Synthetic settings

/// Settings as the core would answer them for a row, decoded through the app's own type.
func settings(
    preset: String, writer: String?, speed: EncoderSpeed? = nil, color: String? = nil,
    width: Int, height: Int, frames: Int = 300, fps: [Int] = [30, 1]
) -> ExportSettings {
    var object: [String: Any] = [
        "preset": preset, "container": "mp4", "codec": preset, "width": width,
        "height": height, "fps": fps,
        "range": ["start": 0, "duration": frames * Int(Fps.thirty.frameDuration)],
    ]
    if let writer { object["writer"] = writer }
    if let speed { object["encoder_speed"] = speed.rawValue }
    if let color { object["color"] = color }
    let data = try! JSONSerialization.data(withJSONObject: object)
    return ReelJSON.decode(ExportSettings.self, from: String(decoding: data, as: UTF8.self))!
}

/// One settings per measured key, by the proof's name for it.
func keyed(width: Int, height: Int, frames: Int = 300) -> [(String, ExportSettings)] {
    var out: [(String, ExportSettings)] = []
    for preset in ["av1", "av1_webm"] {
        for speed in EncoderSpeed.allCases {
            out.append(("\(preset):\(speed.rawValue)", settings(
                preset: preset, writer: "svt_av1", speed: speed, width: width, height: height,
                frames: frames)))
        }
    }
    out.append(("vp9_webm:sdr", settings(
        preset: "vp9_webm", writer: "libvpx", width: width, height: height, frames: frames)))
    out.append(("vp9_webm:hlg", settings(
        preset: "vp9_webm", writer: "libvpx", color: "hlg", width: width, height: height,
        frames: frames)))
    out.append(("vp9_alpha_webm", settings(
        preset: "vp9_alpha_webm", writer: "libvpx", width: width, height: height,
        frames: frames)))
    return out
}

// MARK: - R: the rule

let gib: UInt64 = 1 << 30
var r1: [[String: Any]] = []
for physical in [16, 24, 32, 48, 64, 96, 128] {
    let ledger = ExportEncoderLedger(physicalMemory: UInt64(physical) * gib)
    for (width, height) in [(1920, 1080), (3840, 2160)] {
        for (name, s) in keyed(width: width, height: height) {
            let fresh = ExportEncoderLedger(physicalMemory: UInt64(physical) * gib)
            var admitted = 0
            while fresh.admits(s), admitted < 1000 {
                _ = fresh.begin(s)
                admitted += 1
            }
            r1.append([
                "physicalGiB": physical, "budget": ledger.budget, "key": name,
                "width": width, "height": height,
                "cost": ExportEncoderCosts.memoryBytes(for: s, budget: ledger.budget),
                "admitted": admitted,
            ])
        }
    }
}
answer["r1"] = r1

do {
    let ledger = ExportEncoderLedger(physicalMemory: 64 * gib)
    // A writer row with no entry: every real row is measured (codec-export C5's fix pass
    // measured vp9_alpha_webm), so the rule is read on a synthetic one.
    let alpha = settings(preset: "unmeasured_webm", writer: "libvpx", width: 1920, height: 1080)
    let av1 = settings(preset: "av1", writer: "svt_av1", speed: .faster, width: 640, height: 360)
    let firstAlpha = ledger.admits(alpha)
    let alphaToken = ledger.begin(alpha)
    let secondAlpha = ledger.admits(alpha)
    let av1Beside = ledger.admits(av1)
    let alphaCost = ExportEncoderCosts.memoryBytes(for: alpha, budget: ledger.budget)
    ledger.end(alphaToken)
    let av1Token = ledger.begin(av1)
    let alphaBesideAV1 = ledger.admits(alpha)
    ledger.end(av1Token)
    answer["r2"] = [
        "budget": ledger.budget, "alphaCost": alphaCost, "firstAdmitted": firstAlpha,
        "secondAdmitted": secondAlpha, "av1BesideAlpha": av1Beside,
        "alphaBesideAV1": alphaBesideAV1, "idle": ledger.runningCosts.isEmpty,
    ]

    let h264 = settings(preset: "h264", writer: nil, width: 3840, height: 2160)
    let full = ExportEncoderLedger(physicalMemory: 16 * gib)
    let held = full.begin(alpha)
    let before = full.runningCosts
    let h264Token = full.begin(h264)
    answer["r3"] = [
        "token": h264Token.map { NSNumber(value: $0) } ?? NSNull(),
        "admittedBesideFull": full.admits(h264),
        "costsUnchanged": full.runningCosts == before,
        "cost": ExportEncoderCosts.memoryBytes(for: h264, budget: full.budget),
        "key": ExportEncoderKey(settings: h264) == nil,
    ]
    full.end(held)
}

// MARK: - E: the estimate

var e1: [[String: Any]] = []
for (width, height) in [(1280, 720), (1920, 1080), (2560, 1440), (3840, 2160), (7680, 4320)] {
    for frames in [150, 300, 1800] {
        for (name, s) in keyed(width: width, height: height, frames: frames) {
            e1.append([
                "key": name, "width": width, "height": height, "frames": frames,
                "seconds": ExportEncoderCosts.estimatedSeconds(for: s) ?? NSNull(),
                "line": ExportEncoderCosts.sheetLine(for: s) ?? NSNull(),
            ])
        }
    }
}
answer["e1"] = e1
answer["e2"] = [0.4, 2.4, 7.4, 57.4, 59.9, 60, 89, 90, 3569, 3570, 3600, 5399, 5400].map {
    ["seconds": $0, "text": ExportEncoderCosts.estimateText(seconds: $0)]
}
let h264Settings = settings(preset: "h264", writer: nil, width: 1920, height: 1080)
// A measured key at a rate that cannot be stepped: no frame count, so no estimate.
let unsteppedSettings = settings(
    preset: "av1", writer: "svt_av1", speed: .balanced, width: 1920, height: 1080,
    fps: [0, 1])
answer["e3"] = [
    "line": ExportEncoderCosts.sheetLine(for: h264Settings).map { $0 as Any } ?? NSNull(),
    "seconds": ExportEncoderCosts.estimatedSeconds(for: h264Settings).map { $0 as Any }
        ?? NSNull(),
    "unsteppedFrames": unsteppedSettings.sequenceFrameCount.map { $0 as Any } ?? NSNull(),
    "unsteppedLine": ExportEncoderCosts.sheetLine(for: unsteppedSettings).map { $0 as Any }
        ?? NSNull(),
    "unsteppedSeconds": ExportEncoderCosts.estimatedSeconds(for: unsteppedSettings)
        .map { $0 as Any } ?? NSNull(),
] as [String: Any]

// MARK: - The live projects

func apply(_ project: ReelProject, _ op: ReelOp) throws -> ReelProject {
    switch try project.applying([op]) {
    case .applied(let next): return next
    case .identity: return project
    case .refused(let refusal): throw ProbeError("\(op.name) was refused: \(refusal.reason)")
    }
}

/// The project with AV.mov in its media, on a canvas of `width` × `height` at 30 fps.
func withMedia(width: Int, height: Int) throws -> (ReelProject, UInt32) {
    var project = try apply(
        ProjectDocument().project, .setCanvas(width: width, height: height, fps: Fps.thirty))
    let asset = AVURLAsset(url: media)
    let video = asset.tracks(withMediaType: .video).first
    let size = video?.naturalSize ?? .zero
    let id = project.snapshot.nextId
    project = try apply(project, .addMedia(descriptor: MediaDescriptor(
        path: media.path, kind: .video, duration: CompositionBuilder.ticks(asset.duration),
        width: Int(size.width), height: Int(size.height), fps: Fps.thirty,
        hasVideo: video != nil, hasAudio: !asset.tracks(withMediaType: .audio).isEmpty)))
    return (project, id)
}

func a1() throws -> ReelProject {
    var (project, id) = try withMedia(width: 640, height: 360)
    guard let track = project.snapshot.tracks.first?.id else { throw ProbeError("no track") }
    project = try apply(project, .addClip(track: track, media: id, at: 0))
    project = try apply(project, .addTrack(index: project.snapshot.tracks.count, name: "Titles"))
    guard let titles = project.snapshot.tracks.last?.id else { throw ProbeError("no titles") }
    return try apply(project, .addTextClip(
        track: titles, at: 0, duration: 2 * ReelTime.perSecond, text: TextPatch(content: "AV1")))
}

func w9() throws -> ReelProject {
    var (project, id) = try withMedia(width: 1920, height: 1080)
    guard let track = project.snapshot.tracks.first?.id else { throw ProbeError("no track") }
    for k in 0..<24 {
        project = try apply(project, .addClip(
            track: track, media: id, at: Ticks(k) * 5 * ReelTime.perSecond))
    }
    let clips = project.snapshot.clips.map(\.id)
    return try apply(project, .setVideo(clips: clips, patch: VideoPatch(scale: 3.0)))
}

func urls(_ project: ReelProject) -> [UInt32: URL] {
    var out: [UInt32: URL] = [:]
    for item in project.snapshot.media { out[item.id] = URL(fileURLWithPath: item.path) }
    return out
}

func export(
    _ project: ReelProject, _ preset: String, speed: EncoderSpeed? = nil
) throws -> ExportSettings {
    var overrides: [String: Any] = [:]
    if let speed { overrides["encoder_speed"] = speed.rawValue }
    return try ReelExport.settings(
        project, preset: preset, overrides: overrides.isEmpty ? nil : overrides)
}

func describe(_ s: ExportSettings) -> [String: Any] {
    ["preset": s.preset, "writer": s.writer ?? NSNull(), "speed": s.encoderSpeed?.rawValue
        ?? NSNull(), "color": s.color ?? NSNull(), "width": s.width, "height": s.height,
     "frames": s.sequenceFrameCount ?? 0]
}

/// A private stored property, by reflection.
func reflected<T>(_ object: Any, _ name: String, as: T.Type) -> T? {
    Mirror(reflecting: object).children.first { $0.label == name }?.value as? T
}

func spin(until done: () -> Bool, timeout: Double) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !done(), Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return done()
}

func out(_ name: String) -> URL {
    let url = outFolder.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    return url
}

func headlessSheet(
    _ project: ReelProject, _ settings: ExportSettings, to url: URL
) -> ExportProgressSheetController {
    let sheet = ExportProgressSheetController(
        project: project, urls: urls(project), settings: settings, to: url)
    _ = sheet.view
    sheet.viewDidAppear()
    return sheet
}

func sheetFinished(_ sheet: ExportProgressSheetController) -> Bool {
    reflected(sheet, "didFinish", as: Bool.self) == true
}

/// What the shared queue and ledger did during a live row: every job's state at each
/// change, stamped by a sequence number, and the sequence at which the sheet was first
/// seen finished (checked at every change and every spin, before the jobs are read).
final class Watch {
    let queue = ExportQueueController.shared
    var seq = 0
    var sheet: ExportProgressSheetController?
    var sheetFinishedAt: Int?
    var firstSeen: [String: Int] = [:]   // "<id>:<state>" → seq
    var ledgerCosts: [[UInt64]] = []
    var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: ExportQueueController.didChangeNotification, object: queue, queue: nil
        ) { [unowned self] _ in self.tick() })
        observers.append(NotificationCenter.default.addObserver(
            forName: ExportEncoderLedger.didChangeNotification,
            object: ExportEncoderLedger.shared, queue: nil
        ) { [unowned self] _ in
            self.ledgerCosts.append(ExportEncoderLedger.shared.runningCosts)
            self.tick()
        })
    }

    func tick() {
        seq += 1
        if sheetFinishedAt == nil, let sheet, sheetFinished(sheet) { sheetFinishedAt = seq }
        for job in queue.jobs {
            let key = "\(job.id):\(job.state.rawValue)"
            if firstSeen[key] == nil { firstSeen[key] = seq }
        }
    }

    func at(_ id: UInt64, _ state: ExportQueueController.State) -> Any {
        firstSeen["\(id):\(state.rawValue)"].map { $0 as Any } ?? NSNull()
    }

    func job(_ id: UInt64) -> [String: Any] {
        let job = queue.job(id)
        return [
            "state": job?.state.rawValue ?? "missing", "message": job?.message ?? NSNull(),
            "waiting": at(id, .waiting), "running": at(id, .running),
            "completed": at(id, .completed), "failed": at(id, .failed),
        ]
    }

    func stop() { observers.forEach(NotificationCenter.default.removeObserver) }
}

// MARK: - Q: the live queue

let ledger = ExportEncoderLedger.shared
let realPhysical = ledger.physicalMemory
var q: [String: Any] = [:]
do {
    let small = try a1()
    let long = try w9()
    let sheetSettings = try export(long, "av1", speed: .smaller)
    let aSettings = try export(small, "av1")
    let hSettings = try export(small, "h264")
    q["sheetSettings"] = describe(sheetSettings)
    q["aSettings"] = describe(aSettings)

    // Q1, Q2, Q4: the budget equal to the sheet job's own cost.
    let sheetCost = ExportEncoderCosts.memoryBytes(for: sheetSettings, budget: 0)
    ledger.physicalMemory = 4 * sheetCost
    q["q1Physical"] = ledger.physicalMemory
    let watch = Watch()
    let sheet = headlessSheet(long, sheetSettings, to: out("q1-sheet.mp4"))
    watch.sheet = sheet
    q["q1Booked"] = ledger.runningCosts
    let queue = ExportQueueController.shared
    let aURL = out("q1-a.mp4"), bURL = out("q1-b.mp4"), cURL = out("q1-c.mp4")
    let a = queue.enqueue(project: small, urls: urls(small), settings: aSettings, to: aURL)
    let b = queue.enqueue(project: small, urls: urls(small), settings: hSettings, to: bURL)
    let c = queue.enqueue(project: small, urls: urls(small), settings: hSettings, to: cURL)
    // Q2 and Q4, read at once: B is running and A held behind the sheet.
    q["q4BRunning"] = queue.job(b)?.state == .running
    q["q4A"] = queue.job(a).map { ExportQueueRowView.status($0) } ?? NSNull()
    q["q4C"] = queue.job(c).map { ExportQueueRowView.status($0) } ?? NSNull()
    q["q4ATip"] = queue.job(a).map { ExportQueueRowView.toolTip(for: $0) } ?? NSNull()
    q["q4CTip"] = queue.job(c).map { ExportQueueRowView.toolTip(for: $0) } ?? NSNull()
    AgentExports.shared.track(
        a, settings: aSettings, burnInTimecode: false,
        started: ProcessInfo.processInfo.systemUptime)
    q["q2"] = AgentExports.shared.status(a) ?? NSNull()
    q["q1HeldMessage"] = queue.job(a)?.message ?? NSNull()
    let sheetDone = spin(until: { sheetFinished(sheet) }, timeout: 600)
    watch.tick()
    let drained = spin(until: { queue.isIdle }, timeout: 120)
    watch.tick()
    q["q1"] = [
        "sheetDone": sheetDone, "drained": drained, "sheetFinishedAt": watch.sheetFinishedAt
            .map { $0 as Any } ?? NSNull(),
        "a": watch.job(a), "b": watch.job(b), "c": watch.job(c),
        "files": [aURL, bURL, cURL].map { FileManager.default.fileExists(atPath: $0.path) },
        "sheetStatus": reflected(sheet, "statusLabel", as: NSTextField.self)?.stringValue
            ?? "",
    ]
    q["q5Drained"] = ledger.runningCosts
    watch.stop()

    // Q3: a Mac so large nothing waits.
    ledger.physicalMemory = 1 << 40
    let watch3 = Watch()
    let fast = try export(long, "av1", speed: .faster)
    let sheet3 = headlessSheet(long, fast, to: out("q3-sheet.mp4"))
    watch3.sheet = sheet3
    let a3URL = out("q3-a.mp4")
    let a3 = queue.enqueue(project: small, urls: urls(small), settings: aSettings, to: a3URL)
    let sheet3Done = spin(until: { sheetFinished(sheet3) }, timeout: 600)
    watch3.tick()
    let drained3 = spin(until: { queue.isIdle }, timeout: 120)
    q["q3"] = [
        "sheetDone": sheet3Done, "drained": drained3,
        "sheetFinishedAt": watch3.sheetFinishedAt.map { $0 as Any } ?? NSNull(),
        "a": watch3.job(a3), "file": FileManager.default.fileExists(atPath: a3URL.path),
    ]
    watch3.stop()
    q["q5AfterQ3"] = ledger.runningCosts

    // Q5: two encoder jobs back to back — the second launches inside the first's `end`.
    let x = queue.enqueue(project: small, urls: urls(small), settings: aSettings,
                          to: out("q5-x.mp4"))
    let y = queue.enqueue(project: small, urls: urls(small), settings: aSettings,
                          to: out("q5-y.mp4"))
    let drained5 = spin(until: { queue.isIdle }, timeout: 300)
    q["q5BackToBack"] = [
        "drained": drained5, "x": queue.job(x)?.state.rawValue ?? "missing",
        "y": queue.job(y)?.state.rawValue ?? "missing", "costs": ledger.runningCosts,
    ]

    // Q5: synchronous refusals, in the queue and in a sheet.
    guard let empty = ReelProject.new(width: 640, height: 360, fps: Fps.thirty) else {
        throw ProbeError("no empty project")
    }
    // A1's own `av1` settings (the core resolves none for an empty range) over the empty
    // handle: `Exporter.export` refuses it synchronously, `emptyTimeline`.
    let emptySettings = aSettings
    let z = queue.enqueue(project: empty, urls: [:], settings: emptySettings,
                          to: out("q5-z.mp4"))
    q["q5QueueRefusal"] = [
        "state": queue.job(z)?.state.rawValue ?? "missing",
        "message": queue.job(z)?.message ?? NSNull(), "costs": ledger.runningCosts,
    ]
    let refused = headlessSheet(empty, emptySettings, to: out("q5-sheet.mp4"))
    q["q5SheetRefusal"] = [
        "finished": sheetFinished(refused), "costs": ledger.runningCosts,
        "status": reflected(refused, "statusLabel", as: NSTextField.self)?.stringValue ?? "",
    ]
} catch {
    q["error"] = "\(error)"
}
ledger.physicalMemory = realPhysical
answer["q"] = q
finish()
