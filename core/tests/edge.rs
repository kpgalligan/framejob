//! Slip and roll, through the FFI — the two edge moves of spec §6.
//!
//! Both are defined by what they DON'T change, so most of what is asserted
//! here is an absence: a slip leaves the clip's start and duration exactly
//! where they were, and a roll leaves the pair's outer edges and its total
//! length exactly where they were. The identity tests are the strongest
//! form of that — a slip is its own inverse, and so is a roll — and they
//! compare whole documents rather than the fields the op was expected to
//! touch, which is the only way to catch an op that moved something nobody
//! thought to look at.

use serde_json::{json, Value};

mod common;
use common::{array, assert_contains, at, by_id, flag, int, source_in, text, Handle};

/// One frame at 30 fps, written out rather than imported so a change to
/// `time::TIMESCALE` fails these tests instead of moving with them.
const FRAME: i64 = 20_000;

// ---- fixtures ------------------------------------------------------------

/// Every case the two ops have to clamp or refuse, one per track.
///
/// Ids are one space across media, tracks and clips (spec §5.2), so the
/// tracks start at 3.
///
/// - Track 3: clips 10 (5 s – 15 s) and 11 (15 s – 20 s) meet at a HARD CUT
///   at 15 s, with source to spare on both sides — the roll that works.
///   Clip 11 is REVERSED, which changes none of the arithmetic (`in` is
///   measured in the reversed stream, spec §6) but is a fact about the clip
///   that neither op may quietly drop.
/// - Track 4: clip 12's window is already pressed against the end of a
///   five-second media, and clip 13 runs at double speed.
/// - Track 5: a still (14) and a text clip (15) meeting at a hard cut. Both
///   are SOURCELESS — a still has an instant and no window, text has
///   neither — so the cut between them is bounded by nothing but the frame
///   minimums.
/// - Track 6: clips 16 and 17 OVERLAP, which is a transition and not a cut.
/// - Track 7: clips 18 (whole of a five-second media) and 19 (one second of
///   source in front of it) meet at a hard cut where only one side has
///   anything left to give.
/// - Track 8: clips 20 and 21 with a GAP between them — the roll that has no
///   cut to move.
/// - Track 9: clips 22 and 23 at ×2, so every conversion `roll` makes by the
///   clip's speed is exercised where multiplying and dividing differ from
///   the identity. Clip 22 shows the SHORT media, so its remaining source
///   runs out first.
fn edge_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 2,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 2, "path": "/m/short.mov", "kind": "video", "duration": 3000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": false}
  ],
  "tracks": [
    {"id": 3, "name": "Cut"},
    {"id": 4, "name": "Windows"},
    {"id": 5, "name": "Sourceless"},
    {"id": 6, "name": "Overlap"},
    {"id": 7, "name": "Tight"},
    {"id": 8, "name": "Apart"},
    {"id": 9, "name": "Fast"}
  ],
  "clips": [
    {"id": 10, "track": 3, "start": 3000000, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 1200000}, "video": {}, "audio": {}},
    {"id": 11, "track": 3, "start": 9000000, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 12000000, "reversed": true},
     "video": {}, "audio": {}},
    {"id": 12, "track": 4, "start": 0, "duration": 600000,
     "source": {"kind": "media", "media": 2, "in": 2400000}, "video": {}},
    {"id": 13, "track": 4, "start": 1800000, "duration": 1200000, "speed": 2.0,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 14, "track": 5, "start": 0, "duration": 1200000,
     "source": {"kind": "still", "media": 1, "at": 6000000}, "video": {}},
    {"id": 15, "track": 5, "start": 1200000, "duration": 1200000,
     "source": {"kind": "text"}, "video": {}, "text": {"content": "Hello"}},
    {"id": 16, "track": 6, "start": 0, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 17, "track": 6, "start": 2400000, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {},
     "transition_in": {"kind": "cross_dissolve"}},
    {"id": 18, "track": 7, "start": 0, "duration": 3000000,
     "source": {"kind": "media", "media": 2, "in": 0}, "video": {}},
    {"id": 19, "track": 7, "start": 3000000, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 600000}, "video": {}, "audio": {}},
    {"id": 20, "track": 8, "start": 0, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 21, "track": 8, "start": 2400000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 22, "track": 9, "start": 0, "duration": 1200000, "speed": 2.0,
     "source": {"kind": "media", "media": 2, "in": 0}, "video": {}},
    {"id": 23, "track": 9, "start": 1200000, "duration": 1200000, "speed": 2.0,
     "source": {"kind": "media", "media": 1, "in": 4800000}, "video": {}, "audio": {}}
  ],
  "markers": [],
  "next_id": 30
}"#,
    )
}

