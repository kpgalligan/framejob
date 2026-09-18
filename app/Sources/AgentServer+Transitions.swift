import AppKit

/// The agent's two TRANSITION tools — `add_transition` and
/// `set_transition_style`, road map 5 E1's ops (format version 7).
///
/// A file of its own rather than two more handlers in
/// `AgentServer+Clips.swift`, which is well over the size cap and already
/// holds `set_transition` and `set_transition_duration`;
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
    /// **The trial below now SHADOWS a sentence the core has.** Since
    /// deepening D2·3 a cut with nothing left to give answers
    /// `Outcome::Refused` naming the frames asked for, and the rippled form
    /// has three sentences of its own (a locked track, a pair too short to
    /// halve, every length breaking the overlap rule) — all of which
    /// `.project == nil` catches and replaces with the two below. Deleting
    /// the trial is D2·4's, which is the ticket that makes the core's words
    /// arrive.
    func addTransition(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let kind = try transitionKindArg(a, "kind")
        let duration = try timeArg(a, "duration", document)
        let align = try alignArg(a, "align")
        let ripple = try boolArg(a, "ripple") ?? false
        let ops: [ReelOp] = [
            .addTransition(
                clip: clip.id, kind: kind, duration: duration, align: align, ripple: ripple)
        ]
        // `.project` is nil for an identity AND for a refusal, so the two
        // sentences below are sent in place of whatever the core said. That
        // was the whole point of the trial when the core said nothing;
        // since D2·3 it says more than these do, and D2·4 deletes this.
        // Addressed the same way the commit will be, so a scoped call is
        // tried in the container it will land in.
        if try document.project.applying(addressed(ops, document)).project == nil {
            if ripple {
                throw ToolError(
                    message: "add_transition made no change: with ripple the shift clamped "
                        + "below one frame — the incoming clip's track is locked, a clip is "
                        + "too short for the overlap rule, or sliding a clip on another track "
                        + "into its neighbour would break that track's overlap rule.")
            }
            throw ToolError(
                message: "add_transition made no change: neither side of the cut has media "
                    + "beyond it. An overlap is built out of the source before the incoming "
                    + "clip's in point and after the outgoing clip's out point, and a request "
                    + "that clamps below one frame is refused. Pass ripple: true to make the "
                    + "overlap by sliding the incoming clip and everything after it left, or "
                    + "trim one of the two clips.")
        }
        return try editResult(document, "Set Transition", ops)
    }

    /// `set_transition_style` — the Curve popup and the Crossfade Audio
    /// checkbox in the Clip tab's Transition section
    /// (`VideoPane+Transition.swift`, undo names "Transition Curve" and
    /// "Transition Audio").
    ///
    /// A call with NEITHER key is refused here rather than sent as the
    /// core's `None`. The core is right to answer `None` — asking for no
    /// change is not a way to make a transition — but a tool answering
    /// "made no change" to a caller who simply forgot an argument is a
    /// diagnosis they cannot act on, and the two readers below already
    /// establish that whatever was sent was legible.
    func setTransitionStyle(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let curve = try curveArg(a, "curve")
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

    /// `add_transition`'s `align`, in `addZoomAction`'s `fit` shape.
    private func alignArg(_ a: [String: Any], _ key: String) throws -> TransitionAlign? {
        guard let name = try stringArg(a, key) else { return nil }
        guard let align = TransitionAlign(rawValue: name) else {
            throw ToolError(
                message: "\(key) must be one of "
                    + TransitionAlign.allCases.map { $0.rawValue }.joined(separator: ", ")
                    + " (got \"\(name)\").")
        }
        return align
    }
}
