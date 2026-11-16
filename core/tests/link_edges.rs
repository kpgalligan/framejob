//! The named edge cases of linked pairs (spec §11 AU-91, AU-93): two
//! consecutive detached shots, a J-cut near 0, the shift floor's refusal in
//! each op that shifts, what `delete` and `ripple_delete` take, whose
//! duck a pair's is (AU-157), and an insert or overwrite on the SOUND's track
//! cutting the linked picture (AU-92, #414) unless its track is locked.
//!
//! Every pair here is made by `detach_audio` itself, so the link under test
//! is the one the product writes.

mod common;

use common::{array, at, by_id, int, num, Handle};
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

// ---- whose duck a pair's is (spec §11 AU-157) -------------------------------

const VOICE: u32 = 10;
const SOUND: u32 = 100;
const BED: u32 = 20;
/// Inside the voice's 2–12 s, past its attack.
const DUCKED: i64 = 6 * SEC;

fn duck() -> Value {
    json!({"level": 0.2, "attack": 300_000, "release": 600_000})
}

fn set_duck(clip: u32, duck: Value) -> Value {
    json!({"op": "set_audio", "clips": [clip], "patch": {"duck": duck}})
}

/// The voice (clip 10, 2–12 s, ducking) on track 3 over a 20 s bed (clip 20)
/// on track 1, with track 2 empty for its sound.
fn ducking() -> Handle {
    project(vec![
        shot(BED, 1, 0, 20 * SEC, 0),
        shot(VOICE, 3, 2 * SEC, 10 * SEC, 0),
    ])
    .apply(&set_duck(VOICE, duck()))
}

/// The gain the plan gives `clip` at `t`: its composition audio track's ramp
/// there, from the right.
fn gain(handle: &Handle, clip: u32, t: i64) -> f64 {
    let plan = handle.plan();
    let track = array(&plan, "/audio_tracks")
        .iter()
        .find(|track| {
            array(track, "/segments")
                .iter()
                .any(|s| s["clip"] == json!(clip))
        })
        .unwrap_or_else(|| panic!("no audio track carries clip {clip}: {plan}"));
    for ramp in array(track, "/ramps") {
        let (start, duration) = (int(ramp, "/start"), int(ramp, "/duration"));
        if start <= t && t < start + duration {
            let (from, to) = (num(ramp, "/from"), num(ramp, "/to"));
            return from + (to - from) * ((t - start) as f64 / duration as f64);
        }
    }
    panic!("no ramp covers {t}: {track}");
}

#[test]
fn detach_leaves_the_duck_on_the_sound_half_alone() {
    let pair = detach(ducking(), &[VOICE]).value();
    assert!(
        clip(&pair, 10)["audio"]["duck"].is_null(),
        "the picture keeps no duck: {}",
        clip(&pair, 10)
    );
    assert_eq!(num(clip(&pair, 100), "/audio/duck/level"), 0.2);
    assert_eq!(int(clip(&pair, 100), "/audio/duck/attack"), 300_000);
}

#[test]
fn a_detached_ducker_keeps_its_sound_and_ducks_the_bed_once() {
    let attached = ducking();
    assert_eq!(gain(&attached, VOICE, DUCKED), 1.0);
    assert_eq!(gain(&attached, BED, DUCKED), 0.2);
    let pair = detach(attached, &[VOICE]);
    assert_eq!(gain(&pair, SOUND, DUCKED), 1.0, "its own sound is whole");
    assert_eq!(gain(&pair, BED, DUCKED), 0.2, "the bed is ducked once");
}

#[test]
fn attach_keeps_the_sound_halfs_duck() {
    let back = detach(ducking(), &[VOICE]).apply(&json!({"op": "attach_audio", "clip": VOICE}));
    assert_eq!(num(clip(&back.value(), 10), "/audio/duck/level"), 0.2);
    assert_eq!(gain(&back, VOICE, DUCKED), 1.0);
    assert_eq!(gain(&back, BED, DUCKED), 0.2);
}

