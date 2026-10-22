//! Black-box tests for what an action does to a graphic clip's props over
//! time (format version 13, spec §11 G-34 (b), (e), (h), (i), and G-40),
//! through the C FFI as `ReelCore.swift` drives it: a number ramps and
//! arrives fractional, a colour ramps in OKLab with straight alpha, a
//! string, a boolean and an enum switch at the action's END, the layer's
//! hash moves only while a prop does, `split` is invisible, and an action
//! inside a nest animates its graphic as any other. The door — what
//! `set_action_end` takes and stores — is `graphic_action_door.rs`'s; what a
//! file holds is `schema_v13.rs`'s.
//!
//! Every oracle is worked by hand from the fixture: a linear action at 1 s
//! for 1 s, so 1.5 s is u = 0.5 and 2 s − 1 frame is u = 29/30. A colour's
//! middle is also `graphic/tests/oklab.json`'s, the blends stdlib's
//! `interpolateColors` answers (G-40).

mod common;
#[path = "common/graphic_actions.rs"]
mod fixture;

use serde_json::{json, Value};

use common::int;
use fixture::{
    clip, end, hash_at, project, project_with, props_at, source_at, with_action, with_action_on,
    FRAME, SEC,
};

/// The blends both colour implementations answer (spec §11 G-40), read by
/// path as `colour.rs` reads `colours.json`.
const OKLAB: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../graphic/tests/oklab.json");

/// The bytes of a `#rrggbb[aa]` colour, alpha 255 when absent.
fn channels(colour: &Value) -> [i64; 4] {
    let text = colour
        .as_str()
        .unwrap_or_else(|| panic!("{colour} is no colour"));
    let hex = text.strip_prefix('#').expect("a # colour");
    let pair = |i: usize| i64::from_str_radix(&hex[i..i + 2], 16).expect("hex");
    let alpha = if hex.len() == 8 { pair(6) } else { 255 };
    [pair(0), pair(2), pair(4), alpha]
}

#[test]
fn a_number_ramps_and_arrives_fractional_never_rounded() {
    let (with, action) = with_action();
    let animated = with.apply(&end(action, json!({"graphic": {"props": {"size": 129}}})));
    let mid = SEC + SEC / 2;
    // 64 + (129 − 64) × 0.5 = 96.5: two whole ends, a fraction between.
    assert_eq!(props_at(&animated, mid)["size"], json!(96.5));
    let state = animated.clip_state(11, mid).expect("clip 11");
    assert_eq!(state["graphic"]["props"]["size"], json!(96.5));
    // `clip_state` answers the graphic beside `shape`, its other fields as
    // stored.
    assert_eq!(state["graphic"]["name"], json!("lower-third"));
    assert_eq!(state["graphic"]["props"]["title"], json!("A"));
}

#[test]
fn a_colour_ramps_in_oklab_with_straight_alpha() {
    let (with, action) = with_action();
    let clear = with.apply(&end(
        action,
        json!({"graphic": {"props": {"accent": "#ffffff"}}}),
    ));
    // Black to white in OKLab is L 0 → 1, a and b 0: halfway L is 0.5, so
    // linear light 0.5³ = 0.125, sRGB 1.055 × 0.125^(1/2.4) − 0.055 =
    // 0.3886, × 255 = 99.09, rounding to 99 (0x63). Alpha straight, 0 → 255:
    // 127.5 rounds to 128 (0x80). Premultiplied, the colour would stay
    // white and only the alpha move; channel by channel it would be 0x80.
    assert_eq!(
        props_at(&clear, SEC + SEC / 2)["accent"],
        json!("#63636380")
    );

    let (red, action) = with_action_on(&project_with("accent", json!("#ff0000")));
    let blue = red.apply(&end(
        action,
        json!({"graphic": {"props": {"accent": "#0000ff"}}}),
    ));
    // Opaque both ends, so written `#rrggbb` (G-12); the middle is
    // `oklab.json`'s red → blue at 0.5, never the channel blend `#800080`.
    assert_eq!(props_at(&blue, SEC + SEC / 2)["accent"], json!("#8c53a2"));
}

/// The shared fixture `graphic/tests/oklab.json` (G-40): each blend driven
/// through the FFI as a linear action at 1 s for 1 s from the clip's `from`
/// to an end of `to`, read at 1 s + t, answers the fixture's colour, the
/// one stdlib's `interpolateColors` answers (`graphic/tests/stdlib.rs`).
#[test]
fn a_colour_answers_the_shared_oklab_fixture() {
    let text = std::fs::read_to_string(OKLAB).expect("graphic/tests/oklab.json");
    let fixture: Value = serde_json::from_str(&text).expect("the OKLab fixture is JSON");
    let blends = fixture["blends"].as_array().expect("blends");
    assert!(!blends.is_empty());
    for case in blends {
        let (from, to) = (case[0].clone(), case[1].clone());
        let t = case[2].as_f64().expect("t");
        let (with, action) = with_action_on(&project_with("accent", from));
        let blended = with.apply(&end(action, json!({"graphic": {"props": {"accent": to}}})));
        let at = SEC + (t * SEC as f64) as i64;
        assert_eq!(props_at(&blended, at)["accent"], case[3], "{case}");
    }
}

