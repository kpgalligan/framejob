//! Structural-time admission through the file reader and writer, plus the
//! rational snap boundaries used by admitted and hostile inputs.

use reelcut_core::format;
use reelcut_core::time::{self, Fps, TIMESCALE};
use serde_json::{json, Value};

mod common;
use common::Handle;

const M: i64 = 9_000_000_000_000_000;

fn fixture() -> Value {
    json!({
        "version": 8,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/missing.mov", "kind": "video", "duration": M}],
        "tracks": [{"id": 2}],
        "clips": [{"id": 3, "track": 2, "start": 0, "duration": 20000,
                   "source": {"kind": "media", "media": 1, "in": 0},
                   "actions": [{"id": 4, "start": 0, "duration": 20000, "end": {}}]}],
        "markers": [{"id": 5, "time": 0}],
        "nests": [{"id": 6, "tracks": [{"id": 7}],
                   "clips": [{"id": 8, "track": 7, "start": 0, "duration": 20000,
                              "source": {"kind": "still", "media": 1, "at": 0},
                              "actions": [{"id": 9, "start": 0, "duration": 20000,
                                           "end": {}}]}]}],
        "next_id": 10
    })
}

fn reject(mutated: &Value, path: &str, value: i128) {
    let original = mutated.to_string();
    let expected = format!("{path} must be between -{M} and {M} ticks, not {value}");
    assert_eq!(
        Handle::try_from_value(mutated).err().as_deref(),
        Some(expected.as_str())
    );
    let direct: reelcut_core::Project = serde_json::from_value(mutated.clone()).unwrap();
    assert_eq!(format::write(&direct).unwrap_err(), expected);
    assert_eq!(
        mutated.to_string(),
        original,
        "a failed read changed its input"
    );
}

#[test]
fn boundaries_and_every_structural_family() {
    for value in [M - 1, M] {
        let mut p = fixture();
        p["media"][0]["duration"] = json!(value);
        p["markers"][0]["time"] = json!(-value);
        p["clips"][0]["source"]["in"] = json!(value);
        p["nests"][0]["clips"][0]["source"]["at"] = json!(-value);
        let h = Handle::from_value(&p);
        assert_eq!(Handle::from_json(&h.to_json()).value(), h.value());
    }
    for value in [M + 1, i64::MAX, i64::MIN] {
        let mut p = fixture();
        p["media"][0]["duration"] = json!(value);
        reject(&p, "media 1.duration", i128::from(value));
        let mut p = fixture();
        p["markers"][0]["time"] = json!(value);
        reject(&p, "marker 5.time", i128::from(value));
        let mut p = fixture();
        p["clips"][0]["source"]["in"] = json!(value);
        reject(&p, "clip 3.source.in", i128::from(value));
        let mut p = fixture();
        p["nests"][0]["clips"][0]["source"]["at"] = json!(value);
        reject(&p, "clip 8 in nest 6.source.at", i128::from(value));
        let mut p = fixture();
        p["clips"][0]["actions"][0]["start"] = json!(value);
        reject(&p, "clip 3.action 4.start", i128::from(value));
        if value > 0 {
            let mut p = fixture();
            p["nests"][0]["clips"][0]["actions"][0]["duration"] = json!(value);
            reject(&p, "clip 8 in nest 6.action 9.duration", i128::from(value));
        }
    }
}

#[test]
fn endpoints_are_checked_in_wide_arithmetic() {
    let mut p = fixture();
    p["clips"][0]["start"] = json!(M);
    reject(&p, "clip 3.end", i128::from(M) + 20000);
    let mut p = fixture();
    p["nests"][0]["clips"][0]["actions"][0]["start"] = json!(M);
    reject(&p, "clip 8 in nest 6.action 9.end", i128::from(M) + 20000);
    let mut p = fixture();
    p["clips"][0]["start"] = json!(i64::MAX);
    reject(&p, "clip 3.start", i128::from(i64::MAX));
}

