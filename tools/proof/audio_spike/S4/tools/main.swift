import Accelerate
import AVFoundation
import CryptoKit
import Foundation

let args = CommandLine.arguments
func arg(_ i: Int) -> String { args[i] }
func secondsNow() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
func load() -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/uptime")
    let pipe = Pipe(); p.standardOutput = pipe
    try! p.run(); p.waitUntilExit()
    let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
    return s.components(separatedBy: "load averages:").last!.trimmingCharacters(in: .whitespacesAndNewlines)
}
func cpuSeconds() -> Double {
    var u = rusage(); getrusage(RUSAGE_SELF, &u)
    return Double(u.ru_utime.tv_sec) + Double(u.ru_utime.tv_usec) / 1e6
        + Double(u.ru_stime.tv_sec) + Double(u.ru_stime.tv_usec) / 1e6
}

/// Windows file: one "start end" (seconds) per line.
func readWindows(_ path: String) -> [(Double, Double)] {
    try! String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").compactMap { line in
        let p = line.split(separator: " ").compactMap { Double($0) }
        return p.count == 2 ? (p[0], p[1]) : nil
    }
}

switch args[1] {

case "decode":  // decode <in> <out.f32> [rate]
    let rate = args.count > 4 ? Double(arg(4)) : nil
    let pcm = decode(URL(fileURLWithPath: arg(2)), rate: rate)
    writeRaw(pcm, to: arg(3))
    print("rate \(pcm.rate) channels \(pcm.channels) frames \(pcm.frames) seconds \(Double(pcm.frames) / pcm.rate)")

case "sanity":  // sanity <in.f32> <rate> <ch>
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: Int(arg(4))!)
    let derived = KWeight.derived(rate: 48000)
    let t = KWeight.table48
    print("derived@48k vs table: s1 b0 \(derived.0.b0 - t.0.b0) b1 \(derived.0.b1 - t.0.b1) b2 \(derived.0.b2 - t.0.b2) a1 \(derived.0.a1 - t.0.a1) a2 \(derived.0.a2 - t.0.a2)")
    print("                      s2 a1 \(derived.1.a1 - t.1.a1) a2 \(derived.1.a2 - t.1.a2)")
    if pcm.rate == 48000 {
        let meter = LoudnessMeter(sampleRate: 48000, channelCount: pcm.channels)!
        pcm.samples.withUnsafeBufferPointer { meter.feed($0.baseAddress!, frames: pcm.frames) }
        let r = meter.finish()
        let d = direct(pcm, fa: 0, fb: pcm.frames, coefficients: KWeight.table48)
        let dd = direct(pcm, fa: 0, fb: pcm.frames, coefficients: derived)
        print("LoudnessMeter (verbatim)  I \(fmt(r.integratedLUFS, 4))  TP \(fmt(r.truePeakDBTP, 4))  SP \(fmt(r.samplePeakDBFS, 4))")
        print("direct (table)            I \(fmt(d.lufs, 4))  TP \(fmt(d.truePeakDB, 4))  SP \(fmt(d.samplePeakDB, 4))")
        print("direct (derived coeffs)   I \(fmt(dd.lufs, 4))  TP \(fmt(dd.truePeakDB, 4))")
    }

case "windows":  // windows <in.f32> <rate> <ch> <bps> <windowsfile> [derived]
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: Int(arg(4))!)
    let bps = Int(arg(5))!
    let coeffs = KWeight.coefficients(rate: pcm.rate, useTableAt48: !(args.count > 7 && arg(7) == "derived"))
    let (cache, _) = buildCache(pcm, blocksPerSecond: bps, coefficients: coeffs)
    print("# grain \(1000 / bps) ms, rate \(pcm.rate), ch \(pcm.channels), frames \(pcm.frames)")
    print("# start end | cacheNearest cacheOutward cacheInward | direct phaseMin phaseMax | cacheTP directTP cacheSP directSP")
    for (a, b) in readWindows(arg(6)) {
        let fa = Int((a * pcm.rate).rounded()), fb = min(pcm.frames, Int((b * pcm.rate).rounded()))
        let ex = CommandLine.arguments.contains("--exact-count")
        let n = query(cache, fa: fa, fb: fb, snap: .nearest, exactCount: ex)
        let o = query(cache, fa: fa, fb: fb, snap: .outward, exactCount: ex)
        let i = query(cache, fa: fa, fb: fb, snap: .inward, exactCount: ex)
        let d = direct(pcm, fa: fa, fb: fb, coefficients: coeffs)
        var phases: [Double] = []
        for k in 0..<10 {
            let lead = Int((Double(k) * 0.010 * pcm.rate).rounded())
            if let l = direct(pcm, fa: fa, fb: fb, coefficients: coeffs, leadSilence: lead).lufs { phases.append(l) }
        }
        print(String(format: "%.6f %.6f | %@ %@ %@ | %@ %@ %@ | %@ %@ %@ %@",
                     a, b, fmt(n.lufs, 4), fmt(o.lufs, 4), fmt(i.lufs, 4), fmt(d.lufs, 4),
                     fmt(phases.min(), 4), fmt(phases.max(), 4),
                     fmt(n.truePeakDB, 4), fmt(d.truePeakDB, 4), fmt(n.samplePeakDB, 4), fmt(d.samplePeakDB, 4)))
    }

