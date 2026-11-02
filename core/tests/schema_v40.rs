//! Black-box tests for format version 40, Behind Subject (spec §11 CO-52):
//! `video.behind_subject`, driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 40; every earlier version (1
//! to 39), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 39 without the key writes the
//! same text as the same file at 40, and a `false` is not written; and the
//! key ROUND TRIPS byte for byte, in its place (after `cutout`).

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A one-clip file of `version` whose clip 3 carries `video`.
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
    RC_FORMAT_VERSION >= 40,
    "version 40 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=39u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_at_39_without_the_key_writes_what_it_did() {
    let video = json!({"scale": 0.5, "cutout": {"background": "keep"}});
    let thirty_nine = Handle::from_value(&file(39, video.clone())).to_json();
    let forty = Handle::from_value(&file(40, video)).to_json();
    assert_eq!(thirty_nine, forty);
    assert!(!forty.contains("\"behind_subject\""), "{forty}");
}

#[test]
fn a_false_flag_is_not_written() {
    let opened = Handle::from_value(&file(40, json!({"behind_subject": false})));
    assert!(!opened.to_json().contains("\"behind_subject\""));
    assert_eq!(
        at(&opened.value(), "/clips/0/video/scale"),
        &json!(1.0),
        "the rest of the group is read"
    );
}

#[test]
fn the_key_round_trips_byte_for_byte_after_cutout() {
    let opened = Handle::from_value(&file(
        40,
        json!({"cutout": {"background": "keep"}, "behind_subject": true}),
    ));
    let value = opened.value();
    assert_eq!(at(&value, "/clips/0/video/behind_subject"), &json!(true));
    let once = opened.to_json();
    // The key's place, read off the written text: after `cutout`'s last
    // field.
    let cutout = once.find("\"cutout\"").expect("the cutout");
    let feather = once[cutout..]
        .find("\"feather\"")
        .expect("cutout's last field")
        + cutout;
    let flag = once.find("\"behind_subject\"").expect("the flag");
    assert!(flag > feather, "{once}");
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
}
