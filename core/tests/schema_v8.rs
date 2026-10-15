//! Black-box tests for what format version 8 added — `video.motion`, the
//! entrance, exit and continuous motion a clip carries (road map 5, E2) —
//! driven through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Eight things are pinned here:
//!
//! - **Every older file still opens, and opens as what it always drew.**
//!   The field carries a serde default, so there is no migration step and a
//!   version-1 … version-7 file reads back `"motion": null`, stamped
//!   version 8. The gate itself is `schema_v3.rs`'s claim and is not
//!   restated here.
//! - **`motion` is the LAST key of the video object**, read off the written
//!   TEXT, because a parsed `Value` sorts its keys and cannot tell.
//!   `schema_v6.rs` makes the other half of that claim, that `blend` is now
//!   followed by exactly one key.
//! - **The file default is the DERIVED default**, which is what makes the
//!   field safe to append to a shipped schema: an absent key, an explicit
//!   `null` and a slot-by-slot object of nulls are the same value.
//! - **Every kind's spelling round-trips**, all nine edges and all five
//!   durings. The JSON spelling is persisted, so a rename is silent data
//!   loss in a shipped file, and `spin` is in both enums.
//! - **The normalisation**: a `Motion` whose three slots are all `None` is
//!   stored as `None`, so one clip has one spelling of "no motion" and two
//!   projects a person would call equal compare equal.
//! - **Every range check refuses by NAME**, and a misspelt key at each of
//!   the three levels does too — which is `Group::template`'s doing, since
//!   `check_keys` walks a patch against a fully populated struct and would
//!   have nothing to walk into if the template's motion were `None`.
//! - **Motion is not an animation target** (spec §5.4): `set_action_end`
//!   refuses a patch naming it by name, which is the op's ONE refusal past
//!   "the patch must be an object".
//! - **And the refusal is a courtesy, not the enforcement.** A hand-written
//!   file, a pasted action or a project from another tool reaches the
//!   evaluator without passing that op, so `evaluate_clip` puts the BASE
//!   motion back over whatever an action reached — including when the end
//!   patch has replaced the whole `video` group with a number or a null,
//!   which must fall through to the base props exactly as it always did
//!   rather than panicking inside `IndexMut` or decoding as DEFAULT props.
//!
//! What a preset DOES to a picture is not a claim this file can make: the
//! placement arithmetic is `core/tests/motion.rs`'s and what a copy op
//! keeps is `core/tests/motion_copy.rs`'s. This file owns the SHAPE, the
//! DEFAULTS, the CHECKS and where the field may not travel.

mod common;

use framejob_core::format::RC_FORMAT_VERSION;
use serde_json::{json, Value};

use common::{array, at, num, text, Handle};

/// Ticks per second (spec §5.1), written out rather than imported so a
/// change to `time::TIMESCALE` fails these tests instead of moving with
/// them.
const SEC: i64 = 600_000;

/// Every `EdgeMotion` spelling, in declaration order. A kind added to the
/// model and not to this line is a kind this file does not round-trip.
const EDGE_MOTIONS: [&str; 9] = [
    "fade",
    "zoom_in",
    "zoom_out",
    "slide_left",
    "slide_right",
    "slide_up",
    "slide_down",
    "spin",
    "pop",
];

/// Every `DuringMotion` spelling, in declaration order. `spin` is in both
/// lists, deliberately.
const DURING_MOTIONS: [&str; 5] = ["pulse", "shake", "spin", "bounce", "drift"];

// ---- fixtures ------------------------------------------------------------

/// One media, one track (id 2) and one six-second clip (id 11) carrying
/// whatever `motion` is handed, spelled the way a file of `version` was
/// written — so `None` leaves the key out entirely.
fn moving(version: u32, motion: Option<Value>) -> Value {
    let mut video = json!({ "scale": 0.5, "x": 100.0, "y": -50.0 });
    if let Some(motion) = motion {
        video["motion"] = motion;
    }
    json!({
        "version": version,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/1.mov", "kind": "video",
            "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 6 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "video": video, "audio": {}
        }],
        "next_id": 12
    })
}

/// A full motion, every slot filled with a kind that is not the default, so
/// nothing in a round trip can pass by accident.
fn full_motion() -> Value {
    json!({
        "in": { "kind": "slide_up", "duration": SEC / 2 },
        "out": { "kind": "zoom_out", "duration": SEC },
        "during": { "kind": "shake", "amount": 0.25, "period": 2 * SEC }
    })
}

