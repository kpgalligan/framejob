// Built by tools/proof/log_proof.py as `main.swift` over every other file in
// `app/Sources` (`swift_build.py`), for its `decode-gap` mode (issue batch
// B101, #294). See that script's header.
//
// The first frame of each fixture, decoded by AVFoundation through
// `AVAssetReaderTrackOutput` at each pixel format the request names, read at
// the request's points. `DecoderSupport.enable()` runs before any reader:
// without the opt-in no VP9 file is read at all.
//
//   decode_gap_probe <request.json> <answer.json>
//
// The request: {"fixtures": [{"name", "path"}], "formats": [name], "points":
// [[x, y]]}, a format one of `x420`, `xf20`, `64RGBAHalf`, `128RGBAFloat` and
// `64RGBALE`. The answer: {"rows": [{fixture, format, values: [[x, y, [a, b,
// c]]]} or {fixture, format, error}]}: the biplanar formats as their 10-bit
// (Y, Cb, Cr) codes, chroma at (x/2, y/2); the RGB formats as R, G, B floats
// (`64RGBALE`'s 16-bit integers over 65535).
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

DecoderSupport.enable()

let request = (try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))) as? [String: Any]
    ?? [:]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let points = ((request["points"] as? [[Int]]) ?? []).filter { $0.count == 2 }

let formats: [String: OSType] = [
    "x420": kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
    "xf20": kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
    "64RGBAHalf": kCVPixelFormatType_64RGBAHalf,
    "128RGBAFloat": kCVPixelFormatType_128RGBAFloat,
    "64RGBALE": kCVPixelFormatType_64RGBALE,
]

struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
}

/// The first decoded frame of `url`'s first video track at `format`.
func firstFrame(_ url: URL, format: OSType) throws -> CVPixelBuffer {
    let asset = AVURLAsset(url: url)
    guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .video) else {
        throw ProbeFailure(description: "no video track")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: Int(format)])
    guard reader.canAdd(output) else { throw ProbeFailure(description: "the reader refused") }
    reader.add(output)
    guard reader.startReading() else {
        throw ProbeFailure(description: "the reader did not start: "
            + (reader.error.map { "\($0)" } ?? "no error"))
    }
    defer { reader.cancelReading() }
    guard let sample = output.copyNextSampleBuffer(),
        let buffer = CMSampleBufferGetImageBuffer(sample)
    else {
        throw ProbeFailure(description: "no frame: "
            + (reader.error.map { "\($0)" } ?? "status \(reader.status.rawValue)"))
    }
    guard CVPixelBufferGetPixelFormatType(buffer) == format else {
        throw ProbeFailure(description: "the frame came back as another format "
            + "\(CVPixelBufferGetPixelFormatType(buffer))")
    }
    return buffer
}

/// The values at `points` in `buffer`, read as `name`'s layout; a plane
/// with no base address throws, so the row is an unread format, not a gap.
func values(_ buffer: CVPixelBuffer, name: String) throws -> [[Any]] {
    let unread = ProbeFailure(description: "\(name): a plane has no base address")
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    var answered: [[Any]] = []
    for point in points {
        let x = point[0]
        let y = point[1]
        var triple: [Double] = []
        switch name {
        case "x420", "xf20":
            guard let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
                let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)
            else { throw unread }
            let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            let chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
            let yy = luma.advanced(by: y * lumaRow).assumingMemoryBound(to: UInt16.self)[x]
            let pair = chroma.advanced(by: (y / 2) * chromaRow)
                .assumingMemoryBound(to: UInt16.self)
            triple = [Double(yy >> 6), Double(pair[(x / 2) * 2] >> 6),
                      Double(pair[(x / 2) * 2 + 1] >> 6)]
        case "64RGBAHalf":
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw unread }
            let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer))
                .assumingMemoryBound(to: Float16.self)
            triple = (0..<3).map { Double(row[x * 4 + $0]) }
        case "128RGBAFloat":
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw unread }
            let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer))
                .assumingMemoryBound(to: Float32.self)
            triple = (0..<3).map { Double(row[x * 4 + $0]) }
        default:  // 64RGBALE
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw unread }
            let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer))
                .assumingMemoryBound(to: UInt16.self)
            triple = (0..<3).map { Double(UInt16(littleEndian: row[x * 4 + $0])) / 65535 }
        }
        answered.append([x, y, triple])
    }
    return answered
}

var rows: [[String: Any]] = []
for fixture in (request["fixtures"] as? [[String: Any]]) ?? [] {
    let name = fixture["name"] as? String ?? "?"
    let url = URL(fileURLWithPath: fixture["path"] as? String ?? "")
    for format in (request["formats"] as? [String]) ?? [] {
        guard let code = formats[format] else {
            rows.append(["fixture": name, "format": format, "error": "unknown format"])
            continue
        }
        do {
            let buffer = try firstFrame(url, format: code)
            rows.append(["fixture": name, "format": format,
                         "values": try values(buffer, name: format)])
        } catch {
            rows.append(["fixture": name, "format": format, "error": "\(error)"])
        }
    }
}
let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
    try? data.write(to: out)
}
exit(0)
