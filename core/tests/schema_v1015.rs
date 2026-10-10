//! Black-box tests for format version 1015, the grading branch's own number
//! (spec §11 GR-9) — tone's nine `video.color` keys (GR-2) — driven through
//! the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: every main version (1 to `BRANCH_BASE_VERSION`) opens
//! stamped 1015; the gap between is refused in its own sentence and a later
//! number as newer; the KEY ORDER read off the written text (tone after
//! `hue`, only the keys that are not 0); and the ROUND TRIP, byte for byte,
//! of a neutral file and a toned one.

mod common;

use reelcut_core::format::{BRANCH_BASE_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{assert_contains, at, Handle};

/// One shape clip with its colour's four keys away from 0, in a file of
/// `version`.
fn file(version: u32) -> Value {
    json!({
        "version": version,
        "canvas": { "width": 640, "height": 360, "fps": [30, 1] },
        "tracks": [{ "id": 1, "name": "Picture" }],
        "clips": [
            {"id": 2, "track": 1, "start": 0, "duration": 600000,
             "source": {"kind": "shape"},
             "video": {"color": {"brightness": 0.1, "contrast": -0.2, "saturation": 0.3,
                                 "hue": 40}},
             "shape": {"kind": "rectangle", "width": 100, "height": 50}}
        ],
        "next_id": 3
    })
}

/// The written text's `color` object keys, read off the pretty-printed TEXT
/// (a parsed `Value` would not say where a key sits).
fn color_keys(written: &str) -> Vec<String> {
    let mut keys = Vec::new();
    let mut indent = None;
    for line in written.lines() {
        let trimmed = line.trim_start();
        let depth = line.len() - trimmed.len();
        match indent {
            None if trimmed.starts_with("\"color\": {") => indent = Some(depth),
            Some(open) if depth <= open => break,
            Some(open) if depth == open + 2 => {
                if let Some(rest) = trimmed.strip_prefix('"') {
                    keys.push(rest.split('"').next().unwrap_or_default().to_string());
                }
            }
            _ => {}
        }
    }
    keys
}

#[test]
fn the_branch_numbers_are_what_gr_9_says() {
    assert_eq!(RC_FORMAT_VERSION, 1015);
    assert_eq!(BRANCH_BASE_VERSION, 14);
}

#[test]
fn every_main_version_opens_stamped_1015() {
    for version in 1..=BRANCH_BASE_VERSION {
        let opened = Handle::from_value(&json!({ "version": version }));
        assert_eq!(
            opened.value()["version"],
            json!(RC_FORMAT_VERSION),
            "version {version}"
        );
    }
    let opened = Handle::from_value(&file(14));
    assert_eq!(at(&opened.value(), "/version"), &json!(1015));
    assert_eq!(
        color_keys(&opened.to_json()),
        ["brightness", "contrast", "saturation", "hue"]
    );
}

#[test]
fn the_gap_is_refused_in_its_own_sentence_and_a_later_number_as_newer() {
    for version in [15, 16, 500, 1014] {
        let message = Handle::try_from_value(&json!({ "version": version })).expect_err("the gap");
        assert_eq!(
            message,
            format!(
                "project format version {version} is not one this grading build reads \
                 (it reads 1 to 14 and 1015); open it in the Reelcut that made it"
            )
        );
    }
    let message = Handle::try_from_value(&json!({ "version": 1016 })).expect_err("newer");
    assert_contains(
        &message,
        "project format version 1016 is newer than this build understands (version 1015)",
    );
}

#[test]
fn tone_keys_follow_hue_in_order_and_only_when_set() {
    let toned = Handle::from_value(&file(14)).apply(&json!({
        "op": "set_video", "clips": [2],
        "patch": {"color": {"fade": 0.5, "tint": -0.25, "exposure": 2, "vibrance": 1}}
    }));
    assert_eq!(
        color_keys(&toned.to_json()),
        [
            "brightness",
            "contrast",
            "saturation",
            "hue",
            "exposure",
            "tint",
            "vibrance",
            "fade"
        ]
    );
    let every = Handle::from_value(&file(14)).apply(&json!({
        "op": "set_video", "clips": [2],
        "patch": {"color": {"exposure": 1, "temperature": 1, "tint": 1, "highlights": 1,
                            "shadows": 1, "whites": 1, "blacks": 1, "vibrance": 1,
                            "fade": 1}}
    }));
    assert_eq!(
        color_keys(&every.to_json()),
        [
            "brightness",
            "contrast",
            "saturation",
            "hue",
            "exposure",
            "temperature",
            "tint",
            "highlights",
            "shadows",
            "whites",
            "blacks",
            "vibrance",
            "fade"
        ]
    );
}

#[test]
fn a_neutral_file_and_a_toned_one_round_trip_byte_for_byte() {
    let neutral = Handle::from_value(&file(RC_FORMAT_VERSION));
    let once = neutral.to_json();
    assert_eq!(Handle::from_json(&once).to_json(), once);
    // A neutral 1015 file writes exactly what the same 14 file writes, but
    // for the version.
    let main = Handle::from_value(&file(14)).to_json();
    assert_eq!(main, once);

    let toned = neutral.apply(&json!({
        "op": "set_video", "clips": [2],
        "patch": {"color": {"shadows": -0.75, "blacks": 0.5}}
    }));
    let once = toned.to_json();
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
    assert_eq!(Handle::from_json(&twice).to_json(), once);
}
