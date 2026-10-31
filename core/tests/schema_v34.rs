//! Black-box tests for format version 34, voice effects (spec §11 AU-140):
//! `audio.voice`, driven through the C FFI exactly as `ReelCore.swift`
//! drives it.
//!
//! Pinned here: the current version is at least 34; every earlier version (1
//! to 33), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 33 with no voice writes the same
//! text as the same file at 34; and a voice ROUND TRIPS byte for byte, after
//! `de_esser`, the last field, with its keys in `kind`, `amount`, `pitch`
//! order.

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
    RC_FORMAT_VERSION >= 34,
    "version 34 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=33u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_at_33_with_no_voice_writes_what_it_did() {
    let audio = json!({"volume": 2.0, "isolation": 0.5,
                       "hum": {"frequency": 50, "depth_db": 24.0, "harmonics": 8},
                       "channels": "left", "de_esser": {}});
    let thirty_three = Handle::from_value(&file(33, audio.clone())).to_json();
    let thirty_four = Handle::from_value(&file(34, audio)).to_json();
    assert_eq!(thirty_three, thirty_four);
    assert!(!thirty_four.contains("\"voice\""), "{thirty_four}");
}

#[test]
fn a_voice_round_trips_byte_for_byte_after_de_esser() {
    let voice = json!({"kind": "deep", "amount": 0.75, "pitch": -7.5});
    let opened = Handle::from_value(&file(
        34,
        json!({"isolation": 0.5, "channels": "right", "de_esser": {},
               "voice": voice.clone()}),
    ));
    assert_eq!(at(&opened.value(), "/clips/0/audio/voice"), &voice);
    let once = opened.to_json();
    let mut last = once.find("\"de_esser\"").expect("de_esser");
    for key in ["\"voice\"", "\"kind\"", "\"amount\"", "\"pitch\""] {
        let place = once[last..].find(key).expect(key) + last;
        assert!(place > last, "{key}: {once}");
        last = place;
    }
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
}
