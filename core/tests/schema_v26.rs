//! Black-box tests for format version 26, a PQ still's HDR10 peak (spec §11
//! HD-20 (b)): an image media's `media.color.pq`, driven through the C FFI
//! exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 26; every earlier version (1
//! to 25), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 25 with an S-Log3 setting writes
//! the same text as the same file at 26; and a PQ image's reading ROUND
//! TRIPS byte for byte.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A one-clip file of `version` whose video media carries `color`.
fn file(version: u32, color: Value) -> Value {
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [{"id": 1, "path": "/fixtures/clip.mov", "kind": "video",
                   "duration": 600000, "width": 1920, "height": 1080, "fps": [30, 1],
                   "has_video": true, "color": color}],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 600000,
             "source": {"kind": "media", "media": 1, "in": 0}}
        ],
        "next_id": 4
    })
}

/// A one-clip file of `version` whose image media carries `color`.
fn still_file(version: u32, color: Value) -> Value {
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [{"id": 1, "path": "/fixtures/still_pq.png", "kind": "image",
                   "width": 1024, "height": 128, "color": color}],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 600000,
             "source": {"kind": "image", "media": 1}}
        ],
        "next_id": 4
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 26,
    "version 26 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=25u32).chain([GRADING_BRANCH_VERSION]) {
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
fn an_slog3_file_at_25_writes_what_it_did() {
    let color = json!({"log": "slog3", "gamut": "s_gamut3_cine"});
    let twenty_five = Handle::from_value(&file(25, color.clone())).to_json();
    let twenty_six = Handle::from_value(&file(26, color.clone())).to_json();
    assert_eq!(twenty_five, twenty_six);
    let opened = Handle::from_json(&twenty_six);
    assert_eq!(at(&opened.value(), "/media/0/color"), &color);
}

#[test]
fn a_pq_image_s_reading_round_trips_byte_for_byte() {
    let color = json!({"pq": {"file": 4000, "from": "max_cll"}});
    let opened = Handle::from_value(&still_file(26, color.clone()));
    assert_eq!(at(&opened.value(), "/media/0/color"), &color);
    let once = opened.to_json();
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
    assert_eq!(Handle::from_json(&twice).to_json(), once);
}
