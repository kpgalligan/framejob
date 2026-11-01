import Accelerate
import AVFoundation
import Foundation

// Spike S4: the loudness cache's arithmetic. K-weighting and the true-peak
// FIR are Loudness.swift's (copied, 9e47f56); the coefficients at a rate
// other than 48 kHz are libebur128's derivation from the analog prototype.

struct Biquad { var b0, b1, b2, a1, a2: Double }

enum KWeight {
    /// Loudness.swift's Tables 1 and 2, verbatim (48 kHz only).
    static let table48 = (
        Biquad(b0: 1.535_124_859_586_97, b1: -2.691_696_189_406_38, b2: 1.198_392_810_852_85,
               a1: -1.690_659_293_182_41, a2: 0.732_480_774_215_85),
        Biquad(b0: 1.0, b1: -2.0, b2: 1.0,
               a1: -1.990_047_454_833_98, a2: 0.990_072_250_366_21))

    /// libebur128's `ebur128_init_filter`: the shelf and the RLB high-pass
    /// from their analog parameters through the bilinear transform.
    static func derived(rate: Double) -> (Biquad, Biquad) {
        var f0 = 1681.974450955533
        let G = 3.999843853973347
        var Q = 0.7071752369554196
        var K = tan(Double.pi * f0 / rate)
        let Vh = pow(10.0, G / 20.0)
        let Vb = pow(Vh, 0.4996667741545416)
        let a0 = 1.0 + K / Q + K * K
        let s1 = Biquad(
            b0: (Vh + Vb * K / Q + K * K) / a0, b1: 2.0 * (K * K - Vh) / a0,
            b2: (Vh - Vb * K / Q + K * K) / a0,
            a1: 2.0 * (K * K - 1.0) / a0, a2: (1.0 - K / Q + K * K) / a0)
        f0 = 38.13547087602444
        Q = 0.5003270373238773
        K = tan(Double.pi * f0 / rate)
        let d = 1.0 + K / Q + K * K
        let s2 = Biquad(b0: 1, b1: -2, b2: 1, a1: 2.0 * (K * K - 1.0) / d, a2: (1.0 - K / Q + K * K) / d)
        return (s1, s2)
    }

    static func coefficients(rate: Double, useTableAt48: Bool = true) -> (Biquad, Biquad) {
        if rate == 48000 && useTableAt48 { return table48 }
        return derived(rate: rate)
    }
}

/// Annex 2's 4-phase 12-tap FIR, as Loudness.swift transcribes it.
let peakFilter: [[Double]] = [
    [0.001_708_984_375_0, 0.010_986_328_125_0, -0.019_653_320_312_5, 0.033_203_125_000_0,
     -0.059_448_242_187_5, 0.137_329_101_562_5, 0.972_167_968_750_0, -0.102_294_921_875_0,
     0.047_607_421_875_0, -0.026_611_328_125_0, 0.014_892_578_125_0, -0.008_300_781_250_0],
    [-0.029_174_804_687_5, 0.029_296_875_000_0, -0.051_757_812_500_0, 0.089_111_328_125_0,
     -0.166_503_906_250_0, 0.465_087_890_625_0, 0.779_785_156_250_0, -0.200_317_382_812_5,
     0.101_562_500_000_0, -0.058_227_539_062_5, 0.033_081_054_687_5, -0.018_920_898_437_5],
    [-0.018_920_898_437_5, 0.033_081_054_687_5, -0.058_227_539_062_5, 0.101_562_500_000_0,
     -0.200_317_382_812_5, 0.779_785_156_250_0, 0.465_087_890_625_0, -0.166_503_906_250_0,
     0.089_111_328_125_0, -0.051_757_812_500_0, 0.029_296_875_000_0, -0.029_174_804_687_5],
    [-0.008_300_781_250_0, 0.014_892_578_125_0, -0.026_611_328_125_0, 0.047_607_421_875_0,
     -0.102_294_921_875_0, 0.972_167_968_750_0, 0.137_329_101_562_5, -0.059_448_242_187_5,
     0.033_203_125_000_0, -0.019_653_320_312_5, 0.010_986_328_125_0, 0.001_708_984_375_0],
]
let taps = 12
let history = taps - 1
let reversedTaps: [Double] = peakFilter.flatMap { $0.reversed() }
let reversedTapsF: [Float] = reversedTaps.map(Float.init)

// MARK: - Decoding

