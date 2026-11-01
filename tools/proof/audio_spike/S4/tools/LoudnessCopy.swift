import Foundation
import Accelerate
// MARK: - What a measurement says

/// The answer one pass over a programme gives.
///
/// `integratedLUFS` is optional because "no integrated loudness" is a real
/// state rather than an error: a programme shorter than one 400 ms block
/// yields no block at all, and digital silence has every block gated out by
/// Γa. The caller's answer to nil is "apply no gain and say so", never
/// reaching for −∞ and multiplying by it.
struct LoudnessReport: Equatable {
    /// Integrated loudness in LUFS (the standard spells the unit LKFS; they
    /// are the same number), or nil when every gating block was gated out.
    let integratedLUFS: Double?
    /// The largest interpolated magnitude, in dB relative to full scale.
    /// `-Double.infinity` for digital silence.
    let truePeakDBTP: Double
    /// The largest sample magnitude, in dBFS. Free from the same pass, and
    /// the invariant `truePeakDBTP >= samplePeakDBFS` holds by construction.
    let samplePeakDBFS: Double

    /// Digital silence: nothing to measure and nothing to normalise.
    static let silence = LoudnessReport(
        integratedLUFS: nil, truePeakDBTP: -.infinity, samplePeakDBFS: -.infinity)
}
// MARK: - The meter

/// BS.1770-4 over a stream of interleaved 32-bit float frames.
///
/// Feed it every frame of the programme in order, then ask it once. The
/// K-weighting filters and the true-peak interpolator both carry state
/// ACROSS calls — that is the whole reason this is an object and not a
/// function: the filters run continuously over the programme (blocks
/// overlap by 75 %, so a per-block reset is not even well defined) and the
/// interpolating FIR needs 11 samples of per-channel history, which arrive
/// in one buffer and are needed in the next.
final class LoudnessMeter {

    /// The rate the coefficient tables are published at, and the rate the
    /// export mix is decoded at. Not a default: `init` refuses anything else.
    static let requiredSampleRate: Double = 48000

    /// Every measurement window BS.1770-4 § 2 names, in seconds.
    ///
    /// A gating block is 400 ms; blocks overlap by 75 %, so one starts every
    /// 100 ms and a block is exactly four consecutive 100 ms sub-blocks. That
    /// is why the accumulator below keeps a running sum per sub-block and a
    /// ring of the last four rather than re-summing 19 200 samples per block.
    private static let blockSeconds: Double = 0.400
    private static let hopSeconds: Double = 0.100
    private static let subBlocksPerBlock = 4

    /// BS.1770-4 equation (2)'s offset. Note 1 of that clause says what it
    /// is for: it cancels the K-weighting's gain at 997 Hz, which this
    /// implementation measures as +0.6977 dB.
    private static let offset: Double = -0.691

    /// Γa, the absolute gate, in LUFS. A block at or below it is not
    /// programme.
    private static let absoluteGate: Double = -70

    /// Γr's offset below the gated mean, in LU.
    private static let relativeGate: Double = -10

    // ---- K-weighting -----------------------------------------------------

    /// One biquad, in the difference equation BS.1770-4's Fig. 3 draws:
    ///
    ///     y[n] = b0·x[n] + b1·x[n−1] + b2·x[n−2] − a1·y[n−1] − a2·y[n−2]
    ///
    /// `a0` is 1 in both of the standard's tables and is not carried.
    ///
    /// Double, not Float, and deliberately: the second stage's poles sit at
    /// a1 = −1.99005, a2 = 0.99007 — a hair from DC — and a single-precision
    /// direct form I loses enough per step to drift audibly over a
    /// forty-minute programme. This is not the audio render thread, so the
    /// precision is free.
    private struct Biquad {
        let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    }

