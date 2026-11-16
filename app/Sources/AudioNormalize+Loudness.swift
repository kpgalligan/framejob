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

    /// The cap that bit, when one did: the volume ceiling (AU-24; the note
    /// names a limiter an action's end turns on as the likely reason when
    /// one did the holding, AU-168), or the verify renders running out away
    /// from the target (AU-167).
    enum Limit: String {
        case maxGain = "max_gain"
        case verifyRenders = "verify_renders"
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
        /// On a processed reading (spec §11 AU-64 (e)), the cache's L: `lufs`
        /// is then the clip's loudness through its own chain. nil off the cache.
        var materialLUFS: Double? = nil
        /// The clip's base volume as read, which a solved row keeps when the
        /// solve lands within `keepVolumeDB` of it (AU-64 (f)).
        var currentVolume: Double? = nil
        /// The clip's own limiter as read, nil when it has none: what AU-64
        /// (f)'s keep rule compares the solve against.
        var currentLimiter: LimiterProps? = nil
    }

    /// One rendered clip's solve (AU-64 (e)): the volume and limiter to
    /// write, where the last render says it lands, and how many renders it
    /// took (R0 and the verify renders).
    struct Solved: Equatable {
        let volume: Double
        let limiter: LimiterProps?
        let resultLUFS: Double
        let resultTruePeakDBTP: Double
        let limit: Limit?
        let renders: Int
    }

    /// AU-64 (f): a solved volume within this of the clip's own is not
    /// written — twice the 0.025 dB a re-rendered isolation window moves a
    /// loudness (S2).
    static let keepVolumeDB = 0.05

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
        /// R0's loudness through the clip's chain (AU-64); nil off the cache.
        var processedLUFS: Double? = nil
        /// The renders the solve took; 0 off the cache.
        var renders = 0
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
                        reason: "is still being analyzed — its loudness has not been measured "
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
                    let audio = snapshot.clip(id)?.audio
                    readings.append(
                        LoudnessReading(
                            clip: id, media: media, lufs: lufs, truePeak: reading.truePeak,
                            steps: reading.steps, stepPeaks: reading.stepPeaks,
                            limiter: audio?.limiter, currentVolume: audio?.volume,
                            currentLimiter: audio?.limiter))
                } else {
                    problems.append(
                        Problem(
                            clip: id,
                            reason: "is under −70 LUFS over the part of it that plays, so "
                                + "there is no loudness to normalize."))
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
    /// the default and is reported as `targetLUFS`. A clip in `solved` was
    /// measured through its chain (AU-64) and takes its solve's volume and
    /// limiter instead (`solvedRow`).
    static func plan(
        _ input: LoudnessInput, targetLUFS: Double = defaultTargetLUFS,
        solved: [UInt32: Solved] = [:]
    ) -> LoudnessPlan {
        let target = targetLUFS.isFinite ? targetLUFS : defaultTargetLUFS
        let ceiling = pow(10, ceilingDBTP / 20)
        var ops: [ReelOp] = []
        var normalized: [LoudnessResult] = []
        for reading in input.readings {
            if let solve = solved[reading.clip] {
                let (op, row) = solvedRow(reading, solve)
                ops.append(op)
                normalized.append(row)
                continue
            }
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
                let limiter = ceilingLimiter(reading.limiter)
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

    /// AU-167, AU-64 (e): what stopped a solve the verify renders checked,
    /// from its last render. The ceiling first: at `maxGain` and short by
    /// more than the loop's tolerance. Otherwise a miss past the tolerance,
    /// over or under, is the loop's bound: the loop goes on while it misses
    /// and the volume can move, so it ended there only because
    /// `LoudnessMeasureRun.maximumVerifyRenders` had run. nil when it landed.
    static func verifiedLimit(volume: Double, resultLUFS: Double, targetLUFS: Double) -> Limit? {
        let tolerance = LoudnessMeasureRun.verifyToleranceLU
        if volume >= maxGain && resultLUFS < targetLUFS - tolerance { return .maxGain }
        if abs(resultLUFS - targetLUFS) > tolerance { return .verifyRenders }
        return nil
    }

    /// AU-168 (b): whether a limiter an action's end turns on, not the
    /// ceiling, is the likely reason `result` stopped at ×32 short of the
    /// target: `endLimiter` (`ProcessedLoudness.endLimiterOn`), and R0 at
    /// `maxGain` with nothing more holding it would have reached the target,
    /// so what the last render lacks of that is what a limiter took. A row
    /// with no R0 (off the cache) has no such end.
    static func actionLimiterHeld(_ result: LoudnessResult, endLimiter: Bool, targetLUFS: Double)
        -> Bool
    {
        guard endLimiter, result.limit == .maxGain, let r0 = result.processedLUFS else {
            return false
        }
        return r0 + 20 * log10(maxGain) >= targetLUFS - LoudnessMeasureRun.verifyToleranceLU
    }

    /// The tools' note for `rows` (AU-168 (c)): the clips of `document`'s
    /// open container an action's end turns a limiter on for, read from the
    /// project the run measured (each tool's stale test has passed). Main.
    static func limitNote(_ rows: [LoudnessResult], in document: ProjectDocument, targetLUFS: Double)
        -> String?
    {
        limitNote(
            rows, endLimiters: endLimiterClips(in: document, rows.map(\.clip)),
            targetLUFS: targetLUFS)
    }

    /// The clips of `clips` an action's end turns a limiter on for
    /// (`ProcessedLoudness.endLimiterOn`), in `document`'s open container.
    /// Main.
    static func endLimiterClips(in document: ProjectDocument, _ clips: [UInt32]) -> Set<UInt32> {
        let snapshot = document.editedProject.snapshot
        return Set(clips.filter { ProcessedLoudness.endLimiterOn(snapshot.clip($0)) })
    }

    /// The `note` of `normalize_clip`, `enhance_voice` and `match_audio` for
    /// the clips a limit stopped (AU-167): the ceiling's clips in the sentence
    /// it has always had, but those an action's limiter likely held under
    /// (`actionLimiterHeld`, `endLimiters` the clips it turns on for), whose
    /// sentence names it in the ceiling's place (AU-168 (c)); the verify
    /// bound's in their own with its usual cause, then where to read each
    /// landing once. nil when none has one. The target is written to 0.001
    /// LU, so a caller's −16 or −24.417 reads as it was asked and Match's
    /// measured one does not run to seventeen figures (AU-168 (c)).
    static func limitNote(_ rows: [LoudnessResult], endLimiters: Set<UInt32>, targetLUFS: Double)
        -> String?
    {
        let shown = (targetLUFS * 1000).rounded() / 1000
        func held(_ row: LoudnessResult) -> Bool {
            actionLimiterHeld(
                row, endLimiter: endLimiters.contains(row.clip), targetLUFS: targetLUFS)
        }
        func ids(_ limit: Limit, heldByAction: Bool = false) -> String? {
            let clips = rows.filter { $0.limit == limit }.filter { held($0) == heldByAction }
            return clips.isEmpty ? nil : clips.map { String($0.clip) }.joined(separator: ", ")
        }
        var sentences: [String] = []
        if let ceiling = ids(.maxGain) {
            sentences.append(
                "Clip(s) \(ceiling) stopped short of \(shown) LUFS: the volume that reaches "
                    + "it would pass the \(maxGainName) ceiling (limited_by max_gain).")
        }
        if let action = ids(.maxGain, heldByAction: true) {
            sentences.append(
                "Clip(s) \(action) stopped short of \(shown) LUFS at the \(maxGainName) "
                    + "ceiling (limited_by max_gain), but the likely reason is a limiter an "
                    + "action's end turns on: it holds the sound down harder as the volume "
                    + "rises, so no volume reaches the target.")
        }
        if let bound = ids(.verifyRenders) {
            let tolerance = String(format: "%g", LoudnessMeasureRun.verifyToleranceLU)
            sentences.append(
                "Clip(s) \(bound) ended more than \(tolerance) LU from \(shown) LUFS: the "
                    + "renders that check the volume ran out before it landed within "
                    + "\(tolerance) LU (limited_by verify_renders), usually because a limiter "
                    + "holds the sound down harder as the volume rises.")
        }
        guard !sentences.isEmpty else { return nil }
        return (sentences + ["result_lufs says where each landed."]).joined(separator: " ")
    }

    /// AU-24's limiter for a clip that needs one: its own with the ceiling
    /// lowered to `ceilingDBTP` when above it, else the default there. The
    /// processed solve puts the same one on mid-loop (AU-165 (b)).
    static func ceilingLimiter(_ own: LimiterProps?) -> LimiterProps {
        var limiter = own ?? LimiterProps()
        limiter.ceilingDb = min(limiter.ceilingDb, ceilingDBTP)
        return limiter
    }

    /// A rendered clip's op and row (AU-64 (e), (f)): the solve's volume,
    /// or the clip's own when it already carries the solved limiter (its own
    /// as read, `currentLimiter`, never a chosen one, #400) and the two are
    /// within `keepVolumeDB`, so a second press is an identity.
    private static func solvedRow(_ reading: LoudnessReading, _ solve: Solved)
        -> (ReelOp, LoudnessResult)
    {
        var volume = solve.volume
        if solve.limiter == reading.currentLimiter, let current = reading.currentVolume, current > 0,
            solve.volume > 0, abs(20 * log10(solve.volume / current)) <= keepVolumeDB
        {
            volume = current
        }
        let patch = solve.limiter.map { AudioPatch(volume: volume, limiter: .some($0)) }
            ?? AudioPatch(volume: volume)
        var row = LoudnessResult(
            clip: reading.clip, media: reading.media,
            measuredLUFS: reading.materialLUFS ?? reading.lufs,
            truePeakDBTP: 20 * log10(reading.truePeak), volume: volume,
            resultLUFS: solve.resultLUFS, resultTruePeakDBTP: solve.resultTruePeakDBTP,
            limit: solve.limit, limiter: solve.limiter)
        row.processedLUFS = reading.lufs
        row.renders = solve.renders
        return (.setAudio(clips: [reading.clip], patch: patch), row)
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
