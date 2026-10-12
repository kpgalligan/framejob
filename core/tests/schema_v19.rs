//! Black-box tests for format version 19, camera log (spec §11 GR-16): the
//! optional `media.color` key, driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is 19; every earlier version (1 to 18),
//! and a file numbered 1015 (GR-9's branch number, read as 15), opens
//! stamped current; every number past the current one, 1014 included, and
//! 1016 are refused as newer; a file with no Camera Log at 18 writes the
//! same text as the same file at 19; a media's `color` is written with its
//! keys in the order `log`, `gamut`, `lut`, `detected`, each only when set;
//! and a file with Camera Log ROUND TRIPS byte for byte.

mod common;

use reelcut_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// One video media with `color` (none for `Value::Null`), a LUT media, and a
/// clip of the video, in a file of `version`.
fn file(version: u32, color: Value) -> Value {
    let mut video = json!({"id": 1, "path": "/fixtures/log.mov", "kind": "video",
        "duration": 600000, "width": 1024, "height": 128, "fps": [30, 1],
        "has_video": true});
    if !color.is_null() {
        video["color"] = color;
    }
    json!({
        "version": version,
        "canvas": { "width": 1024, "height": 128, "fps": [30, 1] },
        "media": [video,
                  {"id": 2, "path": "/fixtures/look.cube", "kind": "lut"}],
        "tracks": [{ "id": 3, "name": "Track 1" }],
        "clips": [
            {"id": 4, "track": 3, "start": 0, "duration": 600000,
             "source": {"kind": "media", "media": 1, "in": 0}}
        ],
        "next_id": 5
    })
}

#[test]
fn the_current_version_is_19() {
    assert_eq!(RC_FORMAT_VERSION, 19);
}

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=18u32).chain([GRADING_BRANCH_VERSION]) {
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
                 (version {RC_FORMAT_VERSION}); update Reelcut to open it"
            )
        );
    }
}

#[test]
fn a_file_with_no_camera_log_at_18_writes_what_it_did() {
    let eighteen = Handle::from_value(&file(18, Value::Null)).to_json();
    let nineteen = Handle::from_value(&file(19, Value::Null)).to_json();
    assert_eq!(eighteen, nineteen);
    assert!(!nineteen.contains("\"color\""), "{nineteen}");
}

#[test]
fn a_colour_is_written_log_gamut_lut_detected_each_only_when_set() {
    let detected = json!({"detected": true, "gamut": "bt2020", "log": "apple_log"});
    let text = Handle::from_value(&file(19, detected)).to_json();
    let log = text.find("\"log\"").expect("log");
    let gamut = text.find("\"gamut\"").expect("gamut");
    let flag = text.find("\"detected\"").expect("detected");
    assert!(log < gamut && gamut < flag, "{text}");
    assert!(!text.contains("\"lut\":"), "{text}");

    let opened = Handle::from_value(&file(19, json!({"lut": 2, "detected": false})));
    assert_eq!(at(&opened.value(), "/media/0/color"), &json!({"lut": 2}));
    let lut = opened.to_json();
    for absent in ["\"log\"", "\"gamut\"", "\"detected\""] {
        assert!(!lut.contains(absent), "{absent} in {lut}");
    }
}

#[test]
fn a_file_with_camera_log_round_trips_byte_for_byte() {
    for color in [
        json!({"log": "slog3", "gamut": "s_gamut3"}),
        json!({"log": "apple_log2", "gamut": "apple_wide_gamut", "detected": true}),
        json!({"lut": 2}),
    ] {
        let opened = Handle::from_value(&file(19, color.clone()));
        assert_eq!(at(&opened.value(), "/media/0/color"), &color);
        let once = opened.to_json();
        let twice = Handle::from_json(&once).to_json();
        assert_eq!(twice, once);
        assert_eq!(Handle::from_json(&twice).to_json(), once);
    }
}