/// The current-version fixture with no motion — the handle the op tests
/// patch.
fn plain() -> Handle {
    Handle::from_value(&moving(8, None))
}

fn set_video(patch: Value) -> Value {
    json!({ "op": "set_video", "clips": [11], "patch": patch })
}

// ---- reading older files -------------------------------------------------

fn assert_no_motion(project: &Value) {
    assert_eq!(at(project, "/version"), &json!(RC_FORMAT_VERSION));
    assert_eq!(at(project, "/clips/0/video/motion"), &Value::Null);
    // The neighbours a version-8 reader adds nothing to, so a file that
    // gained one defaulted key gained ONLY that.
    assert_eq!(text(project, "/clips/0/video/blend"), "normal");
    assert_eq!(num(project, "/clips/0/video/scale"), 0.5);
}

#[test]
fn a_version_seven_file_reads_as_a_clip_that_does_not_move() {
    // The field carries a serde default, so a file written before the
    // feature existed opens untouched and comes back as a version-8 project
    // placed exactly where it was placed.
    assert_no_motion(&Handle::from_value(&moving(7, None)).value());
}

#[test]
fn every_older_version_reads_the_same_way() {
    // The migration chain still runs underneath: a version-1 file reaches
    // version 8 through `migrate_1_to_2` and then through nothing at all,
    // because none of versions 3 … 8 needed a rewrite.
    for version in [6, 5, 4, 3, 2, 1] {
        assert_no_motion(&Handle::from_value(&moving(version, None)).value());
    }
}

#[test]
fn the_derived_default_is_the_absence_of_the_key() {
    // The property the field rests on, and the reason it was safe to
    // append: a video group written without it, one written with an
    // explicit `null`, and one the reader filled in must all be the same
    // value.
    let absent = Handle::from_value(&moving(8, None)).value();
    let explicit = Handle::from_value(&moving(8, Some(Value::Null))).value();
    assert_eq!(
        at(&absent, "/clips/0/video"),
        at(&explicit, "/clips/0/video")
    );
}

// ---- the round trip ------------------------------------------------------

#[test]
fn a_full_motion_round_trips_exactly() {
    let written = Handle::from_value(&moving(8, Some(full_motion()))).value();
    assert_eq!(at(&written, "/version"), &json!(RC_FORMAT_VERSION));
    assert_eq!(
        at(&written, "/clips/0/video/motion"),
        &full_motion(),
        "the whole object, key for key"
    );
}

#[test]
fn a_slot_omitted_inside_a_motion_reads_as_null_rather_than_as_a_default() {
    // `Motion`'s own fields are `Option`, so naming one slot says nothing
    // about the other two — which is what lets a clip enter and not leave.
    let written = Handle::from_value(&moving(
        8,
        Some(json!({ "in": { "kind": "pop", "duration": SEC / 4 } })),
    ))
    .value();
    assert_eq!(
        at(&written, "/clips/0/video/motion"),
        &json!({
            "in": { "kind": "pop", "duration": SEC / 4 },
            "out": null,
            "during": null
        })
    );
}

#[test]
fn an_empty_slot_object_takes_the_documented_defaults() {
    // The container-level `#[serde(default)]` over a hand-written `Default`:
    // `{}` is half a second of fade, and a during is a half-strength
    // one-second pulse.
    let written = Handle::from_value(&moving(8, Some(json!({ "in": {}, "during": {} })))).value();
    assert_eq!(
        at(&written, "/clips/0/video/motion"),
        &json!({
            "in": { "kind": "fade", "duration": SEC / 2 },
            "out": null,
            "during": { "kind": "pulse", "amount": 0.5, "period": SEC }
        })
    );
}

#[test]
fn every_motion_kind_survives_a_write_and_a_read() {
    // Fourteen spellings across two enums, each persisted. Neither
    // declaration order is load-bearing — `motion.rs` matches on the
    // variant and nothing crosses to a shader — but the SPELLING is the
    // wire format, so a renamed variant is silent data loss in a shipped
    // file. Naming all fourteen is what makes that fail a test instead of a
    // project.
    for kind in EDGE_MOTIONS {
        let motion = json!({ "in": { "kind": kind }, "out": { "kind": kind } });
        let written = Handle::from_value(&moving(8, Some(motion))).value();
        assert_eq!(text(&written, "/clips/0/video/motion/in/kind"), kind);
        assert_eq!(text(&written, "/clips/0/video/motion/out/kind"), kind);
    }
    for kind in DURING_MOTIONS {
        let motion = json!({ "during": { "kind": kind } });
        let written = Handle::from_value(&moving(8, Some(motion))).value();
        assert_eq!(text(&written, "/clips/0/video/motion/during/kind"), kind);
    }
}

