//! Black-box tests for format version 21, the qualifier's cleanup blur (spec
//! §11 GR-35): `video.qualifier.blur`, driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 21; every earlier version (1 to 20),
//! and a file numbered 1015 (GR-9's branch number, read as 15), opens
//! stamped current; every number past the current one, 1014 included, and
//! 1016 are refused as newer; a file with no blur at 20 writes the same text
//! as the same file at 21; and a file with a blurred qualifier ROUND TRIPS
//! byte for byte, `blur` after `invert`.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A shape and an adjustment clip with `qualifier` (none for `Value::Null`),
/// in a file of `version`.
fn file(version: u32, qualifier: Value) -> Value {
    let mut video = json!({"color": {"saturation": -1.0}});
    if !qualifier.is_null() {
        video["qualifier"] = qualifier;
    }
    json!({
        "version": version,
        "canvas": { "width": 640, "height": 360, "fps": [30, 1] },
        "tracks": [{ "id": 1, "name": "Picture" }, { "id": 2, "name": "Adjustment" }],
        "clips": [
            {"id": 10, "track": 1, "start": 0, "duration": 600000,
             "source": {"kind": "shape"}, "video": {},
             "shape": {"kind": "rectangle", "width": 100, "height": 50}},
            {"id": 11, "track": 2, "start": 0, "duration": 600000,
             "source": {"kind": "adjustment"}, "video": video}
        ],
        "next_id": 20
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 21,
    "version 21 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=20u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_with_no_blur_at_20_writes_what_it_did() {
    let hue = json!({"hue": {"center": 120.0, "width": 40.0, "softness": 20.0}, "invert": true});
    for qualifier in [Value::Null, hue] {
        let twenty = Handle::from_value(&file(20, qualifier.clone())).to_json();
        let twenty_one = Handle::from_value(&file(21, qualifier)).to_json();
        assert_eq!(twenty, twenty_one);
        assert!(!twenty_one.contains("\"blur\""), "{twenty_one}");
    }
}

#[test]
fn a_blurred_qualifier_round_trips_byte_for_byte() {
    for qualifier in [
        json!({"hue": {"center": 120.0, "width": 40.0, "softness": 20.0}, "blur": 0.25}),
        json!({"luma": {"low": 0.2, "high": 0.8, "softness": 0.1}, "invert": true, "blur": 1.0}),
        json!({"blur": 0.05}),
    ] {
        let opened = Handle::from_value(&file(21, qualifier.clone()));
        assert_eq!(at(&opened.value(), "/clips/1/video/qualifier"), &qualifier);
        let once = opened.to_json();
        let twice = Handle::from_json(&once).to_json();
        assert_eq!(twice, once);
        assert_eq!(Handle::from_json(&twice).to_json(), once);
        if qualifier.get("invert").is_some() {
            let invert = once.find("\"invert\"").expect("invert");
            let blur = once.find("\"blur\"").expect("blur");
            assert!(invert < blur, "{once}");
        }
    }
}
