//! Black-box tests for format version 29, ducking by speech and fade shapes
//! (spec §11 AU-110..AU-116), driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 29; every earlier version (1
//! to 28), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 28 writes the same text as the
//! same file at 29, with none of the new keys; and every new key ROUND TRIPS
//! byte for byte when it is not its default, and is left out when it is.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A file of `version`: a voice with `audio`, an overlapping second clip
/// with `transition`, and a media carrying `speech` when given.
fn file(version: u32, audio: Value, transition: Value, speech: Option<Value>) -> Value {
    let mut media = json!({"id": 1, "path": "/fixtures/voice.m4a", "kind": "audio",
                           "duration": 6000000, "has_audio": true});
    if let Some(speech) = speech {
        media["speech"] = speech;
    }
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [media],
        "tracks": [{"id": 2, "name": "Track 1"}],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 1800000,
             "source": {"kind": "media", "media": 1, "in": 0}, "audio": audio},
            {"id": 4, "track": 2, "start": 1200000, "duration": 1800000,
             "source": {"kind": "media", "media": 1, "in": 1800000}, "audio": {},
             "transition_in": transition}
        ],
        "next_id": 5
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 29,
    "version 29 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=28u32).chain([GRADING_BRANCH_VERSION]) {
        let opened = Handle::from_value(&json!({ "version": version }));
        assert_eq!(
            opened.value()["version"],
            json!(RC_FORMAT_VERSION),
            "version {version}"
        );
    }
}

#[test]
fn past_current_to_1014_and_1016_are_newer() {
    for version in [RC_FORMAT_VERSION + 1, 500, 1014, 1016] {
        let message = Handle::try_from_value(&json!({ "version": version })).expect_err("newer");
        assert_eq!(
            message,
            format!(
                "project format version {version} is newer than this build understands \
                 (version {RC_FORMAT_VERSION}); update Frame Job to open it"
            )
        );
    }
}

#[test]
fn a_file_at_28_writes_what_it_did_with_none_of_the_new_keys() {
    let audio = json!({"fade_in": 300000, "duck": {"level": 0.3, "attack": 1, "release": 2}});
    let transition = json!({"kind": "wipe", "curve": "ease_in", "audio": true});
    let twenty_eight = Handle::from_value(&file(28, audio.clone(), transition.clone(), None));
    let twenty_nine = Handle::from_value(&file(29, audio, transition, None));
    assert_eq!(twenty_eight.to_json(), twenty_nine.to_json());
    let text = twenty_nine.to_json();
    for key in [
        "speech",
        "fade_in_shape",
        "fade_out_shape",
        "audio_shape",
        "\"mode\"",
        "pre_roll",
        "\"hold\"",
    ] {
        assert!(!text.contains(key), "{key} written at its default: {text}");
    }
}

#[test]
fn every_new_key_round_trips_byte_for_byte() {
    let audio = json!({"fade_in_shape": "s_curve", "fade_out_shape": "minus_3db",
                       "duck": {"level": 0.3, "attack": 1, "release": 2, "mode": "speech",
                                "pre_roll": 0, "hold": 900000}});
    let transition = json!({"kind": "cross_dissolve", "curve": "linear", "audio": true,
                            "audio_shape": "linear"});
    let speech = json!([[0, 600000], [900000, 1500000]]);
    let opened = Handle::from_value(&file(29, audio, transition, Some(speech.clone())));
    let value = opened.value();
    assert_eq!(at(&value, "/media/0/speech"), &speech);
    assert_eq!(
        at(&value, "/clips/0/audio/fade_in_shape"),
        &json!("s_curve")
    );
    assert_eq!(
        at(&value, "/clips/0/audio/fade_out_shape"),
        &json!("minus_3db")
    );
    assert_eq!(at(&value, "/clips/0/audio/duck/mode"), &json!("speech"));
    assert_eq!(at(&value, "/clips/0/audio/duck/pre_roll"), &json!(0));
    assert_eq!(at(&value, "/clips/0/audio/duck/hold"), &json!(900000));
    assert_eq!(
        at(&value, "/clips/1/transition_in/audio_shape"),
        &json!("linear")
    );
    let once = opened.to_json();
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
}

#[test]
fn an_unknown_shape_or_mode_is_refused_on_read() {
    let bad = file(29, json!({"fade_in_shape": "cubic"}), json!({}), None);
    let message = Handle::try_from_value(&bad).expect_err("unknown shape");
    assert!(message.contains("unknown variant"), "{message}");
    let bad = file(29, json!({"duck": {"mode": "voice"}}), json!({}), None);
    let message = Handle::try_from_value(&bad).expect_err("unknown mode");
    assert!(message.contains("unknown variant"), "{message}");
}
