import Foundation

/// The agent's half of the caption re-time (#341, spec §11 SR-27): the six
/// op tools that can change a clip's source map — `set_speed`,
/// `rate_stretch`, `add_speed_ramp`, `set_action`, `set_action_end` and
/// `remove_action` — append the re-time a person's door appends, in the same
/// step, and their answer names what moved (`captions_retimed`) and what went
/// (`captions_removed`), each only when non-empty.
extension AgentServer {
    /// The plan for `ops` on the container this call acts in —
    /// `effectiveScope`'s nest, else the timeline. The ops are the handler's
    /// own, unscoped; `performGroupedEdit` stamps one scope on all of them.
    func captionRetime(_ ops: [ReelOp], _ document: ProjectDocument) -> CaptionRetime.Plan {
        let container = effectiveScope(document).flatMap { document.project.scoped($0) }
        return CaptionRetime.plan(ops, on: container ?? document.project)
    }

    /// `editResult` with the re-time appended: one step named for the edit
    /// ("… and Re-time Captions" when anything re-times) and the answer's two
    /// keys.
    func retimingEditResult(
        _ document: ProjectDocument, _ actionName: String, _ ops: [ReelOp]
    ) throws -> String {
        let plan = captionRetime(ops, document)
        return try editResult(
            document, plan.undoName(actionName), ops + plan.ops, plan.answerFields)
    }
}
