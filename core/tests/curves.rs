//! Black-box tests for the curves (spec §11 GR-12, format 17): `video.curves
//! {master, red, green, blue}`, each 2–16 `[x, y]` points, driven through the
//! C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the identity absent from the written file, an identity patch
//! an identity, `null` removing a channel and a list replacing one whole;
//! the three sentences, in model then point order, and a point at exactly 0
//! and 1 accepted; an action between curves of one count lerping per point;
//! an identity curve (absent included) aligned to the other's x's, both
//! ways, and kept in an end patch as "animate to neutral"; other count
//! changes switching at the end; an end clamped (a point out of range, a
//! count out of range, x falling); the recipe's `curves` key (all four,
//! after `wheels`); `paste_attributes`, an adjustment clip and a split
//! carrying the curves; and an unknown channel named. What a curve does to
//! a pixel is `tools/proof/curves_proof.py`'s.

mod common;

use serde_json::{json, Value};

use common::{assert_contains, at, by_id, Handle, Outcome};

const SEC: i64 = 600_000;

/// One media clip (10) on track 4, six seconds long, uncurved.
fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 17,
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

fn set_curves(curves: Value) -> Value {
    json!({"op": "set_video", "clips": [10], "patch": {"curves": curves}})
}

/// Clip `id`'s stored `video.curves`, or `null` when the file has none.
fn stored(handle: &Handle, id: u64) -> Value {
    by_id(&handle.value(), "/clips", id)["video"]
        .get("curves")
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

/// Clip 10's evaluated `channel` at `t`, as `clip_state` answers it.
fn state(handle: &Handle, channel: &str, t: i64) -> Value {
    at(
        &handle.clip_state(10, t).expect("clip 10"),
        &format!("/video/curves/{channel}"),
    )
    .clone()
}

/// The middle point's y of a three-point curve.
fn middle_y(curve: &Value) -> f64 {
    curve[1][1].as_f64().expect("a middle y")
}

/// Clip 10 with a one-second action at 0 whose end patch is `end`.
fn acting(base: Handle, end: Value) -> Handle {
    base.apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 20,
                        "patch": {"video": {"curves": end}}}))
}

fn identity_answer(handle: &Handle, op: &Value) -> bool {
    matches!(handle.try_apply(op), Ok(Outcome::Identity))
}

#[test]
fn the_identity_is_absent_and_an_identity_patch_is_an_identity() {
    let base = project();
    let written = base.to_json();
    assert!(!written.contains("\"curves\""), "{written}");
    for identity in [
        json!({"master": [[0, 0], [1, 1]]}),
        json!({"master": [[0, 0], [0.5, 0.5], [1, 1]]}),
        json!({"red": [[0, 0], [0.25, 0.25], [0.75, 0.75], [1, 1]], "blue": null}),
    ] {
        assert!(
            identity_answer(&base, &set_curves(identity.clone())),
            "{identity}"
        );
    }
    let curved = base.apply(&set_curves(json!({"red": [[0, 0], [0.5, 0.7], [1, 1]]})));
    assert_eq!(
        stored(&curved, 10),
        json!({"red": [[0.0, 0.0], [0.5, 0.7], [1.0, 1.0]]})
    );
    // A list replaces whole; an identity list removes the channel; so does
    // `null`; and the text is the base's again.
    let replaced = curved.apply(&set_curves(json!({"red": [[0, 0.1], [1, 0.9]]})));
    assert_eq!(
        stored(&replaced, 10),
        json!({"red": [[0.0, 0.1], [1.0, 0.9]]})
    );
    let straight = replaced.apply(&set_curves(json!({"red": [[0, 0], [0.4, 0.4], [1, 1]]})));
    assert_eq!(straight.to_json(), written);
    let removed = replaced.apply(&set_curves(json!({"red": null})));
    assert_eq!(removed.to_json(), written);
}

