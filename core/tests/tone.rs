//! Black-box tests for tone (spec §11 GR-2, format 1015 on the grading
//! branch): nine keys on `video.color` after `hue`, driven through the C FFI
//! exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: each key's range, refused in its own sentence at both ends;
//! a neutral key absent from the written file and present everywhere a key
//! is walked (an action's interpolation, the patch template, the recipe,
//! `clip_state`, `split`); an action from neutral reaching halfway at
//! mid-span; `paste_attributes` carrying tone with the video group. What
//! tone does to a pixel is `tools/proof/tone_proof.py`'s.

mod common;

use serde_json::{json, Value};

use common::{assert_contains, at, by_id, num, Handle};

const SEC: i64 = 600_000;

/// One media clip (10) on track 4, six seconds long, untoned.
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

fn set_color(color: Value) -> Value {
    json!({"op": "set_video", "clips": [10], "patch": {"color": color}})
}

const TONE: [&str; 9] = [
    "exposure",
    "temperature",
    "tint",
    "highlights",
    "shadows",
    "whites",
    "blacks",
    "vibrance",
    "fade",
];

const THIRTEEN: [&str; 13] = [
    "brightness",
    "contrast",
    "saturation",
    "hue",
    "exposure",
    "temperature",
    "tint",
    "highlights",
    "shadows",
    "whites",
    "blacks",
    "vibrance",
    "fade",
];

#[test]
fn each_tone_key_is_refused_past_either_end_in_its_own_sentence() {
    let base = project();
    let cases: [(&str, f64, f64, &str, &str); 9] = [
        ("exposure", 3.5, -3.25, "-3", "3"),
        ("temperature", 1.5, -1.5, "-1", "1"),
        ("tint", 1.01, -1.01, "-1", "1"),
        ("highlights", 2.0, -2.0, "-1", "1"),
        ("shadows", 2.0, -2.0, "-1", "1"),
        ("whites", 2.0, -2.0, "-1", "1"),
        ("blacks", 2.0, -2.0, "-1", "1"),
        ("vibrance", 2.0, -2.0, "-1", "1"),
        ("fade", 1.5, -0.1, "0", "1"),
    ];
    for (key, over, under, low, high) in cases {
        for value in [over, under] {
            assert_contains(
                &base.errors(&set_color(json!({ key: value }))),
                &format!("video.color.{key} must be between {low} and {high}, not {value}"),
            );
        }
        // Both ends are legal.
        let low: f64 = low.parse().unwrap();
        let high: f64 = high.parse().unwrap();
        for value in [low, high] {
            if value != 0.0 {
                let toned = base.apply(&set_color(json!({ key: value })));
                assert_eq!(
                    num(&toned.value(), &format!("/clips/0/video/color/{key}")),
                    value
                );
            }
        }
    }
}

#[test]
fn a_neutral_key_is_absent_from_the_file_and_a_set_one_follows_hue() {
    let base = project();
    let written = base.to_json();
    for key in TONE {
        assert!(
            !written.contains(&format!("\"{key}\"")),
            "{key} in:\n{written}"
        );
    }
    let toned = base.apply(&set_color(json!({"fade": 0.5, "exposure": 1.0})));
    let color = at(&toned.value(), "/clips/0/video/color").clone();
    let keys: Vec<&str> = color
        .as_object()
        .expect("color is an object")
        .keys()
        .map(String::as_str)
        .collect();
    assert_eq!(
        keys,
        [
            "brightness",
            "contrast",
            "saturation",
            "hue",
            "exposure",
            "fade"
        ]
    );
    // Back to 0: the key leaves the file again, and the text is the base's.
    let back = toned.apply(&set_color(json!({"fade": 0, "exposure": 0})));
    assert_eq!(back.to_json(), written);
    // An all-zero patch on a neutral clip changes nothing.
    base.refuses(&set_color(json!({
        "exposure": 0, "temperature": 0, "tint": 0, "highlights": 0, "shadows": 0,
        "whites": 0, "blacks": 0, "vibrance": 0, "fade": 0
    })));
}

