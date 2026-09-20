//! `add_transition` and `set_transition_style`, through the FFI — road map
//! 5's E1, spec §6 and spec §11's R5-3.
//!
//! `add_transition` is defined as much by what it does NOT move as by what
//! it does: the two clips' OUTER edges stay, every other clip on the track
//! stays, the timeline's length stays, and the material the overlap is made
//! of comes out of handles the two clips already had. So most of what is
//! asserted here is an absence, and the strongest form of it is the whole
//! document compared after an undo.
//!
//! Three things the op does are easy to get subtly wrong and each has its
//! own test below:
//!
//! - **The split happens in FRAMES, after the snap.** Snapping two half
//!   extensions separately loses the odd frame — 1.5 + 1.5 frames snap to
//!   1 + 1 — so a three-frame centred request must land as two frames on
//!   the incoming clip and one on the outgoing.
//! - **The incoming clip's `in` moves by the timeline extension TIMES its
//!   speed**, which is the inverse of the division `source_head` already
//!   did. Applying speed twice is the bug the ×2 track exists to catch.
//! - **The incoming clip's ACTIONS move with its new first frame**, where
//!   `trim_start` deliberately leaves them alone. A screencast zoom is
//!   drawn over a source frame, and a transition reveals material in front
//!   of a first frame nobody asked to move.
//!
//! What `set_transition` does with a style, what the file defaults are and
//! where the keys sit in the written text are `schema_v7.rs`'s; the eased
//! progress and the crossfade ramps are `crossfade.rs`'s.

use serde_json::{json, Value};

mod common;
use common::{array, assert_contains, at, by_id, int, num, source_in, text, Handle};

/// One frame at 30 fps, written out rather than imported so a change to
/// `time::TIMESCALE` fails these tests instead of moving with them.
const FRAME: i64 = 20_000;
const SEC: i64 = 600_000;

// ---- fixtures ------------------------------------------------------------

