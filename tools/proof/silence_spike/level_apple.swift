// Road map 4, S0 (2026-09-13): the level rule re-implemented outside the app
// (10 ms peak buckets of a 16 kHz mono extract, the thresholds −40/−50/−60 and
// an adaptive p10 + 12 dB), Apple's SpeechDetector paired with a
// SpeechTranscriber in file mode, the transcriber's word ranges, and
// SoundAnalysis' built-in classifier at a 0.5 s window. One input per run.
//
//   xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 level_apple.swift -o level_apple
//   ./level_apple <media> [minLength seconds, default 0.5]
//
// archive/roadmap-4.md §2 quotes its output (q1, q2, q3, q4, q5).
import Foundation
import AVFoundation
import Speech
import SoundAnalysis

struct SpikeError: Error, CustomStringConvertible { let description: String }

// MARK: - Extract to 16 kHz mono (the Transcriber's shape), keep the samples
func extract(_ url: URL, to out: URL) throws -> [Float] {
    let asset = AVURLAsset(url: url)
    let sem = DispatchSemaphore(value: 0)
    var tracks: [AVAssetTrack] = []
    asset.loadTracks(withMediaType: .audio) { t, _ in tracks = t ?? []; sem.signal() }
    sem.wait()
    guard let track = tracks.first else { throw SpikeError(description: "no audio track") }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? SpikeError(description: "reader") }
    var samples: [Float] = []
    while let sb = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
        let n = CMBlockBufferGetDataLength(block)
        var chunk = [Float](repeating: 0, count: n / 4)
        chunk.withUnsafeMutableBytes { raw in
            _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: n, destination: raw.baseAddress!)
        }
        samples.append(contentsOf: chunk)
    }
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    let file = try AVAudioFile(forWriting: out, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false],
        commonFormat: .pcmFormatFloat32, interleaved: false)
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buf.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { p in buf.floatChannelData![0].update(from: p.baseAddress!, count: samples.count) }
    try file.write(from: buf)
    return samples
}

// MARK: - Amplitude, the shipped detector's shape: 10 ms peak buckets
func db(_ x: Float) -> Double { x > 0 ? 20 * log10(Double(x)) : -120 }
func buckets(_ s: [Float], rate: Double = 16000, per: Double = 100) -> [Float] {
    let n = Int(rate / per)
    var out: [Float] = []
    var i = 0
    while i < s.count {
        let e = min(s.count, i + n); var m: Float = 0
        for j in i..<e { m = max(m, abs(s[j])) }
        out.append(m); i = e
    }
    return out
}
func rmsBuckets(_ s: [Float], rate: Double = 16000, per: Double = 100) -> [Float] {
    let n = Int(rate / per)
    var out: [Float] = []
    var i = 0
    while i < s.count {
        let e = min(s.count, i + n); var acc: Double = 0
        for j in i..<e { acc += Double(s[j] * s[j]) }
        out.append(Float((acc / Double(max(1, e - i))).squareRoot())); i = e
    }
    return out
}
struct Span { var start: Double; var end: Double }
func quietRuns(_ b: [Float], thresholdDB: Double, minLength: Double, per: Double = 100) -> [Span] {
    var runs: [Span] = []; var start: Int? = nil
    for (i, v) in b.enumerated() {
        let quiet = db(v) <= thresholdDB
        if quiet { if start == nil { start = i } }
        else if let s = start { if Double(i - s) / per >= minLength { runs.append(Span(start: Double(s) / per, end: Double(i) / per)) }; start = nil }
    }
    if let s = start, Double(b.count - s) / per >= minLength { runs.append(Span(start: Double(s) / per, end: Double(b.count) / per)) }
    return runs
}
func percentile(_ sorted: [Double], _ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
func fmt(_ spans: [Span]) -> String { spans.map { String(format: "%.2f–%.2f", $0.start, $0.end) }.joined(separator: "  ") }
func total(_ spans: [Span]) -> Double { spans.reduce(0) { $0 + $1.end - $1.start } }

// MARK: - SpeechDetector paired with SpeechTranscriber (macOS 26 Speech framework)
struct SpeechRun { var detector: [(Bool, Double, Double)]; var words: [(String, Double, Double)]; var note: String }
func speechDetector(_ wav: URL, level: SpeechDetector.SensitivityLevel) async throws -> SpeechRun {
    var note = ""
    let locale = Locale(identifier: "en-US")
    let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
    let installed = await SpeechTranscriber.installedLocales.map { $0.identifier }
    note += "installedLocales=\(installed.count) "
    let t0 = Date()
    if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        note += "installing… "
        try await req.downloadAndInstall()
        note += String(format: "installed in %.1f s ", Date().timeIntervalSince(t0))
    } else { note += "assets present " }
    let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: level), reportResults: true)
    let analyzer = SpeechAnalyzer(modules: [detector, transcriber])
    let file = try AVAudioFile(forReading: wav)
    let collect = Task { () -> [(Bool, Double, Double)] in
        var acc: [(Bool, Double, Double)] = []
        for try await r in detector.results { acc.append((r.speechDetected, r.range.start.seconds, r.range.end.seconds)) }
        return acc
    }
    let words = Task { () -> [(String, Double, Double)] in
        var acc: [(String, Double, Double)] = []
        for try await r in transcriber.results where r.isFinal {
            for run in r.text.runs {
                let text = String(r.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if let range = run.audioTimeRange, !text.isEmpty { acc.append((text, range.start.seconds, range.end.seconds)) }
            }
        }
        return acc
    }
    let last = try await analyzer.analyzeSequence(from: file)
    if let last { try await analyzer.finalizeAndFinish(through: last) } else { await analyzer.cancelAndFinishNow() }
    return SpeechRun(detector: try await collect.value, words: try await words.value, note: note)
}
func wordGaps(_ words: [(String, Double, Double)], minLength: Double) -> [Span] {
    var out: [Span] = []
    for i in 1..<max(1, words.count) { let gap = words[i].1 - words[i - 1].2; if gap >= minLength { out.append(Span(start: words[i - 1].2, end: words[i].1)) } }
    return out
}
func speechGaps(_ rows: [(Bool, Double, Double)], minLength: Double) -> [Span] {
    // merge consecutive non-speech ranges
    var out: [Span] = []
    for r in rows where !r.0 {
        if let l = out.last, abs(l.end - r.1) < 0.001 { out[out.count - 1].end = r.2 } else { out.append(Span(start: r.1, end: r.2)) }
    }
    return out.filter { $0.end - $0.start >= minLength }
}

