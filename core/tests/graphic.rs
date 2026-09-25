//! Black-box tests for `add_graphic_clip` and `set_graphic` (road map 10's
//! G2a), through the C FFI as `ReelCore.swift` drives it: each op's answers,
//! every props sentence by its dotted path (with a schema and without), the
//! 64-key limit on the STORED map, the colour normalisation (G-12), and the
//! props ORDER — read off the written text, since `Project ==` cannot see
//! it. What a graphic clip is on disk is `schema_v10.rs`'s.

mod common;

use serde_json::{json, Map, Value};

use common::{assert_contains, at, Handle, Outcome};
use reelcut_core::model_graphic::{GRAPHIC_MAX_SIDE, GRAPHIC_MIN_SIDE};
use reelcut_core::op_table::OP_TABLE;

/// Ticks per second (spec §5.1), written out rather than imported.
const SEC: i64 = 600_000;

/// A module's schema with one entry of every type and each shape of a
/// number's range.
fn schema() -> Value {
    json!({
        "title": {"type": "string", "default": "Jane"},
        "subtitle": {"type": "string", "default": "Director"},
        "accent": {"type": "color", "default": "#ff5a36"},
        "size": {"type": "number", "default": 64, "min": 12, "max": 200, "step": 1},
        "low": {"type": "number", "default": 1, "min": 0},
        "high": {"type": "number", "default": 1, "max": 10},
        "boxed": {"type": "boolean", "default": true},
        "align": {"type": "enum", "default": "left", "options": ["left", "center", "right"]},
        "logo": {"type": "asset", "default": null}
    })
}

/// Track 2 holding graphic clip 11 (0–5 s, props in the order title,
/// accent, subtitle) and track 3 holding text clip 12.
fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 10,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "tracks": [{"id": 2, "name": "G"}, {"id": 3, "name": "T"}],
        "clips": [
            {"id": 11, "track": 2, "start": 0, "duration": 5 * SEC,
             "source": {"kind": "graphic"}, "video": {},
             "graphic": {"name": "lower-third", "width": 1920, "height": 1080,
                         "props": {"title": "Kevin", "accent": "#2d7ff9",
                                   "subtitle": "Host"}}},
            {"id": 12, "track": 3, "start": 0, "duration": 5 * SEC,
             "source": {"kind": "text"}, "video": {}, "text": {"content": "hi"}}
        ],
        "next_id": 20
    }))
}

fn add(extra: Value) -> Value {
    let mut op = json!({"op": "add_graphic_clip", "track": 2, "at": 10 * SEC,
                        "name": "lower-third"});
    for (key, value) in extra.as_object().expect("an object") {
        op[key.as_str()] = value.clone();
    }
    op
}

fn set(patch: Value) -> Value {
    json!({"op": "set_graphic", "clips": [11], "patch": patch, "schema": schema()})
}

fn set_bare(patch: Value) -> Value {
    json!({"op": "set_graphic", "clips": [11], "patch": patch})
}

/// The stored props' keys, in the order the WRITTEN TEXT holds them.
fn prop_keys(handle: &Handle, clip: usize) -> Vec<String> {
    let value: Value = serde_json::from_str(&handle.to_json()).expect("the written text");
    at(&value, &format!("/clips/{clip}/graphic/props"))
        .as_object()
        .expect("props is an object")
        .keys()
        .cloned()
        .collect()
}

fn many(count: usize, from: usize) -> Value {
    let mut props = Map::new();
    for i in from..from + count {
        props.insert(format!("k{i}"), json!(i));
    }
    Value::Object(props)
}

// ---- add_graphic_clip ----------------------------------------------------

#[test]
fn add_places_the_described_clip_with_its_props_in_caller_order() {
    let after = project().apply(&add(json!({
        "props": {"title": "Ada", "accent": "#FF5A36", "size": 72, "boxed": null},
        "schema": schema()
    })));
    let value = after.value();
    let clip = at(&value, "/clips/2");
    assert_eq!(clip["id"], json!(20));
    assert_eq!(clip["source"], json!({"kind": "graphic"}));
    assert_eq!(clip["start"], json!(10 * SEC));
    assert_eq!(clip["duration"], json!(5 * SEC), "the default five seconds");
    assert_eq!(clip["audio"], Value::Null, "a graphic has no sound");
    assert_eq!(clip["video"]["scale"], json!(1.0));
    assert_eq!(
        clip["graphic"],
        json!({"name": "lower-third", "width": 1920, "height": 1080, "in": 0,
               "length": null, "props": {"title": "Ada", "accent": "#ff5a36", "size": 72}})
    );
    assert_eq!(prop_keys(&after, 2), ["title", "accent", "size"]);
}

