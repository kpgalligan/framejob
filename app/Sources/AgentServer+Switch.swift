import Foundation

/// `copy_pieces` and `switch_angle` (road map "creator-jobs" SW1, spec §11
/// SW-11…SW-15), mirroring Clip ▸ Switch Angle ▸ (`switchAngle` in
/// `EditorViewController+SwitchAngle.swift`): `switch_angle` runs the menu's
/// own planner (`SwitchAngle.plan`) and commits it as one undo step;
/// `copy_pieces` is the op it writes with, one op, one undo step "Copy
/// Pieces".
extension AgentServer {

    func copyPieces(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        _ = try idArg(a, "clip")
        _ = try idArg(a, "track")
        guard let ranges = try rangesArg(a, "ranges", document) else {
            throw ToolError(
                message: "Missing required argument: ranges (an array of [from, to] pairs, "
                    + "each a time in ticks).")
        }
        guard !ranges.isEmpty else {
            throw ToolError(message: "ranges is empty — name at least one [from, to] pair.")
        }
        let clip = try clipArg(a, "clip", document)
        let track = try trackArg(a, "track", document)
        let op = ReelOp.copyPieces(
            clip: clip.id, track: track.id, ranges: ranges,
            video: try boolArg(a, "video"), audio: try boolArg(a, "audio"))
        return try editResult(document, "Copy Pieces", [op])
    }

    /// The container `set_scope` has open, as `text_behind_subject` reads it:
    /// no `scope` key, on the main thread, committed through
    /// `performGroupedEdit` (which stamps that scope on the ops).
    func switchAngle(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try idArg(a, "clip")
        let angle = try idArg(a, "angle")
        let container =
            effectiveScope(document).flatMap { document.project.scoped($0) } ?? document.project
        let answer: SwitchAngle.Answer
        do {
            answer = try SwitchAngle.plan(clip: clip, angle: angle, in: container)
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        switch answer {
        case .refused(let reason):
            throw ToolError(message: reason)
        case .plan(let plan):
            _ = try performGroupedEdit(document, plan.actionName, plan.ops)
            // Written by hand so the keys keep SW-15's order.
            let step = try JSONSerialization.data(
                withJSONObject: plan.actionName, options: .fragmentsAllowed)
            let project = try JSONSerialization.data(withJSONObject: summary(document))
            let pieces = plan.pieces.map(String.init).joined(separator: ",")
            let text = "{\"ok\":true,\"step\":\(String(decoding: step, as: UTF8.self)),"
                + "\"pieces\":[\(pieces)],\"transitions_removed\":\(plan.transitionsRemoved),"
                + "\"project\":\(String(decoding: project, as: UTF8.self))}"
            return try callResult(content: [["type": "text", "text": text]], isError: false)
        }
    }
}
