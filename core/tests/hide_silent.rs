//! Hide while silent (format 43, spec §11 CO-90…CO-93), through the FFI.
//!
//! Every gate is checked against an oracle written here from CO-90's words:
//! the containers outward from the layer's own, the nearest one in which an
//! instance of the media covers `t`, every instance's speech in it projected
//! at its OWN origin and kept to its played window, widened by pre-roll and
//! hold, merged, and the maximum of 1 inside and a straight ramp to 0 over
//! `fade` either side. The oracle reads every instance (no window), so the
//! core's windowed read is pinned equal to the unwindowed one. Pinned too:
//! `clip_state` and `get_project` un-gated; a media with no speech, an empty
//! speech list, no instance covering; Side at a mic clip's end through the
//! plan's `gates`; every refusal in its sentence; not animatable and the
//! base restored; split, the blurred copy, paste and Paste Attributes
//! across documents (row present → remapped; absent → no gate; a target's
//! own media of the same id not followed); `remove_media` clearing a gate
//! inside a nest; `keep_range` keeping the gate's media; and a project
//! whose gate follows a speechless media drawing and planning byte for
//! byte as the same project with no gate.

mod common;

use serde_json::{json, Value};

use common::{array, at, by_id, int, num, Handle};

const SEC: i64 = 600_000;
const PRE: i64 = 120_000;
const HOLD: i64 = 900_000;
const FADE: i64 = 180_000;
/// One frame at 30 fps.
const FRAME: i64 = 20_000;
const EPS: f64 = 1e-9;

/// The mic's speech, source ticks: 2–4 s and 10–11 s.
fn speech() -> Value {
    json!([[2 * SEC, 4 * SEC], [10 * SEC, 11 * SEC]])
}

/// Media 1 the mic (audio only), 2 the camera (no sound), 3 a music bed.
fn media(speech: Option<Value>) -> Value {
    let mut mic = json!({"id": 1, "path": "/fixtures/mic.m4a", "kind": "audio",
                         "duration": 60 * SEC, "has_audio": true});
    if let Some(speech) = speech {
        mic["speech"] = speech;
    }
    json!([mic,
        {"id": 2, "path": "/fixtures/camera.mov", "kind": "video", "duration": 60 * SEC,
         "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": false},
        {"id": 3, "path": "/fixtures/music.m4a", "kind": "audio", "duration": 60 * SEC,
         "has_audio": true}])
}

fn gate(media: u32) -> Value {
    json!({"media": media, "pre_roll": PRE, "hold": HOLD, "fade": FADE})
}

/// Camera clip 20 (track 10, 0–30 s, gated by media 1) and mic clips
/// `mics` (`[id, start, duration, in]`, track 11).
fn project(speech: Option<Value>, mics: &[[i64; 4]], camera_gate: Option<Value>) -> Handle {
    camera_at(speech, mics, camera_gate, (0, 30 * SEC))
}

/// `project`, the camera over `[from, to)`.
fn camera_at(
    speech: Option<Value>,
    mics: &[[i64; 4]],
    camera_gate: Option<Value>,
    (from, to): (i64, i64),
) -> Handle {
    let mut clips = vec![
        json!({"id": 20, "track": 10, "start": from, "duration": to - from,
        "source": {"kind": "media", "media": 2, "in": 0},
        "video": camera_gate.map_or(json!({}), |g| json!({"hide_silent": g}))}),
    ];
    for [id, start, duration, source_in] in mics {
        clips.push(
            json!({"id": id, "track": 11, "start": start, "duration": duration,
            "source": {"kind": "media", "media": 1, "in": source_in}}),
        );
    }
    Handle::from_value(&json!({
        "version": 43,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": media(speech),
        "tracks": [{"id": 10, "name": "Camera"}, {"id": 11, "name": "Mic"},
                   {"id": 12, "name": "Mic 2"}],
        "clips": clips,
        "next_id": 100
    }))
}

