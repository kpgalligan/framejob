//! Shifts at a canvas rate whose frame is not a whole number of ticks
//! (spec §11 #42), through the FFI, at **7 fps** — a frame of
//! 600 000 / 7 = 85 714.28… ticks, so `time::frame_duration` answers `None`
//! and `Project::frame` falls back to 1/30 s.
//!
//! Two claims:
//!
//! - **A shift moves every clip it moves by ONE delta.** `ripple_delete` and
//!   `close_gap` keep two abutting clips abutting, and gain no overlap,
//!   even where that leaves a start a tick off the grid; snapping each moved
//!   clip on its own would open a one-tick gap or mint a one-tick
//!   transition.
//! - **`add_transition`'s ripple form counts whole frames of the REAL
//!   grid** and lands the incoming clip on it, where it used to shift by a
//!   multiple of the 1/30 s fallback.
//!
//! The grid oracle below is integer arithmetic written out here, not
//! `time.rs`'s: frame `k` begins at `k × 600 000 / 7` rounded half up.

use serde_json::{json, Value};

mod common;
use common::{by_id, int, Handle};

// ---- the 7 fps grid, independently ---------------------------------------

/// The tick frame `k ≥ 0` begins at, at 7 fps: `round(k × 600 000 / 7)`.
fn grid(k: i64) -> i64 {
    (2 * k * 600_000 + 7) / 14
}

/// Whether `t ≥ 0` is a frame boundary at 7 fps.
fn on_grid(t: i64) -> bool {
    let nearest = (t * 14 + 600_000) / 1_200_000;
    grid(nearest) == t
}

// ---- fixtures ------------------------------------------------------------

/// A 7 fps project with the given tracks and clips.
fn at_7fps(tracks: &[u32], clips: Value) -> Handle {
    let tracks: Vec<Value> = tracks
        .iter()
        .map(|id| json!({"id": id, "name": format!("T{id}")}))
        .collect();
    Handle::from_value(&json!({
        "version": 8,
        "canvas": {"width": 1920, "height": 1080, "fps": [7, 1], "background": [0, 0, 0, 1]},
        "media": [
            {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
             "width": 1920, "height": 1080, "fps": [30, 1],
             "has_video": true, "has_audio": true}
        ],
        "tracks": tracks,
        "clips": clips,
        "markers": [], "next_id": 90, "nests": []
    }))
}

/// A shape clip: sourceless, so no source window bounds any row here.
fn shape(id: u32, track: u32, start: i64, duration: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "shape"}, "video": {}, "shape": {}})
}

/// `add_transition_edges.rs`'s `odd_rate` pair — clips 10 [1 200 000,
/// 3 600 000) and 11 [3 600 000, 6 000 000), frames 14, 42 and 70 — plus
/// clip 12 at 4 800 000 (frame 56) on a second track, which the ripple
/// moves by the same delta.
fn odd_rate_pair() -> Handle {
    at_7fps(
        &[50, 51],
        json!([
            {"id": 10, "track": 50, "start": 1200000, "duration": 2400000,
             "source": {"kind": "media", "media": 1, "in": 3000000},
             "video": {}, "audio": {}},
            {"id": 11, "track": 50, "start": 3600000, "duration": 2400000,
             "source": {"kind": "media", "media": 1, "in": 12000000},
             "video": {}, "audio": {}},
            shape(12, 51, 4800000, 600000)
        ]),
    )
}

fn ripple(clip: u32, duration: i64) -> Value {
    json!({"op": "add_transition", "clip": clip, "duration": duration, "ripple": true})
}

fn start(project: &Value, id: u64) -> i64 {
    int(by_id(project, "/clips", id), "/start")
}

fn duration(project: &Value, id: u64) -> i64 {
    int(by_id(project, "/clips", id), "/duration")
}

fn transition(project: &Value, id: u64) -> &Value {
    by_id(project, "/clips", id)
        .get("transition_in")
        .unwrap_or(&Value::Null)
}

// ---- add_transition's ripple form counts the real grid -------------------

