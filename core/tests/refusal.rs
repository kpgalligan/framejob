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

// ---- the rules that found their words at D2·3 ----------------------------

/// The fixture the rules of kpgalligan/reelcut#11 are asked against, at the
/// same 600 000 fps — ONE TICK per frame — as [`overlap_project`], so every
/// number in an expected sentence is hand-computable and no snap moves it.
///
/// Track 4 "A" holds clips 10 (0 – 1000, with action 20 across 0 – 400) and
/// 11 (3000 – 4000), leaving a gap 1000 – 3000 to close. Track 5 "B" is
/// LOCKED and holds clips 12 (0 – 1000) and 13 (1000 – 2000), which abut at
/// a hard cut. Track 6 "C" holds clips 15 (0 – 2000) and 16 (2000 – 4000),
/// which abut too and are cut from media 3 — 2000 ticks long, so each clip
/// shows the whole file and neither side of their cut has one unused frame
/// to give a transition. Media 2 is imported and shown by nothing.
///
/// Two more tracks exist for the RIPPLE form of a transition, which makes
/// its overlap by shifting rather than out of handles. Track 8 "D" holds
/// clips 17 (0 – 2500) and 18 (2000 – 3000), already overlapping by exactly
/// 500 — half of the shorter of the two, the most the overlap rule allows —
/// so any leftward shift at all breaks it, and clip 18 starts at 2000, which
/// is the cut on track 6, so the shift touches this track. Track 9 "E" holds
/// clips 19 (0 – 1) and 22 (1 – 2), one tick each: half of the shorter of
/// them is under a frame.
fn rules_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 1,
  "canvas": {"width": 1920, "height": 1080, "fps": [600000, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 2, "path": "/m/spare.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 3, "path": "/m/short.mov", "kind": "video", "duration": 2000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 7, "path": "/m/other.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [{"id": 4, "name": "A"}, {"id": 5, "name": "B", "locked": true},
             {"id": 6, "name": "C"}, {"id": 8, "name": "D"}, {"id": 9, "name": "E"}],
  "clips": [
    {"id": 10, "track": 4, "start": 0, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {},
     "actions": [{"id": 20, "start": 0, "duration": 400, "end": {}}]},
    {"id": 11, "track": 4, "start": 3000, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 12, "track": 5, "start": 0, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 13, "track": 5, "start": 1000, "duration": 1000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 15, "track": 6, "start": 0, "duration": 2000,
     "source": {"kind": "media", "media": 3, "in": 0}, "video": {}, "audio": {}},
    {"id": 16, "track": 6, "start": 2000, "duration": 2000,
     "source": {"kind": "media", "media": 3, "in": 0}, "video": {}, "audio": {}},
    {"id": 17, "track": 8, "start": 0, "duration": 2500,
     "source": {"kind": "media", "media": 7, "in": 0}, "video": {}, "audio": {}},
    {"id": 18, "track": 8, "start": 2000, "duration": 1000,
     "source": {"kind": "media", "media": 7, "in": 0}, "video": {}, "audio": {}},
    {"id": 19, "track": 9, "start": 0, "duration": 1,
     "source": {"kind": "media", "media": 7, "in": 0}, "video": {}, "audio": {}},
    {"id": 22, "track": 9, "start": 1, "duration": 1,
     "source": {"kind": "media", "media": 7, "in": 0}, "video": {}, "audio": {}}
  ],
  "nests": [],
  "markers": [],
  "next_id": 30
}"#,
    )
}

// ---- a locked track ------------------------------------------------------

#[test]
fn a_locked_track_says_so_at_every_op_that_needs_to_move_it() {
    let project = rules_project();
    // Three ops, one rule, one sentence shape: each names track 5 and what
    // it is the lock stopped. A caller reading any of them knows to unlock
    // the track rather than to move the clip.
    project.refuses_with(
        &json!({"op": "close_gap", "track": 5, "at": 2500}),
        "track 5 is locked, so the gap on it cannot be closed",
    );
    project.refuses_with(
        &json!({"op": "insert_clip", "track": 5, "media": 2, "at": 0}),
        "track 5 is locked, so an insert cannot open room on it",
    );
    project.refuses_with(
        &json!({"op": "add_transition", "clip": 13, "duration": 100, "ripple": true}),
        "track 5 is locked, so clip 13 cannot be shifted left to make the overlap",
    );
}

#[test]
fn an_unlocked_track_is_the_boundary_of_that_rule() {
    let project = rules_project();
    // The same three calls on track 4, which is not locked: the gap
    // 1000 – 3000 closes, and an insert lands. Without this the sentences
    // above would pass against a build that refused every track.
    project.apply(&json!({"op": "close_gap", "track": 4, "at": 2500}));
    project.apply(&json!({"op": "insert_clip", "track": 4, "media": 2, "at": 0}));
}