struct PCM {
    var samples: [Float]  // interleaved
    var rate: Double
    var channels: Int
    var frames: Int { samples.count / channels }
}

/// AVAssetReaderTrackOutput, 32-bit float interleaved, at the file's own rate
/// unless `rate` asks for another (the reader's own conversion). Buffers
/// appended in order; a gap or overlap in PTS is reported, not filled.
func decode(_ url: URL, rate: Double? = nil, mixOutputChannels: Int? = nil) -> PCM {
    let asset = AVURLAsset(url: url)
    let tracks = asset.tracks(withMediaType: .audio)
    guard let track = tracks.first, let reader = try? AVAssetReader(asset: asset) else {
        fatalError("no audio track in \(url.path)")
    }
    var settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    if let rate { settings[AVSampleRateKey] = rate }
    let output: AVAssetReaderOutput
    if let channels = mixOutputChannels {
        settings[AVSampleRateKey] = rate ?? 48000
        settings[AVNumberOfChannelsKey] = channels
        let mix = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: settings)
        mix.alwaysCopiesSampleData = false
        output = mix
    } else {
        let t = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        t.alwaysCopiesSampleData = false
        output = t
    }
    reader.add(output)
    guard reader.startReading() else { fatalError("startReading failed") }
    var samples: [Float] = []
    var outRate = 0.0
    var channels = 0
    var expectedNext: Double? = nil
    while let sb = output.copyNextSampleBuffer() {
        let frames = CMSampleBufferGetNumSamples(sb)
        guard frames > 0, let fmt = CMSampleBufferGetFormatDescription(sb),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee,
            let block = CMSampleBufferGetDataBuffer(sb)
        else { continue }
        outRate = asbd.mSampleRate
        channels = Int(asbd.mChannelsPerFrame)
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
        if expectedNext == nil && abs(pts) > 1e-9 {
            FileHandle.standardError.write("note: first PTS \(pts)\n".data(using: .utf8)!)
        }
        if let e = expectedNext, abs(pts - e) > 0.5 / outRate {
            FileHandle.standardError.write("note: PTS \(pts) expected \(e)\n".data(using: .utf8)!)
        }
        expectedNext = pts + Double(frames) / outRate
        let count = frames * channels
        let base = samples.count
        samples.append(contentsOf: repeatElement(0, count: count))
        samples.withUnsafeMutableBytes { raw in
            _ = CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: count * 4,
                destination: raw.baseAddress! + base * 4)
        }
    }
    guard reader.status == .completed else { fatalError("reader status \(reader.status.rawValue)") }
    return PCM(samples: samples, rate: outRate, channels: channels)
}

func readRaw(_ path: String, rate: Double, channels: Int) -> PCM {
    let data = try! Data(contentsOf: URL(fileURLWithPath: path))
    let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    return PCM(samples: samples, rate: rate, channels: channels)
}

func writeRaw(_ pcm: PCM, to path: String) {
    let data = pcm.samples.withUnsafeBufferPointer { Data(buffer: $0) }
    try! data.write(to: URL(fileURLWithPath: path))
}

// MARK: - Per-channel streaming state (K-weighting and the interpolator)

/// One channel's filter and interpolator state, run over consecutive chunks.
final class ChannelState {
    let s1: Biquad, s2: Biquad
    var z = [Double](repeating: 0, count: 8)
    let buffer: UnsafeMutablePointer<Double>
    let phaseOut: UnsafeMutablePointer<Double>
    let bufferF: UnsafeMutablePointer<Float>
    let phaseOutF: UnsafeMutablePointer<Float>
    let peakHistory: UnsafeMutablePointer<Double>
    let coeffs: UnsafeMutablePointer<Double>
    let coeffsF: UnsafeMutablePointer<Float>
    init(coefficients: (Biquad, Biquad), maxChunk: Int) {
        s1 = coefficients.0
        s2 = coefficients.1
        buffer = .allocate(capacity: maxChunk + history); buffer.initialize(repeating: 0, count: maxChunk + history)
        phaseOut = .allocate(capacity: maxChunk); phaseOut.initialize(repeating: 0, count: maxChunk)
        bufferF = .allocate(capacity: maxChunk + history); bufferF.initialize(repeating: 0, count: maxChunk + history)
        phaseOutF = .allocate(capacity: maxChunk); phaseOutF.initialize(repeating: 0, count: maxChunk)
        peakHistory = .allocate(capacity: history); peakHistory.initialize(repeating: 0, count: history)
        coeffs = .allocate(capacity: 48); for i in 0..<48 { (coeffs + i).initialize(to: reversedTaps[i]) }
        coeffsF = .allocate(capacity: 48); for i in 0..<48 { (coeffsF + i).initialize(to: reversedTapsF[i]) }
    }
    deinit {
        buffer.deallocate(); phaseOut.deallocate(); bufferF.deallocate(); phaseOutF.deallocate()
        peakHistory.deallocate(); coeffs.deallocate(); coeffsF.deallocate()
    }

