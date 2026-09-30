//! The non-edits a rule declined, each in the rule's own sentence (spec §11
//! #88), through the FFI.
//!
//! Five ops answered an identity where a rule had declined them — `roll`
//! with no cut, `detach_audio` with no audio, `set_transition_duration`
//! with nothing before the clip or past the pair's limit, `close_gap`
//! aimed at no gap, and an `add_transition` too short to make. Each row
//! pins the whole sentence with `refuses_with` and then sends the value the
//! sentence names, or the nearest one that is a real edit, and sees it
//! APPLY — so the sentence is advice a caller can act on.
//!
//! What stays an identity is pinned too: a roll whose clamps land on the
//! cut is §5.5's clamp family.

use serde_json::{json, Value};

mod common;
use common::{by_id, int, Handle, Outcome};

// ---- fixtures ------------------------------------------------------------

/// A project at `fps` with the given tracks and clips. Media 1 has audio,
/// media 2 has none, and media 3 is exactly 1 200 000 ticks long.
fn doc(fps: [u32; 2], tracks: &[u32], clips: Value) -> Handle {
    let tracks: Vec<Value> = tracks
        .iter()
        .map(|id| json!({"id": id, "name": format!("T{id}")}))
        .collect();
    Handle::from_value(&json!({
        "version": 8,
        "canvas": {"width": 1920, "height": 1080, "fps": fps, "background": [0, 0, 0, 1]},
        "media": [
            {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
             "width": 1920, "height": 1080, "fps": [30, 1],
             "has_video": true, "has_audio": true},
            {"id": 2, "path": "/m/mute.mov", "kind": "video", "duration": 36000000,
             "width": 1920, "height": 1080, "fps": [30, 1],
             "has_video": true, "has_audio": false},
            {"id": 3, "path": "/m/short.mov", "kind": "video", "duration": 1200000,
             "width": 1920, "height": 1080, "fps": [30, 1],
             "has_video": true, "has_audio": true}
        ],
        "tracks": tracks,
        "clips": clips,
        "markers": [], "next_id": 90, "nests": []
    }))
}

fn at_30fps(tracks: &[u32], clips: Value) -> Handle {
    doc([30, 1], tracks, clips)
}

/// A shape clip: sourceless, so no source window clamps anything.
fn shape(id: u32, track: u32, start: i64, duration: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "shape"}, "video": {}, "shape": {}})
}

fn media(id: u32, track: u32, media: u32, r#in: i64, start: i64, duration: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "media", "media": media, "in": r#in},
           "video": {}, "audio": {}})
}

/// Shapes P [0, 1 200 000) and X [1 200 000, 2 400 000) at a hard cut on
/// track 50.
fn pair() -> Handle {
    at_30fps(
        &[50],
        json!([shape(30, 50, 0, 1200000), shape(31, 50, 1200000, 1200000)]),
    )
}

fn start(project: &Value, id: u64) -> i64 {
    int(by_id(project, "/clips", id), "/start")
}

// ---- roll ----------------------------------------------------------------

#[test]
fn roll_across_a_gap_names_the_track_and_the_start() {
    let project = at_30fps(
        &[50],
        json!([
            shape(30, 50, 0, 1200000),
            shape(31, 50, 1200000, 1200000),
            shape(32, 50, 3000000, 1200000)
        ]),
    );
    project.refuses_with(
        &json!({"op": "roll", "clip": 32, "to": 2700000}),
        "no clip on track 50 ends where clip 32 begins (3000000), so there is no cut to roll",
    );
    // The first clip on the track has no cut either.
    project.refuses_with(
        &json!({"op": "roll", "clip": 30, "to": 600000}),
        "no clip on track 50 ends where clip 30 begins (0), so there is no cut to roll",
    );
    // At a hard cut the same op applies.
    let after = project
        .apply(&json!({"op": "roll", "clip": 31, "to": 1000000}))
        .value();
    assert_eq!(start(&after, 31), 1_000_000);
}

#[test]
fn a_roll_whose_clamps_land_on_the_cut_is_still_an_identity() {
    // Clip 30 shows the WHOLE of media 3, so its end cannot grow; clip 31
    // starts at `in` 0, so its head cannot either. Every `to` clamps back
    // to the cut: §5.5's clamp family, which stays an identity.
    let project = at_30fps(
        &[50],
        json!([
            media(30, 50, 3, 0, 0, 1200000),
            media(31, 50, 1, 0, 1200000, 1200000)
        ]),
    );
    for to in [600_000, 1_200_000, 9_000_000] {
        match project.try_apply(&json!({"op": "roll", "clip": 31, "to": to})) {
            Ok(Outcome::Identity) => {}
            other => panic!("roll to {to}: expected an identity, got {other:?}"),
        }
    }
}

// ---- detach_audio ----------------------------------------------------------

#[test]
fn detach_audio_says_why_there_is_nothing_to_detach() {
    let project = at_30fps(
        &[50],
        json!([
            shape(30, 50, 0, 600000),
            media(31, 50, 2, 0, 600000, 600000),
            media(32, 50, 1, 0, 1200000, 600000)
        ]),
    );
    project.refuses_with(
        &json!({"op": "detach_audio", "clip": 30}),
        "clip 30 has no audio to detach: it is not a media clip",
    );
    project.refuses_with(
        &json!({"op": "detach_audio", "clip": 31}),
        "clip 31 has no audio to detach: media 2 has no audio track",
    );
    // The boundary: a media clip with audio detaches, and then has none.
    let detached = project.apply(&json!({"op": "detach_audio", "clip": 32}));
    detached.refuses_with(
        &json!({"op": "detach_audio", "clip": 32}),
        "clip 32 has no audio to detach: its audio is switched off",
    );
}

