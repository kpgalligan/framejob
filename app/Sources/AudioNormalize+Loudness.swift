import Foundation

/// Normalize's Loudness mode (spec §11 AU-4, AU-13, AU-14, AU-24): each clip
/// to one integrated loudness in LUFS under a −1 dBTP true peak, through the
/// clip limiter when the peak needs it, and under the volume ceiling. `read`/`plan`'s seam beside Peak mode's: `readLoudness` touches the
/// document, the plan and the loudness cache once (`ClipLoudness`), and `plan`
/// is pure arithmetic. The pane's button, Clip ▸ Normalize (both through
/// `NormalizeChoice`) and `normalize_clip {mode: "loudness"}` all call these.
extension AudioNormalize {

    enum Mode: String, CaseIterable {
        case peak, loudness
    }

    /// AU-4: −16 LUFS integrated by default; −14 (YouTube's playback
    /// reference) and −23 (EBU R 128) as quick picks.
    static let defaultTargetLUFS = -16.0
    static let targetLUFSQuickPicks: [Double] = [-14, -16, -23]
    /// What a caller may ask for; a tool refuses outside it by name.
    static let targetLUFSRange = -50.0 ... -5.0
    /// The true-peak ceiling, in dBTP. A clip whose true peak would pass it at
    /// the target gets the clip limiter at this ceiling (AU-24).
    static let ceilingDBTP = -1.0

    /// The cap that bit, when one did: only the volume ceiling is left (AU-24).
    enum Limit: String {
        case maxGain = "max_gain"
    }

    /// One clip's measurement, before any target.
    struct LoudnessReading: Equatable {
        let clip: UInt32
        let media: UInt32
        /// Integrated LUFS as the export plays it at volume 1.
        let lufs: Double
        /// Linear, > 0.
        let truePeak: Double
        /// The reading's 10 ms steps and their true peaks, played order
        /// (`ClipLoudness.Reading`): what `AudioLimiterModel` runs over.
        var steps: [Double] = []
        var stepPeaks: [Double] = []
        /// The clip's own limiter, nil when it has none.
        var limiter: LimiterProps? = nil
    }

    /// What one clip's loudness normalise will do.
    struct LoudnessResult: Equatable {
        let clip: UInt32
        let media: UInt32
        let measuredLUFS: Double
        let truePeakDBTP: Double
        /// The volume written — `set_audio`'s `volume`, 0…`maxGain`.
        let volume: Double
        let resultLUFS: Double
        let resultTruePeakDBTP: Double
        /// nil when the clip reaches the target.
        let limit: Limit?
        /// The clip's limiter after the edit, nil when it has none.
        let limiter: LimiterProps?
    }

    struct LoudnessInput {
        let readings: [LoudnessReading]
        let problems: [Problem]

        var isEmpty: Bool { readings.isEmpty }
    }

    struct LoudnessPlan {
        /// The target after `plan`'s finiteness guard — what actually ran.
        let targetLUFS: Double
        let ops: [ReelOp]
        let normalized: [LoudnessResult]
        let skipped: [Problem]

        var isEmpty: Bool { ops.isEmpty }
    }

    // MARK: - Reading

    /// `read`'s shape for Loudness mode: the same admission (`admit`), then the
    /// clip's reading off the loudness cache. nil only for a plan this build
    /// cannot read.
    static func readLoudness(from document: ProjectDocument, clips: [UInt32]? = nil)
        -> LoudnessInput?
    {
        guard let plan = document.editedProject.plan else { return nil }
        let snapshot = document.editedProject.snapshot
        let loader = ClipLoudness.loader(cacheDirectory: document.cacheDirectory)
        let segments = audioSegments(in: plan)
        var readings: [LoudnessReading] = []
        var problems: [Problem] = []
        var seen: Set<UInt32> = []
        for id in clips ?? document.selection.sorted() where seen.insert(id).inserted {
            switch ClipLoudness.answer(
                for: id, snapshot: snapshot, segments: segments, loader: loader) {
            case .unavailable:
                problems.append(
                    admit(id, in: snapshot, segments: segments)
                        ?? Problem(clip: id, reason: "plays no sound in this timeline."))
            case .pending:
                problems.append(
                    Problem(
                        clip: id,
                        reason: "is still being analysed — its loudness has not been measured "
                            + "yet. Try again in a moment."))
            case .reading(let reading):
                if reading.playedTicks < ClipLoudness.minimumPlayedTicks {
                    problems.append(
                        Problem(
                            clip: id,
                            reason: "plays for under 0.4 s, too short for an integrated "
                                + "loudness (one 400 ms gating block)."))
                } else if let lufs = reading.lufs, reading.truePeak > 0 {
                    let media = segments[id]?.first?.media ?? 0
                    readings.append(
                        LoudnessReading(
                            clip: id, media: media, lufs: lufs, truePeak: reading.truePeak,
                            steps: reading.steps, stepPeaks: reading.stepPeaks,
                            limiter: snapshot.clip(id)?.audio?.limiter))
                } else {
                    problems.append(
                        Problem(
                            clip: id,
                            reason: "is under −70 LUFS over the part of it that plays, so "
                                + "there is no loudness to normalise."))
                }
            }
        }
        return LoudnessInput(readings: readings, problems: problems)
    }