    /// Loads `frames` samples of channel `c` (stride `channels`) behind the
    /// history. After this, `buffer[history ..< history+frames]` is the raw run.
    func load(_ p: UnsafePointer<Float>, frames: Int, channel c: Int, channels: Int) {
        buffer.update(from: peakHistory, count: history)
        vDSP_vspdp(p + c, vDSP_Stride(channels), buffer + history, 1, vDSP_Length(frames))
    }

    /// The 4x interpolated maximum over the loaded run (Double, as Loudness.swift).
    func truePeak(frames: Int) -> Double {
        var best = 0.0
        for phase in 0..<4 {
            vDSP_convD(buffer, 1, coeffs + phase * taps, 1, phaseOut, 1,
                       vDSP_Length(frames), vDSP_Length(taps))
            var m = 0.0
            vDSP_maxmgvD(phaseOut, 1, &m, vDSP_Length(frames))
            best = max(best, m)
        }
        return best
    }

    /// The same in single precision (timing alternative).
    func truePeakFloat(frames: Int) -> Double {
        var best: Float = 0
        vDSP_vdpsp(buffer, 1, bufferF, 1, vDSP_Length(frames + history))
        for phase in 0..<4 {
            vDSP_conv(bufferF, 1, coeffsF + phase * taps, 1, phaseOutF, 1,
                      vDSP_Length(frames), vDSP_Length(taps))
            var m: Float = 0
            vDSP_maxmgv(phaseOutF, 1, &m, vDSP_Length(frames))
            best = max(best, m)
        }
        return Double(best)
    }

    /// Keeps the last `history` raw samples, then K-weights the run in place.
    func advanceAndWeight(frames: Int) {
        peakHistory.update(from: buffer + frames, count: history)
        let s = buffer + history
        for (k, sec) in [s1, s2].enumerated() {
            var x1 = z[k * 4], x2 = z[k * 4 + 1], y1 = z[k * 4 + 2], y2 = z[k * 4 + 3]
            for n in 0..<frames {
                let x = s[n]
                let y = sec.b0 * x + sec.b1 * x1 + sec.b2 * x2 - sec.a1 * y1 - sec.a2 * y2
                x2 = x1; x1 = x; y2 = y1; y1 = y
                s[n] = y
            }
            z[k * 4] = x1; z[k * 4 + 1] = x2; z[k * 4 + 2] = y1; z[k * 4 + 3] = y2
        }
    }

    var weighted: UnsafeMutablePointer<Double> { buffer + history }
}

// MARK: - The cache

/// One media's loudness blocks. `energy[c][b]` is Σ y² of channel c's
/// K-weighted samples in block b (a SUM, not a mean); `cross[b]` is Σ yL·yR
/// for a stereo file; `truePeak[c][b]` and `samplePeak[c][b]` linear.
struct LoudnessCache {
    var rate: Double
    var channels: Int
    var blocksPerSecond: Int
    var frames: Int
    var energy: [[Float]]
    var cross: [Float]
    var truePeak: [[Float]]
    var samplePeak: [[Float]]

    var blockCount: Int { energy[0].count }

    /// First frame of block b under the floor rule ⌊f·bps/rate⌋ = b.
    func firstFrame(_ b: Int) -> Int {
        Int((Double(b) * rate / Double(blocksPerSecond)).rounded(.up))
    }
    func framesIn(_ b: Int) -> Int { min(firstFrame(b + 1), frames) - firstFrame(b) }
}

struct BuildTimes { var weight = 0.0, peak = 0.0, total = 0.0 }

