//! Black-box tests for the wheels (spec §11 GR-11, format 16): `video.wheels
//! {lift, gamma, gain}`, each `{x, y, master}`, driven through the C FFI
//! exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: a neutral wheel absent from the written file and an all-zero
//! patch an identity; the written key order; each range's refusal and the
//! circle's, in their own sentences; a rim point made by `cos`/`sin` or by
//! dividing by `hypot` never refused (`WHEEL_RIM_TOLERANCE`) and one just
//! outside refused; a partial patch keeping its siblings; an action's lerp
//! and its end clamped onto the rim; `paste_attributes` carrying the wheels;
//! a split at a clamped end leaving a second clip that takes later edits;
//! an adjustment clip's wheels in the recipe; the recipe's `wheels` key
//! (all nine, between `color` and `look`); and an unknown key in an end
//! patch named. What a wheel does to a pixel is
//! `tools/proof/wheels_proof.py`'s.

mod common;

use serde_json::{json, Value};

use common::{assert_contains, at, by_id, num, Handle};

const SEC: i64 = 600_000;

/// One media clip (10) on track 4, six seconds long, unwheeled.
fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 15,
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

fn set_wheels(wheels: Value) -> Value {
    json!({"op": "set_video", "clips": [10], "patch": {"wheels": wheels}})
}

/// Clip `id`'s stored `video.wheels`, or `null` when the file has none.
fn stored(handle: &Handle, id: u64) -> Value {
    by_id(&handle.value(), "/clips", id)["video"]
        .get("wheels")
        .cloned()
        .unwrap_or(Value::Null)
}

/// Clip `id`'s layer in the recipe at `t`.
fn layer(handle: &Handle, id: u64, t: i64) -> Value {
    handle.recipe(t)["layers"]
        .as_array()
        .and_then(|layers| layers.iter().find(|l| l["clip"] == json!(id)))
        .cloned()
        .unwrap_or_else(|| panic!("clip {id}'s layer"))
}

/// The squared radius of `wheel` (an object with `x` and `y`).
fn radius2(wheel: &Value) -> f64 {
    let x = wheel["x"].as_f64().unwrap_or(0.0);
    let y = wheel["y"].as_f64().unwrap_or(0.0);
    x * x + y * y
}

#[test]
fn a_neutral_wheel_is_absent_and_an_all_zero_patch_is_an_identity() {
    let base = project();
    let written = base.to_json();
    assert!(!written.contains("\"wheels\""), "{written}");
    let pushed = base.apply(&set_wheels(json!({"lift": {"x": 0.2}})));
    assert_eq!(stored(&pushed, 10), json!({"lift": {"x": 0.2}}));
    // Back to 0: the key leaves the file again, and the text is the base's.
    let back = pushed.apply(&set_wheels(json!({"lift": {"x": 0}})));
    assert_eq!(back.to_json(), written);
    base.refuses(&set_wheels(json!({
        "lift": {"x": 0, "y": 0, "master": 0},
        "gamma": {"x": 0, "y": 0, "master": 0},
        "gain": {"x": 0, "y": 0, "master": 0}
    })));
}

#[test]
fn the_written_order_is_lift_gamma_gain_and_x_y_master() {
    let wheeled = project().apply(&set_wheels(json!({
        "gain": {"master": 0.5, "y": -0.25},
        "lift": {"master": -0.1, "x": 0.3},
        "gamma": {"y": 0.2}
    })));
    let wheels = stored(&wheeled, 10);
    let names: Vec<&str> = wheels
        .as_object()
        .expect("wheels")
        .keys()
        .map(String::as_str)
        .collect();
    assert_eq!(names, ["lift", "gamma", "gain"]);
    let keys = |name: &str| -> Vec<String> {
        wheels[name]
            .as_object()
            .expect("a wheel")
            .keys()
            .cloned()
            .collect()
    };
    assert_eq!(keys("lift"), ["x", "master"]);
    assert_eq!(keys("gamma"), ["y"]);
    assert_eq!(keys("gain"), ["y", "master"]);
    // `wheels` sits before `look` in the video group's text.
    let looked = wheeled.apply(&json!({"op": "set_video", "clips": [10],
                                      "patch": {"look": {"kind": "warm"}}}));
    let text = looked.to_json();
    let w = text.find("\"wheels\"").expect("wheels written");
    let l = text.find("\"look\"").expect("look written");
    assert!(w < l, "{text}");
}