#[test]
fn the_three_sentences_in_model_then_point_order() {
    let base = project();
    let seventeen: Vec<Value> = (0..17)
        .map(|i| json!([f64::from(i) / 16.0, f64::from(i) / 16.0]))
        .collect();
    assert_contains(
        &base.errors(&set_curves(json!({"red": seventeen}))),
        "video.curves.red needs 2 to 16 points, not 17",
    );
    assert_contains(
        &base.errors(&set_curves(json!({"red": [[0, 0]]}))),
        "video.curves.red needs 2 to 16 points, not 1",
    );
    assert_contains(
        &base.errors(&set_curves(json!({"red": [[0, 0], [0.5, 0.5], [1.2, 1]]}))),
        "video.curves.red[2].x must be between 0 and 1, not 1.2",
    );
    assert_contains(
        &base.errors(&set_curves(json!({"green": [[0, -0.1], [1, 1]]}))),
        "video.curves.green[0].y must be between 0 and 1, not -0.1",
    );
    assert_contains(
        &base.errors(&set_curves(
            json!({"master": [[0, 0], [0.5, 0.3], [0.4, 0.6], [1, 1]]}),
        )),
        "video.curves.master[2].x (0.4) must be greater than video.curves.master[1].x (0.5)",
    );
    assert_contains(
        &base.errors(&set_curves(
            json!({"blue": [[0, 0], [0.5, 0.3], [0.5, 0.6], [1, 1]]}),
        )),
        "video.curves.blue[2].x (0.5) must be greater than video.curves.blue[1].x (0.5)",
    );
    // Model order: master before red, whichever the patch names first.
    assert_contains(
        &base.errors(&set_curves(
            json!({"red": [[0, 0]], "master": [[2, 0], [1, 1]]}),
        )),
        "video.curves.master[0].x must be between 0 and 1, not 2",
    );
    // Every bound is legal, exactly.
    let edges = base.apply(&set_curves(json!({"green": [[0, 1], [1, 0]],
                                              "blue": [[0, 0], [0.5, 1], [1, 1]]})));
    assert_eq!(
        stored(&edges, 10),
        json!({"green": [[0.0, 1.0], [1.0, 0.0]], "blue": [[0.0, 0.0], [0.5, 1.0], [1.0, 1.0]]})
    );
    let sixteen: Vec<Value> = (0..16)
        .map(|i| json!([f64::from(i) / 15.0, (f64::from(i) / 15.0).powi(2)]))
        .collect();
    base.apply(&set_curves(json!({"master": sixteen})));
}

#[test]
fn an_action_between_curves_of_one_count_lerps_per_point() {
    let base = project().apply(&set_curves(json!({"master": [[0, 0], [0.5, 0.4], [1, 1]]})));
    let handle = acting(base, json!({"master": [[0, 0], [0.5, 0.8], [1, 1]]}));
    assert!((middle_y(&state(&handle, "master", 0)) - 0.4).abs() < 1e-12);
    assert!((middle_y(&state(&handle, "master", SEC / 2)) - 0.6).abs() < 1e-12);
    assert!((middle_y(&state(&handle, "master", 2 * SEC)) - 0.8).abs() < 1e-12);
    // The recipe carries the same numbers.
    let mid = layer(&handle, 10, SEC / 2);
    assert!((middle_y(&mid["curves"]["master"]) - 0.6).abs() < 1e-12);
}

#[test]
fn an_identity_curve_is_aligned_to_the_other_both_ways() {
    // From no curve: the identity takes the end's x's.
    let from_none = acting(project(), json!({"master": [[0, 0], [0.5, 0.8], [1, 1]]}));
    let mid = state(&from_none, "master", SEC / 2);
    assert_eq!(mid.as_array().map(Vec::len), Some(3), "{mid}");
    assert!((middle_y(&mid) - 0.65).abs() < 1e-12, "{mid}");
    assert_eq!(mid[0], json!([0.0, 0.0]));
    assert_eq!(mid[2], json!([1.0, 1.0]));

    // To the identity: the end keeps its key ("animate to neutral"), the
    // middle is halfway, and the end is uncurved.
    let base = project().apply(&set_curves(json!({"master": [[0, 0], [0.5, 0.8], [1, 1]]})));
    let to_none = acting(base, json!({"master": [[0, 0], [1, 1]]}));
    let value = to_none.value();
    let action = &by_id(&value, "/clips", 10)["actions"][0];
    assert_eq!(
        action["end"],
        json!({"video": {"curves": {"master": [[0, 0], [1, 1]]}}})
    );
    assert!((middle_y(&state(&to_none, "master", SEC / 2)) - 0.65).abs() < 1e-12);
    assert_eq!(
        state(&to_none, "master", 2 * SEC),
        json!([[0.0, 0.0], [1.0, 1.0]])
    );
    assert_eq!(
        layer(&to_none, 10, 2 * SEC)["curves"],
        layer(&project(), 10, 2 * SEC)["curves"]
    );

    // The aligned identity takes the other's interior x's, its ends at 0
    // and 1 even when the other's are not.
    let offset = acting(
        project(),
        json!({"red": [[0.1, 0.2], [0.3, 0.5], [0.6, 0.7], [0.9, 0.95]]}),
    );
    let mid = state(&offset, "red", SEC / 2);
    let want = [[0.05, 0.1], [0.3, 0.4], [0.6, 0.65], [0.95, 0.975]];
    for (got, want) in mid.as_array().expect("points").iter().zip(want) {
        for k in 0..2 {
            assert!((got[k].as_f64().unwrap() - want[k]).abs() < 1e-12, "{mid}");
        }
    }
}

#[test]
fn other_count_changes_switch_at_the_end() {
    let base = project().apply(&set_curves(json!({"master": [[0, 0.1], [1, 0.9]]})));
    let handle = acting(base, json!({"master": [[0, 0], [0.5, 0.8], [1, 1]]}));
    assert_eq!(
        state(&handle, "master", SEC / 2),
        json!([[0.0, 0.1], [1.0, 0.9]])
    );
    assert_eq!(
        state(&handle, "master", 2 * SEC),
        json!([[0.0, 0.0], [0.5, 0.8], [1.0, 1.0]])
    );
}