    /// Table 1: "Filter coefficients for stage 1 of the pre-filter to model a
    /// spherical head" — a high shelf, +4 dB above about 2 kHz. Quoted from
    /// Recommendation ITU-R BS.1770-4 (10/2015), for 48 kHz.
    private static let stage1 = Biquad(
        b0: 1.535_124_859_586_97,
        b1: -2.691_696_189_406_38,
        b2: 1.198_392_810_852_85,
        a1: -1.690_659_293_182_41,
        a2: 0.732_480_774_215_85)

    /// Table 2: "Filter coefficients for the second stage weighting curve" —
    /// the RLB high-pass. Same source, same rate.
    private static let stage2 = Biquad(
        b0: 1.0,
        b1: -2.0,
        b2: 1.0,
        a1: -1.990_047_454_833_98,
        a2: 0.990_072_250_366_21)

    // ---- true peak -------------------------------------------------------

    /// Taps per phase of the interpolating FIR.
    private static let peakTaps = 12
    private static let peakPhases = 4

    /// Annex 2, § 3: "One set of filter coefficients (for the order 48,
    /// 4-phase, FIR interpolating) that would satisfy the requirements would
    /// be as follows", transcribed COLUMN BY COLUMN from the standard's own
    /// table — phase 0 first, tap 0 first — so it can be read back against
    /// the printed page a row at a time.
    ///
    /// Phase 3 is phase 0 reversed and phase 2 is phase 1 reversed, which is
    /// the linear-phase symmetry a correct transcription has and a mistyped
    /// one does not; the file's header records the DC gains the four phases
    /// actually have, which is the check that is NOT satisfied and is a
    /// property of the standard's set rather than of this copy of it.
    ///
    /// The standard's first processing step, a 12.04 dB attenuation, is
    /// omitted on the standard's own instruction: "This step is not necessary
    /// if the calculations are performed in floating point." So is the
    /// matching amplification, which is what it was for.
    private static let peakFilter: [[Double]] = [
        [
            0.001_708_984_375_0, 0.010_986_328_125_0, -0.019_653_320_312_5,
            0.033_203_125_000_0, -0.059_448_242_187_5, 0.137_329_101_562_5,
            0.972_167_968_750_0, -0.102_294_921_875_0, 0.047_607_421_875_0,
            -0.026_611_328_125_0, 0.014_892_578_125_0, -0.008_300_781_250_0,
        ],
        [
            -0.029_174_804_687_5, 0.029_296_875_000_0, -0.051_757_812_500_0,
            0.089_111_328_125_0, -0.166_503_906_250_0, 0.465_087_890_625_0,
            0.779_785_156_250_0, -0.200_317_382_812_5, 0.101_562_500_000_0,
            -0.058_227_539_062_5, 0.033_081_054_687_5, -0.018_920_898_437_5,
        ],
        [
            -0.018_920_898_437_5, 0.033_081_054_687_5, -0.058_227_539_062_5,
            0.101_562_500_000_0, -0.200_317_382_812_5, 0.779_785_156_250_0,
            0.465_087_890_625_0, -0.166_503_906_250_0, 0.089_111_328_125_0,
            -0.051_757_812_500_0, 0.029_296_875_000_0, -0.029_174_804_687_5,
        ],
        [
            -0.008_300_781_250_0, 0.014_892_578_125_0, -0.026_611_328_125_0,
            0.047_607_421_875_0, -0.102_294_921_875_0, 0.972_167_968_750_0,
            0.137_329_101_562_5, -0.059_448_242_187_5, 0.033_203_125_000_0,
            -0.019_653_320_312_5, 0.010_986_328_125_0, 0.001_708_984_375_0,
        ],
    ]

    // ---- shape -----------------------------------------------------------

    private let channelCount: Int
    /// Frames in one 100 ms sub-block, and the largest chunk `process`
    /// handles: a chunk never straddles a sub-block boundary, which is what
    /// lets one accumulator serve every channel.
    private let hopFrames: Int
    private let blockFrames: Int

