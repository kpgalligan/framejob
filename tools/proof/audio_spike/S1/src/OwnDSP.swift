import Accelerate
import AudioToolbox
import Foundation

/// A stage the tap (or the offline bench) runs in place over planar float
/// buffers. `prepare` may allocate; `process` must not.
protocol Stage: AnyObject {
    var name: String { get }
    /// Returns nil on success, or a description of what failed.
    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String?
    func reset()
    /// In place. Returns an OSStatus-like code (0 ok) for hosts that can fail.
    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32
    /// Samples of pure delay this stage claims.
    var latency: Int { get }
}

// MARK: - RBJ biquads

struct BQ {
    var b0, b1, b2, a1, a2: Double

    /// |H(e^{jw})| at `f` Hz.
    func magnitude(_ f: Double, fs: Double) -> Double {
        let w = 2 * Double.pi * f / fs
        let (c1, s1, c2, s2) = (cos(w), sin(w), cos(2 * w), sin(2 * w))
        let nr = b0 + b1 * c1 + b2 * c2, ni = -(b1 * s1 + b2 * s2)
        let dr = 1 + a1 * c1 + a2 * c2, di = -(a1 * s1 + a2 * s2)
        return sqrt((nr * nr + ni * ni) / (dr * dr + di * di))
    }
}

enum EQKind: String { case highPass, peaking, lowShelf, highShelf, notch }

/// One EQ band as the stages and the hosts both describe it.
struct EQBand {
    var kind: EQKind
    var freq: Double
    var q: Double = 0.7071067811865476  // high-pass, peaking, notch
    var gainDB: Double = 0  // peaking, shelves
    var slope: Double = 1  // shelves (RBJ S)
    /// Bandwidth in octaves, the parameter AUNBandEQ takes, from Q by RBJ's
    /// digital relation 1/Q = 2 sinh(ln2/2 · BW · w0/sin w0).
    func octaves(fs: Double) -> Double {
        let w0 = 2 * Double.pi * freq / fs
        return asinh(1 / (2 * q)) * 2 / log(2) * sin(w0) / w0
    }
}