#[test]
fn a_stale_duck_on_a_picture_half_ducks_nothing() {
    let stale = detach(ducking(), &[VOICE]).apply(&set_duck(VOICE, duck()));
    assert_eq!(num(clip(&stale.value(), 10), "/audio/duck/level"), 0.2);
    assert_eq!(gain(&stale, SOUND, DUCKED), 1.0);
    assert_eq!(gain(&stale, BED, DUCKED), 0.2);

    // With the sound's own duck off, the picture's is all there is.
    let alone = stale.apply(&set_duck(SOUND, Value::Null));
    assert_eq!(gain(&alone, SOUND, DUCKED), 1.0);
    assert_eq!(gain(&alone, BED, DUCKED), 1.0);
}

#[test]
fn a_stale_duck_inside_a_nest_ducks_nothing() {
    // `nest` takes the pair whole. `Project::clip` cannot see into the nest
    // from the flattened timeline, which is why the rule reads the clip alone.
    let nested = detach(ducking(), &[VOICE])
        .apply(&set_duck(VOICE, duck()))
        .apply(&set_duck(SOUND, Value::Null))
        .apply(&json!({"op": "nest", "clips": [VOICE]}));
    let plain = nested.value();
    assert_eq!(array(&plain, "/nests").len(), 1);
    assert_eq!(
        array(&plain, "/nests/0/clips").len(),
        2,
        "the pair is inside"
    );
    assert_eq!(gain(&nested, BED, DUCKED), 1.0);
}

#[test]
fn a_sound_half_switched_off_still_ducks() {
    let quiet = detach(ducking(), &[VOICE])
        .apply(&json!({"op": "set_enabled", "clip": SOUND, "audio": false}));
    assert_eq!(gain(&quiet, BED, DUCKED), 0.2);
}

#[test]
fn an_unlinked_clip_with_its_audio_off_still_ducks() {
    let quiet = ducking().apply(&json!({"op": "set_enabled", "clip": VOICE, "audio": false}));
    assert!(clip(&quiet.value(), 10).get("linked").is_none());
    assert_eq!(gain(&quiet, BED, DUCKED), 0.2);
}

// ---- insert and overwrite on the sound's track (AU-92, #414) ------------

/// Picture 10 on track 2 and its detached sound 100 on track 1, both
/// 2 s – 8 s, with media 8, two seconds of roll, to bring in.
fn pair_and_roll() -> Handle {
    let pair = detach(project(vec![shot(10, 2, 2 * SEC, 6 * SEC, 0)]), &[10]);
    let mut value = pair.value();
    value["media"].as_array_mut().unwrap().push(json!(
        {"id": 8, "path": "/fixtures/roll.mov", "kind": "video", "duration": 2 * SEC,
         "width": 1920, "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": true}
    ));
    Handle::from_value(&value)
}

fn span(project: &Value, id: u64) -> (i64, i64) {
    (start(project, id), int(clip(project, id), "/duration"))
}

fn linked(project: &Value, id: u64) -> Option<i64> {
    clip(project, id).get("linked").and_then(Value::as_i64)
}

#[test]
fn an_insert_on_the_sounds_track_cuts_the_linked_picture() {
    let before = pair_and_roll().value();
    assert_eq!((track(&before, 10), track(&before, 100)), (2, 1));
    let after = pair_and_roll()
        .apply(&json!({"op": "insert_clip", "track": 1, "media": 8, "at": 4 * SEC}))
        .value();
    // 101 is the sound's second half, 102 the picture's, 103 the new clip.
    assert_eq!(span(&after, 100), (2 * SEC, 2 * SEC));
    assert_eq!(
        span(&after, 10),
        (2 * SEC, 2 * SEC),
        "the picture is cut too"
    );
    assert_eq!(span(&after, 103), (4 * SEC, 2 * SEC));
    assert_eq!(span(&after, 101), (6 * SEC, 4 * SEC));
    assert_eq!(
        span(&after, 102),
        (6 * SEC, 4 * SEC),
        "its tail rides the shift"
    );
    assert_eq!((track(&after, 102), track(&after, 103)), (2, 1));
    assert_eq!(
        (linked(&after, 10), linked(&after, 100)),
        (Some(100), Some(10))
    );
    assert_eq!(
        (linked(&after, 102), linked(&after, 101)),
        (Some(101), Some(102))
    );
}

