//! `add_transition`'s edges, through the FFI — the rows road map 5's E1
//! reader review (§12) added, in a file of their own because
//! `add_transition.rs` is over the size cap and takes nothing on.
//!
//! Four things are asserted here that the shipped suite never reached:
//!
//! - **The written positions land on the FRAME GRID at a canvas rate that
//!   does not divide the timescale.** `Project::frame` is a FALLBACK of
//!   1/30 s there (`time::frame_duration` answers `None` unless
//!   `600 000 × den / num` is whole), and `add_transition` is the only op
//!   in the crate that MULTIPLIES by it to make a position.
//! - **A handle says what the SOURCE holds, not what the timeline in front
//!   of the incoming clip has.** A request longer than that ran the clip's
//!   start past tick 0, which reordered the trial pair, passed the overlap
//!   rule against the wrong neighbours and came back as an `Err` about the
//!   crate's own state — or, on a SHORT pair, passed it with both starts
//!   non-negative and wrote the two clips OUT OF ORDER.
//! - **The step-down walks the CLIPS, not the caller's `duration`.** The
//!   ceiling is arithmetic, so the row below is a wall-clock bound — see
//!   its own comment for the three numbers it was sized from.
//! - **Every source kind, and a reversed clip.** §3i asked for "a reversed
//!   clip's handle in the reversed stream" and nothing tested it; an
//!   image, a shape and a speed at which the HANDLE is what clamps had no
//!   row either.

use serde_json::{json, Value};
use std::time::Instant;

mod common;
use common::{by_id, int, Handle, Outcome};

/// One frame at 30 fps, written out rather than imported so a change to
/// `time::TIMESCALE` fails these tests instead of moving with them.
const FRAME: i64 = 20_000;

// ---- fixtures ------------------------------------------------------------

/// A hard cut at 6 s on a canvas running at **7 fps** — a rate whose frame
/// is 600 000 / 7 = 85 714.28… ticks, so `time::frame_duration` cannot
/// express it and `Project::frame` falls back to 20 000.
///
/// Every stored time here IS on the 7 fps grid (1 200 000 is frame 14,
/// 3 600 000 is frame 42), so anything off it afterwards was put there by
/// the op.
fn odd_rate() -> Handle {
    Handle::from_json(
        r#"{
  "version": 7,
  "canvas": {"width": 1920, "height": 1080, "fps": [7, 1], "background": [0, 0, 0, 1]},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [{"id": 50, "name": "Cut"}],
  "clips": [
    {"id": 10, "track": 50, "start": 1200000, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 11, "track": 50, "start": 3600000, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 12000000}, "video": {}, "audio": {}}
  ],
  "markers": [], "next_id": 60, "nests": []
}"#,
    )
}

