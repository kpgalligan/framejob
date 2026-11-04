//! VR-27 — a framing composed into a clip that already moves (road map
//! "creator-jobs" VR2b1, spec §11 VR-27): the planner reading the placement
//! in force, the base and ends composed, cuts splitting the action they land
//! in, moves scheduled around actions, the counts and their recount,
//! `replace`, `keep` on ends, and the backdrop copy's speed actions. Black
//! box, through `reframe_clip` over the FFI and through the public planner
//! and `composed` for the counts. Every expectation is worked by hand from
//! the decision's figures.
//!
//! The fixture is `reframe_clip.rs`': a 1080 × 1920 canvas at 30 fps (a
//! frame is 20 000 ticks), a 1920 × 1080 video media 20 s long, tracks 5, 6
//! and 7, clip 10 on track 6 from 0 for 10 s at scale 1, x = y = 0. With
//! zoom 1 the window is 607.5 × 1080 source px at k = K = 16/9, its centre's
//! x clamped to −116.25…1196.25 and its y to 960; a face at x px of the
//! picture lies at source x `x − 420`, so a still one puts the base at
//! `x′ = K·(960 − x)`. Samples every 100 ms; faces 0.2 × 0.14 of the
//! picture.

mod common;

use framejob_core::edit_reframe::{FramingFollow, Reframe};
use framejob_core::model::{Action, Curve, Project};
use framejob_core::reframe::{
    fixed_framing, plan_framing, FramingKey, FramingPath, FramingRequest, Subjects, WhereEmpty,
    FRAMING_TUNING,
};
use framejob_core::reframe_compose::{Composed, SHIFT_MAX};
use framejob_core::reframe_tracks::Follow;
use serde_json::{json, Value};

use common::{array, by_id, num, Handle};

const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;
const K: f64 = 1920.0 / 1080.0;

fn document(clip: Value) -> Value {
    let mut c = json!({"id": 10, "track": 6, "start": 0, "duration": 10 * SEC,
                       "source": {"kind": "media", "media": 1, "in": 0},
                       "video": {}, "audio": {}});
    for (k, v) in clip.as_object().unwrap() {
        c[k] = v.clone();
    }
    json!({
        "canvas": {"width": 1080, "height": 1920, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/m.mov", "kind": "video", "duration": 20 * SEC,
                   "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true,
                   "has_audio": true}],
        "tracks": [{"id": 5}, {"id": 6}, {"id": 7}],
        "clips": [c],
        "next_id": 100
    })
}

fn handle(clip: Value) -> Handle {
    Handle::from_value(&document(clip))
}

fn project(clip: Value) -> Project {
    serde_json::from_value(document(clip)).unwrap()
}

fn face(x: f64) -> Value {
    json!({"x": x / 1920.0 - 0.1, "y": 0.33, "w": 0.2, "h": 0.14, "c": 0.9})
}

/// `subjects` every 100 ms over [0, 10] s of the media, with `shots`.
fn subjects(shots: Vec<i64>, faces: impl Fn(f64) -> f64) -> Value {
    let samples: Vec<Value> = (0..=100)
        .map(|n| json!({"t": n * 60_000, "faces": [face(faces(n as f64 / 10.0))]}))
        .collect();
    json!({"samples": samples, "shots": shots})
}

fn plan(p: &Project, s: &Value) -> FramingPath {
    let subjects: Subjects = serde_json::from_value(s.clone()).unwrap();
    let request = FramingRequest {
        follow: Follow::Face,
        zoom: 1.0,
        from_width: 1080,
        from_height: 1920,
        where_empty: WhereEmpty::Fit,
    };
    plan_framing(p, 10, &subjects, &request, &FRAMING_TUNING).unwrap()
}

fn reframe(args: Value) -> Value {
    let mut op = json!({"op": "reframe_clip", "clip": 10});
    for (k, v) in args.as_object().unwrap() {
        op[k] = v.clone();
    }
    op
}