/// One frame at 30000/1001 — 600 000 × 1001 / 30000 exactly, so the grid is
/// still uniform, just not the round one.
const DROP_FRAME: i64 = 20_020;

/// A hard cut on a 30000/1001 canvas whose source bound falls BETWEEN two
/// frames: clip 11 starts 300 000 source ticks in, so `roll`'s lower clamp
/// is 701 000, and 701 000 is not a multiple of 20 020.
fn drop_frame_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 2,
  "canvas": {"width": 1920, "height": 1080, "fps": [30000, 1001],
             "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30000, 1001], "has_video": true, "has_audio": true},
    {"id": 2, "path": "/m/short.mov", "kind": "video", "duration": 1500000,
     "width": 1920, "height": 1080, "fps": [30000, 1001], "has_video": true, "has_audio": false}
  ],
  "tracks": [{"id": 3, "name": "Cut"}],
  "clips": [
    {"id": 10, "track": 3, "start": 0, "duration": 1001000,
     "source": {"kind": "media", "media": 2, "in": 0}, "video": {}},
    {"id": 11, "track": 3, "start": 1001000, "duration": 1001000,
     "source": {"kind": "media", "media": 1, "in": 300000}, "video": {}, "audio": {}}
  ],
  "markers": [],
  "next_id": 30
}"#,
    )
}

// ---- reading -------------------------------------------------------------

fn placement(project: &Value, clip: u64) -> (i64, i64) {
    let found = by_id(project, "/clips", clip);
    (int(found, "/start"), int(found, "/duration"))
}

fn source_at(project: &Value, clip: u64) -> i64 {
    int(by_id(project, "/clips", clip), "/source/at")
}

fn reversed(project: &Value, clip: u64) -> bool {
    flag(by_id(project, "/clips", clip), "/source/reversed")
}

// ---- slip ----------------------------------------------------------------

#[test]
fn slip_moves_the_window_and_leaves_the_clip_where_it_is() {
    let project = edge_project();
    // Clip 10 sits at 5 s – 15 s showing source from 2 s. A positive delta
    // shows LATER material: the film moves forward under a fixed window.
    let later = project
        .apply(&json!({"op": "slip", "clip": 10, "delta": 1200000}))
        .value();
    assert_eq!(placement(&later, 10), (3_000_000, 6_000_000), "unmoved");
    assert_eq!(source_in(&later, 10), 1_200_000 + 1_200_000);

    let earlier = project
        .apply(&json!({"op": "slip", "clip": 10, "delta": -1200000}))
        .value();
    assert_eq!(placement(&earlier, 10), (3_000_000, 6_000_000), "unmoved");
    assert_eq!(source_in(&earlier, 10), 0);

    // Nothing else in the document moved either.
    assert_eq!(placement(&later, 11), (9_000_000, 3_000_000));
    assert_eq!(source_in(&later, 11), 12_000_000);

    // And a reversed clip slips like any other, keeping the flag: `in` is
    // measured in the stream the clip PLAYS (spec §6), so the arithmetic is
    // the same one and the fact about the clip survives it.
    let backwards = project
        .apply(&json!({"op": "slip", "clip": 11, "delta": 600000}))
        .value();
    assert_eq!(source_in(&backwards, 11), 12_000_000 + 600_000);
    assert!(
        reversed(&backwards, 11),
        "a slip does not un-reverse a clip"
    );
}

#[test]
fn slip_by_a_delta_and_back_is_the_identity() {
    let project = edge_project();
    let before = project.to_json();
    // Its own inverse, so no oracle is needed: the document that comes back
    // must be the one that went in, byte for byte.
    for delta in [FRAME, 600_000, 4_200_000] {
        let there = project.apply(&json!({"op": "slip", "clip": 10, "delta": delta}));
        let back = there.apply(&json!({"op": "slip", "clip": 10, "delta": -delta}));
        assert_eq!(
            back.to_json(),
            before,
            "slip by {delta} and back was not the identity"
        );
    }
}

#[test]
fn slip_scales_the_delta_by_the_clip_speed() {
    let project = edge_project();
    // Clip 13 plays at ×2, so one second of TIMELINE travel is two seconds
    // of source — the same conversion `trim_start` makes.
    let after = project
        .apply(&json!({"op": "slip", "clip": 13, "delta": 600000}))
        .value();
    assert_eq!(source_in(&after, 13), 1_200_000);
    assert_eq!(placement(&after, 13), (1_800_000, 1_200_000), "unmoved");
}

