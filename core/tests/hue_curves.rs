//! Black-box tests for the hue curves (spec §11 GR-32, format 20):
//! `video.curves.hue_hue` (a shift in degrees, −180…180, 0 neutral) and
//! `.hue_sat` (a gain, 0…2, 1 neutral), each 2–16 `[hue, value]` points with
//! 0 ≤ hue < 360, driven through the C FFI exactly as `ReelCore.swift`
//! drives it.
//!
//! Pinned here: a hue identity (every value neutral, whatever its x's)
//! absent from the file and an identity patch an identity; a curve stored as
//! written; the refusals in model then point order (count, x at least 0 and
//! below 360, the value range, x rising), every bound that is legal
//! accepted; an action between hue curves of one count lerping per point
//! (x linearly); an identity aligned to the other's x's with the neutral
//! value, both ways, and kept in an end patch; other count changes switching
//! at the end; an end clamped (x to 0…360 then a last x of 360 removed,
//! values to their range, x not rising removed); `ungraded` neutralising
//! both; and `paste_attributes` and an adjustment clip carrying them. What a
//! hue curve does to a pixel is `tools/proof/curves_proof.py`'s.

mod common;

use serde_json::{json, Value};

use common::{assert_contains, at, by_id, Handle, Outcome};

const SEC: i64 = 600_000;
const SHIFT_IDENTITY: [[f64; 2]; 2] = [[0.0, 0.0], [180.0, 0.0]];
const GAIN_IDENTITY: [[f64; 2]; 2] = [[0.0, 1.0], [180.0, 1.0]];

/// One media clip (10) on track 4, six seconds long, uncurved.
fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 20,
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

/// Clip 10 with a one-second action at 0 whose end patch is `end`.
fn acting(base: Handle, end: Value) -> Handle {
    base.apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 20,
                        "patch": {"video": {"curves": end}}}))
}

/// Every number of two point lists within 1e-9 of each other.
fn close(got: &Value, want: &[[f64; 2]]) -> bool {
    got.as_array().is_some_and(|points| {
        points.len() == want.len()
            && points.iter().zip(want).all(|(p, w)| {
                (0..2).all(|k| p[k].as_f64().is_some_and(|v| (v - w[k]).abs() < 1e-9))
            })
    })
}

#[test]
fn a_hue_identity_is_absent_and_an_identity_patch_is_an_identity() {
    let base = project();
    let written = base.to_json();
    for identity in [
        json!({"hue_hue": SHIFT_IDENTITY}),
        json!({"hue_hue": [[10, 0], [200, 0], [300, 0]]}),
        json!({"hue_sat": GAIN_IDENTITY}),
        json!({"hue_sat": [[5, 1], [359.9, 1]], "hue_hue": null}),
    ] {
        assert!(
            matches!(
                base.try_apply(&set_curves(identity.clone())),
                Ok(Outcome::Identity)
            ),
            "{identity}"
        );
    }
    let curved = base.apply(&set_curves(
        json!({"hue_hue": [[0, 0], [60, 0], [120, 40], [180, 0]],
               "hue_sat": [[0, 1], [120, 0], [240, 1]]}),
    ));
    assert_eq!(
        stored(&curved, 10),
        json!({"hue_hue": [[0.0, 0.0], [60.0, 0.0], [120.0, 40.0], [180.0, 0.0]],
               "hue_sat": [[0.0, 1.0], [120.0, 0.0], [240.0, 1.0]]})
    );
    // An identity list removes the channel; so does `null`.
    let straight = curved.apply(&set_curves(
        json!({"hue_hue": [[30, 0], [90, 0]], "hue_sat": null}),
    ));
    assert_eq!(straight.to_json(), written);
}

