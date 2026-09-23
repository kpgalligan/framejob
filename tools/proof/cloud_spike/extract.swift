// tools/proof/cloud_spike/extract.swift — road map 6, spike C0's audio probe.
//
// A STANDALONE AVFoundation instrument: it takes nothing from `app/Sources`
// (the spike runs before C1's first line), but its writer settings are
// `Transcriber.extractSettings` VERBATIM — 16 kHz mono 16-bit little-endian
// LPCM — and its reader is set up the way the shipped extractor sets one up,
// `reader.timeRange = (.zero, asset.duration)` over the whole asset and
// `startSession(atSourceTime: .zero)`, because q4's whole question is what
// that pair does to a track that starts late.
//
// Built by the runner with
//   xcrun swiftc -O -target arm64-apple-macos26.0 extract.swift -o bin/extract
// and every mode prints ONE JSON object on stdout.
//
//   extract wav   <in> <out>            → {ok, frames, seconds, bytes, first_pts_seconds}
//   extract m4a   <in> <out> <bitrate>  → the same, AAC-LC in an .m4a
//   extract flac  <in> <out>            → the same, FLAC (ok:false when the writer refuses)
//   extract tracks <in>                 → the audio track's time range and its segments
//   extract lag   <reference.wav> <candidate> <maxLagSamples>
//                                       → {lag_samples, lag_ms, correlation}

import AVFoundation
import Accelerate
import Foundation

func emit(_ object: [String: Any]) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data("{\"ok\":false,\"error\":\"unserialisable\"}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

func fail(_ message: String) -> Never { emit(["ok": false, "error": message]) }

let extractSampleRate = 16000

/// `app/Sources/Transcriber+Extract.swift`'s `extractSettings`, copied by hand.
let extractSettings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatLinearPCM),
    AVSampleRateKey: extractSampleRate,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsNonInterleaved: false,
]

/// A time as JSON. An EMPTY edit's source start is `kCMTimeInvalid`, whose
/// seconds are NaN, and `NSJSONSerialization` throws on a NaN — which is how
/// the first run of q4 lost the one answer it was there to read.
func number(_ time: CMTime) -> Any {
    let value = CMTimeGetSeconds(time)
    return value.isFinite ? value : NSNull()
}

func audioTrack(_ asset: AVURLAsset) -> AVAssetTrack? {
    asset.tracks(withMediaType: .audio).first
}

/// Every 16-bit sample of a file, decoded at the extract settings.
func decode(_ url: URL) throws -> (samples: [Int16], firstPTS: Double) {
    let asset = AVURLAsset(url: url)
    guard let track = audioTrack(asset) else { throw NSError(domain: "extract", code: 1) }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: extractSettings)
    output.alwaysCopiesSampleData = false
    reader.add(output)
    reader.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
    reader.startReading()
    var samples: [Int16] = []
    var firstPTS = Double.nan
    while let buffer = output.copyNextSampleBuffer() {
        if firstPTS.isNaN {
            firstPTS = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
        }
        if let block = CMSampleBufferGetDataBuffer(buffer) {
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                        totalLengthOut: &length, dataPointerOut: &pointer)
            if let start = pointer, length > 1 {
                start.withMemoryRebound(to: Int16.self, capacity: length / 2) { typed in
                    samples.append(contentsOf: UnsafeBufferPointer(start: typed, count: length / 2))
                }
            }
        }
    }
    if reader.status == .failed { throw reader.error ?? NSError(domain: "extract", code: 2) }
    return (samples, firstPTS.isNaN ? 0 : firstPTS)
}