fn clip(h: &Handle) -> Value {
    by_id(&h.value(), "/clips", 10).clone()
}

fn close(a: f64, b: f64) -> bool {
    (a - b).abs() < 1e-6
}

fn placement(v: &Value) -> (f64, f64, f64) {
    (num(v, "/scale"), num(v, "/x"), num(v, "/y"))
}

fn assert_placement(got: (f64, f64, f64), want: (f64, f64, f64)) {
    assert!(
        close(got.0, want.0) && close(got.1, want.1) && close(got.2, want.2),
        "placement {got:?}, want {want:?}"
    );
}

fn action(p: &Project, id: u32) -> &Action {
    p.clip(10)
        .unwrap()
        .actions
        .iter()
        .find(|a| a.id == id)
        .unwrap()
}

#[test]
fn an_existing_zoom_is_composed_with_one_framing() {
    // A zoom on the face that keeps it at source x 180 (x = 360·(s − 1)):
    // F is (K, 360K, 0) throughout, so the end is F∘old.
    let h = handle(
        json!({"actions": [{"id": 91, "start": 2 * SEC, "duration": SEC,
        "curve": "ease_in_out",
        "end": {"video": {"scale": 1.5, "x": 180.0}, "audio": {"volume": 0.5}}}]}),
    );
    let after = h.apply(&reframe(
        json!({"follow": "face", "subjects": subjects(vec![], |_| 600.0)}),
    ));
    let c = clip(&after);
    assert_placement(placement(&c["video"]), (K, 360.0 * K, 0.0));
    let actions = array(&c, "/actions");
    assert_eq!(actions.len(), 1, "{actions:?}");
    let a = &actions[0];
    assert_eq!(a["id"], 91);
    assert_placement(placement(&a["end"]["video"]), (1.5 * K, 540.0 * K, 0.0));
    assert_eq!(a["end"]["audio"], json!({"volume": 0.5}));
    assert_eq!(
        (a["start"].as_i64(), a["duration"].as_i64()),
        (Some(2 * SEC), Some(SEC))
    );
}

#[test]
fn a_subject_under_a_held_zoom_is_followed_through_it() {
    // A centred zoom to 1.5 over [2, 3] s moves the face (picture x 600) to
    // source x 0; the window follows it there, so at 9 s the face is within
    // the dead zone (0.15 × 607.5 source px, 162 target px) of the canvas's
    // centre. Read from the base only it would sit at 220 px, 320 off.
    let h = handle(
        json!({"actions": [{"id": 91, "start": 2 * SEC, "duration": SEC,
        "curve": "ease_in_out", "end": {"video": {"scale": 1.5}}}]}),
    );
    let after = h.apply(&reframe(
        json!({"follow": "face", "subjects": subjects(vec![], |_| 600.0)}),
    ));
    let state = after.clip_state(10, 9 * SEC).unwrap();
    let (s, x, _) = placement(&state["video"]);
    let face_x = 540.0 + x + s * (600.0 - 960.0);
    assert!((face_x - 540.0).abs() <= 162.0, "face at {face_x}");
}

#[test]
fn a_y_pan_raises_k_until_the_window_fits_the_common_rect() {
    // Base scale 1.2 (2304 × 1296 px, y 312…1608); the action ends at
    // y = 100 (412…1708): the common rect is 1196 px tall, under the 1296 px
    // window k = fill/1.2 would give, so k becomes 1920/1196. At the base
    // and at the action's end the composed picture covers the canvas.
    let h = handle(
        json!({"video": {"scale": 1.2}, "actions": [{"id": 91, "start": SEC,
        "duration": SEC, "end": {"video": {"y": 100.0}}}]}),
    );
    let after = h.apply(&reframe(json!({"follow": "center"})));
    let c = clip(&after);
    let covers = |(s, x, y): (f64, f64, f64)| {
        let (l, r) = (540.0 + x - s * 960.0, 540.0 + x + s * 960.0);
        let (t, b) = (960.0 + y - s * 540.0, 960.0 + y + s * 540.0);
        assert!(
            l <= 1e-6 && r >= 1080.0 - 1e-6 && t <= 1e-6 && b >= 1920.0 - 1e-6,
            "({l}, {t})…({r}, {b}) at {s}, {x}, {y}"
        );
    };
    covers(placement(&c["video"]));
    let end = &array(&c, "/actions")[0]["end"]["video"];
    covers(placement(end));
    assert!(close(num(&c, "/video/scale"), 1.2 * 1920.0 / 1196.0));
}

