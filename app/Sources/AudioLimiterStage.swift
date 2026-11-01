import Accelerate
import Foundation

/// The clip limiter (spec §11 AU-20): a lookahead true-peak limiter, the last
/// stage of `AudioDSPChain`, after an enclosing nest's fold and before the
/// fader. A port of road map "audio" AP0's spike S1 (`OwnLimiter2.swift` at
/// 64 taps, β 10, with Annex 2, taps outermost), which met S1's rule: no
/// allocation or lock on the tap's thread, the same bytes twice and at any
/// buffer size, within 0.1 dB of its ceiling, one constant latency.
///
/// **The detector** reads, per sample and over every channel, the largest of
/// |x|, the three fractional phases of a 64-tap Kaiser-windowed sinc (β 10)
/// 4× interpolator, and BS.1770-4 Annex 2's four 12-tap phases. Both are
/// needed (S1): a detector of Annex 2's size alone lets a broadband onset
/// through by up to +0.97 dB, and Annex 2 over-reads speech by 0.14 dB, so a
/// limiter exact by an accurate meter alone reads −0.86 dBTP on the app's own
/// meter (`Loudness.swift`). Each FIR loops its taps OUTERMOST over
/// element-wise arithmetic, never `vDSP_conv` or `vDSP_biquad`: those give
/// different bits for different buffer sizes, and the player's and the
/// reader's buffers differ (S1).
///
/// **The gain** is the need `min(1, ceiling / peak)`, held by a sliding
/// minimum over `hold` (159) samples, released by a one-pole that never rises
/// above the held value and snaps to it within 2⁻²⁰, then smoothed by the mean
/// of the last `lookahead` (96) released values, summed afresh each sample in
/// one order — no running sum, so a released stage's gain is exactly 1 and the
/// stage is an exact delay. One gain for every channel, so the image does not
/// move. The audio is delayed `latency` (158) samples at any rate: every sample
/// in a peak's interpolation support is gained by no more than that peak
/// needs.
///
/// **What it is told** is the ceiling BEFORE the fader (AU-22): the fader is
/// downstream of the tap, so `AudioLimiterSettings.ceiling` is the clip's
/// dBTP ceiling over its base volume. Nil settings are a ceiling of +∞: the
/// stage keeps its history and its delay, and once released it is a pure
/// delay, which is what a track whose other clips have no limiter needs.
///
/// Real-time rules as `AudioDSP.swift`'s head: every buffer is allocated in
/// `init`, nothing locks, `reset()` restores the fresh state.
final class AudioLimiterStage {
    /// Lookahead samples: S1's 2 ms at 48 kHz, held at 96 at every rate so
    /// the latency is one number (AU-23's lead is in ticks at 48 kHz, as
    /// SY-25's is).
    static let lookahead = 96
    /// The Kaiser interpolator's length.
    static let taps = 64
    /// `lookahead + taps − 2`: what the stage delays its audio by.
    static let latency = 158
    /// `lookahead + taps − 1`: the sliding minimum's window.
    static let hold = 159
    /// The interpolator's Kaiser β.
    static let beta = 10.0
    /// Where the release stops creeping and lands on the held value.
    static let snap = 1.0 / 1_048_576
    /// The release a stage with no settings recovers at.
    static let idleReleaseSeconds = 0.1

    /// BS.1770-4 Annex 2's four phases, as `Loudness.swift` reads them.
    static let annex2: [[Float]] = [
        [0.0017089843750, 0.0109863281250, -0.0196533203125, 0.0332031250000, -0.0594482421875,
         0.1373291015625, 0.9721679687500, -0.1022949218750, 0.0476074218750, -0.0266113281250,
         0.0148925781250, -0.0083007812500],
        [-0.0291748046875, 0.0292968750000, -0.0517578125000, 0.0891113281250, -0.1665039062500,
         0.4650878906250, 0.7797851562500, -0.2003173828125, 0.1015625000000, -0.0582275390625,
         0.0330810546875, -0.0189208984375],
        [-0.0189208984375, 0.0330810546875, -0.0582275390625, 0.1015625000000, -0.2003173828125,
         0.7797851562500, 0.4650878906250, -0.1665039062500, 0.0891113281250, -0.0517578125000,
         0.0292968750000, -0.0291748046875],
        [-0.0083007812500, 0.0148925781250, -0.0266113281250, 0.0476074218750, -0.1022949218750,
         0.9721679687500, 0.1373291015625, -0.0594482421875, 0.0332031250000, -0.0196533203125,
         0.0109863281250, 0.0017089843750],
    ]

