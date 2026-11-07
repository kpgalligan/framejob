//! Crop, corner radius and chroma key on a text, shape, graphic or
//! adjustment clip (spec §11 #524, #535, #536, the owner's "Refuse and
//! skip"), black box through `rc_project_apply`. Such a clip has no Crop,
//! Corner Radius or Chroma Key section, so `set_video` refuses a value the
//! patch names there (clearing allowed, a crop allowed on a matte track but
//! for an adjustment clip, K-7), `set_action_end` refuses the same keys
//! judged on the end it would store (#535), Paste Attributes leaves the
//! target's own, and `switch_layout` refuses up front a shape or graphic
//! role or reach clip the layout would crop or round.
//!
//! The fixture: media 1 a 1280 × 720 camera, media 2 a 1920 × 1080 screen;
//! tracks 3 (back) to 7 (front); screen clip 10 on track 3 over [0, 60 s) at
//! 30 fps. Each test adds the clips it needs through the ops.

mod common;

use std::collections::HashSet;

use common::{by_id, Handle, Outcome};
use serde_json::{json, Value};

const SEC: i64 = 600_000;

fn media(id: u32, w: u32, h: u32) -> Value {
    json!({"id": id, "path": format!("/m/{id}.mov"), "kind": "video", "duration": 600 * SEC,
           "width": w, "height": h, "fps": [30, 1], "has_video": true, "has_audio": false})
}

fn media_clip(id: u32, track: u32, media: u32, start: i64, duration: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "media", "media": media, "in": start}, "video": {}})
}

/// The fixture with `clips` (the screen clip 10 always among them).
fn base(clips: Vec<Value>) -> Handle {
    let mut all = vec![media_clip(10, 3, 2, 0, 60 * SEC)];
    all.extend(clips);
    Handle::from_value(&json!({
        "version": 38,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
        "media": [media(1, 1280, 720), media(2, 1920, 1080)],
        "tracks": [{"id": 3, "name": "Screen"}, {"id": 4, "name": "Camera"},
                   {"id": 5, "name": "Text"}, {"id": 6, "name": "Shape"},
                   {"id": 7, "name": "Graphic"}],
        "clips": all, "markers": [], "next_id": 100
    }))
}

fn ids(project: &Handle) -> HashSet<u64> {
    project.value()["clips"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["id"].as_u64().unwrap())
        .collect()
}

/// Applies `op`, which must add exactly one clip, and answers its id.
fn added(project: &Handle, op: Value) -> (Handle, u64) {
    let before = ids(project);
    let next = project.apply(&op);
    let new: Vec<u64> = ids(&next).difference(&before).copied().collect();
    assert_eq!(new.len(), 1, "{op}: {new:?}");
    (next, new[0])
}

fn text_on(project: &Handle, track: u32, at: i64, duration: i64) -> (Handle, u64) {
    added(
        project,
        json!({"op": "add_text_clip", "track": track, "at": at, "duration": duration}),
    )
}

fn shape_on(project: &Handle, track: u32, at: i64, duration: i64) -> (Handle, u64) {
    added(
        project,
        json!({"op": "add_shape_clip", "track": track, "at": at, "duration": duration}),
    )
}

fn graphic_on(project: &Handle, track: u32, at: i64, duration: i64) -> (Handle, u64) {
    added(
        project,
        json!({"op": "add_graphic_clip", "track": track, "at": at, "duration": duration,
               "name": "lower-third"}),
    )
}

