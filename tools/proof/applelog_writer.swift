// applelog_writer — hdr_proof.py's Apple-Log-labelled fixture (grading-3
// T3-1, spec §11 GR-15): `applelog_writer <in.mov> <out.mov>`.
//
// ffmpeg writes the code values (the ProRes ramp); this tool adds the label
// the way AVFoundation stores it, as the tier-3 brief measured: every
// sample of the input's video track copied as it is (no decode), under a
// format description rebuilt from the input's own extensions with BT.2020
// primaries and matrix, the transfer key removed, the two verbatim
// sample-description keys removed (so the writer writes the extensions, not
// the input's original atom), and `LogTransferFunction` set to Apple Log.
// It then opens what it wrote and reads the label back from the track's
// format description. One line out: the label read back. Exit 0 only when
// the file is written AND the label reads back as Apple Log; 1 otherwise.

import AVFoundation
import CoreMedia
import Foundation

func fail(_ text: String) -> Never {
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("usage: applelog_writer <in.mov> <out.mov>") }
let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])

let asset = AVURLAsset(url: input)
guard let track = asset.tracks(withMediaType: .video).first,
      let old = (track.formatDescriptions as? [CMFormatDescription])?.first
else { fail("\(input.path) has no video track") }

var extensions = (CMFormatDescriptionGetExtensions(old) as? [String: Any]) ?? [:]
extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] =
    kCMFormatDescriptionColorPrimaries_ITU_R_2020
extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] =
    kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
extensions.removeValue(forKey: kCMFormatDescriptionExtension_TransferFunction as String)
extensions.removeValue(forKey: "VerbatimSampleDescription")
extensions.removeValue(forKey: "VerbatimISOSampleEntry")
extensions[kCMFormatDescriptionExtension_LogTransferFunction as String] =
    kCMFormatDescriptionLogTransferFunction_AppleLog
let dimensions = CMVideoFormatDescriptionGetDimensions(old)
var made: CMFormatDescription?
guard CMVideoFormatDescriptionCreate(
        allocator: nil, codecType: CMFormatDescriptionGetMediaSubType(old),
        width: dimensions.width, height: dimensions.height,
        extensions: extensions as CFDictionary, formatDescriptionOut: &made) == noErr,
      let description = made
else { fail("the labelled format description could not be made") }

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
    guard CMSampleBufferGetNumSamples(sample) > 0,
          let data = CMSampleBufferGetDataBuffer(sample)
    else { continue }
    var timing = CMSampleTimingInfo()
    CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing)
    var size = CMSampleBufferGetSampleSize(sample, at: 0)
    var relabelled: CMSampleBuffer?
    guard CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: data, formatDescription: description, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
            sampleSizeArray: &size, sampleBufferOut: &relabelled) == noErr,
          let ready = relabelled
    else { fail("sample \(samples) could not be relabelled") }
    while !into.isReadyForMoreMediaData { usleep(1000) }
    guard into.append(ready) else { fail("sample \(samples) refused: \(String(describing: writer.error))") }
    samples += 1
}
into.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
guard writer.status == .completed, samples > 0 else {
    fail("the writer ended \(writer.status.rawValue) after \(samples) samples: "
        + "\(String(describing: writer.error))")
}

let back = AVURLAsset(url: output)
let label = (back.tracks(withMediaType: .video).first?.formatDescriptions
    as? [CMFormatDescription])?.first.flatMap {
        CMFormatDescriptionGetExtension(
            $0, extensionKey: kCMFormatDescriptionExtension_LogTransferFunction)
    }.map { "\($0)" } ?? "none"
print("LogTransferFunction \(label); \(samples) samples")
exit(label == (kCMFormatDescriptionLogTransferFunction_AppleLog as String) ? 0 : 1)