/// A hard cut per track, each one a different thing for the op to clamp
/// against.
///
/// - Track 50: clips 10 (2 s – 6 s) and 11 (6 s – 10 s), both on media 1
///   with seconds of source on either side of the cut — the case that
///   works, and the one every `align` is measured on.
/// - Track 51: clips 12 and 13 meeting at 2 s, where clip 13 is at `in` 0 —
///   the incoming clip has NO head, so a centred request has to move its
///   whole share to the outgoing clip's tail.
/// - Track 52: clips 14 (a still) and 15 (text) at a hard cut — both
///   SOURCELESS, so neither side is bounded by anything but the frame grid
///   and the overlap rule.
/// - Track 53: clips 16 and 17 at ×2 speed, where the `in` conversion
///   multiplies rather than divides.
/// - Track 54: clips 18 and 19 with a GAP between them.
/// - Track 55: clips 20 and 21 OVERLAPPING already.
/// - Track 56: clips 22, 23 and 24 — a cut at 4 s with a THIRD clip
///   immediately after 23, so the neighbour clamp has something to bite on.
/// - Track 57: clip 25 alone, the first clip on its track.
/// - Track 58: clips 26 (media) and 27 (a NEST clip) at a hard cut, and the
///   nest is longer than the clip shows — so the nest has a tail and no
///   head.
/// - Track 59: clip 33 (a nest clip showing 2 400 000 of a 3 000 000-tick
///   nest, so its tail is 600 000 exactly) and clip 34 (long, at `in` 0, so
///   it has no head) — the pair on which the nest's own length is the
///   binding bound rather than the overlap rule.
fn cuts() -> Handle {
    Handle::from_json(
        r#"{
  "version": 7,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 2, "path": "/m/short.mov", "kind": "video", "duration": 3000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": false}
  ],
  "tracks": [
    {"id": 50, "name": "Cut"},
    {"id": 51, "name": "NoHead"},
    {"id": 52, "name": "Sourceless"},
    {"id": 53, "name": "Fast"},
    {"id": 54, "name": "Gap"},
    {"id": 55, "name": "Overlap"},
    {"id": 56, "name": "Neighbour"},
    {"id": 57, "name": "Alone"},
    {"id": 58, "name": "Nest"},
    {"id": 59, "name": "NestTail"}
  ],
  "clips": [
    {"id": 10, "track": 50, "start": 1200000, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 11, "track": 50, "start": 3600000, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 12000000}, "video": {}, "audio": {},
     "actions": [{"id": 28, "start": 600000, "duration": 600000,
                  "curve": "linear", "end": {"video": {"scale": 2.0}}}]},
    {"id": 12, "track": 51, "start": 0, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 13, "track": 51, "start": 1200000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 14, "track": 52, "start": 0, "duration": 1200000,
     "source": {"kind": "still", "media": 1, "at": 6000000}, "video": {}},
    {"id": 15, "track": 52, "start": 1200000, "duration": 1200000,
     "source": {"kind": "text"}, "video": {}, "text": {"content": "Hello"}},
    {"id": 16, "track": 53, "start": 0, "duration": 1200000, "speed": 2.0,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 17, "track": 53, "start": 1200000, "duration": 1200000, "speed": 2.0,
     "source": {"kind": "media", "media": 1, "in": 12000000}, "video": {}, "audio": {}},
    {"id": 18, "track": 54, "start": 0, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 19, "track": 54, "start": 2400000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 20, "track": 55, "start": 0, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 21, "track": 55, "start": 1800000, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {},
     "transition_in": {"kind": "cross_dissolve"}},
    {"id": 22, "track": 56, "start": 0, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 23, "track": 56, "start": 2400000, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 24, "track": 56, "start": 4800000, "duration": 2400000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 25, "track": 57, "start": 1200000, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 26, "track": 58, "start": 0, "duration": 1200000,
     "source": {"kind": "media", "media": 1, "in": 3000000}, "video": {}, "audio": {}},
    {"id": 27, "track": 58, "start": 1200000, "duration": 1200000,
     "source": {"kind": "nest", "project": 40}, "video": {}},
    {"id": 33, "track": 59, "start": 0, "duration": 2400000,
     "source": {"kind": "nest", "project": 40}, "video": {}},
    {"id": 34, "track": 59, "start": 2400000, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}}
  ],
  "markers": [],
  "next_id": 60,
  "nests": [
    {"id": 40, "name": "Nest 1", "width": 1920, "height": 1080,
     "tracks": [{"id": 41, "name": "Inside"}],
     "clips": [{"id": 42, "track": 41, "start": 0, "duration": 3000000,
                "source": {"kind": "media", "media": 1, "in": 0},
                "video": {}, "audio": {}}]}
  ]
}"#,
    )
}

fn add(clip: u32, duration: i64) -> Value {
    json!({"op": "add_transition", "clip": clip, "duration": duration})
}

fn add_aligned(clip: u32, duration: i64, align: &str) -> Value {
    json!({"op": "add_transition", "clip": clip, "duration": duration, "align": align})
}

/// `(start, duration)` of a clip in a written project.
fn placement(project: &Value, id: u64) -> (i64, i64) {
    let clip = by_id(project, "/clips", id);
    (int(clip, "/start"), int(clip, "/duration"))
}

// ---- the overlap it makes -------------------------------------------------

#[test]
fn a_centred_transition_takes_half_from_each_side() {
    // Twenty frames requested: ten come off the incoming clip's head and
    // ten off the outgoing clip's tail, so the cut that was at 3 600 000
    // becomes an overlap centred on it.
    let after = cuts().apply(&add(11, 20 * FRAME)).value();
    assert_eq!(placement(&after, 10), (1_200_000, 2_400_000 + 10 * FRAME));
    assert_eq!(
        placement(&after, 11),
        (3_600_000 - 10 * FRAME, 2_400_000 + 10 * FRAME)
    );

    // The pair's OUTER edges did not move, which is the whole promise: the
    // timeline is the same length and nothing downstream shifted.
    assert_eq!(int(&after, "/clips/0/start"), 1_200_000);
    assert_eq!(
        placement(&after, 11).0 + placement(&after, 11).1,
        3_600_000 + 2_400_000
    );
}

