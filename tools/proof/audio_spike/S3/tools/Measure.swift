import AVFoundation
import Accelerate
import Foundation

// Spike S3's measuring instruments: BS.1770-4 K-weighting and momentary / short-term
// loudness at 48 kHz, a 4x windowed-sinc true-peak estimator, and a lookahead true-peak
// limiter (offline, the shape AP2 would build). Written for this spike only.

let sampleRate = 48000.0

/// One biquad, direct form I, double precision.
struct Biquad {
    var b0, b1, b2, a1, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    init(_ b: [Double], _ a: [Double]) {
        b0 = b[0]; b1 = b[1]; b2 = b[2]; a1 = a[1]; a2 = a[2]
    }
    mutating func run(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

/// BS.1770-4's K-weighting at 48 kHz (the standard's own coefficients).
func kWeighted(_ x: [Float]) -> [Double] {
    var s1 = Biquad([1.53512485958697, -2.69169618940638, 1.19839281085285],
                    [1, -1.69065929318241, 0.73248077421585])
    var s2 = Biquad([1.0, -2.0, 1.0], [1, -1.99004745483398, 0.99007225036621])
    return x.map { s2.run(s1.run(Double($0))) }
}

/// Loudness over sliding windows: `window` seconds, every `hop` seconds, of a stereo pair
/// (channel weights 1, 1). Returns LUFS per hop (−inf floored at −200).
func loudnessSeries(_ l: [Float], _ r: [Float], window: Double, hop: Double) -> [Double] {
    let kl = kWeighted(l), kr = kWeighted(r)
    let w = Int(window * sampleRate), h = Int(hop * sampleRate)
    var csum = [Double](repeating: 0, count: kl.count + 1)
    for i in 0..<kl.count { csum[i + 1] = csum[i] + kl[i] * kl[i] + kr[i] * kr[i] }
    var out: [Double] = []
    var end = w
    while end <= kl.count {
        let ms = (csum[end] - csum[end - w]) / Double(w)
        out.append(ms > 0 ? -0.691 + 10 * log10(ms) : -200)
        end += h
    }
    return out
}

/// 4x oversampling interpolator: a Hann-windowed sinc, 16 taps a side per phase.
struct Oversampler {
    static let factor = 4
    static let half = 16
    let phases: [[Double]]
    init() {
        var p: [[Double]] = []
        for phase in 1..<Oversampler.factor {
            let frac = Double(phase) / Double(Oversampler.factor)
            var taps: [Double] = []
            for k in -Oversampler.half + 1...Oversampler.half {
                let t = Double(k) - frac  // sample n+k relative to the point n+frac
                let sinc = t == 0 ? 1 : sin(Double.pi * t) / (Double.pi * t)
                let wpos = (t + Double(Oversampler.half)) / Double(2 * Oversampler.half)
                let win = 0.5 - 0.5 * cos(2 * Double.pi * wpos)
                taps.append(sinc * win)
            }
            let s = taps.reduce(0, +)
            p.append(taps.map { $0 / s })
        }
        phases = p
    }
    /// The largest magnitude of the signal anywhere in [n, n+1): the sample and three
    /// interpolated points.
    func peaks(_ x: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: x.count)
        let n = x.count
        for i in 0..<n {
            var m = abs(Double(x[i]))
            for taps in phases {
                var acc = 0.0
                var j = 0
                for k in -Oversampler.half + 1...Oversampler.half {
                    let idx = i + k
                    if idx >= 0 && idx < n { acc += taps[j] * Double(x[idx]) }
                    j += 1
                }
                m = max(m, abs(acc))
            }
            out[i] = Float(m)
        }
        return out
    }
}
let oversampler = Oversampler()

func truePeakDB(_ channels: [[Float]]) -> Double {
    var m: Float = 0
    for c in channels { m = max(m, oversampler.peaks(c).max() ?? 0) }
    return 20 * log10(Double(max(m, 1e-12)))
}

/// A lookahead true-peak limiter, linked across channels, offline: the gain each instant
/// requires (ceiling over the 4x peak), a min-hold over ±A samples, a box average of the
/// same width (so the gain is at or under what each peak requires, reached over the
/// lookahead), and a one-pole release. Non-causal by A samples, which is its lookahead.
func limit(_ channels: [[Float]], ceilingDB: Double, lookahead: Double = 0.0015,
           release: Double = 0.050) -> [[Float]] {
    let n = channels[0].count
    let ceiling = Float(pow(10, ceilingDB / 20))
    var tp = [Float](repeating: 0, count: n)
    for c in channels {
        let p = oversampler.peaks(c)
        for i in 0..<n { tp[i] = max(tp[i], p[i]) }
    }
    // Aim 0.1 dB under, so the box average's ripple and the release cannot leave an over.
    let aim = ceiling * Float(pow(10, -0.1 / 20))
    let req = tp.map { $0 > aim ? aim / $0 : 1 }
    let a = max(1, Int(lookahead * sampleRate))
    var held = [Float](repeating: 1, count: n)
    // Sliding minimum over [i-a, i+a] (simple deque).
    var dq: [Int] = []
    var head = 0
    var next = 0
    for i in 0..<n {
        while next < n && next <= i + a {
            while dq.count > head && req[dq.last!] >= req[next] { dq.removeLast() }
            dq.append(next); next += 1
        }
        while dq[head] < i - a { head += 1 }
        held[i] = req[dq[head]]
    }
    // Box average of width 2a+1.
    var box = [Float](repeating: 1, count: n)
    let width = 2 * a + 1
    func heldAt(_ i: Int) -> Double { i >= 0 && i < n ? Double(held[i]) : 1 }
    // acc = Σ held[i-width+1 ... i], indices outside [0, n) counting as 1.
    var acc = Double(width)
    for i in 0..<(n + a) {
        acc += heldAt(i) - heldAt(i - width)
        let centre = i - a
        if centre >= 0 && centre < n { box[centre] = Float(acc / Double(width)) }
    }
    let rel = Float(1 - exp(-1 / (release * sampleRate)))
    var g: Float = 1
    var gains = [Float](repeating: 1, count: n)
    for i in 0..<n {
        let target = min(box[i], held[i])
        g = target < g ? target : g + (target - g) * rel
        gains[i] = min(g, req[i])
    }
    return channels.map { c in (0..<n).map { c[$0] * gains[$0] } }
}

/// The app's compressor (AudioDSP.swift, copied) over a stereo pair in one linked run,
/// in 4096-frame blocks as the tap would hand it.
func compress(_ channels: [[Float]], settings: AudioCompressorSettings) -> [[Float]] {
    let n = channels[0].count
    let stage = AudioCompressorStage(sampleRate: sampleRate, maxFrames: 4096)
    var l = channels[0], r = channels[1]
    l.withUnsafeMutableBufferPointer { lp in
        r.withUnsafeMutableBufferPointer { rp in
            var offset = 0
            while offset < n {
                let frames = min(4096, n - offset)
                var ptrs: [UnsafeMutablePointer<Float>?] = [lp.baseAddress! + offset, rp.baseAddress! + offset]
                ptrs.withUnsafeMutableBufferPointer { bp in
                    stage.process(bp, count: 2, frames: frames, settings: settings)
                }
                offset += frames
            }
        }
    }
    return [l, r]
}

func add(_ a: [[Float]], _ b: [[Float]]) -> [[Float]] {
    zip(a, b).map { zip($0, $1).map { $0 + $1 } }
}
func scale(_ a: [[Float]], _ g: [Float]) -> [[Float]] {
    a.map { c in (0..<c.count).map { c[$0] * g[$0] } }
}

/// Reads a file as 48 kHz float mono (first channel), through AVAudioFile.
func readMono(_ path: String) -> [Float] {
    let file = try! AVAudioFile(forReading: URL(fileURLWithPath: path))
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    let converter = AVAudioConverter(from: file.processingFormat, to: format)!
    let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try! file.read(into: inBuf)
    let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(file.length) * 48000 / file.processingFormat.sampleRate) + 4096)!
    var done = false
    var err: NSError?
    converter.convert(to: outBuf, error: &err) { _, status in
        if done { status.pointee = .endOfStream; return nil }
        done = true; status.pointee = .haveData; return inBuf
    }
    return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))
}