/// A cut at 4 s onto a face at picture x 1300 (source 880, x′ = −340K).
fn cut_subjects() -> Value {
    subjects(vec![4 * SEC], |t| {
        if t < 1.0 {
            600.0
        } else if t < 4.0 {
            800.0
        } else {
            1300.0
        }
    })
}

#[test]
fn cuts_split_first_then_the_head_carries_the_move() {
    // An eased volume action over the whole clip; a move at 1 s (to source
    // x 380, x′ = 160K) and a cut at 4 s. The cut splits the action into a
    // head [0, c − frame], a linear cut piece and a tail; the move overlaps
    // the head, which carries it to its end.
    let c = 4 * SEC;
    let doc = json!({"actions": [{"id": 91, "start": 0, "duration": 10 * SEC,
        "curve": "ease_in_out", "end": {"audio": {"volume": 0.2}}}]});
    let p = project(doc.clone());
    let path = plan(&p, &cut_subjects());
    assert!(
        path.keys.iter().any(|k| k.t > SEC && k.t < 2 * SEC),
        "{path:?}"
    );
    assert_eq!(path.cuts, vec![c]);
    let (after, counts) = p.composed(10, &path);
    assert_eq!(
        counts,
        Composed {
            re_eased: 1,
            carried: 1
        }
    );
    let before = p.clip(10).unwrap();
    let volume = |t: i64| p.evaluate_clip(before, t).audio.volume;
    let actions = &after.clip(10).unwrap().actions;
    assert_eq!(actions.len(), 3, "{actions:?}");
    let (head, cut, tail) = (&actions[0], &actions[1], &actions[2]);
    assert_eq!((head.id, head.start, head.duration), (91, 0, c - FRAME));
    assert_eq!(head.curve, Curve::EaseInOut);
    assert_placement(placement(&head.end["video"]), (K, 160.0 * K, 0.0));
    assert!(close(
        head.end["audio"]["volume"].as_f64().unwrap(),
        volume(c - FRAME)
    ));
    assert_eq!(
        (cut.start, cut.duration, cut.curve),
        (c - FRAME, FRAME, Curve::Linear)
    );
    assert_placement(placement(&cut.end["video"]), (K, -340.0 * K, 0.0));
    assert!(close(
        cut.end["audio"]["volume"].as_f64().unwrap(),
        volume(c)
    ));
    assert_eq!(
        (tail.start, tail.duration, tail.curve),
        (c, 6 * SEC, Curve::EaseInOut)
    );
    assert_eq!(tail.end, json!({"audio": {"volume": 0.2}}));
    // The tail holds the new shot's framing; the ids are fresh, in time order.
    assert!(cut.id >= 100 && tail.id > cut.id);
    let state = after.evaluate_clip(after.clip(10).unwrap(), 6 * SEC).video;
    assert_placement((state.scale, state.x, state.y), (K, -340.0 * K, 0.0));
    // The op writes the same project.
    let h = handle(doc);
    let op = h.apply(&reframe(
        json!({"follow": "face", "subjects": cut_subjects()}),
    ));
    assert_eq!(serde_json::to_value(&after).unwrap(), op.value());
}

