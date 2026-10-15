//! Black-box tests for format version 20, the hue curves (spec §11 GR-32):
//! `video.curves.hue_hue` and `.hue_sat`, driven through the C FFI exactly
//! as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is 20; every earlier version (1 to 19),
//! and a file numbered 1015 (GR-9's branch number, read as 15), opens
//! stamped current; every number past the current one, 1014 included, and
//! 1016 are refused as newer; a file with no hue curve at 19 writes the
//! same text as the same file at 20; a clip's curves are written in model
//! order (master, red, green, blue, hue_hue, hue_sat), a hue identity not
//! at all; and a file with hue curves ROUND TRIPS byte for byte.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// One video media and a clip of it with `curves` (none for
/// `Value::Null`), in a file of `version`.
fn file(version: u32, curves: Value) -> Value {
    let mut video = json!({});
    if !curves.is_null() {
        video["curves"] = curves;
    }
    json!({
        "version": version,
        "canvas": { "width": 1024, "height": 128, "fps": [30, 1] },
        "media": [{"id": 1, "path": "/fixtures/hue.mov", "kind": "video",
                   "duration": 600000, "width": 1024, "height": 128, "fps": [30, 1],
                   "has_video": true}],
        "tracks": [{ "id": 3, "name": "Track 1" }],
        "clips": [
            {"id": 4, "track": 3, "start": 0, "duration": 600000,
             "source": {"kind": "media", "media": 1, "in": 0}, "video": video}
        ],
        "next_id": 5
    })
}

#[test]
fn the_current_version_is_20() {
    assert_eq!(RC_FORMAT_VERSION, 20);
}

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=19u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_with_no_hue_curve_at_19_writes_what_it_did() {
    let red = json!({"red": [[0.0, 0.0], [0.5, 0.7], [1.0, 1.0]]});
    for curves in [Value::Null, red] {
        let nineteen = Handle::from_value(&file(19, curves.clone())).to_json();
        let twenty = Handle::from_value(&file(20, curves)).to_json();
        assert_eq!(nineteen, twenty);
        assert!(!twenty.contains("\"hue_"), "{twenty}");
    }
}

#[test]
fn curves_are_written_in_model_order_and_a_hue_identity_not_at_all() {
    let curves = json!({
        "hue_sat": [[0.0, 1.0], [120.0, 0.0], [240.0, 1.0]],
        "hue_hue": [[0.0, 0.0], [60.0, 20.0]],
        "master": [[0.0, 0.1], [1.0, 1.0]]
    });
    let text = Handle::from_value(&file(20, curves)).to_json();
    let master = text.find("\"master\"").expect("master");
    let hue = text.find("\"hue_hue\"").expect("hue_hue");
    let sat = text.find("\"hue_sat\"").expect("hue_sat");
    assert!(master < hue && hue < sat, "{text}");

    // Identities read from a file are dropped on write: any x's, every value
    // the neutral.
    let neutral = json!({
        "hue_hue": [[10.0, 0.0], [200.0, 0.0], [300.0, 0.0]],
        "hue_sat": [[0.0, 1.0], [180.0, 1.0]]
    });
    let written = Handle::from_value(&file(20, neutral)).to_json();
    assert!(!written.contains("\"curves\""), "{written}");
}

#[test]
fn a_file_with_hue_curves_round_trips_byte_for_byte() {
    for curves in [
        json!({"hue_hue": [[0.0, -40.0], [180.0, 40.0], [359.5, 0.0]]}),
        json!({"hue_sat": [[30.0, 0.0], [90.0, 2.0]]}),
        json!({"blue": [[0.0, 0.2], [1.0, 1.0]], "hue_hue": [[0.0, 180.0], [10.0, -180.0]],
               "hue_sat": [[0.0, 0.5], [180.0, 1.5]]}),
    ] {
        let opened = Handle::from_value(&file(20, curves.clone()));
        assert_eq!(at(&opened.value(), "/clips/0/video/curves"), &curves);
        let once = opened.to_json();
        let twice = Handle::from_json(&once).to_json();
        assert_eq!(twice, once);
        assert_eq!(Handle::from_json(&twice).to_json(), once);
    }
}
