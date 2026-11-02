//! Black-box tests for format version 41, a picture's cutout (spec §11
//! CO-100): `video.cutout.subject` may be `foreground`, an image clip's only,
//! driven through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 41; every earlier version (1
//! to 40), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 40 without `foreground` writes
//! the same text as the same file at 41; and an image clip's `{subject:
//! "foreground"}` ROUND TRIPS byte for byte, in its place (`subject` first in
//! the cutout).

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A file of `version` with media clip 3 and image clip 4, which carries
/// `video`.
fn file(version: u32, video: Value) -> Value {
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [{"id": 1, "path": "/fixtures/camera.mov", "kind": "video",
                   "duration": 6000000, "width": 1920, "height": 1080,
                   "fps": [30, 1], "has_video": true, "has_audio": true},
                  {"id": 5, "path": "/fixtures/photo.png", "kind": "image",
                   "width": 640, "height": 480}],
        "tracks": [{ "id": 2, "name": "Track 1" }, { "id": 6, "name": "Track 2" }],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 600000,
             "source": {"kind": "media", "media": 1, "in": 0},
             "video": {"cutout": {"edge": 0.5}}},
            {"id": 4, "track": 6, "start": 0, "duration": 600000,
             "source": {"kind": "image", "media": 5},
             "video": video}
        ],
        "next_id": 7
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 41,
    "version 41 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=40u32).chain([GRADING_BRANCH_VERSION]) {
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
    for version in [RC_FORMAT_VERSION + 1, 1014, 1016] {
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
fn a_file_at_40_without_foreground_writes_what_it_did() {
    let video = json!({"scale": 0.5, "cutout": {"background": "keep"}});
    let forty = Handle::from_value(&file(40, video.clone())).to_json();
    let forty_one = Handle::from_value(&file(41, video)).to_json();
    assert_eq!(forty, forty_one);
    assert!(!forty_one.contains("\"foreground\""), "{forty_one}");
}

#[test]
fn a_foreground_subject_round_trips_byte_for_byte_in_its_place() {
    let opened = Handle::from_value(&file(
        41,
        json!({"cutout": {"subject": "foreground", "feather": 0.25}}),
    ));
    let value = opened.value();
    assert_eq!(
        at(&value, "/clips/1/video/cutout"),
        &json!({"subject": "foreground", "quality": "standard", "background": "remove",
                "edge": 0.0, "feather": 0.25})
    );
    assert_eq!(
        at(&value, "/clips/0/video/cutout/subject"),
        &json!("person"),
        "the media clip's subject is the default"
    );
    let once = opened.to_json();
    // The subject's place, read off the written text: the image clip's
    // cutout's first field, before `quality`.
    let clips = once.find("\"clips\"").expect("the clips");
    let image = once[clips..]
        .find("\"kind\": \"image\"")
        .expect("the image clip")
        + clips;
    let cutout = once[image..].find("\"cutout\"").expect("its cutout") + image;
    let subject = once[cutout..]
        .find("\"subject\": \"foreground\"")
        .expect("the subject")
        + cutout;
    let quality = once[cutout..].find("\"quality\"").expect("quality") + cutout;
    assert!(subject < quality, "{once}");
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
}