fn simple() -> Handle {
    project(Some(speech()), &[[21, 0, 20 * SEC, 0]], Some(gate(1)))
}

/// An instance of the mic for the oracle: its container path, its played
/// window, its origin and its source in point.
#[derive(Clone)]
struct Inst {
    path: Vec<i64>,
    start: i64,
    end: i64,
    origin: i64,
    source_in: i64,
}

fn covers(i: &Inst, t: i64, left: bool) -> bool {
    if left {
        i.start < t && t <= i.end
    } else {
        i.start <= t && t < i.end
    }
}

/// CO-90 written out: the nearest container outward from `layer` with a
/// covering instance; every instance there projected at its own origin.
fn oracle(insts: &[Inst], spans: &[[i64; 2]], layer: &[i64], t: i64, left: bool) -> f64 {
    for depth in (0..=layer.len()).rev() {
        let container = &layer[..depth];
        let members: Vec<&Inst> = insts
            .iter()
            .filter(|i| i.path.starts_with(container))
            .collect();
        if !members.iter().any(|i| covers(i, t, left)) {
            continue;
        }
        let mut projected: Vec<(i64, i64)> = Vec::new();
        for i in members {
            for [a, b] in spans {
                let (a, b) = (i.origin + a - i.source_in, i.origin + b - i.source_in);
                let (a, b) = (a.max(i.start), b.min(i.end));
                if b > a {
                    projected.push((a, b));
                }
            }
        }
        projected.sort();
        let mut merged: Vec<(i64, i64)> = Vec::new();
        for (a, b) in projected {
            let (a, b) = (a - PRE, b + HOLD);
            match merged.last_mut() {
                Some(last) if a <= last.1 => last.1 = last.1.max(b),
                _ => merged.push((a, b)),
            }
        }
        return merged
            .iter()
            .map(|&(s, e)| {
                let off = if t < s {
                    s - t
                } else if t > e {
                    t - e
                } else {
                    0
                };
                (1.0 - off as f64 / FADE as f64).max(0.0)
            })
            .fold(0.0, f64::max);
    }
    1.0
}

fn timeline_mics(mics: &[[i64; 4]]) -> Vec<Inst> {
    mics.iter()
        .map(|&[_, start, duration, source_in]| Inst {
            path: vec![],
            start,
            end: start + duration,
            origin: start,
            source_in,
        })
        .collect()
}

/// The opacity the recipe draws clip `clip` at, or `None` with no layer.
fn opacity(handle: &Handle, clip: i64, t: i64) -> Option<f64> {
    array(&handle.recipe(t), "/layers")
        .iter()
        .find(|l| l["clip"] == json!(clip))
        .map(|l| num(l, "/opacity"))
}

fn speech_spans() -> Vec<[i64; 2]> {
    vec![[2 * SEC, 4 * SEC], [10 * SEC, 11 * SEC]]
}

#[test]
fn the_gate_is_one_in_each_widened_span_zero_in_a_gap_and_half_at_the_fades() {
    let handle = simple();
    let insts = timeline_mics(&[[21, 0, 20 * SEC, 0]]);
    for t in (0..30 * SEC).step_by(FRAME as usize) {
        let want = oracle(&insts, &speech_spans(), &[], t, false);
        let got = opacity(&handle, 20, t).expect("a layer");
        assert!((got - want).abs() < EPS, "t {t}: {got} against {want}");
    }
    assert_eq!(opacity(&handle, 20, 3 * SEC), Some(1.0));
    assert_eq!(opacity(&handle, 20, 7 * SEC), Some(0.0));
    let e = 4 * SEC + HOLD + FADE / 2;
    let s = 10 * SEC - PRE - FADE / 2;
    assert!((opacity(&handle, 20, e).expect("layer") - 0.5).abs() < EPS);
    assert!((opacity(&handle, 20, s).expect("layer") - 0.5).abs() < EPS);
    // Past the mic's end nothing of the media plays: the camera shows.
    assert_eq!(opacity(&handle, 20, 25 * SEC), Some(1.0));
}

