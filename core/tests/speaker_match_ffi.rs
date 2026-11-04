//! `rc_project_speaker_match` (road map "creator-jobs" VR6b, spec §11 VR-65):
//! the match `follow: speaker` would make, across the FFI, for Make
//! Vertical's sheet. Its answer is held to `speaker_match` over samples and
//! turns mapped into clip time BY HAND here (never through the code under
//! test), and its `sure` to `plan_speaker_framing`'s weak-match refusal.
//!
//! The fixture is `reframe_speaker.rs`'s: a 1920 × 1080 media (1) on a
//! 1080 × 1920 canvas at 30 fps, faces 0.08 × 0.14 at x 0.42 and 0.58,
//! samples every 100 ms in MEDIA ticks, microphones 4 and 5 (an audio file,
//! each on its own track). Turns are in TIMELINE ticks.

mod common;

use std::ffi::c_char;
use std::ptr;

use framejob_core::ffi_query::rc_project_speaker_match;
use framejob_core::model::Project;
use framejob_core::reframe::WhereEmpty;
use framejob_core::reframe_speaker::{plan_speaker_framing, speaker_match, SpeakerMatch};
use framejob_core::reframe_subjects::{SubjectSample, Subjects, Turn};
use serde_json::{json, Value};

use common::{cstring, take_string, Handle};

const SEC: i64 = 600_000;
const STEP: i64 = 60_000;
const F1: f64 = 0.42;
const F2: f64 = 0.58;

