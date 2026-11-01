import AppKit

/// `match_audio` — the agent's mirror of Clip ▸ Match Audio… (road map
/// "audio" AP12, spec §11 AU-120…AU-128; `EditorViewController.matchAudio`,
/// its sheet's hand-back pressing `AudioMeasureDoor.pressMatch`).
///
/// An APP-STATE composite like `enhance_voice`, for its reason: what it
/// measures is the loudness and speech caches and the clips rendered as they
/// play, none of which is in the model, so `OP_NAMES` is untouched and what
/// reaches the document is one ordinary `set_audio` per target. It takes no
/// `scope`: it follows the open container. Not a line of the arithmetic is
/// here — `AudioMatch.read` and `plan` and an `AudioMatchRun`, the menu's
/// own — and it is an off-main tool (`AgentServer.offMainTools`): the read,
/// the run's start and the commit are on main, the wait
/// (`awaitMeasurement`) here.
extension AgentServer {

    /// The reference's loudness, then each target's row: `set` (exactly the
    /// patch's keys in `set_audio`'s spelling), the EQ and its fit, and
    /// Normalize's figures for the volume; the skips by name. A second
    /// identical call is an identity: "Match Audio made no change".
    func matchAudio(_ a: [String: Any]) throws -> String {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16)
        try requireServerThread("match_audio")
        struct Read {
            let document: ProjectDocument
            let input: AudioMatch.Input
            let run: AudioMatchRun
            let asked: ReelProject
            let scope: UInt32?
        }
        let read = try onMain { () throws -> Read in
            let document = try self.target(a)
            let reference = try self.clipArg(a, "reference", document).id
            let clips = try self.clipsArg(a, "clips", document)
            let loudness = try self.boolArg(a, "loudness") ?? true
            let eq = try self.boolArg(a, "eq") ?? true
            guard loudness || eq else {
                throw ToolError(
                    message: "loudness and eq are both false, so there is nothing to match: "
                        + "leave one of them true (both are by default).")
            }
            switch AudioMatch.read(
                from: document, reference: reference, clips: clips, loudness: loudness, eq: eq)
            {
            case .failure(let refusal): throw ToolError(message: refusal.sentence)
            case .success(let input):
                return Read(
                    document: document, input: input,
                    run: AudioMatchRun(document: document, input: input),
                    asked: document.project, scope: document.scope)
            }
        }
        let outcome = awaitMeasurement(read.run, stop: stop)
        return try onMain {
            defer { read.run.finish() }
            let outcome = try self.measuredOutcome(
                outcome, document: read.document, asked: read.asked, scope: read.scope,
                tool: "match_audio")
            if let refusal = outcome.refusal { throw ToolError(message: refusal.sentence) }
            let plan = AudioMatch.plan(read.input, outcome: outcome)
            guard !plan.matched.isEmpty else {
                throw ToolError(message: AudioMatch.nothingMatched(plan.skipped))
            }
            return try self.matchAnswer(
                plan, input: read.input, referenceLUFS: outcome.referenceLUFS,
                document: read.document)
        }
    }

    /// The answer to `plan`, on main: the reference, the rows, the skips,
    /// the ceiling's note and the edit.
    private func matchAnswer(
        _ plan: AudioMatch.Plan, input: AudioMatch.Input, referenceLUFS: Double,
        document: ProjectDocument
    ) throws -> String {
        let reference = input.reference
        let speech = reference.speech.map { mask in
            Double(mask.filter { $0 }.count) * AudioLimiterModel.stepSeconds
        }
        var fields: [String: Any] = [
            "reference": [
                "clip": Int(reference.clip),
                "media": Int(reference.media),
                "lufs": Self.jsonLevel(referenceLUFS),
                "speech_seconds": speech.map { $0 as Any } ?? NSNull(),
            ] as [String: Any],
            "target_lufs": plan.targetLUFS.map(Self.jsonLevel) ?? NSNull(),
            "matched": plan.matched.map(Self.matchedRow),
        ]
        if !plan.skipped.isEmpty {
            fields["skipped"] = plan.skipped.map { $0.description }
        }
        let limited = plan.matched.filter { $0.loudness?.limit != nil }
        if !limited.isEmpty, let target = plan.targetLUFS {
            let ids = limited.map { String($0.clip) }.joined(separator: ", ")
            fields["note"] =
                "Clip(s) \(ids) stopped short of \(target) LUFS: the volume that reaches it "
                + "would pass the \(AudioNormalize.maxGainName) ceiling (limited_by max_gain). "
                + "result_lufs says where each landed."
        }
        return try editResult(document, AudioMatch.actionName, plan.ops, fields)
    }

    /// One target's row of the answer.
    private static func matchedRow(_ row: AudioMatch.Row) -> [String: Any] {
        func level(_ value: Double?) -> Any { value.map(jsonLevel) ?? NSNull() }
        let loudness = row.loudness
        return [
            "clip": Int(row.clip),
            "media": Int(row.media),
            "set": row.set.dictionary,
            "eq": row.eq.map { $0.dictionary as Any } ?? NSNull(),
            "eq_fit_rms_db": level(row.fitRMSDB),
            "volume": loudness.map { $0.volume as Any } ?? NSNull(),
            "measured_lufs": level(loudness?.measuredLUFS),
            "processed_lufs": level(loudness?.processedLUFS),
            "result_lufs": level(loudness?.resultLUFS),
            "result_true_peak_dbtp": level(loudness?.resultTruePeakDBTP),
            "limited_by": loudness?.limit.map { $0.rawValue as Any } ?? NSNull(),
            "renders": (loudness?.renders ?? 0) + (row.eq != nil ? 1 : 0),
        ]
    }
}
