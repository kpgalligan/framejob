//! Black-box tests for the canvas's blending (spec §11 GR-18, HD-9, HD-16;
//! format 24): `canvas.blending`, `set_canvas {blending}` and the recipe
//! canvas's `blending`, driven through the C FFI exactly as `ReelCore.swift`
//! drives it.
//!
//! Pinned here: a project has no `blending` until one is set; `linear` is
//! written after `output`; `encoded` removes the key, and the project is the
//! text it was; the blending the canvas already has is an identity; an
//! unknown value is invalid input naming both; the recipe canvas carries
//! `"blending": "linear"` last and only when linear, under SDR and HLG (with
//! the SDR version's `dynamic_range` before it); the plan never names it;
//! and a nest's scoped view, and its recipe, carry the document's blending.

mod common;

use serde_json::{json, Value};

use common::{at, Handle, Outcome};

const SECOND: i64 = 600_000;

/// One video media on one track, and a nest (5) of a second clip, shown by
/// a nest clip after it.
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

fn linear(base: &Handle) -> Handle {
    base.apply(&json!({"op": "set_canvas", "blending": "linear"}))
}

fn hlg() -> Handle {
    fixture().apply(&json!({"op": "set_canvas", "output": "hlg"}))
}

/// The keys of `value`'s canvas, in the order they are written (the core's
/// `serde_json` keeps insertion order, `preserve_order`).
fn canvas_keys(value: &Value) -> Vec<String> {
    value["canvas"]
        .as_object()
        .expect("an object")
        .keys()
        .cloned()
        .collect()
}

#[test]
fn a_project_has_no_blending_until_one_is_set() {
    let plain = fixture();
    assert!(plain.value()["canvas"].get("blending").is_none());
    assert!(!plain.to_json().contains("\"blending\""));
    let made = Handle::new(1920, 1080, 30, 1);
    assert!(!made.to_json().contains("\"blending\""));
}

#[test]
fn linear_is_written_after_output() {
    for base in [fixture(), hlg()] {
        let set = linear(&base);
        assert_eq!(at(&set.value(), "/canvas/blending"), &json!("linear"));
        let text = set.to_json();
        let canvas = &text[text.find("\"canvas\"").expect("a canvas")..];
        let canvas = &canvas[..canvas.find('}').expect("the canvas closes")];
        assert!(
            canvas.trim_end().ends_with("\"blending\": \"linear\""),
            "{canvas}"
        );
        if base.value()["canvas"].get("output").is_some() {
            let output = canvas.find("\"output\"").expect("output");
            let blending = canvas.find("\"blending\"").expect("blending");
            assert!(output < blending, "{canvas}");
        }
        // Nothing but the blending moved.
        let mut before = base.value();
        before["canvas"]["blending"] = json!("linear");
        assert_eq!(set.value(), before);
    }
}

#[test]
fn encoded_removes_the_key() {
    for base in [fixture(), hlg()] {
        let back = linear(&base).apply(&json!({"op": "set_canvas", "blending": "encoded"}));
        assert!(back.value()["canvas"].get("blending").is_none());
        assert_eq!(back.to_json(), base.to_json());
    }
}

#[test]
fn the_same_blending_is_an_identity() {
    let encoded = fixture();
    let linear = linear(&encoded);
    for (handle, same) in [(&encoded, "encoded"), (&linear, "linear")] {
        match handle.try_apply(&json!({"op": "set_canvas", "blending": same})) {
            Ok(Outcome::Identity) => {}
            other => panic!("set_canvas {{blending: {same}}} on itself: {other:?}"),
        }
    }
}

#[test]
fn an_unknown_blending_is_invalid_input_naming_both() {
    let message = fixture().errors(&json!({"op": "set_canvas", "blending": "gamma"}));
    assert!(
        message.contains("unknown variant `gamma`, expected `encoded` or `linear`"),
        "{message}"
    );
}

#[test]
fn the_recipe_canvas_carries_linear_last_and_only_when_linear() {
    for base in [fixture(), hlg()] {
        assert!(!base.recipe_text(SECOND).contains("\"blending\""));
        let set = linear(&base);
        let recipe = set.recipe(SECOND);
        assert_eq!(at(&recipe, "/canvas/blending"), &json!("linear"));
        assert_eq!(
            canvas_keys(&recipe).last().map(String::as_str),
            Some("blending")
        );
        // The plan is unchanged.
        assert_eq!(set.plan_text(), base.plan_text());
        assert!(!set.plan_text().contains("\"blending\""));
        // Back to encoded, the recipe is the text it was.
        let back = set.apply(&json!({"op": "set_canvas", "blending": "encoded"}));
        assert_eq!(back.recipe_text(SECOND), base.recipe_text(SECOND));
    }
    // An HLG canvas asked for its SDR version: `dynamic_range` before it.
    let asked = linear(&hlg()).recipe_opts(SECOND, &json!({"dynamic_range": "sdr"}));
    assert_eq!(
        canvas_keys(&asked),
        [
            "width",
            "height",
            "background",
            "output",
            "dynamic_range",
            "blending"
        ]
    );
}

#[test]
fn a_nests_scoped_view_carries_its_documents_blending() {
    let plain_view = fixture().scoped(5);
    assert!(plain_view.value()["canvas"].get("blending").is_none());
    let view = linear(&fixture()).scoped(5);
    assert_eq!(at(&view.value(), "/canvas/blending"), &json!("linear"));
    assert_eq!(
        at(&view.recipe(SECOND), "/canvas/blending"),
        &json!("linear")
    );
}

#[test]
fn set_canvas_blending_inside_a_scope_is_refused() {
    assert_eq!(
        fixture().errors(&json!({"op": "set_canvas", "blending": "linear", "scope": 5})),
        "set_canvas has no meaning inside nest 5"
    );
}
