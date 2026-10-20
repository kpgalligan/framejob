//! Black-box tests for format version 23, the project's dynamic range (spec
//! §11 HD-2, HD-13): the optional `canvas.output` key, driven through the C
//! FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the current version is at least 23; every earlier version (1
//! to 22), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; an SDR file at 22 writes the same text as
//! the same file at 23, with no `output`; `output` is written last in
//! `canvas` and only when `hlg`; and an HLG file ROUND TRIPS byte for byte.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A one-clip file of `version` whose canvas carries `output` (none for
/// `Value::Null`).
fn file(version: u32, output: Value) -> Value {
    let mut canvas = json!({"width": 1920, "height": 1080, "fps": [30, 1],
                            "background": [0.0, 0.0, 0.0, 1.0]});
    if !output.is_null() {
        canvas["output"] = output;
    }
    json!({
        "version": version,
        "canvas": canvas,
        "media": [{"id": 1, "path": "/fixtures/clip.mov", "kind": "video",
                   "duration": 600000, "width": 1920, "height": 1080, "fps": [30, 1],
                   "has_video": true}],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 600000,
             "source": {"kind": "media", "media": 1, "in": 0}}
        ],
        "next_id": 4
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 23,
    "version 23 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=22u32).chain([GRADING_BRANCH_VERSION]) {
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
fn an_sdr_file_at_22_writes_what_it_did() {
    for output in [Value::Null, json!("sdr")] {
        let twenty_two = Handle::from_value(&file(22, output.clone())).to_json();
        let twenty_three = Handle::from_value(&file(23, output)).to_json();
        assert_eq!(twenty_two, twenty_three);
        assert!(!twenty_three.contains("\"output\""), "{twenty_three}");
    }
}

#[test]
fn output_is_written_last_in_the_canvas_and_only_when_hlg() {
    let opened = Handle::from_value(&file(23, json!("hlg")));
    assert_eq!(at(&opened.value(), "/canvas/output"), &json!("hlg"));
    let text = opened.to_json();
    let canvas = &text[text.find("\"canvas\"").expect("a canvas")..];
    let canvas = &canvas[..canvas.find('}').expect("the canvas closes")];
    let order: Vec<usize> = ["\"width\"", "\"timecode_frames\"", "\"output\""]
        .iter()
        .map(|key| {
            canvas
                .find(key)
                .unwrap_or_else(|| panic!("{key} in {canvas}"))
        })
        .collect();
    assert!(order.windows(2).all(|pair| pair[0] < pair[1]), "{canvas}");
    assert!(
        canvas.trim_end().ends_with("\"output\": \"hlg\""),
        "{canvas}"
    );
    let sdr = Handle::from_value(&file(23, json!("sdr"))).to_json();
    assert!(!sdr.contains("\"output\""), "{sdr}");
}

#[test]
fn an_hlg_file_round_trips_byte_for_byte() {
    let opened = Handle::from_value(&file(23, json!("hlg")));
    let once = opened.to_json();
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
    assert_eq!(Handle::from_json(&twice).to_json(), once);
}
