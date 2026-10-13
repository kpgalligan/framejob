//! Black-box tests for the `hevc_10bit` export row — spec §7.8 and §11
//! PR-3 (the precision road map's PR3), driven through `rc_export_presets`
//! and `rc_export_settings` exactly as the export sheet and the agent's
//! `export` tool drive them.
//!
//! The row is `hevc`'s MP4 with the Main 10 profile: the depth is the
//! WRITER's choice (`ExporterWriter+Settings.swift` maps the codec
//! `hevc_10bit` to `AVVideoCodecType.hevc` with
//! `kVTProfileLevel_HEVC_Main10_AutoLevel`), so in the core the row differs
//! from `hevc` in its id, its name and its codec, and in nothing else.
//!
//! What the file is built to catch:
//!
//! 1. **The row, whole.** The preset row and its resolved settings — with
//!    nothing asked for, and with every optional override — are written out
//!    by hand, so a key gained, lost or changed fails here by name.
//! 2. **Its place.** It sits directly after `hevc_alpha`, which G-33 keeps
//!    directly after `hevc`; `core/tests/export.rs`'s
//!    `hevc_alpha_sits_directly_after_hevc` and `the_hevc_row_is_what_it_was`
//!    hold the other two rows where they were.
//! 3. **No alpha.** HEVC Main 10 has no fourth channel; the row is even-sized
//!    like every AVFoundation row but ProRes 4444
//!    (`core/tests/export_size.rs` lists it).

mod common;

use serde_json::{json, Value};

use common::{expect_string, parse_json, text, Handle};
use framejob_core::ffi_query::rc_export_presets;

/// One second in ticks (spec §5.1).
const SECOND: i64 = 600_000;

/// A 1600 × 900, 30 fps project with one ten-second clip: no preset is
/// that size or that rate, so "the project's own" is visible in every
/// number below.
fn project() -> Handle {
    project_with_background_alpha(1)
}

/// The same project with the canvas background at `alpha` (1 opaque, 0
/// transparent).
fn project_with_background_alpha(alpha: i64) -> Handle {
    Handle::from_value(&json!({
        "version": 1,
        "canvas": {
            "width": 1600, "height": 900, "fps": [30, 1],
            "background": [0, 0, 0, alpha], "fit_new_clips": true, "timecode_frames": true
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

fn settings(handle: &Handle, overrides: Option<&Value>) -> Value {
    match handle.export_settings("hevc_10bit", overrides) {
        Ok(value) => value,
        Err(msg) => panic!("hevc_10bit was expected to resolve, but: {msg}"),
    }
}

#[test]
fn the_row_is_written_out_whole() {
    let row = preset_rows()
        .into_iter()
        .find(|row| text(row, "/id") == "hevc_10bit")
        .expect("the menu has no hevc_10bit row");
    assert_eq!(
        row,
        json!({
            "id": "hevc_10bit",
            "name": "HEVC 10-bit (MP4)",
            "container": "mp4",
            "codec": "hevc_10bit",
            "video": true,
            "size": null,
            "fps": null,
            "avf_preset": "AVAssetExportPresetHEVCHighestQuality"
        })
    );
}

#[test]
fn its_resolved_settings_are_written_out_whole() {
    let handle = project();
    assert_eq!(
        settings(&handle, None),
        json!({
            "preset": "hevc_10bit",
            "avf_preset": "AVAssetExportPresetHEVCHighestQuality",
            "container": "mp4",
            "file_type": "public.mpeg-4",
            "codec": "hevc_10bit",
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
    let every = json!({
        "video_bitrate": 8_000_000,
        "audio_bitrate": 192_000,
        "loudness_lufs": -14.0,
        "peak_dbtp": -1.0
    });
    assert_eq!(
        settings(&handle, Some(&every)),
        json!({
            "preset": "hevc_10bit",
            "avf_preset": "AVAssetExportPresetHEVCHighestQuality",
            "container": "mp4",
            "file_type": "public.mpeg-4",
            "codec": "hevc_10bit",
            "width": 1600,
            "height": 900,
            "fps": [30, 1],
            "video_bitrate": 8_000_000,
            "audio_bitrate": 192_000,
            "loudness_lufs": -14.0,
            "peak_dbtp": -1.0,
            "range": {"start": 0, "duration": 6_000_000},
            "audio": true,
            "video": true,
            "alpha": false,
            "optimize_for_network": true
        })
    );
}

/// After `hevc_alpha` and before `prores_422`: G-33 keeps `hevc_alpha`
/// directly after `hevc`, so the 10-bit row is the third HEVC row, and the
/// ProRes pair still follows the HEVC rows.
#[test]
fn it_sits_directly_after_hevc_alpha() {
    let ids: Vec<String> = preset_rows()
        .iter()
        .map(|row| text(row, "/id").to_string())
        .collect();
    let alpha = ids
        .iter()
        .position(|id| id == "hevc_alpha")
        .expect("the menu has no hevc_alpha row");
    assert_eq!(
        ids.get(alpha + 1).map(String::as_str),
        Some("hevc_10bit"),
        "the row after hevc_alpha is not hevc_10bit: {ids:?}"
    );
    assert_eq!(
        ids.get(alpha + 2).map(String::as_str),
        Some("prores_422"),
        "the row after hevc_10bit is not prores_422: {ids:?}"
    );
}

/// No fourth channel, on an opaque canvas or a transparent one: `alpha` is
/// the encoding's fact (§7.8), and Main 10 has none.
#[test]
fn it_carries_no_alpha() {
    let handle = project();
    assert_eq!(settings(&handle, None)["alpha"], json!(false));
    let transparent = project_with_background_alpha(0);
    assert_eq!(settings(&transparent, None)["alpha"], json!(false));
}
