//! Black-box tests for the blend between curves of different point counts
//! (spec §11 GR-34), driven through the C FFI exactly as `ReelCore.swift`
//! drives it.
//!
//! Pinned here: inside an action, a channel whose held curve and end curve
//! are both non-identity with different counts is published in the recipe's
//! `curves` and `clip_state`'s `video.curves` as `{from, to, t}` (t the eased
//! progress), plain points at t = 0 and from the end on; a hue curve the
//! same; a same-count action (its midpoint not an identity) and an identity
//! aligned to the other's x's publish only points; an end the clamp removes
//! never blends; `ungraded` publishes the identity six; an adjustment clip's
//! layer blends; a split mid-blend stores only point lists and its tail
//! starts on the start curve; and a same-count channel beside a mismatched
//! one is lerped while the other blends. What a blend does to a pixel is
//! `tools/proof/curves_proof.py`'s (B1–B3).

mod common;

use serde_json::{json, Value};

use common::{at, Handle};

const SEC: i64 = 600_000;
const FROM: [[f64; 2]; 3] = [[0.0, 0.0], [0.5, 0.3], [1.0, 1.0]];
const TO: [[f64; 2]; 5] = [
    [0.0, 0.0],
    [0.2, 0.35],
    [0.45, 0.5],
    [0.75, 0.9],
    [1.0, 1.0],
];
const HUE_FROM: [[f64; 2]; 3] = [[0.0, 0.0], [120.0, 40.0], [240.0, 0.0]];
const HUE_TO: [[f64; 2]; 5] = [
    [0.0, 0.0],
    [60.0, -30.0],
    [120.0, 0.0],
    [200.0, 30.0],
    [300.0, 0.0],
];

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

fn set_curves(clip: u64, curves: Value) -> Value {
    json!({"op": "set_video", "clips": [clip], "patch": {"curves": curves}})
}

/// `clip` with a one-second action at 0 (id `action`) whose end sets `end`.
fn acting(base: Handle, clip: u64, action: u64, end: Value) -> Handle {
    base.apply(&json!({"op": "add_action", "clip": clip, "at": 0, "duration": SEC}))
        .apply(
            &json!({"op": "set_action_end", "clip": clip, "action": action,
                        "patch": {"video": {"curves": end}}}),
        )
}

/// Clip 10 with master `FROM` on its base and a one-second action to `TO`.
fn mismatched() -> Handle {
    let base = project().apply(&set_curves(10, json!({"master": FROM})));
    acting(base, 10, 20, json!({"master": TO}))
}

/// Clip `id`'s layer in the recipe at `t`.
fn layer(handle: &Handle, id: u64, t: i64) -> Value {
    handle.recipe(t)["layers"]
        .as_array()
        .and_then(|layers| layers.iter().find(|l| l["clip"] == json!(id)))
        .cloned()
        .unwrap_or_else(|| panic!("clip {id}'s layer"))
}

/// Clip `id`'s evaluated `video.curves` at `t`, as `clip_state` answers it.
fn state_curves(handle: &Handle, id: u32, t: i64) -> Value {
    at(
        &handle.clip_state(id, t).expect("the clip"),
        "/video/curves",
    )
    .clone()
}

fn blend(from: &[[f64; 2]], to: &[[f64; 2]], t: f64) -> Value {
    json!({"from": from, "to": to, "t": t})
}

/// A channel written as a list of `[x, y]` number pairs.
fn is_points(value: &Value) -> bool {
    value.as_array().is_some_and(|points| {
        points.len() >= 2
            && points.iter().all(|p| {
                p.as_array()
                    .is_some_and(|pair| pair.len() == 2 && pair.iter().all(Value::is_number))
            })
    })
}

/// Every channel of every curves object in the file — each clip's
/// `video.curves` and each action end's — with where it is.
fn stored_channels(value: &Value) -> Vec<(String, Value)> {
    let mut out = Vec::new();
    for clip in value["clips"].as_array().expect("clips") {
        let id = &clip["id"];
        if let Some(curves) = clip["video"].get("curves").and_then(Value::as_object) {
            for (name, channel) in curves {
                out.push((format!("clip {id} {name}"), channel.clone()));
            }
        }
        for action in clip["actions"].as_array().into_iter().flatten() {
            if let Some(curves) = action["end"]["video"]
                .get("curves")
                .and_then(Value::as_object)
            {
                for (name, channel) in curves {
                    out.push((format!("clip {id} end {name}"), channel.clone()));
                }
            }
        }
    }
    out
}

