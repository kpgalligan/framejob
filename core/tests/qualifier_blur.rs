//! Black-box tests for the qualifier's cleanup blur (spec §11 GR-35, format
//! 21): `video.qualifier.blur` on an adjustment clip, driven through the C
//! FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the key written only when above 0, after `invert`; a blur
//! alone stored as a qualifier, and a blur of 0 there an identity; the
//! refusal on any other clip; the bounds 0 and 1 accepted and 1.5 and −0.1
//! refused in `in_range`'s sentence, checked after luma; the recipe's
//! adjustment source carrying `blur` only when above 0, a blur-0 recipe
//! byte-identical to one without the key, and `ungraded` and `selection`
//! keeping it; an action's blur interpolating from a qualified base (0.25 at
//! the half of a 0 → 0.5 linear second, in `clip_state` and the recipe), a
//! qualifier turned on switching at the end, an end clamped to 1; and Paste
//! Attributes copying it. What the blur does to a pixel is
//! `tools/proof/qualifier_proof.py`'s (Q1–Q6).

mod common;

use framejob_core::format::RC_FORMAT_VERSION;
use serde_json::{json, Value};

use common::{array, assert_contains, at, by_id, Handle, Outcome};

/// Ticks per second (spec §5.1).
const SEC: i64 = 600_000;

/// A shape (10) on track 1 and an adjustment clip (11) on track 2 in front,
/// both four seconds long.
fn project() -> Handle {
    Handle::from_value(&json!({
        "version": RC_FORMAT_VERSION,
        "canvas": {"width": 640, "height": 360, "fps": [30, 1]},
        "tracks": [{"id": 1, "name": "Picture"}, {"id": 2, "name": "Adjustment"}],
        "clips": [
            {"id": 10, "track": 1, "start": 0, "duration": 4 * SEC,
             "source": {"kind": "shape"}, "video": {},
             "shape": {"kind": "rectangle", "width": 100, "height": 50}},
            {"id": 11, "track": 2, "start": 0, "duration": 4 * SEC,
             "source": {"kind": "adjustment"}, "video": {"color": {"saturation": -1.0}}}
        ],
        "next_id": 20
    }))
}

fn set_qualifier(clip: u32, qualifier: Value) -> Value {
    json!({"op": "set_video", "clips": [clip], "patch": {"qualifier": qualifier}})
}

/// Clip `id`'s stored `video.qualifier`, or `null` when the file has none.
fn stored(handle: &Handle, id: u64) -> Value {
    by_id(&handle.value(), "/clips", id)["video"]
        .get("qualifier")
        .cloned()
        .unwrap_or(Value::Null)
}

/// Clip `id`'s layer in the recipe at `t`, under `opts`.
fn layer(handle: &Handle, id: u64, t: i64, opts: &str) -> Value {
    array(&handle.recipe_opts(t, opts), "/layers")
        .iter()
        .find(|l| l["clip"] == json!(id))
        .cloned()
        .unwrap_or_else(|| panic!("clip {id}'s layer"))
}

/// H1's hue range (the proof's).
fn hue() -> Value {
    json!({"center": 120, "width": 40, "softness": 20})
}

/// Clip 11 qualified by `base` (none for `Value::Null`), with a one-second
/// linear action at 0 whose end patch's qualifier is `end`.
fn acting(base: Value, end: Value) -> Handle {
    let start = if base.is_null() {
        project()
    } else {
        project().apply(&set_qualifier(11, base))
    };
    start
        .apply(&json!({"op": "add_action", "clip": 11, "at": 0, "duration": SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 11, "action": 20,
                        "patch": {"video": {"qualifier": end}}}))
}

/// Clip 11's evaluated blur at `t` in `clip_state`, or `None` when its
/// qualifier has none.
fn state_blur(handle: &Handle, t: i64) -> Option<f64> {
    handle
        .clip_state(11, t)
        .expect("clip 11")
        .pointer("/video/qualifier/blur")
        .and_then(Value::as_f64)
}

