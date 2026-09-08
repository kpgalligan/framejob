//! Black-box tests for what format version 2 added — filters, reflection,
//! spotlight, reversed media, audio pan / compressor / noise reduction, and
//! nests — driven through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Four things are pinned here, and each is a promise the rest of M3 leans
//! on:
//!
//! - **A version-1 file still opens.** Every new field carries a serde
//!   default, so that is nearly free; the one shape serde cannot take with
//!   a default is a nest clip's `project`, which was a path and is now an
//!   id, and `format::migrate_1_to_2` is the reason it still reads.
//! - **Every new value is policed by `set_video` / `set_audio`**, naming
//!   the offending key and number the way §5.2's ranges say, including the
//!   `MAX_FILTERS` shader budget.
//! - **`validate` refuses a broken nest graph** — a duplicate id anywhere
//!   in the one id space, a nest that reaches itself, and a stack deeper
//!   than `MAX_NEST_DEPTH` — and the caps count what is inside a nest.
//! - **Every new prop interpolates the §5.4 way**, against an oracle
//!   written out by hand here. The filter LIST is the interesting one: it
//!   is the schema's first array of objects, and the rules it lands on
//!   (same kind interpolates, different kind or different length switches
//!   at the end) are invisible until somebody animates one.
//!
//! That last section outgrew version 2 in road map 2's phase 3c, and
//! deliberately: the rules the filter cases pin are the CRATE's list rule,
//! not the filter's, so the two cases only a SECOND list can show are
//! pinned here beside them rather than in a file of their own — a version-4
//! `video.obscure` entry that changes `shape` holding while its neighbour
//! interpolates, and the `video.spotlight` animation that must NOT change
//! because of it. `actions.rs`'s `ENTRY_DISCRIMINANTS` argues why those two
//! answers differ; these are the tests that would fail if a later hand
//! collapsed them into one.

mod common;

use serde_json::{json, Value};

use common::{array, assert_contains, at, num, text, Handle};

/// Ticks per second (spec §5.1), written out rather than imported so a
/// change to `time::TIMESCALE` fails these tests instead of moving with
/// them.
const SEC: i64 = 600_000;

/// Every expected value below is exactly representable in binary floating
/// point, so this absorbs only the multiply-and-add on the way.
const EPS: f64 = 1e-12;

// ---- fixtures ------------------------------------------------------------