#[test]
fn the_overlap_is_exactly_what_was_asked_for() {
    // The landed duration is readable back: the transition IS the overlap
    // (spec §5.2), so the claim is arithmetic on two placements and needs
    // no second spelling of "duration" in the model.
    let after = cuts().apply(&add(11, 20 * FRAME)).value();
    let (a_start, a_duration) = placement(&after, 10);
    let (b_start, _) = placement(&after, 11);
    assert_eq!(a_start + a_duration - b_start, 20 * FRAME);
}

#[test]
fn an_odd_frame_count_lands_on_the_grid_with_the_odd_frame_on_the_incoming_clip() {
    // Three frames centred: two off the incoming clip, one off the
    // outgoing. This is why the split happens AFTER the snap — snapping
    // 1.5 frames on each side separately would land 1 + 1 and lose a frame
    // of the request.
    let after = cuts().apply(&add(11, 3 * FRAME)).value();
    assert_eq!(placement(&after, 10), (1_200_000, 2_400_000 + FRAME));
    assert_eq!(
        placement(&after, 11),
        (3_600_000 - 2 * FRAME, 2_400_000 + 2 * FRAME)
    );
}

#[test]
fn a_request_between_frames_is_snapped_down() {
    // A duration off the grid never reaches the model (the crate's rule),
    // and DOWN rather than to the nearest, because the op is taking
    // material out of clips that have a finite amount of it.
    let after = cuts().apply(&add(11, 2 * FRAME + 1)).value();
    let (a_start, a_duration) = placement(&after, 10);
    let (b_start, _) = placement(&after, 11);
    assert_eq!(a_start + a_duration - b_start, 2 * FRAME);
}

#[test]
fn before_takes_it_all_from_the_incoming_head() {
    // The outgoing clip's last frame stays exactly where it was.
    let after = cuts().apply(&add_aligned(11, 10 * FRAME, "before")).value();
    assert_eq!(placement(&after, 10), (1_200_000, 2_400_000));
    assert_eq!(
        placement(&after, 11),
        (3_600_000 - 10 * FRAME, 2_400_000 + 10 * FRAME)
    );
}

#[test]
fn after_takes_it_all_from_the_outgoing_tail() {
    // And the incoming clip's first frame stays exactly where it was,
    // its `in` untouched with it.
    let before = cuts().value();
    let after = cuts().apply(&add_aligned(11, 10 * FRAME, "after")).value();
    assert_eq!(placement(&after, 10), (1_200_000, 2_400_000 + 10 * FRAME));
    assert_eq!(placement(&after, 11), (3_600_000, 2_400_000));
    assert_eq!(source_in(&after, 11), source_in(&before, 11));
}

// ---- the handles ----------------------------------------------------------

#[test]
fn the_incoming_clips_in_point_moves_back_by_the_extension() {
    // At speed 1 the source ticks and the timeline ticks are the same, so
    // `in` moves back exactly as far as the clip's front edge did.
    let after = cuts().apply(&add_aligned(11, 10 * FRAME, "before")).value();
    assert_eq!(source_in(&after, 11), 12_000_000 - 10 * FRAME);
}

#[test]
fn speed_is_applied_exactly_once_to_the_handle() {
    // Track 6 runs at ×2, so ten frames of TIMELINE are twenty frames of
    // source. `source_head` divides by the speed to answer in timeline
    // ticks and the write multiplies back; a build that divided twice would
    // move `in` by five frames and one that multiplied twice by forty.
    let after = cuts().apply(&add_aligned(17, 10 * FRAME, "before")).value();
    assert_eq!(
        placement(&after, 17),
        (1_200_000 - 10 * FRAME, 1_200_000 + 10 * FRAME)
    );
    assert_eq!(source_in(&after, 17), 12_000_000 - 20 * FRAME);
}

