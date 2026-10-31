import AppKit

/// `enhance_voice` — the agent's mirror of Clip ▸ Enhance Voice and the
/// Volume section's Enhance Voice button (road map "audio" AP6, spec §11
/// AU-60, AU-64, AU-65; `EditorViewController.enhanceVoice`,
/// `AudioPane+Enhance`, both through `AudioMeasureDoor`).
///
/// An APP-STATE composite like `normalize_clip`, for its reason: what it
/// measures is the loudness and speech caches and the clip rendered through
/// its own chain, none of which is in the model, so `OP_NAMES` is untouched
/// and what reaches the document is one ordinary `set_audio` per clip. It
/// takes no `scope`: it follows the open container, as `normalize_clip` does
/// (`AgentServer+Scope.swift`). Not a line of the arithmetic is here —
/// `AudioEnhance.read`, `choose`, `jobs` and `plan` and a
/// `LoudnessMeasureRun`, the button's and the menu's own — and it is an
/// off-main tool (`AgentServer.offMainTools`): the read, the run's start and
/// the commit are on main, the wait for the renders here. This file also
/// holds the wait and the stale test `normalize_clip`'s Loudness mode shares.
extension AgentServer {

    /// Each clip's measurements, the settings written (`set`, exactly the
    /// patch's keys in `set_audio`'s spelling) and one sentence per rule,
    /// then the solve's figures for the volume (`processed_lufs`, `renders`
    /// and where the last render lands); the skips by name. A second
    /// identical call is an identity: "Enhance Voice made no change".
    func enhanceVoice(_ a: [String: Any]) throws -> String {
        try requireServerThread("enhance_voice")
        let (document, clips, requested) = try onMain {
            () throws -> (ProjectDocument, [UInt32], Double) in
            let document = try self.target(a)
            let clips = try self.clipsArg(a, "clips", document)
            let range = AudioNormalize.targetLUFSRange
            let requested = try self.doubleArg(a, "target_lufs")
                ?? AudioNormalize.defaultTargetLUFS
            guard requested.isFinite, range.contains(requested) else {
                throw ToolError(
                    message: "target_lufs must be a loudness from \(range.lowerBound) to "
                        + "\(range.upperBound) LUFS, and the default is "
                        + "\(AudioNormalize.defaultTargetLUFS).")
            }
            return (document, clips, requested)
        }
        return try enhanceVoice(document: document, clips: clips, targetLUFS: requested)
    }

