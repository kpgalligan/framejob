//! Auto Zoom's planner (spec §11 CU-70…CU-75), black box through
//! `rc_cursor_open` and `rc_cursor_query`'s `plan_zooms` as
//! `ReelCore+Cursor.swift` calls it, its ops applied through
//! `rc_project_apply`. Every expected time and region is worked by hand from
//! the decisions' figures (lead 0.6 s, stay 2.5 s, a 0.8 s zoom back, the
//! inner 60 %, the region of the canvas's aspect at rest × zoom), never read
//! back from the code: Z1 the five clicks in two visits, Z2 the clamp at a
//! corner, Z3 a ramp through S, Z4 Replace off and on, `is_zoom` through
//! Replace's removals, Z7 a split mid-hold, Z8 a visit across a cut, Z9 the
//! placed clip refused and its neighbours planned, Z10 reversed, and every
//! refusal in CU-75's order.
//!
//! The fixture's cursor file maps one point to 2 movie px from the origin,
//! so a file unit (points × 100) is 1/50 px; its movie is 1920 × 1080 on a
//! 1920 × 1080 canvas at 30 fps (a frame is 20 000 ticks).

mod common;

use std::ffi::{c_char, CString};
use std::ptr;

use common::{take_string, Handle};
use framejob_core::cursor_track::CursorTrack;
use framejob_core::ffi_cursor::{rc_cursor_free, rc_cursor_open, rc_cursor_query};
use serde_json::{json, Value};

const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;