/// A cut at 2 s where the incoming clip's HEAD is twenty seconds of source
/// and the timeline in front of it is two — plus one pair per source kind
/// the shipped fixture never covered.
///
/// - Track 50: clips 10 and 11, both media on file 1, clip 11 at `in`
///   12 000 000 so its handle offers twenty seconds where the timeline
///   offers six.
/// - Track 60: clips 70 and 71, both REVERSED, clip 71 at `in` 60 000 —
///   THREE frames of head. `in` is measured in the direction the clip plays
///   (`edit.rs`), so the handle arithmetic is the forward one, the frames
///   revealed are the reversed stream's, and the handle is what clamps.
/// - Track 61: clips 72 and 73, both IMAGES — sourceless, so unbounded.
/// - Track 62: clips 74 and 75, both SHAPES — the same.
/// - Track 63: clips 76 (at `in` 34 000 000 of a 36 000 000-tick file, ×2,
///   so its TAIL is empty) and 77 (at `in` 200 000, ×2, so its head is
///   exactly five frames of timeline). The pair where the handle, not the
///   request and not the overlap rule, is what clamps.
/// - Track 64: clips 78 (ONE frame) and 79 (seven). A pair this short is
///   where an unclamped request writes the two out of ORDER.
fn kinds() -> Handle {
    Handle::from_json(
        r#"{
  "version": 7,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1]},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 3, "path": "/m/pic.png", "kind": "image", "duration": 0,
     "width": 1920, "height": 1080, "has_video": true, "has_audio": false}
  ],
  "tracks": [
    {"id": 50, "name": "Head"}, {"id": 60, "name": "Rev"}, {"id": 61, "name": "Img"},
    {"id": 62, "name": "Shape"}, {"id": 63, "name": "Speed"}, {"id": 64, "name": "Tiny"}
  ],
  "clips": [
    {"id": 10, "track": 50, "start": 1200000, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 11, "track": 50, "start": 3600000, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 12000000}, "video": {}, "audio": {}},

    {"id": 70, "track": 60, "start": 0, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 3000000, "reversed": true},
     "video": {}, "audio": {}},
    {"id": 71, "track": 60, "start": 1200000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 60000, "reversed": true},
     "video": {}, "audio": {}},

    {"id": 72, "track": 61, "start": 0, "duration": 1200000,
     "source": {"kind": "image", "media": 3}, "video": {}},
    {"id": 73, "track": 61, "start": 1200000, "duration": 1200000,
     "source": {"kind": "image", "media": 3}, "video": {}},

    {"id": 74, "track": 62, "start": 0, "duration": 1200000,
     "source": {"kind": "shape"}, "video": {}, "shape": {}},
    {"id": 75, "track": 62, "start": 1200000, "duration": 1200000,
     "source": {"kind": "shape"}, "video": {}, "shape": {}},

    {"id": 76, "track": 63, "start": 0, "duration": 1200000, "speed": 2.0,
     "source": {"kind": "media", "media": 1, "in": 34000000}, "video": {}, "audio": {}},
    {"id": 77, "track": 63, "start": 1200000, "duration": 1200000, "speed": 2.0,
     "source": {"kind": "media", "media": 1, "in": 200000}, "video": {}, "audio": {}},

    {"id": 78, "track": 64, "start": 2000000, "duration": 20000,
     "source": {"kind": "media", "media": 1, "in": 10000000}, "video": {}, "audio": {}},
    {"id": 79, "track": 64, "start": 2020000, "duration": 140000,
     "source": {"kind": "media", "media": 1, "in": 20000000}, "video": {}, "audio": {}}
  ],
  "markers": [], "next_id": 90, "nests": []
}"#,
    )
}

/// A TEXT clip (tail UNBOUNDED) followed by a MEDIA clip at `in` 0 (head
/// EMPTY): `center`'s shortfall moves the WHOLE request to the text side,
/// so one unbounded side is all the step-down needs to be handed the
/// caller's number.
fn one_unbounded_side() -> Handle {
    Handle::from_json(
        r#"{
  "version": 7,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1]},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
  ],
  "tracks": [{"id": 50, "name": "T"}],
  "clips": [
    {"id": 10, "track": 50, "start": 0, "duration": 1200000,
     "source": {"kind": "text"}, "video": {}, "text": {"content": "A"}},
    {"id": 11, "track": 50, "start": 1200000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}}
  ],
  "markers": [], "next_id": 60, "nests": []
}"#,
    )
}

fn add(clip: u32, duration: i64) -> Value {
    json!({"op": "add_transition", "clip": clip, "duration": duration})
}

/// `(start, duration)` of a clip in a written project.
fn placement(project: &Value, id: u64) -> (i64, i64) {
    let clip = by_id(project, "/clips", id);
    (int(clip, "/start"), int(clip, "/duration"))
}

/// The clip's source `in`, or `None` for a source that has no window.
fn source_in(project: &Value, id: u64) -> Option<i64> {
    by_id(project, "/clips", id)
        .pointer("/source/in")
        .and_then(Value::as_i64)
}

/// Frame `t` falls on at 7 fps, as a float — a whole number exactly when
/// `t` is on the grid. `t × num / (TIMESCALE × den)`.
fn frame_at_7fps(t: i64) -> f64 {
    t as f64 * 7.0 / 600_000.0
}

// ---- the frame grid at a rate the timescale does not divide --------------

#[test]
fn at_a_rate_the_timescale_does_not_divide_both_clips_still_land_on_the_grid() {
    // Sixty-one FALLBACK frames (1 220 000 ticks): an odd count, so the
    // centred split is 31 on the incoming clip and 30 on the outgoing, and
    // 31 × 20 000 is not a multiple of the 7 fps frame. Taking the
    // extension as `count × frame` moved clip 11's start to 2 980 000 —
    // frame 34.77, a time `time.rs` says the model never holds.
    let after = odd_rate().apply(&add(11, 61 * FRAME)).value();

    for id in [10u64, 11] {
        let (start, duration) = placement(&after, id);
        for (what, t) in [("start", start), ("end", start + duration)] {
            let frame = frame_at_7fps(t);
            assert_eq!(
                frame,
                frame.round(),
                "clip {id}'s {what} is {t}, frame {frame} at 7 fps — not on the grid"
            );
        }
    }

    // …and the outer edges are still where they were, which is the op's
    // whole promise and the thing a snap must not quietly spend.
    assert_eq!(placement(&after, 10).0, 1_200_000);
    let (start, duration) = placement(&after, 11);
    assert_eq!(start + duration, 6_000_000);
}

