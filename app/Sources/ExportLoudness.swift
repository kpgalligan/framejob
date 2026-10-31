import Foundation

// The arithmetic that turns a loudness measurement into an export gain: a pure move out of
// `Loudness.swift` (road map "audio" AP0's toll T3), which keeps the BS.1770-4 meter and the
// `LoudnessReport` it answers.

// MARK: - What an export did about it

/// A measurement, the target it was measured against, and the gain that
/// follows — the value both consumers of an export read (the progress
/// sheet's final line and the `export` tool's result).
///
/// **The gain is applied under a master limiter** (spec §11 AU-27, AU-28):
/// every export with sound runs `ExportAudioMaster` — the gain, then
/// `AudioLimiterStage` at the export's ceiling — so the gain that reaches a
/// target is solved through `AudioLimiterModel` over pass one's 10 ms steps,
/// the model the clip limiter's Normalize already uses (AU-24). A scalar gain
/// shifts the true peak by itself, and the master holds what passes the
/// ceiling there, so the file's true peak is `min(measured + gain, ceiling)`
/// and what the master took off is `limitedDB`. Nothing clips any more.
///
/// This file stays free of AVFoundation and AppKit: `phase5_chrome.py` §9
/// compiles it with `Loudness.swift`, `StepLoudness.swift` and
/// `AudioLimiterModel.swift` alone.
struct ExportLoudness: Equatable {
    /// What the mix measured, before any gain.
    let measured: LoudnessReport
    /// The integrated target that was asked for, or nil when the export was
    /// not normalised at all and this is a readout.
    let target: Double?
    /// The master limiter's true-peak ceiling, dBTP.
    let ceiling: Double
    /// The gain that was applied, in dB. Quantised (see `gainStepDB`), and
    /// exactly 0 when nothing was applied.
    let gainDB: Double
    /// What the file holds, LUFS: the model's figure at `gainDB` under the
    /// master (AU-28), else the measurement shifted by the gain; nil when
    /// gated out.
    let integratedLUFS: Double?
    /// True when the +40 dB cap, not the target, decided the gain — the case
    /// worth reporting, because the file will then be quieter than asked.
    let cappedByGain: Bool

    /// The master's ceiling when a caller names none: AU-4's −1 dBTP, for
    /// normalised and un-normalised exports alike (AU-27).
    static let defaultCeiling: Double = -1

    /// The most gain a target may ask for, dB.
    static let maxGainDB: Double = 40

    /// The master limiter's release, seconds (AU-27): `ExportAudioMaster`'s,
    /// spelled here so the model and the stage read one number.
    static let masterReleaseSeconds = 0.1

    /// The fewest 10 ms steps the model is run over: one 400 ms gating block.
    private static let modelSteps = 40

    /// The grid the applied gain is rounded to, in dB — to NEAREST (AU-28):
    /// the limiter holds the ceiling, so no rounding has to lean toward it.
    ///
    /// Not cosmetic. AVFoundation's mix is not bit-deterministic near a duck
    /// ramp edge (CLAUDE.md records 38 samples of one 16-bit LSB), which
    /// moves the measured loudness by something like 10⁻⁵ LU — irrelevant to
    /// a ±0.5 LU target, but enough that a raw `Double` gain would differ in
    /// its last bits between two runs and round the ENTIRE file's samples
    /// differently. At 0.01 dB the two runs pick the same gain, so two
    /// normalised exports of one project compare, and "−14.0 LUFS"
    /// reproduces.
    static let gainStepDB: Double = 0.01

    /// The linear multiplier the master applies to the float mix.
    var linearGain: Double { pow(10, gainDB / 20) }

    /// True when the master has no gain to apply. It still limits and
    /// quantises.
    var isUnity: Bool { gainDB == 0 }

    /// The file's true peak: the measurement shifted by the gain, held at the
    /// ceiling. A non-finite measurement passes through unclamped, so the
    /// summary can still say "Silent" (−∞) or that the peak could not be
    /// measured (+∞).
    var truePeakDBTP: Double {
        guard measured.truePeakDBTP.isFinite else { return measured.truePeakDBTP }
        return min(measured.truePeakDBTP + gainDB, ceiling)
    }

