//! The two EDGE writers of a media clip's window, through the FFI: the
//! head bound `trim_start` clamps against and the end bound `trim_end`
//! does (spec §11, D4-2 and D4-5; road map 7 §10, phase B).
//!
//! Split out of `core/tests/source_invariant.rs` at the 400-line cap for a
//! new test file, which is the only reason it is a file of its own: the
//! rows read the same way and were measured the same way — each vector
//! chosen so the answer before the change and the answer after it DIFFER,
//! except the two named PIN, which pin an answer that must NOT move.
//!
//! `roll` reads both of the same two functions and its sixteen rows are
//! `core/tests/edge.rs`'s, unchanged by this phase: that is the claim that
//! routing it through them moved no answer.

use serde_json::{json, Value};

mod common;
use common::{by_id, int, source_in, Handle, Outcome};

/// Ticks per second (spec §5.1), written out rather than imported so a
/// change to `time::TIMESCALE` fails this file instead of moving with it.
const SEC: i64 = 600_000;

/// One frame at 30 fps, the grid every fixture here sits on.
const FRAME_30: i64 = SEC / 30;

// ---- fixtures ------------------------------------------------------------

fn video(id: u32, duration: i64) -> Value {
    json!({
        "id": id,
        "path": format!("/m/{id}.mov"),
        "kind": "video",
        "duration": duration,
        "width": 1920,
        "height": 1080,
        "fps": [30, 1],
        "has_video": true,
        "has_audio": true
    })
}

fn project(media: Vec<Value>, clips: Vec<Value>) -> Value {
    json!({
        "version": 8,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1],
            "background": [0, 0, 0, 1], "fit_new_clips": true,
            "timecode_frames": true
        },
        "media": media,
        "tracks": [{"id": 5, "name": "Picture"}],
        "clips": clips,
        "markers": [],
        "next_id": 100
    })
}

/// A media clip, with its speed and in point written out: every claim here
/// is about what those two do to a measurement.
fn clip(id: u32, media: u32, start: i64, duration: i64, source_in: i64, speed: f64) -> Value {
    json!({
        "id": id,
        "track": 5,
        "start": start,
        "duration": duration,
        "speed": speed,
        "source": {"kind": "media", "media": media, "in": source_in},
        "video": {},
        "audio": {}
    })
}

fn placement(value: &Value, clip: u64) -> (i64, i64) {
    let found = by_id(value, "/clips", clip);
    (int(found, "/start"), int(found, "/duration"))
}

// ---- D4-5: the head bound is snapped UP -----------------------------------

#[test]
fn a_far_left_trim_lands_on_a_frame_rather_than_on_the_floored_head() {
    // ×2 with 130 000 ticks of source in front: the head is 65 000 timeline
    // ticks, so the edge could reach 135 000 — six and three quarter frames,
    // a sub-frame start, which is what `trim_start` used to write. Snapped
    // UP the edge stops at 140 000, one frame INSIDE the material, and the
    // in point that follows it is 10 000 rather than 0.
    let handle = Handle::from_value(&project(
        vec![video(1, 6 * SEC)],
        vec![clip(20, 1, 200_000, 10 * FRAME_30, 130_000, 2.0)],
    ));
    let trimmed = handle.apply(&json!({"op": "trim_start", "clip": 20, "to": -10 * SEC}));
    let value = trimmed.value();
    assert_eq!(
        placement(&value, 20),
        (140_000, 260_000),
        "the head clamp, snapped UP: 135 000 was not on the grid"
    );
    assert_eq!(int(&value, "/clips/0/start") % FRAME_30, 0, "a whole frame");
    assert_eq!(
        source_in(&value, 20),
        10_000,
        "the in point walked back by 60 000 × 2, not by all 130 000"
    );
}

#[test]
fn a_far_left_trim_of_an_off_grid_clip_with_no_head_moves_it_onto_the_grid() {
    // The one other corner D4-5 changes, taken on purpose: a hand-written
    // clip starting at 205 000 with nothing in front of it. Its head bound
    // was its own off-grid start, so the op was an identity; snapped UP it
    // is 220 000, and the trim lands there — `roll`'s answer at the same
    // edge, one frame further into the source.
    let handle = Handle::from_value(&project(
        vec![video(1, 6 * SEC)],
        vec![clip(20, 1, 205_000, 10 * FRAME_30, 0, 1.0)],
    ));
    let trimmed = handle.apply(&json!({"op": "trim_start", "clip": 20, "to": 0}));
    let value = trimmed.value();
    assert_eq!(
        placement(&value, 20),
        (220_000, 185_000),
        "the clip's end did not move and its start is on a frame"
    );
    assert_eq!(
        source_in(&value, 20),
        15_000,
        "in advanced by 220 000 − 205 000"
    );
}

// ---- D4-2: the END writers, pinned ---------------------------------------

#[test]
fn a_far_right_trim_of_an_off_grid_clip_still_lands_on_the_grid() {
    // PIN — this answer must NOT move. `trim_end` measures the bound at the
    // clip's OWN start, which is why the bound function takes `start`: at
    // ×2 out of a 1 100 000-tick file the window is 550 000 timeline ticks,
    // 205 000 + 550 000 = 755 000, and the last frame at or before that is
    // 740 000. Measured from 0 instead the answer would be 745 000 — off
    // the grid, which is the thing #22 closed.
    let handle = Handle::from_value(&project(
        vec![video(1, 1_100_000)],
        vec![clip(30, 1, 205_000, 10 * FRAME_30, 0, 2.0)],
    ));
    let trimmed = handle.apply(&json!({"op": "trim_end", "clip": 30, "to": 100 * SEC}));
    let value = trimmed.value();
    let (start, duration) = placement(&value, 30);
    assert_eq!((start, duration), (205_000, 535_000), "the end is 740 000");
    assert_eq!((start + duration) % FRAME_30, 0, "and it is on the grid");
    assert!(
        source_in(&value, 30) + duration * 2 <= 1_100_000,
        "the window still fits: {duration} ticks at ×2 is {} of source",
        duration * 2
    );
}

#[test]
fn a_trim_end_on_an_unmeasurable_window_is_still_unbounded() {
    // D4-2's second half, pinned: a hand-written clip at speed 0 has a
    // window that exists and cannot be measured, and the tail clamp reads
    // that as NO CLAMP — "empty" would freeze an edge over a field no trim
    // can fix. `evaluate.rs`'s last-line clamp is what covers the result.
    let handle = Handle::from_value(&project(
        vec![video(1, 1_100_000)],
        vec![clip(40, 1, 200_000, 10 * FRAME_30, 0, 0.0)],
    ));
    match handle.try_apply(&json!({"op": "trim_end", "clip": 40, "to": 3_200_000})) {
        Ok(Outcome::Applied(next)) => assert_eq!(
            placement(&next.value(), 40),
            (200_000, 3_000_000),
            "the tail clamp did not run"
        ),
        other => panic!("trim_end on an unmeasured window should apply, got {other:?}"),
    }
}
