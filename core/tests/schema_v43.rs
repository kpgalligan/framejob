//! Black-box tests for format version 43, hide while silent (spec §11
//! CO-90, CO-91): `video.hide_silent`, `{media, pre_roll, hold, fade}` after
//! `motion_blur`, written only when set, driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 43; every earlier version (1
//! to 42), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 42 writes the same text as the
//! same file at 43; `hide_silent` ROUND TRIPS byte for byte, in its place
//! (after `motion_blur`), all four keys written; and `{}` reads as the
//! defaults with media 0.

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
    RC_FORMAT_VERSION >= 43,
    "version 43 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=42u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_at_42_writes_what_it_did_at_43() {
    let video = json!({"scale": 0.5, "motion_blur": 0.5});
    let forty_two = Handle::from_value(&file(42, video.clone())).to_json();
    let forty_three = Handle::from_value(&file(43, video)).to_json();
    assert_eq!(forty_two, forty_three);
    assert!(!forty_three.contains("\"hide_silent\""), "{forty_three}");
}

#[test]
fn hide_silent_round_trips_byte_for_byte_after_motion_blur() {
    let opened = Handle::from_value(&file(
        43,
        json!({"motion_blur": 0.25,
               "hide_silent": {"media": 1, "pre_roll": 1, "hold": 2, "fade": 3}}),
    ));
    let value = opened.value();
    assert_eq!(
        at(&value, "/clips/0/video/hide_silent"),
        &json!({"media": 1, "pre_roll": 1, "hold": 2, "fade": 3})
    );
    let once = opened.to_json();
    // Its place, read off the written text: right after `motion_blur`, its
    // four keys in order.
    let blur = once.find("\"motion_blur\": 0.25").expect("motion_blur");
    let gate = once.find("\"hide_silent\"").expect("hide_silent");
    assert!(blur < gate, "{once}");
    let between = &once[blur + "\"motion_blur\": 0.25".len()..gate];
    assert_eq!(between.trim(), ",", "nothing between the two: {once}");
    let keys: Vec<usize> = [
        "\"media\": 1",
        "\"pre_roll\": 1",
        "\"hold\": 2",
        "\"fade\": 3",
    ]
    .iter()
    .map(|k| once[gate..].find(k).expect("a key") + gate)
    .collect();
    assert!(keys.windows(2).all(|w| w[0] < w[1]), "{once}");
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
}

#[test]
fn an_empty_gate_reads_as_the_defaults_with_media_zero_and_writes_all_four_keys() {
    let opened = Handle::from_value(&file(43, json!({"hide_silent": {}})));
    assert_eq!(
        at(&opened.value(), "/clips/0/video/hide_silent"),
        &json!({"media": 0, "pre_roll": 120000, "hold": 900000, "fade": 180000})
    );
}
