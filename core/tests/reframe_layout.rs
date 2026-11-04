//! `reframe_clip {follow: "layout"}` (road map "creator-jobs" VR5b, spec §11
//! VR-53), black box through `rc_project_apply`. The oracle for every replay
//! is the project a person would make by switching the same layouts directly
//! on the new canvas with `switch_layout` — never a number read back from
//! `layout.rs` — so a re-laid version is the direct one, role by role.
//!
//! The fixture is `layout.rs`'s: media 1 a 1280 × 720 camera, media 2 a
//! 1920 × 1080 screen, media 9 another 1920 × 1080 file; track 3 "Screen"
//! behind track 4 "Camera"; 30 fps (a frame is 20 000 ticks). Every focus
//! is the default (the source centre), inside every layout's crop room.

mod common;

use common::{by_id, Handle};
use serde_json::{json, Value};

const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;

fn media(id: u32, w: u32, h: u32) -> Value {
    json!({"id": id, "path": format!("/m/{id}.mov"), "kind": "video", "duration": 600 * SEC,
           "width": w, "height": h, "fps": [30, 1], "has_video": true, "has_audio": false})
}

fn clip(id: u32, track: u32, media: u32, start: i64, duration: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "media", "media": media, "in": start}, "video": {}})
}

fn project(canvas: (u32, u32), clips: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 38,
        "canvas": {"width": canvas.0, "height": canvas.1, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
        "media": [media(1, 1280, 720), media(2, 1920, 1080), media(9, 1920, 1080)],
        "tracks": [{"id": 3, "name": "Screen"}, {"id": 4, "name": "Camera"},
                   {"id": 5, "name": "Top"}],
        "clips": clips, "markers": [], "next_id": 100
    }))
}

/// Screen clip 10 and camera clip 20, both [0, 30 s).
fn two(canvas: (u32, u32)) -> Handle {
    project(
        canvas,
        vec![clip(10, 3, 2, 0, 30 * SEC), clip(20, 4, 1, 0, 30 * SEC)],
    )
}

fn switch(camera: u64, layout: &str, at: i64) -> Value {
    json!({"op": "switch_layout", "camera": camera, "layout": layout, "at": at})
}

fn switch_for(camera: u64, layout: &str, at: i64, duration: i64, curve: &str) -> Value {
    json!({"op": "switch_layout", "camera": camera, "layout": layout, "at": at,
           "duration": duration, "curve": curve})
}

fn relay(clip: u64) -> Value {
    json!({"op": "reframe_clip", "clip": clip, "follow": "layout",
           "from_width": 1920, "from_height": 1080})
}

fn vertical(canvas: (u32, u32)) -> Value {
    json!({"op": "set_canvas", "width": canvas.0, "height": canvas.1, "rescale_clips": false})
}

/// The three switches: Corner at 0, `middle` at 10 s for 1 s linear, Camera
/// Full at 20 s.
fn three(h: &Handle, middle: &str) -> Handle {
    h.apply_all(&[
        switch(20, "corner", 0),
        switch_for(20, middle, 10 * SEC, SEC, "linear"),
        switch(20, "camera_full", 20 * SEC),
    ])
}

/// The nine numbers of a placement, in a fixed order.
fn nine(video: &Value) -> [f64; 9] {
    let n = |k: &str| {
        video[k]
            .as_f64()
            .unwrap_or_else(|| panic!("{k} in {video}"))
    };
    let c = &video["crop"];
    let crop = |k: &str| c[k].as_f64().unwrap_or(0.0);
    [
        n("x"),
        n("y"),
        n("scale"),
        crop("l"),
        crop("t"),
        crop("r"),
        crop("b"),
        video["corner_radius"].as_f64().unwrap_or(0.0),
        video["opacity"].as_f64().unwrap_or(1.0),
    ]
}

fn near(a: &[f64; 9], b: &[f64; 9]) -> bool {
    a.iter().zip(b).all(|(x, y)| (x - y).abs() <= 1e-9)
}

/// An action's start, duration, curve and end `video`.
type Timed = (i64, i64, String, Value);

