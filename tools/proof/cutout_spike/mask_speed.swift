// Road map "creator-jobs" CO0, spike CO-S1 — which segmentation, at what
// rate, how fast (speed only: S-KEY1 is missing, so J, B, flicker, Best, the
// read size and the rotation are owed).
//
// Vision alone, no app sources: compiled from this file only, copied to
// `tools/proof/work/cutout_spike/bin/mask_speed/main.swift`, through
// `swift_build.build` (`cutout_spike.py`).
//
//   mask_speed job <movie> <candidate> <every|15|10> <source|1920>
//   mask_speed first <movie> <candidate>
//   mask_speed dump <movie> <every|15|10> <out-dir>
//
// Candidates: `person-balanced`, `person-accurate`
// (`VNGeneratePersonSegmentationRequest` at that quality, 8-bit output) and
// `instance-scaled` (`VNGeneratePersonInstanceMaskRequest`, then
// `generateScaledMaskForImage` over every instance). Every request is pinned
// to the Neural Engine with `setComputeDevice(_:for:)` on each stage it
// supports (`effects_spike/vision_common.swift`'s `pin`), and a FRESH request
// is made for every sampled frame (CJ-23's sample rule: every frame, or the
// first frame at or after each k / rate s).
//
// `job` decodes every frame through `AVAssetReaderTrackOutput`, 32BGRA, at
// the read size (`source`, or a long side of 1920 for a larger source), runs
// the request on each sampled frame and copies its mask out to bytes; the
// wall time covers the decode, the requests and the copies. Its last stdout
// line is JSON: {frames, requests, wall_s, source_s, realtime, mask_w,
// mask_h, revision, device, read_w, read_h}.
//
// `first` times a fresh process's first request on the movie's first frame
// (ms, the handler and the perform), last line JSON {first_call_ms, …}.
//
// `dump` writes Standard's masks (person `.balanced`, source size) at the
// rate: `<out>/masks.bin`, each mask 8-bit row-packed, and `<out>/index.json`
// {width, height, timescale, fps, pts: [value…], frames: [source frame
// index…], all_pts: [every decoded frame's time…], source_frames}.
import AVFoundation
import CoreML
import CoreVideo
import Foundation
import Vision

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("mask_speed: \(message)\n".utf8))
    exit(1)
}

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func nowS() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

enum Candidate: String {
    case personBalanced = "person-balanced"
    case personAccurate = "person-accurate"
    case instanceScaled = "instance-scaled"
}

/// The Neural Engine on every stage the request supports; answers the
/// device's description, or "auto" when a stage has none.
func pinNeuralEngine(_ request: VNRequest) -> String {
    guard let stages = try? request.supportedComputeStageDevices else { return "auto" }
    var named = "auto"
    for (stage, devices) in stages {
        guard let pick = devices.first(where: {
            if case .neuralEngine = $0 { return true } else { return false }
        }) else { return "auto (no neural engine on a stage)" }
        request.setComputeDevice(pick, for: stage)
        if case .neuralEngine(let engine) = pick { named = "ane(\(engine.totalCoreCount) cores)" }
    }
    return named
}

/// One fresh request on `frame`; the mask as 8-bit row-packed bytes.
func mask(_ candidate: Candidate, _ frame: CVPixelBuffer)
    throws -> (bytes: [UInt8], width: Int, height: Int, revision: Int, device: String)
{
    let handler = VNImageRequestHandler(cvPixelBuffer: frame, options: [:])
    switch candidate {
    case .personBalanced, .personAccurate:
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = candidate == .personBalanced ? .balanced : .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let device = pinNeuralEngine(request)
        try handler.perform([request])
        guard let buffer = request.results?.first?.pixelBuffer else {
            throw NSError(domain: "mask_speed", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "no person mask"])
        }
        let (bytes, w, h) = copyOut(buffer)
        return (bytes, w, h, request.revision, device)
    case .instanceScaled:
        let request = VNGeneratePersonInstanceMaskRequest()
        let device = pinNeuralEngine(request)
        try handler.perform([request])
        guard let observation = request.results?.first else {
            // No person: an empty mask at the frame's size.
            let w = CVPixelBufferGetWidth(frame), h = CVPixelBufferGetHeight(frame)
            return ([UInt8](repeating: 0, count: w * h), w, h, request.revision, device)
        }
        let buffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances, from: handler)
        let (bytes, w, h) = copyOut(buffer)
        return (bytes, w, h, request.revision, device)
    }
}