/// The fixture with a text clip on 5, a shape on 6 and a graphic on 7, each
/// [0, 10 s), and their ids with their kinds' words.
fn three() -> (Handle, Vec<(u64, &'static str)>) {
    let project = base(vec![]);
    let (project, text) = text_on(&project, 5, 0, 10 * SEC);
    let (project, shape) = shape_on(&project, 6, 0, 10 * SEC);
    let (project, graphic) = graphic_on(&project, 7, 0, 10 * SEC);
    (
        project,
        vec![
            (text, "a text clip"),
            (shape, "a shape clip"),
            (graphic, "a graphic clip"),
        ],
    )
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

fn is_neutral_crop(crop: &Value) -> bool {
    ["l", "t", "r", "b"]
        .iter()
        .all(|k| crop[k].as_f64().unwrap_or(0.0) == 0.0)
}

// ---- set_video ---------------------------------------------------------------

#[test]
fn each_kind_refuses_each_key_in_its_own_sentence_and_changes_nothing() {
    let (project, clips) = three();
    let before = project.value();
    for (id, kind) in clips {
        let cases = [
            (json!({"crop": {"l": 100}}), "a crop off a matte track"),
            (json!({"corner_radius": 40}), "a corner radius"),
            (json!({"chroma": chroma()}), "a chroma key"),
        ];
        for (patch, what) in cases {
            assert_eq!(
                project.errors(&set_video(id, patch)),
                format!("clip {id} is {kind} and cannot take {what}")
            );
        }
    }
    assert_eq!(project.value(), before);
}

#[test]
fn clearing_each_key_is_allowed_on_each_kind() {
    let (project, clips) = three();
    for (id, _) in clips {
        let clear = json!({"crop": {"l": 0, "t": 0, "r": 0, "b": 0}, "corner_radius": 0,
                           "chroma": null});
        assert!(
            matches!(
                project.try_apply(&set_video(id, clear)),
                Ok(Outcome::Identity)
            ),
            "clearing on clip {id}"
        );
        // Another key alongside a neutral one still applies.
        let next = project.apply(&set_video(id, json!({"corner_radius": 0, "opacity": 0.5})));
        assert_eq!(video(&next, id)["opacity"], json!(0.5));
    }
}

#[test]
fn a_media_clip_still_takes_all_three() {
    let project = base(vec![media_clip(20, 4, 1, 0, 60 * SEC)]);
    let next = project.apply(&set_video(
        20,
        json!({"crop": {"l": 100}, "corner_radius": 40, "chroma": chroma()}),
    ));
    let v = video(&next, 20);
    assert_eq!(v["crop"]["l"], json!(100.0));
    assert_eq!(v["corner_radius"], json!(40.0));
    assert!(v["chroma"].is_object(), "{v}");
}

#[test]
fn on_a_matte_track_a_crop_applies_and_a_radius_is_still_refused() {
    let (project, clips) = three();
    for (track, (id, kind)) in [5u32, 6, 7].into_iter().zip(clips) {
        let matted = project.apply(&json!({"op": "set_track", "track": track, "matte": "alpha"}));
        let cropped = matted.apply(&set_video(id, json!({"crop": {"l": 100}})));
        assert_eq!(video(&cropped, id)["crop"]["l"], json!(100.0), "{kind}");
        assert_eq!(
            matted.errors(&set_video(id, json!({"corner_radius": 40}))),
            format!("clip {id} is {kind} and cannot take a corner radius")
        );
        assert_eq!(
            matted.errors(&set_video(id, json!({"chroma": chroma()}))),
            format!("clip {id} is {kind} and cannot take a chroma key")
        );
    }
}

/// A text clip given a crop through a full `paste` (which keeps what its
/// payload holds) keeps it through an edit that does not name it, and a
/// neutral crop clears it.
#[test]
fn a_held_crop_is_kept_by_another_edit_and_cleared_by_a_neutral_one() {
    let (project, clips) = three();
    let (text, _) = clips[0];
    let mut clip = by_id(&project.value(), "/clips", text).clone();
    clip["video"]["crop"] = json!({"l": 100, "t": 0, "r": 0, "b": 0});
    clip["track"] = json!(0);
    clip["start"] = json!(0);
    let payload = json!({"clips": [clip], "media": []});
    let (pasted, id) = added(
        &project,
        json!({"op": "paste", "at": 20 * SEC, "track": 5, "payload": payload}),
    );
    assert_eq!(video(&pasted, id)["crop"]["l"], json!(100.0));
    let faded = pasted.apply(&set_video(id, json!({"opacity": 0.5})));
    assert_eq!(video(&faded, id)["crop"]["l"], json!(100.0));
    assert_eq!(video(&faded, id)["opacity"], json!(0.5));
    let cleared = faded.apply(&set_video(
        id,
        json!({"crop": {"l": 0, "t": 0, "r": 0, "b": 0}}),
    ));
    assert!(is_neutral_crop(&video(&cleared, id)["crop"]));
}

// ---- paste_attributes ----------------------------------------------------------

/// A payload of one media clip showing media 1 with a crop, a radius of 30,
/// a chroma key and opacity 0.5.
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
fn paste_attributes_leaves_a_described_targets_own_pixel_keys() {
    let (project, clips) = three();
    let targets: Vec<u64> = clips.iter().map(|(id, _)| *id).collect();
    let next = project.apply(&json!({"op": "paste_attributes", "clips": targets,
                                      "payload": look()}));
    for (id, kind) in clips {
        let v = video(&next, id);
        assert!(is_neutral_crop(&v["crop"]), "{kind}: {v}");
        assert_eq!(v["corner_radius"].as_f64().unwrap_or(0.0), 0.0, "{kind}");
        assert!(v["chroma"].is_null(), "{kind}: {v}");
        assert_eq!(v["opacity"], json!(0.5), "{kind}");
    }
}

#[test]
fn paste_attributes_keeps_a_matte_track_crop_the_target_holds() {
    let (project, clips) = three();
    let (text, _) = clips[0];
    let held = project
        .apply(&json!({"op": "set_track", "track": 5, "matte": "alpha"}))
        .apply(&set_video(text, json!({"crop": {"l": 50}})));
    let next = held.apply(&json!({"op": "paste_attributes", "clips": [text],
                                   "payload": look()}));
    let v = video(&next, text);
    assert_eq!(v["crop"]["l"], json!(50.0));
    assert_eq!(v["crop"]["t"].as_f64().unwrap_or(0.0), 0.0);
    assert_eq!(v["opacity"], json!(0.5));
}

#[test]
fn paste_attributes_carries_all_three_onto_a_media_clip() {
    let project = base(vec![media_clip(20, 4, 1, 0, 60 * SEC)]);
    let next = project.apply(&json!({"op": "paste_attributes", "clips": [20],
                                      "payload": look()}));
    let v = video(&next, 20);
    assert_eq!(v["crop"]["l"], json!(120.0));
    assert_eq!(v["corner_radius"], json!(30.0));
    assert!(v["chroma"].is_object(), "{v}");
    assert_eq!(v["opacity"], json!(0.5));
}

// ---- switch_layout -------------------------------------------------------------

fn switch(args: Value) -> Value {
    let mut op = json!({"op": "switch_layout"});
    for (k, v) in args.as_object().unwrap() {
        op[k] = v.clone();
    }
    op
}

fn layout_sentence(id: u64, kind: &str) -> String {
    format!("clip {id} is {kind} and cannot take a camera layout's crop or corner radius")
}

#[test]
fn a_graphic_camera_in_a_circle_is_refused_at_its_first_frame_and_mid_clip() {
    let project = base(vec![media_clip(20, 4, 1, 0, 60 * SEC)]);
    let (project, graphic) = graphic_on(&project, 7, 0, 10 * SEC);
    let before = project.value();
    for at in [0, 2 * SEC] {
        project.refuses_with(
            &switch(json!({"camera": graphic, "layout": "corner", "shape": "circle", "at": at})),
            &layout_sentence(graphic, "a graphic clip"),
        );
    }
    assert_eq!(project.value(), before);
}

#[test]
fn a_later_graphic_in_the_cameras_reach_is_refused_and_through_ends_the_reach_before_it() {
    let project = base(vec![media_clip(20, 4, 1, 0, 4 * SEC)]);
    let (project, graphic) = graphic_on(&project, 4, 4 * SEC, 4 * SEC);
    let before = project.value();
    let corner = json!({"camera": 20, "layout": "corner", "shape": "circle", "at": 0});
    project.refuses_with(
        &switch(corner.clone()),
        &layout_sentence(graphic, "a graphic clip"),
    );
    assert_eq!(project.value(), before);
    let mut through = corner;
    through["through"] = json!(2 * SEC);
    assert!(matches!(
        project.try_apply(&switch(through)),
        Ok(Outcome::Applied(_))
    ));
}

#[test]
fn a_shape_screen_takes_corner_square_and_is_refused_side_by_side() {
    let project = Handle::from_value(&json!({
        "version": 38,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
        "media": [media(1, 1280, 720)],
        "tracks": [{"id": 3, "name": "Screen"}, {"id": 4, "name": "Camera"}],
        "clips": [media_clip(20, 4, 1, 0, 60 * SEC)], "markers": [], "next_id": 100
    }));
    let (project, shape) = shape_on(&project, 3, 0, 60 * SEC);
    assert!(matches!(
        project.try_apply(&switch(
            json!({"camera": 20, "layout": "corner", "at": 2 * SEC})
        )),
        Ok(Outcome::Applied(_))
    ));
    project.refuses_with(
        &switch(json!({"camera": 20, "layout": "side_by_side", "at": 2 * SEC})),
        &layout_sentence(shape, "a shape clip"),
    );
}

/// A shape camera on a matte track: `corner` square neither crops nor
/// rounds; `screen_only` keeps the crop it holds, which a matte track takes.
#[test]
fn a_shape_camera_on_a_matte_track_keeps_a_layouts_crop() {
    let project = base(vec![]);
    let (project, shape) = shape_on(&project, 4, 0, 60 * SEC);
    let matted = project
        .apply(&json!({"op": "set_track", "track": 4, "matte": "alpha"}))
        .apply(&set_video(shape, json!({"crop": {"l": 10}})));
    for layout in ["corner", "screen_only"] {
        assert!(
            matches!(
                matted.try_apply(&switch(json!({"camera": shape, "layout": layout,
                                                 "at": 2 * SEC}))),
                Ok(Outcome::Applied(_))
            ),
            "{layout}"
        );
    }
}

// ---- an adjustment clip (#536) ---------------------------------------------------

fn adjustment_on(project: &Handle, track: u32) -> (Handle, u64) {
    added(
        project,
        json!({"op": "add_adjustment_clip", "track": track, "at": 0, "duration": 4 * SEC}),
    )
}

#[test]
fn an_adjustment_clip_refuses_each_key_and_takes_clearing() {
    let project = base(vec![]);
    let (project, adj) = adjustment_on(&project, 7);
    let before = project.value();
    let cases = [
        (json!({"crop": {"l": 100}}), "a crop"),
        (json!({"corner_radius": 40}), "a corner radius"),
        (json!({"chroma": chroma()}), "a chroma key"),
    ];
    for (patch, what) in cases {
        assert_eq!(
            project.errors(&set_video(adj, patch)),
            format!("clip {adj} is an adjustment clip and cannot take {what}")
        );
    }
    assert_eq!(project.value(), before);
    let clear = json!({"crop": {"l": 0, "t": 0, "r": 0, "b": 0}, "corner_radius": 0,
                       "chroma": null});
    assert!(matches!(
        project.try_apply(&set_video(adj, clear)),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn an_adjustment_clip_on_a_matte_track_is_still_refused_a_crop() {
    let project = base(vec![]);
    let (project, adj) = adjustment_on(&project, 7);
    let matted = project.apply(&json!({"op": "set_track", "track": 7, "matte": "alpha"}));
    assert_eq!(
        matted.errors(&set_video(adj, json!({"crop": {"l": 100}}))),
        format!("clip {adj} is an adjustment clip and cannot take a crop")
    );
}

#[test]
fn paste_attributes_leaves_an_adjustment_targets_own_pixel_keys() {
    let project = base(vec![]);
    let (project, adj) = adjustment_on(&project, 7);
    let next = project.apply(&json!({"op": "paste_attributes", "clips": [adj],
                                      "payload": look()}));
    let v = video(&next, adj);
    assert!(is_neutral_crop(&v["crop"]), "{v}");
    assert_eq!(v["corner_radius"].as_f64().unwrap_or(0.0), 0.0);
    assert!(v["chroma"].is_null(), "{v}");
    assert_eq!(v["opacity"], json!(0.5));
}

// ---- set_action_end (#535) ------------------------------------------------------

/// Adds a one-second action at 0 to `clip` and answers its id.
fn with_action(project: &Handle, clip: u64) -> (Handle, u64) {
    let next = project.apply(&json!({"op": "add_action", "clip": clip, "at": 0,
                                      "duration": SEC}));
    let actions = by_id(&next.value(), "/clips", clip)["actions"].clone();
    let id = actions.as_array().unwrap().last().unwrap()["id"]
        .as_u64()
        .unwrap();
    (next, id)
}

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

/// The three described kinds and an adjustment clip, each with an action.
fn four_with_actions() -> (Handle, Vec<(u64, u64, &'static str)>) {
    let (project, clips) = three();
    let mut all: Vec<(u64, &'static str)> = clips;
    let (mut project, adj) = adjustment_on(&project, 4);
    all.push((adj, "an adjustment clip"));
    let mut out = vec![];
    for (clip, kind) in all {
        let (next, action) = with_action(&project, clip);
        project = next;
        out.push((clip, action, kind));
    }
    (project, out)
}

#[test]
fn an_end_refuses_each_key_on_each_kind_in_set_videos_sentence() {
    let (project, clips) = four_with_actions();
    let before = project.value();
    for (clip, action, kind) in clips {
        let crop = if kind == "an adjustment clip" {
            "a crop"
        } else {
            "a crop off a matte track"
        };
        let cases = [
            (json!({"video": {"crop": {"l": 100}}}), crop),
            (json!({"video": {"corner_radius": 40}}), "a corner radius"),
            (json!({"video": {"chroma": chroma()}}), "a chroma key"),
        ];
        for (patch, what) in cases {
            assert_eq!(
                project.errors(&end_op(clip, action, patch)),
                format!("clip {clip} is {kind} and cannot take {what}")
            );
        }
    }
    assert_eq!(project.value(), before);
}

#[test]
fn an_end_clearing_each_key_is_allowed_on_each_kind() {
    let (project, clips) = four_with_actions();
    for (clip, action, kind) in clips {
        for patch in [
            json!({"video": {"crop": {"l": 0, "t": 0, "r": 0, "b": 0}}}),
            json!({"video": {"corner_radius": 0}}),
            json!({"video": {"chroma": null}}),
            json!({"video": null}),
        ] {
            assert!(
                project
                    .try_apply(&end_op(clip, action, patch.clone()))
                    .is_ok(),
                "{kind}: {patch}"
            );
        }
        let off = json!({"op": "set_action_end", "clip": clip, "action": action,
                         "patch": {}, "off": ["video.chroma"]});
        assert!(project.try_apply(&off).is_ok(), "{kind}: off");
    }
}

#[test]
fn an_end_crop_applies_on_a_matte_tracks_text_clip_and_its_radius_is_refused() {
    let (project, clips) = three();
    let (text, _) = clips[0];
    let matted = project.apply(&json!({"op": "set_track", "track": 5, "matte": "alpha"}));
    let (matted, action) = with_action(&matted, text);
    let cropped = matted.apply(&end_op(
        text,
        action,
        json!({"video": {"crop": {"l": 100}}}),
    ));
    assert_eq!(
        end(&cropped, text, action)["video"]["crop"]["l"],
        json!(100)
    );
    assert_eq!(
        matted.errors(&end_op(
            text,
            action,
            json!({"video": {"corner_radius": 40}})
        )),
        format!("clip {text} is a text clip and cannot take a corner radius")
    );
}

#[test]
fn a_media_clips_end_takes_all_three() {
    let project = base(vec![media_clip(20, 4, 1, 0, 60 * SEC)]);
    let (project, action) = with_action(&project, 20);
    let next = project.apply(&end_op(
        20,
        action,
        json!({"video": {"crop": {"l": 100}, "corner_radius": 40, "chroma": chroma()}}),
    ));
    let e = end(&next, 20, action);
    assert_eq!(e["video"]["crop"]["l"], json!(100));
    assert_eq!(e["video"]["corner_radius"], json!(40));
    assert!(e["video"]["chroma"].is_object(), "{e}");
}

/// An end holding a crop from a file is kept by an end edit that does not
/// name it.
#[test]
fn an_end_already_holding_a_crop_is_kept_by_an_end_opacity_edit() {
    let (project, clips) = three();
    let (text, _) = clips[0];
    let (project, action) = with_action(&project, text);
    let mut value = project.value();
    let clip = value["clips"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .find(|c| c["id"].as_u64() == Some(text))
        .unwrap();
    clip["actions"][0]["end"] = json!({"video": {"crop": {"l": 100}}});
    let held = Handle::from_value(&value);
    let next = held.apply(&end_op(text, action, json!({"video": {"opacity": 0.5}})));
    let e = end(&next, text, action);
    assert_eq!(e["video"]["crop"]["l"], json!(100));
    assert_eq!(e["video"]["opacity"], json!(0.5));
}
