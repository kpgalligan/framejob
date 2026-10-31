//! A clip's gate and de-esser (format 33, spec §11 AU-43, AU-45, AU-46),
//! through the FFI: `set_audio`'s two keys, every refusal sentence, `null`
//! clearing, `{}` storing the defaults, an action's end clamped into range,
//! and `paste_attributes` carrying both whole and checking them as a patch is
//! checked.

use serde_json::{json, Value};

mod common;
use common::{array, at, num, Handle};

const SEC: i64 = 600_000;

/// One 10 s clip, id 10, on track 2, with `audio` as its props.
fn one(audio: Value) -> Value {
    json!({
        "version": 32,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/fixtures/1.m4a", "kind": "audio",
                   "duration": 60 * SEC, "has_audio": true}],
        "tracks": [{"id": 2, "name": "A"}],
        "clips": [{"id": 10, "track": 2, "start": 0, "duration": 10 * SEC,
                   "source": {"kind": "media", "media": 1, "in": 0}, "audio": audio}],
        "next_id": 100
    })
}

fn set(patch: Value) -> Value {
    json!({"op": "set_audio", "clips": [10], "patch": patch})
}

fn gate_defaults() -> Value {
    json!({"threshold_db": -10.0, "ratio": 4.0, "range_db": 20.0,
           "attack": 600, "hold": 30_000, "release": 60_000})
}

fn de_esser_defaults() -> Value {
    json!({"frequency": 6000.0, "threshold_db": 0.0, "range_db": 6.0})
}

#[test]
fn set_audio_takes_the_two_keys_and_merges_per_field() {
    let handle = Handle::from_value(&one(json!({})));
    let gate = json!({"threshold_db": -15.0, "ratio": 10.0, "range_db": 40.0,
                      "attack": 0, "hold": 0, "release": 600});
    let de_esser = json!({"frequency": 4000.0, "threshold_db": -6.0, "range_db": 3.0});
    let applied = handle.apply(&set(
        json!({"gate": gate.clone(), "de_esser": de_esser.clone()}),
    ));
    let value = applied.value();
    assert_eq!(at(&value, "/clips/0/audio/gate"), &gate);
    assert_eq!(at(&value, "/clips/0/audio/de_esser"), &de_esser);
    let more = applied.apply(&set(json!({"gate": {"hold": 120_000}})));
    assert_eq!(num(&more.value(), "/clips/0/audio/gate/hold"), 120_000.0);
    assert_eq!(num(&more.value(), "/clips/0/audio/gate/ratio"), 10.0);
}

#[test]
fn an_empty_object_stores_the_defaults_and_null_clears() {
    let base = Handle::from_value(&one(json!({})));
    let defaults = base.apply(&set(json!({"gate": {}, "de_esser": {}})));
    let value = defaults.value();
    assert_eq!(at(&value, "/clips/0/audio/gate"), &gate_defaults());
    assert_eq!(at(&value, "/clips/0/audio/de_esser"), &de_esser_defaults());
    let cleared = defaults.apply(&set(json!({"gate": null, "de_esser": null})));
    assert_eq!(cleared.to_json(), base.to_json());
}

#[test]
fn every_bound_is_refused_in_its_own_sentence() {
    let handle = Handle::from_value(&one(json!({})));
    let cases: Vec<(Value, &str)> = vec![
        (
            json!({"gate": {"threshold_db": -41.0}}),
            "audio.gate.threshold_db must be between -40 and 0, not -41",
        ),
        (
            json!({"gate": {"threshold_db": 1.0}}),
            "audio.gate.threshold_db must be between -40 and 0, not 1",
        ),
        (
            json!({"gate": {"ratio": 0.5}}),
            "audio.gate.ratio must be between 1 and 20, not 0.5",
        ),
        (
            json!({"gate": {"ratio": 21.0}}),
            "audio.gate.ratio must be between 1 and 20, not 21",
        ),
        (
            json!({"gate": {"range_db": 0.5}}),
            "audio.gate.range_db must be between 1 and 80, not 0.5",
        ),
        (
            json!({"gate": {"range_db": 81.0}}),
            "audio.gate.range_db must be between 1 and 80, not 81",
        ),
        (
            json!({"gate": {"attack": -1}}),
            "audio.gate.attack must be between 0 and 60000 ticks, not -1",
        ),
        (
            json!({"gate": {"attack": 60_001}}),
            "audio.gate.attack must be between 0 and 60000 ticks, not 60001",
        ),
        (
            json!({"gate": {"hold": 300_001}}),
            "audio.gate.hold must be between 0 and 300000 ticks, not 300001",
        ),
        (
            json!({"gate": {"release": 599}}),
            "audio.gate.release must be between 600 and 1200000 ticks, not 599",
        ),
        (
            json!({"gate": {"release": 1_200_001}}),
            "audio.gate.release must be between 600 and 1200000 ticks, not 1200001",
        ),
        (
            json!({"de_esser": {"frequency": 1999.0}}),
            "audio.de_esser.frequency must be between 2000 and 12000, not 1999",
        ),
        (
            json!({"de_esser": {"frequency": 12_001.0}}),
            "audio.de_esser.frequency must be between 2000 and 12000, not 12001",
        ),
        (
            json!({"de_esser": {"threshold_db": -31.0}}),
            "audio.de_esser.threshold_db must be between -30 and 20, not -31",
        ),
        (
            json!({"de_esser": {"threshold_db": 21.0}}),
            "audio.de_esser.threshold_db must be between -30 and 20, not 21",
        ),
        (
            json!({"de_esser": {"range_db": 0.0}}),
            "audio.de_esser.range_db must be between 1 and 24, not 0",
        ),
        (
            json!({"de_esser": {"range_db": 25.0}}),
            "audio.de_esser.range_db must be between 1 and 24, not 25",
        ),
        (
            json!({"gate": {"knee": 3.0}}),
            "unknown key \"gate.knee\" in an audio patch",
        ),
        (
            json!({"de_esser": {"ratio": 3.0}}),
            "unknown key \"de_esser.ratio\" in an audio patch",
        ),
    ];
    for (patch, expected) in cases {
        assert_eq!(handle.errors(&set(patch.clone())), expected, "{patch}");
    }
    // Each end of each range is inside it.
    for (gate, de_esser) in [
        (
            json!({"threshold_db": -40.0, "ratio": 1.0, "range_db": 1.0,
                   "attack": 0, "hold": 0, "release": 600}),
            json!({"frequency": 2000.0, "threshold_db": -30.0, "range_db": 1.0}),
        ),
        (
            json!({"threshold_db": 0.0, "ratio": 20.0, "range_db": 80.0,
                   "attack": 60_000, "hold": 300_000, "release": 1_200_000}),
            json!({"frequency": 12000.0, "threshold_db": 20.0, "range_db": 24.0}),
        ),
    ] {
        let applied = handle.apply(&set(
            json!({"gate": gate.clone(), "de_esser": de_esser.clone()}),
        ));
        assert_eq!(at(&applied.value(), "/clips/0/audio/gate"), &gate);
        assert_eq!(at(&applied.value(), "/clips/0/audio/de_esser"), &de_esser);
    }
}

