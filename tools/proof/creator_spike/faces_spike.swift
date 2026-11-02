// Road map "creator-jobs" CJ3, spike CJ-S2 — Vision's face requests on video:
// on which device, at what rate and size they are deterministic, fast enough
// and accurate.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift` (`swift_build.app_sources()`, module FrameJob, the staticlib),
// optimised, through `tools/proof/swift_build.py`, by `faces_spike.py` and
// `face_fixtures.py`. Two modes, each answering one JSON line on stdout:
//
//   faces_spike image <png|jpg>
//   faces_spike run <movie> <long side|native> <rate> <rect device> <landmarks device|none>
//
// `image`: a fresh `VNDetectFaceRectanglesRequest` (revision 3) on the
// picture, every face's box in the top-left frame (0…1, y down), its
// confidence, roll and yaw: `{width, height, faces: [{box, confidence, roll,
// yaw}]}`, ordered by box centre x then y.
//
// `run`: the movie read through the app's own reader (`AnalysisFrames.read`,
// the direct arm, upright) at min(long side, the media's) over the whole
// media; sample k of `rate` a second at tick round(k × 600000 / rate) takes
// the first kept frame whose pts lies in [that tick, that tick + one sample
// interval) (CJ-33's rule; a frame serving two samples is analysed once). Per
// analysed frame a FRESH rectangles request on a fresh handler, revision 3,
// pinned with `AnalysisVision.pin` to `rect device`; then, unless `none`, a
// fresh `VNDetectFaceLandmarksRequest` (revision 3, `.constellation76Points`)
// over those faces on a fresh handler, pinned to `landmarks device`. The
// answer: `pin` per request (the joined readback and each stage's device or
// `auto`), `sha256` per request over its stored fields (the rectangles' pts,
// box, confidence, roll and yaw; the landmarks' mouth gap and width, each
// Float32's bits), `seconds` {decode, rectangles, landmarks, wall}, the source
// seconds and the real-time factor (source over decode + rectangles +
// landmarks), `read` [w, h], and `samples` [{k, pts, faces: [{box, conf,
// roll, yaw, gap, width}]}].
import AVFoundation
import CoreML
import CryptoKit
import Foundation
import Vision

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("faces_spike: \(message)\n".utf8))
    exit(1)
}

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

struct Found {
    var x, y, w, h, confidence, roll, yaw: Float
    var gap = Float.nan, width = Float.nan
}

/// Vision's lower-left box in the top-left frame.
func topLeft(_ box: CGRect) -> CGRect {
    CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
}

func ordered(_ faces: [Found]) -> [Found] {
    faces.sorted { a, b in
        let ax = a.x + a.w / 2, bx = b.x + b.w / 2
        if ax != bx { return ax < bx }
        return a.y + a.h / 2 < b.y + b.h / 2
    }
}

