//! Add Shortcut Overlays' planner (road map creator-jobs CU8, spec §11
//! CU-80…CU-84), black box through `rc_cursor_open` and `rc_cursor_query`'s
//! `plan_overlays` as `ShortcutOverlays.swift` calls it, its ops applied
//! through `rc_project_apply`. Every expected time is worked by hand from
//! CU-80's figures — D_min(n) = 10n + 25 frames, a 1.5 s overlay, a
//! different chord at most 0.5 s late — never read back from the code: O1
//! four shortcuts well apart, O1b no overlap at 60 fps, O2 and O2b the drop,
//! O3 the merge, O4 and O4b the track rule, O6 D_min over every fixture, O9
//! a speed-2 clip and a ramp through S with `from`/`to`, and every refusal in
//! CU-84's order.

mod common;

use std::ffi::{c_char, CString};
use std::ptr;

use common::{take_string, Handle};
use framejob_core::cursor_track::CursorTrack;
use framejob_core::ffi_cursor::{rc_cursor_free, rc_cursor_open, rc_cursor_query};
use serde_json::{json, Value};

const SEC: i64 = 600_000;

/// A cursor file whose shortcuts are `(seconds, keys)`.
fn file(shortcuts: &[(f64, &str)]) -> Value {
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
                     "t": shortcuts.iter().map(|s| (s.0 * 1e6).round() as i64).collect::<Vec<_>>(),
                     "keys": shortcuts.iter().map(|s| s.1).collect::<Vec<_>>(),
                     "code": vec![1; n]},
                 "typed": {"t": []}}
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

/// `plan_overlays` with `args` (the module named for the caller) against
/// `project` (or NULL), one track each.
fn ask(project: Option<&Handle>, tracks: &[&Track], mut args: Value) -> Result<Value, String> {
    if args.get("module").is_none() {
        args["module"] = json!("keyboard-keys");
    }
    let pointers: Vec<*const CursorTrack> = tracks.iter().map(|t| t.0 as *const _).collect();
    let text = CString::new(json!({ "plan_overlays": args }).to_string()).unwrap();
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

fn media(id: u32) -> Value {
    json!({"id": id, "path": format!("/m/{id}.mov"), "kind": "video", "duration": 600 * SEC,
           "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": false,
           "cursor": {"path": format!("/m/{id}.fjcursor"), "in_picture": false}})
}

fn clip(id: u32, track: u32, start: i64, duration: i64, source_in: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "media", "media": 1, "in": source_in}, "video": {}})
}

fn project_at(fps: u32, tracks: Value, clips: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 38,
        "canvas": {"width": 1920, "height": 1080, "fps": [fps, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
        "media": [media(1)], "tracks": tracks, "clips": clips, "markers": [], "next_id": 500
    }))
}

/// One clip 10 on track 2 at container `start`, 30 s long from source 0.
fn one_clip(fps: u32, start: i64) -> Handle {
    project_at(
        fps,
        json!([{"id": 2, "name": "Screen"}]),
        vec![clip(10, 2, start, 30 * SEC, 0)],
    )
}

fn t(seconds: f64) -> i64 {
    (seconds * SEC as f64).round() as i64
}

/// (at, duration, keys, label) of each planned overlay.
fn overlays(answer: &Value) -> Vec<(i64, i64, String, String)> {
    answer["overlays"]
        .as_array()
        .unwrap()
        .iter()
        .map(|o| {
            (
                o["at"].as_i64().unwrap(),
                o["duration"].as_i64().unwrap(),
                o["keys"].as_str().unwrap().to_string(),
                o["label"].as_str().unwrap().to_string(),
            )
        })
        .collect()
}

fn ops(answer: &Value) -> Vec<Value> {
    answer["ops"].as_array().unwrap().clone()
}

fn o(at: f64, frames: i64, fps: i64, keys: &str, label: &str) -> (i64, i64, String, String) {
    (
        t(at),
        frames * SEC / fps,
        keys.to_string(),
        label.to_string(),
    )
}