// MARK: - SoundAnalysis built-in classifier
final class Obs: NSObject, SNResultsObserving {
    var rows: [(Double, Double, Double)] = []
    let done = DispatchSemaphore(value: 0)
    var err: Error?
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let c = result as? SNClassificationResult else { return }
        let conf = c.classification(forIdentifier: "speech")?.confidence ?? 0
        rows.append((c.timeRange.start.seconds, c.timeRange.end.seconds, conf))
    }
    func request(_ request: SNRequest, didFailWithError error: Error) { err = error; done.signal() }
    func requestDidComplete(_ request: SNRequest) { done.signal() }
}
func soundAnalysis(_ wav: URL) throws -> ([(Double, Double, Double)], String) {
    let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
    var note = "constraint=\(req.windowDurationConstraint) hasSpeechLabel=\(req.knownClassifications.contains("speech")) labels=\(req.knownClassifications.count)"
    switch req.windowDurationConstraint {
    case .enumeratedDurations(let ds): if let m = ds.min(by: { $0.seconds < $1.seconds }) { req.windowDuration = m }
    case .durationRange(let r): req.windowDuration = r.start
    @unknown default: break
    }
    req.overlapFactor = 0.9
    note += " window=\(req.windowDuration.seconds)s overlap=\(req.overlapFactor)"
    let obs = Obs()
    let a = try SNAudioFileAnalyzer(url: wav)
    try a.add(req, withObserver: obs)
    a.analyze()
    _ = obs.done.wait(timeout: .now() + 60)
    if let e = obs.err { note += " error=\(e)" }
    return (obs.rows, note)
}
func classifierGaps(_ rows: [(Double, Double, Double)], below: Double, minLength: Double) -> [Span] {
    var out: [Span] = []
    for r in rows where r.2 < below {
        if let l = out.last, r.0 <= l.end { out[out.count - 1].end = max(l.end, r.1) } else { out.append(Span(start: r.0, end: r.1)) }
    }
    return out.filter { $0.end - $0.start >= minLength }
}