#[test]
fn the_windowed_gate_equals_the_unwindowed_one_over_a_mic_cut_in_pieces() {
    let spans: Vec<[i64; 2]> = (0..80)
        .map(|k| [k * 7 * SEC / 10, k * 7 * SEC / 10 + 3 * SEC / 10])
        .collect();
    let mics = [
        [21, 0, 5 * SEC, 0],
        [22, 5 * SEC, 5 * SEC, 12 * SEC],
        [23, 10 * SEC, 8 * SEC, 30 * SEC],
        [24, 20 * SEC, 4 * SEC, 3 * SEC],
    ];
    let handle = project(Some(json!(spans)), &mics, Some(gate(1)));
    let insts = timeline_mics(&mics);
    for t in (0..30 * SEC).step_by((FRAME / 2) as usize) {
        let want = oracle(&insts, &spans, &[], t, false);
        let got = opacity(&handle, 20, t).expect("a layer");
        assert!((got - want).abs() < EPS, "t {t}: {got} against {want}");
    }
}

#[test]
fn clip_state_and_get_project_read_the_clip_ungated() {
    let handle = simple();
    assert_eq!(opacity(&handle, 20, 7 * SEC), Some(0.0));
    let state = handle.clip_state(20, 7 * SEC).expect("state");
    assert_eq!(at(&state, "/video/opacity"), &json!(1.0));
    assert_eq!(at(&state, "/video/hide_silent"), &gate(1));
    let value = handle.value();
    let camera = by_id(&value, "/clips", 20);
    assert!(camera["video"]
        .get("opacity")
        .is_none_or(|o| *o == json!(1.0)));
    assert_eq!(camera["video"]["hide_silent"], gate(1));
}

#[test]
fn no_speech_shows_the_camera_and_an_empty_list_hides_it_where_the_mic_plays() {
    let none = project(None, &[[21, 0, 20 * SEC, 0]], Some(gate(1)));
    assert_eq!(opacity(&none, 20, 7 * SEC), Some(1.0));
    let empty = project(Some(json!([])), &[[21, 0, 20 * SEC, 0]], Some(gate(1)));
    assert_eq!(opacity(&empty, 20, 3 * SEC), Some(0.0));
    assert_eq!(opacity(&empty, 20, 25 * SEC), Some(1.0));
}

#[test]
fn a_gate_on_a_speechless_media_draws_and_plans_byte_for_byte_as_none() {
    let gated = project(None, &[[21, 0, 20 * SEC, 0]], Some(gate(1)));
    let plain = project(None, &[[21, 0, 20 * SEC, 0]], None);
    for t in [0, 3 * SEC, 7 * SEC, 25 * SEC] {
        assert_eq!(gated.recipe_text(t), plain.recipe_text(t), "t {t}");
    }
    assert_eq!(gated.plan_text(), plain.plan_text());
    assert!(!plain.plan_text().contains("\"gates\""));
}

/// The plan's ramps against the oracle, each end and each midpoint, tiling
/// the clip's `[from, to)`.
fn check_ramps(
    handle: &Handle,
    clip: i64,
    insts: &[Inst],
    spans: &[[i64; 2]],
    (from_t, to_t): (i64, i64),
) {
    let plan = handle.plan();
    let entry = array(&plan, "/gates")
        .iter()
        .find(|g| g["clip"] == json!(clip))
        .expect("a gate entry")
        .clone();
    let ramps = array(&entry, "/ramps");
    assert_eq!(int(&ramps[0], "/start"), from_t);
    let mut edge = from_t;
    for ramp in ramps {
        let (a, d) = (int(ramp, "/start"), int(ramp, "/duration"));
        assert_eq!(a, edge, "the ramps tile the clip");
        edge = a + d;
        let (from, to) = (num(ramp, "/from"), num(ramp, "/to"));
        assert!(
            (from - oracle(insts, spans, &[], a, false)).abs() < EPS,
            "from at {a}"
        );
        assert!(
            (to - oracle(insts, spans, &[], a + d, true)).abs() < EPS,
            "to at {}",
            a + d
        );
        let mid = a + d / 2;
        let line = from + (to - from) * (mid - a) as f64 / d as f64;
        assert!(
            (line - oracle(insts, spans, &[], mid, false)).abs() < 1e-5,
            "mid {mid}"
        );
    }
    assert_eq!(edge, to_t);
}

