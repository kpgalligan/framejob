//! Black-box tests for the `av1` export row — spec §7.8 and §11 CX-12
//! (codec-export C1), driven through `rc_export_presets` and
//! `rc_export_settings` exactly as the export sheet and the agent's
//! `export` tool drive them.
//!
//! The row is AV1 in MP4: SVT-AV1 encodes the picture (`writer`
//! `svt_av1`) and AVFoundation writes the MP4 and its AAC, so in the core
//! the row is an AVFoundation row with two keys no other row has — the
//! route and the encoder's speed.
//!
//! What the file is built to catch:
//!
//! 1. **The row, whole.** The preset row and its resolved settings are
//!    written out by hand, so a key gained, lost or changed fails by name.
//! 2. **The speed.** Absent is `balanced`; each of the three words comes
//!    back as asked; null is absent.
//! 3. **The refusals.** A word that is not a speed is refused naming the
//!    key and the value on any row; a speed on a row without one is
//!    refused naming the row and the key; `h264`'s settings are unchanged.
//! 4. **HDR** (spec §11 CX-14). The row is one of HD-5's HDR rows: `"hdr"`
//!    on the row, and in an HLG project its settings carry `color` `hlg` by
//!    default and `pq` or `sdr` as asked, written out whole.

mod common;

use serde_json::{json, Value};

use common::{assert_contains, expect_string, parse_json, text, Handle};
use framejob_core::ffi_query::rc_export_presets;

/// One second in ticks (spec §5.1).
const SECOND: i64 = 600_000;

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
fn the_row_is_written_out_whole() {
    let row = preset_rows()
        .into_iter()
        .find(|row| text(row, "/id") == "av1")
        .expect("the menu has no av1 row");
    assert_eq!(
        row,
        json!({
            "id": "av1",
            "name": "AV1 (MP4)",
            "container": "mp4",
            "codec": "av1",
            "video": true,
            "size": null,
            "fps": null,
            "avf_preset": "AVAssetExportPresetPassthrough",
            "hdr": true,
            "writer": "svt_av1",
            "encoder_speeds": ["faster", "balanced", "smaller"]
        })
    );
}

#[test]
fn no_other_row_names_a_writer_or_speeds() {
    for row in preset_rows() {
        if text(&row, "/id") == "av1" {
            continue;
        }
        assert!(
            row.get("writer").is_none() && row.get("encoder_speeds").is_none(),
            "{} names a writer or speeds: {row}",
            text(&row, "/id")
        );
    }
}

#[test]
fn its_resolved_settings_are_written_out_whole() {
    assert_eq!(
        settings(&project(), "av1", None),
        json!({
            "preset": "av1",
            "avf_preset": "AVAssetExportPresetPassthrough",
            "container": "mp4",
            "file_type": "public.mpeg-4",
            "codec": "av1",
            "width": 1600,
            "height": 900,
            "fps": [30, 1],
            "range": {"start": 0, "duration": 6_000_000},
            "audio": true,
            "video": true,
            "alpha": false,
            "optimize_for_network": true,
            "writer": "svt_av1",
            "encoder_speed": "balanced"
        })
    );
}

#[test]
fn each_speed_comes_back_as_asked_and_null_is_balanced() {
    let handle = project();
    for word in ["faster", "balanced", "smaller"] {
        let out = settings(&handle, "av1", Some(&json!({"encoder_speed": word})));
        assert_eq!(out["encoder_speed"], json!(word), "{word}");
        assert_eq!(out["writer"], json!("svt_av1"), "{word}");
    }
    let out = settings(&handle, "av1", Some(&json!({"encoder_speed": null})));
    assert_eq!(out["encoder_speed"], json!("balanced"));
}

#[test]
fn a_word_that_is_not_a_speed_is_refused_naming_the_key_and_the_value() {
    let handle = project();
    for (preset, value) in [
        ("av1", json!("fast")),
        ("av1", json!(6)),
        ("av1", json!("Balanced")),
        ("h264", json!("fast")),
    ] {
        let msg = refusal(&handle, preset, &json!({"encoder_speed": value}));
        assert_eq!(
            msg,
            format!(
                "export encoder_speed must be \"faster\", \"balanced\" or \"smaller\", not {value}"
            ),
            "{preset} with {value}"
        );
    }
}

#[test]
fn a_speed_on_a_row_without_one_is_refused_naming_the_row() {
    let handle = project();
    for preset in [
        "h264",
        "hevc",
        "hevc_10bit",
        "prores_422",
        "gif",
        "audio_m4a",
    ] {
        let msg = refusal(&handle, preset, &json!({"encoder_speed": "faster"}));
        assert_eq!(
            msg,
            format!("{preset} has no encoder speed; encoder_speed applies to av1")
        );
        assert_contains(&msg, "encoder_speed");
    }
}

#[test]
fn h264s_settings_are_what_they_were() {
    assert_eq!(
        settings(&project(), "h264", None),
        json!({
            "preset": "h264",
            "avf_preset": "AVAssetExportPresetHighestQuality",
            "container": "mp4",
            "file_type": "public.mpeg-4",
            "codec": "h264",
            "width": 1600,
            "height": 900,
            "fps": [30, 1],
            "range": {"start": 0, "duration": 6_000_000},
            "audio": true,
            "video": true,
            "alpha": false,
            "optimize_for_network": true
        })
    );
}

#[test]
fn an_odd_canvas_is_evened_on_av1() {
    let handle = project();
    let out = settings(&handle, "av1", Some(&json!({"width": 641, "height": 361})));
    assert_eq!(
        (out["width"].clone(), out["height"].clone()),
        (json!(640), json!(360))
    );
}

#[test]
fn an_hlg_project_writes_hlg_by_default_and_pq_or_sdr_as_asked() {
    let hlg = project().apply(&json!({"op": "set_canvas", "output": "hlg"}));
    let whole = |color: &str| {
        json!({
            "preset": "av1",
            "avf_preset": "AVAssetExportPresetPassthrough",
            "container": "mp4",
            "file_type": "public.mpeg-4",
            "codec": "av1",
            "width": 1600,
            "height": 900,
            "fps": [30, 1],
            "range": {"start": 0, "duration": 6_000_000},
            "audio": true,
            "video": true,
            "alpha": false,
            "optimize_for_network": true,
            "color": color,
            "writer": "svt_av1",
            "encoder_speed": "balanced"
        })
    };
    assert_eq!(settings(&hlg, "av1", None), whole("hlg"));
    for color in ["hlg", "pq", "sdr"] {
        assert_eq!(
            settings(&hlg, "av1", Some(&json!({"dynamic_range": color}))),
            whole(color),
            "{color}"
        );
    }
}
