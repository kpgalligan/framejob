//! Black-box tests for the qualifier's two recipe options (spec §11 GR-13),
//! `selection` (Show Selection, `render_frame {selection}`) and `behind`
//! (Pick from Canvas), driven through `rc_project_frame_recipe_opts` as
//! `RecipeOptions.swift` drives it.
//!
//! Pinned here: with neither option the recipe is byte-identical; a
//! selection marks its adjustment layer and leaves out every layer in front
//! of it except the ones drawn into a matte, keeping every layer behind; a
//! selection with no such layer on the frame — outside its span, a picture
//! clip's id, a deleted clip — answers no layers on black; `behind` leaves
//! out the layer and the same layers in front, and changes nothing when the
//! clip is not drawn; a mistyped id is off; and the burn-in still comes
//! last.

mod common;

use serde_json::{json, Value};

use common::{array, Handle};

/// Ticks per second (spec §5.1).
const SEC: i64 = 600_000;

/// On a white canvas: a shape (10) on track 1 over `[0, 4 s)`, an
/// adjustment clip (11) on track 2 over `[0, 2 s)`, and shapes in front on
/// tracks 3 (12) and 4 (13) over `[0, 4 s)`.
fn project() -> Handle {
    let shape = |id: u32, track: u32| {
        json!({"id": id, "track": track, "start": 0, "duration": 4 * SEC,
               "source": {"kind": "shape"}, "video": {},
               "shape": {"kind": "rectangle", "width": 100, "height": 50}})
    };
    Handle::from_value(&json!({
        "version": 18,
        "canvas": {"width": 640, "height": 360, "fps": [30, 1],
                   "background": [1.0, 1.0, 1.0, 1.0]},
        "tracks": [{"id": 1, "name": "Back"}, {"id": 2, "name": "Adjustment"},
                   {"id": 3, "name": "Front"}, {"id": 4, "name": "Fronter"}],
        "clips": [
            shape(10, 1),
            {"id": 11, "track": 2, "start": 0, "duration": 2 * SEC,
             "source": {"kind": "adjustment"}, "video": {"color": {"exposure": 1.0}}},
            shape(12, 3),
            shape(13, 4)
        ],
        "next_id": 20
    }))
}

/// The clip ids of the recipe's layers, in order.
fn clips(recipe: &Value) -> Vec<u64> {
    array(recipe, "/layers")
        .iter()
        .filter_map(|l| l["clip"].as_u64())
        .collect()
}

fn background(recipe: &Value) -> &Value {
    &recipe["canvas"]["background"]
}

#[test]
fn neither_option_changes_nothing() {
    let handle = project();
    let plain = handle.recipe_text(SEC);
    for opts in [
        "{}",
        r#"{"selection": null}"#,
        r#"{"selection": "11"}"#,
        r#"{"behind": -11}"#,
        r#"{"selection": 4294967307}"#,
        r#"{"behind": 11.5}"#,
    ] {
        assert_eq!(
            handle.recipe_opts_text(SEC, opts).as_deref(),
            Some(plain.as_str()),
            "{opts}"
        );
    }
}

#[test]
fn a_selection_marks_its_layer_and_leaves_out_the_layers_in_front() {
    let handle = project();
    let recipe = handle.recipe_opts(SEC, r#"{"selection": 11}"#);
    assert_eq!(clips(&recipe), vec![10, 11]);
    let layers = array(&recipe, "/layers");
    assert_eq!(
        layers[1]["source"],
        json!({"kind": "adjustment", "selection": true})
    );
    // Everything behind it is untouched, and so is the background.
    let plain = handle.recipe(SEC);
    assert_eq!(layers[0], array(&plain, "/layers")[0]);
    assert_eq!(background(&recipe), background(&plain));
    // A qualifier rides beside the mark.
    let qualified = handle.apply(&json!({"op": "set_video", "clips": [11],
        "patch": {"qualifier": {"luma": {}}}}));
    let qualified_recipe = qualified.recipe_opts(SEC, r#"{"selection": 11}"#);
    let marked = &array(&qualified_recipe, "/layers")[1];
    assert_eq!(marked["source"]["selection"], json!(true));
    assert_eq!(
        marked["source"]["qualifier"],
        json!({"luma": {"low": 0.0, "high": 1.0, "softness": 0.1}})
    );
}

#[test]
fn a_layer_drawn_into_a_matte_in_front_is_kept() {
    // Track 3 becomes an alpha matte: it cuts track 2, the adjustment clip's.
    let handle = project().apply(&json!({"op": "set_track", "track": 3, "matte": "alpha"}));
    let plain = handle.recipe(SEC);
    let recipe = handle.recipe_opts(SEC, r#"{"selection": 11}"#);
    assert_eq!(clips(&recipe), vec![10, 11, 12]);
    let layers = array(&recipe, "/layers");
    assert_eq!(layers[2], array(&plain, "/layers")[2]);
    assert!(!layers[1]["matte"].is_null(), "{}", layers[1]);
    assert_eq!(recipe["mattes"], plain["mattes"]);
    let behind = handle.recipe_opts(SEC, r#"{"behind": 11}"#);
    assert_eq!(clips(&behind), vec![10, 12]);
}

#[test]
fn a_selection_with_no_such_layer_on_the_frame_is_black() {
    let handle = project();
    let black = json!([0.0, 0.0, 0.0, 1.0]);
    for (t, opts) in [
        (3 * SEC, r#"{"selection": 11}"#),
        (SEC, r#"{"selection": 10}"#),
        (SEC, r#"{"selection": 99}"#),
    ] {
        let recipe = handle.recipe_opts(t, opts);
        assert!(array(&recipe, "/layers").is_empty(), "{opts} at {t}");
        assert_eq!(background(&recipe), &black, "{opts} at {t}");
    }
    let deleted = handle.apply(&json!({"op": "delete", "clips": [11]}));
    let recipe = deleted.recipe_opts(SEC, r#"{"selection": 11}"#);
    assert!(array(&recipe, "/layers").is_empty());
    assert_eq!(background(&recipe), &black);
}

#[test]
fn behind_leaves_out_the_layer_and_the_layers_in_front() {
    let handle = project();
    let recipe = handle.recipe_opts(SEC, r#"{"behind": 11}"#);
    assert_eq!(clips(&recipe), vec![10]);
    assert_eq!(
        array(&recipe, "/layers")[0],
        array(&handle.recipe(SEC), "/layers")[0]
    );
    // Not drawn: unchanged.
    assert_eq!(
        handle.recipe_opts_text(3 * SEC, r#"{"behind": 11}"#),
        Some(handle.recipe_text(3 * SEC))
    );
    assert_eq!(
        handle.recipe_opts_text(SEC, r#"{"behind": 12}"#),
        Some(handle.recipe_text(SEC))
    );
}

#[test]
fn the_burn_in_still_comes_last() {
    let handle = project();
    let recipe = handle.recipe_opts(SEC, r#"{"selection": 11, "burn_in_timecode": true}"#);
    let layers = array(&recipe, "/layers");
    assert_eq!(layers.len(), 3);
    assert_eq!(layers[2]["source"]["kind"], json!("text"));
    assert_eq!(layers[1]["source"]["selection"], json!(true));
}