#[test]
fn motion_is_the_last_key_of_the_video_object() {
    // Declaration order IS key order, and `motion` is the last field of
    // `VideoProps`, so a version-7 file diffed against a version-8 one
    // differs by a trailing key rather than by a re-ordering. Read off the
    // written TEXT, because a `Value` sorts its keys and cannot tell.
    let first = Handle::from_value(&moving(8, Some(full_motion()))).to_json();
    let position = |needle: &str| {
        first
            .find(needle)
            .unwrap_or_else(|| panic!("no {needle:?} in the written text:\n{first}"))
    };
    assert!(position("\"obscure\"") < position("\"blend\""));
    assert!(position("\"blend\"") < position("\"motion\""));
    // ...and its own keys are in declaration order too, which is what makes
    // an `in` and an `out` diff readably.
    let group = &first[position("\"motion\": {")..];
    let inside = |needle: &str| {
        group
            .find(needle)
            .unwrap_or_else(|| panic!("no {needle:?} in the motion object:\n{group}"))
    };
    assert!(inside("\"in\"") < inside("\"out\""));
    assert!(inside("\"out\"") < inside("\"during\""));

    // A second trip through the text is byte-identical to the first, which
    // is what lets Swift compare project strings at all.
    let second = Handle::from_json(&first).to_json();
    assert_eq!(first, second, "a second round trip changed the bytes");
}

// ---- the patch path ------------------------------------------------------

#[test]
fn a_patch_deep_merges_a_motion_rather_than_replacing_it() {
    // `merge_group` calls `actions::merge`, which merges objects key by
    // key, so naming one slot keeps the other two. The replace-whole rule
    // lives at the two Swift edges (`VideoPatch.dictionary` and
    // `motionPatchArg`) and deliberately NOT here.
    //
    // The duration is a FIFTH of a second because this canvas is 30 fps and
    // the door snaps (D1·2): a quarter-second is seven and a half frames
    // and would land on eight, which is a different claim from this test's.
    let after = Handle::from_value(&moving(8, Some(full_motion())))
        .apply(&set_video(json!({
            "motion": { "in": { "kind": "pop", "duration": SEC / 5 } }
        })))
        .value();
    assert_eq!(
        at(&after, "/clips/0/video/motion"),
        &json!({
            "in": { "kind": "pop", "duration": SEC / 5 },
            "out": { "kind": "zoom_out", "duration": SEC },
            "during": { "kind": "shake", "amount": 0.25, "period": 2 * SEC }
        })
    );
}

#[test]
fn an_explicit_null_clears_the_whole_field() {
    let after = Handle::from_value(&moving(8, Some(full_motion())))
        .apply(&set_video(json!({ "motion": null })))
        .value();
    assert_eq!(at(&after, "/clips/0/video/motion"), &Value::Null);
}

#[test]
fn a_motion_whose_slots_are_all_cleared_normalises_back_to_null() {
    // One clip, one spelling of "no motion". Without the normalisation a
    // patch that cleared the last slot would leave `{"in": null, "out":
    // null, "during": null}` behind, which round-trips and would make two
    // projects a person would call equal compare unequal — and would make
    // the Swift side's `isEmpty` guard the only thing standing between a
    // clip and a phantom undo step.
    let cleared = Handle::from_value(&moving(8, Some(full_motion())))
        .apply(&set_video(json!({
            "motion": { "in": null, "out": null, "during": null }
        })))
        .value();
    assert_eq!(at(&cleared, "/clips/0/video/motion"), &Value::Null);

    // The same answer for the emptiest thing a caller can write: `{}`
    // deep-merges into the stored motion, so on a clip that has none it
    // reaches `check_video` as an all-`None` motion, normalises to `None`,
    // equals the clip that went in, and is refused as the no-op it is
    // rather than registering a phantom undo step.
    plain().refuses(&set_video(json!({ "motion": {} })));

    // The READER is deliberately not in this business, and it is recorded
    // rather than fixed: a file that arrives already spelled the long way
    // keeps that spelling until something patches it. Normalising on read
    // would mean the reader rewriting a document nobody asked it to touch,
    // which is the rule `schema_v3.rs` states for identity — a file opens
    // as what it says. The two writers a person can reach (the patch path
    // and the split rule) are where the single spelling is enforced.
    let long_way = Handle::from_value(&moving(
        8,
        Some(json!({ "in": null, "out": null, "during": null })),
    ))
    .value();
    assert_eq!(
        at(&long_way, "/clips/0/video/motion"),
        &json!({ "in": null, "out": null, "during": null })
    );
    // ...and the first patch that touches it puts it right.
    let patched = Handle::from_value(&moving(
        8,
        Some(json!({ "in": null, "out": null, "during": null })),
    ))
    .apply(&set_video(json!({ "motion": { "out": null } })))
    .value();
    assert_eq!(at(&patched, "/clips/0/video/motion"), &Value::Null);
}

