//! One frame is the grid's own first frame at a canvas rate the timescale
//! does not divide (spec §11 #174), through the FFI.
//!
//! At 7 fps a frame is 85 714.28… ticks and at 5994/100 it is 10 010.01…,
//! so `time::frame_duration` has no answer at either. `Project::frame` used
//! to fall back to 1/30 s there, which set every one-frame MINIMUM — a
//! transition's shortest duration, the handle form's arithmetic, a clip's
//! shortest length — to 20 000 ticks. Each row here asks for exactly one
//! grid frame, or a whole number of them, and reads the answer back against
//! the grid computed independently below.

use serde_json::{json, Value};

mod common;
use common::{by_id, int, Handle};

// ---- the grid, written out -----------------------------------------------

/// `n / d` rounded half away from zero, for the non-negative values here.
fn round(n: i128, d: i128) -> i64 {
    ((2 * n + d) / (2 * d)) as i64
}

/// The tick frame `k` begins at: `k × 600 000 × den / num`, rounded.
fn tick(k: i64, fps: [u32; 2]) -> i64 {
    round(
        i128::from(k) * 600_000 * i128::from(fps[1]),
        i128::from(fps[0]),
    )
}

/// The frame `t` lies on, asserting it lies on one exactly.
fn index_on_grid(t: i64, fps: [u32; 2], what: &str) -> i64 {
    let k = round(
        i128::from(t) * i128::from(fps[0]),
        600_000 * i128::from(fps[1]),
    );
    assert_eq!(tick(k, fps), t, "{what} at {t} is not on the {fps:?} grid");
    k
}

const SEVEN: [u32; 2] = [7, 1];
const NTSC_ODD: [u32; 2] = [5994, 100];

// ---- fixtures ------------------------------------------------------------

