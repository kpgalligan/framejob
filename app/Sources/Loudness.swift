import Accelerate
import Foundation

/// ITU-R BS.1770-4 integrated loudness and true peak, plus the arithmetic
/// that turns a measurement into an export gain (road map 2, phase 5).
///
/// **Why this file has no AVFoundation in it.** `AudioDSP.swift`'s rule
/// applied to measurement: plain buffers in, a value type out, no player, no
/// reader, no tap. `Exporter.measureLoudness` is the one place that knows
/// where the samples come from, which is what lets the meter be exercised
/// against synthesized tones — the EBU Tech 3341 cases are *specified
/// signals*, so a check needs no fixture file at all.
///
/// **What the standard asks for, and where each number comes from.** Every
/// constant below is quoted from Recommendation ITU-R BS.1770-4 (10/2015)
/// with its table, and the coefficients are for a **48 kHz** sample rate —
/// the only rate the standard publishes them at, and the rate
/// `ExportWriter.decodedAudioSettings` pins the export mix to. That is why
/// `LoudnessMeter.init` REFUSES any other rate rather than filtering with
/// the wrong numbers: `AudioTapContext.prepare` is the precedent for
/// checking a format instead of assuming it.
///
/// The measurement chain is:
///
/// 1. **K-weighting** — two biquads in series (Tables 1 and 2), run
///    CONTINUOUSLY over the whole programme, never reset per block.
/// 2. **Gating blocks** — 400 ms at 75 % overlap, i.e. a new block every
///    100 ms, each block's mean square `z` summed over channels with the
///    Table 3 weights.
/// 3. **Two gates** — the absolute Γa = −70 LUFS, then the relative
///    Γr = (the gated mean's loudness) − 10 LU, applied ONCE.
/// 4. **True peak** — the UNWEIGHTED signal through the standard's 4-phase
///    12-tap interpolating FIR (Annex 2, § 3), taking the largest magnitude
///    over every phase and every channel.
///
/// **The self-checks that prove the coefficients were typed correctly**, all
/// measured against this implementation while it was written, over
/// synthesized tones fed in 1 013-frame pieces so that buffer edges are
/// exercised too:
///
/// | check | the standard says | measured here |
/// |---|---|---|
/// | K-weighting gain at 1 kHz | +0.6977 dB | **+0.6977 dB** |
/// | 0 dBFS 997 Hz sine in ONE channel of a stereo pair | −3.01 LKFS | −3.010 LUFS |
/// | the same sine in BOTH channels | 0.00 LKFS | 0.000 LUFS |
/// | EBU Tech 3341 case 1 (20 s stereo 1 kHz at 10^(−23/20)) | −23.0 LUFS | −22.993 LUFS |
/// | case 3, the relative gate (10 s @ −36, 60 s @ −23, 10 s @ −36) | −23.0 LUFS | −23.014 LUFS |
/// | case 4, the absolute gate (10 s @ −72, 60 s @ −23, 10 s @ −72) | −23.0 LUFS | −23.015 LUFS |
/// | case 5 (20 s @ −26, 20.1 s @ −20, 20 s @ −26) | −23.0 LUFS | −22.979 LUFS |
///
/// The first row is the one that catches a mistyped digit: the +0.6977 dB is
/// exactly what the standard's −0.691 offset exists to cancel (its Note 1
/// says so), so a wrong coefficient moves it and every row under it. The
/// second is the standard's own calibration sentence, quoted from § 2.1 of
/// Annex 1, and it is the tighter check of the two — it is stated at 997 Hz,
/// which is the frequency the offset cancels EXACTLY. The Tech 3341 cases
/// are all built on a 1 kHz tone, where the weighting is +0.6977 dB against
/// an offset of 0.691, so a pure 1 kHz fixture reads 0.007 LU high by
/// construction; that is the whole of the residual above, and it is not
/// error. The gating cases sit a further 0.02 LU away because their −36 and
/// −72 flanks contribute the blocks that straddle each transition.
///
/// **What this meter can and cannot promise.** Integrated loudness has no
/// slop: the rows above are within 0.03 LU of a number the standard states
/// to one decimal. True peak does — a 4× oversampler can miss an
/// inter-sample peak that falls between two of its own output instants, and
/// the standard's own Appendix 1 puts that under-read at up to 0.554 dB for
/// content at 0.45 × fs. Measured here on 45°-phase sines at amplitude 0.5
/// (analytic true peak −6.021 dBFS): 1 kHz reads −6.014, 4 kHz −5.821 and
/// fs/4 −5.938 — i.e. this meter reads at most 0.2 dB HIGH and never low.
/// `ffmpeg -af ebur128=peak=true` reads the same three tones −6.0, −5.7 and
/// −5.4, so two conforming meters are half a decibel apart at fs/4 and this
/// one is the closer of the two to the analytic answer. So "true peak never
/// exceeds −1 dBTP" is a claim about THIS meter, a proof that compares it to
/// another needs about ±0.7 dB near fs/4 (±0.1 dB against an analytic tone),
/// and the export sheet's copy says the ceiling is measured rather than
/// enforced by a limiter.
///
/// **A property of the standard's own filter, measured and worth knowing
/// before someone "fixes" the table.** The four phases of the interpolating
/// FIR do NOT have equal DC gain: their coefficients sum to 1.001587,
/// 0.973022, 0.973022 and 1.001587 respectively — 0.25 dB of ripple between
/// phases, and 0.111 dB shy of unity overall. That is what the standard
/// prints (it offers the table as "one set of filter coefficients … that
/// would satisfy the requirements", not as the only one), and it is
/// transcribed here verbatim rather than normalised, because a table quoted
/// from its source can be checked against that source and a table adjusted
/// by hand cannot. The consequence is bounded and handled: an inter-sample
/// peak that lands on phase 1 or 2 can read up to 0.24 dB low, and a peak
/// that lands ON a sample would read 0.11 dB low, which is why
/// [`LoudnessReport.truePeakDBTP`] is never allowed below the sample peak —
/// the reconstructed waveform passes exactly through every sample, so the
/// true peak is at least the sample peak by definition rather than by
/// measurement.

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