/// The shipped extractor's shape: whole asset in, one writer input out.
func write(_ input: URL, to output: URL, settings: [String: Any], fileType: AVFileType) -> [String: Any] {
    let asset = AVURLAsset(url: input)
    guard let track = audioTrack(asset) else { return ["ok": false, "error": "no audio track"] }
    try? FileManager.default.removeItem(at: output)
    do {
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: extractSettings)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { return ["ok": false, "error": "reader refused the output"] }
        reader.add(readerOutput)
        reader.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let writer = try AVAssetWriter(outputURL: output, fileType: fileType)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { return ["ok": false, "error": "writer refused the input"] }
        writer.add(writerInput)
        guard reader.startReading(), writer.startWriting() else {
            return ["ok": false,
                    "error": "start failed: \(reader.error?.localizedDescription ?? "-") / "
                        + "\(writer.error?.localizedDescription ?? "-")"]
        }
        writer.startSession(atSourceTime: .zero)
        var frames: Int64 = 0
        var firstPTS = Double.nan
        let queue = DispatchQueue(label: "extract.write")
        let done = DispatchSemaphore(value: 0)
        writerInput.requestMediaDataWhenReady(on: queue) {
            while writerInput.isReadyForMoreMediaData {
                guard let buffer = readerOutput.copyNextSampleBuffer() else {
                    writerInput.markAsFinished()
                    done.signal()
                    return
                }
                if firstPTS.isNaN {
                    firstPTS = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
                }
                frames += Int64(CMSampleBufferGetNumSamples(buffer))
                writerInput.append(buffer)
            }
        }
        done.wait()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        if writer.status != .completed {
            return ["ok": false, "error": writer.error?.localizedDescription ?? "writer did not complete"]
        }
        let sized = try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int
        return ["ok": true, "frames": frames,
                "seconds": Double(frames) / Double(extractSampleRate),
                "bytes": (sized ?? 0) ?? 0,
                "first_pts_seconds": firstPTS.isNaN ? 0 : firstPTS]
    } catch {
        return ["ok": false, "error": error.localizedDescription]
    }
}

/// FLAC at the extract settings, written through `AVAudioFile`.
///
/// `AVAssetWriter` on this host answers "Invalid file type UTI" for
/// `org.xiph.flac` — and it answers it as an Objective-C exception, which
/// Swift cannot catch — so the write goes through the `ExtAudioFile` path
/// road map 6 §3's q2 row named as the alternative. A refusal comes back as
/// `ok: false` with the framework's own sentence.
func flac(_ input: URL, to output: URL) -> [String: Any] {
    try? FileManager.default.removeItem(at: output)
    do {
        let decoded = try decode(input)
        guard let source = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: Double(extractSampleRate),
                                         channels: 1, interleaved: true) else {
            return ["ok": false, "error": "no source format"]
        }
        let file = try AVAudioFile(forWriting: output, settings: [
            AVFormatIDKey: Int(kAudioFormatFLAC),
            AVSampleRateKey: extractSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
        ], commonFormat: .pcmFormatInt16, interleaved: true)
        var written = 0
        while written < decoded.samples.count {
            let count = min(16384, decoded.samples.count - written)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: source,
                                                frameCapacity: AVAudioFrameCount(count)) else {
                return ["ok": false, "error": "no buffer"]
            }
            buffer.frameLength = AVAudioFrameCount(count)
            if let channel = buffer.int16ChannelData {
                for index in 0 ..< count { channel[0][index] = decoded.samples[written + index] }
            }
            try file.write(from: buffer)
            written += count
        }
        let sized = try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int
        return ["ok": true, "frames": written,
                "seconds": Double(written) / Double(extractSampleRate),
                "bytes": (sized ?? 0) ?? 0,
                "first_pts_seconds": decoded.firstPTS]
    } catch {
        return ["ok": false, "error": error.localizedDescription]
    }
}

func tracks(_ input: URL) -> [String: Any] {
    let asset = AVURLAsset(url: input)
    guard let track = audioTrack(asset) else { return ["ok": false, "error": "no audio track"] }
    var rows: [[String: Any]] = []
    for segment in track.segments {
        rows.append([
            "empty": segment.isEmpty,
            "source_start": number(segment.timeMapping.source.start),
            "source_duration": number(segment.timeMapping.source.duration),
            "target_start": number(segment.timeMapping.target.start),
            "target_duration": number(segment.timeMapping.target.duration),
        ])
    }
    return ["ok": true,
            "asset_duration": number(asset.duration),
            "track_start": number(track.timeRange.start),
            "track_duration": number(track.timeRange.duration),
            "segments": rows]
}

