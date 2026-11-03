// Road map "creator-jobs" VR1, spike VR-S1 — Vision's person and saliency
// requests on video: at what rate and frame size they run deterministically
// and fast enough, on which device (CJ-S2's rules 1–3 re-run for them).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift` (`swift_build.app_sources()`, module FrameJob, the staticlib),
// optimised, through `tools/proof/swift_build.py`, by `subjects_spike.py`. One
// mode, answering one JSON line on stdout:
//
//   subjects_spike run <movie> <long side|native> <rate> <people device|none>
//                      <salient device|none> [whole]
//
// The movie is read through the app's own reader (`AnalysisFrames.read`, the
// direct arm, upright) at min(long side, the media's) over the whole media;
// sample k of `rate` a second at tick round(k × 600000 / rate) takes the first
// kept frame whose pts lies in [that tick, that tick + one sample interval)
// (CJ-33's rule; a frame serving two samples is analysed once). Per analysed
// frame a FRESH `VNDetectHumanRectanglesRequest` (revision 2, `upperBodyOnly`
// true, spec §11 VR-4 as VR-10 amends it; `whole` sets it false, a comparison
// row only, so the amendment's figures stay reproducible) and a FRESH
// `VNGenerateAttentionBasedSaliencyImageRequest` (revision 2), each unless
// `none`, each pinned with `AnalysisVision.pin` to its device, performed
// together on ONE fresh `VNImageRequestHandler`. The answer: `pin`
// per request (the joined readback and each stage's device or `auto`),
// `sha256` per request over its stored fields (each sample's pts, then each
// box's x, y, w, h and confidence as Float32 bits, in CJ-31's order),
// `seconds` {decode, vision, wall}, the source seconds and the real-time
// factor (source over decode + vision), `read` [w, h], and `samples` [{k, pts,
// people: [{box, conf}], salient: [{box, conf}]}], boxes top-left 0…1.
import AVFoundation
import CoreML
import CryptoKit
import Foundation
import Vision

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("subjects_spike: \(message)\n".utf8))
    exit(1)
}

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

struct Found {
    var x, y, w, h, confidence: Float
}

/// Vision's lower-left box in the top-left frame.
func topLeft(_ box: CGRect) -> CGRect {
    CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
}

func ordered(_ boxes: [Found]) -> [Found] {
    boxes.sorted { a, b in
        let ax = a.x + a.w / 2, bx = b.x + b.w / 2
        if ax != bx { return ax < bx }
        return a.y + a.h / 2 < b.y + b.h / 2
    }
}

func found(_ box: CGRect, _ confidence: Float) -> Found {
    let b = topLeft(box)
    return Found(
        x: Float(b.minX), y: Float(b.minY), w: Float(b.width), h: Float(b.height),
        confidence: confidence)
}

func stages(_ request: VNRequest) -> [String: String] {
    guard let supported = try? request.supportedComputeStageDevices else { return [:] }
    var out: [String: String] = [:]
    for stage in supported.keys {
        out[stage.rawValue] = request.computeDevice(for: stage).map(AnalysisVision.name(of:))
            ?? "auto"
    }
    return out
}

func device(_ name: String) -> AnalysisVision.Device? {
    if name == "none" { return nil }
    guard let d = AnalysisVision.Device(rawValue: name) else { die("no device \(name)") }
    return d
}

let args = CommandLine.arguments
guard args.count == 7 || args.count == 8, args[1] == "run", let rate = Double(args[4]), rate > 0
else {
    die("run <movie> <long side|native> <rate> <people device|none> <salient device|none>")
}
let url = URL(fileURLWithPath: args[2])
let peopleDevice = device(args[5])
let salientDevice = device(args[6])
/// An eighth argument `whole` sets `upperBodyOnly` false — a comparison row
/// only; the kind's request is the upper-body one (VR-4 as VR-10 amends it).
let upperBodyOnly = !(args.count == 8 && args[7] == "whole")
guard peopleDevice != nil || salientDevice != nil else { die("both requests are none") }
let descriptor: MediaDescriptor
do { descriptor = try MediaImporter.probeBlocking(url: url) } catch { die("probe: \(error)") }
guard let blank = ReelProject.new(width: 1920, height: 1080, fps: Fps(num: 30, den: 1)),
    let media = (try? blank.applying(.addMedia(descriptor: descriptor)))?.project?.snapshot
        .media.last
else { die("no media") }
let native = max(media.width, media.height)
let longSide = args[3] == "native" ? native : min(Int(args[3]) ?? native, native)
let frames = AnalysisGrid(media: media)
let interval = 600_000 / rate
func sampleTicks(_ k: Int) -> Double { (Double(k) * 600_000 / rate).rounded() }
let sampleCount = max(1, Int((Double(media.duration) * rate / 600_000 - 1e-6).rounded(.up)))

/// The samples frame `pts` serves: k with previous < ticks(k) ≤ pts and
/// pts < ticks(k) + interval.
func served(_ pts: Int64, after previous: Int64?) -> [Int] {
    var k = max(0, Int((Double(pts) * rate / 600_000).rounded(.down)) + 1)
    while k > 0, sampleTicks(k) > Double(pts) { k -= 1 }
    var out: [Int] = []
    while k >= 0, sampleTicks(k) <= Double(pts) {
        let t = sampleTicks(k)
        if let previous, t <= Double(previous) { break }
        if Double(pts) >= t + interval { break }
        if k < sampleCount { out.append(k) }
        k -= 1
    }
    return out.reversed()
}

