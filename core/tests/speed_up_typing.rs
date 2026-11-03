//! Speed Up Typing's planner (road map creator-jobs CU9b, spec §11 CU-91,
//! CU-92), black box through `rc_cursor_open` and `rc_cursor_query`'s
//! `plan_typing` as `SpeedUpTyping.swift` calls it, its ops applied through
//! `rc_project_apply`. Every expected tick is worked by hand from CU-91 at
//! 30 fps (a frame is 20,000 ticks), never read back from the code: the
//! margins, speech cut back, a shortcut's overlay kept at ×1 (its
//! Shortcuts-track clip, else 1.5 s), a press before `from`, two clips
//! united before `shortest`, `needs_speech`, sync across three tracks after
//! two ranges answered right to left, a ×2 clip and a ramp through S,
//! all or nothing, and every refusal in CU-92's order.

mod common;

use std::ffi::{c_char, CString};
use std::ptr;

use common::{take_string, Handle};
use framejob_core::cursor_track::CursorTrack;
use framejob_core::ffi_cursor::{rc_cursor_free, rc_cursor_open, rc_cursor_query};
use serde_json::{json, Value};

const SEC: i64 = 600_000;

fn t(seconds: f64) -> i64 {
    (seconds * SEC as f64).round() as i64
}

/// Typing marks every 0.25 s from `a` to `b` s, `b` included.
fn typing(a: f64, b: f64) -> Vec<i64> {
    let mut out = Vec::new();
    let mut s = a;
    while s < b - 1e-9 {
        out.push((s * 1e6).round() as i64);
        s += 0.25;
    }
    out.push((b * 1e6).round() as i64);
    out
}

/// A cursor file with `typed` marks (µs) and `shortcuts` (seconds).
fn file(typed: Vec<i64>, shortcuts: &[f64]) -> Value {
    let n = shortcuts.len();
    json!({
        "format": "framejob-cursor", "version": 1, "in_picture": false, "source": "display",
        "display_id": 1, "source_frame": [0, 0, 96000, 54000], "point_size": [96000, 54000],
        "pixels_per_point": 2.0, "content_size": [1920, 1080], "movie_size": [1920, 1080],
        "anchor": "e2", "anchor_host_us": 1000, "cursor_image": "current-system",
        "moves": {"t": [0], "x": [48000], "y": [27000]}, "images": [],
        "image_changes": {"t": [], "id": []}, "hidden": {"from": [], "to": []},
        "clicks": {"t": [], "button": [], "down": [], "x": [], "y": [], "count": []},
        "scrolls": {"t": [], "x": [], "y": [], "dx": [], "dy": []},
        "geometry": [{"t": 0, "screen_rect": [0, 0, 96000, 54000],
                      "content_rect": [0, 0, 96000, 54000],
                      "content_scale": 1.0, "scale_factor": 2.0}],
        "dirty": {"t": [], "x": [], "y": [], "w": [], "h": []},
        "keys": {"shortcut": {
                     "t": shortcuts.iter().map(|s| (s * 1e6).round() as i64).collect::<Vec<_>>(),
                     "keys": vec!["cmd+s"; n], "code": vec![1; n]},
                 "typed": {"t": typed}}
    })
}

struct Track(*mut CursorTrack);

impl Track {
    fn open(body: &Value) -> Track {
        let bytes = serde_json::to_vec(body).unwrap();
        let mut err: *mut c_char = ptr::null_mut();
        let handle = unsafe { rc_cursor_open(bytes.as_ptr(), bytes.len(), &mut err) };
        assert!(!handle.is_null(), "open refused: {:?}", take_string(err));
        Track(handle)
    }
}

impl Drop for Track {
    fn drop(&mut self) {
        unsafe { rc_cursor_free(self.0) };
    }
}

