//! A recipe layer's `nest` key (spec §7.3): the outermost nest clip around a
//! layer in the view asked, and where that clip is. A nest clip never draws
//! itself, so this is all the canvas has to draw and hit its box from
//! (`CanvasLayerBox.boxes(recipe:snapshot:)`, #476).
//!
//! The placement is the one `frame_of` ENTERS the nest clip with, so a
//! `video.motion` is in it. `clip_state` reads the clip un-moved, which is
//! why the last test holds the key to the nested layer's `clip_rect` and
//! apart from `clip_state`.

mod common;

use serde_json::{json, Value};

use common::{array, at, int, num, Handle};

/// Ticks per second (spec §5.1).
const SEC: i64 = 600_000;

/// Slack for a slide's curve.
const EPS: f64 = 1e-9;

fn video_media(id: u32) -> Value {
    json!({
        "id": id, "path": format!("/fixtures/{id}.mov"), "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

fn track(id: u32) -> Value {
    json!({ "id": id, "name": format!("Track {id}") })
}

fn media_clip(id: u32, on: u32, duration: i64, media: u32) -> Value {
    json!({
        "id": id, "track": on, "start": 0, "duration": duration,
        "source": { "kind": "media", "media": media, "in": 0 },
        "video": {}, "audio": {}
    })
}

fn nest_clip(id: u32, on: u32, duration: i64, shows: u32) -> Value {
    json!({
        "id": id, "track": on, "start": 0, "duration": duration,
        "source": { "kind": "nest", "project": shows }, "video": {}
    })
}

fn nest(id: u32, tracks: Vec<Value>, clips: Vec<Value>) -> Value {
    json!({
        "id": id, "name": format!("Nest {id}"), "width": 1920, "height": 1080,
        "tracks": tracks, "clips": clips
    })
}

fn project(clips: Vec<Value>, nests: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 2,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0],
                    "fit_new_clips": true, "timecode_frames": true },
        "media": [video_media(1)], "tracks": [track(2), track(10)], "clips": clips,
        "markers": [], "next_id": 20, "nests": nests
    }))
}

fn layer_of(recipe: &Value, clip: i64) -> Value {
    array(recipe, "/layers")
        .iter()
        .find(|layer| int(layer, "/clip") == clip)
        .cloned()
        .unwrap_or_else(|| panic!("no layer for clip {clip}"))
}

/// Timeline nest clip 3 over nest 4, whose track 5 holds clip 6 over nest 7,
/// whose track 8 holds media clip 9.
fn two_deep(outer: Value) -> Handle {
    let mut clip = nest_clip(3, 2, 2 * SEC, 4);
    clip["video"] = outer;
    let mut middle = nest_clip(6, 5, 2 * SEC, 7);
    middle["video"] = json!({"x": 40.0, "scale": 0.5});
    project(
        vec![clip],
        vec![
            nest(4, vec![track(5)], vec![middle]),
            nest(7, vec![track(8)], vec![media_clip(9, 8, 2 * SEC, 1)]),
        ],
    )
}

#[test]
fn a_nested_layer_names_its_nest_clip_and_where_that_clip_is() {
    let mut outer = nest_clip(3, 2, 2 * SEC, 4);
    outer["video"] = json!({
        "x": 100.0, "y": 50.0, "scale": 0.5, "rotation": 90.0,
        "crop": {"l": 10.0, "t": 20.0, "r": 30.0, "b": 40.0}
    });
    let mut inner = media_clip(6, 5, 2 * SEC, 1);
    inner["video"] = json!({"x": 200.0, "scale": 2.0});
    let handle = project(vec![outer], vec![nest(4, vec![track(5)], vec![inner])]);

    let nest = at(&layer_of(&handle.recipe(SEC), 6), "/nest").clone();
    assert_eq!(int(&nest, "/clip"), 3);
    assert_eq!(num(&nest, "/x"), 100.0);
    assert_eq!(num(&nest, "/y"), 50.0);
    assert_eq!(num(&nest, "/scale"), 0.5);
    assert_eq!(num(&nest, "/rotation"), 90.0);
    assert_eq!(
        at(&nest, "/crop"),
        &json!({"l": 10.0, "t": 20.0, "r": 30.0, "b": 40.0})
    );
}

