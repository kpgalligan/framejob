//! Black-box tests for format version 17, the curves (spec §11 GR-12): the
//! optional `video.curves` key, driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! Pinned here: every earlier version (1 to 16), and a file numbered 1015
//! (GR-9's branch number, read as 15), opens stamped current; every number
//! past the current one, 1014 included, and 1016 are refused as newer; an
//! uncurved file at 16 writes the same text as the same file at 17; an
//! identity channel in a file reads as no curve and is not written back;
//! and a curved file ROUND TRIPS byte for byte.

mod common;

use reelcut_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// One shape clip, in a file of `version`, with `video` as given.
fn file(version: u32, video: Value) -> Value {
    json!({
        "version": version,
        "canvas": { "width": 640, "height": 360, "fps": [30, 1] },
        "tracks": [{ "id": 1, "name": "Picture" }],
        "clips": [
            {"id": 2, "track": 1, "start": 0, "duration": 600000,
             "source": {"kind": "shape"},
             "video": video,
             "shape": {"kind": "rectangle", "width": 100, "height": 50}}
        ],
        "next_id": 3
    })
}

#[test]
fn the_current_version_is_17() {
    assert_eq!(RC_FORMAT_VERSION, 17);
}

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=16u32).chain([GRADING_BRANCH_VERSION]) {
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
fn an_uncurved_16_file_writes_what_it_did() {
    let video = json!({"wheels": {"lift": {"x": 0.25}}, "color": {"exposure": 0.5}});
    let sixteen = Handle::from_value(&file(16, video.clone())).to_json();
    let seventeen = Handle::from_value(&file(17, video)).to_json();
    assert_eq!(sixteen, seventeen);
    assert!(!seventeen.contains("\"curves\""), "{seventeen}");
}

#[test]
fn an_identity_channel_in_a_file_is_not_written_back() {
    let opened = Handle::from_value(&file(
        17,
        json!({"curves": {"master": [[0, 0], [0.5, 0.5], [1, 1]],
                          "red": [[0, 0], [0.5, 0.7], [1, 1]]}}),
    ));
    assert_eq!(
        at(&opened.value(), "/clips/0/video/curves"),
        &json!({"red": [[0.0, 0.0], [0.5, 0.7], [1.0, 1.0]]})
    );
    let all_identity =
        Handle::from_value(&file(17, json!({"curves": {"green": [[0, 0], [1, 1]]}})));
    assert!(!all_identity.to_json().contains("\"curves\""));
}

#[test]
fn a_curved_file_round_trips_byte_for_byte() {
    let curves = json!({
        "master": [[0.0, 0.05], [0.25, 0.2], [0.75, 0.85], [1.0, 0.95]],
        "blue": [[0.0, 0.1], [1.0, 1.0]]
    });
    let opened = Handle::from_value(&file(17, json!({"curves": curves})));
    assert_eq!(at(&opened.value(), "/clips/0/video/curves"), &curves);
    let once = opened.to_json();
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
    assert_eq!(Handle::from_json(&twice).to_json(), once);
}
