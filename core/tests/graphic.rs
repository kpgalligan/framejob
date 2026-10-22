//! Black-box tests for `add_graphic_clip` and `set_graphic` (road map 10's
//! G2a), through the C FFI as `ReelCore.swift` drives it: each op's answers,
//! every props sentence by its dotted path (with a schema and without), the
//! 64-key limit on the STORED map, the colour normalisation (G-12), and the
//! props ORDER — read off the written text, since `Project ==` cannot see
//! it. What a graphic clip is on disk is `schema_v10.rs`'s. Road map 10's
//! G2b adds the graphic's own timeline under the trims, `roll` and `split`
//! (G-9) and the layer source the recipe publishes — its frame, its `ctx`
//! and its hash. A graphic's props as action targets (G-34) are
//! `graphic_actions.rs`'s and `graphic_action_door.rs`'s.

mod common;

use serde_json::{json, Map, Value};

use common::{array, assert_contains, at, int, num, Handle, Outcome};
use framejob_core::model_graphic::{GRAPHIC_MAX_SIDE, GRAPHIC_MIN_SIDE};
use framejob_core::op_table::OP_TABLE;

/// G-12's shared colour fixture, the engine's test file.
const COLOURS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../graphic/tests/colours.json");

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
        project.errors(&add(
            json!({"schema": {"title": {"type": "string", "default": "x", "animate": "no"}}})
        )),
        "schema.title.animate \"no\" is not a boolean"
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
    let colour = "must be a CSS colour (#rgb, #rgba, #rrggbb, #rrggbbaa, rgb(), rgba(), hsl(), \
                  hsla() or a colour name)";
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
        (set(json!({"props": {"accent": "bluish"}})), format!("props.accent {colour}, not \"bluish\"")),
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
    // G-12's one fixture, which `graphic/tests/stdlib.rs` runs through the
    // standard library's `interpolateColors` too.
    let text = std::fs::read_to_string(COLOURS).expect("graphic/tests/colours.json");
    let fixture: Value = serde_json::from_str(&text).expect("the colour fixture is JSON");
    let project = project();
    let accepted = fixture["accepted"].as_array().expect("accepted");
    assert!(!accepted.is_empty());
    for case in accepted {
        let (sent, stored) = (&case[0], &case[1]);
        let after = project.apply(&set(json!({"props": {"accent": sent}})));
        assert_eq!(
            at(&after.value(), "/clips/0/graphic/props/accent"),
            stored,
            "{sent}"
        );
    }
    let refused = fixture["refused"].as_array().expect("refused");
    assert!(!refused.is_empty());
    for sent in refused {
        assert_eq!(
            project.errors(&set(json!({"props": {"accent": sent}}))),
            format!(
                "props.accent must be a CSS colour (#rgb, #rgba, #rrggbb, #rrggbbaa, rgb(), \
                 rgba(), hsl(), hsla() or a colour name), not {sent}"
            ),
        );
    }
}

