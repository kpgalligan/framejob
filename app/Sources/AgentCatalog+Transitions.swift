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
/// Both rows are `opTool`'s (road map 7's D3·4): the PROSE is here and the
/// structure — the two vocabularies among it — is printed from the core's
/// published table, so the thirteen kinds and the three alignments are the
/// core's own list rather than `TransitionKind.allCases` restated. `scope`
/// arrives on both for free: `tool()`, which `opTool` goes through, puts one
/// on every row whose name the CORE calls an op (`rc_op_names`), so an op
/// tool cannot be declared without one.
extension AgentServer {
    /// The transition rows, given the two SENTENCES the clip group already
    /// hoisted — the ticks note and the clip-id prose — so neither is spelled
    /// a second time.
    func transitionTools(ticks: String, clipDescription: String) -> [[String: Any]] {
        return [
            opTool(
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
                    + "clamps below one frame is refused. An affected track already outside "
                    + "the overlap rule is refused by that rule before fitting. align center takes half from "
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
                    + "set_transition or set_transition_duration for that one). With "
                    + "ripple true the overlap is made by MOVING instead — the sheet's Shift "
                    + "Clips Left button when neither clip has footage beyond the cut: no "
                    + "material is read and align is ignored, and the incoming clip plus "
                    + "every clip at or after the cut on every unlocked track slides left by "
                    + "duration, so the timeline gets that much shorter and no clip's source "
                    + "window changes. It is capped at half the shorter of the two clips and "
                    + "limited to the greatest whole-frame shift that leaves every moved "
                    + "track inside the overlap rule, including after clips cross; a clip "
                    + "on another track pushed into its neighbour gets a cross_dissolve; "
                    + "markers do not move.",
                [
                    "clip": clipDescription,
                    "kind": "The transition. Absent uses the clip's stored kind, else "
                        + "cross_dissolve. Not nullable — set_transition clears.",
                    "duration": "Requested overlap length, \(ticks) Clamped, never "
                        + "refused for being too long.",
                    "align": "Which side the overlap comes out of. Default center. Ignored "
                        + "with ripple.",
                    "ripple": "Make the overlap by sliding the incoming clip and everything "
                        + "after it left, for two clips with no footage beyond the cut. "
                        + "Default false.",
                ]),
            opTool(
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
                    "clip": clipDescription,
                    "curve": "How the transition's progress is eased.",
                    "audio": "Crossfade the two clips' sound across the overlap.",
                ]),
        ]
    }
}