/// Where `candidate` sits against `reference`, in samples, by normalised
/// cross-correlation of the reference's loudest half second.
func lag(reference: URL, candidate: URL, maxLag: Int) -> [String: Any] {
    do {
        let left = try decode(reference).samples
        let right = try decode(candidate)
        let window = min(8000, left.count / 4)
        guard window > 64, right.samples.count > window else {
            return ["ok": false, "error": "too little audio to correlate"]
        }
        var a = [Float](repeating: 0, count: left.count)
        vDSP.convertElements(of: left, to: &a)
        var b = [Float](repeating: 0, count: right.samples.count)
        vDSP.convertElements(of: right.samples, to: &b)
        // The loudest window of the reference, so the peak is a peak.
        var best = 0
        var bestEnergy = Float(-1)
        var index = 0
        while index + window <= a.count {
            let energy = vDSP.sumOfSquares(a[index ..< index + window])
            if energy > bestEnergy { bestEnergy = energy; best = index }
            index += window / 2
        }
        let filter = Array(a[best ..< best + window])
        let from = max(0, best - maxLag)
        let to = min(b.count - window, best + maxLag)
        guard to >= from else { return ["ok": false, "error": "the candidate is shorter than the search"] }
        let results = to - from + 1
        var correlation = [Float](repeating: 0, count: results)
        let signal = Array(b[from ..< min(b.count, from + results + window - 1)])
        guard signal.count >= results + window - 1 else {
            return ["ok": false, "error": "the candidate is shorter than the search window"]
        }
        vDSP_conv(signal, 1, filter, 1, &correlation, 1, vDSP_Length(results), vDSP_Length(window))
        // Normalise each lag by its own energy, so a loud stretch cannot win
        // on level alone.
        var peak = -2.0
        var peakIndex = 0
        let filterNorm = sqrt(Double(vDSP.sumOfSquares(filter)))
        // The sliding energy is accumulated in DOUBLE: a Float running sum
        // over eighty thousand updates at these magnitudes drifts far enough
        // to move the peak, which is how the first build of this probe put a
        // file's lag against ITSELF at 35 943 samples.
        var running = 0.0
        for index in 0 ..< window { running += Double(signal[index]) * Double(signal[index]) }
        for n in 0 ..< results {
            if n > 0 {
                let entering = Double(signal[n + window - 1])
                let leaving = Double(signal[n - 1])
                running += entering * entering - leaving * leaving
            }
            let denominator = filterNorm * sqrt(max(running, 1))
            let value = denominator > 0 ? Double(correlation[n]) / denominator : 0
            if value > peak { peak = value; peakIndex = n }
        }
        let samples = (from + peakIndex) - best
        return ["ok": true,
                "lag_samples": samples,
                "lag_ms": Double(samples) * 1000.0 / Double(extractSampleRate),
                "correlation": peak,
                "reference_samples": left.count,
                "candidate_samples": right.samples.count,
                "candidate_first_pts_seconds": right.firstPTS]
    } catch {
        return ["ok": false, "error": error.localizedDescription]
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fail("usage: extract wav|m4a|flac|tracks|lag …") }
let mode = arguments[1]
let first = URL(fileURLWithPath: arguments[2])

switch mode {
case "wav":
    guard arguments.count >= 4 else { fail("usage: extract wav <in> <out>") }
    emit(write(first, to: URL(fileURLWithPath: arguments[3]),
               settings: extractSettings, fileType: .wav))
case "m4a":
    guard arguments.count >= 5, let bitrate = Int(arguments[4]) else {
        fail("usage: extract m4a <in> <out> <bitrate>")
    }
    var mono = AudioChannelLayout()
    mono.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
    emit(write(first, to: URL(fileURLWithPath: arguments[3]), settings: [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: extractSampleRate,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: bitrate,
        AVChannelLayoutKey: Data(bytes: &mono, count: MemoryLayout<AudioChannelLayout>.size),
    ], fileType: .m4a))
case "flac":
    guard arguments.count >= 4 else { fail("usage: extract flac <in> <out>") }
    emit(flac(first, to: URL(fileURLWithPath: arguments[3])))
case "tracks":
    emit(tracks(first))
case "lag":
    guard arguments.count >= 5, let maximum = Int(arguments[4]) else {
        fail("usage: extract lag <reference.wav> <candidate> <maxLagSamples>")
    }
    emit(lag(reference: first, candidate: URL(fileURLWithPath: arguments[3]), maxLag: maximum))
default:
    fail("unknown mode \(mode)")
}
