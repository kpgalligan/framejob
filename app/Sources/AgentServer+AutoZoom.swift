import Foundation

/// `auto_zoom` (road map "creator-jobs" CU7, spec §11 CU-76) — mirrors Clip ▸ Auto Zoom…
/// (`EditorViewController+AutoZoom.swift`, `AutoZoomSheetController`) through the same planner,
/// `AutoZoom.plan`. An app-state composite of `remove_action`, `set_video` and
/// `add_zoom_action`: no `scope` key (dispatch reads `scope` only for op names); it acts in the
/// container `set_scope` has open.
extension AgentServer {

    /// What the first main-thread hop resolves.
    private struct AutoZoomCall {
        let document: ProjectDocument
        let clips: [UInt32]
        let files: [UInt32: URL]
        let settings: AutoZoomSettings
        let from: Ticks?
        let to: Ticks?
        let asked: ReelProject
        let scope: UInt32?
    }

    /// **Runs on the SERVER thread** (`creatorOffMainTools`): one main hop resolves the clips
    /// and their cursor files, the files are read here, and a last main hop refuses when the
    /// project or the scope changed meanwhile, plans and applies as one undo step "Auto Zoom".
    func autoZoom(_ a: [String: Any]) throws -> String {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "auto_zoom must run on the server thread — its name is missing from "
                    + "AgentServer.creatorOffMainTools.")
        }
        let call = try onMain { try self.resolveAutoZoom(a) }
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
                    message: "the project changed while auto_zoom read the cursor files, so "
                        + "nothing was zoomed. Call auto_zoom again.")
            }
            let snapshot = document.editedProject.snapshot
            let clips = call.clips.compactMap { snapshot.clip($0) }
            let plan: AutoZoomPlan
            do {
                plan = try AutoZoom.plan(
                    clips, tracks: tracks, project: document.editedProject,
                    settings: call.settings, from: call.from, to: call.to)
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
            let fields: [String: Any] = [
                "visits": plan.visits, "added": plan.added, "replaced": plan.replaced,
                "dropped": plan.dropped, "closed_at_cut": plan.closedAtCut,
                "bases_set": plan.basesSet, "actions": plan.actions,
            ]
            guard !plan.ops.isEmpty else {
                var answer = fields
                answer["ok"] = true
                answer["note"] = "no click or typing in the clips' played windows called for "
                    + "a zoom, so nothing was changed"
                answer["project"] = self.summary(document)
                return try self.jsonResult(answer)
            }
            return try self.editResult(document, AutoZoom.actionName, plan.ops, fields)
        }
    }

    /// Exactly one of `clip` and `clips`; the arguments in the planner's order — the ranges,
    /// then `from`/`to`, then each clip's cursor file.
    private func resolveAutoZoom(_ a: [String: Any]) throws -> AutoZoomCall {
        func given(_ key: String) -> Bool { a[key] != nil && !(a[key] is NSNull) }
        guard given("clip") != given("clips") else {
            throw ToolError(
                message: "Name exactly one of clip and clips: the screen recording clip, or "
                    + "the clips, to plan zooms on.")
        }
        var settings = AutoZoomSettings()
        func number(_ key: String, _ unit: String, _ range: ClosedRange<Double>) throws
            -> Double?
        {
            guard let v = try doubleArg(a, key) else { return nil }
            guard v.isFinite, range.contains(v) else {
                let lo = Self.plain(range.lowerBound), hi = Self.plain(range.upperBound)
                throw ToolError(
                    message: AutoZoom.sentence(
                        "\(key) is \(Self.plain(v))\(unit); it runs \(lo)–\(hi)"))
            }
            return v
        }
        settings.zoom = try number("zoom", "", AutoZoomSettings.zoomRange) ?? settings.zoom
        settings.lead = try number("lead", " s", AutoZoomSettings.leadRange) ?? settings.lead
        settings.stay = try number("stay", " s", AutoZoomSettings.stayRange) ?? settings.stay
        settings.follow = try boolArg(a, "follow") ?? settings.follow
        settings.typing = try boolArg(a, "typing") ?? settings.typing
        settings.replace = try boolArg(a, "replace") ?? settings.replace
        let from = try intArg(a, "from").map { Ticks($0) }
        let to = try intArg(a, "to").map { Ticks($0) }
        if let from, let to, to <= from {
            throw ToolError(message: "To (\(to)) must be after from (\(from)).")
        }
        let document = try target(a)
        let ids = given("clip") ? [try clipArg(a, "clip", document).id] : try clipsArg(a, "clips", document)
        let snapshot = document.editedProject.snapshot
        let clips = ids.compactMap { snapshot.clip($0) }
        let files: [UInt32: URL]
        do {
            files = try AutoZoom.cursorFiles(clips, in: snapshot)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        return AutoZoomCall(
            document: document, clips: ids, files: files, settings: settings, from: from,
            to: to, asked: document.project, scope: document.scope)
    }

    /// A number as the core prints it: no ".0" on a whole one.
    private static func plain(_ v: Double) -> String {
        v.rounded() == v && abs(v) < 1e15 ? String(Int64(v)) : String(v)
    }
}
