//! The reader bounds a clip's `speed` to the ops' ×0.1 – ×1000 (spec §11
//! R6-10, amended by #41): `Project::validate` refuses any clip outside
//! `SPEED_MIN..=SPEED_MAX`, on the timeline and in a nest, naming the clip
//! and the value as JSON spells it — on read, through the FFI, and in every
//! edit's `finish`.

use serde_json::{json, Value};

mod common;
use common::Handle;

const M: i64 = 9_000_000_000_000_000;

/// `time_bounds.rs`'s fixture: media clip 3 on the timeline, and still clip
/// 8 in nest 6.
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

/// Asserts the reader refuses `project` with exactly `expected`, and that
/// the failed read left its input as it was.
fn refuse(project: &Value, expected: &str) {
    let original = project.to_string();
    assert_eq!(
        Handle::try_from_value(project).err().as_deref(),
        Some(expected)
    );
    assert_eq!(
        project.to_string(),
        original,
        "a failed read changed its input"
    );
}

#[test]
fn the_reader_refuses_a_timeline_speed_outside_the_ops_range() {
    // The value is spelled as serde_json spells it, which is not `{}`'s:
    // 1e300 is `1e+300`, not 301 digits.
    //
    // The parse limit: the core's serde_json has no `float_roundtrip`, so
    // the text `0.09999999999999999` — the float directly below 0.1 —
    // parses to exactly 0.1 and opens. That float cannot be written in any
    // file this reader parses; `0.09999999999999998` is the nearest one
    // below the bound that can.
    for (speed, said) in [
        (1e300, "1e+300"),
        (1e-300, "1e-300"),
        (f64::MAX, "1.7976931348623157e+308"),
        (5e-324, "5e-324"),
        (1000.0000000000002, "1000.0000000000002"),
        (0.09999999999999998, "0.09999999999999998"),
        (0.0, "0.0"),
        (-1.0, "-1.0"),
    ] {
        let mut p = fixture();
        p["clips"][0]["speed"] = json!(speed);
        refuse(&p, &format!("clip 3's speed {said} is outside ×0.1–×1000"));
    }
    // At every format version: the refusal is not a format change, and the
    // file is never migrated into acceptance.
    for version in [1, 2, 7, 8] {
        for (speed, said) in [(1e300, "1e+300"), (1e-300, "1e-300")] {
            let mut p = fixture();
            p["version"] = json!(version);
            p["clips"][0]["speed"] = json!(speed);
            refuse(&p, &format!("clip 3's speed {said} is outside ×0.1–×1000"));
        }
    }
}

#[test]
fn the_reader_refuses_a_nested_speed_and_names_the_nest() {
    let mut p = fixture();
    p["nests"][0]["clips"][0]["speed"] = json!(1e300);
    refuse(&p, "clip 8 in nest 6's speed 1e+300 is outside ×0.1–×1000");
}

#[test]
fn both_bounds_themselves_open() {
    for speed in [0.1, 1000.0] {
        let mut p = fixture();
        p["clips"][0]["speed"] = json!(speed);
        let h = Handle::from_value(&p);
        assert_eq!(h.value()["clips"][0]["speed"], json!(speed));
    }
}

#[test]
fn the_ops_clamp_and_the_readers_bound_agree() {
    for (rate, landed) in [(4000.0, 1000.0), (0.05, 0.1)] {
        let h = Handle::from_value(&fixture())
            .apply(&json!({"op": "set_speed", "clip": 3, "rate": rate}));
        let reopened = Handle::try_from_json(&h.to_json())
            .unwrap_or_else(|why| panic!("×{rate} clamped to a speed the reader refuses: {why}"));
        assert_eq!(reopened.value()["clips"][0]["speed"], json!(landed));
    }
}

#[test]
fn no_edit_can_carry_an_out_of_range_speed() {
    // The FFI refuses this project, so it is built against the library
    // directly (the precedent is `evaluate_tests.rs`'s absent-media slate):
    // `finish` runs the same `validate`, so the edit is an error rather
    // than a project nobody could open again.
    let mut p = fixture();
    p["clips"][0]["speed"] = json!(5000.0);
    let project: reelcut_core::Project =
        serde_json::from_value(p).expect("the JSON itself is well formed");
    assert_eq!(
        project.apply(r#"{"op":"move_clip","clips":[3],"delta":20000}"#),
        Err("clip 3's speed 5000.0 is outside ×0.1–×1000".to_string())
    );
}
