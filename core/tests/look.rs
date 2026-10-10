//! Black-box tests for looks (spec §11 GR-7, format 1015 on the grading
//! branch): `video.look {kind, amount}` and the recipe's `look`, driven
//! through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the amount's range, refused in its own sentence at both
//! ends; an unknown kind refused naming the eight and `lut`; a kind alone landing at
//! the default amount, and a new kind keeping the amount; an amount alone
//! refused on a clip with no look; an action's end naming only an amount on
//! a clip with no look evaluating as no look without losing its other keys;
//! `null` removing it; no key in an untouched file; the recipe's `null` and
//! its object, the burn-in included; the amount interpolating and the kind
//! switching at the end; `paste_attributes` carrying it; and the eight
//! definitions in range, not neutral and distinct. What a look does to a
//! pixel is `tools/proof/look_proof.py`'s.

mod common;

use serde_json::{json, Value};

use common::{assert_contains, by_id, num, Handle};

const SEC: i64 = 600_000;

const KINDS: [&str; 8] = [
    "warm",
    "cool",
    "teal_orange",
    "vivid",
    "faded",
    "vintage",
    "dramatic",
    "black_white",
];

/// One media clip (10) on track 4, six seconds long, with no look.
fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 14,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [
            {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
             "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true,
             "has_audio": false}
        ],
        "tracks": [{"id": 4, "name": "Track 1"}],
        "clips": [
            {"id": 10, "track": 4, "start": 0, "duration": 6 * SEC, "speed": 1.0,
             "source": {"kind": "media", "media": 1, "in": 0},
             "enabled": {"video": true, "audio": false}, "video": {}}
        ],
        "next_id": 20
    }))
}

fn set_look(look: Value) -> Value {
    json!({"op": "set_video", "clips": [10], "patch": {"look": look}})
}

/// Clip 10's stored look, or `Value::Null` when it has none.
fn stored(handle: &Handle) -> Value {
    by_id(&handle.value(), "/clips", 10)["video"]
        .get("look")
        .cloned()
        .unwrap_or(Value::Null)
}

/// Clip 10's evaluated look at `t`, or `Value::Null` when it has none.
fn evaluated(handle: &Handle, t: i64) -> Value {
    handle.clip_state(10, t).expect("clip 10")["video"]
        .get("look")
        .cloned()
        .unwrap_or(Value::Null)
}

/// Clip 10's recipe layer at `t`.
fn layer(handle: &Handle, t: i64) -> Value {
    handle.recipe(t)["layers"]
        .as_array()
        .and_then(|layers| layers.iter().find(|l| l["clip"] == json!(10)))
        .cloned()
        .expect("clip 10's layer")
}

/// A two-second linear action from 1 s whose end is `end`'s video group.
fn animated(handle: Handle, end: Value) -> Handle {
    handle
        .apply(&json!({"op": "add_action", "clip": 10, "at": SEC, "duration": 2 * SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 20,
                        "patch": {"video": end}}))
}

#[test]
fn the_amount_is_refused_past_either_end_in_its_own_sentence() {
    let base = project();
    for value in [1.5, -0.25] {
        assert_contains(
            &base.errors(&set_look(json!({"kind": "warm", "amount": value}))),
            &format!("video.look.amount must be between 0 and 1, not {value}"),
        );
    }
    for value in [0.0, 1.0] {
        let looked = base.apply(&set_look(json!({"kind": "warm", "amount": value})));
        assert_eq!(stored(&looked), json!({"kind": "warm", "amount": value}));
    }
}

#[test]
fn an_unknown_kind_is_refused_naming_the_eight_and_lut() {
    // `lut` (spec §11 GR-8) follows the eight built-ins.
    let names: Vec<String> = KINDS
        .iter()
        .chain(["lut"].iter())
        .map(|k| format!("`{k}`"))
        .collect();
    assert_contains(
        &project().errors(&set_look(json!({"kind": "sepia"}))),
        &format!(
            "bad value at \"look.kind\" in a video patch: unknown variant `sepia`, \
             expected one of {}",
            names.join(", ")
        ),
    );
}

