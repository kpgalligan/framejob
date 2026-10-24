//! A media clip's source map (spec §11 SR-20 (a)), `rc_project_source_map`:
//! what Swift's readers take to convert between source and timeline time.
//!
//! Pinned here, through the FFI, against closed-form oracles written in this
//! file: a linear ×1 → ×2 ramp's points at `in + round(S(t))` on every
//! breakpoint (0, every 600 ticks through the ramp, its end, D) and equal to
//! the plan's audio `ramp.map`; the same for an `ease_in_out` ramp; a
//! constant clip at ×1.5 the two-point form; a reversed ramped clip the
//! forward twin's map; a clip in a nest, through `rc_project_scoped`, its own
//! unlifted map though the nest clip cuts it; and NULL for a text clip, an
//! unknown id and a NULL project.

mod common;

use std::ptr;

use serde_json::{json, Value};

use common::{array, int, take_string, Handle};
use framejob_core::ffi_query::rc_project_source_map;

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;
/// The map's step inside a ramp: 1 ms.
const STEP: i64 = 600;

/// The two curves' eases' integrals over [0, u], derived by hand from
/// §5.4's polynomials: u and u²(3 − 2u).
fn ease_integral(curve: &str, u: f64) -> f64 {
    match curve {
        "linear" => u * u / 2.0,
        "ease_in_out" => u.powi(3) - u.powi(4) / 2.0,
        other => panic!("no curve {other}"),
    }
}

/// S(t) for a clip at `r0` with ONE speed action over [a, b) ending at
/// `r1` along `curve`, held after: the closed form.
fn s_of(t: i64, r0: f64, r1: f64, a: i64, b: i64, curve: &str) -> f64 {
    let t = t as f64;
    let (a, b) = (a as f64, b as f64);
    let mut s = r0 * t.min(a);
    if t > a {
        let inside = t.min(b) - a;
        s += r0 * inside + (r1 - r0) * (b - a) * ease_integral(curve, inside / (b - a));
    }
    if t > b {
        s += r1 * (t - b);
    }
    s
}

/// 60 s of 1920x1080 at 30 fps with sound.
fn media() -> Value {
    json!({
        "id": 1, "path": "/fixtures/source-map.mov", "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

/// Clip 11 at 0.5 s, 3 s long, from `in` 1 s on track `track`, at `speed`,
/// with `actions`, played `reversed` or not.
fn clip(track: u32, speed: f64, actions: Value, reversed: bool) -> Value {
    json!({
        "id": 11, "track": track, "start": SEC / 2, "duration": 3 * SEC,
        "source": { "kind": "media", "media": 1, "in": SEC, "reversed": reversed },
        "speed": speed, "video": {}, "audio": {}, "actions": actions
    })
}

fn project(clips: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media()],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": clips,
        "next_id": 100
    }))
}

/// Action 21 over clip time [1 s, 2 s) ending at ×2 along `curve`.
fn ramp(curve: &str) -> Value {
    json!([{ "id": 21, "start": SEC, "duration": SEC, "curve": curve,
             "end": { "speed": 2.0 } }])
}

/// The plan's audio segment of clip 11: its `ramp.map`.
fn plan_map(handle: &Handle) -> Value {
    let plan = handle.plan();
    for track in array(&plan, "/audio_tracks") {
        for segment in array(track, "/segments") {
            if int(segment, "/clip") == 11 {
                return segment["ramp"]["map"].clone();
            }
        }
    }
    panic!("no audio segment for clip 11: {plan}")
}

/// The breakpoints of [`ramp`]'s map, written out: 0, every 600 ticks from
/// the action's start to its end, the end, D.
fn breakpoints() -> Vec<i64> {
    let mut times = vec![0];
    times.extend((0..SEC / STEP).map(|k| SEC + k * STEP));
    times.extend([2 * SEC, 3 * SEC]);
    times
}

#[test]
fn a_ramp_answers_its_closed_form_map_and_the_plans() {
    for curve in ["linear", "ease_in_out"] {
        let handle = project(vec![clip(2, 1.0, ramp(curve), false)]);
        let map = handle.source_map(11).expect("a media clip has a map");
        assert_eq!(map["ramped"], json!(true), "{curve}");
        let expected: Vec<Value> = breakpoints()
            .iter()
            .map(|t| {
                json!([
                    t,
                    SEC + s_of(*t, 1.0, 2.0, SEC, 2 * SEC, curve).round() as i64
                ])
            })
            .collect();
        assert_eq!(array(&map, "/map"), &expected, "{curve}");
        assert_eq!(map["map"], plan_map(&handle), "{curve}");
    }
}

#[test]
fn a_constant_clip_answers_two_points() {
    let handle = project(vec![clip(2, 1.5, json!([]), false)]);
    let map = handle.source_map(11).expect("a media clip has a map");
    // 3 s at ×1.5 reads 4.5 s from `in` 1 s.
    assert_eq!(
        map,
        json!({ "ramped": false, "map": [[0, SEC], [3 * SEC, SEC + 2_700_000]] })
    );
}

#[test]
fn a_reversed_ramped_clip_answers_the_forward_twins_map() {
    let forward = project(vec![clip(2, 1.0, ramp("linear"), false)]);
    let reversed = project(vec![clip(2, 1.0, ramp("linear"), true)]);
    let map = reversed.source_map(11).expect("a media clip has a map");
    assert_eq!(map["ramped"], json!(true));
    assert_eq!(Some(map), forward.source_map(11));
}

#[test]
fn a_clip_in_a_nest_answers_its_own_unlifted_map() {
    // Nest clip 60 shows the nest from 0 for 2 s, so it cuts clip 11
    // (0.5 s to 3.5 s inside) at 1.5 s of its 3 s; the scoped handle's
    // answer is the whole clip's.
    let top = project(vec![clip(2, 1.0, ramp("linear"), false)]);
    let nested = Handle::from_value(&json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media()],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{ "id": 60, "track": 2, "start": 0, "duration": 2 * SEC,
                    "source": { "kind": "nest", "project": 50 } }],
        "nests": [{ "id": 50, "name": "Nest", "width": 1920, "height": 1080,
                    "tracks": [{ "id": 53, "name": "Inner" }],
                    "clips": [clip(53, 1.0, ramp("linear"), false)] }],
        "next_id": 100
    }));
    assert_eq!(nested.source_map(11), None, "clip 11 is not top-level");
    let inner = nested.scoped(50).source_map(11).expect("a media clip");
    assert_eq!(Some(inner.clone()), top.source_map(11));
    let points = array(&inner, "/map");
    assert_eq!(points.last(), Some(&json!([3 * SEC, SEC + 2_700_000])));
}

#[test]
fn a_text_clip_an_unknown_id_and_null_answer_null() {
    let handle = project(vec![json!({
        "id": 12, "track": 2, "start": 0, "duration": SEC,
        "source": { "kind": "text" }, "video": {}, "text": { "content": "A" }
    })]);
    assert_eq!(handle.source_map(12), None);
    assert_eq!(handle.source_map(99), None);
    assert_eq!(
        take_string(unsafe { rc_project_source_map(ptr::null(), 11) }),
        None
    );
}
