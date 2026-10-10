//! Black-box tests for adjustment clips (spec §11 GR-6), driven through the
//! C FFI exactly as `ReelCore.swift` drives it: the op's placement and
//! defaults, the recipe's `{"kind":"adjustment"}` layer, every sentence on
//! its own channel, the commands that keep working (split, copy and paste),
//! the inert clip on a matte track, the `ungraded` option, the evaluator's
//! clamp of an action's end, and the round trip through the current format.
//! What the pass does to a pixel is `tools/proof/adjustment_proof.py`'s.

mod common;

use serde_json::{json, Value};

use common::{array, by_id, Handle, Outcome};
use reelcut_core::format::RC_FORMAT_VERSION;

/// Ticks per second (spec §5.1).
const SEC: i64 = 600_000;

/// The id of the last element of the array at `pointer`.
fn last_id(handle: &Handle, pointer: &str) -> u32 {
    let value = handle.value();
    let id = array(&value, pointer)
        .iter()
        .filter_map(|v| v["id"].as_u64())
        .max()
        .unwrap_or_else(|| panic!("no ids at {pointer}"));
    u32::try_from(id).expect("an id fits in u32")
}

/// A new track at the front, and its id.
fn add_track(handle: Handle) -> (Handle, u32) {
    let next = handle.apply(&json!({"op": "add_track"}));
    let id = last_id(&next, "/tracks");
    (next, id)
}

/// The fixture: a shape on track 1 over `[0, 4 s)`, an adjustment clip on a
/// track of its own over `[0, 4 s)`, and a shape in front of it on a third.
/// Answers the handle, the adjustment clip's id and its track's.
fn fixture() -> (Handle, u32, u32) {
    let handle = Handle::new(640, 360, 30, 1)
        .apply(&json!({"op": "add_shape_clip", "track": 1, "at": 0, "duration": 4 * SEC}));
    let (handle, two) = add_track(handle);
    let handle = handle
        .apply(&json!({"op": "add_adjustment_clip", "track": two, "at": 0, "duration": 4 * SEC}));
    let adjustment = last_id(&handle, "/clips");
    let (handle, three) = add_track(handle);
    let handle = handle
        .apply(&json!({"op": "add_shape_clip", "track": three, "at": 0, "duration": 4 * SEC}));
    (handle, adjustment, two)
}

/// The clip with this id.
fn clip(handle: &Handle, id: u32) -> Value {
    by_id(&handle.value(), "/clips", u64::from(id)).clone()
}

/// The recipe layer drawing this clip at `t`, if any.
fn layer(handle: &Handle, id: u32, t: i64) -> Option<Value> {
    array(&handle.recipe(t), "/layers")
        .iter()
        .find(|l| l["clip"] == json!(id))
        .cloned()
}

/// The transition sentence (choice 10).
fn no_transition(id: u32) -> String {
    format!("clip {id} is an adjustment clip and cannot take a transition; fade it with opacity instead")
}

#[test]
fn the_op_places_a_five_second_clip_with_no_picture_and_default_video() {
    let handle = Handle::new(640, 360, 30, 1).apply(&json!({
        "op": "add_adjustment_clip", "track": 1, "at": SEC
    }));
    let id = last_id(&handle, "/clips");
    let placed = clip(&handle, id);
    assert_eq!(placed["source"], json!({"kind": "adjustment"}));
    assert_eq!(placed["start"], json!(SEC));
    assert_eq!(placed["duration"], json!(5 * SEC));
    assert_eq!(placed["video"]["scale"], json!(1.0));
    assert_eq!(placed["video"]["opacity"], json!(1.0));
    assert!(placed["audio"].is_null(), "{placed}");
    assert!(placed["text"].is_null() && placed["shape"].is_null());
}

#[test]
fn its_layer_is_an_adjustment_source_with_no_size_between_the_tracks() {
    let (handle, adjustment, _) = fixture();
    let recipe = handle.recipe(SEC);
    let layers = array(&recipe, "/layers");
    assert_eq!(layers.len(), 3, "{recipe}");
    assert_eq!(
        layers[1]["clip"],
        json!(adjustment),
        "drawn between the two"
    );
    assert_eq!(layers[1]["source"], json!({"kind": "adjustment"}));
    assert!(layers[1]["source_size"].is_null());
    assert_eq!(layers[1]["blend"], json!("normal"));
}

