import Foundation

/// Match Audio (road map "audio" AP12, spec §11 AU-120…AU-128): a reference
/// clip in, ordinary settings on the target clips out. Clip ▸ Match Audio…
/// (through `AudioMeasureDoor.pressMatch`) and the agent's `match_audio` call
/// `read`, run an `AudioMatchRun` over its input, and `plan` over the run's
/// outcome — `AudioEnhance`'s seam: no door does arithmetic, so the two
/// cannot mean different things.
///
/// **What it reads** (AU-122, AU-124): the reference's and each target's
/// loudness cache reading (Normalize's admission and skips; the reference's
/// are refusals naming it) and, when EQ is matched, each one's speech mask
/// over its played 10 ms steps (`media.speech`, else the VAD cache's spans,
/// AU-61's).
///
/// **What it writes** (AU-120, AU-123, AU-127): one `set_audio` per target,
/// its BASE props: `eq` (the five tonal slots the fit chose, its passes kept,
/// `bypass: false`) when EQ is on, `volume` and `limiter` (Loudness Normalize
/// to the reference's loudness) when Loudness is on. Every other key is left.
enum AudioMatch {
    static let actionName = "Match Audio"

    struct Reference: Equatable {
        let clip: UInt32
        let media: UInt32
        let loudness: ClipLoudness.Reading
        /// One flag per played step; nil when EQ is off.
        let speech: [Bool]?
    }

    struct Target: Equatable {
        let clip: UInt32
        let media: UInt32
        let loudness: AudioNormalize.LoudnessReading
        /// One flag per played step; nil when EQ is off.
        let speech: [Bool]?
        /// The clip's audio group now: its EQ's passes are kept.
        let current: AudioProps
    }

    struct Input {
        let reference: Reference
        let targets: [Target]
        let problems: [AudioNormalize.Problem]
        let loudness: Bool
        let eq: Bool
    }

    /// The sentence a refusal says, whole.
    enum Refusal: Error, Equatable {
        /// The reference cannot be matched to.
        case reference(String)
        /// No target can be matched: "Nothing could be matched." and every reason.
        case nothingToMatch(String)

        var sentence: String {
            switch self {
            case .reference(let text), .nothingToMatch(let text): return text
            }
        }
    }

    /// What one target's match will do.
    struct Row: Equatable {
        let clip: UInt32
        let media: UInt32
        /// The EQ written; nil with EQ off.
        let eq: EqProps?
        let fitRMSDB: Double?
        /// Normalize's row for the volume and limiter; nil with Loudness off.
        let loudness: AudioNormalize.LoudnessResult?
        let set: AudioPatch
    }

    struct Plan {
        /// The reference's loudness, the targets' target; nil with Loudness off.
        let targetLUFS: Double?
        let ops: [ReelOp]
        let matched: [Row]
        let skipped: [AudioNormalize.Problem]
    }

    // MARK: - Reading

