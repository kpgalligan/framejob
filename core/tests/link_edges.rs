//! The named edge cases of linked pairs (spec §11 AU-91, AU-93): two
//! consecutive detached shots, a J-cut near 0, the shift floor's refusal in
//! each op that shifts, and what `delete` and `ripple_delete` take.
//!
//! Every pair here is made by `detach_audio` itself, so the link under test
//! is the one the product writes.

mod common;

use common::{at, by_id, int, Handle};
use serde_json::{json, Value};

const SEC: i64 = 600_000;
const FRAME: i64 = SEC / 30;

fn shot(id: u32, track: u32, start: i64, duration: i64, r#in: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "media", "media": 9, "in": r#in},
           "video": {}, "audio": {}})
}

/// Tracks 1 (back), 2 and 3 (front); `clips` on them; next id 100.
fn project(clips: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 28,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 9, "path": "/fixtures/talk.mov", "kind": "video",
                   "duration": 30 * SEC, "width": 1920, "height": 1080,
                   "fps": [30, 1], "has_video": true, "has_audio": true}],
        "tracks": [{"id": 1, "name": "A"}, {"id": 2, "name": "B"}, {"id": 3, "name": "C"}],
        "clips": clips,
        "next_id": 100
    }))
}

fn detach(handle: Handle, clips: &[u32]) -> Handle {
    clips.iter().fold(handle, |h, id| {
        h.apply(&json!({"op": "detach_audio", "clip": id}))
    })
}

fn clip(project: &Value, id: u64) -> &Value {
    by_id(project, "/clips", id)
}

fn start(project: &Value, id: u64) -> i64 {
    int(clip(project, id), "/start")
}

fn track(project: &Value, id: u64) -> i64 {
    int(clip(project, id), "/track")
}

fn has(project: &Value, id: u64) -> bool {
    at(project, "/clips")
        .as_array()
        .is_some_and(|c| c.iter().any(|x| x["id"] == json!(id)))
}

/// P1 (10) and P2 (12) back to back on track 2, each detached: S1 (100)
/// and S2 (101) back to back on track 1.
fn consecutive() -> Handle {
    detach(
        project(vec![
            shot(10, 2, 2 * SEC, 3 * SEC, 0),
            shot(12, 2, 5 * SEC, 3 * SEC, 6 * SEC),
        ]),
        &[10, 12],
    )
}

#[test]
fn a_sound_dragged_to_an_empty_track_goes_alone_and_then_leads_cleanly() {
    let pairs = consecutive().value();
    assert_eq!(track(&pairs, 101), 1);
    let moved = consecutive().apply(&json!({"op": "move_clip", "clips": [101], "delta": 0,
                                            "track": 3}));
    let value = moved.value();
    assert_eq!(track(&value, 101), 3, "the sound changes track");
    assert_eq!(track(&value, 12), 2, "its picture stays on its own");
    assert_eq!(start(&value, 12), 5 * SEC);

    // On a track of its own, a half-second lead overlaps nothing, so the
    // sound gains no transition.
    let led = moved
        .apply(
            &json!({"op": "trim_start", "clip": 101, "to": 5 * SEC - SEC / 2,
                       "alone": true}),
        )
        .value();
    assert_eq!(start(&led, 101), 5 * SEC - SEC / 2);
    assert_eq!(start(&led, 12), 5 * SEC);
    assert!(at(clip(&led, 101), "/transition_in").is_null());
    assert_eq!(clip(&led, 101)["linked"], json!(12));
}

#[test]
fn a_picture_moved_up_a_track_lands_on_the_track_asked_for() {
    // The anchor is the CALLER's clip: the picture's track, not its
    // sound's, so a move to the front track lands there.
    let pairs = detach(project(vec![shot(10, 2, 2 * SEC, 3 * SEC, 0)]), &[10]);
    let after = pairs
        .apply(&json!({"op": "move_clip", "clips": [10], "delta": 0, "track": 3}))
        .value();
    assert_eq!((track(&after, 10), track(&after, 100)), (3, 1));
}

#[test]
fn a_j_cut_near_zero_keeps_its_lead_when_the_picture_is_dragged_left() {
    let pairs = detach(project(vec![shot(10, 2, SEC, 3 * SEC, 2 * SEC)]), &[10]);
    let j = pairs.apply(&json!({"op": "trim_start", "clip": 100, "to": SEC / 2,
                                "alone": true}));
    let after = j
        .apply(&json!({"op": "move_clip", "clips": [10], "delta": -5 * SEC}))
        .value();
    assert_eq!(start(&after, 100), 0, "the sound stops at 0");
    assert_eq!(start(&after, 10), SEC / 2, "the lead is kept");
}