/// A clip's base nine numbers and each action's start, duration, curve and
/// end, in start order.
fn shape(p: &Value, id: u64) -> ([f64; 9], Vec<Timed>) {
    let c = by_id(p, "/clips", id);
    let mut actions: Vec<Timed> = c["actions"]
        .as_array()
        .cloned()
        .unwrap_or_default()
        .iter()
        .map(|a| {
            (
                a["start"].as_i64().unwrap(),
                a["duration"].as_i64().unwrap(),
                a["curve"].as_str().unwrap_or("linear").to_string(),
                a["end"]["video"].clone(),
            )
        })
        .collect();
    actions.sort_by_key(|a| a.0);
    (nine(&with_defaults(&c["video"])), actions)
}

/// A base `video` with the six keys' defaults where absent.
fn with_defaults(video: &Value) -> Value {
    let mut v = json!({"x": 0.0, "y": 0.0, "scale": 1.0, "crop": {"l": 0, "t": 0, "r": 0, "b": 0},
                       "corner_radius": 0.0, "opacity": 1.0});
    if let Some(map) = video.as_object() {
        for (k, val) in map {
            v[k] = val.clone();
        }
    }
    v
}

fn same_clip(got: &Value, want: &Value, id: u64, what: &str) {
    let (gb, ga) = shape(got, id);
    let (wb, wa) = shape(want, id);
    assert!(
        near(&gb, &wb),
        "{what}: clip {id}'s base {gb:?}, want {wb:?}"
    );
    assert_eq!(
        ga.len(),
        wa.len(),
        "{what}: clip {id}'s actions {ga:?}, want {wa:?}"
    );
    for (g, w) in ga.iter().zip(&wa) {
        assert_eq!(
            (g.0, g.1, &g.2),
            (w.0, w.1, &w.2),
            "{what}: clip {id}'s action timing"
        );
        assert!(
            near(&nine(&g.3), &nine(&w.3)),
            "{what}: clip {id}'s end at {}: {} want {}",
            g.0,
            g.3,
            w.3
        );
    }
}

/// The clips on `track`, by start.
fn on_track(p: &Value, track: u64) -> Vec<u64> {
    let mut found: Vec<(i64, u64)> = p["clips"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|c| c["track"] == track)
        .map(|c| (c["start"].as_i64().unwrap(), c["id"].as_u64().unwrap()))
        .collect();
    found.sort();
    found.into_iter().map(|(_, id)| id).collect()
}

/// Every clip of `got` equal to `want`'s at the same place on each track.
fn same_tracks(got: &Value, want: &Value, what: &str) {
    for track in [3u64, 4, 5] {
        let (g, w) = (on_track(got, track), on_track(want, track));
        assert_eq!(g.len(), w.len(), "{what}: track {track}'s clips");
        for (gi, wi) in g.iter().zip(&w) {
            let (gc, wc) = (by_id(got, "/clips", *gi), by_id(want, "/clips", *wi));
            assert_eq!(gc["start"], wc["start"], "{what}: track {track}");
            assert_eq!(gc["source"], wc["source"], "{what}: track {track}");
            // Same ids on both sides: compare through a renamed copy.
            let mut renamed = want.clone();
            for c in renamed["clips"].as_array_mut().unwrap() {
                if c["id"] == *wi {
                    c["id"] = json!(*gi);
                } else if c["id"] == *gi {
                    c["id"] = json!(u32::MAX);
                }
            }
            same_clip(got, &renamed, *gi, what);
        }
    }
}

// ---- the replay --------------------------------------------------------------

#[test]
fn three_switches_replayed_on_each_canvas_equal_the_direct_switches() {
    let old = three(&two((1920, 1080)), "side_by_side");
    for (canvas, middle) in [
        ((1080, 1920), "stacked"),
        ((1080, 1350), "stacked"),
        ((1080, 1080), "side_by_side"),
    ] {
        let got = old.apply(&vertical(canvas)).apply(&relay(20)).value();
        let want = three(&two(canvas), middle).value();
        for id in [10, 20] {
            same_clip(&got, &want, id, &format!("{canvas:?}"));
        }
    }
}

#[test]
fn the_screen_or_the_camera_may_be_named_and_gives_the_same_replay() {
    let old = three(&two((1920, 1080)), "side_by_side").apply(&vertical((1080, 1920)));
    assert_eq!(old.apply(&relay(20)).value(), old.apply(&relay(10)).value());
}