fn ask(project: Option<&Handle>, tracks: &[&Track], args: Value) -> Result<Value, String> {
    let pointers: Vec<*const CursorTrack> = tracks.iter().map(|t| t.0 as *const _).collect();
    let text = CString::new(json!({ "plan_typing": args }).to_string()).unwrap();
    let mut err: *mut c_char = ptr::null_mut();
    let answer = unsafe {
        rc_cursor_query(
            pointers.as_ptr(),
            pointers.len(),
            project.map_or(ptr::null(), |p| p.as_ptr()),
            text.as_ptr(),
            &mut err,
        )
    };
    if answer.is_null() {
        return Err(take_string(err).expect("NULL without a sentence"));
    }
    Ok(serde_json::from_str(&take_string(answer).unwrap()).unwrap())
}

fn plan(project: &Handle, tracks: &[&Track], args: Value) -> Value {
    ask(Some(project), tracks, args).expect("the plan was refused")
}

/// A screen recording with a cursor file and no sound.
fn screen(id: u32) -> Value {
    json!({"id": id, "path": format!("/m/{id}.mov"), "kind": "video", "duration": 600 * SEC,
           "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": false,
           "cursor": {"path": format!("/m/{id}.fjcursor"), "in_picture": false}})
}

/// A media with sound and the given stored speech (none when `None`).
fn sound(id: u32, video: bool, speech: Option<Value>) -> Value {
    let mut m = json!({"id": id, "path": format!("/m/{id}.mov"),
                       "kind": if video { "video" } else { "audio" }, "duration": 600 * SEC,
                       "has_video": video, "has_audio": true});
    if video {
        m["width"] = json!(1920);
        m["height"] = json!(1080);
        m["fps"] = json!([30, 1]);
    }
    if let Some(s) = speech {
        m["speech"] = s;
    }
    m
}

fn clip(id: u32, track: u32, media: u32, start: i64, duration: i64, source_in: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "media", "media": media, "in": source_in}})
}

fn project(media: Vec<Value>, tracks: Value, clips: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 38,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
        "media": media, "tracks": tracks, "clips": clips, "markers": [], "next_id": 500
    }))
}

/// One screen clip 10 on track 2 at 0, 30 s from source 0.
fn one_screen() -> Handle {
    project(
        vec![screen(1)],
        json!([{"id": 2, "name": "Screen"}]),
        vec![clip(10, 2, 1, 0, 30 * SEC, 0)],
    )
}

fn ranges(answer: &Value) -> Vec<(i64, i64)> {
    answer["ranges"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| (r["from"].as_i64().unwrap(), r["to"].as_i64().unwrap()))
        .collect()
}

fn ops(answer: &Value) -> Vec<Value> {
    answer["ops"].as_array().unwrap().clone()
}

/// (start, duration, speed, in) of every clip on `track`, in time order.
fn pieces(v: &Value, track: u32) -> Vec<(i64, i64, f64, i64)> {
    let mut out: Vec<(i64, i64, f64, i64)> = v["clips"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|c| c["track"] == track)
        .map(|c| {
            (
                c["start"].as_i64().unwrap(),
                c["duration"].as_i64().unwrap(),
                c["speed"].as_f64().unwrap_or(1.0),
                c["source"]["in"].as_i64().unwrap(),
            )
        })
        .collect();
    out.sort_by_key(|p| p.0);
    out
}

#[test]
fn r10_a_stretch_keeps_0_3_s_at_x1_at_each_end() {
    let handle = one_screen();
    let track = Track::open(&file(typing(2.0, 8.3), &[]));
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    // [2.0, 8.3) less 0.3 s each end: [2.3, 8.0) = frames 69 and 240.
    assert_eq!(ranges(&answer), vec![(t(2.3), t(8.0))]);
    // 5.7 s ÷ 4 = 1.425 s: 2.3 + 1.425 = 3.725 s, frame 111.75 → 112.
    assert_eq!(answer["ranges"][0]["sped_to"], 112 * 20_000);
    assert_eq!(answer["saved"], t(8.0) - 112 * 20_000);
    assert_eq!(
        (answer["stretches"].as_i64(), answer["short"].as_i64()),
        (Some(1), Some(0))
    );
    assert_eq!(answer["needs_speech"], json!([]));
    assert_eq!(
        ops(&answer),
        vec![
            json!({"op": "retime_range", "from": t(2.3), "to": t(8.0), "rate": 4.0,
                    "keep_pitch": true})
        ]
    );
    let after = handle.apply_all(&ops(&answer));
    let p = pieces(&after.value(), 2);
    assert_eq!(p.len(), 3, "{p:?}");
    assert_eq!((p[0].0, p[0].1, p[0].2), (0, t(2.3), 1.0));
    assert_eq!(
        (p[1].0, p[1].1, p[1].2),
        (t(2.3), 112 * 20_000 - t(2.3), 4.0)
    );
    assert_eq!((p[2].0, p[2].2, p[2].3), (112 * 20_000, 1.0, t(8.0)));
}

