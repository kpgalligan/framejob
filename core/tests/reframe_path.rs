//! VR-24 — cuts, loss and two people (spec §11 VR-24), black box through
//! `plan_framing` and `choose_subject`. Every expected key is worked by hand
//! from the decision's figures with `core/tests/reframe.rs`' explicit tuning
//! {0.10, 0.08, 0.5, 0.38}, never read back from the code.
//!
//! The fixture is `reframe.rs`': a 1920 × 1080 source canvas and media, the
//! clip at scale 1, x = y = 0, no crop, on a 1080 × 1920 canvas at 30 fps (a
//! frame is 20 000 ticks), 10 s long. k = 16/9, the window 607.5 × 1080
//! source px, its centre's x clamped to 303.75…1616.25 and its y held at 540;
//! a window key's centre is `960 − x/k`. The `fit` state fits the 1920 × 1080
//! picture into 1080 × 1920: scale 0.5625, x = y = 0. Samples every 100 ms;
//! a face box 0.08 × 0.14 of the picture (153.6 px wide).

use framejob_core::model::{Curve, Project};
use framejob_core::reframe::{
    plan_framing, FramingPath, FramingRequest, FramingTuning, Subjects, WhereEmpty,
};
use framejob_core::reframe_path::{CUT_MEDIAN, EMPTY_EASE, LOSS_HOLD, PAIR_WIDEN, RETURN_SEEN};
use framejob_core::reframe_tracks::{choose_subject, Follow, SubjectBox, SubjectSample};
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

fn project(media_fps: [u32; 2], clip: Value) -> Project {
    let mut c = json!({"id": 3, "track": 2, "start": 0, "duration": 10 * SEC,
                       "source": {"kind": "media", "media": 1, "in": 0}});
    for (k, v) in clip.as_object().unwrap() {
        c[k] = v.clone();
    }
    serde_json::from_value(json!({
        "canvas": {"width": 1080, "height": 1920, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/m.mov", "kind": "video", "duration": 20 * SEC,
                   "width": 1920, "height": 1080, "fps": media_fps, "has_video": true}],
        "tracks": [{"id": 2}],
        "clips": [c],
        "next_id": 20
    }))
    .unwrap()
}

fn tall() -> Project {
    project([30, 1], json!({}))
}

fn face_w(cx: f64, w: f64, h: f64) -> SubjectBox {
    SubjectBox {
        x: cx / 1920.0 - w / 2.0,
        y: 432.0 / 1080.0 - h / 2.0,
        w,
        h,
        c: 0.9,
    }
}

fn face(cx: f64) -> SubjectBox {
    face_w(cx, 0.08, 0.14)
}

/// Samples every 100 ms over `[0, to]` s, each holding `boxes(s)`.
fn samples(to: f64, boxes: impl Fn(f64) -> Vec<SubjectBox>) -> Vec<SubjectSample> {
    (0..=(to * 10.0).round() as i64)
        .map(|n| SubjectSample {
            t: n * STEP,
            faces: boxes(n as f64 / 10.0),
            people: vec![],
            salient: vec![],
        })
        .collect()
}

fn plan_with(
    p: &Project,
    s: Vec<SubjectSample>,
    shots: Vec<i64>,
    empty: WhereEmpty,
) -> FramingPath {
    let request = FramingRequest {
        follow: Follow::Subject,
        zoom: 1.0,
        from_width: 1920,
        from_height: 1080,
        where_empty: empty,
    };
    let subjects = Subjects {
        samples: s,
        shots,
        cursor: vec![],
    };
    plan_framing(p, 3, &subjects, &request, &TUNING).expect("a path")
}

fn plan(s: Vec<SubjectSample>, shots: Vec<i64>) -> FramingPath {
    plan_with(&tall(), s, shots, WhereEmpty::Fit)
}

/// A key's (t, what it holds, curve): `Some(centre x)` for a window,
/// `None` for the fit state.
type Key = (i64, Option<f64>, Curve);

fn keys(path: &FramingPath) -> Vec<Key> {
    path.keys
        .iter()
        .map(|k| {
            if (k.scale - K).abs() < 1e-12 {
                assert!(k.y.abs() < 1e-9, "y {}", k.y);
                (k.t, Some(960.0 - k.x / k.scale), k.curve)
            } else {
                assert!(
                    (k.scale - 0.5625).abs() < 1e-12 && k.x.abs() < 1e-9 && k.y.abs() < 1e-9,
                    "neither a window nor fit: {k:?}"
                );
                (k.t, None, k.curve)
            }
        })
        .collect()
}

fn assert_keys(path: &FramingPath, expected: &[Key]) {
    let got = keys(path);
    assert_eq!(got.len(), expected.len(), "keys {got:?}");
    for (g, e) in got.iter().zip(expected) {
        assert_eq!((g.0, g.2), (e.0, e.2), "keys {got:?}");
        match (g.1, e.1) {
            (Some(a), Some(b)) => assert!((a - b).abs() < 1e-6, "keys {got:?}"),
            (None, None) => {}
            _ => panic!("keys {got:?}, want {expected:?}"),
        }
    }
}

