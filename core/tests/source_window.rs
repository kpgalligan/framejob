//! The source window — one mover, three readers, one on-grid bound
//! (`core/src/source_window.rs`, road map 7 §10 phase A), through the FFI.
//!
//! The module exists because the arithmetic it holds is written in TWO
//! units and the callers used to convert between them by hand. So every
//! claim below is a UNIT claim, and every vector is chosen so a wrong unit
//! or a wrong rounding produces a different number:
//!
//! - **`round` must differ from `floor`.** The movers advance a source in
//!   point by `round(Δ × speed)`, so the speed here is 1.00003 and the
//!   delta one 20 000-tick frame: `20 000 × 1.00003 = 20 000.6`, which
//!   rounds to 20 001 and floors to 20 000.
//! - **`×` must differ from `÷`.** The readers divide where the movers
//!   multiply, so every reader vector runs at speed 2, where the two
//!   directions are a factor of four apart.
//!
//! Each row's arithmetic is written out in its comment rather than computed
//! here, so a change in the module fails these tests instead of moving with
//! them. Op arguments are `core/src/op_table.rs`'s.

use framejob_core::source_window::SourceBound;
use framejob_core::{Outcome, Project};
use serde_json::{json, Value};

mod common;
use common::{array, by_id, int, source_in, Handle};

// ---- the oracle's own constants ------------------------------------------

/// Ticks per second (spec §5.1), written out rather than imported so a
/// change to `time::TIMESCALE` fails this file instead of moving with it.
const SEC: i64 = 600_000;

/// One frame at 30 fps and one at 15 fps — the two grids below.
const FRAME_30: i64 = SEC / 30;
const FRAME_15: i64 = SEC / 15;

/// The speed that makes `round` and `floor` disagree over one frame:
/// `20 000 × 1.00003 = 20 000.6`.
const ODD_SPEED: f64 = 1.00003;

/// What one frame of timeline is worth in SOURCE ticks at [`ODD_SPEED`] —
/// `round(20 000.6)`. A mover that floored, or that divided, would write
/// 20 000 or 19 999 instead.
const ODD_FRAME_IN_SOURCE: i64 = 20_001;

/// The ids the fixtures' `next_id` hands out, in order (spec §6 — a new id
/// is the project's `next_id` from BEFORE the call).
const MINTED: u64 = 100;
const MINTED_SECOND: u64 = 101;

// ---- fixtures ------------------------------------------------------------

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

/// A media clip. `speed` is written out on every clip here, because every
/// claim in this file is about what a speed does to a measurement.
fn clip(id: u32, track: u32, start: i64, duration: i64, source_in: i64, speed: f64) -> Value {
    json!({
        "id": id,
        "track": track,
        "start": start,
        "duration": duration,
        "speed": speed,
        "source": {"kind": "media", "media": 1, "in": source_in},
        "video": {},
        "audio": {}
    })
}

/// Two tracks, one media of `length` ticks, the given clips, `next_id` 100.
fn project(fps: [u32; 2], length: i64, clips: Vec<Value>) -> Value {
    json!({
        "version": 2,
        "canvas": {
            "width": 1920, "height": 1080, "fps": fps,
            "background": [0, 0, 0, 1], "fit_new_clips": true,
            "timecode_frames": true
        },
        "media": [media(1, length)],
        "tracks": [{"id": 5, "name": "Picture"}, {"id": 6, "name": "Bed"}],
        "clips": clips,
        "markers": [],
        "next_id": 100
    })
}

