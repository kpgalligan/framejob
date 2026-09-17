//! The patch door: what a caller is told when a property patch is wrong.
//!
//! A patch is a caller-authored object an op merges into a clip's property
//! group (`CONTEXT.md`), and the core is the one validator of it. Every
//! refusal here answers the same three things, whichever group the patch
//! was for and however deep the mistake sits:
//!
//! 1. **Where** — the dotted path to the mistake, array indices included,
//!    so `filters[1].kindd` says which entry to fix.
//! 2. **What** — the offending value as the caller sent it, and for a
//!    misspelt variant what the vocabulary allows.
//! 3. **Nothing happened** — the invalid-input tier (NULL with a message,
//!    so no undo step) and a project byte-identical to the one before.
//!
//! The groups do not all have the same shapes to get wrong. `video` and
//! `shape` hold lists of objects (`filters`, `obscure`, `gradient.stops`);
//! `text` and `shape` hold colours, lists of numbers whose indices a type
//! error names; `audio` holds no list and no enum at all, and `set_clip`'s
//! patch is two flat strings. Each group is tested at the deepest place its
//! own vocabulary has.

mod common;

use serde_json::{json, Value};

use common::{assert_contains, Handle};

/// Ticks per second (spec §5.1), written out so a change to the timescale
/// fails here rather than moving with the test.
const SEC: i64 = 600_000;

// ---- fixtures ------------------------------------------------------------

/// One track holding a media clip (11), a text clip (12) and a shape clip
/// (13), each carrying the OPTIONAL sub-objects a wrong-typed value would
/// otherwise be read as clearing: a shadow and a duck on the media clip, an
/// outline on the text, a stroke on the shape. The media clip also holds a
/// filter, so a list refusal has a stored list it must leave alone.
fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 8,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/1.mov", "kind": "video",
            "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            {
                "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
                "source": { "kind": "media", "media": 1, "in": 0 },
                "video": {
                    "shadow": { "x": 0.0, "y": 8.0, "blur": 12.0, "color": [0.0, 0.0, 0.0, 0.5] },
                    "filters": [{ "kind": "sepia", "amount": 0.8 }]
                },
                "audio": { "duck": { "level": 0.3, "attack": 300000, "release": 600000 } }
            },
            {
                "id": 12, "track": 2, "start": 10 * SEC, "duration": 5 * SEC,
                "source": { "kind": "text" },
                "video": {},
                "text": { "content": "Hello", "outline": { "width": 3.0, "color": [0.0, 0.0, 0.0, 1.0] } }
            },
            {
                "id": 13, "track": 2, "start": 15 * SEC, "duration": 5 * SEC,
                "source": { "kind": "shape" },
                "video": {},
                "shape": { "stroke": { "width": 4.0, "color": [1.0, 0.0, 0.0, 1.0] } }
            }
        ],
        "next_id": 14
    }))
}

/// The op for `group`'s patch, aimed at the clip that has that group.
fn patch(group: &str, patch: Value) -> Value {
    let clip = match group {
        "video" | "audio" | "clip" => 11,
        "text" => 12,
        "shape" => 13,
        other => panic!("no clip in the fixture carries a {other} group"),
    };
    json!({ "op": format!("set_{group}"), "clips": [clip], "patch": patch })
}

/// Applies `op`, asserting it is REFUSED as invalid input — an error with a
/// message, which the app registers no undo step for — that the project is
/// byte-identical afterwards, and that the message follows the core's error
/// rule (it does not open with a capital) and contains every `needle`: the
/// path, and the value. Returns the message for an exact comparison.
fn refused(project: &Handle, op: Value, needles: &[&str]) -> String {
    let before = project.to_json();
    let msg = project.errors(&op);
    assert_eq!(
        project.to_json(),
        before,
        "a refusal left the project changed: {op}"
    );
    assert!(
        !msg.starts_with(char::is_uppercase),
        "the core's messages are lowercase, got {msg:?}"
    );
    for needle in needles {
        assert_contains(&msg, needle);
    }
    msg
}

// ---- an unknown key, at depth, with indices --------------------------------