#[test]
fn a_linear_volume_action_plays_unchanged_across_a_split() {
    let doc = json!({"actions": [{"id": 91, "start": 0, "duration": 10 * SEC,
        "end": {"audio": {"volume": 0.2}}}]});
    let p = project(doc);
    let (after, counts) = p.composed(10, &plan(&p, &cut_subjects()));
    assert_eq!(counts.re_eased, 0);
    assert_eq!(after.clip(10).unwrap().actions.len(), 3);
    let (b, a) = (p.clip(10).unwrap(), after.clip(10).unwrap());
    for t in (0..=10 * SEC).step_by(FRAME as usize) {
        let (x, y) = (
            p.evaluate_clip(b, t).audio.volume,
            after.evaluate_clip(a, t).audio.volume,
        );
        assert!((x - y).abs() < 1e-9, "volume at {t}: {x} then {y}");
    }
}

#[test]
fn an_eased_action_split_at_a_cut_is_re_eased() {
    let doc = json!({"actions": [{"id": 91, "start": 3 * SEC, "duration": 2 * SEC,
        "curve": "ease_in", "end": {"audio": {"volume": 0.2}}}]});
    let p = project(doc);
    let (after, counts) = p.composed(10, &plan(&p, &cut_subjects()));
    assert_eq!(counts.re_eased, 1);
    let actions = &after.clip(10).unwrap().actions;
    let ours: Vec<(i64, i64, Curve)> = actions
        .iter()
        .filter(|a| a.start >= 3 * SEC)
        .map(|a| (a.start, a.duration, a.curve))
        .collect();
    assert_eq!(
        ours,
        vec![
            (3 * SEC, SEC - FRAME, Curve::EaseIn),
            (4 * SEC - FRAME, FRAME, Curve::Linear),
            (4 * SEC, SEC, Curve::EaseIn)
        ]
    );
    assert_eq!(action(&after, 91).duration, SEC - FRAME);
}

#[test]
fn a_speed_action_is_never_split_and_carries_the_cut() {
    let doc = json!({"actions": [{"id": 91, "start": 0, "duration": 10 * SEC,
        "end": {"speed": 1.5}}]});
    let p = project(doc);
    let path = plan(&p, &cut_subjects());
    assert!(!path.cuts.is_empty());
    let (after, counts) = p.composed(10, &path);
    assert_eq!(counts.carried, 1);
    let actions = &after.clip(10).unwrap().actions;
    assert_eq!(actions.len(), 1, "{actions:?}");
    let a = &actions[0];
    assert_eq!((a.id, a.start, a.duration), (91, 0, 10 * SEC));
    assert_eq!(a.end["speed"], json!(1.5));
    assert!(names_all(&a.end));
}

/// No two of the clip's actions overlap (touching allowed).
fn no_overlap(p: &Project) {
    let actions = &p.clip(10).unwrap().actions;
    for w in actions.windows(2) {
        assert!(w[0].start + w[0].duration <= w[1].start, "{actions:?}");
    }
}

