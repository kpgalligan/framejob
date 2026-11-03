//! The framing planner (spec §11 VR-20…VR-23), black box through
//! `plan_framing` and `choose_subject`. Every expected key is worked by hand
//! from the decisions' figures with an explicit tuning {0.10, 0.08, 0.5,
//! 0.38}, never read back from the code.
//!
//! The usual fixture: a 1920 × 1080 source canvas and media, the clip at
//! scale 1, x = y = 0, no crop, on a 1080 × 1920 canvas at 30 fps (a frame is
//! 20 000 ticks). Then k = 1920/1080 = 16/9, the window is 607.5 × 1080
//! source px, its centre's x clamped to 303.75…1616.25 and its y held at 540
//! (so every key's y is 0); the dead zone is 60.75 px across; a move runs at
//! 0.5 × 607.5 = 303.75 px a second, at least 0.4 s. A key's window centre is
//! `960 − x/k`. Samples are every 100 ms (60 000 ticks); a face box is 0.08 ×
//! 0.14 of the picture.

use framejob_core::model::{Curve, Project};
use framejob_core::reframe::{
    plan_framing, FramingPath, FramingRequest, FramingTuning, Subjects, FRAMING_TUNING,
};
use framejob_core::reframe_tracks::{
    choose_subject, Follow, SubjectBox, SubjectKind, SubjectSample,
};
use serde_json::{json, Value};

const SEC: i64 = 600_000;
const STEP: i64 = 60_000;
const TUNING: FramingTuning = FramingTuning {
    dead_zone_width: 0.10,
    dead_zone_height: 0.08,
    speed: 0.5,
    headroom: 0.38,
};
const K: f64 = 1920.0 / 1080.0;