func buildCache(_ pcm: PCM, blocksPerSecond: Int, coefficients: (Biquad, Biquad),
                floatPeak: Bool = false, skipPeak: Bool = false) -> (LoudnessCache, BuildTimes) {
    let ch = pcm.channels
    let rate = pcm.rate
    var cache = LoudnessCache(
        rate: rate, channels: ch, blocksPerSecond: blocksPerSecond, frames: pcm.frames,
        energy: Array(repeating: [], count: ch), cross: [],
        truePeak: Array(repeating: [], count: ch), samplePeak: Array(repeating: [], count: ch))
    let maxChunk = Int((rate / Double(blocksPerSecond)).rounded(.up)) + 1
    let states = (0..<ch).map { _ in ChannelState(coefficients: coefficients, maxChunk: maxChunk) }
    var times = BuildTimes()
    let t0 = DispatchTime.now().uptimeNanoseconds
    var b = 0
    pcm.samples.withUnsafeBufferPointer { all in
        while true {
            let start = cache.firstFrame(b)
            if start >= pcm.frames { break }
            let end = min(cache.firstFrame(b + 1), pcm.frames)
            let n = end - start
            let p = all.baseAddress! + start * ch
            var crossSum = 0.0
            for c in 0..<ch {
                let st = states[c]
                st.load(p, frames: n, channel: c, channels: ch)
                var sp: Float = 0
                vDSP_maxmgv(p + c, vDSP_Stride(ch), &sp, vDSP_Length(n))
                let tp0 = DispatchTime.now().uptimeNanoseconds
                let tp = skipPeak ? 0 : (floatPeak ? st.truePeakFloat(frames: n) : st.truePeak(frames: n))
                let tp1 = DispatchTime.now().uptimeNanoseconds
                st.advanceAndWeight(frames: n)
                let tp2 = DispatchTime.now().uptimeNanoseconds
                times.peak += Double(tp1 - tp0) / 1e9
                times.weight += Double(tp2 - tp1) / 1e9
                var e = 0.0
                let w = st.weighted
                vDSP_svesqD(w, 1, &e, vDSP_Length(n))
                cache.energy[c].append(Float(e))
                cache.samplePeak[c].append(sp)
                cache.truePeak[c].append(Float(max(tp, Double(sp))))
            }
            if ch == 2 {
                let l = states[0].weighted, r = states[1].weighted
                vDSP_dotprD(l, 1, r, 1, &crossSum, vDSP_Length(n))
                cache.cross.append(Float(crossSum))
            }
            b += 1
        }
    }
    times.total = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
    return (cache, times)
}

// MARK: - Reading a window from the cache

let absoluteGate = -70.0
let relativeGate = -10.0
let lufsOffset = -0.691

func loudness(_ ms: Double) -> Double { ms > 0 ? lufsOffset + 10 * log10(ms) : -.infinity }
func db(_ x: Double) -> Double { x > 0 ? 20 * log10(x) : -.infinity }

/// BS.1770's two gates over a list of gating-block mean squares (Σ over
/// channels of Gᵢ·zᵢ), optionally weighted (a ramp's output time).
func gatedIntegrated(_ blocks: [Double], weights: [Double]? = nil) -> Double? {
    let w = weights ?? Array(repeating: 1, count: blocks.count)
    var sum = 0.0, wsum = 0.0
    for (i, z) in blocks.enumerated() where z > 0 && loudness(z) > absoluteGate {
        sum += z * w[i]; wsum += w[i]
    }
    guard wsum > 0 else { return nil }
    let threshold = loudness(sum / wsum) + relativeGate
    sum = 0; wsum = 0
    for (i, z) in blocks.enumerated() where z > 0 && loudness(z) > threshold {
        sum += z * w[i]; wsum += w[i]
    }
    guard wsum > 0 else { return nil }
    return loudness(sum / wsum)
}

enum Snap { case nearest, outward, inward }

/// A 2×2 static channel matrix applied before the meter (stereo only):
/// out0 = m00·L + m01·R, out1 = m10·L + m11·R. nil is identity.
typealias Matrix = (Double, Double, Double, Double)

struct WindowAnswer { var lufs: Double?; var truePeakDB: Double; var samplePeakDB: Double; var first: Int; var end: Int }

func blockIndex(frame: Int, cache: LoudnessCache, snap: Snap, isEnd: Bool) -> Int {
    let x = Double(frame) * Double(cache.blocksPerSecond) / cache.rate
    switch snap {
    case .nearest: return Int(x.rounded())
    case .outward: return Int(isEnd ? x.rounded(.up) : x.rounded(.down))
    case .inward: return Int(isEnd ? x.rounded(.down) : x.rounded(.up))
    }
}