#[test]
fn slip_clamps_inside_the_media_and_refuses_when_there_is_no_room() {
    let project = edge_project();
    // Clip 10 shows 10 s of a 60 s media, so the last legal in point is
    // 60 s − 10 s. A slip past it stops there rather than running off.
    let tail = project
        .apply(&json!({"op": "slip", "clip": 10, "delta": 36000000}))
        .value();
    assert_eq!(source_in(&tail, 10), 36_000_000 - 6_000_000);
    let head = project
        .apply(&json!({"op": "slip", "clip": 10, "delta": -36000000}))
        .value();
    assert_eq!(source_in(&head, 10), 0);

    // Clip 12 is already at the tail of its five-second media (4 s in, 1 s
    // long): forward has nowhere to go, backward does.
    project.refuses(&json!({"op": "slip", "clip": 12, "delta": 600000}));
    let back = project
        .apply(&json!({"op": "slip", "clip": 12, "delta": -600000}))
        .value();
    assert_eq!(source_in(&back, 12), 1_800_000);

    // Clip 13 is already at the head.
    project.refuses(&json!({"op": "slip", "clip": 13, "delta": -600000}));
    // And a delta of nothing is nothing.
    project.refuses(&json!({"op": "slip", "clip": 10, "delta": 0}));
}

#[test]
fn a_still_slips_the_frame_it_holds() {
    let project = edge_project();
    // A still has one source TIME rather than a window, and slipping it is
    // what choosing a different frozen frame means.
    let after = project
        .apply(&json!({"op": "slip", "clip": 14, "delta": 1200000}))
        .value();
    assert_eq!(source_at(&after, 14), 6_000_000 + 1_200_000);
    assert_eq!(placement(&after, 14), (0, 1_200_000), "unmoved");

    // Clamped a frame short of the media's end, as `freeze_frame` clamps.
    let tail = project
        .apply(&json!({"op": "slip", "clip": 14, "delta": 36000000}))
        .value();
    assert_eq!(source_at(&tail, 14), 36_000_000 - FRAME);
}

#[test]
fn slip_on_a_clip_with_no_source_is_an_error() {
    let project = edge_project();
    // The non-media rule: a text clip named for a source op is an invalid
    // argument, the same class as an unknown id — not a refusal.
    assert_contains(
        &project.errors(&json!({"op": "slip", "clip": 15, "delta": 600000})),
        "clip 15 is not a media clip",
    );
    assert_contains(
        &project.errors(&json!({"op": "slip", "clip": 999, "delta": 600000})),
        "no clip with id 999",
    );
}

// ---- roll ----------------------------------------------------------------

#[test]
fn roll_moves_the_cut_and_keeps_everything_else() {
    let project = edge_project();
    let before = project.value();
    let outer = (
        int(by_id(&before, "/clips", 10), "/start"),
        int(by_id(&before, "/clips", 11), "/start")
            + int(by_id(&before, "/clips", 11), "/duration"),
    );

    // Earlier: clip 10 gives up a second, clip 11 takes it and its in point
    // follows back by the same second (front-trim semantics).
    let after = project
        .apply(&json!({"op": "roll", "clip": 11, "to": 8400000}))
        .value();
    assert_eq!(placement(&after, 10), (3_000_000, 5_400_000));
    assert_eq!(placement(&after, 11), (8_400_000, 3_600_000));
    assert_eq!(source_in(&after, 11), 12_000_000 - 600_000);
    assert_eq!(source_in(&after, 10), 1_200_000, "an end trim keeps its in");
    assert!(reversed(&after, 11), "a roll does not un-reverse a clip");
    assert_eq!(
        (
            int(by_id(&after, "/clips", 10), "/start"),
            int(by_id(&after, "/clips", 11), "/start")
                + int(by_id(&after, "/clips", 11), "/duration")
        ),
        outer,
        "the pair's outer edges do not move"
    );

    // And later, the same in reverse.
    let later = project
        .apply(&json!({"op": "roll", "clip": 11, "to": 10200000}))
        .value();
    assert_eq!(placement(&later, 10), (3_000_000, 7_200_000));
    assert_eq!(placement(&later, 11), (10_200_000, 1_800_000));
    assert_eq!(source_in(&later, 11), 12_000_000 + 1_200_000);

    // No other track was touched.
    assert_eq!(
        array(&after, "/clips").len(),
        array(&before, "/clips").len()
    );
    for id in [12u64, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23] {
        assert_eq!(
            by_id(&after, "/clips", id),
            by_id(&before, "/clips", id),
            "clip {id} moved"
        );
    }
}