func found(_ o: VNFaceObservation) -> Found {
    let box = topLeft(o.boundingBox)
    return Found(
        x: Float(box.minX), y: Float(box.minY), w: Float(box.width), h: Float(box.height),
        confidence: o.confidence, roll: o.roll?.floatValue ?? .nan, yaw: o.yaw?.floatValue ?? .nan)
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

func device(_ name: String) -> AnalysisVision.Device {
    guard let d = AnalysisVision.Device(rawValue: name) else { die("no device \(name)") }
    return d
}

let args = CommandLine.arguments
guard args.count >= 3 else { die("faces_spike image <file> | run <movie> <side> <rate> <rect> <lm>") }

if args[1] == "image" {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { die("\(args[2]) does not read as an image") }
    let request = VNDetectFaceRectanglesRequest()
    request.revision = VNDetectFaceRectanglesRequestRevision3
    do {
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    } catch { die("Vision: \(error.localizedDescription)") }
    let faces = ordered((request.results ?? []).map(found))
    emit([
        "width": image.width, "height": image.height,
        "faces": faces.map { f -> [String: Any] in
            ["box": [f.x, f.y, f.w, f.h].map(Double.init), "confidence": Double(f.confidence),
             "roll": Double(f.roll), "yaw": Double(f.yaw)]
        },
    ])
    exit(0)
}

guard args[1] == "run", args.count == 7, let rate = Double(args[4]), rate > 0 else {
    die("run <movie> <long side|native> <rate> <rect device> <landmarks device|none>")
}
let url = URL(fileURLWithPath: args[2])
let rectDevice = device(args[5])
let landmarksDevice: AnalysisVision.Device? = args[6] == "none" ? nil : device(args[6])
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

var rectPin = "", landmarksPin = "none"
var rectStages: [String: String] = [:], landmarksStages: [String: String] = [:]
var rectHash = SHA256(), landmarksHash = SHA256()
var decodeS = 0.0, rectS = 0.0, landmarksS = 0.0
var samples: [Int: (pts: Int64, faces: [Found])] = [:]
var readSize = [0, 0]
var previous: Int64?

func feed(_ hash: inout SHA256, _ values: [Float]) {
    let bits = values.map { $0.bitPattern.littleEndian }
    bits.withUnsafeBytes { hash.update(bufferPointer: $0) }
}

func feed(_ hash: inout SHA256, pts: Int64) {
    withUnsafeBytes(of: pts.littleEndian) { hash.update(bufferPointer: $0) }
}

func analyse(_ picture: AnalysisPicture) throws -> [Found] {
    var wrapped: CVPixelBuffer?
    guard CVPixelBufferCreateWithBytes(
        kCFAllocatorDefault, picture.width, picture.height, kCVPixelFormatType_32BGRA,
        UnsafeMutableRawPointer(mutating: picture.bytes), picture.bytesPerRow, nil, nil, nil,
        &wrapped) == kCVReturnSuccess, let wrapped
    else { die("the frame could not be wrapped") }
    var t = now()
    let rect = VNDetectFaceRectanglesRequest()
    rect.revision = VNDetectFaceRectanglesRequestRevision3
    rectPin = AnalysisVision.pin(rect, to: rectDevice)
    rectStages = stages(rect)
    try VNImageRequestHandler(cvPixelBuffer: wrapped, options: [:]).perform([rect])
    let observations = rect.results ?? []
    rectS += now() - t
    var faces = observations.map(found)
    if let landmarksDevice, !observations.isEmpty {
        t = now()
        let marks = VNDetectFaceLandmarksRequest()
        marks.revision = VNDetectFaceLandmarksRequestRevision3
        marks.constellation = .constellation76Points
        marks.inputFaceObservations = observations
        landmarksPin = AnalysisVision.pin(marks, to: landmarksDevice)
        landmarksStages = stages(marks)
        try VNImageRequestHandler(cvPixelBuffer: wrapped, options: [:]).perform([marks])
        let size = CGSize(width: picture.width, height: picture.height)
        for (i, o) in (marks.results ?? []).enumerated() where i < faces.count {
            let boxH = Double(o.boundingBox.height) * Double(picture.height)
            guard boxH > 0, let inner = o.landmarks?.innerLips?.pointsInImage(imageSize: size),
                let outer = o.landmarks?.outerLips?.pointsInImage(imageSize: size),
                !inner.isEmpty, !outer.isEmpty
            else { continue }
            let ys = inner.map(\.y), xs = outer.map(\.x)
            faces[i].gap = Float((ys.max()! - ys.min()!) / boxH)
            faces[i].width = Float((xs.max()! - xs.min()!) / boxH)
        }
        landmarksS += now() - t
    } else if landmarksDevice != nil {
        let marks = VNDetectFaceLandmarksRequest()
        marks.revision = VNDetectFaceLandmarksRequestRevision3
        landmarksPin = AnalysisVision.pin(marks, to: landmarksDevice!)
        landmarksStages = stages(marks)
    }
    return ordered(faces)
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
        let faces = try analyse(picture)
        for k in ks { samples[k] = (pts, faces) }
    }
} catch { die("read: \(error.localizedDescription)") }
let wall = now() - started

var rows: [[String: Any]] = []
for k in 0..<sampleCount {
    let entry = samples[k] ?? (-1, [])
    feed(&rectHash, pts: entry.pts)
    for f in entry.faces {
        feed(&rectHash, [f.x, f.y, f.w, f.h, f.confidence, f.roll, f.yaw])
        feed(&landmarksHash, [f.gap, f.width])
    }
    rows.append([
        "k": k, "pts": entry.pts,
        "faces": entry.faces.map { f -> [String: Any] in
            var row: [String: Any] = [
                "box": [f.x, f.y, f.w, f.h].map(Double.init), "conf": Double(f.confidence),
                "roll": f.roll.isNaN ? NSNull() : Double(f.roll),
                "yaw": f.yaw.isNaN ? NSNull() : Double(f.yaw),
            ]
            if !f.gap.isNaN { row["gap"] = Double(f.gap) }
            if !f.width.isNaN { row["width"] = Double(f.width) }
            return row
        },
    ])
}
let sourceS = Double(media.duration) / 600_000
let work = decodeS + rectS + landmarksS
func hex(_ h: SHA256) -> String { h.finalize().map { String(format: "%02x", $0) }.joined() }
emit([
    "pin": ["rectangles": ["joined": rectPin, "stages": rectStages],
            "landmarks": ["joined": landmarksPin, "stages": landmarksStages]],
    "sha256": ["rectangles": hex(rectHash), "landmarks": hex(landmarksHash)],
    "seconds": ["decode": decodeS, "rectangles": rectS, "landmarks": landmarksS, "wall": wall],
    "source_s": sourceS, "realtime": work > 0 ? sourceS / work : 0,
    "read": readSize, "long_side": longSide, "rate": rate, "frames_fps": [media.fps.num, media.fps.den],
    "sample_count": sampleCount, "analysed": Set(samples.values.map(\.pts)).count,
    "samples": rows,
])
