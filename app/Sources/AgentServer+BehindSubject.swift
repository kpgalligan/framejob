import Foundation

/// `text_behind_subject` (road map creator-jobs CO5, spec §11 CO-54), mirroring Insert ▸ Text
/// Behind Subject (`insertTextBehindSubject` in `EditorViewController+BehindSubject.swift`):
/// the same `BehindSubjectPlan`, applied as one undo step "Text Behind Subject". On the main
/// thread; top-level only, as the menu item is. The selection is left as it was.
extension AgentServer {

    func textBehindSubject(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        guard document.scope == nil else {
            throw ToolError(
                message: "text_behind_subject works on the top-level timeline: set_scope with "
                    + "no nest first.")
        }
        let at = try optionalTimeArg(a, "at", document) ?? document.playhead
        var clip: UInt32?
        if let raw = a["clip"], !(raw is NSNull) { clip = try idArg(a, "clip") }
        let content = try stringArg(a, "content")
        if let content, content.isEmpty {
            throw ToolError(message: "content must not be empty")
        }
        let snapshot = document.project.snapshot
        let plan: BehindSubjectPlan.Plan
        switch BehindSubjectPlan.plan(
            in: snapshot, at: at, selection: document.selection, clip: clip)
        {
        case .success(let planned): plan = planned
        case .failure(let refusal): throw ToolError(message: refusal.sentence)
        }
        _ = try performGroupedEdit(
            document, BehindSubjectPlan.actionName,
            BehindSubjectPlan.ops(plan, content: content))
        return try jsonResult([
            "ok": true, "clip": plan.clip, "track": plan.track, "text": plan.text,
            "duration": plan.duration, "cutout_added": plan.addsCutout,
            "project": summary(document),
        ])
    }
}