use Curve::{EaseInOut as E, Linear as L};

const FIT: Option<f64> = None;

#[test]
fn the_constants_are_vr_24s() {
    assert_eq!(LOSS_HOLD, SEC);
    assert_eq!(EMPTY_EASE, SEC * 4 / 5);
    assert_eq!(RETURN_SEEN, SEC * 3 / 5);
    assert_eq!(CUT_MEDIAN, SEC);
    assert_eq!(PAIR_WIDEN, 1.15);
}

#[test]
fn a_cut_is_one_linear_frame_onto_the_new_shots_median() {
    // The shot at 3 s: c = 1 800 000, the frame before 1 780 000; the new
    // shot's first second holds the face at 1300.
    let s = samples(9.9, |t| vec![face(if t < 3.0 { 600.0 } else { 1300.0 })]);
    let path = plan(s, vec![3 * SEC]);
    assert_keys(
        &path,
        &[
            (0, Some(600.0), L),
            (1_780_000, Some(600.0), L),
            (1_800_000, Some(1300.0), L),
        ],
    );
    assert!(!path.shows_fit);
}

#[test]
fn a_mixed_rate_cut_lands_on_the_first_frame_showing_the_new_shot() {
    // 25 fps media on the 30 fps canvas, the shot at media pts 1.04 s
    // (624 000 ticks): frame 31.2 of the canvas, so the first canvas frame
    // showing it is 32 (640 000), not the nearest, 31 (620 000).
    let p = project([25, 1], json!({}));
    let s = samples(9.9, |t| vec![face(if t < 1.04 { 600.0 } else { 1300.0 })]);
    let path = plan_with(&p, s, vec![624_000], WhereEmpty::Fit);
    assert_keys(
        &path,
        &[
            (0, Some(600.0), L),
            (620_000, Some(600.0), L),
            (640_000, Some(1300.0), L),
        ],
    );
}

#[test]
fn a_cut_onto_a_move_end_writes_no_second_hold() {
    // A wide face (0.2, 384 px, so a 150 px step stays one track) 960 → 1110
    // at 2.0 s; the shot at 1 460 000 leaves the median at 2.0 s five of
    // each, 1035, 75 px away: a 0.4 s move to 1 440 000, the cut's frame
    // before, so no hold key is written there again.
    let s = samples(9.9, |t| {
        vec![face_w(
            match t {
                t if t < 1.95 => 960.0,
                t if t < 2.45 => 1110.0,
                _ => 1300.0,
            },
            0.2,
            0.14,
        )]
    });
    let path = plan(s, vec![1_460_000]);
    assert_keys(
        &path,
        &[
            (0, Some(960.0), L),
            (1_200_000, Some(960.0), L),
            (1_440_000, Some(1035.0), E),
            (1_460_000, Some(1300.0), L),
        ],
    );
}

#[test]
fn a_cut_into_an_empty_shot_goes_to_where_empty() {
    let s = samples(9.9, |t| if t < 3.0 { vec![face(600.0)] } else { vec![] });
    let path = plan(s, vec![3 * SEC]);
    assert_keys(
        &path,
        &[
            (0, Some(600.0), L),
            (1_780_000, Some(600.0), L),
            (1_800_000, FIT, L),
        ],
    );
    assert!(path.shows_fit);
}

/// A (track 0, bigger and nearer the centre) at 760; B at 1500, far enough
/// that the pair never fits the window.
fn a_and_b(a_present: impl Fn(f64) -> bool) -> Vec<SubjectSample> {
    samples(9.9, |t| {
        let mut v = vec![];
        if a_present(t) {
            v.push(face_w(760.0, 0.1, 0.17));
        }
        v.push(face(1500.0));
        v
    })
}

#[test]
fn a_blink_keeps_the_primary_and_a_loss_hands_over_after_a_second() {
    // A missing at 3.0 s only: B stands in, lost, and A is chosen again.
    let blink = a_and_b(|t| (t - 3.0).abs() > 0.05);
    let chosen = choose_subject(&blink, &[], Follow::Face);
    assert!(
        chosen[30].lost && chosen[30].identity == Some(1),
        "{:?}",
        chosen[30]
    );
    assert!(
        !chosen[31].lost && chosen[31].identity == Some(0),
        "{:?}",
        chosen[31]
    );
    // The framing holds A: no move to B.
    assert_keys(&plan(blink, vec![]), &[(0, Some(760.0), L)]);
    // A gone from 3.0 s for good: B stands in until 4.0 s, then is chosen.
    let gone = a_and_b(|t| t < 2.95);
    let chosen = choose_subject(&gone, &[], Follow::Face);
    assert!(chosen[30].lost && chosen[39].lost, "{:?}", &chosen[30..40]);
    assert!(
        !chosen[40].lost && chosen[40].identity == Some(1),
        "{:?}",
        chosen[40]
    );
}