/// Clip 11 sits at 400 000 with 1 000 000 ticks of source in front of it,
/// and clip 10 ends EXACTLY where it starts, which is the hard cut `roll`
/// and `add_transition` both need. Both run at [`ODD_SPEED`]; the media is
/// six seconds, far more than any of the six movers below consumes.
fn cut() -> Handle {
    Handle::from_value(&project(
        [30, 1],
        6 * SEC,
        vec![
            clip(10, 5, 0, 20 * FRAME_30, 0, ODD_SPEED),
            clip(11, 5, 400_000, 20 * FRAME_30, 1_000_000, ODD_SPEED),
        ],
    ))
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

/// The source TIME of the one `still` clip in a written project — what
/// `freeze_frame` froze. The still is minted after the split, so it is
/// found by its source kind rather than by an id worked out on paper.
fn still_at(value: &Value) -> i64 {
    let found: Vec<&Value> = array(value, "/clips")
        .iter()
        .filter(|c| c.pointer("/source/kind").and_then(Value::as_str) == Some("still"))
        .collect();
    assert_eq!(found.len(), 1, "expected exactly one still in {value}");
    int(found[0], "/source/at")
}

fn placement(value: &Value, clip: u64) -> (i64, i64) {
    let found = by_id(value, "/clips", clip);
    (int(found, "/start"), int(found, "/duration"))
}

/// A project the FFI's reader refuses with `sentence`, built against the
/// library directly instead, so the readings below can still be pinned
/// (the precedent is `evaluate_tests.rs`'s absent-media slate).
fn refused_then_built(value: &Value, sentence: &str) -> Project {
    assert_eq!(
        Handle::try_from_value(value).err().as_deref(),
        Some(sentence)
    );
    serde_json::from_value(value.clone()).expect("the JSON itself is well formed")
}

/// The project an op applied, as the value its file would hold.
fn applied(answer: Result<Outcome, String>) -> Value {
    match answer {
        Ok(Outcome::Applied(next)) => serde_json::to_value(&next).expect("a project serializes"),
        other => panic!("this op was expected to apply, got {other:?}"),
    }
}

// ---- (a) the six movers are ONE equation ---------------------------------

#[test]
fn every_mover_advances_the_in_point_by_the_same_rounded_product() {
    // One frame of timeline forward, six ways, from one fixture. Every
    // answer is 1 000 000 + round(20 000 × 1.00003) = 1 000 000 + 20 001.
    let base = cut();
    let moved = 1_000_000 + ODD_FRAME_IN_SOURCE;
    let to = 400_000 + FRAME_30;

    // 1. `trim_start` — the front edge moves forward a frame and the frame
    //    under it does not move.
    let after = base.apply(&json!({"op": "trim_start", "clip": 11, "to": to}));
    assert_eq!(source_in(&after.value(), 11), moved, "trim_start");

    // 2. `roll` — the same, with the predecessor growing by what this clip
    //    loses.
    let after = base.apply(&json!({"op": "roll", "clip": 11, "to": to}));
    let value = after.value();
    assert_eq!(source_in(&value, 11), moved, "roll");
    assert_eq!(placement(&value, 10), (0, to), "roll grows the predecessor");

    // 3. `split` — the SECOND half starts a frame into the source.
    let after = base.apply(&json!({"op": "split", "clips": [11], "at": to}));
    assert_eq!(source_in(&after.value(), MINTED), moved, "split");

    // 4. `freeze_frame` — the still holds the frame the playhead is on.
    let after = base.apply(&json!({"op": "freeze_frame", "clip": 11, "at": to}));
    assert_eq!(still_at(&after.value()), moved, "freeze_frame");

    // 5. `slip` — nothing moves on the timeline and the film slides by the
    //    same amount.
    let after = base.apply(&json!({"op": "slip", "clip": 11, "delta": FRAME_30}));
    assert_eq!(source_in(&after.value(), 11), moved, "slip");

    // 6. `add_transition` with the sign FLIPPED: one frame of overlap taken
    //    entirely from the incoming clip's head walks the in point BACK by
    //    the same 20 001, and the outgoing clip keeps its length.
    let after = base.apply(&json!({
        "op": "add_transition", "clip": 11, "duration": FRAME_30, "align": "before"
    }));
    let value = after.value();
    assert_eq!(
        source_in(&value, 11),
        1_000_000 - ODD_FRAME_IN_SOURCE,
        "add_transition"
    );
    assert_eq!(
        placement(&value, 11),
        (400_000 - FRAME_30, 21 * FRAME_30),
        "the incoming clip grew at the front by exactly one frame"
    );
    assert_eq!(
        placement(&value, 10),
        (0, 20 * FRAME_30),
        "`before` leaves the outgoing clip's last frame where it was"
    );
}

// ---- (b) the head is TIMELINE ticks ---------------------------------------

#[test]
fn the_head_is_timeline_ticks_so_a_far_left_trim_lands_at_start_minus_in_over_speed() {
    // Clip 20 runs at ×2 with 120 000 ticks of source in front of it, so
    // the head is 120 000 / 2 = 60 000 TIMELINE ticks — three 30 fps
    // frames, not the twelve that multiplying would give. Dragged to the
    // far left it stops at 200 000 − 60 000 = 140 000, with its in point
    // at exactly 0: the file's first frame, and no further.
    let handle = Handle::from_value(&project(
        [30, 1],
        6 * SEC,
        vec![clip(20, 5, 200_000, 10 * FRAME_30, 120_000, 2.0)],
    ));
    let value = handle
        .apply(&json!({"op": "trim_start", "clip": 20, "to": -10 * SEC}))
        .value();
    assert_eq!(
        placement(&value, 20),
        (140_000, 260_000),
        "the head clamp is 200 000 − 120 000/2, and the clip keeps its end at 400 000"
    );
    assert_eq!(
        source_in(&value, 20),
        0,
        "the front edge landed on the file's first frame"
    );
}

// ---- (c) the length is TIMELINE ticks, and THE bound is on the grid ------

/// A media of 1 100 000 ticks: at ×2 the remaining length is 550 000
/// timeline ticks, which is 27.5 frames at 30 fps and 13.75 at 15 fps — so
/// the NEAREST snap (28 frames, 14 frames) is past the end of the file on
/// both grids and only a DOWN snap is inside it (spec §11, #22).
const OVERHANG: i64 = 1_100_000;

#[test]
fn the_length_is_timeline_ticks_and_a_far_right_trim_stops_on_a_whole_frame() {
    let handle = Handle::from_value(&project(
        [30, 1],
        OVERHANG,
        vec![clip(30, 5, 0, 10 * FRAME_30, 0, 2.0)],
    ));
    let value = handle
        .apply(&json!({"op": "trim_end", "clip": 30, "to": 100 * SEC}))
        .value();
    let (_, duration) = placement(&value, 30);
    assert_eq!(
        duration,
        27 * FRAME_30,
        "540 000: the floored 550 000 snapped DOWN, where 550 000 itself is 27.5 frames"
    );
    assert_eq!(duration % FRAME_30, 0, "and it is a whole 30 fps frame");
    assert!(
        duration * 2 <= OVERHANG,
        "{duration} ticks at ×2 consumes {} of a file that holds {OVERHANG}",
        duration * 2
    );
}

#[test]
fn a_coarser_grid_holds_the_clip_to_the_bound_snapped_down_to_the_new_frame() {
    // The same clip, already 540 000 long, re-snapped to 15 fps. 540 000 is
    // 13.5 frames there, so the nearest snap is 14 frames — 560 000 — and
    // the bound is 550 000 / 40 000 = 13.75 frames snapped DOWN to 13, or
    // 520 000. The clip lands on the BOUND, not on the un-snapped 550 000.
    let handle = Handle::from_value(&project(
        [30, 1],
        OVERHANG,
        vec![clip(30, 5, 0, 27 * FRAME_30, 0, 2.0)],
    ));
    let value = handle
        .apply(&json!({"op": "set_canvas", "fps": [15, 1]}))
        .value();
    let (_, duration) = placement(&value, 30);
    assert_eq!(
        duration,
        13 * FRAME_15,
        "520 000, the bound on the new grid"
    );
    assert_eq!(duration % FRAME_15, 0, "and it is a whole 15 fps frame");
    assert!(
        duration * 2 <= OVERHANG,
        "{duration} ticks at ×2 consumes {} of a file that holds {OVERHANG}",
        duration * 2
    );
}

// ---- (d) the content length is SOURCE ticks ------------------------------

#[test]
fn the_window_slipped_to_its_tail_stop_ends_exactly_at_the_end_of_the_file() {
    // Clip 30 is 200 000 ticks of timeline at ×2, which is 400 000 ticks of
    // SOURCE — not 200 000 and not 100 000. Slipped as far right as it will
    // go, its in point stops at 1 100 000 − 400 000 = 700 000, and the plan
    // then asks for 400 000 ticks from there: the two measurements meet
    // exactly at the end of the file.
    let handle = Handle::from_value(&project(
        [30, 1],
        OVERHANG,
        vec![clip(30, 5, 0, 10 * FRAME_30, 0, 2.0)],
    ));
    let slipped = handle.apply(&json!({"op": "slip", "clip": 30, "delta": 100 * SEC}));
    let landed = source_in(&slipped.value(), 30);
    assert_eq!(landed, 700_000, "the window's last legal in point");

    let plan = slipped.plan();
    for group in ["video_tracks", "audio_tracks"] {
        let segment = segment_of(&plan, group, 30);
        assert_eq!(int(&segment, "/source_in"), landed, "{group} source_in");
        assert_eq!(
            int(&segment, "/source_duration"),
            400_000,
            "{group} plays 200 000 ticks of timeline as 400 000 of source"
        );
        assert_eq!(
            landed + int(&segment, "/source_duration"),
            OVERHANG,
            "{group}: the window ends exactly where the file does"
        );
    }
}

// ---- (e) D4-1: one content length, and the plan obeys it -----------------

#[test]
fn a_sub_tick_speed_is_refused_and_its_content_length_falls_back_to_one_to_one() {
    // Spec §11's D4-1. 200 000 ticks at ×0.000001 is 0.2 ticks of source —
    // under one tick, reachable by no file since R6-10's amendment (#41):
    // the reader refuses the speed, and every op holds one in ×0.1 – ×1000.
    // So the project is built against the library directly, and the ONE
    // content length still answers the 1:1 fallback, 200 000, and the plan
    // reads that function rather than its own copy, which answered 1.
    let project = refused_then_built(
        &project(
            [30, 1],
            OVERHANG,
            vec![clip(40, 5, 0, 10 * FRAME_30, 0, 1e-6)],
        ),
        "clip 40's speed 1e-6 is outside ×0.1–×1000",
    );
    let plan = project.composition_plan();
    for group in ["video_tracks", "audio_tracks"] {
        assert_eq!(
            int(&segment_of(&plan, group, 40), "/source_duration"),
            200_000,
            "{group}: the plan's source_duration is the 1:1 fallback, not 1"
        );
    }

    // And the three ops that read the same function agree with it: at ×1
    // the clip is exactly as long as the source it was already showing.
    let value = applied(project.apply(r#"{"op":"set_speed","clip":40,"rate":1.0}"#));
    assert_eq!(
        placement(&value, 40),
        (0, 10 * FRAME_30),
        "set_speed to ×1 leaves the ten frames where they were"
    );
}

// ---- (f) an UNMEASURED window, read both ways ----------------------------

#[test]
fn an_unmeasured_window_is_refused_and_read_empty_at_the_head_and_unbounded_at_the_tail() {
    // A media clip at speed 0, reachable by no file since R6-10's amendment
    // (#41): the window is there, the arithmetic is not. The two readings
    // are named at the call sites, and they are opposite; they are pinned
    // here at the `SourceBound` level, since every edit's `finish` now
    // refuses a result that still carries the speed.
    let project = refused_then_built(
        &project(
            [30, 1],
            OVERHANG,
            vec![clip(50, 5, 200_000, 10 * FRAME_30, 0, 0.0)],
        ),
        "clip 50's speed 0.0 is outside ×0.1–×1000",
    );
    let clip = project.clip(50).expect("clip 50 is in the fixture");

    // EMPTY at the head: the front edge may not move left at all, so a drag
    // to the far left is a valid op that changes nothing.
    match project.apply(r#"{"op":"trim_start","clip":50,"to":0}"#) {
        Ok(Outcome::Identity) => {}
        other => panic!("trim_start on an unmeasured head should be an identity, got {other:?}"),
    }
    assert_eq!(
        project.source_head_on_timeline(clip),
        SourceBound::Unmeasured
    );
    assert_eq!(project.source_head_on_timeline(clip).or_empty(), Some(0));

    // UNBOUNDED at the tail: no clamp is applied at all — and the edit that
    // would carry the speed into a new project is refused by `finish`.
    assert_eq!(
        project.apply(r#"{"op":"trim_end","clip":50,"to":3200000}"#),
        Err("clip 50's speed 0.0 is outside ×0.1–×1000".to_string())
    );
    assert_eq!(
        project.longest_duration_on_grid(clip),
        SourceBound::Unmeasured
    );
    assert_eq!(project.longest_duration_on_grid(clip).or_unbounded(), None);
}

#[test]
fn an_unmeasured_window_is_refused_and_gives_a_transition_no_tail() {
    // Clip 60 is the outgoing clip and its speed is 0, reachable by no file
    // since R6-10's amendment (#41), so its tail handle is EMPTY rather than
    // unbounded — the reading `add_transition` step 2 takes. The edit itself
    // is refused by `finish`, which still sees the speed.
    let project = refused_then_built(
        &project(
            [30, 1],
            OVERHANG,
            vec![
                clip(60, 6, 0, 10 * FRAME_30, 0, 0.0),
                clip(61, 6, 200_000, 20 * FRAME_30, 200_000, 1.0),
            ],
        ),
        "clip 60's speed 0.0 is outside ×0.1–×1000",
    );
    assert_eq!(
        project.apply(&format!(
            r#"{{"op":"add_transition","clip":61,"duration":{}}}"#,
            2 * FRAME_30
        )),
        Err("clip 60's speed 0.0 is outside ×0.1–×1000".to_string())
    );
    let outgoing = project.clip(60).expect("clip 60 is in the fixture");
    assert_eq!(
        project.longest_duration_on_grid(outgoing).or_empty(),
        Some(0),
        "an unmeasured window has no tail"
    );
}

/// `MINTED_SECOND` is here so the fixture's id budget is stated once: a
/// `freeze_frame` mints the split half and then the still, which is the
/// only op above that mints two.
#[test]
fn a_freeze_mints_the_split_half_before_the_still() {
    let value = cut()
        .apply(&json!({"op": "freeze_frame", "clip": 11, "at": 400_000 + FRAME_30}))
        .value();
    assert_eq!(
        int(by_id(&value, "/clips", MINTED_SECOND), "/source/at"),
        1_000_000 + ODD_FRAME_IN_SOURCE,
        "the still is the SECOND id the freeze minted"
    );
    assert_eq!(
        source_in(&value, MINTED),
        1_000_000 + ODD_FRAME_IN_SOURCE,
        "and the split half it cut is the first, moved by the same equation"
    );
}