    /// One channel's samples for the current chunk, with the previous
    /// chunk's last 11 frames in front of them — the history the
    /// interpolating FIR needs across a buffer edge, and the reason a
    /// per-buffer implementation misses every inter-sample peak that
    /// straddles one (buffer edges arrive about a thousand times a minute).
    private let channelBuffer: UnsafeMutablePointer<Double>
    /// One phase's interpolated output for the current chunk.
    private let phaseBuffer: UnsafeMutablePointer<Double>
    /// `peakTaps − 1` raw samples per channel, carried between chunks.
    private let peakHistory: UnsafeMutablePointer<Double>
    /// Four coefficients per phase, REVERSED, because `vDSP_convD` computes
    /// a correlation (`C[n] = Σ A[n+p]·F[p]`) and a filter is the same sum
    /// with the taps the other way round. Derived here rather than typed
    /// again, so the literal above stays the only transcription.
    private let peakCoefficients: UnsafeMutablePointer<Double>
    /// Two sections of `x[n−1], x[n−2], y[n−1], y[n−2]`, per channel.
    private let filterState: UnsafeMutablePointer<Double>
    /// Int16 arrives from the fallback decode; the converted floats land
    /// here. `nil` until something asks, since the float path never does.
    private var int16Scratch: UnsafeMutablePointer<Float>?
    private var int16Capacity = 0

    /// Σ over channels of Σ y² for the sub-block being filled.
    private var subBlockSum: Double = 0
    private var subBlockFilled = 0
    /// The last four sub-block sums, oldest overwritten.
    private var ring: [Double]
    private var ringWrites = 0
    /// One `Σᵢ Gᵢ·zᵢ` per completed 400 ms block. 100 ms apart, so ten a
    /// second — 36 000 doubles for an hour of programme, which is why the
    /// two-sweep gating can keep them all.
    private var blocks: [Double] = []

    private var truePeakLinear: Double = 0
    private var samplePeakLinear: Double = 0

    /// nil for a rate the coefficients are not published at, or a channel
    /// count this build cannot weight.
    ///
    /// **Both refusals are assertions, not conveniences.** The K-weighting
    /// table is 48 kHz only, and filtering at another rate would answer a
    /// number that looks right and is not. And BS.1770-4's Table 3 weights
    /// the surround channels 1.41 and excludes the LFE, which needs a
    /// channel LAYOUT this meter is not handed; mono and stereo are the two
    /// cases whose weights are all 1.0 and therefore need no layout, and the
    /// export mix is stereo by `ExportWriter.decodedAudioSettings`. A
    /// surround measurement is a feature, not a widening of this guard.
    init?(sampleRate: Double, channelCount: Int) {
        guard sampleRate == Self.requiredSampleRate, (1...2).contains(channelCount) else {
            return nil
        }
        self.channelCount = channelCount
        hopFrames = Int((sampleRate * Self.hopSeconds).rounded())
        blockFrames = hopFrames * Self.subBlocksPerBlock
        guard hopFrames > Self.peakTaps else { return nil }

        let taps = Self.peakTaps
        channelBuffer = .allocate(capacity: hopFrames + taps - 1)
        channelBuffer.initialize(repeating: 0, count: hopFrames + taps - 1)
        phaseBuffer = .allocate(capacity: hopFrames)
        phaseBuffer.initialize(repeating: 0, count: hopFrames)
        peakHistory = .allocate(capacity: channelCount * (taps - 1))
        peakHistory.initialize(repeating: 0, count: channelCount * (taps - 1))
        peakCoefficients = .allocate(capacity: Self.peakPhases * taps)
        peakCoefficients.initialize(repeating: 0, count: Self.peakPhases * taps)
        for (index, phase) in Self.peakFilter.enumerated() {
            for (tap, value) in phase.reversed().enumerated() {
                peakCoefficients[index * taps + tap] = value
            }
        }
        filterState = .allocate(capacity: channelCount * 8)
        filterState.initialize(repeating: 0, count: channelCount * 8)
        ring = Array(repeating: 0, count: Self.subBlocksPerBlock)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("LoudnessMeter does not support NSCoder")
    }

