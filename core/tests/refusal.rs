//! Black-box tests for the THREE answers an op gives (spec §5.5), driven
//! the way the app drives them: one JSON envelope at a time through
//! `rc_project_apply`.
//!
//! Until deepening D2 an identity and a refusal were the same answer — NULL
//! with `err_out` untouched — so nothing outside the core could tell "the
//! project is already in that state" from "a rule said no". This file pins
//! the distinction at the seam a caller actually stands at:
//!
//! - **applied** — a new handle;
//! - **an identity** — no handle, no sentence;
//! - **a refusal** — no handle, and the rule's own sentence through
//!   `reason_out`;
//! - **invalid input** — no handle, and a message through `err_out`,
//!   unchanged in meaning and wording by D2.
//!
//! The overlap rule (spec §11) is the first rule to speak, and it is the
//! rule tested here because it is the one whose sentence carries numbers a
//! caller can act on. Every expected sentence is written out whole — the
//! clip ids and the tick counts included, hand-computed from the fixture —
//! because a keyword match would pass on a sentence that had lost exactly
//! the part a caller reads.

mod common;

use std::ffi::c_char;
use std::ptr;

use serde_json::json;

use common::{cstring, Handle, Outcome};
use reelcut_core::ffi_edit::rc_project_apply;

// ---- fixtures ------------------------------------------------------------

/// The overlap-rule fixture, deliberately at 600 000 fps — ONE TICK per
/// frame, so a test can pin the rule's boundary exactly instead of
/// bracketing it to within a frame (every op snaps its arguments to the
/// canvas grid first, spec §6).
///
/// Track 2 holds clips 10 (0 – 1000) and 11 (2000 – 3000), both 1000 ticks
/// long, so the rule allows them 500 ticks of overlap. Track 3 holds clips
/// 15 (0 – 1000), 16 (900 – 1300) and 17 (5000 – 5400) for the
/// two-neighbours case. Nest 20 holds the same pair again, so the same rule
/// can be asked from inside a scope.
fn overlap_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [600000, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [{"id": 2, "name": "A"}, {"id": 3, "name": "B"}],
  "clips": [
    {"id": 10, "track": 2, "start": 0, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 11, "track": 2, "start": 2000, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 15, "track": 3, "start": 0, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 16, "track": 3, "start": 900, "duration": 400,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {},
     "transition_in": {"kind": "fade_black"}},
    {"id": 17, "track": 3, "start": 5000, "duration": 400,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 18, "track": 2, "start": 8000, "duration": 3000,
     "source": {"kind": "nest", "project": 20}, "video": {}, "audio": {}}
  ],
  "nests": [
    {"id": 20, "name": "Nest 1", "width": 1920, "height": 1080,
     "tracks": [{"id": 21, "name": "Inside"}],
     "clips": [
       {"id": 22, "track": 21, "start": 0, "duration": 1000,
        "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
       {"id": 23, "track": 21, "start": 2000, "duration": 1000,
        "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}}
     ]}
  ],
  "markers": [],
  "next_id": 30
}"#,
    )
}

// ---- the refusal arm -----------------------------------------------------

#[test]
fn a_move_the_overlap_rule_refuses_carries_the_rule_s_own_sentence() {
    let project = overlap_project();
    // Clip 11 lands at 499 and runs to 1499; clip 10 ends at 1000, so they
    // overlap by 501 of the 500 ticks half the shorter clip allows.
    project.refuses_with(
        &json!({"op": "move_clip", "clips": [11], "delta": -1501}),
        "clips 10 and 11 would overlap by 501 ticks, more than half of the \
         shorter clip (500 ticks)",
    );
}

#[test]
fn the_two_neighbour_rule_speaks_too() {
    let project = overlap_project();
    // Clip 17 (400 long) dropped at 950 sits inside clip 16 (900 – 1300)
    // and still reaches back into clip 15 (0 – 1000): a clip may overlap at
    // most ONE neighbour on each side (spec §11).
    project.refuses_with(
        &json!({"op": "move_clip", "clips": [17], "delta": -4050}),
        "clip 15 would overlap more than one neighbour on one side (clips 16 and 17)",
    );
}