/// Integrated loudness and true peak over source frames [fa, fb) from the
/// cache. Loudness on `snap`'s blocks; peaks always outward (never under-read).
/// `dualMono` adds a mono file's channel a second time (the export's
/// stereo mix duplicates it). `reversed` mirrors nothing here: the caller
/// passes the mirrored frames.
func query(_ cache: LoudnessCache, fa: Int, fb: Int, snap: Snap = .nearest,
           matrix: Matrix? = nil, dualMono: Bool = false, dense: Bool = false,
           alignEnd: Bool = false, speed: Double = 1, exactCount: Bool = false) -> WindowAnswer {
    let bps = cache.blocksPerSecond
    precondition(bps % 10 == 0, "grain must divide 100 ms")
    // At a speed, a played 400 ms block reads 400*speed ms of source (time-scaled gating).
    let hop = dense ? 1 : max(1, Int((Double(bps / 10) * speed).rounded()))
    let per = max(1, Int((Double(bps / 10) * 4 * speed).rounded()))
    let s = max(0, blockIndex(frame: fa, cache: cache, snap: snap, isEnd: false))
    let e = min(cache.blockCount, blockIndex(frame: fb, cache: cache, snap: snap, isEnd: true))
    var blocks: [Double] = []
    // Gating blocks start at the PLAYED start: the window's first block, or
    // for a reversed clip (alignEnd) its last, stepping backwards.
    var starts: [Int] = []
    if exactCount {
        // As many gating blocks as the EXACT window holds (an export of it
        // keeps a block only if it ends inside the window), laid from the
        // snapped played start: only the grid's offset is approximated.
        let length = Double(fb - fa) / cache.rate / speed
        let n = length >= 0.4 ? Int(((length - 0.4) / 0.1 + 1e-9).rounded(.down)) + 1 : 0
        for k in 0..<n {
            let j = alignEnd ? e - per - k * hop : s + k * hop
            if j >= 0 && j + per <= cache.blockCount { starts.append(j) }
        }
    } else if alignEnd {
        var j = e - per
        while j >= s { starts.append(j); j -= hop }
    } else {
        var j = s
        while j + per <= e { starts.append(j); j += hop }
    }
    for j in starts {
        var z = 0.0
        var n = 0
        if cache.channels == 2, let m = matrix {
            var eL = 0.0, eR = 0.0, eX = 0.0
            for k in j..<(j + per) {
                eL += Double(cache.energy[0][k]); eR += Double(cache.energy[1][k]); eX += Double(cache.cross[k])
                n += cache.framesIn(k)
            }
            let o0 = m.0 * m.0 * eL + m.1 * m.1 * eR + 2 * m.0 * m.1 * eX
            let o1 = m.2 * m.2 * eL + m.3 * m.3 * eR + 2 * m.2 * m.3 * eX
            z = (o0 + o1) / Double(n)
        } else {
            var sum = 0.0
            for k in j..<(j + per) {
                for c in 0..<cache.channels { sum += Double(cache.energy[c][k]) }
                n += cache.framesIn(k)
            }
            z = sum * (dualMono && cache.channels == 1 ? 2 : 1) / Double(n)
        }
        blocks.append(z)
    }
    let ps = max(0, blockIndex(frame: fa, cache: cache, snap: .outward, isEnd: false))
    let pe = min(cache.blockCount, blockIndex(frame: fb, cache: cache, snap: .outward, isEnd: true))
    var tp: Float = 0, sp: Float = 0
    if ps < pe {
        for c in 0..<cache.channels {
            for k in ps..<pe { tp = max(tp, cache.truePeak[c][k]); sp = max(sp, cache.samplePeak[c][k]) }
        }
    }
    return WindowAnswer(lufs: gatedIntegrated(blocks), truePeakDB: db(Double(tp)),
                        samplePeakDB: db(Double(sp)), first: s, end: e)
}

// MARK: - DIRECT: a meter fed exactly the window (an export of it)

