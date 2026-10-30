import Accelerate
import AudioToolbox
import Foundation

/// The true-peak limiter, second version: the detector is a `taps`-tap
/// Kaiser-windowed-sinc polyphase interpolator (32 taps, beta 8: flat within
/// 0.001 dB to 20 kHz at 48 kHz), run a block at a time with `vDSP_conv`
/// (or, with `vectorDetector` false, a scalar loop with a fixed summation
/// order). The gain path is the first version's: a sliding minimum of the
/// requirement over `hold` samples, a release that never rises above it, and a
/// `look`-sample box filter, with hold = look + 2H − 1 and the audio delayed
/// look + 2H − 2 samples (H = taps / 2), so every sample in the interpolation
/// support of a peak is gained by no more than that peak requires.
final class OwnTruePeakLimiter2: Stage {
    let name: String
    var ceilingDB: Double = -1
    var lookaheadSeconds = 0.002
    var releaseSeconds = 0.1
    let taps: Int
    let beta: Double
    let vectorDetector: Bool
    /// Also take BS.1770-4 Annex 2's own 4-phase 12-tap reading (the filter
    /// `Loudness.swift` reports with), so the app's own meter can never read
    /// above the ceiling either.
    let annexToo: Bool
    /// Scalar arithmetic in a fixed order per output (tap 0 first), with
    /// the TAP loop outermost so the compiler vectorises across samples:
    /// bit-identical to the scalar loop, and invariant to block size.
    var tapOuter = false
    private var annex: UnsafeMutablePointer<Float>?  // 4 × 12, reversed for vDSP_conv

    private var H = 16
    private(set) var look = 96
    private var hold = 0
    private(set) var delay = 0
    private var ceiling: Float = 0.891
    private var relCoef: Float = 0
    private var channels = 0
    private var cap = 0
    private var fir: UnsafeMutablePointer<Float>?  // 3 × taps
    private var hb: UnsafeMutablePointer<Float>?  // channels × (taps − 1 + cap)
    private var tmp: UnsafeMutablePointer<Float>?  // cap
    private var peakBuf: UnsafeMutablePointer<Float>?  // cap
    private var dline: UnsafeMutablePointer<Float>?
    private var dmask = 0, dpos = 0
    private var dqVal: UnsafeMutablePointer<Float>?
    private var dqIdx: UnsafeMutablePointer<Int>?
    private var dqCap = 0, dqHead = 0, dqCount = 0
    private var box: UnsafeMutablePointer<Float>?
    private var boxPos = 0
    private var boxSum: Double = 0
    private var env: Float = 1
    private var n = 0
    var latency: Int { delay }

    init(taps: Int = 32, beta: Double = 8, vectorDetector: Bool = true, annexToo: Bool = false) {
        self.taps = taps
        self.beta = beta
        self.vectorDetector = vectorDetector
        self.annexToo = annexToo
        name = "own true-peak limiter (\(taps) taps\(vectorDetector ? ", vDSP_conv" : ", scalar")\(annexToo ? " + Annex 2" : ""))"
        let a = UnsafeMutablePointer<Float>.allocate(capacity: 48)
        for ph in 0..<4 { for k in 0..<12 { a[ph * 12 + k] = Self.annex2[ph][11 - k] } }
        annex = a
    }

    deinit { for p in [fir, hb, tmp, peakBuf, dline, dqVal, box, annex] { p?.deallocate() }; dqIdx?.deallocate() }

    static let annex2: [[Float]] = [
        [0.0017089843750, 0.0109863281250, -0.0196533203125, 0.0332031250000, -0.0594482421875, 0.1373291015625,
         0.9721679687500, -0.1022949218750, 0.0476074218750, -0.0266113281250, 0.0148925781250, -0.0083007812500],
        [-0.0291748046875, 0.0292968750000, -0.0517578125000, 0.0891113281250, -0.1665039062500, 0.4650878906250,
         0.7797851562500, -0.2003173828125, 0.1015625000000, -0.0582275390625, 0.0330810546875, -0.0189208984375],
        [-0.0189208984375, 0.0330810546875, -0.0582275390625, 0.1015625000000, -0.2003173828125, 0.7797851562500,
         0.4650878906250, -0.1665039062500, 0.0891113281250, -0.0517578125000, 0.0292968750000, -0.0291748046875],
        [-0.0083007812500, 0.0148925781250, -0.0266113281250, 0.0476074218750, -0.1022949218750, 0.9721679687500,
         0.1373291015625, -0.0594482421875, 0.0332031250000, -0.0196533203125, 0.0109863281250, 0.0017089843750],
    ]

    private static func i0(_ x: Double) -> Double {
        var sum = 1.0, term = 1.0, k = 1.0
        while term > 1e-12 * sum { term *= (x / (2 * k)) * (x / (2 * k)); sum += term; k += 1 }
        return sum
    }

