import Foundation

/// The clip's compressor at block rate (spec §11 AU-62, AU-64 (h)): what its
/// 10 ms steps' energies and true peaks become through `CompressorProps`,
/// read off the loudness cache (`ClipLoudness.Reading`) without running the
/// stage — `AudioLimiterModel`'s shape, one stage earlier. Enhance Voice sets
/// its compressor's makeup from it (`makeupDB`, AU-62), and nothing else
/// reads it: the volume is solved on the rendered clip (AU-64).
///
/// **The model.** Per step, in played order: a follower that takes the
/// step's peak at once and falls by the release's pole over the step,
/// `lvl = max(p, lvl·e^(−0.01/max(release, 0.01)))` (the stage's follower
/// falls no faster than 10 ms); the target reduction `(20·log10 lvl −
/// threshold)(1 − 1/ratio)` above the threshold, else 0; the reduction moving
/// `red += (target − red)(1 − e^(−0.01/τ))`, τ the attack while the target
/// is above it and the release otherwise (τ 0 moves at once); and the gain
/// `10^((makeup − red)/20)` on each step's energy, squared, and its peak.
/// The settings are bounded as `AudioCompressorSettings` bounds them for the
/// stage. It is the stage's gain path (`AudioCompressorStage`) seen 10 ms at
/// a time; the audio probe's E2 checks the makeup it gives.
enum AudioDynamicsModel {
    /// A step's length in seconds: the loudness cache's 10 ms grid.
    static let stepSeconds = AudioLimiterModel.stepSeconds

    /// `steps` (energies) and `peaks` (linear true peaks) through
    /// `compressor`, in played order.
    static func compressed(steps: [Double], peaks: [Double], compressor: CompressorProps)
        -> (steps: [Double], peaks: [Double])
    {
        let s = settings(compressor)
        let threshold = pow(10, s.thresholdDB / 20)
        let slope = s.ratio > 1 ? 1 - 1 / s.ratio : 0
        let fall = exp(-stepSeconds / max(s.releaseSeconds, stepSeconds))
        let attack = pole(s.attackSeconds)
        let release = pole(s.releaseSeconds)
        var level = 0.0
        var reduction = 0.0
        var outSteps: [Double] = []
        var outPeaks: [Double] = []
        outSteps.reserveCapacity(steps.count)
        outPeaks.reserveCapacity(steps.count)
        for (index, energy) in steps.enumerated() {
            let peak = index < peaks.count ? peaks[index] : 0
            level = max(peak, level * fall)
            let target = level > threshold && slope > 0
                ? (20 * log10(level) - s.thresholdDB) * slope : 0
            reduction += (target - reduction) * (target > reduction ? attack : release)
            let gain = pow(10, (s.makeupDB - reduction) / 20)
            outSteps.append(energy * gain * gain)
            outPeaks.append(peak * gain)
        }
        return (outSteps, outPeaks)
    }

    /// The makeup that gives back what `compressor` takes from `reading`'s
    /// integrated loudness (AU-62): L less the model's loudness at makeup 0,
    /// rounded to a whole dB and held to 0…24 (the stage's range). 0 for a
    /// reading with no loudness.
    static func makeupDB(_ reading: ClipLoudness.Reading, compressor: CompressorProps) -> Double {
        guard let lufs = reading.lufs else { return 0 }
        var flat = compressor
        flat.makeupDb = 0
        let squeezed = compressed(
            steps: reading.steps, peaks: reading.stepPeaks, compressor: flat)
        guard let after = StepLoudness.integrated(squeezed.steps) else { return 0 }
        let lost = (lufs - after).rounded()
        return lost.isFinite ? min(max(lost, 0), 24) : 0
    }

    /// The stage's own bounds on a model value (`AudioCompressorSettings`).
    private static func settings(_ c: CompressorProps) -> AudioCompressorSettings {
        AudioCompressorSettings(
            thresholdDB: c.thresholdDb, ratio: c.ratio,
            attackSeconds: Double(c.attack) / Double(ReelTime.perSecond),
            releaseSeconds: Double(c.release) / Double(ReelTime.perSecond), makeupDB: c.makeupDb)
    }

    /// One step's share of a one-pole over `seconds`; 1 (at once) at 0.
    private static func pole(_ seconds: Double) -> Double {
        seconds > 0 ? 1 - exp(-stepSeconds / seconds) : 1
    }
}
