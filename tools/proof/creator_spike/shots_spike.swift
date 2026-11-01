// Road map "creator-jobs" CJ2a, spike CJ-S4 — the shot signature.
//
// Built alone (as `main.swift`) through `tools/proof/swift_build.py` by
// `shots_spike.py`. One file per run:
//
//   shots_spike <movie> <out.json> <fps>
//
// Decodes the first video track in presentation order through
// `AVAssetReaderTrackOutput`, 32BGRA at long side 256, and for every frame
// computes three candidate signals against the two frames decoded before it
// (the VFR-safe neighbours p1, p2): the L1 distance of a 32-bin luma
// histogram of a 64 × 36 area downscale, of a 4 × 4 × 4 colour histogram at
// long side 256 (both histograms of whole-pixel counts, their L1 divided by
// the pixel count, so it lies in 0…2 and equal counts give equal values),
// and the 64 × 36 luma mean absolute difference over 255 (the SAD fallback).
// The answer is `{width, height, frames: [{pts, k, l1, l2, c1, c2, s1, s2}]}`
// where `pts` is in ticks (600 000 a second) and `k` is round(pts × fps) for
// the media's rate as the caller gives it (the file's `r_frame_rate`, not the
// track's nominal rate, which a VFR file averages); the first frame on an
// index wins.
import AVFoundation
import CoreVideo
import Foundation

let args = CommandLine.arguments
guard args.count == 4, let fps = Double(args[3]) else {
    FileHandle.standardError.write(Data("usage: shots_spike <movie> <out.json> <fps>\n".utf8))
    exit(2)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]),
                       options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
guard let track = asset.tracks(withMediaType: .video).first else {
    FileHandle.standardError.write(Data("no video track\n".utf8))
    exit(1)
}
let natural = track.naturalSize
let longSide = 256.0
let scale = longSide / Double(max(natural.width, natural.height))
let width = Int((Double(natural.width) * scale).rounded())
let height = Int((Double(natural.height) * scale).rounded())

let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])
output.alwaysCopiesSampleData = false
reader.add(output)
guard reader.startReading() else {
    FileHandle.standardError.write(Data("reader failed: \(String(describing: reader.error))\n".utf8))
    exit(1)
}

struct Signature {
    var luma: [Double]    // 32 bins
    var colour: [Double]  // 64 bins
    var small: [Double]   // 64 × 36 luma, 0…255
}

func signature(_ buffer: CVPixelBuffer) -> Signature {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let w = CVPixelBufferGetWidth(buffer)
    let h = CVPixelBufferGetHeight(buffer)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    var colour = [Double](repeating: 0, count: 64)
    var lumaFull = [Double](repeating: 0, count: w * h)
    for y in 0..<h {
        for x in 0..<w {
            let p = base + y * row + x * 4
            let b = Int(p[0]), g = Int(p[1]), r = Int(p[2])
            colour[(r >> 6) * 16 + (g >> 6) * 4 + (b >> 6)] += 1
            lumaFull[y * w + x] = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
        }
    }
    // 64 × 36 by area: each target cell averages the source pixels whose
    // centres fall in it.
    let sw = 64, sh = 36
    var small = [Double](repeating: 0, count: sw * sh)
    var counts = [Double](repeating: 0, count: sw * sh)
    for y in 0..<h {
        let ty = min(sh - 1, y * sh / h)
        for x in 0..<w {
            let tx = min(sw - 1, x * sw / w)
            small[ty * sw + tx] += lumaFull[y * w + x]
            counts[ty * sw + tx] += 1
        }
    }
    for i in 0..<small.count where counts[i] > 0 { small[i] /= counts[i] }
    var luma = [Double](repeating: 0, count: 32)
    for v in small { luma[min(31, Int(v) >> 3)] += 1 }
    return Signature(luma: luma, colour: colour, small: small)
}

/// L1 of two histograms of whole-pixel COUNTS, summed exactly and divided
/// once by the pixel count, so two distances that are equal in counts are
/// equal to the bit (a flash's two sides tie, as the rule's tie-break needs).
func l1(_ a: [Double], _ b: [Double]) -> Double {
    var sum = 0.0
    var total = 0.0
    for i in 0..<a.count {
        sum += abs(a[i] - b[i])
        total += a[i]
    }
    return total > 0 ? sum / total : 0
}

func sad(_ a: [Double], _ b: [Double]) -> Double {
    var sum = 0.0
    for i in 0..<a.count { sum += abs(a[i] - b[i]) }
    return sum / Double(a.count) / 255
}

var rows: [[String: Any]] = []
var p1: Signature?
var p2: Signature?
var seen = Set<Int>()
while let sample = output.copyNextSampleBuffer() {
    guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
    let ticks = Int64((pts.seconds * 600000).rounded())
    let k = Int((pts.seconds * fps).rounded())
    guard !seen.contains(k) else { continue }  // the first frame on an index wins
    seen.insert(k)
    let s = signature(buffer)
    var row: [String: Any] = ["pts": ticks, "k": k]
    row["l1"] = p1.map { l1(s.luma, $0.luma) } ?? 0
    row["l2"] = p2.map { l1(s.luma, $0.luma) } ?? 0
    row["c1"] = p1.map { l1(s.colour, $0.colour) } ?? 0
    row["c2"] = p2.map { l1(s.colour, $0.colour) } ?? 0
    row["s1"] = p1.map { sad(s.small, $0.small) } ?? 0
    row["s2"] = p2.map { sad(s.small, $0.small) } ?? 0
    rows.append(row)
    p2 = p1
    p1 = s
}
if reader.status == .failed {
    FileHandle.standardError.write(Data("reader failed: \(String(describing: reader.error))\n".utf8))
    exit(1)
}
let answer: [String: Any] = ["width": width, "height": height, "fps": fps, "frames": rows]
let data = try JSONSerialization.data(withJSONObject: answer)
try data.write(to: URL(fileURLWithPath: args[2]))
print("\(rows.count) frames at \(width)×\(height)")