#[test]
fn a_request_longer_than_the_handles_clamps_rather_than_refusing() {
    // Clip 13 is at `in` 0 and clip 12 has 3 000 000 source ticks in front
    // of it and the whole media behind, so a five-second centred request
    // lands as much as the pair can give and not a frame more — spec §11's
    // R5-3: a shorter transition is the same edit at a size the media
    // allows.
    let after = cuts().apply(&add(13, 5 * SEC)).value();
    let (a_start, a_duration) = placement(&after, 12);
    let (b_start, b_duration) = placement(&after, 13);
    assert_eq!(b_start, 1_200_000, "a clip at in 0 has no head to give");
    assert_eq!(b_duration, 1_200_000);
    // The overlap rule caps it at half of the SHORTER clip, and the two
    // clips are 1 200 000 apiece, so the whole request collapses onto the
    // outgoing tail and stops at that bound.
    let overlap = a_start + a_duration - b_start;
    assert!(overlap > 0, "something landed");
    assert_eq!(overlap, a_duration.min(b_duration) / 2);
}

#[test]
fn a_centred_request_moves_a_shortfall_to_the_other_side() {
    // Clip 13 has no head, so `center`'s half for the incoming clip has
    // nowhere to come from and moves to the outgoing tail — which is what
    // makes a centred request on a clip at `in` 0 do something at all
    // rather than landing at half size.
    let after = cuts().apply(&add(13, 10 * FRAME)).value();
    assert_eq!(placement(&after, 13), (1_200_000, 1_200_000));
    assert_eq!(placement(&after, 12), (0, 1_200_000 + 10 * FRAME));
}

#[test]
fn a_sourceless_pair_is_bounded_only_by_the_overlap_rule() {
    // A still and a text clip have no window at all, so both handles are
    // unbounded and a request lands whole — up to the half rule, which is
    // what the request below stays inside.
    let after = cuts().apply(&add(15, 10 * FRAME)).value();
    assert_eq!(placement(&after, 14), (0, 1_200_000 + 5 * FRAME));
    assert_eq!(
        placement(&after, 15),
        (1_200_000 - 5 * FRAME, 1_200_000 + 5 * FRAME)
    );
}

#[test]
fn a_nest_gives_a_tail_but_no_head() {
    // Trimming a nest clip's head MOVES its contents rather than revealing
    // anything (`nest.rs`), so a nest incoming clip has nothing to give and
    // a centred request goes wholly to the outgoing clip's tail. One rule
    // for "no handle", not an `Err` of its own.
    let after = cuts().apply(&add(27, 10 * FRAME)).value();
    assert_eq!(placement(&after, 27), (1_200_000, 1_200_000));
    assert_eq!(placement(&after, 26), (0, 1_200_000 + 10 * FRAME));

    // ...and `before`, which has nowhere else to go, is the domain refusal.
    cuts().refuses(&add_aligned(27, 10 * FRAME, "before"));
}

#[test]
fn a_nest_outgoing_clip_can_only_grow_to_the_nests_own_length() {
    // Clip 33 shows 2 400 000 of a 3 000 000-tick nest, so its tail is
    // 600 000 ticks — past which it would draw nothing at all (`nest.rs`).
    // Clip 34 has no head, so a five-second CENTRED request moves its whole
    // share to that tail and then stops at the nest's own length, which is
    // well inside the overlap rule's bound of half the shorter clip.
    let after = cuts().apply(&add(34, 5 * SEC)).value();
    assert_eq!(placement(&after, 33), (0, 2_400_000 + 600_000));
    assert_eq!(placement(&after, 34), (2_400_000, 6_000_000));
    assert_eq!(
        placement(&after, 33).1,
        3_000_000,
        "the nest clip now shows exactly the whole nest and not a tick more"
    );
}

// ---- what does NOT move ---------------------------------------------------

