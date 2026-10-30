import Foundation

// The arithmetic that turns a loudness measurement into an export gain: a pure move out of
// `Loudness.swift` (road map "audio" AP0's toll T3), which keeps the BS.1770-4 meter and the
// `LoudnessReport` it answers.

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
/// **With one exception:** a mix past full scale written with NO gain is
/// clipped by the write pass's 16-bit decode, so the file holds a signal the
/// measurement never saw. `mixClipped` is that case, it is the only one, and
/// `summary` names it rather than letting the figures pass as the file's. A
/// gained export reads the same float mix the measurement read and is
/// quantised once, after the gain (spec §11 #86), so it is not clipped.
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

    /// True when the mix passed full scale and is written with NO gain — the
    /// one case where the two lines above describe the MIX and not the file.
    ///
    /// The measurement reads 32-bit float on purpose (`ExporterLoudness` says
    /// why), and so does the write pass whenever a gain applies (spec §11
    /// #86), so a gained export is the measured signal turned down. An
    /// export with no gain is written from the 16-bit decode, which
    /// SATURATES: for a mix past full scale the file holds it hard-clipped,
    /// and no arithmetic here can carry the measurement into that, because a
    /// clip is not a gain. The decode is kept for those exports because
    /// changing it would change every such file's bytes, so `summary` names
    /// the overshoot and says whose numbers these are.
    ///
    /// A gain of exactly 0 dB is `isUnity`, and the writer then applies none.
    var mixClipped: Bool { measured.samplePeakDBFS > 0 && isUnity }

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
        // ceiling keeps every 16-bit sample inside full scale, and the clip
        // in the writer's quantiser (`ExportAudioGain`) never has to fire.
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
