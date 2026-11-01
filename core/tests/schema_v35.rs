//! Black-box tests for format version 35, a track's volume and pan (spec §11
//! AU-102): `tracks[].volume` and `tracks[].pan`, driven through the C FFI
//! exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 35; every earlier version (1
//! to 34), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 34 whose tracks carry neither key
//! writes the same text as the same file at 35, with no `volume` or `pan` on
//! a track; and a track's volume and pan ROUND TRIP byte for byte, after
//! `matte`, in `volume`, `pan` order, on the timeline's tracks and a nest's.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A one-clip file of `version` whose track 2 is `track` and whose nest 5
/// has one track, `inner`.
fn file(version: u32, track: Value, inner: Value) -> Value {
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [{"id": 1, "path": "/fixtures/tone.wav", "kind": "audio",
                   "duration": 6000000, "has_video": false, "has_audio": true}],
        "tracks": [track],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 600000,
             "source": {"kind": "media", "media": 1, "in": 0}},
            {"id": 4, "track": 2, "start": 600000, "duration": 600000,
             "source": {"kind": "nest", "project": 5}}
        ],
        "next_id": 9,
        "nests": [{"id": 5, "name": "Nest 1", "width": 1920, "height": 1080,
                   "tracks": [inner],
                   "clips": [{"id": 7, "track": 6, "start": 0, "duration": 600000,
                              "source": {"kind": "media", "media": 1, "in": 0}}]}]
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 35,
    "version 35 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=34u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_at_34_with_default_tracks_writes_what_it_did() {
    let track = json!({"id": 2, "name": "Track 1", "solo": true, "matte": "luma"});
    let inner = json!({"id": 6, "name": "Inner", "muted": true});
    let thirty_four = Handle::from_value(&file(34, track.clone(), inner.clone())).to_json();
    let thirty_five = Handle::from_value(&file(35, track, inner)).to_json();
    assert_eq!(thirty_four, thirty_five);
    assert!(!thirty_five.contains("\"volume\""), "{thirty_five}");
    assert!(!thirty_five.contains("\"pan\""), "{thirty_five}");
}

#[test]
fn volume_and_pan_round_trip_byte_for_byte_after_matte() {
    let opened = Handle::from_value(&file(
        35,
        json!({"id": 2, "name": "Track 1", "matte": "alpha", "volume": 0.5, "pan": -0.25}),
        json!({"id": 6, "name": "Inner", "volume": 2.0, "pan": 1.0}),
    ));
    let value = opened.value();
    assert_eq!(at(&value, "/tracks/0/volume"), &json!(0.5));
    assert_eq!(at(&value, "/tracks/0/pan"), &json!(-0.25));
    assert_eq!(at(&value, "/nests/0/tracks/0/volume"), &json!(2.0));
    assert_eq!(at(&value, "/nests/0/tracks/0/pan"), &json!(1.0));
    let once = opened.to_json();
    let mut last = once.find("\"matte\"").expect("matte");
    for key in ["\"volume\"", "\"pan\""] {
        let place = once[last..].find(key).expect(key) + last;
        assert!(place > last, "{key}: {once}");
        last = place;
    }
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
}

#[test]
fn a_volume_alone_writes_no_pan_and_a_pan_alone_no_volume() {
    let opened = Handle::from_value(&file(
        35,
        json!({"id": 2, "name": "Track 1", "volume": 0.25}),
        json!({"id": 6, "name": "Inner", "pan": 0.5}),
    ));
    let value = opened.value();
    assert!(value["tracks"][0].get("pan").is_none(), "{value}");
    assert!(
        value["nests"][0]["tracks"][0].get("volume").is_none(),
        "{value}"
    );
}
