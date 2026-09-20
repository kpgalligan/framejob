//! `insert_clip` and `overwrite_clip`, through the FFI — spec §6.
//!
//! The two are opposites and are tested as such. An insert must leave every
//! frame that was in the cut still in the cut, moved later by exactly the
//! new clip's length; an overwrite must leave every frame OUTSIDE the span
//! it takes exactly where it was, on every track including its own. Each
//! test therefore asserts on what did NOT move at least as much as on what
//! did, and both check the other tracks byte for byte.
//!
//! The clip each op mints is named by reading `next_id` before the call
//! (spec §6: "a new id is the project's `next_id` from BEFORE the call"),
//! and an insert that has to split first mints two — the split's tail, then
//! the new clip — which is the one place the order matters.

use serde_json::{json, Value};

mod common;
use common::{array, assert_contains, by_id, int, source_in, text, Handle};

// ---- fixtures ------------------------------------------------------------

/// A cut with something to insert into on every side. Ids are one space
/// across media, tracks and clips (spec §5.2), so the tracks start at 5.
///
/// - Media 1 is a minute of picture, media 2 is the ten seconds being
///   brought in, media 3 an image with no duration of its own (so a clip of
///   it takes the five-second default) and media 4 a video with no duration
///   at all — the one that cannot be placed.
/// - Track 5 holds clips 10 (0 – 10 s) and 11 (10 s – 20 s), meeting at a
///   cut, so a drop at 8 s lands INSIDE a clip and a drop at 10 s does not.
/// - Track 6 holds clip 12 (5 s – 15 s), which STRADDLES 8 s and must ride
///   an insert whole, and clip 13 (20 s – 25 s) behind it.
/// - Track 7 is LOCKED and holds clip 14 (0 – 10 s).
fn insert_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 2,
  "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "background": [0, 0, 0, 1],
             "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 2, "path": "/m/roll.mov", "kind": "video", "duration": 6000000,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true},
    {"id": 3, "path": "/m/logo.png", "kind": "image", "width": 800, "height": 600,
     "fps": [30, 1]},
    {"id": 4, "path": "/m/empty.mov", "kind": "video", "duration": 0,
     "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": false}
  ],
  "tracks": [
    {"id": 5, "name": "Picture"},
    {"id": 6, "name": "Bed"},
    {"id": 7, "name": "Locked", "locked": true}
  ],
  "clips": [
    {"id": 10, "track": 5, "start": 0, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 11, "track": 5, "start": 6000000, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 6000000}, "video": {}, "audio": {}},
    {"id": 12, "track": 6, "start": 3000000, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 13, "track": 6, "start": 12000000, "duration": 3000000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}},
    {"id": 14, "track": 7, "start": 0, "duration": 6000000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}}
  ],
  "markers": [{"id": 20, "time": 9000000, "name": "Later"}],
  "next_id": 30
}"#,
    )
}

/// One frame at 30000/1001, and the five-second default clip length ON that
/// grid — 150 frames of 20 020 ticks, which is 3 003 000 and not the round
/// 3 000 000 the constant spells.
const DROP_FRAME: i64 = 20_020;
const DROP_FRAME_DEFAULT: i64 = 150 * DROP_FRAME;

