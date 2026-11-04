//! `follow: speaker` (road map "creator-jobs" VR6a, spec §11 VR-60, VR-61):
//! the match through `speaker_match`, the segments and cuts through
//! `plan_speaker_framing`, and the op's refusals through the FFI. Every
//! expected number is worked by hand from the decisions' figures, never read
//! back from the code.
//!
//! The usual fixture: a 1920 × 1080 media at scale 1, x = y = 0, no crop,
//! the clip 10 s from 0 on a 1080 × 1920 canvas at 30 fps (a frame is
//! 20 000 ticks). Then k = 16/9 and the window is 607.5 × 1080 source px; a
//! face box 0.08 × 0.14 centred at cx (0…1) puts a key's x at
//! `k·(960 − 1920·cx)`: face 1 at 0.42 → +273.07, face 2 at 0.58 → −273.07,
//! the pair's union (each widened 1.15: 0.374…0.626, 484.6 px, fitting
//! 607.5) centred at 0.5 → 0. At zoom 2 the window is 303.75 px and the pair
//! does not fit. Samples are every 100 ms (60 000 ticks). Microphones are
//! clips 4, 5 and 6 of an audio file, each on its own track.

mod common;

use framejob_core::edit_reframe::no_subjects;
use framejob_core::model::Project;
use framejob_core::reframe::{FramingPath, WhereEmpty};
use framejob_core::reframe_speaker::{
    pearson, plan_speaker_framing, speaker_match, sure, ACTIVITY_SPAN, FACE_SHARE,
    SPEAKER_AGREEMENT, SPEAKER_HOLD,
};
use framejob_core::reframe_subjects::{SubjectSample, Subjects, Turn};
use serde_json::{json, Value};

use common::Handle;

const SEC: i64 = 600_000;
const STEP: i64 = 60_000;
const K: f64 = 1920.0 / 1080.0;
const F1: f64 = 0.42;
const F2: f64 = 0.58;
const F3: f64 = 0.74;

