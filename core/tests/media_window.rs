//! A media clip's window stays INSIDE its file, on the grid — spec §11
//! (kpgalligan/framejob#22), through the FFI.
//!
//! Three sites write a media clip's duration from its source:
//! `whole_media_length` (what `add_clip` gives a clip, and therefore the room
//! `insert_clip` opens and the span `overwrite_clip` clears), `set_canvas`'s
//! fps re-snap, and `trim_end`'s tail clamp. All three snap DOWN, so
//! `in + duration × speed ≤ media.duration` holds by construction and the
//! plan hands the clip a segment whose `source_duration` equals its
//! `duration` — the rate AVFoundation plays it at is exactly 1.
//!
//! Every media length below is chosen so the NEAREST snap and the DOWN snap
//! DIFFER, except the rows marked as regression rows: a vector where the two
//! agree cannot fail against a build that kept the nearest snap, and a test
//! that cannot fail proves nothing. Each row's frame arithmetic is written
//! out in its comment rather than computed here, so a change in `time.rs`
//! fails these tests instead of moving with them.

use serde_json::{json, Value};

mod common;
use common::{array, assert_contains, by_id, int, Handle};

// ---- the oracle's own constants ------------------------------------------

/// Ticks per second (spec §5.1), written out rather than imported so a change
/// to `time::TIMESCALE` fails this file instead of moving with it.
const SEC: i64 = 600_000;

/// One frame at 30 fps, at 25 fps, and at 30000/1001 — the last exactly
/// 600 000 × 1001 / 30000 ticks, which divides out to a whole number.
const FRAME_30: i64 = SEC / 30;
const FRAME_25: i64 = SEC / 25;
const DROP_FRAME: i64 = 20_020;

/// The id `add_clip` mints here: the fixtures' `next_id` (spec §6 — a new id
/// is the project's `next_id` from BEFORE the call).
const MINTED: u64 = 30;

// ---- fixtures ------------------------------------------------------------