    deinit {
        channelBuffer.deallocate()
        phaseBuffer.deallocate()
        peakHistory.deallocate()
        peakCoefficients.deallocate()
        filterState.deallocate()
        int16Scratch?.deallocate()
    }

    // MARK: - Feeding

    /// `frames` interleaved frames of 32-bit float, in programme order.
    func feed(_ samples: UnsafePointer<Float>, frames: Int) {
        var offset = 0
        while offset < frames {
            // Never across a sub-block boundary, and never more than one
            // sub-block: the accumulator then belongs to exactly one
            // sub-block for the whole chunk, whichever channel is being
            // walked.
            let take = Swift.min(hopFrames - subBlockFilled, frames - offset)
            process(samples + offset * channelCount, frames: take)
            offset += take
        }
    }

    /// The same, for the 16-bit fallback decode: `AVAssetReaderAudioMixOutput`
    /// is asked for float first and this is what a refusal falls back to
    /// (`Exporter.measureAudioSettings`). Scaled by 1/32768 so full scale is
    /// 1.0, which is what every threshold above is expressed in.
    func feedInt16(_ samples: UnsafePointer<Int16>, frames: Int) {
        let count = frames * channelCount
        guard count > 0 else { return }
        if int16Capacity < count {
            int16Scratch?.deallocate()
            int16Scratch = .allocate(capacity: count)
            int16Capacity = count
        }
        guard let scratch = int16Scratch else { return }
        var scale = Float(1.0 / 32768.0)
        vDSP_vflt16(samples, 1, scratch, 1, vDSP_Length(count))
        vDSP_vsmul(scratch, 1, &scale, scratch, 1, vDSP_Length(count))
        feed(scratch, frames: frames)
    }

    /// One chunk, wholly inside one sub-block.
    private func process(_ samples: UnsafePointer<Float>, frames: Int) {
        guard frames > 0 else { return }
        let taps = Self.peakTaps
        let history = taps - 1
        let stride = vDSP_Stride(channelCount)

        var chunkPeak: Float = 0
        vDSP_maxmgv(samples, 1, &chunkPeak, vDSP_Length(frames * channelCount))
        samplePeakLinear = Swift.max(samplePeakLinear, Double(chunkPeak))

        for channel in 0..<channelCount {
            // The channel's history, then its new samples: one contiguous
            // run of `history + frames` doubles, which is exactly what both
            // the interpolator and the biquads want.
            channelBuffer.update(from: peakHistory + channel * history, count: history)
            vDSP_vspdp(
                samples + channel, stride, channelBuffer + history, 1, vDSP_Length(frames))

            // True peak, on the UNWEIGHTED samples. Feeding K-weighted ones
            // here is an easy wiring mistake and reads up to 4 dB high on
            // bright material.
            for phase in 0..<Self.peakPhases {
                vDSP_convD(
                    channelBuffer, 1, peakCoefficients + phase * taps, 1, phaseBuffer, 1,
                    vDSP_Length(frames), vDSP_Length(taps))
                var peak: Double = 0
                vDSP_maxmgvD(phaseBuffer, 1, &peak, vDSP_Length(frames))
                truePeakLinear = Swift.max(truePeakLinear, peak)
            }

            // Before the filtering, which overwrites the same run: the last
            // `history` RAW samples are the next chunk's history.
            (peakHistory + channel * history).update(
                from: channelBuffer + frames, count: history)

            weight(channelBuffer + history, frames: frames, channel: channel)
            var sum: Double = 0
            vDSP_svesqD(channelBuffer + history, 1, &sum, vDSP_Length(frames))
            // Table 3's Gᵢ is 1.0 for left, right and centre, so the sum over
            // channels needs no weight at all here; `init` is where the
            // channel counts that would need one are refused.
            subBlockSum += sum
        }

        subBlockFilled += frames
        if subBlockFilled >= hopFrames { closeSubBlock() }
    }

