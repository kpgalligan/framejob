import Foundation

/// Synchronize Audio's drift correction (road map "audio-sync", AS-2; spec
/// §11 SY-6, SY-8..SY-10): whether a measured drift is corrected, the rate
/// band a clip is matched within, where the corrected mover goes, how long
/// it becomes and in which order its two ops run.
///
/// Pure, as `AudioSync.plan` is: readings and a fitted line in, a speed, a
/// delta and ops out. The correction is the existing `set_speed` op with
/// `keep_pitch: false` (SY-6): the model keeps the rate as an f64, the plan
/// plays it as integer ticks over integer ticks, and `.varispeed` resamples
/// it with none of the time-pitch algorithm's processing.
extension AudioSync {

    // MARK: - The numbers (SY-8, SY-9)

    /// 0.2%: the furthest from ×1 a clip may play and still be matched, and
    /// the furthest a correction may take it.
    static let maximumRateDeviation = 0.002
    /// A drift under this, over the whole overlap, is left alone.
    static let minimumCorrectionMilliseconds = 5.0
    /// A drift must be at least this many times its own uncertainty to be
    /// corrected — the significance test (the owner's choice, 2026-10-15).
    static let minimumSignificance = 3.0

    /// What becomes of one mover's drift: a new speed, or left as it is
    /// with the sentence that says why (nil when it was not measured, whose
    /// own note says why).
    enum Correction: Equatable {
        case apply(speed: Double)
        case leave(note: String?)
    }

    // MARK: - Deciding (SY-8)

    /// The correction for `drift` measured on a clip playing at `speed`, the
    /// three rules in SY-8's order: corrected when `|drift_ms| ≥ max(5, 3 ×
    /// drift_error_ms)` and the new speed stays in SY-9's band. The
    /// uncertainty is a test of significance, not a cap.
    static func correction(for drift: AudioSyncMatch.DriftAnswer, speed: Double) -> Correction {
        guard case .measured(let fit) = drift else { return .leave(note: nil) }
        if abs(fit.milliseconds) < minimumCorrectionMilliseconds {
            return .leave(
                note: "a drift of " + String(format: "%.2f", fit.milliseconds)
                    + " ms over the overlap is under the "
                    + "\(String(format: "%g", minimumCorrectionMilliseconds)) ms Synchronize "
                    + "Audio corrects.")
        }
        if abs(fit.milliseconds) < minimumSignificance * fit.errorMilliseconds {
            return .leave(
                note: "a drift of " + String(format: "%.2f", fit.milliseconds)
                    + " ms over the overlap is under "
                    + "\(String(format: "%g", minimumSignificance)) times its uncertainty (±"
                    + String(format: "%.2f", fit.errorMilliseconds) + " ms), so it cannot be "
                    + "told from no drift.")
        }
        let corrected = speed * (1 - fit.rate)
        guard inBand(corrected) else {
            return .leave(
                note: "correcting it would play the clip at ×" + String(format: "%g", corrected)
                    + ", beyond the 0.2% Synchronize Audio corrects.")
        }
        return .apply(speed: corrected)
    }

    // MARK: - The band (SY-9)

    /// Why a clip playing at `rate` cannot be matched; nil within the band.
    static func rateProblem(_ rate: Double) -> String? {
        guard !inBand(rate) else { return nil }
        return "plays at ×\(String(format: "%g", rate)); Synchronize Audio lines up clips "
            + "playing at ×1 or within 0.2% of it."
    }

    /// Why a clip whose speed is ×1 but whose source is stretched to `rate`
    /// cannot be matched, even inside the band: its speed is not its rate.
    static func stretched(_ rate: Double) -> String {
        "plays at ×\(String(format: "%g", rate)) though its speed is ×1; Synchronize Audio "
            + "lines up clips whose speed is the rate they play at."
    }

    /// Why a RAMPED clip, mover or anchor, cannot be matched (spec §11
    /// SR-20 (e)): the drift line assumes one rate over the clip.
    static let ramped = "ramps its speed (a speed action changes its rate over its length); "
        + "Synchronize Audio lines up clips playing at one rate."

    /// `|rate − 1| ≤ maximumRateDeviation`, as a closed range so that the
    /// band's own edges (×1.002, ×0.998) are inside it in binary arithmetic.
    private static func inBand(_ rate: Double) -> Bool {
        ((1 - maximumRateDeviation)...(1 + maximumRateDeviation)).contains(rate)
    }

    // MARK: - The corrected span (SY-6, SY-10)

    /// The duration `set_speed` writes when a clip of `duration` playing at
    /// `old` is set to `new`: its content `round(d·old)` over `new`, snapped
    /// to the grid and at least one frame — the core's arithmetic without its
    /// hold to the file, which stays the core's backstop.
    static func durationAtSpeed(_ duration: Ticks, from old: Double, to new: Double, fps: Fps)
        -> Ticks {
        let content = (Double(duration) * old).rounded()
        let scaled = ReelTime.snapToFrame(Ticks((content / new).rounded()), fps: fps)
        return max(scaled, fps.frameDuration)
    }

    /// The move that puts a mover set to `speed` in sync along the fitted
    /// line (SY-6): `set_speed` keeps its start S and in point I, so source
    /// tick μ plays at `S + δ + (μ − I)/s'`, which is where the anchor plays
    /// the same sound when `δ = zeroA + 75·c/(1 − ρ) − S + I/s'` (c in
    /// samples, 75 ticks each, SY-21); snapped.
    static func correctedDelta(
        anchor: Reading, mover: Reading, drift: AudioSyncMatch.Drift, speed: Double, fps: Fps
    ) -> Ticks {
        let shift = Double(AudioSyncPHAT.sampleTicks) * drift.intercept / (1 - drift.rate)
        let exact = Double(anchor.zero) + shift - Double(mover.start)
            + Double(mover.sourceIn) / speed
        return ReelTime.snapToFrame(Ticks(exact.rounded()), fps: fps)
    }

    /// One mover's ops, each only when it changes something, ordered so
    /// that every span in between lies inside the old one or the final one
    /// (SY-10): a mover that grows moves first, one that shrinks or keeps
    /// its length changes speed first. A mover trimmed at its head (SY-16,
    /// `trimTo` the `trim_start` target S + e) changes speed first, so the
    /// trim advances its in point at the new speed, then trims, then moves.
    static func ops(
        clip: UInt32, delta: Ticks, from old: Double, to new: Double?, duration: Ticks,
        newDuration: Ticks, trimTo: Ticks? = nil
    ) -> [ReelOp] {
        let move: ReelOp? = delta != 0 ? ReelOp.moveClip(clips: [clip], delta: delta) : nil
        var speed: ReelOp?
        if let new = new, new != old {
            speed = ReelOp.setSpeed(clip: clip, rate: new, keepPitch: false)
        }
        if let trimTo {
            return [speed, ReelOp.trimStart(clip: clip, to: trimTo), move].compactMap { $0 }
        }
        if newDuration > duration {
            return [move, speed].compactMap { $0 }
        }
        return [speed, move].compactMap { $0 }
    }
}