#[test]
fn roll_there_and_back_is_the_identity() {
    let project = edge_project();
    let before = project.to_json();
    for to in [8_400_000, 10_200_000, 9_000_000 + FRAME] {
        let there = project.apply(&json!({"op": "roll", "clip": 11, "to": to}));
        let back = there.apply(&json!({"op": "roll", "clip": 11, "to": 9000000}));
        assert_eq!(
            back.to_json(),
            before,
            "roll to {to} and back was not the identity"
        );
    }
}

#[test]
fn roll_clamps_to_one_frame_on_each_side() {
    let project = edge_project();
    // Dragged to the start of the timeline, the cut stops one frame into
    // the predecessor rather than deleting it.
    let early = project
        .apply(&json!({"op": "roll", "clip": 11, "to": 0}))
        .value();
    assert_eq!(placement(&early, 10), (3_000_000, FRAME));
    assert_eq!(
        placement(&early, 11),
        (3_000_000 + FRAME, 12_000_000 - 3_000_000 - FRAME)
    );
    assert_eq!(
        source_in(&early, 11),
        12_000_000 - (9_000_000 - 3_000_000 - FRAME)
    );

    // And dragged past the end, one frame short of this clip's own end.
    let late = project
        .apply(&json!({"op": "roll", "clip": 11, "to": 100000000}))
        .value();
    assert_eq!(placement(&late, 11), (12_000_000 - FRAME, FRAME));
    assert_eq!(
        placement(&late, 10),
        (3_000_000, 12_000_000 - FRAME - 3_000_000)
    );
}

#[test]
fn roll_clamps_to_the_source_available_on_each_side() {
    let project = edge_project();
    // Track 7: clip 18 shows the WHOLE of a five-second media, so it has
    // nothing left to grow into; clip 19 has one second of source in front
    // of it, so the cut can only move earlier, and only by that second.
    let earlier = project
        .apply(&json!({"op": "roll", "clip": 19, "to": 2400000}))
        .value();
    assert_eq!(placement(&earlier, 18), (0, 2_400_000));
    assert_eq!(placement(&earlier, 19), (2_400_000, 3_600_000));
    assert_eq!(source_in(&earlier, 19), 0, "the source head is exhausted");

    // Asked for more than that, it stops where the source does.
    let clamped = project
        .apply(&json!({"op": "roll", "clip": 19, "to": 1200000}))
        .value();
    assert_eq!(placement(&clamped, 18), (0, 2_400_000));
    assert_eq!(source_in(&clamped, 19), 0);

    // The other way there is nothing at all: clip 18's media is spent, so
    // the clamp lands back on the cut and the op changes nothing.
    project.refuses(&json!({"op": "roll", "clip": 19, "to": 4800000}));
}

#[test]
fn roll_needs_a_hard_cut_and_refuses_without_one() {
    let project = edge_project();
    // A gap: nothing ends exactly where clip 21 begins.
    project.refuses(&json!({"op": "roll", "clip": 21, "to": 1800000}));
    // An overlap: that is a transition, and its length belongs to
    // `set_transition_duration`.
    project.refuses(&json!({"op": "roll", "clip": 17, "to": 1800000}));
    // The first clip on a track has no predecessor at all.
    project.refuses(&json!({"op": "roll", "clip": 10, "to": 2400000}));
    // And a roll to where the cut already is changes nothing.
    project.refuses(&json!({"op": "roll", "clip": 11, "to": 9000000}));

    assert_contains(
        &project.errors(&json!({"op": "roll", "clip": 999, "to": 600000})),
        "no clip with id 999",
    );
}

#[test]
fn roll_converts_by_the_clips_own_speed_on_both_sides() {
    let project = edge_project();
    // Track 9 runs at ×2. Clip 23 begins 8 s into its media (in 4 800 000)
    // and the cut is at 2 s, so moving the cut one second earlier must move
    // the in point TWO seconds — the same `delta × speed` a trim makes.
    let earlier = project
        .apply(&json!({"op": "roll", "clip": 23, "to": 600000}))
        .value();
    assert_eq!(placement(&earlier, 22), (0, 600_000));
    assert_eq!(placement(&earlier, 23), (600_000, 1_800_000));
    assert_eq!(source_in(&earlier, 23), 4_800_000 - 1_200_000);

    // The other side's clamp is a DIVISION by the speed: clip 22 shows a
    // five-second media at ×2, so it has 2.5 s of timeline left in it and
    // the cut can go no further than there — not the 4 s − 1 frame the
    // frame minimum alone would allow.
    let clamped = project
        .apply(&json!({"op": "roll", "clip": 23, "to": 2400000}))
        .value();
    assert_eq!(
        placement(&clamped, 22),
        (0, 1_500_000),
        "3 000 000 source / 2"
    );
    assert_eq!(placement(&clamped, 23), (1_500_000, 900_000));
    assert_eq!(source_in(&clamped, 23), 4_800_000 + 600_000);
}