#[test]
fn add_takes_an_explicit_size_and_fits_an_oversized_one() {
    let after = project().apply(&add(
        json!({"width": 3840, "height": 2160, "duration": SEC}),
    ));
    let value = after.value();
    assert_eq!(at(&value, "/clips/2/graphic/width"), &json!(3840));
    assert_eq!(at(&value, "/clips/2/graphic/height"), &json!(2160));
    assert_eq!(at(&value, "/clips/2/video/scale"), &json!(0.5));
    assert_eq!(at(&value, "/clips/2/duration"), &json!(SEC));
}

#[test]
fn add_is_refused_by_the_overlap_rule_in_its_own_sentence() {
    project().refuses_with(
        &add(json!({"at": 0})),
        "clips 11 and 20 would overlap by 3000000 ticks, more than half of the shorter \
         clip (1500000 ticks)",
    );
}

#[test]
fn add_errs_on_a_bad_name_a_bad_side_a_bad_schema_and_too_many_props() {
    let project = project();
    assert_eq!(
        project.errors(&add(json!({"name": "Lower Third"}))),
        "graphic name \"Lower Third\" is not a module name (lowercase letters, digits and -, \
         starting with a letter or a digit, at most 63 characters)"
    );
    assert_eq!(
        project.errors(&add(json!({"name": "-x"}))),
        "graphic name \"-x\" is not a module name (lowercase letters, digits and -, \
         starting with a letter or a digit, at most 63 characters)"
    );
    assert_eq!(
        project.errors(&add(json!({"width": 0}))),
        "width must be between 1 and 8192, not 0"
    );
    assert_eq!(
        project.errors(&add(json!({"height": 8193}))),
        "height must be between 1 and 8192, not 8193"
    );
    assert_eq!(
        project.errors(&add(
            json!({"schema": {"title": {"type": "text", "default": "x"}}})
        )),
        "schema.title.type \"text\" is not one of string, number, boolean, color, enum, asset"
    );
    assert_eq!(
        project.errors(&add(json!({"schema": {"title": {"type": "string"}}}))),
        "schema.title has no default"
    );
    assert_eq!(
        project.errors(&add(json!({"props": many(65, 0)}))),
        "props has 65 keys; the most is 64"
    );
    // A null is dropped before the count, so 64 values and a null fit.
    let mut sixty_four = many(64, 0);
    sixty_four["gone"] = Value::Null;
    project.apply(&add(json!({"props": sixty_four})));
    assert_eq!(
        project.errors(&add(json!({"props": [1]}))),
        "props must be a json object, not [1]"
    );
    assert_contains(&project.errors(&add(json!({"track": 99}))), "99");
}

#[test]
fn a_canvas_over_the_side_bound_needs_an_explicit_size() {
    let wide = Handle::new(16384, 1080, 30, 1);
    let op = json!({"op": "add_graphic_clip", "track": 1, "at": 0, "name": "g"});
    assert_eq!(
        wide.errors(&op),
        "the canvas is 16384×1080 and a graphic's side is at most 8192; pass width and height"
    );
    let mut sized = op.clone();
    sized["width"] = json!(1920); // the defaulted height, 1080, fits
    wide.apply(&sized);
}

#[test]
fn the_published_bound_is_the_constant_and_the_sentence() {
    let row = OP_TABLE
        .iter()
        .find(|row| row.name == "add_graphic_clip")
        .expect("the row");
    for side in ["width", "height"] {
        let bound = row
            .arguments
            .iter()
            .find(|a| a.name == side)
            .and_then(|a| a.bound)
            .expect("a bound");
        assert_eq!((bound.min, bound.max), (GRAPHIC_MIN_SIDE, GRAPHIC_MAX_SIDE));
        let message = project().errors(&add(json!({side: bound.max + 1})));
        assert_eq!(
            message,
            format!(
                "{side} must be between {} and {}, not {}",
                bound.min,
                bound.max,
                bound.max + 1
            )
        );
    }
}