case "stats":  // stats <in.f32> <rate> <ch> <count> <minS> <maxS> <seed>
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: Int(arg(4))!)
    let count = Int(arg(5))!, minS = Double(arg(6))!, maxS = Double(arg(7))!
    var rng = UInt64(arg(8))!
    func rnd() -> Double { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Double(rng >> 11) / Double(1 << 53) }
    let coeffs = KWeight.coefficients(rate: pcm.rate)
    let c100 = buildCache(pcm, blocksPerSecond: 10, coefficients: coeffs).0
    let c25 = buildCache(pcm, blocksPerSecond: 40, coefficients: coeffs).0
    let c10 = buildCache(pcm, blocksPerSecond: 100, coefficients: coeffs).0
    let T = Double(pcm.frames) / pcm.rate
    print("# dur spread | e100 e25 e10 e10dense | out100 out25 out10 out10dense (distance outside the phase band) | dense-phaseMean")
    for _ in 0..<count {
        let d = minS + (maxS - minS) * rnd()
        let a = (T - d) * rnd()
        let fa = Int((a * pcm.rate).rounded()), fb = min(pcm.frames, Int(((a + d) * pcm.rate).rounded()))
        let d0 = direct(pcm, fa: fa, fb: fb, coefficients: coeffs).lufs ?? .nan
        var phases: [Double] = []
        for k in 0..<10 {
            let lead = Int((Double(k) * 0.010 * pcm.rate).rounded())
            if let l = direct(pcm, fa: fa, fb: fb, coefficients: coeffs, leadSilence: lead).lufs { phases.append(l) }
        }
        let lo = phases.min()!, hi = phases.max()!
        let mean = phases.reduce(0, +) / Double(phases.count)
        func out(_ x: Double) -> Double { x < lo ? lo - x : (x > hi ? x - hi : 0) }
        let ex = CommandLine.arguments.contains("--exact-count")
        let q100 = query(c100, fa: fa, fb: fb, exactCount: ex).lufs ?? .nan
        let q25 = query(c25, fa: fa, fb: fb, exactCount: ex).lufs ?? .nan
        let q10 = query(c10, fa: fa, fb: fb, exactCount: ex).lufs ?? .nan
        let q10d = query(c10, fa: fa, fb: fb, dense: true).lufs ?? .nan
        print(String(format: "%.2f %.4f | %.4f %.4f %.4f %.4f | %.4f %.4f %.4f %.4f | %.4f", d, hi - lo,
                     q100 - d0, q25 - d0, q10 - d0, q10d - d0, out(q100), out(q25), out(q10), out(q10d), q10d - mean))
    }

case "speed":  // speed <in.f32> <rate> <ch> <windowsfile>: time-scaled gating at 10 ms grain
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: Int(arg(4))!)
    let (cache, _) = buildCache(pcm, blocksPerSecond: 100, coefficients: KWeight.coefficients(rate: pcm.rate))
    for (a, b) in readWindows(arg(5)) {
        let fa = Int((a * pcm.rate).rounded()), fb = min(pcm.frames, Int((b * pcm.rate).rounded()))
        var line = String(format: "%.3f %.3f", a, b)
        for sp in [1.0, 0.5, 0.8, 1.25, 2.0] {
            line += String(format: " x%.2f %@", sp, fmt(query(cache, fa: fa, fb: fb, speed: sp, exactCount: true).lufs, 3))
        }
        print(line)
    }