#[test]
fn a_request_under_one_frame_of_the_real_grid_is_refused_rather_than_stored_flat() {
    // One fallback frame at 7 fps is a QUARTER of a real one. The op's own
    // posture for a request under a frame is a refusal naming the shortest
    // duration that passes (spec §11 #88), not a zero-length overlap.
    odd_rate().refuses_with(
        &add(11, FRAME),
        "a transition of 20000 ticks is too short to make at the cut before clip 11; \
         pass a duration of at least 85714 ticks",
    );
}

// ---- the handle is not the timeline --------------------------------------

#[test]
fn a_request_longer_than_the_timeline_in_front_of_the_clip_clamps_rather_than_erroring() {
    // Clip 11 starts at 3 600 000 and carries twenty seconds of head, so
    // its handle would happily move it to -3 600 000. There it sorts
    // BEFORE clip 10, the overlap rule measures that other pair, passes on
    // the first trial, and the op used to hand back
    // `Err("clip 11 has negative start -3600000")` — an error about the
    // crate's own state for a request that is merely too long.
    //
    // Step 3's ceiling is what closes it, and closes it completely: a
    // swapped pair passes the rule only at nine times that ceiling, so no
    // trial the loop can reach has a negative start. A second, explicit
    // clamp at tick 0 was written, found to have no input left that
    // reaches it, and deleted.
    let after = kinds().apply(&add(11, 720 * FRAME)).value();

    let (start, duration) = placement(&after, 11);
    assert!(start >= 0, "clip 11 starts at {start}");
    assert_eq!(start + duration, 6_000_000, "clip 11's end moved");
    // The answer a shorter request already gave: the overlap rule is what
    // binds here, not the head.
    assert_eq!((start, duration), (2_800_000, 3_200_000));
}

#[test]
fn requests_either_side_of_the_timelines_edge_agree_and_never_swap_the_pair() {
    // The clamp is at `later.start / frame` = 180 frames, and `center`
    // gives the incoming clip half the request, so 360 frames is the
    // request that first reaches tick 0. All three answer alike, which is
    // what "clamped rather than refused" means.
    let answers: Vec<(i64, i64)> = [358, 360, 362]
        .iter()
        .map(|frames| placement(&kinds().apply(&add(11, frames * FRAME)).value(), 11))
        .collect();
    assert_eq!(answers[0], answers[1]);
    assert_eq!(answers[1], answers[2]);
    assert!(answers[0].0 >= 0, "clip 11 starts at {}", answers[0].0);

    // A non-negative start is not the whole of it: on the SHORT pair (one
    // frame before seven) the swapped form passes the overlap rule without
    // going negative — with the ceiling reverted, 40 frames centred writes
    // `79@1620000+540000` BEFORE `78@2000000+420000`, a project `validate`
    // accepts. The ceiling is two frames here, so the order holds.
    let after = kinds().apply(&add(79, 40 * FRAME)).value();
    assert_eq!(placement(&after, 78), (2_000_000, 40_000));
    assert_eq!(placement(&after, 79), (2_020_000, 140_000));
}

// ---- the step-down walks the clips, not the request ----------------------

#[test]
fn a_huge_duration_is_answered_in_the_time_a_small_one_takes() {
    // The step-down removes ONE frame per pass, so before the ceiling in
    // step 3 the pass count followed the caller's `duration`: a measured
    // ladder on this fixture ran 3e4 passes in 0.010 s, 3e5 in 0.087 s,
    // 3e6 in 0.880 s and 3e7 in 8.608 s — 287 ns a pass, which puts the
    // 9.0e15 ticks the MCP argument gate allows at 4.5e11 passes and
    // ~36 hours.
    //
    // Fixed and unfixed give the SAME answer — the ceiling only removes
    // trials that were going to fail — so the assertion has to be the
    // clock. The three numbers it is sized from: this call takes under a
    // millisecond fixed, the bound `B` below is 1 s, and the same call
    // against a build without the ceiling takes ~17 s. The request is
    // SIZED, not extreme, so a revert fails this row in under a minute
    // instead of hanging `make test`.
    const B: f64 = 1.0;
    let project = one_unbounded_side();
    let request = 60_000_000 * FRAME;

    let started = Instant::now();
    let out = project.try_apply(&add(11, request));
    let elapsed = started.elapsed().as_secs_f64();

    assert!(
        matches!(out, Ok(Outcome::Applied(_))),
        "expected the request to be clamped and applied, got {out:?}"
    );
    assert!(
        elapsed < B,
        "add_transition took {elapsed:.3} s for a {request}-tick request \
         (bound {B} s): the step-down is following the REQUEST again"
    );
}