    /// The two-stage K-weighting, in place, with this channel's state.
    private func weight(_ samples: UnsafeMutablePointer<Double>, frames: Int, channel: Int) {
        let base = filterState + channel * 8
        for (index, section) in [Self.stage1, Self.stage2].enumerated() {
            let state = base + index * 4
            var x1 = state[0], x2 = state[1], y1 = state[2], y2 = state[3]
            for n in 0..<frames {
                let x = samples[n]
                let y = section.b0 * x + section.b1 * x1 + section.b2 * x2
                    - section.a1 * y1 - section.a2 * y2
                x2 = x1
                x1 = x
                y2 = y1
                y1 = y
                samples[n] = y
            }
            state[0] = x1
            state[1] = x2
            state[2] = y1
            state[3] = y2
        }
    }

    private func closeSubBlock() {
        ring[ringWrites % Self.subBlocksPerBlock] = subBlockSum
        ringWrites += 1
        subBlockSum = 0
        subBlockFilled = 0
        guard ringWrites >= Self.subBlocksPerBlock else { return }
        blocks.append(ring.reduce(0, +) / Double(blockFrames))
    }

    // MARK: - The answer

    /// The gated integrated loudness and the true peak.
    ///
    /// A trailing partial block is discarded, which the standard requires and
    /// which means a programme shorter than 400 ms has no integrated loudness
    /// at all.
    ///
    /// **A non-finite sample is not defended against here**, and what it does
    /// is worth knowing before someone reads a strange number as a bug in the
    /// filter: a NaN is dropped by both peak accumulators (`Swift.max` keeps
    /// the accumulator when the new value is NaN) but poisons the biquad
    /// state, so every later block is NaN and is dropped by `integrated`'s
    /// `$0 > 0`, leaving the integrated figure that of the programme up to
    /// that sample; an infinity survives into `truePeakDBTP` as +∞. Neither
    /// is silently normalised, and neither can push a file up:
    /// `ExportLoudness.resolve` reads a non-finite peak as NO headroom, and
    /// `summary` says the peak could not be measured rather than calling the
    /// programme silent.
    func finish() -> LoudnessReport {
        let peak = Swift.max(truePeakLinear, samplePeakLinear)
        return LoudnessReport(
            integratedLUFS: integrated(),
            truePeakDBTP: Self.decibels(peak),
            samplePeakDBFS: Self.decibels(samplePeakLinear))
    }

    /// BS.1770-4 equations (5)–(7): the absolute gate, then the relative one,
    /// applied ONCE.
    ///
    /// The mean is over the LINEAR mean squares, never over the block
    /// loudnesses. Both gates are expressed in dB, which invites averaging
    /// dB; the gates only SELECT blocks, and the answer is the loudness of
    /// the survivors' linear mean.
    private func integrated() -> Double? {
        let gated = blocks.filter { $0 > 0 && Self.loudness($0) > Self.absoluteGate }
        guard !gated.isEmpty else { return nil }
        let threshold = Self.loudness(gated.reduce(0, +) / Double(gated.count))
            + Self.relativeGate
        let kept = gated.filter { Self.loudness($0) > threshold }
        guard !kept.isEmpty else { return nil }
        return Self.loudness(kept.reduce(0, +) / Double(kept.count))
    }

    /// A weighted mean square as a loudness, BS.1770-4 equation (2).
    private static func loudness(_ meanSquare: Double) -> Double {
        guard meanSquare > 0 else { return -.infinity }
        return offset + 10 * log10(meanSquare)
    }

    private static func decibels(_ linear: Double) -> Double {
        linear > 0 ? 20 * log10(linear) : -.infinity
    }
}