#[test]
fn the_layer_hash_moves_only_while_a_prop_does() {
    let (with, action) = with_action();
    let animated = with.apply(&end(action, json!({"graphic": {"props": {"size": 129}}})));
    let still = project();
    // Before the action, and at its first tick (u = 0, the integer start
    // as stored): the hash a clip with no action has.
    for t in [SEC / 2, SEC] {
        assert_eq!(hash_at(&animated, t), hash_at(&still, t), "at {t}");
    }
    let (early, late) = (SEC + SEC / 5, SEC + SEC / 2);
    for t in [early, late] {
        assert_ne!(hash_at(&animated, t), hash_at(&still, t), "at {t}");
    }
    assert_ne!(props_at(&animated, early), props_at(&animated, late));
    assert_ne!(hash_at(&animated, early), hash_at(&animated, late));
    // After it: the hash of a clip whose base IS the end.
    let ended = project_with("size", json!(129));
    let after = 2 * SEC + SEC / 2;
    assert_eq!(hash_at(&animated, after), hash_at(&ended, after));
    assert_eq!(props_at(&animated, after), props_at(&ended, after));
}

#[test]
fn a_string_a_boolean_and_an_enum_switch_at_the_end() {
    let (with, action) = with_action();
    let patch = json!({"graphic": {"props": {"title": "B", "boxed": false, "align": "right"}}});
    let switched = with.apply(&end(action, patch));
    let before = props_at(&switched, 2 * SEC - FRAME);
    assert_eq!(
        (&before["title"], &before["boxed"], &before["align"]),
        (&json!("A"), &json!(true), &json!("left"))
    );
    let after = props_at(&switched, 2 * SEC);
    assert_eq!(
        (&after["title"], &after["boxed"], &after["align"]),
        (&json!("B"), &json!(false), &json!("right"))
    );
}

#[test]
fn a_split_through_an_animated_prop_is_invisible() {
    let mut base = fixture::base();
    base["clips"][0]["graphic"]["props"]["size"] = json!(0);
    base["clips"][0]["graphic"]["props"]["accent"] = json!("#000000");
    let at_zero = common::Handle::from_value(&base)
        .apply(&json!({"op": "add_action", "clip": 11, "at": 0, "duration": SEC}));
    let action = int(&clip(&at_zero, 11), "/actions/0/id");
    let patch = json!({"graphic": {"props": {"size": 300, "accent": "#1e1e1e", "title": "B"}}});
    let whole = at_zero.apply(&end(action, patch));
    let split = whole.apply(&json!({"op": "split", "clips": [11], "at": 10 * FRAME}));
    assert_eq!(
        common::array(&split.value(), "/clips").len(),
        3,
        "the cut made a second graphic clip"
    );
    for frame in 0..36 {
        let t = frame * FRAME;
        let (one, two) = (props_at(&whole, t), props_at(&split, t));
        let (a, b) = (one["size"].as_f64(), two["size"].as_f64());
        let (a, b) = (a.expect("a size"), b.expect("a size"));
        assert!((a - b).abs() < 1e-9, "frame {frame}: size {a} against {b}");
        for (x, y) in channels(&one["accent"])
            .iter()
            .zip(channels(&two["accent"]))
        {
            assert!((x - y).abs() <= 1, "frame {frame}: {one} against {two}");
        }
        for key in ["title", "boxed", "align"] {
            assert_eq!(one[key], two[key], "frame {frame}: {key}");
        }
    }
}

#[test]
fn an_action_inside_a_nest_animates_its_graphic() {
    let nested = project().apply(&json!({"op": "nest", "clips": [11]}));
    let nest = int(&nested.value(), "/nests/0/id");
    let added = nested.apply(&json!({"op": "add_action", "clip": 11, "at": SEC,
                                     "duration": SEC, "scope": nest}));
    let action = int(&added.value(), "/nests/0/clips/0/actions/0/id");
    let mut op = end(action, json!({"graphic": {"props": {"size": 129}}}));
    op["scope"] = json!(nest);
    let animated = added.apply(&op);
    assert_eq!(props_at(&animated, SEC + SEC / 2)["size"], json!(96.5));
    assert_eq!(
        source_at(&animated, SEC + SEC / 2)["name"],
        json!("lower-third")
    );
}