#[test]
fn a_third_clip_on_the_track_never_moves() {
    // Track 56 is three clips in a row. The pair grows into the material it
    // owns and clip 24 is untouched, whatever the op does to the two it
    // names.
    //
    // The neighbour clamp itself is DEFENCE IN DEPTH rather than the bound
    // that bites here, and that is worth saying out loud: the outgoing
    // clip's room is at least the incoming clip's whole duration (the
    // successor cannot start before the incoming clip ends), while the
    // overlap rule already caps the overlap at HALF the shorter of the two.
    // So a request that would reach a neighbour has been refused by the
    // half rule first — as `roll`'s own overlap check is unreachable for
    // the pair it moves, and kept for the same reason.
    let before = cuts().value();
    for request in [20 * FRAME, 20 * SEC] {
        let after = cuts().apply(&add(23, request)).value();
        assert_eq!(
            by_id(&after, "/clips", 24),
            by_id(&before, "/clips", 24),
            "the neighbour was touched by a request of {request}"
        );
        // ...and the pair's own outer edges are where they were.
        assert_eq!(placement(&after, 22).0, 0);
        let (b_start, b_duration) = placement(&after, 23);
        assert_eq!(b_start + b_duration, 2_400_000 + 2_400_000);
    }

    // The 20-frame request is the ordinary case: ten frames each way.
    let after = cuts().apply(&add(23, 20 * FRAME)).value();
    assert_eq!(placement(&after, 22), (0, 2_400_000 + 10 * FRAME));
    assert_eq!(
        placement(&after, 23),
        (2_400_000 - 10 * FRAME, 2_400_000 + 10 * FRAME)
    );
}

#[test]
fn nothing_outside_the_pair_changes_at_all() {
    // The whole document, minus the two clips the op names. An op that
    // quietly renumbered, re-sorted or re-stamped something is what this
    // catches and a per-field assertion cannot.
    let before = cuts().value();
    let after = cuts().apply(&add(11, 20 * FRAME)).value();
    for key in ["media", "tracks", "markers", "nests", "next_id", "canvas"] {
        assert_eq!(
            at(&after, &format!("/{key}")),
            at(&before, &format!("/{key}")),
            "{key} changed"
        );
    }
    for clip in array(&before, "/clips") {
        let id = int(clip, "/id") as u64;
        if id == 10 || id == 11 {
            continue;
        }
        assert_eq!(by_id(&after, "/clips", id), clip, "clip {id} changed");
    }
}

#[test]
fn the_document_comes_back_byte_for_byte_after_an_undo() {
    // The strongest form of "nothing else moved": the app's undo is a
    // handle, so this is the same comparison it makes.
    let before = cuts();
    let text_before = before.to_json();
    let after = before.apply(&add(11, 20 * FRAME));
    assert_ne!(after.to_json(), text_before, "the op did something");
    // The inverse state is the ORIGINAL handle, which the app keeps; what
    // is pinned here is that applying the op did not mutate it.
    assert_eq!(before.to_json(), text_before);
}

// ---- actions ---------------------------------------------------------------

#[test]
fn the_incoming_clips_actions_move_with_its_new_first_frame() {
    // Clip 11's action is drawn over a SOURCE frame — a screencast zoom on
    // a click — so revealing ten frames in front of it must carry the
    // action along, where `trim_start` deliberately leaves actions alone.
    let after = cuts().apply(&add_aligned(11, 10 * FRAME, "before")).value();
    let action = &array(by_id(&after, "/clips", 11), "/actions")[0];
    assert_eq!(int(action, "/start"), 600_000 + 10 * FRAME);
    assert_eq!(int(action, "/duration"), 600_000);
    assert_eq!(num(action, "/end/video/scale"), 2.0);

    // The other side's clip has none and gains none.
    assert_eq!(array(by_id(&after, "/clips", 10), "/actions").len(), 0);
}

