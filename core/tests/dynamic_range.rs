//! Black-box tests for an HLG project's deliverables (spec §11 HD-5, HD-14):
//! the export override `dynamic_range`, the settings' `color`, the presets'
//! `hdr`, and the recipe option that puts the output pass's arm on the
//! recipe's canvas, driven through the C FFI exactly as `ReelCore.swift`
//! drives it.
//!
//! Pinned here: every video row's `color` in both outputs at each value; the
//! two refusals' sentences and the reader's; an SDR project's settings and
//! recipe text unchanged by `dynamic_range: "sdr"`; the recipe's
//! `dynamic_range` present only for an HLG canvas asked `sdr` or `pq`; an
//! audio row unchanged; `hdr` on the three 10-bit rows alone; and a nest's
//! scoped view of an HLG project carrying the key.

mod common;

use serde_json::{json, Value};

use common::{at, expect_string, parse_json, text, Handle};
use framejob_core::ffi_query::rc_export_presets;

const SECOND: i64 = 600_000;
const HDR_ROWS: [&str; 3] = ["hevc_10bit", "prores_422", "prores_4444"];

/// One video media on one track, and a nest (5) of a second clip, shown by a
/// nest clip after it.
fn fixture() -> Handle {
    Handle::from_value(&json!({
        "version": 23,
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

fn preset_rows() -> Vec<Value> {
    let text_ = expect_string(unsafe { rc_export_presets() }, "rc_export_presets");
    match parse_json(&text_, "rc_export_presets") {
        Value::Array(rows) => rows,
        other => panic!("rc_export_presets is not an array: {other}"),
    }
}

fn rows() -> Vec<(String, bool)> {
    preset_rows()
        .iter()
        .map(|row| (text(row, "/id").to_string(), row["video"] == json!(true)))
        .collect()
}

fn asking(range: &str) -> Value {
    json!({ "dynamic_range": range })
}

fn sdr_needs_hlg(range: &str) -> String {
    format!("dynamic_range \"{range}\" needs an HLG project; set_canvas output \"hlg\" first")
}

fn eight_bit(id: &str, range: &str) -> String {
    format!(
        "{id} is 8-bit and writes the SDR version; export dynamic_range \"{range}\" as \
         hevc_10bit, prores_422 or prores_4444"
    )
}

#[test]
fn every_video_row_of_an_hlg_project_at_each_value() {
    let hlg = hlg();
    let sdr = fixture();
    for (id, video) in rows() {
        if !video {
            continue;
        }
        let plain = sdr.export_settings(&id, None).expect("resolves in SDR");
        let with = |color: &str| {
            let mut want = plain.clone();
            want["color"] = json!(color);
            want
        };
        if HDR_ROWS.contains(&id.as_str()) {
            assert_eq!(hlg.export_settings(&id, None), Ok(with("hlg")), "{id}");
            for range in ["hlg", "pq", "sdr"] {
                assert_eq!(
                    hlg.export_settings(&id, Some(&asking(range))),
                    Ok(with(range)),
                    "{id} at {range}"
                );
            }
        } else {
            assert_eq!(hlg.export_settings(&id, None), Ok(with("sdr")), "{id}");
            assert_eq!(
                hlg.export_settings(&id, Some(&asking("sdr"))),
                Ok(with("sdr")),
                "{id} at sdr"
            );
            for range in ["hlg", "pq"] {
                assert_eq!(
                    hlg.export_settings(&id, Some(&asking(range))),
                    Err(eight_bit(&id, range)),
                    "{id} at {range}"
                );
            }
        }
    }
}

#[test]
fn an_sdr_project_refuses_hdr_and_takes_sdr_as_nothing() {
    let sdr = fixture();
    for (id, video) in rows() {
        let plain = sdr.export_settings(&id, None).expect("resolves");
        let asked = sdr
            .export_settings(&id, Some(&asking("sdr")))
            .expect("sdr resolves in an SDR project");
        assert_eq!(asked.to_string(), plain.to_string(), "{id}");
        assert!(!plain.to_string().contains("\"color\""), "{id}: {plain}");
        for range in ["hlg", "pq"] {
            let answer = sdr.export_settings(&id, Some(&asking(range)));
            if video {
                assert_eq!(answer, Err(sdr_needs_hlg(range)), "{id} at {range}");
            } else {
                assert_eq!(answer, Ok(plain.clone()), "{id}: an audio row ignores it");
            }
        }
    }
}

#[test]
fn an_audio_row_reads_the_value_and_ignores_it() {
    let hlg = hlg();
    let sdr = fixture();
    for (id, video) in rows() {
        if video {
            continue;
        }
        let plain = sdr.export_settings(&id, None).expect("resolves");
        for range in ["hlg", "pq", "sdr"] {
            assert_eq!(
                hlg.export_settings(&id, Some(&asking(range))),
                Ok(plain.clone()),
                "{id} at {range}"
            );
        }
        // Read, so a value that is not one of the three is still refused.
        assert!(hlg.export_settings(&id, Some(&asking("bogus"))).is_err());
    }
}

#[test]
fn the_reader_refuses_anything_but_the_three_words() {
    for handle in [fixture(), hlg()] {
        for (value, shown) in [
            (json!("bogus"), "\"bogus\""),
            (json!("HLG"), "\"HLG\""),
            (json!(1), "1"),
            (json!(true), "true"),
            (json!(["pq"]), "[\"pq\"]"),
        ] {
            assert_eq!(
                handle.export_settings("h264", Some(&json!({ "dynamic_range": value }))),
                Err(format!(
                    "export dynamic_range must be \"hlg\", \"pq\" or \"sdr\", not {shown}"
                )),
            );
        }
        // Null is absent (rule 1).
        assert_eq!(
            handle.export_settings("h264", Some(&json!({"dynamic_range": null}))),
            handle.export_settings("h264", None)
        );
    }
}

#[test]
fn the_presets_name_hdr_on_the_three_ten_bit_rows_alone() {
    let presets = preset_rows();
    for row in &presets {
        let id = text(row, "/id");
        if HDR_ROWS.contains(&id) {
            assert_eq!(row["hdr"], json!(true), "{id}");
        } else {
            assert!(row.get("hdr").is_none(), "{id}: {row}");
        }
    }
    assert_eq!(
        presets
            .iter()
            .filter(|row| row.get("hdr").is_some())
            .count(),
        3
    );
}

#[test]
fn the_recipe_names_the_range_only_for_an_hlg_canvas_asked_sdr_or_pq() {
    let sdr = fixture();
    let hlg = hlg();
    let plain = sdr.recipe_text(SECOND);
    for range in ["hlg", "pq", "sdr", "bogus"] {
        assert_eq!(
            sdr.recipe_opts_text(SECOND, &asking(range)).as_deref(),
            Some(plain.as_str()),
            "an SDR project at {range}"
        );
    }
    let hlg_plain = hlg.recipe_text(SECOND);
    assert!(!hlg_plain.contains("dynamic_range"), "{hlg_plain}");
    for range in ["hlg", "bogus"] {
        assert_eq!(
            hlg.recipe_opts_text(SECOND, &asking(range)).as_deref(),
            Some(hlg_plain.as_str()),
            "an HLG project at {range}"
        );
    }
    assert_eq!(
        hlg.recipe_opts_text(SECOND, &json!({"dynamic_range": 1}))
            .as_deref(),
        Some(hlg_plain.as_str())
    );
    for range in ["sdr", "pq"] {
        let recipe = hlg.recipe_opts(SECOND, &asking(range));
        assert_eq!(at(&recipe, "/canvas/dynamic_range"), &json!(range));
        // After `output`, and nothing else moved.
        let keys: Vec<&String> = recipe["canvas"]
            .as_object()
            .expect("canvas")
            .keys()
            .collect();
        assert_eq!(keys.last().map(|k| k.as_str()), Some("dynamic_range"));
        let mut back = recipe.clone();
        back["canvas"]
            .as_object_mut()
            .expect("canvas")
            .remove("dynamic_range");
        assert_eq!(back.to_string(), hlg_plain, "{range}");
    }
}

#[test]
fn a_nests_scoped_view_of_an_hlg_project_carries_the_key() {
    let view = hlg().scoped(5);
    let recipe = view.recipe_opts(SECOND, &asking("sdr"));
    assert_eq!(at(&recipe, "/canvas/output"), &json!("hlg"));
    assert_eq!(at(&recipe, "/canvas/dynamic_range"), &json!("sdr"));
    let sdr_view = fixture().scoped(5);
    assert_eq!(
        sdr_view.recipe_opts_text(SECOND, &asking("sdr")),
        Some(sdr_view.recipe_text(SECOND))
    );
}