case "compmix":  // compmix <mono file>: the export's reader over a composition of the file
    let url = URL(fileURLWithPath: arg(2))
    let asset = AVURLAsset(url: url)
    let source = asset.tracks(withMediaType: .audio)[0]
    let comp = AVMutableComposition()
    let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try! track.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: source, at: .zero)
    let params = AVMutableAudioMixInputParameters(track: track)
    params.setVolume(1, at: .zero)
    let mix = AVMutableAudioMix()
    mix.inputParameters = [params]
    let reader = try! AVAssetReader(asset: comp)
    let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let out = AVAssetReaderAudioMixOutput(audioTracks: comp.tracks(withMediaType: .audio), audioSettings: settings)
    out.audioMix = mix
    reader.add(out)
    reader.startReading()
    var samples: [Float] = []
    while let sb = out.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
        let n = CMBlockBufferGetDataLength(block) / 4
        let base = samples.count
        samples.append(contentsOf: repeatElement(0, count: n))
        samples.withUnsafeMutableBytes { raw in
            _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: n * 4, destination: raw.baseAddress! + base * 4)
        }
    }
    let st = PCM(samples: samples, rate: 48000, channels: 2)
    let mono = decode(url)
    var maxLR: Float = 0, maxLM: Float = 0
    for f in 0..<min(st.frames, mono.frames) {
        maxLR = max(maxLR, abs(st.samples[2 * f] - st.samples[2 * f + 1]))
        maxLM = max(maxLM, abs(st.samples[2 * f] - mono.samples[f]))
    }
    let m = direct(st, fa: 0, fb: st.frames, coefficients: KWeight.table48)
    let mm = direct(mono, fa: 0, fb: mono.frames, coefficients: KWeight.table48)
    print("composition mix: frames \(st.frames), max |L-R| \(maxLR), max |L-mono| \(maxLM); stereo mix \(fmt(m.lufs, 4)) LUFS vs mono \(fmt(mm.lufs, 4)) LUFS")

case "qtime":  // qtime <in.f32> <rate> <ch>: how long a whole-file query takes, and a direct pass
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: Int(arg(4))!)
    let coeffs = KWeight.coefficients(rate: pcm.rate)
    for bps in [10, 100] {
        let (cache, _) = buildCache(pcm, blocksPerSecond: bps, coefficients: coeffs, floatPeak: true)
        var best = Double.infinity
        var answer: WindowAnswer! = nil
        for _ in 0..<5 {
            let t0 = secondsNow()
            answer = query(cache, fa: 0, fb: pcm.frames)
            best = min(best, secondsNow() - t0)
        }
        print(String(format: "query of the whole %.0f s from the %d ms cache: %.2f ms (I %@)", Double(pcm.frames) / pcm.rate, 1000 / bps, best * 1000, fmt(answer.lufs, 3)))
    }
    let t0 = secondsNow()
    let d = direct(pcm, fa: 0, fb: pcm.frames, coefficients: coeffs)
    print(String(format: "direct pass over memory (no decode): %.3f s (I %@)", secondsNow() - t0, fmt(d.lufs, 3)))

case "grains":  // grains <in.f32> <rate> <ch> <count> <minS> <maxS> <seed>: |cache - direct| per grain, exact count
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: Int(arg(4))!)
    let count = Int(arg(5))!, minS = Double(arg(6))!, maxS = Double(arg(7))!
    var rng = UInt64(arg(8))!
    func rnd() -> Double { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Double(rng >> 11) / Double(1 << 53) }
    let coeffs = KWeight.coefficients(rate: pcm.rate)
    let grains = [10, 20, 40, 100, 200, 1000]
    let caches = grains.map { buildCache(pcm, blocksPerSecond: $0, coefficients: coeffs, floatPeak: true).0 }
    let T = Double(pcm.frames) / pcm.rate
    var errs = Array(repeating: [Double](), count: grains.count)
    var tpUnder = 0; var tpWorst = 0.0; var tpSampleUnder = false
    for _ in 0..<count {
        let d = minS + (maxS - minS) * rnd()
        let a = (T - d) * rnd()
        let fa = Int((a * pcm.rate).rounded()), fb = min(pcm.frames, Int(((a + d) * pcm.rate).rounded()))
        let dir = direct(pcm, fa: fa, fb: fb, coefficients: coeffs)
        for (i, c) in caches.enumerated() {
            let q = query(c, fa: fa, fb: fb, exactCount: true)
            errs[i].append(abs((q.lufs ?? .nan) - (dir.lufs ?? .nan)))
            if i == 0 && q.truePeakDB < dir.truePeakDB - 1e-9 { tpUnder += 1; tpWorst = max(tpWorst, dir.truePeakDB - q.truePeakDB); tpSampleUnder = tpSampleUnder || q.samplePeakDB < dir.samplePeakDB - 1e-9 }
        }
    }
    print("| grain | median | p95 | max | share > 0.1 LU |")
    print("|---|---|---|---|---|")
    for (i, g) in grains.enumerated() {
        let e = errs[i].sorted()
        let med = e[e.count / 2], p95 = e[Int(Double(e.count - 1) * 0.95)], mx = e.last!
        let share = Double(e.filter { $0 > 0.1 }.count) / Double(e.count) * 100
        print(String(format: "| %g ms | %.3f | %.3f | %.3f | %.1f %% |", 1000.0 / Double(g), med, p95, mx, share))
    }
    print("windows where the 100 ms cache's true peak read under DIRECT's: \(tpUnder) of \(count), by at most \(fmt(tpWorst, 4)) dB; a sample peak under: \(tpSampleUnder)")

