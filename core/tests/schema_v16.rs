//! Black-box tests for format version 16, the wheels (spec §11 GR-11): the
//! optional `video.wheels` key, driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! Pinned here: version 16 is at most the current version; every earlier
//! version (1 to 15), and a file numbered 1015 (GR-9's branch number, read
//! as 15), opens stamped current; every number past the current one, 1014
//! included, and 1016 are refused as newer; an unwheeled file at 15 writes
//! the same text as the same file at 16; and a wheeled file ROUND TRIPS byte
//! for byte.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
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

const _: () = assert!(
    RC_FORMAT_VERSION >= 16,
    "version 16 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=15u32).chain([GRADING_BRANCH_VERSION]) {
        let opened = Handle::from_value(&json!({ "version": version }));
        assert_eq!(
            opened.value()["version"],
            json!(RC_FORMAT_VERSION),
            "version {version}"
        );
    }
    let wheeled = Handle::from_value(&file(
        GRADING_BRANCH_VERSION,
        json!({"wheels": {"lift": {"x": 0.25}}}),
    ));
    assert_eq!(
        at(&wheeled.value(), "/clips/0/video/wheels"),
        &json!({"lift": {"x": 0.25}})
    );
}

#[test]
fn past_current_to_1014_and_1016_are_newer() {
    for version in [
        RC_FORMAT_VERSION + 1,
        RC_FORMAT_VERSION + 2,
        500,
        1014,
        1016,
    ] {
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
fn an_unwheeled_15_file_writes_what_it_did() {
    let video = json!({"color": {"brightness": 0.1, "contrast": 0, "saturation": 0, "hue": 0,
                                 "exposure": 0.5}});
    let fifteen = Handle::from_value(&file(15, video.clone())).to_json();
    let sixteen = Handle::from_value(&file(16, video)).to_json();
    assert_eq!(fifteen, sixteen);
    assert!(!sixteen.contains("\"wheels\""), "{sixteen}");
}

#[test]
fn a_wheeled_file_round_trips_byte_for_byte() {
    // A rim point, an ulp past 1 (x² + y²), as an action's clamp writes it.
    let rim = std::f64::consts::FRAC_1_SQRT_2;
    let wheels = json!({
        "lift": {"x": rim, "y": rim, "master": -0.1},
        "gamma": {"master": 0.25},
        "gain": {"y": -0.5}
    });
    let opened = Handle::from_value(&file(16, json!({"wheels": wheels})));
    assert_eq!(at(&opened.value(), "/clips/0/video/wheels"), &wheels);
    let once = opened.to_json();
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
    assert_eq!(Handle::from_json(&twice).to_json(), once);
}