#[test]
fn an_unknown_key_inside_a_list_entry_names_its_index() {
    // The acceptance example: a misspelt kind on the SECOND filter. Without
    // the index the caller learns only that some filter is wrong.
    let msg = refused(
        &project(),
        patch(
            "video",
            json!({ "filters": [{ "kind": "blur", "amount": 0.5 }, { "kindd": "sepia", "amount": 1.0 }] }),
        ),
        &[],
    );
    assert_eq!(msg, "unknown key \"filters[1].kindd\" in a video patch");
}

#[test]
fn an_unknown_key_at_depth_is_named_by_its_path_at_every_group() {
    // One row per group at the deepest place that group has. `audio` has
    // no list, so its path is a dotted one; `set_clip`'s patch is flat.
    let project = project();
    for (group, body, expected) in [
        (
            "video",
            json!({ "obscure": [{ "kind": "blur" }, { "shape": "rect", "kynd": "blur" }] }),
            "unknown key \"obscure[1].kynd\" in a video patch",
        ),
        (
            "video",
            json!({ "motion": { "during": { "ammount": 0.5 } } }),
            "unknown key \"motion.during.ammount\" in a video patch",
        ),
        (
            "audio",
            json!({ "compressor": { "ratoi": 4.0 } }),
            "unknown key \"compressor.ratoi\" in an audio patch",
        ),
        (
            "text",
            json!({ "animation": { "kind": "typewriter", "kynd": "line_rise" } }),
            "unknown key \"animation.kynd\" in a text patch",
        ),
        (
            "shape",
            json!({ "gradient": { "stops": [{ "at": 0.0 }, { "at": 1.0, "colour": [1.0, 0.0, 0.0, 1.0] }] } }),
            "unknown key \"gradient.stops[1].colour\" in a shape patch",
        ),
        (
            "clip",
            json!({ "nmae": "Intro" }),
            "unknown key \"nmae\" in a clip patch",
        ),
    ] {
        assert_eq!(refused(&project, patch(group, body), &[]), expected);
    }
}

#[test]
fn a_new_clips_patch_is_refused_as_the_set_op_would_refuse_it() {
    // `add_text_clip`'s `text` and `add_shape_clip`'s `shape` are patches
    // over the creation preset, "exactly as `set_text` would" (spec §6), so
    // they answer in the same words — and add no clip.
    let project = project();
    let msg = refused(
        &project,
        json!({ "op": "add_text_clip", "track": 2, "at": 20 * SEC,
                "text": { "animation": { "kind": "fade" } } }),
        &["unknown variant `fade`", "expected one of `typewriter`"],
    );
    assert!(
        msg.starts_with("bad value at \"animation.kind\" in a text patch: "),
        "got {msg:?}"
    );
    assert_eq!(
        refused(
            &project,
            json!({ "op": "add_shape_clip", "track": 2, "at": 20 * SEC, "shape": { "gradient": {
                "stops": [{ "at": 0.0, "color": [1.0, 0.0, 0.0, 1.0] }, { "at": 1.0, "colr": [0.0, 0.0, 1.0, 1.0] }]
            } } }),
            &[],
        ),
        "unknown key \"gradient.stops[1].colr\" in a shape patch"
    );
}

// ---- a misspelt variant, with its path and the vocabulary ------------------

#[test]
fn a_misspelt_variant_inside_a_list_entry_names_its_path_value_and_vocabulary() {
    // The failure the Swift door used to have: `glw` decoded as the
    // vocabulary's FIRST case. The core names the entry, the value sent and
    // what it could have been.
    let msg = refused(
        &project(),
        patch(
            "video",
            json!({ "filters": [{ "kind": "blur", "amount": 0.5 }, { "kind": "glw", "amount": 1.0 }] }),
        ),
        &["unknown variant `glw`", "expected one of `blur`, `sharpen`"],
    );
    assert!(
        msg.starts_with("bad value at \"filters[1].kind\" in a video patch: "),
        "the path, in the key walk's form, got {msg:?}"
    );
}

