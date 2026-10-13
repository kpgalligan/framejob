// Road map 4, S0 (2026-09-13): SoundAnalysis' speech confidence at 0.5 s and
// 1.0 s windows — the non-speech gaps it reports and its separation over the
// level rule's loud and quiet buckets — and Apple's SpeechDetector through the
// STREAMING input path, paired with a transcriber (it traps alone). Any number
// of inputs per run.
//
//   xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 separation_streaming.swift -o separation_streaming
//   ./separation_streaming <media>...
//
// archive/roadmap-4.md §2 quotes its output (q3, q5).
import Foundation
@preconcurrency import AVFoundation
import Speech
import SoundAnalysis

// SpeechDetector through the STREAMING input path, and SoundAnalysis speech-confidence separation.
struct E: Error, CustomStringConvertible { let description: String }

func wav16k(_ url: URL, to out: URL) throws -> [Float] {
    let asset = AVURLAsset(url: url); let sem = DispatchSemaphore(value: 0); var tracks: [AVAssetTrack] = []
    asset.loadTracks(withMediaType: .audio) { t, _ in tracks = t ?? []; sem.signal() }; sem.wait()
    guard let track = tracks.first else { throw E(description: "no audio") }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
    reader.add(output); guard reader.startReading() else { throw E(description: "reader") }
    var s: [Float] = []
    while let sb = output.copyNextSampleBuffer() { guard let b = CMSampleBufferGetDataBuffer(sb) else { continue }; let n = CMBlockBufferGetDataLength(b); var c = [Float](repeating: 0, count: n / 4); c.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(b, atOffset: 0, dataLength: n, destination: $0.baseAddress!) }; s.append(contentsOf: c) }
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    let file = try AVAudioFile(forWriting: out, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(s.count))!; buf.frameLength = AVAudioFrameCount(s.count)
    s.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: s.count) }; try file.write(from: buf)
    return s
}
func db(_ x: Float) -> Double { x > 0 ? 20 * log10(Double(x)) : -120 }
func peaks(_ s: [Float]) -> [Float] { var o: [Float] = []; var i = 0; while i < s.count { let e = min(s.count, i + 160); var m: Float = 0; for j in i..<e { m = max(m, abs(s[j])) }; o.append(m); i = e }; return o }
func pct(_ a: [Double], _ p: Double) -> Double { let s = a.sorted(); return s.isEmpty ? .nan : s[min(s.count - 1, Int(Double(s.count) * p))] }

func detectorStreaming(_ wav: URL, withTranscriber: Bool) async throws -> (Int, Int, String) {
    let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: true)
    var modules: [any SpeechModule] = [detector]
    let transcriber = SpeechTranscriber(locale: Locale(identifier: "en-US"), transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
    if withTranscriber { modules.append(transcriber) }
    let analyzer = SpeechAnalyzer(modules: modules)
    let file = try AVAudioFile(forReading: wav)
    guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else { throw E(description: "no format") }
    let conv = AVAudioConverter(from: file.processingFormat, to: fmt)!
    let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
    let collect = Task { () -> [(Bool, Double, Double)] in var acc: [(Bool, Double, Double)] = []; for try await r in detector.results { acc.append((r.speechDetected, r.range.start.seconds, r.range.end.seconds)) }; return acc }
    let tcount = Task { () -> Int in var n = 0; if withTranscriber { for try await _ in transcriber.results { n += 1 } }; return n }
    let analyze = Task { try await analyzer.analyzeSequence(stream) }
    let frames: AVAudioFrameCount = 4096
    while file.framePosition < file.length {
        let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames)!
        try file.read(into: inBuf, frameCount: frames)
        let outBuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(Double(inBuf.frameLength) * fmt.sampleRate / file.processingFormat.sampleRate) + 16)!
        var fed = false; var err: NSError?
        conv.convert(to: outBuf, error: &err) { _, status in if fed { status.pointee = .noDataNow; return nil }; fed = true; status.pointee = .haveData; return inBuf }
        if let err { throw err }
        cont.yield(AnalyzerInput(buffer: outBuf))
    }
    cont.finish()
    let last = try await analyze.value
    if let last { try await analyzer.finalizeAndFinish(through: last) } else { await analyzer.cancelAndFinishNow() }
    let rows = try await collect.value
    let sample = rows.prefix(10).map { String(format: "%@%.2f–%.2f", $0.0 ? "S" : "·", $0.1, $0.2) }.joined(separator: " ")
    return (rows.count, try await tcount.value, "format=\(fmt.sampleRate)Hz/\(fmt.channelCount)ch  " + sample)
}