fn video_media(id: u32) -> Value {
    json!({
        "id": id, "path": format!("/fixtures/{id}.mov"), "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

/// One media, one track, one 10 s media clip (id 11) carrying both property
/// groups — the shape `set_video` and `set_audio` need to see.
fn one_clip(video: Value, audio: Value) -> Value {
    json!({
        "version": 2,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [video_media(1)],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "video": video, "audio": audio
        }],
        "next_id": 12
    })
}

fn plain() -> Handle {
    Handle::from_value(&one_clip(json!({}), json!({})))
}

/// A project whose clip 11 carries `video`/`audio` and one linear action
/// running 2 s to 4 s with `end` as its patch — so at 3 s the eased
/// progress is exactly 0.5 and the oracle below is arithmetic on paper.
fn animated(video: Value, audio: Value, end: Value) -> Handle {
    let mut project = one_clip(video, audio);
    project["clips"][0]["actions"] = json!([{
        "id": 21, "start": 2 * SEC, "duration": 2 * SEC, "curve": "linear",
        "end": end
    }]);
    project["next_id"] = json!(22);
    Handle::from_value(&project)
}

/// One nest: a group of tracks and clips in the parent's id space.
fn nest(id: u32, track: u32, clips: Vec<Value>) -> Value {
    json!({
        "id": id, "name": format!("Nest {id}"), "width": 1920, "height": 1080,
        "tracks": [{ "id": track, "name": "Nested" }],
        "clips": clips
    })
}

fn text_clip(id: u32, track: u32, start: i64) -> Value {
    json!({
        "id": id, "track": track, "start": start, "duration": SEC,
        "source": { "kind": "text" }
    })
}

fn nest_clip(id: u32, track: u32, start: i64, shows: u32) -> Value {
    json!({
        "id": id, "track": track, "start": start, "duration": SEC,
        "source": { "kind": "nest", "project": shows }
    })
}

/// A project holding `nests`, with one top-level clip showing `shows`.
fn with_nests(shows: u32, nests: Vec<Value>) -> Value {
    json!({
        "version": 2,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [nest_clip(3, 2, 0, shows)],
        "next_id": 10_000,
        "nests": nests
    })
}

fn state(handle: &Handle, t: i64) -> Value {
    handle.clip_state(11, t).expect("clip 11 exists")
}

fn close(actual: f64, expected: f64, what: &str) {
    assert!(
        (actual - expected).abs() < EPS,
        "{what}: expected {expected}, got {actual}"
    );
}

// ---- reading a version-1 file --------------------------------------------

#[test]
fn a_version_one_file_reads_with_the_new_fields_at_their_defaults() {
    // The whole point of "every new field carries a serde default": a file
    // written before any of this existed opens untouched, and what comes
    // back is a version-2 project with M1 behaviour.
    let project = Handle::from_value(&json!({
        "version": 1,
        "tracks": [{ "id": 1 }],
        "clips": [{
            "id": 2, "track": 1, "start": 0, "duration": SEC,
            "source": { "kind": "text" }, "video": {}, "audio": {}
        }],
        "next_id": 3
    }))
    .value();

    assert_eq!(at(&project, "/version"), &json!(4));
    assert_eq!(at(&project, "/nests"), &json!([]));
    assert_eq!(at(&project, "/clips/0/video/filters"), &json!([]));
    assert_eq!(at(&project, "/clips/0/video/reflection"), &Value::Null);
    assert_eq!(at(&project, "/clips/0/video/spotlight"), &Value::Null);
    assert_eq!(at(&project, "/clips/0/audio/pan"), &json!(0.0));
    assert_eq!(at(&project, "/clips/0/audio/compressor"), &Value::Null);
    assert_eq!(at(&project, "/clips/0/audio/noise_reduction"), &json!(0.0));
}

#[test]
fn a_version_one_nest_path_becomes_a_named_empty_nest() {
    // Version 1 spelled `source.project` as a PATH the core could never
    // resolve. Version 2 spells it as a nest id, and the migration keeps
    // the clip rather than dropping it: the path survives as the nest's
    // name, and the nest itself is empty because there was never anything
    // in the file to fill it with.
    let project = Handle::from_value(&json!({
        "version": 1,
        "canvas": { "width": 1280, "height": 720, "fps": [30, 1] },
        "tracks": [{ "id": 1 }],
        "clips": [{
            "id": 2, "track": 1, "start": 0, "duration": SEC,
            "source": { "kind": "nest", "project": "Intro.reelcut" }
        }],
        "next_id": 3
    }))
    .value();

    let id = at(&project, "/clips/0/source/project")
        .as_u64()
        .expect("the migrated payload is a nest id, not a path");
    assert_eq!(id, 3, "the nest takes the file's next free id");
    assert_eq!(
        at(&project, "/nests/0"),
        &json!({
            "id": 3, "name": "Intro.reelcut", "width": 1280, "height": 720,
            "tracks": [], "clips": []
        }),
        "the nest carries the path as its name and the file's canvas"
    );
    // The counter moved past the id the migration handed out, which is
    // what keeps `validate` happy and the next `allocate_id` unique.
    assert_eq!(at(&project, "/next_id"), &json!(4));
}

#[test]
fn a_version_one_file_with_no_nest_clip_is_untouched_by_the_migration() {
    let project = Handle::from_value(&json!({
        "version": 1,
        "tracks": [{ "id": 1 }],
        "clips": [{ "id": 2, "track": 1, "start": 0, "duration": SEC,
                    "source": { "kind": "text" } }],
        "next_id": 3
    }))
    .value();
    assert_eq!(at(&project, "/next_id"), &json!(3), "next_id must not move");
    assert_eq!(at(&project, "/nests"), &json!([]));
}

// ---- reversed media ------------------------------------------------------

#[test]
fn reversed_survives_a_round_trip_and_defaults_to_forward() {
    let project = Handle::from_value(&one_clip(json!({}), json!({}))).value();
    assert_eq!(
        at(&project, "/clips/0/source/reversed"),
        &json!(false),
        "a source that does not mention it plays forward"
    );

    let mut reversed = one_clip(json!({}), json!({}));
    reversed["clips"][0]["source"] =
        json!({ "kind": "media", "media": 1, "in": 3 * SEC, "reversed": true });
    let written = Handle::from_value(&reversed).value();
    assert_eq!(at(&written, "/clips/0/source/reversed"), &json!(true));
    // `in` is untouched by the flag: it is an offset into the reversed
    // stream, which has the same duration, so every time computation in the
    // core stays as it was.
    assert_eq!(at(&written, "/clips/0/source/in"), &json!(3 * SEC));
}

// ---- the range checks ----------------------------------------------------

#[test]
fn every_new_video_value_is_range_checked_and_the_message_names_it() {
    let project = plain();
    let cases: [(Value, &str); 10] = [
        (
            json!({ "filters": [{ "kind": "blur", "amount": 1.5 }] }),
            "video.filters[].amount must be between 0 and 1, not 1.5",
        ),
        (
            json!({ "filters": [{ "kind": "blur", "amount": -0.5 }] }),
            "video.filters[].amount must be between 0 and 1, not -0.5",
        ),
        (
            json!({ "reflection": { "opacity": 2.0 } }),
            "video.reflection.opacity must be between 0 and 1, not 2",
        ),
        (
            json!({ "reflection": { "height": -0.1 } }),
            "video.reflection.height must be between 0 and 1, not -0.1",
        ),
        (
            json!({ "reflection": { "gap": -4.0 } }),
            "video.reflection.gap must be at least 0, not -4",
        ),
        (
            json!({ "reflection": { "falloff": 1.5 } }),
            "video.reflection.falloff must be between 0 and 1, not 1.5",
        ),
        (
            json!({ "spotlight": { "width": 0.0 } }),
            "video.spotlight.width must be greater than 0, not 0",
        ),
        (
            json!({ "spotlight": { "feather": -1.0 } }),
            "video.spotlight.feather must be at least 0, not -1",
        ),
        (
            json!({ "spotlight": { "dim": 1.5 } }),
            "video.spotlight.dim must be between 0 and 1, not 1.5",
        ),
        (
            // Below 1 is a magnifier held backwards, so the range starts
            // at "no zoom" rather than at 0.
            json!({ "spotlight": { "zoom": 0.5 } }),
            "video.spotlight.zoom must be between 1 and 2, not 0.5",
        ),
    ];
    for (patch, expected) in cases {
        let msg = project.errors(&json!({ "op": "set_video", "clips": [11], "patch": patch }));
        assert_eq!(msg, expected);
    }
}

#[test]
fn every_new_audio_value_is_range_checked_and_the_message_names_it() {
    let project = plain();
    let cases: [(Value, &str); 6] = [
        (
            json!({ "pan": -1.5 }),
            "audio.pan must be between -1 and 1, not -1.5",
        ),
        (
            json!({ "noise_reduction": 2.0 }),
            "audio.noise_reduction must be between 0 and 1, not 2",
        ),
        (
            json!({ "compressor": { "threshold_db": -80.0 } }),
            "audio.compressor.threshold_db must be between -60 and 0, not -80",
        ),
        (
            json!({ "compressor": { "ratio": 0.5 } }),
            "audio.compressor.ratio must be between 1 and 20, not 0.5",
        ),
        (
            json!({ "compressor": { "attack": -1 } }),
            "audio.compressor.attack must not be negative, not -1",
        ),
        (
            json!({ "compressor": { "makeup_db": 30.0 } }),
            "audio.compressor.makeup_db must be between 0 and 24, not 30",
        ),
    ];
    for (patch, expected) in cases {
        let msg = project.errors(&json!({ "op": "set_audio", "clips": [11], "patch": patch }));
        assert_eq!(msg, expected);
    }
}

#[test]
fn the_filter_budget_is_named_rather_than_silently_trimmed() {
    // MAX_FILTERS is the uniform block's four (kind, amount) pairs. A fifth
    // filter would be dropped from the next write and the user would be
    // looking at a control that did nothing, so the op refuses.
    let project = plain();
    let five = json!({
        "filters": [
            { "kind": "blur" }, { "kind": "sharpen" }, { "kind": "sepia" },
            { "kind": "noir" }, { "kind": "invert" }
        ]
    });
    let msg = project.errors(&json!({ "op": "set_video", "clips": [11], "patch": five }));
    assert_eq!(msg, "video.filters must hold at most 4 filters, not 5");

    // Four is the boundary and it is inclusive.
    let four = json!({
        "filters": [
            { "kind": "blur" }, { "kind": "sharpen" }, { "kind": "sepia" },
            { "kind": "noir" }
        ]
    });
    let applied = project
        .apply(&json!({ "op": "set_video", "clips": [11], "patch": four }))
        .value();
    assert_eq!(array(&applied, "/clips/0/video/filters").len(), 4);
    assert_eq!(text(&applied, "/clips/0/video/filters/3/kind"), "noir");
    // An omitted `amount` is the Filter default, not zero: a filter added
    // from the inspector has to do something visible.
    close(
        num(&applied, "/clips/0/video/filters/0/amount"),
        0.5,
        "the default amount",
    );
}

#[test]
fn an_unknown_key_inside_a_filter_is_named_like_any_other() {
    // `filters` is the schema's first array of objects, so the unknown-key
    // check has to descend into an array's elements — otherwise serde drops
    // the misspelling in silence, which is exactly what edit_props.rs
    // exists to prevent.
    let msg = plain().errors(&json!({
        "op": "set_video", "clips": [11],
        "patch": { "filters": [{ "kind": "blur", "amont": 0.5 }] }
    }));
    assert_contains(&msg, "unknown key");
    assert_contains(&msg, "amont");
}

#[test]
fn a_new_value_inside_range_applies_and_round_trips() {
    let project = plain()
        .apply(&json!({
            "op": "set_video", "clips": [11],
            "patch": {
                "filters": [{ "kind": "vignette", "amount": 0.75 }],
                "reflection": { "opacity": 0.5, "height": 0.25, "gap": 8.0, "falloff": 0.5 },
                "spotlight": { "shape": "ellipse", "x": 40.0, "y": -20.0, "width": 600.0,
                               "height": 400.0, "feather": 12.0, "dim": 0.8, "zoom": 1.75 }
            }
        }))
        .apply(&json!({
            "op": "set_audio", "clips": [11],
            "patch": {
                "pan": 0.5, "noise_reduction": 0.4,
                "compressor": { "threshold_db": -12.0, "ratio": 6.0, "attack": 3000,
                                "release": 60_000, "makeup_db": 6.0 }
            }
        }))
        .value();

    assert_eq!(
        at(&project, "/clips/0/video/spotlight"),
        &json!({ "shape": "ellipse", "x": 40.0, "y": -20.0, "width": 600.0,
                 "height": 400.0, "feather": 12.0, "dim": 0.8, "zoom": 1.75 })
    );
    assert_eq!(
        at(&project, "/clips/0/video/reflection"),
        &json!({ "opacity": 0.5, "height": 0.25, "gap": 8.0, "falloff": 0.5 })
    );
    assert_eq!(
        at(&project, "/clips/0/audio/compressor"),
        &json!({ "threshold_db": -12.0, "ratio": 6.0, "attack": 3000,
                 "release": 60_000, "makeup_db": 6.0 })
    );
    close(num(&project, "/clips/0/audio/pan"), 0.5, "pan");
}

// ---- the recipe ----------------------------------------------------------

#[test]
fn every_layer_carries_the_new_recipe_keys() {
    let handle = plain().apply(&json!({
        "op": "set_video", "clips": [11],
        "patch": { "filters": [{ "kind": "sepia", "amount": 0.5 }],
                   "reflection": {}, "spotlight": {} }
    }));
    let recipe = handle.recipe(SEC);
    let layer = &array(&recipe, "/layers")[0];

    assert_eq!(text(layer, "/filters/0/kind"), "sepia");
    close(num(layer, "/filters/0/amount"), 0.5, "the layer's filter");
    close(
        num(layer, "/reflection/opacity"),
        0.35,
        "the layer's reflection",
    );
    close(num(layer, "/spotlight/dim"), 0.6, "the layer's spotlight");
    // Always null for now: only a nest sets one, and nest evaluation is not
    // written yet. The key is emitted so the compositor can implement the
    // clip once, against a recipe shape that will not change.
    assert_eq!(at(layer, "/clip_rect"), &Value::Null);
}

#[test]
fn a_layer_with_nothing_set_still_carries_the_keys() {
    let recipe = plain().recipe(SEC);
    let layer = &array(&recipe, "/layers")[0];
    assert_eq!(at(layer, "/filters"), &json!([]));
    assert_eq!(at(layer, "/reflection"), &Value::Null);
    assert_eq!(at(layer, "/spotlight"), &Value::Null);
    assert_eq!(at(layer, "/clip_rect"), &Value::Null);
}

// ---- interpolation -------------------------------------------------------

#[test]
fn a_filter_amount_interpolates_while_the_kind_holds() {
    // 0.2 -> 1.0 over 2 s, linear: halfway is 0.2 + 0.8 * 0.5.
    let handle = animated(
        json!({ "filters": [{ "kind": "blur", "amount": 0.2 }] }),
        json!({}),
        json!({ "video": { "filters": [{ "kind": "blur", "amount": 1.0 }] } }),
    );
    for (t, expected) in [(2 * SEC, 0.2), (3 * SEC, 0.6), (4 * SEC, 1.0)] {
        let at_t = state(&handle, t);
        close(
            num(&at_t, "/video/filters/0/amount"),
            expected,
            &format!("amount at {t}"),
        );
        assert_eq!(text(&at_t, "/video/filters/0/kind"), "blur");
    }
}

#[test]
fn a_filter_patch_that_names_no_kind_still_interpolates() {
    // "Same filter, more of it" is the common animation, and leaving `kind`
    // out of the patch is how a builder writes it.
    let handle = animated(
        json!({ "filters": [{ "kind": "blur", "amount": 0.2 }] }),
        json!({}),
        json!({ "video": { "filters": [{ "amount": 1.0 }] } }),
    );
    let halfway = state(&handle, 3 * SEC);
    close(
        num(&halfway, "/video/filters/0/amount"),
        0.6,
        "amount halfway",
    );
    assert_eq!(text(&halfway, "/video/filters/0/kind"), "blur");
}

#[test]
fn a_filter_that_changes_kind_switches_at_the_end() {
    // A blur's strength and a sepia's are not the same quantity, so there
    // is nothing to interpolate: the element holds, then switches, exactly
    // as a bare string field does (§5.4).
    let handle = animated(
        json!({ "filters": [{ "kind": "blur", "amount": 0.2 }] }),
        json!({}),
        json!({ "video": { "filters": [{ "kind": "sepia", "amount": 1.0 }] } }),
    );
    let halfway = state(&handle, 3 * SEC);
    assert_eq!(text(&halfway, "/video/filters/0/kind"), "blur");
    close(num(&halfway, "/video/filters/0/amount"), 0.2, "held amount");

    let ended = state(&handle, 4 * SEC);
    assert_eq!(text(&ended, "/video/filters/0/kind"), "sepia");
    close(
        num(&ended, "/video/filters/0/amount"),
        1.0,
        "switched amount",
    );
}

#[test]
fn a_filter_list_of_a_different_length_switches_at_the_end() {
    // One filter toward two has no correspondence between the elements —
    // the only alternative is to invent an off-strength second filter to
    // grow from, which is a guess about what the list means.
    let handle = animated(
        json!({ "filters": [{ "kind": "blur", "amount": 0.2 }] }),
        json!({}),
        json!({ "video": { "filters": [
            { "kind": "blur", "amount": 0.2 },
            { "kind": "vignette", "amount": 1.0 }
        ] } }),
    );
    assert_eq!(array(&state(&handle, 3 * SEC), "/video/filters").len(), 1);
    let ended = state(&handle, 4 * SEC);
    assert_eq!(array(&ended, "/video/filters").len(), 2);
    assert_eq!(text(&ended, "/video/filters/1/kind"), "vignette");
}

/// One hidden region, written out WHOLE. An end patch replaces a list
/// rather than merging into it, so a partial entry would take its missing
/// keys from `ObscureRegion::default()` at the switch — a real property of
/// the schema (the filter tests above lean on it deliberately) but noise in
/// a test measuring which entries held and which moved.
fn region(shape: &str, kind: &str, width: f64, amount: f64) -> Value {
    json!({
        "shape": shape, "x": 0.0, "y": 0.0, "width": width, "height": 200.0,
        "feather": 0.0, "kind": kind, "amount": amount
    })
}

#[test]
fn an_obscure_region_that_changes_shape_holds_and_switches_at_the_end() {
    // Version 4's `video.obscure` is the schema's SECOND array of objects
    // and gets not one line of interpolation code of its own — the list
    // rule (`actions.rs`, on `lerp`) already governs it. What it adds is a
    // second discrete field: `shape` names WHAT the entry is, so a rect
    // toward an ellipse is not a rectangle growing rounder, it is another
    // region arriving at that index, and there is nothing to morph.
    let handle = animated(
        json!({ "obscure": [region("rect", "pixelate", 400.0, 0.2)] }),
        json!({}),
        json!({ "video": { "obscure": [region("ellipse", "pixelate", 800.0, 1.0)] } }),
    );

    let halfway = state(&handle, 3 * SEC);
    assert_eq!(text(&halfway, "/video/obscure/0/shape"), "rect");
    close(num(&halfway, "/video/obscure/0/width"), 400.0, "held width");
    close(num(&halfway, "/video/obscure/0/amount"), 0.2, "held amount");

    let ended = state(&handle, 4 * SEC);
    assert_eq!(text(&ended, "/video/obscure/0/shape"), "ellipse");
    close(
        num(&ended, "/video/obscure/0/width"),
        800.0,
        "switched width",
    );
    close(
        num(&ended, "/video/obscure/0/amount"),
        1.0,
        "switched amount",
    );
}

#[test]
fn an_obscure_list_interpolates_per_index_and_holds_only_the_entry_that_changed() {
    // The hold is per ENTRY, not per list: the correspondence a matching
    // length establishes is index by index, and index 1 losing it says
    // nothing about index 0. A screencast whose blur grows over a face
    // while a second region is swapped for another shape must still see
    // the first one grow.
    let handle = animated(
        json!({ "obscure": [
            region("rect", "pixelate", 400.0, 0.2),
            region("rect", "blur", 400.0, 0.2)
        ] }),
        json!({}),
        json!({ "video": { "obscure": [
            region("rect", "pixelate", 800.0, 1.0),
            region("ellipse", "blur", 800.0, 1.0)
        ] } }),
    );

    let halfway = state(&handle, 3 * SEC);
    close(num(&halfway, "/video/obscure/0/width"), 600.0, "width at 0");
    close(num(&halfway, "/video/obscure/0/amount"), 0.6, "amount at 0");
    close(num(&halfway, "/video/obscure/1/width"), 400.0, "width at 1");
    close(num(&halfway, "/video/obscure/1/amount"), 0.2, "amount at 1");
    assert_eq!(text(&halfway, "/video/obscure/1/shape"), "rect");
}

#[test]
fn a_spotlight_that_changes_shape_still_interpolates_its_geometry() {
    // A REGRESSION GUARD, and the reason `shape` is a discriminant for a
    // list ENTRY only. There is exactly one `video.spotlight`: rounding it
    // off is a change to that spotlight, not another one arriving in its
    // place, so its centre, its box and its dim keep moving through the
    // change exactly as they did before version 4 existed. Widening
    // `lerp_at`'s object rule to `shape` would freeze all three until the
    // last instant and then jump them — silently, in a feature phase 3 has
    // nothing to do with. This test is what says so out loud.
    let handle = animated(
        json!({ "spotlight": { "shape": "rect", "x": 0.0, "y": 0.0, "width": 400.0,
                               "height": 200.0, "feather": 0.0, "dim": 0.0, "zoom": 1.0 } }),
        json!({}),
        json!({ "video": { "spotlight": {
            "shape": "ellipse", "x": 200.0, "width": 800.0, "dim": 1.0
        } } }),
    );

    let halfway = state(&handle, 3 * SEC);
    close(num(&halfway, "/video/spotlight/x"), 100.0, "x");
    close(num(&halfway, "/video/spotlight/width"), 600.0, "width");
    close(num(&halfway, "/video/spotlight/dim"), 0.5, "dim");
    // The enum itself is a string and switches at the end, as it always
    // has — it is the numbers beside it that must not wait for it.
    assert_eq!(text(&halfway, "/video/spotlight/shape"), "rect");

    let ended = state(&handle, 4 * SEC);
    assert_eq!(text(&ended, "/video/spotlight/shape"), "ellipse");
    close(num(&ended, "/video/spotlight/x"), 200.0, "x at the end");
    close(
        num(&ended, "/video/spotlight/width"),
        800.0,
        "width at the end",
    );
}

#[test]
fn reflection_and_spotlight_interpolate_field_by_field() {
    let handle = animated(
        json!({
            "reflection": { "opacity": 0.2, "height": 0.4, "gap": 0.0, "falloff": 1.0 },
            "spotlight": { "shape": "rect", "x": 0.0, "y": 0.0, "width": 400.0,
                           "height": 200.0, "feather": 0.0, "dim": 0.0, "zoom": 1.0 }
        }),
        json!({}),
        json!({ "video": {
            "reflection": { "opacity": 1.0, "gap": 40.0 },
            "spotlight": { "x": 200.0, "dim": 1.0, "zoom": 2.0 }
        } }),
    );

    let halfway = state(&handle, 3 * SEC);
    close(num(&halfway, "/video/reflection/opacity"), 0.6, "opacity");
    close(num(&halfway, "/video/reflection/gap"), 20.0, "gap");
    // A key the patch never mentions holds its base value.
    close(num(&halfway, "/video/reflection/height"), 0.4, "height");
    close(num(&halfway, "/video/spotlight/x"), 100.0, "x");
    close(num(&halfway, "/video/spotlight/dim"), 0.5, "dim");
    close(num(&halfway, "/video/spotlight/zoom"), 1.5, "zoom");
    // `shape` is an enum: it would switch at the end, and here it never
    // changes at all.
    assert_eq!(text(&halfway, "/video/spotlight/shape"), "rect");
}

#[test]
fn pan_noise_reduction_and_the_compressor_interpolate() {
    let handle = animated(
        json!({}),
        json!({
            "pan": -1.0, "noise_reduction": 0.0,
            "compressor": { "threshold_db": -40.0, "ratio": 2.0, "attack": 6000,
                            "release": 120_000, "makeup_db": 0.0 }
        }),
        json!({ "audio": {
            "pan": 1.0, "noise_reduction": 1.0,
            "compressor": { "threshold_db": 0.0, "ratio": 10.0, "attack": 12_000 }
        } }),
    );

    let halfway = state(&handle, 3 * SEC);
    close(num(&halfway, "/audio/pan"), 0.0, "pan");
    close(
        num(&halfway, "/audio/noise_reduction"),
        0.5,
        "noise_reduction",
    );
    close(
        num(&halfway, "/audio/compressor/threshold_db"),
        -20.0,
        "threshold_db",
    );
    close(num(&halfway, "/audio/compressor/ratio"), 6.0, "ratio");
    // Attack is Ticks — an integer in the schema — so it must interpolate
    // as one rather than becoming 9000.5 and failing to deserialize.
    assert_eq!(at(&halfway, "/audio/compressor/attack"), &json!(9000));
}

#[test]
fn an_action_end_outside_the_range_is_clamped_rather_than_refused() {
    // An `end` patch is deliberately lenient — a half-written animation
    // stays editable — so nothing rejects it. The clamp is the last line of
    // defence before a nonsense uniform reaches the compositor.
    let handle = animated(
        json!({ "filters": [{ "kind": "blur", "amount": 0.5 }], "spotlight": {} }),
        json!({ "pan": 0.0, "noise_reduction": 0.0, "compressor": {} }),
        json!({
            "video": {
                "filters": [{ "kind": "blur", "amount": 5.0 }],
                "spotlight": { "dim": -2.0, "zoom": 9.0, "width": 0.0 },
                "reflection": { "opacity": 4.0, "falloff": -1.0 }
            },
            "audio": {
                "pan": -9.0, "noise_reduction": 4.0,
                "compressor": { "ratio": 100.0, "makeup_db": -5.0, "threshold_db": -900.0 }
            }
        }),
    );

    let ended = state(&handle, 4 * SEC);
    close(num(&ended, "/video/filters/0/amount"), 1.0, "amount");
    close(num(&ended, "/video/spotlight/dim"), 0.0, "dim");
    close(num(&ended, "/video/spotlight/zoom"), 2.0, "zoom");
    close(num(&ended, "/video/spotlight/width"), 1.0, "width");
    close(num(&ended, "/video/reflection/opacity"), 1.0, "opacity");
    close(num(&ended, "/video/reflection/falloff"), 0.0, "falloff");
    close(num(&ended, "/audio/pan"), -1.0, "pan");
    close(
        num(&ended, "/audio/noise_reduction"),
        1.0,
        "noise_reduction",
    );
    close(num(&ended, "/audio/compressor/ratio"), 20.0, "ratio");
    close(num(&ended, "/audio/compressor/makeup_db"), 0.0, "makeup_db");
    close(
        num(&ended, "/audio/compressor/threshold_db"),
        -60.0,
        "threshold_db",
    );
}

#[test]
fn an_action_that_asks_for_more_filters_than_the_budget_keeps_the_first_four() {
    // The shader budget is a hard limit on the RECIPE, not a preference,
    // and the extras go from the end so the ones the user put first live.
    let handle = animated(
        json!({ "filters": [{ "kind": "blur", "amount": 0.5 }] }),
        json!({}),
        json!({ "video": { "filters": [
            { "kind": "blur", "amount": 1.0 }, { "kind": "sharpen", "amount": 1.0 },
            { "kind": "sepia", "amount": 1.0 }, { "kind": "noir", "amount": 1.0 },
            { "kind": "invert", "amount": 1.0 }, { "kind": "vignette", "amount": 1.0 }
        ] } }),
    );
    let ended = state(&handle, 4 * SEC);
    let filters = array(&ended, "/video/filters");
    assert_eq!(filters.len(), 4, "the recipe never carries a fifth filter");
    assert_eq!(text(&ended, "/video/filters/0/kind"), "blur");
    assert_eq!(text(&ended, "/video/filters/3/kind"), "noir");
}

#[test]
fn an_action_that_asks_for_more_regions_than_the_budget_keeps_the_first_four() {
    // `MAX_OBSCURE` is the same hard limit on the recipe for the same
    // reason, and an `end` patch is the way past `set_video`'s named
    // refusal, so the evaluator has to hold the line for the shader.
    let handle = animated(
        json!({ "obscure": [region("rect", "pixelate", 100.0, 1.0)] }),
        json!({}),
        json!({ "video": { "obscure": [
            region("rect", "pixelate", 100.0, 1.0),
            region("rect", "pixelate", 200.0, 1.0),
            region("rect", "pixelate", 300.0, 1.0),
            region("rect", "pixelate", 400.0, 1.0),
            region("rect", "pixelate", 500.0, 1.0)
        ] } }),
    );
    let ended = state(&handle, 4 * SEC);
    assert_eq!(
        array(&ended, "/video/obscure").len(),
        4,
        "the recipe never carries a fifth region"
    );
    close(num(&ended, "/video/obscure/0/width"), 100.0, "first kept");
    close(num(&ended, "/video/obscure/3/width"), 400.0, "fourth kept");
}

#[test]
fn a_region_outside_its_ranges_is_clamped_rather_than_refused() {
    // The same last line of defence the rest of the video group gets, with
    // one value chosen differently: a NaN `amount` resolves to 1, not to 0.
    // Every other neutral in `clamp_video` is "changes nothing"; here
    // "changes nothing" would publish the face the region was drawn over.
    let handle = animated(
        json!({ "obscure": [region("rect", "pixelate", 400.0, 1.0)] }),
        json!({}),
        json!({ "video": { "obscure": [{
            "shape": "rect", "x": 0.0, "y": 0.0, "width": 0.0, "height": -10.0,
            "feather": -5.0, "kind": "blur", "amount": 4.0
        }] } }),
    );
    let ended = state(&handle, 4 * SEC);
    close(num(&ended, "/video/obscure/0/width"), 1.0, "width");
    close(num(&ended, "/video/obscure/0/height"), 1.0, "height");
    close(num(&ended, "/video/obscure/0/feather"), 0.0, "feather");
    close(num(&ended, "/video/obscure/0/amount"), 1.0, "amount");
}

// ---- nests: the schema and its invariants --------------------------------

#[test]
fn a_nest_round_trips_and_fills_in_its_defaults() {
    let project = Handle::from_value(&with_nests(
        20,
        vec![json!({ "id": 20, "clips": [], "tracks": [] })],
    ))
    .value();
    assert_eq!(
        at(&project, "/nests/0"),
        &json!({ "id": 20, "name": "", "width": 1920, "height": 1080,
                 "tracks": [], "clips": [] }),
        "a nest with only an id takes the documented defaults"
    );

    // ...and the full shape survives unchanged, ids and all.
    let full = with_nests(
        20,
        vec![nest(
            20,
            21,
            vec![text_clip(22, 21, 0), text_clip(23, 21, SEC)],
        )],
    );
    let written = Handle::from_value(&full).value();
    assert_eq!(at(&written, "/nests/0/tracks/0/id"), &json!(21));
    assert_eq!(at(&written, "/nests/0/clips/1/id"), &json!(23));
    assert_eq!(at(&written, "/clips/0/source/project"), &json!(20));
}

#[test]
fn a_clip_pointing_at_a_nest_that_is_not_there_is_refused() {
    let msg = Handle::try_from_value(&with_nests(99, vec![nest(20, 21, vec![])]))
        .expect_err("an unknown nest must be refused");
    assert_eq!(msg, "clip 3 refers to unknown nest 99");
}

#[test]
fn nested_ids_share_the_one_id_space() {
    // The reason a nest is not a nested project: one number space, so an
    // MCP call can name anything by one integer. A nested clip that reuses
    // a timeline clip's id is a duplicate, not a scoped name.
    let mut project = with_nests(20, vec![nest(20, 21, vec![text_clip(3, 21, 0)])]);
    let msg = Handle::try_from_value(&project).expect_err("a reused id must be refused");
    assert_eq!(msg, "duplicate id 3 on a clip in nest 20");

    // The same for a nested TRACK against a timeline track...
    project = with_nests(20, vec![nest(20, 2, vec![])]);
    let msg = Handle::try_from_value(&project).expect_err("a reused track id must be refused");
    assert_eq!(msg, "duplicate id 2 on a track in nest 20");

    // ...and between two nests, which is the case a second id space would
    // have made legal.
    project = with_nests(
        20,
        vec![
            nest(20, 21, vec![text_clip(22, 21, 0)]),
            nest(30, 31, vec![text_clip(22, 31, 0)]),
        ],
    );
    let msg = Handle::try_from_value(&project).expect_err("two nests sharing an id");
    assert_eq!(msg, "duplicate id 22 on a clip in nest 30");
}

#[test]
fn next_id_must_be_past_every_nested_id_too() {
    let mut project = with_nests(20, vec![nest(20, 21, vec![text_clip(22, 21, 0)])]);
    project["next_id"] = json!(22);
    let msg = Handle::try_from_value(&project).expect_err("next_id must clear nested ids");
    assert_contains(&msg, "next_id 22 is not greater than id 22");
}

#[test]
fn a_nested_clip_is_checked_against_its_own_tracks() {
    // The nest's clips live on the NEST's tracks, and the message says
    // where the offending clip actually is.
    let project = with_nests(20, vec![nest(20, 21, vec![text_clip(22, 2, 0)])]);
    let msg = Handle::try_from_value(&project).expect_err("a nested clip on a parent track");
    assert_eq!(msg, "clip 22 in nest 20 is on unknown track 2");

    let mut bad_span = with_nests(20, vec![nest(20, 21, vec![text_clip(22, 21, 0)])]);
    bad_span["nests"][0]["clips"][0]["duration"] = json!(0);
    let msg = Handle::try_from_value(&bad_span).expect_err("a zero-length nested clip");
    assert_eq!(msg, "clip 22 in nest 20 has non-positive duration 0");
}

#[test]
fn a_nested_clip_references_the_parents_media() {
    // A nest has no `media[]` of its own — that is what keeps
    // `CompositionBuilder`'s url lookup working unchanged — so a nested
    // clip naming a media the PROJECT does not hold is refused.
    let mut project = with_nests(20, vec![nest(20, 21, vec![text_clip(22, 21, 0)])]);
    project["nests"][0]["clips"][0]["source"] = json!({ "kind": "media", "media": 7, "in": 0 });
    let msg = Handle::try_from_value(&project).expect_err("an unknown media inside a nest");
    assert_eq!(msg, "clip 22 in nest 20 refers to unknown media 7");
}

#[test]
fn a_nest_that_reaches_itself_is_refused() {
    // Directly...
    let project = with_nests(20, vec![nest(20, 21, vec![nest_clip(22, 21, 0, 20)])]);
    let msg = Handle::try_from_value(&project).expect_err("a self-nesting nest");
    assert_eq!(msg, "nest 20 contains itself");

    // ...and at one remove, which is the case a naive depth counter would
    // spin on forever.
    let project = with_nests(
        20,
        vec![
            nest(20, 21, vec![nest_clip(22, 21, 0, 30)]),
            nest(30, 31, vec![nest_clip(32, 31, 0, 20)]),
        ],
    );
    let msg = Handle::try_from_value(&project).expect_err("a two-nest cycle");
    assert_eq!(msg, "nest 20 contains itself");
}

#[test]
fn a_cycle_no_clip_points_at_is_still_refused() {
    // An orphan nest is still in the file, and `unnest` can still put its
    // contents back on the timeline, so a cycle hiding in one is a corrupt
    // project whether or not anything shows it today.
    let mut project = with_nests(20, vec![nest(20, 21, vec![])]);
    project["nests"] = json!([
        nest(20, 21, vec![]),
        nest(40, 41, vec![nest_clip(42, 41, 0, 50)]),
        nest(50, 51, vec![nest_clip(52, 51, 0, 40)])
    ]);
    let msg = Handle::try_from_value(&project).expect_err("an unreferenced cycle");
    assert_eq!(msg, "nest 40 contains itself");
}

/// `depth` nests in a chain, each showing the next, with a timeline clip
/// showing the first — so the innermost sits at level `depth`.
fn chain(depth: u32) -> Value {
    let id = |level: u32| 100 + level * 10;
    let nests: Vec<Value> = (1..=depth)
        .map(|level| {
            let (nest_id, track_id, clip_id) = (id(level), id(level) + 1, id(level) + 2);
            let inner = if level == depth {
                text_clip(clip_id, track_id, 0)
            } else {
                nest_clip(clip_id, track_id, 0, id(level + 1))
            };
            nest(nest_id, track_id, vec![inner])
        })
        .collect();
    with_nests(id(1), nests)
}

#[test]
fn nesting_is_capped_at_eight_levels() {
    // Eight is `MAX_NEST_DEPTH` (RC_MAX_NEST_DEPTH in the header): the cap
    // is on the WALK, since every evaluation of a nested layer recurses
    // once per level.
    Handle::from_value(&chain(8));

    let msg = Handle::try_from_value(&chain(9)).expect_err("nine levels must be refused");
    assert_eq!(msg, "nests are more than 8 deep at nest 190");
}

#[test]
fn a_nest_shown_twice_is_walked_once_not_twice() {
    // A diamond — one nest showing another twice — is legal, and the depth
    // walk must memoize rather than re-descend, or eight levels of it is
    // exponential. Six deep, doubled at every level: 2^6 paths if the memo
    // is missing, and this test would hang rather than fail.
    let id = |level: u32| 200 + level * 10;
    let nests: Vec<Value> = (1..=6)
        .map(|level| {
            let (nest_id, track_id) = (id(level), id(level) + 1);
            let clips = if level == 6 {
                vec![text_clip(id(level) + 2, track_id, 0)]
            } else {
                vec![
                    nest_clip(id(level) + 2, track_id, 0, id(level + 1)),
                    nest_clip(id(level) + 3, track_id, SEC, id(level + 1)),
                ]
            };
            nest(nest_id, track_id, clips)
        })
        .collect();
    Handle::from_value(&with_nests(id(1), nests));
}

#[test]
fn a_nests_tracks_and_clips_count_toward_the_caps() {
    // They are the same tracks and clips — flattening a nest at evaluation
    // time gives its clips real composition tracks — so counting them
    // separately would let a project past a cap that exists to bound
    // exactly that.
    let tracks: Vec<Value> = (0..64)
        .map(|i| json!({ "id": 1000 + i, "name": "t" }))
        .collect();
    let mut project = with_nests(20, vec![nest(20, 21, vec![])]);
    project["tracks"] = Value::Array(tracks);
    project["clips"] = json!([nest_clip(3, 1000, 0, 20)]);
    let msg = Handle::try_from_value(&project).expect_err("65 tracks in total");
    assert_eq!(msg, "too many tracks: 65 (max 64)");

    // And the clip cap, one over, with the last two inside the nest.
    let clips: Vec<Value> = (0..4095)
        .map(|i| text_clip(2000 + i, 2, i as i64 * SEC))
        .collect();
    let mut project = with_nests(
        20,
        vec![nest(
            20,
            21,
            vec![text_clip(30, 21, 0), text_clip(31, 21, SEC)],
        )],
    );
    project["clips"] = Value::Array(clips);
    project["clips"]
        .as_array_mut()
        .expect("the clips array")
        .push(nest_clip(3, 2, 0, 20));
    let msg = Handle::try_from_value(&project).expect_err("4098 clips in total");
    assert_eq!(msg, "too many clips: 4098 (max 4096)");
}

#[test]
fn a_nest_clip_draws_the_clips_inside_it_and_never_itself() {
    // The schema's half of nest evaluation: a nest clip is ONE clip on the
    // timeline whose LAYERS are the clips inside it. `nest.rs` and
    // `tests/nest.rs` own the rest; what matters here is that a version-2
    // file holding one evaluates at all, and that the nest clip's own id
    // never reaches the canvas.
    let handle = Handle::from_value(&with_nests(
        20,
        vec![nest(20, 21, vec![text_clip(22, 21, 0)])],
    ));
    assert_eq!(handle.duration(), SEC, "the nest clip's own extent");
    let recipe = handle.recipe(0);
    let layers = array(&recipe, "/layers");
    assert_eq!(layers.len(), 1, "one clip inside, one layer");
    assert_eq!(
        at(&recipe, "/layers/0/clip"),
        &Value::from(22),
        "the layer is the clip INSIDE the nest, not the nest clip"
    );
    // A text clip needs no composition track, nested or not.
    let plan = handle.plan();
    assert_eq!(array(&plan, "/video_tracks").len(), 0);
    assert_eq!(array(&plan, "/audio_tracks").len(), 0);
}
