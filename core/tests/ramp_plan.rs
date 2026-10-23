//! The composition plan of a RAMPED clip (spec §7.2, §11 SR-10): a media
//! clip one of whose actions ends at a `speed`.
//!
//! Pinned here, through the FFI, against closed-form oracles written in this
//! file: one video segment per held span and one per canvas frame inside a
//! ramp, each reading `in + round(S(t_k))` for `round(S(t_k+1)) −
//! round(S(t_k))`, for each of the four curves; the one audio segment, its
//! map's ends and breakpoints, and `glide` only with keep pitch on; a ramped
//! clip's segments on ONE composition track after an overlap, the track the
//! recipe names; a peak above ×12 leaving the audio out, read off the
//! instance's own clip and not the nest's cut of it; a nest's tail cut
//! truncating the video and the audio; an action ending at the rate already
//! in force planning one segment and no glide; and three clips that are not
//! ramped — non-speed actions only, a speed end set then removed, a still
//! with a hand-written speed end — planning byte for byte as their
//! action-free twins.

mod common;

use serde_json::{json, Value};

use common::{array, int, Handle};

/// Ticks per second and per 30 fps frame (spec §5.1), written out.
const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;

/// The four curves' eases' integrals over [0, u], derived by hand from
/// §5.4's polynomials: u, u², 1 − (1 − u)², u²(3 − 2u).
fn ease_integral(curve: &str, u: f64) -> f64 {
    match curve {
        "linear" => u * u / 2.0,
        "ease_in" => u.powi(3) / 3.0,
        "ease_out" => u * u - u.powi(3) / 3.0,
        "ease_in_out" => u.powi(3) - u.powi(4) / 2.0,
        other => panic!("no curve {other}"),
    }
}

/// S(t) for a clip at `r0` with ONE speed action over [a, b) ending at
/// `r1` along `curve`, held after: the closed form.
fn s_of(t: i64, r0: f64, r1: f64, a: i64, b: i64, curve: &str) -> f64 {
    let t = t as f64;
    let (a, b) = (a as f64, b as f64);
    let mut s = r0 * t.min(a);
    if t > a {
        let inside = t.min(b) - a;
        s += r0 * inside + (r1 - r0) * (b - a) * ease_integral(curve, inside / (b - a));
    }
    if t > b {
        s += r1 * (t - b);
    }
    s
}

fn round(s: f64) -> i64 {
    s.round() as i64
}

/// 60 s of 1920x1080 at 30 fps with sound.
fn media(id: u32) -> Value {
    json!({
        "id": id, "path": format!("/fixtures/ramp-{id}.mov"), "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

fn project(clips: Vec<Value>, nests: Vec<Value>) -> Value {
    json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media(1)],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": clips,
        "nests": nests,
        "next_id": 100
    })
}

/// A media clip on track 2 reading from `in`.
fn clip(id: u32, start: i64, duration: i64, source_in: i64, actions: Value) -> Value {
    json!({
        "id": id, "track": 2, "start": start, "duration": duration,
        "source": { "kind": "media", "media": 1, "in": source_in },
        "actions": actions
    })
}

fn speed_action(id: u32, start: i64, duration: i64, curve: &str, rate: f64) -> Value {
    json!({ "id": id, "start": start, "duration": duration, "curve": curve,
            "end": { "speed": rate } })
}

/// Every segment of `clip` on the plan's `kind` tracks, with its track id.
fn segments_of(plan: &Value, kind: &str, clip: i64) -> Vec<(i64, Value)> {
    let mut out = Vec::new();
    for track in array(plan, &format!("/{kind}")) {
        for segment in array(track, "/segments") {
            if int(segment, "/clip") == clip {
                out.push((int(track, "/id"), segment.clone()));
            }
        }
    }
    out
}

fn keys(value: &Value) -> Vec<String> {
    value
        .as_object()
        .map(|o| o.keys().cloned().collect())
        .unwrap_or_default()
}

/// Clip 11 at 0.5 s, 3 s long, from `in` 1 s, at ×1 with action 21 over
/// clip time [1 s, 2 s) ending at ×3 along `curve`.
const START: i64 = SEC / 2;
const IN: i64 = SEC;

