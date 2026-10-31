//! Black-box tests for format version 37, the leveller (spec §11 AU-66):
//! `audio.leveller`, driven through the C FFI exactly as `ReelCore.swift`
//! drives it.
//!
//! Pinned here: the current version is at least 37; every earlier version (1
//! to 36), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 36 without the key writes the
//! same text as the same file at 37; the leveller ROUND TRIPS byte for byte,
//! in its place after `voice`, each field in its own order; and `{}` stores
//! and writes its defaults.

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
    RC_FORMAT_VERSION >= 37,
    "version 37 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=36u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_at_36_without_the_key_writes_what_it_did() {
    let audio = json!({"volume": 2.0, "gate": {}, "de_esser": {},
                       "voice": {"kind": "robot", "amount": 0.5}});
    let thirty_six = Handle::from_value(&file(36, audio.clone())).to_json();
    let thirty_seven = Handle::from_value(&file(37, audio)).to_json();
    assert_eq!(thirty_six, thirty_seven);
    assert!(!thirty_seven.contains("\"leveller\""), "{thirty_seven}");
}

#[test]
fn the_leveller_round_trips_byte_for_byte_in_its_place() {
    let leveller = json!({"target_db": -3.0, "max_up_db": 18.0, "max_down_db": 6.0,
                          "response": 2_400_000});
    let opened = Handle::from_value(&file(
        37,
        json!({"gate": {}, "de_esser": {},
               "voice": {"kind": "robot", "amount": 0.5},
               "leveller": leveller.clone()}),
    ));
    let value = opened.value();
    assert_eq!(at(&value, "/clips/0/audio/leveller"), &leveller);
    let once = opened.to_json();
    // The key's place, read off the written text: after `voice`, and its
    // fields in declaration order.
    let mut last = once.find("\"voice\"").expect("voice");
    for key in [
        "\"leveller\"",
        "\"target_db\"",
        "\"max_up_db\"",
        "\"max_down_db\"",
        "\"response\"",
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
    let opened = Handle::from_value(&file(37, json!({"leveller": {}})));
    assert_eq!(
        at(&opened.value(), "/clips/0/audio/leveller"),
        &json!({"target_db": 0.0, "max_up_db": 12.0, "max_down_db": 12.0,
                "response": 1_200_000})
    );
}