#[test]
fn an_insert_leaves_a_linked_picture_on_a_locked_track_whole() {
    let locked = pair_and_roll().apply(&json!({"op": "set_track", "track": 2, "locked": true}));
    let after = locked
        .apply(&json!({"op": "insert_clip", "track": 1, "media": 8, "at": 4 * SEC}))
        .value();
    assert_eq!(span(&after, 10), (2 * SEC, 6 * SEC), "not cut, not moved");
    assert_eq!(span(&after, 100), (2 * SEC, 2 * SEC));
    // 101 is the sound's second half, 102 the new clip.
    assert_eq!(span(&after, 101), (6 * SEC, 4 * SEC));
    assert_eq!(span(&after, 102), (4 * SEC, 2 * SEC));
}

#[test]
fn an_overwrite_leaves_a_linked_picture_on_a_locked_track_whole() {
    let locked = pair_and_roll().apply(&json!({"op": "set_track", "track": 2, "locked": true}));
    let after = locked
        .apply(&json!({"op": "overwrite_clip", "track": 1, "media": 8, "at": 4 * SEC}))
        .value();
    assert_eq!(span(&after, 10), (2 * SEC, 6 * SEC), "not cut, not moved");
    assert_eq!(track(&after, 10), 2);
    // The cut at 4 s mints 101 (the sound from 4 s), the cut at 6 s mints
    // 102 (the sound's tail), and 103 is the new clip. No picture is minted.
    assert_eq!(span(&after, 100), (2 * SEC, 2 * SEC));
    assert!(!has(&after, 101), "the sound under the new clip is gone");
    assert_eq!(span(&after, 102), (6 * SEC, 2 * SEC), "nothing moved");
    assert_eq!(span(&after, 103), (4 * SEC, 2 * SEC));
    assert_eq!(
        (track(&after, 100), track(&after, 102), track(&after, 103)),
        (1, 1, 1)
    );
    let clips = array(&after, "/clips");
    assert_eq!(
        clips.len(),
        4,
        "the picture, two sound pieces, the new clip"
    );
    assert_eq!(
        clips.iter().filter(|c| c["track"] == json!(2)).count(),
        1,
        "the locked track holds the picture alone"
    );
    // Each cut left the picture linked to the piece sharing more of its time
    // (the first on a tie): 101 both times, the piece the new clip replaced.
    // So the pair is over, and no clip names another.
    for id in [10, 100, 102, 103] {
        assert_eq!(linked(&after, id), None, "clip {id}");
    }
}

/// The 2 s roll overwritten at `at` onto the sound of a pair whose picture's
/// track is locked.
fn overwrite_on_a_locked_pair(at: i64) -> Value {
    pair_and_roll()
        .apply(&json!({"op": "set_track", "track": 2, "locked": true}))
        .apply(&json!({"op": "overwrite_clip", "track": 1, "media": 8, "at": at}))
        .value()
}