// MARK: - What an export did about it

/// A measurement, the target it was measured against, and the gain that
/// follows — the value both consumers of an export read (the progress
/// sheet's final line and the `export` tool's result).
///
/// **Gain only, no limiter.** That is what makes every number here
/// arithmetic instead of a second measurement: a scalar gain shifts
/// integrated loudness and true peak by exactly itself, so "measured plus
/// the gain" IS what the file holds. Add a limiter, a soft clip or a
/// fader-shaped ramp and the reported figure becomes a guess.
///
/// **With one exception, and it is not one this file chose:** a mix that was
/// already past full scale is clipped by the WRITE pass's Int16 decode before
/// the gain is applied to it, so the file holds a signal the measurement pass
/// never saw. `mixClipped` is that case, it is the only one, and `summary`
/// names it rather than letting the figures pass as the file's.
struct ExportLoudness: Equatable {
    /// What the mix measured, before any gain.
    let measured: LoudnessReport
    /// The integrated target that was asked for, or nil when the export was
    /// not normalised at all and this is a readout.
    let target: Double?
    /// The true-peak ceiling the gain was capped against.
    let ceiling: Double
    /// The gain that was applied, in dB. Quantised (see `gainStepDB`), and
    /// exactly 0 when nothing was applied.
    let gainDB: Double
    /// True when the ceiling, not the target, decided the gain — the case
    /// worth reporting, because the file will then be quieter than asked.
    let cappedByPeak: Bool

    /// The ceiling assumed when a caller asks for a target and names none.
    /// 0 dBTP is not a loudness opinion, it is "do not push the programme
    /// past full scale", which is true of every file: the export sheet always
    /// sends `peakCeilingDBTP`, and only a script can reach this default.
    static let fullScaleCeiling: Double = 0

    /// The grid the applied gain is rounded to, in dB.
    ///
    /// Not cosmetic. AVFoundation's mix is not bit-deterministic near a duck
    /// ramp edge (CLAUDE.md records 38 samples of one 16-bit LSB), which
    /// moves the measured loudness by something like 10⁻⁵ LU — irrelevant to
    /// a ±0.5 LU target, but enough that a raw `Double` gain would differ in
    /// its last bits between two runs and round the ENTIRE file's 16-bit
    /// samples differently. At 0.01 dB the two runs pick the same gain, so
    /// two normalised exports of one project compare, and "−14.0 LUFS"
    /// reproduces.
    static let gainStepDB: Double = 0.01