var peoplePin = "none", salientPin = "none"
var peopleStages: [String: String] = [:], salientStages: [String: String] = [:]
var peopleHash = SHA256(), salientHash = SHA256()
var decodeS = 0.0, visionS = 0.0
var samples: [Int: (pts: Int64, people: [Found], salient: [Found])] = [:]
var readSize = [0, 0]
var previous: Int64?

func feed(_ hash: inout SHA256, _ values: [Float]) {
    let bits = values.map { $0.bitPattern.littleEndian }
    bits.withUnsafeBytes { hash.update(bufferPointer: $0) }
}

func feed(_ hash: inout SHA256, pts: Int64) {
    withUnsafeBytes(of: pts.littleEndian) { hash.update(bufferPointer: $0) }
}

func analyse(_ picture: AnalysisPicture) throws -> ([Found], [Found]) {
    var wrapped: CVPixelBuffer?
    guard CVPixelBufferCreateWithBytes(
        kCFAllocatorDefault, picture.width, picture.height, kCVPixelFormatType_32BGRA,
        UnsafeMutableRawPointer(mutating: picture.bytes), picture.bytesPerRow, nil, nil, nil,
        &wrapped) == kCVReturnSuccess, let wrapped
    else { die("the frame could not be wrapped") }
    let t = now()
    var requests: [VNRequest] = []
    var people: VNDetectHumanRectanglesRequest?
    var salient: VNGenerateAttentionBasedSaliencyImageRequest?
    if let peopleDevice {
        let request = VNDetectHumanRectanglesRequest()
        request.revision = VNDetectHumanRectanglesRequestRevision2
        request.upperBodyOnly = upperBodyOnly
        peoplePin = AnalysisVision.pin(request, to: peopleDevice)
        peopleStages = stages(request)
        requests.append(request)
        people = request
    }
    if let salientDevice {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        request.revision = VNGenerateAttentionBasedSaliencyImageRequestRevision2
        salientPin = AnalysisVision.pin(request, to: salientDevice)
        salientStages = stages(request)
        requests.append(request)
        salient = request
    }
    try VNImageRequestHandler(cvPixelBuffer: wrapped, options: [:]).perform(requests)
    visionS += now() - t
    let personBoxes = (people?.results ?? []).map { found($0.boundingBox, $0.confidence) }
    let salientBoxes = (salient?.results?.first?.salientObjects ?? []).map {
        found($0.boundingBox, $0.confidence)
    }
    return (ordered(personBoxes), ordered(salientBoxes))
}

let started = now()
do {
    let source = AnalysisFrames.Source(media: media, url: url, input: nil)
    var lastFrameEnd = now()
    _ = try AnalysisFrames.read(
        range: 0...frames.lastIndex, grid: frames, source: source, longSide: longSide,
        cancelled: { false }
    ) { _, pts, picture in
        decodeS += now() - lastFrameEnd
        defer {
            previous = pts
            lastFrameEnd = now()
        }
        readSize = [picture.width, picture.height]
        let ks = served(pts, after: previous)
        guard !ks.isEmpty else { return }
        let (people, salient) = try autoreleasepool { try analyse(picture) }
        for k in ks { samples[k] = (pts, people, salient) }
    }
} catch { die("read: \(error.localizedDescription)") }
let wall = now() - started

func rowsOf(_ boxes: [Found]) -> [[String: Any]] {
    boxes.map { ["box": [$0.x, $0.y, $0.w, $0.h].map(Double.init), "conf": Double($0.confidence)] }
}

var rows: [[String: Any]] = []
for k in 0..<sampleCount {
    let entry = samples[k] ?? (-1, [], [])
    feed(&peopleHash, pts: entry.pts)
    feed(&salientHash, pts: entry.pts)
    for f in entry.people { feed(&peopleHash, [f.x, f.y, f.w, f.h, f.confidence]) }
    for f in entry.salient { feed(&salientHash, [f.x, f.y, f.w, f.h, f.confidence]) }
    rows.append(["k": k, "pts": entry.pts, "people": rowsOf(entry.people),
                 "salient": rowsOf(entry.salient)])
}
let sourceS = Double(media.duration) / 600_000
let work = decodeS + visionS
func hex(_ h: SHA256) -> String { h.finalize().map { String(format: "%02x", $0) }.joined() }
emit([
    "pin": ["people": ["joined": peoplePin, "stages": peopleStages],
            "salient": ["joined": salientPin, "stages": salientStages]],
    "sha256": ["people": peopleDevice == nil ? "none" : hex(peopleHash),
               "salient": salientDevice == nil ? "none" : hex(salientHash)],
    "seconds": ["decode": decodeS, "vision": visionS, "wall": wall],
    "source_s": sourceS, "realtime": work > 0 ? sourceS / work : 0,
    "read": readSize, "long_side": longSide, "rate": rate, "upper_body_only": upperBodyOnly,
    "frames_fps": [media.fps.num, media.fps.den],
    "sample_count": sampleCount, "analysed": Set(samples.values.map(\.pts)).count,
    "samples": rows,
])
