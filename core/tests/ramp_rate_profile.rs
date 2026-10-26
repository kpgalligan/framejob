//! A ramped clip's rate profile (spec §11 SR-26), `rc_project_source_map`'s
//! `rate`: what the action lanes draw as a line.
//!
//! Pinned here, through the FFI, against closed-form oracles written in this
//! file: a linear ×1 → ×2 ramp over [1 s, 3 s) of a 5 s clip answers its
//! edges and 33 samples across the ramp at 1 + (t − 1 s)/2 s; an `ease_in`
//! ×1 → ×0.5 ramp's middle sample 1 − 0.5·0.5² = 0.875; a ×3 action over
//! [0, 2 s) trimmed to 1 s ends at the rate it reached there, ×2; an action
//! ending at the base rate answers ×1 everywhere; a reversed clip the
//! forward twin's list; and a constant clip no `rate` key at all.

mod common;

use serde_json::{json, Value};

use common::{array, Handle};

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;
/// Samples across one ramp piece: 32 chords, 33 ticks.
const SAMPLES: i64 = 32;

/// 60 s of 1920x1080 at 30 fps with sound.
fn media() -> Value {
    json!({
        "id": 1, "path": "/fixtures/rate-profile.mov", "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

/// Clip 11 at 0, 5 s long, from `in` 1 s, at `speed`, with `actions`,
/// played `reversed` or not.
fn clip(speed: f64, actions: Value, reversed: bool) -> Value {
    json!({
        "id": 11, "track": 2, "start": 0, "duration": 5 * SEC,
        "source": { "kind": "media", "media": 1, "in": SEC, "reversed": reversed },
        "speed": speed, "video": {}, "audio": {}, "actions": actions
    })
}

fn project(clip: Value) -> Handle {
    Handle::from_value(&json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media()],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [clip],
        "next_id": 100
    }))
}

/// Action 21 over clip time [`from`, `to`) ending at `rate` along `curve`.
fn action(from: i64, to: i64, curve: &str, rate: f64) -> Value {
    json!([{ "id": 21, "start": from, "duration": to - from, "curve": curve,
             "end": { "speed": rate } }])
}

/// The clip's `rate` list as `(tick, rate)` pairs.
fn rate(handle: &Handle) -> Vec<(i64, f64)> {
    let map = handle.source_map(11).expect("a media clip has a map");
    assert_eq!(map["ramped"], json!(true), "{map}");
    array(&map, "/rate")
        .iter()
        .map(|row| {
            let pair = row.as_array().expect("a row is a pair");
            assert_eq!(pair.len(), 2, "{row}");
            (
                pair[0].as_i64().expect("an integer tick"),
                pair[1].as_f64().expect("a number rate"),
            )
        })
        .collect()
}

fn assert_profile(got: &[(i64, f64)], expected: &[(i64, f64)]) {
    assert_eq!(got.len(), expected.len(), "{got:?}");
    for (g, e) in got.iter().zip(expected) {
        assert_eq!(g.0, e.0, "{got:?}");
        assert!((g.1 - e.1).abs() <= 1e-12, "{g:?} against {e:?}");
    }
}

#[test]
fn a_linear_ramp_answers_its_edges_and_33_samples() {
    let handle = project(clip(1.0, action(SEC, 3 * SEC, "linear", 2.0), false));
    let mut expected = vec![(0, 1.0)];
    for k in 0..=SAMPLES {
        let t = SEC + 2 * SEC * k / SAMPLES;
        expected.push((t, 1.0 + (t - SEC) as f64 / (2 * SEC) as f64));
    }
    expected.push((5 * SEC, 2.0));
    let got = rate(&handle);
    assert_profile(&got, &expected);
    assert_eq!(got.get(1), Some(&(SEC, 1.0)));
    assert!(got.contains(&(3 * SEC, 2.0)));
}

#[test]
fn an_ease_in_slow_down_answers_its_middle_sample() {
    let handle = project(clip(1.0, action(SEC, 3 * SEC, "ease_in", 0.5), false));
    let got = rate(&handle);
    let middle = got
        .iter()
        .find(|(t, _)| *t == 2 * SEC)
        .expect("a sample at 2 s");
    // 1 + (0.5 − 1)·ease_in(0.5) = 1 − 0.5·0.25.
    assert!((middle.1 - 0.875).abs() <= 1e-12, "{middle:?}");
    assert_eq!(got.last(), Some(&(5 * SEC, 0.5)));
}

#[test]
fn a_trimmed_ramp_ends_at_the_rate_it_reached() {
    let handle = project(clip(1.0, action(0, 2 * SEC, "linear", 3.0), false));
    let trimmed = handle.apply(&json!({"op": "trim_end", "clip": 11, "to": SEC}));
    let got = rate(&trimmed);
    assert_eq!(got.first(), Some(&(0, 1.0)));
    let last = got.last().expect("a point");
    assert_eq!(last.0, SEC);
    // Halfway through a ×1 → ×3 linear ramp.
    assert!((last.1 - 2.0).abs() <= 1e-12, "{last:?}");
}

#[test]
fn an_action_ending_at_the_base_rate_answers_the_base_everywhere() {
    let handle = project(clip(1.0, action(SEC, 3 * SEC, "linear", 1.0), false));
    let got = rate(&handle);
    assert!(got.len() >= 2, "{got:?}");
    assert!(got.iter().all(|(_, r)| *r == 1.0), "{got:?}");
    assert_eq!(got.first().map(|p| p.0), Some(0));
    assert_eq!(got.last().map(|p| p.0), Some(5 * SEC));
}

#[test]
fn a_reversed_clip_answers_the_forward_twins_rate() {
    let forward = project(clip(1.0, action(SEC, 3 * SEC, "linear", 2.0), false));
    let reversed = project(clip(1.0, action(SEC, 3 * SEC, "linear", 2.0), true));
    let map = reversed.source_map(11).expect("a media clip has a map");
    let twin = forward.source_map(11).expect("a media clip has a map");
    assert_eq!(map["rate"], twin["rate"]);
    assert!(map["rate"].is_array());
}

#[test]
fn a_constant_clip_has_no_rate_key() {
    let handle = project(clip(1.5, json!([]), false));
    let map = handle.source_map(11).expect("a media clip has a map");
    assert_eq!(map["ramped"], json!(false));
    assert!(map.get("rate").is_none(), "{map}");
}
