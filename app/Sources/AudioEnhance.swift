import Foundation

/// Enhance Voice (road map "audio" AP6, spec §11 AU-60…AU-62, AU-64):
/// measurements in, ordinary settings out. Clip ▸ Enhance Voice, the Volume
/// section's Enhance Voice button (both through `AudioMeasureDoor`) and the
/// agent's `enhance_voice` call `read`, `choose` and `jobs`, run the jobs
/// through a `LoudnessMeasureRun`, and `plan` over its outcome —
/// `AudioNormalize`'s seam and posture: no door does arithmetic, so the
/// three cannot mean different things, and the rules can be checked without
/// a window (`audio_ap6_probe.py`).
///
/// **What it measures** (AU-61) is pre-chain: the clip's `ClipLoudness`
/// reading — L, the true peak, each 10 ms played step's energy, true peak,
/// source midpoint and high band — split into speech and pause steps by the
/// media's speech spans (`media.speech`, else the VAD cache's
/// `DuckSpeech.spans`). Nothing it reads depends on a key it writes, so a
/// second press writes the same values and the core answers an identity.
///
/// **What it writes** (AU-60, AU-62, AU-67): one `set_audio` per clip, its
/// BASE props, owning exactly nine keys — `eq` (Rumble Cut on the clip's own
/// EQ), `isolation`, `noise_reduction`, `gate`, `leveller`
/// (`AudioEnhance+Leveller.swift`), `de_esser`, `compressor`, `limiter` and
/// `volume`; every other key is left as it is. Volume and
/// limiter are solved on the clip rendered through the chosen settings
/// (AU-64), as Loudness Normalize solves a processed clip, so Normalize after
/// Enhance changes nothing either.
enum AudioEnhance {
    static let actionName = "Enhance Voice"
    /// AU-62: a floor less than this under L cleans and gates; at or under it,
    /// the pauses are already quiet.
    static let noisyGapDB = -45.0
    /// The gate opens this far above the pauses' median true peak.
    static let gateAbovePausePeakDB = 10.0
    /// The gate's threshold, dB re L, is held here.
    static let gateThresholdRange = -40.0 ... -6.0
    /// A speech step whose high band reads at least L + this is sibilant.
    static let sibilanceGapDB = -10.0
    /// The de-esser goes on at this share of sibilant speech steps.
    static let sibilanceShare = 0.05
    /// 1 s of speech, in 10 ms steps: under it there is no voice to measure.
    static let minimumSpeechSteps = 100
    /// 0.5 s of pause: under it there is no floor.
    static let minimumPauseSteps = 50

    /// One clip's measurements (AU-61), before any rule.
    struct Measurement: Equatable {
        /// The `ClipLoudness` reading's integrated LUFS and linear true peak.
        let lufs: Double
        let truePeak: Double
        let speechSteps: Int
        let pauseSteps: Int
        /// The median pause-step loudness, LUFS (−∞ allowed); nil under
        /// `minimumPauseSteps`.
        let floorLUFS: Double?
        /// The median pause-step true peak, dBFS (−∞ allowed); nil with the floor.
        let pausePeakMedianDB: Double?
        /// The share of speech steps whose high band reads ≥ L + `sibilanceGapDB`.
        let sibilantShare: Double
        /// The median speech-step true peak, dBFS.
        let peakMedianDB: Double
        /// The speech's short-term loudness range, LU (AU-67); nil under 3 s.
        let speechRangeLU: Double?

        /// floor − L, dB; nil without a floor.
        var floorGapDB: Double? { floorLUFS.map { $0 - lufs } }
    }

    /// What `read` took for one clip.
    struct Reading: Equatable {
        let clip: UInt32
        let media: UInt32
        let measurement: Measurement
        let loudness: ClipLoudness.Reading
        /// The clip's audio group now: the EQ Rumble Cut joins and the
        /// limiter whose ceiling is kept.
        let current: AudioProps
    }

    struct Input {
        let readings: [Reading]
        let problems: [AudioNormalize.Problem]

        var isEmpty: Bool { readings.isEmpty }
    }

    /// One clip's settings before its volume (AU-62): `patch` writes neither
    /// volume nor limiter; `limiter` is the one the solve uses and the edit
    /// writes.
    struct Choice: Equatable {
        let clip: UInt32
        let media: UInt32
        let measurement: Measurement
        let patch: AudioPatch
        let limiter: LimiterProps
        let reasons: [String]
    }

