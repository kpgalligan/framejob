//! Black-box tests for the `ungraded` recipe option (spec §11 GR-4, §7.3),
//! driven through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! The oracle is written independently of the code under test: the SAME
//! project with every `video.color` group, every `video.wheels` (GR-11),
//! every `video.curves` (GR-12) and every `video.look` (GR-7) removed from its JSON — on top-level clips, inside a nest, on a luma-matte
//! clip, on an adjustment clip and in an action's end — read back through
//! `rc_project_from_json`. The option's recipe must be that
//! project's recipe byte for byte, and with the option off (or misspelt) the
//! recipe must be the plain one byte for byte. What the option does to a
//! pixel is `tools/proof/seeing_proof.py`'s.

mod common;

use serde_json::{json, Value};

use common::{array, Handle};

/// Ticks per second (spec §5.1).
const SEC: i64 = 600_000;

/// Inside the action, at its end, and past it; every clip covers all three.
const TIMES: [i64; 3] = [SEC / 2, SEC, 3 * SEC / 2];

/// The id of the last element of the array at `pointer`.
fn last_id(handle: &Handle, pointer: &str) -> u32 {
    let value = handle.value();
    let id = array(&value, pointer)
        .iter()
        .filter_map(|v| v["id"].as_u64())
        .max()
        .unwrap_or_else(|| panic!("no ids at {pointer}"));
    u32::try_from(id).expect("an id fits in u32")
}

/// A new track at the front, and its id.
fn add_track(handle: Handle) -> (Handle, u32) {
    let next = handle.apply(&json!({"op": "add_track"}));
    let id = last_id(&next, "/tracks");
    (next, id)
}

/// A rectangle on `track` over `[0, 2 s)` graded by `color`, and its id.
fn graded_shape(handle: Handle, track: u32, color: Value) -> (Handle, u32) {
    let next = handle.apply(&json!({
        "op": "add_shape_clip", "track": track, "at": 0, "duration": 2 * SEC
    }));
    let id = last_id(&next, "/clips");
    let next = next.apply(&json!({"op": "set_video", "clips": [id], "patch": {"color": color}}));
    (next, id)
}

/// A graded, wheeled, curved media clip with a look on track 1; a graded shape with a filter,
/// a chroma key and an opacity (all kept) on track 2, with an action whose
/// end grades it further, gains it, curves it and gives it a look; a graded shape inside a nest
/// on track 3; a graded shape on a luma-matte track 4; an adjustment clip
/// whose only grades are a look, a gamma push and a blue curve on track 5.
fn graded() -> Handle {
    let handle = Handle::new(640, 360, 30, 1).apply_all(&[
        json!({"op": "add_media", "descriptor": {
            "path": "/m/a.mov", "kind": "video", "duration": 6 * SEC,
            "width": 640, "height": 360, "fps": [30, 1],
            "has_video": true, "has_audio": false}}),
        json!({"op": "add_clip", "track": 1, "media": 2, "at": 0}),
    ]);
    let media_clip = last_id(&handle, "/clips");
    let handle = handle.apply(&json!({"op": "set_video", "clips": [media_clip], "patch": {
        "color": {"exposure": 1.0, "brightness": 0.1, "contrast": 0.2},
        "wheels": {"lift": {"x": 0.3, "master": 0.1}},
        "curves": {"master": [[0, 0], [0.5, 0.3], [1, 1]]},
        "look": {"kind": "warm", "amount": 0.8}}}));

    let (handle, two) = add_track(handle);
    let (handle, toned) = graded_shape(
        handle,
        two,
        json!({"temperature": 0.5, "hue": 20, "fade": 0.25}),
    );
    let handle = handle
        .apply(&json!({"op": "set_video", "clips": [toned], "patch": {
            "opacity": 0.8,
            "filters": [{"kind": "sepia", "amount": 0.6}],
            "chroma": {"key": [0, 1, 0], "tolerance": 0.3, "softness": 0.1, "spill": 0.2}}}))
        .apply(&json!({"op": "add_action", "clip": toned, "at": 0, "duration": SEC}));
    let action = {
        let value = handle.value();
        let clip = array(&value, "/clips")
            .iter()
            .find(|c| c["id"] == json!(toned))
            .cloned()
            .expect("the toned clip");
        let id = array(&clip, "/actions")[0]["id"]
            .as_u64()
            .expect("an action id");
        u32::try_from(id).expect("an id fits in u32")
    };
    let handle = handle.apply(
        &json!({"op": "set_action_end", "clip": toned, "action": action,
        "patch": {"video": {"color": {"saturation": 0.5, "vibrance": -0.5},
                            "wheels": {"gain": {"master": -0.4}},
                            "curves": {"red": [[0, 0.1], [1, 1]]},
                            "look": {"kind": "cool"}}}}),
    );

    let (handle, three) = add_track(handle);
    let (handle, inner) = graded_shape(handle, three, json!({"brightness": -0.2, "shadows": 0.4}));
    let handle = handle.apply(&json!({"op": "nest", "clips": [inner]}));

    let (handle, four) = add_track(handle);
    let (handle, _) = graded_shape(handle, four, json!({"exposure": -1.0, "whites": 0.3}));
    let handle = handle.apply(&json!({"op": "set_track", "track": four, "matte": "luma"}));

    let (handle, five) = add_track(handle);
    let handle = handle.apply(&json!({
        "op": "add_adjustment_clip", "track": five, "at": 0, "duration": 2 * SEC
    }));
    let adjustment = last_id(&handle, "/clips");
    handle.apply(&json!({"op": "set_video", "clips": [adjustment],
                         "patch": {"look": {"kind": "vivid"},
                                   "wheels": {"gamma": {"y": 0.5}},
                                   "curves": {"blue": [[0, 0], [0.5, 0.6], [1, 1]],
                                              "hue_sat": [[0, 0.5], [180, 1.5]]}}}))
}