// ---- the checks ----------------------------------------------------------

#[test]
fn every_range_check_refuses_by_name() {
    let handle = plain();
    for (patch, message) in [
        (
            json!({ "motion": { "in": { "kind": "fade", "duration": -1 } } }),
            "video.motion.in.duration must not be negative, not -1",
        ),
        (
            json!({ "motion": { "out": { "kind": "fade", "duration": -20000 } } }),
            "video.motion.out.duration must not be negative, not -20000",
        ),
        (
            json!({ "motion": { "during": { "kind": "pulse", "amount": 1.5 } } }),
            "video.motion.during.amount must be between 0 and 1, not 1.5",
        ),
        (
            json!({ "motion": { "during": { "kind": "pulse", "amount": -0.5 } } }),
            "video.motion.during.amount must be between 0 and 1, not -0.5",
        ),
        (
            json!({ "motion": { "during": { "kind": "pulse", "period": 0 } } }),
            "video.motion.during.period must be at least one tick, not 0",
        ),
        (
            json!({ "motion": { "during": { "kind": "pulse", "period": -600000 } } }),
            "video.motion.during.period must be at least one tick, not -600000",
        ),
    ] {
        assert_eq!(handle.errors(&set_video(patch)), message);
    }

    // A duration of 0 is LEGAL — it means that end of the clip does not
    // move — which is the boundary the negative cases above sit beside.
    let zero = handle
        .apply(&set_video(json!({
            "motion": { "in": { "kind": "fade", "duration": 0 } }
        })))
        .value();
    assert_eq!(num(&zero, "/clips/0/video/motion/in/duration"), 0.0);
}

// ---- the frame grid ------------------------------------------------------

#[test]
fn a_motions_ticks_are_snapped_to_the_frame_grid_by_the_patch_door() {
    // The core's Times rule — every tick value that reaches the model is
    // snapped first (core/CLAUDE.md) — holds for these two as of D1·2
    // (kpgalligan/framejob#3). It did not before: the comment in
    // `props_check.rs` said "the inspector snaps", which left an agent's
    // value sub-frame and made two callers of one op disagree.
    //
    // The canvas is 30 fps, so a frame is 20 000 ticks.
    let handle = plain();
    let snapped = handle
        .apply(&set_video(json!({
            "motion": { "in": { "kind": "fade", "duration": 310_000 },
                        "out": { "kind": "pop", "duration": 9_999 },
                        "during": { "kind": "pulse", "amount": 0.5, "period": 1_200_001 } }
        })))
        .value();
    assert_eq!(
        at(&snapped, "/clips/0/video/motion"),
        &json!({
            // 15.5 frames, rounded half AWAY from zero like every other
            // snapped length in the crate.
            "in": { "kind": "fade", "duration": 320_000 },
            // Half a frame: the nearest boundary is 0, which is a legal
            // duration and means that end of the clip does not move.
            "out": { "kind": "pop", "duration": 0 },
            "during": { "kind": "pulse", "amount": 0.5, "period": 1_200_000 }
        })
    );

    // `period` is the one value with no zero — it divides in every `during`
    // formula — so it lands on the FIRST frame rather than on the nearest
    // one when the nearest is nothing. The range check that says "at least
    // one tick" runs on what the caller sent, so a negative one is still
    // named rather than snapped into legality.
    let floored = handle
        .apply(&set_video(json!({
            "motion": { "during": { "kind": "pulse", "amount": 0.5, "period": 5 } }
        })))
        .value();
    assert_eq!(
        num(&floored, "/clips/0/video/motion/during/period"),
        20_000.0
    );
    assert_eq!(
        handle.errors(&set_video(json!({
            "motion": { "during": { "kind": "pulse", "period": -1 } }
        }))),
        "video.motion.during.period must be at least one tick, not -1"
    );

    // A value already ON the grid that changes nothing is an identity — no
    // undo step, and no sentence — which is what keeps the snap from turning
    // every repeated write into an edit.
    let stored = Handle::from_value(&moving(8, Some(full_motion())));
    stored.refuses(&set_video(json!({ "motion": full_motion() })));
    // ...and a sub-frame value that snaps ONTO the stored one is the same
    // identity, for the same reason.
    stored.refuses(&set_video(json!({
        "motion": { "in": { "kind": "slide_up", "duration": SEC / 2 + 9_999 } }
    })));
}

