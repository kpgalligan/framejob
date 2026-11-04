//! `follow: cursor` (road map "creator-jobs" VR5, spec §11 VR-50, VR-51):
//! the planner through `plan_cursor_framing`, and the op's refusals through
//! the FFI. Every expected key is worked by hand from the decisions'
//! figures, never read back from the code.
//!
//! The usual fixture: a 1920 × 1080 media with a cursor file, the clip at
//! scale 1, x = y = 0, no crop, 10 s on a 1080 × 1920 canvas at 30 fps (a
//! frame is 20 000 ticks). Then k = 16/9, the window is 607.5 × 1080 source
//! px, its centre's x clamped to 303.75…1616.25 and its y held at 540 (so
//! every key's y is 0); a key's x is `k·(960 − cx)` for a window centred at
//! cx. `CURSOR_TUNING` (0.20, 0.12, 0.8): a dead zone of 121.5 px, 486 px a
//! second, a move at least 0.4 s. Points are every 100 ms (60 000 ticks).

mod common;

use framejob_core::edit_reframe::{cursor_not_faces, no_cursor_file, no_subjects};
use framejob_core::model::{Curve, Project};
use framejob_core::reframe::FramingPath;
use framejob_core::reframe_cursor::plan_cursor_framing;
use framejob_core::reframe_subjects::CursorPoint;
use serde_json::{json, Value};

use common::{by_id, Handle};

const SEC: i64 = 600_000;
const STEP: i64 = 60_000;
const K: f64 = 1920.0 / 1080.0;
const W: f64 = 607.5;

