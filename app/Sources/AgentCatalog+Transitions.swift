import AppKit

/// The agent's two TRANSITION rows — `add_transition` and
/// `set_transition_style`, road map 5 E1's ops (format version 7).
///
/// A file of its own rather than two more rows in `AgentCatalog+Clips.swift`,
/// which is the file the forty-five clip and action rows already live in and
/// is well over the size cap. The two rows are spliced into `catalogJSON()`
/// immediately AFTER that group — right where `set_transition` and
/// `set_transition_duration` end — and never appended at the very end of the
/// catalog, which is where `tools/proof/recording_probe.py` reads the last
/// eleven names from.
///
/// `scope` arrives on both for free: `tool()` puts it on every row whose name
/// the CORE calls an op (`rc_op_names`), so an op tool cannot be declared
/// without one.
extension AgentServer {
    /// The transition rows, given the two locals the clip group already
    /// hoisted — the ticks sentence and the clip-id property — so neither is
    /// spelled a second time.
    func transitionTools(ticks: String, clipProperty: [String: Any]) -> [[String: Any]] {
        let transitionNames = TransitionKind.allCases.map { $0.rawValue }
        let curveNames = Curve.allCases.map { $0.rawValue }
        let alignNames = TransitionAlign.allCases.map { $0.rawValue }
        return [
            tool(
                "add_transition",
                "Makes an overlap at the HARD CUT before a clip and puts a transition on it — "
                    + "Clip ▸ Transition ▸ <kind> on a clip that abuts the one before it. The "
                    + "overlap is built out of material the two clips already have (the source "
                    + "before the incoming clip's in point, and after the outgoing clip's "
                    + "out point), so NOTHING else on the timeline moves and the pair's outer "
                    + "edges stay exactly where they were. duration is snapped down to whole "
                    + "frames and CLAMPED — to each side's available material, to the "
                    + "neighbours on the track, and to the overlap rule — so a request too "
                    + "long for the media lands shorter rather than failing; a request that "
                    + "clamps below one frame changes nothing. align center takes half from "
                    + "each side (an odd frame goes to the incoming clip, and a side with "
                    + "nothing to give passes its share to the other), before takes it all "
                    + "from the incoming clip's head, after all from the outgoing clip's tail. "
                    + "kind absent uses the clip's stored kind if it has one and "
                    + "cross_dissolve otherwise; a stored transition keeps its curve and "
                    + "crossfade, a new one is eased at both ends and crossfades its sound. "
                    + "The incoming clip's actions move with its new first frame, so a zoom "
                    + "stays on the source frame it was drawn over. Errors when duration is "
                    + "not positive and when the clip is NOT at a hard cut, naming which of: "
                    + "no clip before it, a gap, an overlap that already exists (use "
                    + "set_transition or set_transition_duration for that one).",
                [
                    "clip": clipProperty,
                    "kind": [
                        "type": "string", "enum": transitionNames,
                        "description":
                            "The transition. Absent uses the clip's stored kind, else "
                            + "cross_dissolve. Not nullable — set_transition clears.",
                    ] as [String: Any],
                    "duration": [
                        "type": "integer",
                        "description": "Requested overlap length, \(ticks) Clamped, never "
                            + "refused for being too long.",
                    ],
                    "align": [
                        "type": "string", "enum": alignNames,
                        "description":
                            "Which side the overlap comes out of. Default center.",
                    ] as [String: Any],
                ], required: ["clip", "duration"]),
            tool(
                "set_transition_style",
                "Sets how a transition is EASED and whether it crossfades the two clips' "
                    + "sound — the Curve popup and the Crossfade Audio checkbox in the Clip "
                    + "tab's Transition section. An absent key keeps what is there, so "
                    + "changing the curve never touches the crossfade and the other way "
                    + "round; neither key given changes nothing at all. Like set_transition "
                    + "it writes onto ANY clip, with or without an overlap — a stored "
                    + "transition on a clip with no overlap is simply not drawn until there "
                    + "is one — and a clip with no transition at all gets a cross_dissolve "
                    + "with the style applied. The crossfade is constant power (cosine out, "
                    + "sine in), which holds the level across two unrelated takes where a "
                    + "straight-line pair dips 3 dB. A project written before this existed "
                    + "reads as linear with no crossfade, exactly as it always sounded.",
                [
                    "clip": clipProperty,
                    "curve": [
                        "type": "string", "enum": curveNames,
                        "description": "How the transition's progress is eased.",
                    ] as [String: Any],
                    "audio": [
                        "type": "boolean",
                        "description": "Crossfade the two clips' sound across the overlap.",
                    ],
                ], required: ["clip"]),
        ]
    }
}