/// Clip 11's blur at `t` in the recipe's adjustment source, or `None`.
fn recipe_blur(handle: &Handle, t: i64) -> Option<f64> {
    layer(handle, 11, t, "{}")["source"]
        .pointer("/qualifier/blur")
        .and_then(Value::as_f64)
}

fn close(a: Option<f64>, b: f64) -> bool {
    a.is_some_and(|a| (a - b).abs() < 1e-9)
}

#[test]
fn written_only_above_zero_and_after_invert() {
    let base = project();
    let blurred = base.apply(&set_qualifier(
        11,
        json!({"blur": 0.4, "invert": true, "hue": hue()}),
    ));
    assert_eq!(
        stored(&blurred, 11),
        json!({"hue": {"center": 120.0, "width": 40.0, "softness": 20.0},
               "invert": true, "blur": 0.4})
    );
    let text = blurred.to_json();
    let invert = text.find("\"invert\"").expect("invert");
    let blur = text.find("\"blur\"").expect("blur");
    assert!(invert < blur, "{text}");
    // Back to 0: the key goes, and the text is the unblurred qualifier's.
    let unblurred = blurred.apply(&set_qualifier(11, json!({"blur": 0})));
    let plain = base.apply(&set_qualifier(11, json!({"invert": true, "hue": hue()})));
    assert_eq!(unblurred.to_json(), plain.to_json());
    assert!(!plain.to_json().contains("\"blur\""));
}

#[test]
fn a_blur_alone_is_a_qualifier_and_zero_there_an_identity() {
    let base = project();
    let alone = base.apply(&set_qualifier(11, json!({"blur": 0.4})));
    assert_eq!(stored(&alone, 11), json!({"blur": 0.4}));
    assert!(matches!(
        base.try_apply(&set_qualifier(11, json!({"blur": 0}))),
        Ok(Outcome::Identity)
    ));
    // A blur alone draws nothing: the recipe publishes it, the pass needs a
    // range (Swift's `blursSelection`).
    assert_eq!(
        layer(&alone, 11, SEC, "{}")["source"],
        json!({"kind": "adjustment", "qualifier": {"blur": 0.4}})
    );
}