#[test]
fn an_action_edge_inside_the_cut_frame_bounds_its_pieces() {
    // Ticks off the frame grid (a 1 s action on 29.97 fps footage): A ends,
    // and B starts, halfway through the cut frame [c - frame, c]. A's
    // pieces stay inside A, so B is untouched and nothing overlaps.
    let (c, edge) = (4 * SEC, 4 * SEC - FRAME / 2);
    let doc = json!({"actions": [
        {"id": 91, "start": 0, "duration": edge, "end": {"audio": {"volume": 0.2}}},
        {"id": 92, "start": edge, "duration": 6 * SEC - edge,
         "end": {"audio": {"volume": 0.5}}}]});
    let p = project(doc.clone());
    let path = plan(&p, &cut_subjects());
    assert_eq!(path.cuts, vec![c]);
    let (after, _) = p.composed(10, &path);
    no_overlap(&after);
    let spans: Vec<(i64, i64, Curve)> = after
        .clip(10)
        .unwrap()
        .actions
        .iter()
        .filter(|a| a.start + a.duration <= edge)
        .map(|a| (a.start, a.start + a.duration, a.curve))
        .collect();
    assert_eq!(
        spans,
        vec![
            (0, c - FRAME, Curve::Linear),
            (c - FRAME, edge, Curve::Linear)
        ]
    );
    assert_eq!(action(&after, 91).duration, c - FRAME);
    let b = action(&after, 92);
    assert_eq!((b.start, b.duration), (edge, 6 * SEC - edge));
    let (before, a) = (p.clip(10).unwrap(), after.clip(10).unwrap());
    for t in (0..=10 * SEC).step_by(FRAME as usize) {
        let (x, y) = (
            p.evaluate_clip(before, t).audio.volume,
            after.evaluate_clip(a, t).audio.volume,
        );
        assert!((x - y).abs() < 1e-9, "volume at {t}: {x} then {y}");
    }
    let state = |t: i64| {
        let v = after.evaluate_clip(a, t).video;
        (v.scale, v.x, v.y)
    };
    assert_placement(state(c - FRAME), (K, 160.0 * K, 0.0));
    assert_placement(state(c), (K, -340.0 * K, 0.0));
    let op = handle(doc).apply(&reframe(
        json!({"follow": "face", "subjects": cut_subjects()}),
    ));
    assert_eq!(serde_json::to_value(&after).unwrap(), op.value());

    // B alone, starting inside the cut frame: no head, its cut piece
    // [edge, c] keeps its id and is F''s own segment, the tail is fresh.
    let doc = json!({"actions": [{"id": 92, "start": edge, "duration": 6 * SEC - edge,
        "end": {"audio": {"volume": 0.5}}}]});
    let p = project(doc);
    let (after, counts) = p.composed(10, &plan(&p, &cut_subjects()));
    assert_eq!(counts.carried, 0);
    no_overlap(&after);
    let cut = action(&after, 92);
    assert_eq!(
        (cut.start, cut.duration, cut.curve),
        (edge, FRAME / 2, Curve::Linear)
    );
    assert!(after
        .clip(10)
        .unwrap()
        .actions
        .iter()
        .any(|x| x.id != 92 && x.start == c && x.start + x.duration == 6 * SEC));
    let a = after.clip(10).unwrap();
    let v = after.evaluate_clip(a, c).video;
    assert_placement((v.scale, v.x, v.y), (K, -340.0 * K, 0.0));
}

fn names_all(end: &Value) -> bool {
    ["scale", "x", "y"]
        .iter()
        .all(|k| end["video"][k].is_number())
}

#[test]
fn an_action_past_the_clips_end_is_not_split() {
    // Left running to 12 s by a trim: carried, its span kept.
    let doc = json!({"actions": [{"id": 91, "start": 2 * SEC, "duration": 10 * SEC,
        "end": {"audio": {"volume": 0.5}}}]});
    let p = project(doc);
    let (after, counts) = p.composed(10, &plan(&p, &cut_subjects()));
    assert_eq!(counts.carried, 1);
    let actions = &after.clip(10).unwrap().actions;
    let a = action(&after, 91);
    assert_eq!((a.start, a.duration), (2 * SEC, 10 * SEC));
    assert!(names_all(&a.end));
    assert!(actions
        .iter()
        .all(|x| x.id == 91 || x.start + x.duration <= 2 * SEC));
}

fn key(t: i64, x: f64, curve: Curve) -> FramingKey {
    FramingKey {
        t,
        scale: K,
        x,
        y: 0.0,
        curve,
    }
}

/// A hand path: hold to 2.8 s, then one move to x 100 ending at `to`.
fn one_move(to: i64) -> FramingPath {
    FramingPath {
        keys: vec![
            key(0, 0.0, Curve::Linear),
            key(2 * SEC + 480_000, 0.0, Curve::Linear),
            key(to, 100.0, Curve::EaseInOut),
        ],
        shows_fit: false,
        cuts: vec![],
    }
}

