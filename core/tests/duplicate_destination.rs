//! `duplicate`'s destination (spec §11 #465): `delta` and `track`, what
//! ⌥-drag sends, read as `move_clip` reads them. The overlap rule is asked
//! once, at the landing; the track shift is anchored on and applied to the
//! clips NAMED, so an unnamed linked partner's copy keeps its track (AU-91)
//! and still counts for the rule.
//!
//! Every pair here is made by `detach_audio` itself, so the link under test
//! is the one the product writes.

mod common;

use common::{array, assert_contains, by_id, int, Handle};
use serde_json::{json, Value};

const SEC: i64 = 600_000;

fn shot(id: u32, track: u32, start: i64, duration: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "media", "media": 9, "in": 5 * SEC},
           "video": {}, "audio": {}})
}

/// Tracks 1 (back), 2 and 3 (front); `clips` on them; next id 100.
fn project(clips: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 28,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 9, "path": "/fixtures/talk.mov", "kind": "video",
                   "duration": 60 * SEC, "width": 1920, "height": 1080,
                   "fps": [30, 1], "has_video": true, "has_audio": true}],
        "tracks": [{"id": 1, "name": "A"}, {"id": 2, "name": "B"}, {"id": 3, "name": "C"}],
        "clips": clips,
        "next_id": 100
    }))
}

/// Clips 10 and 11 back to back on track 2, the first of a run.
fn run() -> Handle {
    project(vec![shot(10, 2, 0, 5 * SEC), shot(11, 2, 5 * SEC, 5 * SEC)])
}

/// Picture 10 on track 2 at `start`, its sound on track 1: (the project, the
/// sound's id).
fn pair(start: i64) -> (Handle, u64) {
    let linked = project(vec![shot(10, 2, start, 5 * SEC)])
        .apply(&json!({"op": "detach_audio", "clip": 10}));
    let sound = int(by_id(&linked.value(), "/clips", 10), "/linked") as u64;
    assert_eq!(
        track(&linked.value(), sound),
        1,
        "the sound is on the back lane"
    );
    (linked, sound)
}

fn start(project: &Value, id: u64) -> i64 {
    int(by_id(project, "/clips", id), "/start")
}

fn track(project: &Value, id: u64) -> i64 {
    int(by_id(project, "/clips", id), "/track")
}

/// The clips `after` has and `before` had not, as (track, start).
fn landed(before: &Value, after: &Value) -> Vec<(i64, i64)> {
    let known: Vec<i64> = array(before, "/clips")
        .iter()
        .map(|c| int(c, "/id"))
        .collect();
    let mut out: Vec<(i64, i64)> = array(after, "/clips")
        .iter()
        .filter(|c| !known.contains(&int(c, "/id")))
        .map(|c| (int(c, "/track"), int(c, "/start")))
        .collect();
    out.sort_unstable();
    out
}

#[test]
fn the_first_of_a_run_copies_to_where_the_rule_allows() {
    let project = run();
    // One span later is on top of clip 11: the bare op is refused, as ever.
    project.refuses_with(
        &json!({"op": "duplicate", "clips": [10]}),
        "clips 11 and 100 would overlap by 3000000 ticks, more than half of the shorter clip (1500000 ticks)",
    );
    let after = project
        .apply(&json!({"op": "duplicate", "clips": [10], "delta": 12 * SEC, "track": 3}))
        .value();
    assert_eq!(landed(&project.value(), &after), [(3, 12 * SEC)]);
    assert_eq!((start(&after, 10), track(&after, 10)), (0, 2));
    assert_eq!((start(&after, 11), track(&after, 11)), (5 * SEC, 2));

    let along = project
        .apply(&json!({"op": "duplicate", "clips": [10], "delta": 20 * SEC}))
        .value();
    assert_eq!(landed(&project.value(), &along), [(2, 20 * SEC)]);
}

#[test]
fn a_delta_of_nothing_on_the_same_tracks_reaches_the_rule() {
    run().refuses(&json!({"op": "duplicate", "clips": [10], "delta": 0}));
}

