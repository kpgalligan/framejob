import Foundation

/// Enhance Voice's leveller rule (spec §11 AU-67): the speech's short-term
/// loudness range, and whether it turns the leveller on.
///
/// **The range** is measured pre-chain, like everything Enhance reads
/// (AU-61): the clip's 10 ms steps where the speech mask is true,
/// concatenated, in 3 s windows (`shortTermSteps`) at a 0.1 s hop
/// (`shortTermHopSteps`); each window's loudness is `StepLoudness.loudness`
/// of its mean energy. EBU Tech 3342's gating applies — absolute −70 LUFS,
/// then −20 LU under the energy mean of what passed — and the range is the
/// 95th percentile less the 10th, each linearly interpolated (numpy's
/// default). Under one window of speech there is none.
///
/// **The rule.** Over `levellerRangeLU` Enhance writes the leveller at its
/// defaults; at or under it, null; with no range the key is left out of the
/// edit. Each case has its sentence. A second press measures the same range,
/// so it writes the same value (AU-61's idempotence).
extension AudioEnhance {
    /// Over this range the leveller goes on.
    static let levellerRangeLU = 6.0
    /// A short-term window, 3 s of 10 ms steps.
    static let shortTermSteps = 300
    /// The windows' hop, 0.1 s.
    static let shortTermHopSteps = 10
    /// EBU Tech 3342's two gates, LUFS and LU.
    private static let rangeAbsoluteGate = -70.0
    private static let rangeRelativeGate = -20.0

    /// The speech's short-term loudness range in LU, from each step's energy
    /// and the speech mask; nil under `shortTermSteps` speech steps or when
    /// every window is gated out.
    static func speechRange(steps: [Double], speech: [Bool]) -> Double? {
        let count = min(steps.count, speech.count)
        var energies: [Double] = []
        energies.reserveCapacity(count)
        for k in 0..<count where speech[k] { energies.append(steps[k]) }
        guard energies.count >= shortTermSteps else { return nil }
        var windows: [Double] = []
        var sum = energies[0..<shortTermSteps].reduce(0, +)
        var start = 0
        while true {
            windows.append(sum / Double(shortTermSteps))
            let next = start + shortTermHopSteps
            guard next + shortTermSteps <= energies.count else { break }
            // Summed afresh at each hop: no running drift over a long clip.
            sum = energies[next..<(next + shortTermSteps)].reduce(0, +)
            start = next
        }
        let passed = windows.filter { StepLoudness.loudness($0) >= rangeAbsoluteGate }
        guard !passed.isEmpty else { return nil }
        let relative = StepLoudness.loudness(passed.reduce(0, +) / Double(passed.count))
            + rangeRelativeGate
        let levels = passed.map(StepLoudness.loudness).filter { $0 >= relative }.sorted()
        guard !levels.isEmpty else { return nil }
        return percentile(levels, 0.95) - percentile(levels, 0.10)
    }

    /// The `p` quantile of sorted `values`, linearly interpolated between the
    /// two nearest ranks (numpy's default).
    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        let position = p * Double(values.count - 1)
        let low = Int(position.rounded(.down))
        let high = min(low + 1, values.count - 1)
        return values[low] + (values[high] - values[low]) * (position - Double(low))
    }

    /// AU-67's rule over one measurement: the leveller to write (nil: the key
    /// is left out; `.some(nil)`: off) and its sentence.
    static func levellerRule(_ m: Measurement) -> (leveller: LevellerProps??, reason: String) {
        let line = String(format: "%g LU", levellerRangeLU)
        guard let range = m.speechRangeLU else {
            return (nil, "Leveller: under \(seconds(shortTermSteps)) of speech, so there is no "
                + "short-term loudness range to measure; the leveller is left as it is.")
        }
        let measured = "the speech's short-term loudness range is \(signed(range, "%.1f LU"))"
        if range > levellerRangeLU {
            return (.some(LevellerProps()), "Leveller: \(measured), above \(line), so the "
                + "leveller is on at its defaults.")
        }
        return (.some(nil), "Leveller: \(measured), at or under \(line), so the leveller is off.")
    }
}