/// A cursor file with down clicks at `(µs, px x, px y)`, typed marks and
/// wheel events at µs, and one move at the centre.
fn file(downs: &[(i64, f64, f64)], typed: &[i64], scrolls: &[i64]) -> Value {
    let n = downs.len();
    let unit = |px: f64| (px * 50.0).round() as i64;
    json!({
        "format": "framejob-cursor", "version": 1, "in_picture": false, "source": "display",
        "display_id": 1, "source_frame": [0, 0, 96000, 54000], "point_size": [96000, 54000],
        "pixels_per_point": 2.0, "content_size": [1920, 1080], "movie_size": [1920, 1080],
        "anchor": "e2", "anchor_host_us": 1000, "cursor_image": "current-system",
        "moves": {"t": [0], "x": [48000], "y": [27000]}, "images": [],
        "image_changes": {"t": [], "id": []}, "hidden": {"from": [], "to": []},
        "clicks": {
            "t": downs.iter().map(|d| d.0).collect::<Vec<_>>(),
            "button": vec![0; n], "down": vec![1; n],
            "x": downs.iter().map(|d| unit(d.1)).collect::<Vec<_>>(),
            "y": downs.iter().map(|d| unit(d.2)).collect::<Vec<_>>(),
            "count": vec![1; n],
        },
        "scrolls": {"t": scrolls, "x": vec![48000; scrolls.len()], "y": vec![27000; scrolls.len()],
                    "dx": vec![0; scrolls.len()], "dy": vec![-100; scrolls.len()]},
        "geometry": [{"t": 0, "screen_rect": [0, 0, 96000, 54000],
                      "content_rect": [0, 0, 96000, 54000],
                      "content_scale": 1.0, "scale_factor": 2.0}],
        "dirty": {"t": [], "x": [], "y": [], "w": [], "h": []},
        "keys": {"shortcut": {"t": [], "keys": [], "code": []}, "typed": {"t": typed}}
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

/// `plan_zooms` with `args` against `project` (or NULL), one track each.
fn ask(project: Option<&Handle>, tracks: &[&Track], args: Value) -> Result<Value, String> {
    let pointers: Vec<*const CursorTrack> = tracks.iter().map(|t| t.0 as *const _).collect();
    let text = CString::new(json!({ "plan_zooms": args }).to_string()).unwrap();
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

fn media(id: u32, w: u32, h: u32) -> Value {
    json!({"id": id, "path": format!("/m/{id}.mov"), "kind": "video", "duration": 600 * SEC,
           "width": w, "height": h, "fps": [30, 1], "has_video": true, "has_audio": false,
           "cursor": {"path": format!("/m/{id}.fjcursor"), "in_picture": false}})
}

fn clip(id: u32, start: i64, duration: i64, source_in: i64, video: Value) -> Value {
    json!({"id": id, "track": 2, "start": start, "duration": duration,
           "source": {"kind": "media", "media": 1, "in": source_in}, "video": video})
}

fn project_with(canvas: (u32, u32), media: Vec<Value>, clips: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 38,
        "canvas": {"width": canvas.0, "height": canvas.1, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
        "media": media, "tracks": [{"id": 2, "name": "Screen"}], "clips": clips,
        "markers": [], "next_id": 500
    }))
}

fn one_clip(video: Value, actions: Value) -> Handle {
    let mut c = clip(10, 0, 20 * SEC, 0, video);
    c["actions"] = actions;
    project_with((1920, 1080), vec![media(1, 1920, 1080)], vec![c])
}

/// (clip, at, duration, kind) of each planned action.
fn spans(answer: &Value) -> Vec<(u64, i64, i64, String)> {
    answer["actions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| {
            (
                a["clip"].as_u64().unwrap(),
                a["at"].as_i64().unwrap(),
                a["duration"].as_i64().unwrap(),
                a["kind"].as_str().unwrap().to_string(),
            )
        })
        .collect()
}

fn ops(answer: &Value) -> Vec<Value> {
    answer["ops"].as_array().unwrap().clone()
}

fn zooms(answer: &Value) -> Vec<Value> {
    ops(answer)
        .into_iter()
        .filter(|o| o["op"] == "add_zoom_action")
        .collect()
}

fn placed(handle: &Handle, clip: u32, t: i64) -> (f64, f64, f64) {
    let state = handle.clip_state(clip, t).expect("no state");
    let v = &state["video"];
    (
        v["scale"].as_f64().unwrap(),
        v["x"].as_f64().unwrap(),
        v["y"].as_f64().unwrap(),
    )
}

fn close(a: (f64, f64, f64), b: (f64, f64, f64), tol: f64) {
    assert!(
        (a.0 - b.0).abs() <= tol && (a.1 - b.1).abs() <= tol && (a.2 - b.2).abs() <= tol,
        "{a:?} is not {b:?}"
    );
}

fn s(us: f64) -> i64 {
    (us * 1e6) as i64
}

/// Z1's clicks: 2.0 s at the centre, 3.0 s inside the inner 60 %, 4.0 s
/// outside it, 12.0 s and 13.0 s together.
fn z1_file() -> Value {
    file(
        &[
            (s(2.0), 960.0, 540.0),
            (s(3.0), 1060.0, 600.0),
            (s(4.0), 1500.0, 540.0),
            (s(12.0), 700.0, 500.0),
            (s(13.0), 720.0, 520.0),
        ],
        &[],
        &[],
    )
}

#[test]
fn z1_five_clicks_make_two_visits_at_the_worked_times() {
    let handle = one_clip(json!({}), json!([]));
    let track = Track::open(&z1_file());
    let answer = plan(&handle, &[&track], json!({"clips": [10], "follow": false}));
    let k = |at: f64, d: f64, kind: &str| (10, s(at) * 6 / 10, s(d) * 6 / 10, kind.to_string());
    assert_eq!(
        spans(&answer),
        vec![
            k(1.4, 0.6, "in"),
            k(3.4, 0.6, "pan"),
            k(6.5, 0.8, "back"),
            k(11.4, 0.6, "in"),
            k(15.5, 0.8, "back"),
        ]
    );
    assert_eq!(answer["visits"], 2);
    assert_eq!(answer["added"], 5);
    assert_eq!(answer["dropped"], 0);
    let z = zooms(&answer);
    // The zoom-in: the centre, 960 × 540 (the canvas at ×2).
    assert_eq!(
        z[0]["region"],
        json!({"x": 0.0, "y": 0.0, "width": 960.0, "height": 540.0})
    );
    // The pan aims at 540 px right of centre, clamped to 480.
    assert_eq!(z[1]["region"]["x"], 480.0);
    assert_eq!(z[2]["region"], Value::Null);
    assert_eq!(z[0]["fit"], "fit");
    assert_eq!(z[0]["curve"], "ease_in_out");
    // Applied, the hold sits at ×2 and the back returns to the base.
    let after = handle.apply_all(&ops(&answer));
    close(placed(&after, 10, 2 * SEC), (2.0, 0.0, 0.0), 1e-9);
    close(placed(&after, 10, s(7.3) * 6 / 10), (1.0, 0.0, 0.0), 1e-9);
}

#[test]
fn z1_a_scroll_burst_ends_a_visit_and_a_near_visit_merges() {
    let handle = one_clip(json!({}), json!([]));
    // A burst at 4.5 s: the back starts there, not at 6.5 s, and the click
    // at 5.0 s (within Stay) starts a new visit.
    let burst = [s(4.5), s(4.7), s(4.9)];
    let f = file(
        &[
            (s(2.0), 960.0, 540.0),
            (s(4.0), 960.0, 540.0),
            (s(6.0), 960.0, 540.0),
        ],
        &[],
        &burst,
    );
    let track = Track::open(&f);
    let answer = plan(&handle, &[&track], json!({"clips": [10], "follow": false}));
    assert_eq!(answer["visits"], 2);
    // The back at 4.5 s would end 5.3 s, under 1 s before the next zoom-in
    // at 5.4 s: merged into one pan ending at 6.0 s.
    let k = |at: f64, d: f64, kind: &str| (10, s(at) * 6 / 10, s(d) * 6 / 10, kind.to_string());
    assert_eq!(
        spans(&answer),
        vec![k(1.4, 0.6, "in"), k(5.4, 0.6, "pan"), k(8.5, 0.8, "back")]
    );
}

#[test]
fn z1_typing_aims_at_the_last_click_before_it() {
    let handle = one_clip(json!({}), json!([]));
    let typed = [s(5.0), s(5.5), s(6.0), s(6.5)];
    let f = file(&[(s(1.0), 1500.0, 540.0)], &typed, &[]);
    let track = Track::open(&f);
    let answer = plan(&handle, &[&track], json!({"clips": [10], "follow": false}));
    // The click at 1.0 s is one visit (back at 3.5 s, ending 4.3 s); the
    // stretch from 5.0 s is another (1.0 + 2.5 < 5.0), aimed at the click,
    // its zoom-in from 4.4 s — under 1 s after 4.3 s, so the two merge into
    // a pan; its activity runs to 6.5 s, so the back is at 9.0 s.
    let k = |at: f64, d: f64, kind: &str| (10, s(at) * 6 / 10, s(d) * 6 / 10, kind.to_string());
    assert_eq!(
        spans(&answer),
        vec![k(0.4, 0.6, "in"), k(4.4, 0.6, "pan"), k(9.0, 0.8, "back")]
    );
    assert_eq!(answer["visits"], 2);
    assert_eq!(zooms(&answer)[1]["region"]["x"], 480.0);
    let off = plan(
        &handle,
        &[&track],
        json!({"clips": [10], "follow": false, "typing": false}),
    );
    assert_eq!(off["added"], 2);
}

#[test]
fn follow_pans_after_the_cursor_leaves_the_inner_70_percent() {
    let handle = one_clip(json!({}), json!([]));
    // Held at the centre, then at 1700 px from 3.0 s on.
    let mut f = file(&[(s(2.0), 960.0, 540.0)], &[], &[]);
    f["moves"] = json!({"t": [0, s(3.0)], "x": [48000, 85000], "y": [27000, 27000]});
    let track = Track::open(&f);
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    // Outside from the 3.0 s sample (740 px from the centre > 336), so the
    // pan starts at 3.3 s, lasts 0.5 s and aims at 740 clamped to 480; the
    // cursor is then inside, so there is no second.
    let k = |at: f64, d: f64, kind: &str| (10, s(at) * 6 / 10, s(d) * 6 / 10, kind.to_string());
    assert_eq!(
        spans(&answer),
        vec![
            k(1.4, 0.6, "in"),
            k(3.3, 0.5, "follow"),
            k(4.5, 0.8, "back")
        ]
    );
    assert_eq!(zooms(&answer)[1]["region"]["x"], 480.0);
}

#[test]
fn z2_the_region_is_clamped_at_a_corner() {
    let handle = one_clip(json!({}), json!([]));
    let track = Track::open(&file(&[(s(2.0), 10.0, 10.0)], &[], &[]));
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    assert_eq!(
        zooms(&answer)[0]["region"],
        json!({"x": -480.0, "y": -270.0, "width": 960.0, "height": 540.0})
    );
    // A crop moves the rect it is clamped in, and Q is from its centre.
    let cropped = one_clip(
        json!({"crop": {"l": 100, "t": 0, "r": 0, "b": 0}}),
        json!([]),
    );
    let answer = plan(&cropped, &[&track], json!({"clips": [10]}));
    let r = &zooms(&answer)[0]["region"];
    // P x clamped to −960 + 100 + 480 = −380; Q = P − 50.
    assert_eq!(r["x"], -430.0);
}

#[test]
fn z3_a_ramped_clip_is_placed_through_s() {
    // ×1 to ×2 over the first 0.6 s (S(0.6 s) = 0.9 s of source), then ×2.
    let ramp = json!([{"id": 90, "start": 0, "duration": 360_000, "curve": "linear",
                       "end": {"speed": 2.0}}]);
    let handle = one_clip(json!({}), ramp);
    let track = Track::open(&file(&[(s(4.9), 960.0, 540.0)], &[], &[]));
    let answer = plan(&handle, &[&track], json!({"clips": [10], "follow": false}));
    // Source 4.9 s is clip 0.6 + (4.9 − 0.9) / 2 = 2.6 s.
    let k = |at: f64, d: f64, kind: &str| (10, s(at) * 6 / 10, s(d) * 6 / 10, kind.to_string());
    assert_eq!(spans(&answer), vec![k(2.0, 0.6, "in"), k(5.1, 0.8, "back")]);
}

#[test]
fn z4_replace_off_keeps_a_hand_zoom_and_counts_the_drop() {
    let hand = json!([{"id": 91, "start": 900_000, "duration": SEC, "curve": "linear",
                       "end": {"video": {"scale": 3, "x": 10, "y": 10}}},
                      {"id": 92, "start": 12 * SEC, "duration": SEC, "curve": "linear",
                       "end": {"video": {"opacity": 0.5}}}]);
    let handle = one_clip(json!({}), hand);
    let track = Track::open(&z1_file());
    // The zoom-in [1.4, 2.0) s meets the hand zoom at [1.5, 2.5) s: dropped.
    // The zoom-in [11.4, 12.0) s ends where the opacity action starts.
    let off = plan(&handle, &[&track], json!({"clips": [10], "follow": false}));
    assert_eq!(off["dropped"], 1);
    assert_eq!(off["replaced"], 0);
    assert_eq!(off["added"], 4);
    assert!(ops(&off).iter().all(|o| o["op"] != "remove_action"));
    let after = handle.apply_all(&ops(&off));
    let actions = &after.value()["clips"][0]["actions"];
    assert!(actions.as_array().unwrap().iter().any(|a| a["id"] == 91));
    // Replace on removes the zoom, never the opacity action, and plans
    // the zoom-in in its place.
    let on = plan(
        &handle,
        &[&track],
        json!({"clips": [10], "follow": false, "replace": true}),
    );
    assert_eq!(on["replaced"], 1);
    assert_eq!(on["dropped"], 0);
    assert_eq!(on["added"], 5);
    assert_eq!(
        ops(&on)[0],
        json!({"op": "remove_action", "clip": 10, "action": 91})
    );
    let after = handle.apply_all(&ops(&on));
    let ids: Vec<i64> = after.value()["clips"][0]["actions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| a["id"].as_i64().unwrap())
        .collect();
    assert!(ids.contains(&92) && !ids.contains(&91));
}

#[test]
fn replace_removes_exactly_the_ends_is_zoom_names() {
    let zoom = json!({"scale": 2, "x": 0, "y": 0});
    let ends = [
        (json!({"video": zoom}), true),
        (json!({"video": {"scale": 2, "x": 0}}), false),
        (
            json!({"video": {"scale": 2, "x": 0, "y": 0, "rotation": 5}}),
            false,
        ),
        (json!({"video": zoom, "audio": {}}), true),
        (json!({"video": zoom, "audio": {"volume": 0.5}}), false),
        (json!({"video": zoom, "text": null}), true),
        (json!({"video": zoom, "graphic": {"props": {}}}), true),
        (
            json!({"video": zoom, "graphic": {"props": {"size": 1}}}),
            false,
        ),
        (json!({"video": zoom, "speed": 1.0}), false),
        (json!({}), false),
        (
            json!({"video": {"x": 0, "y": 0, "scale": 1, "crop": {"l": 0, "t": 0, "r": 0, "b": 0},
                             "corner_radius": 0, "opacity": 1}}),
            false,
        ),
        (json!({"audio": {"volume": 0}}), false),
    ];
    let actions: Vec<Value> = ends
        .iter()
        .enumerate()
        .map(|(i, (end, _))| {
            json!({"id": 100 + i, "start": i as i64 * SEC, "duration": SEC / 2,
                   "curve": "linear", "end": end})
        })
        .collect();
    let handle = one_clip(json!({}), Value::Array(actions));
    let track = Track::open(&file(&[], &[], &[]));
    let answer = plan(&handle, &[&track], json!({"clips": [10], "replace": true}));
    let removed: Vec<i64> = ops(&answer)
        .iter()
        .filter(|o| o["op"] == "remove_action")
        .map(|o| o["action"].as_i64().unwrap())
        .collect();
    let expected: Vec<i64> = ends
        .iter()
        .enumerate()
        .filter(|(_, (_, z))| *z)
        .map(|(i, _)| 100 + i as i64)
        .collect();
    assert_eq!(removed, expected);
    // `from`/`to` narrow what Replace removes to the actions meeting them.
    let narrow = plan(
        &handle,
        &[&track],
        json!({"clips": [10], "replace": true, "from": 3 * SEC, "to": 7 * SEC}),
    );
    assert_eq!(narrow["replaced"], 3); // ends 3, 5 and 6
}

/// A clip split at 6 s: A = 10 on [0, 6) s, B = 11 on [6, 12) s continuing
/// its source; `b_video` is B's base.
fn split(b_video: Value) -> Handle {
    project_with(
        (1920, 1080),
        vec![media(1, 1920, 1080)],
        vec![
            clip(10, 0, 6 * SEC, 0, json!({})),
            clip(11, 6 * SEC, 6 * SEC, 6 * SEC, b_video),
        ],
    )
}

#[test]
fn z7_a_later_half_zooms_back_to_the_first_halfs_base() {
    let handle = split(json!({"scale": 2, "x": -100, "y": 0}));
    let track = Track::open(&file(&[(s(8.0), 960.0, 540.0)], &[], &[]));
    // Replace off: B keeps its base, and the back is the region whose solve
    // is A's base.
    let off = plan(&handle, &[&track], json!({"clips": [11], "follow": false}));
    let z = zooms(&off);
    assert_eq!(z.len(), 2);
    assert!(
        z[1]["region"].is_object(),
        "a later half's back is a region"
    );
    let after = handle.apply_all(&ops(&off));
    close(placed(&after, 11, s(11.3) * 6 / 10), (1.0, 0.0, 0.0), 1e-6);
    // Replace on: B is reset to A's base, and the back is then null.
    let on = plan(
        &handle,
        &[&track],
        json!({"clips": [11], "follow": false, "replace": true}),
    );
    assert_eq!(on["bases_set"], 1);
    assert_eq!(
        ops(&on)[0],
        json!({"op": "set_video", "clips": [11], "patch": {"scale": 1.0, "x": 0.0, "y": 0.0}})
    );
    assert_eq!(zooms(&on)[1]["region"], Value::Null);
    let after = handle.apply_all(&ops(&on));
    close(placed(&after, 11, 6 * SEC), (1.0, 0.0, 0.0), 1e-9);
    close(placed(&after, 11, s(11.3) * 6 / 10), (1.0, 0.0, 0.0), 1e-6);
}

#[test]
fn z7_a_zoom_in_never_lands_on_a_half_that_was_not_given() {
    let handle = split(json!({}));
    let track = Track::open(&file(&[(s(6.2), 960.0, 540.0)], &[], &[]));
    let answer = plan(&handle, &[&track], json!({"clips": [11], "follow": false}));
    // [5.6, 6.2) s straddles the cut; A was not given, so it starts there.
    assert_eq!(spans(&answer)[0], (11, 0, s(0.6) * 6 / 10, "in".into()));
    let after = handle.apply_all(&ops(&answer));
    assert_eq!(after.value()["clips"][0]["actions"], json!([]));
}

#[test]
fn z8_a_visit_across_a_cut_sets_the_later_base_and_straddles_nothing() {
    let handle = split(json!({}));
    let track = Track::open(&file(
        &[(s(4.0), 960.0, 540.0), (s(6.5), 1500.0, 540.0)],
        &[],
        &[],
    ));
    let tracks = [&track, &track];
    let answer = plan(
        &handle,
        &tracks,
        json!({"clips": [10, 11], "follow": false}),
    );
    assert_eq!(answer["visits"], 1);
    assert_eq!(answer["bases_set"], 1);
    let k = |c: u64, at: f64, d: f64, kind: &str| (c, s(at) * 6 / 10, s(d) * 6 / 10, kind.into());
    assert_eq!(
        spans(&answer),
        vec![
            k(10, 3.4, 0.6, "in"),
            k(11, 0.0, 0.6, "pan"),
            k(11, 3.0, 0.8, "back"),
        ]
    );
    for (c, at, d, _) in spans(&answer) {
        assert!(
            at >= 0 && at + d <= 6 * SEC,
            "clip {c} [{at}, {}) leaves it",
            at + d
        );
    }
    let after = handle.apply_all(&ops(&answer));
    let a_end = placed(&after, 10, 6 * SEC - FRAME);
    let b_start = placed(&after, 11, 6 * SEC);
    close(a_end, b_start, 1e-9);
    close(a_end, (2.0, 0.0, 0.0), 1e-9);
    close(placed(&after, 11, s(9.8) * 6 / 10), (1.0, 0.0, 0.0), 1e-6);
}

#[test]
fn z8_a_kept_action_on_the_later_half_closes_the_visit_at_the_cut() {
    let mut b = clip(11, 6 * SEC, 6 * SEC, 6 * SEC, json!({}));
    b["actions"] = json!([{"id": 95, "start": 2 * SEC, "duration": SEC / 2,
                           "curve": "linear", "end": {"video": {"opacity": 0.5}}}]);
    let handle = project_with(
        (1920, 1080),
        vec![media(1, 1920, 1080)],
        vec![clip(10, 0, 6 * SEC, 0, json!({})), b],
    );
    let track = Track::open(&file(
        &[(s(4.0), 960.0, 540.0), (s(6.5), 960.0, 540.0)],
        &[],
        &[],
    ));
    let answer = plan(
        &handle,
        &[&track, &track],
        json!({"clips": [10, 11], "follow": false}),
    );
    assert_eq!(answer["closed_at_cut"], 1);
    assert_eq!(answer["bases_set"], 0);
    assert_eq!(answer["visits"], 2);
    let k = |c: u64, at: f64, d: f64, kind: &str| (c, s(at) * 6 / 10, s(d) * 6 / 10, kind.into());
    assert_eq!(spans(&answer)[1], k(10, 5.2, 0.8, "back"));
}

#[test]
fn z9_a_placed_clip_is_refused_and_its_neighbours_planned() {
    let track = Track::open(&file(&[(s(2.0), 960.0, 540.0)], &[], &[]));
    let side = one_clip(json!({"scale": 0.5, "x": -480}), json!([]));
    assert_eq!(
        ask(Some(&side), &[&track], json!({"clips": [10]})).unwrap_err(),
        "clip 10 is placed smaller than the canvas; a zoom would fill the canvas. Nest it \
         (Clip ▸ Nest) and run Auto Zoom inside the nest."
    );
    let moved = one_clip(json!({"scale": 1.2, "x": -200}), json!([]));
    let answer = plan(&moved, &[&track], json!({"clips": [10]}));
    let r = &zooms(&answer)[0]["region"];
    assert!((r["width"].as_f64().unwrap() - 800.0).abs() < 1e-9);
    let small = project_with(
        (3840, 2160),
        vec![media(1, 2560, 1440)],
        vec![clip(10, 0, 20 * SEC, 0, json!({}))],
    );
    assert!(ask(Some(&small), &[&track], json!({"clips": [10]})).is_ok());
    // Nested, the side-by-side clip is planned inside, against the nest's
    // canvas, and the nest clip is unchanged.
    let nested = side.apply(&json!({"op": "nest", "clips": [10]}));
    let nest = nested.value()["nests"][0]["id"].as_u64().unwrap() as u32;
    let inside = nested.scoped(nest);
    let fixed = inside.apply(&json!({"op": "set_video", "clips": [10],
                                     "patch": {"scale": 1, "x": 0, "y": 0}}));
    let answer = plan(&fixed, &[&track], json!({"clips": [10]}));
    assert_eq!(answer["added"], 2);
}

#[test]
fn z10_a_reversed_clip_is_refused() {
    let mut c = clip(10, 0, 20 * SEC, 0, json!({}));
    c["source"]["reversed"] = json!(true);
    let handle = project_with((1920, 1080), vec![media(1, 1920, 1080)], vec![c]);
    let track = Track::open(&file(&[], &[], &[]));
    assert_eq!(
        ask(Some(&handle), &[&track], json!({"clips": [10]})).unwrap_err(),
        "clip 10 plays reversed; Auto Zoom plans only clips that play forward"
    );
}

#[test]
fn every_refusal_in_order() {
    let mut text = json!({"id": 30, "track": 2, "start": 30 * SEC, "duration": SEC,
                          "source": {"kind": "text"}, "video": {}, "text": {"content": "Hi"}});
    text["track"] = json!(2);
    let mut bare = media(3, 1920, 1080);
    bare.as_object_mut().unwrap().remove("cursor");
    let mut no_cursor = clip(31, 32 * SEC, SEC, 0, json!({}));
    no_cursor["source"]["media"] = json!(3);
    let mut no_picture = clip(33, 34 * SEC, SEC, 0, json!({}));
    no_picture.as_object_mut().unwrap().remove("video");
    let handle = project_with(
        (1920, 1080),
        vec![media(1, 1920, 1080), bare],
        vec![
            clip(10, 0, 20 * SEC, 0, json!({})),
            text,
            no_cursor,
            no_picture,
        ],
    );
    let track = Track::open(&file(&[], &[], &[]));
    let refuse = |args: Value, tracks: &[&Track]| ask(Some(&handle), tracks, args).unwrap_err();
    let t1: &[&Track] = &[&track];
    assert_eq!(
        refuse(json!({"clips": [99], "zoom": 1.2}), t1),
        "zoom is 1.2; it runs 1.25–4"
    );
    assert_eq!(
        refuse(json!({"clips": [10], "lead": 0.1}), t1),
        "lead is 0.1 s; it runs 0.2–2"
    );
    assert_eq!(
        refuse(json!({"clips": [10], "stay": 11}), t1),
        "stay is 11 s; it runs 0.5–10"
    );
    assert_eq!(
        refuse(json!({"clips": [10], "from": 100, "to": 100}), t1),
        "to (100) must be after from (100)"
    );
    assert_eq!(
        refuse(json!({"clips": []}), &[]),
        "plan_zooms needs at least one clip"
    );
    assert_eq!(
        refuse(json!({"clips": [10]}), &[&track, &track]),
        "plan_zooms reads one cursor track per clip; 1 clips and 2 tracks were given"
    );
    assert_eq!(
        ask(None, t1, json!({"clips": [10]})).unwrap_err(),
        "plan_zooms needs the project"
    );
    let t2: &[&Track] = &[&track, &track];
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
        refuse(json!({"clips": [31]}), t1),
        "clip 31's media 3 has no cursor file"
    );
    assert_eq!(refuse(json!({"clips": [33]}), t1), "clip 33 has no picture");
    assert!(refuse(json!({"clips": [10], "wobble": 1}), t1).contains("wobble"));
    // The six reads keep their one-track rule.
    let pointers: Vec<*const CursorTrack> = vec![track.0, track.0];
    let request = CString::new(r#"{"state":{"at":0}}"#).unwrap();
    let mut err: *mut c_char = ptr::null_mut();
    let answer = unsafe {
        rc_cursor_query(
            pointers.as_ptr(),
            2,
            ptr::null(),
            request.as_ptr(),
            &mut err,
        )
    };
    assert!(answer.is_null());
    assert_eq!(
        take_string(err).unwrap(),
        "state reads one cursor track; 2 were given"
    );
}
