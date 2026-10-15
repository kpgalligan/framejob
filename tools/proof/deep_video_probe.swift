// Built by tools/proof/log_proof.py as `main.swift` over every other file in
// `app/Sources` (`swift_build.py`). See that script's header, row L16 (issue
// batch B103, #294, spec §11 PR-12).
//
// What a video track's first format description carries, and what
// `DeepVideoFrame.isDeep` answers for it. Descriptions only: no picture is
// decoded here.
//
//   deep_video_probe <request.json> <answer.json>
//
// The request: {"scratch": DIR, "items": [{"label", "kind", "path"}]}. `kind`
// is
//   - "file": the file opened as is;
//   - "webm": the WebM rewrapped by `ContainerRewrap.rewrap` (import's own
//     route: its precheck, then `ContainerRewrapWriter.write`) into a scratch
//     `.mov`, then opened.
// The answer: {"items": [{label, subtype (the media subtype as a FourCC),
// bitsPerComponent ("absent" or the extension's value), vpcC (the record's
// first 8 bytes, hex, or "absent"), deep (`DeepVideoFrame.isDeep`)} or
// {label, error}]}.
import AVFoundation
import CoreMedia
import Foundation

DecoderSupport.enable()

let request = (try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))) as? [String: Any]
    ?? [:]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let scratch = URL(fileURLWithPath: request["scratch"] as? String ?? NSTemporaryDirectory())
try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
}

func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

/// A FourCC as its four characters.
func fourCC(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }
    return String(bytes: bytes, encoding: .macOSRoman) ?? String(code)
}

/// The first format description of the first video track of `url`.
func firstDescription(_ url: URL) throws -> CMFormatDescription {
    let asset = AVURLAsset(url: url)
    guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .video) else {
        throw ProbeFailure(description: "\(url.lastPathComponent) has no video track")
    }
    guard let description = (CompositionBuilder.keyed(track, "formatDescriptions")
        as? [CMFormatDescription])?.first
    else {
        throw ProbeFailure(description: "\(url.lastPathComponent) has no format description")
    }
    return description
}

func read(_ url: URL, label: String) throws -> [String: Any] {
    let description = try firstDescription(url)
    let bits = CMFormatDescriptionGetExtension(
        description, extensionKey: kCMFormatDescriptionExtension_BitsPerComponent)
    let atoms = CMFormatDescriptionGetExtension(
        description, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
        as? [String: Any] ?? [:]
    let vpcC = atoms["vpcC"] as? Data
    return [
        "label": label,
        "subtype": fourCC(CMFormatDescriptionGetMediaSubType(description)),
        "bitsPerComponent": bits.map { "\($0)" } ?? "absent",
        "vpcC": vpcC.map { hex($0.prefix(8)) } ?? "absent",
        "deep": DeepVideoFrame.isDeep(description),
    ]
}

var answered: [[String: Any]] = []
for (index, item) in ((request["items"] as? [[String: Any]]) ?? []).enumerated() {
    let label = item["label"] as? String ?? "item \(index)"
    let path = URL(fileURLWithPath: item["path"] as? String ?? "")
    do {
        switch item["kind"] as? String {
        case "file":
            answered.append(try read(path, label: label))
        case "webm":
            let copy = scratch.appendingPathComponent("rewrap-\(index).mov")
            try? FileManager.default.removeItem(at: copy)
            try ContainerRewrap.rewrap(path, to: copy)
            answered.append(try read(copy, label: label))
        default:
            throw ProbeFailure(description: "unknown kind \(item["kind"] ?? "none")")
        }
    } catch {
        answered.append(["label": label, "error": "\(error)"])
    }
}
let answer: [String: Any] = ["items": answered]
if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
    try? data.write(to: out)
}
exit(0)