#[test]
fn o1_four_shortcuts_well_apart_land_on_one_new_front_track() {
    let handle = one_clip(30, t(2.0));
    let track = Track::open(&file(&[
        (1.0, "cmd+s"),
        (4.0, "cmd+shift+4"),
        (7.0, "ctrl+left"),
        (10.0, "cmd+plus"),
    ]));
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    assert_eq!(
        overlays(&answer),
        vec![
            o(3.0, 45, 30, "cmd+s", ""),
            o(6.0, 55, 30, "cmd+shift+4", ""),
            o(9.0, 45, 30, "ctrl+left", ""),
            o(12.0, 45, 30, "cmd+plus", ""),
        ]
    );
    assert_eq!(answer["new_track"], true);
    assert_eq!(answer["track"], 500);
    assert_eq!(
        (answer["added"].as_i64(), answer["dropped"].as_i64()),
        (Some(4), Some(0))
    );
    let list = ops(&answer);
    assert_eq!(
        list[0],
        json!({"op": "add_track", "index": 1, "name": "Shortcuts"})
    );
    assert_eq!(
        list[1]["props"],
        json!({"keys": "cmd+s", "label": "", "position": "bottom", "theme": "dark"})
    );
    assert_eq!(list[1]["name"], "keyboard-keys");
    let after = handle.apply_all(&list);
    let v = after.value();
    let tracks = v["tracks"].as_array().unwrap();
    assert_eq!(tracks.last().unwrap()["name"], "Shortcuts");
    assert_eq!(tracks.last().unwrap()["id"], 500);
    let placed: Vec<(i64, i64)> = v["clips"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|c| c["track"] == 500)
        .map(|c| {
            (
                c["start"].as_i64().unwrap(),
                c["duration"].as_i64().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        placed,
        vec![
            (t(3.0), t(1.5)),
            (t(6.0), t(55.0 / 30.0)),
            (t(9.0), t(1.5)),
            (t(12.0), t(1.5))
        ]
    );
}

#[test]
fn o1b_a_chord_one_second_later_ends_the_first_at_60_fps() {
    let handle = one_clip(60, 0);
    let track = Track::open(&file(&[(1.0, "cmd+s"), (2.0, "cmd+c")]));
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    assert_eq!(
        overlays(&answer),
        vec![o(1.0, 60, 60, "cmd+s", ""), o(2.0, 90, 60, "cmd+c", "")]
    );
}

#[test]
fn o2_a_chord_0_3_s_later_is_dropped_at_30_fps_and_placed_at_60() {
    let track = Track::open(&file(&[(1.0, "cmd+s"), (1.3, "cmd+c")]));
    let at30 = plan(&one_clip(30, 0), &[&track], json!({"clips": [10]}));
    assert_eq!(overlays(&at30), vec![o(1.0, 45, 30, "cmd+s", "")]);
    assert_eq!(at30["dropped"], 1);
    let at60 = plan(&one_clip(60, 0), &[&track], json!({"clips": [10]}));
    // D_min(2) is 45 frames, 0.75 s: the second starts 0.45 s late.
    assert_eq!(
        overlays(&at60),
        vec![o(1.0, 45, 60, "cmd+s", ""), o(1.75, 90, 60, "cmd+c", "")]
    );
    assert_eq!(at60["dropped"], 0);
}

#[test]
fn o2b_three_keycaps_hold_the_next_chord_too_long_at_60_fps() {
    let track = Track::open(&file(&[(1.0, "cmd+shift+4"), (1.3, "cmd+c")]));
    let answer = plan(&one_clip(60, 0), &[&track], json!({"clips": [10]}));
    // D_min(3) is 55 frames; the second would start 37 frames (0.62 s) late.
    assert_eq!(overlays(&answer), vec![o(1.0, 90, 60, "cmd+shift+4", "")]);
    assert_eq!(answer["dropped"], 1);
}

#[test]
fn o3_one_chord_three_times_is_one_overlay_labelled_x3() {
    let track = Track::open(&file(&[(1.0, "cmd+z"), (1.3, "cmd+z"), (1.6, "cmd+z")]));
    let answer = plan(&one_clip(30, 0), &[&track], json!({"clips": [10]}));
    // From the first press to the last + 1.5 s: 1.0 → 3.1 s, 63 frames.
    assert_eq!(overlays(&answer), vec![o(1.0, 63, 30, "cmd+z", "×3")]);
    assert_eq!(answer["merged"], 2);
    assert_eq!(answer["dropped"], 0);
}

/// Screen (2) behind Shortcuts (7), plus a third track (9) given in front.
fn two_screens() -> Handle {
    project_at(
        30,
        json!([{"id": 2, "name": "Screen"}, {"id": 7, "name": "Shortcuts"},
               {"id": 9, "name": "Front"}]),
        vec![clip(10, 2, 0, 30 * SEC, 0), clip(11, 9, 0, 30 * SEC, 0)],
    )
}

#[test]
fn o4_a_free_shortcuts_track_is_reused_and_an_occupied_one_is_not() {
    let free = project_at(
        30,
        json!([{"id": 2, "name": "Screen"}, {"id": 7, "name": "Shortcuts"}]),
        vec![clip(10, 2, 0, 30 * SEC, 0)],
    );
    let track = Track::open(&file(&[(5.0, "cmd+s")]));
    let answer = plan(&free, &[&track], json!({"clips": [10]}));
    assert_eq!(
        (answer["track"].clone(), answer["new_track"].clone()),
        (json!(7), json!(false))
    );
    assert_eq!(ops(&answer).len(), 1);
    let mut taken = free.value();
    taken["clips"].as_array_mut().unwrap().push(
        json!({"id": 20, "track": 7, "start": t(6.0), "duration": SEC,
                     "source": {"kind": "text"}, "video": {}, "text": {"content": "Hi"}}),
    );
    let taken = Handle::from_value(&taken);
    let answer = plan(&taken, &[&track], json!({"clips": [10]}));
    assert_eq!(answer["new_track"], true);
    // Locked, hidden and matte tracks are never reused either.
    for (key, value) in [
        ("locked", json!(true)),
        ("hidden", json!(true)),
        ("matte", json!("alpha")),
    ] {
        let mut v = free.value();
        v["tracks"][1][key] = value;
        let answer = plan(&Handle::from_value(&v), &[&track], json!({"clips": [10]}));
        assert_eq!(answer["new_track"], true, "{key}");
    }
}

#[test]
fn o4b_a_shortcuts_track_behind_a_given_clip_is_not_reused() {
    let handle = two_screens();
    let track = Track::open(&file(&[(5.0, "cmd+s")]));
    let answer = plan(&handle, &[&track], json!({"clips": [11]}));
    assert_eq!(answer["new_track"], true);
    let after = handle.apply_all(&ops(&answer));
    let v = after.value();
    let names: Vec<&str> = v["tracks"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["name"].as_str().unwrap())
        .collect();
    assert_eq!(names, vec!["Screen", "Shortcuts", "Front", "Shortcuts"]);
    assert!(v["clips"]
        .as_array()
        .unwrap()
        .iter()
        .all(|c| c["track"] != 7));
    // The clip on the screen behind it still reuses it.
    let behind = plan(&handle, &[&track], json!({"clips": [10]}));
    assert_eq!(behind["track"], 7);
}

#[test]
fn o6_no_overlay_is_shorter_than_its_d_min_or_off_the_grid() {
    let presses: Vec<(f64, &str)> = vec![
        (1.0, "cmd+s"),
        (1.1, "cmd+shift+4"),
        (1.4, "ctrl+opt+cmd+left"),
        (1.6, "cmd+c"),
        (3.0, "cmd+v"),
        (3.2, "cmd+v"),
        (3.5, "cmd+shift+z"),
        (6.0, "cmd+a"),
        (6.45, "cmd+b"),
    ];
    let track = Track::open(&file(&presses));
    for fps in [24u32, 30, 60] {
        for duration in [0.5, 1.5, 3.0] {
            let handle = one_clip(fps, t(0.5));
            let answer = plan(
                &handle,
                &[&track],
                json!({"clips": [10], "duration": duration}),
            );
            let frame = SEC / i64::from(fps);
            let mut last_end = i64::MIN;
            for (at, length, keys, _) in overlays(&answer) {
                let n = keys.split('+').filter(|k| !k.is_empty()).count() as i64;
                assert_eq!(at % frame, 0, "{fps} fps: {at} is off the grid");
                assert_eq!(length % frame, 0, "{fps} fps: {length} is off the grid");
                assert!(
                    length >= (10 * n + 25) * frame,
                    "{fps} fps, {duration} s: {keys} lasts {} frames",
                    length / frame
                );
                assert!(at >= last_end, "{fps} fps: overlays overlap at {at}");
                last_end = at + length;
            }
        }
    }
}

#[test]
fn o9_presses_map_through_s_and_from_to_filters_them() {
    // ×2 from container 1 s: 3 s of clip read source [0, 6) s, so source
    // 2.0 s is clip 1.0 s and 5.6 s is clip 2.8 s; 9.0 s is past the window.
    let track = Track::open(&file(&[(2.0, "cmd+s"), (5.6, "cmd+c"), (9.0, "cmd+v")]));
    let mut fast = clip(10, 2, t(1.0), t(3.0), 0);
    fast["speed"] = json!(2.0);
    let handle = project_at(30, json!([{"id": 2, "name": "Screen"}]), vec![fast]);
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    let at: Vec<i64> = overlays(&answer).iter().map(|o| o.0).collect();
    assert_eq!(at, vec![t(2.0), t(3.8)]);
    // ×1 to ×2 over the first 0.6 s (S(0.6 s) = 0.9 s), then ×2: source
    // 4.9 s is clip 0.6 + (4.9 − 0.9) / 2 = 2.6 s; 9.1 s is clip 4.7 s.
    let track = Track::open(&file(&[(4.9, "cmd+c"), (9.1, "cmd+v")]));
    let mut ramp = clip(10, 2, 0, t(20.0), 0);
    ramp["actions"] = json!([{"id": 90, "start": 0, "duration": 360_000, "curve": "linear",
                              "end": {"speed": 2.0}}]);
    let handle = project_at(30, json!([{"id": 2, "name": "Screen"}]), vec![ramp]);
    let answer = plan(&handle, &[&track], json!({"clips": [10]}));
    let at: Vec<i64> = overlays(&answer).iter().map(|o| o.0).collect();
    assert_eq!(at, vec![t(2.6), t(4.7)]);
    // `from`/`to` keep only [2.0, 3.0) s of container time.
    let answer = plan(
        &handle,
        &[&track],
        json!({"clips": [10], "from": t(2.0), "to": t(3.0)}),
    );
    let at: Vec<i64> = overlays(&answer).iter().map(|o| o.0).collect();
    assert_eq!(at, vec![t(2.6)]);
}

#[test]
fn nothing_recorded_places_nothing_and_settings_reach_the_props() {
    let handle = one_clip(30, 0);
    let empty = Track::open(&file(&[]));
    let answer = plan(&handle, &[&empty], json!({"clips": [10]}));
    assert_eq!(answer["ops"], json!([]));
    assert_eq!(answer["track"], Value::Null);
    let track = Track::open(&file(&[(1.0, "cmd+s")]));
    let answer = plan(
        &handle,
        &[&track],
        json!({"clips": [10], "duration": 3, "position": "top", "theme": "light",
               "schema": {"keys": {"type": "string", "default": "x"}}}),
    );
    let op = &ops(&answer)[1];
    assert_eq!(op["duration"], t(3.0));
    assert_eq!(op["props"]["position"], "top");
    assert_eq!(op["props"]["theme"], "light");
    assert_eq!(op["schema"]["keys"]["default"], "x");
}

#[test]
fn every_refusal_in_order() {
    let mut reversed = clip(12, 2, 40 * SEC, SEC, 0);
    reversed["source"]["reversed"] = json!(true);
    let mut bare = media(3);
    bare.as_object_mut().unwrap().remove("cursor");
    let mut no_cursor = clip(13, 2, 42 * SEC, SEC, 0);
    no_cursor["source"]["media"] = json!(3);
    let text = json!({"id": 30, "track": 2, "start": 50 * SEC, "duration": SEC,
                      "source": {"kind": "text"}, "video": {}, "text": {"content": "Hi"}});
    let handle = Handle::from_value(&json!({
        "version": 38,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
        "media": [media(1), bare], "tracks": [{"id": 2, "name": "Screen"}],
        "clips": [clip(10, 2, 0, 30 * SEC, 0), reversed, no_cursor, text],
        "markers": [], "next_id": 500
    }));
    let track = Track::open(&file(&[]));
    let refuse = |args: Value, tracks: &[&Track]| ask(Some(&handle), tracks, args).unwrap_err();
    let t1: &[&Track] = &[&track];
    let t2: &[&Track] = &[&track, &track];
    assert_eq!(
        refuse(json!({"clips": [99], "duration": 0.2}), t1),
        "duration is 0.2 s; it runs 0.5–10"
    );
    assert_eq!(
        refuse(json!({"clips": [99], "duration": 11}), t1),
        "duration is 11 s; it runs 0.5–10"
    );
    assert_eq!(
        refuse(json!({"clips": [99], "from": 100, "to": 100}), t1),
        "to (100) must be after from (100)"
    );
    assert_eq!(
        refuse(json!({"clips": []}), &[]),
        "plan_overlays needs at least one clip"
    );
    assert_eq!(
        refuse(json!({"clips": [10]}), t2),
        "plan_overlays reads one cursor track per clip; 1 clips and 2 tracks were given"
    );
    assert_eq!(
        ask(None, t1, json!({"clips": [10]})).unwrap_err(),
        "plan_overlays needs the project"
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
        "clip 12 plays reversed; Add Shortcut Overlays places only clips that play forward"
    );
    let position = refuse(json!({"clips": [10], "position": "left"}), t1);
    assert!(
        position.contains("plan_overlays.position") && position.contains("left"),
        "{position}"
    );
    let theme = refuse(json!({"clips": [10], "theme": "neon"}), t1);
    assert!(theme.contains("plan_overlays.theme"), "{theme}");
    assert!(refuse(json!({"clips": [10], "wobble": 1}), t1).contains("wobble"));
}