#[test]
fn a_zoom_on_a_corner_screen_keeps_its_point_in_the_picture() {
    let laid = two((1920, 1080)).apply(&switch(20, "corner", 0));
    let id = laid.value()["next_id"].as_u64().unwrap();
    let old = laid.apply_all(&[
        json!({"op": "add_action", "clip": 10, "at": 2 * SEC, "duration": SEC}),
        json!({"op": "set_action_end", "clip": 10, "action": id,
               "patch": {"video": {"scale": 2.0, "x": -400.0, "y": -200.0}}}),
    ]);
    let zoom = |p: &Value| -> Value {
        by_id(p, "/clips", 10)["actions"]
            .as_array()
            .unwrap()
            .iter()
            .find(|a| a["end"]["video"].as_object().is_some_and(|v| v.len() == 3))
            .unwrap_or_else(|| panic!("no zoom on clip 10 in {p}"))["end"]["video"]
            .clone()
    };
    let before = zoom(&old.value());
    assert_eq!(before["x"], -400.0, "the fixture's zoom: {before}");
    let got = old.apply(&vertical((1080, 1920))).apply(&relay(20)).value();
    let after = zoom(&got);
    let screen = with_defaults(&by_id(&got, "/clips", 10)["video"]);
    let (sx, sy, ss) = (
        screen["x"].as_f64().unwrap(),
        screen["y"].as_f64().unwrap(),
        screen["scale"].as_f64().unwrap(),
    );
    // The source point the old zoom puts at the canvas centre: u = −(x, y)/s.
    let (u, v) = (200.0, 100.0);
    let (x, y, s) = (
        after["x"].as_f64().unwrap(),
        after["y"].as_f64().unwrap(),
        after["scale"].as_f64().unwrap(),
    );
    // Old: x + s·u − screen.x = 0 (screen at 0, scale 1), so the new one is
    // 0 × the screen's scale ratio too, relative to the new screen.
    let ratio = ss / 1.0;
    assert!(
        ((x + s * u - sx) - 0.0 * ratio).abs() <= 1.0
            && ((y + s * v - sy) - 0.0 * ratio).abs() <= 1.0,
        "the zoomed point moved in the picture: {after}, screen {screen}"
    );
    assert!((s - 2.0 * ratio).abs() <= 1e-9, "scale {s}, ratio {ratio}");
    // keep's per-axis rule would put y at −200 × 1920/1080.
    assert!(
        (y - -200.0 * 1920.0 / 1080.0).abs() > 100.0,
        "keep's y: {after}"
    );
}

#[test]
fn a_camera_starting_late_keeps_its_cut_and_the_screen_its_glide() {
    let clips = || {
        vec![
            clip(10, 3, 2, 0, 30 * SEC),
            clip(20, 4, 1, 5 * SEC, 25 * SEC),
        ]
    };
    let old = project((1920, 1080), clips()).apply(&switch(20, "side_by_side", 5 * SEC));
    let got = old.apply(&vertical((1080, 1920))).apply(&relay(20)).value();
    // The screen's base before the switch is add_clip's on each canvas: Fit,
    // which `keep`'s rescale gives it on 9:16.
    let mut tall = clips();
    tall[0]["video"] = json!({"scale": 0.5625});
    let want = project((1080, 1920), tall)
        .apply(&switch(20, "stacked", 5 * SEC))
        .value();
    for id in [10, 20] {
        same_clip(&got, &want, id, "late camera");
    }
    let (_, camera) = shape(&got, 20);
    assert_eq!((camera[0].0, camera[0].1), (0, FRAME), "the camera's cut");
    let (_, screen) = shape(&got, 10);
    assert_eq!(
        (screen[0].0, screen[0].1, screen[0].2.as_str()),
        (5 * SEC, SEC / 2, "ease_in_out"),
        "the screen's glide"
    );
}

#[test]
fn a_camera_cut_in_two_is_re_laid_by_one_op() {
    let make = |canvas: (u32, u32), middle: &str| {
        let h = two(canvas).apply_all(&[
            switch(20, "corner", 0),
            switch_for(20, middle, 10 * SEC, SEC, "linear"),
            json!({"op": "split", "clips": [20], "at": 15 * SEC}),
        ]);
        let half = on_track(&h.value(), 4)[1];
        h.apply(&switch(half, "camera_full", 20 * SEC))
    };
    let old = make((1920, 1080), "side_by_side");
    let got = old.apply(&vertical((1080, 1920))).apply(&relay(20)).value();
    same_tracks(&got, &make((1080, 1920), "stacked").value(), "camera cut");
}

