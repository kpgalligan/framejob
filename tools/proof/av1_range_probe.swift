// Built by tools/proof/log_proof.py as `main.swift` over every other file in
// `app/Sources` (`swift_build.py`). See that script's header, row L15 (issue
// batch B101, #293).
//
// What an AV1 track's first format description carries, and what
// `CompositionBuilder.isFullRange` answers for it. Descriptions only: AV1
// does not decode on an M1/M2 (`DecoderSupport.refusal`), so no picture is
// ever decoded here.
//
//   av1_range_probe <request.json> <answer.json>
//
// The request: {"scratch": DIR, "base": AV1 MP4, "items": [{"label", "kind",
// "path"?, "record"?}]}. `kind` is
//   - "file": the MP4 opened as is;
//   - "webm": the WebM rewrapped by `ContainerRewrapWriter.write` (the
//     precheck skipped, which refuses AV1 without hardware decode; the
//     description decoded as `ContainerRewrap.describe` does) into a scratch
//     `.mov`, then opened;
//   - "record": `base`'s first compressed sample re-described as `av01` with
//     the atoms {av1C: record} (`ContainerRewrapWriter.videoFormat`'s shape),
//     written as a one-sample `.mov` by a passthrough `AVAssetWriterInput`,
//     then opened.
// The answer: {"items": [{label, key ("absent" / "true" / "false"), av1C,
// colr (atoms), atoms, head (av1C's first 8 bytes, hex), extensions (the
// description's extension keys), fullRange} or {label, error}]}.
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

func bytes(hex text: String) -> Data {
    ContainerRewrapWriter.data(hex: text)
}

/// The first format description of the first video track of `url`.
func firstDescription(_ url: URL) throws -> (AVAssetTrack, CMFormatDescription) {
    let asset = AVURLAsset(url: url)
    guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .video) else {
        throw ProbeFailure(description: "\(url.lastPathComponent) has no video track")
    }
    guard let description = (CompositionBuilder.keyed(track, "formatDescriptions")
        as? [CMFormatDescription])?.first
    else {
        throw ProbeFailure(description: "\(url.lastPathComponent) has no format description")
    }
    return (track, description)
}

/// The WebM at `source` copied into `destination` by the built-in rewrap's
/// writer.
func rewrap(_ source: URL, to destination: URL) throws {
    try? FileManager.default.removeItem(at: destination)
    let container = try ReelContainer(path: source.path)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let description = try decoder.decode(
        ContainerDescription.self, from: Data(container.describeJSON.utf8))
    try ContainerRewrapWriter.write(
        container, description, from: source, to: destination, stopAfter: nil)
}