fn ramped(curve: &str) -> Handle {
    Handle::from_value(&project(
        vec![clip(
            11,
            START,
            3 * SEC,
            IN,
            json!([speed_action(21, SEC, SEC, curve, 3.0)]),
        )],
        vec![],
    ))
}

#[test]
fn a_ramp_is_one_video_segment_a_frame_reading_the_closed_form_map() {
    for curve in ["linear", "ease_in", "ease_out", "ease_in_out"] {
        let plan = ramped(curve).plan();
        let s = |t: i64| round(s_of(t, 1.0, 3.0, SEC, 2 * SEC, curve));
        let mut bounds = vec![0, SEC];
        bounds.extend((1..30).map(|k| SEC + k * FRAME));
        bounds.extend([2 * SEC, 3 * SEC]);
        let video = segments_of(&plan, "video_tracks", 11);
        assert_eq!(video.len(), bounds.len() - 1, "{curve}: {video:?}");
        for ((_, segment), pair) in video.iter().zip(bounds.windows(2)) {
            let (a, b) = (pair[0], pair[1]);
            assert_eq!(int(segment, "/start"), START + a, "{curve} at {a}");
            assert_eq!(int(segment, "/duration"), b - a, "{curve} at {a}");
            assert_eq!(int(segment, "/source_in"), IN + s(a), "{curve} at {a}");
            assert_eq!(
                int(segment, "/source_duration"),
                s(b) - s(a),
                "{curve} at {a}"
            );
        }
        let tracks: Vec<i64> = video.iter().map(|(id, _)| *id).collect();
        assert!(
            tracks.iter().all(|id| *id == tracks[0]),
            "{curve}: {tracks:?}"
        );
    }
}

#[test]
fn the_audio_is_one_segment_carrying_the_map() {
    for curve in ["linear", "ease_in_out"] {
        let plan = ramped(curve).plan();
        let s = |t: i64| round(s_of(t, 1.0, 3.0, SEC, 2 * SEC, curve));
        let audio = segments_of(&plan, "audio_tracks", 11);
        assert_eq!(audio.len(), 1, "{curve}: {audio:?}");
        let segment = &audio[0].1;
        assert_eq!(
            keys(segment),
            [
                "clip",
                "media",
                "source_in",
                "source_duration",
                "start",
                "duration",
                "pitch",
                "ramp"
            ],
            "{segment}"
        );
        assert_eq!(int(segment, "/source_in"), IN);
        assert_eq!(int(segment, "/source_duration"), s(3 * SEC));
        assert_eq!(int(segment, "/start"), START);
        assert_eq!(int(segment, "/duration"), 3 * SEC);
        assert_eq!(segment["pitch"], json!("off"));
        let ramp = &segment["ramp"];
        assert_eq!(keys(ramp), ["keep_pitch", "glide", "map"]);
        assert_eq!(ramp["keep_pitch"], json!(true));
        assert_eq!(ramp["glide"], json!([[SEC, 2 * SEC]]));

        let mut times = vec![0];
        times.extend((0..1000).map(|k| SEC + k * 600));
        times.extend([2 * SEC, 3 * SEC]);
        let expected: Vec<Value> = times.iter().map(|t| json!([t, IN + s(*t)])).collect();
        assert_eq!(array(ramp, "/map"), &expected, "{curve}");
    }
}

#[test]
fn glide_is_written_only_with_keep_pitch_on() {
    let mut value = project(
        vec![clip(
            11,
            START,
            3 * SEC,
            IN,
            json!([speed_action(21, SEC, SEC, "linear", 3.0)]),
        )],
        vec![],
    );
    value["clips"][0]["audio"] = json!({ "keep_pitch": false });
    let plan = Handle::from_value(&value).plan();
    let audio = segments_of(&plan, "audio_tracks", 11);
    let ramp = &audio[0].1["ramp"];
    assert_eq!(keys(ramp), ["keep_pitch", "map"], "{ramp}");
    assert_eq!(ramp["keep_pitch"], json!(false));
    assert_eq!(audio[0].1["pitch"], json!("off"));
}