#[test]
fn a_lost_subject_is_held_a_second_then_another_is_followed() {
    // A gone at 3.0 s: nothing moves before 4.0 s; then B at 1500, 740 px
    // away: 740/303.75 s = 1 461 728 ticks from 2 400 000, frame 193.
    let path = plan(a_and_b(|t| t < 2.95), vec![]);
    assert_keys(
        &path,
        &[
            (0, Some(760.0), L),
            (2_400_000, Some(760.0), L),
            (3_860_000, Some(1500.0), E),
        ],
    );
}

#[test]
fn with_nothing_left_the_framing_eases_to_where_empty() {
    // The face gone at 2.0 s: held to 3.0 s, then 0.8 s to the state.
    let s = || samples(9.9, |t| if t < 1.95 { vec![face(600.0)] } else { vec![] });
    let fit = plan(s(), vec![]);
    assert_keys(
        &fit,
        &[
            (0, Some(600.0), L),
            (1_800_000, Some(600.0), L),
            (2_280_000, FIT, E),
        ],
    );
    assert!(fit.shows_fit);
    let centre = plan_with(&tall(), s(), vec![], WhereEmpty::Center);
    assert_keys(
        &centre,
        &[
            (0, Some(600.0), L),
            (1_800_000, Some(600.0), L),
            (2_280_000, Some(960.0), E),
        ],
    );
    assert!(!centre.shows_fit);
}

#[test]
fn the_framing_returns_after_0_6_s_seen_and_not_after_0_5_s() {
    // Nothing until 2.0 s: EMPTY from the start. Seen from 2.0 s, the
    // return starts at 2.6 s: 360 px from the centre, 1.1852 s, 711 111
    // ticks from 1 560 000, frame 114.
    let seen = samples(9.9, |t| if t >= 1.95 { vec![face(600.0)] } else { vec![] });
    assert_keys(
        &plan(seen, vec![]),
        &[
            (0, FIT, L),
            (1_560_000, FIT, L),
            (2_280_000, Some(600.0), E),
        ],
    );
    let brief = samples(9.9, |t| {
        if (1.95..2.55).contains(&t) {
            vec![face(600.0)]
        } else {
            vec![]
        }
    });
    assert_keys(&plan(brief, vec![]), &[(0, FIT, L)]);
}

#[test]
fn an_empty_first_second_starts_empty_and_a_subject_within_it_does_not() {
    // From 1.5 s: EMPTY, returning at 2.1 s (frame 99 of the move's end).
    let late = samples(9.9, |t| if t >= 1.45 { vec![face(600.0)] } else { vec![] });
    assert_keys(
        &plan(late, vec![]),
        &[
            (0, FIT, L),
            (1_260_000, FIT, L),
            (1_980_000, Some(600.0), E),
        ],
    );
    // From 0.9 s: within LOSS_HOLD, so the first key is the subject's.
    let early = samples(9.9, |t| if t >= 0.85 { vec![face(600.0)] } else { vec![] });
    assert_keys(&plan(early, vec![]), &[(0, Some(600.0), L)]);
}

#[test]
fn two_faces_are_framed_together_when_the_widened_pair_fits() {
    // Equal faces 400 px apart: widened 176.64 px each, the union 576.64 px
    // wide, inside the 607.5 px window: its centre, 960.
    let near = samples(3.0, |_| vec![face(760.0), face(1160.0)]);
    assert_keys(&plan(near, vec![]), &[(0, Some(960.0), L)]);
    // 1,400 px apart: the union does not fit; the first face alone, clamped.
    let far = samples(3.0, |_| vec![face(260.0), face(1660.0)]);
    assert_keys(&plan(far, vec![]), &[(0, Some(303.75), L)]);
}

#[test]
fn every_window_key_lies_inside_the_cropped_rect() {
    // 200 px off the left and 100 off the right: the cropped rect is
    // 200…1820. A face panning 300 → 1700 over the clip, a cut at 5 s, a gap
    // from 7 to 8.5 s, `center` where empty.
    let p = project(
        [30, 1],
        json!({"video": {"crop": {"l": 200.0, "t": 0.0, "r": 100.0, "b": 0.0}}}),
    );
    let s = samples(9.9, |t| {
        if (7.0..8.5).contains(&t) {
            vec![]
        } else {
            vec![face(300.0 + 140.0 * t)]
        }
    });
    let path = plan_with(&p, s, vec![5 * SEC], WhereEmpty::Center);
    assert!(path.keys.len() > 3, "{:?}", path.keys);
    for k in &path.keys {
        assert!((k.scale - K).abs() < 1e-12, "{k:?}");
        let centre = 960.0 - k.x / k.scale;
        assert!(
            centre - 303.75 >= 200.0 - 1e-6 && centre + 303.75 <= 1820.0 + 1e-6,
            "{k:?}: window {} … {}",
            centre - 303.75,
            centre + 303.75
        );
    }
    let ts: Vec<i64> = path.keys.iter().map(|k| k.t).collect();
    assert!(ts.windows(2).all(|w| w[0] < w[1]), "{ts:?}");
    assert!(ts.iter().all(|t| t % 20_000 == 0), "{ts:?}");
}