#[test]
fn an_end_is_clamped() {
    let ends = acting(
        project(),
        json!({
            "master": [[-0.5, -1], [0.5, 0.6], [1.5, 2]],
            "red": (0..17).map(|i| json!([f64::from(i) / 16.0, 0.5])).collect::<Vec<_>>(),
            "green": [[0, 0], [0.5, 0.5], [0.4, 0.9], [1, 1]],
            "blue": [[-0.2, 0.1], [-0.1, 0.2], [1, 1]]
        }),
    );
    assert_eq!(
        state(&ends, "master", 2 * SEC),
        json!([[0.0, 0.0], [0.5, 0.6], [1.0, 1.0]])
    );
    // Too many points, x falling, and x tied at 0 after the clamp: removed,
    // so the channel is the identity.
    for channel in ["red", "green", "blue"] {
        assert_eq!(
            state(&ends, channel, 2 * SEC),
            json!([[0.0, 0.0], [1.0, 1.0]]),
            "{channel}"
        );
    }
}

#[test]
fn the_recipe_carries_all_four_after_the_wheels() {
    let handle = project().apply(&set_curves(json!({"green": [[0, 0.1], [1, 1]]})));
    let layer = layer(&handle, 10, SEC);
    let keys: Vec<&str> = layer
        .as_object()
        .expect("a layer")
        .keys()
        .map(String::as_str)
        .collect();
    let wheels = keys.iter().position(|k| *k == "wheels").expect("wheels");
    assert_eq!(keys[wheels + 1], "curves");
    assert_eq!(keys[wheels + 2], "look");
    let identity = json!([[0.0, 0.0], [1.0, 1.0]]);
    assert_eq!(
        layer["curves"],
        json!({"master": identity, "red": identity, "green": [[0.0, 0.1], [1.0, 1.0]],
               "blue": identity})
    );
    let plain = self::layer(&project(), 10, SEC);
    assert_eq!(
        plain["curves"],
        json!({"master": identity, "red": identity, "green": identity, "blue": identity})
    );
}

#[test]
fn paste_an_adjustment_clip_and_a_split_carry_the_curves() {
    let curves = json!({"master": [[0.0, 0.0], [0.5, 0.3], [1.0, 1.0]],
                        "blue": [[0.0, 0.2], [1.0, 1.0]]});
    let payload = json!({"clips": [{
        "id": 1, "track": 0, "start": 0, "duration": 600000,
        "source": {"kind": "shape"},
        "video": {"curves": curves},
        "shape": {"kind": "rectangle", "width": 10, "height": 10}
    }]});
    let pasted = project().apply(&json!({"op": "paste_attributes", "clips": [10],
                                         "payload": payload}));
    assert_eq!(stored(&pasted, 10), curves);

    // The new track takes id 20 and the adjustment clip 21 (`next_id`).
    let adjusted = project()
        .apply(&json!({"op": "add_track"}))
        .apply(&json!({"op": "add_adjustment_clip", "track": 20, "at": 0, "duration": 2 * SEC}))
        .apply(&json!({"op": "set_video", "clips": [21],
                        "patch": {"curves": {"red": [[0, 0], [0.5, 0.7], [1, 1]]}}}));
    assert_eq!(
        stored(&adjusted, 21),
        json!({"red": [[0.0, 0.0], [0.5, 0.7], [1.0, 1.0]]})
    );
    assert_eq!(
        layer(&adjusted, 21, SEC)["curves"]["red"],
        json!([[0.0, 0.0], [0.5, 0.7], [1.0, 1.0]])
    );

    // A split mid-action writes the evaluated curve as the tail's base, and
    // the tail takes later edits.
    let split = acting(project(), json!({"master": [[0, 0], [0.5, 0.8], [1, 1]]}))
        .apply(&json!({"op": "split", "clips": [10], "at": SEC / 2}));
    let value = split.value();
    let tail = value["clips"]
        .as_array()
        .expect("clips")
        .iter()
        .find(|c| c["id"] != json!(10))
        .expect("the tail")
        .clone();
    let tail_id = tail["id"].as_u64().expect("an id");
    assert!((middle_y(&tail["video"]["curves"]["master"]) - 0.65).abs() < 1e-12);
    let edited = split.apply(&json!({"op": "set_video", "clips": [tail_id],
                                     "patch": {"curves": {"red": [[0, 0.1], [1, 1]]}}}));
    assert_eq!(
        stored(&edited, tail_id)["red"],
        json!([[0.0, 0.1], [1.0, 1.0]])
    );
}

#[test]
fn an_unknown_channel_in_a_patch_or_an_end_is_named() {
    let base = project();
    assert_contains(
        &base.errors(&set_curves(json!({"alpha": [[0, 0], [1, 1]]}))),
        "unknown key \"curves.alpha\" in a video patch",
    );
    let acting = base.apply(&json!({"op": "add_action", "clip": 10, "at": 0,
                                    "duration": SEC}));
    assert_contains(
        &acting.errors(&json!({"op": "set_action_end", "clip": 10, "action": 20,
                               "patch": {"video": {"curves": {"luma": [[0, 0], [1, 1]]}}}})),
        "curves.luma",
    );
}
