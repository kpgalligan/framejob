import Foundation

/// `retime_range` (spec §11 CU-90 (e); road map "creator-jobs" CU9a),
/// mirroring Clip ▸ Retime Range… (`showRetimeSheet` in
/// `EditorViewController+Retime.swift`, whose sheet commits one
/// `retime_range` through `SpeedAudioDrop.commit`): an agent is told in its
/// answer what a person is asked.
extension AgentServer {

    /// Writes its own tail rather than `editResult`'s: the generic answer
    /// diffs the project before and after, where a split half is new and so
    /// never counted, and would overwrite this list with a partial one. The
    /// crossing is read on `SpeedAudioDrop`'s baseline BEFORE the edit, in the
    /// container the call edits.
    func retimeRange(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let from = try timeArg(a, "from", document)
        let to = try timeArg(a, "to", document)
        guard to > from else {
            throw ToolError(message: "to must be after from (got \(from) and \(to)).")
        }
        guard let rate = try doubleArg(a, "rate") else {
            throw ToolError(message: "Missing required argument: rate (1 = normal speed).")
        }
        guard rate.isFinite && rate > 0 else {
            throw ToolError(message: "rate must be a positive number (1 = normal speed).")
        }
        let keepPitch = try boolArg(a, "keep_pitch")
        let ops: [ReelOp] = [.retimeRange(from: from, to: to, rate: rate, keepPitch: keepPitch)]
        let landing = scopeLanding(ops, document)
        let crossing = SpeedAudioDrop.crossing(
            applying: ops,
            to: effectiveScope(document).flatMap { document.project.scoped($0) }
                ?? document.project)
        let before = try performGroupedEdit(document, "Retime Range", ops)
        var result: [String: Any] = ["ok": true]
        result.merge(Self.created(from: before, to: document.project.snapshot)) { _, new in new }
        result.merge(SpeedAudioDrop.answerFields(crossing)) { _, new in new }
        result.merge(landing) { _, new in new }
        result["project"] = summary(document)
        return try jsonResult(result)
    }
}