#[test]
fn a_move_is_shifted_by_half_a_second_at_most_else_carried() {
    let p = project(
        json!({"actions": [{"id": 91, "start": 3 * SEC, "duration": SEC,
        "end": {"audio": {"volume": 0.5}}}]}),
    );
    // 2.8 → 3.4 s overlaps [3, 4) s: shifted 0.4 s to end at 3 s.
    let (after, counts) = p.composed(10, &one_move(3 * SEC + 240_000));
    assert_eq!(counts, Composed::default());
    let actions = &after.clip(10).unwrap().actions;
    assert_eq!(actions.len(), 2, "{actions:?}");
    let moved = &actions[0];
    assert_eq!((moved.start, moved.duration), (3 * SEC - 360_000, 360_000));
    assert_eq!(moved.curve, Curve::EaseInOut);
    assert_placement(placement(&moved.end["video"]), (K, 100.0, 0.0));
    assert_eq!(action(&after, 91).end, json!({"audio": {"volume": 0.5}}));
    // 2.8 → 3.6 s would need 0.6 s: carried by the action instead.
    const { assert!(360_000 > SHIFT_MAX) };
    let (after, counts) = p.composed(10, &one_move(3 * SEC + 360_000));
    assert_eq!(counts.carried, 1);
    let actions = &after.clip(10).unwrap().actions;
    assert_eq!(actions.len(), 1, "{actions:?}");
    assert_placement(placement(&actions[0].end["video"]), (K, 100.0, 0.0));
    assert_eq!(actions[0].end["audio"], json!({"volume": 0.5}));
}

#[test]
fn replace_strips_placement_keys_keeps_volume_and_fits_the_base() {
    let h = handle(json!({"video": {"scale": 2.0, "x": 40.0}, "actions": [
        {"id": 91, "start": SEC, "duration": SEC,
         "end": {"video": {"scale": 2.0, "x": 10.0}, "audio": {"volume": 0.5}}},
        {"id": 92, "start": 3 * SEC, "duration": SEC, "end": {"video": {"x": 50.0}}}]}));
    let after = h.apply(&reframe(json!({"follow": "fit", "replace": true})));
    let c = clip(&after);
    assert_placement(placement(&c["video"]), (0.5625, 0.0, 0.0));
    let actions = array(&c, "/actions");
    assert_eq!(actions.len(), 1, "{actions:?}");
    assert_eq!(actions[0]["id"], 91);
    assert_eq!(actions[0]["end"], json!({"audio": {"volume": 0.5}}));
    // `replace: false` is the default: the ends are composed, both kept.
    let kept = h.apply(&reframe(json!({"follow": "fit", "replace": false})));
    assert_eq!(array(&clip(&kept), "/actions").len(), 2);
}

#[test]
fn under_replace_the_counts_and_their_recount_agree() {
    // VR-27 (f): no move or cut inside the action, so nothing is carried,
    // and the recount reads the AFTER handle's placement across it.
    let doc = json!({"actions": [{"id": 91, "start": 2 * SEC, "duration": SEC,
        "end": {"video": {"scale": 2.0}, "audio": {"volume": 0.5}}}]});
    let p = project(doc);
    let stripped = p.replaced(10);
    let path = fixed_framing(&stripped, 10, WhereEmpty::Center, 1.0).unwrap();
    let (after, counts) = stripped.composed(10, &path);
    assert_eq!(counts.carried, 0);
    let op = p
        .reframe_clip(&Reframe {
            clip: 10,
            follow: FramingFollow::Center,
            zoom: None,
            where_empty: None,
            from_width: None,
            from_height: None,
            backdrop: None,
            replace: Some(true),
            mics: None,
            mic_faces: None,
            subjects: None,
        })
        .unwrap();
    let framejob_core::Outcome::Applied(applied) = op else {
        panic!("not applied")
    };
    assert_eq!(applied, after);
    let (b, a) = (p.clip(10).unwrap(), after.clip(10).unwrap());
    let recount = b
        .actions
        .iter()
        .filter_map(|x| {
            a.actions
                .iter()
                .find(|y| y.id == x.id && y.start == x.start && y.duration == x.duration)
        })
        .filter(|y| {
            let at = |t: i64| after.evaluate_clip(a, t).video;
            let (s, e) = (at(y.start), at(y.start + y.duration));
            (s.scale - e.scale).abs() > 1e-6 || (s.x - e.x).abs() > 1e-6 || (s.y - e.y).abs() > 1e-6
        })
        .count();
    assert_eq!(recount, 0);
}

