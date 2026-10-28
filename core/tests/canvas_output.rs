//! Black-box tests for the project's dynamic range (spec §11 HD-2, HD-13;
//! format 23): `canvas.output`, `set_canvas {output}`, the recipe's and the
//! plan's `output`, and the export resolver's HLG arm, driven through the C
//! FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: `set_canvas {output: "hlg"}` applies and the same output is
//! an identity; an unknown value is invalid input naming serde's list; the
//! recipe's canvas and the plan carry `"output": "hlg"` only in an HLG
//! project; in an HLG project the four HDR rows gain `"color": "hlg"`,
//! every other video row `"color": "sdr"` (H-3's SDR version, spec §11
//! HD-14, where H-2 refused it) and an audio row is unchanged, while an SDR
//! project's settings are the text they were; `set_canvas` inside a scope
//! is still refused; and a nest's scoped view of an HLG project composes in
//! HLG.

mod common;

use serde_json::{json, Value};

use common::{at, expect_string, parse_json, text, Handle, Outcome};
use framejob_core::ffi_query::rc_export_presets;

const SECOND: i64 = 600_000;

/// One video media on one track, and a nest (5) of a second clip, shown by
/// a nest clip after it.
fn fixture() -> Handle {
    Handle::from_value(&json!({
        "version": 22,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{
            "id": 1, "path": "/fixtures/clip.mov", "kind": "video",
            "duration": 10 * SECOND, "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{"id": 2, "name": "Track 1"}],
        "clips": [
            {"id": 3, "track": 2, "start": 0, "duration": 4 * SECOND,
             "source": {"kind": "media", "media": 1, "in": 0}},
            {"id": 4, "track": 2, "start": 4 * SECOND, "duration": 2 * SECOND,
             "source": {"kind": "nest", "project": 5}, "video": {}}
        ],
        "nests": [{
            "id": 5, "name": "Nest 5", "width": 1920, "height": 1080,
            "tracks": [{"id": 6, "name": "Track 1"}],
            "clips": [{"id": 7, "track": 6, "start": 0, "duration": 2 * SECOND,
                       "source": {"kind": "media", "media": 1, "in": 0}}]
        }],
        "next_id": 8
    }))
}

fn hlg() -> Handle {
    fixture().apply(&json!({"op": "set_canvas", "output": "hlg"}))
}

fn preset_ids() -> Vec<(String, bool)> {
    let text_ = expect_string(unsafe { rc_export_presets() }, "rc_export_presets");
    match parse_json(&text_, "rc_export_presets") {
        Value::Array(rows) => rows
            .iter()
            .map(|row| (text(row, "/id").to_string(), row["video"] == json!(true)))
            .collect(),
        other => panic!("rc_export_presets is not an array: {other}"),
    }
}

#[test]
fn set_canvas_output_applies_and_the_same_output_is_an_identity() {
    let sdr = fixture();
    assert!(sdr.value()["canvas"].get("output").is_none());
    let hlg = hlg();
    assert_eq!(at(&hlg.value(), "/canvas/output"), &json!("hlg"));
    // Nothing but the output moved.
    let mut before = sdr.value();
    before["canvas"]["output"] = json!("hlg");
    assert_eq!(hlg.value(), before);
    for (handle, same) in [(&sdr, "sdr"), (&hlg, "hlg")] {
        match handle.try_apply(&json!({"op": "set_canvas", "output": same})) {
            Ok(Outcome::Identity) => {}
            other => panic!("set_canvas {{output: {same}}} on itself: {other:?}"),
        }
    }
    let back = hlg.apply(&json!({"op": "set_canvas", "output": "sdr"}));
    assert_eq!(back.to_json(), sdr.to_json());
}

#[test]
fn an_unknown_output_is_invalid_input_naming_the_list() {
    let message = fixture().errors(&json!({"op": "set_canvas", "output": "pq"}));
    assert!(
        message.contains("unknown variant `pq`, expected `sdr` or `hlg`"),
        "{message}"
    );
}

#[test]
fn the_recipe_and_the_plan_name_the_output_only_when_hlg() {
    let sdr = fixture();
    assert!(!sdr.plan_text().contains("\"output\""));
    assert!(!sdr.recipe_text(SECOND).contains("\"output\""));
    let hlg = hlg();
    assert_eq!(at(&hlg.plan(), "/output"), &json!("hlg"));
    assert_eq!(at(&hlg.recipe(SECOND), "/canvas/output"), &json!("hlg"));
    // The SDR texts are the texts an HLG project's would be without the key.
    let back = hlg.apply(&json!({"op": "set_canvas", "output": "sdr"}));
    assert_eq!(back.plan_text(), sdr.plan_text());
    assert_eq!(back.recipe_text(SECOND), sdr.recipe_text(SECOND));
}

#[test]
fn each_export_row_in_both_outputs() {
    let sdr = fixture();
    let hlg = hlg();
    let rows = preset_ids();
    assert!(rows.len() >= 11, "{rows:?}");
    for (id, video) in rows {
        let plain = sdr
            .export_settings(&id, None)
            .unwrap_or_else(|msg| panic!("{id} in an SDR project: {msg}"));
        assert!(plain.get("color").is_none(), "{id}: {plain}");
        let answer = hlg.export_settings(&id, None);
        if !video {
            assert_eq!(
                answer.as_ref(),
                Ok(&plain),
                "{id}: an audio row is unchanged"
            );
        } else if [
            "hevc_10bit",
            "av1",
            "av1_webm",
            "vp9_webm",
            "prores_422",
            "prores_4444",
        ]
        .contains(&id.as_str())
        {
            let mut want = plain.clone();
            want["color"] = json!("hlg");
            assert_eq!(answer, Ok(want), "{id}");
        } else {
            // H-3 (spec §11 HD-14): the SDR version, where H-2 refused.
            let mut want = plain.clone();
            want["color"] = json!("sdr");
            assert_eq!(answer, Ok(want), "{id}");
        }
    }
}

#[test]
fn an_sdr_projects_settings_text_is_unchanged() {
    let sdr = fixture();
    let round = hlg().apply(&json!({"op": "set_canvas", "output": "sdr"}));
    for (id, _) in preset_ids() {
        let a = sdr.export_settings(&id, None).expect("resolves");
        let b = round.export_settings(&id, None).expect("resolves");
        assert_eq!(a.to_string(), b.to_string(), "{id}");
        assert!(!a.to_string().contains("\"color\""), "{id}: {a}");
    }
}

#[test]
fn set_canvas_inside_a_scope_is_still_refused() {
    for base in [fixture(), hlg()] {
        assert_eq!(
            base.errors(&json!({"op": "set_canvas", "output": "hlg", "scope": 5})),
            "set_canvas has no meaning inside nest 5"
        );
    }
}

#[test]
fn a_nests_scoped_view_composes_in_its_documents_output() {
    let sdr_view = fixture().scoped(5);
    assert!(sdr_view.value()["canvas"].get("output").is_none());
    assert!(!sdr_view.plan_text().contains("\"output\""));
    let view = hlg().scoped(5);
    assert_eq!(at(&view.value(), "/canvas/output"), &json!("hlg"));
    assert_eq!(at(&view.plan(), "/output"), &json!("hlg"));
    assert_eq!(at(&view.recipe(SECOND), "/canvas/output"), &json!("hlg"));
}