case "mirror":  // mirror <fwd.f32> <rate> <ch> <bps> <windowsfile>: windows in the REVERSED stream
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: Int(arg(4))!)
    let bps = Int(arg(5))!
    let coeffs = KWeight.coefficients(rate: pcm.rate)
    let (cache, _) = buildCache(pcm, blocksPerSecond: bps, coefficients: coeffs)
    // The reversed stream, sample-exact: rev[i] = fwd[N-1-i].
    var rev = pcm
    let N = pcm.frames, ch = pcm.channels
    for f in 0..<N { for c in 0..<ch { rev.samples[f * ch + c] = pcm.samples[(N - 1 - f) * ch + c] } }
    print("# rev window | cacheMirrored(nearest) | directOnReversed | directOnForwardWindow | cacheTP directRevTP")
    for (a, b) in readWindows(arg(6)) {
        let fa = Int((a * pcm.rate).rounded()), fb = min(N, Int((b * pcm.rate).rounded()))
        let m = query(cache, fa: N - fb, fb: N - fa, snap: .nearest, alignEnd: true,
                      exactCount: CommandLine.arguments.contains("--exact-count"))
        let d = direct(rev, fa: fa, fb: fb, coefficients: coeffs)
        let fw = direct(pcm, fa: N - fb, fb: N - fa, coefficients: coeffs)
        print(String(format: "%.6f %.6f | %@ | %@ | %@ | %@ %@", a, b, fmt(m.lufs, 4), fmt(d.lufs, 4),
                     fmt(fw.lufs, 4), fmt(m.truePeakDB, 4), fmt(d.truePeakDB, 4)))
    }

case "stereo":  // stereo <in.f32> <rate> <bps> <windowsfile>: matrices from the cache's covariance
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: 2)
    let bps = Int(arg(4))!
    let coeffs = KWeight.coefficients(rate: pcm.rate)
    let (cache, _) = buildCache(pcm, blocksPerSecond: bps, coefficients: coeffs)
    let mats: [(String, Matrix)] = [
        ("identity", (1, 0, 0, 1)), ("monoFold (L+R)/2 both", (0.5, 0.5, 0.5, 0.5)),
        ("left only (both)", (1, 0, 1, 0)), ("swap", (0, 1, 1, 0)),
        ("pan 0.5 right (balance gL=0.5)", (0.5, 0, 0, 1)),
    ]
    for (a, b) in readWindows(arg(5)) {
        let fa = Int((a * pcm.rate).rounded()), fb = min(pcm.frames, Int((b * pcm.rate).rounded()))
        for (name, m) in mats {
            let q = query(cache, fa: fa, fb: fb, snap: .nearest, matrix: m)
            let d = direct(pcm, fa: fa, fb: fb, coefficients: coeffs, matrix: m)
            print(String(format: "%.3f %.3f %-32@ cache %@ direct %@ diff %@", a, b, name as NSString,
                         fmt(q.lufs, 4), fmt(d.lufs, 4), fmt((q.lufs ?? 0) - (d.lufs ?? 0), 4)))
        }
    }

