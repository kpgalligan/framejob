//! Black-box tests for the `audio_bits` export override — spec §7.8 and
//! §11 AU-29 (road map "audio" AP2 part 2), driven through
//! `rc_export_presets` and `rc_export_settings` exactly as the export
//! sheet and the agent's `export` tool drive them.
//!
//! What the file is built to catch:
//!
//! 1. **The rows.** `audio_wav` and `audio_aiff` list `audio_bits`
//!    `[16, 24]`, written out whole; no other row lists it.
//! 2. **The depth.** Absent and null are 16 on those two rows; 16 and 24
//!    come back as asked.
//! 3. **The refusals.** A value that is not 16 or 24 is refused naming the
//!    key and the value, on any row; a depth on a row without one is
//!    refused naming the row and the key; no other row's settings carry
//!    the key.
//! 4. **The ceiling alone** (AU-27): `peak_dbtp` without a target resolves
//!    on these rows with the depth beside it.

mod common;

use serde_json::{json, Value};

use common::{assert_contains, expect_string, parse_json, text, Handle};
use framejob_core::ffi_query::rc_export_presets;

/// One second in ticks (spec §5.1).
const SECOND: i64 = 600_000;

/// The two rows the override applies to.
const LPCM_ROWS: [&str; 2] = ["audio_wav", "audio_aiff"];

/// A 1600 × 900, 30 fps project with one ten-second clip.
fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 1,
        "canvas": {
            "width": 1600, "height": 900, "fps": [30, 1],
            "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true
        },
        "media": [{
            "id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 60 * SECOND,
            "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{"id": 2, "name": "Track 1"}],
        "clips": [{
            "id": 3, "track": 2, "start": 0, "duration": 10 * SECOND,
            "source": {"kind": "media", "media": 1, "in": 0}
        }],
        "next_id": 4
    }))
}

/// The menu, exactly as `rc_export_presets` hands it to the picker.
fn preset_rows() -> Vec<Value> {
    let text = expect_string(unsafe { rc_export_presets() }, "rc_export_presets");
    match parse_json(&text, "rc_export_presets") {
        Value::Array(rows) => rows,
        other => panic!("rc_export_presets is not an array: {other}"),
    }
}

fn settings(handle: &Handle, preset: &str, overrides: Option<&Value>) -> Value {
    match handle.export_settings(preset, overrides) {
        Ok(value) => value,
        Err(msg) => panic!("{preset} was expected to resolve, but: {msg}"),
    }
}

fn refusal(handle: &Handle, preset: &str, overrides: &Value) -> String {
    match handle.export_settings(preset, Some(overrides)) {
        Ok(value) => panic!("{preset} with {overrides} was expected to be refused: {value}"),
        Err(msg) => msg,
    }
}

#[test]
fn the_two_lpcm_rows_are_written_out_whole() {
    let rows = preset_rows();
    for (id, name, container) in [
        ("audio_wav", "Audio only (WAV)", "wav"),
        ("audio_aiff", "Audio only (AIFF)", "aiff"),
    ] {
        let row = rows
            .iter()
            .find(|row| text(row, "/id") == id)
            .unwrap_or_else(|| panic!("the menu has no {id} row"));
        assert_eq!(
            *row,
            json!({
                "id": id,
                "name": name,
                "container": container,
                "codec": "lpcm",
                "video": false,
                "size": null,
                "fps": null,
                "avf_preset": "AVAssetExportPresetAppleM4A",
                "audio_bits": [16, 24]
            })
        );
    }
}

#[test]
fn no_other_row_lists_a_bit_depth() {
    let rows = preset_rows();
    let listing: Vec<&str> = rows
        .iter()
        .filter(|row| row.get("audio_bits").is_some())
        .map(|row| text(row, "/id"))
        .collect();
    assert_eq!(listing, LPCM_ROWS.to_vec());
}

#[test]
fn absent_and_null_are_16_and_each_depth_comes_back_as_asked() {
    let handle = project();
    for preset in LPCM_ROWS {
        let plain = settings(&handle, preset, None);
        assert_eq!(plain["audio_bits"], json!(16), "{preset}");
        let null = settings(&handle, preset, Some(&json!({"audio_bits": null})));
        assert_eq!(null, plain, "{preset}: null is not absent");
        for bits in [16, 24] {
            let out = settings(&handle, preset, Some(&json!({"audio_bits": bits})));
            assert_eq!(out["audio_bits"], json!(bits), "{preset} {bits}");
        }
    }
}

#[test]
fn a_value_that_is_not_16_or_24_is_refused_naming_the_key_and_the_value() {
    let handle = project();
    // On a row that takes a depth and on one that does not: the value is
    // read first, so a 20 is named whatever the row.
    for preset in ["audio_wav", "audio_aiff", "h264"] {
        for value in [
            json!(20),
            json!(32),
            json!(8),
            json!(0),
            json!(-16),
            json!(24.5),
            json!("24"),
            json!(true),
            json!([24]),
        ] {
            let msg = refusal(&handle, preset, &json!({"audio_bits": value}));
            assert_eq!(
                msg,
                format!("export audio_bits must be 16 or 24, not {value}"),
                "{preset} {value}"
            );
        }
    }
}

#[test]
fn a_depth_on_a_row_without_one_is_refused_naming_the_row() {
    let handle = project();
    for row in preset_rows() {
        let preset = text(&row, "/id");
        if LPCM_ROWS.contains(&preset) {
            continue;
        }
        for bits in [16, 24] {
            let msg = refusal(&handle, preset, &json!({"audio_bits": bits}));
            assert_eq!(
                msg,
                format!(
                    "{preset} has no bit depth; audio_bits applies to audio_wav and audio_aiff"
                )
            );
            assert_contains(&msg, "audio_bits");
        }
        // And unasked, its settings never carry the key.
        assert!(
            settings(&handle, preset, None).get("audio_bits").is_none(),
            "{preset}'s settings carry a depth"
        );
    }
}

#[test]
fn a_ceiling_alone_resolves_beside_the_depth() {
    let handle = project();
    for preset in LPCM_ROWS {
        let out = settings(
            &handle,
            preset,
            Some(&json!({"peak_dbtp": -3.0, "audio_bits": 24})),
        );
        assert_eq!(out["peak_dbtp"], json!(-3.0), "{preset}");
        assert_eq!(out["audio_bits"], json!(24), "{preset}");
        assert!(out.get("loudness_lufs").is_none(), "{preset}: {out}");
    }
}
