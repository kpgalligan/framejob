//! A REVERSED ramped clip (spec §11 SR-18 (g), the road map's F): no case.
//!
//! `in` and S are measured in the direction the clip plays, so a reversed
//! twin answers the forward clip's numbers. Pinned here, through the FFI:
//! `split` of an `ease_out` ramp (the second half's `in`, its base rate,
//! the head's solved end rate and the tail) and `trim_end`'s bound read
//! through the map, each the same forward and reversed, and the forward
//! one at its closed form.

mod common;

use serde_json::{json, Value};

use common::{array, by_id, int, Handle};

/// Ticks per second and per 30 fps frame (spec §5.1), written out.
const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;
const START: i64 = SEC;

/// A clip at 1 s from `in` 0, `duration` long, with `actions`, in a
/// `file`-tick media, played `reversed` or not.
fn twin(file: i64, duration: i64, actions: Value, reversed: bool) -> Handle {
    Handle::from_value(&json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/reversed.mov", "kind": "video", "duration": file,
            "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": START, "duration": duration,
            "source": { "kind": "media", "media": 1, "in": 0, "reversed": reversed },
            "speed": 1.0, "video": {}, "audio": {}, "actions": actions
        }],
        "next_id": 100
    }))
}

/// Every clip's `source.reversed` dropped, so the twins can be compared.
fn forward_view(value: &Value) -> Value {
    let mut out = value.clone();
    if let Some(clips) = out["clips"].as_array_mut() {
        for clip in clips {
            if let Some(source) = clip["source"].as_object_mut() {
                source.remove("reversed");
            }
        }
    }
    out["clips"].clone()
}

#[test]
fn a_reversed_twin_splits_as_the_forward_clip_does() {
    let actions = json!([{ "id": 21, "start": 0, "duration": 4 * SEC, "curve": "ease_out",
                           "end": { "speed": 3.0 } }]);
    let op = json!({ "op": "split", "clips": [11], "at": START + 2 * SEC });
    let forward = twin(600 * SEC, 4 * SEC, actions.clone(), false)
        .apply(&op)
        .value();
    let reversed = twin(600 * SEC, 4 * SEC, actions, true).apply(&op).value();
    assert_eq!(forward_view(&forward), forward_view(&reversed));
    let second = array(&reversed, "/clips")
        .iter()
        .find(|c| int(c, "/start") == START + 2 * SEC)
        .expect("a second half")
        .clone();
    assert_eq!(int(&second, "/source/in"), 2_200_000);
    assert_eq!(second["source"]["reversed"], json!(true));
}

#[test]
fn a_reversed_twin_trims_its_end_to_the_forward_clip_s_bound() {
    // ×1 → ×2 over [0, 1 s), ×2 after, in a 5 s file: the end may reach
    // snapped_down(1 s + 2.75 s).
    let actions = json!([{ "id": 21, "start": 0, "duration": SEC, "curve": "linear",
                           "end": { "speed": 2.0 } }]);
    let op = json!({ "op": "trim_end", "clip": 11, "to": 10 * SEC });
    for reversed in [false, true] {
        let after = twin(5 * SEC, 2 * SEC, actions.clone(), reversed)
            .apply(&op)
            .value();
        let clip = by_id(&after, "/clips", 11);
        assert_eq!(
            int(clip, "/duration"),
            (START + 1_650_000).div_euclid(FRAME) * FRAME - START,
            "reversed: {reversed}"
        );
    }
}