    /// The linear multiplier `ExportWriter` applies to the decoded samples.
    var linearGain: Double { pow(10, gainDB / 20) }

    /// True when the writer has nothing to do — which is what keeps an
    /// un-normalised export on exactly the code path it had before this
    /// phase existed.
    var isUnity: Bool { gainDB == 0 }

    /// What the file holds: the measurement shifted by the gain — unless
    /// `mixClipped`, which is the one case where it does not.
    var integratedLUFS: Double? { measured.integratedLUFS.map { $0 + gainDB } }
    var truePeakDBTP: Double { measured.truePeakDBTP + gainDB }

    /// True when the mix passed full scale BEFORE any gain — the one case
    /// where the two lines above describe the MIX and not the file.
    ///
    /// The measurement pass reads 32-bit float on purpose (`ExporterLoudness`
    /// says why: a mix hotter than full scale is exactly the material
    /// normalisation exists for, and an Int16 decode would pin its true peak
    /// at 0 dBTP by the decode rather than by the signal), while the write
    /// pass decodes that same mix to Int16 — which SATURATES — and applies
    /// the gain to what comes out. So where the mix passes full scale the two
    /// passes see different signals: the file holds the mix hard-clipped and
    /// then turned down, whose true peak and integrated loudness are both a
    /// decibel or more away from what was measured, and no arithmetic here
    /// can carry one into the other, because a clip is not a gain.
    ///
    /// Neither pass can be moved without giving something up that was decided
    /// (measure in Int16 and the over-scale peak is lost; write in float and
    /// the format description the encoder consumes changes, which changes
    /// every existing export's bytes), so what is fixed here is the REPORT:
    /// `summary` names the overshoot and says whose numbers these are. What
    /// must not survive is publishing the mix's figures as the file's in
    /// silence.
    var mixClipped: Bool { measured.samplePeakDBFS > 0 }

    /// The gain a `target` and a `ceiling` ask for over `measured`.
    ///
    /// `target` nil is "do not normalise": the measurement is still carried,
    /// because the road map wants every export's final line to report what
    /// the file actually holds, normalised or not.
    static func resolve(
        measured: LoudnessReport, target: Double?, ceiling: Double?
    ) -> ExportLoudness {
        let ceiling = ceiling ?? fullScaleCeiling
        guard let target = target, let integrated = measured.integratedLUFS else {
            return ExportLoudness(
                measured: measured, target: target, ceiling: ceiling, gainDB: 0,
                cappedByPeak: false)
        }
        let wanted = target - integrated
        // The cap is computed on TRUE peak rather than sample peak, and that
        // is what makes the write safe as well as honest: true peak is never
        // below sample peak, so a gain that keeps the true peak under the
        // ceiling keeps every 16-bit sample inside full scale, and the
        // saturation in `LoudnessInt16Gain` never has to fire.
        //
        // A peak that is not a finite number is NO headroom, which is the
        // safe answer and not the obvious one. −∞ cannot reach this line at
        // all — a nil `integratedLUFS` has already returned above, and a
        // programme with any block above Γa has a non-zero sample peak — so
        // the only value that gets here is a +∞ carried in from float source
        // media holding a non-finite sample, and "the peak cannot be
        // measured" has to mean "do not push it up". Infinite headroom would
        // mean the opposite: apply the whole requested boost and ignore the
        // ceiling.
        let headroom = measured.truePeakDBTP.isFinite ? ceiling - measured.truePeakDBTP : 0
        // The two are quantised DIFFERENTLY, because they mean different
        // things. `wanted` is a target and rounds to nearest: half a
        // hundredth of a decibel either way of a ±0.5 LU claim is nothing.
        // `headroom` is a CONSTRAINT — rounding it to nearest hands back up
        // to 0.005 dB of the attenuation the ceiling asked for, and a
        // ceiling-capped export then reports, and holds, a true peak ABOVE
        // the ceiling it names about half the time (which is what the sheet's
        // "capped so its true peak stays under −1 dBTP" would then be
        // promising falsely). It rounds DOWN, toward more attenuation, so the
        // shifted true peak can only land at or under the ceiling.
        let quantised = Swift.min(
            (wanted / gainStepDB).rounded() * gainStepDB,
            (headroom / gainStepDB).rounded(.down) * gainStepDB)
        return ExportLoudness(
            measured: measured, target: target, ceiling: ceiling,
            gainDB: quantised.isFinite ? quantised : 0, cappedByPeak: headroom < wanted)
    }