// ---- the track stack -----------------------------------------------------

#[test]
fn a_track_that_still_holds_clips_names_them_and_the_way_on() {
    let project = rules_project();
    // Track 5 holds clips 12 and 13. The sentence lists them — a caller
    // that reads it knows what `with_clips` would take with the track —
    // and names the argument that would let it through.
    project.refuses_with(
        &json!({"op": "remove_track", "track": 5}),
        "track 5 still holds clips 12 and 13; pass with_clips: true to remove the track \
         and its clips",
    );
    // The way on works, which is what makes the sentence advice rather
    // than decoration.
    project.apply(&json!({"op": "remove_track", "track": 5, "with_clips": true}));
    // One clip is the singular form of the same sentence — the arm of
    // `clip_list` that says "clip", not "clips".
    let one_left = project.apply(&json!({"op": "delete", "clips": [11]}));
    one_left.refuses_with(
        &json!({"op": "remove_track", "track": 4}),
        "track 4 still holds clip 10; pass with_clips: true to remove the track and \
         its clips",
    );
}

#[test]
fn the_last_track_says_it_is_the_last() {
    let project = rules_project();
    // Down to one track, the long way, because the rule is about the state
    // and not about the argument: both removals below apply.
    let one = project.apply_all(&[
        json!({"op": "remove_track", "track": 5, "with_clips": true}),
        json!({"op": "remove_track", "track": 6, "with_clips": true}),
        json!({"op": "remove_track", "track": 8, "with_clips": true}),
        json!({"op": "remove_track", "track": 9, "with_clips": true}),
    ]);
    one.refuses_with(
        &json!({"op": "remove_track", "track": 4, "with_clips": true}),
        "track 4 is the only track left, and a project must always have one",
    );
    // …and the rule outranks the clips it holds: `with_clips: true` is the
    // way past the other refusal and not past this one.
    one.refuses_with(
        &json!({"op": "remove_track", "track": 4}),
        "track 4 is the only track left, and a project must always have one",
    );
}

// ---- the media list ------------------------------------------------------

#[test]
fn a_media_a_clip_still_shows_names_the_clips_and_the_way_on() {
    let project = rules_project();
    // Media 1 is shown by clips 10, 11, 12 and 13 — more than the sentence
    // names one by one, so the tail is a count rather than a list that
    // could run to a hundred ids.
    project.refuses_with(
        &json!({"op": "remove_media", "media": 1}),
        "media 1 is still used by clips 10, 11, 12 and 1 more; pass with_clips: true to \
         remove the media and its clips",
    );
    // Media 3 is shown by exactly two, which is the short form.
    project.refuses_with(
        &json!({"op": "remove_media", "media": 3}),
        "media 3 is still used by clips 15 and 16; pass with_clips: true to remove the \
         media and its clips",
    );
    // Three is the longest list that is still a list: at four the tail
    // becomes a count, above.
    let three = project.apply(&json!({"op": "delete", "clips": [22]}));
    three.refuses_with(
        &json!({"op": "remove_media", "media": 7}),
        "media 7 is still used by clips 17, 18 and 19; pass with_clips: true to remove \
         the media and its clips",
    );
    // Media 2 is shown by nothing: no rule to break, so the op applies.
    project.apply(&json!({"op": "remove_media", "media": 2}));
    project.apply(&json!({"op": "remove_media", "media": 3, "with_clips": true}));
}

// ---- a cut with nothing left to give a transition -------------------------

#[test]
fn a_cut_with_no_unused_material_says_how_much_it_has() {
    let project = rules_project();
    // Clips 15 and 16 each show the whole of media 3 (2000 ticks), so the
    // outgoing clip has nothing after its out point and the incoming clip
    // nothing before its in point. The sentence names the number the caller
    // sent, which is the one it would change, and the way that does not
    // need handles at all.
    project.refuses_with(
        &json!({"op": "add_transition", "clip": 16, "duration": 100}),
        "the cut before clip 16 has no room for an overlap: the 100 frames asked for clamp \
         to nothing against the two clips' unused material, their neighbours and the \
         overlap rule; pass ripple: true to make the overlap by shifting the timeline \
         left instead",
    );
}

#[test]
fn a_cut_with_handles_to_spare_is_the_boundary_of_that_rule() {
    let project = rules_project();
    // The same cut, one track over: clips 12 and 13 are cut from media 1
    // (36 000 000 ticks), so both handles are long. Track 5 is locked,
    // which stops the RIPPLE form and not this one — the handle form moves
    // nothing that a lock could hold.
    project.apply(&json!({"op": "add_transition", "clip": 13, "duration": 100}));
}