#[test]
fn an_after_aligned_transition_leaves_the_actions_alone() {
    // Nothing was revealed in front of the incoming clip, so nothing about
    // its clip time moved.
    let after = cuts().apply(&add_aligned(11, 10 * FRAME, "after")).value();
    let action = &array(by_id(&after, "/clips", 11), "/actions")[0];
    assert_eq!(int(action, "/start"), 600_000);
}

// ---- the transition it writes ---------------------------------------------

#[test]
fn a_new_transition_is_minted() {
    // Spec §11 R5-2: a transition the core makes NOW is eased and
    // crossfading, where an old file's is linear and silent.
    let after = cuts().apply(&add(11, 20 * FRAME)).value();
    assert_eq!(
        at(by_id(&after, "/clips", 11), "/transition_in"),
        &json!({"kind": "cross_dissolve", "curve": "ease_in_out", "audio": true})
    );
}

#[test]
fn a_named_kind_is_used() {
    let after = cuts()
        .apply(
            &json!({"op": "add_transition", "clip": 11, "kind": "wipe_up",
                       "duration": 20 * FRAME}),
        )
        .value();
    assert_eq!(
        text(by_id(&after, "/clips", 11), "/transition_in/kind"),
        "wipe_up"
    );
}

#[test]
fn a_stored_kind_and_style_are_kept() {
    // Clip ▸ Transition ▸ at a hard cut stores an UNDRAWN transition, so by
    // the time the person drags an overlap out of the cut the kind — and
    // any curve they set with `set_transition_style` — is already there and
    // must survive.
    let project = cuts()
        .apply(&json!({"op": "set_transition", "clip": 11, "kind": "slide"}))
        .apply(&json!({"op": "set_transition_style", "clip": 11,
                       "curve": "ease_out", "audio": false}));
    let after = project.apply(&add(11, 20 * FRAME)).value();
    assert_eq!(
        at(by_id(&after, "/clips", 11), "/transition_in"),
        &json!({"kind": "slide", "curve": "ease_out", "audio": false})
    );
}

#[test]
fn a_named_kind_over_a_stored_one_keeps_the_stored_style() {
    let project = cuts().apply(&json!({"op": "set_transition_style", "clip": 11,
                                       "curve": "ease_in", "audio": false}));
    let after = project
        .apply(&json!({"op": "add_transition", "clip": 11, "kind": "zoom",
                       "duration": 20 * FRAME}))
        .value();
    assert_eq!(
        at(by_id(&after, "/clips", 11), "/transition_in"),
        &json!({"kind": "zoom", "curve": "ease_in", "audio": false})
    );
}

// ---- refusals --------------------------------------------------------------

#[test]
fn a_non_positive_duration_is_an_error() {
    // Before anything else is read, so it is the answer even for a clip
    // that is not at a hard cut.
    for bad in [0, -1, -20 * FRAME] {
        let msg = cuts().errors(&add(11, bad));
        assert_contains(&msg, "duration must be positive");
    }
    assert_contains(&cuts().errors(&add(19, 0)), "duration must be positive");
}

#[test]
fn an_unknown_clip_is_an_error() {
    assert_contains(&cuts().errors(&add(999, 20 * FRAME)), "no clip with id 999");
}

#[test]
fn a_first_clip_on_its_track_names_the_reason() {
    // Not being at a hard cut is a wrong ARGUMENT (spec §11 R5-3): the op
    // was pointed at one cut by a caller who meant that cut, unlike `roll`,
    // which a drag can reach at any edge. So each of the three says which
    // it is rather than answering a bare `None`.
    let msg = cuts().errors(&add(25, 20 * FRAME));
    assert_contains(&msg, "clip 25 is not at a hard cut");
    assert_contains(&msg, "first clip on its track");
}

#[test]
fn a_gap_before_the_clip_names_the_gap() {
    let msg = cuts().errors(&add(19, 20 * FRAME));
    assert_contains(&msg, "clip 19 is not at a hard cut");
    assert_contains(&msg, "gap of 1200000 ticks");
}