#[test]
fn a_kind_alone_lands_at_full_and_a_new_kind_keeps_the_amount() {
    let looked = project().apply(&set_look(json!({"kind": "warm"})));
    assert_eq!(stored(&looked), json!({"kind": "warm", "amount": 1.0}));
    let partial = looked.apply(&set_look(json!({"amount": 0.4})));
    let switched = partial.apply(&set_look(json!({"kind": "cool"})));
    assert_eq!(stored(&switched), json!({"kind": "cool", "amount": 0.4}));
}

#[test]
fn an_amount_alone_on_a_clip_with_no_look_is_refused() {
    let base = project();
    assert_contains(
        &base.errors(&set_look(json!({"amount": 0.5}))),
        "bad value at \"look\" in a video patch: missing field `kind`",
    );
}

#[test]
fn null_removes_it_and_an_untouched_file_has_no_key() {
    let base = project();
    let written = base.to_json();
    assert!(!written.contains("\"look\""), "{written}");
    let looked = base.apply(&set_look(json!({"kind": "vintage", "amount": 0.5})));
    assert!(looked.to_json().contains("\"look\""));
    let removed = looked.apply(&set_look(Value::Null));
    assert_eq!(removed.to_json(), written);
    // `null` on a clip with no look changes nothing.
    base.refuses(&set_look(Value::Null));
}

#[test]
fn a_kindless_end_on_a_clip_with_no_look_is_no_look_and_keeps_its_other_keys() {
    let end = json!({"look": {"amount": 1}, "opacity": 0.5});
    let handle = animated(project(), end.clone());
    assert_eq!(evaluated(&handle, 4 * SEC), Value::Null);
    let state = handle.clip_state(10, 4 * SEC).expect("clip 10");
    assert_eq!(num(&state, "/video/opacity"), 0.5);
    let mid = handle.clip_state(10, 2 * SEC).expect("clip 10");
    assert!((num(&mid, "/video/opacity") - 0.75).abs() < 1e-9, "{mid}");
    assert_eq!(layer(&handle, 4 * SEC)["look"], Value::Null);
    assert_eq!(layer(&handle, 4 * SEC)["opacity"], json!(0.5));

    // A look removed after the end was written: the same answer.
    let looked = animated(
        project().apply(&set_look(json!({"kind": "warm", "amount": 0.3}))),
        end,
    );
    assert_eq!(
        evaluated(&looked, 4 * SEC),
        json!({"kind": "warm", "amount": 1.0})
    );
    let removed = looked.apply(&set_look(Value::Null));
    assert_eq!(evaluated(&removed, 4 * SEC), Value::Null);
    let state = removed.clip_state(10, 4 * SEC).expect("clip 10");
    assert_eq!(num(&state, "/video/opacity"), 0.5);
}

