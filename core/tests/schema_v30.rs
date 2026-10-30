//! Black-box tests for format version 30, the clip limiter (spec §11 AU-21):
//! `audio.limiter`, driven through the C FFI exactly as `ReelCore.swift`
//! drives it.
//!
//! Pinned here: the current version is at least 30; every earlier version (1
//! to 29), and a file numbered 1015 (GR-9's branch number, read as 15),
//! opens stamped current; every number past the current one, 1014 included,
//! and 1016 are refused as newer; a file at 29 with no limiter writes the
//! same text as the same file at 30; `audio.limiter` ROUND TRIPS byte for
//! byte, in its place after `noise_reduction`; `{limiter: {}}` stores the
//! defaults; each bound and an unknown inner key is refused by name; and
//! `limiter: null` clears it.

mod common;

use framejob_core::format::{GRADING_BRANCH_VERSION, RC_FORMAT_VERSION};
use serde_json::{json, Value};

use common::{at, Handle};

/// A one-clip file of `version` whose clip 3 carries `audio`.
fn file(version: u32, audio: Value) -> Value {
    json!({
        "version": version,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [{"id": 1, "path": "/fixtures/voice.m4a", "kind": "audio",
                   "duration": 6000000, "has_video": false, "has_audio": true}],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 600000,
             "source": {"kind": "media", "media": 1, "in": 0},
             "audio": audio}
        ],
        "next_id": 4
    })
}

const _: () = assert!(
    RC_FORMAT_VERSION >= 30,
    "version 30 is at most the current version"
);

#[test]
fn every_earlier_version_and_1015_open_stamped_current() {
    for version in (1..=29u32).chain([GRADING_BRANCH_VERSION]) {
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
fn a_file_at_29_with_no_limiter_writes_what_it_did() {
    let audio = json!({"volume": 2.0, "noise_reduction": 0.5});
    let twenty_nine = Handle::from_value(&file(29, audio.clone())).to_json();
    let thirty = Handle::from_value(&file(30, audio)).to_json();
    assert_eq!(twenty_nine, thirty);
    assert!(!thirty.contains("\"limiter\""), "{thirty}");
}

#[test]
fn a_limiter_round_trips_byte_for_byte() {
    let limiter = json!({"ceiling_db": -3.5, "release": 120_000});
    let opened = Handle::from_value(&file(
        30,
        json!({"noise_reduction": 0.25, "limiter": limiter.clone()}),
    ));
    assert_eq!(at(&opened.value(), "/clips/0/audio/limiter"), &limiter);
    let once = opened.to_json();
    // The key's place, read off the written text: after `noise_reduction`,
    // the field it follows, with its own two keys in order.
    let noise = once.find("\"noise_reduction\"").expect("noise_reduction");
    let key = once.find("\"limiter\"").expect("the limiter key");
    assert!(noise < key, "{once}");
    let ceiling = once.find("\"ceiling_db\"").expect("ceiling_db");
    let release = once[key..].find("\"release\"").expect("release") + key;
    assert!(key < ceiling && ceiling < release, "{once}");
    let twice = Handle::from_json(&once).to_json();
    assert_eq!(twice, once);
    assert_eq!(Handle::from_json(&twice).to_json(), once);
}

#[test]
fn an_empty_limiter_stores_the_defaults_and_null_clears_it() {
    let base = Handle::from_value(&file(30, json!({})));
    let limited = base.apply(&json!({
        "op": "set_audio", "clips": [3], "patch": { "limiter": {} }
    }));
    assert_eq!(
        at(&limited.value(), "/clips/0/audio/limiter"),
        &json!({"ceiling_db": -1.0, "release": 60_000})
    );
    let cleared = limited.apply(&json!({
        "op": "set_audio", "clips": [3], "patch": { "limiter": null }
    }));
    let text = cleared.to_json();
    assert!(!text.contains("\"limiter\""), "{text}");
    assert_eq!(text, base.to_json());
}

#[test]
fn each_bound_and_an_unknown_inner_key_is_refused_by_name() {
    let project = Handle::from_value(&file(30, json!({})));
    let cases: [(Value, &str); 5] = [
        (
            json!({ "limiter": { "ceiling_db": -24.5 } }),
            "audio.limiter.ceiling_db must be between -24 and 0, not -24.5",
        ),
        (
            json!({ "limiter": { "ceiling_db": 0.5 } }),
            "audio.limiter.ceiling_db must be between -24 and 0, not 0.5",
        ),
        (
            json!({ "limiter": { "release": 599 } }),
            "audio.limiter.release must be between 600 and 600000 ticks, not 599",
        ),
        (
            json!({ "limiter": { "release": 600_001 } }),
            "audio.limiter.release must be between 600 and 600000 ticks, not 600001",
        ),
        (
            json!({ "limiter": { "ceiling": -2.0 } }),
            "unknown key \"limiter.ceiling\" in an audio patch",
        ),
    ];
    for (patch, expected) in cases {
        let msg = project.errors(&json!({ "op": "set_audio", "clips": [3], "patch": patch }));
        assert_eq!(msg, expected);
    }
    // Each end of each range is inside it.
    for limiter in [
        json!({ "ceiling_db": -24.0, "release": 600 }),
        json!({ "ceiling_db": 0.0, "release": 600_000 }),
    ] {
        let set = project.apply(&json!({
            "op": "set_audio", "clips": [3], "patch": { "limiter": limiter.clone() }
        }));
        assert_eq!(at(&set.value(), "/clips/0/audio/limiter"), &limiter);
    }
}