enum RBJ {
    static func design(_ b: EQBand, fs: Double) -> BQ {
        let w0 = 2 * Double.pi * b.freq / fs
        let cw = cos(w0), sw = sin(w0)
        let alpha = sw / (2 * b.q)
        let A = pow(10, b.gainDB / 40)
        var (b0, b1, b2, a0, a1, a2) = (0.0, 0.0, 0.0, 1.0, 0.0, 0.0)
        switch b.kind {
        case .highPass:
            b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .peaking:
            b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A
            a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A
        case .notch:
            b0 = 1; b1 = -2 * cw; b2 = 1
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .lowShelf, .highShelf:
            let al = sw / 2 * sqrt((A + 1 / A) * (1 / b.slope - 1) + 2)
            let sa = 2 * sqrt(A) * al
            if b.kind == .lowShelf {
                b0 = A * ((A + 1) - (A - 1) * cw + sa)
                b1 = 2 * A * ((A - 1) - (A + 1) * cw)
                b2 = A * ((A + 1) - (A - 1) * cw - sa)
                a0 = (A + 1) + (A - 1) * cw + sa
                a1 = -2 * ((A - 1) + (A + 1) * cw)
                a2 = (A + 1) + (A - 1) * cw - sa
            } else {
                b0 = A * ((A + 1) + (A - 1) * cw + sa)
                b1 = -2 * A * ((A - 1) + (A + 1) * cw)
                b2 = A * ((A + 1) + (A - 1) * cw - sa)
                a0 = (A + 1) - (A - 1) * cw + sa
                a1 = 2 * ((A - 1) - (A + 1) * cw)
                a2 = (A + 1) - (A - 1) * cw - sa
            }
        }
        return BQ(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// 4th-order Butterworth high-pass as two sections.
    static func butterworth4HighPass(_ f: Double) -> [EQBand] {
        [EQBand(kind: .highPass, freq: f, q: 0.5411961001461969),
         EQBand(kind: .highPass, freq: f, q: 1.3065629648763766)]
    }
}

/// A cascade of biquad sections, transposed direct form II, computed in
/// Double (state and coefficients), Float in and out. Per sample, so the
/// output does not depend on how the stream is cut into buffers.
final class OwnBiquadStage: Stage {
    let name: String
    let bands: [EQBand]
    private(set) var sections: [BQ] = []
    private var state: UnsafeMutablePointer<Double>?
    private var channels = 0
    let latency = 0

    init(_ name: String, bands: [EQBand]) {
        self.name = name
        self.bands = bands
    }
    deinit { state?.deallocate() }

    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? {
        sections = bands.map { RBJ.design($0, fs: sampleRate) }
        state?.deallocate()
        self.channels = channels
        state = .allocate(capacity: max(1, channels * sections.count * 2))
        reset()
        return nil
    }

    func reset() { state?.update(repeating: 0, count: max(1, channels * sections.count * 2)) }

    /// Swaps coefficients without touching the state (an abrupt change).
    func setSections(_ s: [BQ]) {
        for i in 0..<min(s.count, sections.count) { sections[i] = s[i] }
    }

    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        guard let state else { return 0 }
        let n = min(abl.count, channels)
        sections.withUnsafeBufferPointer { secs in
            for c in 0..<n {
                guard let d = abl[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                for (k, s) in secs.enumerated() {
                    let st = state + (c * secs.count + k) * 2
                    var z1 = st[0], z2 = st[1]
                    for i in 0..<frames {
                        let x = Double(d[i])
                        let y = s.b0 * x + z1
                        z1 = s.b1 * x - s.a1 * y + z2
                        z2 = s.b2 * x - s.a2 * y
                        d[i] = Float(y)
                    }
                    st[0] = z1
                    st[1] = z2
                }
            }
        }
        return 0
    }
}

/// The same cascade through Accelerate's single-precision `vDSP_biquad`
/// (CPU comparison only).
final class OwnVDSPBiquadStage: Stage {
    let name: String
    let bands: [EQBand]
    private var setup: vDSP_biquad_Setup?
    private var delays: [UnsafeMutablePointer<Float>] = []
    private var sectionCount = 0
    let latency = 0

    init(_ name: String, bands: [EQBand]) {
        self.name = name
        self.bands = bands
    }
    deinit {
        if let setup { vDSP_biquad_DestroySetup(setup) }
        delays.forEach { $0.deallocate() }
    }

    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? {
        let secs = bands.map { RBJ.design($0, fs: sampleRate) }
        sectionCount = secs.count
        var coeffs: [Double] = []
        for s in secs { coeffs += [s.b0, s.b1, s.b2, s.a1, s.a2] }
        if let setup { vDSP_biquad_DestroySetup(setup) }
        setup = vDSP_biquad_CreateSetup(coeffs, vDSP_Length(secs.count))
        delays.forEach { $0.deallocate() }
        delays = (0..<channels).map { _ in .allocate(capacity: 2 * secs.count + 2) }
        reset()
        return setup == nil ? "vDSP_biquad_CreateSetup failed" : nil
    }

    func reset() { delays.forEach { $0.update(repeating: 0, count: 2 * sectionCount + 2) } }

    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        guard let setup else { return 0 }
        for c in 0..<min(abl.count, delays.count) {
            guard let d = abl[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
            vDSP_biquad(setup, delays[c], d, 1, d, 1, vDSP_Length(frames))
        }
        return 0
    }
}

/// A peaking band whose gain glides to its target (one pole, `glideSeconds`),
/// coefficients recomputed every sample — the zipper test's smoothed case.
final class OwnSmoothedPeakingStage: Stage {
    let name = "own peaking (smoothed)"
    var band: EQBand
    var targetDB: Double
    private var currentDB: Double
    private var fs = 48000.0
    private var glide = 0.0
    private var z: [Double] = [0, 0]
    let glideSeconds: Double
    let latency = 0

    init(band: EQBand, glideSeconds: Double) {
        self.band = band
        targetDB = band.gainDB
        currentDB = band.gainDB
        self.glideSeconds = glideSeconds
    }

    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? {
        fs = sampleRate
        glide = 1 - exp(-1 / (glideSeconds * sampleRate))
        return nil
    }
    func reset() { z = [0, 0] }

    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        guard let d = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return 0 }
        var z1 = z[0], z2 = z[1]
        var b = band
        for i in 0..<frames {
            currentDB += (targetDB - currentDB) * glide
            b.gainDB = currentDB
            let s = RBJ.design(b, fs: fs)
            let x = Double(d[i])
            let y = s.b0 * x + z1
            z1 = s.b1 * x - s.a1 * y + z2
            z2 = s.b2 * x - s.a2 * y
            d[i] = Float(y)
        }
        z[0] = z1
        z[1] = z2
        return 0
    }
}