#[test]
fn a_colour_default_is_checked_against_the_colour_grammar() {
    // G-25 (a): the same fixture as a schema's `color` DEFAULT. Every
    // accepted text is a default `add_graphic_clip` takes; every refused one
    // refuses the schema in the engine's sentence, `graphic/tests/module.rs`'s.
    let text = std::fs::read_to_string(COLOURS).expect("graphic/tests/colours.json");
    let fixture: Value = serde_json::from_str(&text).expect("the colour fixture is JSON");
    let project = project();
    let with = |default: &Value| {
        let mut schema = schema();
        schema["accent"]["default"] = default.clone();
        add(json!({"schema": schema}))
    };
    let accepted = fixture["accepted"].as_array().expect("accepted");
    assert!(!accepted.is_empty());
    for case in accepted {
        let after = project.apply(&with(&case[0]));
        assert_eq!(array(&after.value(), "/clips").len(), 3, "{}", case[0]);
    }
    let refused = fixture["refused"].as_array().expect("refused");
    assert!(!refused.is_empty());
    for sent in refused {
        assert_eq!(
            project.errors(&with(sent)),
            format!("schema.accent.default {sent} is not a color")
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

// ---- G2b: the graphic's own timeline (G-9, G-10) ---------------------------

/// One frame at 30 fps, in ticks.
const FRAME: i64 = 20_000;

/// The layer `clip` draws in `recipe`.
fn layer_of(recipe: &Value, clip: i64) -> Value {
    array(recipe, "/layers")
        .iter()
        .find(|l| int(l, "/clip") == clip)
        .unwrap_or_else(|| panic!("no layer for clip {clip} in {recipe}"))
        .clone()
}

/// The `source` of clip `clip`'s layer at `t`.
fn source_at(handle: &Handle, clip: i64, t: i64) -> Value {
    layer_of(&handle.recipe(t), clip)["source"].clone()
}

/// [`project`] with clip 11's graphic at `in` and `length`.
fn project_with(r#in: i64, length: Value) -> Handle {
    let mut value = project().value();
    value["clips"][0]["graphic"]["in"] = json!(r#in);
    value["clips"][0]["graphic"]["length"] = length;
    Handle::from_value(&value)
}

/// [`project`] with a media clip 30 on track 2 at 0–2 s and clip 11 moved
/// to 2–5 s, so 30 ends EXACTLY where 11 starts: a cut `roll` can move.
fn project_with_cut() -> Handle {
    let mut value = project().value();
    value["media"] = json!([
        {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
         "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
    ]);
    value["clips"][0]["start"] = json!(2 * SEC);
    value["clips"][0]["duration"] = json!(3 * SEC);
    value["clips"].as_array_mut().expect("clips").push(
        json!({"id": 30, "track": 2, "start": 0, "duration": 2 * SEC,
                     "source": {"kind": "media", "media": 1, "in": 0},
                     "video": {}, "audio": {}}),
    );
    value["next_id"] = json!(31);
    Handle::from_value(&value)
}

/// Clip `id` in `handle`'s project.
fn clip(handle: &Handle, id: i64) -> Value {
    array(&handle.value(), "/clips")
        .iter()
        .find(|c| int(c, "/id") == id)
        .unwrap_or_else(|| panic!("no clip {id}"))
        .clone()
}

/// The graphic clips in `handle`, by start.
fn graphic_starts(handle: &Handle) -> Vec<Value> {
    let mut clips: Vec<Value> = array(&handle.value(), "/clips")
        .iter()
        .filter(|c| c["source"]["kind"] == json!("graphic"))
        .cloned()
        .collect();
    clips.sort_by_key(|c| int(c, "/start"));
    clips
}

#[test]
fn split_advances_the_second_halfs_in_and_pins_both_lengths() {
    let once = project().apply(&json!({"op": "split", "clips": [11], "at": 2 * SEC}));
    assert_eq!(at(&clip(&once, 11), "/graphic/in"), &json!(0));
    assert_eq!(at(&clip(&once, 11), "/graphic/length"), &json!(3_000_000));
    assert_eq!(at(&clip(&once, 20), "/graphic/in"), &json!(1_200_000));
    assert_eq!(at(&clip(&once, 20), "/graphic/length"), &json!(3_000_000));

    // The pin's discriminator is the FIRST half: its own `in + duration` is
    // only the head, 60 frames.
    let before = source_at(&once, 11, 2 * SEC - FRAME);
    assert_eq!(before["frame"], json!(59));
    assert_eq!(before["ctx"]["durationInFrames"], json!(150));
    let after = source_at(&once, 20, 2 * SEC + FRAME);
    assert_eq!(after["frame"], json!(61));
    assert_eq!(after["ctx"]["durationInFrames"], json!(150));
    // And the second half's, once its end moves: 120 without the pin.
    let trimmed = once.apply(&json!({"op": "trim_end", "clip": 20, "to": 4 * SEC}));
    let after = source_at(&trimmed, 20, 2 * SEC + FRAME);
    assert_eq!(after["ctx"]["durationInFrames"], json!(150));

    let twice = once.apply(&json!({"op": "split", "clips": [20], "at": 4 * SEC}));
    let pieces = graphic_starts(&twice);
    assert_eq!(pieces.len(), 3);
    assert_eq!(pieces[2]["graphic"]["in"], json!(2_400_000));
    assert_eq!(pieces[2]["graphic"]["length"], json!(3_000_000));

    let lifted = project().apply(&json!({"op": "lift_range", "from": 2 * SEC, "to": 3 * SEC}));
    let pieces = graphic_starts(&lifted);
    assert_eq!(pieces.len(), 2);
    assert_eq!(pieces[0]["graphic"]["in"], json!(0));
    assert_eq!(pieces[1]["start"], json!(3 * SEC));
    assert_eq!(pieces[1]["graphic"]["in"], json!(1_800_000));
    for piece in &pieces {
        assert_eq!(piece["graphic"]["length"], json!(3_000_000));
    }
}

#[test]
fn trim_start_advances_in_with_no_head_bound_and_trim_end_leaves_length_alone() {
    let trimmed = project().apply(&json!({"op": "trim_start", "clip": 11, "to": SEC}));
    assert_eq!(at(&clip(&trimmed, 11), "/graphic/in"), &json!(600_000));
    assert_eq!(at(&clip(&trimmed, 11), "/graphic/length"), &Value::Null);
    let source = source_at(&trimmed, 11, SEC);
    assert_eq!(source["frame"], json!(30));
    assert_eq!(source["ctx"]["durationInFrames"], json!(150));

    let back = trimmed.apply(&json!({"op": "trim_start", "clip": 11, "to": 0}));
    assert_eq!(at(&clip(&back, 11), "/graphic/in"), &json!(0));
    assert_eq!(
        source_at(&back, 11, 0)["ctx"]["durationInFrames"],
        json!(150)
    );

    // No head bound: a start dragged past the graphic's first frame
    // saturates `in` at 0.
    let late = project_with(600_000, Value::Null)
        .apply(&json!({"op": "move_clip", "clips": [11], "delta": 2 * SEC}));
    let early = late.apply(&json!({"op": "trim_start", "clip": 11, "to": 0}));
    assert_eq!(at(&clip(&early, 11), "/start"), &json!(0));
    assert_eq!(at(&clip(&early, 11), "/graphic/in"), &json!(0));

    let longer = project().apply(&json!({"op": "trim_end", "clip": 11, "to": 8 * SEC}));
    assert_eq!(at(&clip(&longer, 11), "/graphic/length"), &Value::Null);
    assert_eq!(
        source_at(&longer, 11, 0)["ctx"]["durationInFrames"],
        json!(240)
    );
    let fixed = project()
        .apply(&set_bare(json!({"length": 1_800_000})))
        .apply(&json!({"op": "trim_end", "clip": 11, "to": 8 * SEC}));
    assert_eq!(at(&clip(&fixed, 11), "/graphic/length"), &json!(1_800_000));
    assert_eq!(
        source_at(&fixed, 11, 0)["ctx"]["durationInFrames"],
        json!(90)
    );
}

#[test]
fn roll_advances_the_graphics_in_as_a_front_trim() {
    let cut = project_with_cut();
    let before = source_at(&cut, 11, 3 * SEC);
    assert_eq!(before["frame"], json!(30));
    assert_eq!(before["ctx"]["durationInFrames"], json!(90));

    let rolled = cut.apply(&json!({"op": "roll", "clip": 11, "to": 3 * SEC}));
    let moved = clip(&rolled, 11);
    assert_eq!(moved["start"], json!(1_800_000));
    assert_eq!(moved["duration"], json!(1_200_000));
    assert_eq!(moved["graphic"]["in"], json!(600_000));
    assert_eq!(moved["graphic"]["length"], Value::Null);
    assert_eq!(clip(&rolled, 30)["duration"], json!(1_800_000));
    let after = source_at(&rolled, 11, 3 * SEC);
    assert_eq!(after["frame"], json!(30), "the frame under the cut stays");
    assert_eq!(after["ctx"]["durationInFrames"], json!(90));

    let back = rolled.apply(&json!({"op": "roll", "clip": 11, "to": 2 * SEC}));
    assert_eq!(at(&clip(&back, 11), "/graphic/in"), &json!(0));
}

#[test]
fn add_transition_moves_the_graphics_in_back_under_its_head() {
    let with_in = |r#in: i64| {
        let mut value = project_with_cut().value();
        value["clips"][0]["graphic"]["in"] = json!(r#in);
        Handle::from_value(&value)
    };
    let op = json!({"op": "add_transition", "clip": 11, "duration": 10 * FRAME,
                    "align": "before"});

    let cut = with_in(600_000);
    let before = source_at(&cut, 11, 2 * SEC);
    assert_eq!(before["frame"], json!(30));
    assert_eq!(before["ctx"]["durationInFrames"], json!(120));
    let joined = cut.apply(&op);
    let moved = clip(&joined, 11);
    assert_eq!(moved["start"], json!(1_000_000));
    assert_eq!(moved["graphic"]["in"], json!(400_000));
    let after = source_at(&joined, 11, 2 * SEC);
    assert_eq!(after["frame"], json!(30), "the frame at the old cut stays");
    assert_eq!(after["ctx"]["durationInFrames"], json!(120));

    // No head bound (G-18a): `in` saturates at 0, and the graphic's first
    // frame lands on the clip's new first frame.
    let joined = with_in(0).apply(&op);
    assert_eq!(at(&clip(&joined, 11), "/graphic/in"), &json!(0));
    assert_eq!(source_at(&joined, 11, 2 * SEC)["frame"], json!(10));
}

#[test]
fn a_canvas_rate_change_puts_in_and_length_on_the_new_grid() {
    let fps = json!({"op": "set_canvas", "fps": [24, 1]});
    let moved = project_with(620_000, json!(1_220_000)).apply(&fps);
    assert_eq!(at(&clip(&moved, 11), "/graphic/in"), &json!(625_000));
    assert_eq!(at(&clip(&moved, 11), "/graphic/length"), &json!(1_225_000));

    let open = project_with(620_000, Value::Null).apply(&fps);
    assert_eq!(at(&clip(&open, 11), "/graphic/length"), &Value::Null);

    let tiny = project_with(0, json!(1)).apply(&fps);
    assert_eq!(at(&clip(&tiny, 11), "/graphic/length"), &json!(25_000));
}

#[test]
fn paste_attributes_leaves_a_graphic_untouched() {
    let with = project().apply(&add(json!({"width": 1280, "height": 720,
                                            "props": {"title": "Ada"}})));
    let before = clip(&with, 20)["graphic"].to_string();
    let mut source = clip(&with, 11);
    source["video"]["opacity"] = json!(0.5);
    source["track"] = json!(0);
    let payload = json!({"clips": [source], "media": [], "nests": []});
    let pasted = with.apply(&json!({"op": "paste_attributes", "clips": [20], "payload": payload}));
    let target = clip(&pasted, 20);
    assert_eq!(target["video"]["opacity"], json!(0.5));
    assert_eq!(target["graphic"].to_string(), before);
}

#[test]
fn the_recipe_publishes_the_seams_shape() {
    let fixture: Value =
        serde_json::from_str(include_str!("fixtures/graphic_v10_recipe.json")).expect("fixture");
    let project = Handle::from_json(include_str!("fixtures/graphic_v10.json"));
    let t = int(&fixture, "/t");
    let recipe = project.recipe(t);
    let layer = &array(&recipe, "/layers")[0];
    assert_eq!(layer["source"], fixture["source"]);
    assert_eq!(layer["source_size"], fixture["source_size"]);

    let written: Value = serde_json::from_str(&project.recipe_text(t)).expect("the recipe");
    let keys: Vec<&String> = at(&written, "/layers/0/source")
        .as_object()
        .expect("source is an object")
        .keys()
        .collect();
    assert_eq!(
        keys,
        [
            "kind",
            "name",
            "hash",
            "frame",
            "ctx",
            "props",
            "props_json",
            "ctx_json"
        ]
    );
}

#[test]
fn the_props_and_ctx_texts_parse_back_to_their_objects_as_written() {
    let project = project().apply(&set_bare(json!({"props": {"accent_color": "#123456"}})));
    let source = source_at(&project, 11, 37 * FRAME);
    for (text, object) in [("props_json", "props"), ("ctx_json", "ctx")] {
        let written = source[text].as_str().expect("a string");
        let parsed: Value = serde_json::from_str(written).expect("the text parses");
        assert_eq!(parsed, source[object], "{text}");
    }
    let props_json = source["props_json"].as_str().expect("a string");
    assert_contains(props_json, "\"accent_color\":\"#123456\"");
    // The ctx text's key ORDER, read under `preserve_order` as `prop_keys`
    // reads the props'.
    let ctx: Value = serde_json::from_str(source["ctx_json"].as_str().expect("a string"))
        .expect("the ctx text parses");
    let keys: Vec<&str> = ctx
        .as_object()
        .expect("ctx is an object")
        .keys()
        .map(String::as_str)
        .collect();
    assert_eq!(
        keys,
        [
            "fps",
            "time",
            "durationInFrames",
            "progress",
            "width",
            "height",
            "canvas"
        ]
    );
}

#[test]
fn frame_and_ctx_follow_the_graphics_own_timeline() {
    let project = project();
    let layer = layer_of(&project.recipe(37 * FRAME), 11);
    let source = &layer["source"];
    assert_eq!(source["kind"], json!("graphic"));
    assert_eq!(source["name"], json!("lower-third"));
    assert_eq!(source["frame"], json!(37));
    let ctx = &source["ctx"];
    assert_eq!(num(ctx, "/fps"), 30.0);
    assert_eq!(num(ctx, "/time"), 37.0 / 30.0);
    assert_eq!(ctx["durationInFrames"], json!(150));
    assert_eq!(num(ctx, "/progress"), 37.0 / 149.0);
    assert_eq!(ctx["width"], json!(1920));
    assert_eq!(ctx["height"], json!(1080));
    assert_eq!(ctx["canvas"], json!({"width": 1920, "height": 1080}));
    assert_eq!(
        source["props"],
        json!({"title": "Kevin", "accent": "#2d7ff9", "subtitle": "Host"})
    );
    assert_eq!(layer["source_size"], json!([1920, 1080]));
    // Floored onto the grid: the last tick of frame 37 is frame 37.
    assert_eq!(
        source_at(&project, 11, 37 * FRAME + 19_999)["frame"],
        json!(37)
    );

    // `in` 600000 is graphic frame 30 at the clip's first frame, and a null
    // length ends with the clip, at graphic time `in + duration`.
    let offset = source_at(&project_with(600_000, Value::Null), 11, FRAME);
    assert_eq!(offset["frame"], json!(31));
    assert_eq!(offset["ctx"]["durationInFrames"], json!(180));

    // A length shorter than the clip: the frame runs on, the progress holds.
    let short = source_at(&project_with(0, json!(1_200_000)), 11, 100 * FRAME);
    assert_eq!(short["ctx"]["durationInFrames"], json!(60));
    assert_eq!(short["frame"], json!(100));
    assert_eq!(num(&short, "/ctx/progress"), 1.0);

    let mut bare = project.value();
    bare["clips"][0]["graphic"] = Value::Null;
    let layer = layer_of(&Handle::from_value(&bare).recipe(0), 11);
    assert_eq!(layer["source"]["kind"], json!("missing"));
    assert_eq!(layer["source_size"], Value::Null);
}

#[test]
fn on_a_29_97_canvas_frame_n_is_at_tick_n_times_20020() {
    let ntsc = Handle::new(1920, 1080, 30000, 1001);
    let track = int(&ntsc.value(), "/tracks/0/id");
    let with = ntsc.apply(&json!({"op": "add_graphic_clip", "track": track, "at": 0,
                                  "name": "lower-third"}));
    let id = int(&with.value(), "/clips/0/id");
    let source = source_at(&with, id, 37 * 20_020);
    let rate = 30000.0 / 1001.0;
    assert_eq!(source["frame"], json!(37));
    assert_eq!(num(&source, "/ctx/fps"), rate);
    assert_eq!(num(&source, "/ctx/time"), 37.0 / rate);
    assert_eq!(source_at(&project(), 11, 37 * FRAME)["frame"], json!(37));
}

#[test]
fn the_hash_follows_everything_render_is_called_with() {
    let project = project();
    let hash = |handle: &Handle, clip: i64, t: i64| -> String {
        source_at(handle, clip, t)["hash"]
            .as_str()
            .expect("a hash")
            .to_string()
    };
    let here = hash(&project, 11, 37 * FRAME);
    assert_eq!(here.len(), 16, "{here}");
    assert!(
        here.chars()
            .all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c)),
        "{here}"
    );
    assert_eq!(hash(&project, 11, 37 * FRAME), here);
    assert_ne!(hash(&project, 11, 38 * FRAME), here);
    let patched = project.apply(&set_bare(json!({"props": {"title": "Ada"}})));
    assert_ne!(hash(&patched, 11, 37 * FRAME), here);
    // The same frame of a shorter graphic is a different outro.
    let shorter = project.apply(&json!({"op": "trim_end", "clip": 11, "to": 4 * SEC}));
    assert_eq!(source_at(&shorter, 11, 37 * FRAME)["frame"], json!(37));
    assert_ne!(hash(&shorter, 11, 37 * FRAME), here);

    // Props sent in opposite key orders hash equal: the key is sorted.
    let pair = project
        .apply(
            &json!({"op": "add_graphic_clip", "track": 2, "at": 10 * SEC,
                       "name": "lower-third", "props": {"title": "Ada", "subtitle": "Host"}}),
        )
        .apply(
            &json!({"op": "add_graphic_clip", "track": 3, "at": 10 * SEC,
                       "name": "lower-third", "props": {"subtitle": "Host", "title": "Ada"}}),
        );
    let t = 10 * SEC + 37 * FRAME;
    assert_eq!(hash(&pair, 20, t), hash(&pair, 21, t));
}

#[test]
fn a_graphic_inside_a_nest_counts_frames_from_its_own_first_frame() {
    let nested = project().apply(&json!({"op": "nest", "clips": [11]}));
    let nest_clip = array(&nested.value(), "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("nest"))
        .map(|c| int(c, "/id"))
        .expect("a nest clip");
    // A project canvas that differs from the nest's frozen 1920×1080, so
    // `ctx.canvas` can only be the PROJECT's.
    let resized = nested.apply(&json!({"op": "set_canvas", "width": 1280, "height": 720}));
    assert_eq!(at(&resized.value(), "/nests/0/width"), &json!(1920));
    assert_eq!(at(&resized.value(), "/nests/0/height"), &json!(1080));
    let moved = resized.apply(&json!({"op": "move_clip", "clips": [nest_clip], "delta": SEC}));
    let layer = layer_of(&moved.recipe(SEC + 37 * FRAME), 11);
    assert_eq!(layer["source"]["frame"], json!(37));
    assert_eq!(
        layer["source"]["ctx"]["canvas"],
        json!({"width": 1280, "height": 720})
    );
    assert!(!layer["clip_rect"].is_null(), "{layer}");
}
