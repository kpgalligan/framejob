//! Camera layouts at the playhead (road map "creator-jobs" CO6, spec §11
//! CO-60…CO-65), black box through `rc_project_apply`'s `switch_layout`.
//! Every expected placement is worked here from CO-60's figures — the
//! picture's box on the canvas first, then the offset of its centre — never
//! read back from `layout.rs`; the corner square is CAM-10 (3)'s
//! `cornerPatch` as the Swift landing writes it.
//!
//! The fixture: media 1 a 1280 × 720 camera, media 2 a 1920 × 1080 screen;
//! track 3 "Screen" behind track 4 "Camera"; screen clip 10 and camera clip
//! 20 over [0, 60 s) at 30 fps (a frame is 20 000 ticks).

mod common;

use common::{by_id, Handle, Outcome};
use serde_json::{json, Value};

const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;

fn media(id: u32, w: u32, h: u32) -> Value {
    json!({"id": id, "path": format!("/m/{id}.mov"), "kind": "video", "duration": 600 * SEC,
           "width": w, "height": h, "fps": [30, 1], "has_video": true, "has_audio": false})
}

fn clip(id: u32, track: u32, media: u32, start: i64, duration: i64) -> Value {
    // Track 1 is id 3, track 2 id 4: ids are one space with the media's.
    json!({"id": id, "track": track + 2, "start": start, "duration": duration,
           "source": {"kind": "media", "media": media, "in": start}, "video": {}})
}