#[test]
fn each_range_and_the_circle_are_refused_in_their_own_sentences() {
    let base = project();
    for name in ["lift", "gamma", "gain"] {
        for (key, value) in [("x", 1.5), ("x", -1.01), ("y", 2.0), ("master", -1.5)] {
            assert_contains(
                &base.errors(&set_wheels(json!({ name: { key: value } }))),
                &format!("video.wheels.{name}.{key} must be between -1 and 1, not {value}"),
            );
        }
        assert_contains(
            &base.errors(&set_wheels(json!({ name: {"x": 0.9, "y": 0.6} }))),
            &format!(
                "video.wheels.{name} must lie inside the unit circle (x² + y² ≤ 1), not x 0.9, y 0.6"
            ),
        );
        // Every end of every range is legal.
        for key in ["x", "y", "master"] {
            for value in [-1.0, 1.0] {
                let set = base.apply(&set_wheels(json!({ name: { key: value } })));
                assert_eq!(num(&stored(&set, 10), &format!("/{name}/{key}")), value);
            }
        }
    }
}

#[test]
fn a_rim_point_is_never_refused_and_one_just_outside_is() {
    let base = project();
    let mut over = 0;
    for k in 0..720 {
        let theta = std::f64::consts::TAU * f64::from(k) / 720.0;
        let (x, y) = (theta.cos(), theta.sin());
        if x * x + y * y > 1.0 {
            over += 1;
        }
        base.apply(&set_wheels(json!({"gain": {"x": x, "y": y}})));
    }
    // A pseudo-random walk of points scaled onto the rim by their hypot,
    // the inspector's clamp and `clamp_wheels`' own arithmetic.
    let mut seed: u64 = 0x5eed_1234_abcd_0042;
    let mut next = || {
        seed = seed
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        (seed >> 11) as f64 / (1u64 << 53) as f64 * 2.0 - 1.0
    };
    for _ in 0..720 {
        let (x, y) = (next(), next());
        let r = x.hypot(y);
        if r == 0.0 {
            continue;
        }
        let (x, y) = (x / r, y / r);
        if x * x + y * y > 1.0 {
            over += 1;
        }
        base.apply(&set_wheels(json!({"lift": {"x": x, "y": y}})));
    }
    assert!(
        over > 0,
        "no rim point landed past 1, so nothing was tested"
    );
    let r = 1.0 + 1e-6;
    let (x, y) = (r * 0.6, r * 0.8);
    assert_contains(
        &base.errors(&set_wheels(json!({"gamma": {"x": x, "y": y}}))),
        "video.wheels.gamma must lie inside the unit circle (x² + y² ≤ 1)",
    );
}

#[test]
fn a_partial_patch_keeps_its_siblings() {
    let handle = project()
        .apply(&set_wheels(
            json!({"lift": {"x": 0.2, "y": 0.1, "master": 0.3}, "gain": {"master": -0.2}}),
        ))
        .apply(&set_wheels(json!({"lift": {"master": 0.5}})));
    assert_eq!(
        stored(&handle, 10),
        json!({"lift": {"x": 0.2, "y": 0.1, "master": 0.5}, "gain": {"master": -0.2}})
    );
}

#[test]
fn an_action_lerps_and_its_end_is_clamped_onto_the_rim() {
    let handle = project()
        .apply(&json!({"op": "add_action", "clip": 10, "at": SEC, "duration": 2 * SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 20,
                        "patch": {"video": {"wheels": {"lift": {"x": 0.6}}}}}));
    let x = |t: i64| {
        num(
            &handle.clip_state(10, t).expect("clip 10"),
            "/video/wheels/lift/x",
        )
    };
    assert_eq!(x(SEC), 0.0);
    assert!((x(2 * SEC) - 0.3).abs() < 1e-9, "{}", x(2 * SEC));
    assert_eq!(x(3 * SEC), 0.6);
    // The recipe carries the same numbers.
    assert!((num(&layer(&handle, 10, 2 * SEC), "/wheels/lift/x") - 0.3).abs() < 1e-9);

    // An end outside the circle and the master's range is clamped: onto
    // the rim along its own angle, the master to ±1, a NaN never stored.
    let wild = project()
        .apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 20,
                        "patch": {"video": {"wheels": {"gain": {"x": 0.9, "y": 0.9,
                                                                 "master": 3}}}}}));
    let state = wild.clip_state(10, 2 * SEC).expect("clip 10");
    let gain = at(&state, "/video/wheels/gain");
    assert!(radius2(gain) <= 1.0 + 1e-9, "{gain}");
    assert!((num(gain, "/x") - std::f64::consts::FRAC_1_SQRT_2).abs() < 1e-12);
    assert_eq!(num(gain, "/x"), num(gain, "/y"));
    assert_eq!(num(gain, "/master"), 1.0);
}

#[test]
fn paste_attributes_carries_the_wheels_with_the_video_group() {
    let wheels = json!({"lift": {"x": 0.3, "y": -0.2, "master": 0.1}, "gain": {"master": -0.4}});
    let payload = json!({"clips": [{
        "id": 1, "track": 0, "start": 0, "duration": 600000,
        "source": {"kind": "shape"},
        "video": {"wheels": wheels},
        "shape": {"kind": "rectangle", "width": 10, "height": 10}
    }]});
    let after = project().apply(&json!({"op": "paste_attributes", "clips": [10],
                                        "payload": payload}));
    assert_eq!(stored(&after, 10), wheels);
}