/// LoudnessMeter generalised over the coefficients: fresh state at the
/// window's first frame, blocks aligned there (after `leadSilence` zero
/// frames, which puts the window at a phase of the block grid), trailing
/// partial block discarded.
func direct(_ pcm: PCM, fa: Int, fb: Int, coefficients: (Biquad, Biquad),
            leadSilence: Int = 0, matrix: Matrix? = nil, dualMono: Bool = false) -> WindowAnswer {
    let ch = pcm.channels
    var frames = [Float](repeating: 0, count: leadSilence * ch)
    frames.append(contentsOf: pcm.samples[(fa * ch)..<(fb * ch)])
    var src = PCM(samples: frames, rate: pcm.rate, channels: ch)
    if ch == 2, let m = matrix {
        for f in 0..<src.frames {
            let l = Double(src.samples[2 * f]), r = Double(src.samples[2 * f + 1])
            src.samples[2 * f] = Float(m.0 * l + m.1 * r)
            src.samples[2 * f + 1] = Float(m.2 * l + m.3 * r)
        }
    }
    let hopFrames = Int((pcm.rate / 10).rounded())
    let blockFrames = hopFrames * 4
    let states = (0..<ch).map { _ in ChannelState(coefficients: coefficients, maxChunk: hopFrames) }
    var subSums: [Double] = []
    var tp = 0.0
    var sp: Float = 0
    src.samples.withUnsafeBufferPointer { all in
        var start = 0
        while start < src.frames {
            let n = min(hopFrames, src.frames - start)
            let p = all.baseAddress! + start * ch
            var sum = 0.0
            for c in 0..<ch {
                let st = states[c]
                st.load(p, frames: n, channel: c, channels: ch)
                var m: Float = 0
                vDSP_maxmgv(p + c, vDSP_Stride(ch), &m, vDSP_Length(n))
                sp = max(sp, m)
                tp = max(tp, st.truePeak(frames: n))
                st.advanceAndWeight(frames: n)
                var e = 0.0
                vDSP_svesqD(st.weighted, 1, &e, vDSP_Length(n))
                sum += e
            }
            if n == hopFrames { subSums.append(sum * (dualMono && ch == 1 ? 2 : 1)) }
            start += n
        }
    }
    var blocks: [Double] = []
    if subSums.count >= 4 {
        for j in 0...(subSums.count - 4) {
            blocks.append((subSums[j] + subSums[j + 1] + subSums[j + 2] + subSums[j + 3]) / Double(blockFrames))
        }
    }
    return WindowAnswer(lufs: gatedIntegrated(blocks), truePeakDB: db(max(tp, Double(sp))),
                        samplePeakDB: db(Double(sp)), first: fa, end: fb)
}

// MARK: - The binary file

/// Writes the cache as the proposed `.bin`: a 32-byte header then the
/// block columns (see record.md). Answers the byte count.
@discardableResult
func writeCache(_ c: LoudnessCache, to path: String, layout: String) -> Int {
    var data = Data()
    func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
    func f32s(_ a: [Float]) { a.withUnsafeBufferPointer { data.append(Data(buffer: $0)) } }
    data.append("FJLC".data(using: .ascii)!)  // magic
    u32(1)                                       // file format version
    u32(UInt32(c.rate))
    u32(UInt32(c.channels))
    u32(UInt32(c.blocksPerSecond))
    u32(UInt32(c.blockCount))
    u32(UInt32(truncatingIfNeeded: c.frames))
    u32(UInt32(truncatingIfNeeded: c.frames >> 32))
    switch layout {
    case "sum":  // channel-summed energy + one true peak (folded with sample peak)
        var e = [Float](repeating: 0, count: c.blockCount)
        var t = [Float](repeating: 0, count: c.blockCount)
        for ch in 0..<c.channels {
            for b in 0..<c.blockCount { e[b] += c.energy[ch][b]; t[b] = max(t[b], c.truePeak[ch][b]) }
        }
        f32s(e); f32s(t)
    case "full":  // per-channel energy, cross term (stereo), per-channel true peak
        for ch in 0..<c.channels { f32s(c.energy[ch]) }
        if c.channels == 2 { f32s(c.cross) }
        for ch in 0..<c.channels { f32s(c.truePeak[ch]) }
    default:  // "brief": everything incl. sample peak per channel
        for ch in 0..<c.channels { f32s(c.energy[ch]) }
        if c.channels == 2 { f32s(c.cross) }
        for ch in 0..<c.channels { f32s(c.truePeak[ch]); f32s(c.samplePeak[ch]) }
    }
    try! data.write(to: URL(fileURLWithPath: path))
    return data.count
}

func fmt(_ x: Double?, _ d: Int = 3) -> String {
    guard let x else { return "nil" }
    return String(format: "%.\(d)f", x)
}