#[test]
fn the_anchor_is_the_back_most_clip_named() {
    let project = project(vec![shot(10, 1, 0, 5 * SEC), shot(11, 2, 0, 5 * SEC)]);
    let after = project
        .apply(&json!({"op": "duplicate", "clips": [11, 10], "delta": 6 * SEC, "track": 2}))
        .value();
    assert_eq!(
        landed(&project.value(), &after),
        [(2, 6 * SEC), (3, 6 * SEC)],
        "two lanes stay two lanes, the back-most clip on the destination"
    );
}

#[test]
fn an_unnamed_partners_copy_keeps_its_track_and_the_one_delta() {
    let (project, sound) = pair(0);
    let before = project.value();
    let after = project
        .apply(&json!({"op": "duplicate", "clips": [10], "delta": 12 * SEC, "track": 3}))
        .value();
    assert_eq!(
        landed(&before, &after),
        [(1, 12 * SEC), (3, 12 * SEC)],
        "the picture's copy on the destination, the sound's on the sound's lane"
    );
    let copies: Vec<&Value> = array(&after, "/clips")
        .iter()
        .filter(|c| int(c, "/id") as u64 != 10 && int(c, "/id") as u64 != sound)
        .collect();
    assert_eq!(copies.len(), 2);
    assert_eq!(int(copies[0], "/linked"), int(copies[1], "/id"));
    assert_eq!(int(copies[1], "/linked"), int(copies[0], "/id"));
}

#[test]
fn both_halves_named_move_together_from_the_back_most() {
    let (project, sound) = pair(0);
    let before = project.value();
    let after = project
        .apply(&json!({"op": "duplicate", "clips": [10, sound], "delta": 12 * SEC, "track": 2}))
        .value();
    assert_eq!(landed(&before, &after), [(2, 12 * SEC), (3, 12 * SEC)]);
}

#[test]
fn a_partners_copy_counts_for_the_overlap_rule() {
    // The picture straight up at no time delta: its lane is free, its
    // sound's copy would sit on the sound.
    let (project, _) = pair(0);
    project.refuses_with(
        &json!({"op": "duplicate", "clips": [10], "delta": 0, "track": 3}),
        "clips 100 and 102 would overlap by 3000000 ticks, more than half of the shorter clip (1500000 ticks)",
    );
}

#[test]
fn a_copy_off_the_track_list_is_refused_in_move_clips_sentence() {
    let project = project(vec![shot(10, 2, 0, 5 * SEC), shot(11, 3, 0, 5 * SEC)]);
    let sentence = "clip 11 would land on track index 3, which is out of range (0..3)";
    project.refuses_with(
        &json!({"op": "move_clip", "clips": [10, 11], "delta": 6 * SEC, "track": 3}),
        sentence,
    );
    project.refuses_with(
        &json!({"op": "duplicate", "clips": [10, 11], "delta": 6 * SEC, "track": 3}),
        sentence,
    );
}

#[test]
fn an_unknown_track_is_an_error() {
    assert_contains(
        &run().errors(&json!({"op": "duplicate", "clips": [10], "delta": 12 * SEC, "track": 77})),
        "no track with id 77",
    );
}

#[test]
fn the_clamp_at_zero_is_taken_over_the_closure() {
    // A J-cut: the sound leads the picture by a second.
    let (linked, sound) = pair(20 * SEC);
    let project = linked.apply(&json!({
        "op": "trim_start", "clip": sound, "to": 19 * SEC, "alone": true
    }));
    let before = project.value();
    assert_eq!(start(&before, sound), 19 * SEC);
    let after = project
        .apply(&json!({"op": "duplicate", "clips": [10], "delta": -100 * SEC}))
        .value();
    assert_eq!(
        landed(&before, &after),
        [(1, 0), (2, SEC)],
        "the sound's copy stops at 0 and the picture keeps its second"
    );
}