fn project(canvas: (u32, u32, [u32; 2]), clip: Value) -> Project {
    let mut c = json!({"id": 3, "track": 2, "start": 0, "duration": 10 * SEC,
                       "source": {"kind": "media", "media": 1, "in": 0}});
    for (k, v) in clip.as_object().unwrap() {
        c[k] = v.clone();
    }
    serde_json::from_value(json!({
        "canvas": {"width": canvas.0, "height": canvas.1, "fps": canvas.2},
        "media": [{"id": 1, "path": "/m.mov", "kind": "video", "duration": 20 * SEC,
                   "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true}],
        "tracks": [{"id": 2}],
        "clips": [c],
        "next_id": 20
    }))
    .unwrap()
}

fn tall(clip: Value) -> Project {
    project((1080, 1920, [30, 1]), clip)
}

/// A face box centred at (cx, cy) px of the 1920 × 1080 picture.
fn face(cx: f64, cy: f64) -> SubjectBox {
    SubjectBox {
        x: cx / 1920.0 - 0.04,
        y: cy / 1080.0 - 0.07,
        w: 0.08,
        h: 0.14,
        c: 0.9,
    }
}

fn sample(t: i64, faces: Vec<SubjectBox>) -> SubjectSample {
    SubjectSample {
        t,
        faces,
        people: vec![],
        salient: vec![],
    }
}

/// Media samples every 100 ms over `[from, to]` s, the face's x by `x(s)`.
fn faces(from: f64, to: f64, x: impl Fn(f64) -> f64) -> Vec<SubjectSample> {
    let (a, b) = ((from * 10.0).round() as i64, (to * 10.0).round() as i64);
    (a..=b)
        .map(|n| sample(n * STEP, vec![face(x(n as f64 / 10.0), 432.0)]))
        .collect()
}

fn request(zoom: f64) -> FramingRequest {
    FramingRequest {
        follow: Follow::Subject,
        zoom,
        from_width: 1920,
        from_height: 1080,
    }
}

fn plan(p: &Project, samples: Vec<SubjectSample>) -> FramingPath {
    let subjects = Subjects {
        samples,
        shots: vec![],
    };
    plan_framing(p, 3, &subjects, &request(1.0), &TUNING).expect("a path")
}

/// The keys as (t, window centre x, curve), each key's y checked 0.
fn keys(path: &FramingPath) -> Vec<(i64, f64, Curve)> {
    path.keys
        .iter()
        .map(|k| {
            assert!((k.scale - K).abs() < 1e-12, "scale {}", k.scale);
            assert!(k.y.abs() < 1e-9, "y {}", k.y);
            (k.t, 960.0 - k.x / k.scale, k.curve)
        })
        .collect()
}

fn assert_keys(path: &FramingPath, expected: &[(i64, f64, Curve)]) {
    let got = keys(path);
    assert_eq!(got.len(), expected.len(), "keys {got:?}");
    for (g, e) in got.iter().zip(expected) {
        assert_eq!((g.0, g.2), (e.0, e.2), "keys {got:?}");
        assert!((g.1 - e.1).abs() < 1e-6, "keys {got:?}");
    }
}

use Curve::{EaseInOut as E, Linear as L};

#[test]
fn the_tuning_is_vr_23s_recorded_verdict() {
    // VR-S2's verdict, recorded in VR-23: dead zone 0.15 (its height 0.8 x
    // that), speed 0.8, headroom 0.38.
    let verdict = FramingTuning {
        dead_zone_width: 0.15,
        dead_zone_height: 0.12,
        speed: 0.8,
        headroom: 0.38,
    };
    assert_eq!(FRAMING_TUNING, verdict);
}

#[test]
fn a_still_subject_with_jitter_makes_no_move() {
    // ±9.6 px across, ±5.4 down: inside the 60.75 px dead zone.
    let samples: Vec<SubjectSample> = (0..=99)
        .map(|n| {
            let t = n as f64 / 10.0;
            let b = face(960.0 + 9.6 * (7.3 * t).sin(), 432.0 + 5.4 * (5.1 * t).cos());
            sample(n * STEP, vec![b])
        })
        .collect();
    let path = plan(&tall(json!({})), samples);
    assert_eq!(path.keys.len(), 1, "{:?}", path.keys);
    assert_eq!(path.moves(), 0);
    assert!((keys(&path)[0].1 - 960.0).abs() < 9.6);
}

#[test]
fn a_short_step_moves_for_the_floor() {
    // 960 → 1040 at 2 s: 80 px is past the dead zone; 80/303.75 s is under
    // the floor, so 0.4 s. The median over ±0.5 s turns at 2.0 s exactly
    // (6 of 11 samples), not at 1.9 s (5 of 11).
    let path = plan(
        &tall(json!({})),
        faces(0.0, 9.9, |t| if t < 2.0 { 960.0 } else { 1040.0 }),
    );
    assert_keys(
        &path,
        &[(0, 960.0, L), (1_200_000, 960.0, L), (1_440_000, 1040.0, E)],
    );
    assert_eq!(path.moves(), 1);
}

#[test]
fn a_long_step_moves_for_its_distance() {
    // 960 → 1100: 140/303.75 = 0.4609 s, 276 543 ticks, from 1 200 000 to
    // 1 476 543, snapped to frame 74, 1 480 000.
    let path = plan(
        &tall(json!({})),
        faces(0.0, 9.9, |t| if t < 2.0 { 960.0 } else { 1100.0 }),
    );
    assert_keys(
        &path,
        &[(0, 960.0, L), (1_200_000, 960.0, L), (1_480_000, 1100.0, E)],
    );
}

#[test]
fn no_move_within_half_a_second_of_the_last_unless_outside() {
    // 960 → 1040 at 2.0 s (ends 2.4 s), → 1120 at 2.6 s: 80 px is inside the
    // window, so it waits to 2.9 s and ends 3.3 s.
    let x = |t: f64| match t {
        t if t < 2.0 => 960.0,
        t if t < 2.55 => 1040.0,
        _ => 1120.0,
    };
    let path = plan(&tall(json!({})), faces(0.0, 9.9, x));
    assert_keys(
        &path,
        &[
            (0, 960.0, L),
            (1_200_000, 960.0, L),
            (1_440_000, 1040.0, E),
            (1_740_000, 1040.0, L),
            (1_980_000, 1120.0, E),
        ],
    );
    // → 1500 at 2.6 s is 460 px away, past the window's half (303.75): it
    // moves at once, 460/303.75 s = 908 642 ticks, from 1 560 000 to frame 123.
    let x = |t: f64| match t {
        t if t < 2.0 => 960.0,
        t if t < 2.55 => 1040.0,
        _ => 1500.0,
    };
    let path = plan(&tall(json!({})), faces(0.0, 9.9, x));
    assert_keys(
        &path,
        &[
            (0, 960.0, L),
            (1_200_000, 960.0, L),
            (1_440_000, 1040.0, E),
            (1_560_000, 1040.0, L),
            (2_460_000, 1500.0, E),
        ],
    );
}

#[test]
fn an_exception_move_on_the_last_end_drops_its_hold_key() {
    // → 1500 at 2.4 s, the sample the first move ends on: its hold key would
    // be at 1 440 000, the previous key's tick, so it is not written; the
    // move eases from that key, 908 642 ticks, to frame 117.
    let x = |t: f64| match t {
        t if t < 2.0 => 960.0,
        t if t < 2.35 => 1040.0,
        _ => 1500.0,
    };
    let path = plan(&tall(json!({})), faces(0.0, 9.9, x));
    assert_keys(
        &path,
        &[
            (0, 960.0, L),
            (1_200_000, 960.0, L),
            (1_440_000, 1040.0, E),
            (2_340_000, 1500.0, E),
        ],
    );
}

#[test]
fn a_move_is_at_least_a_frame_and_never_past_the_end() {
    // At 1 fps, 2.0 s + 0.4 s snaps back to 2 s: the end is one frame on, 3 s.
    let p = project((1080, 1920, [1, 1]), json!({}));
    let path = plan(
        &p,
        faces(0.0, 9.9, |t| if t < 2.0 { 960.0 } else { 1040.0 }),
    );
    assert_keys(
        &path,
        &[(0, 960.0, L), (2 * SEC, 960.0, L), (3 * SEC, 1040.0, E)],
    );
    // A step at 9.8 s of a 10 s clip would end at 10.2 s: not started.
    let path = plan(
        &tall(json!({})),
        faces(0.0, 9.9, |t| if t < 9.8 { 960.0 } else { 1040.0 }),
    );
    assert_keys(&path, &[(0, 960.0, L)]);
}

#[test]
fn headroom_in_a_tall_window_and_centred_in_a_wide_one() {
    let still = faces(0.0, 3.0, |_| 960.0);
    let subjects = Subjects {
        samples: still,
        shots: vec![],
    };
    // Zoom 2 on the tall canvas: k = 32/9, the window 303.75 × 540; the face
    // (y 432) 0.38 × 540 below its top puts the centre at 496.8, y = k·43.2.
    let path = plan_framing(&tall(json!({})), 3, &subjects, &request(2.0), &TUNING).unwrap();
    let k = &path.keys[0];
    assert!((k.scale - 2.0 * K).abs() < 1e-12);
    assert!(
        k.x.abs() < 1e-6 && (k.y - 2.0 * K * 43.2).abs() < 1e-6,
        "{k:?}"
    );
    // Zoom 2 on a 1920 × 1080 canvas: k = 2, the window 960 × 540 (wide): the
    // face at the centre, y = 2·(540 − 432).
    let wide = project((1920, 1080, [30, 1]), json!({}));
    let path = plan_framing(&wide, 3, &subjects, &request(2.0), &TUNING).unwrap();
    let k = &path.keys[0];
    assert!((k.scale - 2.0).abs() < 1e-12);
    assert!(k.x.abs() < 1e-6 && (k.y - 216.0).abs() < 1e-6, "{k:?}");
}

#[test]
fn a_persons_top_sits_twelve_percent_below_the_windows() {
    // A person box from y 0.3 (324 px), zoom 2: the window's top at 324 −
    // 0.12 × 540 = 259.2, its centre 529.2, y = k·10.8.
    let person = SubjectBox {
        x: 0.4,
        y: 0.3,
        w: 0.2,
        h: 0.5,
        c: 0.9,
    };
    let samples = (0..=30)
        .map(|n| SubjectSample {
            t: n * STEP,
            faces: vec![],
            people: vec![person],
            salient: vec![],
        })
        .collect();
    let subjects = Subjects {
        samples,
        shots: vec![],
    };
    let mut req = request(2.0);
    req.follow = Follow::Person;
    let path = plan_framing(&tall(json!({})), 3, &subjects, &req, &TUNING).unwrap();
    let k = &path.keys[0];
    assert!(
        k.x.abs() < 1e-6 && (k.y - 2.0 * K * 10.8).abs() < 1e-6,
        "{k:?}"
    );
}

#[test]
fn the_window_is_clamped_at_the_pictures_edge() {
    let path = plan(&tall(json!({})), faces(0.0, 3.0, |_| 100.0));
    assert_keys(&path, &[(0, 303.75, L)]);
}

#[test]
fn a_crop_keeps_the_point_and_moves_the_clamp() {
    // 400 px cropped off the left: the face at 500 px is where it was, but
    // the cropped rect starts at 400, so the window's centre is at least 703.75.
    let still = || faces(0.0, 3.0, |_| 500.0);
    assert_keys(&plan(&tall(json!({})), still()), &[(0, 500.0, L)]);
    let cropped = tall(json!({"video": {"crop": {"l": 400.0, "t": 0.0, "r": 0.0, "b": 0.0}}}));
    assert_keys(&plan(&cropped, still()), &[(0, 703.75, L)]);
}

#[test]
fn samples_outside_the_played_window_are_dropped() {
    // The clip plays media 2–5 s; the face is at 960 there and at 400 outside.
    let p = tall(
        json!({"source": {"kind": "media", "media": 1, "in": 2 * SEC},
                        "duration": 3 * SEC}),
    );
    let x = |t: f64| {
        if (2.0..5.0).contains(&t) {
            960.0
        } else {
            400.0
        }
    };
    assert_keys(&plan(&p, faces(0.0, 9.9, x)), &[(0, 960.0, L)]);
}

#[test]
fn a_double_speed_clip_moves_at_its_clip_time() {
    // ×2: media 4 s is clip 2 s; the samples are 50 ms apart in clip time.
    let p = tall(json!({"speed": 2.0, "duration": 5 * SEC}));
    let path = plan(
        &p,
        faces(0.0, 9.9, |t| if t < 4.0 { 960.0 } else { 1040.0 }),
    );
    assert_keys(
        &path,
        &[(0, 960.0, L), (1_200_000, 960.0, L), (1_440_000, 1040.0, E)],
    );
}

#[test]
fn a_reversed_clip_reads_its_samples_ascending() {
    // Reversed from in 0 over 10 s of a 20 s media: clip t plays forward
    // 20 − t. The face is at 1040 up to forward 12 s (clip 8 s on) and at 960
    // after; the samples arrive in forward order, descending in clip time.
    let p = tall(json!({"source": {"kind": "media", "media": 1, "in": 0, "reversed": true}}));
    let path = plan(
        &p,
        faces(0.0, 20.0, |t| if t <= 12.0 { 1040.0 } else { 960.0 }),
    );
    assert_keys(
        &path,
        &[(0, 960.0, L), (4_800_000, 960.0, L), (5_040_000, 1040.0, E)],
    );
}

#[test]
fn a_ramped_clip_moves_through_its_speed_map() {
    // Rate 1 → 2 over the first 2 s, then 2: S(t) = t + t²/4 to 2 s, so media
    // 4 s is clip 2.5 s. At clip 2.45 s (media 3.9 s) the ±0.5 s window holds
    // ten samples each side and the median is 1000, inside the dead zone.
    let p = tall(json!({"duration": 5 * SEC,
                        "actions": [{"id": 11, "start": 0, "duration": 2 * SEC,
                                     "curve": "linear", "end": {"speed": 2.0}}]}));
    let path = plan(
        &p,
        faces(0.0, 9.0, |t| if t < 4.0 { 960.0 } else { 1040.0 }),
    );
    assert_keys(
        &path,
        &[(0, 960.0, L), (1_500_000, 960.0, L), (1_740_000, 1040.0, E)],
    );
}

#[test]
fn every_no_path_arm() {
    let samples = || Subjects {
        samples: faces(0.0, 1.0, |_| 960.0),
        shots: vec![],
    };
    let ask = |p: &Project, clip: u32, req: FramingRequest| {
        plan_framing(p, clip, &samples(), &req, &TUNING)
    };
    let p = tall(json!({}));
    assert!(ask(&p, 3, request(1.0)).is_some());
    assert!(ask(&p, 99, request(1.0)).is_none(), "no such clip");
    let still = tall(json!({"source": {"kind": "still", "media": 1, "at": 0}}));
    assert!(ask(&still, 3, request(1.0)).is_none(), "a still");
    let turned = tall(json!({"video": {"rotation": 90.0}}));
    assert!(ask(&turned, 3, request(1.0)).is_none(), "rotation");
    let mut sizeless = tall(json!({}));
    sizeless.media[0].width = 0;
    assert!(ask(&sizeless, 3, request(1.0)).is_none(), "no media size");
    let mut silent = tall(json!({}));
    silent.media[0].has_video = false;
    assert!(ask(&silent, 3, request(1.0)).is_none(), "no picture");
    let cropped = tall(json!({"video": {"crop": {"l": 1000.0, "t": 0.0, "r": 920.0, "b": 0.0}}}));
    assert!(ask(&cropped, 3, request(1.0)).is_none(), "cropped away");
    assert!(ask(&p, 3, request(0.99)).is_none(), "zoom under 1");
    assert!(ask(&p, 3, request(4.01)).is_none(), "zoom over 4");
    assert!(ask(&p, 3, request(4.0)).is_some(), "zoom 4");
    let mut zero = request(1.0);
    zero.from_width = 0;
    assert!(ask(&p, 3, zero).is_none(), "zero from_width");
    let mut zero = request(1.0);
    zero.from_height = 0;
    assert!(ask(&p, 3, zero).is_none(), "zero from_height");
}

// ---- choosing the subject (VR-21) ----------------------------------------

fn bx(x: f64, y: f64, w: f64, h: f64) -> SubjectBox {
    SubjectBox { x, y, w, h, c: 0.9 }
}

fn at(t: f64) -> i64 {
    (t * 10.0).round() as i64 * STEP
}

fn tracks_of(chosen: &[framejob_core::reframe_tracks::Chosen]) -> Vec<Option<u32>> {
    chosen.iter().map(|c| c.track).collect()
}

#[test]
fn a_track_bridges_a_gap_of_0_9_s_and_not_1_1_s() {
    let b = bx(0.4, 0.4, 0.1, 0.1);
    let run = |gap_to: f64| -> Vec<SubjectSample> {
        let mut s: Vec<SubjectSample> = (0..=10).map(|n| sample(n * STEP, vec![b])).collect();
        s.push(sample(at(gap_to), vec![b]));
        s
    };
    let linked = choose_subject(&run(1.9), &[], Follow::Face);
    assert_eq!(linked.last().unwrap().track, Some(0));
    let broken = choose_subject(&run(2.1), &[], Follow::Face);
    assert_eq!(broken.last().unwrap().track, Some(1));
}

#[test]
fn an_iou_of_0_29_does_not_link_and_0_31_does() {
    // Two 0.1 boxes side by side, d apart: IoU = (0.1 − d)/(0.1 + d).
    let d = |iou: f64| 0.1 * (1.0 - iou) / (1.0 + iou);
    for (iou, track) in [(0.29, 1), (0.31, 0)] {
        let s = vec![
            sample(0, vec![bx(0.4, 0.4, 0.1, 0.1)]),
            sample(STEP, vec![bx(0.4 + d(iou), 0.4, 0.1, 0.1)]),
        ];
        assert_eq!(
            choose_subject(&s, &[], Follow::Face)[1].track,
            Some(track),
            "iou {iou}"
        );
    }
}

#[test]
fn a_cut_ends_every_track() {
    let b = bx(0.4, 0.4, 0.1, 0.1);
    let s: Vec<SubjectSample> = (0..=20).map(|n| sample(n * STEP, vec![b])).collect();
    let tracks = tracks_of(&choose_subject(&s, &[at(1.0)], Follow::Face));
    assert_eq!(tracks[9], Some(0));
    assert_eq!(tracks[10], Some(1));
    assert_eq!(tracks[20], Some(1));
}

#[test]
fn a_face_outranks_a_bigger_person_and_salient_counts_only_alone() {
    let f = bx(0.0, 0.0, 0.05, 0.05);
    let p = bx(0.3, 0.3, 0.4, 0.4);
    let r = bx(0.2, 0.2, 0.6, 0.6);
    let s = vec![
        SubjectSample {
            t: 0,
            faces: vec![f],
            people: vec![p],
            salient: vec![r],
        },
        SubjectSample {
            t: STEP,
            faces: vec![],
            people: vec![p],
            salient: vec![r],
        },
        SubjectSample {
            t: 2 * STEP,
            faces: vec![],
            people: vec![],
            salient: vec![r],
        },
        SubjectSample {
            t: 3 * STEP,
            faces: vec![],
            people: vec![],
            salient: vec![],
        },
    ];
    let kinds: Vec<_> = choose_subject(&s, &[], Follow::Subject)
        .iter()
        .map(|c| c.kind)
        .collect();
    assert_eq!(
        kinds,
        vec![
            Some(SubjectKind::Face),
            Some(SubjectKind::Person),
            Some(SubjectKind::Salient),
            None
        ]
    );
    let only: Vec<_> = choose_subject(&s, &[], Follow::Salient)
        .iter()
        .map(|c| c.kind)
        .collect();
    let salient = Some(SubjectKind::Salient);
    assert_eq!(only, vec![salient, salient, salient, None]);
}

#[test]
fn a_faces_body_carries_it_while_it_is_away() {
    // F (id 0) and its small body P1 (id 1) from 0 s; F is away 3.0–4.4 s,
    // when a person P2 (id 2) scoring far higher, and never holding F's
    // centre, appears. P1 carries the subject; F is back at 4.5 s, a new
    // track (id 3) after 1.6 s away, and takes it.
    let f = bx(0.45, 0.2, 0.1, 0.1);
    let p1 = bx(0.42, 0.18, 0.16, 0.3);
    let p2 = bx(0.52, 0.05, 0.45, 0.9);
    let s: Vec<SubjectSample> = (0..=60)
        .map(|n| {
            let t = n as f64 / 10.0;
            let away = (3.0..4.45).contains(&t);
            SubjectSample {
                t: n * STEP,
                faces: if away { vec![] } else { vec![f] },
                people: if t >= 3.0 { vec![p1, p2] } else { vec![p1] },
                salient: vec![],
            }
        })
        .collect();
    let tracks = tracks_of(&choose_subject(&s, &[], Follow::Subject));
    assert_eq!(&tracks[..30], &[Some(0); 30][..]);
    assert_eq!(&tracks[30..45], &[Some(1); 15][..]);
    assert_eq!(tracks[45], Some(3));
}

#[test]
fn a_rival_needs_1_25_times_for_2_s() {
    // A (id 0) centred at x 0.25 and B (id 1) at 0.75, equal: A, the lower
    // id. B's box grows ×1.5 from 2.0 s; the median over ±1 s turns at 2.0 s
    // and back when the growth ends.
    let a = bx(0.1875, 0.4375, 0.125, 0.125);
    let small = bx(0.6875, 0.4375, 0.125, 0.125);
    let big = bx(0.65625, 0.4375, 0.1875, 0.125);
    let run = |big_until: f64| -> Vec<Option<u32>> {
        let s: Vec<SubjectSample> = (0..=80)
            .map(|n| {
                let t = n as f64 / 10.0;
                let b = if (2.0..big_until).contains(&t) {
                    big
                } else {
                    small
                };
                sample(n * STEP, vec![a, b])
            })
            .collect();
        tracks_of(&choose_subject(&s, &[], Follow::Face))
    };
    // Big for 2.1 s (2.0–4.0): it meets 1.25 × from 2.0 s to 4.0 s, and takes
    // the frame at 4.0 s.
    let held = run(4.05);
    assert_eq!(&held[..40], &[Some(0); 40][..]);
    assert_eq!(held[40], Some(1));
    // Big for 1.9 s (2.0–3.8): it meets from 2.0 s to 3.8 s only.
    assert!(run(3.85).iter().all(|t| *t == Some(0)));
}