#[test]
fn a_misspelt_key_is_refused_by_name_at_every_level() {
    // `Group::template`'s doing: `check_keys` recurses into objects against
    // a fully populated struct, and `Motion::template()` is what gives it
    // something to recurse INTO. With a `None` in the template the two
    // nested cases here would be accepted and silently dropped.
    let handle = plain();
    for (patch, needle) in [
        (json!({ "motion": { "inn": {} } }), "motion.inn"),
        (
            json!({ "motion": { "in": { "durration": 1 } } }),
            "motion.in.durration",
        ),
        (
            json!({ "motion": { "during": { "ammount": 0.5 } } }),
            "motion.during.ammount",
        ),
    ] {
        common::assert_contains(&handle.errors(&set_video(patch)), needle);
    }
}

#[test]
fn an_unknown_kind_is_refused_at_the_serde_boundary() {
    // Both enums are closed, so a misspelt kind is a schema error on the
    // way in rather than a value clamped later — there is no neutral motion
    // to fall back to. The refusal names the slot's path and the value sent
    // (D1·1, kpgalligan/framejob#2; it used to read "video patch does not
    // match the schema" and say nothing of which slot).
    let handle = plain();
    let msg = handle.errors(&set_video(
        json!({ "motion": { "in": { "kind": "slide_lft" } } }),
    ));
    common::assert_contains(&msg, "bad value at \"motion.in.kind\" in a video patch: ");
    common::assert_contains(&msg, "`slide_lft`");
    let msg = handle.errors(&set_video(
        json!({ "motion": { "during": { "kind": "wobble" } } }),
    ));
    common::assert_contains(
        &msg,
        "bad value at \"motion.during.kind\" in a video patch: ",
    );
    common::assert_contains(&msg, "`wobble`");
}

// ---- not an animation target ---------------------------------------------

#[test]
fn set_action_end_refuses_a_patch_naming_motion() {
    // Spec §5.4, and the op's ONE refusal past "the patch must be an
    // object". A preset is anchored to the clip's two ends and an action is
    // a ramp between two states, so there is nothing to interpolate.
    let with_action = plain().apply(&json!({
        "op": "add_action", "clip": 11, "at": 0, "duration": SEC
    }));
    let action = num(&with_action.value(), "/clips/0/actions/0/id") as u32;
    let end = |patch: Value| json!({ "op": "set_action_end", "clip": 11, "action": action, "patch": patch });
    for patch in [
        json!({ "video": { "motion": {} } }),
        json!({ "video": { "motion": null } }),
        json!({ "video": { "opacity": 0.0, "motion": { "in": { "kind": "fade" } } } }),
    ] {
        assert_eq!(
            with_action.errors(&end(patch)),
            "video.motion is not an animation target"
        );
    }

    // An end patch that says nothing about motion is untouched by the rule,
    // which is what keeps the op lenient everywhere else.
    let ok = with_action.apply(&end(json!({ "video": { "opacity": 0.0 } })));
    assert_eq!(
        num(&ok.value(), "/clips/0/actions/0/end/video/opacity"),
        0.0
    );
}

/// [`plain`]'s fixture with one action over the whole clip whose `end` is
/// written straight into the file — the path `set_action_end`'s refusal
/// cannot reach, and the reason `evaluate_clip` restores rather than trusts.
fn with_written_end(motion: Option<Value>, end: Value) -> Handle {
    let mut project = moving(8, motion);
    project["clips"][0]["actions"] = json!([{
        "id": 20, "start": 0, "duration": 6 * SEC, "curve": "linear", "end": end
    }]);
    project["next_id"] = json!(21);
    Handle::from_value(&project)
}