#[test]
fn the_refusals_in_model_then_point_order() {
    let base = project();
    let seventeen: Vec<Value> = (0..17).map(|i| json!([f64::from(i) * 20.0, 10])).collect();
    let cases = [
        (
            json!({"hue_hue": seventeen}),
            "video.curves.hue_hue needs 2 to 16 points, not 17",
        ),
        (
            json!({"hue_sat": [[0, 0.5]]}),
            "video.curves.hue_sat needs 2 to 16 points, not 1",
        ),
        (
            json!({"hue_hue": [[0, 0], [100, 10], [360, 0]]}),
            "video.curves.hue_hue[2].x must be at least 0 and below 360, not 360",
        ),
        (
            json!({"hue_sat": [[-1, 1], [100, 0.5]]}),
            "video.curves.hue_sat[0].x must be at least 0 and below 360, not -1",
        ),
        (
            json!({"hue_hue": [[0, 0], [100, 200]]}),
            "video.curves.hue_hue[1].y must be between -180 and 180, not 200",
        ),
        (
            json!({"hue_sat": [[0, 2.5], [100, 1]]}),
            "video.curves.hue_sat[0].y must be between 0 and 2, not 2.5",
        ),
        (
            json!({"hue_sat": [[0, -0.1], [100, 1]]}),
            "video.curves.hue_sat[0].y must be between 0 and 2, not -0.1",
        ),
        (
            json!({"hue_hue": [[0, 0], [120, 10], [90, 5]]}),
            "video.curves.hue_hue[2].x (90) must be greater than video.curves.hue_hue[1].x (120)",
        ),
        // Model order: master before hue_hue, hue_hue before hue_sat.
        (
            json!({"hue_hue": [[0, 500], [1, 0]], "master": [[2, 0], [1, 1]]}),
            "video.curves.master[0].x must be between 0 and 1, not 2",
        ),
        (
            json!({"hue_sat": [[0, 9], [1, 0]], "hue_hue": [[0, 500], [1, 0]]}),
            "video.curves.hue_hue[0].y must be between -180 and 180, not 500",
        ),
    ];
    for (patch, sentence) in cases {
        assert_contains(&base.errors(&set_curves(patch)), sentence);
    }
    // Every legal bound is accepted, exactly.
    let edges = base.apply(&set_curves(
        json!({"hue_hue": [[0, -180], [359.9, 180]], "hue_sat": [[0, 0], [359.99, 2]]}),
    ));
    assert_eq!(
        stored(&edges, 10),
        json!({"hue_hue": [[0.0, -180.0], [359.9, 180.0]],
               "hue_sat": [[0.0, 0.0], [359.99, 2.0]]})
    );
}

#[test]
fn an_action_between_hue_curves_of_one_count_lerps_per_point() {
    let base = project().apply(&set_curves(json!({"hue_hue": [[0, 0], [120, 40]]})));
    let handle = acting(base, json!({"hue_hue": [[20, 10], [200, -20]]}));
    assert!(close(
        &state(&handle, "hue_hue", SEC / 2),
        &[[10.0, 5.0], [160.0, 10.0]]
    ));
    assert!(close(
        &layer(&handle, 10, SEC / 2)["curves"]["hue_hue"],
        &[[10.0, 5.0], [160.0, 10.0]]
    ));
    assert!(close(
        &state(&handle, "hue_hue", 2 * SEC),
        &[[20.0, 10.0], [200.0, -20.0]]
    ));
}

#[test]
fn a_hue_identity_is_aligned_to_the_other_both_ways() {
    // From no curve: the identity takes the end's x's at the neutral.
    let from_none = acting(
        project(),
        json!({"hue_sat": [[0, 1], [60, 1], [120, 0], [180, 1]]}),
    );
    assert!(close(
        &state(&from_none, "hue_sat", SEC / 2),
        &[[0.0, 1.0], [60.0, 1.0], [120.0, 0.5], [180.0, 1.0]]
    ));
    let shifted = acting(
        project(),
        json!({"hue_hue": [[10, 40], [180, 0], [350, -20]]}),
    );
    assert!(close(
        &state(&shifted, "hue_hue", SEC / 2),
        &[[10.0, 20.0], [180.0, 0.0], [350.0, -10.0]]
    ));

    // To the identity: the end keeps its key, the middle is halfway, and the
    // end is uncurved.
    let base = project().apply(&set_curves(
        json!({"hue_hue": [[0, 0], [60, 0], [120, 40]]}),
    ));
    let to_none = acting(base, json!({"hue_hue": SHIFT_IDENTITY}));
    let value = to_none.value();
    assert_eq!(
        by_id(&value, "/clips", 10)["actions"][0]["end"],
        json!({"video": {"curves": {"hue_hue": [[0.0, 0.0], [180.0, 0.0]]}}})
    );
    assert!(close(
        &state(&to_none, "hue_hue", SEC / 2),
        &[[0.0, 0.0], [60.0, 0.0], [120.0, 20.0]]
    ));
    assert_eq!(
        layer(&to_none, 10, 2 * SEC)["curves"],
        layer(&project(), 10, 2 * SEC)["curves"]
    );
}

