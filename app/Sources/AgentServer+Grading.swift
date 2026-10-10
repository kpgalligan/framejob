// app/Sources/AgentServer+Grading.swift — the grading road map's op tools
// (spec §11 GR-6): `add_adjustment_clip`.

import Foundation

extension AgentServer {

    /// `add_adjustment_clip` — UI path: Insert ▸ Adjustment Clip (grading
    /// GR4b's menu item). An omitted `duration` is the core's 5 s, as
    /// `add_text_clip`'s is; every refusal is the core's sentence.
    func addAdjustmentClip(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let at = try timeArg(a, "at", document)
        let duration = try optionalTimeArg(a, "duration", document)
        return try editResult(
            document, "Add Adjustment Clip",
            [.addAdjustmentClip(track: track.id, at: at, duration: duration)])
    }
}
