//! Voice effects' model (format 34, spec §11 AU-140), through the FFI:
//! `set_audio {voice}` stored and round-tripped with `pitch` written only
//! when set, `null` clearing it, a patch merging key by key (a new `kind`
//! keeping `amount` and `pitch`, `pitch: null` dropping it), the three
//! refusals in the core's own sentences, a kindless patch over no voice
//! refused, an action end clamped by the evaluator, and `paste_attributes`
//! carrying it with the audio group.

use serde_json::{json, Value};

mod common;
use common::{assert_contains, at, num, Handle};

const SEC: i64 = 600_000;

/// Two 10 s voice clips, 11 and 12, the second after the first.
fn two() -> Handle {
    Handle::from_value(&json!({
        "version": 34,
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

fn set(voice: Value) -> Value {
    json!({"op": "set_audio", "clips": [11], "patch": {"voice": voice}})
}

fn stored(handle: &Handle) -> Value {
    handle.value()["clips"][0]["audio"]
        .get("voice")
        .cloned()
        .unwrap_or(Value::Null)
}

#[test]
fn a_voice_stores_and_round_trips_with_pitch_absent_when_unset() {
    let voiced = two().apply(&set(json!({"kind": "hall"})));
    assert_eq!(stored(&voiced), json!({"kind": "hall", "amount": 1.0}));
    let text = voiced.to_json();
    assert!(!text.contains("\"pitch\""), "{text}");
    assert_eq!(Handle::from_json(&text).to_json(), text);

    let pitched = two().apply(&set(json!({"kind": "high", "amount": 0.5, "pitch": 8.0})));
    assert_eq!(
        stored(&pitched),
        json!({"kind": "high", "amount": 0.5, "pitch": 8.0})
    );
    let text = pitched.to_json();
    assert_eq!(Handle::from_json(&text).to_json(), text);
}

#[test]
fn null_clears_it_and_an_untouched_file_has_no_key() {
    let base = two();
    let written = base.to_json();
    assert!(!written.contains("\"voice\""), "{written}");
    let voiced = base.apply(&set(json!({"kind": "robot", "amount": 0.4})));
    let cleared = voiced.apply(&set(Value::Null));
    assert_eq!(cleared.to_json(), written);
}

#[test]
fn a_kind_change_keeps_amount_and_pitch_and_pitch_null_drops_it() {
    let high = two().apply(&set(json!({"kind": "high", "amount": 0.7, "pitch": 8.0})));
    let robot = high.apply(&set(json!({"kind": "robot"})));
    assert_eq!(
        stored(&robot),
        json!({"kind": "robot", "amount": 0.7, "pitch": 8.0})
    );
    let deep = high.apply(&set(json!({"kind": "deep", "pitch": null})));
    assert_eq!(stored(&deep), json!({"kind": "deep", "amount": 0.7}));
}

#[test]
fn out_of_range_values_and_an_unknown_kind_are_refused_in_the_core_sentences() {
    let voiced = two().apply(&set(json!({"kind": "pitch"})));
    assert_eq!(
        voiced.errors(&set(json!({"amount": 1.5}))),
        "audio.voice.amount must be between 0 and 1, not 1.5"
    );
    assert_eq!(
        voiced.errors(&set(json!({"pitch": 13.0}))),
        "audio.voice.pitch must be between -12 and 12, not 13"
    );
    assert_eq!(
        voiced.errors(&set(json!({"kind": "robo"}))),
        "bad value at \"voice.kind\" in an audio patch: unknown variant `robo`, expected one \
         of `pitch`, `high`, `deep`, `robot`, `bass`, `treble`, `bright`, `telephone`, \
         `radio`, `lofi`, `distorted`, `echo`, `room`, `hall`, `plate`, `cathedral`"
    );
}

#[test]
fn an_amount_alone_over_no_voice_is_refused() {
    assert_contains(
        &two().errors(&set(json!({"amount": 0.5}))),
        "bad value at \"voice\" in an audio patch: missing field `kind`",
    );
}

#[test]
fn an_action_end_past_the_ranges_clamps() {
    let base = two()
        .apply(&set(json!({"kind": "high", "amount": 0.5})))
        .apply(&json!({
            "op": "add_action", "clip": 11, "at": 0, "duration": 2 * SEC
        }));
    let action = base.value()["clips"][0]["actions"][0]["id"]
        .as_i64()
        .expect("an action id");
    let wild = base.apply(&json!({
        "op": "set_action_end", "clip": 11, "action": action,
        "patch": {"audio": {"voice": {"kind": "high", "amount": 3.0, "pitch": 40.0}}}
    }));
    let state = wild
        .clip_state(11, 2 * SEC)
        .expect("clip_state at the action's end");
    assert_eq!(num(&state, "/audio/voice/amount"), 1.0);
    assert_eq!(num(&state, "/audio/voice/pitch"), 12.0);
}

#[test]
fn paste_attributes_carries_the_voice_with_the_audio_group() {
    let voiced = two().apply(&set(json!({"kind": "echo", "amount": 0.6})));
    let source = voiced.value()["clips"][0].clone();
    let payload = json!({"clips": [source], "media": []});
    let pasted = voiced.apply(&json!({"op": "paste_attributes", "clips": [12],
        "payload": payload, "groups": ["audio"]}));
    assert_eq!(
        at(&pasted.value(), "/clips/1/audio/voice"),
        &json!({"kind": "echo", "amount": 0.6})
    );
}