#[test]
fn keep_rescales_the_ends_it_names() {
    // keep from 2160 × 1920: x × 0.5, y × 1, scale × 0.5.
    let h = handle(
        json!({"video": {"x": 40.0}, "actions": [{"id": 91, "start": SEC,
        "duration": SEC, "end": {"video": {"x": 100.0, "scale": 2.0}, "audio": {"volume": 0.5}}}]}),
    );
    let after = h.apply(&reframe(json!({"follow": "keep", "from_width": 2160})));
    let c = clip(&after);
    assert!(close(num(&c, "/video/x"), 20.0));
    let end = &array(&c, "/actions")[0]["end"];
    assert_eq!(
        end,
        &json!({"video": {"x": 50.0, "scale": 1.0}, "audio": {"volume": 0.5}})
    );
}

#[test]
fn an_action_free_clip_is_written_as_vr2a2_wrote_it() {
    // The oracle is VR-26's writing: key 0 composed into the base, one
    // action per later change of value with the end `{video: {scale, x,
    // y}}`, ids from `next_id` in time order.
    let s = subjects(vec![6 * SEC], |t| {
        if t < 2.0 {
            600.0
        } else if t < 6.0 {
            700.0
        } else {
            1300.0
        }
    });
    let p = project(json!({"video": {"x": 12.0, "y": -8.0, "scale": 1.1}}));
    let path = plan(&p, &s);
    assert!(path.moves() >= 2 && !path.cuts.is_empty(), "{path:?}");
    let (after, counts) = p.composed(10, &path);
    assert_eq!(counts, Composed::default());
    let mut want = p.clip(10).unwrap().clone();
    let base = want.video.clone().unwrap();
    let compose = |k: &FramingKey| {
        (
            k.scale * base.scale,
            k.scale * base.x + k.x,
            k.scale * base.y + k.y,
        )
    };
    let (scale, x, y) = compose(&path.keys[0]);
    let video = want.video.as_mut().unwrap();
    (video.scale, video.x, video.y) = (scale, x, y);
    let mut id = 100;
    for w in path.keys.windows(2) {
        if (w[0].scale, w[0].x, w[0].y) == (w[1].scale, w[1].x, w[1].y) {
            continue;
        }
        let (s, x, y) = compose(&w[1]);
        want.actions.push(Action {
            id,
            start: w[0].t,
            duration: w[1].t - w[0].t,
            curve: w[1].curve,
            end: json!({"video": {"scale": s, "x": x, "y": y}}),
        });
        id += 1;
    }
    assert_eq!(
        serde_json::to_string(after.clip(10).unwrap()).unwrap(),
        serde_json::to_string(&want).unwrap()
    );
}

#[test]
fn a_ramped_clips_backdrop_keeps_its_speed_action() {
    let h = handle(json!({"actions": [
        {"id": 91, "start": 0, "duration": 5 * SEC, "end": {"speed": 1.5}},
        {"id": 92, "start": 6 * SEC, "duration": SEC, "end": {"audio": {"volume": 0.5}}}]}));
    let after = h.apply(&reframe(json!({"follow": "fit", "backdrop": 5})));
    let project = after.value();
    let copy = array(&project, "/clips")
        .iter()
        .find(|c| c["track"] == 5)
        .unwrap()
        .clone();
    let actions = array(&copy, "/actions");
    assert_eq!(actions.len(), 1, "{actions:?}");
    let a = &actions[0];
    assert_eq!(
        (a["start"].as_i64(), a["duration"].as_i64()),
        (Some(0), Some(5 * SEC))
    );
    assert_eq!(a["end"], json!({"speed": 1.5}));
    assert!(a["id"].as_u64().unwrap() > copy["id"].as_u64().unwrap());
}