#[test]
fn a_project_without_one_keeps_its_recipe_and_the_plan_has_no_segment_for_one() {
    let (handle, adjustment, _) = fixture();
    let without = handle.apply(&json!({"op": "delete", "clips": [adjustment]}));
    let with_layers = array(&handle.recipe(SEC), "/layers").clone();
    let without_layers = array(&without.recipe(SEC), "/layers").clone();
    let kept: Vec<Value> = with_layers
        .into_iter()
        .filter(|l| l["clip"] != json!(adjustment))
        .collect();
    assert_eq!(kept, without_layers);
    assert_eq!(handle.plan(), without.plan(), "nothing to decode");
}

#[test]
fn the_op_inside_a_scope_is_an_error_naming_itself() {
    let (handle, _, _) = fixture();
    let shape = array(&handle.value(), "/clips")[0]["id"]
        .as_u64()
        .expect("a clip id");
    let handle = handle.apply(&json!({"op": "nest", "clips": [shape]}));
    let nest = last_id(&handle, "/nests");
    let inner_track = array(&handle.value(), "/nests/0/tracks")[0]["id"]
        .as_u64()
        .expect("a nest track");
    let error = handle.errors(&json!({
        "op": "add_adjustment_clip", "track": inner_track, "at": 0, "scope": nest
    }));
    assert_eq!(
        error,
        format!("add_adjustment_clip has no meaning inside nest {nest}")
    );
}

#[test]
fn nest_refuses_a_selection_holding_one() {
    let (handle, adjustment, _) = fixture();
    let ids: Vec<u64> = array(&handle.value(), "/clips")
        .iter()
        .filter_map(|c| c["id"].as_u64())
        .collect();
    handle.refuses_with(
        &json!({"op": "nest", "clips": ids}),
        &format!(
            "clip {adjustment} is an adjustment clip, and an adjustment clip cannot go inside a nest"
        ),
    );
}

#[test]
fn a_file_with_one_inside_a_nest_is_an_error_naming_it() {
    let (handle, _, _) = fixture();
    let shape = array(&handle.value(), "/clips")[0]["id"]
        .as_u64()
        .expect("a clip id");
    let handle = handle.apply(&json!({"op": "nest", "clips": [shape]}));
    let mut value = handle.value();
    let nest = value["nests"][0]["id"].as_u64().expect("a nest id");
    let inner = value["nests"][0]["clips"][0].clone();
    let inner_id = inner["id"].as_u64().expect("an inner clip id");
    value["nests"][0]["clips"][0]["source"] = json!({"kind": "adjustment"});
    let Err(error) = Handle::try_from_value(&value) else {
        panic!("a file with an adjustment clip inside a nest was read");
    };
    assert!(
        error.contains(&format!(
            "clip {inner_id} in nest {nest} is an adjustment clip, and an adjustment clip cannot \
             be inside a nest"
        )),
        "{error}"
    );
}

#[test]
fn a_paste_into_a_scope_is_an_error_naming_the_pasted_clip() {
    let (handle, adjustment, _) = fixture();
    let shape = array(&handle.value(), "/clips")[0]["id"]
        .as_u64()
        .expect("a clip id");
    let handle = handle.apply(&json!({"op": "nest", "clips": [shape]}));
    let nest = last_id(&handle, "/nests");
    let mut copied = clip(&handle, adjustment);
    copied["track"] = json!(0);
    let payload = json!({"clips": [copied], "media": []});
    let next_id = handle.value()["next_id"].as_u64().expect("next_id");
    let error = handle.errors(&json!({
        "op": "paste", "at": 10 * SEC, "payload": payload, "scope": nest
    }));
    assert_eq!(
        error,
        format!(
            "clip {next_id} in nest {nest} is an adjustment clip, and an adjustment clip cannot \
             be inside a nest"
        )
    );
}