#[test]
fn a_trim_the_overlap_rule_refuses_speaks_in_the_same_words() {
    let project = overlap_project();
    // The sentence belongs to the rule, not to the op: clip 10 grown to
    // 0 – 2600 reaches 600 ticks into clip 11 (2000 – 3000), and half the
    // shorter of the two is still 500.
    project.refuses_with(
        &json!({"op": "trim_end", "clip": 10, "to": 2600}),
        "clips 10 and 11 would overlap by 600 ticks, more than half of the \
         shorter clip (500 ticks)",
    );
}

#[test]
fn a_refusal_inside_a_nest_comes_back_out_of_the_scope() {
    let project = overlap_project();
    // The same rule, the same words, one level down: nest 20 holds clips 22
    // (0 – 1000) and 23 (2000 – 3000). A scope widens the invalid-input
    // tier (`core/src/scope.rs`) and must not narrow this one.
    project.refuses_with(
        &json!({"op": "move_clip", "clips": [23], "delta": -1501, "scope": 20}),
        "clips 22 and 23 would overlap by 501 ticks, more than half of the \
         shorter clip (500 ticks)",
    );
}

#[test]
fn a_refusal_is_still_no_undo_step() {
    let project = overlap_project();
    // `refuses` is the helper 91 call sites use for "no handle, so no undo
    // step". A refusal has to keep passing it: what D2 added is a second
    // question a test may ask, not a new answer at this one.
    project.refuses(&json!({"op": "move_clip", "clips": [11], "delta": -1501}));
}

// ---- the identity arm ----------------------------------------------------

#[test]
fn a_true_identity_carries_no_sentence() {
    let project = overlap_project();
    // Moved by nothing, renamed to the name it has, and handed an empty
    // selection: three ways to change nothing, none of them a rule saying
    // no.
    for op in [
        json!({"op": "move_clip", "clips": [11], "delta": 0}),
        json!({"op": "set_track", "track": 2, "name": "A"}),
        json!({"op": "delete", "clips": []}),
    ] {
        match project.try_apply(&op) {
            Ok(Outcome::Identity) => {}
            other => panic!("{op} was expected to be an identity, but answered {other:?}"),
        }
    }
}

// ---- the applied arm -----------------------------------------------------

#[test]
fn an_applied_op_carries_no_sentence() {
    let project = overlap_project();
    // The invariant `Handle::try_apply` asserts for the whole suite, pinned
    // here at the seam it is about: a handle and a sentence never come back
    // together, so a caller that got a project never has to wonder whether
    // it was also told no.
    let op = json!({"op": "move_clip", "clips": [11], "delta": -1000});
    match project.try_apply(&op) {
        Ok(Outcome::Applied(_)) => {}
        other => panic!("{op} was expected to apply, but answered {other:?}"),
    }
}

// ---- the invalid-input tier ----------------------------------------------

#[test]
fn invalid_input_is_unchanged() {
    let project = overlap_project();
    // Unchanged in meaning and in wording: an unknown id, an unknown op
    // name and a malformed envelope all still answer through `err_out`,
    // and `Handle::try_apply` asserts that none of them also set the
    // refusal channel.
    assert_eq!(
        project.errors(&json!({"op": "move_clip", "clips": [99], "delta": 0})),
        "no clip with id 99"
    );
    assert!(project
        .errors(&json!({"op": "not_an_op"}))
        .starts_with("unknown op \"not_an_op\""));
    assert_eq!(
        project.errors(&json!({"op": "trim_end", "clip": 18, "to": 9000, "scope": 44})),
        "no nest with id 44"
    );
}

#[test]
fn a_refusal_tolerates_a_caller_that_passes_no_reason_channel() {
    let project = overlap_project();
    // NULL tolerance first, for the new out-parameter as for every other:
    // a caller that has not been taught about the refusal channel — the app
    // itself, until the next ticket — must get the old answer, NULL with
    // `err_out` untouched, and not a crash.
    let op = cstring(&json!({"op": "move_clip", "clips": [11], "delta": -1501}).to_string());
    let mut err: *mut c_char = ptr::null_mut();
    let next =
        unsafe { rc_project_apply(project.as_ptr(), op.as_ptr(), &mut err, ptr::null_mut()) };
    assert!(next.is_null(), "a refused op returns no handle");
    assert!(err.is_null(), "a refusal is not an error");
}