// ---- set_transition_duration ---------------------------------------------

#[test]
fn set_transition_duration_on_the_first_clip_names_the_track() {
    pair().refuses_with(
        &json!({"op": "set_transition_duration", "clip": 30, "duration": 200000}),
        "clip 30 is the first clip on track 50, so there is no clip before it to overlap",
    );
}

#[test]
fn set_transition_duration_before_the_timeline_names_the_limit_that_applies() {
    pair().refuses_with(
        &json!({"op": "set_transition_duration", "clip": 31, "duration": 1800000}),
        "clip 31 would start at -600000, before the timeline, to overlap clip 30 by 1800000 \
         ticks; the two can overlap by at most 600000 ticks",
    );
    let after = pair()
        .apply(&json!({"op": "set_transition_duration", "clip": 31, "duration": 600000}))
        .value();
    assert_eq!(start(&after, 31), 600_000);
}

#[test]
fn set_transition_duration_never_moves_a_clip_in_front_of_its_predecessor() {
    // #175: 900 000 is longer than P itself, so X would land at
    // [2 100 000, 2 400 000) — in front of P, the pair's order flipped. It
    // used to apply. The limit is half the shorter clip (150 000), snapped
    // down to the grid.
    let project = at_30fps(
        &[50],
        json!([
            shape(30, 50, 2400000, 600000),
            shape(31, 50, 3000000, 300000)
        ]),
    );
    project.refuses_with(
        &json!({"op": "set_transition_duration", "clip": 31, "duration": 900000}),
        "clip 31 would start at 2100000, before clip 30 starts at 2400000, to overlap clip 30 \
         by 900000 ticks; the two can overlap by at most 140000 ticks",
    );
    // Past the limit without leaving the predecessor: the same sentence,
    // with no clause about where.
    project.refuses_with(
        &json!({"op": "set_transition_duration", "clip": 31, "duration": 300000}),
        "clip 31 would start at 2700000 to overlap clip 30 by 300000 ticks; the two can \
         overlap by at most 140000 ticks",
    );
    let after = project
        .apply(&json!({"op": "set_transition_duration", "clip": 31, "duration": 140000}))
        .value();
    assert_eq!(start(&after, 31), 2_860_000);
}

// ---- close_gap -------------------------------------------------------------

#[test]
fn close_gap_aimed_at_no_gap_names_what_is_there() {
    let project = at_30fps(
        &[50],
        json!([shape(30, 50, 0, 1200000), shape(31, 50, 2400000, 1200000)]),
    );
    project.refuses_with(
        &json!({"op": "close_gap", "track": 50, "at": 600000}),
        "clip 30 runs from 0 to 1200000 on track 50, so 600000 is not in a gap",
    );
    project.refuses_with(
        &json!({"op": "close_gap", "track": 50, "at": 4200000}),
        "no clip on track 50 starts after 4200000, so there is no gap to close",
    );
    // Both edges of the gap, and its middle, close it.
    for at in [1_200_000, 1_800_000] {
        let after = project
            .apply(&json!({"op": "close_gap", "track": 50, "at": at}))
            .value();
        assert_eq!(start(&after, 31), 1_200_000, "closing at {at}");
    }
}

// ---- add_transition too short ----------------------------------------------

#[test]
fn a_transition_under_one_frame_names_the_shortest_that_passes_in_both_forms() {
    for ripple in [false, true] {
        let too_short =
            json!({"op": "add_transition", "clip": 31, "duration": 10000, "ripple": ripple});
        pair().refuses_with(
            &too_short,
            "a transition of 10000 ticks is too short to make at the cut before clip 31; \
             pass a duration of at least 20000 ticks",
        );
        let one = json!({"op": "add_transition", "clip": 31, "duration": 20000, "ripple": ripple});
        let after = pair().apply(&one).value();
        assert!(
            !by_id(&after, "/clips", 31)["transition_in"].is_null(),
            "ripple {ripple}: the one-frame transition was made"
        );
    }
}

#[test]
fn at_5994_over_100_one_grid_frame_passes_in_both_forms() {
    // 10 010 ticks is one frame of the real grid, and both forms count on
    // that grid (spec §11 #174): a tick less is too short and names it, and
    // it passes.
    let project = doc(
        [5994, 100],
        &[50],
        json!([shape(30, 50, 0, 1201201), shape(31, 50, 1201201, 1201201)]),
    );
    for ripple in [false, true] {
        project.refuses_with(
            &json!({"op": "add_transition", "clip": 31, "duration": 10009, "ripple": ripple}),
            "a transition of 10009 ticks is too short to make at the cut before clip 31; \
             pass a duration of at least 10010 ticks",
        );
        let after = project
            .apply(
                &json!({"op": "add_transition", "clip": 31, "duration": 10010,
                           "ripple": ripple}),
            )
            .value();
        assert!(
            start(&after, 31) < 1_201_201,
            "ripple {ripple}: the incoming clip grew back"
        );
    }
}
