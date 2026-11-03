// Road map "creator-jobs" FC3, spike FC-S1 — Sound Analysis as a signal:
// does `SNClassifySoundRequest` `.version1` know FC-31's labels, how fast is
// it, at which window, and does the stream analyzer agree with the file one?
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift` (`swift_build.app_sources()`, module FrameJob, the staticlib),
// optimised, through `tools/proof/swift_build.py`, by `sound_spike.py`. Two
// modes, each answering one JSON line on stdout:
//
//   sound_spike labels
//   sound_spike run <file> <window s> file|stream
//
// `labels`: each FC-31 label's presence in `.version1`'s
// `knownClassifications`, the count of known labels, and its
// `windowDurationConstraint` (enumerated seconds or a range).
//
// `run`: the request at `window` seconds and overlap 0.5, through
// `SNAudioFileAnalyzer` over the file, or through `SNAudioStreamAnalyzer` fed
// the app's own 16 kHz mono float decode (`MediaImporter.speechReader`, past
// an MP3's encoder delay) of the file's first audio track. Per result its
// start and duration in seconds and the six groups' maxima over their labels
// (NaN as null); `seconds` the analysis's wall time (the decode included for
// `stream`); `duration` the decoded or file seconds; `realtime` their ratio;
// and `sha256` of every value's Float32 bits in result order.
import AVFoundation
import CryptoKit
import Foundation
import SoundAnalysis

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sound_spike: \(message)\n".utf8))
    exit(1)
}

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

/// FC-31's group table, in its order.
let groups: [(String, [String])] = [
    ("laughter", ["laughter", "belly_laugh", "chuckle_chortle", "giggling", "snicker"]),
    ("applause", ["applause", "clapping"]),
    ("cheering", ["cheering"]),
    ("crowd", ["crowd"]),
    ("music", ["music"]),
    ("speech", ["speech"]),
]

func makeRequest(window: Double) -> SNClassifySoundRequest {
    guard let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else {
        die("SNClassifySoundRequest(.version1) could not be made")
    }
    request.windowDuration = CMTime(seconds: window, preferredTimescale: 48_000)
    request.overlapFactor = 0.5
    return request
}

final class Collector: NSObject, SNResultsObserving {
    let lock = NSLock()
    var rows: [(start: Double, duration: Double, values: [Float])] = []
    var failure: String?

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let values = groups.map { _, labels -> Float in
            let found = labels.compactMap { result.classification(forIdentifier: $0)?.confidence }
            return found.isEmpty ? .nan : Float(found.max()!)
        }
        lock.lock()
        rows.append((result.timeRange.start.seconds, result.timeRange.duration.seconds, values))
        lock.unlock()
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        lock.lock()
        failure = "\(error)"
        lock.unlock()
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { die("usage: sound_spike labels | run <file> <window> file|stream") }

switch arguments[1] {
case "labels":
    let request = makeRequest(window: 1.5)
    let known = Set(request.knownClassifications)
    var labels: [String: Bool] = [:]
    for (_, names) in groups { for name in names { labels[name] = known.contains(name) } }
    var constraint: [String: Any] = [:]
    switch request.windowDurationConstraint {
    case .enumeratedDurations(let durations):
        constraint = ["type": "enumerated", "seconds": durations.map(\.seconds)]
    case .durationRange(let range):
        constraint = ["type": "range", "from": range.start.seconds, "to": range.end.seconds]
    @unknown default:
        constraint = ["type": "unknown"]
    }
    var windows: [String: Double] = [:]
    for w in [1.0, 1.5, 3.0] {
        windows[String(w)] = makeRequest(window: w).windowDuration.seconds
    }
    emit(["labels": labels, "known_count": known.count, "constraint": constraint,
          "windows_set": windows])

case "run":
    guard arguments.count == 5, let window = Double(arguments[3]) else {
        die("usage: sound_spike run <file> <window> file|stream")
    }
    let url = URL(fileURLWithPath: arguments[2])
    let mode = arguments[4]
    let request = makeRequest(window: window)
    let collector = Collector()
    let started = now()
    var duration = 0.0
    if mode == "file" {
        guard let analyzer = try? SNAudioFileAnalyzer(url: url) else { die("no file analyzer") }
        do { try analyzer.add(request, withObserver: collector) } catch { die("add: \(error)") }
        analyzer.analyze()
        let asset = AVURLAsset(url: url)
        var assets: [UInt32: AVURLAsset] = [1: asset]
        if let track = CompositionBuilder.assetTrack(at: url, key: 1, mediaType: .audio, assets: &assets) {
            duration = track.timeRange.duration.seconds
        }
    } else {
        var assets: [UInt32: AVURLAsset] = [:]
        guard let track = CompositionBuilder.assetTrack(at: url, key: 1, mediaType: .audio, assets: &assets),
            let asset = assets[1],
            let (reader, output) = MediaImporter.speechReader(asset: asset, track: track),
            reader.canAdd(output)
        else { die("no audio track to read") }
        reader.add(output)
        guard reader.startReading() else { die("the reader did not start") }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let analyzer = SNAudioStreamAnalyzer(format: format)
        do { try analyzer.add(request, withObserver: collector) } catch { die("add: \(error)") }
        var position: AVAudioFramePosition = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let floats = MediaImporter.monoFloats(of: sample), !floats.isEmpty,
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: AVAudioFrameCount(floats.count))
            else { continue }
            buffer.frameLength = AVAudioFrameCount(floats.count)
            floats.withUnsafeBufferPointer { source in
                buffer.floatChannelData![0].update(from: source.baseAddress!, count: floats.count)
            }
            analyzer.analyze(buffer, atAudioFramePosition: position)
            position += AVAudioFramePosition(floats.count)
        }
        let status = reader.status
        reader.cancelReading()
        guard status == .completed else { die("the reader ended \(status.rawValue)") }
        analyzer.completeAnalysis()
        duration = Double(position) / 16_000
    }
    let seconds = now() - started
    collector.lock.lock()
    let rows = collector.rows.sorted { $0.start < $1.start }
    let failure = collector.failure
    collector.lock.unlock()
    if let failure { die("the request failed: \(failure)") }
    var bits = Data()
    for row in rows {
        for value in row.values {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { bits.append(contentsOf: $0) }
        }
    }
    let digest = SHA256.hash(data: bits).map { String(format: "%02x", $0) }.joined()
    emit([
        "mode": mode, "window": window, "window_set": request.windowDuration.seconds,
        "groups": groups.map(\.0), "seconds": seconds, "duration": duration,
        "realtime": seconds > 0 ? duration / seconds : 0, "sha256": digest,
        "windows": rows.map { row -> [String: Any] in
            ["start": row.start, "duration": row.duration,
             "values": row.values.map { $0.isNaN ? NSNull() as Any : Double($0) as Any }]
        },
    ])

default:
    die("unknown mode \(arguments[1])")
}
