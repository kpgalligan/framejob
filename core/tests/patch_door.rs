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
//! 3. **Nothing happened** — the invalid-input tier: NULL with a message,
//!    so there is no new project and no undo step.
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

/// The `set_<group>` op carrying `patch`, aimed at the clip that has that
/// group.
fn patch_op(group: &str, patch: Value) -> Value {
    let clip = match group {
        "video" | "audio" | "clip" => 11,
        "text" => 12,
        "shape" => 13,
        other => panic!("no clip in the fixture carries a {other} group"),
    };
    json!({ "op": format!("set_{group}"), "clips": [clip], "patch": patch })
}

/// Applies `op`, asserting it is REFUSED as invalid input, that the message
/// follows the core's error rule (it does not open with a capital) and that
/// it contains every `needle`. Returns the message for an exact comparison.
///
/// "The project is unchanged" is the invalid-input answer itself, and
/// `Handle::errors` is what asserts it: NULL with `err_out` set, so there is
/// no new project and no undo step. A handle is immutable, so comparing the
/// one passed in before and after would prove nothing. What CAN go wrong —
/// a wrong-typed shadow read as a clear, a misspelt kind read as the first
/// case — comes back as a new handle, and `errors` panics on that.
fn refused(project: &Handle, op: Value, needles: &[&str]) -> String {
    let msg = project.errors(&op);
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
fn an_unknown_key_at_depth_is_named_by_its_path_at_every_group() {
    // One row per group at the deepest place that group has, led by the
    // acceptance example: a misspelt key on the SECOND filter, where a path
    // with no index would leave the caller comparing every entry. `audio`
    // has no list, so its path is a dotted one; `set_clip`'s is flat.
    let project = project();
    for (group, body, expected) in [
        (
            "video",
            json!({ "filters": [{ "kind": "blur", "amount": 0.5 }, { "kindd": "sepia", "amount": 1.0 }] }),
            "unknown key \"filters[1].kindd\" in a video patch",
        ),
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
        assert_eq!(refused(&project, patch_op(group, body), &[]), expected);
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
fn a_misspelt_variant_is_named_by_its_path_at_every_group_that_has_one() {
    // The failure the Swift door used to have: `glw` decoded as the
    // vocabulary's FIRST case. Each row: the path, the value as sent, and
    // one spelling the vocabulary does allow. `audio` holds no enum and
    // `set_clip`'s patch holds two strings, so neither has a row.
    let project = project();
    for (group, body, path, value, allowed) in [
        (
            "video",
            json!({ "filters": [{ "kind": "blur", "amount": 0.5 }, { "kind": "glw", "amount": 1.0 }] }),
            "filters[1].kind",
            "`glw`",
            "`sharpen`",
        ),
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
            patch_op(group, body),
            &[&format!("unknown variant {value}, expected "), allowed],
        );
        let prefix = format!("bad value at \"{path}\" in a {group} patch: ");
        assert!(msg.starts_with(&prefix), "expected {prefix:?}, got {msg:?}");
    }
}

// ---- a wrong type, never read as a clear ----------------------------------

#[test]
fn a_wrong_type_where_a_nested_object_belongs_is_refused_not_cleared() {
    // Every clip in the fixture HOLDS the sub-object named here, so a
    // number read as "no shadow" would be a real edit and `refused` would
    // see a new project. The refusal names the kind the schema has there.
    let project = project();
    for (group, body, expected) in [
        (
            "video",
            json!({ "shadow": 5 }),
            "bad value at \"shadow\" in a video patch: expected an object, not 5",
        ),
        (
            "audio",
            json!({ "duck": 5 }),
            "bad value at \"duck\" in an audio patch: expected an object, not 5",
        ),
        (
            "text",
            json!({ "outline": "thick" }),
            "bad value at \"outline\" in a text patch: expected an object, not \"thick\"",
        ),
        (
            "shape",
            json!({ "stroke": true }),
            "bad value at \"stroke\" in a shape patch: expected an object, not true",
        ),
    ] {
        assert_eq!(refused(&project, patch_op(group, body), &[]), expected);
    }
    // A clip patch's two keys are strings, and the op's own reader names
    // the key and the value the same way.
    assert_eq!(
        refused(&project, patch_op("clip", json!({ "name": 5 })), &[]),
        "\"name\" in a clip patch must be a string or null, not 5"
    );
}

#[test]
fn a_wrong_type_inside_a_nested_object_or_a_list_names_the_index() {
    // Inside the object, and inside a list: a filter entry, a colour's
    // component, a gradient stop. The colour row is how `text` gets an
    // index of its own — a colour is a list of four numbers.
    let project = project();
    for (group, body, expected) in [
        (
            "video",
            json!({ "filters": [{ "kind": "blur", "amount": "lots" }] }),
            "bad value at \"filters[0].amount\" in a video patch: expected a number, not \"lots\"",
        ),
        (
            "audio",
            json!({ "duck": { "attack": 0.5 } }),
            "bad value at \"duck.attack\" in an audio patch: expected a whole number, not 0.5",
        ),
        (
            "text",
            json!({ "outline": { "color": [0.0, "black", 0.0, 1.0] } }),
            "bad value at \"outline.color[1]\" in a text patch: expected a number, not \"black\"",
        ),
        (
            "shape",
            json!({ "gradient": { "stops": [
                { "at": 0.0, "color": [1.0, 0.0, 0.0, 1.0] },
                { "at": "end", "color": [0.0, 0.0, 1.0, 1.0] }
            ] } }),
            "bad value at \"gradient.stops[1].at\" in a shape patch: expected a number, not \"end\"",
        ),
    ] {
        assert_eq!(refused(&project, patch_op(group, body), &[]), expected);
    }
    // A `null` passes the walk, because in a patch it clears; a REQUIRED
    // field refuses it at the read, still by path and value.
    refused(
        &project,
        patch_op("video", json!({ "crop": null })),
        &["bad value at \"crop\" in a video patch: invalid type: null"],
    );
}

#[test]
fn a_list_or_an_object_where_the_schema_has_another_kind_is_refused_not_read_positionally() {
    // serde reads a struct from a JSON ARRAY of its fields in declaration
    // order, and a unit variant from a one-key object. Neither is how the
    // schema is written, so `{"duck": [0.9, 300000, 600000]}` would store a
    // duck nobody spelt and `{"blend": {"multiply": null}}` a blend by a
    // spelling `get_project` never gives back. Each is refused, naming the
    // kind the schema has there and the value sent.
    let project = project();
    for (group, body, expected) in [
        (
            "audio",
            json!({ "duck": [0.9, 300000, 600000] }),
            "bad value at \"duck\" in an audio patch: expected an object, not [0.9,300000,600000]",
        ),
        (
            "video",
            json!({ "filters": [["blur", 0.5]] }),
            "bad value at \"filters[0]\" in a video patch: expected an object, not [\"blur\",0.5]",
        ),
        (
            "video",
            json!({ "crop": [1.0, 2.0, 3.0, 4.0] }),
            "bad value at \"crop\" in a video patch: expected an object, not [1.0,2.0,3.0,4.0]",
        ),
        (
            "video",
            json!({ "blend": { "multiply": null } }),
            "bad value at \"blend\" in a video patch: expected a string, not {\"multiply\":null}",
        ),
        (
            "text",
            json!({ "animation": ["word_fade", 0, 0] }),
            "bad value at \"animation\" in a text patch: expected an object, not [\"word_fade\",0,0]",
        ),
        (
            "shape",
            json!({ "stroke": [4.0, [1.0, 0.0, 0.0, 1.0]] }),
            "bad value at \"stroke\" in a shape patch: expected an object, not [4.0,[1.0,0.0,0.0,1.0]]",
        ),
    ] {
        assert_eq!(refused(&project, patch_op(group, body), &[]), expected);
    }
}