/// The same two ops on a canvas whose rate does not divide the timescale,
/// with the media that has no duration of its own: an image, which takes the
/// default length. That default is a CONSTANT number of ticks, so it is the
/// one length in the op that can fall between two frames.
fn drop_frame_project() -> Handle {
    Handle::from_json(
        r#"{
  "version": 2,
  "canvas": {"width": 1920, "height": 1080, "fps": [30000, 1001],
             "background": [0, 0, 0, 1], "fit_new_clips": true, "timecode_frames": true},
  "media": [
    {"id": 1, "path": "/m/talk.mov", "kind": "video", "duration": 36000000,
     "width": 1920, "height": 1080, "fps": [30000, 1001], "has_video": true, "has_audio": true},
    {"id": 2, "path": "/m/logo.png", "kind": "image", "width": 800, "height": 600,
     "fps": [30000, 1001]}
  ],
  "tracks": [{"id": 5, "name": "Picture"}],
  "clips": [
    {"id": 10, "track": 5, "start": 0, "duration": 6006000,
     "source": {"kind": "media", "media": 1, "in": 0}, "video": {}, "audio": {}}
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

fn ids_on(project: &Value, track: i64) -> Vec<i64> {
    let mut found: Vec<(i64, i64)> = array(project, "/clips")
        .iter()
        .filter(|c| int(c, "/track") == track)
        .map(|c| (int(c, "/start"), int(c, "/id")))
        .collect();
    found.sort();
    found.into_iter().map(|(_, id)| id).collect()
}

// ---- insert --------------------------------------------------------------

#[test]
fn insert_clip_cuts_its_own_track_and_opens_time_on_every_other() {
    let project = insert_project();
    let before = project.value();
    let minted = int(&before, "/next_id");

    // Ten seconds of media 2 dropped at 8 s, which is inside clip 10.
    let after = project
        .apply(&json!({"op": "insert_clip", "track": 5, "media": 2, "at": 4800000}))
        .value();
    let tail = minted as u64;
    let placed = minted as u64 + 1;

    // Clip 10 keeps its head where it was; its tail is the split's, moved
    // right by the whole length with the source it had advanced to.
    assert_eq!(placement(&after, 10), (0, 4_800_000));
    assert_eq!(placement(&after, tail), (4_800_000 + 6_000_000, 1_200_000));
    assert_eq!(source_in(&after, tail), 4_800_000);
    // And the new clip fills exactly the room that was made.
    assert_eq!(placement(&after, placed), (4_800_000, 6_000_000));
    assert_eq!(int(by_id(&after, "/clips", placed), "/source/media"), 2);
    assert_eq!(source_in(&after, placed), 0);

    // Everything that began at or after the drop is later by exactly the
    // new clip's length; everything before it is where it was.
    assert_eq!(placement(&after, 11), (6_000_000 + 6_000_000, 6_000_000));
    assert_eq!(placement(&after, 13), (12_000_000 + 6_000_000, 3_000_000));
    // The straddler on the other track is neither cut nor moved (spec §11's
    // rule 3): only the destination track is cut.
    assert_eq!(
        by_id(&after, "/clips", 12),
        by_id(&before, "/clips", 12),
        "a straddler on another track was disturbed"
    );
    // The locked track keeps everything.
    assert_eq!(by_id(&after, "/clips", 14), by_id(&before, "/clips", 14));
    // `insert_time` carries the markers, so the mark keeps the moment it
    // named rather than the wall-clock time it had.
    assert_eq!(
        int(by_id(&after, "/markers", 20), "/time"),
        9_000_000 + 6_000_000
    );

    assert_eq!(ids_on(&after, 5), vec![10, placed as i64, tail as i64, 11]);
}

#[test]
fn an_insert_at_a_cut_splits_nothing() {
    let project = insert_project();
    let before = project.value();
    let placed = int(&before, "/next_id") as u64;

    // 10 s is where clip 10 ends and clip 11 begins: strictly inside
    // neither, so there is nothing to cut and only one id is minted.
    let after = project
        .apply(&json!({"op": "insert_clip", "track": 5, "media": 2, "at": 6000000}))
        .value();
    assert_eq!(
        array(&after, "/clips").len(),
        array(&before, "/clips").len() + 1
    );
    assert_eq!(placement(&after, 10), (0, 6_000_000), "untouched");
    assert_eq!(placement(&after, placed), (6_000_000, 6_000_000));
    assert_eq!(placement(&after, 11), (12_000_000, 6_000_000));
    assert_eq!(ids_on(&after, 5), vec![10, placed as i64, 11]);
}

#[test]
fn an_insert_into_a_locked_track_refuses() {
    let project = insert_project();
    // `insert_time` will not shift a locked track, so the room is never
    // made and the clip lands on material that did not move.
    project.refuses(&json!({"op": "insert_clip", "track": 7, "media": 2, "at": 3000000}));
}

// ---- overwrite -----------------------------------------------------------

#[test]
fn overwrite_clip_clears_its_own_track_and_moves_nothing() {
    let project = insert_project();
    let before = project.value();
    let minted = int(&before, "/next_id");

    // The same ten seconds at the same 8 s, taking room instead of making
    // it: the span is 8 s – 18 s and only track 5 gives anything up.
    let after = project
        .apply(&json!({"op": "overwrite_clip", "track": 5, "media": 2, "at": 4800000}))
        .value();
    // Two splits then the new clip: clip 10's tail, clip 11's tail, the clip.
    let head_tail = minted as u64;
    let far_tail = minted as u64 + 1;
    let placed = minted as u64 + 2;

    assert_eq!(placement(&after, 10), (0, 4_800_000), "the head survives");
    assert_eq!(placement(&after, placed), (4_800_000, 6_000_000));
    assert_eq!(placement(&after, far_tail), (10_800_000, 1_200_000));
    assert_eq!(source_in(&after, far_tail), 6_000_000 + 4_800_000);
    // The two pieces that lay inside the span are gone, clip 11 with them.
    for gone in [head_tail, 11] {
        assert!(
            !array(&after, "/clips")
                .iter()
                .any(|c| int(c, "/id") as u64 == gone),
            "clip {gone} was inside the span and should be gone"
        );
    }
    assert_eq!(ids_on(&after, 5), vec![10, placed as i64, far_tail as i64]);

    // Nothing else in the document moved at all — no shift, no other track.
    for id in [12u64, 13, 14] {
        assert_eq!(
            by_id(&after, "/clips", id),
            by_id(&before, "/clips", id),
            "clip {id} moved under an overwrite"
        );
    }
    assert_eq!(
        by_id(&after, "/markers", 20),
        by_id(&before, "/markers", 20)
    );
}

#[test]
fn an_overwrite_inside_one_clip_leaves_a_head_and_a_tail() {
    let project = insert_project();
    let before = project.value();
    let minted = int(&before, "/next_id");

    // Media 3 is an image with no duration, so its clip is the five-second
    // default: the span 8 s – 13 s falls entirely inside clip 12.
    let after = project
        .apply(&json!({"op": "overwrite_clip", "track": 6, "media": 3, "at": 4800000}))
        .value();
    let tail = minted as u64 + 1;
    let placed = minted as u64 + 2;

    assert_eq!(placement(&after, 12), (3_000_000, 1_800_000), "the head");
    assert_eq!(placement(&after, placed), (4_800_000, 3_000_000));
    assert_eq!(
        text(by_id(&after, "/clips", placed), "/source/kind"),
        "image"
    );
    assert_eq!(placement(&after, tail), (7_800_000, 1_200_000), "the tail");
    assert_eq!(source_in(&after, tail), 4_800_000);
    assert_eq!(ids_on(&after, 6), vec![12, placed as i64, tail as i64, 13]);

    // The other tracks are untouched, clip 13 included.
    for id in [10u64, 11, 13, 14] {
        assert_eq!(by_id(&after, "/clips", id), by_id(&before, "/clips", id));
    }
}

#[test]
fn an_overwrite_past_the_end_of_a_track_just_places_the_clip() {
    let project = insert_project();
    let before = project.value();
    let placed = int(&before, "/next_id") as u64;

    let after = project
        .apply(&json!({"op": "overwrite_clip", "track": 5, "media": 2, "at": 18000000}))
        .value();
    assert_eq!(
        array(&after, "/clips").len(),
        array(&before, "/clips").len() + 1
    );
    assert_eq!(placement(&after, placed), (18_000_000, 6_000_000));
    for id in [10u64, 11, 12, 13, 14] {
        assert_eq!(by_id(&after, "/clips", id), by_id(&before, "/clips", id));
    }
}

#[test]
fn an_overwrite_clears_a_locked_track_because_the_caller_named_it() {
    let project = insert_project();
    let before = project.value();
    let placed = int(&before, "/next_id") as u64;
    // A lock says "this stays where it is", and nothing here moves — the
    // named track is cleared exactly as `ripple_delete` removes the clips
    // it was given. The insert twin refuses instead, because the room it
    // promises cannot be made on a track `insert_time` will not shift.
    let after = project
        .apply(&json!({"op": "overwrite_clip", "track": 7, "media": 2, "at": 0}))
        .value();
    assert_eq!(placement(&after, placed), (0, 6_000_000));
    assert!(
        !array(&after, "/clips").iter().any(|c| int(c, "/id") == 14),
        "the locked track's clip was inside the span and is gone"
    );
    for id in [10u64, 11, 12, 13] {
        assert_eq!(by_id(&after, "/clips", id), by_id(&before, "/clips", id));
    }
}

#[test]
fn a_locked_destination_refuses_an_insert_even_with_room_to_spare() {
    let project = insert_project();
    // Past the end of the locked track's only clip, so nothing could
    // collide: the refusal is the lock itself and not a stacked clip.
    project.refuses(&json!({"op": "insert_clip", "track": 7, "media": 2, "at": 12000000}));
}

#[test]
fn the_default_image_length_is_on_the_frame_grid() {
    let project = drop_frame_project();
    // Five seconds at 30000/1001 is 3 003 000 ticks, not the 3 000 000 the
    // constant spells. An unsnapped default made `overwrite_clip` clear a
    // span that missed the fragment `split_clips` had just made — the
    // fragment survived, the new clip landed on top of it, and the overlap
    // rule refused the whole op.
    let minted = int(&project.value(), "/next_id") as u64;
    let after = project
        .apply(&json!({"op": "overwrite_clip", "track": 5, "media": 2, "at": 0}))
        .value();
    assert_eq!(placement(&after, minted + 1), (0, DROP_FRAME_DEFAULT));
    assert_eq!(
        placement(&after, minted),
        (DROP_FRAME_DEFAULT, 6_006_000 - DROP_FRAME_DEFAULT),
        "the tail begins exactly where the new clip ends"
    );

    // And an insert opens exactly the room the clip fills, not a sliver
    // more: the tail's start moves by the placed clip's own length.
    let inserted = project
        .apply(&json!({"op": "insert_clip", "track": 5, "media": 2, "at": 1001000}))
        .value();
    assert_eq!(
        placement(&inserted, minted + 1),
        (1_001_000, DROP_FRAME_DEFAULT)
    );
    assert_eq!(
        int(by_id(&inserted, "/clips", minted), "/start"),
        1_001_000 + DROP_FRAME_DEFAULT
    );
    for id in [minted, minted + 1] {
        let found = by_id(&inserted, "/clips", id);
        assert_eq!(int(found, "/start") % DROP_FRAME, 0, "clip {id} start");
        assert_eq!(
            int(found, "/duration") % DROP_FRAME,
            0,
            "clip {id} duration"
        );
    }
}

// ---- arguments -----------------------------------------------------------

#[test]
fn an_unknown_track_media_or_an_empty_media_is_an_error() {
    let project = insert_project();
    for op in ["insert_clip", "overwrite_clip"] {
        assert_contains(
            &project.errors(&json!({"op": op, "track": 99, "media": 2, "at": 0})),
            "no track with id 99",
        );
        assert_contains(
            &project.errors(&json!({"op": op, "track": 5, "media": 99, "at": 0})),
            "no media with id 99",
        );
        // The length comes from `whole_media_length`, which is `add_clip`'s
        // own: a media that cannot make a clip cannot make room for one
        // either, and it says so before anything is cut.
        assert_contains(
            &project.errors(&json!({"op": op, "track": 5, "media": 4, "at": 0})),
            "media 4 has no duration",
        );
    }
}
