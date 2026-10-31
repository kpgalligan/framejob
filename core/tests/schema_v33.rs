//! Black-box tests for format version 33, the gate and de-esser (spec §11
//! AU-46): `audio.gate` and `audio.de_esser`, driven through the C FFI
//! exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 33; every earlier version (1
//! to 32), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 32 with neither key writes the
//! same text as the same file at 33; the two ROUND TRIP byte for byte, in
//! their place after `channels`, each field in its own order; and `{}`
//! stores and writes each one's defaults.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A one-clip file of `version` whose clip 3 carries `audio`.
fn file(version: u32, audio: Value) -> Value {
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [{"id": 1, "path": "/fixtures/voice.m4a", "kind": "audio",
                   "duration": 6000000, "has_video": false, "has_audio": true}],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 600000,
             "source": {"kind": "media", "media": 1, "in": 0},
             "audio": audio}
        ],
        "next_id": 4
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 33,
    "version 33 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=32u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_at_32_with_neither_key_writes_what_it_did() {
    let audio = json!({"volume": 2.0, "isolation": 0.5,
                       "hum": {"frequency": 50, "depth_db": 24.0, "harmonics": 2},
                       "channels": "left"});
    let thirty_two = Handle::from_value(&file(32, audio.clone())).to_json();
    let thirty_three = Handle::from_value(&file(33, audio)).to_json();
    assert_eq!(thirty_two, thirty_three);
    for key in ["\"gate\"", "\"de_esser\""] {
        assert!(!thirty_three.contains(key), "{key}: {thirty_three}");
    }
}

#[test]
fn the_two_round_trip_byte_for_byte_in_their_place() {
    let gate = json!({"threshold_db": -12.0, "ratio": 10.0, "range_db": 40.0,
                      "attack": 1200, "hold": 60_000, "release": 150_000});
    let de_esser = json!({"frequency": 5000.0, "threshold_db": -3.0, "range_db": 10.0});
    let opened = Handle::from_value(&file(
        33,
        json!({"hum": {"frequency": 60, "depth_db": 30.0, "harmonics": 4},
               "channels": "right", "gate": gate.clone(), "de_esser": de_esser.clone()}),
    ));
    let value = opened.value();
    assert_eq!(at(&value, "/clips/0/audio/gate"), &gate);
    assert_eq!(at(&value, "/clips/0/audio/de_esser"), &de_esser);
    let once = opened.to_json();
    // The keys' places, read off the written text: after `channels`, gate
    // then de-esser, and each one's fields in declaration order.
    let mut last = once.find("\"channels\"").expect("channels");
    for key in [
        "\"gate\"",
        "\"threshold_db\"",
        "\"ratio\"",
        "\"range_db\"",
        "\"attack\"",
        "\"hold\"",
        "\"release\"",
        "\"de_esser\"",
        "\"frequency\"",
        "\"threshold_db\"",
        "\"range_db\"",
    ] {
        let place = once[last..].find(key).expect(key) + last;
        assert!(place > last, "{key}: {once}");
        last = place;
    }
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
    assert_eq!(Handle::from_json(&twice).to_json(), once);
}

#[test]
fn an_empty_object_reads_as_the_defaults() {
    let opened = Handle::from_value(&file(33, json!({"gate": {}, "de_esser": {}})));
    let value = opened.value();
    assert_eq!(
        at(&value, "/clips/0/audio/gate"),
        &json!({"threshold_db": -10.0, "ratio": 4.0, "range_db": 20.0,
                "attack": 600, "hold": 30_000, "release": 60_000})
    );
    assert_eq!(
        at(&value, "/clips/0/audio/de_esser"),
        &json!({"frequency": 6000.0, "threshold_db": 0.0, "range_db": 6.0})
    );
}
