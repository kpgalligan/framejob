//! A nest clip takes a crop but no corner radius or chroma key (spec §11
//! #536's nest half and #535's, the owner's round-3 answer, 2026-11-07),
//! black box through `rc_project_apply`. A crop draws on a nest; a radius
//! and a chroma key do not, and a nest has no section for either. So
//! `set_video` and `set_action_end` refuse the two there (clearing allowed,
//! the crop taken), Paste Attributes leaves a nest target's own two, a
//! camera layout writes a nest role's radius as 0 (amending CO-60), and
//! `reframe_clip {follow: layout}` does not compare a nest role's radius,
//! so a switch written before (the panel radius) and after (0) are both
//! recognised (amending VR-53 (b)).
//!
//! The fixture is `layout.rs`'s: media 1 a 1280 × 720 camera, media 2 a
//! 1920 × 1080 screen; track 3 "Screen" behind track 4 "Camera"; screen
//! clip 10 and camera clip 20 over [0, 30 s); 30 fps. A nest is made with
//! the `nest` op, so it is the canvas's size.

mod common;

use std::collections::HashSet;

use common::{by_id, Handle, Outcome};
use serde_json::{json, Value};

const SEC: i64 = 600_000;

fn media(id: u32, w: u32, h: u32) -> Value {
    json!({"id": id, "path": format!("/m/{id}.mov"), "kind": "video", "duration": 600 * SEC,
           "width": w, "height": h, "fps": [30, 1], "has_video": true, "has_audio": false})
}

fn clip(id: u32, track: u32, media: u32, start: i64, duration: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "media", "media": media, "in": start}, "video": {}})
}

