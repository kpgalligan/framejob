// Road map "creator-jobs" CJ2a, spike CJ-S3 (a) and (c) — what decoding for
// analysis costs, and whether a second concurrent picture job pays.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift` (module FrameJob, the staticlib), through
// `tools/proof/swift_build.py`, by `lane_spike.py`. One measurement a process:
//
//   lane_spike <movie> <direct|converted> <long side> <jobs>
//
// `direct` is an `AVAssetReaderTrackOutput` over the first video track, 32BGRA
// at the long side; `converted` is an `AVAssetReaderVideoCompositionOutput`
// over `MediaImporter.oneClip`'s one-clip composition (step 0, the HLG input
// converted for an SDR canvas), its configuration's `renderSize` set to the
// long side as `Playback+PreviewQuality.swift` sets a preview's, reading the
// compositor's one format (`Compositor.outputPixelFormat`, 64RGBAHalf). `jobs` readers
// of the whole file run at once on their own `.utility` threads. The answer is
// one JSON line: `{frames, seconds, fps, jobs, width, height}`, `fps` the
// total frames over the wall time.
import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count == 5, let longSide = Int(args[3]), let jobs = Int(args[4]) else {
    FileHandle.standardError.write(Data("usage: lane_spike <movie> <direct|converted> <long> <jobs>\n".utf8))
    exit(2)
}
let url = URL(fileURLWithPath: args[1])
let mode = args[2]
let descriptor = try MediaImporter.probeBlocking(url: url)
guard var project = ReelProject.new(width: 1920, height: 1080, fps: Fps(num: 30, den: 1)),
    let added = (try? project.applying(.addMedia(descriptor: descriptor)))?.project,
    let media = added.snapshot.media.last
else {
    FileHandle.standardError.write(Data("no media\n".utf8))
    exit(1)
}
project = added
let scale = Double(longSide) / Double(max(media.width, media.height))
let width = Int((Double(media.width) * scale).rounded())
let height = Int((Double(media.height) * scale).rounded())

func readDirect() -> Int {
    let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let track = asset.tracks(withMediaType: .video).first,
        let reader = try? AVAssetReader(asset: asset)
    else { return -1 }
    let natural = track.naturalSize
    let s = Double(longSide) / Double(max(natural.width, natural.height))
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int((Double(natural.width) * s).rounded()),
        kCVPixelBufferHeightKey as String: Int((Double(natural.height) * s).rounded()),
    ])
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else { return -1 }
    var count = 0
    while let sample = output.copyNextSampleBuffer() {
        if CMSampleBufferGetImageBuffer(sample) != nil { count += 1 }
    }
    return reader.status == .failed ? -1 : count
}

func readConverted() -> Int {
    var assets: [UInt32: AVURLAsset] = [:]
    let track = CompositionBuilder.assetTrack(at: url, key: 0, mediaType: .video, assets: &assets)
    guard let input = ThumbnailInput(media: media, urls: [media.id: url])
            ?? track.flatMap(ThumbnailInput.init(track:))
    else {
        FileHandle.standardError.write(Data("the media does not convert\n".utf8))
        return -1
    }
    let key = RecipeSource.shared.register()
    defer { RecipeSource.shared.unregister(key) }
    guard let built = MediaImporter.oneClip(media, url: url, input: input, key: key),
        let reader = try? AVAssetReader(asset: built.composition)
    else { return -1 }
    var configuration = built.videoConfiguration
    configuration.renderSize = CGSize(width: width, height: height)
    let videoTracks = built.composition.tracks.filter { $0.mediaType == .video }
    let output = AVAssetReaderVideoCompositionOutput(
        videoTracks: videoTracks,
        videoSettings: [
            // The one format the compositor produces (as `ExportWriter` asks).
            kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.outputPixelFormat),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
    output.videoComposition = AVVideoComposition(configuration: configuration)
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else {
        FileHandle.standardError.write(Data("start: \(String(describing: reader.error))\n".utf8))
        return -1
    }
    var count = 0
    while let sample = output.copyNextSampleBuffer() {
        if CMSampleBufferGetImageBuffer(sample) != nil { count += 1 }
    }
    if reader.status == .failed {
        FileHandle.standardError.write(Data("read: \(String(describing: reader.error))\n".utf8))
        return -1
    }
    return count
}

let group = DispatchGroup()
let lock = NSLock()
var total = 0
var failed = false
let started = Date()
for index in 0..<jobs {
    group.enter()
    DispatchQueue(label: "lane-spike-\(index)", qos: .utility).async {
        let count = mode == "converted" ? readConverted() : readDirect()
        lock.lock()
        if count < 0 { failed = true } else { total += count }
        lock.unlock()
        group.leave()
    }
}
group.wait()
let seconds = Date().timeIntervalSince(started)
let answer: [String: Any] = [
    "frames": total, "seconds": seconds, "fps": Double(total) / seconds, "jobs": jobs,
    "width": width, "height": height, "failed": failed, "mode": mode,
]
print(String(decoding: try JSONSerialization.data(withJSONObject: answer), as: UTF8.self))
exit(failed ? 1 : 0)