#[test]
fn a_ramped_clip_after_an_overlap_is_one_unit_on_one_track() {
    // Clip 10 holds composition track 1 until 2 s; clip 11 starts at 1.5 s,
    // so its WHOLE ramp goes to track 2, even the segments after 2 s.
    let handle = Handle::from_value(&project(
        vec![
            clip(10, 0, 2 * SEC, 0, json!([])),
            clip(
                11,
                3 * SEC / 2,
                3 * SEC,
                0,
                json!([speed_action(21, 0, SEC, "linear", 2.0)]),
            ),
        ],
        vec![],
    ));
    let plan = handle.plan();
    let video = segments_of(&plan, "video_tracks", 11);
    assert!(video.len() > 2, "{video:?}");
    let ids: Vec<i64> = video.iter().map(|(id, _)| *id).collect();
    assert!(ids.iter().all(|id| *id == ids[0]), "{ids:?}");
    assert_ne!(ids[0], segments_of(&plan, "video_tracks", 10)[0].0);
    for t in [3 * SEC / 2 + FRAME, 3 * SEC, 4 * SEC] {
        let recipe = handle.recipe(t);
        let layer = array(&recipe, "/layers")
            .iter()
            .find(|l| int(l, "/clip") == 11)
            .unwrap_or_else(|| panic!("no layer for clip 11 at {t}: {recipe}"))
            .clone();
        assert_eq!(int(&layer, "/source/track_id"), ids[0], "at {t}");
    }
}

#[test]
fn a_peak_above_x12_leaves_the_audio_out() {
    // Base ×1, ending at ×13: the peak, not the base, crosses #190's ×12.
    let handle = Handle::from_value(&project(
        vec![clip(
            11,
            0,
            2 * SEC,
            0,
            json!([speed_action(21, 0, SEC, "linear", 13.0)]),
        )],
        vec![],
    ));
    let plan = handle.plan();
    assert!(segments_of(&plan, "audio_tracks", 11).is_empty(), "{plan}");
    assert!(!segments_of(&plan, "video_tracks", 11).is_empty());
    // At ×12 itself the audio stays.
    let at_twelve = Handle::from_value(&project(
        vec![clip(
            11,
            0,
            2 * SEC,
            0,
            json!([speed_action(21, 0, SEC, "linear", 12.0)]),
        )],
        vec![],
    ));
    assert_eq!(segments_of(&at_twelve.plan(), "audio_tracks", 11).len(), 1);
}

/// Nest 50 holding media clip 51 (4 s, from 0, action 52 over [2 s, 4 s)
/// linear to `rate`), shown by nest clip 60 at 1 s for 3 s.
fn nested(rate: f64) -> Handle {
    let inner = json!({
        "id": 51, "track": 53, "start": 0, "duration": 4 * SEC,
        "source": { "kind": "media", "media": 1, "in": 0 },
        "actions": [speed_action(52, 2 * SEC, 2 * SEC, "linear", rate)]
    });
    let nest = json!({ "id": 50, "name": "Nest", "width": 1920, "height": 1080,
                       "tracks": [{ "id": 53, "name": "Inner" }], "clips": [inner] });
    let shown = json!({ "id": 60, "track": 2, "start": SEC, "duration": 3 * SEC,
                        "source": { "kind": "nest", "project": 50 } });
    Handle::from_value(&project(vec![shown], vec![nest]))
}

#[test]
fn a_nest_s_tail_cut_truncates_the_video_and_the_audio() {
    let plan = nested(4.0).plan();
    let s = |t: i64| round(s_of(t, 1.0, 4.0, 2 * SEC, 4 * SEC, "linear"));
    let video = segments_of(&plan, "video_tracks", 51);
    let last = &video.last().expect("video segments").1;
    assert_eq!(int(last, "/start") + int(last, "/duration"), 4 * SEC);
    let total: i64 = video.iter().map(|(_, v)| int(v, "/source_duration")).sum();
    assert_eq!(total, s(3 * SEC));
    let audio = segments_of(&plan, "audio_tracks", 51);
    assert_eq!(audio.len(), 1, "{plan}");
    let segment = &audio[0].1;
    assert_eq!(int(segment, "/start"), SEC);
    assert_eq!(int(segment, "/duration"), 3 * SEC);
    assert_eq!(int(segment, "/source_duration"), s(3 * SEC));
    let map = array(segment, "/ramp/map");
    assert_eq!(map.last(), Some(&json!([3 * SEC, s(3 * SEC)])));
    assert_eq!(segment["ramp"]["glide"], json!([[2 * SEC, 3 * SEC]]));
}

