import Foundation

/// The clip limiter at block rate (spec §11 AU-24): what a clip's integrated
/// loudness becomes at a gain when its limiter holds a ceiling, read off the
/// loudness cache's 10 ms steps (`ClipLoudness.Reading.steps`, `stepPeaks`)
/// without running the stage. Normalize's Loudness mode solves it for the
/// gain that reaches a target; the Volume section's At volume row reads it
/// while the clip's limiter is on (AU-26).
///
/// **The model.** Per step, in played order: the need
/// `min(1, ceiling / (peak · gain))`; an envelope that falls to a lower need
/// at once and rises toward a higher one by the release's one-pole over the
/// step, `env + (need − env)(1 − e^(−0.01/release))`; and the step's energy
/// times `gain² · env²`, gated by `StepLoudness.integrated`. It is the stage's
/// gain path (`AudioLimiterStage`) seen 10 ms at a time: the stage's hold and
/// box mean sit inside one step, and its release is the same pole. It reads
/// within 0.3 LU of the stage on the owner's recording (the limiter probe's
/// L8).
enum AudioLimiterModel {
    /// A step's length in seconds: the loudness cache's 10 ms grid.
    static let stepSeconds = 0.01

    /// The integrated loudness, LUFS, of `steps` (energies at gain 1, with
    /// their true peaks `peaks`, linear) at `gain` under a post-fader
    /// `ceiling` (linear) released over `releaseSeconds`. nil when gated
    /// out, or for fewer than one gating block.
    static func integrated(
        steps: [Double], peaks: [Double], gain: Double, ceiling: Double, releaseSeconds: Double
    ) -> Double? {
        guard gain > 0, gain.isFinite else { return nil }
        let rise = 1 - exp(-stepSeconds / max(releaseSeconds, 1e-6))
        var env = 1.0
        var limited: [Double] = []
        limited.reserveCapacity(steps.count)
        for (index, energy) in steps.enumerated() {
            let peak = index < peaks.count ? peaks[index] * gain : 0
            let need = peak > ceiling ? ceiling / peak : 1
            env = need < env ? need : env + (need - env) * rise
            limited.append(energy * gain * gain * env * env)
        }
        return StepLoudness.integrated(limited)
    }

    /// The gain that brings `steps` to `targetLUFS` under the limiter, found
    /// by bisection on its logarithm to 0.001 LU, never above `maxGain`.
    ///
    /// The limiter only ever lowers a step, so the gain that would reach the
    /// target unlimited is a lower bound: the search runs from it to
    /// `maxGain`. When that lower bound already reaches the target (nothing
    /// is limited there) it is the answer exactly; when even `maxGain` falls
    /// short, `maxGain` is.
    static func gain(
        reaching targetLUFS: Double, steps: [Double], peaks: [Double], ceiling: Double,
        releaseSeconds: Double, maxGain: Double
    ) -> Double {
        func loudness(_ gain: Double) -> Double {
            integrated(
                steps: steps, peaks: peaks, gain: gain, ceiling: ceiling,
                releaseSeconds: releaseSeconds) ?? -.infinity
        }
        guard let unlimited = StepLoudness.integrated(steps) else { return maxGain }
        var low = min(pow(10, (targetLUFS - unlimited) / 20), maxGain)
        if loudness(low) >= targetLUFS - tolerance { return low }
        var high = maxGain
        if loudness(high) < targetLUFS - tolerance { return high }
        for _ in 0..<200 {
            let middle = (low * high).squareRoot()
            let reached = loudness(middle)
            if abs(reached - targetLUFS) <= tolerance { return middle }
            if reached < targetLUFS { low = middle } else { high = middle }
            if high / low <= 1 + 1e-12 { break }
        }
        return high
    }

    /// The bisection's stop: within 0.001 LU of the target.
    static let tolerance = 0.001
}
