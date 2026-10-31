//! Black-box tests for an audio segment's automation (road map "audio"
//! AP8b, spec §7.2, §11 AU-85, AU-86), through the C FFI as `ReelCore.swift`
//! drives it.
//!
//! Pinned here: a plan carries no `automation` without an action naming a
//! tap key; a linear pan action gives exactly four points (the voice's ends
//! and the action's), an eased one the 1/30 s grid inside; a nested segment
//! reads its INNER clip's actions at the inner clip's origin; `isolation` is
//! present at 0 and ramps from it; an EQ slope holds until the action's end;
//! and a gate keyed on at an action's end appears only from that point.

mod common;

use serde_json::{json, Value};

use common::{array, at, int, num, Handle};

/// Ticks per second (spec §5.1), written out so a change to
/// `time::TIMESCALE` fails these tests instead of moving with them.
const SEC: i64 = 600_000;

/// The envelope's action grid, 1/30 s (`audio.rs`'s `ACTION_SAMPLE`).
const GRID: i64 = SEC / 30;

// ---- fixtures ------------------------------------------------------------

fn video_media() -> Value {
    json!({
        "id": 1, "path": "/fixtures/1.mov", "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

fn track(id: u32) -> Value {
    json!({ "id": id, "name": format!("Track {id}") })
}

/// Media clip `id` on track `on` at `start` for 10 s, with `audio` and one
/// action over [1 s, 3 s) of clip time ending at `end` along `curve`.
fn clip(id: u32, on: u32, start: i64, audio: Value, curve: &str, end: Value) -> Value {
    json!({
        "id": id, "track": on, "start": start, "duration": 10 * SEC,
        "source": { "kind": "media", "media": 1, "in": 0 },
        "video": {}, "audio": audio,
        "actions": [{ "id": 90 + id, "start": SEC, "duration": 2 * SEC,
                      "curve": curve, "end": end }]
    })
}

fn project(clips: Vec<Value>, nests: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 35,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0] },
        "media": [video_media()], "tracks": [track(2)], "clips": clips, "markers": [],
        "next_id": 200, "nests": nests
    }))
}

/// One timeline clip 3 at 0 with `audio` and an action ending at `end`.
fn one(audio: Value, curve: &str, end: Value) -> Handle {
    project(vec![clip(3, 2, 0, audio, curve, end)], vec![])
}

/// The plan's one audio segment.
fn segment(handle: &Handle) -> Value {
    let plan = handle.plan();
    let tracks = array(&plan, "/audio_tracks");
    assert_eq!(tracks.len(), 1, "one audio track: {plan}");
    let segments = array(&tracks[0], "/segments");
    assert_eq!(segments.len(), 1, "one audio segment: {plan}");
    segments[0].clone()
}

fn points(handle: &Handle) -> Vec<Value> {
    array(&segment(handle), "/automation").clone()
}

fn times(points: &[Value]) -> Vec<i64> {
    points.iter().map(|p| int(p, "/at")).collect()
}

// ---- tests -----------------------------------------------------------------

#[test]
fn no_automation_without_an_action_naming_a_tap_key() {
    let volume = one(json!({}), "linear", json!({ "audio": { "volume": 0.5 } }));
    let s = segment(&volume);
    assert!(s.get("automation").is_none(), "{s}");
    let video = one(json!({}), "linear", json!({ "video": { "opacity": 0.5 } }));
    let s = segment(&video);
    assert!(s.get("automation").is_none(), "{s}");
}

#[test]
fn a_linear_pan_action_gives_exactly_four_points() {
    let handle = one(json!({}), "linear", json!({ "audio": { "pan": 0.5 } }));
    let p = points(&handle);
    assert_eq!(times(&p), vec![0, SEC, 3 * SEC, 10 * SEC]);
    assert_eq!(num(&p[0], "/audio/pan"), 0.0);
    assert_eq!(num(&p[1], "/audio/pan"), 0.0);
    assert_eq!(num(&p[2], "/audio/pan"), 0.5);
    assert_eq!(num(&p[3], "/audio/pan"), 0.5);
    // Only tap keys: no volume, no fades, no keep_pitch.
    let keys: Vec<&String> = p[0]["audio"]
        .as_object()
        .expect("an object")
        .keys()
        .collect();
    for key in keys {
        assert!(
            [
                "mono",
                "pan",
                "compressor",
                "noise_reduction",
                "limiter",
                "isolation",
                "eq",
                "hum",
                "channels",
                "gate",
                "de_esser"
            ]
            .contains(&key.as_str()),
            "{key} is not a tap key: {}",
            p[0]
        );
    }
}

