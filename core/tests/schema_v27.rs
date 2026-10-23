//! Black-box tests for format version 27, a clip's rate as an action target
//! (spec §11 SR-10): `actions[].end.speed`, driven through the C FFI exactly
//! as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 27; every earlier version (1
//! to 26), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 26 with an action writes the same
//! text as the same file at 27; and an end's `speed` ROUND TRIPS byte for
//! byte, in its place among the end's keys.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A one-clip file of `version` whose action 4 ends at `end`.
fn file(version: u32, end: Value) -> Value {
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [{"id": 1, "path": "/fixtures/clip.mov", "kind": "video",
                   "duration": 6000000, "width": 1920, "height": 1080, "fps": [30, 1],
                   "has_video": true}],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 600000,
             "source": {"kind": "media", "media": 1, "in": 0},
             "actions": [{"id": 4, "start": 0, "duration": 300000, "curve": "ease_in",
                          "end": end}]}
        ],
        "next_id": 5
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 27,
    "version 27 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=26u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_at_26_with_an_action_writes_what_it_did() {
    let end = json!({"video": {"opacity": 0.5}});
    let twenty_six = Handle::from_value(&file(26, end.clone())).to_json();
    let twenty_seven = Handle::from_value(&file(27, end.clone())).to_json();
    assert_eq!(twenty_six, twenty_seven);
    let opened = Handle::from_json(&twenty_seven);
    assert_eq!(at(&opened.value(), "/clips/0/actions/0/end"), &end);
}

#[test]
fn an_end_s_speed_round_trips_byte_for_byte() {
    let end = json!({"video": {"opacity": 0.5}, "speed": 2.5});
    let opened = Handle::from_value(&file(27, end.clone()));
    assert_eq!(at(&opened.value(), "/clips/0/actions/0/end"), &end);
    let once = opened.to_json();
    // The key's place, read off the written text: after the group it
    // followed, as the file had it (the clip's own `speed` comes earlier).
    let video = once.find("\"opacity\"").expect("the opacity key");
    let speed = once.rfind("\"speed\"").expect("the end's speed key");
    assert!(video < speed, "{once}");
    let value = once[speed..].trim_start_matches("\"speed\"").trim_start();
    assert!(
        value.starts_with(": 2.5") || value.starts_with(":2.5"),
        "{once}"
    );
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
    assert_eq!(Handle::from_json(&twice).to_json(), once);
}