fn project_json(canvas: (u32, u32), clip: Value) -> Value {
    let mut c = json!({"id": 3, "track": 6, "start": 0, "duration": 10 * SEC,
                       "source": {"kind": "media", "media": 1, "in": 0}, "video": {}});
    for (k, v) in clip.as_object().unwrap() {
        c[k] = v.clone();
    }
    json!({
        "canvas": {"width": canvas.0, "height": canvas.1, "fps": [30, 1]},
        "media": [
            {"id": 1, "path": "/m.mov", "kind": "video", "duration": 20 * SEC,
             "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true,
             "cursor": {"path": "/m.fjcursor", "in_picture": false}},
            {"id": 2, "path": "/n.mov", "kind": "video", "duration": 20 * SEC,
             "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true}
        ],
        "tracks": [{"id": 5}, {"id": 6}, {"id": 7}],
        "clips": [c],
        "nests": [
            {"id": 50, "name": "Nest", "width": 1920, "height": 1080,
             "tracks": [{"id": 51}],
             "clips": [{"id": 52, "track": 51, "start": 0, "duration": 3 * SEC,
                        "source": {"kind": "media", "media": 1, "in": 0}, "video": {}}]}
        ],
        "next_id": 100
    })
}

fn project(canvas: (u32, u32), clip: Value) -> Project {
    serde_json::from_value(project_json(canvas, clip)).unwrap()
}

fn tall(clip: Value) -> Project {
    project((1080, 1920), clip)
}

fn point(t: i64, x: f64) -> CursorPoint {
    CursorPoint {
        t,
        x: x / 1920.0,
        y: 0.5,
        click: false,
        typing: false,
    }
}

/// Media points every 100 ms over `[from, to]` s at x px `x(s)`.
fn points(from: f64, to: f64, x: impl Fn(f64) -> f64) -> Vec<CursorPoint> {
    let (a, b) = ((from * 10.0).round() as i64, (to * 10.0).round() as i64);
    (a..=b)
        .map(|n| point(n * STEP, x(n as f64 / 10.0)))
        .collect()
}

fn plan(p: &Project, pts: &[CursorPoint], zoom: f64) -> FramingPath {
    plan_cursor_framing(p, 3, pts, zoom).expect("a path")
}

fn key_x(cx: f64) -> f64 {
    K * (960.0 - cx)
}

fn close(a: f64, b: f64) -> bool {
    (a - b).abs() < 1e-6
}

/// The keys as (t, x), every y 0.
fn keys(path: &FramingPath) -> Vec<(i64, f64)> {
    for k in &path.keys {
        assert!(close(k.y, 0.0), "y {} at {}", k.y, k.t);
        assert!(close(k.scale, K), "scale {} at {}", k.scale, k.t);
    }
    path.keys.iter().map(|k| (k.t, k.x)).collect()
}

fn assert_keys(path: &FramingPath, want: &[(i64, f64)]) {
    let got = keys(path);
    assert_eq!(got.len(), want.len(), "keys {got:?}, want {want:?}");
    for (g, w) in got.iter().zip(want) {
        assert!(g.0 == w.0 && close(g.1, w.1), "keys {got:?}, want {want:?}");
    }
}

/// 600 px for 0–5 s, then a down click at 5 s on 1500 px, held there.
fn click_at_five() -> Vec<CursorPoint> {
    let mut pts = points(0.0, 10.0, |s| if s < 5.0 { 600.0 } else { 1500.0 });
    pts[50].click = true;
    pts
}

/// The click's arrival worked by hand: 900 px is 1.4815 W, 1.8519 s at 0.8
/// W a second, 1 111 111 ticks; planned from 3 000 000 − that = 1 888 889,
/// so it starts at the first point at or after it, 3.2 s (1 920 000).
fn click_keys() -> Vec<(i64, f64)> {
    vec![
        (0, key_x(600.0)),
        (1_920_000, key_x(600.0)),
        (3_000_000, key_x(1500.0)),
    ]
}

#[test]
fn a_still_cursor_holds_one_key_and_the_path_never_shows_fit() {
    let path = plan(&tall(json!({})), &points(0.0, 10.0, |_| 600.0), 1.0);
    assert_keys(&path, &[(0, key_x(600.0))]);
    assert!(!path.shows_fit);
    assert!(path.cuts.is_empty());
}

#[test]
fn a_step_inside_the_dead_zone_moves_nothing() {
    // 0.17 W is inside 0.20 W (a face's 0.15 W would move).
    let to = 600.0 + 0.17 * W;
    let path = plan(
        &tall(json!({})),
        &points(0.0, 10.0, |s| if s < 2.0 { 600.0 } else { to }),
        1.0,
    );
    assert_keys(&path, &[(0, key_x(600.0))]);
}

#[test]
fn a_step_outside_the_dead_zone_moves_in_the_shortest_move() {
    // 0.25 W: 0.3125 s at 0.8 W a second, so the 0.4 s floor, 2.0 → 2.4 s.
    let to = 600.0 + 0.25 * W;
    let path = plan(
        &tall(json!({})),
        &points(0.0, 10.0, |s| if s < 2.0 { 600.0 } else { to }),
        1.0,
    );
    assert_keys(
        &path,
        &[
            (0, key_x(600.0)),
            (1_200_000, key_x(600.0)),
            (1_440_000, key_x(to)),
        ],
    );
    assert_eq!(path.keys[2].curve, Curve::EaseInOut);
}

#[test]
fn a_click_arrives_on_its_frame_centred_on_it() {
    let path = plan(&tall(json!({})), &click_at_five(), 1.0);
    assert_keys(&path, &click_keys());
    assert_eq!(path.keys[2].curve, Curve::EaseInOut);
}

#[test]
fn a_click_past_the_edge_arrives_on_its_clamped_point() {
    let mut pts = points(0.0, 10.0, |s| if s < 5.0 { 600.0 } else { 1800.0 });
    pts[50].click = true;
    let path = plan(&tall(json!({})), &pts, 1.0);
    let last = keys(&path).last().copied().expect("a key");
    assert_eq!(last.0, 3_000_000);
    assert!(close(last.1, key_x(1616.25)), "{last:?}");
}

#[test]
fn a_running_move_shortens_an_arrival() {
    // 960 px to 1 s, 700 px to 2.9 s, a click at 3 s on 1500 px. The move
    // at 1 s: 260 px, 0.535 s, ending on 920 000. Its arrival from 700 px
    // would last 1.646 s, planned from 1.354 s, but no earlier than that
    // move's end, so it starts at the next point, 1.6 s, and lasts 1.4 s.
    let mut pts = points(0.0, 10.0, |s| {
        if s < 1.0 {
            960.0
        } else if s < 3.0 {
            700.0
        } else {
            1500.0
        }
    });
    pts[30].click = true;
    let path = plan(&tall(json!({})), &pts, 1.0);
    assert_keys(
        &path,
        &[
            (0, key_x(960.0)),
            (600_000, key_x(960.0)),
            (920_000, key_x(700.0)),
            (960_000, key_x(700.0)),
            (1_800_000, key_x(1500.0)),
        ],
    );
}

#[test]
fn a_typing_stretch_holds_the_window_and_the_move_follows_it() {
    // 600 px to 2 s, then typing from 2 s to 4 s while the pointer drifts to
    // 1000 px, held there after 4 s.
    let mut pts = points(0.0, 10.0, |s| {
        if s < 2.0 {
            600.0
        } else if s < 4.0 {
            600.0 + (s - 2.0) * 200.0
        } else {
            1000.0
        }
    });
    for p in &mut pts[20..40] {
        p.typing = true;
    }
    let path = plan(&tall(json!({})), &pts, 1.0);
    let got = keys(&path);
    assert!(
        got.iter().all(|&(t, _)| !(t > 1_200_000 && t < 2_400_000)),
        "a key inside the typing stretch: {got:?}"
    );
    assert!(
        got.iter().any(|&(t, _)| t > 2_400_000),
        "no move after it: {got:?}"
    );
    assert!(close(got.last().expect("a key").1, key_x(1000.0)));
}

#[test]
fn a_click_inside_a_typing_stretch_still_arrives() {
    let mut pts = click_at_five();
    for p in &mut pts[20..60] {
        p.typing = true;
    }
    assert_keys(&plan(&tall(json!({})), &pts, 1.0), &click_keys());
}

#[test]
fn a_clip_at_twice_the_speed_maps_the_points_into_clip_time() {
    // Media points every 200 ms over 0–19.8 s; the click at media 10 s is
    // clip 5 s.
    let mut pts: Vec<CursorPoint> = (0..100)
        .map(|n| point(n * 2 * STEP, if n < 50 { 600.0 } else { 1500.0 }))
        .collect();
    pts[50].click = true;
    let path = plan(&tall(json!({"speed": 2.0})), &pts, 1.0);
    assert_keys(&path, &click_keys());
}

#[test]
fn a_reversed_clip_maps_the_points_through_the_mirror() {
    // Reversed over the 20 s media from in 0, clip tick c plays media
    // 20 s − c: media 10.1–15 s (clip 5–9.9 s) at 1500 px, the click at media
    // 15 s (clip 5 s), media 15.1–20 s (clip 0–4.9 s) at 600 px.
    let mut pts = points(10.1, 20.0, |s| if s <= 15.0 { 1500.0 } else { 600.0 });
    let click = pts.iter().position(|p| p.t == 15 * SEC).expect("15 s");
    pts[click].click = true;
    let path = plan(
        &tall(json!({"source": {"kind": "media", "media": 1, "in": 0, "reversed": true}})),
        &pts,
        1.0,
    );
    assert_keys(&path, &click_keys());
}

#[test]
fn at_zoom_two_on_a_wide_canvas_a_click_arrives_on_its_clamped_point() {
    // 1920 × 1080 at zoom 2: k = 2, a 960 × 540 window, its x clamped to
    // 480…1440. 600 → 1440 is 840 px, 0.875 W, 1.094 s: planned from 3.906
    // s, so it starts at 4.0 s.
    let mut pts = points(0.0, 10.0, |s| if s < 5.0 { 600.0 } else { 1700.0 });
    pts[50].click = true;
    let path = plan(&project((1920, 1080), json!({})), &pts, 2.0);
    let got: Vec<(i64, f64, f64, f64)> =
        path.keys.iter().map(|k| (k.t, k.scale, k.x, k.y)).collect();
    let want = [
        (0, 2.0, 2.0 * 360.0, 0.0),
        (2_400_000, 2.0, 2.0 * 360.0, 0.0),
        (3_000_000, 2.0, 2.0 * (960.0 - 1440.0), 0.0),
    ];
    assert_eq!(got.len(), want.len(), "{got:?}");
    for (g, w) in got.iter().zip(&want) {
        assert!(
            g.0 == w.0 && close(g.1, w.1) && close(g.2, w.2) && close(g.3, w.3),
            "{got:?}"
        );
    }
}

// ---- the op, through the FFI ------------------------------------------------

fn handle(clip: Value) -> Handle {
    Handle::from_value(&project_json((1080, 1920), clip))
}

fn cursor_json(pts: &[CursorPoint]) -> Value {
    json!({"samples": [], "shots": [], "cursor": pts})
}

fn reframe(args: Value) -> Value {
    let mut op = json!({"op": "reframe_clip", "clip": 3});
    for (k, v) in args.as_object().unwrap() {
        op[k] = v.clone();
    }
    op
}

#[test]
fn the_new_sentences_are_the_ones_the_app_lists() {
    assert_eq!(
        no_cursor_file(7),
        "clip 7's media has no cursor file, so there is no cursor to follow; frame it with \
         subject, center, fit or keep"
    );
    assert_eq!(
        cursor_not_faces(7),
        "clip 7's media has a cursor file, so it follows the cursor, not faces; frame it with \
         cursor, center, fit or keep"
    );
}

#[test]
fn the_op_writes_the_cursor_path_and_ignores_where_empty_and_backdrop() {
    let h = handle(json!({}));
    let next = h.apply(&reframe(json!({
        "follow": "cursor", "where_empty": "center", "backdrop": 5,
        "subjects": cursor_json(&click_at_five())
    })));
    let v = next.value();
    assert_eq!(v["clips"].as_array().unwrap().len(), 1, "no backdrop copy");
    let clip = by_id(&v, "/clips", 3);
    assert!(close(clip["video"]["x"].as_f64().unwrap(), key_x(600.0)));
    let actions = clip["actions"].as_array().expect("actions");
    assert!(actions.iter().any(|a| {
        a["start"].as_i64().unwrap() + a["duration"].as_i64().unwrap() == 3_000_000
            && close(a["end"]["video"]["x"].as_f64().unwrap(), key_x(1500.0))
    }));
}

#[test]
fn every_new_refusal_in_its_order() {
    let ok = cursor_json(&click_at_five());
    // A media with no cursor file (clip 3 on media 2).
    let plain = handle(json!({"source": {"kind": "media", "media": 2, "in": 0}}));
    plain.refuses_with(
        &reframe(json!({"follow": "cursor", "subjects": ok})),
        &no_cursor_file(3),
    );
    // A face follow on the clip with a cursor file, with or without subjects.
    let h = handle(json!({}));
    for follow in ["subject", "face", "person", "salient"] {
        h.refuses_with(&reframe(json!({"follow": follow})), &cursor_not_faces(3));
    }
    // A nest and a still keep their sentences, before VR-50's and VR-51's.
    let nest = handle(json!({"source": {"kind": "nest", "project": 50}}));
    nest.refuses_with(
        &reframe(json!({"follow": "cursor"})),
        "clip 3 shows a nest, which has no subjects to follow; frame it with center, fit or keep",
    );
    let still = handle(json!({"source": {"kind": "still", "media": 1, "at": 0}}));
    still.refuses_with(
        &reframe(json!({"follow": "cursor"})),
        "clip 3 shows a still picture, which has no subjects to follow; frame it with center, \
         fit or keep",
    );
    // Both come before the matte refusal.
    let matte = h.apply(&json!({"op": "set_track", "track": 6, "matte": "alpha"}));
    matte.refuses_with(&reframe(json!({"follow": "face"})), &cursor_not_faces(3));
    let plain_matte = plain.apply(&json!({"op": "set_track", "track": 6, "matte": "alpha"}));
    plain_matte.refuses_with(&reframe(json!({"follow": "cursor"})), &no_cursor_file(3));
    // No subjects, and no point in the played window, last.
    h.refuses_with(&reframe(json!({"follow": "cursor"})), &no_subjects(3));
    let late = points(19.0, 19.9, |_| 600.0);
    h.refuses_with(
        &reframe(json!({"follow": "cursor", "subjects": cursor_json(&late)})),
        &no_subjects(3),
    );
    // Center, fit and keep frame a cursor clip.
    for follow in ["center", "fit", "keep"] {
        let _ = h
            .try_apply(&reframe(json!({"follow": follow, "from_width": 1920,
                                            "from_height": 1080})))
            .expect("valid");
    }
}

#[test]
fn bad_cursor_values_are_refused_naming_the_point() {
    let h = handle(json!({}));
    let at = |pts: Value| {
        reframe(json!({"follow": "cursor",
        "subjects": {"samples": [], "shots": [], "cursor": pts}}))
    };
    h.refuses_with(
        &at(json!([{"t": 0, "x": 0.5, "y": 0.5}, {"t": 0, "x": 0.5, "y": 0.5}])),
        "subjects cursor[1] is at 0, not after the one before it (0); cursor times must be \
         strictly increasing",
    );
    h.refuses_with(
        &at(json!([{"t": 0, "x": 1.5, "y": 0.5}])),
        "subjects cursor[0].x is 1.5, outside 0…1",
    );
    h.refuses_with(
        &at(json!([{"t": 0, "x": 0.5, "y": -0.25}])),
        "subjects cursor[0].y is -0.25, outside 0…1",
    );
    let many: Vec<Value> = (0..100_001)
        .map(|n| json!({"t": n, "x": 0.5, "y": 0.5}))
        .collect();
    h.refuses_with(
        &at(Value::Array(many)),
        "subjects holds 100001 cursor points, more than 100000",
    );
    // The reader: an object at every level, a stray member named.
    let err = h.errors(&at(json!([1])));
    assert!(err.contains("subjects.cursor[0]"), "{err}");
    let err = h.errors(&at(json!([{"t": 0, "x": 0.5, "y": 0.5, "z": 1}])));
    assert!(
        err.contains("subjects.cursor[0]") && err.contains('z'),
        "{err}"
    );
}

#[test]
fn a_face_follow_never_reads_the_cursor() {
    // On a media with no cursor file, a face path is the same with or without
    // cursor points beside its samples.
    let h = handle(json!({"source": {"kind": "media", "media": 2, "in": 0}}));
    let samples: Vec<Value> = (0..=100)
        .map(|n| {
            json!({"t": n * STEP, "faces": [
            {"x": (if n < 50 { 500.0 } else { 1300.0 }) / 1920.0 - 0.04, "y": 0.33,
             "w": 0.08, "h": 0.14, "c": 0.9}]})
        })
        .collect();
    let bare = json!({"samples": samples, "shots": []});
    let mut with = bare.clone();
    with["cursor"] = json!(click_at_five());
    let a = h.apply(&reframe(json!({"follow": "face", "subjects": bare})));
    let b = h.apply(&reframe(json!({"follow": "face", "subjects": with})));
    assert_eq!(a.value(), b.value());
}