#[test]
fn a_cut_between_two_sourceless_clips_rolls_freely() {
    let project = edge_project();
    // Clip 14 is a still and clip 15 is text: neither has a window, so
    // `source_head` and `source_length` both answer `None` and the only
    // bounds left are the frame minimums.
    let after = project
        .apply(&json!({"op": "roll", "clip": 15, "to": 600000}))
        .value();
    assert_eq!(placement(&after, 14), (0, 600_000));
    assert_eq!(placement(&after, 15), (600_000, 1_800_000));
    assert_eq!(
        source_at(&after, 14),
        6_000_000,
        "a still keeps its instant"
    );

    // And the clamps are the frame minimums alone, at both ends.
    let early = project
        .apply(&json!({"op": "roll", "clip": 15, "to": -100000}))
        .value();
    assert_eq!(placement(&early, 14), (0, FRAME));
    let late = project
        .apply(&json!({"op": "roll", "clip": 15, "to": 100000000}))
        .value();
    assert_eq!(placement(&late, 15), (2_400_000 - FRAME, FRAME));
}

#[test]
fn slip_on_a_clip_with_no_source_is_an_error_whatever_the_delta() {
    let project = edge_project();
    // The zero-delta short circuit must not run first: a delta that rounds
    // to nothing would otherwise turn an invalid ARGUMENT into "valid,
    // changes nothing", which is the one answer the non-media rule exists
    // to stop being given.
    for delta in [600_000, 0, 1] {
        assert_contains(
            &project.errors(&json!({"op": "slip", "clip": 15, "delta": delta})),
            "clip 15 is not a media clip",
        );
    }
}

#[test]
fn a_roll_lands_on_the_frame_grid_at_a_rate_that_does_not_divide_the_timescale() {
    let project = drop_frame_project();
    // 30000/1001 is 20 020 ticks a frame. Clip 11 begins 300 000 source
    // ticks in, so its head bound is 701 000 — a tick the grid does not
    // land on. The clamp has to snap INWARD, to the first frame at or after
    // it, or both clips end up with sub-frame times.
    let after = project
        .apply(&json!({"op": "roll", "clip": 11, "to": 0}))
        .value();
    let (start, duration) = placement(&after, 11);
    assert_eq!(
        start, 720_720,
        "the frame after the source head, not the head"
    );
    assert_eq!(start % DROP_FRAME, 0);
    assert_eq!(duration % DROP_FRAME, 0);
    assert_eq!(placement(&after, 10), (0, 720_720));
    assert_eq!(source_in(&after, 11), 300_000 - (1_001_000 - 720_720));

    // The upper clamp is the mirror: clip 10 shows a 1 500 000-tick media,
    // so the cut can reach 1 500 000 — which is between two frames, and the
    // bound must therefore round DOWN, to frame 74.
    let late = project
        .apply(&json!({"op": "roll", "clip": 11, "to": 100000000}))
        .value();
    let (start, duration) = placement(&late, 11);
    assert_eq!(start, 74 * DROP_FRAME, "the frame before the source tail");
    assert_eq!(duration % DROP_FRAME, 0);
    assert_eq!(placement(&late, 10), (0, 74 * DROP_FRAME));
}

#[test]
fn a_roll_leaves_the_pair_meeting_with_no_transition() {
    let project = edge_project();
    // The two edges move together, so the clips still abut exactly: no
    // overlap is created and neither clip gains a default dissolve.
    let after = project
        .apply(&json!({"op": "roll", "clip": 11, "to": 8400000}))
        .value();
    let clip = by_id(&after, "/clips", 11);
    assert!(
        at(clip, "/transition_in").is_null(),
        "a roll invented a transition: {clip}"
    );
    // While the overlapping pair that already had one keeps it.
    assert_eq!(
        text(by_id(&after, "/clips", 17), "/transition_in/kind"),
        "cross_dissolve"
    );
}