/// A timed media of exactly `duration` ticks, with both a picture and a
/// sound track so the plan carries a video AND an audio segment for it.
fn media(id: u32, duration: i64) -> Value {
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

fn clip(id: u32, track: u32, start: i64, duration: i64, source: u32, source_in: i64) -> Value {
    json!({
        "id": id,
        "track": track,
        "start": start,
        "duration": duration,
        "source": {"kind": "media", "media": source, "in": source_in},
        "video": {},
        "audio": {}
    })
}

/// Two tracks, the given media and clips, and `next_id` 30.
fn project(fps: [u32; 2], media: Vec<Value>, clips: Vec<Value>) -> Value {
    json!({
        "version": 2,
        "canvas": {
            "width": 1920, "height": 1080, "fps": fps,
            "background": [0, 0, 0, 1], "fit_new_clips": true,
            "timecode_frames": true
        },
        "media": media,
        "tracks": [{"id": 5, "name": "Picture"}, {"id": 6, "name": "Bed"}],
        "clips": clips,
        "markers": [],
        "next_id": 30
    })
}

// ---- reading a landed clip back ------------------------------------------

/// The segment for `clip` on the given side of the plan, wherever it landed.
fn segment_of(plan: &Value, group: &str, clip: u64) -> Value {
    for comp in array(plan, &format!("/{group}")) {
        for segment in array(comp, "/segments") {
            if int(segment, "/clip") == clip as i64 {
                return segment.clone();
            }
        }
    }
    panic!("no {group} segment for clip {clip} in {plan}");
}

/// The invariant, asserted on the project as it was read back: `clip`'s start
/// and duration are whole frames of `frame`, and its source window ends at or
/// before the end of the media it names. Returns the duration, which every
/// row then compares against the length it worked out on paper.
fn assert_inside(value: &Value, clip: u64, media: u64, frame: i64) -> i64 {
    let landed = by_id(value, "/clips", clip);
    let start = int(landed, "/start");
    let duration = int(landed, "/duration");
    let source_in = int(landed, "/source/in");
    let speed = landed.get("speed").and_then(Value::as_f64).unwrap_or(1.0);
    let file = int(by_id(value, "/media", media), "/duration");
    assert_eq!(
        start % frame,
        0,
        "clip {clip} starts at {start}, which is not a whole {frame}-tick frame"
    );
    assert_eq!(
        duration % frame,
        0,
        "clip {clip} runs {duration}, which is not a whole {frame}-tick frame"
    );
    assert_eq!(
        (start + duration) % frame,
        0,
        "clip {clip} ends at {}, which is not a whole {frame}-tick frame",
        start + duration
    );
    let consumed = source_in + (duration as f64 * speed).round() as i64;
    assert!(
        consumed <= file,
        "clip {clip} consumes {consumed} ticks of a media that holds {file}"
    );
    duration
}

// ---- 1. what `add_clip` mints --------------------------------------------

#[test]
fn a_whole_file_clip_lands_on_the_last_whole_frame_inside_its_media() {
    // (the file's length, the clip's, what the NEAREST snap would have given)
    for (length, expected, nearest) in [
        // 300.6 frames: the nearest boundary is 301, which is 20 000 ticks
        // past the end of the file. The row that moves against a nearest
        // snap.
        (6_012_000, 6_000_000, 6_020_000),
        // 300.4 frames: nearest and down agree — a regression row.
        (6_008_000, 6_000_000, 6_000_000),
        // Exactly 300 frames — a regression row.
        (6_000_000, 6_000_000, 6_000_000),
    ] {
        let handle = Handle::from_value(&project([30, 1], vec![media(1, length)], vec![]));
        let placed = handle.apply(&json!({"op": "add_clip", "track": 5, "media": 1, "at": 0}));
        let value = placed.value();
        let duration = assert_inside(&value, MINTED, 1, FRAME_30);
        assert_eq!(
            duration, expected,
            "a {length}-tick media makes a clip of {duration} (nearest would give {nearest})"
        );
        assert_eq!(int(by_id(&value, "/clips", MINTED), "/start"), 0);

        // The point of the bound: the plan asks for exactly as much source as
        // the clip is long, on both sides, so Swift inserts it at rate 1 and
        // nothing is resampled (spec §7.2).
        let plan = placed.plan();
        for group in ["video_tracks", "audio_tracks"] {
            let segment = segment_of(&plan, group, MINTED);
            assert_eq!(int(&segment, "/source_in"), 0, "{group} source_in");
            assert_eq!(
                int(&segment, "/source_duration"),
                duration,
                "{group} plays {length} ticks of source at rate 1"
            );
            assert_eq!(int(&segment, "/duration"), duration, "{group} duration");
        }
    }
}

#[test]
fn the_bound_holds_at_a_drop_frame_rate() {
    // 6 020 000 / 20 020 = 300.6993 frames: the nearest boundary is frame
    // 301 at 6 026 020, six thousand ticks PAST the end of the file, and the
    // last one inside it is frame 300 at 6 006 000. (6 016 000 would not do:
    // its nearest is already frame 300, so the row could not fail.)
    let handle = Handle::from_value(&project([30000, 1001], vec![media(1, 6_020_000)], vec![]));
    let placed = handle.apply(&json!({"op": "add_clip", "track": 5, "media": 1, "at": 0}));
    let value = placed.value();
    let duration = assert_inside(&value, MINTED, 1, DROP_FRAME);
    assert_eq!(
        duration,
        300 * DROP_FRAME,
        "the clip stops on frame 300 (6 006 000), not on 301 (6 026 020)"
    );
    let plan = placed.plan();
    for group in ["video_tracks", "audio_tracks"] {
        assert_eq!(
            int(&segment_of(&plan, group, MINTED), "/source_duration"),
            duration,
            "{group} at 30000/1001 plays at rate 1"
        );
    }
}

// ---- 2. the two ops that open room for that length -----------------------

#[test]
fn insert_and_overwrite_open_exactly_that_length() {
    // Media 2 is the 6 012 000-tick file of the first test; clip 10 sits at
    // 6 000 000, which is exactly where a down-snapped whole-file clip ends.
    let handle = Handle::from_value(&project(
        [30, 1],
        vec![media(1, 36_000_000), media(2, 6_012_000)],
        vec![clip(10, 5, 6_000_000, 1_000_000, 1, 0)],
    ));

    let inserted = handle.apply(&json!({"op": "insert_clip", "track": 5, "media": 2, "at": 0}));
    let value = inserted.value();
    assert_eq!(assert_inside(&value, MINTED, 2, FRAME_30), 6_000_000);
    assert_eq!(
        int(by_id(&value, "/clips", 10), "/start"),
        6_000_000 + 6_000_000,
        "the room opened is the clip's own length, so the clip that was at \
         6 000 000 moved by exactly that"
    );

    let over = handle.apply(&json!({"op": "overwrite_clip", "track": 5, "media": 2, "at": 0}));
    let value = over.value();
    assert_eq!(assert_inside(&value, MINTED, 2, FRAME_30), 6_000_000);
    let following = by_id(&value, "/clips", 10);
    assert_eq!(
        (int(following, "/start"), int(following, "/duration")),
        (6_000_000, 1_000_000),
        "the span cleared is [0, 6 000 000), so the clip at 6 000 000 is whole"
    );
}

// ---- 3. the media that cannot be a clip ----------------------------------

#[test]
fn a_media_shorter_than_a_frame_is_an_error_naming_the_frame() {
    // 12 000 ticks is 0.6 of a 30 fps frame: the nearest snap would mint a
    // 20 000-tick clip of 8 000 ticks of nothing.
    let handle = Handle::from_value(&project(
        [30, 1],
        vec![media(1, 12_000), media(2, 0)],
        vec![],
    ));
    for op in ["add_clip", "insert_clip", "overwrite_clip"] {
        let message = handle.errors(&json!({"op": op, "track": 5, "media": 1, "at": 0}));
        assert_contains(&message, "media 1 is shorter than a frame");
        assert_contains(&message, "12000");
        assert_contains(&message, "20000");

        // The older sentence, unchanged: a media with no duration at all.
        let message = handle.errors(&json!({"op": op, "track": 5, "media": 2, "at": 0}));
        assert_contains(&message, "media 2 has no duration");
    }

    // At a rate that does not divide the timescale the frame the sentence
    // names is the real grid (`snapped_up(1)`), not `frame()`'s 1/30 s
    // fallback: 22 000 ticks at 24981/1000 is under the 24 018-tick frame,
    // and a sentence saying "a frame is 20000 ticks" would contradict itself.
    let handle = Handle::from_value(&project([24981, 1000], vec![media(1, 22_000)], vec![]));
    let message = handle.errors(&json!({"op": "add_clip", "track": 5, "media": 1, "at": 0}));
    assert_contains(&message, "media 1 is shorter than a frame");
    assert_contains(&message, "22000");
    assert_contains(&message, "24018");
}

// ---- 4. the fps re-snap --------------------------------------------------

#[test]
fn a_rate_change_keeps_the_window_inside_the_media() {
    // Clip 11 is a trimmed window: in 1 000 000, 251 frames of 30 fps.
    let handle = Handle::from_value(&project(
        [30, 1],
        vec![media(1, 6_021_000)],
        vec![clip(11, 6, 0, 5_020_000, 1, 1_000_000)],
    ));
    let placed = handle.apply(&json!({"op": "add_clip", "track": 5, "media": 1, "at": 0}));
    let value = placed.value();
    assert_eq!(assert_inside(&value, MINTED, 1, FRAME_30), 6_020_000);

    let slower = placed.apply(&json!({"op": "set_canvas", "fps": [25, 1]}));
    let value = slower.value();
    // 6 020 000 re-snapped to a 24 000-tick grid is frame 251, 6 024 000 —
    // three thousand ticks past the file. The source bound is 6 021 000
    // snapped DOWN, frame 250, 6 000 000.
    assert_eq!(assert_inside(&value, MINTED, 1, FRAME_25), 6_000_000);
    // And the trimmed one: 5 020 000 re-snaps to frame 209, 5 016 000, which
    // is inside the 5 021 000 ticks its `in` leaves — it keeps its re-snap.
    assert_eq!(assert_inside(&value, 11, 1, FRAME_25), 5_016_000);
    assert_eq!(int(by_id(&value, "/clips", 11), "/source/in"), 1_000_000);
}

// ---- 5. the tail clamp ---------------------------------------------------

#[test]
fn trim_end_past_the_media_stops_on_the_grid() {
    let handle = Handle::from_value(&project([30, 1], vec![media(1, 6_021_000)], vec![]));
    let placed = handle.apply(&json!({"op": "add_clip", "track": 5, "media": 1, "at": 0}));
    let short = placed.apply(&json!({"op": "trim_end", "clip": MINTED, "to": 3_000_000}));
    assert_eq!(
        assert_inside(&short.value(), MINTED, 1, FRAME_30),
        3_000_000
    );

    // Dragged back out past the end of the file: the clamp is the file's
    // remaining length snapped DOWN, so the end lands on frame 301 and not on
    // the 6 021 000 the file actually holds.
    let back = short.apply(&json!({"op": "trim_end", "clip": MINTED, "to": 9_000_000}));
    assert_eq!(assert_inside(&back.value(), MINTED, 1, FRAME_30), 6_020_000);

    // The same from a trimmed head: the bound is `start` plus what the file
    // has left, snapped down.
    let moved = short.apply(&json!({"op": "trim_start", "clip": MINTED, "to": 1_000_000}));
    let out = moved.apply(&json!({"op": "trim_end", "clip": MINTED, "to": 9_000_000}));
    let value = out.value();
    assert_eq!(assert_inside(&value, MINTED, 1, FRAME_30), 5_020_000);
    assert_eq!(int(by_id(&value, "/clips", MINTED), "/start"), 1_000_000);
    assert_eq!(
        int(by_id(&value, "/clips", MINTED), "/source/in"),
        1_000_000
    );
}
