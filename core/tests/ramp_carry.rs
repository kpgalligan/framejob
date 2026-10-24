//! What copies, re-snaps or holds a RAMPED clip keeps what it reads (spec
//! §6, §11 SR-19 (e)–(h), the road map's M).
//!
//! Pinned here, through the FFI, against closed-form oracles written in this
//! file: `detach_audio`'s twin reads the same map; `paste` — at the same
//! rate, from a 24 fps payload into 30 fps, under `scope` into a nest and
//! inside a pasted nest — keeps a speed action running past the clip's end
//! where it lies, and holds a clip matched to a shorter file; `set_canvas`'s
//! fps re-snap leaves a speed action unclamped, clamps another action as
//! before and holds a clip the new grid makes overrun; `unnest` carries the
//! clip; `relink_media`'s hold to a shorter file is the closed form; and
//! `paste_attributes` carries no profile.

mod common;

use serde_json::{json, Value};

use common::{array, by_id, int, num, Handle};

/// Ticks per second (spec §5.1), written out.
const SEC: i64 = 600_000;
/// One frame at 30 fps.
const FRAME: i64 = 20_000;
/// One frame at 24 fps.
const FRAME_24: i64 = 25_000;
/// The media's path, on both sides of a paste.
const PATH: &str = "/fixtures/carry.mov";

/// S(t) for a clip at `r0` with ONE `linear` speed action over [a, b)
/// ending at `r1`, held after, read on past the clip's end (S∞).
fn s_of(t: i64, r0: f64, r1: f64, a: i64, b: i64) -> f64 {
    let t = t as f64;
    let (a, b) = (a as f64, b as f64);
    let mut s = r0 * t.min(a);
    if t > a {
        let inside = t.min(b) - a;
        s += r0 * inside + (r1 - r0) * (b - a) * (inside / (b - a)).powi(2) / 2.0;
    }
    if t > b {
        s += r1 * (t - b);
    }
    s
}

/// The last grid tick at which S∞ has read no more than `file`: the hold's
/// snapped_down(S∞⁻¹(file)).
fn held(file: i64, frame: i64, r0: f64, r1: f64, a: i64, b: i64) -> i64 {
    (0..)
        .map(|k| k * frame)
        .take_while(|t| s_of(*t, r0, r1, a, b) <= file as f64)
        .last()
        .unwrap()
}