#[test]
fn a_huge_duration_lands_the_same_overlap_a_request_at_the_ceiling_does() {
    // A CONTROL, not a regression row: `split` is `requested.min(ceiling)`,
    // so every request at or above the ceiling is the same edit BY
    // CONSTRUCTION, and this row passes against the ceiling reverted too
    // (measured). What evidences "no answer MOVES" is §12's 18 144-case
    // differential sweep, not this row. Both requests are SIZED: 9.0e15
    // and `i64::MAX` ARE the loop reverted, so §12 records them instead.
    let ceiling = (1_200_000 + 1_200_000) / (3 * FRAME);
    let at_ceiling = placement(
        &one_unbounded_side()
            .apply(&add(11, ceiling * FRAME))
            .value(),
        10,
    );
    for request in [ceiling * FRAME + FRAME, 60_000_000 * FRAME] {
        let after = placement(&one_unbounded_side().apply(&add(11, request)).value(), 10);
        assert_eq!(after, at_ceiling, "request {request} landed differently");
    }
}

// ---- every source kind, and a reversed clip ------------------------------

#[test]
fn a_reversed_pair_takes_its_handle_out_of_the_reversed_stream() {
    // `in` is measured in the direction the clip plays (`edit.rs`,
    // `set_reversed`), so revealing frames in front of a reversed clip is
    // the SAME subtraction as for a forward one — and the frames it
    // reveals are the reversed stream's. Clip 71 holds THREE, so ten asked
    // for clamp to three there and `center`'s shortfall moves the other
    // seven to the tail: the HANDLE is what binds, which is what makes the
    // mutant "handles never clamp" fail this row.
    let after = kinds().apply(&add(71, 10 * FRAME)).value();
    assert_eq!(placement(&after, 70), (0, 1_200_000 + 7 * FRAME));
    assert_eq!(
        placement(&after, 71),
        (1_200_000 - 3 * FRAME, 1_200_000 + 3 * FRAME)
    );
    assert_eq!(source_in(&after, 71), Some(0));
    // …and the flag is still set: the op reads the window, never the
    // direction.
    let clip = by_id(&after, "/clips", 71);
    assert_eq!(clip.pointer("/source/reversed"), Some(&json!(true)));
}

#[test]
fn an_image_pair_and_a_shape_pair_are_bounded_by_nothing_but_the_overlap_rule() {
    // Neither kind has a source window, so both handles are UNBOUNDED and
    // the ten frames asked for land five and five — the same answer the
    // shipped fixture only ever measured on a `still` and a `text`.
    for (earlier, later) in [(72u64, 73u64), (74, 75)] {
        let after = kinds().apply(&add(later as u32, 10 * FRAME)).value();
        assert_eq!(
            placement(&after, earlier),
            (0, 1_200_000 + 5 * FRAME),
            "clip {earlier}"
        );
        assert_eq!(
            placement(&after, later),
            (1_200_000 - 5 * FRAME, 1_200_000 + 5 * FRAME),
            "clip {later}"
        );
        assert_eq!(source_in(&after, later), None, "clip {later} grew a window");
    }
}

#[test]
fn at_double_speed_the_handle_is_what_clamps_and_the_in_point_moves_by_the_speed() {
    // Clip 77 sits at `in` 200 000 and plays at ×2, so its head is five
    // frames of TIMELINE; clip 76 is 1 000 000 source ticks from the end
    // of the file and already shows 1 200 000 of timeline, so its tail is
    // empty. Ten frames asked for: five land, all on the incoming side,
    // and its `in` moves by 100 000 × 2 — not by 100 000, and not by
    // 100 000 / 2.
    let after = kinds().apply(&add(77, 10 * FRAME)).value();
    assert_eq!(placement(&after, 76), (0, 1_200_000));
    assert_eq!(
        placement(&after, 77),
        (1_200_000 - 5 * FRAME, 1_200_000 + 5 * FRAME)
    );
    assert_eq!(source_in(&after, 77), Some(0));
}