    /// Reads the document's edited project, plan and caches. A reference that
    /// cannot be matched to is a `.reference` refusal by name; a target that
    /// cannot be matched is a problem, and none left is `.nothingToMatch`.
    static func read(
        from document: ProjectDocument, reference: UInt32, clips: [UInt32], loudness: Bool,
        eq: Bool
    ) -> Result<Input, Refusal> {
        guard let plan = document.editedProject.plan else {
            return .failure(
                .reference(
                    "The project's audio plan could not be read, so there is no sound to "
                        + "match."))
        }
        let snapshot = document.editedProject.snapshot
        let loader = ClipLoudness.loader(cacheDirectory: document.cacheDirectory)
        let segments = AudioNormalize.audioSegments(in: plan)

        /// One clip's cache reading, media and speech mask, or why it has none.
        enum Measured {
            case reading(ClipLoudness.Reading, UInt32, [Bool]?)
            case problem(AudioNormalize.Problem)
        }
        func measured(_ id: UInt32) -> Measured {
            func problem(_ reason: String) -> Measured {
                .problem(AudioNormalize.Problem(clip: id, reason: reason))
            }
            let answer = ClipLoudness.answer(
                for: id, snapshot: snapshot, segments: segments, loader: loader)
            guard case .reading(let reading) = answer else {
                if answer == .pending {
                    return problem(
                        "is still being analysed — its loudness has not been measured yet. Try "
                            + "again in a moment.")
                }
                return .problem(
                    AudioNormalize.admit(id, in: snapshot, segments: segments)
                        ?? AudioNormalize.Problem(
                            clip: id, reason: "plays no sound in this timeline."))
            }
            guard reading.playedTicks >= ClipLoudness.minimumPlayedTicks else {
                return problem(
                    "plays for under 0.4 s, too short for an integrated loudness (one 400 ms "
                        + "gating block).")
            }
            guard reading.lufs != nil, reading.truePeak > 0 else {
                return problem(
                    "is under −70 LUFS over the part of it that plays, so there is no sound to "
                        + "match.")
            }
            let mediaID = segments[id]?.first?.media ?? 0
            guard eq else { return .reading(reading, mediaID, nil) }
            guard let media = snapshot.media(mediaID),
                let spans = media.speech
                    ?? AudioEnhance.speechSpans(media, cache: document.cacheDirectory)
            else {
                return problem(
                    "is still being analysed — its speech has not been detected yet. Try again "
                        + "in a moment.")
            }
            return .reading(
                reading, mediaID,
                AudioEnhance.speechMask(sources: reading.stepSources, spans: spans))
        }

        let referenceReading: Reference
        switch measured(reference) {
        case .problem(let problem):
            return .failure(.reference("The reference, clip \(reference), \(problem.reason)"))
        case .reading(let reading, let media, let speech):
            referenceReading = Reference(
                clip: reference, media: media, loudness: reading, speech: speech)
        }

        var targets: [Target] = []
        var problems: [AudioNormalize.Problem] = []
        var seen: Set<UInt32> = []
        for id in clips where seen.insert(id).inserted {
            guard id != reference else {
                problems.append(AudioNormalize.Problem(clip: id, reason: "is the reference."))
                continue
            }
            switch measured(id) {
            case .problem(let problem): problems.append(problem)
            case .reading(let reading, let media, let speech):
                let audio = snapshot.clip(id)?.audio
                targets.append(
                    Target(
                        clip: id, media: media,
                        loudness: AudioNormalize.LoudnessReading(
                            clip: id, media: media, lufs: reading.lufs ?? 0,
                            truePeak: reading.truePeak, steps: reading.steps,
                            stepPeaks: reading.stepPeaks, limiter: audio?.limiter,
                            currentVolume: audio?.volume),
                        speech: speech, current: audio ?? AudioProps()))
            }
        }
        guard !targets.isEmpty else {
            return .failure(.nothingToMatch(nothingMatched(problems)))
        }
        return .success(
            Input(
                reference: referenceReading, targets: targets, problems: problems,
                loudness: loudness, eq: eq))
    }

    /// "Nothing could be matched." and every reason, each naming its clip.
    static func nothingMatched(_ problems: [AudioNormalize.Problem]) -> String {
        (["Nothing could be matched."] + problems.map { $0.description }).joined(separator: " ")
    }

    // MARK: - Planning

    /// The ops, from the input and the run's outcome: one `set_audio` per
    /// target with every part it asked for — the fit's EQ applied to its own
    /// (AU-127) and Normalize's volume and limiter at the reference's
    /// loudness (AU-123). A target missing a part is under `skipped` with the
    /// run's reason. Pure.
    static func plan(_ input: Input, outcome: AudioMatchRun.Outcome) -> Plan {
        var normalized: [UInt32: AudioNormalize.LoudnessResult] = [:]
        var skipped = input.problems + outcome.problems
        if input.loudness, let loudness = outcome.loudness {
            let solved = AudioNormalize.plan(
                loudness.input, targetLUFS: outcome.referenceLUFS, solved: loudness.solved)
            for row in solved.normalized { normalized[row.clip] = row }
            skipped += loudness.input.problems
        }
        var ops: [ReelOp] = []
        var rows: [Row] = []
        for target in input.targets {
            var patch = AudioPatch()
            var eq: EqProps?
            var rms: Double?
            if input.eq {
                guard let fit = outcome.fits[target.clip] else { continue }
                let applied = AudioMatchFit.applied(fit, to: target.current.eq)
                patch.eq = .some(applied)
                eq = applied
                rms = fit.rmsDB
            }
            var loudness: AudioNormalize.LoudnessResult?
            if input.loudness {
                guard let row = normalized[target.clip] else { continue }
                patch.volume = row.volume
                if let limiter = row.limiter { patch.limiter = .some(limiter) }
                loudness = row
            }
            ops.append(.setAudio(clips: [target.clip], patch: patch))
            rows.append(
                Row(
                    clip: target.clip, media: target.media, eq: eq, fitRMSDB: rms,
                    loudness: loudness, set: patch))
        }
        return Plan(
            targetLUFS: input.loudness ? outcome.referenceLUFS : nil, ops: ops, matched: rows,
            skipped: skipped)
    }
}