    /// How far the master turned the hottest peak down, dB: the shifted
    /// measurement's excess over the ceiling, 0 when under it or not finite.
    var limitedDB: Double {
        guard measured.truePeakDBTP.isFinite else { return 0 }
        return max(0, measured.truePeakDBTP + gainDB - ceiling)
    }

    /// The gain a `target` asks for over `measured` and its 10 ms `steps`
    /// (energies) and `peaks` (true peaks, linear) under the master's
    /// `ceiling` (spec §11 AU-28).
    ///
    /// `target` nil is "do not normalise": the measurement is still carried,
    /// and the file's loudness is still the model's, because the master
    /// limits an un-normalised mix that passes the ceiling too.
    ///
    /// A peak that is not a finite number keeps the old handling: no model,
    /// no gain, the measured loudness. −∞ is digital silence; +∞ is float
    /// source media holding a non-finite sample, and "the peak cannot be
    /// measured" has to mean "do not push it up".
    static func resolve(
        measured: LoudnessReport, steps: [Double], peaks: [Double], target: Double?,
        ceiling: Double?
    ) -> ExportLoudness {
        let ceiling = ceiling ?? defaultCeiling
        guard measured.truePeakDBTP.isFinite else {
            return ExportLoudness(
                measured: measured, target: target, ceiling: ceiling, gainDB: 0,
                integratedLUFS: measured.integratedLUFS, cappedByGain: false)
        }
        let linearCeiling = pow(10, ceiling / 20)
        let modelled = steps.count >= modelSteps && StepLoudness.integrated(steps) != nil
        var gainDB = 0.0
        var capped = false
        if let target, let integrated = measured.integratedLUFS {
            let wanted: Double
            if modelled {
                let maxGain = pow(10, maxGainDB / 20)
                let gain = AudioLimiterModel.gain(
                    reaching: target, steps: steps, peaks: peaks, ceiling: linearCeiling,
                    releaseSeconds: masterReleaseSeconds, maxGain: maxGain)
                capped = gain >= maxGain
                wanted = 20 * log10(gain)
            } else {
                // Under one gating block, or no float read: the unlimited gain.
                wanted = target - integrated
                capped = wanted > maxGainDB
            }
            let rounded = min((wanted / gainStepDB).rounded() * gainStepDB, maxGainDB)
            gainDB = rounded.isFinite ? rounded : 0
        }
        let shifted = measured.integratedLUFS.map { $0 + gainDB }
        let lufs = modelled
            ? AudioLimiterModel.integrated(
                steps: steps, peaks: peaks, gain: pow(10, gainDB / 20), ceiling: linearCeiling,
                releaseSeconds: masterReleaseSeconds) ?? shifted
            : shifted
        return ExportLoudness(
            measured: measured, target: target, ceiling: ceiling, gainDB: gainDB,
            integratedLUFS: lufs, cappedByGain: capped)
    }

    /// The one line every export reports: `"Peak −1.0 dBTP · −16.0 LUFS"`, with
    /// `" · peaks limited by 8.6 dB"` when the master took 0.05 dB or more off.
    var summary: String {
        guard truePeakDBTP.isFinite else {
            // −∞ is digital silence. Anything else non-finite is a mix
            // carrying a non-finite sample, and calling THAT silent is the
            // loudest lie this line could tell.
            return truePeakDBTP == -.infinity
                ? "Silent" : "Peak not measurable (a non-finite sample in the mix)"
        }
        let peak = "Peak \(Self.decibels(truePeakDBTP)) dBTP"
        var measurement: String
        if let integrated = integratedLUFS {
            measurement = "\(peak) · \(Self.decibels(integrated)) LUFS"
        } else {
            // A programme shorter than one 400 ms gating block, or one whose
            // every block fell under Γa. It has a peak and no loudness, and
            // saying which is better than printing −∞.
            measurement = "\(peak) · loudness not measurable"
        }
        if limitedDB >= 0.05 {
            measurement += " · peaks limited by \(Self.decibels(limitedDB)) dB"
        }
        return measurement
    }

    /// One decimal, with the typographic minus the rest of the chrome uses.
    private static func decibels(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: "-", with: "−")
    }
}