#[test]
fn r3_speech_on_any_track_cuts_the_stretch_back_to_its_edges() {
    // The screen has no sound; a microphone on track 4 talks 4.0–5.0 s.
    let handle = project(
        vec![screen(1), sound(3, false, Some(json!([[t(4.0), t(5.0)]])))],
        json!([{"id": 2, "name": "Screen"}, {"id": 4, "name": "Mic"}]),
        vec![
            clip(10, 2, 1, 0, 30 * SEC, 0),
            clip(11, 4, 3, 0, 30 * SEC, 0),
        ],
    );
    let track = Track::open(&file(typing(1.0, 9.0), &[]));
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    assert_eq!(ranges(&answer), vec![(t(1.3), t(3.7)), (t(5.3), t(8.7))]);
    // Right to left: the later range first.
    let list = ops(&answer);
    assert_eq!(
        (list[0]["from"].as_i64(), list[1]["from"].as_i64()),
        (Some(t(5.3)), Some(t(1.3)))
    );
    // A speech span read through a clip that starts at 2 s from source 1 s.
    let handle = project(
        vec![screen(1), sound(3, false, Some(json!([[t(4.0), t(5.0)]])))],
        json!([{"id": 2, "name": "Screen"}, {"id": 4, "name": "Mic"}]),
        vec![
            clip(10, 2, 1, 0, 30 * SEC, 0),
            clip(11, 4, 3, t(2.0), 20 * SEC, t(1.0)),
        ],
    );
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    // Source 4.0–5.0 s plays at 5.0–6.0 s.
    assert_eq!(ranges(&answer), vec![(t(1.3), t(4.7)), (t(6.3), t(8.7))]);
}

#[test]
fn a_media_with_sound_and_no_stored_speech_is_asked_for_first() {
    let handle = project(
        vec![screen(1), sound(3, false, None), sound(5, true, None)],
        json!([{"id": 2, "name": "Screen"}, {"id": 4, "name": "Mic"}, {"id": 6, "name": "Cam"}]),
        vec![
            clip(10, 2, 1, 0, 30 * SEC, 0),
            clip(11, 4, 3, 0, 30 * SEC, 0),
            // Media 5 plays only after the typing: not counted.
            clip(12, 6, 5, t(20.0), 5 * SEC, 0),
        ],
    );
    let track = Track::open(&file(typing(1.0, 9.0), &[]));
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    assert_eq!(answer["needs_speech"], json!([3]));
    assert_eq!(answer["ops"], json!([]));
    assert_eq!(answer["ranges"], json!([]));
}