#[test]
fn an_existing_overlap_points_at_the_other_two_ops() {
    let msg = cuts().errors(&add(21, 20 * FRAME));
    assert_contains(&msg, "clip 21 is not at a hard cut");
    assert_contains(&msg, "already overlaps clip 20");
    assert_contains(&msg, "set_transition");
}

#[test]
fn an_unknown_align_is_named_with_the_three_that_are_legal() {
    // `Op` denies unknown fields and closes its enums, so a misspelt
    // alignment is a parse failure that LISTS the vocabulary rather than
    // falling back to `center`. The MCP handler refuses it by the argument's
    // NAME one layer up (`AgentServer+Transitions.swift`); this is the
    // core's own answer, which an agent reaches by any other route.
    let msg = cuts().errors(&add_aligned(11, 20 * FRAME, "middle"));
    assert_contains(&msg, "middle");
    assert_contains(&msg, "center");
    assert_contains(&msg, "before");
    assert_contains(&msg, "after");
}

#[test]
fn no_handle_at_all_is_the_domain_refusal() {
    // `before` on a clip whose `in` is 0: there is nothing to reveal, the
    // request clamps below one frame, and the answer is a REFUSAL carrying
    // the cut's own sentence — no undo step, and not an error.
    cuts().refuses(&add_aligned(13, 20 * FRAME, "before"));
}

// ---- set_transition_style --------------------------------------------------

#[test]
fn the_style_op_writes_onto_a_clip_with_no_overlap() {
    // Same storage rule as `set_transition`: a stored transition on a clip
    // with no overlap is undrawn until there is one, which is what lets the
    // inspector and the Clip menu set a style before the overlap exists.
    let after = cuts()
        .apply(&json!({"op": "set_transition_style", "clip": 11, "curve": "ease_in"}))
        .value();
    assert_eq!(
        at(by_id(&after, "/clips", 11), "/transition_in"),
        &json!({"kind": "cross_dissolve", "curve": "ease_in", "audio": true}),
        "with nothing stored it mints and applies the style over it"
    );
}

#[test]
fn each_key_moves_alone() {
    let project = cuts().apply(&json!({"op": "set_transition_style", "clip": 21,
                                       "curve": "ease_out"}));
    let after = project.value();
    assert_eq!(
        at(by_id(&after, "/clips", 21), "/transition_in"),
        &json!({"kind": "cross_dissolve", "curve": "ease_out", "audio": false}),
        "the file's own audio flag is kept where no argument named it"
    );

    let then = project
        .apply(&json!({"op": "set_transition_style", "clip": 21, "audio": true}))
        .value();
    assert_eq!(
        at(by_id(&then, "/clips", 21), "/transition_in"),
        &json!({"kind": "cross_dissolve", "curve": "ease_out", "audio": true}),
        "and the curve is kept where no argument named that"
    );
}

#[test]
fn neither_key_never_mints() {
    // Asking for no change is not a way to make a transition. The clip
    // keeps whatever it had — nothing, here — and there is no undo step.
    cuts().refuses(&json!({"op": "set_transition_style", "clip": 11}));
    assert_eq!(
        at(by_id(&cuts().value(), "/clips", 11), "/transition_in"),
        &Value::Null
    );

    // And on a clip that HAS one it is equally inert.
    cuts().refuses(&json!({"op": "set_transition_style", "clip": 21}));
}

#[test]
fn writing_the_style_a_clip_already_has_changes_nothing() {
    let project = cuts().apply(&json!({"op": "set_transition_style", "clip": 21,
                                       "curve": "ease_in", "audio": true}));
    project.refuses(&json!({"op": "set_transition_style", "clip": 21,
                            "curve": "ease_in", "audio": true}));
}

#[test]
fn the_style_op_refuses_an_unknown_clip_by_name() {
    assert_contains(
        &cuts().errors(&json!({"op": "set_transition_style", "clip": 999, "curve": "ease_in"})),
        "no clip with id 999",
    );
}