/// `base`'s first compressed sample, re-described with `record` as its
/// `av1C`, written alone into `destination`.
func redescribe(_ base: URL, record: Data, to destination: URL) throws {
    try? FileManager.default.removeItem(at: destination)
    let asset = AVURLAsset(url: base)
    guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .video) else {
        throw ProbeFailure(description: "the base has no video track")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    guard reader.startReading() else {
        throw ProbeFailure(description: "the base could not be read: "
            + (reader.error?.localizedDescription ?? "no error"))
    }
    // The passthrough read answers an empty marker buffer first (measured:
    // no data buffer, 0 samples), so the first buffer holding a sample is
    // the first sample.
    var first: CMSampleBuffer?
    while let next = output.copyNextSampleBuffer() {
        if CMSampleBufferGetNumSamples(next) > 0, CMSampleBufferGetDataBuffer(next) != nil {
            first = next
            break
        }
    }
    reader.cancelReading()
    guard let sample = first, let whole = CMSampleBufferGetDataBuffer(sample) else {
        throw ProbeFailure(description: "the base's first sample could not be read: "
            + (reader.error?.localizedDescription ?? "no sample"))
    }
    var length = CMSampleBufferGetSampleSize(sample, at: 0)
    var sliced: CMBlockBuffer?
    let cut = CMBlockBufferCreateWithBufferReference(
        allocator: nil, referenceBuffer: whole, offsetToData: 0, dataLength: length, flags: 0,
        blockBufferOut: &sliced)
    guard cut == noErr, let data = sliced else {
        throw ProbeFailure(description: "the base's first sample could not be cut (\(cut))")
    }
    guard let original = CMSampleBufferGetFormatDescription(sample) else {
        throw ProbeFailure(description: "the base's first sample has no description")
    }
    let size = CMVideoFormatDescriptionGetDimensions(original)
    let extensions: [String: Any] = [
        kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String: ["av1C": record]
    ]
    var format: CMFormatDescription?
    var status = CMVideoFormatDescriptionCreate(
        allocator: nil, codecType: kCMVideoCodecType_AV1, width: size.width, height: size.height,
        extensions: extensions as CFDictionary, formatDescriptionOut: &format)
    guard status == noErr, let format else {
        throw ProbeFailure(description: "the description was refused (\(status))")
    }
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: .zero,
        decodeTimeStamp: .invalid)
    var copy: CMSampleBuffer?
    status = CMSampleBufferCreateReady(
        allocator: nil, dataBuffer: data, formatDescription: format, sampleCount: 1,
        sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
        sampleSizeArray: &length, sampleBufferOut: &copy)
    guard status == noErr, let copy else {
        throw ProbeFailure(description: "the sample was refused (\(status))")
    }
    let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
    input.expectsMediaDataInRealTime = false
    guard writer.canAdd(input) else {
        throw ProbeFailure(description: "the writer would not take an av01 input")
    }
    writer.add(input)
    guard writer.startWriting() else {
        throw ProbeFailure(description: "the writer did not start: "
            + (writer.error?.localizedDescription ?? "no error"))
    }
    writer.startSession(atSourceTime: .zero)
    guard input.append(copy) else {
        throw ProbeFailure(description: "the sample was not appended: "
            + (writer.error?.localizedDescription ?? "no error"))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else {
        throw ProbeFailure(description: "the movie was not finished: "
            + (writer.error?.localizedDescription ?? "status \(writer.status.rawValue)"))
    }
}

func read(_ url: URL, label: String) throws -> [String: Any] {
    let (track, description) = try firstDescription(url)
    let key = CMFormatDescriptionGetExtension(
        description, extensionKey: kCMFormatDescriptionExtension_FullRangeVideo)
    let atoms = CMFormatDescriptionGetExtension(
        description, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
        as? [String: Any] ?? [:]
    let av1C = atoms["av1C"] as? Data
    return [
        "label": label,
        "key": key.map { ($0 as? Bool).map { $0 ? "true" : "false" } ?? "\($0)" } ?? "absent",
        "av1C": av1C != nil,
        "colr": atoms["colr"] != nil,
        "atoms": atoms.keys.sorted(),
        "head": av1C.map { hex($0.prefix(8)) } ?? "",
        "extensions": ((CMFormatDescriptionGetExtensions(description) as? [String: Any]) ?? [:])
            .keys.sorted(),
        "fullRange": CompositionBuilder.isFullRange(track),
    ]
}

var answered: [[String: Any]] = []
let base = URL(fileURLWithPath: request["base"] as? String ?? "")
for (index, item) in ((request["items"] as? [[String: Any]]) ?? []).enumerated() {
    let label = item["label"] as? String ?? "item \(index)"
    do {
        switch item["kind"] as? String {
        case "file":
            answered.append(try read(URL(fileURLWithPath: item["path"] as? String ?? ""),
                                     label: label))
        case "webm":
            let copy = scratch.appendingPathComponent("rewrap-\(index).mov")
            try rewrap(URL(fileURLWithPath: item["path"] as? String ?? ""), to: copy)
            answered.append(try read(copy, label: label))
        case "record":
            let copy = scratch.appendingPathComponent("record-\(index).mov")
            try redescribe(base, record: bytes(hex: item["record"] as? String ?? ""), to: copy)
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