/// A one-component buffer as row-packed bytes; floats as round(v × 255).
func copyOut(_ buffer: CVPixelBuffer) -> ([UInt8], Int, Int) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let base = CVPixelBufferGetBaseAddress(buffer)!
    var out = [UInt8](repeating: 0, count: w * h)
    switch CVPixelBufferGetPixelFormatType(buffer) {
    case kCVPixelFormatType_OneComponent8:
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<h { for x in 0..<w { out[y * w + x] = bytes[y * stride + x] } }
    case kCVPixelFormatType_OneComponent32Float:
        for y in 0..<h {
            let row = (base + y * stride).assumingMemoryBound(to: Float32.self)
            for x in 0..<w { out[y * w + x] = UInt8(max(0, min(255, (row[x] * 255).rounded()))) }
        }
    case kCVPixelFormatType_OneComponent16Half:
        for y in 0..<h {
            let row = (base + y * stride).assumingMemoryBound(to: Float16.self)
            for x in 0..<w {
                out[y * w + x] = UInt8(max(0, min(255, (Float(row[x]) * 255).rounded())))
            }
        }
    default:
        die("an unhandled mask format \(CVPixelBufferGetPixelFormatType(buffer))")
    }
    return (out, w, h)
}

struct Reader {
    let reader: AVAssetReader
    let output: AVAssetReaderTrackOutput
    let fps: Double
    let duration: Double
    let timescale: Int32
    let size: (Int, Int)
}

/// Every frame, 32BGRA, at `readSize` (`source` or `1920`: a long side of
/// 1920 for a larger source, never up).
func open(_ path: String, readSize: String) -> Reader {
    let asset = AVURLAsset(
        url: URL(fileURLWithPath: path), options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let track = asset.tracks(withMediaType: .video).first else { die("\(path): no video") }
    let natural = track.naturalSize
    var w = Int(natural.width), h = Int(natural.height)
    if readSize == "1920", max(w, h) > 1920 {
        let scale = 1920.0 / Double(max(w, h))
        w = Int((Double(w) * scale / 2).rounded()) * 2
        h = Int((Double(h) * scale / 2).rounded()) * 2
    }
    guard let reader = try? AVAssetReader(asset: asset) else { die("\(path): no reader") }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
    ])
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else { die("\(path): \(String(describing: reader.error))") }
    let fps = Double(track.nominalFrameRate)
    return Reader(reader: reader, output: output, fps: fps > 0 ? fps : 30,
                  duration: CMTimeGetSeconds(asset.duration), timescale: track.naturalTimeScale,
                  size: (w, h))
}

/// CJ-23's sample rule: every frame (at most 30 a second), or the first frame
/// at or after each k / rate s. `next` is the next sample time.
struct Sampler {
    let rate: Double?
    var next = 0.0
    var k = 0
    var last = -1.0
    init(_ name: String) { rate = name == "every" ? nil : Double(name) }

