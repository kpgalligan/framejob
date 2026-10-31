//! Black-box tests for format version 36, a track's compressor and limiter
//! (spec §11 AU-150): `tracks[].compressor` and `tracks[].limiter`, driven
//! through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 36; every earlier version (1
//! to 35), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 35 whose tracks carry neither key
//! writes the same text as the same file at 36, with no `compressor` or
//! `limiter` on a track; and both ROUND TRIP byte for byte, after `pan`, in
//! `compressor`, `limiter` order.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A one-clip file of `version` whose track 2 is `track`.
fn file(version: u32, track: Value) -> Value {
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [{"id": 1, "path": "/fixtures/tone.wav", "kind": "audio",
                   "duration": 6000000, "has_video": false, "has_audio": true}],
        "tracks": [track],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 600000,
             "source": {"kind": "media", "media": 1, "in": 0}}
        ],
        "next_id": 4
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 36,
    "version 36 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=35u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_at_35_with_undynamic_tracks_writes_what_it_did() {
    let track = json!({"id": 2, "name": "Track 1", "volume": 0.5, "pan": 0.25});
    let thirty_five = Handle::from_value(&file(35, track.clone())).to_json();
    let thirty_six = Handle::from_value(&file(36, track)).to_json();
    assert_eq!(thirty_five, thirty_six);
    assert!(!thirty_six.contains("\"compressor\""), "{thirty_six}");
    assert!(!thirty_six.contains("\"limiter\""), "{thirty_six}");
}

#[test]
fn compressor_and_limiter_round_trip_byte_for_byte_after_pan() {
    let opened = Handle::from_value(&file(
        36,
        json!({"id": 2, "name": "Track 1", "pan": -0.25,
               "compressor": {"threshold_db": -20.0, "ratio": 4.0, "attack": 6000,
                              "release": 120000, "makeup_db": 3.0},
               "limiter": {"ceiling_db": -6.0, "release": 60000}}),
    ));
    let value = opened.value();
    assert_eq!(at(&value, "/tracks/0/compressor/ratio"), &json!(4.0));
    assert_eq!(at(&value, "/tracks/0/limiter/ceiling_db"), &json!(-6.0));
    let once = opened.to_json();
    let mut last = once.find("\"pan\"").expect("pan");
    for key in ["\"compressor\"", "\"limiter\""] {
        let place = once[last..].find(key).expect(key) + last;
        assert!(place > last, "{key}: {once}");
        last = place;
    }
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
}

#[test]
fn a_limiter_alone_writes_no_compressor() {
    let opened = Handle::from_value(&file(
        36,
        json!({"id": 2, "name": "Track 1", "limiter": {"ceiling_db": -3.0}}),
    ));
    let value = opened.value();
    assert!(value["tracks"][0].get("compressor").is_none(), "{value}");
    assert_eq!(
        at(&value, "/tracks/0/limiter"),
        &json!({"ceiling_db": -3.0, "release": 60000})
    );
}