#[test]
fn r9_a_shortcut_keeps_its_overlay_at_x1() {
    let handle = one_screen();
    let track = Track::open(&file(typing(0.5, 9.5), &[4.0]));
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    // No Shortcuts track: [4.0, 5.5) stays.
    assert_eq!(ranges(&answer), vec![(t(0.8), t(3.7)), (t(5.8), t(9.2))]);
    let with = |start: f64, end: f64| {
        project(
            vec![screen(1)],
            json!([{"id": 2, "name": "Screen"}, {"id": 7, "name": "Shortcuts"}]),
            vec![
                clip(10, 2, 1, 0, 30 * SEC, 0),
                json!({"id": 20, "track": 7, "start": t(start), "duration": t(end - start),
                       "source": {"kind": "text"}, "text": {"content": "⌘S"}}),
            ],
        )
    };
    // The overlay holding the press: its span [3.9, 6.0).
    let answer = plan(&with(3.9, 6.0), &[&track], json!({"clips": [10]}));
    assert_eq!(ranges(&answer), vec![(t(0.8), t(3.6)), (t(6.3), t(9.2))]);
    // An overlay starting 0.3 s late: from the press to its end, 6.5 s.
    let answer = plan(&with(4.3, 6.5), &[&track], json!({"clips": [10]}));
    assert_eq!(ranges(&answer), vec![(t(0.8), t(3.7)), (t(6.8), t(9.2))]);
    // One starting 0.6 s late is not the press's: the 1.5 s fallback, and
    // the clip itself is no cut.
    let answer = plan(&with(4.6, 4.8), &[&track], json!({"clips": [10]}));
    assert_eq!(ranges(&answer), vec![(t(0.8), t(3.7)), (t(5.8), t(9.2))]);
}

#[test]
fn a_press_before_from_still_keeps_its_overlay() {
    let handle = one_screen();
    let track = Track::open(&file(typing(1.0, 12.0), &[4.0]));
    let answer = plan(
        &handle,
        &[&track],
        json!({"clips": [10], "from": t(5.0), "to": t(10.0)}),
    );
    // [5.0, 10.0) less [4.0, 5.5): [5.5, 10.0) → [5.8, 9.7).
    assert_eq!(ranges(&answer), vec![(t(5.8), t(9.7))]);
    let handle = project(
        vec![screen(1)],
        json!([{"id": 2, "name": "Screen"}, {"id": 7, "name": "Shortcuts"}]),
        vec![
            clip(10, 2, 1, 0, 30 * SEC, 0),
            json!({"id": 20, "track": 7, "start": t(4.0), "duration": t(2.0),
                   "source": {"kind": "text"}, "text": {"content": "⌘S"}}),
        ],
    );
    let answer = plan(&handle, &[&track], json!({"clips": [10], "from": t(5.0)}));
    // [5.0, 12.0) less [4.0, 6.0): [6.0, 12.0) → [6.3, 11.7).
    assert_eq!(ranges(&answer), vec![(t(6.3), t(11.7))]);
}

#[test]
fn r15_two_clips_of_one_recording_are_united_before_shortest() {
    // Blade-split at 10 s: B continues A.
    let handle = project(
        vec![screen(1)],
        json!([{"id": 2, "name": "Screen"}]),
        vec![
            clip(10, 2, 1, 0, 10 * SEC, 0),
            clip(11, 2, 1, 10 * SEC, 20 * SEC, 10 * SEC),
        ],
    );
    let track = Track::open(&file(typing(8.0, 12.5), &[]));
    let answer = plan(
        &handle,
        &[&track, &track],
        json!({"clips": [10, 11], "shortest": 3}),
    );
    // [8.0, 10.0) and [10.0, 12.5) touch: one 4.5 s piece → [8.3, 12.2).
    assert_eq!(ranges(&answer), vec![(t(8.3), t(12.2))]);
    assert_eq!(answer["short"], 0);
    assert_eq!(ops(&answer).len(), 1);
    let after = handle.apply_all(&ops(&answer));
    let sped: Vec<f64> = pieces(&after.value(), 2).iter().map(|p| p.2).collect();
    assert_eq!(sped, vec![1.0, 4.0, 4.0, 1.0]);
}