#[test]
fn a_rippled_transition_of_three_real_frames_lands_the_incoming_clip_three_frames_back() {
    // 257 143 ticks is exactly frame 3's boundary, so it is three whole
    // frames; the cut is frame 42, so the clip lands on frame 39.
    let after = odd_rate_pair().apply(&ripple(11, 257_143)).value();
    assert_eq!(start(&after, 11), grid(39));
    assert_eq!(start(&after, 11), 3_342_857);
    assert!(on_grid(start(&after, 11)));
    assert_eq!(duration(&after, 11), 2_400_000, "the clip moves whole");
    // The other track's clip moves by the SAME delta, and here that lands
    // it on frame 53.
    assert_eq!(start(&after, 12), 4_800_000 - (3_600_000 - grid(39)));
    assert_eq!(start(&after, 12), 4_542_857);
    assert!(on_grid(start(&after, 12)));
    assert_eq!(start(&after, 10), 1_200_000, "the outgoing clip stays");
    assert!(!transition(&after, 11).is_null());
}

#[test]
fn a_request_one_tick_short_of_three_frames_is_two_frames_of_the_real_grid() {
    // One tick under frame 3's boundary is two whole frames. Counted in
    // 1/30 s fallback frames it was twelve (240 000 ticks), and the clip
    // landed at 3 360 000 — frame 39.2, off the grid.
    let after = odd_rate_pair().apply(&ripple(11, 257_142)).value();
    assert_eq!(start(&after, 11), grid(40));
    assert_eq!(start(&after, 11), 3_428_571);
    assert!(on_grid(start(&after, 11)));
}

// ---- a shift is one delta ------------------------------------------------

#[test]
fn ripple_delete_keeps_two_abutting_clips_abutting_with_no_transition() {
    // Clip 20 is frames 2–3; clips 21 (85 715 ticks, frames 5–6) and 22
    // (frame 6 on) abut. Deleting 20 moves both back by its 85 714 ticks:
    // 342 857 and 428 572. Snapping each start apart would put 22 at
    // 428 571, a one-tick overlap `set_gained_transitions` mints a
    // cross_dissolve on.
    let project = at_7fps(
        &[50],
        json!([
            shape(20, 50, grid(2), grid(3) - grid(2)),
            shape(21, 50, grid(5), 85_715),
            shape(22, 50, grid(6), 85_714)
        ]),
    );
    assert_eq!(grid(5) + 85_715, grid(6), "the fixture's pair abuts");
    let after = project
        .apply(&json!({"op": "ripple_delete", "clips": [20]}))
        .value();
    let delta = grid(3) - grid(2);
    assert_eq!(start(&after, 21), grid(5) - delta);
    assert_eq!(start(&after, 21), 342_857);
    assert_eq!(start(&after, 22), grid(6) - delta);
    assert_eq!(start(&after, 22), 428_572);
    assert_eq!(start(&after, 21) + duration(&after, 21), start(&after, 22));
    assert!(transition(&after, 22).is_null(), "no overlap was made");
    assert!(
        (start(&after, 22) - grid(5)).abs() <= 1,
        "the start sits within a tick of the grid"
    );
}

#[test]
fn close_gap_keeps_two_abutting_clips_abutting_with_no_transition() {
    // F is frame 0; M (frame 3) and N (frame 4) abut. The gap is
    // [85 714, 257 143), so both move back 171 429 ticks: 85 714 and
    // 171 428, the second a tick short of frame 2 (171 429).
    let project = at_7fps(
        &[50],
        json!([
            shape(30, 50, 0, 85_714),
            shape(31, 50, 257_143, 85_714),
            shape(32, 50, 342_857, 85_714)
        ]),
    );
    let after = project
        .apply(&json!({"op": "close_gap", "track": 50, "at": grid(2)}))
        .value();
    assert_eq!(start(&after, 31), 85_714);
    assert_eq!(start(&after, 32), 171_428);
    assert_eq!(start(&after, 31) + duration(&after, 31), start(&after, 32));
    assert!(transition(&after, 32).is_null(), "no overlap was made");
    assert_eq!(
        start(&after, 32),
        grid(2) - 1,
        "a tick off the grid, by design"
    );
}
