// hdr10_writer — hdr_proof.py's HDR10 fixtures written the way AVFoundation stores HDR10
// static metadata (hdr H-1, spec §11 HD-6, HD-12):
// `hdr10_writer <in.mov> <out.mov> <max luminance in 0.0001 cd/m²> <MaxCLL> <MaxFALL>`.
//
// x265 writes the code values and, for some fixtures, its own SEI; this tool adds the
// sample description's two extensions, as applelog_writer.swift adds a label: every sample
// of the input's video track copied as it is (no decode), under a format description
// rebuilt from the input's own extensions (each sample's attachments kept, so only the
// IDR frame is a sync sample) with the two verbatim sample-description keys removed (so the writer writes the extensions, not the input's original atom) and
// `MasteringDisplayColorVolume` (24 bytes, SMPTE ST 2086 in the order H.265's SEI 137
// carries it: the G, B and R primaries and the white point as x265's
// `G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)`, the given maximum and a
// minimum of 50, each big-endian) and `ContentLightLevelInfo` (4 bytes, CTA-861.3:
// MaxCLL, MaxFALL) set. The frames' own SEI, if any, is left in the samples. It then
// opens what it wrote and reads both extensions back from the track's format
// description. One line out: what was read back. Exit 0 only when the file is written AND
// both extensions read back as the bytes asked for; 1 otherwise.

import AVFoundation
import CoreMedia
import Foundation

func fail(_ text: String) -> Never {
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
    exit(1)
}

func be16(_ v: UInt32) -> [UInt8] { [UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
func be32(_ v: UInt32) -> [UInt8] {
    [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
}
/// Copies each sample's attachments (`NotSync`, `DependsOnOthers`…) from the reader's
/// buffer to the relabelled one, so only x265's IDR frame is written as a sync sample.
func copyAttachments(from source: CMSampleBuffer, to target: CMSampleBuffer) {
    guard let from = CMSampleBufferGetSampleAttachmentsArray(source, createIfNecessary: false)
            as NSArray?,
          let to = CMSampleBufferGetSampleAttachmentsArray(target, createIfNecessary: true)
            as NSArray?
    else { return }
    for index in 0..<min(from.count, to.count) {
        if let read = from[index] as? [AnyHashable: Any], let write = to[index] as? NSMutableDictionary {
            write.addEntries(from: read)
        }
    }
}

func hex(_ data: Data?) -> String {
    data.map { $0.map { String(format: "%02x", $0) }.joined() } ?? "none"
}

let arguments = CommandLine.arguments
guard arguments.count == 6, let maximum = UInt32(arguments[3]), let maxCLL = UInt32(arguments[4]),
      let maxFALL = UInt32(arguments[5]), maxCLL <= 0xffff, maxFALL <= 0xffff
else { fail("usage: hdr10_writer <in.mov> <out.mov> <max luminance> <MaxCLL> <MaxFALL>") }
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let mastering = Data(be16(13250) + be16(34500) + be16(7500) + be16(3000) + be16(34000)
    + be16(16000) + be16(15635) + be16(16450) + be32(maximum) + be32(50))
let contentLight = Data(be16(maxCLL) + be16(maxFALL))

let asset = AVURLAsset(url: input)
guard let track = asset.tracks(withMediaType: .video).first,
      let old = (track.formatDescriptions as? [CMFormatDescription])?.first
else { fail("\(input.path) has no video track") }

var extensions = (CMFormatDescriptionGetExtensions(old) as? [String: Any]) ?? [:]
extensions.removeValue(forKey: "VerbatimSampleDescription")
extensions.removeValue(forKey: "VerbatimISOSampleEntry")
extensions[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String] = mastering
extensions[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] = contentLight
let dimensions = CMVideoFormatDescriptionGetDimensions(old)
var made: CMFormatDescription?
guard CMVideoFormatDescriptionCreate(
        allocator: nil, codecType: CMFormatDescriptionGetMediaSubType(old),
        width: dimensions.width, height: dimensions.height,
        extensions: extensions as CFDictionary, formatDescriptionOut: &made) == noErr,
      let description = made
else { fail("the HDR10 format description could not be made") }

try? FileManager.default.removeItem(at: output)
let reader: AVAssetReader
let writer: AVAssetWriter
do {
    reader = try AVAssetReader(asset: asset)
    writer = try AVAssetWriter(outputURL: output, fileType: .mov)
} catch {
    fail("reader or writer: \(error)")
}
let copied = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
reader.add(copied)
let into = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: description)
writer.add(into)
guard reader.startReading(), writer.startWriting() else {
    fail("could not start: \(String(describing: reader.error ?? writer.error))")
}
writer.startSession(atSourceTime: .zero)
var samples = 0
while let sample = copied.copyNextSampleBuffer() {
    // The reader's first buffer of an x265 track holds no sample (hdr H-1's spec).
    let count = CMSampleBufferGetNumSamples(sample)
    guard count > 0, let data = CMSampleBufferGetDataBuffer(sample) else { continue }
    var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
    CMSampleBufferGetSampleTimingInfoArray(
        sample, entryCount: count, arrayToFill: &timings, entriesNeededOut: nil)
    var sizes = [Int](repeating: 0, count: count)
    CMSampleBufferGetSampleSizeArray(
        sample, entryCount: count, arrayToFill: &sizes, entriesNeededOut: nil)
    var relabelled: CMSampleBuffer?
    guard CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: data, formatDescription: description,
            sampleCount: count, sampleTimingEntryCount: count, sampleTimingArray: &timings,
            sampleSizeEntryCount: count, sampleSizeArray: &sizes,
            sampleBufferOut: &relabelled) == noErr,
          let ready = relabelled
    else { fail("sample \(samples) could not be relabelled") }
    copyAttachments(from: sample, to: ready)
    while !into.isReadyForMoreMediaData { usleep(1000) }
    guard into.append(ready) else {
        fail("sample \(samples) refused: \(String(describing: writer.error))")
    }
    samples += count
}
into.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
guard writer.status == .completed, samples > 0 else {
    fail("the writer ended \(writer.status.rawValue) after \(samples) samples: "
        + "\(String(describing: writer.error))")
}

let back = (AVURLAsset(url: output).tracks(withMediaType: .video).first?.formatDescriptions
    as? [CMFormatDescription])?.first
func read(_ key: CFString) -> Data? {
    back.flatMap { CMFormatDescriptionGetExtension($0, extensionKey: key) as? Data }
}
let gotMastering = read(kCMFormatDescriptionExtension_MasteringDisplayColorVolume)
let gotLight = read(kCMFormatDescriptionExtension_ContentLightLevelInfo)
print("MasteringDisplayColorVolume \(hex(gotMastering)); ContentLightLevelInfo "
    + "\(hex(gotLight)); \(samples) samples")
exit(gotMastering == mastering && gotLight == contentLight ? 0 : 1)