/// A J-cut 0.8 s deep under a picture at 1 s, after a one-second clip
/// (20) on the picture's track: anything that closes that second takes
/// the sound below 0.
fn leading() -> Handle {
    let pairs = detach(
        project(vec![
            shot(20, 2, 0, SEC, 0),
            shot(10, 2, SEC, 3 * SEC, 2 * SEC),
        ]),
        &[10],
    );
    pairs.apply(&json!({"op": "trim_start", "clip": 100, "to": SEC / 5, "alone": true}))
}

fn floor() -> String {
    format!(
        "clip 100 would start before 0: it leads its linked clip 10 by {} ticks",
        SEC - SEC / 5
    )
}

#[test]
fn a_ripple_that_would_push_a_leading_sound_below_zero_refuses() {
    leading().refuses_with(&json!({"op": "ripple_delete", "clips": [20]}), &floor());
}

#[test]
fn a_range_ripple_cuts_the_lead_it_covers_and_keeps_the_rest_in_step() {
    // The range form cuts the sound at the range's end, removes the lead
    // inside it, and closes: the second half, linked to the picture, moves
    // with it to 0.
    let after = leading()
        .apply(&json!({"op": "ripple_delete_range", "from": 0, "to": SEC}))
        .value();
    assert_eq!(start(&after, 10), 0);
    let sound = clip(&after, 10)["linked"].as_u64().expect("still linked");
    assert_eq!(start(&after, sound), 0);
    assert_eq!(clip(&after, sound)["linked"], json!(10));
}

#[test]
fn closing_the_gap_before_a_leading_sound_refuses() {
    let j = leading().apply(&json!({"op": "delete", "clips": [20]}));
    j.refuses_with(
        &json!({"op": "close_gap", "track": 2, "at": SEC / 2}),
        &floor(),
    );
}

#[test]
fn a_ripple_transition_that_would_push_a_leading_sound_below_zero_refuses() {
    // Half a second of overlap moves the picture to 0.5 s and the sound to
    // −0.3 s.
    leading().refuses_with(
        &json!({"op": "add_transition", "clip": 10, "duration": SEC / 2, "ripple": true}),
        &floor(),
    );
}

#[test]
fn a_ripple_with_room_moves_the_pair_together() {
    let pairs = detach(
        project(vec![
            shot(20, 2, 0, SEC, 0),
            shot(10, 2, 2 * SEC, 3 * SEC, 2 * SEC),
        ]),
        &[10],
    );
    let j = pairs.apply(
        &json!({"op": "trim_start", "clip": 100, "to": 2 * SEC - 15 * FRAME,
                                "alone": true}),
    );
    let after = j
        .apply(&json!({"op": "ripple_delete", "clips": [20]}))
        .value();
    assert_eq!(start(&after, 10), SEC);
    assert_eq!(start(&after, 100), SEC - 15 * FRAME);
}

#[test]
fn delete_and_ripple_delete_take_what_the_half_you_grab_decides() {
    let pairs = detach(project(vec![shot(10, 2, 0, 3 * SEC, 0)]), &[10]);
    let sound_alone = pairs
        .apply(&json!({"op": "delete", "clips": [100]}))
        .value();
    assert!(has(&sound_alone, 10) && !has(&sound_alone, 100));
    assert!(clip(&sound_alone, 10).get("linked").is_none());
    assert_eq!(at(clip(&sound_alone, 10), "/enabled/audio"), &json!(false));

    let picture = pairs.apply(&json!({"op": "delete", "clips": [10]})).value();
    assert!(!has(&picture, 10) && !has(&picture, 100));

    let rippled = pairs
        .apply(&json!({"op": "ripple_delete", "clips": [100]}))
        .value();
    assert!(!has(&rippled, 10) && !has(&rippled, 100));
}

#[test]
fn a_split_of_both_consecutive_pairs_at_their_cut_changes_nothing() {
    // The cut between the two shots is a boundary, not an inside point, so
    // nothing is cut and the links stand.
    let pairs = consecutive();
    assert!(matches!(
        pairs.try_apply(&json!({"op": "split", "clips": [10, 12], "at": 5 * SEC})),
        Ok(common::Outcome::Identity)
    ));
}
