//! Voice isolation's model (format 31, spec §11 AU-50), through the FFI:
//! `set_audio {isolation}` range-checked in `in_range`'s own sentence, a
//! value inside the range applied, an action end past 1 clamped to 1 by the
//! evaluator, and `paste_attributes` carrying it with the audio group.

use serde_json::{json, Value};

mod common;
use common::{at, num, Handle};

const SEC: i64 = 600_000;

/// Two 10 s voice clips, 11 and 12, the second after the first.
fn two() -> Handle {
    Handle::from_value(&json!({
        "version": 31,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/fixtures/voice.m4a", "kind": "audio",
                   "duration": 60 * SEC, "has_audio": true}],
        "tracks": [{"id": 2, "name": "A"}],
        "clips": [
            {"id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
             "source": {"kind": "media", "media": 1, "in": 0}, "audio": {}},
            {"id": 12, "track": 2, "start": 10 * SEC, "duration": 10 * SEC,
             "source": {"kind": "media", "media": 1, "in": 10 * SEC}, "audio": {}}
        ],
        "next_id": 100
    }))
}

fn set(isolation: Value) -> Value {
    json!({"op": "set_audio", "clips": [11], "patch": {"isolation": isolation}})
}

#[test]
fn out_of_range_is_refused_in_the_check_sentence() {
    let handle = two();
    assert_eq!(
        handle.errors(&set(json!(1.5))),
        "audio.isolation must be between 0 and 1, not 1.5"
    );
    assert_eq!(
        handle.errors(&set(json!(-0.1))),
        "audio.isolation must be between 0 and 1, not -0.1"
    );
}

#[test]
fn a_value_in_range_applies_and_zero_writes_no_key() {
    let isolated = two().apply(&set(json!(0.8)));
    assert_eq!(
        at(&isolated.value(), "/clips/0/audio/isolation"),
        &json!(0.8)
    );
    let off = isolated.apply(&set(json!(0.0)));
    assert!(
        off.value()["clips"][0]["audio"].get("isolation").is_none(),
        "isolation 0 is not written"
    );
    assert!(!off.to_json().contains("isolation"));
}

#[test]
fn an_action_end_past_one_clamps_to_one() {
    let base = two().apply(&json!({
        "op": "add_action", "clip": 11, "at": 0, "duration": 2 * SEC
    }));
    let action = base.value()["clips"][0]["actions"][0]["id"]
        .as_i64()
        .expect("an action id");
    let wild = base.apply(&json!({
        "op": "set_action_end", "clip": 11, "action": action,
        "patch": {"audio": {"isolation": 2.0}}
    }));
    let state = wild
        .clip_state(11, 2 * SEC)
        .expect("clip_state at the action's end");
    assert_eq!(num(&state, "/audio/isolation"), 1.0);
}

#[test]
fn paste_attributes_carries_isolation_with_the_audio_group() {
    let isolated = two().apply(&set(json!(0.6)));
    let source = isolated.value()["clips"][0].clone();
    let payload = json!({"clips": [source], "media": []});
    let pasted = isolated.apply(&json!({"op": "paste_attributes", "clips": [12],
        "payload": payload, "groups": ["audio"]}));
    assert_eq!(at(&pasted.value(), "/clips/1/audio/isolation"), &json!(0.6));
}
