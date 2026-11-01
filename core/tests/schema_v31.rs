//! Black-box tests for format version 31, voice isolation (spec §11 AU-50),
//! driven through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 31; every earlier version (1
//! to 30), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 30 writes the same text as the
//! same file at 31, with no `isolation`; and `isolation` ROUND TRIPS byte for
//! byte when it is not 0, in its place after `limiter`, and is left out when
//! it is 0.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A file of `version`: one voice clip carrying `audio`.
fn file(version: u32, audio: Value) -> Value {
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [{"id": 1, "path": "/fixtures/voice.m4a", "kind": "audio",
                   "duration": 6000000, "has_audio": true}],
        "tracks": [{"id": 2, "name": "Track 1"}],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 1800000,
             "source": {"kind": "media", "media": 1, "in": 0}, "audio": audio}
        ],
        "next_id": 4
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 31,
    "version 31 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=30u32).chain([GRADING_BRANCH_VERSION]) {
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
    for version in [RC_FORMAT_VERSION + 1, 32, 1014, 1016] {
        if version <= RC_FORMAT_VERSION {
            continue;
        }
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
fn a_file_at_30_writes_what_it_did_with_no_isolation() {
    let audio = json!({"fade_in": 300000, "noise_reduction": 0.5});
    let thirty = Handle::from_value(&file(30, audio.clone()));
    let thirty_one = Handle::from_value(&file(31, audio));
    assert_eq!(thirty.to_json(), thirty_one.to_json());
    let text = thirty_one.to_json();
    assert!(!text.contains("isolation"), "isolation written: {text}");
}

#[test]
fn isolation_round_trips_byte_for_byte_after_limiter_and_is_absent_at_zero() {
    let opened = Handle::from_value(&file(
        31,
        json!({"isolation": 0.8, "limiter": {"ceiling_db": -2.0, "release": 60_000}}),
    ));
    let value = opened.value();
    assert_eq!(at(&value, "/clips/0/audio/isolation"), &json!(0.8));
    let once = opened.to_json();
    // The key's place, read off the written text: after `limiter`, the field
    // it follows.
    let limiter = once.find("\"limiter\"").expect("the limiter key");
    let isolation = once.find("\"isolation\"").expect("the isolation key");
    assert!(limiter < isolation, "{once}");
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);

    let zero = Handle::from_value(&file(31, json!({"isolation": 0.0})));
    let text = zero.to_json();
    assert!(
        !text.contains("isolation"),
        "isolation written at 0: {text}"
    );
}
