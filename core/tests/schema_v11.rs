//! Black-box tests for what format version 11 added — the media key
//! `original`, the WebM or Matroska file a playable copy was made from
//! (spec §11 #228-O) — driven through the C FFI exactly as `ReelCore.swift`
//! drives it.
//!
//! Pinned here: the SHAPE (every older file opens with `original` null,
//! stamped the current version, and a version-10 media keeps every key it
//! had), the KEY ORDER read off the written text (`original` closes the
//! media object; its own keys are `path`, `bookmark`), and the ROUND TRIP
//! (an inline version-11 file, byte for byte, twice). What the ops do with
//! the key is `media_original.rs`'s.

mod common;

use framejob_core::format::RC_FORMAT_VERSION;
use serde_json::{json, Value};

use common::{at, Handle};

/// One media, every version-10 key filled and nothing at its default, in a
/// file of `version`.
fn file(version: u32) -> Value {
    json!({
        "version": version,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/Users/x/talk.mov", "bookmark": "Ym9va21hcmsA",
            "kind": "video", "duration": 6_000_000, "width": 1280, "height": 720,
            "fps": [25, 1], "has_video": true, "has_audio": true, "has_alpha": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "next_id": 3
    })
}

/// A version-11 file with an original, as the writer writes it: hand-checked
/// against spec §5.2's media element, `original` last with `path` before
/// `bookmark`.
const V11: &str = r#"{
  "version": 11,
  "canvas": {
    "width": 1920,
    "height": 1080,
    "fps": [
      30,
      1
    ],
    "background": [
      0.0,
      0.0,
      0.0,
      1.0
    ],
    "fit_new_clips": true,
    "timecode_frames": true
  },
  "media": [
    {
      "id": 1,
      "path": "/Users/x/Library/Application Support/Frame Job/Rewrapped/talk-0123456789abcdef.mov",
      "bookmark": "Y29weQ==",
      "kind": "video",
      "duration": 6000000,
      "width": 1280,
      "height": 720,
      "fps": [
        30,
        1
      ],
      "has_video": true,
      "has_audio": true,
      "has_alpha": false,
      "original": {
        "path": "/Users/x/Movies/talk.webm",
        "bookmark": "b3JpZ2luYWw="
      }
    }
  ],
  "tracks": [
    {
      "id": 2,
      "name": "Track 1",
      "hidden": false,
      "muted": false,
      "locked": false,
      "solo": false
    }
  ],
  "clips": [],
  "markers": [],
  "next_id": 3,
  "nests": []
}"#;

/// `fixture` as the writer writes it today: its `"version": 11,` line
/// stamped with the current version, once, and nothing else changed.
fn current(fixture: &str) -> String {
    assert!(
        fixture.contains("\"version\": 11,"),
        "the fixture's version line was not where expected"
    );
    fixture.replacen(
        "\"version\": 11,",
        &format!("\"version\": {RC_FORMAT_VERSION},"),
        1,
    )
}

/// The keys of the first object opened by `opener`, in the order the
/// writer put them, read off the pretty-printed TEXT by indentation.
fn written_keys(written: &str, opener: &str) -> Vec<String> {
    let lines: Vec<&str> = written.lines().collect();
    let open = lines
        .iter()
        .position(|line| line.trim_start().starts_with(opener))
        .unwrap_or_else(|| panic!("no {opener} in:\n{written}"));
    let indent = lines[open].len() - lines[open].trim_start().len();
    let mut keys = Vec::new();
    for line in &lines[open + 1..] {
        let here = line.len() - line.trim_start().len();
        if here == indent {
            break;
        }
        if here == indent + 2 {
            if let Some(rest) = line.trim_start().strip_prefix('"') {
                keys.push(rest.split('"').next().unwrap_or_default().to_string());
            }
        }
    }
    keys
}

// ---- reading older files -------------------------------------------------

#[test]
fn every_older_version_reads_with_original_null() {
    for version in [10, 9, 8, 7, 6, 5, 4, 3, 2, 1] {
        let project = Handle::from_value(&file(version)).value();
        assert_eq!(
            at(&project, "/version"),
            &json!(RC_FORMAT_VERSION),
            "version {version}"
        );
        assert_eq!(
            at(&project, "/media/0/original"),
            &Value::Null,
            "version {version}"
        );
    }
}

#[test]
fn a_version_10_media_keeps_all_ten_of_its_keys() {
    let before = file(10);
    let project = Handle::from_value(&before).value();
    let had = at(&before, "/media/0").as_object().expect("a media");
    let has = at(&project, "/media/0").as_object().expect("a media");
    for (key, value) in had {
        assert_eq!(has.get(key), Some(value), "media key {key}");
    }
    assert_eq!(had.len(), 11, "the fixture's id and its ten keys");
    assert_eq!(has.len(), 12, "the same keys and `original`");
}

// ---- the key order -------------------------------------------------------

#[test]
fn original_closes_the_media_object_with_path_before_bookmark() {
    let written = Handle::from_json(V11).to_json();
    // The media's keys sit one level inside the `media` array, at indent 6.
    let element: Vec<String> = written
        .lines()
        .skip_while(|line| !line.trim_start().starts_with("\"media\": ["))
        .take_while(|line| !line.trim_start().starts_with("\"tracks\""))
        .filter(|line| line.len() - line.trim_start().len() == 6)
        .filter_map(|line| line.trim_start().strip_prefix('"'))
        .map(|rest| rest.split('"').next().unwrap_or_default().to_string())
        .collect();
    assert_eq!(
        element,
        [
            "id",
            "path",
            "bookmark",
            "kind",
            "duration",
            "width",
            "height",
            "fps",
            "has_video",
            "has_audio",
            "has_alpha",
            "original"
        ],
        "the media's keys, in written order"
    );
    assert_eq!(
        written_keys(&written, "\"original\": {"),
        ["path", "bookmark"]
    );
}

#[test]
fn a_media_with_no_original_writes_it_as_null() {
    let written = Handle::from_value(&file(10)).to_json();
    assert!(
        written.contains("      \"has_alpha\": true,\n      \"original\": null\n    }"),
        "{written}"
    );
}

// ---- the round trip ------------------------------------------------------

#[test]
fn a_version_11_file_round_trips_byte_for_byte_twice() {
    let expected = current(V11);
    let first = Handle::from_json(V11).to_json();
    assert_eq!(first, expected, "the first write changed the bytes");
    let second = Handle::from_json(&first).to_json();
    assert_eq!(second, expected, "the second write changed the bytes");
}

#[test]
fn an_original_without_a_bookmark_reads_with_bookmark_null() {
    let mut given = file(11);
    given["media"][0]["original"] = json!({"path": "/Users/x/Movies/talk.webm"});
    let project = Handle::from_value(&given).value();
    assert_eq!(
        at(&project, "/media/0/original"),
        &json!({"path": "/Users/x/Movies/talk.webm", "bookmark": null})
    );
}
