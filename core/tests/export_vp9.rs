//! Black-box tests for the `vp9_webm` export row — spec §7.8 and §11 CX-16
//! (codec-export C4), driven through `rc_export_presets` and
//! `rc_export_settings` exactly as the export sheet and the agent's `export`
//! tool drive them.
//!
//! The row is VP9 in WebM: libvpx encodes the picture (`writer` `libvpx`) at
//! its one speed (CX-3), into the WebM the core writes, with Opus sound.
//!
//! What the file is built to catch:
//!
//! 1. **The row, whole**, directly after `av1_webm`: `hdr`, `writer`
//!    `libvpx` and no `encoder_speeds`.
//! 2. **The settings**, written out whole: `writer` and no `encoder_speed`,
//!    `optimize_for_network` off.
//! 3. **The speed refusal.** `encoder_speed` on the row is refused naming
//!    the row and the key, whatever the word.
//! 4. **HDR.** In an HLG project the settings carry `color` `hlg` by
//!    default and `pq` or `sdr` as asked; an SDR project refuses `hlg` and
//!    `pq` and takes `sdr` as nothing.
//! 5. **Even-sized**, as every 4:2:0 row.

mod common;

use serde_json::{json, Value};

use common::{expect_string, parse_json, text, Handle};
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

fn preset_rows() -> Vec<Value> {
    let text = expect_string(unsafe { rc_export_presets() }, "rc_export_presets");
    match parse_json(&text, "rc_export_presets") {
        Value::Array(rows) => rows,
        other => panic!("rc_export_presets is not an array: {other}"),
    }
}

fn settings(handle: &Handle, overrides: Option<&Value>) -> Value {
    match handle.export_settings("vp9_webm", overrides) {
        Ok(value) => value,
        Err(msg) => panic!("vp9_webm was expected to resolve, but: {msg}"),
    }
}

fn refusal(handle: &Handle, overrides: &Value) -> String {
    match handle.export_settings("vp9_webm", Some(overrides)) {
        Ok(value) => panic!("vp9_webm with {overrides} was expected to be refused: {value}"),
        Err(msg) => msg,
    }
}

/// The settings of the 1600 × 900 project, `color` added when given.
fn whole(color: Option<&str>) -> Value {
    let mut out = json!({
        "preset": "vp9_webm",
        "avf_preset": "AVAssetExportPresetPassthrough",
        "container": "webm",
        "file_type": "org.webmproject.webm",
        "codec": "vp9",
        "width": 1600,
        "height": 900,
        "fps": [30, 1],
        "range": {"start": 0, "duration": 6_000_000},
        "audio": true,
        "video": true,
        "alpha": false,
        "optimize_for_network": false,
        "writer": "libvpx"
    });
    if let Some(color) = color {
        out["color"] = json!(color);
    }
    out
}

#[test]
fn the_row_is_written_out_whole_directly_after_av1_webm() {
    let rows = preset_rows();
    let at = rows
        .iter()
        .position(|row| text(row, "/id") == "vp9_webm")
        .expect("the menu has no vp9_webm row");
    assert_eq!(text(&rows[at - 1], "/id"), "av1_webm");
    assert_eq!(
        rows[at],
        json!({
            "id": "vp9_webm",
            "name": "VP9 (WebM)",
            "container": "webm",
            "codec": "vp9",
            "video": true,
            "size": null,
            "fps": null,
            "avf_preset": "AVAssetExportPresetPassthrough",
            "hdr": true,
            "writer": "libvpx"
        })
    );
}

#[test]
fn its_settings_carry_the_writer_and_no_speed() {
    let out = settings(&project(), None);
    assert_eq!(out, whole(None));
    assert!(out.get("encoder_speed").is_none());
    let null = settings(&project(), Some(&json!({"encoder_speed": null})));
    assert_eq!(null, whole(None), "null is absent");
}

#[test]
fn a_speed_on_it_is_refused_naming_the_row() {
    let handle = project();
    for word in ["faster", "balanced", "smaller"] {
        assert_eq!(
            refusal(&handle, &json!({"encoder_speed": word})),
            "vp9_webm has no encoder speed; encoder_speed applies to av1 and av1_webm",
            "{word}"
        );
    }
    assert_eq!(
        refusal(&handle, &json!({"encoder_speed": "fast"})),
        "export encoder_speed must be \"faster\", \"balanced\" or \"smaller\", not \"fast\""
    );
}

#[test]
fn an_hlg_project_writes_hlg_by_default_and_pq_or_sdr_as_asked() {
    let hlg = project().apply(&json!({"op": "set_canvas", "output": "hlg"}));
    assert_eq!(settings(&hlg, None), whole(Some("hlg")));
    for color in ["hlg", "pq", "sdr"] {
        assert_eq!(
            settings(&hlg, Some(&json!({"dynamic_range": color}))),
            whole(Some(color)),
            "{color}"
        );
    }
}

#[test]
fn an_sdr_project_refuses_hdr_and_takes_sdr_as_nothing() {
    let sdr = project();
    for range in ["hlg", "pq"] {
        assert_eq!(
            refusal(&sdr, &json!({"dynamic_range": range})),
            format!(
                "dynamic_range \"{range}\" needs an HLG project; set_canvas output \"hlg\" first"
            )
        );
    }
    assert_eq!(
        settings(&sdr, Some(&json!({"dynamic_range": "sdr"}))),
        whole(None)
    );
}

#[test]
fn an_odd_size_is_evened() {
    let out = settings(&project(), Some(&json!({"width": 641, "height": 361})));
    assert_eq!(
        (out["width"].clone(), out["height"].clone()),
        (json!(640), json!(360))
    );
}