    mutating func takes(_ pts: Double) -> Bool {
        guard let rate else {
            // Every frame, capped at 30 a second.
            if last >= 0, pts < last + 1.0 / 30.0 - 1e-6 { return false }
            last = pts
            return true
        }
        guard pts + 1e-9 >= next else { return false }
        while Double(k) / rate <= pts + 1e-9 { k += 1 }
        next = Double(k) / rate
        return true
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    die("usage: mask_speed job <movie> <candidate> <every|15|10> <source|1920> | "
        + "first <movie> <candidate> | dump <movie> <rate> <out-dir>")
}

switch arguments[1] {
case "job":
    guard arguments.count == 6, let candidate = Candidate(rawValue: arguments[3]) else {
        die("job <movie> <candidate> <every|15|10> <source|1920>")
    }
    let started = nowS()
    let input = open(arguments[2], readSize: arguments[5])
    var sampler = Sampler(arguments[4])
    var frames = 0, requests = 0, maskW = 0, maskH = 0, revision = 0, device = ""
    var checksum = 0
    while let sample = input.output.copyNextSampleBuffer() {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
        frames += 1
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
        guard sampler.takes(pts) else { continue }
        do {
            let answer = try autoreleasepool { try mask(candidate, buffer) }
            requests += 1
            maskW = answer.width
            maskH = answer.height
            revision = answer.revision
            device = answer.device
            checksum &+= Int(answer.bytes[answer.bytes.count / 2])
        } catch {
            die("frame at \(pts) s: \(error.localizedDescription)")
        }
    }
    guard input.reader.status == .completed else {
        die("reader ended \(input.reader.status.rawValue): \(String(describing: input.reader.error))")
    }
    let wall = nowS() - started
    emit(["frames": frames, "requests": requests, "wall_s": wall, "source_s": input.duration,
          "realtime": input.duration / wall, "mask_w": maskW, "mask_h": maskH,
          "revision": revision, "device": device, "read_w": input.size.0,
          "read_h": input.size.1, "checksum": checksum])
case "first":
    guard let candidate = Candidate(rawValue: arguments[3]) else { die("first <movie> <candidate>") }
    let input = open(arguments[2], readSize: "source")
    guard let sample = input.output.copyNextSampleBuffer(),
          let buffer = CMSampleBufferGetImageBuffer(sample)
    else { die("no first frame") }
    let started = nowS()
    do {
        let answer = try mask(candidate, buffer)
        emit(["first_call_ms": (nowS() - started) * 1000, "mask_w": answer.width,
              "mask_h": answer.height, "device": answer.device, "revision": answer.revision])
    } catch {
        die("the first request: \(error.localizedDescription)")
    }
case "dump":
    guard arguments.count == 5 else { die("dump <movie> <rate> <out-dir>") }
    let out = URL(fileURLWithPath: arguments[4], isDirectory: true)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let input = open(arguments[2], readSize: "source")
    var sampler = Sampler(arguments[3])
    FileManager.default.createFile(atPath: out.appendingPathComponent("masks.bin").path, contents: nil)
    guard let handle = FileHandle(forWritingAtPath: out.appendingPathComponent("masks.bin").path)
    else { die("cannot write masks.bin") }
    var pts: [Int64] = [], frameIndex: [Int] = [], width = 0, height = 0, index = -1
    var allPts: [Int64] = []
    while let sample = input.output.copyNextSampleBuffer() {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
        index += 1
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        allPts.append(CMTimeConvertScale(time, timescale: input.timescale,
                                         method: .roundHalfAwayFromZero).value)
        guard sampler.takes(CMTimeGetSeconds(time)) else { continue }
        do {
            let answer = try autoreleasepool { try mask(.personBalanced, buffer) }
            width = answer.width
            height = answer.height
            handle.write(Data(answer.bytes))
            pts.append(CMTimeConvertScale(time, timescale: input.timescale,
                                          method: .roundHalfAwayFromZero).value)
            frameIndex.append(index)
        } catch {
            die("dump at \(CMTimeGetSeconds(time)) s: \(error.localizedDescription)")
        }
    }
    try? handle.close()
    let index_ = ["width": width, "height": height, "timescale": Int(input.timescale),
                  "fps": input.fps, "pts": pts, "frames": frameIndex, "all_pts": allPts,
                  "source_frames": index + 1, "duration_s": input.duration] as [String: Any]
    let data = try! JSONSerialization.data(withJSONObject: index_, options: [.sortedKeys])
    try! data.write(to: out.appendingPathComponent("index.json"))
    emit(["masks": pts.count, "width": width, "height": height, "source_frames": index + 1])
default:
    die("unknown mode \(arguments[1])")
}
