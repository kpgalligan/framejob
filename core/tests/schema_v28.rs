//! Black-box tests for format version 28, a linked pair (spec §11 AU-90):
//! `clips[].linked`, driven through the C FFI exactly as `ReelCore.swift`
//! drives it.
//!
//! Pinned here: the current version is at least 28; every earlier version
//! (1 to 27) opens stamped current; a file at 27 writes the same text as
//! the same file at 28, with no `linked` key; a link ROUND TRIPS byte for
//! byte, in its place after `label`; and a one-sided link — to a clip that
//! does not name it back, to an absent clip, to itself, or across
//! containers — is refused on open, in the core's sentence.

mod common;

use framejob_core::format::RC_FORMAT_VERSION;
use serde_json::{json, Value};

use common::{at, Handle};

/// A two-clip file of `version`; `links` sets each clip's `linked`.
fn file(version: u32, links: [Option<u32>; 2]) -> Value {
    let mut clips = vec![
        json!({"id": 3, "track": 2, "start": 0, "duration": 600000,
               "source": {"kind": "media", "media": 1, "in": 0},
               "enabled": {"video": true, "audio": false}, "label": "blue"}),
        json!({"id": 4, "track": 5, "start": 0, "duration": 600000,
               "source": {"kind": "media", "media": 1, "in": 0},
               "enabled": {"video": false, "audio": true}}),
    ];
    for (clip, link) in clips.iter_mut().zip(links) {
        if let Some(id) = link {
            clip["linked"] = json!(id);
        }
    }
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [{"id": 1, "path": "/fixtures/clip.mov", "kind": "video",
                   "duration": 6000000, "width": 1920, "height": 1080, "fps": [30, 1],
                   "has_video": true, "has_audio": true}],
        "tracks": [{"id": 5, "name": "Track 1"}, {"id": 2, "name": "Track 2"}],
        "clips": clips,
        "next_id": 6
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 28,
    "version 28 is at most the current version"
);

#[test]
fn every_earlier_version_opens_stamped_current() {
    for version in 1..=27u32 {
        let opened = Handle::from_value(&json!({ "version": version }));
        assert_eq!(
            opened.value()["version"],
            json!(RC_FORMAT_VERSION),
            "version {version}"
        );
    }
}

#[test]
fn a_file_at_27_writes_what_it_did() {
    let twenty_seven = Handle::from_value(&file(27, [None, None])).to_json();
    let twenty_eight = Handle::from_value(&file(28, [None, None])).to_json();
    assert_eq!(twenty_seven, twenty_eight);
    assert!(!twenty_eight.contains("\"linked\""), "{twenty_eight}");
}

#[test]
fn a_link_round_trips_byte_for_byte_after_label() {
    let opened = Handle::from_value(&file(28, [Some(4), Some(3)]));
    assert_eq!(at(&opened.value(), "/clips/0/linked"), &json!(4));
    assert_eq!(at(&opened.value(), "/clips/1/linked"), &json!(3));
    let once = opened.to_json();
    // The key's place, read off the written text: after `label`.
    let label = once.find("\"label\"").expect("the label key");
    let linked = once.find("\"linked\"").expect("the linked key");
    assert!(label < linked, "{once}");
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
}

#[test]
fn a_one_sided_link_is_refused_on_open() {
    let cases = [
        (
            [Some(4), None],
            "clip 3 is linked to clip 4, which is not linked back",
        ),
        (
            [Some(9), None],
            "clip 3 is linked to clip 9, which is not linked back",
        ),
        (
            [Some(3), None],
            "clip 3 is linked to clip 3, which is not linked back",
        ),
        (
            [Some(4), Some(4)],
            "clip 3 is linked to clip 4, which is not linked back",
        ),
    ];
    for (links, sentence) in cases {
        let message = Handle::try_from_value(&file(28, links)).expect_err("one-sided");
        assert_eq!(message, sentence);
    }
}

#[test]
fn a_link_across_containers_is_refused_on_open() {
    // Clip 4 moved into a nest: its link to clip 3 on the timeline cannot be
    // mutual inside one container.
    let mut value = file(28, [Some(4), Some(3)]);
    let mut inner = value["clips"][1].take();
    inner["track"] = json!(8);
    value["clips"] = json!([value["clips"][0].clone()]);
    value["nests"] = json!([{"id": 7, "name": "Nest 1",
                             "tracks": [{"id": 8, "name": "Inner"}],
                             "clips": [inner]}]);
    value["next_id"] = json!(9);
    let message = Handle::try_from_value(&value).expect_err("across containers");
    assert_eq!(
        message,
        "clip 3 is linked to clip 4, which is not linked back"
    );
}