#[test]
fn a_three_to_five_master_action_blends_its_values() {
    let handle = mismatched();
    let identity = json!([[0.0, 0.0], [1.0, 1.0]]);
    // Its start is the start curve's points: today's bytes.
    assert_eq!(layer(&handle, 10, 0)["curves"]["master"], json!(FROM));
    // Halfway: the blend, every other channel still points.
    let mid = layer(&handle, 10, SEC / 2)["curves"].clone();
    assert_eq!(mid["master"], blend(&FROM, &TO, 0.5));
    let keys: Vec<&str> = mid["master"]
        .as_object()
        .expect("a blend")
        .keys()
        .map(String::as_str)
        .collect();
    assert_eq!(keys, ["from", "to", "t"]);
    for channel in ["red", "green", "blue"] {
        assert_eq!(mid[channel], identity, "{channel}");
    }
    assert_eq!(mid["hue_hue"], json!([[0.0, 0.0], [180.0, 0.0]]));
    assert_eq!(mid["hue_sat"], json!([[0.0, 1.0], [180.0, 1.0]]));
    // `clip_state` publishes the same object.
    assert_eq!(state_curves(&handle, 10, SEC / 2), mid);
    // The end is the end curve's points.
    assert_eq!(layer(&handle, 10, 2 * SEC)["curves"]["master"], json!(TO));
    assert_eq!(state_curves(&handle, 10, 2 * SEC)["master"], json!(TO));
}

#[test]
fn t_is_the_eased_progress() {
    let handle = mismatched().apply(&json!({"op": "set_action", "clip": 10, "action": 20,
                                            "curve": "ease_in"}));
    assert_eq!(
        layer(&handle, 10, SEC / 2)["curves"]["master"],
        blend(&FROM, &TO, 0.25)
    );
    assert_eq!(
        state_curves(&handle, 10, SEC / 2)["master"],
        blend(&FROM, &TO, 0.25)
    );
}

#[test]
fn a_hue_curve_of_another_count_blends_too() {
    let base = project().apply(&set_curves(10, json!({"hue_hue": HUE_FROM})));
    let handle = acting(base, 10, 20, json!({"hue_hue": HUE_TO}));
    assert_eq!(layer(&handle, 10, 0)["curves"]["hue_hue"], json!(HUE_FROM));
    assert_eq!(
        layer(&handle, 10, SEC / 2)["curves"]["hue_hue"],
        blend(&HUE_FROM, &HUE_TO, 0.5)
    );
    assert_eq!(
        state_curves(&handle, 10, SEC / 2)["hue_hue"],
        blend(&HUE_FROM, &HUE_TO, 0.5)
    );
    assert_eq!(
        layer(&handle, 10, 2 * SEC)["curves"]["hue_hue"],
        json!(HUE_TO)
    );
}

#[test]
fn a_same_count_or_an_aligned_action_publishes_only_points() {
    // Same count, different x's: the midpoint lerp is not an identity, so
    // the clamp keeps it and only the count test keeps it from blending.
    let base = project().apply(&set_curves(
        10,
        json!({"master": [[0, 0], [0.2, 0.6], [1, 1]]}),
    ));
    let same = acting(
        base,
        10,
        20,
        json!({"master": [[0, 0], [0.8, 0.5], [1, 1]]}),
    );
    let mid = layer(&same, 10, SEC / 2)["curves"]["master"].clone();
    assert!(is_points(&mid), "{mid}");
    let middle = &mid[1];
    assert!((middle[0].as_f64().unwrap() - 0.5).abs() < 1e-12, "{mid}");
    assert!((middle[1].as_f64().unwrap() - 0.55).abs() < 1e-12, "{mid}");
    assert_ne!(middle[0], middle[1], "the lerp must not be an identity");
    assert_eq!(state_curves(&same, 10, SEC / 2)["master"], mid);

    // From no curve: the identity takes the end's x's, and lerps per point.
    let aligned = acting(project(), 10, 20, json!({"master": TO}));
    let curves = layer(&aligned, 10, SEC / 2)["curves"].clone();
    for (name, channel) in curves.as_object().expect("curves") {
        assert!(is_points(channel), "{name}: {channel}");
    }
    assert_eq!(curves["master"].as_array().map(Vec::len), Some(5));
}

