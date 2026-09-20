//! THE invariant, at every site that writes a media clip's window:
//! `in + duration × speed ≤ media.duration`, with `duration` on the canvas
//! grid, so the plan hands AVFoundation a segment whose rate is exactly the
//! clip's speed (spec §11, #22 and D4-2 to D4-5; road map 7 §10, phase B).
//!
//! `core/tests/source_window.rs` proves the module's arithmetic is ONE
//! equation in the right unit; this file proves every WRITER reads it. So
//! every vector here was measured against the tree before the change and
//! chosen because the two answers DIFFER — each comment carries the old
//! number beside the new one — except two rows named PIN, which exist
//! because an answer that must NOT move is as much a claim as one that must.
//!
//! The invariant is asserted the same way everywhere: the placement is read
//! back through the written project, and then the PLAN's segment is read,
//! because the plan is where the defect showed — a duration a rounding put
//! past the end of its file came back as a segment whose rate was not the
//! clip's speed, and AVFoundation resampled material nobody asked to retime.

use serde_json::{json, Value};

mod common;
use common::{array, assert_contains, by_id, int, source_in, Handle};

/// Ticks per second (spec §5.1), written out rather than imported so a
/// change to `time::TIMESCALE` fails this file instead of moving with it.
const SEC: i64 = 600_000;

/// One frame at 30 fps, and one at the 24 fps the `unnest` vector moves to.
const FRAME_30: i64 = SEC / 30;
const FRAME_24: i64 = SEC / 24;

/// A file whose length is not a whole number of 30 fps frames and whose
/// last frame is MORE than half short: 6 233 613 is 311.68 frames, so
/// `add_clip` gives 311 of them (6 220 000) and a ×2 duration of half that
/// rounds UP to 156 (3 120 000), which is 6 240 000 ticks of source — past
/// the end of the file. The measured overrun of `silence2_proof.py` 1(d).
const ODD_FILE: i64 = 6_233_613;

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