fn project(canvas: (u32, u32), camera: (u32, u32), screen: (u32, u32), clips: Vec<Value>) -> Value {
    json!({
        "version": 38,
        "canvas": {"width": canvas.0, "height": canvas.1, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
        "media": [media(1, camera.0, camera.1), media(2, screen.0, screen.1)],
        "tracks": [{"id": 3, "name": "Screen"}, {"id": 4, "name": "Camera"}],
        "clips": clips, "markers": [], "next_id": 100
    })
}

/// Screen clip 10 and camera clip 20, both [0, 60 s).
fn two(canvas: (u32, u32)) -> Handle {
    Handle::from_value(&project(
        canvas,
        (1280, 720),
        (1920, 1080),
        vec![clip(10, 1, 2, 0, 60 * SEC), clip(20, 2, 1, 0, 60 * SEC)],
    ))
}

fn switch(args: Value) -> Value {
    let mut op = json!({"op": "switch_layout"});
    for (k, v) in args.as_object().unwrap() {
        op[k] = v.clone();
    }
    op
}

/// The six keys, as nine numbers in a fixed order.
#[derive(Debug, Clone, Copy)]
struct P {
    x: f64,
    y: f64,
    s: f64,
    crop: [f64; 4],
    r: f64,
    o: f64,
}

fn read(video: &Value) -> P {
    let n = |k: &str| {
        video[k]
            .as_f64()
            .unwrap_or_else(|| panic!("{k} in {video}"))
    };
    let c = &video["crop"];
    P {
        x: n("x"),
        y: n("y"),
        s: n("scale"),
        crop: ["l", "t", "r", "b"].map(|k| c[k].as_f64().unwrap()),
        r: n("corner_radius"),
        o: n("opacity"),
    }
}

fn same(got: P, want: P, what: &str) {
    let near = |a: f64, b: f64| (a - b).abs() < 1e-9;
    assert!(
        got.x == want.x
            && got.y == want.y
            && near(got.s, want.s)
            && got.crop.iter().zip(want.crop).all(|(a, b)| near(*a, b))
            && near(got.r, want.r)
            && near(got.o, want.o),
        "{what}: got {got:?}, want {want:?}"
    );
}

/// The action on `clip` starting at clip time `t`.
fn action(project: &Value, clip: u64, t: i64) -> Value {
    by_id(project, "/clips", clip)["actions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["start"] == t)
        .unwrap_or_else(|| panic!("no action at {t} on clip {clip}"))
        .clone()
}

fn end(project: &Value, clip: u64, t: i64) -> P {
    read(&action(project, clip, t)["end"]["video"])
}

// ---- the oracle: CO-60 worked as boxes on the canvas -----------------------

/// An uncropped picture `w × h` on screen, its top-left at (left, top).
fn at_rect(canvas: (f64, f64), left: f64, top: f64, w: f64, h: f64, s: f64, r: f64) -> P {
    P {
        x: (left + w / 2.0 - canvas.0 / 2.0).round(),
        y: (top + h / 2.0 - canvas.1 / 2.0).round(),
        s,
        crop: [0.0; 4],
        r,
        o: 1.0,
    }
}

/// A source `a × b` cropped to fill the box (left, top, bw, bh), the crop
/// centred on `focus` and clamped.
fn filling(canvas: (f64, f64), src: (f64, f64), rect: [f64; 4], focus: (f64, f64), r: f64) -> P {
    let [left, top, bw, bh] = rect;
    let s = (bw / src.0).max(bh / src.1);
    let (cw, ch) = ((bw / s).min(src.0), (bh / s).min(src.1));
    let side = |whole: f64, part: f64, f: f64| {
        let room = (whole - part) / 2.0;
        let f = f.clamp(-room, room);
        (room + f, room - f)
    };
    let (l, rr) = side(src.0, cw, focus.0);
    let (t, b) = side(src.1, ch, focus.1);
    // The cropped centre sits at the box's centre; the anchor is s·c behind.
    let cx = left + bw / 2.0 - canvas.0 / 2.0 - s * (l - rr) / 2.0;
    let cy = top + bh / 2.0 - canvas.1 / 2.0 - s * (t - b) / 2.0;
    P {
        x: cx.round(),
        y: cy.round(),
        s,
        crop: [l, t, rr, b],
        r: r / s,
        o: 1.0,
    }
}

fn full(canvas: (f64, f64), src: (f64, f64)) -> P {
    let s = if src.0 > canvas.0 || src.1 > canvas.1 {
        (canvas.0 / src.0).min(canvas.1 / src.1)
    } else {
        1.0
    };
    P {
        x: 0.0,
        y: 0.0,
        s,
        crop: [0.0; 4],
        r: 0.0,
        o: 1.0,
    }
}

/// (camera, screen) for `layout` at the bottom-right, square.
fn oracle(layout: &str, canvas: (f64, f64), cam: (f64, f64), scr: (f64, f64)) -> (P, P) {
    let (w, h) = canvas;
    let m = 0.04 * w.min(h);
    let panel = 0.02 * w.min(h);
    match layout {
        "corner" => {
            let s = (w / 4.0 / cam.0).min(h / 3.0 / cam.1);
            let (pw, ph) = (cam.0 * s, cam.1 * s);
            let camera = at_rect(canvas, 0.95 * w - pw, 0.95 * h - ph, pw, ph, s, 0.0);
            (camera, full(canvas, scr))
        }
        "side_by_side" => {
            let inner = w - 3.0 * m;
            let (bw, bh) = (inner * 2.0 / 3.0, h - 2.0 * m);
            let s = (bw / scr.0).min(bh / scr.1);
            let (pw, ph) = (scr.0 * s, scr.1 * s);
            let screen = at_rect(
                canvas,
                m + (bw - pw) / 2.0,
                m + (bh - ph) / 2.0,
                pw,
                ph,
                s,
                panel / s,
            );
            let rect = [m + bw + m, m, inner / 3.0, bh];
            (filling(canvas, cam, rect, (0.0, 0.0), panel), screen)
        }
        "stacked" => {
            let s = ((w - 2.0 * m) / scr.0).min((h - 3.0 * m) * 2.0 / 3.0 / scr.1);
            let (pw, ph) = (scr.0 * s, scr.1 * s);
            let screen = at_rect(canvas, (w - pw) / 2.0, m, pw, ph, s, panel / s);
            let rect = [m, 2.0 * m + ph, w - 2.0 * m, h - 3.0 * m - ph];
            (filling(canvas, cam, rect, (0.0, 0.0), panel), screen)
        }
        "camera_full" => {
            let s = (w / cam.0).max(h / cam.1);
            (
                P {
                    x: 0.0,
                    y: 0.0,
                    s,
                    crop: [0.0; 4],
                    r: 0.0,
                    o: 1.0,
                },
                full(canvas, scr),
            )
        }
        _ => unreachable!(),
    }
}

// ---- CO-60: the geometry ---------------------------------------------------

#[test]
fn every_layout_lands_its_six_keys_on_three_canvases() {
    for canvas in [(1920u32, 1080u32), (1080, 1920), (1080, 1080)] {
        let size = (f64::from(canvas.0), f64::from(canvas.1));
        for layout in ["corner", "side_by_side", "stacked", "camera_full"] {
            let after = two(canvas)
                .apply(&switch(
                    json!({"camera": 20, "layout": layout, "at": 2 * SEC}),
                ))
                .value();
            let (camera, screen) = oracle(layout, size, (1280.0, 720.0), (1920.0, 1080.0));
            same(
                end(&after, 20, 2 * SEC),
                camera,
                &format!("{canvas:?} {layout} camera"),
            );
            same(
                end(&after, 10, 2 * SEC),
                screen,
                &format!("{canvas:?} {layout} screen"),
            );
            for id in [10, 20] {
                let a = action(&after, id, 2 * SEC);
                let keys: Vec<&String> = a["end"]["video"].as_object().unwrap().keys().collect();
                assert_eq!(keys.len(), 6, "{layout}: {keys:?}");
                assert_eq!(a["end"].as_object().unwrap().len(), 1, "only video");
                assert_eq!(a["duration"], SEC / 2, "0.5 s");
                assert_eq!(a["curve"], "ease_in_out");
            }
        }
        // screen_only: the camera where it is, at opacity 0.
        let after = two(canvas)
            .apply(&switch(
                json!({"camera": 20, "layout": "screen_only", "at": 2 * SEC}),
            ))
            .value();
        let mut kept = full(size, (1280.0, 720.0));
        kept.s = 1.0;
        kept.o = 0.0;
        same(end(&after, 20, 2 * SEC), kept, "screen_only camera");
    }
}

#[test]
fn the_corner_square_is_cam_10s_corner_patch() {
    // `RecordingLanding.cornerPatch`, written out as Swift computes it.
    for (cw, ch) in [(1920.0f64, 1080.0f64), (1080.0, 1920.0), (1280.0, 720.0)] {
        let (sw, sh) = (1280.0f64, 720.0f64);
        let fit = (0.25 * cw / sw).min(1.0 / 3.0 * ch / sh);
        let scale = fit.clamp(0.01, 10.0);
        let x = (cw / 2.0 - 0.05 * cw - sw * scale / 2.0).round();
        let y = (ch / 2.0 - 0.05 * ch - sh * scale / 2.0).round();
        let after = two((cw as u32, ch as u32))
            .apply(&switch(
                json!({"camera": 20, "layout": "corner", "at": 2 * SEC}),
            ))
            .value();
        let got = end(&after, 20, 2 * SEC);
        assert_eq!((got.x, got.y), (x, y), "{cw}×{ch}");
        assert!((got.s - scale).abs() < 1e-12);
    }
}

#[test]
fn the_four_corners_mirror_the_bottom_right() {
    let base = two((1920, 1080));
    let at = |corner: &str| {
        let after = base
            .apply(&switch(
                json!({"camera": 20, "layout": "corner", "corner": corner,
                                  "at": 2 * SEC}),
            ))
            .value();
        let p = end(&after, 20, 2 * SEC);
        (p.x, p.y)
    };
    let (x, y) = at("bottom_right");
    assert_eq!(at("bottom_left"), (-x, y));
    assert_eq!(at("top_right"), (x, -y));
    assert_eq!(at("top_left"), (-x, -y));
}

#[test]
fn the_screens_full_placement_is_add_clips() {
    // A smaller screen: add_clip never scales up.
    let small = Handle::from_value(&project(
        (1920, 1080),
        (1280, 720),
        (1280, 720),
        vec![clip(10, 1, 2, 0, 60 * SEC), clip(20, 2, 1, 0, 60 * SEC)],
    ));
    // A larger one with fit_new_clips off: add_clip leaves it at 1.
    let mut off = project(
        (1920, 1080),
        (1280, 720),
        (3840, 2160),
        vec![clip(10, 1, 2, 0, 60 * SEC), clip(20, 2, 1, 0, 60 * SEC)],
    );
    off["canvas"]["fit_new_clips"] = json!(false);
    // And a larger one with it on: Fit.
    let on = Handle::from_value(&project(
        (1920, 1080),
        (1280, 720),
        (3840, 2160),
        vec![clip(10, 1, 2, 0, 60 * SEC), clip(20, 2, 1, 0, 60 * SEC)],
    ));
    for handle in [small, Handle::from_value(&off), on] {
        let added = handle
            .apply(&json!({"op": "add_clip", "track": 3, "media": 2, "at": 120 * SEC}))
            .value();
        let placed = added["clips"].as_array().unwrap().last().unwrap()["video"].clone();
        let after = handle
            .apply(&switch(
                json!({"camera": 20, "layout": "corner", "at": 2 * SEC}),
            ))
            .value();
        let got = end(&after, 10, 2 * SEC);
        assert_eq!(got.s, placed["scale"].as_f64().unwrap());
        assert_eq!((got.x, got.y, got.r, got.o), (0.0, 0.0, 0.0, 1.0));
        assert_eq!(got.crop, [0.0; 4]);
    }
}

#[test]
fn circle_crops_the_largest_square_and_rounded_takes_its_radius() {
    let base = two((1920, 1080));
    let after = base
        .apply(&switch(
            json!({"camera": 20, "layout": "corner", "shape": "circle",
                              "at": 2 * SEC}),
        ))
        .value();
    let p = end(&after, 20, 2 * SEC);
    assert_eq!(
        p.crop,
        [280.0, 0.0, 280.0, 0.0],
        "a 720 square of 1280 × 720"
    );
    assert_eq!(p.r, 360.0, "half the square's side");
    assert!((p.s - 0.5).abs() < 1e-12, "360 canvas px for 720 source px");
    // The square's outer corner at the inset: right edge 1824, bottom 1026.
    assert_eq!((p.x, p.y), (1824.0 - 180.0 - 960.0, 1026.0 - 180.0 - 540.0));
    let after = base
        .apply(&switch(
            json!({"camera": 20, "layout": "corner", "shape": "rounded",
                              "at": 2 * SEC}),
        ))
        .value();
    let p = end(&after, 20, 2 * SEC);
    // 8 % of min(480, 360) canvas px at scale 0.375.
    assert!((p.r - 0.08 * 360.0 / 0.375).abs() < 1e-9, "{}", p.r);
}

#[test]
fn focus_centres_the_crop_and_is_clamped_inside_the_source() {
    let base = two((1920, 1080));
    let crop = |focus: Value| {
        let after = base
            .apply(&switch(
                json!({"camera": 20, "layout": "corner", "shape": "circle",
                                  "focus": focus, "at": 2 * SEC}),
            ))
            .value();
        end(&after, 20, 2 * SEC).crop
    };
    assert_eq!(crop(json!([100.0, 50.0])), [380.0, 0.0, 180.0, 0.0]);
    assert_eq!(crop(json!([1000.0, 0.0])), [560.0, 0.0, 0.0, 0.0]);
    assert_eq!(crop(json!([-1000.0, 0.0])), [0.0, 0.0, 560.0, 0.0]);
    // The fill crop too: side by side's tall box crops across.
    let after = base
        .apply(&switch(json!({"camera": 20, "layout": "side_by_side",
                              "focus": [-50.0, 0.0], "at": 2 * SEC})))
        .value();
    let p = end(&after, 20, 2 * SEC);
    assert!((p.crop[0] - p.crop[2] + 100.0).abs() < 1e-9, "{:?}", p.crop);
}

// ---- CO-61: the switch and its reach -----------------------------------------

#[test]
fn a_first_frame_switch_is_a_cut() {
    let after = two((1920, 1080))
        .apply(&switch(json!({"camera": 20, "layout": "corner", "at": 0})))
        .value();
    let base = read(&by_id(&after, "/clips", 20)["video"]);
    let a = action(&after, 20, 0);
    assert_eq!(a["duration"], FRAME, "one frame");
    same(
        read(&a["end"]["video"]),
        base,
        "the marker's end is the base",
    );
    let (camera, _) = oracle(
        "corner",
        (1920.0, 1080.0),
        (1280.0, 720.0),
        (1920.0, 1080.0),
    );
    same(base, camera, "the base is the layout");
}

fn cut_camera(cuts: &[(u32, i64, i64)]) -> Value {
    let mut clips = vec![clip(10, 1, 2, 0, 60 * SEC)];
    for (id, start, length) in cuts {
        clips.push(clip(*id, 2, 1, *start, *length));
    }
    project((1920, 1080), (1280, 720), (1920, 1080), clips)
}

#[test]
fn the_reach_carries_to_later_clips_and_stops_at_a_layout_action() {
    let mut fixture = cut_camera(&[
        (20, 0, 10 * SEC),
        (21, 10 * SEC, 10 * SEC),
        (22, 20 * SEC, 10 * SEC),
        (23, 30 * SEC, 10 * SEC),
        (24, 40 * SEC, 10 * SEC),
    ]);
    let six = json!({"video": {"x": 0, "y": 0, "scale": 1, "crop": {"l": 0, "t": 0, "r": 0,
                                "b": 0}, "corner_radius": 0, "opacity": 1}});
    fixture["clips"][5]["actions"] = json!([{"id": 90, "start": 0, "duration": FRAME, "end": six}]);
    let before = Handle::from_value(&fixture);
    let after = before
        .apply(&switch(
            json!({"camera": 21, "layout": "corner", "at": 12 * SEC}),
        ))
        .value();
    let (camera, _) = oracle(
        "corner",
        (1920.0, 1080.0),
        (1280.0, 720.0),
        (1920.0, 1080.0),
    );
    end(&after, 21, 2 * SEC);
    for id in [22, 23] {
        same(
            read(&by_id(&after, "/clips", id)["video"]),
            camera,
            "carried",
        );
    }
    assert_eq!(
        by_id(&after, "/clips", 24),
        by_id(&before.value(), "/clips", 24)
    );
    assert_eq!(
        by_id(&after, "/clips", 20),
        by_id(&before.value(), "/clips", 20)
    );
}

#[test]
fn a_later_clip_with_a_mid_clip_layout_action_takes_the_base_and_keeps_it() {
    let mut fixture = cut_camera(&[
        (20, 0, 10 * SEC),
        (21, 10 * SEC, 10 * SEC),
        (22, 20 * SEC, 10 * SEC),
    ]);
    let six = json!({"video": {"x": 5, "y": 5, "scale": 0.5, "crop": {"l": 0, "t": 0, "r": 0,
                                "b": 0}, "corner_radius": 0, "opacity": 1}});
    fixture["clips"][2]["actions"] =
        json!([{"id": 90, "start": 5 * SEC, "duration": SEC / 2, "end": six}]);
    let before = Handle::from_value(&fixture);
    let after = before
        .apply(&switch(
            json!({"camera": 20, "layout": "corner", "at": 2 * SEC}),
        ))
        .value();
    let (camera, _) = oracle(
        "corner",
        (1920.0, 1080.0),
        (1280.0, 720.0),
        (1920.0, 1080.0),
    );
    let held = by_id(&after, "/clips", 21);
    same(read(&held["video"]), camera, "the new base");
    assert_eq!(
        held["actions"],
        by_id(&before.value(), "/clips", 21)["actions"],
        "its action kept"
    );
    assert_eq!(
        by_id(&after, "/clips", 22),
        by_id(&before.value(), "/clips", 22)
    );
}

#[test]
fn through_ends_the_reach() {
    let fixture = cut_camera(&[
        (20, 0, 10 * SEC),
        (21, 10 * SEC, 10 * SEC),
        (22, 20 * SEC, 10 * SEC),
    ]);
    let before = Handle::from_value(&fixture);
    let after = before
        .apply(&switch(
            json!({"camera": 20, "layout": "corner", "at": 2 * SEC,
                              "through": 15 * SEC}),
        ))
        .value();
    assert_ne!(
        by_id(&after, "/clips", 21),
        by_id(&before.value(), "/clips", 21)
    );
    assert_eq!(
        by_id(&after, "/clips", 22),
        by_id(&before.value(), "/clips", 22)
    );
    let all = before
        .apply(&switch(
            json!({"camera": 20, "layout": "corner", "at": 2 * SEC}),
        ))
        .value();
    assert_ne!(
        by_id(&all, "/clips", 22),
        by_id(&before.value(), "/clips", 22)
    );
}

#[test]
fn two_switches_on_one_clip_make_two_actions_and_the_second_holds() {
    let after = two((1920, 1080))
        .apply(&switch(
            json!({"camera": 20, "layout": "corner", "at": 2 * SEC}),
        ))
        .apply(&switch(
            json!({"camera": 20, "layout": "side_by_side", "at": 5 * SEC}),
        ));
    let value = after.value();
    assert_eq!(
        by_id(&value, "/clips", 20)["actions"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
    let state = after.clip_state(20, 30 * SEC).unwrap();
    let (camera, _) = oracle(
        "side_by_side",
        (1920.0, 1080.0),
        (1280.0, 720.0),
        (1920.0, 1080.0),
    );
    same(read(&state["video"]), camera, "held at 30 s");
}

#[test]
fn a_switch_inside_a_running_layout_action_shortens_it() {
    let first = two((1920, 1080)).apply(&switch(
        json!({"camera": 20, "layout": "corner", "at": 2 * SEC}),
    ));
    let id = action(&first.value(), 20, 2 * SEC)["id"].clone();
    let after = first
        .apply(&switch(json!({"camera": 20, "layout": "side_by_side",
                              "at": 2 * SEC + 6 * FRAME})))
        .value();
    let a = action(&after, 20, 2 * SEC);
    assert_eq!(a["id"], id);
    assert_eq!(a["duration"], 6 * FRAME, "ends at the second switch");
    assert_eq!(action(&after, 20, 2 * SEC + 6 * FRAME)["duration"], SEC / 2);
}

#[test]
fn a_layout_action_at_at_is_replaced() {
    let first = two((1920, 1080)).apply(&switch(
        json!({"camera": 20, "layout": "corner", "at": 2 * SEC}),
    ));
    let after = first
        .apply(&switch(
            json!({"camera": 20, "layout": "camera_full", "at": 2 * SEC}),
        ))
        .value();
    assert_eq!(
        by_id(&after, "/clips", 20)["actions"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(end(&after, 20, 2 * SEC).s, 1.5, "camera_full's fill");
}

#[test]
fn the_duration_is_clamped_to_the_clip_and_the_next_layout_action() {
    let first = two((1920, 1080)).apply(&switch(
        json!({"camera": 20, "layout": "corner", "at": 10 * SEC}),
    ));
    let after = first
        .apply(&switch(
            json!({"camera": 20, "layout": "stacked", "at": 9 * SEC,
                              "duration": 3 * SEC}),
        ))
        .value();
    assert_eq!(action(&after, 20, 9 * SEC)["duration"], SEC);
    let after = two((1920, 1080))
        .apply(&switch(
            json!({"camera": 20, "layout": "stacked", "at": 59 * SEC,
                              "duration": 3 * SEC, "curve": "linear"}),
        ))
        .value();
    let a = action(&after, 20, 59 * SEC);
    assert_eq!(
        (a["duration"].clone(), a["curve"].clone()),
        (json!(SEC), json!("linear"))
    );
}

// ---- CO-62: movers, nests -----------------------------------------------------

/// Screen clips 10 [0, 10 s) and 11 [10 s, 20 s), 11 zooming at clip time
/// 2 s; camera 20 over [0, 60 s).
fn zoomed_later_screen() -> Handle {
    let mut later = clip(11, 1, 2, 10 * SEC, 10 * SEC);
    later["actions"] = json!([{"id": 50, "start": 2 * SEC, "duration": SEC,
                               "curve": "ease_in_out",
                               "end": {"video": {"scale": 2, "x": 100, "y": 50}}}]);
    Handle::from_value(&project(
        (1920, 1080),
        (1280, 720),
        (1920, 1080),
        vec![
            clip(10, 1, 2, 0, 10 * SEC),
            later,
            clip(20, 2, 1, 0, 60 * SEC),
        ],
    ))
}

#[test]
fn a_later_zoom_refuses_and_nest_true_nests_like_nest_then_switch() {
    let base = zoomed_later_screen();
    let op = json!({"camera": 20, "layout": "side_by_side", "at": 2 * SEC});
    base.refuses_with(
        &switch(op.clone()),
        "The screen clip 11 at 00:00:10:00 zooms (action 50); nest the screen's clips so \
         the layout moves the nest and the zoom stays inside it.",
    );
    let mut nesting = op.clone();
    nesting["nest"] = json!(true);
    let nested = base.apply(&switch(nesting)).value();
    let twin = base
        .apply(&json!({"op": "nest", "clips": [10, 11]}))
        .apply(&switch(op))
        .value();
    assert_eq!(nested, twin);
    let inside = &nested["nests"][0]["clips"];
    let zoomed = inside
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == 11)
        .unwrap();
    assert_eq!(zoomed["actions"][0]["id"], 50, "the zoom inside the nest");
}

#[test]
fn a_mover_on_the_camera_refuses_and_another_action_meets_add_actions_rule() {
    let mut fixture = project(
        (1920, 1080),
        (1280, 720),
        (1920, 1080),
        vec![clip(10, 1, 2, 0, 60 * SEC), clip(20, 2, 1, 0, 60 * SEC)],
    );
    fixture["clips"][1]["actions"] = json!([{"id": 60, "start": SEC, "duration": 2 * SEC,
                                             "end": {"video": {"opacity": 0.5}}}]);
    Handle::from_value(&fixture).refuses_with(
        &switch(json!({"camera": 20, "layout": "corner", "at": 2 * SEC})),
        "The camera clip 20 at 00:00:00:00 moves (action 60); nest the camera's clips so \
         the layout moves the nest and the action stays inside it.",
    );
    fixture["clips"][1]["actions"][0]["end"] = json!({"video": {"rotation": 10}});
    Handle::from_value(&fixture).refuses_with(
        &switch(json!({"camera": 20, "layout": "corner", "at": 2 * SEC})),
        "action 60 on clip 20 already runs from 600000 to 1800000 ticks, and two actions on \
         one clip may not overlap",
    );
}

/// Screen clip 10 over [0, 60 s) with zooms at 10 s and 20 s.
fn zoomed_screen(base: Value) -> Handle {
    let mut screen = clip(10, 1, 2, 0, 60 * SEC);
    screen["video"] = base;
    Handle::from_value(&project(
        (1920, 1080),
        (1280, 720),
        (1920, 1080),
        vec![screen, clip(20, 2, 1, 0, 60 * SEC)],
    ))
    .apply(&json!({"op": "add_zoom_action", "clip": 10, "at": 10 * SEC,
                   "region": {"x": 0, "y": 0, "width": 960, "height": 540}}))
    .apply(&json!({"op": "add_zoom_action", "clip": 10, "at": 20 * SEC}))
}

#[test]
fn a_full_placement_screen_with_zooms_takes_a_corner_and_keeps_them() {
    let zoomed = zoomed_screen(json!({}));
    let before = by_id(&zoomed.value(), "/clips", 10)["actions"].clone();
    for layout in ["corner", "camera_full", "screen_only"] {
        let after = zoomed
            .apply(&switch(
                json!({"camera": 20, "layout": layout, "shape": "square",
                                  "at": 5 * SEC}),
            ))
            .value();
        let actions = by_id(&after, "/clips", 10)["actions"]
            .as_array()
            .unwrap()
            .clone();
        for kept in before.as_array().unwrap() {
            assert!(actions.contains(kept), "{layout}: zoom {kept} changed");
        }
        same(
            end(&after, 10, 5 * SEC),
            full((1920.0, 1080.0), (1920.0, 1080.0)),
            "the screen's end is its full placement",
        );
    }
    // A screen not at its full placement still refuses.
    let off = zoomed_screen(json!({"scale": 0.8}));
    let zoom = by_id(&off.value(), "/clips", 10)["actions"][0]["id"].clone();
    off.refuses_with(
        &switch(json!({"camera": 20, "layout": "corner", "at": 5 * SEC})),
        &format!(
            "The screen clip 10 at 00:00:00:00 zooms (action {zoom}); nest the screen's \
             clips so the layout moves the nest and the zoom stays inside it."
        ),
    );
}

#[test]
fn an_earlier_full_layout_action_does_not_block_the_nest() {
    // The four steps: corner at 2 s, a zoom on the screen at 40 s, then
    // side by side at 30 s — refused for the zoom, and nested with `nest`.
    let corner = two((1920, 1080))
        .apply(&switch(
            json!({"camera": 20, "layout": "corner", "at": 2 * SEC}),
        ))
        .apply(&json!({"op": "add_zoom_action", "clip": 10, "at": 40 * SEC,
                       "region": {"x": 0, "y": 0, "width": 960, "height": 540}}));
    let zoom = action(&corner.value(), 10, 40 * SEC)["id"].clone();
    corner.refuses_with(
        &switch(json!({"camera": 20, "layout": "side_by_side", "at": 30 * SEC})),
        &format!(
            "The screen clip 10 at 00:00:00:00 zooms (action {zoom}); nest the screen's \
             clips so the layout moves the nest and the zoom stays inside it."
        ),
    );
    let nested = corner
        .apply(&switch(
            json!({"camera": 20, "layout": "side_by_side", "at": 30 * SEC,
                              "nest": true}),
        ))
        .value();
    let inside = nested["nests"][0]["clips"][0]["actions"]
        .as_array()
        .unwrap();
    assert_eq!(
        inside.len(),
        2,
        "the corner's layout action and the zoom, inside"
    );
}

#[test]
fn a_laid_out_clip_refuses_the_nest() {
    let laid = zoomed_later_screen()
        .apply(&json!({"op": "set_video", "clips": [10], "patch": {"x": 300}}));
    laid.refuses_with(
        &switch(
            json!({"camera": 20, "layout": "side_by_side", "at": 2 * SEC,
                       "nest": true}),
        ),
        "clip 10 is already laid out; a nest would lay it out twice.",
    );
}

#[test]
fn a_nest_clip_camera_refuses_a_radius() {
    let nested = two((1920, 1080)).apply(&json!({"op": "nest", "clips": [20]}));
    let camera = nested.value()["clips"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["source"]["kind"] == "nest")
        .unwrap()["id"]
        .as_u64()
        .unwrap();
    for shape in ["circle", "rounded"] {
        nested.refuses_with(
            &switch(json!({"camera": camera, "layout": "corner", "shape": shape,
                           "at": 2 * SEC})),
            &format!(
                "clip {camera} is a nest clip, which cannot draw a rounded corner or a circle."
            ),
        );
    }
    nested.apply(&switch(
        json!({"camera": camera, "layout": "corner", "at": 2 * SEC}),
    ));
    // A camera that would become one.
    let mut fixture = project(
        (1920, 1080),
        (1280, 720),
        (1920, 1080),
        vec![clip(10, 1, 2, 0, 60 * SEC), clip(20, 2, 1, 0, 60 * SEC)],
    );
    fixture["clips"][1]["actions"] = json!([{"id": 60, "start": 10 * SEC, "duration": SEC,
                                             "end": {"video": {"scale": 2, "x": 0, "y": 0}}}]);
    Handle::from_value(&fixture).refuses_with(
        &switch(
            json!({"camera": 20, "layout": "corner", "shape": "circle", "at": 2 * SEC,
                       "nest": true}),
        ),
        "clip 20 is a nest clip, which cannot draw a rounded corner or a circle.",
    );
}

// ---- CO-64: roles, errors and refusals ----------------------------------------

#[test]
fn every_role_refusal_in_its_own_words() {
    let mut fixture = project(
        (1920, 1080),
        (1280, 720),
        (1920, 1080),
        vec![clip(10, 1, 2, 0, 60 * SEC), clip(20, 2, 1, 0, 60 * SEC)],
    );
    fixture["clips"].as_array_mut().unwrap().push(json!({
        "id": 30, "track": 4, "start": 60 * SEC, "duration": SEC,
        "source": {"kind": "text"}, "video": {}, "text": {"content": "hi"}}));
    let base = Handle::from_value(&fixture);
    base.refuses_with(
        &switch(json!({"camera": 30, "layout": "corner", "at": 60 * SEC})),
        "clip 30 has no picture to lay out",
    );
    base.refuses_with(
        &switch(json!({"camera": 20, "layout": "corner", "at": 70 * SEC})),
        "clip 20 does not play at 00:01:10:00",
    );
    base.refuses_with(
        &switch(json!({"camera": 10, "screen": 20, "layout": "corner", "at": 2 * SEC})),
        "the screen (clip 20) must be on a track behind the camera's (clip 10)",
    );
    let hidden = base.apply(&json!({"op": "set_track", "track": 3, "hidden": true}));
    for layout in ["side_by_side", "stacked"] {
        hidden.refuses_with(
            &switch(json!({"camera": 20, "layout": layout, "at": 2 * SEC})),
            "no clip draws behind clip 20 at 00:00:02:00 to be the screen",
        );
    }
    // The camera alone in the other three.
    let alone = hidden
        .apply(&switch(
            json!({"camera": 20, "layout": "corner", "at": 2 * SEC}),
        ))
        .value();
    assert_eq!(
        by_id(&alone, "/clips", 10)["actions"],
        json!([]),
        "the screen untouched"
    );
}

#[test]
fn bad_arguments_are_errors() {
    let base = two((1920, 1080));
    let msg = base.errors(&switch(
        json!({"camera": 20, "layout": "corner", "at": 2 * SEC,
                                         "through": 2 * SEC}),
    ));
    assert!(msg.contains("through must be after at"), "{msg}");
    let msg = base.errors(&switch(
        json!({"camera": 20, "layout": "corner", "at": 2 * SEC,
                                         "duration": 0}),
    ));
    assert!(msg.contains("duration must be positive"), "{msg}");
    let msg = base.errors(&switch(
        json!({"camera": 20, "layout": "corner", "at": -SEC}),
    ));
    assert!(msg.contains("at must not be negative"), "{msg}");
    let msg = base.errors(&switch(json!({"camera": 99, "layout": "corner", "at": 0})));
    assert!(msg.contains("no clip with id 99"), "{msg}");
    let msg = base.errors(&switch(
        json!({"camera": 20, "layout": "diagonal", "at": 0}),
    ));
    assert!(msg.contains("side_by_side"), "{msg}");
}

#[test]
fn a_switch_inside_a_nest_scope_works_on_the_nests_canvas() {
    let inner = two((1080, 1920)).value();
    let outer = json!({
        "version": 38,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
        "media": inner["media"], "tracks": [{"id": 6, "name": "T"}],
        "clips": [{"id": 5, "track": 6, "start": 0, "duration": 60 * SEC,
                   "source": {"kind": "nest", "project": 7}, "video": {}}],
        "markers": [], "next_id": 100,
        "nests": [{"id": 7, "name": "N", "width": 1080, "height": 1920,
                   "tracks": inner["tracks"], "clips": inner["clips"]}]
    });
    let mut op = switch(json!({"camera": 20, "layout": "stacked", "at": 2 * SEC}));
    op["scope"] = json!(7);
    let after = Handle::from_value(&outer).apply(&op).value();
    let camera = after["nests"][0]["clips"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == 20)
        .unwrap()
        .clone();
    let (want, _) = oracle(
        "stacked",
        (1080.0, 1920.0),
        (1280.0, 720.0),
        (1920.0, 1080.0),
    );
    same(
        read(&camera["actions"][0]["end"]["video"]),
        want,
        "the nest's canvas",
    );
}

#[test]
fn one_op_is_one_answer_and_the_input_is_untouched() {
    let base = two((1920, 1080));
    let text = base.to_json();
    match base
        .try_apply(&switch(
            json!({"camera": 20, "layout": "stacked", "at": 2 * SEC}),
        ))
        .unwrap()
    {
        Outcome::Applied(_) => {}
        other => panic!("{other:?}"),
    }
    assert_eq!(base.to_json(), text);
}
