//! Black-box tests for format version 18, the qualifier (spec §11 GR-13):
//! the optional `video.qualifier` key, driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! Pinned here: version 18 is at most the current version; every earlier version (1 to 17),
//! and a file numbered 1015 (GR-9's branch number, read as 15), opens
//! stamped current; every number past the current one, 1014 included, and
//! 1016 are refused as newer; an unqualified file at 17 writes the same
//! text as the same file at 18; a neutral qualifier in a file reads as none
//! and is not written back; and a qualified file ROUND TRIPS byte for byte.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// One adjustment clip, in a file of `version`, with `video` as given.
fn file(version: u32, video: Value) -> Value {
    json!({
        "version": version,
        "canvas": { "width": 640, "height": 360, "fps": [30, 1] },
        "tracks": [{ "id": 1, "name": "Adjustment" }],
        "clips": [
            {"id": 2, "track": 1, "start": 0, "duration": 600000,
             "source": {"kind": "adjustment"},
             "video": video}
        ],
        "next_id": 3
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 18,
    "version 18 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=17u32).chain([GRADING_BRANCH_VERSION]) {
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
fn an_unqualified_17_file_writes_what_it_did() {
    let video = json!({"curves": {"red": [[0, 0], [0.5, 0.7], [1, 1]]},
                       "color": {"exposure": 0.5}});
    let seventeen = Handle::from_value(&file(17, video.clone())).to_json();
    let eighteen = Handle::from_value(&file(18, video)).to_json();
    assert_eq!(seventeen, eighteen);
    assert!(!eighteen.contains("\"qualifier\""), "{eighteen}");
}

#[test]
fn a_neutral_qualifier_in_a_file_is_not_written_back() {
    for neutral in [json!({}), json!({"invert": false}), json!({"hue": null})] {
        let opened = Handle::from_value(&file(18, json!({"qualifier": neutral})));
        assert!(!opened.to_json().contains("\"qualifier\""), "{neutral}");
    }
}

#[test]
fn a_qualified_file_round_trips_byte_for_byte() {
    let qualifier = json!({
        "hue": {"center": 25.0, "width": 30.0, "softness": 15.0},
        "saturation": {"low": 0.15, "high": 1.0, "softness": 0.05},
        "luma": {"low": 0.0, "high": 0.8, "softness": 0.1},
        "invert": true
    });
    let opened = Handle::from_value(&file(18, json!({"qualifier": qualifier})));
    assert_eq!(at(&opened.value(), "/clips/0/video/qualifier"), &qualifier);
    let once = opened.to_json();
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
    assert_eq!(Handle::from_json(&twice).to_json(), once);
}
