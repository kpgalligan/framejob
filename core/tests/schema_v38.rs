//! Black-box tests for format version 38, the cursor (spec §11 CU-30, CU-35,
//! CU-39): `media.cursor` and `video.cursor`, driven through the C FFI
//! exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 38; every earlier version (1
//! to 37), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 37 without the keys writes the
//! same text as the same file at 38; both keys ROUND TRIP byte for byte, in
//! their places (after `speech`; after `look`), each field in its own order;
//! and `{}` reads as the cursor props' defaults.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A one-clip file of `version` whose media 1 carries `cursor` (when not
/// null) and whose clip 3 carries `video`.
fn file(version: u32, cursor: Value, video: Value) -> Value {
    let mut media = json!({"id": 1, "path": "/fixtures/screen.mov", "kind": "video",
                           "duration": 6000000, "width": 1920, "height": 1080,
                           "fps": [30, 1], "has_video": true, "has_audio": true,
                           "speech": [[0, 600000]]});
    if !cursor.is_null() {
        media["cursor"] = cursor;
    }
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [media],
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
    RC_FORMAT_VERSION >= 38,
    "version 38 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=37u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_at_37_without_the_keys_writes_what_it_did() {
    let video = json!({"scale": 0.5, "look": {"kind": "warm", "amount": 0.5}});
    let thirty_seven = Handle::from_value(&file(37, Value::Null, video.clone())).to_json();
    let thirty_eight = Handle::from_value(&file(38, Value::Null, video)).to_json();
    assert_eq!(thirty_seven, thirty_eight);
    assert!(!thirty_eight.contains("\"cursor\""), "{thirty_eight}");
}

#[test]
fn both_keys_round_trip_byte_for_byte_in_their_places() {
    let media_cursor = json!({"path": "/fixtures/screen.fjcursor", "bookmark": "Qk0=",
                              "in_picture": false});
    let props = json!({"show": false, "scale": 2.5, "style": "arrow", "smoothing": 0.5,
                       "hide_idle": 3.0, "clicks": "ripple", "click_color": "red",
                       "click_size": 1.5});
    let opened = Handle::from_value(&file(
        38,
        media_cursor.clone(),
        json!({"look": {"kind": "warm", "amount": 0.5}, "cursor": props.clone()}),
    ));
    let value = opened.value();
    assert_eq!(at(&value, "/media/0/cursor"), &media_cursor);
    assert_eq!(at(&value, "/clips/0/video/cursor"), &props);
    let once = opened.to_json();
    // The keys' places, read off the written text: the media's cursor after
    // `speech`, the clip's after `look`, and the fields in declaration order.
    let mut last = once.find("\"speech\"").expect("speech");
    for key in ["\"cursor\"", "\"path\"", "\"bookmark\"", "\"in_picture\""] {
        let place = once[last..].find(key).expect(key) + last;
        assert!(place > last, "{key}: {once}");
        last = place;
    }
    let mut last = once.find("\"look\"").expect("look");
    for key in [
        "\"cursor\"",
        "\"show\"",
        "\"scale\"",
        "\"style\"",
        "\"smoothing\"",
        "\"hide_idle\"",
        "\"clicks\"",
        "\"click_color\"",
        "\"click_size\"",
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
    let opened = Handle::from_value(&file(
        38,
        json!({"path": "/fixtures/screen.fjcursor", "in_picture": true}),
        json!({"cursor": {}}),
    ));
    let value = opened.value();
    assert_eq!(
        at(&value, "/clips/0/video/cursor"),
        &json!({"show": true, "scale": 1.0, "style": "recorded", "smoothing": 0.0,
                "hide_idle": null, "clicks": "none", "click_color": "#ffffffcc",
                "click_size": 1.0})
    );
    assert_eq!(
        at(&value, "/media/0/cursor"),
        &json!({"path": "/fixtures/screen.fjcursor", "in_picture": true})
    );
}
