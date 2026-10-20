//! Black-box tests for format version 22, a PQ file's HDR10 peak (spec §11
//! HD-12): the optional `media.color.pq` key, driven through the C FFI
//! exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 22; every earlier version (1
//! to 21), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file with no `pq` at 21 writes the same
//! text as the same file at 22; `pq` is written after `detected`, its keys in
//! the order `file`, `from`, `peak`, each only when set, and an empty reading
//! as `{}`; and a file with a peak ROUND TRIPS byte for byte.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// One video media with `color` (none for `Value::Null`), a LUT media, and a
/// clip of the video, in a file of `version`.
fn file(version: u32, color: Value) -> Value {
    let mut video = json!({"id": 1, "path": "/fixtures/pq.mov", "kind": "video",
        "duration": 600000, "width": 1024, "height": 128, "fps": [30, 1],
        "has_video": true});
    if !color.is_null() {
        video["color"] = color;
    }
    json!({
        "version": version,
        "canvas": { "width": 1024, "height": 128, "fps": [30, 1] },
        "media": [video,
                  {"id": 2, "path": "/fixtures/look.cube", "kind": "lut"}],
        "tracks": [{ "id": 3, "name": "Track 1" }],
        "clips": [
            {"id": 4, "track": 3, "start": 0, "duration": 600000,
             "source": {"kind": "media", "media": 1, "in": 0}}
        ],
        "next_id": 5
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 22,
    "version 22 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=21u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_with_no_pq_at_21_writes_what_it_did() {
    for color in [Value::Null, json!({"log": "slog3", "gamut": "s_gamut3"})] {
        let twenty_one = Handle::from_value(&file(21, color.clone())).to_json();
        let twenty_two = Handle::from_value(&file(22, color)).to_json();
        assert_eq!(twenty_one, twenty_two);
        assert!(!twenty_two.contains("\"pq\""), "{twenty_two}");
    }
}

#[test]
fn pq_is_written_after_detected_file_from_peak_each_only_when_set() {
    let full = json!({"pq": {"peak": 1000, "from": "max_cll", "file": 4000},
                      "detected": true, "gamut": "bt2020", "log": "apple_log"});
    let text = Handle::from_value(&file(22, full)).to_json();
    let order: Vec<usize> = ["\"detected\"", "\"pq\"", "\"file\"", "\"from\"", "\"peak\""]
        .iter()
        .map(|key| text.find(key).unwrap_or_else(|| panic!("{key} in {text}")))
        .collect();
    assert!(order.windows(2).all(|pair| pair[0] < pair[1]), "{text}");

    let empty = Handle::from_value(&file(22, json!({"pq": {}})));
    assert_eq!(at(&empty.value(), "/media/0/color"), &json!({"pq": {}}));
    let written = empty.to_json();
    for absent in [
        "\"file\"",
        "\"from\"",
        "\"peak\"",
        "\"log\"",
        "\"detected\"",
    ] {
        assert!(!written.contains(absent), "{absent} in {written}");
    }
}

#[test]
fn a_file_with_a_peak_round_trips_byte_for_byte() {
    for color in [
        json!({"pq": {}}),
        json!({"pq": {"file": 4000, "from": "max_cll"}}),
        json!({"pq": {"file": 2000, "from": "mastering_display", "peak": 600}}),
        json!({"pq": {"peak": 10000}}),
        json!({"lut": 2, "pq": {"file": 1000, "from": "max_cll"}}),
    ] {
        let opened = Handle::from_value(&file(22, color.clone()));
        assert_eq!(at(&opened.value(), "/media/0/color"), &color);
        let once = opened.to_json();
        let twice = Handle::from_json(&once).to_json();
        assert_eq!(twice, once);
        assert_eq!(Handle::from_json(&twice).to_json(), once);
    }
}