#[test]
fn every_transition_op_refuses_it_in_one_sentence() {
    // A shape ending exactly where an adjustment clip begins: a hard cut.
    let handle = Handle::new(640, 360, 30, 1).apply_all(&[
        json!({"op": "add_shape_clip", "track": 1, "at": 0, "duration": 2 * SEC}),
        json!({"op": "add_adjustment_clip", "track": 1, "at": 2 * SEC, "duration": 2 * SEC}),
        json!({"op": "add_shape_clip", "track": 1, "at": 4 * SEC, "duration": 2 * SEC}),
    ]);
    let ids: Vec<u32> = array(&handle.value(), "/clips")
        .iter()
        .map(|c| u32::try_from(c["id"].as_u64().unwrap()).unwrap())
        .collect();
    let (adjustment, after) = (ids[1], ids[2]);
    let sentence = no_transition(adjustment);
    // As the incoming clip, and as the outgoing one, in both forms.
    for ripple in [false, true] {
        handle.refuses_with(
            &json!({"op": "add_transition", "clip": adjustment, "duration": SEC / 2,
                    "ripple": ripple}),
            &sentence,
        );
        handle.refuses_with(
            &json!({"op": "add_transition", "clip": after, "duration": SEC / 2,
                    "ripple": ripple}),
            &sentence,
        );
    }
    handle.refuses_with(
        &json!({"op": "set_transition", "clip": adjustment, "kind": "cross_dissolve"}),
        &sentence,
    );
    handle.refuses_with(
        &json!({"op": "set_transition_style", "clip": adjustment, "curve": "ease_in"}),
        &sentence,
    );
    handle.refuses_with(
        &json!({"op": "set_transition_style", "clip": adjustment, "audio": true}),
        &sentence,
    );
    // Neither key is still an identity, and a clear stays one.
    assert!(matches!(
        handle.try_apply(&json!({"op": "set_transition_style", "clip": adjustment})),
        Ok(Outcome::Identity)
    ));
    assert!(matches!(
        handle.try_apply(&json!({"op": "set_transition", "clip": adjustment, "kind": null})),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn an_overlap_with_one_is_refused_in_the_overlap_rules_sentence() {
    let handle = Handle::new(640, 360, 30, 1).apply_all(&[
        json!({"op": "add_shape_clip", "track": 1, "at": 0, "duration": 2 * SEC}),
        json!({"op": "add_adjustment_clip", "track": 1, "at": 2 * SEC, "duration": 2 * SEC}),
    ]);
    let ids: Vec<u32> = array(&handle.value(), "/clips")
        .iter()
        .map(|c| u32::try_from(c["id"].as_u64().unwrap()).unwrap())
        .collect();
    let (shape, adjustment) = (ids[0], ids[1]);
    let sentence = format!(
        "clips {shape} and {adjustment} would overlap, and clip {adjustment} is an adjustment \
         clip, which cannot take a transition; fade it with opacity instead"
    );
    // A neighbour trimmed over it, moved over it, and the clip moved back.
    handle.refuses_with(
        &json!({"op": "trim_end", "clip": shape, "to": 2 * SEC + SEC / 2}),
        &sentence,
    );
    handle.refuses_with(
        &json!({"op": "move_clip", "clips": [adjustment], "delta": -SEC / 2}),
        &sentence,
    );
    handle.refuses_with(
        &json!({"op": "set_transition_duration", "clip": adjustment, "duration": SEC / 2}),
        &sentence,
    );
    // A new clip placed onto it.
    let added = handle.value()["next_id"].as_u64().unwrap();
    handle.refuses_with(
        &json!({"op": "add_text_clip", "track": 1, "at": 3 * SEC, "duration": 2 * SEC}),
        &format!(
            "clips {adjustment} and {added} would overlap, and clip {adjustment} is an \
             adjustment clip, which cannot take a transition; fade it with opacity instead"
        ),
    );
}

#[test]
fn the_neighbourhood_filters_and_a_blend_are_errors_and_the_point_filters_land() {
    let (handle, adjustment, _) = fixture();
    for kind in ["blur", "sharpen", "pixelate"] {
        let error = handle.errors(&json!({"op": "set_video", "clips": [adjustment],
            "patch": {"filters": [{"kind": "sepia", "amount": 1.0}, {"kind": kind, "amount": 0.5}]}}));
        assert_eq!(
            error,
            format!("clip {adjustment} is an adjustment clip and cannot take the {kind} filter")
        );
    }
    let error = handle.errors(&json!({"op": "set_video", "clips": [adjustment],
        "patch": {"blend": "multiply"}}));
    assert_eq!(
        error,
        format!("clip {adjustment} is an adjustment clip and cannot take a blend mode")
    );
    let graded = handle.apply(&json!({"op": "set_video", "clips": [adjustment], "patch": {
        "opacity": 0.5,
        "color": {"brightness": 0.2, "exposure": 1.0},
        "filters": [{"kind": "sepia", "amount": 1.0}, {"kind": "noir", "amount": 0.5},
                    {"kind": "vignette", "amount": 0.5}, {"kind": "invert", "amount": 1.0}]}}));
    let drawn = layer(&graded, adjustment, SEC).expect("a layer");
    assert_eq!(drawn["opacity"], json!(0.5));
    assert_eq!(array(&drawn, "/filters").len(), 4, "{drawn}");
}

#[test]
fn paste_attributes_lands_unless_the_copied_video_has_a_refused_key() {
    let (handle, adjustment, _) = fixture();
    let shape = array(&handle.value(), "/clips")[0]["id"]
        .as_u64()
        .expect("a clip id");
    let moved = handle.apply(&json!({"op": "set_video", "clips": [shape], "patch": {
        "x": 40.0, "rotation": 10.0, "color": {"contrast": 0.3},
        "filters": [{"kind": "invert", "amount": 1.0}]}}));
    let source = by_id(&moved.value(), "/clips", shape).clone();
    let payload = json!({"clips": [source.clone()], "media": []});
    let landed = moved.apply(&json!({"op": "paste_attributes", "clips": [adjustment],
        "payload": payload, "groups": ["video"]}));
    assert_eq!(
        clip(&landed, adjustment)["video"]["color"]["contrast"],
        json!(0.3)
    );

    let mut blurred = source.clone();
    blurred["video"]["filters"] = json!([{"kind": "blur", "amount": 0.5}]);
    let error = moved.errors(&json!({"op": "paste_attributes", "clips": [adjustment],
        "payload": {"clips": [blurred], "media": []}, "groups": ["video"]}));
    assert!(
        error.contains(&format!(
            "clip {adjustment} is an adjustment clip and cannot take the blur filter"
        )),
        "{error}"
    );
    let mut blended = source;
    blended["video"]["blend"] = json!("screen");
    let error = moved.errors(&json!({"op": "paste_attributes", "clips": [adjustment],
        "payload": {"clips": [blended], "media": []}, "groups": ["video"]}));
    assert!(
        error.contains(&format!(
            "clip {adjustment} is an adjustment clip and cannot take a blend mode"
        )),
        "{error}"
    );
}

#[test]
fn an_actions_end_is_clamped_by_the_evaluator() {
    let (handle, adjustment, _) = fixture();
    let handle =
        handle.apply(&json!({"op": "add_action", "clip": adjustment, "at": 0, "duration": SEC}));
    let action = array(&clip(&handle, adjustment), "/actions")[0]["id"]
        .as_u64()
        .expect("an action id");
    let handle = handle.apply(&json!({"op": "set_action_end", "clip": adjustment,
        "action": action, "patch": {"video": {"blend": "multiply",
        "filters": [{"kind": "blur", "amount": 1.0}, {"kind": "sepia", "amount": 1.0}]}}}));
    let drawn = layer(&handle, adjustment, 2 * SEC).expect("a layer");
    assert_eq!(drawn["blend"], json!("normal"));
    assert_eq!(
        drawn["filters"],
        json!([{"kind": "sepia", "amount": 1.0}]),
        "{drawn}"
    );
}

#[test]
fn split_makes_two_adjustment_clips_dividing_the_actions() {
    let (handle, adjustment, _) = fixture();
    let handle = handle
        .apply(&json!({"op": "add_action", "clip": adjustment, "at": SEC, "duration": 2 * SEC}));
    let split = handle.apply(&json!({"op": "split", "clips": [adjustment], "at": 2 * SEC}));
    let halves: Vec<Value> = array(&split.value(), "/clips")
        .iter()
        .filter(|c| c["source"] == json!({"kind": "adjustment"}))
        .cloned()
        .collect();
    assert_eq!(halves.len(), 2);
    assert_eq!(halves[0]["duration"], json!(2 * SEC));
    assert_eq!(halves[1]["start"], json!(2 * SEC));
    assert_eq!(array(&halves[0], "/actions").len(), 1);
    assert_eq!(array(&halves[1], "/actions").len(), 1);
    // Trimmed to any length, past the five seconds a media bound would cap.
    let trimmed = split.apply(&json!({"op": "trim_end",
        "clip": halves[1]["id"], "to": 20 * SEC}));
    let second = by_id(
        &trimmed.value(),
        "/clips",
        halves[1]["id"].as_u64().unwrap(),
    )
    .clone();
    assert_eq!(second["duration"], json!(18 * SEC));
}

#[test]
fn copy_and_paste_and_duplicate_land_at_the_top_level() {
    let (handle, adjustment, _) = fixture();
    let mut copied = clip(&handle, adjustment);
    copied["track"] = json!(0);
    let pasted = handle.apply(&json!({"op": "paste", "at": 10 * SEC,
        "payload": {"clips": [copied], "media": []}}));
    let landed = last_id(&pasted, "/clips");
    assert_eq!(
        clip(&pasted, landed)["source"],
        json!({"kind": "adjustment"})
    );
    assert_eq!(clip(&pasted, landed)["start"], json!(10 * SEC));
    let duplicated = handle.apply(&json!({"op": "duplicate", "clips": [adjustment]}));
    let copy = last_id(&duplicated, "/clips");
    assert_eq!(
        clip(&duplicated, copy)["source"],
        json!({"kind": "adjustment"})
    );
}

#[test]
fn on_a_matte_track_it_draws_nothing_and_cuts_nothing() {
    let (handle, adjustment, two) = fixture();
    let matted = handle.apply(&json!({"op": "set_track", "track": two, "matte": "alpha"}));
    let without = matted.apply(&json!({"op": "delete", "clips": [adjustment]}));
    assert_eq!(matted.recipe_text(SEC), without.recipe_text(SEC));
    assert!(layer(&matted, adjustment, SEC).is_none());
}

#[test]
fn under_a_matte_it_is_drawn_into_its_target_like_any_layer() {
    let (handle, adjustment, two) = fixture();
    // The front shape's track becomes the matte, so the track directly
    // behind it, the adjustment clip's, is its target (MT-2).
    let front = last_id(&handle, "/tracks");
    assert_ne!(u64::from(front), u64::from(two));
    let matted = handle.apply(&json!({"op": "set_track", "track": front, "matte": "alpha"}));
    let drawn = layer(&matted, adjustment, SEC).expect("a layer");
    assert!(!drawn["matte"].is_null(), "{drawn}");
    assert_eq!(drawn["source"], json!({"kind": "adjustment"}));
}

#[test]
fn ungraded_neutralises_its_colour_and_keeps_its_point_filters() {
    let (handle, adjustment, _) = fixture();
    let graded = handle.apply(&json!({"op": "set_video", "clips": [adjustment], "patch": {
        "color": {"brightness": 0.2, "exposure": 1.0},
        "filters": [{"kind": "invert", "amount": 1.0}]}}));
    let recipe = graded.recipe_opts(SEC, r#"{"ungraded": true}"#);
    let drawn = array(&recipe, "/layers")
        .iter()
        .find(|l| l["clip"] == json!(adjustment))
        .cloned()
        .expect("a layer");
    let neutral = layer(&handle, adjustment, SEC).expect("a layer");
    assert_eq!(drawn["color"], neutral["color"]);
    assert_eq!(drawn["filters"], json!([{"kind": "invert", "amount": 1.0}]));
}

#[test]
fn it_round_trips_through_the_current_format() {
    let (handle, adjustment, _) = fixture();
    let text = handle.to_json();
    assert!(
        text.contains(&format!("\"version\": {RC_FORMAT_VERSION}")),
        "{text}"
    );
    assert!(text.contains("\"kind\": \"adjustment\""), "{text}");
    let back = Handle::from_json(&text);
    assert_eq!(back.value(), handle.value());
    assert_eq!(
        clip(&back, adjustment)["source"],
        json!({"kind": "adjustment"})
    );
}
