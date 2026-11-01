//! A clip's EQ, hum notch and channel pick (format 32, spec §11 AU-31,
//! AU-33, AU-34, AU-37), through the FFI: `set_audio`'s three keys, every
//! refusal sentence, `null` clearing a slot or the group, `{}` storing the
//! defaults, an action's end clamped into range, and `paste_attributes`
//! carrying the three whole and checking them as a patch is checked.

use serde_json::{json, Value};

mod common;
use common::{array, at, num, Handle};

const SEC: i64 = 600_000;

/// One 10 s clip, id 10, on track 2, with `audio` as its props.
fn one(audio: Value) -> Value {
    json!({
        "version": 31,
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

#[test]
fn set_audio_takes_the_three_keys() {
    let handle = Handle::from_value(&one(json!({})));
    let eq = json!({
        "high_pass": {"frequency": 80.0, "slope": 24},
        "band_1": {"frequency": 300.0, "gain_db": -3.0, "q": 1.0},
        "band_3": {"frequency": 4000.0, "gain_db": 3.0, "q": 1.0}
    });
    let hum = json!({"frequency": 50, "depth_db": 48.0, "harmonics": 8});
    let applied = handle.apply(&set(
        json!({"eq": eq.clone(), "hum": hum.clone(), "channels": "right"}),
    ));
    let value = applied.value();
    assert_eq!(at(&value, "/clips/0/audio/eq"), &eq);
    assert_eq!(at(&value, "/clips/0/audio/hum"), &hum);
    assert_eq!(at(&value, "/clips/0/audio/channels"), &json!("right"));
    // A slot patch merges per key: the low-pass joins, the rest stay.
    let more = applied.apply(&set(json!({"eq": {"low_pass": {"frequency": 9000.0}}})));
    assert_eq!(
        at(&more.value(), "/clips/0/audio/eq/low_pass"),
        &json!({"frequency": 9000.0, "slope": 12})
    );
    assert_eq!(at(&more.value(), "/clips/0/audio/eq/band_1"), &eq["band_1"]);
    for pick in ["both", "left", "swapped"] {
        let picked = applied.apply(&set(json!({"channels": pick})));
        let stored = picked.value()["clips"][0]["audio"]["channels"].clone();
        if pick == "both" {
            assert_eq!(stored, Value::Null, "both is not written");
        } else {
            assert_eq!(stored, json!(pick));
        }
    }
}

#[test]
fn an_empty_object_stores_each_slots_defaults() {
    let handle = Handle::from_value(&one(json!({})));
    let defaults = handle.apply(&set(json!({"eq": {
        "high_pass": {}, "low_shelf": {}, "band_1": {}, "band_2": {}, "band_3": {},
        "high_shelf": {}, "low_pass": {}
    }, "hum": {}})));
    let value = defaults.value();
    assert_eq!(
        at(&value, "/clips/0/audio/eq"),
        &json!({
            "high_pass": {"frequency": 80.0, "slope": 12},
            "low_shelf": {"frequency": 100.0, "gain_db": 0.0},
            "band_1": {"frequency": 1000.0, "gain_db": 0.0, "q": 1.0},
            "band_2": {"frequency": 1000.0, "gain_db": 0.0, "q": 1.0},
            "band_3": {"frequency": 1000.0, "gain_db": 0.0, "q": 1.0},
            "high_shelf": {"frequency": 8000.0, "gain_db": 0.0},
            "low_pass": {"frequency": 12000.0, "slope": 12}
        })
    );
    assert_eq!(
        at(&value, "/clips/0/audio/hum"),
        &json!({"frequency": 60, "depth_db": 30.0, "harmonics": 4})
    );
    // `{eq: {}}` is an EQ with every slot off, and it is written.
    let empty = handle.apply(&set(json!({"eq": {}})));
    assert_eq!(at(&empty.value(), "/clips/0/audio/eq"), &json!({}));
}

#[test]
fn null_clears_a_slot_or_the_group() {
    let base = Handle::from_value(&one(json!({})));
    let set_all = base.apply(&set(json!({
        "eq": {"high_pass": {}, "band_2": {"gain_db": 2.0}, "bypass": true},
        "hum": {}, "channels": "swapped"
    })));
    let slot_cleared = set_all.apply(&set(json!({"eq": {"high_pass": null}})));
    assert_eq!(
        at(&slot_cleared.value(), "/clips/0/audio/eq"),
        &json!({"band_2": {"frequency": 1000.0, "gain_db": 2.0, "q": 1.0}, "bypass": true})
    );
    let cleared = set_all.apply(&set(json!({"eq": null, "hum": null, "channels": "both"})));
    assert_eq!(cleared.to_json(), base.to_json());
}

#[test]
fn every_bound_is_refused_in_its_own_sentence() {
    let handle = Handle::from_value(&one(json!({})));
    let cases: Vec<(Value, &str)> = vec![
        (
            json!({"eq": {"high_pass": {"frequency": 5.0}}}),
            "audio.eq.high_pass.frequency must be between 20 and 20000, not 5",
        ),
        (
            json!({"eq": {"low_pass": {"frequency": 20001.0}}}),
            "audio.eq.low_pass.frequency must be between 20 and 20000, not 20001",
        ),
        (
            json!({"eq": {"high_pass": {"slope": 18}}}),
            "audio.eq.high_pass.slope must be 12 or 24, not 18",
        ),
        (
            json!({"eq": {"low_pass": {"slope": 6}}}),
            "audio.eq.low_pass.slope must be 12 or 24, not 6",
        ),
        (
            json!({"eq": {"low_shelf": {"frequency": 10.0}}}),
            "audio.eq.low_shelf.frequency must be between 20 and 20000, not 10",
        ),
        (
            json!({"eq": {"low_shelf": {"gain_db": 30.0}}}),
            "audio.eq.low_shelf.gain_db must be between -24 and 24, not 30",
        ),
        (
            json!({"eq": {"high_shelf": {"gain_db": -25.0}}}),
            "audio.eq.high_shelf.gain_db must be between -24 and 24, not -25",
        ),
        (
            json!({"eq": {"high_shelf": {"frequency": 30000.0}}}),
            "audio.eq.high_shelf.frequency must be between 20 and 20000, not 30000",
        ),
        (
            json!({"eq": {"band_1": {"frequency": 19.0}}}),
            "audio.eq.band_1.frequency must be between 20 and 20000, not 19",
        ),
        (
            json!({"eq": {"band_2": {"gain_db": 30.0}}}),
            "audio.eq.band_2.gain_db must be between -24 and 24, not 30",
        ),
        (
            json!({"eq": {"band_3": {"q": 0.0}}}),
            "audio.eq.band_3.q must be between 0.1 and 10, not 0",
        ),
        (
            json!({"eq": {"band_1": {"q": 11.0}}}),
            "audio.eq.band_1.q must be between 0.1 and 10, not 11",
        ),
        (
            json!({"hum": {"frequency": 55}}),
            "audio.hum.frequency must be 50 or 60, not 55",
        ),
        (
            json!({"hum": {"depth_db": 3.0}}),
            "audio.hum.depth_db must be between 6 and 60, not 3",
        ),
        (
            json!({"hum": {"depth_db": 61.0}}),
            "audio.hum.depth_db must be between 6 and 60, not 61",
        ),
        (
            json!({"hum": {"harmonics": 9}}),
            "audio.hum.harmonics must be between 1 and 8, not 9",
        ),
        (
            json!({"hum": {"harmonics": 0}}),
            "audio.hum.harmonics must be between 1 and 8, not 0",
        ),
        (
            json!({"eq": {"band_4": {}}}),
            "unknown key \"eq.band_4\" in an audio patch",
        ),
        (
            json!({"hum": {"depth": 3.0}}),
            "unknown key \"hum.depth\" in an audio patch",
        ),
    ];
    for (patch, expected) in cases {
        assert_eq!(handle.errors(&set(patch.clone())), expected, "{patch}");
    }
    // A pick the vocabulary does not have is serde's variant error.
    let error = handle.errors(&set(json!({"channels": "centre"})));
    assert!(error.contains("unknown variant `centre`"), "{error}");
    // Each end of each range is inside it.
    for (eq, hum) in [
        (
            json!({"high_pass": {"frequency": 20.0, "slope": 12},
                   "band_1": {"frequency": 20.0, "gain_db": -24.0, "q": 0.1}}),
            json!({"frequency": 50, "depth_db": 6.0, "harmonics": 1}),
        ),
        (
            json!({"low_pass": {"frequency": 20000.0, "slope": 24},
                   "band_3": {"frequency": 20000.0, "gain_db": 24.0, "q": 10.0}}),
            json!({"frequency": 60, "depth_db": 60.0, "harmonics": 8}),
        ),
    ] {
        let applied = handle.apply(&set(json!({"eq": eq.clone(), "hum": hum.clone()})));
        assert_eq!(at(&applied.value(), "/clips/0/audio/eq"), &eq);
        assert_eq!(at(&applied.value(), "/clips/0/audio/hum"), &hum);
    }
}

#[test]
fn an_actions_end_is_clamped_into_range() {
    let handle = Handle::from_value(&one(json!({
        "eq": {"high_pass": {}, "band_2": {}, "low_pass": {}}, "hum": {}
    })))
    .apply(&json!({"op": "add_action", "clip": 10, "at": 0, "duration": 2 * SEC}));
    let action = array(&handle.value(), "/clips/0/actions")[0]["id"].clone();
    let ended = handle.apply(&json!({
        "op": "set_action_end", "clip": 10, "action": action,
        "patch": {"audio": {
            "eq": {"high_pass": {"frequency": 5.0, "slope": 18},
                   "band_2": {"frequency": 90_000.0, "gain_db": 40.0, "q": 0.0},
                   "low_pass": {"slope": 17}},
            "hum": {"frequency": 55, "depth_db": 100.0, "harmonics": 12}
        }}
    }));
    let state = ended.clip_state(10, 3 * SEC).expect("clip 10 has a state");
    let audio = at(&state, "/audio");
    assert_eq!(num(audio, "/eq/high_pass/frequency"), 20.0);
    assert_eq!(at(audio, "/eq/high_pass/slope"), &json!(24));
    assert_eq!(num(audio, "/eq/band_2/frequency"), 20_000.0);
    assert_eq!(num(audio, "/eq/band_2/gain_db"), 24.0);
    assert_eq!(num(audio, "/eq/band_2/q"), 0.1);
    assert_eq!(at(audio, "/eq/low_pass/slope"), &json!(12));
    assert_eq!(at(audio, "/hum/frequency"), &json!(60));
    assert_eq!(num(audio, "/hum/depth_db"), 60.0);
    assert_eq!(at(audio, "/hum/harmonics"), &json!(8));
    // The other side of each rounding rule.
    let other = ended.apply(&json!({
        "op": "set_action_end", "clip": 10, "action": action,
        "patch": {"audio": {"hum": {"frequency": 54, "depth_db": 1.0, "harmonics": 0}}}
    }));
    let state = other.clip_state(10, 3 * SEC).expect("clip 10 has a state");
    let hum = at(&state, "/audio/hum");
    assert_eq!(
        hum,
        &json!({"frequency": 50, "depth_db": 6.0, "harmonics": 1})
    );
}

#[test]
fn paste_attributes_carries_the_three_and_checks_them() {
    let handle = Handle::from_value(&json!({
        "version": 31,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/fixtures/1.m4a", "kind": "audio",
                   "duration": 60 * SEC, "has_audio": true}],
        "tracks": [{"id": 2, "name": "A"}],
        "clips": [
            {"id": 10, "track": 2, "start": 0, "duration": 5 * SEC,
             "source": {"kind": "media", "media": 1, "in": 0},
             "audio": {"eq": {"high_pass": {"frequency": 80.0, "slope": 24},
                              "band_3": {"frequency": 4000.0, "gain_db": 3.0, "q": 1.0}},
                       "hum": {"frequency": 50, "depth_db": 24.0, "harmonics": 2},
                       "channels": "left"}},
            {"id": 20, "track": 2, "start": 5 * SEC, "duration": 5 * SEC,
             "source": {"kind": "media", "media": 1, "in": 0}, "audio": {}}
        ],
        "next_id": 100
    }));
    let source = array(&handle.value(), "/clips")[0].clone();
    let pasted = handle.apply(&json!({"op": "paste_attributes", "clips": [20],
        "payload": {"clips": [source.clone()], "media": []}, "groups": ["audio"]}));
    let value = pasted.value();
    for key in ["eq", "hum", "channels"] {
        assert_eq!(
            at(&value, &format!("/clips/1/audio/{key}")),
            at(&source, &format!("/audio/{key}")),
            "{key}"
        );
    }
    // A hand-written payload out of range meets the patch's sentence.
    let mut bad = source.clone();
    bad["audio"]["eq"]["band_3"]["q"] = json!(0.0);
    let error = handle.errors(&json!({"op": "paste_attributes", "clips": [20],
        "payload": {"clips": [bad], "media": []}, "groups": ["audio"]}));
    assert!(
        error.contains("audio.eq.band_3.q must be between 0.1 and 10, not 0"),
        "{error}"
    );
    let mut bad = source;
    bad["audio"]["hum"]["harmonics"] = json!(9);
    let error = handle.errors(&json!({"op": "paste_attributes", "clips": [20],
        "payload": {"clips": [bad], "media": []}, "groups": ["audio"]}));
    assert!(
        error.contains("audio.hum.harmonics must be between 1 and 8, not 9"),
        "{error}"
    );
}