// MARK: - Gain

final class GainStage: Stage {
    let name: String
    var gain: Float
    let latency = 0
    init(db: Float) {
        name = String(format: "gain %+.1f dB", db)
        gain = powf(10, db / 20)
    }
    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? { nil }
    func reset() {}
    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        var g = gain
        for c in 0..<abl.count {
            guard let d = abl[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
            vDSP_vsmul(d, 1, &g, d, 1, vDSP_Length(frames))
        }
        return 0
    }
}

// MARK: - Downward expander

/// Linked peak-follower detector; below the threshold every dB under it is
/// pushed down by (ratio − 1) dB, at most `rangeDB`. Opens at `attack`,
/// closes at `release`.
final class OwnExpanderStage: Stage {
    let name = "own expander"
    var thresholdDB: Float = -50, ratio: Float = 2, rangeDB: Float = 24
    var attackSeconds = 0.001, releaseSeconds = 0.1
    private var reduction: Float = 0, follower: Float = 0
    private var att: Float = 1, rel: Float = 1, fall: Float = 0
    private var gains: UnsafeMutablePointer<Float>?, det: UnsafeMutablePointer<Float>?,
        scratch: UnsafeMutablePointer<Float>?
    private var cap = 0
    let latency = 0

    deinit { gains?.deallocate(); det?.deallocate(); scratch?.deallocate() }

    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? {
        cap = max(1, maxFrames)
        for p in [gains, det, scratch] { p?.deallocate() }
        gains = .allocate(capacity: cap); det = .allocate(capacity: cap)
        scratch = .allocate(capacity: cap)
        att = Float(1 - exp(-1 / (attackSeconds * sampleRate)))
        rel = Float(1 - exp(-1 / (releaseSeconds * sampleRate)))
        fall = Float(exp(-1 / (0.010 * sampleRate)))
        reset()
        return nil
    }
    func reset() { reduction = 0; follower = 0 }

    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        guard let gains, let det, let scratch else { return 0 }
        var off = 0
        while off < frames {
            let n = min(cap, frames - off)
            var wrote = false
            for c in 0..<abl.count {
                guard let d = abl[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                if !wrote {
                    vDSP_vabs(d + off, 1, det, 1, vDSP_Length(n)); wrote = true
                } else {
                    vDSP_vabs(d + off, 1, scratch, 1, vDSP_Length(n))
                    vDSP_vmax(det, 1, scratch, 1, det, 1, vDSP_Length(n))
                }
            }
            for i in 0..<n {
                follower = max(det[i], follower * fall)
                let levelDB = 20 * log10f(max(follower, 1e-9))
                var target: Float = 0
                if levelDB < thresholdDB { target = min(rangeDB, (thresholdDB - levelDB) * (ratio - 1)) }
                reduction += (target - reduction) * (target < reduction ? att : rel)
                gains[i] = expf(-reduction * 0.11512925)
            }
            for c in 0..<abl.count {
                guard let d = abl[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                vDSP_vmul(d + off, 1, gains, 1, d + off, 1, vDSP_Length(n))
            }
            off += n
        }
        return 0
    }
}

// MARK: - Compressor (the shipped AudioCompressorStage's arithmetic, 9e47f56)

final class OwnCompressorStage: Stage {
    let name = "own compressor (shipped)"
    var thresholdDB: Float = -18, ratio: Float = 3, attackSeconds = 0.005, releaseSeconds = 0.1,
        makeupDB: Float = 0
    private var reductionDB: Float = 0, detectorState: Float = 0
    private var sr = 48000.0
    private var detector: UnsafeMutablePointer<Float>?, scratch: UnsafeMutablePointer<Float>?,
        gains: UnsafeMutablePointer<Float>?
    private var cap = 0
    let latency = 0

    deinit { detector?.deallocate(); scratch?.deallocate(); gains?.deallocate() }

    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? {
        sr = sampleRate
        cap = max(1, maxFrames)
        for p in [detector, scratch, gains] { p?.deallocate() }
        detector = .allocate(capacity: cap); scratch = .allocate(capacity: cap)
        gains = .allocate(capacity: cap)
        reset()
        return nil
    }
    func reset() { reductionDB = 0; detectorState = 0 }

