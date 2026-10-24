//! `freeze_frame` inside a RAMP (spec §6, §11 SR-18 (f), the road map's J).
//!
//! Pinned here, through the FFI, against closed-form oracles written in this
//! file: the still holds `in + round(S(at − start))`, which is the tick a
//! `split` at the same place starts its second half on, and the tick the
//! freeze's own first half ends on read from its stored actions — for an
//! `ease_out` ramp, where the head's end rate is solved, and a `linear` one.

mod common;

use serde_json::{json, Value};

use common::{array, by_id, int, num, text, Handle};

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;
const START: i64 = SEC;
const IN: i64 = SEC / 2;
const AT: i64 = START + 2 * SEC;

fn ease_integral(curve: &str, u: f64) -> f64 {
    match curve {
        "linear" => u * u / 2.0,
        "ease_out" => u * u - u.powi(3) / 3.0,
        other => panic!("no curve {other} here"),
    }
}

/// S(t) for a clip at `r0` with ONE speed action over [0, b) ending at `r1`
/// along `curve`, held after: the closed form.
fn s_of(t: i64, r0: f64, r1: f64, b: i64, curve: &str) -> f64 {
    let (t, b) = (t as f64, b as f64);
    let inside = t.min(b);
    let mut s = r0 * inside + (r1 - r0) * b * ease_integral(curve, inside / b);
    if t > b {
        s += r1 * (t - b);
    }
    s
}

/// A 4 s clip at 1 s from `in` 0.5 s, ×1 → ×3 over its whole length.
fn ramped(curve: &str) -> Handle {
    Handle::from_value(&json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/freeze.mov", "kind": "video", "duration": 600 * SEC,
            "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": START, "duration": 4 * SEC,
            "source": { "kind": "media", "media": 1, "in": IN },
            "speed": 1.0, "video": {}, "audio": {},
            "actions": [{ "id": 21, "start": 0, "duration": 4 * SEC, "curve": curve,
                          "end": { "speed": 3.0 } }]
        }],
        "next_id": 100
    }))
}

fn media_clip_at(value: &Value, start: i64) -> Value {
    array(value, "/clips")
        .iter()
        .find(|c| int(c, "/start") == start && text(c, "/source/kind") == "media")
        .unwrap_or_else(|| panic!("no media clip starts at {start} in {value}"))
        .clone()
}

#[test]
fn a_freeze_inside_a_ramp_holds_the_tick_the_split_halves_meet_at() {
    for curve in ["ease_out", "linear"] {
        let handle = ramped(curve);
        let split = handle
            .apply(&json!({ "op": "split", "clips": [11], "at": AT }))
            .value();
        let joined = int(&media_clip_at(&split, AT), "/source/in");
        assert_eq!(
            joined,
            IN + s_of(2 * SEC, 1.0, 3.0, 4 * SEC, curve).round() as i64,
            "{curve}"
        );

        let frozen = handle
            .apply(&json!({ "op": "freeze_frame", "clip": 11, "at": AT, "duration": SEC }))
            .value();
        let still = array(&frozen, "/clips")
            .iter()
            .find(|c| text(c, "/source/kind") == "still")
            .expect("a still was added")
            .clone();
        assert_eq!(int(&still, "/start"), AT);
        assert_eq!(int(&still, "/source/at"), joined, "{curve}");

        // The freeze's own halves: the second, moved past the still, starts
        // on the held tick, and the first ends on it, read from its stored
        // actions.
        let second = media_clip_at(&frozen, AT + SEC);
        assert_eq!(int(&second, "/source/in"), joined, "{curve}");
        let first = by_id(&frozen, "/clips", 11);
        let head = &array(first, "/actions")[0];
        let head_end = IN as f64
            + s_of(
                int(first, "/duration"),
                num(first, "/speed"),
                num(head, "/end/speed"),
                int(head, "/duration"),
                curve,
            );
        assert!(
            (head_end - joined as f64).abs() <= 1.0,
            "{curve}: the first half ends at {head_end}, the still holds {joined}"
        );
    }
}