#[test]
fn the_x12_test_reads_the_instance_s_own_clip_not_the_nest_s_cut() {
    // The cut ends the ramp at ×10.5, but clip 51 itself reaches ×20 —
    // the figure `SpeedAudioDrop` reads off the snapshot.
    let plan = nested(20.0).plan();
    assert!(segments_of(&plan, "audio_tracks", 51).is_empty(), "{plan}");
    assert!(!segments_of(&plan, "video_tracks", 51).is_empty());
}

#[test]
fn an_action_ending_at_the_rate_in_force_is_held() {
    let mut value = project(
        vec![clip(
            11,
            0,
            3 * SEC,
            0,
            json!([speed_action(21, SEC, SEC, "linear", 2.0)]),
        )],
        vec![],
    );
    value["clips"][0]["speed"] = json!(2.0);
    value["clips"][0]["audio"] = json!({ "keep_pitch": true });
    let plan = Handle::from_value(&value).plan();
    let over: Vec<Value> = segments_of(&plan, "video_tracks", 11)
        .into_iter()
        .map(|(_, s)| s)
        .filter(|s| int(s, "/start") < 2 * SEC && int(s, "/start") + int(s, "/duration") > SEC)
        .collect();
    assert_eq!(over.len(), 1, "{over:?}");
    assert_eq!(int(&over[0], "/start"), SEC);
    assert_eq!(int(&over[0], "/duration"), SEC);
    assert_eq!(int(&over[0], "/source_duration"), 2 * SEC);
    let audio = segments_of(&plan, "audio_tracks", 11);
    assert_eq!(audio[0].1["ramp"]["glide"], json!([]), "{plan}");
}

/// The plan text of `clip` alone, and of the same clip with no actions.
fn plan_and_twin(clip: Value) -> (String, String) {
    let mut twin = clip.clone();
    twin["actions"] = json!([]);
    (
        Handle::from_value(&project(vec![clip], vec![])).plan_text(),
        Handle::from_value(&project(vec![twin], vec![])).plan_text(),
    )
}

#[test]
fn a_clip_with_only_other_actions_plans_as_its_twin() {
    let opacity = json!([{ "id": 21, "start": 0, "duration": SEC,
                           "end": { "video": { "opacity": 0.5 } } }]);
    let (plan, twin) = plan_and_twin(clip(11, 0, 3 * SEC, IN, opacity));
    assert_eq!(plan, twin);
}

#[test]
fn a_speed_end_set_then_removed_plans_as_its_twin() {
    let start = Handle::from_value(&project(
        vec![clip(
            11,
            0,
            3 * SEC,
            IN,
            json!([{ "id": 21, "start": 0, "duration": SEC, "end": {} }]),
        )],
        vec![],
    ));
    let op = |speed: Value| json!({ "op": "set_action_end", "clip": 11, "action": 21, "patch": { "speed": speed } });
    let ramped = start.apply(&op(json!(2)));
    assert_ne!(ramped.plan_text(), start.plan_text());
    let removed = ramped.apply(&op(Value::Null));
    let twin = Handle::from_value(&project(vec![clip(11, 0, 3 * SEC, IN, json!([]))], vec![]));
    assert_eq!(removed.plan_text(), twin.plan_text());
}

#[test]
fn a_still_with_a_hand_written_speed_end_plans_as_its_twin() {
    let still = json!({
        "id": 11, "track": 2, "start": 0, "duration": 3 * SEC,
        "source": { "kind": "still", "media": 1, "at": SEC },
        "actions": [speed_action(21, 0, SEC, "linear", 2.0)]
    });
    let (plan, twin) = plan_and_twin(still);
    assert_eq!(plan, twin);
}
