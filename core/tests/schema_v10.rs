//! Black-box tests for what format version 10 added — the `graphic` source
//! kind and the clip's `graphic` key (road map 10, G2a) — driven through
//! the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the SHAPE (every older file opens with `graphic` null,
//! stamped version 10, and a version-9 page keeps every text key it had),
//! the ROUND TRIP (road map 10 §5g's clip, byte for byte, twice), the KEY
//! ORDER read off the written text (`graphic` after `shape` and before
//! `actions`; `props` in the file's own order), and what `validate` says
//! about a graphic clip in a file. What the ops do is `graphic.rs`'s.

mod common;

use serde_json::{json, Value};

use common::{at, text, Handle};

/// Ticks per second (spec §5.1), written out rather than imported.
const SEC: i64 = 600_000;

/// Road map 10 §5g's clip 40, as the writer writes it.
const FIXTURE: &str = include_str!("fixtures/graphic_v10.json");

/// `schema_v9.rs`'s page: one text clip whose group carries the three
/// version-9 keys, written as a file of `version`.
fn page(version: u32) -> Value {
    json!({
        "version": version,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 6 * SEC,
            "source": { "kind": "text" }, "video": {},
            "text": {
                "content": "so here's the thing", "size": 96.0, "case": "upper",
                "words": [
                    {"start": 0, "end": 108000}, {"start": 120000, "end": 276000},
                    {"start": 288000, "end": 348000}, {"start": 360000, "end": 618000}
                ],
                "word_style": { "mode": "build" }
            }
        }],
        "next_id": 12
    })
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
fn every_older_version_reads_with_graphic_null() {
    for version in [9, 8, 7, 6, 5, 4, 3, 2, 1] {
        let project = Handle::from_value(&page(version)).value();
        assert_eq!(at(&project, "/version"), &json!(10), "version {version}");
        assert_eq!(
            at(&project, "/clips/0/graphic"),
            &Value::Null,
            "version {version}"
        );
    }
}

#[test]
fn a_version_9_page_keeps_every_text_key() {
    let before = page(9);
    let project = Handle::from_value(&before).value();
    assert_eq!(at(&project, "/version"), &json!(10));
    assert_eq!(at(&project, "/clips/0/graphic"), &Value::Null);
    assert_eq!(
        text(&project, "/clips/0/text/content"),
        "so here's the thing"
    );
    assert_eq!(text(&project, "/clips/0/text/case"), "upper");
    assert_eq!(
        at(&project, "/clips/0/text/words"),
        at(&before, "/clips/0/text/words")
    );
    assert_eq!(text(&project, "/clips/0/text/word_style/mode"), "build");
}

// ---- the round trip ------------------------------------------------------

#[test]
fn the_fixture_round_trips_byte_for_byte_twice() {
    let first = Handle::from_json(FIXTURE).to_json();
    assert_eq!(first, FIXTURE, "the first write changed the bytes");
    let second = Handle::from_json(&first).to_json();
    assert_eq!(second, FIXTURE, "the second write changed the bytes");
}

#[test]
fn the_fixture_is_road_map_10s_clip() {
    let project = Handle::from_json(FIXTURE).value();
    assert_eq!(at(&project, "/version"), &json!(10));
    assert_eq!(at(&project, "/clips/0/source"), &json!({"kind": "graphic"}));
    assert_eq!(
        at(&project, "/clips/0/graphic"),
        &json!({"name": "lower-third", "width": 1920, "height": 1080, "in": 0,
                "length": null, "props": {"title": "Kevin", "accent": "#2d7ff9"}})
    );
    assert_eq!(at(&project, "/clips/0/audio"), &Value::Null);
}

#[test]
fn graphic_follows_shape_and_precedes_actions() {
    let written = Handle::from_json(FIXTURE).to_json();
    // The clip's keys sit one level inside the `clips` array, at indent 6.
    let clip_keys: Vec<&str> = written
        .lines()
        .skip_while(|line| !line.trim_start().starts_with("\"clips\": ["))
        .take_while(|line| !line.trim_start().starts_with("\"markers\""))
        .filter(|line| line.len() - line.trim_start().len() == 6)
        .filter_map(|line| line.trim_start().strip_prefix('"'))
        .map(|rest| rest.split('"').next().unwrap_or_default())
        .collect();
    let shape = clip_keys.iter().position(|k| *k == "shape").expect("shape");
    assert_eq!(
        &clip_keys[shape..shape + 3],
        ["shape", "graphic", "actions"],
        "the clip's keys, in written order: {clip_keys:?}"
    );
    assert_eq!(
        written_keys(&written, "\"graphic\": {"),
        ["name", "width", "height", "in", "length", "props"]
    );
}

#[test]
fn props_come_back_in_the_files_order() {
    let written = Handle::from_json(FIXTURE).to_json();
    assert_eq!(written_keys(&written, "\"props\": {"), ["title", "accent"]);
    let swapped = FIXTURE.replacen(
        "\"title\": \"Kevin\",\n          \"accent\": \"#2d7ff9\"",
        "\"accent\": \"#2d7ff9\",\n          \"title\": \"Kevin\"",
        1,
    );
    assert_ne!(
        swapped, FIXTURE,
        "the fixture's props were not where expected"
    );
    let written = Handle::from_json(&swapped).to_json();
    assert_eq!(written_keys(&written, "\"props\": {"), ["accent", "title"]);
    assert_eq!(written, swapped);
}

// ---- validate ------------------------------------------------------------

#[test]
fn a_file_with_a_bad_module_name_is_refused_and_an_absent_description_is_not() {
    let mut bad: Value = serde_json::from_str(FIXTURE).expect("the fixture");
    bad["clips"][0]["graphic"]["name"] = json!("Lower Third");
    let Err(message) = Handle::try_from_value(&bad) else {
        panic!("a bad module name was read");
    };
    assert!(
        message.contains(
            "clip 40 has graphic name \"Lower Third\", which is not a module name (lowercase \
             letters, digits and -, starting with a letter or a digit, at most 63 characters)"
        ),
        "{message}"
    );
    let mut absent: Value = serde_json::from_str(FIXTURE).expect("the fixture");
    absent["clips"][0]
        .as_object_mut()
        .expect("a clip")
        .remove("graphic");
    let project = Handle::from_value(&absent).value();
    assert_eq!(at(&project, "/clips/0/graphic"), &Value::Null);
}
