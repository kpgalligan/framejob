import Foundation

/// `speed_up_typing` (road map "creator-jobs" CU9b, spec §11 CU-93) — mirrors Clip ▸ Speed Up
/// Typing… (`EditorViewController+SpeedUpTyping.swift`, `SpeedUpTypingSheetController`) through
/// the same `SpeedUpTyping.resolve`. An app-state composite of `set_media_speech` and
/// `retime_range`: no `scope` key (dispatch reads `scope` only for op names); it acts in the
/// container `set_scope` has open, as `auto_zoom` does. An agent is told in its answer what a
/// person is asked (`SpeedAudioDrop`'s note), as `retime_range`'s tool does.
extension AgentServer {

    /// What the first main-thread hop resolves.
    private struct SpeedUpTypingCall {
        let document: ProjectDocument
        let clips: [UInt32]
        let files: [UInt32: URL]
        let settings: SpeedUpTypingSettings
        let from: Ticks?
        let to: Ticks?
        let asked: ReelProject
        let scope: UInt32?
    }

    /// **Runs on the SERVER thread** (`creatorOffMainTools`): one main hop resolves the clips
    /// and their cursor files, the files are read here, and a last main hop refuses when the
    /// project or the scope changed meanwhile, resolves the plan and its speech step, and
    /// applies both as one undo step "Speed Up Typing". Writes its own tail rather than
    /// `editResult`'s: the crossing is read on `SpeedAudioDrop`'s baseline of the
    /// speech-applied handle BEFORE the edit, where a split half is not yet new.
    func speedUpTyping(_ a: [String: Any]) throws -> String {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "speed_up_typing must run on the server thread — its name is missing "
                    + "from AgentServer.creatorOffMainTools.")
        }
        let call = try onMain { try self.resolveSpeedUpTyping(a) }
        let tracks: [UInt32: ReelCursor]
        do {
            tracks = try AutoZoom.readTracks(call.files)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        return try onMain {
            let document = call.document
            guard document.project === call.asked, document.scope == call.scope else {
                throw ToolError(
                    message: "the project changed while speed_up_typing read the cursor "
                        + "files, so nothing was sped up. Call speed_up_typing again.")
            }
            let snapshot = document.editedProject.snapshot
            let clips = call.clips.compactMap { snapshot.clip($0) }
            let outcome: SpeedUpTypingOutcome
            do {
                outcome = try SpeedUpTyping.resolve(
                    clips, tracks: tracks, project: document.editedProject,
                    cacheDirectory: document.cacheDirectory, settings: call.settings,
                    from: call.from, to: call.to)
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
            switch outcome {
            case .waiting(let names):
                // A pass that could not read a file is not retried until the next open, so
                // the door that sees pending starts it (idempotent).
                document.generateCaches()
                throw ToolError(
                    message: "\(names.joined(separator: ", "))'s speech has not been detected "
                        + "yet. Try again in a moment.")
            case .planned(let speechOps, let plan):
                return try self.applySpeedUpTyping(
                    document, speechOps: speechOps, plan: plan, shortest: call.settings.shortest)
            }
        }
    }

    /// The edit and its answer, on main.
    private func applySpeedUpTyping(
        _ document: ProjectDocument, speechOps: [ReelOp], plan: SpeedUpTypingPlan,
        shortest: Double
    ) throws -> String {
        let ranges: [[String: Any]] = plan.ranges.map {
            ["from": $0.from, "to": $0.to, "sped_to": $0.spedTo]
        }
        var result: [String: Any] = [
            "ok": true, "stretches": plan.stretches, "short": plan.short, "ranges": ranges,
            "saved": plan.saved,
        ]
        guard !plan.ops.isEmpty else {
            result["note"] = "no typing stretch without speech or a shortcut lasted "
                + "\(SpeedUpTyping.plain(shortest)) s or more in the clips' played windows, "
                + "so nothing was changed"
            result["project"] = summary(document)
            return try jsonResult(result)
        }
        let ops = speechOps + plan.ops
        let landing = scopeLanding(ops, document)
        let edited =
            effectiveScope(document).flatMap { document.project.scoped($0) } ?? document.project
        let spoken = (try? edited.applying(speechOps))?.project ?? edited
        let crossing = SpeedAudioDrop.crossing(applying: plan.ops, to: spoken)
        let before = try performGroupedEdit(document, SpeedUpTyping.actionName, ops)
        result["speech_saved"] = speechOps.compactMap { ($0.args["media"] as? UInt32).map(Int.init) }
        result.merge(Self.created(from: before, to: document.project.snapshot)) { _, new in new }
        result.merge(SpeedAudioDrop.answerFields(crossing)) { _, new in new }
        result.merge(landing) { _, new in new }
        result["project"] = summary(document)
        return try jsonResult(result)
    }

    /// Exactly one of `clip` and `clips`; then `from`/`to` and each clip's cursor file. The
    /// rate's and shortest's ranges are the core's refusals (CU-92).
    private func resolveSpeedUpTyping(_ a: [String: Any]) throws -> SpeedUpTypingCall {
        func given(_ key: String) -> Bool { a[key] != nil && !(a[key] is NSNull) }
        guard given("clip") != given("clips") else {
            throw ToolError(
                message: "Name exactly one of clip and clips: the screen recording clip, or "
                    + "the clips, whose typing to speed up.")
        }
        var settings = SpeedUpTypingSettings()
        settings.rate = try doubleArg(a, "rate") ?? settings.rate
        settings.shortest = try doubleArg(a, "shortest") ?? settings.shortest
        settings.keepPitch = try boolArg(a, "keep_pitch") ?? settings.keepPitch
        let from = try intArg(a, "from").map { Ticks($0) }
        let to = try intArg(a, "to").map { Ticks($0) }
        let document = try target(a)
        let ids =
            given("clip") ? [try clipArg(a, "clip", document).id] : try clipsArg(a, "clips", document)
        let snapshot = document.editedProject.snapshot
        let clips = ids.compactMap { snapshot.clip($0) }
        let files: [UInt32: URL]
        do {
            files = try AutoZoom.cursorFiles(clips, in: snapshot)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        return SpeedUpTypingCall(
            document: document, clips: ids, files: files, settings: settings, from: from,
            to: to, asked: document.project, scope: document.scope)
    }
}