fn project_json(clip: Value) -> Value {
    let mut c = json!({"id": 3, "track": 21, "start": 0, "duration": 10 * SEC,
                       "source": {"kind": "media", "media": 1, "in": 0}, "video": {}});
    for (k, v) in clip.as_object().unwrap() {
        c[k] = v.clone();
    }
    let mic = |id: u32, track: u32| {
        json!({"id": id, "track": track, "start": 0, "duration": 10 * SEC,
               "source": {"kind": "media", "media": 2, "in": 0}})
    };
    json!({
        "canvas": {"width": 1080, "height": 1920, "fps": [30, 1]},
        "media": [
            {"id": 1, "path": "/wide.mov", "kind": "video", "duration": 40 * SEC,
             "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true},
            {"id": 2, "path": "/mic.wav", "kind": "audio", "duration": 40 * SEC,
             "has_audio": true},
            {"id": 11, "path": "/mute.mov", "kind": "video", "duration": 40 * SEC,
             "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true}
        ],
        "tracks": [{"id": 20}, {"id": 21}, {"id": 22}, {"id": 23}, {"id": 24}],
        "clips": [c, mic(4, 22), mic(5, 23), mic(6, 20),
                  {"id": 8, "track": 24, "start": 0, "duration": 10 * SEC,
                   "source": {"kind": "media", "media": 11, "in": 0}, "video": {}}],
        "next_id": 100
    })
}

fn face(cx: f64, mouth: Option<f64>) -> Value {
    let mut b = json!({"x": cx - 0.04, "y": 0.33, "w": 0.08, "h": 0.14, "c": 0.9});
    if let Some(m) = mouth {
        b["mouth"] = json!(m);
    }
    b
}

/// Samples every 100 ms over `[0, secs]`, sample n's faces `faces(n)`.
fn samples(secs: i64, faces: impl Fn(i64) -> Vec<Value>) -> Vec<Value> {
    (0..=secs * 10)
        .map(|n| json!({"t": n * STEP, "faces": faces(n)}))
        .collect()
}

/// A mouth: alternating 0.05 / 0.20 while talking, else 0.05.
fn mouth(n: i64, talking: bool) -> f64 {
    if talking && n % 2 == 1 {
        0.20
    } else {
        0.05
    }
}

fn turns(list: &[(f64, f64, u32)]) -> Vec<Value> {
    list.iter()
        .map(|&(a, b, mic)| {
            json!({"from": (a * SEC as f64).round() as i64, "to": (b * SEC as f64).round() as i64,
                   "mic": mic})
        })
        .collect()
}

fn covers(list: &[(f64, f64, u32)], mic: u32, n: i64) -> bool {
    let s = n as f64 / 10.0;
    list.iter().any(|&(a, b, m)| m == mic && a <= s && s < b)
}

/// Two still faces whose mouths move inside their microphone's turns: face
/// 1 talks for `mic_one`, face 2 for `mic_two`.
fn talking(list: &[(f64, f64, u32)], mic_one: u32, mic_two: u32) -> Value {
    let l = list.to_vec();
    let s = samples(10, move |n| {
        vec![
            face(F1, Some(mouth(n, covers(&l, mic_one, n)))),
            face(F2, Some(mouth(n, covers(&l, mic_two, n)))),
        ]
    });
    json!({"samples": s, "shots": [], "turns": turns(list)})
}

/// Still faces at `xs` over the media's 40 s, no mouths, and the turns.
fn still(xs: &[f64], list: &[(f64, f64, u32)]) -> Value {
    let xs = xs.to_vec();
    let s = samples(40, move |_| xs.iter().map(|&x| face(x, None)).collect());
    json!({"samples": s, "shots": [], "turns": turns(list)})
}

fn reframe(args: Value) -> Value {
    let mut op = json!({"op": "reframe_clip", "clip": 3, "follow": "speaker", "mics": [4, 5]});
    for (k, v) in args.as_object().unwrap() {
        op[k] = v.clone();
    }
    op
}

fn plan(
    clip: Value,
    subjects: Value,
    mics: &[u32],
    faces: Option<&[u32]>,
    zoom: f64,
) -> FramingPath {
    let p: Project = serde_json::from_value(project_json(clip)).unwrap();
    let subjects: Subjects = serde_json::from_value(subjects).unwrap();
    plan_speaker_framing(&p, 3, &subjects, mics, faces, zoom, WhereEmpty::Fit).expect("a path")
}

fn key_x(cx: f64) -> f64 {
    K * (960.0 - 1920.0 * cx)
}

/// The framing's x at clip second `s`.
fn x_at(path: &FramingPath, s: f64) -> f64 {
    path.at((s * SEC as f64) as i64).1
}

fn close(a: f64, b: f64) -> bool {
    (a - b).abs() < 1e-6
}

fn assert_x(path: &FramingPath, s: f64, cx: f64) {
    let x = x_at(path, s);
    assert!(
        close(x, key_x(cx)),
        "x {x} at {s} s, want face at {cx} ({})",
        key_x(cx)
    );
}

// ---- the match ---------------------------------------------------------------

fn sample_list(v: Vec<Value>) -> Vec<SubjectSample> {
    serde_json::from_value(Value::Array(v)).unwrap()
}

fn turn_list(list: &[(f64, f64, u32)]) -> Vec<Turn> {
    serde_json::from_value(Value::Array(turns(list))).unwrap()
}

#[test]
fn the_numbers_are_the_decisions() {
    assert_eq!(SPEAKER_HOLD, 2 * SEC);
    assert_eq!(ACTIVITY_SPAN, SEC / 4);
    assert_eq!(FACE_SHARE, 0.25);
    assert_eq!(SPEAKER_AGREEMENT, 0.2);
}

#[test]
fn faces_chain_across_a_gap_and_are_numbered_left_to_right() {
    // The right face first in every sample; the left one away from 3.05 s to
    // 6 s, three seconds, past `LINK_GAP`, so two tracks and one chain.
    let s = sample_list(samples(10, |n| {
        let mut f = vec![face(F2, None)];
        if !(31..60).contains(&n) {
            f.push(face(F1, None));
        }
        f
    }));
    let m = speaker_match(&s, &[], &[4, 5]).expect("two faces");
    assert_eq!(m.faces.len(), 2);
    assert_eq!(m.faces[0].face, 1);
    assert!(close(m.faces[0].x, F1), "{:?}", m.faces);
    assert_eq!(m.faces[0].samples, 101 - 29);
    assert!(close(m.faces[1].x, F2));
    assert_eq!(m.faces[1].samples, 101);
}

#[test]
fn a_face_needs_a_quarter_of_the_samples() {
    // 100 samples; a third face in exactly 25 of them is a face, in 24 not.
    let with = |n_third: i64| {
        sample_list(
            (0..100)
                .map(|n| {
                    let mut f = vec![face(F1, None), face(F2, None)];
                    if n < n_third {
                        f.push(face(F3, None));
                    }
                    json!({"t": n * STEP, "faces": f})
                })
                .collect(),
        )
    };
    assert_eq!(
        speaker_match(&with(25), &[], &[4, 5]).unwrap().faces.len(),
        3
    );
    assert_eq!(
        speaker_match(&with(24), &[], &[4, 5]).unwrap().faces.len(),
        2
    );
    // Fewer faces than microphones: no match.
    assert!(speaker_match(&with(0), &[], &[4, 5, 6]).is_none());
}

#[test]
fn pearson_against_hand_values() {
    // x̄ 2, ȳ 2/3: Σxy 1, Σxx 2, Σyy 2/3, r = 1/√(4/3).
    let r = pearson(&[(1.0, 0.0), (2.0, 1.0), (3.0, 1.0)]);
    assert!(close(r, 1.0 / (4.0f64 / 3.0).sqrt()), "{r}");
    assert_eq!(pearson(&[(1.0, 0.0), (1.0, 1.0)]), 0.0);
    assert_eq!(pearson(&[(1.0, 1.0)]), 0.0);
}

#[test]
fn activity_reads_a_quarter_second_each_side() {
    // Face 1's mouth is 0 but for 0.5 at 5.0 s. Inside ±0.25 s — 4.8 … 5.2 s,
    // five samples — every window holds the spike and four zeros: std 0.2;
    // 4.7 s is 0.3 s away and reads none. Mic 4's turn covers exactly those
    // five samples, so its agreement with face 1 is 1.
    let s = sample_list(samples(10, |n| {
        vec![
            face(F1, Some(if n == 50 { 0.5 } else { 0.0 })),
            face(F2, Some(0.0)),
        ]
    }));
    let list = [(4.8, 5.3, 4), (0.0, 4.0, 5)];
    let m = speaker_match(&s, &turn_list(&list), &[4, 5]).unwrap();
    assert!(close(m.agreement[0][0], 1.0), "{:?}", m.agreement);
    assert!(m.agreement[1][0] < 0.0, "{:?}", m.agreement);
    // Face 2 never moves: undefined, 0.
    assert_eq!(m.agreement[0][1], 0.0);
}

#[test]
fn a_long_clip_matches_in_linear_time() {
    // `MAX_SUBJECT_SAMPLES` (100 000) samples at 10 Hz, 10 000 s, two faces,
    // and 2 000 turns of 5 s alternating mic 4 (face 1) and mic 5 (face 2).
    // A window per box over every box (10¹⁰ comparisons a face) or every turn
    // per sample (8 × 10⁸) takes minutes; the forward walks take milliseconds.
    // The bound is generous for a loaded machine.
    let n_samples: i64 = 100_000;
    let turn = 5 * SEC;
    let mic_at = |n: i64| if (n * STEP / turn) % 2 == 0 { 4 } else { 5 };
    let s = sample_list(
        (0..n_samples)
            .map(|n| {
                let mic = mic_at(n);
                json!({"t": n * STEP, "faces": [face(F1, Some(mouth(n, mic == 4))),
                                                 face(F2, Some(mouth(n, mic == 5)))]})
            })
            .collect(),
    );
    let t: Vec<Turn> = (0..n_samples * STEP / turn)
        .map(|k| Turn {
            from: k * turn,
            to: (k + 1) * turn,
            mic: if k % 2 == 0 { 4 } else { 5 },
        })
        .collect();
    assert_eq!(t.len(), 2_000);
    let began = std::time::Instant::now();
    let m = speaker_match(&s, &t, &[4, 5]).expect("two faces");
    let took = began.elapsed();
    assert_eq!(m.assignment, vec![1, 2]);
    assert!(m.sure, "{:?}", m.agreement);
    assert!(took.as_secs_f64() < 5.0, "speaker_match took {took:?}");
}

#[test]
fn the_assignment_is_the_best_sum_and_a_tie_the_smallest_list() {
    let list = [(0.0, 4.0, 4), (4.0, 8.0, 5), (8.0, 10.0, 4)];
    let s: Subjects = serde_json::from_value(talking(&list, 4, 5)).unwrap();
    let m = speaker_match(&s.samples, &s.turns, &[4, 5]).unwrap();
    assert_eq!(m.assignment, vec![1, 2]);
    assert!(m.sure, "{:?}", m.agreement);
    // Swapped mouths: mic 4 is face 2.
    let s: Subjects = serde_json::from_value(talking(&list, 5, 4)).unwrap();
    let m = speaker_match(&s.samples, &s.turns, &[4, 5]).unwrap();
    assert_eq!(m.assignment, vec![2, 1]);
    // Nothing moves: every sum 0, the smallest list, not sure.
    let s: Subjects = serde_json::from_value(still(&[F1, F2], &list)).unwrap();
    let m = speaker_match(&s.samples, &s.turns, &[4, 5]).unwrap();
    assert_eq!(m.assignment, vec![1, 2]);
    assert!(!m.sure);
}

#[test]
fn sure_at_its_edge() {
    assert!(!sure(&[0.19, 0.9]));
    assert!(sure(&[0.2, 0.9]));
}

// ---- segments and cuts ---------------------------------------------------------

#[test]
fn each_speaker_change_is_a_cut_on_the_first_frame_after_it() {
    let list = [(0.0, 4.01, 4), (4.01, 8.0, 5), (8.0, 10.0, 4)];
    let path = plan(
        json!({}),
        still(&[F1, F2], &list),
        &[4, 5],
        Some(&[1, 2]),
        1.0,
    );
    // 4.01 s is 2 406 000 ticks: the next frame is 2 420 000.
    assert_eq!(path.cuts, vec![2_420_000, 8 * SEC]);
    assert_x(&path, 2.0, F1);
    assert_x(&path, 6.0, F2);
    assert_x(&path, 9.0, F1);
    // The hold before a cut is the frame before it.
    assert_x(&path, 2_400_000.0 / SEC as f64, F1);
}

#[test]
fn nobody_holds_and_the_first_label_reaches_back_to_zero() {
    let list = [(3.0, 6.0, 5), (7.0, 10.0, 4)];
    let path = plan(
        json!({}),
        still(&[F1, F2], &list),
        &[4, 5],
        Some(&[1, 2]),
        1.0,
    );
    // 0–3 s takes B's face (the first labelled), 6–7 s holds it.
    assert_eq!(path.cuts, vec![7 * SEC]);
    assert_x(&path, 1.0, F2);
    assert_x(&path, 6.5, F2);
    assert_x(&path, 8.0, F1);
}

#[test]
fn both_frame_the_pair_when_it_fits_and_the_face_framed_when_not() {
    let list = [(0.0, 4.0, 4), (4.0, 7.0, 4), (4.0, 7.0, 5), (7.0, 10.0, 5)];
    let path = plan(
        json!({}),
        still(&[F1, F2], &list),
        &[4, 5],
        Some(&[1, 2]),
        1.0,
    );
    assert_eq!(path.cuts, vec![4 * SEC, 7 * SEC]);
    assert_x(&path, 5.5, 0.5);
    // At zoom 2 the pair does not fit: face 1, already framed, holds.
    let path = plan(
        json!({}),
        still(&[F1, F2], &list),
        &[4, 5],
        Some(&[1, 2]),
        2.0,
    );
    assert_eq!(path.cuts, vec![7 * SEC]);
}

#[test]
fn three_microphones_and_the_two_second_hold() {
    let faces = [F1, F2, F3];
    let three = |list: &[(f64, f64, u32)]| {
        plan(
            json!({}),
            still(&faces, list),
            &[4, 5, 6],
            Some(&[1, 2, 3]),
            1.0,
        )
    };
    let path = three(&[(0.0, 3.0, 4), (3.0, 6.0, 5), (6.0, 10.0, 6)]);
    assert_eq!(path.cuts, vec![3 * SEC, 6 * SEC]);
    assert_x(&path, 8.0, F3);
    // B for 1.9 s joins A before it: one cut, at C's start.
    let path = three(&[(0.0, 4.0, 4), (4.0, 5.9, 5), (5.9, 10.0, 6)]);
    assert_eq!(path.cuts, vec![3_540_000]);
    assert_x(&path, 5.0, F1);
    // 2.0 s stands.
    let path = three(&[(0.0, 4.0, 4), (4.0, 6.0, 5), (6.0, 10.0, 6)]);
    assert_eq!(path.cuts, vec![4 * SEC, 6 * SEC]);
    // The first segment short: it joins the one after.
    let path = three(&[(0.0, 1.9, 4), (1.9, 10.0, 5)]);
    assert!(path.cuts.is_empty(), "{:?}", path.cuts);
    assert_x(&path, 0.5, F2);
}

#[test]
fn turns_are_timeline_ticks_whatever_the_clip_plays() {
    // At ×2 from 1 s, the clip plays 10 s of media in 5 s: a turn change at
    // timeline 3.5 s is clip 2.5 s.
    let list = [(1.0, 3.5, 4), (3.5, 6.0, 5)];
    for reversed in [false, true] {
        let clip = json!({"start": SEC, "duration": 5 * SEC, "speed": 2.0,
                          "source": {"kind": "media", "media": 1, "in": 0,
                                     "reversed": reversed}});
        let path = plan(clip, still(&[F1, F2], &list), &[4, 5], Some(&[1, 2]), 1.0);
        assert_eq!(path.cuts, vec![1_500_000], "reversed {reversed}");
        assert_x(&path, 1.0, F1);
        assert_x(&path, 4.0, F2);
    }
}

// ---- the op, through the FFI ---------------------------------------------------

fn handle(clip: Value) -> Handle {
    Handle::from_value(&project_json(clip))
}

#[test]
fn the_op_matches_the_faces_itself_and_mic_faces_overrides() {
    let list = [(0.0, 4.0, 4), (4.0, 8.0, 5), (8.0, 10.0, 4)];
    let h = handle(json!({}));
    let applied = h.apply(&reframe(json!({"subjects": talking(&list, 4, 5)})));
    let given = h.apply(&reframe(
        json!({"subjects": talking(&list, 4, 5), "mic_faces": [1, 2]}),
    ));
    assert_eq!(applied.value()["clips"], given.value()["clips"]);
    // A weak match with mic_faces given applies with that pairing.
    let swapped = h.apply(&reframe(json!({"subjects": still(&[F1, F2], &list),
                                          "mic_faces": [2, 1]})));
    let face_two_first = h.apply(&reframe(json!({"subjects": talking(&list, 5, 4)})));
    assert_eq!(swapped.value()["clips"], face_two_first.value()["clips"]);
    assert_ne!(swapped.value()["clips"], applied.value()["clips"]);
}

#[test]
fn every_refusal_in_its_sentence_and_order() {
    let list = [(0.0, 4.0, 4), (4.0, 8.0, 5)];
    let good = talking(&list, 4, 5);
    let h = handle(json!({}));
    let off = handle(json!({})).apply(&json!({"op": "set_enabled", "clip": 4, "audio": false}));
    let refuse = |h: &Handle, args: Value, why: &str| h.refuses_with(&reframe(args), why);
    refuse(
        &h,
        json!({"mics": null}),
        "follow speaker needs two to four microphone clips in mics, not 0",
    );
    refuse(
        &h,
        json!({"mics": [4]}),
        "follow speaker needs two to four microphone clips in mics, not 1",
    );
    refuse(&h, json!({"mics": [4, 4]}), "clip 4 is named twice in mics");
    refuse(
        &h,
        json!({"mics": [4, 3]}),
        "clip 3 is the clip being framed, so it cannot be one of its microphones",
    );
    refuse(
        &h,
        json!({"mics": [4, 8]}),
        "clip 8 has no sound from a media file, so it cannot be a microphone",
    );
    // The sound off: named, before "no subjects" and before mic_faces.
    let sound_off = "clip 4's sound is off, so it never says who is talking; turn its sound on \
                     or leave it out of mics";
    refuse(&off, json!({}), sound_off);
    refuse(
        &off,
        json!({"mic_faces": [1, 2], "subjects": good.clone()}),
        sound_off,
    );
    let shared = handle(json!({})).apply(&json!({"op": "move_clip", "clips": [5], "track": 22,
                                                 "delta": 10 * SEC}));
    refuse(
        &shared,
        json!({}),
        "clips 4 and 5 are both on track 22; each microphone needs its own track",
    );
    refuse(
        &h,
        json!({"mic_faces": [1]}),
        "mic_faces needs one face number for each of the 2 microphones in mics, not 1",
    );
    refuse(
        &h,
        json!({"mic_faces": [0, 1]}),
        "mic_faces names face 0; faces are numbered from 1",
    );
    refuse(
        &h,
        json!({"mic_faces": [2, 2]}),
        "mic_faces names face 2 twice; each microphone needs its own face",
    );
    // Bad subjects, then none.
    let mut bad = good.clone();
    bad["turns"] = json!([{"from": 5, "to": 5, "mic": 4}]);
    refuse(
        &h,
        json!({"subjects": bad}),
        "subjects turns[0] runs from 5 to 5; a turn must end after it starts",
    );
    let mut bad = good.clone();
    bad["turns"] = json!([{"from": 9, "to": 20, "mic": 4}, {"from": 5, "to": 20, "mic": 5}]);
    refuse(
        &h,
        json!({"subjects": bad}),
        "subjects turns[1] starts at 5, before the one before it (9); turns must be in time \
            order",
    );
    let mut bad = good.clone();
    bad["samples"][0]["faces"][0]["mouth"] = json!(-0.1);
    refuse(
        &h,
        json!({"subjects": bad}),
        "subjects sample 0's faces[0].mouth is -0.1; a mouth opening must be a number of at \
            least 0",
    );
    let mut bad = good.clone();
    bad["samples"][0]["people"] = json!([face(F1, Some(0.1))]);
    refuse(
        &h,
        json!({"subjects": bad}),
        "subjects sample 0's people[0] has a mouth; only a face box has one",
    );
    refuse(&h, json!({}), &no_subjects(3));
    // Then the planner's, each with every later one also true.
    let mut bad = still(&[F1], &[(0.0, 4.0, 6)]);
    bad["shots"] = json!([3 * SEC]);
    refuse(
        &h,
        json!({"subjects": bad.clone()}),
        "subjects turns[0] names clip 6, which is not one of mics",
    );
    bad["turns"] = json!(turns(&[(20.0, 21.0, 4)]));
    refuse(
        &h,
        json!({"subjects": bad.clone()}),
        "clip 3 changes shot at 00:00:03:00; follow speaker frames one wide shot — split the \
            clip at its shot changes first",
    );
    bad["shots"] = json!([]);
    refuse(
        &h,
        json!({"subjects": bad.clone(), "mic_faces": [1, 3]}),
        "clip 3 shows 1 face for 2 microphones; follow speaker needs a face for each \
            microphone",
    );
    let two = still(&[F1, F2], &[(20.0, 21.0, 4)]);
    refuse(
        &h,
        json!({"subjects": two.clone(), "mic_faces": [1, 3]}),
        "mic_faces names face 3, but clip 3 shows only 2 faces",
    );
    refuse(
        &h,
        json!({"subjects": two}),
        "clip 3 has no turn of its microphones inside it, so there is no speaker to follow",
    );
    refuse(
        &h,
        json!({"subjects": still(&[F1, F2], &list)}),
        "clip 3's faces do not show which microphone is whose: the best match agrees only \
            0.00 (under 0.2); name each microphone's face with mic_faces, in mics' order — face \
            1 at 42 % across the picture, face 2 at 58 %",
    );
    // An unknown microphone is invalid input; another follow ignores mics.
    assert_eq!(
        h.errors(&reframe(json!({"mics": [4, 99]}))),
        "no clip with id 99"
    );
    h.apply(&json!({"op": "reframe_clip", "clip": 3, "follow": "center", "mics": [99]}));
    // A turn that is not an object is named by its path.
    let mut bad = good;
    bad["turns"] = json!([5]);
    assert_eq!(
        h.errors(&reframe(json!({"subjects": bad}))),
        "op \"reframe_clip\" is not valid: bad value at \"subjects.turns[0]\": expected an \
         object, not 5"
    );
}