#[test]
fn sync_across_three_tracks_after_two_ranges() {
    let handle = project(
        vec![
            screen(1),
            sound(2, true, Some(json!([]))),
            sound(3, false, Some(json!([]))),
        ],
        json!([{"id": 6, "name": "Screen"}, {"id": 7, "name": "Camera"},
               {"id": 8, "name": "Mic"}]),
        vec![
            clip(10, 6, 1, 0, 30 * SEC, 0),
            clip(11, 7, 2, 0, 30 * SEC, 0),
            clip(12, 8, 3, 0, 30 * SEC, 0),
        ],
    );
    let mut marks = typing(2.0, 8.1);
    marks.extend(typing(14.0, 20.1));
    let track = Track::open(&file(marks, &[]));
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    assert_eq!(ranges(&answer), vec![(t(2.3), t(7.8)), (t(14.3), t(19.8))]);
    let list = ops(&answer);
    assert_eq!(list[0]["from"], t(14.3));
    assert_eq!(list[1]["from"], t(2.3));
    let after = handle.apply_all(&list).value();
    // 5.5 s ÷ 4 = 1.375 s: 2.3 + 1.375 = 3.675 s, frame 110.25 → 110, and
    // 14.3 + 1.375 = 15.675 s, frame 470.25 → 470; each range loses 234 −
    // 110 = 124 frames (and 594 − 470), 4.1333 s, twice.
    let lost = 2 * (t(7.8) - 110 * 20_000);
    let screen_pieces = pieces(&after, 6);
    let last = screen_pieces.last().unwrap();
    assert_eq!(last.0 + last.1, 30 * SEC - lost);
    // Source 15 s plays sped (the later range, not one shifted by the first).
    let holding = screen_pieces
        .iter()
        .find(|p| p.3 <= t(15.0) && t(15.0) < p.3 + (p.1 as f64 * p.2).round() as i64)
        .unwrap();
    assert_eq!(holding.2, 4.0, "{screen_pieces:?}");
    // Every track starts every piece at the same source tick.
    let starts = |track: u32| -> Vec<(i64, i64)> {
        pieces(&after, track).iter().map(|p| (p.0, p.3)).collect()
    };
    assert_eq!(starts(6), starts(7));
    assert_eq!(starts(6), starts(8));
    assert_eq!(starts(6).len(), 5);
}

#[test]
fn a_x2_clip_and_a_ramp_read_through_s() {
    // ×2 from container 1 s: source 4.0–14.0 s is clip 2.0–7.0 s, container
    // 3.0–8.0 s.
    let mut fast = clip(10, 2, 1, t(1.0), t(10.0), 0);
    fast["speed"] = json!(2.0);
    let handle = project(
        vec![screen(1)],
        json!([{"id": 2, "name": "Screen"}]),
        vec![fast],
    );
    let track = Track::open(&file(typing(4.0, 14.0), &[]));
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    assert_eq!(ranges(&answer), vec![(t(3.3), t(7.7))]);
    // ×1 to ×2 over the first 0.6 s (S(0.6 s) = 0.9 s), then ×2: source
    // 4.9 s is clip 0.6 + (4.9 − 0.9) ÷ 2 = 2.6 s; 9.1 s is clip 4.7 s.
    let mut ramp = clip(10, 2, 1, 0, t(20.0), 0);
    ramp["actions"] = json!([{"id": 90, "start": 0, "duration": 360_000, "curve": "linear",
                              "end": {"speed": 2.0}}]);
    let handle = project(
        vec![screen(1)],
        json!([{"id": 2, "name": "Screen"}]),
        vec![ramp],
    );
    let track = Track::open(&file(typing(4.9, 9.1), &[]));
    let answer = plan(&handle, &[&track], json!({"clips": [10], "shortest": 1}));
    assert_eq!(ranges(&answer), vec![(t(2.9), t(4.4))]);
}

#[test]
fn short_stretches_change_nothing_and_settings_reach_the_ops() {
    let handle = one_screen();
    let track = Track::open(&file(typing(2.0, 4.5), &[]));
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    assert_eq!(answer["ops"], json!([]));
    assert_eq!(answer["short"], 1);
    assert_eq!(answer["saved"], 0);
    let answer = plan(
        &handle,
        &[&track],
        json!({"clips": [10], "shortest": 2, "rate": 6, "keep_pitch": false}),
    );
    assert_eq!(
        ops(&answer),
        vec![
            json!({"op": "retime_range", "from": t(2.3), "to": t(4.2), "rate": 6.0,
                    "keep_pitch": false})
        ]
    );
}

