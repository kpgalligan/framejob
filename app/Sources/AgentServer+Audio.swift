import AppKit

/// The agent's sound tools: `normalize_clip`, the mirror of Normalize Clip
/// (road map 2 phase 5c), and `sync_audio`, the mirror of Clip ▸ Synchronize
/// Audio (road map "audio-sync", AS-1; spec §11 SY-1..SY-5), which takes the
/// same posture — `AudioSync.read` + `plan`, the menu's own pair, and nothing
/// measured here.
///
/// It is an APP-STATE composite rather than an op, for `detect_silence`'s
/// reason exactly: the level it measures comes from `cache/peaks/<media
/// id>.bin`, which is not in the model, and the core does no sample work at
/// all (spec §7). So `OP_NAMES` is untouched, nothing goes in
/// `opsWithoutTools`, and what actually reaches the document is the ordinary
/// `set_audio` the op table already carries — one per clip, since each clip
/// gets its own measured gain.
///
/// **Not a line of the arithmetic is here.** `AudioNormalize` is a value type
/// — peaks in, ops out — and this handler calls the same `read` + `plan` pair
/// the Audio pane's button calls. That is what makes "the button and the tool
/// do the same thing" a fact about the code rather than a claim in a comment;
/// re-deriving the gain here would be the drift that "one implementation per
/// algorithm" exists to prevent, and a proof that measured the tool would then
/// be saying nothing about the button.
///
/// Both are off-main tools (`AgentServer.offMainTools`), on that set's stated
/// criterion — "waits for something the main thread has to deliver or must
/// not be doing", not "touches the disk". `sync_audio`'s `plan` is seconds of
/// signal arithmetic on a long take (spec §11 SY-22); `normalize_clip` in
/// Loudness mode may render a clip through its chain and wait for it (AU-64,
/// AU-65). The read and the commit hop to main; the plan and the wait do not.
extension AgentServer {