    /// `enhance_voice`'s body over clips and a target already read — also
    /// `record_screen {enhance}`'s (spec §11 AU-68 (f)): a read hop, the wait
    /// here, the commit hop. SERVER THREAD.
    func enhanceVoice(document: ProjectDocument, clips: [UInt32], targetLUFS requested: Double)
        throws -> String
    {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16)
        try requireServerThread("enhance_voice")
        struct Read {
            let document: ProjectDocument
            let input: AudioEnhance.Input
            let choices: [AudioEnhance.Choice]
            let run: LoudnessMeasureRun
            let target: Double
            let asked: ReelProject
            let scope: UInt32?
        }
        let read = try onMain { () throws -> Read in
            guard let input = AudioEnhance.read(from: document, clips: clips) else {
                throw ToolError(
                    message: "The project's audio plan could not be read, so there is no "
                        + "voice to measure.")
            }
            // Nothing MEASURED is a different answer from nothing CHANGED, as
            // in `normalize_clip`: every reason, each naming its clip.
            guard !input.isEmpty else {
                let reasons = input.problems.map { $0.description }.joined(separator: " ")
                throw ToolError(message: "Nothing could be enhanced. \(reasons)")
            }
            let choices = AudioEnhance.choose(input)
            let run = LoudnessMeasureRun(
                document: document, jobs: AudioEnhance.jobs(input, choices),
                problems: input.problems, targetLUFS: requested)
            return Read(
                document: document, input: input, choices: choices, run: run,
                target: requested, asked: document.project, scope: document.scope)
        }
        let outcome = awaitMeasurement(read.run, stop: stop)
        return try onMain {
            defer { read.run.finish() }
            let outcome = try self.measuredOutcome(
                outcome, document: read.document, asked: read.asked, scope: read.scope,
                tool: "enhance_voice")
            let plan = AudioEnhance.plan(
                read.input, choices: read.choices, outcome: outcome, targetLUFS: read.target)
            guard !plan.enhanced.isEmpty else {
                let reasons = plan.skipped.map { $0.description }.joined(separator: " ")
                throw ToolError(message: "Nothing could be enhanced. \(reasons)")
            }
            return try self.enhanceAnswer(plan, document: read.document)
        }
    }

    /// The answer to `plan`, on main: the rows, the skips, the ceiling's note
    /// and the edit.
    private func enhanceAnswer(_ plan: AudioEnhance.Plan, document: ProjectDocument)
        throws -> String
    {
        var fields: [String: Any] = [
            "target_lufs": plan.targetLUFS,
            "ceiling_dbtp": AudioNormalize.ceilingDBTP,
            "enhanced": plan.enhanced.map(Self.enhancedRow),
        ]
        if !plan.skipped.isEmpty {
            fields["skipped"] = plan.skipped.map { $0.description }
        }
        let limited = plan.enhanced.filter { $0.loudness.limit != nil }
        if !limited.isEmpty {
            let ids = limited.map { String($0.clip) }.joined(separator: ", ")
            fields["note"] =
                "Clip(s) \(ids) stopped short of \(plan.targetLUFS) LUFS: the volume that reaches "
                + "it would pass the \(AudioNormalize.maxGainName) ceiling (limited_by max_gain). "
                + "result_lufs says where each landed."
        }
        return try editResult(document, AudioEnhance.actionName, plan.ops, fields)
    }

    /// One clip's row of the answer.
    private static func enhancedRow(_ row: AudioEnhance.Row) -> [String: Any] {
        let m = row.measurement
        func level(_ value: Double?) -> Any { value.map(jsonLevel) ?? NSNull() }
        return [
            "clip": Int(row.clip),
            "media": Int(row.media),
            "measured_lufs": jsonLevel(m.lufs),
            "true_peak_dbtp": jsonLevel(m.truePeak > 0 ? 20 * log10(m.truePeak) : -.infinity),
            "speech_seconds": Double(m.speechSteps) * AudioLimiterModel.stepSeconds,
            "floor_lufs": level(m.floorLUFS),
            "floor_gap_db": level(m.floorGapDB),
            "pause_peak_dbfs": level(m.pausePeakMedianDB),
            "sibilance_share": m.sibilantShare,
            "speech_range_lu": level(m.speechRangeLU),
            "set": row.patch.dictionary,
            "reasons": row.reasons,
            "volume": row.loudness.volume,
            "processed_lufs": level(row.processedLUFS),
            "renders": row.renders,
            "result_lufs": jsonLevel(row.loudness.resultLUFS),
            "result_true_peak_dbtp": jsonLevel(row.loudness.resultTruePeakDBTP),
            "limited_by": row.loudness.limit.map { $0.rawValue as Any } ?? NSNull(),
        ]
    }

    // MARK: - The measurement's wait (shared with `normalize_clip`)

    /// Refuses a call that reached a measuring tool on the main thread, where
    /// its wait would hold the very thread the run answers on.
    func requireServerThread(_ tool: String) throws {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "\(tool) must run on the server thread — its name is missing from "
                    + "AgentServer.offMainTools.")
        }
    }

    /// Starts `run` on main and waits here for its outcome; the assistant's
    /// Stop cancels it (nil). Never main.
    func awaitMeasurement<Run: AudioMeasureRunning>(_ run: Run, stop: AgentCallCancel?)
        -> Run.Outcome?
    {
        let box = AudioMeasureOutcomeBox<Run.Outcome>()
        let done = DispatchSemaphore(value: 0)
        stop?.onCancel { run.cancel() }
        onMain {
            run.start { outcome in
                box.outcome = outcome
                done.signal()
            }
        }
        done.wait()
        return box.outcome
    }

    /// On main: the outcome, or an error when the run was stopped or the
    /// project or scope changed while it measured (the sheet's own test).
    func measuredOutcome<O>(
        _ outcome: O?, document: ProjectDocument, asked: ReelProject,
        scope: UInt32?, tool: String
    ) throws -> O {
        guard let outcome else {
            throw ToolError(
                message: "\(tool) was stopped while its sound was being measured, so nothing "
                    + "changed.")
        }
        guard document.project === asked, document.scope == scope else {
            throw ToolError(message: AudioMeasureDoor.staleReason(again: "Call \(tool) again."))
        }
        return outcome
    }
}