fn project_json(clip: Value) -> Value {
    let mut c = json!({"id": 3, "track": 21, "start": 0, "duration": 10 * SEC,
                       "source": {"kind": "media", "media": 1, "in": 0}, "video": {}});
    for (k, v) in clip.as_object().unwrap() {
        c[k] = v.clone();
    }
    let mic = |id: u32, track: u32| {
        json!({"id": id, "track": track, "start": 0, "duration": 20 * SEC,
               "source": {"kind": "media", "media": 2, "in": 0}})
    };
    json!({
        "canvas": {"width": 1080, "height": 1920, "fps": [30, 1]},
        "media": [
            {"id": 1, "path": "/wide.mov", "kind": "video", "duration": 40 * SEC,
             "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true},
            {"id": 2, "path": "/mic.wav", "kind": "audio", "duration": 40 * SEC,
             "has_audio": true}
        ],
        "tracks": [{"id": 20}, {"id": 21}, {"id": 22}, {"id": 23}],
        "clips": [c, mic(4, 22), mic(5, 23)],
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

/// A mouth: alternating 0.05 / 0.20 while talking, else 0.05.
fn mouth(n: i64, talking: bool) -> f64 {
    if talking && n % 2 == 1 {
        0.20
    } else {
        0.05
    }
}

/// Media samples every 100 ms over `[0, secs]`: two faces, face 1's mouth
/// moving where `one(media seconds)`, face 2's where `two(…)`; `None` for no
/// mouths at all.
fn media_samples(
    secs: i64,
    one: Option<&dyn Fn(f64) -> bool>,
    two: Option<&dyn Fn(f64) -> bool>,
) -> Vec<Value> {
    (0..=secs * 10)
        .map(|n| {
            let s = n as f64 / 10.0;
            let m1 = one.map(|f| mouth(n, f(s)));
            let m2 = two.map(|f| mouth(n, f(s)));
            json!({"t": n * STEP, "faces": [face(F1, m1), face(F2, m2)]})
        })
        .collect()
}

fn turns(list: &[(f64, f64, u32)]) -> Vec<Value> {
    list.iter()
        .map(|&(a, b, mic)| {
            json!({"from": (a * SEC as f64).round() as i64, "to": (b * SEC as f64).round() as i64,
                   "mic": mic})
        })
        .collect()
}

fn subjects(samples: Vec<Value>, timeline_turns: &[(f64, f64, u32)]) -> Value {
    json!({"samples": samples, "shots": [], "turns": turns(timeline_turns)})
}

/// The oracle: `speaker_match` over samples whose `t` is mapped by `to_clip`
/// (media ticks → clip ticks, `None` outside the played window) and turns
/// already in clip seconds.
fn oracle(
    media: &[Value],
    to_clip: impl Fn(i64) -> Option<i64>,
    clip_turns: &[(f64, f64, u32)],
) -> Option<SpeakerMatch> {
    let mut mapped: Vec<Value> = media
        .iter()
        .filter_map(|s| {
            let t = to_clip(s["t"].as_i64().unwrap())?;
            let mut s = s.clone();
            s["t"] = json!(t);
            Some(s)
        })
        .collect();
    mapped.sort_by_key(|s| s["t"].as_i64().unwrap());
    // Through text, as the FFI reads them: serde_json's float parse may land an
    // ulp from the value it printed.
    let samples: Vec<SubjectSample> =
        serde_json::from_str(&Value::Array(mapped).to_string()).unwrap();
    let turns: Vec<Turn> = serde_json::from_value(Value::Array(turns(clip_turns))).unwrap();
    speaker_match(&samples, &turns, &[4, 5])
}

/// The FFI's answer written as `SpeakerMatch` would be, and read back from
/// text as the answer is.
fn as_json(found: &SpeakerMatch) -> Value {
    let written = json!({
        "faces": found.faces.iter().map(|f| json!({"face": f.face, "x": f.x, "samples": f.samples}))
            .collect::<Vec<_>>(),
        "agreement": found.agreement,
        "assignment": found.assignment,
        "sure": found.sure,
    });
    serde_json::from_str(&written.to_string()).unwrap()
}

/// Whether `plan_speaker_framing` with no `mic_faces` refuses the weak
/// match (`Some(true)`), applies (`Some(false)`) or refuses otherwise.
fn plan_refuses_weak(clip: Value, subjects: &Value) -> Option<bool> {
    let p: Project = serde_json::from_value(project_json(clip)).unwrap();
    let s: Subjects = serde_json::from_value(subjects.clone()).unwrap();
    match plan_speaker_framing(&p, 3, &s, &[4, 5], None, 1.0, WhereEmpty::Fit) {
        Ok(_) => Some(false),
        Err(why) if why.contains("do not show which microphone is whose") => Some(true),
        Err(_) => None,
    }
}

fn answer(clip: Value, subjects: &Value) -> Value {
    Handle::from_value(&project_json(clip))
        .speaker_match(3, &json!({"mics": [4, 5], "subjects": subjects}))
        .expect("a media clip with good args answers")
}

#[test]
fn the_answer_is_speaker_match_on_the_clip_s_samples() {
    // From 0 at ×1: clip time is media time, the played window [0, 10 s).
    let one = |s: f64| !(4.0..8.0).contains(&s);
    let two = |s: f64| (4.0..8.0).contains(&s);
    let media = media_samples(10, Some(&one), Some(&two));
    let list = [(0.0, 4.0, 4), (4.0, 8.0, 5), (8.0, 10.0, 4)];
    let s = subjects(media.clone(), &list);
    let want = oracle(&media, |t| (t < 10 * SEC).then_some(t), &list).expect("two faces");
    assert!(want.sure, "{want:?}");
    assert_eq!(want.assignment, vec![1, 2]);
    let got = answer(json!({}), &s);
    assert_eq!(got, as_json(&want));
    assert_eq!(got["faces"][0]["x"].as_f64(), Some(F1));
    assert_eq!(got["faces"][1]["x"].as_f64(), Some(F2));
    assert_eq!(plan_refuses_weak(json!({}), &s), Some(false));
}

#[test]
fn a_clip_at_an_offset_maps_its_turns_as_the_framing_does() {
    // The clip from 2 s on the timeline, media from 0: a turn at timeline
    // [2, 6) is clip [0, 4). Its mouths move in media [0, 4) and [4, 8).
    let one = |s: f64| s < 4.0;
    let two = |s: f64| (4.0..8.0).contains(&s);
    let media = media_samples(10, Some(&one), Some(&two));
    let clip = json!({"start": 2 * SEC, "duration": 8 * SEC});
    for (timeline, swapped) in [
        ([(2.0, 6.0, 4), (6.0, 10.0, 5)], false),
        ([(2.0, 6.0, 5), (6.0, 10.0, 4)], true),
    ] {
        let s = subjects(media.clone(), &timeline);
        let in_clip: Vec<(f64, f64, u32)> = timeline
            .iter()
            .map(|&(a, b, m)| (a - 2.0, b - 2.0, m))
            .collect();
        let want = oracle(&media, |t| (t < 8 * SEC).then_some(t), &in_clip).expect("two faces");
        let got = answer(clip.clone(), &s);
        assert_eq!(got, as_json(&want), "swapped {swapped}");
        assert_eq!(
            got["assignment"],
            if swapped {
                json!([2, 1])
            } else {
                json!([1, 2])
            }
        );
        assert_eq!(got["sure"], json!(true));
        assert_eq!(plan_refuses_weak(clip.clone(), &s), Some(false));
    }
    // Turns that read the timeline as clip time would agree with nothing
    // the mouths do in [0, 2): the offset is applied, so the answer is the
    // offset oracle's, not this one.
    let s = subjects(media.clone(), &[(2.0, 6.0, 4), (6.0, 10.0, 5)]);
    let unshifted = oracle(
        &media,
        |t| (t < 8 * SEC).then_some(t),
        &[(2.0, 6.0, 4), (6.0, 8.0, 5)],
    )
    .unwrap();
    assert_ne!(answer(clip, &s), as_json(&unshifted));
}

#[test]
fn a_clip_at_double_speed_maps_samples_and_turns_and_not_sure_is_the_refusal() {
    // At ×2 from 1 s, the clip plays media [0, 10 s) in 5 s: media t is clip
    // t / 2, and a timeline turn [1, 3.5) is clip [0, 2.5), media [0, 5).
    let clip = json!({"start": SEC, "duration": 5 * SEC, "speed": 2.0});
    let one = |s: f64| s < 5.0;
    let two = |s: f64| (5.0..10.0).contains(&s);
    let media = media_samples(10, Some(&one), Some(&two));
    let timeline = [(1.0, 3.5, 4), (3.5, 6.0, 5)];
    let s = subjects(media.clone(), &timeline);
    let to_clip = |t: i64| (t < 10 * SEC).then_some(t / 2);
    let want = oracle(&media, to_clip, &[(0.0, 2.5, 4), (2.5, 5.0, 5)]).unwrap();
    let got = answer(clip.clone(), &s);
    assert_eq!(got, as_json(&want));
    assert_eq!(got["assignment"], json!([1, 2]));
    assert_eq!(got["sure"], json!(true));
    assert_eq!(plan_refuses_weak(clip.clone(), &s), Some(false));

    // Still mouths: the match is not sure, exactly where the framing refuses
    // the weak match.
    let still = subjects(media_samples(10, None, None), &timeline);
    let got = answer(clip.clone(), &still);
    assert_eq!(got["sure"], json!(false));
    assert_eq!(got["faces"].as_array().map(Vec::len), Some(2));
    assert_eq!(plan_refuses_weak(clip, &still), Some(true));
}

#[test]
fn fewer_faces_than_microphones_is_the_empty_answer() {
    let one: Vec<Value> = (0..=100)
        .map(|n| json!({"t": n * STEP, "faces": [face(F1, Some(mouth(n, true)))]}))
        .collect();
    let got = answer(json!({}), &subjects(one, &[(0.0, 4.0, 4), (4.0, 8.0, 5)]));
    assert_eq!(
        got,
        json!({"faces": [], "agreement": [], "assignment": [], "sure": false})
    );
}

#[test]
fn null_for_what_it_cannot_answer() {
    let h = Handle::from_value(&project_json(json!({})));
    let good = subjects(
        media_samples(10, None, None),
        &[(0.0, 4.0, 4), (4.0, 8.0, 5)],
    );
    let args = |mics: Value| json!({"mics": mics, "subjects": good.clone()});
    assert!(h.speaker_match(3, &args(json!([4, 5]))).is_some());
    let raw = |p: *const Project, clip: u32, text: Option<&str>| -> Option<String> {
        let c = text.map(cstring);
        let ptr_: *const c_char = c.as_ref().map_or(ptr::null(), |c| c.as_ptr());
        take_string(unsafe { rc_project_speaker_match(p, clip, ptr_) })
    };
    let text = args(json!([4, 5])).to_string();
    assert!(raw(ptr::null(), 3, Some(&text)).is_none(), "a NULL project");
    assert!(raw(h.as_ptr(), 3, None).is_none(), "NULL args");
    assert!(
        raw(h.as_ptr(), 3, Some("not json")).is_none(),
        "malformed args"
    );
    assert!(
        h.speaker_match(99, &args(json!([4, 5]))).is_none(),
        "an unknown clip"
    );
    assert!(h.speaker_match(3, &args(json!([]))).is_none(), "mics []");
    assert!(
        h.speaker_match(3, &args(json!([4, 5, 6, 7, 8]))).is_none(),
        "five mics"
    );
    assert!(
        h.speaker_match(3, &json!({"mics": [4, 5]})).is_none(),
        "no subjects"
    );
    let mut bad = good.clone();
    bad["turns"] = json!([{"from": SEC, "to": SEC, "mic": 4}]);
    assert!(
        h.speaker_match(3, &json!({"mics": [4, 5], "subjects": bad}))
            .is_none(),
        "subjects that fail check_subjects"
    );
    let texted = h.apply(&json!({"op": "add_text_clip", "track": 20, "at": 0,
                                 "duration": SEC}));
    let text_clip = texted.value()["clips"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["source"]["kind"] == "text")
        .and_then(|c| c["id"].as_u64())
        .expect("a text clip") as u32;
    assert!(
        texted
            .speaker_match(text_clip, &args(json!([4, 5])))
            .is_none(),
        "a text clip"
    );
}