    // MARK: - Planning

    /// AU-24: `v0 = min(10^((T−L)/20), maxGain)`. A clip with no limiter whose
    /// true peak fits the ceiling at `v0` gets `volume: v0` alone (AP1's
    /// result). Any other gets one `set_audio {volume, limiter}`: its own
    /// limiter kept, the ceiling lowered to −1 dBTP when above it, or the
    /// default; the volume is `AudioLimiterModel`'s gain for the target under
    /// that limiter. `limited_by` is `max_gain` when the volume ceiling stops
    /// it short. It may turn a clip down. A non-finite target falls back to
    /// the default and is reported as `targetLUFS`.
    static func plan(_ input: LoudnessInput, targetLUFS: Double = defaultTargetLUFS)
        -> LoudnessPlan
    {
        let target = targetLUFS.isFinite ? targetLUFS : defaultTargetLUFS
        let ceiling = pow(10, ceilingDBTP / 20)
        var ops: [ReelOp] = []
        var normalized: [LoudnessResult] = []
        for reading in input.readings {
            let wanted = pow(10, (target - reading.lufs) / 20)
            let first = max(0, min(wanted, maxGain))
            let row: LoudnessResult
            if reading.limiter == nil, reading.truePeak * first <= ceiling {
                ops.append(.setAudio(clips: [reading.clip], patch: AudioPatch(volume: first)))
                row = LoudnessResult(
                    clip: reading.clip, media: reading.media, measuredLUFS: reading.lufs,
                    truePeakDBTP: 20 * log10(reading.truePeak), volume: first,
                    resultLUFS: reading.lufs + 20 * log10(first),
                    resultTruePeakDBTP: 20 * log10(reading.truePeak * first),
                    limit: wanted <= maxGain ? nil : .maxGain, limiter: nil)
            } else {
                var limiter = reading.limiter ?? LimiterProps()
                limiter.ceilingDb = min(limiter.ceilingDb, ceilingDBTP)
                let solved = solve(reading, target: target, wanted: first, limiter: limiter)
                ops.append(
                    .setAudio(
                        clips: [reading.clip],
                        patch: AudioPatch(volume: solved.volume, limiter: .some(limiter))))
                row = LoudnessResult(
                    clip: reading.clip, media: reading.media, measuredLUFS: reading.lufs,
                    truePeakDBTP: 20 * log10(reading.truePeak), volume: solved.volume,
                    resultLUFS: solved.lufs,
                    resultTruePeakDBTP: 20 * log10(
                        min(reading.truePeak * solved.volume, pow(10, limiter.ceilingDb / 20))),
                    limit: solved.lufs < target - AudioLimiterModel.tolerance ? .maxGain : nil,
                    limiter: limiter)
            }
            normalized.append(row)
        }
        return LoudnessPlan(
            targetLUFS: target, ops: ops, normalized: normalized, skipped: input.problems)
    }

    /// The volume and the model's loudness for one reading under `limiter`.
    /// A reading with no steps (none this build makes) has nothing for the
    /// model to run over, and gets the unlimited gain.
    private static func solve(
        _ reading: LoudnessReading, target: Double, wanted: Double, limiter: LimiterProps
    ) -> (volume: Double, lufs: Double) {
        guard !reading.steps.isEmpty else {
            return (wanted, reading.lufs + 20 * log10(wanted))
        }
        let ceiling = pow(10, limiter.ceilingDb / 20)
        let release = Double(max(limiter.release, 0)) / Double(ReelTime.perSecond)
        let volume = AudioLimiterModel.gain(
            reaching: target, steps: reading.steps, peaks: reading.stepPeaks, ceiling: ceiling,
            releaseSeconds: release, maxGain: maxGain)
        let lufs = AudioLimiterModel.integrated(
            steps: reading.steps, peaks: reading.stepPeaks, gain: volume, ceiling: ceiling,
            releaseSeconds: release) ?? (reading.lufs + 20 * log10(volume))
        return (volume, lufs)
    }
}