    private func coefficient(_ s: Double) -> Float { s > 0 ? Float(1 - exp(-1 / (s * sr))) : 1 }

    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        guard let detector, let scratch, let gains else { return 0 }
        var off = 0
        while off < frames {
            let n = min(cap, frames - off)
            var wrote = false
            for c in 0..<abl.count {
                guard let d = abl[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                if !wrote {
                    vDSP_vabs(d + off, 1, detector, 1, vDSP_Length(n)); wrote = true
                } else {
                    vDSP_vabs(d + off, 1, scratch, 1, vDSP_Length(n))
                    vDSP_vmax(detector, 1, scratch, 1, detector, 1, vDSP_Length(n))
                }
            }
            let slope = ratio > 1 ? 1 - 1 / ratio : 0
            let thLin = expf(thresholdDB * 0.11512925)
            let attack = coefficient(attackSeconds), release = coefficient(releaseSeconds)
            let fall = Float(exp(-1 / (max(releaseSeconds, 0.010) * sr)))
            for i in 0..<n {
                detectorState = max(detector[i], detectorState * fall)
                var target: Float = 0
                if slope > 0, detectorState > thLin {
                    target = (20 * log10f(max(detectorState, 1e-9)) - thresholdDB) * slope
                }
                reductionDB += (target - reductionDB) * (target > reductionDB ? attack : release)
                gains[i] = expf((makeupDB - reductionDB) * 0.11512925)
            }
            for c in 0..<abl.count {
                guard let d = abl[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                vDSP_vmul(d + off, 1, gains, 1, d + off, 1, vDSP_Length(n))
            }
            off += n
        }
        return 0
    }
}

// MARK: - True-peak limiter

/// Lookahead true-peak limiter, channel-linked.
///
/// Detection: every input sample's neighbourhood is interpolated at the three
/// quarter positions after it by a 12-tap-per-phase windowed-sinc polyphase
/// FIR (the BS.1770 annex 2 shape), and the required gain ceiling/peak is
/// taken. Gain: a sliding minimum of the requirement over `hold` samples,
/// a release (one pole, never above the held minimum), and a box filter of
/// `look` samples that turns the step into a ramp. With hold = look + 12 and
/// the audio delayed by look + 11 samples, every sample in the interpolation
/// support of a peak is gained by no more than that peak requires.
final class OwnTruePeakLimiterStage: Stage {
    let name = "own true-peak limiter"
    var ceilingDB: Double = -1
    var lookaheadSeconds = 0.002
    var releaseSeconds = 0.1
    static let half = 6  // taps either side: support x[m-5 ... m+6]
    static let taps = 12

    private(set) var look = 96
    private var hold = 108
    private(set) var delay = 107
    private var ceiling: Float = 0.891
    private var relCoef: Float = 0
    private var channels = 0
    // FIR phases 1..3, 12 taps each, applied to x[m-5 ... m+6].
    private let fir = UnsafeMutablePointer<Float>.allocate(capacity: 3 * 12)
    // Per channel: history ring (16, mask 15) and delay ring (pow2).
    private var hist: UnsafeMutablePointer<Float>?
    private var histPos = 0
    private var dline: UnsafeMutablePointer<Float>?
    private var dmask = 0
    private var dpos = 0
    // Sliding minimum deque (values, indices), ring of capacity `dqCap`.
    private var dqVal: UnsafeMutablePointer<Float>?
    private var dqIdx: UnsafeMutablePointer<Int>?
    private var dqCap = 0, dqHead = 0, dqCount = 0
    // Box filter ring.
    private var box: UnsafeMutablePointer<Float>?
    private var boxPos = 0
    private var boxSum: Double = 0
    private var env: Float = 1
    private var n = 0  // running sample index
    var latency: Int { delay }

    init() {
        for p in 1...3 {
            let frac = Double(p) / 4
            var sum = 0.0
            var row = [Double](repeating: 0, count: 12)
            for k in 0..<12 {
                let j = Double(k - 5)  // offsets -5 ... +6
                let t = frac - j
                let sinc = t == 0 ? 1 : sin(Double.pi * t) / (Double.pi * t)
                // Kaiser-like window over |t| <= 6.5 (Hann on the span).
                let w = 0.5 + 0.5 * cos(Double.pi * t / 6.5)
                row[k] = sinc * w
                sum += row[k]
            }
            for k in 0..<12 { fir[(p - 1) * 12 + k] = Float(row[k] / sum) }
        }
    }