    private let channelCount: Int
    private let sampleRate: Double
    private let cap: Int
    private let half = AudioLimiterStage.taps / 2
    /// 3 × taps: the Kaiser interpolator's fractional phases, row p for the
    /// point m + (p + 1)/4.
    private let fir: UnsafeMutablePointer<Float>
    /// 4 × 12: Annex 2's phases, each row reversed.
    private let annex: UnsafeMutablePointer<Float>
    /// Per channel, the last `taps − 1` inputs then the block being read.
    private let history: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>
    /// One tap's products, before they are added into `scratch`.
    private let product: UnsafeMutablePointer<Float>
    private let peaks: UnsafeMutablePointer<Float>
    /// Per channel, a ring of `mask + 1` samples: the delay line.
    private let line: UnsafeMutablePointer<Float>
    private let mask: Int
    private var linePosition = 0
    /// The sliding minimum's monotone deque: values and their sample index.
    private let dequeValues: UnsafeMutablePointer<Float>
    private let dequeIndices: UnsafeMutablePointer<Int>
    private let dequeCapacity = AudioLimiterStage.hold + 2
    private var dequeHead = 0
    private var dequeCount = 0
    /// The last `lookahead` released values.
    private let box: UnsafeMutablePointer<Float>
    private var boxPosition = 0
    /// In Double: a Float one-pole stalls near 1, where a long release's
    /// step falls under half an ulp well before the snap.
    private var envelope: Double = 1
    private var sampleIndex = 0

    init(channelCount: Int, sampleRate: Double, maxFrames: Int) {
        let taps = Self.taps
        self.channelCount = max(0, channelCount)
        self.sampleRate = sampleRate >= 1 ? sampleRate : 48_000
        cap = max(1, maxFrames)
        // Tap k multiplies x[m + k − H + 1] for the point m + p/4.
        fir = .allocate(capacity: 3 * taps)
        let edge = Double(half) + 0.5
        for p in 1...3 {
            var row = [Double](repeating: 0, count: taps)
            for k in 0..<taps {
                let t = Double(p) / 4 - Double(k - half + 1)
                let sinc = t == 0 ? 1 : sin(Double.pi * t) / (Double.pi * t)
                let r = max(0, 1 - (t / edge) * (t / edge))
                row[k] = sinc * Self.besselI0(Self.beta * r.squareRoot()) / Self.besselI0(Self.beta)
            }
            let sum = row.reduce(0, +)
            for k in 0..<taps { fir[(p - 1) * taps + k] = Float(row[k] / sum) }
        }
        annex = .allocate(capacity: 48)
        for phase in 0..<4 {
            for k in 0..<12 { annex[phase * 12 + k] = Self.annex2[phase][11 - k] }
        }
        let stride = taps - 1 + cap
        history = .allocate(capacity: max(1, self.channelCount * stride))
        scratch = .allocate(capacity: cap)
        product = .allocate(capacity: cap)
        peaks = .allocate(capacity: cap)
        var size = 1
        while size < Self.latency + 1 { size <<= 1 }
        mask = size - 1
        line = .allocate(capacity: max(1, self.channelCount * size))
        dequeValues = .allocate(capacity: dequeCapacity)
        dequeIndices = .allocate(capacity: dequeCapacity)
        box = .allocate(capacity: Self.lookahead)
        reset()
    }

    deinit {
        for pointer in [fir, annex, history, scratch, product, peaks, line, dequeValues, box] {
            pointer.deallocate()
        }
        dequeIndices.deallocate()
    }