#[test]
fn a_misspelt_variant_is_named_by_its_path_at_every_group_that_has_one() {
    // `audio` holds no enum and `set_clip`'s patch holds two strings, so
    // neither has a variant to misspell. Each row: the path, the value as
    // sent, and one spelling the vocabulary does allow.
    let project = project();
    for (group, body, path, value, allowed) in [
        (
            "video",
            json!({ "blend": "muliply" }),
            "blend",
            "`muliply`",
            "`multiply`",
        ),
        (
            "video",
            json!({ "motion": { "in": { "kind": "slide_lft", "duration": 600000 } } }),
            "motion.in.kind",
            "`slide_lft`",
            "`slide_left`",
        ),
        (
            "video",
            json!({ "obscure": [{ "kind": "blurr" }] }),
            "obscure[0].kind",
            "`blurr`",
            "`pixelate`",
        ),
        (
            "text",
            json!({ "align": "centre" }),
            "align",
            "`centre`",
            "`center`",
        ),
        (
            "text",
            json!({ "animation": { "kind": "fade" } }),
            "animation.kind",
            "`fade`",
            "`word_fade`",
        ),
        (
            "shape",
            json!({ "kind": "circle" }),
            "kind",
            "`circle`",
            "`ellipse`",
        ),
        (
            "shape",
            json!({ "gradient": { "kind": "conic" } }),
            "gradient.kind",
            "`conic`",
            "`radial`",
        ),
    ] {
        let msg = refused(
            &project,
            patch(group, body),
            &[&format!("unknown variant {value}, expected "), allowed],
        );
        let prefix = format!("bad value at \"{path}\" in a {group} patch: ");
        assert!(msg.starts_with(&prefix), "expected {prefix:?}, got {msg:?}");
    }
}

// ---- a wrong type, never read as a clear ----------------------------------

#[test]
fn a_wrong_type_where_a_nested_object_belongs_is_refused_not_cleared() {
    // Every clip in the fixture HOLDS the sub-object named here, and
    // `refused` asserts the project is byte-identical afterwards: a number
    // where a shadow belongs is a mistake, never "no shadow".
    let project = project();
    for (group, body, path, value) in [
        ("video", json!({ "shadow": 5 }), "shadow", "integer `5`"),
        ("audio", json!({ "duck": 5 }), "duck", "integer `5`"),
        (
            "text",
            json!({ "outline": "thick" }),
            "outline",
            "string \"thick\"",
        ),
        (
            "shape",
            json!({ "stroke": true }),
            "stroke",
            "boolean `true`",
        ),
    ] {
        let msg = refused(&project, patch(group, body), &[value]);
        let article = if group == "audio" { "an" } else { "a" };
        let prefix = format!("bad value at \"{path}\" in {article} {group} patch: invalid type: ");
        assert!(msg.starts_with(&prefix), "expected {prefix:?}, got {msg:?}");
    }
    // A clip patch's two keys are strings, and the op's own reader names
    // the key and the value the same way.
    assert_eq!(
        refused(&project, patch("clip", json!({ "name": 5 })), &[]),
        "\"name\" in a clip patch must be a string or null, not 5"
    );
}

#[test]
fn a_wrong_type_inside_a_nested_object_or_a_list_names_the_index() {
    // Inside the object, and inside a list: a filter entry, a colour's
    // component, a gradient stop. The colour row is how `text` gets an
    // index of its own — a colour is a list of four numbers.
    let project = project();
    for (group, body, path, value) in [
        (
            "video",
            json!({ "filters": [{ "kind": "blur", "amount": "lots" }] }),
            "filters[0].amount",
            "string \"lots\"",
        ),
        ("video", json!({ "crop": null }), "crop", "null"),
        (
            "audio",
            json!({ "duck": { "attack": 0.5 } }),
            "duck.attack",
            "floating point `0.5`",
        ),
        (
            "text",
            json!({ "outline": { "color": [0.0, "black", 0.0, 1.0] } }),
            "outline.color[1]",
            "string \"black\"",
        ),
        (
            "shape",
            json!({ "gradient": { "stops": [
                { "at": 0.0, "color": [1.0, 0.0, 0.0, 1.0] },
                { "at": "end", "color": [0.0, 0.0, 1.0, 1.0] }
            ] } }),
            "gradient.stops[1].at",
            "string \"end\"",
        ),
    ] {
        let msg = refused(&project, patch(group, body), &[value]);
        assert_contains(&msg, &format!("bad value at \"{path}\" in "));
    }
}