    /// What one clip's enhance will do.
    struct Row: Equatable {
        let clip: UInt32
        let media: UInt32
        let measurement: Measurement
        let patch: AudioPatch
        /// One sentence per rule: the measurement, the threshold, what it set.
        let reasons: [String]
        /// Normalize's row for the volume and limiter (AU-62's last rule).
        let loudness: AudioNormalize.LoudnessResult
        /// R0's loudness through the chosen settings, and the renders the
        /// solve took (AU-64).
        var processedLUFS: Double? { loudness.processedLUFS }
        var renders: Int { loudness.renders }
    }

    struct Plan {
        /// The target after `plan`'s finiteness guard — what actually ran.
        let targetLUFS: Double
        let ops: [ReelOp]
        let enhanced: [Row]
        let skipped: [AudioNormalize.Problem]

        var isEmpty: Bool { ops.isEmpty }
    }

    // MARK: - Reading

    /// Reads the document's edited project, plan and caches for `clips` (nil:
    /// the selection). nil only for a plan this build cannot read; a clip that
    /// cannot be enhanced is a problem, by name (AU-60).
    static func read(from document: ProjectDocument, clips: [UInt32]? = nil) -> Input? {
        guard let plan = document.editedProject.plan else { return nil }
        let snapshot = document.editedProject.snapshot
        let loader = ClipLoudness.loader(cacheDirectory: document.cacheDirectory)
        let segments = AudioNormalize.audioSegments(in: plan)
        var readings: [Reading] = []
        var problems: [AudioNormalize.Problem] = []
        var seen: Set<UInt32> = []
        func skip(_ id: UInt32, _ reason: String) {
            problems.append(AudioNormalize.Problem(clip: id, reason: reason))
        }
        for id in clips ?? document.selection.sorted() where seen.insert(id).inserted {
            let answer = ClipLoudness.answer(
                for: id, snapshot: snapshot, segments: segments, loader: loader)
            guard case .reading(let loudness) = answer else {
                if answer == .pending {
                    skip(id, "is still being analyzed — its loudness has not been measured "
                        + "yet. Try again in a moment.")
                } else {
                    problems.append(
                        AudioNormalize.admit(id, in: snapshot, segments: segments)
                            ?? AudioNormalize.Problem(
                                clip: id, reason: "plays no sound in this timeline."))
                }
                continue
            }
            guard loudness.playedTicks >= ClipLoudness.minimumPlayedTicks else {
                skip(id, "plays for under 0.4 s, too short for an integrated loudness (one "
                    + "400 ms gating block).")
                continue
            }
            guard loudness.lufs != nil, loudness.truePeak > 0 else {
                skip(id, "is under −70 LUFS over the part of it that plays, so there is no "
                    + "voice to enhance.")
                continue
            }
            let own = (segments[id] ?? []).filter { $0.media == segments[id]?.first?.media }
            let mediaID = own.first?.media ?? 0
            guard let media = snapshot.media(mediaID),
                let spans = media.speech ?? speechSpans(media, cache: document.cacheDirectory)
            else {
                skip(id, "is still being analyzed — its speech has not been detected yet. Try "
                    + "again in a moment.")
                continue
            }
            let mask = speechMask(sources: loudness.stepSources, spans: spans)
            guard let measurement = measure(loudness, speech: mask) else {
                skip(id, "has under 1 s of speech over the part of it that plays, too little "
                    + "to measure a voice from.")
                continue
            }
            readings.append(
                Reading(
                    clip: id, media: mediaID, measurement: measurement, loudness: loudness,
                    current: snapshot.clip(id)?.audio ?? AudioProps()))
        }
        return Input(readings: readings, problems: problems)
    }

    /// The media's speech spans off its VAD cache, nil while it is not written.
    static func speechSpans(_ media: MediaSnapshot, cache: URL?) -> [[Ticks]]? {
        guard let cache, let p = MediaImporter.loadSpeech(for: media.id, in: cache) else {
            return nil
        }
        return DuckSpeech.spans(p, duration: media.duration)
    }