#[test]
fn an_action_from_neutral_is_halfway_at_mid_span() {
    // A new action's curve is linear.
    let handle = project()
        .apply(&json!({"op": "add_action", "clip": 10, "at": SEC, "duration": 2 * SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 20,
                        "patch": {"video": {"color": {"exposure": 1}}}}));
    let exposure = |t: i64| {
        num(
            &handle.clip_state(10, t).expect("clip 10"),
            "/video/color/exposure",
        )
    };
    assert_eq!(exposure(SEC), 0.0);
    assert!(
        (exposure(2 * SEC) - 0.5).abs() < 1e-9,
        "{}",
        exposure(2 * SEC)
    );
    assert_eq!(exposure(3 * SEC), 1.0);
    assert_eq!(exposure(5 * SEC), 1.0);
}

#[test]
fn the_recipe_carries_all_thirteen_and_clip_state_equals_it() {
    let handle = project()
        .apply(&set_color(json!({"temperature": 0.25})))
        .apply(&json!({"op": "add_action", "clip": 10, "at": SEC, "duration": 2 * SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 20,
                        "patch": {"video": {"color": {"vibrance": -0.5}}}}));
    for t in [0, 2 * SEC, 4 * SEC] {
        let recipe = handle.recipe(t);
        let layer = recipe["layers"]
            .as_array()
            .and_then(|layers| layers.iter().find(|l| l["clip"] == json!(10)))
            .expect("clip 10's layer")
            .clone();
        let keys: Vec<&str> = layer["color"]
            .as_object()
            .expect("color is an object")
            .keys()
            .map(String::as_str)
            .collect();
        assert_eq!(keys, THIRTEEN, "at {t}");
        assert_eq!(layer["color"]["temperature"], json!(0.25), "at {t}");
        let state = handle.clip_state(10, t).expect("clip 10");
        assert_eq!(state["video"]["color"], layer["color"], "at {t}");
    }
}

#[test]
fn paste_attributes_carries_tone_with_the_video_group() {
    let payload = json!({"clips": [{
        "id": 1, "track": 0, "start": 0, "duration": 600000,
        "source": {"kind": "shape"},
        "video": {"color": {"exposure": -1.5, "whites": 0.25, "fade": 0.75}},
        "shape": {"kind": "rectangle", "width": 10, "height": 10}
    }]});
    let after = project()
        .apply(&json!({"op": "paste_attributes", "clips": [10], "payload": payload}))
        .value();
    let color = &by_id(&after, "/clips", 10)["video"]["color"];
    assert_eq!(color["exposure"], json!(-1.5));
    assert_eq!(color["whites"], json!(0.25));
    assert_eq!(color["fade"], json!(0.75));
}

#[test]
fn a_split_mid_action_keeps_a_tone_key_that_is_zero_at_the_cut() {
    // Base exposure −1, a 2 s linear action to +1 from 0 s: at 1 s it is 0,
    // the value a plain `to_json` would leave out of the state at the cut.
    let handle = project()
        .apply(&set_color(json!({"exposure": -1})))
        .apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": 2 * SEC}))
        .apply(&json!({"op": "set_action_end", "clip": 10, "action": 20,
                        "patch": {"video": {"color": {"exposure": 1}}}}))
        .apply(&json!({"op": "split", "clips": [10], "at": SEC}));
    let value = handle.value();
    let clips = value["clips"].as_array().expect("clips");
    assert_eq!(clips.len(), 2);
    let head = by_id(&value, "/clips", 10);
    let tail = clips
        .iter()
        .find(|c| c["id"] != json!(10))
        .expect("the tail");
    assert_eq!(head["video"]["color"]["exposure"], json!(-1.0));
    assert_eq!(
        head["actions"][0]["end"]["video"]["color"]["exposure"],
        json!(0.0),
        "the head's action ends where the cut was: {}",
        head["actions"][0]
    );
    let tail_exposure = tail["video"]["color"]
        .get("exposure")
        .cloned()
        .unwrap_or(json!(0.0));
    assert_eq!(
        tail_exposure,
        json!(0.0),
        "the tail starts at the cut's value"
    );
    // And the join is invisible: the head at its last instant and the tail
    // at its first both evaluate to 0.
    let head_end = handle.clip_state(10, SEC - 1).expect("head");
    assert!(num(&head_end, "/video/color/exposure").abs() < 1e-5);
}
