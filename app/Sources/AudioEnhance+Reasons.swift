import Foundation

/// Enhance Voice's reason sentences (spec §11 AU-62): the loudness row's
/// sentence and the numbers every rule's sentence is written with, moved out
/// of `AudioEnhance.swift` when the processed solve (AU-64) took it past 400
/// lines.
extension AudioEnhance {

    /// The last reason: what the processed render measured, the limiter, the
    /// volume, where the last render says it lands and how many renders it
    /// took; the volume ceiling when it stopped short.
    static func loudnessReason(
        _ result: AudioNormalize.LoudnessResult, limiter: LimiterProps, target: Double
    ) -> String {
        let through = result.processedLUFS.map {
            "measured through these settings at \(lufs($0)), "
        } ?? ""
        let renders = result.renders == 1 ? "1 render" : "\(result.renders) renders"
        return "Loudness: " + through + "the limiter at "
            + "\(signed(limiter.ceilingDb, "%.1f dBTP")) and the volume "
            + "\(String(format: "%.3f", result.volume)) take it to "
            + "\(lufs(result.resultLUFS)) (\(renders))"
            + (result.limit == nil ? "." : ", short of \(lufs(target)): the volume "
                + "would pass \(AudioNormalize.maxGainName).")
    }

    // MARK: - The sentences' numbers

    static func signed(_ value: Double, _ format: String) -> String {
        guard value.isFinite else { return value < 0 ? "−∞" : "∞" }
        return String(format: format, value).replacingOccurrences(of: "-", with: "−")
    }
    static func db(_ value: Double) -> String { signed(value, "%.1f dB") }
    static func dbfs(_ value: Double) -> String { signed(value, "%.1f dBFS") }
    static func lufs(_ value: Double) -> String { signed(value, "%.1f LUFS") }
    static func percent(_ share: Double) -> String { String(format: "%.0f %%", share * 100) }
    static func seconds(_ steps: Int) -> String {
        String(format: "%g s", Double(steps) * AudioLimiterModel.stepSeconds)
    }
}
