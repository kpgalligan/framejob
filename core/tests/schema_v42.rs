//! Black-box tests for format version 42, motion blur (spec §11 CU-113):
//! `video.motion_blur`, a number after `behind_subject`, written only above
//! 0, driven through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 42; every earlier version (1
//! to 41), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 41 writes the same text as the
//! same file at 42; and `motion_blur` ROUND TRIPS byte for byte, in its
//! place (after `behind_subject`).

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A file of `version` with one media clip, 3, which carries `video`.
fn file(version: u32, video: Value) -> Value {
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [{"id": 1, "path": "/fixtures/camera.mov", "kind": "video",
                   "duration": 6000000, "width": 1920, "height": 1080,
                   "fps": [30, 1], "has_video": true, "has_audio": true}],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 600000,
             "source": {"kind": "media", "media": 1, "in": 0},
             "video": video}
        ],
        "next_id": 4
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 42,
    "version 42 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=41u32).chain([GRADING_BRANCH_VERSION]) {
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
    for version in [RC_FORMAT_VERSION + 1, 1014, 1016] {
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
fn a_file_at_41_writes_what_it_did_at_42() {
    let video = json!({"scale": 0.5, "behind_subject": true});
    let forty_one = Handle::from_value(&file(41, video.clone())).to_json();
    let forty_two = Handle::from_value(&file(42, video)).to_json();
    assert_eq!(forty_one, forty_two);
    assert!(!forty_two.contains("\"motion_blur\""), "{forty_two}");
}

#[test]
fn motion_blur_round_trips_byte_for_byte_after_behind_subject() {
    let opened = Handle::from_value(&file(
        42,
        json!({"behind_subject": true, "motion_blur": 0.375}),
    ));
    let value = opened.value();
    assert_eq!(at(&value, "/clips/0/video/motion_blur"), &json!(0.375));
    let once = opened.to_json();
    // Its place, read off the written text: right after `behind_subject`.
    let behind = once
        .find("\"behind_subject\": true")
        .expect("behind_subject");
    let blur = once.find("\"motion_blur\": 0.375").expect("motion_blur");
    assert!(behind < blur, "{once}");
    let between = &once[behind + "\"behind_subject\": true".len()..blur];
    assert_eq!(between.trim(), ",", "nothing between the two: {once}");
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
}