#[test]
fn old_versions_bound_speeds_and_negative_values_keep_their_reading() {
    for version in [1, 2, 7, 8] {
        for speed in [0.1, 1000.0] {
            let mut p = fixture();
            p["version"] = json!(version);
            p["clips"][0]["speed"] = json!(speed);
            p["clips"][0]["source"]["in"] = json!(-M);
            p["markers"][0]["time"] = json!(-M);
            p["clips"][0]["actions"][0]["start"] = json!(-M);
            // Opaque end-patch timings are outside D7-1.
            p["clips"][0]["actions"][0]["end"] = json!({"video": {"motion": {
                "enter": {"duration": i64::MAX}
            }}});
            let h = Handle::from_value(&p);
            assert_eq!(h.value()["version"], format::RC_FORMAT_VERSION);
            assert_eq!(h.value()["clips"][0]["speed"], json!(speed));
        }
    }
}

fn rounded(n: i128, d: i128) -> i128 {
    if n >= 0 {
        (n + d / 2) / d
    } else {
        -((-n + d / 2) / d)
    }
}
fn saturate(n: i128) -> i64 {
    n.clamp(i128::from(i64::MIN), i128::from(i64::MAX)) as i64
}
fn representable(n: i128) -> bool {
    (i128::from(i64::MIN)..=i128::from(i64::MAX)).contains(&n)
}
fn oracle(t: i64, fps: Fps) -> (i128, i64) {
    let index = rounded(
        i128::from(t) * i128::from(fps.num),
        i128::from(TIMESCALE) * i128::from(fps.den),
    );
    let tick = saturate(rounded(
        index * i128::from(TIMESCALE) * i128::from(fps.den),
        i128::from(fps.num),
    ));
    (index, tick)
}

#[test]
fn rational_snap_uses_wide_indices_until_the_public_boundary() {
    for rate in [(30, 1), (30000, 1001), (7, 1), (u32::MAX, 1), (1, u32::MAX)] {
        let fps = Fps {
            num: rate.0,
            den: rate.1,
        };
        for tick in [i64::MIN, -M, -M + 1, M - 1, M, i64::MAX] {
            let (index, near) = oracle(tick, fps);
            assert_eq!(time::frame_index(tick, fps), Some(saturate(index)));
            assert_eq!(time::snap_to_frame(tick, fps), near, "{tick} {rate:?}");
            let at = |index: i128| {
                saturate(rounded(
                    index * i128::from(TIMESCALE) * i128::from(fps.den),
                    i128::from(fps.num),
                ))
            };
            let up = if near < tick { at(index + 1) } else { near };
            let down = if near > tick { at(index - 1) } else { near };
            assert_eq!(time::snap_up_to_frame(tick, fps), up, "up {tick} {rate:?}");
            assert_eq!(
                time::snap_down_to_frame(tick, fps),
                down,
                "down {tick} {rate:?}"
            );
            let raw_at = |index: i128| {
                rounded(
                    index * i128::from(TIMESCALE) * i128::from(fps.den),
                    i128::from(fps.num),
                )
            };
            let raw_near = raw_at(index);
            let raw_up = if raw_near < i128::from(tick) {
                raw_at(index + 1)
            } else {
                raw_near
            };
            let raw_down = if raw_near > i128::from(tick) {
                raw_at(index - 1)
            } else {
                raw_near
            };
            if representable(raw_near) {
                assert_eq!(
                    time::snap_to_frame(near, fps),
                    near,
                    "nearest stability {tick} {rate:?}"
                );
            }
            if representable(raw_up) {
                assert!(up >= tick, "up moved below {tick} at {rate:?}");
                assert_eq!(
                    time::snap_up_to_frame(up, fps),
                    up,
                    "up stability {tick} {rate:?}"
                );
            }
            if representable(raw_down) {
                assert!(down <= tick, "down moved above {tick} at {rate:?}");
                assert_eq!(
                    time::snap_down_to_frame(down, fps),
                    down,
                    "down stability {tick} {rate:?}"
                );
            }
        }
    }
}
