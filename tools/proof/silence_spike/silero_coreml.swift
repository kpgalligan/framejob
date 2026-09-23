// Road map 4, S0 (2026-09-13): Silero VAD v6.2.1 through Core ML — the 32 ms
// streaming variant of aufklarer/Silero-VAD-v6.2.1-CoreML (MIT), driven over
// MLModel.prediction with the 64-sample context carried and the LSTM state fed
// back. Reports speed, the non-speech spans at probability < 0.5 (with and
// without Silero's own hysteresis), the edge error against the say fixture's
// known pauses, and a 32 ms trace around the first pause.
//
// The model is NOT in the tree. Fetch it beside this file (the README has the
// five files and their ETags), or point SILERO_MLMODELC at a .mlmodelc:
//
//   xcrun swiftc -O -target arm64-apple-macos26.0 silero_coreml.swift -o silero_coreml
//   SILERO_MLMODELC=./silero_vad.mlmodelc ./silero_coreml <media>...
//
// designs/reelcut-roadmap-4.md §2 quotes its output (q6, q7).
import Foundation
@preconcurrency import AVFoundation
import CoreML

struct E: Error, CustomStringConvertible { let description: String }
func mono16k(_ url: URL) throws -> [Float] {
    let asset = AVURLAsset(url: url); let sem = DispatchSemaphore(value: 0); var tracks: [AVAssetTrack] = []
    asset.loadTracks(withMediaType: .audio) { t, _ in tracks = t ?? []; sem.signal() }; sem.wait()
    guard let track = tracks.first else { throw E(description: "no audio") }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
    reader.add(output); guard reader.startReading() else { throw E(description: "reader") }
    var s: [Float] = []
    while let sb = output.copyNextSampleBuffer() { guard let b = CMSampleBufferGetDataBuffer(sb) else { continue }; let n = CMBlockBufferGetDataLength(b); var c = [Float](repeating: 0, count: n / 4); c.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(b, atOffset: 0, dataLength: n, destination: $0.baseAddress!) }; s.append(contentsOf: c) }
    return s
}
func db(_ x: Float) -> Double { x > 0 ? 20 * log10(Double(x)) : -120 }
func peaks(_ s: [Float]) -> [Float] { var o: [Float] = []; var i = 0; while i < s.count { let e = min(s.count, i + 160); var m: Float = 0; for j in i..<e { m = max(m, abs(s[j])) }; o.append(m); i = e }; return o }
func pct(_ a: [Double], _ p: Double) -> Double { let s = a.sorted(); return s.isEmpty ? .nan : s[min(s.count - 1, Int(Double(s.count) * p))] }
struct Span { var start: Double; var end: Double }
func fmt(_ spans: [Span]) -> String { spans.map { String(format: "%.2f–%.2f", $0.start, $0.end) }.joined(separator: "  ") }

/// Silero v6.2.1 (Core ML): 512 new samples per call at 16 kHz, 64 samples of left context, LSTM state fed back.
final class Silero {
    let model: MLModel
    var h: MLMultiArray; var c: MLMultiArray
    init(_ url: URL) throws {
        let cfg = MLModelConfiguration(); cfg.computeUnits = .cpuAndNeuralEngine
        model = try MLModel(contentsOf: url, configuration: cfg)
        h = try MLMultiArray(shape: [1, 1, 128], dataType: .float16); c = try MLMultiArray(shape: [1, 1, 128], dataType: .float16)
        for i in 0..<128 { h[i] = 0; c[i] = 0 }
    }
    /// One probability per 32 ms chunk over the whole signal.
    func run(_ s: [Float]) throws -> [Float] {
        var probs: [Float] = []
        var context = [Float](repeating: 0, count: 64)
        let audio = try MLMultiArray(shape: [1, 1, 576], dataType: .float16)
        var i = 0
        while i + 512 <= s.count {
            audio.withUnsafeMutableBytes { raw, _ in
                let p = raw.bindMemory(to: Float16.self)
                for k in 0..<64 { p[k] = Float16(context[k]) }
                for k in 0..<512 { p[64 + k] = Float16(s[i + k]) }
            }
            let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["audio": audio, "h": h, "c": c]))
            probs.append(Float(truncating: out.featureValue(for: "probability")!.multiArrayValue![0]))
            h = out.featureValue(for: "h_out")!.multiArrayValue!; c = out.featureValue(for: "c_out")!.multiArrayValue!
            context = Array(s[(i + 512 - 64)..<(i + 512)])
            i += 512
        }
        return probs
    }
}
/// Non-speech spans with hysteresis (onset / offset thresholds, Silero's own post-processing shape), merged, at least minLength long.
func gaps(_ probs: [Float], onset: Float, offset: Float, minLength: Double) -> [Span] {
    let hop = 512.0 / 16000.0
    var out: [Span] = []; var speaking = false; var gapStart = 0.0
    for (i, p) in probs.enumerated() {
        let t = Double(i) * hop
        if speaking { if p < offset { speaking = false; gapStart = t } }
        else if p >= onset { speaking = true; if t - gapStart >= minLength { out.append(Span(start: gapStart, end: t)) } }
    }
    if !speaking { let t = Double(probs.count) * hop; if t - gapStart >= minLength { out.append(Span(start: gapStart, end: t)) } }
    return out
}

let modelURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SILERO_MLMODELC"] ?? "silero_vad.mlmodelc")
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    do {
        let s = try mono16k(url); let seconds = Double(s.count) / 16000
        let pk = peaks(s); let floor = pct(pk.map(db), 0.10)
        let t0 = Date(); let vad = try Silero(modelURL); let load = Date().timeIntervalSince(t0)
        let t1 = Date(); let probs = try vad.run(s); let dt = Date().timeIntervalSince(t1)
        // separation against the LEVEL split (loud = bucket > floor + 12 dB), same confound as before: quiet includes soft syllables
        var loud: [Double] = []; var quiet: [Double] = []
        for (i, p) in probs.enumerated() { let b = Int(Double(i) * 512.0 / 160.0 + 1.6); guard b < pk.count else { continue }; (db(pk[b]) > floor + 12 ? { loud.append(Double(p)) } : { quiet.append(Double(p)) })() }
        print(String(format: "== %@  %.2f s  floor p10 %.1f dBFS  load %.2f s  %d chunks in %.2f s (%.0fx realtime)", url.lastPathComponent, seconds, floor, load, probs.count, dt, seconds / max(dt, 0.001)))
        print(String(format: "  prob over LOUD buckets p10 %.2f p50 %.2f p90 %.2f (n=%d); over QUIET buckets p10 %.2f p50 %.2f p90 %.2f (n=%d)", pct(loud, 0.1), pct(loud, 0.5), pct(loud, 0.9), loud.count, pct(quiet, 0.1), pct(quiet, 0.5), pct(quiet, 0.9), quiet.count))
        let g1 = gaps(probs, onset: 0.5, offset: 0.5, minLength: 0.5)
        let g2 = gaps(probs, onset: 0.5, offset: 0.35, minLength: 0.5)
        print(String(format: "  gaps ≥ 0.5 s, threshold 0.5: %d  %@", g1.count, fmt(g1)))
        print(String(format: "  gaps ≥ 0.5 s, onset 0.5 / offset 0.35: %d  %@", g2.count, fmt(g2)))
        if url.lastPathComponent != "speech.aiff", !url.lastPathComponent.hasPrefix("Screen") { } 
        if ["speech.aiff", "quiet.wav", "hum.wav", "hum2.wav", "hum3.wav", "quiet2.wav"].contains(url.lastPathComponent) {
            let truth = [Span(start: 2.72, end: 4.29), Span(start: 6.68, end: 7.81)]
            let err = zip(truth, g2.prefix(2)).map { String(format: "start %+.3f end %+.3f", $1.start - $0.start, $1.end - $0.end) }.joined(separator: " | ")
            print("  edge error vs the level rule's exact pauses (2.72–4.29, 6.68–7.81): \(err)")
        }
        // a 32 ms probability trace around the first pause, for the record
        let from = Int(2.4 / 0.032), to = min(probs.count, Int(4.6 / 0.032))
        if to > from, url.lastPathComponent == "speech.aiff" || url.lastPathComponent == "hum3.wav" { print("  trace 2.40–4.60 s: " + probs[from..<to].map { String(format: "%.2f", $0) }.joined(separator: " ")) }
    } catch { print("ERROR \(path): \(error)") }
}
