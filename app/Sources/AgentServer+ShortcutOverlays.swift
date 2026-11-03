import Foundation

/// `add_shortcut_overlays` (road map "creator-jobs" CU8, spec §11 CU-84) — mirrors Clip ▸ Add
/// Shortcut Overlays (`EditorViewController+ShortcutOverlays.swift`) through the same run,
/// `ShortcutOverlays.prepared`. An app-state composite of `add_track` and `add_graphic_clip`:
/// no `scope` key (dispatch reads `scope` only for op names); it acts in the container
/// `set_scope` has open.
extension AgentServer {

    /// What the first main-thread hop resolves.
    private struct ShortcutOverlayCall {
        let document: ProjectDocument
        let clips: [UInt32]
        let files: [UInt32: URL]
        let settings: ShortcutOverlaySettings
        let from: Ticks?
        let to: Ticks?
        let asked: ReelProject
        let scope: UInt32?
    }

    /// **Runs on the SERVER thread** (`creatorOffMainTools`): one main hop resolves the clips
    /// and their cursor files, the files are read here, and a last main hop refuses when the
    /// project or the scope changed meanwhile, places and applies as one undo step "Add
    /// Shortcut Overlays".
    func addShortcutOverlays(_ a: [String: Any]) throws -> String {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "add_shortcut_overlays must run on the server thread — its name is "
                    + "missing from AgentServer.creatorOffMainTools.")
        }
        let call = try onMain { try self.resolveShortcutOverlays(a) }
        return try runShortcutOverlays(call)
    }

    /// The tool's body over `clips` of `document` with `settings` and no `from`/`to`: what
    /// `record_screen`'s polish on landing calls (road map "creator-jobs" CU10, spec §11
    /// CU-100). **SERVER THREAD**; one undo step "Add Shortcut Overlays", answered as the tool
    /// answers.
    func addShortcutOverlays(
        document: ProjectDocument, clips: [UInt32], settings: ShortcutOverlaySettings
    ) throws -> String {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "add_shortcut_overlays must run on the server thread — its name is "
                    + "missing from AgentServer.creatorOffMainTools.")
        }
        let call = try onMain {
            try self.shortcutOverlayCall(document, clips, settings: settings, from: nil, to: nil)
        }
        return try runShortcutOverlays(call)
    }

    /// Both forms' body after the first hop: the files read here, then the last main hop.
    private func runShortcutOverlays(_ call: ShortcutOverlayCall) throws -> String {
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
                    message: "the project changed while add_shortcut_overlays read the cursor "
                        + "files, so no overlay was added. Call add_shortcut_overlays again.")
            }
            let run: (plan: ShortcutOverlayPlan, module: String, written: Bool)
            do {
                run = try ShortcutOverlays.prepared(
                    document, clips: call.clips, tracks: tracks, settings: call.settings,
                    from: call.from, to: call.to)
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
            let plan = run.plan
            var fields: [String: Any] = [
                "added": plan.added, "dropped": plan.dropped, "merged": plan.merged,
                "track": plan.ops.isEmpty ? (NSNull() as Any) : (Int(plan.track) as Any),
                "new_track": plan.newTrack, "module": run.module, "written": run.written,
                "overlays": plan.overlays,
            ]
            guard !plan.ops.isEmpty else {
                fields["ok"] = true
                fields["note"] = ShortcutOverlays.nothingSentence
                fields["project"] = self.summary(document)
                return try self.jsonResult(fields)
            }
            if plan.dropped > 0 {
                fields["note"] = ShortcutOverlays.droppedSentence(plan.dropped)
            }
            return try self.editResult(document, ShortcutOverlays.actionName, plan.ops, fields)
        }
    }

    /// Exactly one of `clip` and `clips`; the arguments in the planner's order — `duration`,
    /// `position` and `theme`, then `from`/`to`, then each clip's cursor file.
    private func resolveShortcutOverlays(_ a: [String: Any]) throws -> ShortcutOverlayCall {
        func given(_ key: String) -> Bool { a[key] != nil && !(a[key] is NSNull) }
        guard given("clip") != given("clips") else {
            throw ToolError(
                message: "Name exactly one of clip and clips: the screen recording clip, or "
                    + "the clips, to place shortcut overlays for.")
        }
        var settings = ShortcutOverlaySettings()
        if let v = try doubleArg(a, "duration") {
            let range = ShortcutOverlaySettings.durationRange
            guard v.isFinite, range.contains(v) else {
                throw ToolError(
                    message: AutoZoom.sentence(
                        "duration is \(Self.plainNumber(v)) s; it runs "
                            + "\(Self.plainNumber(range.lowerBound))–"
                            + "\(Self.plainNumber(range.upperBound))"))
            }
            settings.duration = v
        }
        func word(_ key: String, _ allowed: [String]) throws -> String? {
            guard given(key) else { return nil }
            guard let v = a[key] as? String, allowed.contains(v) else {
                throw ToolError(
                    message: "\(key) is \(Self.quoted(a[key])); it is one of "
                        + allowed.joined(separator: ", ") + ".")
            }
            return v
        }
        settings.position =
            try word("position", ShortcutOverlaySettings.positions) ?? settings.position
        settings.theme = try word("theme", ShortcutOverlaySettings.themes) ?? settings.theme
        let from = try intArg(a, "from").map { Ticks($0) }
        let to = try intArg(a, "to").map { Ticks($0) }
        if let from, let to, to <= from {
            throw ToolError(message: "To (\(to)) must be after from (\(from)).")
        }
        let document = try target(a)
        let ids =
            given("clip") ? [try clipArg(a, "clip", document).id] : try clipsArg(a, "clips", document)
        return try shortcutOverlayCall(document, ids, settings: settings, from: from, to: to)
    }

    /// The clips' cursor files and the handle the last hop compares. Main.
    private func shortcutOverlayCall(
        _ document: ProjectDocument, _ ids: [UInt32], settings: ShortcutOverlaySettings,
        from: Ticks?, to: Ticks?
    ) throws -> ShortcutOverlayCall {
        let snapshot = document.editedProject.snapshot
        let clips = ids.compactMap { snapshot.clip($0) }
        let files: [UInt32: URL]
        do {
            files = try AutoZoom.cursorFiles(clips, in: snapshot)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        return ShortcutOverlayCall(
            document: document, clips: ids, files: files, settings: settings, from: from,
            to: to, asked: document.project, scope: document.scope)
    }

    /// A number as the core prints it: no ".0" on a whole one.
    private static func plainNumber(_ v: Double) -> String {
        v.rounded() == v && abs(v) < 1e15 ? String(Int64(v)) : String(v)
    }

    /// A caller's value for a sentence: a string quoted, anything else as JSON writes it.
    private static func quoted(_ v: Any?) -> String {
        if let s = v as? String { return "\"\(s)\"" }
        guard let v, JSONSerialization.isValidJSONObject([v]),
            let data = try? JSONSerialization.data(withJSONObject: [v])
        else { return "not a string" }
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}