#[test]
fn the_plans_gates_tile_the_clip_and_read_each_side_at_the_mics_end() {
    let handle = simple();
    let insts = timeline_mics(&[[21, 0, 20 * SEC, 0]]);
    check_ramps(&handle, 20, &insts, &speech_spans(), (0, 30 * SEC));
    // At the mic's end the gate jumps: 0 from the left, 1 from the right.
    let quiet = project(
        Some(json!([[SEC, 2 * SEC]])),
        &[[21, 0, 20 * SEC, 0]],
        Some(gate(1)),
    );
    let ramps = array(&quiet.plan(), "/gates/0/ramps").clone();
    let into = ramps
        .iter()
        .find(|r| int(r, "/start") + int(r, "/duration") == 20 * SEC)
        .expect("ramp to 20 s");
    let after = ramps
        .iter()
        .find(|r| int(r, "/start") == 20 * SEC)
        .expect("ramp from 20 s");
    assert_eq!((num(into, "/to"), num(after, "/from")), (0.0, 1.0));
    // Close spans: the fall and the rise meet at the midpoint.
    let close = project(
        Some(json!([[2 * SEC, 3 * SEC], [49 * SEC / 10, 6 * SEC]])),
        &[[21, 0, 20 * SEC, 0]],
        Some(gate(1)),
    );
    check_ramps(
        &close,
        20,
        &insts,
        &[[2 * SEC, 3 * SEC], [49 * SEC / 10, 6 * SEC]],
        (0, 30 * SEC),
    );
}

#[test]
fn a_short_cameras_ramps_read_only_the_mics_near_it_and_equal_the_oracle() {
    // A camera over 12–18 s: `gate_ramps`' window, `[10.2 s, 18.5 s]`,
    // drops mics 21 and 22 on the left and 24 on the right, while the
    // oracle reads every instance.
    let spans: Vec<[i64; 2]> = (0..80)
        .map(|k| [k * 7 * SEC / 10, k * 7 * SEC / 10 + 3 * SEC / 10])
        .collect();
    let mics = [
        [21, 0, 5 * SEC, 0],
        [22, 5 * SEC, 5 * SEC, 12 * SEC],
        [23, 10 * SEC, 8 * SEC, 30 * SEC],
        [24, 20 * SEC, 4 * SEC, 3 * SEC],
    ];
    let span = (12 * SEC, 18 * SEC);
    let handle = camera_at(Some(json!(spans)), &mics, Some(gate(1)), span);
    check_ramps(&handle, 20, &timeline_mics(&mics), &spans, span);
}