fn fixture(canvas: (u32, u32), clips: Vec<Value>) -> Value {
    json!({
        "version": 38,
        "canvas": {"width": canvas.0, "height": canvas.1, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
        "media": [media(1, 1280, 720), media(2, 1920, 1080)],
        "tracks": [{"id": 3, "name": "Screen"}, {"id": 4, "name": "Camera"}],
        "clips": clips, "markers": [], "next_id": 100
    })
}

/// Screen clip 10 and camera clip 20, both [0, 30 s).
fn two() -> Handle {
    Handle::from_value(&fixture(
        (1920, 1080),
        vec![clip(10, 3, 2, 0, 30 * SEC), clip(20, 4, 1, 0, 30 * SEC)],
    ))
}

fn ids(project: &Handle) -> HashSet<u64> {
    project.value()["clips"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["id"].as_u64().unwrap())
        .collect()
}

/// `clip` nested alone: the project and the new nest clip's id.
fn nested(project: &Handle, clip: u64) -> (Handle, u64) {
    let before = ids(project);
    let next = project.apply(&json!({"op": "nest", "clips": [clip]}));
    let new: Vec<u64> = ids(&next).difference(&before).copied().collect();
    assert_eq!(new.len(), 1, "{new:?}");
    let id = new[0];
    assert_eq!(by_id(&next.value(), "/clips", id)["source"]["kind"], "nest");
    (next, id)
}

/// The fixture with both clips nested: (project, screen nest, camera nest).
fn two_nests() -> (Handle, u64, u64) {
    let (project, screen) = nested(&two(), 10);
    let (project, camera) = nested(&project, 20);
    (project, screen, camera)
}

fn chroma() -> Value {
    json!({"key": [0, 1, 0], "tolerance": 0.3, "softness": 0.1, "spill": 0.5})
}

fn set_video(clip: u64, patch: Value) -> Value {
    json!({"op": "set_video", "clips": [clip], "patch": patch})
}

fn video(project: &Handle, clip: u64) -> Value {
    by_id(&project.value(), "/clips", clip)["video"].clone()
}

fn radius(video: &Value) -> f64 {
    video["corner_radius"].as_f64().unwrap_or(0.0)
}

fn crop_sum(video: &Value) -> f64 {
    ["l", "t", "r", "b"]
        .iter()
        .map(|k| video["crop"][k].as_f64().unwrap_or(0.0))
        .sum()
}

fn radius_sentence(id: u64) -> String {
    format!("clip {id} is a nest clip and cannot take a corner radius")
}

fn chroma_sentence(id: u64) -> String {
    format!("clip {id} is a nest clip and cannot take a chroma key")
}

/// `project` with `clip`'s video given `radius` and `chroma` in the FILE,
/// as a project saved before #536 holds them.
fn held(project: &Handle, clip: u64, radius: f64, chroma: Value) -> Handle {
    let mut value = project.value();
    let at = value["clips"]
        .as_array()
        .unwrap()
        .iter()
        .position(|c| c["id"].as_u64() == Some(clip))
        .unwrap();
    value["clips"][at]["video"]["corner_radius"] = json!(radius);
    value["clips"][at]["video"]["chroma"] = chroma;
    Handle::from_value(&value)
}

// ---- set_video -------------------------------------------------------------------

#[test]
fn set_video_on_a_nest_refuses_a_radius_and_a_chroma_key_and_takes_a_crop() {
    let (project, _, nest) = two_nests();
    let before = project.value();
    assert_eq!(
        project.errors(&set_video(nest, json!({"corner_radius": 40}))),
        radius_sentence(nest)
    );
    assert_eq!(
        project.errors(&set_video(nest, json!({"chroma": chroma()}))),
        chroma_sentence(nest)
    );
    assert_eq!(project.value(), before);
    let cropped = project.apply(&set_video(nest, json!({"crop": {"l": 100}})));
    assert_eq!(video(&cropped, nest)["crop"]["l"], json!(100.0));
    let clear = json!({"corner_radius": 0, "chroma": null});
    assert!(matches!(
        project.try_apply(&set_video(nest, clear)),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn a_radius_and_chroma_key_held_in_a_file_are_kept_and_can_be_cleared() {
    let (project, _, nest) = two_nests();
    let project = held(&project, nest, 12.0, chroma());
    let faded = project.apply(&set_video(nest, json!({"opacity": 0.5})));
    let v = video(&faded, nest);
    assert_eq!(radius(&v), 12.0);
    assert!(v["chroma"].is_object(), "{v}");
    assert_eq!(v["opacity"], json!(0.5));
    let cleared = faded.apply(&set_video(
        nest,
        json!({"corner_radius": 0, "chroma": null}),
    ));
    let v = video(&cleared, nest);
    assert_eq!(radius(&v), 0.0);
    assert!(v["chroma"].is_null(), "{v}");
}

#[test]
fn a_nest_on_a_matte_track_is_refused_a_radius_and_takes_a_crop() {
    let (project, _, nest) = two_nests();
    let track = by_id(&project.value(), "/clips", nest)["track"].clone();
    let matted = project.apply(&json!({"op": "set_track", "track": track, "matte": "alpha"}));
    assert_eq!(
        matted.errors(&set_video(nest, json!({"corner_radius": 40}))),
        radius_sentence(nest)
    );
    let cropped = matted.apply(&set_video(nest, json!({"crop": {"l": 100}})));
    assert_eq!(video(&cropped, nest)["crop"]["l"], json!(100.0));
}

// ---- set_action_end (#535) --------------------------------------------------------

fn end_op(clip: u64, action: u64, patch: Value) -> Value {
    json!({"op": "set_action_end", "clip": clip, "action": action, "patch": patch})
}

fn end(project: &Handle, clip: u64, action: u64) -> Value {
    by_id(&project.value(), "/clips", clip)["actions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["id"].as_u64() == Some(action))
        .unwrap()["end"]
        .clone()
}

/// The camera nest with a one-second action at 0.
fn nest_with_action() -> (Handle, u64, u64) {
    let (project, _, nest) = two_nests();
    let next = project.apply(&json!({"op": "add_action", "clip": nest, "at": 0,
                                      "duration": SEC}));
    let actions = by_id(&next.value(), "/clips", nest)["actions"].clone();
    let action = actions.as_array().unwrap().last().unwrap()["id"]
        .as_u64()
        .unwrap();
    (next, nest, action)
}

#[test]
fn an_end_on_a_nest_refuses_a_radius_and_a_chroma_key() {
    let (project, nest, action) = nest_with_action();
    let before = project.value();
    assert_eq!(
        project.errors(&end_op(
            nest,
            action,
            json!({"video": {"corner_radius": 40}})
        )),
        radius_sentence(nest)
    );
    assert_eq!(
        project.errors(&end_op(
            nest,
            action,
            json!({"video": {"chroma": chroma()}})
        )),
        chroma_sentence(nest)
    );
    assert_eq!(project.value(), before);
}

#[test]
fn an_end_on_a_nest_takes_a_crop_and_clearing() {
    let (project, nest, action) = nest_with_action();
    let cropped = project.apply(&end_op(
        nest,
        action,
        json!({"video": {"crop": {"l": 100}}}),
    ));
    assert_eq!(
        end(&cropped, nest, action)["video"]["crop"]["l"].as_f64(),
        Some(100.0)
    );
    let removed = cropped.apply(&end_op(nest, action, json!({"video": {"crop": null}})));
    assert!(end(&removed, nest, action)["video"].get("crop").is_none());
    for patch in [
        json!({"video": {"corner_radius": 0}}),
        json!({"video": {"chroma": null}}),
        json!({"video": null}),
    ] {
        assert!(
            project
                .try_apply(&end_op(nest, action, patch.clone()))
                .is_ok(),
            "{patch}"
        );
    }
    let off = json!({"op": "set_action_end", "clip": nest, "action": action,
                     "patch": {}, "off": ["video.chroma"]});
    assert!(project.try_apply(&off).is_ok());
}

// ---- paste_attributes ----------------------------------------------------------------

/// A payload of one media clip with a crop, a radius of 30, a chroma key and
/// opacity 0.5.
fn look() -> Value {
    json!({
        "clips": [{"id": 3, "track": 0, "start": 0, "duration": SEC, "speed": 1.0,
                   "source": {"kind": "media", "media": 1, "in": 0},
                   "enabled": {"video": true, "audio": false},
                   "video": {"crop": {"l": 120, "t": 10, "r": 0, "b": 0}, "corner_radius": 30,
                             "chroma": chroma(), "opacity": 0.5}}],
        "media": [media(1, 1280, 720)]
    })
}

#[test]
fn paste_attributes_gives_a_nest_the_crop_and_leaves_its_own_radius_and_chroma_key() {
    let (project, _, nest) = two_nests();
    let own = json!({"key": [1, 0, 0], "tolerance": 0.2, "softness": 0.1, "spill": 0.5});
    let project = held(&project, nest, 12.0, own.clone());
    let own = video(&project, nest)["chroma"].clone();
    let next = project.apply(&json!({"op": "paste_attributes", "clips": [nest],
                                      "payload": look()}));
    let v = video(&next, nest);
    assert_eq!(v["crop"]["l"], json!(120.0));
    assert_eq!(v["crop"]["t"], json!(10.0));
    assert_eq!(v["opacity"], json!(0.5));
    assert_eq!(radius(&v), 12.0);
    assert_eq!(v["chroma"], own);
}

// ---- switch_layout -------------------------------------------------------------------

fn switch(camera: u64, layout: &str, at: i64) -> Value {
    json!({"op": "switch_layout", "camera": camera, "layout": layout, "at": at})
}

/// Every layout action's end on `clip` (one naming all six keys).
fn layout_ends(project: &Handle, clip: u64) -> Vec<Value> {
    by_id(&project.value(), "/clips", clip)["actions"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|a| a["end"]["video"].get("opacity").is_some())
        .map(|a| a["end"]["video"].clone())
        .collect()
}

#[test]
fn side_by_side_and_stacked_write_a_nest_roles_radius_as_zero() {
    let (project, screen, camera) = two_nests();
    for layout in ["side_by_side", "stacked"] {
        let next = project.apply(&switch(camera, layout, SEC));
        for (role, id) in [("screen", screen), ("camera", camera)] {
            let ends = layout_ends(&next, id);
            assert_eq!(ends.len(), 1, "{layout} {role}");
            assert_eq!(radius(&ends[0]), 0.0, "{layout} {role}: {}", ends[0]);
        }
        // The layout did run: the camera is cropped to its panel.
        assert!(crop_sum(&layout_ends(&next, camera)[0]) > 1.0, "{layout}");
    }
}

#[test]
fn a_first_frame_switch_writes_zero_into_a_nests_base_and_its_cut() {
    let (project, screen, camera) = two_nests();
    for layout in ["side_by_side", "stacked"] {
        let next = project.apply(&switch(camera, layout, 0));
        for id in [screen, camera] {
            assert_eq!(radius(&video(&next, id)), 0.0, "{layout} base of {id}");
            for e in layout_ends(&next, id) {
                assert_eq!(radius(&e), 0.0, "{layout} cut of {id}: {e}");
            }
        }
        assert!(crop_sum(&video(&next, camera)) > 1.0, "{layout}");
    }
}

#[test]
fn nest_true_writes_zero_on_the_nest_it_makes() {
    let mut value = fixture(
        (1920, 1080),
        vec![clip(10, 3, 2, 0, 30 * SEC), clip(20, 4, 1, 0, 30 * SEC)],
    );
    value["clips"][1]["actions"] = json!([{"id": 60, "start": 10 * SEC, "duration": SEC,
                                           "end": {"video": {"scale": 2, "x": 0, "y": 0}}}]);
    let project = Handle::from_value(&value);
    for layout in ["side_by_side", "stacked"] {
        let before = ids(&project);
        let mut op = switch(20, layout, 2 * SEC);
        op["nest"] = json!(true);
        let next = project.apply(&op);
        let new: Vec<u64> = ids(&next).difference(&before).copied().collect();
        assert_eq!(new.len(), 1, "{layout}: {new:?}");
        let ends = layout_ends(&next, new[0]);
        assert_eq!(ends.len(), 1, "{layout}");
        assert_eq!(radius(&ends[0]), 0.0, "{layout}: {}", ends[0]);
    }
}

#[test]
fn a_media_camera_beside_a_nest_screen_keeps_its_panel_radius() {
    let (project, screen) = nested(&two(), 10);
    let next = project.apply(&switch(20, "side_by_side", SEC));
    assert!(radius(&layout_ends(&next, 20)[0]) > 1.0);
    assert_eq!(radius(&layout_ends(&next, screen)[0]), 0.0);
}

// ---- reframe_clip {follow: layout} ---------------------------------------------------

fn relay(clip: u64) -> Value {
    json!({"op": "reframe_clip", "clip": clip, "follow": "layout",
           "from_width": 1920, "from_height": 1080})
}

fn vertical() -> Value {
    json!({"op": "set_canvas", "width": 1080, "height": 1920, "rescale_clips": false})
}

/// Side by Side at 1 s on the two nests.
fn laid_nests() -> (Handle, u64, u64) {
    let (project, screen, camera) = two_nests();
    (
        project.apply(&switch(camera, "side_by_side", SEC)),
        screen,
        camera,
    )
}

fn replayed_with_zero(project: &Handle, screen: u64, camera: u64) {
    let tall = project.apply(&vertical());
    let next = tall.apply(&relay(camera));
    for id in [screen, camera] {
        let ends = layout_ends(&next, id);
        assert_eq!(ends.len(), 1, "clip {id}");
        assert_eq!(radius(&ends[0]), 0.0, "clip {id}: {}", ends[0]);
    }
    // Replayed as Stacked on the tall canvas: the camera sits below the screen.
    let camera_end = &layout_ends(&next, camera)[0];
    let screen_end = &layout_ends(&next, screen)[0];
    assert!(
        camera_end["y"].as_f64().unwrap() > screen_end["y"].as_f64().unwrap(),
        "{camera_end} {screen_end}"
    );
}

#[test]
fn a_nest_layout_written_with_radius_zero_is_recognised_and_replayed_with_zero() {
    let (project, screen, camera) = laid_nests();
    replayed_with_zero(&project, screen, camera);
}

#[test]
fn a_nest_layout_holding_the_old_panel_radius_is_recognised_and_replayed_with_zero() {
    let (project, screen, camera) = laid_nests();
    // The panel radius a switch wrote before #536: 2 % of the shorter side
    // in canvas pixels, in source pixels ÷ the end's scale.
    let mut value = project.value();
    for id in [screen, camera] {
        let at = value["clips"]
            .as_array()
            .unwrap()
            .iter()
            .position(|c| c["id"].as_u64() == Some(id))
            .unwrap();
        for action in value["clips"][at]["actions"].as_array_mut().unwrap() {
            let scale = action["end"]["video"]["scale"].as_f64().unwrap();
            action["end"]["video"]["corner_radius"] = json!(0.02 * 1080.0 / scale);
        }
    }
    let old = Handle::from_value(&value);
    for id in [screen, camera] {
        assert!(radius(&layout_ends(&old, id)[0]) > 10.0);
    }
    replayed_with_zero(&old, screen, camera);
}

#[test]
fn a_media_cameras_radius_moved_by_hand_is_still_not_recognised() {
    let project = two().apply(&switch(20, "side_by_side", SEC));
    let p = project.value();
    let action = by_id(&p, "/clips", 20)["actions"][0].clone();
    let mut v = action["end"]["video"].clone();
    v["corner_radius"] = json!(v["corner_radius"].as_f64().unwrap() + 5.0);
    let moved = project.apply(&end_op(
        20,
        action["id"].as_u64().unwrap(),
        json!({"video": v}),
    ));
    moved.apply(&vertical()).refuses_with(
        &relay(20),
        &format!(
            "clip 20's layout action {} at 00:00:01:00 is not a camera layout Frame Job made on \
             the 1920 × 1080 canvas, so it cannot be re-laid; keep its clips as placed",
            action["id"]
        ),
    );
}
