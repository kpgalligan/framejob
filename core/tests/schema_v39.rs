//! Black-box tests for format version 39, the cutout (spec §11 CO-20,
//! CO-23): `video.cutout`, driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 39; every earlier version (1
//! to 38), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 38 without the key writes the
//! same text as the same file at 39; the key ROUND TRIPS byte for byte, in
//! its place (after `cursor`), each field in its own order; and `{}` reads
//! as the five defaults.

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
    RC_FORMAT_VERSION >= 39,
    "version 39 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=38u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_at_38_without_the_key_writes_what_it_did() {
    let video = json!({"scale": 0.5, "cursor": {"scale": 2.0}});
    let thirty_eight = Handle::from_value(&file(38, video.clone())).to_json();
    let thirty_nine = Handle::from_value(&file(39, video)).to_json();
    assert_eq!(thirty_eight, thirty_nine);
    assert!(!thirty_nine.contains("\"cutout\""), "{thirty_nine}");
}

#[test]
fn the_key_round_trips_byte_for_byte_after_cursor() {
    let cutout = json!({"subject": "person", "quality": "best", "background": "keep",
                        "edge": -0.25, "feather": 0.5});
    let opened = Handle::from_value(&file(
        39,
        json!({"cursor": {"scale": 2.0}, "cutout": cutout.clone()}),
    ));
    let value = opened.value();
    assert_eq!(at(&value, "/clips/0/video/cutout"), &cutout);
    let once = opened.to_json();
    // The key's place, read off the written text: after `cursor`'s last
    // field, and the fields in declaration order.
    let mut last = once.find("\"click_size\"").expect("cursor's last field");
    for key in [
        "\"cutout\"",
        "\"subject\"",
        "\"quality\"",
        "\"background\"",
        "\"edge\"",
        "\"feather\"",
    ] {
        let place = once[last..].find(key).expect(key) + last;
        assert!(place > last, "{key}: {once}");
        last = place;
    }
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
    assert_eq!(Handle::from_json(&twice).to_json(), once);
}

#[test]
fn an_empty_object_reads_as_the_defaults() {
    let opened = Handle::from_value(&file(39, json!({"cutout": {}})));
    assert_eq!(
        at(&opened.value(), "/clips/0/video/cutout"),
        &json!({"subject": "person", "quality": "standard", "background": "remove",
                "edge": 0.0, "feather": 0.0})
    );
}