#[test]
fn every_refusal_in_its_sentence() {
    let handle = simple();
    let set = |clip: i64, g: Value| json!({"op": "set_video", "clips": [clip], "patch": {"hide_silent": g}});
    for key in ["pre_roll", "hold", "fade"] {
        let mut g = gate(1);
        g[key] = json!(3_000_001);
        let error = handle.errors(&set(20, g));
        assert!(
            error.contains(&format!(
                "video.hide_silent.{key} must be between 0 and 3000000 ticks, not 3000001"
            )),
            "{error}"
        );
    }
    let error = handle.errors(&set(20, json!({"media": 0})));
    assert!(
        error.contains(
            "video.hide_silent.media is required: the media whose speech the clip follows"
        ),
        "{error}"
    );
    let error = handle.errors(&set(20, json!({"media": 9})));
    assert!(
        error.contains("video.hide_silent.media 9 is not a media of this project"),
        "{error}"
    );
    let error = handle.errors(&set(20, json!({"media": 2})));
    assert!(
        error.contains("video.hide_silent.media 2 has no sound to follow"),
        "{error}"
    );
    let nested = handle.apply(&json!({"op": "nest", "clips": [21]}));
    let nest = array(&nested.value(), "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("nest"))
        .map(|c| int(c, "/id"))
        .expect("a nest clip");
    let error = nested.errors(&set(nest, json!({"media": 1})));
    assert!(
        error.contains(&format!(
            "clip {nest} shows a nest and cannot hide while silent: set it on the clips inside"
        )),
        "{error}"
    );
    // A patch merges: `{media: 3}` keeps the defaults it does not name.
    let plain = project(Some(speech()), &[[21, 0, 20 * SEC, 0]], None);
    let set3 = plain.apply(&set(20, json!({"media": 3})));
    assert_eq!(
        by_id(&set3.value(), "/clips", 20)["video"]["hide_silent"],
        gate(3)
    );
    let cleared = set3.apply(&set(20, Value::Null));
    assert!(by_id(&cleared.value(), "/clips", 20)["video"]
        .get("hide_silent")
        .is_none());
}

#[test]
fn it_is_not_an_animation_target_and_the_base_comes_back_over_an_end() {
    let handle =
        simple().apply(&json!({"op": "add_action", "clip": 20, "at": 0, "duration": 10 * SEC}));
    let action = int(&by_id(&handle.value(), "/clips", 20)["actions"][0], "/id");
    for patch in [
        json!({"video": {"hide_silent": {"fade": 0}}}),
        json!({"video": {"hide_silent": null}}),
    ] {
        let error = handle.errors(
            &json!({"op": "set_action_end", "clip": 20, "action": action,
                                          "patch": patch}),
        );
        assert!(
            error.contains("video.hide_silent is not an animation target"),
            "{error}"
        );
    }
    let error = handle.errors(
        &json!({"op": "set_action_end", "clip": 20, "action": action,
                                      "patch": {}, "off": ["video.hide_silent"]}),
    );
    assert!(
        error.contains("video.hide_silent is not an animation target"),
        "{error}"
    );
    // A hand-written end that names it is drawn with the base's gate.
    let mut value = handle.value();
    value["clips"][0]["actions"][0]["end"] =
        json!({"video": {"hide_silent": {"media": 3, "fade": 0}}});
    let written = Handle::from_value(&value);
    let state = written.clip_state(20, 10 * SEC).expect("state");
    assert_eq!(at(&state, "/video/hide_silent"), &gate(1));
    assert!(
        (opacity(&written, 20, 5 * SEC + HOLD).expect("layer")
            - opacity(&simple(), 20, 5 * SEC + HOLD).expect("layer"))
        .abs()
            < EPS
    );
    // With no base gate the end's is dropped.
    value["clips"][0]["video"] = json!({});
    let ungated = Handle::from_value(&value);
    assert!(ungated.clip_state(20, 10 * SEC).expect("state")["video"]
        .get("hide_silent")
        .is_none());
    assert_eq!(opacity(&ungated, 20, 7 * SEC), Some(1.0));
}

#[test]
fn split_and_the_blurred_copy_keep_the_gate() {
    let split = simple().apply(&json!({"op": "split", "clips": [20], "at": 6 * SEC}));
    let value = split.value();
    let cameras: Vec<&Value> = array(&value, "/clips")
        .iter()
        .filter(|c| c["source"]["media"] == json!(2))
        .collect();
    assert_eq!(cameras.len(), 2);
    for camera in cameras {
        assert_eq!(camera["video"]["hide_silent"], gate(1));
    }
    let blurred = simple().apply(&json!({"op": "add_blurred_background", "clip": 20}));
    let value = blurred.value();
    let copies = array(&value, "/clips")
        .iter()
        .filter(|c| c["source"]["media"] == json!(2))
        .count();
    assert_eq!(copies, 2);
    for camera in array(&value, "/clips")
        .iter()
        .filter(|c| c["source"]["media"] == json!(2))
    {
        assert_eq!(camera["video"]["hide_silent"], gate(1));
    }
}

/// The camera nested apart from the mic follows the mic outside; with a
/// second mic beside it in the nest, that one wins where it plays.
#[test]
fn a_nested_camera_reads_the_nearest_container_with_the_mic() {
    let handle = simple();
    let nested = handle.apply(&json!({"op": "nest", "clips": [20]}));
    let value = nested.value();
    let inner = int(&array(&value, "/nests/0/clips")[0], "/id");
    let nest = array(&value, "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("nest"))
        .map(|c| int(c, "/id"))
        .expect("a nest clip");
    let insts = timeline_mics(&[[21, 0, 20 * SEC, 0]]);
    for t in (0..30 * SEC).step_by((FRAME * 3) as usize) {
        let want = oracle(&insts, &speech_spans(), &[nest], t, false);
        let got = opacity(&nested, inner, t).expect("a layer");
        assert!((got - want).abs() < EPS, "t {t}: {got} against {want}");
    }
    // Mic 25 (in 10 s, 0–10 s, track 12) nested with the camera.
    let mut both = handle.value();
    both["clips"].as_array_mut().expect("clips").push(json!({"id": 25, "track": 12,
        "start": 0, "duration": 10 * SEC, "source": {"kind": "media", "media": 1, "in": 10 * SEC}}));
    let both = Handle::from_value(&both).apply(&json!({"op": "nest", "clips": [20, 25]}));
    let value = both.value();
    let nest = array(&value, "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("nest"))
        .map(|c| int(c, "/id"))
        .expect("a nest clip");
    let inner = array(&value, "/nests/0/clips")
        .iter()
        .find(|c| c["source"]["media"] == json!(2))
        .map(|c| int(c, "/id"))
        .expect("the camera");
    let mut insts = timeline_mics(&[[21, 0, 20 * SEC, 0]]);
    insts.push(Inst {
        path: vec![nest],
        start: 0,
        end: 10 * SEC,
        origin: 0,
        source_in: 10 * SEC,
    });
    for t in (0..30 * SEC).step_by((FRAME * 3) as usize) {
        let want = oracle(&insts, &speech_spans(), &[nest], t, false);
        let got = opacity(&both, inner, t).expect("a layer");
        assert!((got - want).abs() < EPS, "t {t}: {got} against {want}");
    }
    // Inside, at 3 s only the nested mic's speech (10–11 s at 0–1 s) counts.
    assert_eq!(opacity(&both, inner, 3 * SEC), Some(0.0));
    // remove_media clears the gate inside the nest too.
    let removed = both.apply(&json!({"op": "remove_media", "media": 1, "with_clips": true}));
    let value = removed.value();
    let camera = array(&value, "/nests/0/clips")
        .iter()
        .find(|c| c["source"]["media"] == json!(2))
        .expect("the camera");
    assert!(camera["video"].get("hide_silent").is_none(), "{camera}");
    assert_eq!(opacity(&removed, inner, 7 * SEC), Some(1.0));
}

#[test]
fn remove_media_clears_the_gate_and_refuses_nothing_new() {
    let removed = simple().apply(&json!({"op": "remove_media", "media": 1, "with_clips": true}));
    assert!(by_id(&removed.value(), "/clips", 20)["video"]
        .get("hide_silent")
        .is_none());
    assert_eq!(opacity(&removed, 20, 7 * SEC), Some(1.0));
    // Without with_clips the mic clip is still in use and that is the refusal.
    simple().refuses(&json!({"op": "remove_media", "media": 1}));
    // The camera alone does not use the mic.
    let only = simple().apply(&json!({"op": "delete", "clips": [21]}));
    let gone = only.apply(&json!({"op": "remove_media", "media": 1}));
    assert!(by_id(&gone.value(), "/clips", 20)["video"]
        .get("hide_silent")
        .is_none());
}

#[test]
fn keep_range_keeps_the_gates_media() {
    let handle = project(Some(speech()), &[[21, 25 * SEC, 5 * SEC, 0]], Some(gate(1)));
    let kept = handle.apply(&json!({"op": "keep_range", "from": 0, "to": 10 * SEC}));
    let ids: Vec<i64> = array(&kept.value(), "/media")
        .iter()
        .map(|m| int(m, "/id"))
        .collect();
    assert!(ids.contains(&1), "{ids:?}");
    assert!(!ids.contains(&3), "{ids:?}");
}

/// A payload of the camera clip, with the mic's row when `row`.
fn payload(row: bool) -> Value {
    let value = simple().value();
    let mut clip = by_id(&value, "/clips", 20).clone();
    clip["track"] = json!(0);
    clip["video"]["x"] = json!(40.0);
    let rows: Vec<Value> = array(&value, "/media")
        .iter()
        .filter(|m| m["id"] == json!(2) || (row && m["id"] == json!(1)))
        .cloned()
        .collect();
    json!({"clips": [clip], "media": rows})
}

/// Another project: media 1 is a music bed here, the camera at id 4, the
/// mic's file at id 5.
fn elsewhere() -> Handle {
    Handle::from_value(&json!({
        "version": 43,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/fixtures/bed.m4a", "kind": "audio",
                   "duration": 60 * SEC, "has_audio": true},
                  {"id": 4, "path": "/fixtures/camera.mov", "kind": "video", "duration": 60 * SEC,
                   "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true,
                   "has_audio": false},
                  {"id": 5, "path": "/fixtures/mic.m4a", "kind": "audio",
                   "duration": 60 * SEC, "has_audio": true}],
        "tracks": [{"id": 6, "name": "Track 1"}],
        "clips": [{"id": 7, "track": 6, "start": 0, "duration": 30 * SEC,
                   "source": {"kind": "media", "media": 4, "in": 0}, "video": {}}],
        "next_id": 50
    }))
}

#[test]
fn paste_carries_the_gates_media_by_path_and_drops_a_gate_without_its_row() {
    let pasted =
        elsewhere().apply(&json!({"op": "paste", "at": 40 * SEC, "payload": payload(true)}));
    let value = pasted.value();
    let clip = array(&value, "/clips")
        .iter()
        .find(|c| int(c, "/id") >= 50)
        .expect("pasted");
    assert_eq!(clip["video"]["hide_silent"], gate(5));
    assert_eq!(array(&value, "/media").len(), 3);
    let bare =
        elsewhere().apply(&json!({"op": "paste", "at": 40 * SEC, "payload": payload(false)}));
    let value = bare.value();
    let clip = array(&value, "/clips")
        .iter()
        .find(|c| int(c, "/id") >= 50)
        .expect("pasted");
    assert!(clip["video"].get("hide_silent").is_none(), "{clip}");
}

#[test]
fn paste_attributes_carries_the_gates_media_and_never_follows_the_targets_own_id() {
    let pasted = elsewhere().apply(&json!({"op": "paste_attributes", "clips": [7],
                                           "payload": payload(true)}));
    assert_eq!(
        by_id(&pasted.value(), "/clips", 7)["video"]["hide_silent"],
        gate(5)
    );
    let bare = elsewhere().apply(&json!({"op": "paste_attributes", "clips": [7],
                                         "payload": payload(false)}));
    assert!(by_id(&bare.value(), "/clips", 7)["video"]
        .get("hide_silent")
        .is_none());
}