    deinit {
        fir.deallocate()
        hist?.deallocate(); dline?.deallocate(); dqVal?.deallocate(); dqIdx?.deallocate()
        box?.deallocate()
    }

    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? {
        self.channels = channels
        look = max(16, Int((lookaheadSeconds * sampleRate).rounded()))
        hold = look + 12
        delay = look + 11
        ceiling = Float(pow(10, ceilingDB / 20))
        relCoef = Float(1 - exp(-1 / (releaseSeconds * sampleRate)))
        var size = 1
        while size < delay + 1 { size <<= 1 }
        dmask = size - 1
        hist?.deallocate(); dline?.deallocate(); dqVal?.deallocate(); dqIdx?.deallocate()
        box?.deallocate()
        hist = .allocate(capacity: channels * 16)
        dline = .allocate(capacity: channels * size)
        dqCap = hold + 2
        dqVal = .allocate(capacity: dqCap)
        dqIdx = .allocate(capacity: dqCap)
        box = .allocate(capacity: look)
        reset()
        return nil
    }

    func reset() {
        hist?.update(repeating: 0, count: channels * 16)
        dline?.update(repeating: 0, count: channels * (dmask + 1))
        box?.update(repeating: 1, count: look)
        boxSum = Double(look)
        histPos = 0; dpos = 0; boxPos = 0; dqHead = 0; dqCount = 0
        env = 1
        n = 0
    }

    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        guard let hist, let dline, let dqVal, let dqIdx, let box else { return 0 }
        let chans = min(abl.count, channels)
        let dsize = dmask + 1
        for i in 0..<frames {
            // Push the new sample of every channel; take the linked peak of
            // the neighbourhood centred 6 samples back.
            var peak: Float = 0
            histPos = (histPos + 1) & 15
            for c in 0..<chans {
                guard let d = abl[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                let h = hist + c * 16
                h[histPos] = d[i]
                // x[m] with m = newest − 6; support x[m-5 ... m+6] = newest-11 ... newest.
                let xm = h[(histPos - 6) & 15]
                peak = max(peak, abs(xm))
                for p in 0..<3 {
                    var acc: Float = 0
                    let row = fir + p * 12
                    for k in 0..<12 { acc += row[k] * h[(histPos - 11 + k) & 15] }
                    peak = max(peak, abs(acc))
                }
            }
            let need: Float = peak > ceiling ? ceiling / peak : 1
            // Sliding minimum over the last `hold` requirements.
            while dqCount > 0, dqVal[(dqHead + dqCount - 1) % dqCap] >= need { dqCount -= 1 }
            dqVal[(dqHead + dqCount) % dqCap] = need
            dqIdx[(dqHead + dqCount) % dqCap] = n
            dqCount += 1
            while dqIdx[dqHead] <= n - hold { dqHead = (dqHead + 1) % dqCap; dqCount -= 1 }
            let held = dqVal[dqHead]
            env = held < env ? held : env + (held - env) * relCoef
            boxSum += Double(env) - Double(box[boxPos])
            box[boxPos] = env
            boxPos = boxPos + 1 == look ? 0 : boxPos + 1
            let g = Float(boxSum / Double(look))
            // Delay the audio and apply.
            for c in 0..<chans {
                guard let d = abl[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                let line = dline + c * dsize
                line[dpos] = d[i]
                d[i] = line[(dpos - delay) & dmask] * g
            }
            dpos = (dpos + 1) & dmask
            n += 1
        }
        return 0
    }
}

/// Several stages in order, as one stage.
final class ChainStage: Stage {
    let name: String
    let stages: [Stage]
    init(_ name: String, _ stages: [Stage]) {
        self.name = name
        self.stages = stages
    }
    var latency: Int { stages.reduce(0) { $0 + $1.latency } }
    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? {
        for s in stages {
            if let e = s.prepare(channels: channels, sampleRate: sampleRate, maxFrames: maxFrames) {
                return "\(s.name): \(e)"
            }
        }
        return nil
    }
    func reset() { stages.forEach { $0.reset() } }
    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        for s in stages {
            let r = s.process(abl, frames: frames)
            if r != 0 { return r }
        }
        return 0
    }
}