    /// The modified Bessel function of the first kind, order 0: the Kaiser
    /// window's kernel. `init` only.
    private static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        var k = 1.0
        while term > 1e-12 * sum {
            term *= (x / (2 * k)) * (x / (2 * k))
            sum += term
            k += 1
        }
        return sum
    }

    /// The fresh state: silence behind, nothing held, the gain at 1.
    func reset() {
        history.update(repeating: 0, count: max(1, channelCount * (Self.taps - 1 + cap)))
        line.update(repeating: 0, count: max(1, channelCount * (mask + 1)))
        box.update(repeating: 1, count: Self.lookahead)
        linePosition = 0
        boxPosition = 0
        dequeHead = 0
        dequeCount = 0
        envelope = 1
        sampleIndex = 0
    }

    /// Limits `frames` samples of the first `count` channels in place, in
    /// chunks of at most the `maxFrames` the stage was built with.
    func process(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        frames: Int, settings: AudioLimiterSettings?
    ) {
        let count = min(count, channels.count, channelCount)
        guard frames > 0, count > 0 else { return }
        let ceiling = settings?.ceiling ?? .infinity
        let release = settings?.releaseSeconds ?? Self.idleReleaseSeconds
        let coefficient = 1 - exp(-1 / (max(release, 1e-6) * sampleRate))
        var offset = 0
        while offset < frames {
            let length = min(cap, frames - offset)
            chunk(
                channels, count: count, offset: offset, frames: length, ceiling: ceiling,
                coefficient: coefficient)
            offset += length
        }
    }

    private func chunk(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        offset: Int, frames: Int, ceiling: Float, coefficient: Double
    ) {
        let taps = Self.taps
        let stride = taps - 1 + cap
        let length = vDSP_Length(frames)
        // A ceiling of +∞ needs nothing measured: every need is 1. The
        // history still advances, so a limited clip after it reads its
        // onset with the samples that came before.
        let detect = ceiling.isFinite
        peaks.update(repeating: 0, count: frames)
        for channel in 0..<count {
            guard let data = channels[channel] else { continue }
            let h = history + channel * stride
            (h + taps - 1).update(from: data + offset, count: frames)
            if detect {
                // |x[m]|, m = newest − H.
                vDSP_vabs(h + half - 1, 1, scratch, 1, length)
                vDSP_vmax(peaks, 1, scratch, 1, peaks, 1, length)
                for phase in 0..<3 {
                    accumulate(row: fir + phase * taps, length: taps, from: h, frames: frames)
                    vDSP_vabs(scratch, 1, scratch, 1, length)
                    vDSP_vmax(peaks, 1, scratch, 1, peaks, 1, length)
                }
                // Annex 2 at m: x[m − 5 … m + 6].
                for phase in 0..<4 {
                    accumulate(row: annex + phase * 12, length: 12, from: h + half - 6, frames: frames)
                    vDSP_vabs(scratch, 1, scratch, 1, length)
                    vDSP_vmax(peaks, 1, scratch, 1, peaks, 1, length)
                }
            }
            // Keep the last taps − 1 inputs for the next block.
            memmove(h, h + frames, (taps - 1) * MemoryLayout<Float>.size)
        }
        let size = mask + 1
        let hold = Self.hold
        let look = Self.lookahead
        for i in 0..<frames {
            let peak = peaks[i]
            let need: Float = peak > ceiling ? ceiling / peak : 1
            while dequeCount > 0,
                dequeValues[(dequeHead + dequeCount - 1) % dequeCapacity] >= need
            {
                dequeCount -= 1
            }
            dequeValues[(dequeHead + dequeCount) % dequeCapacity] = need
            dequeIndices[(dequeHead + dequeCount) % dequeCapacity] = sampleIndex
            dequeCount += 1
            while dequeIndices[dequeHead] <= sampleIndex - hold {
                dequeHead = (dequeHead + 1) % dequeCapacity
                dequeCount -= 1
            }
            let held = Double(dequeValues[dequeHead])
            if held < envelope {
                envelope = held
            } else {
                envelope += (held - envelope) * coefficient
                if held - envelope <= Self.snap { envelope = held }
            }
            box[boxPosition] = Float(envelope)
            boxPosition = boxPosition + 1 == look ? 0 : boxPosition + 1
            // Summed afresh over the whole box, the same call on the same
            // buffer every sample: a box of ones is exactly `look`.
            var sum: Float = 0
            vDSP_sve(box, 1, &sum, vDSP_Length(look))
            let gain = sum / Float(look)
            for channel in 0..<count {
                guard let data = channels[channel] else { continue }
                let ring = line + channel * size
                ring[linePosition] = data[offset + i]
                data[offset + i] = ring[(linePosition - Self.latency) & mask] * gain
            }
            linePosition = (linePosition + 1) & mask
            sampleIndex += 1
        }
    }

    /// `scratch[i] = Σ_k row[k]·source[i + k]`, the taps outermost: per tap
    /// one element-wise multiply, rounded, then one element-wise add, rounded
    /// — the scalar loop's arithmetic in its order, whatever `frames` is, and
    /// fast in an unoptimised build too, where a scalar loop misses the tap's
    /// real-time deadline.
    private func accumulate(
        row: UnsafeMutablePointer<Float>, length: Int, from source: UnsafeMutablePointer<Float>,
        frames: Int
    ) {
        let n = vDSP_Length(frames)
        scratch.update(repeating: 0, count: frames)
        for k in 0..<length {
            var c = row[k]
            vDSP_vsmul(source + k, 1, &c, product, 1, n)
            vDSP_vadd(scratch, 1, product, 1, scratch, 1, n)
        }
    }
}