case "speech":  // speech <in.f32> <rate> <ch> <thresholdDB>
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: Int(arg(4))!)
    let thr = Double(arg(5))!
    let (cache, _) = buildCache(pcm, blocksPerSecond: 10, coefficients: KWeight.coefficients(rate: pcm.rate))
    // Speech spans by energy: a 100 ms block whose K-weighted loudness is above
    // thr, closed over gaps < 300 ms and opened by 100 ms at each side.
    let n = cache.blockCount
    var loud = (0..<n).map { b -> Bool in
        let e = (0..<cache.channels).reduce(0.0) { $0 + Double(cache.energy[$1][b]) } / Double(cache.framesIn(b))
        return loudness(e) > thr
    }
    // close gaps shorter than 3 blocks
    var b = 0
    while b < n {
        if !loud[b] { var e = b; while e < n && !loud[e] { e += 1 }
            if b > 0 && e < n && e - b < 3 { for k in b..<e { loud[k] = true } }
            b = e } else { b += 1 }
    }
    var spans = loud
    for k in 0..<n where loud[k] { if k > 0 { spans[k - 1] = true }; if k + 1 < n { spans[k + 1] = true } }
    let speechBlocks = spans.filter { $0 }.count
    // Integrated over speech: 400 ms gating blocks lying wholly in speech spans, gated as BS.1770.
    var gating: [Double] = [], speechOnlyUngated: [Double] = []
    for j in 0...(n - 4) {
        var s = 0.0, f = 0
        for k in j..<(j + 4) { for c in 0..<cache.channels { s += Double(cache.energy[c][k]) }; f += cache.framesIn(k) }
        gating.append(s / Double(f))
        if (j..<(j + 4)).allSatisfy({ spans[$0] }) { speechOnlyUngated.append(s / Double(f)) }
    }
    let gated = gatedIntegrated(gating)
    let speechGated = gatedIntegrated(speechOnlyUngated)
    let speechMean = speechOnlyUngated.isEmpty ? nil : loudness(speechOnlyUngated.reduce(0, +) / Double(speechOnlyUngated.count))
    print(String(format: "threshold %.0f LUFS: speech %.1f%% of blocks; gated integrated %@; speech-only gated %@; speech-only ungated mean %@",
                 thr, 100 * Double(speechBlocks) / Double(n), fmt(gated, 3), fmt(speechGated, 3), fmt(speechMean, 3)))

case "bench":  // bench <in> : timing on a long file
    let url = URL(fileURLWithPath: arg(2))
    print("load before: \(load())")
    var decodeBest = Double.infinity, decodeCPU = 0.0
    var pcm: PCM! = nil
    for _ in 0..<3 {
        let t0 = secondsNow(), c0 = cpuSeconds()
        pcm = decode(url, rate: args.count > 3 ? Double(arg(3)) : nil)
        let t1 = secondsNow(), c1 = cpuSeconds()
        if t1 - t0 < decodeBest { decodeBest = t1 - t0; decodeCPU = c1 - c0 }
    }
    let seconds = Double(pcm.frames) / pcm.rate
    print(String(format: "file %.1f s, rate %.0f, ch %d", seconds, pcm.rate, pcm.channels))
    print(String(format: "decode (AVAssetReader float, own rate): wall %.3f s cpu %.3f s  (%.0fx real time)", decodeBest, decodeCPU, seconds / decodeBest))
    // The peaks pass's own arithmetic: max magnitude per 10 ms bucket.
    var peaksBest = Double.infinity
    for _ in 0..<3 {
        let t0 = secondsNow()
        let per = Int(pcm.rate / 100) * pcm.channels
        var buckets = [Float](repeating: 0, count: pcm.samples.count / per + 1)
        pcm.samples.withUnsafeBufferPointer { p in
            var i = 0, b = 0
            while i < p.count { var m: Float = 0; vDSP_maxmgv(p.baseAddress! + i, 1, &m, vDSP_Length(min(per, p.count - i))); buckets[b] = m; b += 1; i += per }
        }
        peaksBest = min(peaksBest, secondsNow() - t0)
        _ = buckets
    }
    print(String(format: "peaks buckets (max per 10 ms) over memory: %.3f s", peaksBest))
    let coeffs = KWeight.coefficients(rate: pcm.rate)
    for bps in [10, 40, 100] {
        for (label, floatPeak, skip) in [("TP double", false, false), ("TP float", true, false), ("no TP", false, true)] {
            var best = BuildTimes(weight: 0, peak: 0, total: .infinity)
            var cpu = 0.0
            var cache: LoudnessCache! = nil
            for _ in 0..<3 {
                let c0 = cpuSeconds()
                let (c, t) = buildCache(pcm, blocksPerSecond: bps, coefficients: coeffs, floatPeak: floatPeak, skipPeak: skip)
                let c1 = cpuSeconds()
                if t.total < best.total { best = t; cpu = c1 - c0 }
                cache = c
            }
            print(String(format: "build %3d ms blocks, %-9@: total %.3f s (K-weight %.3f, TP %.3f) cpu %.3f s", 1000 / bps, label as NSString, best.total, best.weight, best.peak, cpu))
            if !skip && !floatPeak {
                let dir = (arg(2) as NSString).deletingLastPathComponent
                for layout in ["sum", "full", "brief"] {
                    let bytes = writeCache(cache, to: "\(dir)/../out/bench-\(bps)-\(layout).bin", layout: layout)
                    print(String(format: "   layout %-5@: %d bytes = %.1f KB per hour", layout as NSString, bytes, Double(bytes) / seconds * 3600 / 1024))
                }
            }
        }
    }
    // Streaming, as the cache lane would run it: decode and build in one loop.
    print("load after: \(load())")