final class Obs: NSObject, SNResultsObserving {
    var rows: [(Double, Double, Double)] = []; let done = DispatchSemaphore(value: 0)
    func request(_ request: SNRequest, didProduce result: SNResult) { guard let c = result as? SNClassificationResult else { return }; rows.append((c.timeRange.start.seconds, c.timeRange.end.seconds, c.classification(forIdentifier: "speech")?.confidence ?? 0)) }
    func request(_ request: SNRequest, didFailWithError error: Error) { done.signal() }
    func requestDidComplete(_ request: SNRequest) { done.signal() }
}
func sound(_ wav: URL, window: Double) throws -> [(Double, Double, Double)] {
    let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
    req.windowDuration = CMTime(seconds: window, preferredTimescale: 16000); req.overlapFactor = 0.9
    let o = Obs(); let a = try SNAudioFileAnalyzer(url: wav); try a.add(req, withObserver: o); a.analyze(); _ = o.done.wait(timeout: .now() + 60); return o.rows
}

@main struct Spike2 {
    static func main() async {
        setlinebuf(stdout)
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            let wav = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("spike2-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: wav) }
            do {
                let s = try wav16k(url, to: wav)
                let pk = peaks(s); let floor = pct(pk.map(db), 0.10)
                print("== \(url.lastPathComponent)  floor p10 \(String(format: "%.1f", floor)) dBFS")
                for window in [0.5, 1.0] {
                    let rows = try sound(wav, window: window)
                    // separation: confidence over windows whose centre bucket is > floor+12 (loud) vs <= floor+12 (quiet)
                    var loud: [Double] = []; var quiet: [Double] = []
                    for r in rows { let c = Int(((r.0 + r.1) / 2) * 100); guard c < pk.count else { continue }; if db(pk[c]) > floor + 12 { loud.append(r.2) } else { quiet.append(r.2) } }
                    var gaps: [(Double, Double)] = []
                    for r in rows where r.2 < 0.5 { if let l = gaps.last, r.0 <= l.1 { gaps[gaps.count - 1].1 = max(l.1, r.1) } else { gaps.append((r.0, r.1)) } }
                    let long = gaps.filter { $0.1 - $0.0 >= 0.5 }
                    print(String(format: "  SoundAnalysis window %.1f s: gaps (speech<0.5) >= 0.5 s: %d  %@", window, long.count, long.map { String(format: "%.2f–%.2f", $0.0, $0.1) }.joined(separator: "  ")))
                    print(String(format: "  SoundAnalysis window %.1f s: speech conf over LOUD buckets p10 %.2f p50 %.2f p90 %.2f (n=%d); over QUIET buckets p10 %.2f p50 %.2f p90 %.2f (n=%d)", window, pct(loud, 0.1), pct(loud, 0.5), pct(loud, 0.9), loud.count, pct(quiet, 0.1), pct(quiet, 0.5), pct(quiet, 0.9), quiet.count))
                }
                for withT in [true] {
                    do { let (n, t, note) = try await detectorStreaming(wav, withTranscriber: withT); print("  SpeechDetector streaming withTranscriber=\(withT): \(n) detector results, \(t) transcriber results  \(note)") }
                    catch { print("  SpeechDetector streaming withTranscriber=\(withT): ERROR \(error)") }
                }
            } catch { print("ERROR \(error)") }
        }
    }
}