/// `value` with every `video` object's `color`, `wheels`, `curves` and `look` removed,
/// at every depth.
fn without_grade(value: &Value) -> Value {
    match value {
        Value::Object(map) => Value::Object(
            map.iter()
                .map(|(key, item)| {
                    let mut item = without_grade(item);
                    if key == "video" {
                        if let Value::Object(video) = &mut item {
                            video.remove("color");
                            video.remove("wheels");
                            video.remove("curves");
                            video.remove("look");
                        }
                    }
                    (key.clone(), item)
                })
                .collect(),
        ),
        Value::Array(items) => Value::Array(items.iter().map(without_grade).collect()),
        other => other.clone(),
    }
}

/// The graded project's own neutral twin.
fn neutral(handle: &Handle) -> Handle {
    Handle::from_value(&without_grade(&handle.value()))
}

#[test]
fn the_fixture_grades_every_role_it_claims_to() {
    let value = graded().value();
    let text = value.to_string();
    let twin = without_grade(&value).to_string();
    assert!(text.contains("\"exposure\""), "{text}");
    assert!(!twin.contains("\"exposure\""), "{twin}");
    assert!(!twin.contains("\"vibrance\""), "{twin}");
    assert!(text.contains("\"look\""), "{text}");
    assert!(!twin.contains("\"look\""), "{twin}");
    assert!(text.contains("\"wheels\""), "{text}");
    assert!(!twin.contains("\"wheels\""), "{twin}");
    assert!(text.contains("\"curves\""), "{text}");
    assert!(!twin.contains("\"curves\""), "{twin}");
    let handle = graded();
    let recipe = handle.recipe(SEC / 2);
    let looked = array(&recipe, "/layers")
        .iter()
        .filter(|l| !l["look"].is_null())
        .count();
    assert_eq!(
        looked, 2,
        "the media clip's and the adjustment clip's looks"
    );
    let past = handle.recipe(3 * SEC / 2);
    assert_eq!(
        array(&past, "/layers")
            .iter()
            .filter(|l| !l["look"].is_null())
            .count(),
        3,
        "and the action's end gives the shape a look"
    );
    assert!(array(&recipe, "/mattes")
        .iter()
        .any(|m| m["mode"] == json!("luma")));
    assert!(array(&recipe, "/layers")
        .iter()
        .any(|l| !l["clip_rect"].is_null()));
}

#[test]
fn ungraded_is_the_recipe_of_the_same_project_with_every_grade_removed() {
    let handle = graded();
    let twin = neutral(&handle);
    for t in TIMES {
        let ungraded = handle
            .recipe_opts_text(t, r#"{"ungraded": true}"#)
            .expect("a recipe");
        assert_eq!(ungraded, twin.recipe_text(t), "at {t}");
        assert_ne!(ungraded, handle.recipe_text(t), "at {t}");
    }
}

#[test]
fn ungraded_keeps_every_other_key() {
    let handle = graded();
    let plain = handle.recipe(SEC / 2);
    let ungraded = handle.recipe_opts(SEC / 2, r#"{"ungraded": true}"#);
    let layers = array(&plain, "/layers");
    let stripped = array(&ungraded, "/layers");
    assert_eq!(layers.len(), stripped.len());
    for (a, b) in layers.iter().zip(stripped) {
        let (mut a, mut b) = (a.clone(), b.clone());
        for color in b["color"].as_object().expect("color").values() {
            assert_eq!(color, &json!(0.0), "{b}");
        }
        assert_eq!(b["look"], Value::Null, "{b}");
        for wheel in b["wheels"].as_object().expect("wheels").values() {
            for value in wheel.as_object().expect("a wheel").values() {
                assert_eq!(value, &json!(0.0), "{b}");
            }
        }
        a["color"] = Value::Null;
        b["color"] = Value::Null;
        let identity = |name: &str| match name {
            "hue_hue" => json!([[0.0, 0.0], [180.0, 0.0]]),
            "hue_sat" => json!([[0.0, 1.0], [180.0, 1.0]]),
            _ => json!([[0.0, 0.0], [1.0, 1.0]]),
        };
        let curves = b["curves"].as_object().expect("curves");
        assert_eq!(curves.len(), 6, "{b}");
        for (name, curve) in curves {
            assert_eq!(curve, &identity(name), "{b}");
        }
        a["wheels"] = Value::Null;
        b["wheels"] = Value::Null;
        a["curves"] = Value::Null;
        b["curves"] = Value::Null;
        a["look"] = Value::Null;
        assert_eq!(a, b);
    }
    assert_eq!(plain["mattes"], ungraded["mattes"]);
}

#[test]
fn the_option_off_or_misspelt_is_the_plain_recipe_byte_for_byte() {
    let handle = graded();
    for t in TIMES {
        let plain = handle.recipe_text(t);
        for opts in [
            r#"{"ungraded": false}"#,
            r#"{"ungraded": "yes"}"#,
            r#"{"ungraded": 1}"#,
            r#"{"ungraded": null}"#,
            "{}",
        ] {
            assert_eq!(
                handle.recipe_opts_text(t, opts).as_deref(),
                Some(plain.as_str()),
                "{opts} at {t}"
            );
        }
    }
}

#[test]
fn burn_in_and_ungraded_together_are_the_twin_burnt() {
    let handle = graded();
    let twin = neutral(&handle);
    for t in TIMES {
        assert_eq!(
            handle.recipe_opts_text(t, r#"{"burn_in_timecode": true, "ungraded": true}"#),
            twin.recipe_opts_text(t, r#"{"burn_in_timecode": true}"#),
            "at {t}"
        );
    }
}