@main struct Spike {
    static func main() async {
        setlinebuf(stdout)
        print("SFSpeechRecognizer.authorizationStatus before: \(SFSpeechRecognizer.authorizationStatus().rawValue)")
        let args = CommandLine.arguments
        guard args.count >= 2 else { print("usage: spike <media> [minLength]"); return }
        let url = URL(fileURLWithPath: args[1])
        let minLength = args.count >= 3 ? Double(args[2]) ?? 0.5 : 0.5
        let wav = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("spike-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        do {
            var t0 = Date()
            let samples = try extract(url, to: wav)
            let seconds = Double(samples.count) / 16000
            print(String(format: "file %@  %.2f s  extract %.2f s", url.lastPathComponent, seconds, Date().timeIntervalSince(t0)))

            let pk = buckets(samples); let rm = rmsBuckets(samples)
            let pkDB = pk.map(db).sorted(); let rmDB = rm.map(db).sorted()
            print(String(format: "peak dBFS percentiles  p1 %.1f  p5 %.1f  p10 %.1f  p25 %.1f  p50 %.1f  p75 %.1f  p90 %.1f  p99 %.1f",
                percentile(pkDB, 0.01), percentile(pkDB, 0.05), percentile(pkDB, 0.10), percentile(pkDB, 0.25), percentile(pkDB, 0.5), percentile(pkDB, 0.75), percentile(pkDB, 0.9), percentile(pkDB, 0.99)))
            print(String(format: "rms  dBFS percentiles  p1 %.1f  p5 %.1f  p10 %.1f  p25 %.1f  p50 %.1f  p75 %.1f  p90 %.1f  p99 %.1f",
                percentile(rmDB, 0.01), percentile(rmDB, 0.05), percentile(rmDB, 0.10), percentile(rmDB, 0.25), percentile(rmDB, 0.5), percentile(rmDB, 0.75), percentile(rmDB, 0.9), percentile(rmDB, 0.99)))
            for th in [-40.0, -50.0, -60.0] {
                let q = quietRuns(pk, thresholdDB: th, minLength: minLength)
                print(String(format: "amplitude %.0f dBFS min %.1f s: %d runs, %.2f s   %@", th, minLength, q.count, total(q), fmt(q)))
            }
            let floor = percentile(pkDB, 0.10)
            let adaptive = floor + 12
            let qa = quietRuns(pk, thresholdDB: adaptive, minLength: minLength)
            print(String(format: "amplitude ADAPTIVE (p10 %.1f + 12 = %.1f dBFS): %d runs, %.2f s   %@", floor, adaptive, qa.count, total(qa), fmt(qa)))

            // SoundAnalysis FIRST, since the speech section can crash the process.
            t0 = Date()
            let (srows, note) = try soundAnalysis(wav)
            let dts = Date().timeIntervalSince(t0)
            let sg = classifierGaps(srows, below: 0.5, minLength: minLength)
            print(String(format: "SoundAnalysis: %@; %d windows in %.2f s (%.1fx realtime); gaps (speech<0.5) ≥ %.1f s: %d, %.2f s   %@", note, srows.count, dts, seconds / max(dts, 0.001), minLength, sg.count, total(sg), fmt(sg)))
            print("  first 12 windows: " + srows.prefix(12).map { String(format: "%.2f–%.2f:%.2f", $0.0, $0.1, $0.2) }.joined(separator: " "))

            for level in [SpeechDetector.SensitivityLevel.low, .medium, .high] {
                t0 = Date()
                let run = try await speechDetector(wav, level: level)
                let rows = run.detector
                let dt = Date().timeIntervalSince(t0)
                let gaps = speechGaps(rows, minLength: minLength)
                let lens = rows.map { $0.2 - $0.1 }.sorted()
                print(String(format: "SpeechDetector %@ (%@): %d results in %.2f s (%.1fx realtime); range lengths min %.3f median %.3f max %.3f; speech %.2f s; gaps ≥ %.1f s: %d, %.2f s   %@",
                    "\(level)", run.note, rows.count, dt, seconds / max(dt, 0.001), lens.first ?? 0, lens.isEmpty ? 0 : lens[lens.count / 2], lens.last ?? 0,
                    rows.filter { $0.0 }.reduce(0) { $0 + $1.2 - $1.1 }, minLength, gaps.count, total(gaps), fmt(gaps)))
                print("  first 16 results: " + rows.prefix(16).map { String(format: "%@%.2f–%.2f", $0.0 ? "S" : "·", $0.1, $0.2) }.joined(separator: " "))
                if level == .medium {
                    let wg = wordGaps(run.words, minLength: minLength)
                    print(String(format: "  transcriber: %d words; word gaps ≥ %.1f s: %d, %.2f s   %@", run.words.count, minLength, wg.count, total(wg), fmt(wg)))
                    print("  words: " + run.words.prefix(40).map { String(format: "%@[%.2f–%.2f]", $0.0, $0.1, $0.2) }.joined(separator: " "))
                }
            }
            print("SFSpeechRecognizer.authorizationStatus after: \(SFSpeechRecognizer.authorizationStatus().rawValue)")
        } catch {
            print("ERROR: \(error)")
        }
    }
}