#[test]
fn an_overwrite_keeps_a_locked_pictures_link_only_where_its_cuts_leave_it() {
    // Spec §11 AU-166: each cut links the uncut picture to the half sharing
    // more of its time (the first on a tie), so the link follows the cuts in
    // order, not the longest piece left. The sound is (2 s, 6 s).

    // L 1, M 2, R 3 s: the first cut (3 s) links the half from 3 s (5 s
    // against 1), the second (5 s) the tail (3 s against 2), which stays.
    let after = overwrite_on_a_locked_pair(3 * SEC);
    assert_eq!(span(&after, 10), (2 * SEC, 6 * SEC), "the picture is whole");
    assert!(!has(&after, 101), "the sound under the new clip is gone");
    assert_eq!(span(&after, 102), (5 * SEC, 3 * SEC));
    assert_eq!(span(&after, 103), (3 * SEC, 2 * SEC), "the new clip");
    assert_eq!(
        (linked(&after, 10), linked(&after, 102)),
        (Some(102), Some(10)),
        "the picture keeps the tail"
    );
    assert_eq!((linked(&after, 100), linked(&after, 103)), (None, None));

    // L 2.5, M 2, R 1.5 s: the first cut (4.5 s) links the half from 4.5 s
    // (3.5 s against 2.5), the second (6.5 s) its head, the 2 s under the new
    // clip (2 against 1.5), so the pair is over though L is the longest.
    let after = overwrite_on_a_locked_pair(4 * SEC + SEC / 2);
    assert_eq!(span(&after, 10), (2 * SEC, 6 * SEC), "the picture is whole");
    assert!(!has(&after, 101), "the sound under the new clip is gone");
    assert_eq!(span(&after, 100), (2 * SEC, 2 * SEC + SEC / 2));
    assert_eq!(span(&after, 102), (6 * SEC + SEC / 2, SEC + SEC / 2));
    assert_eq!(
        span(&after, 103),
        (4 * SEC + SEC / 2, 2 * SEC),
        "the new clip"
    );
    for id in [10, 100, 102, 103] {
        assert_eq!(linked(&after, id), None, "clip {id}");
    }

    // L 4, M 2 s, the file ending where the sound ends: one cut (6 s), and
    // the head (4 s against 2) keeps the picture.
    let after = overwrite_on_a_locked_pair(6 * SEC);
    assert_eq!(span(&after, 10), (2 * SEC, 6 * SEC), "the picture is whole");
    assert!(!has(&after, 101), "the sound under the new clip is gone");
    assert_eq!(span(&after, 100), (2 * SEC, 4 * SEC));
    assert_eq!(span(&after, 102), (6 * SEC, 2 * SEC), "the new clip");
    assert_eq!(
        (linked(&after, 10), linked(&after, 100)),
        (Some(100), Some(10)),
        "the picture keeps the head"
    );
    assert_eq!(linked(&after, 102), None);
}

#[test]
fn an_overwrite_on_the_sounds_track_cuts_the_linked_picture_at_both_ends() {
    let after = pair_and_roll()
        .apply(&json!({"op": "overwrite_clip", "track": 1, "media": 8, "at": 4 * SEC}))
        .value();
    // The cut at 4 s mints 101 (sound) and 102 (picture); the cut at 6 s
    // mints 103 (the sound's tail) and 104 (the picture's); 105 is the new
    // clip.
    assert!(!has(&after, 101), "the sound under the new clip is gone");
    assert_eq!(span(&after, 105), (4 * SEC, 2 * SEC));
    assert_eq!(track(&after, 105), 1);
    assert_eq!(span(&after, 10), (2 * SEC, 2 * SEC));
    assert_eq!(span(&after, 102), (4 * SEC, 2 * SEC), "its middle stays");
    assert_eq!(span(&after, 104), (6 * SEC, 2 * SEC));
    assert_eq!(span(&after, 103), (6 * SEC, 2 * SEC), "nothing moved");
    assert_eq!(linked(&after, 102), None, "and is no longer linked");
    assert_eq!(
        (linked(&after, 10), linked(&after, 100)),
        (Some(100), Some(10))
    );
    assert_eq!(
        (linked(&after, 104), linked(&after, 103)),
        (Some(103), Some(104))
    );
}