/// A hard cut at frame 600 between shapes 10 and 11 on track 50 (shapes have
/// no source window, so no handle clamps anything); track 51 is empty; and
/// media clip 12 on track 52 shows a 60 s video.
fn doc(fps: [u32; 2]) -> Handle {
    let cut = tick(600, fps);
    Handle::from_value(&json!({
        "version": 10,
        "canvas": {"width": 1920, "height": 1080, "fps": fps, "background": [0, 0, 0, 1]},
        "media": [
            {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36_000_000,
             "width": 1920, "height": 1080, "fps": [30, 1],
             "has_video": true, "has_audio": true}
        ],
        "tracks": [{"id": 50}, {"id": 51}, {"id": 52}],
        "clips": [
            {"id": 10, "track": 50, "start": 0, "duration": cut,
             "source": {"kind": "shape"}, "video": {}, "shape": {}},
            {"id": 11, "track": 50, "start": cut, "duration": cut,
             "source": {"kind": "shape"}, "video": {}, "shape": {}},
            {"id": 12, "track": 52, "start": 0, "duration": cut,
             "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}}
        ],
        "markers": [], "next_id": 90, "nests": []
    }))
}

fn add(duration: i64, ripple: bool, align: &str) -> Value {
    json!({"op": "add_transition", "clip": 11, "duration": duration,
           "ripple": ripple, "align": align})
}

/// The overlap the op made, in whole grid frames, with both of its edges
/// asserted on the grid.
fn overlap_frames(after: &Value, fps: [u32; 2]) -> i64 {
    let a = by_id(after, "/clips", 10);
    let b = by_id(after, "/clips", 11);
    assert!(!b["transition_in"].is_null(), "the transition was made");
    let a_end = index_on_grid(int(a, "/start") + int(a, "/duration"), fps, "A's end");
    let b_start = index_on_grid(int(b, "/start"), fps, "B's start");
    a_end - b_start
}

fn one_frame_applies(fps: [u32; 2], ripple: bool) {
    let after = doc(fps).apply(&add(tick(1, fps), ripple, "center")).value();
    assert_eq!(overlap_frames(&after, fps), 1, "ripple {ripple}");
}

fn one_tick_less_is_refused_naming_one_frame(fps: [u32; 2]) {
    let one = tick(1, fps);
    for ripple in [false, true] {
        doc(fps).refuses_with(
            &add(one - 1, ripple, "center"),
            &format!(
                "a transition of {} ticks is too short to make at the cut before clip 11; \
                 pass a duration of at least {one} ticks",
                one - 1
            ),
        );
    }
}

/// A handle-form request of `frames` grid frames, centred: the overlap is
/// exactly that many frames, split with the odd one on the incoming side.
fn centred_handle_request_overlaps(fps: [u32; 2], frames: i64) {
    let after = doc(fps)
        .apply(&add(tick(frames, fps), false, "center"))
        .value();
    assert_eq!(overlap_frames(&after, fps), frames);
    let a = by_id(&after, "/clips", 10);
    let b = by_id(&after, "/clips", 11);
    assert_eq!(int(a, "/duration"), tick(600 + frames / 2, fps));
    assert_eq!(int(b, "/start"), tick(600 - (frames - frames / 2), fps));
}

// ---- 7 fps ---------------------------------------------------------------

#[test]
fn seven_fps_one_grid_frame_applies_in_the_handle_form() {
    one_frame_applies(SEVEN, false);
}

#[test]
fn seven_fps_one_grid_frame_applies_in_the_ripple_form() {
    one_frame_applies(SEVEN, true);
}

#[test]
fn seven_fps_one_tick_under_a_grid_frame_is_refused_naming_it() {
    one_tick_less_is_refused_naming_one_frame(SEVEN);
}

#[test]
fn seven_fps_a_two_frame_centred_handle_request_overlaps_two_grid_frames() {
    centred_handle_request_overlaps(SEVEN, 2);
}

#[test]
fn seven_fps_trim_end_to_the_start_leaves_one_grid_frame() {
    let after = doc(SEVEN)
        .apply(&json!({"op": "trim_end", "clip": 10, "to": 0}))
        .value();
    assert_eq!(int(by_id(&after, "/clips", 10), "/duration"), 85_714);
}

// ---- 5994/100 ------------------------------------------------------------

#[test]
fn ntsc_odd_one_grid_frame_applies_in_the_handle_form() {
    one_frame_applies(NTSC_ODD, false);
}

#[test]
fn ntsc_odd_one_grid_frame_applies_in_the_ripple_form() {
    one_frame_applies(NTSC_ODD, true);
}

#[test]
fn ntsc_odd_one_tick_under_a_grid_frame_is_refused_naming_it() {
    one_tick_less_is_refused_naming_one_frame(NTSC_ODD);
}

#[test]
fn ntsc_odd_a_two_frame_centred_handle_request_overlaps_two_grid_frames() {
    centred_handle_request_overlaps(NTSC_ODD, 2);
}

#[test]
fn ntsc_odd_a_150_frame_handle_request_overlaps_150_grid_frames() {
    assert_eq!(tick(150, NTSC_ODD), 1_501_502);
    centred_handle_request_overlaps(NTSC_ODD, 150);
}

#[test]
fn ntsc_odd_add_text_clip_accepts_one_grid_frame() {
    let after = doc(NTSC_ODD)
        .apply(&json!({"op": "add_text_clip", "track": 51, "at": 0, "duration": 10_010}))
        .value();
    assert_eq!(int(by_id(&after, "/clips", 90), "/duration"), 10_010);
}

#[test]
fn ntsc_odd_freeze_frame_accepts_one_grid_frame() {
    let at = tick(300, NTSC_ODD);
    let after = doc(NTSC_ODD)
        .apply(&json!({"op": "freeze_frame", "clip": 12, "at": at, "duration": 10_010}))
        .value();
    let still = after["clips"]
        .as_array()
        .expect("clips")
        .iter()
        .find(|clip| clip["source"]["kind"] == "still")
        .expect("a still was placed");
    assert_eq!(int(still, "/duration"), 10_010);
    assert_eq!(int(still, "/start"), at);
}

#[test]
fn ntsc_odd_trim_end_to_the_start_leaves_one_grid_frame() {
    let after = doc(NTSC_ODD)
        .apply(&json!({"op": "trim_end", "clip": 10, "to": 0}))
        .value();
    assert_eq!(int(by_id(&after, "/clips", 10), "/duration"), 10_010);
}
