//! Black-box tests for what format version 14 added — the track key
//! `matte` (spec §11 MT-1) — driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! Pinned here: older files (13 and 12) open stamped the current version
//! with every track ordinary and NO `matte` key written; the KEY ORDER read
//! off the written text (`matte` after `solo`, and only on a matte track);
//! and the ROUND TRIP (a version-14 file with a matte track, byte for byte,
//! twice). What a matte does to a frame is `matte.rs`'s.

mod common;

use reelcut_core::format::RC_FORMAT_VERSION;
use serde_json::{json, Value};

use common::{at, Handle};

/// Two tracks, every pre-14 key at a non-default where it can be, in a
/// file of `version`.
fn file(version: u32) -> Value {
    json!({
        "version": version,
        "canvas": { "width": 640, "height": 360, "fps": [30, 1] },
        "tracks": [
            { "id": 1, "name": "Picture", "hidden": true, "muted": true,
              "locked": true, "solo": true },
            { "id": 2, "name": "Window" }
        ],
        "next_id": 3
    })
}

/// The written text's track objects, as the key lists the writer put in
/// them, read off the pretty-printed TEXT by indentation (a parsed `Value`
/// would not say where `matte` sits).
fn track_keys(written: &str) -> Vec<Vec<String>> {
    let mut tracks = Vec::new();
    let mut inside = false;
    let mut current: Vec<String> = Vec::new();
    for line in written.lines() {
        let indent = line.len() - line.trim_start().len();
        let trimmed = line.trim_start();
        if indent == 2 && trimmed.starts_with("\"tracks\": [") {
            inside = true;
            continue;
        }
        if !inside {
            continue;
        }
        if indent == 2 {
            break;
        }
        if indent == 4 && trimmed.starts_with('}') {
            tracks.push(std::mem::take(&mut current));
        } else if indent == 6 {
            if let Some(rest) = trimmed.strip_prefix('"') {
                current.push(rest.split('"').next().unwrap_or_default().to_string());
            }
        }
    }
    tracks
}

#[test]
fn older_files_open_stamped_current_with_every_track_ordinary() {
    for version in [13, 12] {
        let opened = Handle::from_value(&file(version));
        let value = opened.value();
        assert_eq!(
            at(&value, "/version"),
            &json!(RC_FORMAT_VERSION),
            "version {version}"
        );
        let written = opened.to_json();
        assert!(
            !written.contains("\"matte\""),
            "version {version}:\n{written}"
        );
        let ordinary = ["id", "name", "hidden", "muted", "locked", "solo"];
        assert_eq!(
            track_keys(&written),
            [ordinary, ordinary],
            "version {version}"
        );
        // Each pre-14 value survives.
        assert_eq!(at(&value, "/tracks/0/solo"), &json!(true));
        assert_eq!(at(&value, "/tracks/0/locked"), &json!(true));
    }
}

#[test]
fn matte_is_written_after_solo_and_only_on_a_matte_track() {
    let opened = Handle::from_value(&file(13));
    let matted = opened.apply(&json!({"op": "set_track", "track": 2, "matte": "luma_inverted"}));
    let written = matted.to_json();
    let ordinary = ["id", "name", "hidden", "muted", "locked", "solo"];
    let matte = ["id", "name", "hidden", "muted", "locked", "solo", "matte"];
    assert_eq!(track_keys(&written), [ordinary.to_vec(), matte.to_vec()]);
    assert_eq!(
        at(&matted.value(), "/tracks/1/matte"),
        &json!("luma_inverted")
    );

    // Switched off, the key is gone again.
    let off = matted.apply(&json!({"op": "set_track", "track": 2, "matte": "none"}));
    assert!(!off.to_json().contains("\"matte\""));
    assert_eq!(off.to_json(), opened.to_json());
}

#[test]
fn a_matte_track_round_trips_byte_for_byte_twice() {
    for mode in ["alpha", "alpha_inverted", "luma", "luma_inverted"] {
        let matted = Handle::from_value(&file(13))
            .apply(&json!({"op": "set_track", "track": 2, "matte": mode}));
        let once = matted.to_json();
        let twice = Handle::from_json(&once).to_json();
        assert_eq!(twice, once, "{mode}");
        assert_eq!(Handle::from_json(&twice).to_json(), once, "{mode}");
    }
}

#[test]
fn a_file_naming_an_unknown_matte_is_refused_naming_the_five() {
    let mut project = file(RC_FORMAT_VERSION);
    project["tracks"][1]["matte"] = json!("chroma");
    let message = Handle::try_from_value(&project).expect_err("an unknown matte");
    for name in [
        "`chroma`",
        "`none`",
        "`alpha`",
        "`alpha_inverted`",
        "`luma`",
        "`luma_inverted`",
    ] {
        assert!(message.contains(name), "{name} missing from: {message}");
    }
}
