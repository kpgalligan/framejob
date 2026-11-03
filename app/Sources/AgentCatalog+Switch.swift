import Foundation

/// The catalog rows of `copy_pieces` and `switch_angle` (road map
/// "creator-jobs" SW1, spec §11 SW-11…SW-15), spliced in last by
/// `creatorTools()`, after `switch_layout`'s.
extension AgentServer {

    func switchTools() -> [[String: Any]] {
        let ticks = "in TICKS — 600000 per second, so 1 s = 600000 and one 30 fps frame = 20000"
        return [
            // The primitive Clip ▸ Switch Angle ▸ (`switchAngle` in
            // EditorViewController+SwitchAngle.swift) writes with: one per
            // angle clip the shot's span crosses.
            opTool(
                "copy_pieces",
                "Copies pieces of a clip onto another track at the same project times — the "
                    + "op Clip ▸ Switch Angle ▸ writes with. Each piece is exactly what two "
                    + "splits at its range's ends would leave in the middle: the same source "
                    + "frames at the same times (speed, a ramp, reversal, a graphic's own "
                    + "timeline, timed words and actions cut as split cuts them), so a piece "
                    + "of a synced camera angle shows that angle's own frame at every time. "
                    + "Pieces get fresh ids, no transition and no link. One undo step, \"Copy "
                    + "Pieces\". Each range's ends are snapped to the frame grid and a reversed "
                    + "pair is the same range; a range empty on the grid is skipped. Refused, "
                    + "nothing changed, in this order: a nest clip, a range outside the clip, "
                    + "two ranges that overlap (touching is fine), a locked destination, and a "
                    + "destination holding a clip over a range (naming that clip and its ends). "
                    + "Inside a nest (scope) the times and tracks are the nest's.",
                [
                    "clip": "The clip to copy pieces of.",
                    "track": "The track the pieces land on; it must be free over every range.",
                    "ranges": "[[from, to], …] project times, \(ticks), inside the clip and "
                        + "not overlapping. At least one pair.",
                    "video": "Set each piece's picture on (true) or off (false). Default: the "
                        + "clip's own.",
                    "audio": "Set each piece's sound on (true) or off (false). Default: the "
                        + "clip's own.",
                ]),
            // It mirrors Clip ▸ Switch Angle ▸ (`switchAngle` in
            // EditorViewController+SwitchAngle.swift), through the same planner
            // (SwitchAngle.swift). An app-state composite of ordinary ops: no
            // `scope`, one undo step.
            tool(
                "switch_angle",
                "Re-picks one shot from another camera angle — the mirror of Clip ▸ Switch "
                    + "Angle ▸. An angle is a TRACK whose video clips (media with a picture; a "
                    + "clip with its picture off or on a hidden track still counts) cover the "
                    + "shot's whole span. The shot is deleted and the angle copied over the same "
                    + "span with copy_pieces, one piece per angle clip the span crosses (where "
                    + "two angle clips overlap, the later one takes over at its own start), "
                    + "each with the shot's video and audio switches; the clips either side are "
                    + "trimmed back to their old edges, so a dissolve on either edge is re-formed "
                    + "with its kind, curve and audio shape. The shot's grade, punch-in, actions "
                    + "and other settings do NOT carry. One undo step, \"Switch Angle\", or "
                    + "\"Switch Angle (transition removed)\" when an edge's dissolve could not be "
                    + "re-formed against a short piece and was dropped. Works in the container "
                    + "set_scope has open. Answers {ok, step, pieces (the new clip ids in time "
                    + "order), transitions_removed (0–2), project}. Refused, nothing changed: "
                    + "the angle is the shot's own track, the shot's track is locked, the shot "
                    + "is linked (Detach Audio's pair), the angle does not cover the shot "
                    + "(naming the first uncovered tick), or a step of the sequence is refused "
                    + "or an edge is held short by a speed ramp (in its own sentence).",
                [
                    "clip": [
                        "type": "integer",
                        "description": "The shot to re-pick: a clip on the program track.",
                    ],
                    "angle": [
                        "type": "integer",
                        "description": "The id of the track to re-pick it from.",
                    ],
                ], required: ["clip", "angle"]),
        ]
    }
}