#[test]
fn a_ripple_that_every_length_would_break_says_what_it_tried() {
    let project = rules_project();
    // Track 8 holds clips 17 and 18 already overlapping by exactly 500 —
    // half of the shorter of the two, the most the rule allows — and clip
    // 18 starts at the cut, so the shift touches that track. Every length
    // from 1000 frames down to one adds to that overlap and breaks it.
    project.refuses_with(
        &json!({"op": "add_transition", "clip": 16, "duration": 1000, "ripple": true}),
        "clips 15 and 16 cannot overlap by shifting: no overlap from 1000 frames down to \
         one leaves every track the shift moves inside the overlap rule",
    );
    // Take track 8 out of the way and the same call lands, so the sentence
    // above is about the rule and not about the ripple form as such.
    let clear = project.apply(&json!({"op": "remove_track", "track": 8, "with_clips": true}));
    clear.apply(&json!({"op": "add_transition", "clip": 16, "duration": 1000, "ripple": true}));
}

#[test]
fn a_pair_too_short_to_halve_says_so_rather_than_naming_the_rule() {
    let project = rules_project();
    // Clips 19 and 22 are one tick each at 600 000 fps — one frame — so
    // half of the shorter of them is under a frame and there is no length
    // to step down from. A different sentence from the one above on
    // purpose: what a caller acts on here is the clips' length, not the
    // overlap rule.
    project.refuses_with(
        &json!({"op": "add_transition", "clip": 22, "duration": 1, "ripple": true}),
        "clips 19 and 22 have no room to overlap by shifting: the overlap asked for is 1 \
         frames and half of the shorter clip is 0 frames",
    );
}

// ---- an action that would overlap another --------------------------------

#[test]
fn an_action_that_would_overlap_another_names_the_one_in_the_way() {
    let project = rules_project();
    // Clip 10 carries action 20 across 0 – 400. A new action at 200 for
    // 100 lands inside it: the sentence names the action a caller would
    // move, and the span it is asking about.
    project.refuses_with(
        &json!({"op": "add_action", "clip": 10, "at": 200, "duration": 100}),
        "action 20 on clip 10 already runs from 0 to 400 ticks, and two actions on one \
         clip may not overlap",
    );
    // `set_action` refuses on the same test and in the same words: a second
    // action moved back on top of the first.
    let two = project.apply(&json!({"op": "add_action", "clip": 10, "at": 500, "duration": 100}));
    two.refuses_with(
        &json!({"op": "set_action", "clip": 10, "action": 30, "start": 300}),
        "action 20 on clip 10 already runs from 0 to 400 ticks, and two actions on one \
         clip may not overlap",
    );
    // …and the same move to a free span applies, so the sentence is about
    // the collision and not about `set_action`.
    two.apply(&json!({"op": "set_action", "clip": 10, "action": 30, "start": 400}));
}

#[test]
fn an_action_that_would_run_past_the_clip_names_both_ends() {
    let project = rules_project();
    // Clip 10 is 1000 ticks long. An action of 200 at 900 would end at
    // 1100: the sentence names the end it wanted and the end it has.
    project.refuses_with(
        &json!({"op": "add_action", "clip": 10, "at": 900, "duration": 200}),
        "an action of 200 ticks at 900 would end at 1100, past clip 10's own end at 1000 \
         ticks",
    );
    project.refuses_with(
        &json!({"op": "set_action", "clip": 10, "action": 20, "duration": 1200}),
        "an action of 1200 ticks at 0 would end at 1200, past clip 10's own end at 1000 \
         ticks",
    );
    // The boundary: an action that ends exactly at the clip's end is fine.
    project.apply(&json!({"op": "add_action", "clip": 10, "at": 900, "duration": 100}));
}

// ---- a move off the track stack ------------------------------------------

#[test]
fn a_move_off_the_track_stack_names_the_index_it_would_land_on() {
    let project = rules_project();
    // Five tracks, indices 0 – 4. Clips 15 (track 6, index 2) and 17
    // (track 8, index 3) moved to track 9 (index 4) travel two tracks each:
    // 15 lands on 4 and 17 would land on 5, which the document has not got.
    // The comment on this rule has called it a refusal since it was written
    // — clamping would silently stack two clips on one track — and this is
    // the ticket where it says so out loud.
    project.refuses_with(
        &json!({"op": "move_clip", "clips": [15, 17], "delta": 0, "track": 9}),
        "clip 17 would land on track index 5, which is out of range (0..5)",
    );
    // The boundary: a move onto a track the stack HAS lands. The time delta
    // is there to clear clip 11, since the overlap rule still applies.
    project.apply(&json!({"op": "move_clip", "clips": [22], "delta": 4000, "track": 4}));
}