// ---- set_graphic ---------------------------------------------------------

#[test]
fn set_patches_each_key() {
    let after = project().apply(&set(json!({
        "name": "title-card", "width": 1280, "height": 720, "length": 605_000,
        "props": {"size": 100, "align": "center", "logo": "logo.png"}
    })));
    let value = after.value();
    assert_eq!(
        at(&value, "/clips/0/graphic"),
        &json!({"name": "title-card", "width": 1280, "height": 720, "in": 0,
                "length": 600_000,
                "props": {"title": "Kevin", "accent": "#2d7ff9", "subtitle": "Host",
                          "size": 100, "align": "center", "logo": "logo.png"}})
    );
    let back = after.apply(&set(json!({"length": null})));
    assert_eq!(at(&back.value(), "/clips/0/graphic/length"), &Value::Null);
}

#[test]
fn set_is_an_identity_when_nothing_changes() {
    let project = project();
    assert!(matches!(
        project.try_apply(&set(json!({"props": {"title": "Kevin"}}))),
        Ok(Outcome::Identity)
    ));
    // A colour re-sent in another spelling normalises to what is stored.
    assert!(matches!(
        project.try_apply(&set(json!({"props": {"accent": "#2D7FF9FF"}}))),
        Ok(Outcome::Identity)
    ));
    assert!(matches!(
        project.try_apply(&json!({"op": "set_graphic", "clips": [], "patch": {}})),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn set_errs_naming_the_clip_the_key_and_the_value() {
    let project = project();
    let name_rule = "is not a module name (lowercase letters, digits and -, starting with a \
                     letter or a digit, at most 63 characters)";
    let colour = "must be a CSS colour (#rgb, #rgba, #rrggbb, #rrggbbaa, rgb(), rgba())";
    // Laid out by hand, one case a line, as `op_table.rs`'s rows are.
    #[rustfmt::skip]
    let cases = [
        (json!({"op": "set_graphic", "clips": [12], "patch": {}}), "clip 12 is not a graphic clip".to_string()),
        (json!({"op": "set_graphic", "clips": [11], "patch": [1]}),
         "graphic patch must be a json object, not [1]".to_string()),
        (set(json!({"in": 0})),
         "\"in\" cannot be patched: trim_start and split own a graphic's in point".to_string()),
        (set(json!({"bogus": 1})), "unknown key \"bogus\" in a graphic patch".to_string()),
        (set(json!({"props": {"nope": 1}})), "unknown key \"props.nope\" in a graphic patch".to_string()),
        (set(json!({"props": {"title": 5}})), "props.title must be a string, not 5".to_string()),
        (set(json!({"props": {"size": 500}})), "props.size must be between 12 and 200, not 500".to_string()),
        (set(json!({"props": {"low": -1}})), "props.low must be at least 0, not -1".to_string()),
        (set(json!({"props": {"high": 11}})), "props.high must be at most 10, not 11".to_string()),
        (set(json!({"props": {"boxed": "yes"}})), "props.boxed must be a boolean, not \"yes\"".to_string()),
        (set(json!({"props": {"align": "middle"}})),
         "props.align must be one of left, center, right, not \"middle\"".to_string()),
        (set(json!({"props": {"accent": "blue"}})), format!("props.accent {colour}, not \"blue\"")),
        (set(json!({"props": {"title": "x".repeat(4097)}})),
         "props.title must be at most 4096 characters, not 4097".to_string()),
        (set(json!({"name": "Bad Name"})), format!("graphic name \"Bad Name\" {name_rule}")),
        (set(json!({"width": 0})), "width must be between 1 and 8192, not 0".to_string()),
        (set(json!({"height": 5_000_000_000u64})),
         "height must be between 1 and 8192, not 5000000000".to_string()),
        (set(json!({"length": 5_000})),
         "length must be at least one frame (20000 ticks), not 5000".to_string()),
        (json!({"op": "set_graphic", "clips": [11], "patch": {},
                "schema": {"Bad Key": {"type": "string", "default": ""}}}),
         "schema key \"Bad Key\" is not a name (letters, digits and _, starting with a letter or \
          _, at most 32 characters)".to_string()),
    ];
    for (op, sentence) in cases {
        assert_eq!(project.errors(&op), sentence, "{op}");
    }
}

#[test]
fn the_key_limit_is_on_the_merged_map() {
    let full = project().apply(&json!({"op": "add_graphic_clip", "track": 3,
                                       "at": 10 * SEC, "name": "g", "props": many(64, 0)}));
    let id = at(&full.value(), "/clips/2/id").clone();
    assert_eq!(
        full.errors(&json!({"op": "set_graphic", "clips": [id],
                            "patch": {"props": {"k64": 1}}})),
        "props has 65 keys; the most is 64"
    );
    let swapped = full.apply(&json!({"op": "set_graphic", "clips": [id],
                                     "patch": {"props": {"k0": null, "k64": 1}}}));
    let keys = prop_keys(&swapped, 2);
    assert_eq!(keys.len(), 64);
    assert_eq!(keys.first().map(String::as_str), Some("k1"));
    assert_eq!(keys.last().map(String::as_str), Some("k64"));
}

#[test]
fn without_a_schema_only_the_shape_is_checked() {
    let project = project();
    #[rustfmt::skip]
    let cases = [
        (json!({"meta": {"a": 1}}),
         "props.meta must be a string, a number or a boolean, not {\"a\":1}"),
        (json!({"list": [1]}), "props.list must be a string, a number or a boolean, not [1]"),
        (json!({"title": "x".repeat(4097)}), "props.title must be at most 4096 characters, not 4097"),
        (json!({"1st": 1}),
         "props key \"1st\" is not a name (letters, digits and _, starting with a letter or _, \
          at most 32 characters)"),
    ];
    for (props, sentence) in cases {
        assert_eq!(project.errors(&set_bare(json!({"props": props}))), sentence);
    }
    // A key no schema names, and a colour left exactly as it was sent.
    let after = project.apply(&set_bare(
        json!({"props": {"extra": true, "accent": "#FFF"}}),
    ));
    assert_eq!(
        at(&after.value(), "/clips/0/graphic/props"),
        &json!({"title": "Kevin", "accent": "#FFF", "subtitle": "Host", "extra": true})
    );
}

#[test]
fn a_colour_is_stored_as_lowercase_hex() {
    let project = project();
    for (sent, stored) in [
        ("#FF5A36", "#ff5a36"),
        ("#f00", "#ff0000"),
        ("#f008", "#ff000088"),
        ("rgba(255, 0, 0, 0.5)", "#ff000080"),
        ("rgb(255 0 0 / 50%)", "#ff000080"),
        ("rgb(100%, 0%, 0%)", "#ff0000"),
        ("#ff5a36ff", "#ff5a36"),
        ("#FF5A3680", "#ff5a3680"),
    ] {
        let after = project.apply(&set(json!({"props": {"accent": sent}})));
        assert_eq!(
            at(&after.value(), "/clips/0/graphic/props/accent"),
            &json!(stored),
            "{sent}"
        );
    }
    for refused in [
        "red",
        "hsl(0, 100%, 50%)",
        "#ff5a3",
        "rgb(256, 0, 0)",
        "rgb(1, 2)",
    ] {
        assert_contains(
            &project.errors(&set(json!({"props": {"accent": refused}}))),
            "must be a CSS colour",
        );
    }
}

#[test]
fn a_null_removes_its_key_and_the_rest_keep_their_order() {
    // `old` is a key the schema lacks, stored by an op without one.
    let stale = project().apply(&set_bare(json!({"props": {"old": 1, "tail": 2}})));
    let after = stale.apply(&set(json!({"props": {"title": null, "old": null}})));
    assert_eq!(prop_keys(&after, 0), ["accent", "subtitle", "tail"]);
}

#[test]
fn a_re_sent_key_keeps_its_slot_and_a_new_one_lands_last() {
    let after = project().apply(&set(json!({"props": {"size": 20, "title": "Ada"}})));
    assert_eq!(
        prop_keys(&after, 0),
        ["title", "accent", "subtitle", "size"]
    );
    assert_eq!(
        at(&after.value(), "/clips/0/graphic/props/title"),
        &json!("Ada")
    );
}
