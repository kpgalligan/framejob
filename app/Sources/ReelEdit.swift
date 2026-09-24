import Foundation

/// **What an op ANSWERS**, on the app's side of the FFI: the three arms of
/// `core/src/outcome.rs` as Swift, the value a refusal carries, and the fold
/// that applies a LIST of ops (which names no `rc_*` symbol, so it belongs
/// here rather than in `ReelCore.swift`).
///
/// The single-op call itself stays next door, because it is the one place
/// `rc_project_apply` is named (root `CLAUDE.md`'s FFI rule). This file is
/// the other half: what its answer MEANS, and what a caller owes each arm.
///
/// **Why it is a file of its own, and not three more types in
/// `ReelCore.swift`.** It mirrors the core module by module — the core gave
/// the answer a module of its own for the same reason (`outcome.rs`) — and
/// `ReelCore.swift` stood at 1507 lines against app/CLAUDE.md's ~600 cap, and
/// a file at that cap gives something up before it takes anything on. What
/// it gave up is the list fold below, which never touched the FFI.
///
/// **The rule the whole app leans on**: only `.applied` is an undo step.
/// `.identity` and `.refused` are BOTH "the project did not change" — a
/// refusal is not an error tier (spec #8's ninth decision) — and the
/// difference between them is only what a caller can SAY. Deepening D2·2
/// (kpgalligan/reelcut#10) is where that difference started reaching an
/// agent; a person at the machine still gets the beep and, for a refusal,
/// the sentence at the inspector's foot (spec §11 CI-10).

/// A rule's refusal: which op the core declined, and the sentence it wrote.
///
/// The sentence is the rule's own, carried through verbatim from
/// `reason_out` so that the rule is written once — "clips 3 and 4 would
/// overlap by 8000 ticks, more than half of the shorter clip (6000 ticks)".
/// Nothing on this side rewords it, appends to it or parses it: it is prose
/// for a caller to read, not a code to switch on.
struct ReelRefusal {
    /// The op-table name of the op that was refused (`move_clip`,
    /// `trim_start`, …). For a LIST applied in order it is the op the
    /// refusal came from, which is the whole reason it is carried: a call
    /// that groups several ops has to say WHICH one to fix, and the answer
    /// is otherwise one word about a list.
    let op: String

    /// The core's own sentence, verbatim.
    let reason: String
}

/// The answer to one op, or to a list of them (spec §5.5).
enum ReelEdit {
    /// The op changed the project; here is the new handle. **The only arm
    /// that is an undo step.**
    case applied(ReelProject)

    /// The op was valid and nothing needed to change — the project already
    /// says what the caller asked it to say, or the op was handed an empty
    /// selection. No undo step, and **nothing to explain**: a caller told
    /// about a rule here would go looking for one it did not break.
    case identity

    /// A rule declined the op, in the rule's own words. No undo step either,
    /// and the project is exactly as it was, so a refused call is safe to
    /// retry.
    ///
    /// Not every refusal the core's doc comments describe arrives here yet —
    /// `Outcome::Identity`'s doc in `core/src/outcome.rs` is the one list of
    /// which rules can say so out loud, and the rest answer `.identity`
    /// until road map 7's D2·3 gives them their sentences.
    case refused(ReelRefusal)

    /// The new project, or nil for BOTH non-applied arms.
    ///
    /// This is the spelling for a caller that deliberately treats a refusal
    /// as "nothing happened" — a probe whose result is dropped, a live drag
    /// that must not go chatty mid-gesture, a repair that runs before the
    /// document exists. A caller that can SAY something about the two arms
    /// matches them instead, and the five paths that decide whether an undo
    /// step exists all do (`ProjectDocument`).
    var project: ReelProject? {
        if case .applied(let project) = self { return project }
        return nil
    }
}

extension Optional where Wrapped == ReelEdit {
    /// `ReelEdit.project` with a THROW folded in, for the `try?` probes: a
    /// handful of callers apply an op purely to see what the core would do,
    /// and to them an invalid op, an identity and a refusal are one answer —
    /// "no new project, carry on with the handle you have".
    var project: ReelProject? {
        switch self {
        case .some(let edit): return edit.project
        case .none: return nil
        }
    }
}

extension ReelProject {
    /// Applies ops in order, each to the result of the last.
    ///
    /// **A refusal does not stop the list.** A later op still runs after one,
    /// exactly as it runs after an identity, so a compound gesture — a freeze
    /// frame, a multi-file import, a recording's landing — is not thrown away
    /// because one of its steps was declined. What comes back is therefore
    /// `.applied` whenever ANY op applied, which is byte for byte the
    /// decision this method made before it could tell the two kinds of
    /// "nothing" apart.
    ///
    /// The FIRST refusal is remembered and answered only when nothing applied
    /// at all, because that is the case where a caller is owed a reason and
    /// the earliest thing that went wrong is the one to name. `.identity`
    /// when every op was one.
    func applying(_ ops: [ReelOp]) throws -> ReelEdit {
        var current: ReelProject?
        var refusal: ReelRefusal?
        for op in ops {
            switch try (current ?? self).applying(op) {
            case .applied(let next): current = next
            case .identity: break
            case .refused(let why): if refusal == nil { refusal = why }
            }
        }
        if let current = current { return .applied(current) }
        return refusal.map { ReelEdit.refused($0) } ?? .identity
    }
}
