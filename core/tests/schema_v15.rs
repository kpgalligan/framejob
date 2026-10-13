//! Black-box tests for format version 15, grading (spec §11 GR-2..GR-9) —
//! tone's nine `video.color` keys (GR-2), adjustment clips (GR-6), looks
//! (GR-7) and `.cube` LUTs (GR-8) — driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! Pinned here: every earlier version (1 to 14) opens stamped current; a
//! file numbered 1015, the grading branch's builds' number, opens as 15 with
//! its grades intact, its written text byte for byte the same file's at 15
//! (GR-9); every number past the current one (16), 1014 included, and every
//! number past 1015 are refused as newer; the
//! KEY ORDER read off the written text (tone after `hue`, only the keys that
//! are not 0); and the ROUND TRIP, byte for byte, of a neutral file and a
//! toned one.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

const SEC: i64 = 600_000;

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

/// Every grade at once, in a file of `version`: media 1 a video and media 2
/// a `lut`; clip 10 toned with a built-in look; clip 11 an adjustment clip on
/// a track of its own; clip 12 with the LUT as its look.
fn graded(version: u32) -> Value {
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [
            {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
             "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true,
             "has_audio": false},
            {"id": 2, "path": "/l/a.cube", "kind": "lut"}
        ],
        "tracks": [{"id": 4, "name": "Track 1"}, {"id": 5, "name": "Track 2"}],
        "clips": [
            {"id": 10, "track": 4, "start": 0, "duration": 6 * SEC, "speed": 1.0,
             "source": {"kind": "media", "media": 1, "in": 0},
             "enabled": {"video": true, "audio": false},
             "video": {"color": {"exposure": 0.5, "temperature": -0.25, "shadows": 0.3,
                                 "fade": 0.2},
                       "look": {"kind": "warm", "amount": 0.6}}},
            {"id": 11, "track": 5, "start": 0, "duration": 6 * SEC, "speed": 1.0,
             "source": {"kind": "adjustment"},
             "video": {"color": {"vibrance": 0.4}}},
            {"id": 12, "track": 4, "start": 6 * SEC, "duration": 2 * SEC, "speed": 1.0,
             "source": {"kind": "media", "media": 1, "in": 0},
             "enabled": {"video": true, "audio": false},
             "video": {"look": {"kind": "lut", "media": 2}}}
        ],
        "next_id": 20
    })
}

#[test]
fn every_earlier_version_opens_stamped_current() {
    for version in 1..=14u32 {
        let opened = Handle::from_value(&json!({ "version": version }));
        assert_eq!(
            opened.value()["version"],
            json!(RC_FORMAT_VERSION),
            "version {version}"
        );
    }
    let opened = Handle::from_value(&file(14));
    assert_eq!(at(&opened.value(), "/version"), &json!(RC_FORMAT_VERSION));
    assert_eq!(
        color_keys(&opened.to_json()),
        ["brightness", "contrast", "saturation", "hue"]
    );
}

#[test]
fn a_1015_file_opens_as_15_with_its_grades_intact() {
    let branch = Handle::from_value(&graded(GRADING_BRANCH_VERSION));
    let value = branch.value();
    assert_eq!(at(&value, "/version"), &json!(RC_FORMAT_VERSION));
    assert_eq!(at(&value, "/media/1/kind"), &json!("lut"));
    assert_eq!(at(&value, "/clips/0/video/color/exposure"), &json!(0.5));
    assert_eq!(
        at(&value, "/clips/0/video/look"),
        &json!({"kind": "warm", "amount": 0.6})
    );
    assert_eq!(
        at(&value, "/clips/1/source"),
        &json!({"kind": "adjustment"})
    );
    assert_eq!(
        at(&value, "/clips/2/video/look"),
        &json!({"kind": "lut", "media": 2, "amount": 1.0})
    );
    // 15 is the fixture's own number here (GR-9's target), not the current
    // version read back: the same file at 15 writes the same bytes.
    let fifteen = Handle::from_value(&graded(15)).to_json();
    assert_eq!(branch.to_json(), fifteen);
}

#[test]
fn past_current_to_1014_and_past_1015_are_newer() {
    for version in [RC_FORMAT_VERSION + 1, 500, 1014, 1016] {
        let message = Handle::try_from_value(&json!({ "version": version })).expect_err("newer");
        assert_eq!(
            message,
            format!(
                "project format version {version} is newer than this build understands \
                 (version {RC_FORMAT_VERSION}); update Frame Job to open it"
            )
        );
        assert!(!message.contains("grading build"), "{message}");
    }
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
    // A neutral current file writes exactly what the same 14 file writes.
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
