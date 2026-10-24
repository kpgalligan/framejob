//! A ramped clip INSIDE a nest (spec §11 SR-18 (g), the road map's G): no
//! case.
//!
//! `scope` applies an op unchanged inside the nest it names, so a ramped
//! clip there splits and trims as its twin at the top level does. Pinned
//! here, through the FFI: `split` of an `ease_out` ramp and `trim_end`
//! through the map, each through `scope` against the same op on the same
//! clip at the top level.

mod common;

use serde_json::{json, Value};

use common::{array, by_id, int, Handle};

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;

fn media() -> Value {
    json!({
        "id": 1, "path": "/fixtures/nested.mov", "kind": "video", "duration": 5 * SEC,
        "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true
    })
}

/// Media clip 51 at 1 s, 2 s long from `in` 0, on `track`, ×1 → ×3
/// ease-out over [0, 2 s): S(2 s) = 4.667 s, in a 5 s file.
fn ramped(track: u32) -> Value {
    json!({
        "id": 51, "track": track, "start": SEC, "duration": 2 * SEC,
        "source": { "kind": "media", "media": 1, "in": 0 },
        "speed": 1.0, "video": {}, "audio": {},
        "actions": [{ "id": 52, "start": 0, "duration": 2 * SEC, "curve": "ease_out",
                      "end": { "speed": 3.0 } }]
    })
}

fn top_level() -> Handle {
    Handle::from_value(&json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media()],
        "tracks": [{ "id": 53, "name": "Track 1" }],
        "clips": [ramped(53)],
        "next_id": 100
    }))
}

/// The same clip in nest 50, shown by nest clip 60 at 0 for 10 s.
fn nested() -> Handle {
    Handle::from_value(&json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media()],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{ "id": 60, "track": 2, "start": 0, "duration": 10 * SEC,
                    "source": { "kind": "nest", "project": 50 } }],
        "nests": [{ "id": 50, "name": "Nest", "width": 1920, "height": 1080,
                    "tracks": [{ "id": 53, "name": "Inner" }], "clips": [ramped(53)] }],
        "next_id": 100
    }))
}

fn scoped(op: &Value) -> Value {
    let mut out = op.clone();
    out["scope"] = json!(50);
    out
}

#[test]
fn split_through_scope_matches_the_top_level() {
    let op = json!({ "op": "split", "clips": [51], "at": 2 * SEC });
    let top = top_level().apply(&op).value();
    let inner = nested().apply(&scoped(&op)).value();
    let nest = by_id(&inner, "/nests", 50);
    assert_eq!(array(nest, "/clips"), array(&top, "/clips"));
    let second = array(&top, "/clips")
        .iter()
        .find(|c| int(c, "/start") == 2 * SEC)
        .expect("a second half")
        .clone();
    assert_eq!(int(&second, "/source/in"), 1_100_000);
}

#[test]
fn trim_end_through_scope_matches_the_top_level() {
    let op = json!({ "op": "trim_end", "clip": 51, "to": 10 * SEC });
    let top = top_level().apply(&op).value();
    let inner = nested().apply(&scoped(&op)).value();
    let nest = by_id(&inner, "/nests", 50);
    assert_eq!(array(nest, "/clips"), array(&top, "/clips"));
    // S(2 s) = 2.8M ticks, then ×3 to the 3M-tick file: 66 667 ticks more,
    // the end snapped down from the clip's start at 1 s.
    let clip = by_id(&top, "/clips", 51);
    assert_eq!(int(clip, "/duration"), 2 * SEC + 60_000);
}
