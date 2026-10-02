// tools/proof/formats_probe.swift — the formats probe's entry (issue #46).
//
// Copied to tools/proof/work/formats-probe/main.swift and compiled LAST with
// every app/Sources/*.swift except the app's main.swift, so the question each
// row asks is the product's own: `MediaImporter.waitForProbe` (AVFoundation
// or ImageIO, no ffmpeg rewrap). Then one decode of the first picture, the
// first sound or the image, each bounded at 15 s, and AVFoundation's
// `isPlayable` for a non-image file.
//
//   formats-probe <file> [<file> …]
//
// Prints one HOST line, then one ROW line per argument, each a JSON object
// (formats_probe.py reads them). stdout is line-buffered so every finished
// line survives a kill by the runner's bound.

import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import VideoToolbox

setvbuf(stdout, nil, _IOLBF, 0)

/// Carries one async answer across a semaphore.
final class Box<T>: @unchecked Sendable {
    var value: T?
}

/// `body`'s answer, or nil when it does not arrive within `seconds`.
func waitFor<T>(_ seconds: Double, _ body: @escaping @Sendable () async -> T) -> T? {
    let box = Box<T>()
    let done = DispatchSemaphore(value: 0)
    Task.detached(priority: .userInitiated) {
        box.value = await body()
        done.signal()
    }
    guard done.wait(timeout: .now() + seconds) == .success else { return nil }
    return box.value
}

func emit(_ tag: String, _ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(tag + " " + String(decoding: data, as: UTF8.self))
}

func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "" }
    return String(cString: bytes)
}

/// The first sample buffer of `track` through an `AVAssetReader`, or why not.
func readFirstSample(_ url: URL, video: Bool) async -> (Bool, String) {
    let asset = AVURLAsset(url: url)
    let type: AVMediaType = video ? .video : .audio
    let tracks: [AVAssetTrack]
    do {
        tracks = try await asset.loadTracks(withMediaType: type)
    } catch {
        return (false, "loadTracks: \(error)")
    }
    guard let track = tracks.first else { return (false, "no \(type.rawValue) track") }
    let reader: AVAssetReader
    do {
        reader = try AVAssetReader(asset: asset)
    } catch {
        return (false, "AVAssetReader: \(error)")
    }
    let settings: [String: Any] = video
        ? [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        : [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
           AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
           AVLinearPCMIsNonInterleaved: false]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    guard reader.canAdd(output) else { return (false, "reader cannot add the output") }
    reader.add(output)
    guard reader.startReading() else {
        return (false, "startReading: \(reader.error.map { "\($0)" } ?? "no error")")
    }
    while true {
        if let sample = output.copyNextSampleBuffer() {
            let frames = CMSampleBufferGetNumSamples(sample)
            reader.cancelReading()
            if video {
                guard let image = CMSampleBufferGetImageBuffer(sample) else { continue }
                return (true, "first frame \(CVPixelBufferGetWidth(image))x\(CVPixelBufferGetHeight(image)) BGRA")
            }
            return (true, "first buffer \(frames) frames float32")
        }
        let status = reader.status
        let why = reader.error.map { "\($0)" } ?? "no error"
        reader.cancelReading()
        return (false, "no sample buffer (status \(status.rawValue)): \(why)")
    }
}

func decodeImage(_ url: URL) -> (Bool, String) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return (false, "CGImageSourceCreateWithURL returned nil")
    }
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return (false, "CGImageSourceCreateImageAtIndex returned nil")
    }
    return (true, "CGImage \(image.width)x\(image.height)")
}

let version = ProcessInfo.processInfo.operatingSystemVersion
emit("HOST", [
    "macos": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
    "build": sysctlString("kern.osversion"),
    "hw_av1": VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1),
    "hw_vp9": VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9),
    "hw_hevc": VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC),
])

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    var row: [String: Any] = ["file": url.lastPathComponent]
    let descriptor: MediaDescriptor
    do {
        descriptor = try MediaImporter.waitForProbe(url)
    } catch {
        row["probe"] = "error"
        row["error"] = String(describing: error)
        row["decode"] = "n/a"
        row["decode_detail"] = "probe failed"
        if !MediaImporter.isImage(url) {
            row["playable"] = waitFor(15) { (try? await AVURLAsset(url: url).load(.isPlayable)) ?? false }
                ?? NSNull()
        }
        emit("ROW", row)
        continue
    }
    row["probe"] = "ok"
    row["kind"] = descriptor.kind.rawValue
    row["width"] = descriptor.width
    row["height"] = descriptor.height
    row["has_video"] = descriptor.hasVideo
    row["has_audio"] = descriptor.hasAudio
    row["duration_ticks"] = Int(descriptor.duration)
    let decoded: (Bool, String)
    if descriptor.kind == .image {
        decoded = waitFor(15) { decodeImage(url) } ?? (false, "timed out after 15 s")
    } else {
        let video = descriptor.hasVideo
        decoded = waitFor(15) { await readFirstSample(url, video: video) }
            ?? (false, "timed out after 15 s")
        row["playable"] = waitFor(15) { (try? await AVURLAsset(url: url).load(.isPlayable)) ?? false }
            ?? NSNull()
    }
    row["decode"] = decoded.0 ? "ok" : "failed"
    row["decode_detail"] = decoded.1
    emit("ROW", row)
}