#[test]
fn an_actions_end_is_clamped_into_range() {
    let handle = Handle::from_value(&one(json!({"gate": {}, "de_esser": {}})))
        .apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": 2 * SEC}));
    let action = array(&handle.value(), "/clips/0/actions")[0]["id"].clone();
    let ended = handle.apply(&json!({
        "op": "set_action_end", "clip": 10, "action": action,
        "patch": {"audio": {
            "gate": {"threshold_db": -90.0, "ratio": 50.0, "range_db": 200.0,
                     "attack": 90_000, "hold": 900_000, "release": 10},
            "de_esser": {"frequency": 90_000.0, "threshold_db": 40.0, "range_db": 0.0}
        }}
    }));
    let state = ended.clip_state(10, 3 * SEC).expect("clip 10 has a state");
    let audio = at(&state, "/audio");
    assert_eq!(
        at(audio, "/gate"),
        &json!({"threshold_db": -40.0, "ratio": 20.0, "range_db": 80.0,
                "attack": 60_000, "hold": 300_000, "release": 600})
    );
    assert_eq!(
        at(audio, "/de_esser"),
        &json!({"frequency": 12000.0, "threshold_db": 20.0, "range_db": 1.0})
    );
    // The other end of each range.
    let other = ended.apply(&json!({
        "op": "set_action_end", "clip": 10, "action": action,
        "patch": {"audio": {
            "gate": {"threshold_db": 5.0, "ratio": 0.0, "range_db": 0.0,
                     "attack": -5, "hold": -5, "release": 9_000_000},
            "de_esser": {"frequency": 10.0, "threshold_db": -90.0, "range_db": 90.0}
        }}
    }));
    let state = other.clip_state(10, 3 * SEC).expect("clip 10 has a state");
    let audio = at(&state, "/audio");
    assert_eq!(
        at(audio, "/gate"),
        &json!({"threshold_db": 0.0, "ratio": 1.0, "range_db": 1.0,
                "attack": 0, "hold": 0, "release": 1_200_000})
    );
    assert_eq!(
        at(audio, "/de_esser"),
        &json!({"frequency": 2000.0, "threshold_db": -30.0, "range_db": 24.0})
    );
}

#[test]
fn paste_attributes_carries_both_and_checks_them() {
    let handle = Handle::from_value(&json!({
        "version": 32,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/fixtures/1.m4a", "kind": "audio",
                   "duration": 60 * SEC, "has_audio": true}],
        "tracks": [{"id": 2, "name": "A"}],
        "clips": [
            {"id": 10, "track": 2, "start": 0, "duration": 5 * SEC,
             "source": {"kind": "media", "media": 1, "in": 0},
             "audio": {"gate": {"threshold_db": -15.0, "ratio": 10.0},
                       "de_esser": {"frequency": 5000.0}}},
            {"id": 20, "track": 2, "start": 5 * SEC, "duration": 5 * SEC,
             "source": {"kind": "media", "media": 1, "in": 0}, "audio": {}}
        ],
        "next_id": 100
    }));
    let source = array(&handle.value(), "/clips")[0].clone();
    let pasted = handle.apply(&json!({"op": "paste_attributes", "clips": [20],
        "payload": {"clips": [source.clone()], "media": []}, "groups": ["audio"]}));
    let value = pasted.value();
    for key in ["gate", "de_esser"] {
        assert_eq!(
            at(&value, &format!("/clips/1/audio/{key}")),
            at(&source, &format!("/audio/{key}")),
            "{key}"
        );
    }
    let mut bad = source.clone();
    bad["audio"]["gate"]["hold"] = json!(400_000);
    let error = handle.errors(&json!({"op": "paste_attributes", "clips": [20],
        "payload": {"clips": [bad], "media": []}, "groups": ["audio"]}));
    assert!(
        error.contains("audio.gate.hold must be between 0 and 300000 ticks, not 400000"),
        "{error}"
    );
    let mut bad = source;
    bad["audio"]["de_esser"]["range_db"] = json!(30.0);
    let error = handle.errors(&json!({"op": "paste_attributes", "clips": [20],
        "payload": {"clips": [bad], "media": []}, "groups": ["audio"]}));
    assert!(
        error.contains("audio.de_esser.range_db must be between 1 and 24, not 30"),
        "{error}"
    );
}
