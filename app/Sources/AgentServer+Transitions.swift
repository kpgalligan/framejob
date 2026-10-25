import AppKit

/// The agent's two TRANSITION tools — `add_transition` and
/// `set_transition_style`, road map 5 E1's ops (format version 7).
///
/// A file of its own rather than two more handlers in
/// `AgentServer+Clips.swift`, which is well over the size cap
/// (`set_transition` and `set_transition_duration` are now
/// `AgentServer+Properties.swift`'s);
/// `AgentServer+Background.swift` is the shape and the precedent. Both
/// handlers are the canonical form (app/CLAUDE.md's agent-parity rule):
/// `target(a)`, validate the ids and the vocabulary, build the typed
/// `ReelOp`, `editResult` — and each carries a comment naming the UI path it
/// mirrors.
///
/// **Every string argument is refused BY NAME before a builder is called**,
/// which is not automatic here and is the reason the argument reading is
/// spelled out rather than leaning on a decoder. `ProjectSnapshot`'s enums
/// decode LENIENTLY — an unknown name becomes the first case — so a
/// misspelt `kind` or `align` that reached a typed value would be silently
/// accepted and the caller told its wipe had landed. The three readers below
/// each name the key and list the allowed values, which is
/// `AgentServer+Clips.swift`'s `fit` and `curve` shape exactly.
extension AgentServer {

    /// `add_transition` — Clip ▸ Transition ▸ <kind> on a clip that ABUTS
    /// the one before it (`EditorViewController.setTransitionKind:`, whose
    /// body is `setTransitionKindCommand` in
    /// `EditorViewController+Inspector.swift`; the menu sends 0.5 s
    /// centred), and with `ripple` that sheet's Shift Clips Left button.
    ///
    /// `kind` is optional and NOT nullable: absent means the clip's own
    /// stored kind if it has one and `cross_dissolve` otherwise, where
    /// `set_transition`'s absent kind is a CLEAR. An explicit `null` here is
    /// refused rather than read as absent, because the two ops mean opposite
    /// things by it and a caller that sent one meant the other op.
    ///
    /// The clamps are the core's and none is pre-checked: a duration longer
    /// than the material lands shorter, and "not at a hard cut" is the
    /// core's sentence naming which of the three it is.
    ///
    /// **Nothing is tried first.** This handler used to apply the op to the
    /// handle, see `.project == nil` and write one of two sentences of its
    /// own, because the shared reply could say nothing but "made no change".
    /// Since deepening D2·3 the core refuses a cut with nothing left to give
    /// in its own words — naming the frames asked for and `ripple: true` —
    /// and the rippled form has three sentences of its own (a locked track,
    /// a pair too short to halve, every length breaking the overlap rule).
    /// D2·4 deleted the trial and both sentences, so what a caller hears
    /// here is the rule's own, through `performGroupedEdit`.
    func addTransition(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let kind = try transitionKindArg(a, "kind")
        let duration = try timeArg(a, "duration", document)
        let align = try enumArg(a, "align", TransitionAlign.self)
        let ripple = try boolArg(a, "ripple") ?? false
        return try editResult(
            document, "Set Transition",
            [
                .addTransition(
                    clip: clip.id, kind: kind, duration: duration, align: align, ripple: ripple)
            ])
    }

    /// `set_transition_style` — the Curve popup and the Crossfade Audio
    /// checkbox in the Clip tab's Transition section
    /// (`VideoPane+Transition.swift`, undo names "Transition Curve" and
    /// "Transition Audio").
    ///
    /// **A call with NEITHER key is an ARGUMENT that is missing, not a rule
    /// that said no**, which is why deepening D2·4 left this guard standing
    /// where it deleted the trial-apply above. The core answers
    /// `Outcome::Identity` for it, and rightly — nothing was asked for, so
    /// nothing changed — and an identity has nothing to say beyond that
    /// (`core/src/outcome.rs`). There is therefore no core sentence for this
    /// one to shadow: it names the tool's own two keys to a caller who
    /// forgot both, the way `set_track`, `set_marker`, `set_canvas` and
    /// `ripple_delete_ranges` name theirs.
    func setTransitionStyle(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let curve = try enumArg(a, "curve", Curve.self)
        let audio = try boolArg(a, "audio")
        guard curve != nil || audio != nil else {
            throw ToolError(
                message: "set_transition_style needs curve or audio — curve one of "
                    + Curve.allCases.map { $0.rawValue }.joined(separator: ", ")
                    + ", audio a boolean.")
        }
        return try editResult(
            document, "Transition Style",
            [.setTransitionStyle(clip: clip.id, curve: curve, audio: audio)])
    }

    /// `add_transition`'s `kind`: absent is nil, a name is the kind, and
    /// anything else — an explicit null, a number, a misspelling — is
    /// refused listing the thirteen.
    private func transitionKindArg(
        _ a: [String: Any], _ key: String
    ) throws -> TransitionKind? {
        guard let raw = a[key] else { return nil }
        guard let name = raw as? String, let kind = TransitionKind(rawValue: name) else {
            throw ToolError(
                message: "\(key) must be one of "
                    + TransitionKind.allCases.map { $0.rawValue }.joined(separator: ", ")
                    + ". Leave it out to keep the clip's own kind, and use set_transition to "
                    + "remove a transition.")
        }
        return kind
    }
}