#[test]
fn a_plan_one_range_of_which_is_refused_is_refused_whole() {
    let handle = project(
        vec![screen(1)],
        json!([{"id": 2, "name": "Screen"}, {"id": 3, "name": "Locked", "locked": true}]),
        vec![
            clip(10, 2, 1, 0, 30 * SEC, 0),
            json!({"id": 20, "track": 3, "start": t(20.0), "duration": SEC,
                   "source": {"kind": "text"}, "text": {"content": "x"}}),
        ],
    );
    let track = Track::open(&file(typing(2.0, 8.3), &[]));
    let why = ask(Some(&handle), &[&track], json!({"clips": [10]})).unwrap_err();
    assert!(
        why.starts_with(&format!(
            "the typing from {} to {} ticks cannot be sped up: ",
            t(2.3),
            t(8.0)
        )),
        "{why}"
    );
    assert!(why.contains("locked"), "{why}");
}

#[test]
fn every_refusal_in_order() {
    let mut reversed = clip(12, 2, 1, 40 * SEC, SEC, 0);
    reversed["source"]["reversed"] = json!(true);
    let mut bare = screen(3);
    bare.as_object_mut().unwrap().remove("cursor");
    let no_cursor = clip(13, 2, 3, 42 * SEC, SEC, 0);
    let text = json!({"id": 30, "track": 2, "start": 50 * SEC, "duration": SEC,
                      "source": {"kind": "text"}, "text": {"content": "Hi"}});
    let handle = project(
        vec![screen(1), bare],
        json!([{"id": 2, "name": "Screen"}]),
        vec![clip(10, 2, 1, 0, 30 * SEC, 0), reversed, no_cursor, text],
    );
    let track = Track::open(&file(vec![], &[]));
    let refuse = |args: Value, tracks: &[&Track]| ask(Some(&handle), tracks, args).unwrap_err();
    let t1: &[&Track] = &[&track];
    let t2: &[&Track] = &[&track, &track];
    assert_eq!(
        refuse(json!({"clips": [99], "rate": 9, "shortest": 0.5}), t1),
        "rate is ×9; it runs ×2–×8"
    );
    assert_eq!(
        refuse(json!({"clips": [99], "rate": 1.5}), t1),
        "rate is ×1.5; it runs ×2–×8"
    );
    assert_eq!(
        refuse(
            json!({"clips": [99], "shortest": 0.5, "from": 5, "to": 5}),
            t1
        ),
        "shortest is 0.5 s; it runs 1–30"
    );
    assert_eq!(
        refuse(json!({"clips": [99], "shortest": 31}), t1),
        "shortest is 31 s; it runs 1–30"
    );
    assert_eq!(
        refuse(json!({"clips": [], "from": 100, "to": 100}), &[]),
        "to (100) must be after from (100)"
    );
    assert_eq!(
        refuse(json!({"clips": []}), &[]),
        "plan_typing needs at least one clip"
    );
    assert_eq!(
        refuse(json!({"clips": [10]}), t2),
        "plan_typing reads one cursor track per clip; 1 clips and 2 tracks were given"
    );
    assert_eq!(
        ask(None, t1, json!({"clips": [10]})).unwrap_err(),
        "plan_typing needs the project"
    );
    assert_eq!(
        refuse(json!({"clips": [10, 10]}), t2),
        "clip 10 is named twice"
    );
    assert_eq!(refuse(json!({"clips": [10, 99]}), t2), "no clip with id 99");
    assert_eq!(
        refuse(json!({"clips": [30]}), t1),
        "clip 30 is not a media clip"
    );
    assert_eq!(
        refuse(json!({"clips": [13]}), t1),
        "clip 13's media 3 has no cursor file"
    );
    assert_eq!(
        refuse(json!({"clips": [12]}), t1),
        "clip 12 plays reversed; Speed Up Typing speeds only clips that play forward"
    );
    assert!(refuse(json!({"clips": [10], "wobble": 1}), t1).contains("wobble"));
}