#[test]
fn only_an_adjustment_clip_takes_one() {
    let base = project();
    assert_contains(
        &base.errors(&set_qualifier(10, json!({"blur": 0.3}))),
        "clip 10 is not an adjustment clip and cannot take a qualifier",
    );
    assert!(matches!(
        base.try_apply(&set_qualifier(10, json!({"blur": 0}))),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn the_bounds_and_the_sentence_after_luma() {
    let base = project().apply(&set_qualifier(11, json!({"hue": hue(), "blur": 0.4})));
    for (blur, shown) in [(1.5, "1.5"), (-0.1, "-0.1")] {
        let before = base.to_json();
        assert_contains(
            &base.errors(&set_qualifier(11, json!({"blur": blur}))),
            &format!("video.qualifier.blur must be between 0 and 1, not {shown}"),
        );
        assert_eq!(base.to_json(), before);
    }
    for edge in [0.0, 1.0] {
        let applied = base.apply(&set_qualifier(11, json!({"blur": edge})));
        assert_eq!(
            stored(&applied, 11).get("blur").and_then(Value::as_f64),
            (edge > 0.0).then_some(edge)
        );
    }
    // A bad luma and a bad blur: the luma is named (blur is checked last).
    assert_contains(
        &base.errors(&set_qualifier(
            11,
            json!({"blur": 2, "luma": {"softness": 1.5}}),
        )),
        "video.qualifier.luma.softness must be between 0 and 1, not 1.5",
    );
}

#[test]
fn the_recipe_carries_it_only_above_zero() {
    let ranged = project().apply(&set_qualifier(11, json!({"hue": hue()})));
    let unblurred = ranged.recipe_text(SEC);
    assert!(!unblurred.contains("\"blur\""), "{unblurred}");
    let blurred = ranged.apply(&set_qualifier(11, json!({"blur": 0.25})));
    assert_eq!(
        layer(&blurred, 11, SEC, "{}")["source"],
        json!({"kind": "adjustment",
               "qualifier": {"hue": {"center": 120.0, "width": 40.0, "softness": 20.0},
                             "blur": 0.25}})
    );
    // Back to 0, and a file that spells `"blur": 0`: today's recipe, byte for
    // byte.
    let back = blurred.apply(&set_qualifier(11, json!({"blur": 0})));
    assert_eq!(back.recipe_text(SEC), unblurred);
    let mut value = ranged.value();
    value["clips"][1]["video"]["qualifier"]["blur"] = json!(0.0);
    let spelled = Handle::from_value(&value);
    assert_eq!(spelled.recipe_text(SEC), unblurred);
    // `ungraded` and `selection` keep it.
    let plain = layer(&blurred, 11, SEC, "{}")["source"].clone();
    assert_eq!(
        layer(&blurred, 11, SEC, r#"{"ungraded": true}"#)["source"],
        plain
    );
    let selected = layer(&blurred, 11, SEC, r#"{"selection": 11}"#)["source"].clone();
    assert_eq!(selected["qualifier"], plain["qualifier"]);
    assert_eq!(selected["selection"], json!(true));
}

#[test]
fn an_action_interpolates_it_from_a_qualified_base() {
    let handle = acting(json!({"hue": hue()}), json!({"blur": 0.5}));
    assert!(close(state_blur(&handle, 0), 0.0), "at 0");
    assert!(
        close(state_blur(&handle, SEC / 2), 0.25),
        "clip_state at 0.5"
    );
    assert!(
        close(recipe_blur(&handle, SEC / 2), 0.25),
        "the recipe at 0.5"
    );
    assert!(close(state_blur(&handle, 2 * SEC), 0.5), "clip_state after");
    assert!(
        close(recipe_blur(&handle, 2 * SEC), 0.5),
        "the recipe after"
    );
    // From one blur to another.
    let between = acting(json!({"hue": hue(), "blur": 0.2}), json!({"blur": 0.6}));
    assert!(
        close(state_blur(&between, SEC / 2), 0.4),
        "0.2 → 0.6 at 0.5"
    );
}

#[test]
fn a_qualifier_turned_on_switches_at_the_end() {
    let handle = acting(Value::Null, json!({"hue": hue(), "blur": 0.5}));
    let mid = handle.clip_state(11, SEC / 2).expect("clip 11");
    assert!(mid["video"].get("qualifier").is_none(), "{mid}");
    assert!(close(state_blur(&handle, 2 * SEC), 0.5), "after");
}

#[test]
fn an_actions_end_is_clamped() {
    let handle = acting(json!({"hue": hue()}), json!({"blur": 3}));
    assert!(close(state_blur(&handle, 2 * SEC), 1.0), "3 → 1");
    let below = acting(json!({"hue": hue(), "blur": 0.5}), json!({"blur": -2}));
    let after = handle_qualifier(&below, 2 * SEC);
    assert!(
        after.get("blur").is_none_or(|b| b == &json!(0.0)),
        "{after}"
    );
}

/// Clip 11's evaluated qualifier in the recipe at `t`.
fn handle_qualifier(handle: &Handle, t: i64) -> Value {
    at(&layer(handle, 11, t, "{}"), "/source/qualifier").clone()
}

#[test]
fn paste_attributes_copies_it_between_adjustment_clips() {
    let blurred = json!({"hue": {"center": 120.0, "width": 40.0, "softness": 20.0},
                         "blur": 0.3});
    let payload = json!({"clips": [{"id": 1, "track": 0, "start": 0, "duration": SEC,
                                    "source": {"kind": "adjustment"},
                                    "video": {"qualifier": blurred}}]});
    let pasted = project().apply(&json!({"op": "paste_attributes", "clips": [11],
                                         "payload": payload}));
    assert_eq!(stored(&pasted, 11), blurred);
}
