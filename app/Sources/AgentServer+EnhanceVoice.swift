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
    /// identical call is an identity: "Enhance Voice made no change". One
    /// main-thread hop reads the arguments and the setup (#412).
    func enhanceVoice(_ a: [String: Any]) throws -> String {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16)
        try requireServerThread("enhance_voice")
        let read = try onMain { () throws -> EnhanceRead in
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
            return try self.enhanceRead(document: document, clips: clips, targetLUFS: requested)
        }
        return try enhanceMeasured(read, stop: stop)
    }

    /// The body over clips and a target already read, `record_screen
    /// {enhance}`'s (spec §11 AU-68 (f)): one read hop, the wait here, the
    /// commit hop. SERVER THREAD.
    func enhanceVoice(document: ProjectDocument, clips: [UInt32], targetLUFS: Double)
        throws -> String
    {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16)
        try requireServerThread("enhance_voice")
        let read = try onMain {
            try self.enhanceRead(document: document, clips: clips, targetLUFS: targetLUFS)
        }
        return try enhanceMeasured(read, stop: stop)
    }

    /// What one read hop holds: the setup the press shares
    /// (`AudioMeasureDoor.enhanceSetup`), its run, and the project and scope
    /// the stale test compares.
    private struct EnhanceRead {
        let document: ProjectDocument
        let setup: AudioMeasureDoor.EnhanceSetup
        let run: LoudnessMeasureRun
        let asked: ReelProject
        let scope: UInt32?
    }

    /// The setup and, after its refusals, its run. MAIN.
    private func enhanceRead(document: ProjectDocument, clips: [UInt32], targetLUFS: Double)
        throws -> EnhanceRead
    {
        guard
            let setup = AudioMeasureDoor.enhanceSetup(
                document: document, clips: clips, targetLUFS: targetLUFS)
        else {
            throw ToolError(
                message: "The project's audio plan could not be read, so there is no "
                    + "voice to measure.")
        }
        // Nothing MEASURED is a different answer from nothing CHANGED, as
        // in `normalize_clip`: every reason, each naming its clip.
        guard !setup.input.isEmpty else {
            let reasons = setup.input.problems.map { $0.description }.joined(separator: " ")
            throw ToolError(message: "Nothing could be enhanced. \(reasons)")
        }
        return EnhanceRead(
            document: document, setup: setup, run: setup.makeRun(document: document),
            asked: document.project, scope: document.scope)
    }

    /// The wait for `read`'s run, then the commit hop. SERVER THREAD.
    private func enhanceMeasured(_ read: EnhanceRead, stop: AgentCallCancel?) throws -> String {
        let outcome = awaitMeasurement(read.run, stop: stop)
        return try onMain {
            defer { read.run.finish() }
            let outcome = try self.measuredOutcome(
                outcome, document: read.document, asked: read.asked, scope: read.scope,
                tool: "enhance_voice")
            let plan = read.setup.plan(outcome)
            guard !plan.enhanced.isEmpty else {
                let reasons = plan.skipped.map { $0.description }.joined(separator: " ")
                throw ToolError(message: "Nothing could be enhanced. \(reasons)")
            }
            return try self.enhanceAnswer(plan, document: read.document)
        }
    }

    /// The answer to `plan`, on main: the rows, the skips, the limits' note
    /// (AU-167, AU-168) and the edit.
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
        if let note = AudioNormalize.limitNote(
            plan.enhanced.map(\.loudness), in: document, targetLUFS: plan.targetLUFS)
        {
            fields["note"] = note
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