#[test]
fn a_doubly_nested_layer_names_the_outermost_nest_clip() {
    let handle = two_deep(json!({"x": 200.0, "scale": 0.75}));
    let nest = at(&layer_of(&handle.recipe(SEC), 9), "/nest").clone();
    assert_eq!(
        int(&nest, "/clip"),
        3,
        "the clip the timeline shows, not clip 6"
    );
    assert_eq!(num(&nest, "/x"), 200.0);
    assert_eq!(num(&nest, "/scale"), 0.75);
}

#[test]
fn a_timeline_clip_and_the_burn_in_have_none() {
    let handle = project(vec![media_clip(3, 2, 2 * SEC, 1)], vec![]);
    assert_eq!(at(&layer_of(&handle.recipe(SEC), 3), "/nest"), &Value::Null);

    let burnt = handle.recipe_opts(SEC, &json!({"burn_in_timecode": true}).to_string());
    let last = array(&burnt, "/layers")
        .last()
        .expect("the burn-in")
        .clone();
    assert_eq!(at(&last, "/nest"), &Value::Null);
}

#[test]
fn a_scoped_view_names_its_own_direct_child() {
    // Inside nest 4 the view's own clip is 6: clip 3 is not in this view,
    // and a box for it could never be found in the view's snapshot.
    let handle = two_deep(json!({"x": 200.0, "scale": 0.75}));
    let inside = handle.scoped(4);
    let nest = at(&layer_of(&inside.recipe(SEC), 9), "/nest").clone();
    assert_eq!(int(&nest, "/clip"), 6);
    assert_eq!(num(&nest, "/x"), 40.0);
    assert_eq!(num(&nest, "/scale"), 0.5);
}

#[test]
fn an_action_on_the_nest_clip_is_in_the_key() {
    let mut outer = nest_clip(3, 2, 2 * SEC, 4);
    outer["actions"] = json!([{
        "id": 15, "start": 0, "duration": SEC, "curve": "linear",
        "end": {"video": {"x": 300.0}}
    }]);
    let inner = media_clip(6, 5, 2 * SEC, 1);
    let handle = project(vec![outer], vec![nest(4, vec![track(5)], vec![inner])]);

    let at_end = at(&layer_of(&handle.recipe(SEC), 6), "/nest").clone();
    assert_eq!(num(&at_end, "/x"), 300.0);
    let midway = at(&layer_of(&handle.recipe(SEC / 2), 6), "/nest").clone();
    assert!((num(&midway, "/x") - 150.0).abs() < EPS);
}

#[test]
fn a_nest_clips_motion_is_in_the_key_where_clip_state_has_none() {
    let mut outer = nest_clip(3, 2, 2 * SEC, 4);
    outer["video"] = json!({
        "x": 100.0, "scale": 0.5,
        "motion": { "in": { "kind": "slide_left", "duration": SEC } }
    });
    let inner = media_clip(6, 5, 2 * SEC, 1);
    let handle = project(vec![outer], vec![nest(4, vec![track(5)], vec![inner])]);

    let t = SEC / 4;
    let layer = layer_of(&handle.recipe(t), 6);
    let nest = at(&layer, "/nest").clone();
    let rest = handle.clip_state(3, t).expect("clip 3 has a state");
    let rest_x = num(&rest, "/video/x");
    assert_eq!(rest_x, 100.0, "clip_state reads the clip un-moved");
    assert!(
        (num(&nest, "/x") - rest_x).abs() > 1.0,
        "a slide part-way in is displaced: key {}, rest {rest_x}",
        num(&nest, "/x")
    );
    // The clip rect is the nest's canvas where the nest clip put it, its
    // centre measured from the canvas's top-left corner.
    let rect = at(&layer, "/clip_rect").clone();
    assert!((num(&rect, "/x") - (960.0 + num(&nest, "/x"))).abs() < EPS);
    assert!((num(&rect, "/y") - (540.0 + num(&nest, "/y"))).abs() < EPS);
    assert!((num(&rect, "/w") - 1920.0 * num(&nest, "/scale")).abs() < EPS);

    // Past the slide it is back at rest.
    let settled = at(&layer_of(&handle.recipe(SEC + SEC / 2), 6), "/nest").clone();
    assert_eq!(num(&settled, "/x"), 100.0);
}