#[test]
fn other_count_changes_switch_at_the_end() {
    let base = project().apply(&set_curves(json!({"hue_sat": [[0, 0.5], [180, 1.5]]})));
    let handle = acting(base, json!({"hue_sat": [[0, 1], [120, 0], [240, 1]]}));
    assert!(close(
        &state(&handle, "hue_sat", SEC / 2),
        &[[0.0, 0.5], [180.0, 1.5]]
    ));
    assert!(close(
        &state(&handle, "hue_sat", 2 * SEC),
        &[[0.0, 1.0], [120.0, 0.0], [240.0, 1.0]]
    ));
}

#[test]
fn an_end_is_clamped() {
    let ends = acting(
        project(),
        json!({"hue_hue": [[-10, -300], [90, 40], [200, 300]],
               "hue_sat": [[0, 3], [100, -1], [400, 1]]}),
    );
    assert!(close(
        &state(&ends, "hue_hue", 2 * SEC),
        &[[0.0, -180.0], [90.0, 40.0], [200.0, 180.0]]
    ));
    // A last x clamped onto 360 removes the channel: the identity.
    assert!(close(&state(&ends, "hue_sat", 2 * SEC), &GAIN_IDENTITY));

    let falling = acting(project(), json!({"hue_hue": [[100, 10], [50, 20]]}));
    assert!(close(&state(&falling, "hue_hue", 2 * SEC), &SHIFT_IDENTITY));
    let tied = acting(
        project(),
        json!({"hue_sat": [[-20, 0.5], [-10, 0.2], [90, 1]]}),
    );
    assert!(close(&state(&tied, "hue_sat", 2 * SEC), &GAIN_IDENTITY));
}

#[test]
fn ungraded_neutralises_both() {
    let handle = project().apply(&set_curves(
        json!({"hue_hue": [[0, 30], [180, 0]], "hue_sat": [[0, 0.2], [180, 1]]}),
    ));
    let plain = layer(&handle, 10, SEC);
    assert!(close(
        &plain["curves"]["hue_hue"],
        &[[0.0, 30.0], [180.0, 0.0]]
    ));
    let ungraded = handle.recipe_opts(SEC, r#"{"ungraded": true}"#);
    let layers = ungraded["layers"].as_array().expect("layers");
    let curves = &layers[0]["curves"];
    assert!(close(&curves["hue_hue"], &SHIFT_IDENTITY), "{curves}");
    assert!(close(&curves["hue_sat"], &GAIN_IDENTITY), "{curves}");
}

#[test]
fn paste_and_an_adjustment_clip_carry_them() {
    let curves = json!({"hue_hue": [[0.0, 0.0], [120.0, 30.0]],
                        "hue_sat": [[0.0, 0.5], [180.0, 1.0]]});
    let payload = json!({"clips": [{
        "id": 1, "track": 0, "start": 0, "duration": 600000,
        "source": {"kind": "shape"},
        "video": {"curves": curves},
        "shape": {"kind": "rectangle", "width": 10, "height": 10}
    }]});
    let pasted = project().apply(&json!({"op": "paste_attributes", "clips": [10],
                                         "payload": payload}));
    assert_eq!(stored(&pasted, 10), curves);

    let adjusted = project()
        .apply(&json!({"op": "add_track"}))
        .apply(&json!({"op": "add_adjustment_clip", "track": 20, "at": 0, "duration": 2 * SEC}))
        .apply(&json!({"op": "set_video", "clips": [21],
                        "patch": {"curves": {"hue_sat": [[0, 0], [180, 2]]}}}));
    assert!(close(
        &layer(&adjusted, 21, SEC)["curves"]["hue_sat"],
        &[[0.0, 0.0], [180.0, 2.0]]
    ));
}