#[test]
fn the_recipe_publishes_null_or_the_kind_the_amount_and_the_definition() {
    let base = project();
    assert_eq!(layer(&base, SEC)["look"], Value::Null);
    let none = base.apply(&set_look(json!({"kind": "warm", "amount": 0})));
    assert_eq!(layer(&none, SEC)["look"], Value::Null);

    let looked = base.apply(&set_look(json!({"kind": "warm", "amount": 0.6})));
    let look = layer(&looked, SEC)["look"].clone();
    let keys: Vec<&str> = look
        .as_object()
        .expect("an object")
        .keys()
        .map(String::as_str)
        .collect();
    assert_eq!(keys, ["kind", "amount", "definition"]);
    assert_eq!(look["kind"], json!("warm"));
    assert_eq!(look["amount"], json!(0.6));
    let color = &look["definition"]["color"];
    assert_eq!(color.as_object().expect("color").len(), 13, "{color}");
    assert_eq!(color["temperature"], json!(0.35));
    assert_eq!(color["tint"], json!(0.05));
    assert_eq!(color["vibrance"], json!(0.1));
    assert_eq!(color["exposure"], json!(0.0));
    assert_eq!(
        look["definition"]["split"],
        json!({"shadow_hue": 0.0, "shadow_amount": 0.0,
               "highlight_hue": 40.0, "highlight_amount": 0.25})
    );

    // The burn-in publishes the key too, as null, and the drawn layer is
    // unchanged beside it.
    let burnt = looked.recipe_opts(SEC, r#"{"burn_in_timecode": true}"#);
    let layers = burnt["layers"].as_array().expect("layers");
    let burn_in = layers.last().expect("the burn-in");
    assert_eq!(burn_in.get("look"), Some(&Value::Null), "{burn_in}");
    let drawn = layers
        .iter()
        .find(|l| l["clip"] == json!(10))
        .expect("clip 10");
    assert_eq!(drawn["look"], look);
}

#[test]
fn the_amount_interpolates_and_a_new_kind_switches_at_the_end() {
    let handle = animated(
        project().apply(&set_look(json!({"kind": "warm", "amount": 0.2}))),
        json!({"look": {"amount": 1}}),
    );
    let amount = |t: i64| {
        num(
            &handle.clip_state(10, t).expect("clip 10"),
            "/video/look/amount",
        )
    };
    assert!((amount(SEC) - 0.2).abs() < 1e-9);
    assert!((amount(2 * SEC) - 0.6).abs() < 1e-9, "{}", amount(2 * SEC));
    assert_eq!(amount(4 * SEC), 1.0);
    assert!(
        (layer(&handle, 2 * SEC)["look"]["amount"]
            .as_f64()
            .expect("amount")
            - 0.6)
            .abs()
            < 1e-9
    );

    let switched = animated(
        project().apply(&set_look(json!({"kind": "warm"}))),
        json!({"look": {"kind": "cool"}}),
    );
    assert_eq!(evaluated(&switched, 3 * SEC - 1)["kind"], json!("warm"));
    assert_eq!(evaluated(&switched, 3 * SEC)["kind"], json!("cool"));
    assert_eq!(layer(&switched, 3 * SEC)["look"]["kind"], json!("cool"));
}

#[test]
fn paste_attributes_carries_the_look_with_the_video_group() {
    let payload = json!({"clips": [{
        "id": 1, "track": 0, "start": 0, "duration": 600000,
        "source": {"kind": "shape"},
        "video": {"look": {"kind": "dramatic", "amount": 0.75}},
        "shape": {"kind": "rectangle", "width": 10, "height": 10}
    }]});
    let after = project().apply(&json!({"op": "paste_attributes", "clips": [10],
                                        "payload": payload}));
    assert_eq!(stored(&after), json!({"kind": "dramatic", "amount": 0.75}));
}

#[test]
fn each_definition_is_in_range_not_neutral_and_distinct() {
    let mut seen: Vec<Value> = Vec::new();
    for kind in KINDS {
        let looked = project().apply(&set_look(json!({ "kind": kind })));
        let definition = layer(&looked, SEC)["look"]["definition"].clone();
        let color = definition["color"].clone();
        // In range: the colour is a patch `check_video` takes.
        project().apply(&json!({"op": "set_video", "clips": [10],
                                "patch": {"color": color}}));
        let split = &definition["split"];
        for key in ["shadow_amount", "highlight_amount"] {
            let amount = split[key].as_f64().expect("a split amount");
            assert!((0.0..=1.0).contains(&amount), "{kind} {key} {amount}");
        }
        for key in ["shadow_hue", "highlight_hue"] {
            let hue = split[key].as_f64().expect("a split hue");
            assert!((0.0..360.0).contains(&hue), "{kind} {key} {hue}");
        }
        let neutral = color
            .as_object()
            .expect("color")
            .values()
            .all(|v| v == &json!(0.0));
        assert!(!neutral, "{kind} has a neutral colour");
        assert!(!seen.contains(&definition), "{kind} repeats a definition");
        seen.push(definition);
    }
    assert_eq!(seen.len(), 8);
}