    /// `normalize_clip` — the Audio section's Normalize button
    /// (`AudioPane.normalize`) and the Clip menu's Normalize item.
    ///
    /// Three properties of the command are worth stating wherever it is
    /// described, because each is a decision rather than an accident, and the
    /// button's tooltip, the catalog's description and this comment all say
    /// the same three (contract D-C3):
    ///
    /// 1. it REPLACES `audio.volume` rather than multiplying it, so pressing
    ///    it twice changes nothing — the peaks cache is pre-fader and knows
    ///    nothing about the volume the clip already carries;
    /// 2. it writes the clip's BASE props even while the playhead sits inside
    ///    an action, because it is a statement about the whole clip;
    /// 3. it leaves `muted` alone — a mute is a switch, not a level.
    ///
    /// The result reports what actually ran, `detect_silence`'s posture: every
    /// clip's measured peak and the volume written, every clip that could not
    /// be measured with the reason it could not, and a note when the model's
    /// volume ceiling (`AudioNormalize.maxGain`) stopped a clip short of the
    /// level asked for.
    ///
    /// **A second identical call is an identity edit** and comes back as the
    /// shared "Normalize made no change: the project is already in that
    /// state", exactly as a second `set_audio` with the same volume would:
    /// the idempotence working, not a failure.
    ///
    /// **Measuring nothing is a different answer, and is the one below**
    /// (spec §11's D2-1, which is why D2·4 left it standing). The level
    /// comes from `cache/peaks/<media id>.bin`, which is not in the model
    /// and which the core has never seen (spec §7), so with no reading
    /// there is no op and the shared reply would be the identity's — which
    /// would send a caller to look at its volumes when what happened is
    /// that its peaks were not there to read.
    ///
    /// Off the main thread (spec §11 AU-65, `AgentServer.offMainTools`):
    /// Loudness mode may render a clip through its chain (AU-64), seconds on a
    /// long clip, so every document touch goes through `onMain` and the wait
    /// is here; Peak mode is one `onMain` hop.
    func normalizeClip(_ a: [String: Any]) throws -> String {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16)
        try requireServerThread("normalize_clip")
        let (document, clips, mode) = try onMain {
            () throws -> (ProjectDocument, [UInt32], AudioNormalize.Mode) in
            let document = try self.target(a)
            let clips = try self.clipsArg(a, "clips", document)
            return (document, clips, try self.normalizeMode(a))
        }
        // Loudness mode (spec §11 AU-16, AU-25): the button's and the menu's
        // default (`NormalizeChoice`), and this tool's unless it names
        // `peak_db` alone.
        if mode == .loudness {
            return try normalizeLoudness(a, document: document, clips: clips, stop: stop)
        }
        return try onMain { try self.normalizePeak(a, document: document, clips: clips) }
    }

    /// `normalize_clip {mode: "peak"}`, on main: the button's Peak mode.
    private func normalizePeak(_ a: [String: Any], document: ProjectDocument, clips: [UInt32])
        throws -> String
    {
        guard try doubleArg(a, "target_lufs") == nil else {
            throw ToolError(
                message: "target_lufs is the loudness mode's target; with mode \"peak\" the "
                    + "level is peak_db. Pass mode \"loudness\" to normalize to a loudness.")
        }
        let peakDB = try normalizePeakDB(a)
        guard let input = AudioNormalize.read(from: document, clips: clips) else {
            throw ToolError(
                message: "The project's audio plan could not be read, so there is no level to "
                    + "measure.")
        }
        // Nothing was MEASURED — a question about the READ, not a guess at
        // what the core would answer, so it is asked of `input` and before
        // there is a plan. Each reason is already a sentence naming its
        // clip, and a caller that asked about five needs to know which of
        // the five it hit; there is no partial success to report beside
        // them.
        guard !input.isEmpty else {
            let reasons = input.problems.map { $0.description }.joined(separator: " ")
            throw ToolError(
                message: "Nothing could be normalized. \(reasons)")
        }
        let plan = AudioNormalize.plan(input, peakDB: peakDB)

        var fields: [String: Any] = [
            "mode": AudioNormalize.Mode.peak.rawValue,
            // The level that RAN, off the plan rather than off the argument:
            // `AudioNormalize.plan` substitutes the default for a non-finite
            // one, and a caller reading this back sees what was used.
            "peak_db": plan.peakDB,
            "normalized": plan.normalized.map { result in
                [
                    "clip": Int(result.clip),
                    "media": Int(result.media),
                    "measured_db": Self.jsonLevel(result.measuredDB),
                    "volume": result.volume,
                    "result_db": Self.jsonLevel(result.resultDB),
                    "clamped": result.clamped,
                ] as [String: Any]
            },
        ]
        // The same flat array of "clip N: …" sentences `transcribe` and
        // `import_captions` report, so an agent can hand any of the three back
        // to a person unchanged.
        if !plan.skipped.isEmpty {
            fields["skipped"] = plan.skipped.map { $0.description }
        }
        let clamped = plan.normalized.filter { $0.clamped }
        if !clamped.isEmpty {
            // The clamp is reported rather than refused (contract D-C7): a
            // clip quieter than about −31 dBFS cannot reach −1 with a volume
            // the model allows, so it is normalised to the loudest it can be
            // and told so. `result_db` on each row is where it actually
            // landed.
            let ids = clamped.map { String($0.clip) }.joined(separator: ", ")
            fields["note"] =
                "Clip(s) \(ids) wanted more gain than the model's "
                + "\(AudioNormalize.maxGainName) ceiling on volume, so each "
                + "was raised as far as it goes and lands below \(plan.peakDB) dBFS — result_db "
                + "says where."
        }
        return try editResult(document, "Normalize", plan.ops, fields)
    }

    /// `sync_audio` — Clip ▸ Synchronize Audio (`EditorViewController
    /// .synchronizeAudio`). All or nothing (SY-1): a refusal names every
    /// reason and moves nothing; a plan with no op (already in sync)
    /// answers `moved: false` and makes no undo step; otherwise each
    /// mover's `move_clip`, when its drift is corrected its `set_speed`
    /// (SY-6, SY-10), and when it would start before 0 its `trim_start`
    /// (SY-16), all one step. Each mover's row carries its match (its z, the
    /// search and rule that chose it, the candidates, SY-14), its measured
    /// drift (SY-7), the speed it plays at after the command and whether the
    /// drift was corrected, with the residual left (SY-8), and the head it
    /// lost. A plan with WEAK moves (SY-18, `AudioSync.weakMoves`, the
    /// menu's own test) answers `moved: false` with `weak` and a note and
    /// changes nothing, unless `accept_weak` is true — the Weak match sheet's
    /// Apply (SY-19).
    ///
    /// Off the main thread (SY-22, `AgentServer.offMainTools`): the
    /// arguments and `read` on main, `plan` here on the server's thread, then
    /// back on main the stale test — the project or scope changed meanwhile
    /// is an error, the Synchronizing Audio sheet's own rule — and the answer.
    func syncAudio(_ a: [String: Any]) throws -> String {
        let (document, input, acceptWeak, asked, scope) = try onMain {
            () throws -> (ProjectDocument, AudioSync.Input, Bool, ReelProject, UInt32?) in
            let document = try self.target(a)
            let clips = try self.clipsArg(a, "clips", document)
            let acceptWeak = try self.boolArg(a, "accept_weak") ?? false
            var anchor: UInt32?
            if try self.intArg(a, "anchor") != nil {
                let named = try self.idArg(a, "anchor")
                guard clips.contains(named) else {
                    throw ToolError(
                        message: "anchor must be one of clips: clip \(named) is not in clips.")
                }
                anchor = named
            }
            guard let input = AudioSync.read(from: document, clips: clips, anchor: anchor) else {
                throw ToolError(
                    message: "The project's audio plan could not be read, so there is no "
                        + "sound to line up.")
            }
            return (document, input, acceptWeak, document.project, document.scope)
        }
        let plan = AudioSync.plan(input)
        return try onMain {
            guard document.project === asked, document.scope == scope else {
                throw ToolError(
                    message: "the project changed while Synchronize Audio was matching, so "
                        + "nothing moved. Call sync_audio again.")
            }
            return try self.syncAnswer(plan, document: document, acceptWeak: acceptWeak)
        }
    }

    /// `sync_audio`'s answer to `plan`, on the main thread: the refusal, the
    /// already-in-sync and weak answers, or the edit.
    private func syncAnswer(_ plan: AudioSync.Plan, document: ProjectDocument, acceptWeak: Bool)
        throws -> String {
        switch plan {
        case .refused(let problems):
            let reasons = problems.map { $0.description }.joined(separator: " ")
            throw ToolError(message: "Synchronize Audio was refused: \(reasons)")
        case .planned(let anchorClip, let synced, let ops):
            let weak = AudioSync.weakMoves(synced)
            var fields: [String: Any] = [
                "anchor": Int(anchorClip),
                "synced": synced.map(Self.syncedRow),
                "weak": weak.map { Int($0.clip) },
            ]
            guard !ops.isEmpty else {
                fields["ok"] = true
                fields["moved"] = false
                fields["note"] = "already in sync"
                fields["project"] = summary(document)
                return try jsonResult(fields)
            }
            guard weak.isEmpty || acceptWeak else {
                // Not a refusal and never an error: the person decides (SY-19).
                fields["ok"] = true
                fields["moved"] = false
                fields["note"] = AudioSync.weakNote(weak)
                fields["project"] = summary(document)
                return try jsonResult(fields)
            }
            fields["moved"] = true
            return try editResult(document, "Synchronize Audio", ops, fields)
        }
    }

    /// One mover's row of `sync_audio`'s answer.
    private static func syncedRow(_ row: AudioSync.Synced) -> [String: Any] {
        var result: [String: Any] = [
            "clip": Int(row.clip),
            "media": Int(row.media),
            "offset": row.lag,
            "coarse_offset": row.coarseLag,
            "refined": row.refinement?.clear == true ? "phat" : "coarse",
            "refine_confidence": row.refinement.map { Self.jsonLevel($0.z) } ?? NSNull(),
            "delta": row.delta,
            "start": row.start,
            "confidence": row.confidence,
            "search": row.search.rawValue,
            "chosen_by": row.chosenBy.rawValue,
            "matched_on": row.matchedOn.rawValue,
            "candidates": row.candidates.map {
                ["offset": $0.offset, "delta": $0.delta, "confidence": $0.confidence] as [String: Any]
            },
            "trimmed": row.trimmed,
        ]
        result["speed"] = row.speed
        switch row.drift {
        case .measured(let drift):
            result["drift_ppm"] = drift.ppm
            result["drift_ms"] = drift.milliseconds
            result["drift_error_ms"] = Self.jsonLevel(drift.errorMilliseconds)
            result["drift_on"] = drift.on.rawValue
            result["drift_windows"] = drift.windows
        case .notMeasured(let note):
            result["drift_ppm"] = NSNull()
            result["drift_ms"] = NSNull()
            result["drift_error_ms"] = NSNull()
            result["drift_on"] = NSNull()
            result["drift_windows"] = NSNull()
            result["residual_ms"] = NSNull()
            result["drift_note"] = note
        }
        switch row.correction {
        case .apply:
            result["drift_corrected"] = true
            if case .measured(let drift) = row.drift {
                result["residual_ms"] = Self.jsonLevel(drift.errorMilliseconds)
            }
        case .leave(let note):
            result["drift_corrected"] = false
            if case .measured(let drift) = row.drift {
                result["residual_ms"] = drift.milliseconds
            }
            if let note = note { result["drift_note"] = note }
        }
        return result
    }

    /// `mode`, refused by name outside its two values; absent is Loudness
    /// (spec §11 AU-25), except beside a `peak_db`, which only Peak takes.
    private func normalizeMode(_ a: [String: Any]) throws -> AudioNormalize.Mode {
        guard let raw = try stringArg(a, "mode") else {
            return try doubleArg(a, "peak_db") == nil ? .loudness : .peak
        }
        guard let mode = AudioNormalize.Mode(rawValue: raw) else {
            throw ToolError(
                message: "mode must be \"peak\" or \"loudness\", not \"\(raw)\"; the default "
                    + "is \"loudness\" (\"peak\" when peak_db is given).")
        }
        return mode
    }

    /// `normalize_clip {mode: "loudness"}` — the Normalize button and Clip ▸
    /// Normalize in Loudness mode (`AudioMeasureDoor`), through the same
    /// `readLoudness`, `LoudnessMeasureRun` and `plan` (spec §11 AU-13,
    /// AU-14, AU-16, AU-64). `peak_db` is refused by name, and `target_lufs`
    /// outside −50…−5 is refused, never clamped. The read and the run's start
    /// are on main, the wait here, then on main the stale test (the project
    /// or scope changed meanwhile is an error, the Measuring Sound sheet's
    /// own rule) and the answer. The answer reports each clip's measured
    /// loudness and true peak (the readout's numbers; for a rendered clip the
    /// true peak is the processed one), its processed loudness and the renders
    /// it took (null and 0 off the cache), the volume written, the clip's
    /// limiter after the edit (AU-24), where it lands, and the volume ceiling
    /// when it stopped it short; a note names each such clip.
    private func normalizeLoudness(
        _ a: [String: Any], document: ProjectDocument, clips: [UInt32], stop: AgentCallCancel?
    ) throws -> String {
        let (run, requested, asked, scope) = try onMain {
            () throws -> (LoudnessMeasureRun, Double, ReelProject, UInt32?) in
            guard try self.doubleArg(a, "peak_db") == nil else {
                throw ToolError(
                    message: "peak_db is the peak mode's level; with mode \"loudness\" the "
                        + "target is target_lufs.")
            }
            let range = AudioNormalize.targetLUFSRange
            let requested = try self.doubleArg(a, "target_lufs")
                ?? AudioNormalize.defaultTargetLUFS
            guard requested.isFinite, range.contains(requested) else {
                throw ToolError(
                    message: "target_lufs must be a loudness from \(range.lowerBound) to "
                        + "\(range.upperBound) LUFS, and the default is "
                        + "\(AudioNormalize.defaultTargetLUFS).")
            }
            guard let input = AudioNormalize.readLoudness(from: document, clips: clips) else {
                throw ToolError(
                    message: "The project's audio plan could not be read, so there is no "
                        + "loudness to measure.")
            }
            guard !input.isEmpty else {
                let reasons = input.problems.map { $0.description }.joined(separator: " ")
                throw ToolError(message: "Nothing could be normalized. \(reasons)")
            }
            let run = LoudnessMeasureRun(
                document: document, jobs: AudioMeasureDoor.normalizeJobs(input, in: document),
                problems: input.problems, targetLUFS: requested)
            return (run, requested, document.project, document.scope)
        }
        let outcome = awaitMeasurement(run, stop: stop)
        return try onMain {
            defer { run.finish() }
            let outcome = try self.measuredOutcome(
                outcome, document: document, asked: asked, scope: scope, tool: "normalize_clip")
            let plan = AudioNormalize.plan(
                outcome.input, targetLUFS: requested, solved: outcome.solved)
            guard !plan.normalized.isEmpty else {
                let reasons = plan.skipped.map { $0.description }.joined(separator: " ")
                throw ToolError(message: "Nothing could be normalized. \(reasons)")
            }
            return try self.loudnessAnswer(plan, document: document)
        }
    }

    /// Loudness mode's answer to `plan`, on main.
    private func loudnessAnswer(_ plan: AudioNormalize.LoudnessPlan, document: ProjectDocument)
        throws -> String
    {
        var fields: [String: Any] = [
            "mode": AudioNormalize.Mode.loudness.rawValue,
            "target_lufs": plan.targetLUFS,
            "ceiling_dbtp": AudioNormalize.ceilingDBTP,
            "normalized": plan.normalized.map { result in
                [
                    "clip": Int(result.clip),
                    "media": Int(result.media),
                    "measured_lufs": Self.jsonLevel(result.measuredLUFS),
                    "true_peak_dbtp": Self.jsonLevel(result.truePeakDBTP),
                    "volume": result.volume,
                    "result_lufs": Self.jsonLevel(result.resultLUFS),
                    "result_true_peak_dbtp": Self.jsonLevel(result.resultTruePeakDBTP),
                    "limited_by": result.limit.map { $0.rawValue as Any } ?? NSNull(),
                    "limiter": result.limiter.map {
                        ["ceiling_db": $0.ceilingDb, "release": $0.release] as Any
                    } ?? NSNull(),
                    "processed_lufs": result.processedLUFS.map(Self.jsonLevel) ?? NSNull(),
                    "renders": result.renders,
                ] as [String: Any]
            },
        ]
        if !plan.skipped.isEmpty {
            fields["skipped"] = plan.skipped.map { $0.description }
        }
        let limited = plan.normalized.filter { $0.limit != nil }
        if !limited.isEmpty {
            let ids = limited.map { String($0.clip) }.joined(separator: ", ")
            fields["note"] =
                "Clip(s) \(ids) stopped short of \(plan.targetLUFS) LUFS: the volume that reaches "
                + "it would pass the \(AudioNormalize.maxGainName) ceiling (limited_by max_gain). "
                + "result_lufs says where each landed."
        }
        return try editResult(document, "Normalize", plan.ops, fields)
    }

    /// `peak_db`, in the button's own unit, refused by name.
    ///
    /// The pane has no control for it at all — it presses the constant — so
    /// this is the tool's own knob and the tool is the only place it can be
    /// wrong. It is REFUSED rather than clamped, the rule every argument in
    /// this server follows (`silenceSettings` argues it for `threshold_db`):
    /// clamping silently would normalise to a level the caller did not ask
    /// for and report success. `AudioNormalize.plan` carries its own
    /// finiteness fallback for the pane's sake; a NaN that arrived here is a
    /// caller's mistake and is named.
    private func normalizePeakDB(_ a: [String: Any]) throws -> Double {
        guard let peakDB = try doubleArg(a, "peak_db") else {
            return AudioNormalize.defaultPeakDB
        }
        let range = AudioNormalize.peakDBRange
        guard peakDB.isFinite, range.contains(peakDB) else {
            throw ToolError(
                message: "peak_db must be a level from \(range.lowerBound) to "
                    + "\(range.upperBound) dBFS — above 0 is a request to clip — and the "
                    + "default is \(AudioNormalize.defaultPeakDB).")
        }
        return peakDB
    }

    /// A decibel figure as something `JSONSerialization` will write: the number
    /// itself, or null where it is not finite.
    ///
    /// Not defensive decoration. `JSONSerialization.data` THROWS on an
    /// infinity, so an un-guarded −∞ would turn a completed export or a
    /// committed normalise into a tool error reported after the work was
    /// done — the worst of both answers. And −∞ is a real value on both sides
    /// of this file: `LoudnessReport.silence` measures digital silence that
    /// way, and a peak read out of a corrupt cache could be anything at all.
    ///
    /// Shared by `normalize_clip`'s per-clip levels and `export`'s loudness
    /// echo (`AgentServer+Export.swift`), which are the two places this server
    /// reports a level; it lives here because this is the file whose subject
    /// is sound.
    static func jsonLevel(_ value: Double) -> Any {
        value.isFinite ? value : NSNull()
    }
}