#[test]
fn a_split_at_a_clamped_end_leaves_a_clip_that_takes_later_edits() {
    // The end (0.9, 0.9) evaluates onto the rim by its hypot — a point whose
    // x² + y² is an ulp over 1 — and the split writes it as the tail's base.
    let handle = project()
        .apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": 2 * SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 20,
                        "patch": {"video": {"wheels": {"lift": {"x": 0.9, "y": 0.9}}}}}))
        .apply(&json!({"op": "split", "clips": [10], "at": 3 * SEC}));
    let value = handle.value();
    let tail = value["clips"]
        .as_array()
        .expect("clips")
        .iter()
        .find(|c| c["id"] != json!(10))
        .expect("the tail")
        .clone();
    let tail_id = tail["id"].as_u64().expect("an id");
    let lift = &tail["video"]["wheels"]["lift"];
    assert!(radius2(lift) > 1.0, "the fixture is an ulp past 1: {lift}");
    assert!(radius2(lift) <= 1.0 + 1e-9, "{lift}");
    let edited = handle.apply(&json!({"op": "set_video", "clips": [tail_id],
                                      "patch": {"wheels": {"gain": {"master": 0.2}}}}));
    assert_eq!(num(&stored(&edited, tail_id), "/gain/master"), 0.2);
    let payload = json!({"clips": [{
        "id": 1, "track": 0, "start": 0, "duration": 600000,
        "source": {"kind": "shape"},
        "video": {"wheels": {"lift": lift.clone(), "gain": {"master": 0.3}}},
        "shape": {"kind": "rectangle", "width": 10, "height": 10}
    }]});
    let pasted = handle.apply(&json!({"op": "paste_attributes", "clips": [tail_id],
                                      "payload": payload}));
    assert_eq!(stored(&pasted, tail_id)["lift"], *lift);
    assert_eq!(num(&stored(&pasted, tail_id), "/gain/master"), 0.3);
}

#[test]
fn an_adjustment_clip_carries_its_wheels_into_the_recipe() {
    // The new track takes id 20 and the adjustment clip 21 (`next_id`).
    let handle = project()
        .apply(&json!({"op": "add_track"}))
        .apply(&json!({"op": "add_adjustment_clip", "track": 20, "at": 0, "duration": 2 * SEC}));
    let adjustment = 21;
    assert_eq!(
        by_id(&handle.value(), "/clips", adjustment)["source"],
        json!({"kind": "adjustment"})
    );
    let graded = handle.apply(&json!({"op": "set_video", "clips": [adjustment],
                                      "patch": {"wheels": {"gain": {"master": 0.5}}}}));
    assert_eq!(
        stored(&graded, adjustment),
        json!({"gain": {"master": 0.5}})
    );
    assert_eq!(
        num(&layer(&graded, adjustment, SEC), "/wheels/gain/master"),
        0.5
    );
}

#[test]
fn the_recipe_carries_all_nine_between_color_and_look() {
    let handle = project().apply(&set_wheels(json!({"gamma": {"y": -0.3}})));
    let layer = layer(&handle, 10, SEC);
    let keys: Vec<&str> = layer
        .as_object()
        .expect("a layer")
        .keys()
        .map(String::as_str)
        .collect();
    let color = keys.iter().position(|k| *k == "color").expect("color");
    assert_eq!(keys[color + 1], "wheels");
    assert_eq!(keys[color + 2], "look");
    assert_eq!(
        layer["wheels"],
        json!({"lift": {"x": 0.0, "y": 0.0, "master": 0.0},
               "gamma": {"x": 0.0, "y": -0.3, "master": 0.0},
               "gain": {"x": 0.0, "y": 0.0, "master": 0.0}})
    );
    // And an unwheeled clip's layer has all nine at 0.
    let plain = self::layer(&project(), 10, SEC);
    for wheel in plain["wheels"].as_object().expect("wheels").values() {
        for value in wheel.as_object().expect("a wheel").values() {
            assert_eq!(value, &json!(0.0));
        }
    }
}

#[test]
fn an_unknown_key_in_a_patch_or_an_end_is_named() {
    let base = project();
    assert_contains(
        &base.errors(&set_wheels(json!({"lift": {"z": 1}}))),
        "unknown key \"wheels.lift.z\" in a video patch",
    );
    let acting = base.apply(&json!({"op": "add_action", "clip": 10, "at": 0,
                                    "duration": SEC}));
    assert_contains(
        &acting.errors(&json!({"op": "set_action_end", "clip": 10, "action": 20,
                               "patch": {"video": {"wheels": {"offset": {"x": 0.1}}}}})),
        "wheels.offset",
    );
}