#[test]
fn an_end_the_clamp_removes_never_blends() {
    let base = project().apply(&set_curves(10, json!({"master": FROM})));
    let seventeen: Vec<Value> = (0..17)
        .map(|i| json!([f64::from(i) / 16.0, (f64::from(i) / 16.0).sqrt()]))
        .collect();
    let handle = acting(base, 10, 20, json!({"master": seventeen}));
    assert_eq!(layer(&handle, 10, SEC / 2)["curves"]["master"], json!(FROM));
    assert_eq!(state_curves(&handle, 10, SEC / 2)["master"], json!(FROM));
}

#[test]
fn ungraded_publishes_the_identity_six() {
    let handle = mismatched();
    let ungraded = handle.recipe_opts(SEC / 2, r#"{"ungraded": true}"#);
    let layers = ungraded["layers"].as_array().expect("layers");
    let identity = json!([[0.0, 0.0], [1.0, 1.0]]);
    assert_eq!(
        layers[0]["curves"],
        json!({"master": identity, "red": identity, "green": identity, "blue": identity,
               "hue_hue": [[0.0, 0.0], [180.0, 0.0]], "hue_sat": [[0.0, 1.0], [180.0, 1.0]]})
    );
}

#[test]
fn an_adjustment_clips_layer_blends() {
    // The new track takes id 20, the adjustment clip 21 and its action 22.
    let base = project()
        .apply(&json!({"op": "add_track"}))
        .apply(&json!({"op": "add_adjustment_clip", "track": 20, "at": 0, "duration": 2 * SEC}))
        .apply(&set_curves(21, json!({"master": FROM})));
    let handle = acting(base, 21, 22, json!({"master": TO}));
    assert_eq!(
        layer(&handle, 21, SEC / 2)["curves"]["master"],
        blend(&FROM, &TO, 0.5)
    );
}

#[test]
fn a_split_mid_blend_stores_only_points_and_its_tail_starts_on_the_start_curve() {
    let split = mismatched().apply(&json!({"op": "split", "clips": [10], "at": SEC / 2}));
    let value = split.value();
    let channels = stored_channels(&value);
    assert!(channels.len() >= 4, "{channels:?}");
    for (place, channel) in &channels {
        assert!(is_points(channel), "{place}: {channel}");
    }
    let tail = value["clips"]
        .as_array()
        .expect("clips")
        .iter()
        .find(|c| c["id"] != json!(10))
        .expect("the tail")
        .clone();
    assert_eq!(tail["video"]["curves"]["master"], json!(FROM));
    let tail_id = tail["id"].as_u64().expect("an id");
    assert_eq!(
        layer(&split, tail_id, SEC / 2)["curves"]["master"],
        json!(FROM)
    );
    // The tail's action still blends toward the end curve.
    let tail_mid = layer(&split, tail_id, SEC / 2 + SEC / 4)["curves"]["master"].clone();
    assert_eq!(tail_mid["from"], json!(FROM), "{tail_mid}");
    assert_eq!(tail_mid["to"], json!(TO), "{tail_mid}");
}

#[test]
fn a_same_count_master_beside_a_mismatched_red() {
    let base = project().apply(&set_curves(
        10,
        json!({"master": [[0, 0], [0.5, 0.4], [1, 1]], "red": FROM}),
    ));
    let handle = acting(
        base,
        10,
        20,
        json!({"master": [[0, 0], [0.5, 0.8], [1, 1]], "red": TO}),
    );
    let mid = layer(&handle, 10, SEC / 2)["curves"].clone();
    assert!(is_points(&mid["master"]), "{mid}");
    assert!(
        (mid["master"][1][1].as_f64().unwrap() - 0.6).abs() < 1e-12,
        "{mid}"
    );
    assert_eq!(mid["red"], blend(&FROM, &TO, 0.5));
    assert_eq!(state_curves(&handle, 10, SEC / 2), mid);
}