#[test]
fn an_eased_action_is_sampled_on_the_envelopes_grid() {
    let handle = one(json!({}), "ease_in_out", json!({ "audio": { "pan": 1.0 } }));
    let mut expected = vec![0, SEC];
    let mut t = SEC + GRID;
    while t < 3 * SEC {
        expected.push(t);
        t += GRID;
    }
    expected.extend([3 * SEC, 10 * SEC]);
    let p = points(&handle);
    assert_eq!(times(&p), expected);
    // Halfway, smoothstep is exactly one half.
    let half = p
        .iter()
        .find(|q| int(q, "/at") == 2 * SEC)
        .expect("a point at 2 s");
    assert!((num(half, "/audio/pan") - 0.5).abs() < 1e-12, "{half}");
}

#[test]
fn a_nested_segment_reads_its_inner_clip_at_its_origin() {
    let nest = json!({
        "id": 4, "name": "Nest 4", "width": 1920, "height": 1080,
        "tracks": [track(5)],
        "clips": [clip(6, 5, 0, json!({}), "linear", json!({ "audio": { "pan": -1.0 } }))]
    });
    let nest_clip = json!({
        "id": 3, "track": 2, "start": 2 * SEC, "duration": 10 * SEC,
        "source": { "kind": "nest", "project": 4 }, "video": {}, "audio": {},
        "actions": [{ "id": 80, "start": 0, "duration": SEC, "curve": "linear",
                      "end": { "audio": { "pan": 1.0 } } }]
    });
    let handle = project(vec![nest_clip], vec![nest]);
    let s = segment(&handle);
    assert_eq!(int(&s, "/clip"), 6, "{s}");
    let p = array(&s, "/automation");
    // The inner clip's action, [1 s, 3 s) of its time, at the nest clip's 2 s.
    assert_eq!(times(p), vec![2 * SEC, 3 * SEC, 5 * SEC, 12 * SEC]);
    assert_eq!(num(&p[2], "/audio/pan"), -1.0);
}

#[test]
fn isolation_is_present_at_zero_and_ramps_from_it() {
    let handle = one(
        json!({}),
        "linear",
        json!({ "audio": { "isolation": 0.8 } }),
    );
    let p = points(&handle);
    assert_eq!(num(&p[0], "/audio/isolation"), 0.0, "{}", p[0]);
    let halfway = handle.clip_state(3, 2 * SEC).expect("clip 3 has a state");
    assert!(
        (num(&halfway, "/audio/isolation") - 0.4).abs() < 1e-12,
        "{halfway}"
    );
}

#[test]
fn an_eq_slope_holds_until_the_actions_end() {
    let base = json!({ "eq": { "high_pass": { "frequency": 80.0, "slope": 12 } } });
    let end = json!({ "audio": { "eq": { "high_pass": { "frequency": 160.0, "slope": 24 } } } });
    let handle = one(base, "linear", end);
    let midway = handle.clip_state(3, 2 * SEC).expect("clip 3 has a state");
    assert_eq!(int(&midway, "/audio/eq/high_pass/slope"), 12, "{midway}");
    assert!((num(&midway, "/audio/eq/high_pass/frequency") - 120.0).abs() < 1e-9);
    let late = handle
        .clip_state(3, 3 * SEC - 1)
        .expect("clip 3 has a state");
    assert_eq!(int(&late, "/audio/eq/high_pass/slope"), 12, "{late}");
    let after = handle.clip_state(3, 3 * SEC).expect("clip 3 has a state");
    assert_eq!(int(&after, "/audio/eq/high_pass/slope"), 24, "{after}");
}

#[test]
fn a_hum_mains_holds_until_the_actions_end() {
    let base = json!({ "hum": { "frequency": 50, "depth_db": 30.0, "harmonics": 2 } });
    let end = json!({ "audio": { "hum": { "frequency": 60, "harmonics": 6 } } });
    let handle = one(base, "linear", end);
    let midway = handle.clip_state(3, 2 * SEC).expect("clip 3 has a state");
    assert_eq!(int(&midway, "/audio/hum/frequency"), 50, "{midway}");
    assert_eq!(int(&midway, "/audio/hum/harmonics"), 2, "{midway}");
    let after = handle.clip_state(3, 3 * SEC).expect("clip 3 has a state");
    assert_eq!(int(&after, "/audio/hum/frequency"), 60, "{after}");
    assert_eq!(int(&after, "/audio/hum/harmonics"), 6, "{after}");
}

#[test]
fn a_gate_keyed_on_appears_only_from_the_actions_end() {
    let handle = one(json!({}), "linear", json!({ "audio": { "gate": {} } }));
    let p = points(&handle);
    assert_eq!(times(&p), vec![0, SEC, 3 * SEC, 10 * SEC]);
    assert!(p[0]["audio"].get("gate").is_none(), "{}", p[0]);
    assert!(p[1]["audio"].get("gate").is_none(), "{}", p[1]);
    assert!(at(&p[2], "/audio/gate").is_object(), "{}", p[2]);
    assert!(at(&p[3], "/audio/gate").is_object(), "{}", p[3]);
}