#[test]
fn split_screens_are_re_based_and_another_media_is_left_alone() {
    // At 25 s: the second half holds no layout action; it is a piece of the
    // 20 s switch. A later clip of media 9 at the same base is not.
    let make = |canvas: (u32, u32), middle: &str| {
        let mut clips = vec![clip(10, 3, 2, 0, 30 * SEC), clip(20, 4, 1, 0, 30 * SEC)];
        clips.push(clip(30, 3, 9, 30 * SEC, 5 * SEC));
        let h = three(&project(canvas, clips), middle);
        h.apply(&json!({"op": "split", "clips": [10], "at": 25 * SEC}))
    };
    let old = make((1920, 1080), "side_by_side");
    let got = old.apply(&vertical((1080, 1920))).apply(&relay(20)).value();
    let want = make((1080, 1920), "stacked").value();
    let (gs, ws) = (on_track(&got, 3), on_track(&want, 3));
    assert_eq!(gs.len(), 3);
    let half = by_id(&got, "/clips", gs[1]);
    assert_eq!(
        half["source"]["in"],
        json!(25 * SEC),
        "the half's in advanced"
    );
    let (gb, _) = shape(&got, gs[1]);
    let (wb, _) = shape(&want, ws[1]);
    assert!(near(&gb, &wb), "the 25 s half's base {gb:?}, want {wb:?}");
    assert_eq!(
        by_id(&got, "/clips", 30),
        by_id(&old.value(), "/clips", 30),
        "the other media's clip"
    );

    // At 15 s: the second half holds the 20 s action; the 10 s switch
    // re-bases it, its own switch re-lays it.
    let make = |canvas: (u32, u32), middle: &str| {
        two(canvas).apply_all(&[
            switch(20, "corner", 0),
            switch_for(20, middle, 10 * SEC, SEC, "linear"),
            json!({"op": "split", "clips": [10], "at": 15 * SEC}),
            switch(20, "camera_full", 20 * SEC),
        ])
    };
    let got = make((1920, 1080), "side_by_side")
        .apply(&vertical((1080, 1920)))
        .apply(&relay(20))
        .value();
    same_tracks(
        &got,
        &make((1080, 1920), "stacked").value(),
        "screen cut at 15 s",
    );
}

// ---- the refusals, in order -------------------------------------------------

#[test]
fn a_clip_with_no_layout_is_refused() {
    two((1080, 1920)).refuses_with(
        &relay(20),
        "clip 20 holds no camera layout to re-lay; frame it with subject, center, fit or keep",
    );
}

/// Clip 30 on track 5 laid out over clip 20 at 2 s, and clip 20 over clip 10
/// at 5 s: clip 20 is a screen and a camera.
fn both() -> Handle {
    let clips = vec![
        clip(10, 3, 2, 0, 30 * SEC),
        clip(20, 4, 1, 0, 30 * SEC),
        clip(30, 5, 1, 0, 30 * SEC),
    ];
    project((1920, 1080), clips).apply_all(&[
        json!({"op": "switch_layout", "camera": 30, "screen": 20, "layout": "corner",
               "at": 2 * SEC}),
        switch(20, "corner", 5 * SEC),
    ])
}

#[test]
fn a_clip_both_camera_and_screen_is_refused() {
    both().apply(&vertical((1080, 1920))).refuses_with(
        &relay(30),
        "clip 20 is laid out both as a camera and as a screen, so its layouts cannot be re-laid; \
         keep its clips as placed",
    );
}

/// A layout action on the screen at 8 s that no camera action meets, its id.
fn unpaired(h: &Handle) -> (Handle, u64) {
    let id = h.value()["next_id"].as_u64().unwrap();
    let full = json!({"x": 0.0, "y": 0.0, "scale": 1.0, "crop": {"l": 0, "t": 0, "r": 0, "b": 0},
                      "corner_radius": 0.0, "opacity": 1.0});
    let h = h.apply_all(&[
        json!({"op": "add_action", "clip": 10, "at": 8 * SEC, "duration": SEC / 2}),
        json!({"op": "set_action_end", "clip": 10, "action": id, "patch": {"video": full}}),
    ]);
    (h, id)
}