    /// Whether each step's source midpoint lies in a span `[start, end)`;
    /// `spans` sorted, as `DuckSpeech.spans` and `media.speech` keep them.
    static func speechMask(sources: [Ticks], spans: [[Ticks]]) -> [Bool] {
        let ranges = spans.compactMap { $0.count == 2 && $0[1] > $0[0] ? ($0[0], $0[1]) : nil }
        return sources.map { tick in
            var low = 0
            var high = ranges.count
            while low < high {
                let middle = (low + high) / 2
                if ranges[middle].1 <= tick { low = middle + 1 } else { high = middle }
            }
            return low < ranges.count && ranges[low].0 <= tick
        }
    }

    /// AU-61's figures from a reading and its speech mask; nil without a
    /// loudness or under `minimumSpeechSteps` of speech.
    static func measure(_ reading: ClipLoudness.Reading, speech: [Bool]) -> Measurement? {
        guard let lufs = reading.lufs else { return nil }
        let count = min(reading.steps.count, reading.stepPeaks.count, speech.count)
        var speechPeaks: [Double] = []
        var pauseLevels: [Double] = []
        var pausePeaks: [Double] = []
        var sibilant = 0
        for k in 0..<count {
            let peak = reading.stepPeaks[k] > 0 ? 20 * log10(reading.stepPeaks[k]) : -.infinity
            if speech[k] {
                speechPeaks.append(peak)
                let high = k < reading.stepHighs.count ? reading.stepHighs[k] : 0
                if StepLoudness.loudness(high) >= lufs + sibilanceGapDB { sibilant += 1 }
            } else {
                pauseLevels.append(StepLoudness.loudness(reading.steps[k]))
                pausePeaks.append(peak)
            }
        }
        guard speechPeaks.count >= minimumSpeechSteps else { return nil }
        let floored = pauseLevels.count >= minimumPauseSteps
        return Measurement(
            lufs: lufs, truePeak: reading.truePeak, speechSteps: speechPeaks.count,
            pauseSteps: pauseLevels.count, floorLUFS: floored ? median(pauseLevels) : nil,
            pausePeakMedianDB: floored ? median(pausePeaks) : nil,
            sibilantShare: Double(sibilant) / Double(speechPeaks.count),
            peakMedianDB: median(speechPeaks),
            speechRangeLU: speechRange(steps: reading.steps, speech: speech))
    }