    func prepare(channels: Int, sampleRate: Double, maxFrames: Int) -> String? {
        for p in [fir, hb, tmp, peakBuf, dline, dqVal, box] { p?.deallocate() }
        dqIdx?.deallocate()
        self.channels = channels
        cap = max(1, maxFrames)
        H = taps / 2
        look = max(16, Int((lookaheadSeconds * sampleRate).rounded()))
        hold = look + 2 * H - 1
        delay = look + 2 * H - 2
        ceiling = Float(pow(10, ceilingDB / 20))
        relCoef = Float(1 - exp(-1 / (releaseSeconds * sampleRate)))
        // Coefficients: tap k multiplies x[m + j], j = k − H + 1, for the
        // point m + p/4.
        let f = UnsafeMutablePointer<Float>.allocate(capacity: 3 * taps)
        let half = Double(H) + 0.5
        for p in 1...3 {
            var row = [Double](repeating: 0, count: taps)
            for k in 0..<taps {
                let t = Double(p) / 4 - Double(k - H + 1)
                let s = t == 0 ? 1 : sin(Double.pi * t) / (Double.pi * t)
                let r = max(0, 1 - (t / half) * (t / half))
                row[k] = s * Self.i0(beta * r.squareRoot()) / Self.i0(beta)
            }
            let sum = row.reduce(0, +)
            for k in 0..<taps { f[(p - 1) * taps + k] = Float(row[k] / sum) }
        }
        fir = f
        hb = .allocate(capacity: channels * (taps - 1 + cap))
        tmp = .allocate(capacity: cap)
        peakBuf = .allocate(capacity: cap)
        var size = 1
        while size < delay + 1 { size <<= 1 }
        dmask = size - 1
        dline = .allocate(capacity: channels * size)
        dqCap = hold + 2
        dqVal = .allocate(capacity: dqCap)
        dqIdx = .allocate(capacity: dqCap)
        box = .allocate(capacity: look)
        reset()
        return nil
    }

    func reset() {
        hb?.update(repeating: 0, count: channels * (taps - 1 + cap))
        dline?.update(repeating: 0, count: channels * (dmask + 1))
        box?.update(repeating: 1, count: look)
        boxSum = Double(look)
        dpos = 0; boxPos = 0; dqHead = 0; dqCount = 0
        env = 1
        n = 0
    }

    func process(_ abl: UnsafeMutableAudioBufferListPointer, frames: Int) -> Int32 {
        var off = 0
        while off < frames {
            let len = min(cap, frames - off)
            chunk(abl, offset: off, frames: len)
            off += len
        }
        return 0
    }

    private func chunk(_ abl: UnsafeMutableAudioBufferListPointer, offset: Int, frames: Int) {
        guard let fir, let hb, let tmp, let peakBuf, let dline, let dqVal, let dqIdx, let box else { return }
        let chans = min(abl.count, channels)
        let stride = taps - 1 + cap
        let len = vDSP_Length(frames)
        peakBuf.update(repeating: 0, count: frames)
        for c in 0..<chans {
            guard let d = abl[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
            let h = hb + c * stride
            (h + taps - 1).update(from: d + offset, count: frames)
            // |x[m]|, m = newest − H: hb[i + H − 1].
            vDSP_vabs(h + H - 1, 1, tmp, 1, len)
            vDSP_vmax(peakBuf, 1, tmp, 1, peakBuf, 1, len)
            for p in 0..<3 {
                let row = fir + p * taps
                if tapOuter {
                    tmp.update(repeating: 0, count: frames)
                    for k in 0..<taps {
                        let c = row[k]
                        let src = h + k
                        for i in 0..<frames { tmp[i] += c * src[i] }
                    }
                } else if vectorDetector {
                    vDSP_conv(h, 1, row, 1, tmp, 1, len, vDSP_Length(taps))
                } else {
                    for i in 0..<frames {
                        var acc: Float = 0
                        for k in 0..<taps { acc += row[k] * h[i + k] }
                        tmp[i] = acc
                    }
                }
                vDSP_vabs(tmp, 1, tmp, 1, len)
                vDSP_vmax(peakBuf, 1, tmp, 1, peakBuf, 1, len)
            }
            if annexToo, let annex, H >= 6 {
                // y_p at newest' = m + 6: x[m−5 ... m+6] = hb[i + H − 6 ...].
                for ph in 0..<4 {
                    let row = annex + ph * 12
                    if tapOuter {
                        let base = h + H - 6
                        tmp.update(repeating: 0, count: frames)
                        for k in 0..<12 {
                            let c = row[k]
                            let src = base + k
                            for i in 0..<frames { tmp[i] += c * src[i] }
                        }
                    } else if vectorDetector {
                        vDSP_conv(h + H - 6, 1, row, 1, tmp, 1, len, 12)
                    } else {
                        let base = h + H - 6
                        for i in 0..<frames {
                            var acc: Float = 0
                            for k in 0..<12 { acc += row[k] * base[i + k] }
                            tmp[i] = acc
                        }
                    }
                    vDSP_vabs(tmp, 1, tmp, 1, len)
                    vDSP_vmax(peakBuf, 1, tmp, 1, peakBuf, 1, len)
                }
            }
            // Keep the last taps − 1 inputs for the next block.
            memmove(h, h + frames, (taps - 1) * MemoryLayout<Float>.size)
        }
        let dsize = dmask + 1
        for i in 0..<frames {
            let peak = peakBuf[i]
            let need: Float = peak > ceiling ? ceiling / peak : 1
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
            for c in 0..<chans {
                guard let d = abl[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                let line = dline + c * dsize
                line[dpos] = d[offset + i]
                d[offset + i] = line[(dpos - delay) & dmask] * g
            }
            dpos = (dpos + 1) & dmask
            n += 1
        }
    }
}
