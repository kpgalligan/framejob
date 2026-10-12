// reverse_probe — precision_proof.py's real-renderer entry (precision-2 P2-2,
// spec §11 PR-7): `reverse_probe SOURCE DEST OUT_JSON`.
//
// Compiled with every `app/Sources` file but `main.swift` (this tree's, or a
// mutant copy's) through `swift_build.build`, as `main.swift` of its own. It
// runs the real `ReverseRenderer` on one file — the `Job` built from
// `MediaImporter.probeBlocking`, as `source_mirror_probe.py` §3 builds it —
// and writes JSON:
//   {ok, error?, seconds, bytes, peakRSS, width, height, sourceFrames,
//    writtenFrames, firstIsZero, ascending, worstDrift}
// `seconds` is the render's wall time, `bytes` the written file's size,
// `peakRSS` this process's `ru_maxrss` (bytes on macOS), `width`/`height` the
// written video track's natural size. The stamp half is §3's logic, copied:
// both files DECODED to 32BGRA, the written stamps against the walk
// `[T − following]` from the end of the source, drift counted in the output
// track's timescale. Exit 0 whenever the JSON is written.

import AVFoundation
import AppKit
import Foundation

_ = NSApplication.shared

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write("usage: reverse_probe SOURCE DEST OUT_JSON\n".data(using: .utf8)!)
    exit(2)
}
let fixture = URL(fileURLWithPath: arguments[1])
let destination = URL(fileURLWithPath: arguments[2])
let out = URL(fileURLWithPath: arguments[3])

var answer: [String: Any] = ["ok": false]
func write() {
    let data = (try? JSONSerialization.data(withJSONObject: answer)) ?? Data()
    try? data.write(to: out)
}
func fail(_ why: String) -> Never {
    answer["ok"] = false
    answer["error"] = why
    write()
    exit(0)
}

func peakRSS() -> Int {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Int(usage.ru_maxrss)
}

/// Every video presentation stamp of one file, in order — DECODED, not
/// sample references (source_mirror_probe.py §3: a compressed read answered
/// 149 stamps for a 150-frame source and 152 for its reversal).
func stamps(_ asset: AVURLAsset) -> [CMTime] {
    guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .video),
          let reader = try? AVAssetReader(asset: asset)
    else { return [] }
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
    guard reader.canAdd(output) else { return [] }
    reader.add(output)
    guard reader.startReading() else { return [] }
    var times: [CMTime] = []
    while let sample = output.copyNextSampleBuffer() {
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        if time.isNumeric { times.append(time) }
    }
    return times.sorted { $0 < $1 }
}

guard FileManager.default.fileExists(atPath: fixture.path) else {
    fail("\(fixture.path) is not there")
}
guard let probed = try? MediaImporter.probeBlocking(url: fixture) else {
    fail("the fixture could not be probed")
}
try? FileManager.default.removeItem(at: destination)
try? FileManager.default.createDirectory(
    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
let job = ReverseRenderer.Job(
    media: 1, name: fixture.lastPathComponent, source: fixture, destination: destination,
    duration: probed.duration, fps: probed.fps, hasAudio: probed.hasAudio)
let started = Date()
let outcome = ReverseRenderer(job: job).run()
answer["seconds"] = Date().timeIntervalSince(started)
answer["peakRSS"] = peakRSS()

switch outcome {
case .failure(let error):
    fail("\(error)")
case .success(let url):
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
    answer["bytes"] = size?.int64Value ?? -1
    let written = AVURLAsset(url: url)
    let track = CompositionBuilder.firstTrack(of: written, mediaType: .video)
    let natural = track?.naturalSize ?? .zero
    answer["width"] = Int(natural.width)
    answer["height"] = Int(natural.height)

    let total = CompositionBuilder.time(probed.duration)
    let source = stamps(AVURLAsset(url: fixture)).filter { $0 < total }
    let got = stamps(written)
    let outputScale = track?.naturalTimeScale ?? CMTimeScale(ReelTime.perSecond)
    // `following` starts at T, so the source's LAST frame is written at zero
    // and every frame back is written at T − the stamp of the frame that
    // followed it.
    var expected: [CMTime] = [ReverseMirror.mirrored(total, about: total)]
    for index in stride(from: source.count - 1, to: 0, by: -1) {
        expected.append(ReverseMirror.mirrored(source[index], about: total))
    }
    var worst: Int64 = 0
    for (index, want) in expected.enumerated() where index < got.count {
        let wanted = CMTimeConvertScale(want, timescale: outputScale, method: .roundHalfAwayFromZero)
        worst = max(worst, abs(got[index].value - wanted.value))
    }
    var ascending = true
    for index in 1..<max(got.count, 1) where got[index] <= got[index - 1] {
        ascending = false
    }
    answer["sourceFrames"] = source.count
    answer["writtenFrames"] = got.count
    answer["firstIsZero"] = got.first == .zero
    answer["ascending"] = ascending
    answer["worstDrift"] = Int(worst)
    answer["ok"] = true
    write()
}