case "tpfloat":  // tpfloat <in.f32> <rate> <ch>: Double vs Float true peak per block
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: Int(arg(4))!)
    let coeffs = KWeight.coefficients(rate: pcm.rate)
    let (d, _) = buildCache(pcm, blocksPerSecond: 10, coefficients: coeffs)
    let (f, _) = buildCache(pcm, blocksPerSecond: 10, coefficients: coeffs, floatPeak: true)
    var worst = 0.0
    for c in 0..<pcm.channels { for b in 0..<d.blockCount where d.truePeak[c][b] > 1e-6 {
        worst = max(worst, abs(db(Double(d.truePeak[c][b])) - db(Double(f.truePeak[c][b]))))
    } }
    print(String(format: "largest |TP double - TP float| over blocks: %.6f dB", worst))

case "mix":  // mix <mono file>: what the export's stereo mix does to a mono track
    let url = URL(fileURLWithPath: arg(2))
    let mono = decode(url)
    let st = decode(url, rate: 48000, mixOutputChannels: 2)
    let n = min(mono.frames, st.frames)
    var maxDiffL: Float = 0, maxDiffR: Float = 0, maxLR: Float = 0
    var eM = 0.0, eL = 0.0, eR = 0.0
    for f in 0..<n {
        let m = mono.samples[f], l = st.samples[2 * f], r = st.samples[2 * f + 1]
        maxDiffL = max(maxDiffL, abs(l - m)); maxDiffR = max(maxDiffR, abs(r - m)); maxLR = max(maxLR, abs(l - r))
        eM += Double(m * m); eL += Double(l * l); eR += Double(r * r)
    }
    print("mono frames \(mono.frames), mix frames \(st.frames) (2 ch)")
    print(String(format: "max |L-mono| %.3g, max |R-mono| %.3g, max |L-R| %.3g; energy L/mono %.6f dB, R/mono %.6f dB",
                 maxDiffL, maxDiffR, maxLR, 10 * log10(eL / eM), 10 * log10(eR / eM)))
    let meterMono = direct(mono, fa: 0, fb: mono.frames, coefficients: KWeight.table48)
    let meterSt = direct(st, fa: 0, fb: st.frames, coefficients: KWeight.table48)
    let (cache, _) = buildCache(mono, blocksPerSecond: 10, coefficients: KWeight.table48)
    let dual = query(cache, fa: 0, fb: mono.frames, dualMono: true)
    print("mono measured as mono: \(fmt(meterMono.lufs, 4)) LUFS; the stereo mix measured: \(fmt(meterSt.lufs, 4)) LUFS; cache read dual-mono: \(fmt(dual.lufs, 4)) LUFS")

case "determinism":  // determinism <in> <rate>: reader conversion, three runs
    let url = URL(fileURLWithPath: arg(2))
    for _ in 0..<3 {
        let p = decode(url, rate: Double(arg(3))!)
        let h = p.samples.withUnsafeBufferPointer { SHA256.hash(data: Data(buffer: $0)) }
        let (cache, _) = buildCache(p, blocksPerSecond: 10, coefficients: KWeight.coefficients(rate: p.rate))
        let q = query(cache, fa: 0, fb: p.frames)
        print("frames \(p.frames) sha \(h.description.suffix(16)) I \(fmt(q.lufs, 6)) TP \(fmt(q.truePeakDB, 6))")
    }

default:
    print("unknown command")
}