fn media(id: u32, file: i64) -> Value {
    json!({
        "id": id, "path": PATH, "kind": "video", "duration": file,
        "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

fn project(fps: [u32; 2], file: i64, clips: Vec<Value>, nests: Vec<Value>) -> Value {
    json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": fps },
        "media": [media(1, file)],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": clips,
        "nests": nests,
        "next_id": 100
    })
}

fn speed_action(id: u32, start: i64, duration: i64, rate: f64) -> Value {
    json!({ "id": id, "start": start, "duration": duration, "curve": "linear",
            "end": { "speed": rate } })
}

fn opacity_action(id: u32, start: i64, duration: i64) -> Value {
    json!({ "id": id, "start": start, "duration": duration, "curve": "linear",
            "end": { "video": { "opacity": 0.4 } } })
}

/// A 2 s media clip on `track` at `start` from `in` 0 of `media`, holding
/// [0, 4 s) ×1 → ×3 as `trim_end` leaves it: it has read S(2 s) = 3 s.
fn trimmed(id: u32, track: u32, start: i64, media: u32) -> Value {
    json!({
        "id": id, "track": track, "start": start, "duration": 2 * SEC,
        "source": { "kind": "media", "media": media, "in": 0 },
        "speed": 1.0, "video": {}, "audio": {},
        "actions": [speed_action(id + 1, 0, 4 * SEC, 3.0)]
    })
}

/// The clip's audio segments in the plan.
fn audio_segments(handle: &Handle, clip: i64) -> Vec<Value> {
    let plan = handle.plan();
    let mut out = Vec::new();
    for track in array(&plan, "/audio_tracks") {
        for segment in array(track, "/segments") {
            if int(segment, "/clip") == clip {
                out.push(segment.clone());
            }
        }
    }
    out
}

/// The source the plan reads for the clip: its one audio segment's length.
fn planned_source(handle: &Handle, clip: i64) -> i64 {
    let audio = audio_segments(handle, clip);
    assert_eq!(audio.len(), 1, "{audio:?}");
    int(&audio[0], "/source_duration")
}

/// The clip in `clips` that `before` did not have.
fn added(before: &[Value], after: &[Value]) -> Value {
    after
        .iter()
        .find(|c| !before.iter().any(|b| b["id"] == c["id"]))
        .unwrap_or_else(|| panic!("nothing was added to {after:?}"))
        .clone()
}

/// The clip's one speed action's start, duration and end rate.
fn ramp_of(clip: &Value) -> (i64, i64, f64) {
    let ramp = array(clip, "/actions")
        .iter()
        .find(|a| a["end"].get("speed").is_some())
        .unwrap_or_else(|| panic!("no speed action on {clip}"))
        .clone();
    (
        int(&ramp, "/start"),
        int(&ramp, "/duration"),
        num(&ramp, "/end/speed"),
    )
}

fn without_ids(actions: &Value) -> Vec<Value> {
    actions
        .as_array()
        .unwrap()
        .iter()
        .map(|a| {
            let mut a = a.clone();
            a["id"] = json!(0);
            a
        })
        .collect()
}

#[test]
fn detach_audio_s_twin_reads_the_same_map() {
    let mut clip = trimmed(11, 2, SEC, 1);
    clip["actions"]
        .as_array_mut()
        .unwrap()
        .push(opacity_action(13, 0, SEC));
    let handle = Handle::from_value(&project([30, 1], 600 * SEC, vec![clip], vec![]));
    let map_before = audio_segments(&handle, 11)[0]["ramp"]["map"].clone();
    let before = handle.value();
    let after = handle.apply(&json!({ "op": "detach_audio", "clip": 11 }));
    let value = after.value();
    let twin = added(array(&before, "/clips"), array(&value, "/clips"));
    assert_eq!(
        without_ids(&twin["actions"]),
        without_ids(&by_id(&before, "/clips", 11)["actions"])
    );
    let audio = audio_segments(&after, int(&twin, "/id"));
    assert_eq!(audio.len(), 1, "{audio:?}");
    assert_eq!(audio[0]["ramp"]["map"], map_before);
}

#[test]
fn paste_keeps_a_speed_action_past_the_end_at_the_same_rate() {
    let base = Handle::from_value(&project([30, 1], 600 * SEC, vec![], vec![]));
    let mut clip = trimmed(7, 0, 0, 5);
    clip["track"] = json!(0);
    let payload = json!({ "clips": [clip], "media": [media(5, 600 * SEC)] });
    let before = base.value();
    let after = base.apply(&json!({ "op": "paste", "at": SEC, "payload": payload }));
    let value = after.value();
    let pasted = added(array(&before, "/clips"), array(&value, "/clips"));
    assert_eq!(int(&pasted, "/duration"), 2 * SEC);
    assert_eq!(ramp_of(&pasted), (0, 4 * SEC, 3.0));
    assert!((planned_source(&after, int(&pasted, "/id")) - 1_800_000).abs() <= 1);
}

#[test]
fn paste_from_24_fps_into_30_snaps_a_speed_action_without_clamping_it() {
    let base = Handle::from_value(&project([30, 1], 600 * SEC, vec![], vec![]));
    let mut clip = trimmed(7, 0, 0, 5);
    // On the 24 fps grid and not on the 30: 97 frames of 24.
    clip["actions"][0]["duration"] = json!(97 * FRAME_24);
    let payload = json!({ "clips": [clip], "media": [media(5, 600 * SEC)] });
    let before = base.value();
    let value = base
        .apply(&json!({ "op": "paste", "at": SEC, "payload": payload }))
        .value();
    let pasted = added(array(&before, "/clips"), array(&value, "/clips"));
    assert_eq!(int(&pasted, "/duration"), 2 * SEC);
    // 2 425 000 is 121.25 frames of 30: snapped to 121, and past the end.
    assert_eq!(ramp_of(&pasted), (0, 121 * FRAME, 3.0));
}

#[test]
fn paste_under_scope_and_a_pasted_nest_keep_the_speed_action() {
    // Under `scope` into nest 50.
    let nest = json!({ "id": 50, "name": "Nest", "width": 1920, "height": 1080,
                       "tracks": [{ "id": 53, "name": "Inner" }], "clips": [] });
    let shown = json!({ "id": 60, "track": 2, "start": 0, "duration": 10 * SEC,
                        "source": { "kind": "nest", "project": 50 } });
    let base = Handle::from_value(&project([30, 1], 600 * SEC, vec![shown], vec![nest]));
    let mut clip = trimmed(7, 0, 0, 5);
    clip["actions"][0]["duration"] = json!(97 * FRAME_24);
    let payload = json!({ "clips": [clip.clone()], "media": [media(5, 600 * SEC)] });
    let value = base
        .apply(&json!({ "op": "paste", "at": SEC, "payload": payload, "scope": 50 }))
        .value();
    let inside = array(by_id(&value, "/nests", 50), "/clips");
    assert_eq!(inside.len(), 1, "{inside:?}");
    assert_eq!(int(&inside[0], "/duration"), 2 * SEC);
    assert_eq!(ramp_of(&inside[0]), (0, 121 * FRAME, 3.0));

    // Inside a nest the payload brings.
    let base = Handle::from_value(&project([30, 1], 600 * SEC, vec![], vec![]));
    let mut inner = clip;
    inner["track"] = json!(42);
    let payload = json!({
        "clips": [{ "id": 40, "track": 0, "start": 0, "duration": 4 * SEC,
                    "source": { "kind": "nest", "project": 43 }, "video": {} }],
        "media": [media(5, 600 * SEC)],
        "nests": [{ "id": 43, "width": 1920, "height": 1080,
                    "tracks": [{ "id": 42, "name": "Inner" }], "clips": [inner] }]
    });
    let value = base
        .apply(&json!({ "op": "paste", "at": 0, "payload": payload }))
        .value();
    let nested = &array(&value, "/nests")[0];
    let inside = array(nested, "/clips");
    assert_eq!(int(&inside[0], "/duration"), 2 * SEC);
    assert_eq!(ramp_of(&inside[0]), (0, 121 * FRAME, 3.0));
}

#[test]
fn paste_matched_to_a_shorter_file_is_held_and_fits() {
    // The project's own record of the path is 2.5 s; the payload's says
    // 600 s. The clip reads S(2 s) = 3 s, so it is held.
    let file = 1_500_000;
    let base = Handle::from_value(&project([30, 1], file, vec![], vec![]));
    let mut clip = trimmed(7, 0, 0, 5);
    clip["track"] = json!(0);
    let payload = json!({ "clips": [clip], "media": [media(5, 600 * SEC)] });
    let before = base.value();
    let after = base.apply(&json!({ "op": "paste", "at": SEC, "payload": payload }));
    let value = after.value();
    assert_eq!(array(&value, "/media").len(), 1);
    let pasted = added(array(&before, "/clips"), array(&value, "/clips"));
    let expected = held(file, FRAME, 1.0, 3.0, 0, 4 * SEC);
    assert_eq!(expected, 1_040_000);
    assert_eq!(int(&pasted, "/duration"), expected);
    assert_eq!(ramp_of(&pasted), (0, 4 * SEC, 3.0));
    assert!(planned_source(&after, int(&pasted, "/id")) <= file);
}

#[test]
fn set_canvas_fps_leaves_a_speed_action_unclamped_and_clamps_the_others() {
    let mut clip = trimmed(11, 2, SEC, 1);
    // An opacity action running past the end too, as `trim_end` leaves it.
    clip["actions"]
        .as_array_mut()
        .unwrap()
        .push(opacity_action(13, SEC + SEC / 2, SEC));
    let handle = Handle::from_value(&project([30, 1], 600 * SEC, vec![clip], vec![]));
    let value = handle
        .apply(&json!({ "op": "set_canvas", "fps": [24, 1] }))
        .value();
    let clip = by_id(&value, "/clips", 11);
    assert_eq!(int(clip, "/duration"), 2 * SEC);
    assert_eq!(ramp_of(clip), (0, 4 * SEC, 3.0));
    let other = by_id(clip, "/actions", 13);
    assert_eq!(int(other, "/start"), SEC + SEC / 2);
    assert_eq!(int(other, "/duration"), SEC / 2, "clamped into the clip");
}

#[test]
fn a_re_snap_that_would_read_past_the_file_is_held_by_the_second_pass() {
    // [260 000, 860 000) ×1 → ×3 on a 2 s clip reads S(2 s) = 2 480 000:
    // exactly the file at 30 fps. At 24 fps the action starts at 250 000
    // and the clip would read 2 500 000.
    let file = 2_480_000;
    let clip = json!({
        "id": 11, "track": 2, "start": SEC, "duration": 2 * SEC,
        "source": { "kind": "media", "media": 1, "in": 0 },
        "speed": 1.0, "video": {}, "audio": {},
        "actions": [speed_action(12, 260_000, SEC, 3.0)]
    });
    assert_eq!(s_of(2 * SEC, 1.0, 3.0, 260_000, 860_000), file as f64);
    let handle = Handle::from_value(&project([30, 1], file, vec![clip], vec![]));
    let after = handle.apply(&json!({ "op": "set_canvas", "fps": [24, 1] }));
    let value = after.value();
    let clip = by_id(&value, "/clips", 11);
    assert_eq!(ramp_of(clip), (250_000, SEC, 3.0));
    let expected = held(file, FRAME_24, 1.0, 3.0, 250_000, 850_000);
    assert!(expected < 2 * SEC);
    assert_eq!(int(clip, "/duration"), expected);
    assert!(planned_source(&after, 11) <= file);
}

#[test]
fn unnest_carries_the_speed_action_past_the_end() {
    let nest = json!({ "id": 50, "name": "Nest", "width": 1920, "height": 1080,
                       "tracks": [{ "id": 53, "name": "Inner" }],
                       "clips": [trimmed(51, 53, 0, 1)] });
    let shown = json!({ "id": 60, "track": 2, "start": SEC, "duration": 2 * SEC,
                        "source": { "kind": "nest", "project": 50 } });
    let handle = Handle::from_value(&project([30, 1], 600 * SEC, vec![shown], vec![nest]));
    let after = handle.apply(&json!({ "op": "unnest", "clip": 60 }));
    let value = after.value();
    let clips = array(&value, "/clips");
    assert_eq!(clips.len(), 1, "{clips:?}");
    let opened = &clips[0];
    assert_eq!(int(opened, "/start"), SEC);
    assert_eq!(int(opened, "/duration"), 2 * SEC);
    assert_eq!(ramp_of(opened), (0, 4 * SEC, 3.0));
    assert!((planned_source(&after, int(opened, "/id")) - 1_800_000).abs() <= 1);
}

#[test]
fn relink_to_a_shorter_file_holds_to_the_closed_form() {
    let handle = Handle::from_value(&project(
        [30, 1],
        600 * SEC,
        vec![trimmed(11, 2, SEC, 1)],
        vec![],
    ));
    let file = 1_500_000;
    let probe = json!({ "kind": "video", "duration": file, "width": 1920, "height": 1080,
                        "fps": [30, 1], "has_video": true, "has_audio": true,
                        "has_alpha": false });
    let after = handle.apply(&json!({ "op": "relink_media", "media": 1,
                                      "path": "/fixtures/short.mov", "probe": probe }));
    let value = after.value();
    let clip = by_id(&value, "/clips", 11);
    assert_eq!(
        int(clip, "/duration"),
        held(file, FRAME, 1.0, 3.0, 0, 4 * SEC)
    );
    assert_eq!(
        clip["actions"],
        by_id(&handle.value(), "/clips", 11)["actions"]
    );
    assert!(planned_source(&after, 11) <= file);
}

#[test]
fn paste_attributes_carries_no_profile() {
    let constant = json!({
        "id": 21, "track": 2, "start": 4 * SEC, "duration": 2 * SEC,
        "source": { "kind": "media", "media": 1, "in": 0 },
        "speed": 1.5, "video": {}, "audio": {}
    });
    let handle = Handle::from_value(&project(
        [30, 1],
        600 * SEC,
        vec![trimmed(11, 2, SEC, 1), constant],
        vec![],
    ));
    let mut source = trimmed(7, 0, 0, 5);
    source["speed"] = json!(2.0);
    source["actions"] = json!([speed_action(8, 0, SEC, 9.0)]);
    source["video"] = json!({ "opacity": 0.5 });
    let payload = json!({ "clips": [source], "media": [media(5, 600 * SEC)] });
    let before = handle.value();
    let value = handle
        .apply(&json!({ "op": "paste_attributes", "clips": [11, 21], "payload": payload }))
        .value();
    for id in [11, 21] {
        let (was, now) = (by_id(&before, "/clips", id), by_id(&value, "/clips", id));
        assert_eq!(now["speed"], was["speed"], "clip {id}");
        assert_eq!(now["actions"], was["actions"], "clip {id}");
        assert_eq!(now["duration"], was["duration"], "clip {id}");
        assert_eq!(num(now, "/video/opacity"), 0.5, "clip {id}");
    }
}