#[test]
fn an_end_patch_written_into_a_file_cannot_animate_motion() {
    // The refusal above is a courtesy; THIS is the enforcement. A
    // hand-written file, a pasted action or a project from another tool
    // reaches the evaluator without passing the op, so `evaluate_clip` puts
    // the base motion back over whatever the action reached.
    let handle = with_written_end(
        Some(full_motion()),
        json!({ "video": { "motion": { "in": { "kind": "spin", "duration": 5 * SEC } } } }),
    );
    for t in [0, SEC, 3 * SEC, 6 * SEC - 20_000] {
        let state = handle.clip_state(11, t).expect("the clip has a state");
        assert_eq!(
            at(&state, "/video/motion"),
            &full_motion(),
            "clip_state at {t} reported an animated motion"
        );
    }

    // ...and the recipe places what the BASE motion asks for and nothing
    // else, measured against a control project carrying the same base and
    // no action at all.
    let control = Handle::from_value(&moving(8, Some(full_motion())));
    for t in [0, SEC, 3 * SEC] {
        let recipe = handle.recipe(t);
        let control_recipe = control.recipe(t);
        assert_eq!(
            array(&recipe, "/layers")[0],
            array(&control_recipe, "/layers")[0],
            "the recipe at {t} differs from the un-animated control"
        );
    }
}

#[test]
fn an_end_patch_that_replaces_the_whole_video_group_falls_through_to_the_base() {
    // The "no input may panic" rule applied to a value nothing validates.
    // `merge_at` REPLACES on a type mismatch and `set_action_end` checks
    // only the patch's top level, so `state["video"]` can be any JSON type
    // by the time the motion restore runs — and `serde_json`'s
    // `IndexMut<&str>` panics on all of them but null, where it would
    // instead MINT `{"motion": …}` and have it decode as DEFAULT props
    // rather than falling through to the base. Each of these must reach the
    // base video props exactly as it did before the restore existed: a
    // caught panic would come back as "internal error" from `clip_state`
    // and as a NULL recipe, and defaults would move the clip.
    let control = Handle::from_value(&moving(8, Some(full_motion())));
    let mut base = at(&control.value(), "/clips/0/video").clone();
    // `clip_state` reports `color` with every key, tone's nine at 0 included
    // (spec §11 GR-2), where the stored clip leaves a neutral tone key out.
    for key in [
        "exposure",
        "temperature",
        "tint",
        "highlights",
        "shadows",
        "whites",
        "blacks",
        "vibrance",
        "fade",
    ] {
        base["color"][key] = json!(0.0);
    }
    // And `wheels` with all nine at 0 (spec §11 GR-11), which the stored
    // clip leaves out when neutral.
    let neutral = json!({"x": 0.0, "y": 0.0, "master": 0.0});
    base["wheels"] = json!({"lift": neutral, "gamma": neutral, "gain": neutral});
    // And `curves` with all six as the identity (spec §11 GR-12, GR-32),
    // which the stored clip leaves out.
    let identity = json!([[0.0, 0.0], [1.0, 1.0]]);
    base["curves"] = json!({"master": identity, "red": identity, "green": identity,
        "blue": identity, "hue_hue": [[0.0, 0.0], [180.0, 0.0]],
        "hue_sat": [[0.0, 1.0], [180.0, 1.0]]});
    for replacement in [
        json!(5),
        json!(null),
        json!("slide"),
        json!([1, 2]),
        json!(true),
    ] {
        let handle = with_written_end(Some(full_motion()), json!({ "video": replacement.clone() }));
        let state = handle
            .clip_state(11, 3 * SEC)
            .unwrap_or_else(|| panic!("clip_state failed for {replacement}"));
        assert_eq!(
            at(&state, "/video"),
            &base,
            "an end patch of {replacement} did not fall through to the base video props"
        );
        let recipe = handle.recipe(3 * SEC);
        let control_recipe = control.recipe(3 * SEC);
        assert_eq!(
            array(&recipe, "/layers")[0],
            array(&control_recipe, "/layers")[0],
            "the recipe under an end patch of {replacement} is not the base's"
        );
    }
}