    /// The middle value, or the mean of the two middle ones; −∞ sorts first.
    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return -.infinity }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    // MARK: - Planning

    /// AU-62's rules over each reading: every setting but the volume. Pure:
    /// no document, no disk, no AppKit.
    static func choose(_ input: Input) -> [Choice] {
        input.readings.map { reading in
            let m = reading.measurement
            var patch = AudioPatch()
            var reasons: [String] = []

            patch.eq = .some(EqPreset.rumbleCut.applied(to: reading.current.eq ?? EqProps()))
            reasons.append("High-pass: always — the EQ's Rumble Cut, 80 Hz at 24 dB/octave.")

            if let gap = m.floorGapDB, let floor = m.floorLUFS {
                let measured = "the pauses' floor is \(lufs(floor)), \(db(gap)) under the "
                    + "voice's \(lufs(m.lufs))"
                if gap > noisyGapDB {
                    // Isolation serves a clip at any speed (AU-55 as amended).
                    patch.isolation = IsolationCache.defaultAmount
                    patch.noiseReduction = 0
                    reasons.append("Noise: \(measured), above the \(db(noisyGapDB)) line, "
                        + "so voice isolation at \(percent(IsolationCache.defaultAmount)) "
                        + "and noise reduction off.")
                    let opens = (m.pausePeakMedianDB ?? -.infinity) + gateAbovePausePeakDB - m.lufs
                    let threshold = min(
                        max(opens.rounded(), gateThresholdRange.lowerBound),
                        gateThresholdRange.upperBound)
                    patch.gate = .some(GateProps(thresholdDb: threshold))
                    reasons.append("Gate: the pauses' median peak is "
                        + "\(dbfs(m.pausePeakMedianDB ?? -.infinity)), so the gate opens "
                        + "\(db(gateAbovePausePeakDB)) above it, at \(db(threshold)) re the "
                        + "loudness (held to \(db(gateThresholdRange.lowerBound))…"
                        + "\(db(gateThresholdRange.upperBound))).")
                } else {
                    patch.isolation = 0
                    patch.noiseReduction = 0
                    patch.gate = .some(nil)
                    reasons.append("Noise: \(measured), at or under the \(db(noisyGapDB)) "
                        + "line, so isolation, noise reduction and the gate are off.")
                }
            } else {
                reasons.append("Noise: under \(seconds(minimumPauseSteps)) of pause, so there "
                    + "is no floor to measure; isolation, noise reduction and the gate are "
                    + "left as they are.")
            }

            let levelling = levellerRule(m)
            if let leveller = levelling.leveller { patch.leveller = leveller }
            reasons.append(levelling.reason)

            let hot = m.sibilantShare >= sibilanceShare
            patch.deEsser = .some(hot ? DeEsserProps() : nil)
            reasons.append("De-esser: \(percent(m.sibilantShare)) of the speech has its high "
                + "band at \(db(sibilanceGapDB)) re the loudness or above, "
                + (hot ? "at least" : "under") + " \(percent(sibilanceShare)), so the "
                + "de-esser is " + (hot ? "on at its defaults." : "off."))

            let threshold = min(max(m.peakMedianDB.rounded(), -60), 0)
            let makeup = AudioDynamicsModel.makeupDB(
                reading.loudness, compressor: CompressorProps(thresholdDb: threshold, makeupDb: 0))
            let compressor = CompressorProps(thresholdDb: threshold, makeupDb: makeup)
            patch.compressor = .some(compressor)
            reasons.append("Compressor: the speech's median peak is \(dbfs(m.peakMedianDB)), so "
                + "the threshold is \(dbfs(threshold)) at \(String(format: "%g", compressor.ratio)):1, "
                + "with \(db(makeup)) of makeup to "
                + "give back what it takes.")

            var limiter = reading.current.limiter ?? LimiterProps()
            limiter.ceilingDb = min(limiter.ceilingDb, AudioNormalize.ceilingDBTP)
            return Choice(
                clip: reading.clip, media: reading.media, measurement: m, patch: patch,
                limiter: limiter, reasons: reasons)
        }
    }

    /// Each choice as a measurement job (AU-64 (b)): the clip's cache
    /// reading carrying the chosen limiter, its current volume and its own
    /// limiter (the keep rule's, AU-64 (f), #400), rendered
    /// through the chosen settings.
    static func jobs(_ input: Input, _ choices: [Choice]) -> [LoudnessMeasureRun.Job] {
        choices.compactMap { choice in
            guard let reading = input.readings.first(where: { $0.clip == choice.clip }) else {
                return nil
            }
            let m = reading.measurement
            return LoudnessMeasureRun.Job(
                reading: AudioNormalize.LoudnessReading(
                    clip: choice.clip, media: choice.media, lufs: m.lufs, truePeak: m.truePeak,
                    steps: reading.loudness.steps, stepPeaks: reading.loudness.stepPeaks,
                    limiter: choice.limiter, currentVolume: reading.current.volume,
                    currentLimiter: reading.current.limiter),
                chain: choice.patch)
        }
    }

    /// The ops, from the choices and the run's outcome (AU-62's last rule,
    /// AU-64): each choice's patch with its solve's volume and limiter, one
    /// `set_audio` per clip; a clip the run skipped is under `skipped`. Pure.
    /// A non-finite target falls back to the default and is reported as
    /// `targetLUFS`.
    static func plan(
        _ input: Input, choices: [Choice], outcome: LoudnessMeasureRun.Outcome,
        targetLUFS: Double
    ) -> Plan {
        let target = targetLUFS.isFinite ? targetLUFS : AudioNormalize.defaultTargetLUFS
        let solved = AudioNormalize.plan(outcome.input, targetLUFS: target, solved: outcome.solved)
        var ops: [ReelOp] = []
        var rows: [Row] = []
        for choice in choices {
            guard let result = solved.normalized.first(where: { $0.clip == choice.clip }) else {
                continue
            }
            var patch = choice.patch
            patch.limiter = .some(result.limiter ?? choice.limiter)
            patch.volume = result.volume
            let loudness = loudnessReason(result, limiter: choice.limiter, target: target)
            ops.append(.setAudio(clips: [choice.clip], patch: patch))
            rows.append(
                Row(
                    clip: choice.clip, media: choice.media, measurement: choice.measurement,
                    patch: patch, reasons: choice.reasons + [loudness], loudness: result))
        }
        return Plan(targetLUFS: target, ops: ops, enhanced: rows, skipped: outcome.input.problems)
    }
}