fn project(fps: [u32; 2], media: Vec<Value>, clips: Vec<Value>) -> Value {
    json!({
        "version": 8,
        "canvas": {
            "width": 1920, "height": 1080, "fps": fps,
            "background": [0, 0, 0, 1], "fit_new_clips": true,
            "timecode_frames": true
        },
        "media": media,
        "tracks": [{"id": 5, "name": "Picture"}, {"id": 6, "name": "Bed"}],
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

// ---- reading a landed clip back ------------------------------------------

fn placement(value: &Value, clip: u64) -> (i64, i64) {
    let found = by_id(value, "/clips", clip);
    (int(found, "/start"), int(found, "/duration"))
}

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

/// THE invariant, read off the written project and the plan at once: the
/// window the clip claims fits inside the file, and the segment the plan
/// asks for is exactly `duration × speed` — the rate AVFoundation will play
/// it at, which is the number the whole phase is about.
fn holds(handle: &Handle, clip: u64, speed: f64, media_duration: i64) {
    let value = handle.value();
    let (_, duration) = placement(&value, clip);
    let landed = source_in(&value, clip);
    let consumed = (duration as f64 * speed).round() as i64;
    assert!(
        landed + consumed <= media_duration,
        "clip {clip}: in {landed} + {duration} × {speed} = {} runs past a file of \
         {media_duration}",
        landed + consumed
    );
    let plan = handle.plan();
    for group in ["video_tracks", "audio_tracks"] {
        let segment = segment_of(&plan, group, clip);
        assert_eq!(
            int(&segment, "/source_duration"),
            consumed,
            "{group}: the plan asks for a segment whose rate is not ×{speed}"
        );
    }
}

// ---- D4-3: set_speed ------------------------------------------------------

#[test]
fn a_whole_file_clip_set_to_double_speed_plays_at_exactly_double_speed() {
    // The vector `silence2_proof.py` 1(d) measures. `add_clip` of the odd
    // file gives 6 220 000; ×2 wants 3 110 000, whose NEAREST frame is
    // 3 120 000 — 6 240 000 ticks of source out of a file holding
    // 6 233 613, which the plan clamped back to the remainder and handed
    // over at rate 1.99795. Held to the bound measured AT ×2 it is
    // 3 100 000 (155 frames), and the segment is 6 200 000: exactly double.
    let handle = Handle::from_value(&project([30, 1], vec![video(1, ODD_FILE)], vec![]));
    let placed = handle.apply(&json!({"op": "add_clip", "track": 5, "media": 1, "at": 0}));
    assert_eq!(
        placement(&placed.value(), 100),
        (0, 311 * FRAME_30),
        "add_clip's own length is unchanged: 311 whole frames, snapped DOWN"
    );

    let sped = placed.apply(&json!({"op": "set_speed", "clip": 100, "rate": 2.0}));
    assert_eq!(
        placement(&sped.value(), 100),
        (0, 155 * FRAME_30),
        "3 100 000, the bound at ×2 — where the nearest snap alone gave 3 120 000"
    );
    holds(&sped, 100, 2.0, ODD_FILE);
}

#[test]
fn a_mid_file_clip_keeps_the_nearest_snap_its_speed_asks_for() {
    // PIN — this answer must NOT move. 200 000 ticks of content at ×1.3 is
    // 153 846, whose nearest frame is 160 000: the snap rounds UP, and the
    // window grows to 208 000 ticks of source. There is room for it (the
    // clip sits at the head of a six-second file), so the bound does not
    // bite and `set_speed` writes what it always wrote.
    let handle = Handle::from_value(&project(
        [30, 1],
        vec![video(1, 6 * SEC)],
        vec![clip(10, 1, 0, 10 * FRAME_30, 0, 1.0)],
    ));
    let sped = handle.apply(&json!({"op": "set_speed", "clip": 10, "rate": 1.3}));
    assert_eq!(
        placement(&sped.value(), 10),
        (0, 8 * FRAME_30),
        "160 000: the nearest snap, rounded UP, with the file's tail far away"
    );
    holds(&sped, 10, 1.3, 6 * SEC);
}

// ---- D4-4: every re-snap of a duration ------------------------------------

/// The payload `paste` reads (`core/src/edit_paste.rs`'s module doc), whose
/// clip is 650 000 ticks long — 26 frames at 24 fps — over a media of
/// 655 000. On a 30 fps grid 650 000 re-snaps UP to 660 000, five thousand
/// ticks past the end of the file; held to the bound it is 640 000.
fn overrunning_payload(nested: bool) -> Value {
    // `track` is a DEPTH on a payload clip and a track ID inside a nest
    // (`edit_paste.rs`), which is the one difference between the two forms.
    let inner = json!({
        "id": 1, "track": if nested { 4 } else { 0 }, "start": 0, "duration": 650_000,
        "speed": 1.0,
        "source": {"kind": "media", "media": 7, "in": 0},
        "video": {}, "audio": {}
    });
    let media = json!([{
        "id": 7, "path": "/m/short.mov", "kind": "video", "duration": 655_000,
        "width": 1920, "height": 1080, "fps": [24, 1],
        "has_video": true, "has_audio": true
    }]);
    if !nested {
        return json!({"clips": [inner], "media": media});
    }
    json!({
        "clips": [{
            "id": 2, "track": 0, "start": 0, "duration": 650_000,
            "source": {"kind": "nest", "project": 3}, "video": {}
        }],
        "media": media,
        "nests": [{
            "id": 3, "name": "Nest", "width": 1920, "height": 1080,
            "tracks": [{"id": 4, "name": "Inner"}],
            "clips": [inner]
        }]
    })
}

#[test]
fn a_pasted_clip_is_re_snapped_onto_the_grid_and_then_inside_its_file() {
    let handle = Handle::from_value(&project([30, 1], vec![], vec![]));
    let pasted = handle.apply(&json!({
        "op": "paste", "at": 0, "payload": overrunning_payload(false)
    }));
    let value = pasted.value();
    let landed = int(&array(&value, "/clips")[0], "/id") as u64;
    assert_eq!(
        placement(&value, landed),
        (0, 32 * FRAME_30),
        "640 000, the bound — where the re-snap alone gave 660 000 over a 655 000 file"
    );
    holds(&pasted, landed, 1.0, 655_000);
}

#[test]
fn a_clip_inside_a_pasted_nest_is_held_to_its_file_too() {
    // `absorb_nests` is the second writer in this op and it was the same
    // 660 000. The nest's contents are read through the written document
    // rather than through the plan, which flattens them.
    let handle = Handle::from_value(&project([30, 1], vec![], vec![]));
    let value = handle
        .apply(&json!({"op": "paste", "at": 0, "payload": overrunning_payload(true)}))
        .value();
    let inner: Vec<i64> = array(&value, "/nests")
        .iter()
        .flat_map(|n| array(n, "/clips").iter().map(|c| int(c, "/duration")))
        .collect();
    assert_eq!(
        inner,
        vec![32 * FRAME_30],
        "640 000 inside the nest, not the 660 000 the re-snap alone gave"
    );
}

#[test]
fn an_unnested_clip_is_re_snapped_onto_the_grid_and_then_inside_its_file() {
    // A whole-file clip of a 645 000-tick media (640 000 on a 30 fps grid),
    // nested, and the document then moved to 24 fps. `set_canvas`'s re-snap
    // walks the timeline's clips ONLY, so the nested clip is still on the
    // old grid when `unnest` hands it back: 640 000 re-snaps UP to 650 000
    // at 24 fps, past the end of the file, and the bound holds it to 25
    // frames — 625 000.
    let handle = Handle::from_value(&project([30, 1], vec![video(1, 645_000)], vec![]));
    let nested = handle.apply_all(&[
        json!({"op": "add_clip", "track": 5, "media": 1, "at": 0}),
        json!({"op": "nest", "clips": [100]}),
        json!({"op": "set_canvas", "fps": [24, 1]}),
    ]);
    let nest_clip = int(&array(&nested.value(), "/clips")[0], "/id");
    let opened = nested.apply(&json!({"op": "unnest", "clip": nest_clip}));
    let value = opened.value();
    let landed = int(&array(&value, "/clips")[0], "/id") as u64;
    assert_eq!(
        placement(&value, landed),
        (0, 25 * FRAME_24),
        "625 000, the bound on the new grid — where the re-snap alone gave 650 000"
    );
    holds(&opened, landed, 1.0, 645_000);
}

// ---- D4-4: the timeline-length plate --------------------------------------

#[test]
fn a_video_background_ends_where_its_file_does_rather_than_stretching() {
    // A six-second file used as the backdrop of a twelve-second cut. The
    // plate ran the timeline's length and the plan stretched the file over
    // it at rate 0.5 — the op's doc claimed it "shows nothing" for the
    // second half, which was false. Held to `whole_media_length` it is six
    // seconds of plate at rate 1, and the rest of the cut shows the canvas.
    let handle = Handle::from_value(&project(
        [30, 1],
        vec![video(1, 6 * SEC)],
        vec![json!({
            "id": 10, "track": 5, "start": 6 * SEC, "duration": 6 * SEC,
            "source": {"kind": "text"}, "video": {}, "text": {"content": "Hi"}
        })],
    ));
    assert_eq!(handle.duration(), 12 * SEC, "the timeline the plate covers");
    let plated = handle.apply(&json!({"op": "add_background", "media": 1}));
    assert_eq!(
        placement(&plated.value(), 101),
        (0, 6 * SEC),
        "the plate is the file's own length, not the timeline's 12 s"
    );
    holds(&plated, 101, 1.0, 6 * SEC);
}

#[test]
fn a_given_background_duration_is_held_to_the_file_as_well() {
    let handle = Handle::from_value(&project([30, 1], vec![video(1, ODD_FILE)], vec![]));
    let plated = handle.apply(&json!({
        "op": "add_background", "media": 1, "duration": 20 * SEC
    }));
    assert_eq!(
        placement(&plated.value(), 101),
        (0, 311 * FRAME_30),
        "6 220 000: `add_clip`'s own measurement of the whole file"
    );
    holds(&plated, 101, 1.0, ODD_FILE);
}

#[test]
fn an_image_background_still_runs_the_whole_timeline() {
    // The other arm, pinned: an image has no source bound at all, so the
    // clamp must not reach it — a five-second PNG is still a plate as long
    // as the cut.
    let handle = Handle::from_value(&project(
        [30, 1],
        vec![json!({
            "id": 2, "path": "/m/wall.png", "kind": "image",
            "width": 3840, "height": 2400, "fps": [30, 1], "duration": 3 * SEC
        })],
        vec![json!({
            "id": 10, "track": 5, "start": 0, "duration": 12 * SEC,
            "source": {"kind": "text"}, "video": {}, "text": {"content": "Hi"}
        })],
    ));
    let plated = handle.apply(&json!({"op": "add_background", "media": 2}));
    assert_eq!(
        placement(&plated.value(), 101),
        (0, 12 * SEC),
        "an image plate covers the cut, however long its descriptor says it is"
    );
}

#[test]
fn a_background_of_a_media_shorter_than_a_frame_is_an_error_naming_the_frame() {
    // The plate reads `whole_media_length`, so it inherits that function's
    // two `Err` sentences — this one used to be a twelve-second plate of a
    // file holding a third of a frame.
    let handle = Handle::from_value(&project(
        [30, 1],
        vec![video(1, 6_000)],
        vec![json!({
            "id": 10, "track": 5, "start": 0, "duration": 12 * SEC,
            "source": {"kind": "text"}, "video": {}, "text": {"content": "Hi"}
        })],
    ));
    let message = handle.errors(&json!({"op": "add_background", "media": 1}));
    assert_contains(
        &message,
        "media 1 is shorter than a frame (6000 ticks; a frame is 20000 ticks)",
    );
}
