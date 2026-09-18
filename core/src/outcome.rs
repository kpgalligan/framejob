//! What an op answers (spec §5.5): the three arms every edit in the crate
//! returns, and the one place their meanings are written down.
//!
//! Until deepening D2 an edit answered `Option<Project>`, and `None` carried
//! two meanings at once — "the value you asked for is the value already
//! stored" and "a rule said no". The reason existed at the moment of the
//! refusal (the overlap rule writes a full sentence naming the two clips and
//! the exact tick counts) and was thrown away one line later, so nothing
//! outside the core could tell the two apart or learn which rule had spoken.
//!
//! [`Outcome`] is that answer made explicit. It is an enum rather than a
//! second out-parameter for one reason: a site that has not decided which
//! answer it is giving does not compile. Adding an arm, or changing which
//! arm a rule takes, is therefore a change the compiler walks the caller
//! through.
//!
//! **A composed op passes the other two arms straight back.** `insert_clip`,
//! `overwrite_clip` and `add_zoom_action` are built from other ops, and each
//! matches all three arms of what it called rather than asking only "did
//! this apply": an inner refusal returned as an identity is exactly how the
//! reason used to be lost, one composition instead of one rule.
//!
//! The fourth possibility — the request itself could not be read — is not an
//! arm here. It stays the `Err(String)` of the enclosing `Result`, because
//! it is a different class of answer: a refusal is about the PROJECT (the
//! op was understood and a rule declined it), an error is about the
//! REQUEST. `core/CLAUDE.md`'s Errors rule states both tiers, and
//! `ffi_edit.rs` maps all four onto C.

use crate::model::Project;

/// The answer one op gives, the three ways it can end (spec §5.5).
///
/// Every `impl Project` edit in the crate returns `Result<Outcome, String>`:
/// this enum for an op that was understood, `Err` for a request that was
/// not.
#[derive(Debug, Clone, PartialEq)]
pub enum Outcome {
    /// The op changed the project; here is the new one. The app pushes an
    /// undo step, and nothing else does.
    ///
    /// The value is never an identical copy of the input — `Project::finish`
    /// is the universal exit that turns one into [`Outcome::Identity`] —
    /// because a copy would register a phantom undo step the user has to
    /// undo twice.
    Applied(Project),

    /// The op was valid and nothing needed to change: the project already
    /// says what the caller asked it to say, or the op was handed an empty
    /// selection. **No undo step, and no explaining**: a caller told about a
    /// rule here would go looking for one it did not break.
    ///
    /// **Not every "refuses" in this crate's doc comments reaches a caller
    /// as [`Outcome::Refused`] yet.** The overlap rule found its channel
    /// first, because it already wrote a full sentence; the rules whose
    /// words are still owed — a locked track, the last track, a media row a
    /// clip still shows, a cut with nothing left to give a transition, and
    /// an action that would overlap another — answer `Identity` until road
    /// map 7's D2·3 writes them, and so do a few smaller ones the spec did
    /// not name (a move to a track index the document has not got, a trim
    /// whose two clamps crossed). A doc comment saying an op "refuses" is
    /// describing the DOMAIN, which is what a reader needs; this is the one
    /// place that says which of them can say so out loud.
    Identity,

    /// A rule declined the op, in the rule's own words. **No undo step**,
    /// exactly as for an identity — a refusal is not an error tier and the
    /// project is left exactly as it was — but the caller is told why.
    ///
    /// The sentence is the one the rule itself writes, passed through
    /// verbatim so it is written once: "clips 3 and 4 would overlap by 8000
    /// ticks, more than half of the shorter clip (6000 ticks)". It names
    /// what a caller could act on, and it is prose, not a code.
    Refused(String),
}