    /// The one line every export reports: `"Peak −1.0 dBTP · −14.0 LUFS"`.
    var summary: String {
        guard truePeakDBTP.isFinite else {
            // −∞ is digital silence. Anything else non-finite is a mix
            // carrying a non-finite sample, and calling THAT silent is the
            // loudest lie this line could tell.
            return truePeakDBTP == -.infinity
                ? "Silent" : "Peak not measurable (a non-finite sample in the mix)"
        }
        let peak = "Peak \(Self.decibels(truePeakDBTP)) dBTP"
        let measurement: String
        if let integrated = integratedLUFS {
            measurement = "\(peak) · \(Self.decibels(integrated)) LUFS"
        } else {
            // A programme shorter than one 400 ms gating block, or one whose
            // every block fell under Γa. It has a peak and no loudness, and
            // saying which is better than printing −∞.
            measurement = "\(peak) · loudness not measurable"
        }
        guard mixClipped else { return measurement }
        // The figures are the mix's and the file's are worse, so the line
        // says which it is showing — in both consumers at once, since the
        // progress sheet's last line and the `export` tool's result are the
        // same string. `mixClipped` says why they differ at all.
        return "\(measurement) — measured on the mix, which clipped at +"
            + "\(Self.decibels(measured.samplePeakDBFS)) dBFS before it was written"
    }

    /// One decimal, with the typographic minus the rest of the chrome uses.
    private static func decibels(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: "-", with: "−")
    }
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

// MARK: - Applying a gain to 16-bit samples

/// Scales interleaved 16-bit samples by a gain, rounding and saturating.
///
/// The export writer reads the mix as 16-bit LPCM and hands 16-bit LPCM to
/// the encoder (`ExportWriter.decodedAudioSettings` is literally the same
/// dictionary on both sides), so a normalisation gain is applied in that
/// domain. Two things about that are worth stating rather than discovering:
///
/// - **It rounds, it does not truncate.** Truncation biases every sample
///   toward zero and shows up as DC on quiet material. (`vDSP_vfixr16`
///   rounds to the nearest, ties to even, which is the unbiased choice and
///   the one the machine's rounding mode already makes.)
/// - **It costs a fraction of a bit.** A −6 dB normalisation gives away one
///   bit of a 16-bit intermediate — quantisation noise at about −90 dBFS,
///   under the noise floor of anything that was recorded and below what the
///   AAC encoder downstream will resolve. A file that needed 40 dB of gain
///   would be a different conversation, and the true-peak cap is what stops
///   the gain going the other way and clipping.
///
/// Not on the audio render thread: this runs on the export's own audio pump
/// queue, so the scratch buffer may grow when a larger sample buffer arrives
/// (in practice once, on the first one).
final class LoudnessInt16Gain {
    private var floats: UnsafeMutablePointer<Float>?
    private var capacity = 0

    init() {}

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("LoudnessInt16Gain does not support NSCoder")
    }

    deinit { floats?.deallocate() }

    /// Multiplies `count` samples in place. Returns false only when the
    /// scratch could not be sized, which the caller reports as a failed
    /// write rather than silently appending ungained audio.
    @discardableResult
    func scale(_ samples: UnsafeMutablePointer<Int16>, count: Int, gain: Float) -> Bool {
        guard count > 0 else { return true }
        if capacity < count {
            floats?.deallocate()
            floats = .allocate(capacity: count)
            capacity = count
        }
        guard let floats = floats else { return false }
        var gain = gain
        var low = Float(Int16.min)
        var high = Float(Int16.max)
        let n = vDSP_Length(count)
        vDSP_vflt16(samples, 1, floats, 1, n)
        vDSP_vsmul(floats, 1, &gain, floats, 1, n)
        // Saturate before the conversion: `vDSP_vfixr16` wraps rather than
        // clamps, so an over-range sample would come back as its own
        // opposite — a click, not a clip.
        vDSP_vclip(floats, 1, &low, &high, floats, 1, n)
        vDSP_vfixr16(floats, 1, samples, 1, n)
        return true
    }
}
