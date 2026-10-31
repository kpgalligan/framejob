//! Black-box tests for format version 32, EQ, hum and channels (spec §11
//! AU-37): `audio.eq`, `audio.hum` and `audio.channels`, driven through the
//! C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 32; every earlier version (1
//! to 31), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 31 with none of the three writes
//! the same text as the same file at 32; the three ROUND TRIP byte for byte,
//! in their place after `limiter` and `isolation`, each slot in its own order;
//! and
//! `channels: both` is not written.

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
    RC_FORMAT_VERSION >= 32,
    "version 32 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=31u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_at_31_with_none_of_the_three_writes_what_it_did() {
    let audio = json!({"volume": 2.0, "limiter": {"ceiling_db": -2.0, "release": 60_000},
                       "isolation": 0.5});
    let thirty_one = Handle::from_value(&file(31, audio.clone())).to_json();
    let thirty_two = Handle::from_value(&file(32, audio)).to_json();
    assert_eq!(thirty_one, thirty_two);
    for key in ["\"eq\"", "\"hum\"", "\"channels\""] {
        assert!(!thirty_two.contains(key), "{key}: {thirty_two}");
    }
}

#[test]
fn the_three_round_trip_byte_for_byte_in_their_place() {
    let eq = json!({
        "high_pass": {"frequency": 90.0, "slope": 24},
        "low_shelf": {"frequency": 120.0, "gain_db": -2.0},
        "band_1": {"frequency": 300.0, "gain_db": -3.0, "q": 1.0},
        "band_2": {"frequency": 1000.0, "gain_db": 1.5, "q": 2.0},
        "band_3": {"frequency": 4000.0, "gain_db": 3.0, "q": 0.7},
        "high_shelf": {"frequency": 9000.0, "gain_db": 2.0},
        "low_pass": {"frequency": 15000.0, "slope": 12},
        "bypass": true
    });
    let hum = json!({"frequency": 50, "depth_db": 24.0, "harmonics": 8});
    let opened = Handle::from_value(&file(
        32,
        json!({"limiter": {"ceiling_db": -1.0, "release": 60_000}, "isolation": 0.5,
               "eq": eq.clone(), "hum": hum.clone(), "channels": "left"}),
    ));
    let value = opened.value();
    assert_eq!(at(&value, "/clips/0/audio/eq"), &eq);
    assert_eq!(at(&value, "/clips/0/audio/hum"), &hum);
    assert_eq!(at(&value, "/clips/0/audio/channels"), &json!("left"));
    let once = opened.to_json();
    // The keys' places, read off the written text: after `limiter` and
    // `isolation`, in `eq`, `hum`, `channels` order, and the slots in signal
    // order.
    let mut last = once.find("\"limiter\"").expect("limiter");
    for key in [
        "\"isolation\"",
        "\"eq\"",
        "\"high_pass\"",
        "\"low_shelf\"",
        "\"band_1\"",
        "\"band_2\"",
        "\"band_3\"",
        "\"high_shelf\"",
        "\"low_pass\"",
        "\"bypass\"",
        "\"hum\"",
        "\"harmonics\"",
        "\"channels\"",
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
fn both_and_an_unbypassed_empty_eq_write_only_what_is_set() {
    let opened = Handle::from_value(&file(
        32,
        json!({"eq": {"band_2": {}, "bypass": false}, "channels": "both"}),
    ));
    let text = opened.to_json();
    assert!(!text.contains("\"channels\""), "{text}");
    assert!(!text.contains("\"bypass\""), "{text}");
    assert!(!text.contains("\"high_pass\""), "{text}");
    assert_eq!(
        at(&opened.value(), "/clips/0/audio/eq"),
        &json!({"band_2": {"frequency": 1000.0, "gain_db": 0.0, "q": 1.0}})
    );
}