#[test]
fn an_unpaired_screen_action_is_refused_before_an_unrecognised_switch() {
    let (h, id) = unpaired(&two((1920, 1080)).apply(&switch(20, "corner", 0)));
    let sentence = format!(
        "clip 10's layout action {id} at 00:00:08:00 has no camera switch in front of it, so it \
         cannot be re-laid; keep its clips as placed"
    );
    h.apply(&vertical((1080, 1920)))
        .refuses_with(&relay(20), &sentence);
    // With an unrecognised camera end too, the unpaired action is named first.
    let moved = moved_end(&h, 20, 0, "x", 2.0);
    moved
        .apply(&vertical((1080, 1920)))
        .refuses_with(&relay(20), &sentence);
    // And a clip both camera and screen before either.
    let (h, _) = unpaired(&both());
    h.apply(&vertical((1080, 1920))).refuses_with(
        &relay(30),
        "clip 20 is laid out both as a camera and as a screen, so its layouts cannot be re-laid; \
         keep its clips as placed",
    );
}

/// `clip`'s layout action starting at clip time `t` with `key` moved by `by`.
fn moved_end(h: &Handle, clip: u64, t: i64, key: &str, by: f64) -> Handle {
    let p = h.value();
    let action = by_id(&p, "/clips", clip)["actions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["start"] == t && a["end"]["video"].get("opacity").is_some())
        .unwrap()
        .clone();
    let mut video = action["end"]["video"].clone();
    match key {
        "l" | "t" | "r" | "b" => {
            let v = video["crop"][key].as_f64().unwrap_or(0.0);
            video["crop"][key] = json!(v + by);
        }
        _ => {
            let v = video[key].as_f64().unwrap();
            video[key] = json!(v + by);
        }
    }
    h.apply(
        &json!({"op": "set_action_end", "clip": clip, "action": action["id"],
                    "patch": {"video": video}}),
    )
}

#[test]
fn an_unrecognised_switch_names_the_camera_or_the_screen_action() {
    let old = three(&two((1920, 1080)), "side_by_side");
    let id_at = |h: &Handle, clip: u64, t: i64| {
        by_id(&h.value(), "/clips", clip)["actions"]
            .as_array()
            .unwrap()
            .iter()
            .find(|a| a["start"] == t)
            .unwrap()["id"]
            .as_u64()
            .unwrap()
    };
    let camera = moved_end(&old, 20, 10 * SEC, "x", 40.0);
    let id = id_at(&camera, 20, 10 * SEC);
    camera.apply(&vertical((1080, 1920))).refuses_with(
        &relay(20),
        &format!(
            "clip 20's layout action {id} at 00:00:10:00 is not a camera layout Frame Job made on \
             the 1920 × 1080 canvas, so it cannot be re-laid; keep its clips as placed"
        ),
    );
    let screen = moved_end(&old, 10, 10 * SEC, "y", 2.0);
    let id = id_at(&screen, 10, 10 * SEC);
    screen.apply(&vertical((1080, 1920))).refuses_with(
        &relay(20),
        &format!(
            "clip 10's layout action {id} at 00:00:10:00 is not a camera layout Frame Job made on \
             the 1920 × 1080 canvas, so it cannot be re-laid; keep its clips as placed"
        ),
    );
    // A later unrecognised switch does not hide an earlier one.
    let both_moved = moved_end(
        &moved_end(&old, 20, 20 * SEC, "scale", 0.5),
        20,
        10 * SEC,
        "y",
        3.0,
    );
    let id = id_at(&both_moved, 20, 10 * SEC);
    both_moved.apply(&vertical((1080, 1920))).refuses_with(
        &relay(20),
        &format!(
            "clip 20's layout action {id} at 00:00:10:00 is not a camera layout Frame Job made on \
             the 1920 × 1080 canvas, so it cannot be re-laid; keep its clips as placed"
        ),
    );
}

#[test]
fn layout_reads_no_zoom_where_empty_replace_or_backdrop() {
    let old = three(&two((1920, 1080)), "side_by_side").apply(&vertical((1080, 1920)));
    let plain = old.apply(&relay(20)).value();
    let mut op = relay(20);
    op["zoom"] = json!(3.0);
    op["where_empty"] = json!("center");
    op["replace"] = json!(true);
    op["backdrop"] = json!(3);
    assert_eq!(old.apply(&op).value(), plain);
}

#[test]
fn from_defaults_to_the_canvas() {
    // With no `from_*` the authored canvas is the current one: a 16:9 layout
    // is not one Frame Job made on 9:16.
    let old = three(&two((1920, 1080)), "side_by_side").apply(&vertical((1080, 1920)));
    old.refuses(&json!({"op": "reframe_clip", "clip": 20, "follow": "layout"}));
}
