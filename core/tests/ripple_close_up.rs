//! `ripple_delete {clips}` closes up to the neighbour that begins inside a
//! removed clip, and is refused when a track it moved breaks THE overlap
//! rule (spec §11 #601), through the FFI.
//!
//! The fixture is the issue's: on track 8, A [0, 4 s), B [3 s, 8 s), C [7 s,
//! 12 s), D [12 s, 20 s), B and C each dissolving in. Ripple-deleting B used
//! to shift by B's 5 s at 8 s, leaving C at 7 s (it starts inside B) and
//! sliding D to 7 s, wholly under it. Every number below is computed here, by
//! hand, and every applied answer is held to the tests' own oracle
//! (`common/overlap_oracle.rs`), never to the core's rule.

mod common;
#[path = "common/overlap_oracle.rs"]
mod overlap_oracle;

use common::{by_id, int, Handle};
use overlap_oracle::overlap_rule_holds;
use serde_json::{json, Value};

/// Ticks per second (spec §5.1).
const SEC: i64 = 600_000;

const A: u32 = 10;
const B: u32 = 11;
const C: u32 = 12;
const D: u32 = 13;

/// The main track, a second unlocked one, and a locked one.
const MAIN: u32 = 8;
const OTHER: u32 = 9;
const LOCKED: u32 = 7;

fn media() -> Value {
    json!({"id": 1, "path": "/fixtures/v1.mov", "kind": "video", "duration": 600 * SEC,
           "width": 1920, "height": 1080, "fps": [30, 1],
           "has_video": true, "has_audio": true})
}

/// A media clip, each reading its own stretch of the one long file.
fn clip(id: u32, track: u32, start: i64, duration: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "media", "media": 1, "in": i64::from(id) * 10 * SEC},
           "video": {}, "audio": {}})
}

/// `clip` with a cross dissolve into it.
fn dissolving(id: u32, track: u32, start: i64, duration: i64) -> Value {
    let mut c = clip(id, track, start, duration);
    c["transition_in"] = json!({"kind": "cross_dissolve"});
    c
}

/// A detached picture and its sound, naming each other (AU-90).
fn linked(mut picture: Value, mut sound: Value) -> [Value; 2] {
    picture["enabled"] = json!({"video": true, "audio": false});
    sound["enabled"] = json!({"video": false, "audio": true});
    if let Some(fields) = sound.as_object_mut() {
        fields.remove("video");
    }
    picture["linked"] = sound["id"].clone();
    sound["linked"] = picture["id"].clone();
    [picture, sound]
}

fn project(clips: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 37,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [media()],
        "tracks": [{"id": MAIN, "name": "Main"}, {"id": OTHER, "name": "Other"},
                   {"id": LOCKED, "name": "Locked", "locked": true}],
        "clips": clips,
        "next_id": 100
    }))
}

/// The issue's track: A, B, C, D, with B and C dissolving in.
fn issue_track() -> Vec<Value> {
    vec![
        clip(A, MAIN, 0, 4 * SEC),
        dissolving(B, MAIN, 3 * SEC, 5 * SEC),
        dissolving(C, MAIN, 7 * SEC, 5 * SEC),
        clip(D, MAIN, 12 * SEC, 8 * SEC),
    ]
}

fn with(mut clips: Vec<Value>, more: impl IntoIterator<Item = Value>) -> Vec<Value> {
    clips.extend(more);
    clips
}

fn ripple(ids: &[u32]) -> Value {
    json!({"op": "ripple_delete", "clips": ids})
}

/// The op applied, its answer held to the overlap oracle.
fn applied(handle: &Handle, op: &Value) -> Value {
    let value = handle.apply(op).value();
    assert!(
        overlap_rule_holds(&value),
        "{op} applied and broke the overlap rule: {value}"
    );
    value
}

/// The op refused in exactly `sentence`, and the project as it was.
fn refused(handle: &Handle, op: &Value, sentence: &str) {
    let before = handle.to_json();
    handle.refuses_with(op, sentence);
    assert_eq!(handle.to_json(), before, "a refusal changed the handle");
}

/// Each named clip's start, in the order named; a removed clip is absent.
fn starts(project: &Value, ids: &[u32]) -> Vec<i64> {
    ids.iter()
        .map(|id| int(by_id(project, "/clips", u64::from(*id)), "/start"))
        .collect()
}

fn ids(project: &Value) -> Vec<u64> {
    let mut out: Vec<u64> = project["clips"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["id"].as_u64().unwrap())
        .collect();
    out.sort_unstable();
    out
}

/// THE overlap rule's sentence for a pair past the half-shorter limit.
fn past_limit(earlier: u32, later: u32, overlap: i64, limit: i64) -> String {
    format!(
        "clips {earlier} and {later} would overlap by {overlap} ticks, more than half of the \
         shorter clip ({limit} ticks)"
    )
}

// ---- R1: transitions on both sides, the issue -----------------------------

#[test]
fn r1_the_issue_closes_up_to_c_and_every_unlocked_track_moves_by_4_s() {
    let e = 20;
    let l = 30;
    let handle = project(with(
        issue_track(),
        [
            clip(e, OTHER, 12 * SEC, 3 * SEC),
            clip(l, LOCKED, 12 * SEC, 3 * SEC),
        ],
    ));
    let after = applied(&handle, &ripple(&[B]));
    // The span is [3 s, 7 s): C to 3 s, D to 8 s, the other unlocked track
    // by 4 s (not B's 5 s), the locked one not at all.
    assert_eq!(
        starts(&after, &[A, C, D, e, l]),
        vec![0, 3 * SEC, 8 * SEC, 8 * SEC, 12 * SEC]
    );
    assert_eq!(ids(&after), vec![10, 12, 13, 20, 30]);
    // C keeps its own stored dissolve, now over the second A had with B.
    let c = by_id(&after, "/clips", u64::from(C));
    assert_eq!(c["transition_in"]["kind"], "cross_dissolve");
    assert!(by_id(&after, "/clips", u64::from(D))["transition_in"].is_null());
}

// ---- R2: a transition out only --------------------------------------------

#[test]
fn r2_a_first_clip_with_a_transition_out_closes_up_to_its_neighbour() {
    let handle = project(vec![
        clip(B, MAIN, 0, 5 * SEC),
        dissolving(C, MAIN, 4 * SEC, 5 * SEC),
        clip(D, MAIN, 9 * SEC, 6 * SEC),
    ]);
    let after = applied(&handle, &ripple(&[B]));
    assert_eq!(starts(&after, &[C, D]), vec![0, 5 * SEC]);
}

// ---- R3: no transition out, the shift unchanged ---------------------------

#[test]
fn r3_with_no_clip_beginning_inside_the_shift_is_still_the_clips_length() {
    // C begins after B's end, past a one-second gap: no pull-back, so the
    // shift is B's 5 s at 9 s and the gap survives.
    let e = 20;
    let handle = project(vec![
        clip(A, MAIN, 0, 4 * SEC),
        clip(B, MAIN, 4 * SEC, 5 * SEC),
        clip(C, MAIN, 10 * SEC, 5 * SEC),
        clip(e, OTHER, 12 * SEC, 3 * SEC),
    ]);
    let after = applied(&handle, &ripple(&[B]));
    assert_eq!(starts(&after, &[A, C, e]), vec![0, 5 * SEC, 7 * SEC]);
}

// ---- R4, R5: a linked pair ------------------------------------------------

/// The issue's track with B a picture linked to sound S on the other
/// track, S followed there by `next` (given as a whole clip).
fn pair_fixture(next: Value, before: Option<Value>) -> Handle {
    let s = 21;
    let [picture, sound] = linked(
        dissolving(B, MAIN, 3 * SEC, 5 * SEC),
        clip(s, OTHER, 3 * SEC, 5 * SEC),
    );
    let mut clips = vec![
        clip(A, MAIN, 0, 4 * SEC),
        picture,
        dissolving(C, MAIN, 7 * SEC, 5 * SEC),
        clip(D, MAIN, 12 * SEC, 8 * SEC),
        sound,
        next,
    ];
    clips.extend(before);
    project(clips)
}

#[test]
fn r4_a_pair_whose_halves_stop_apart_closes_to_the_first_stop_either_half_named() {
    // The picture dissolves into C at 7 s; the sound butts Q at 8 s. The
    // span ends at 7 s on both tracks, so Q lands at 4 s, a one-second gap
    // after the hole's start: the second the picture's dissolve covers.
    let q = 22;
    for named in [B, 21] {
        let handle = pair_fixture(clip(q, OTHER, 8 * SEC, 8 * SEC), None);
        let after = applied(&handle, &ripple(&[named]));
        assert_eq!(
            starts(&after, &[A, C, D, q]),
            vec![0, 3 * SEC, 8 * SEC, 4 * SEC],
            "named {named}"
        );
        assert_eq!(ids(&after), vec![10, 12, 13, 22], "named {named}");
    }
}

#[test]
fn r5_a_pair_dissolving_at_the_same_second_on_both_tracks_moves_everything_by_4_s() {
    // The sound S [3 s, 8 s) follows P [0, 4 s) and crossfades into Q at
    // 7 s, as the picture does into C: Q lands on P as C lands on A.
    let (p, q) = (23, 22);
    let handle = pair_fixture(
        dissolving(q, OTHER, 7 * SEC, 8 * SEC),
        Some(clip(p, OTHER, 0, 4 * SEC)),
    );
    let after = applied(&handle, &ripple(&[B]));
    assert_eq!(
        starts(&after, &[A, C, D, p, q]),
        vec![0, 3 * SEC, 8 * SEC, 0, 3 * SEC]
    );
}

// ---- R6: several removed clips, one span ----------------------------------

#[test]
fn r6_a_removed_neighbour_is_not_a_stop_and_the_span_closes_to_the_survivor() {
    // B and C both removed: C, which begins inside B, is not a survivor.
    // D begins inside C at 11 s, so the one span [3 s, 12 s) closes to 11 s
    // and D lands on A at 3 s.
    let handle = project(vec![
        clip(A, MAIN, 0, 4 * SEC),
        dissolving(B, MAIN, 3 * SEC, 5 * SEC),
        dissolving(C, MAIN, 7 * SEC, 5 * SEC),
        dissolving(D, MAIN, 11 * SEC, 9 * SEC),
    ]);
    let after = applied(&handle, &ripple(&[B, C]));
    assert_eq!(starts(&after, &[A, D]), vec![0, 3 * SEC]);
    assert_eq!(ids(&after), vec![10, 13]);
}

#[test]
fn r6_two_tracks_stopping_apart_in_one_span_close_to_the_earlier_stop() {
    // B [3 s, 8 s) with C inside it at 7 s; X [3 s, 9 s) on the other track
    // with Y inside it at 6 s. One span [3 s, 9 s), closed to 6 s: 3 s on
    // every track, C butting A at 4 s and Y at 3 s.
    let (x, y) = (20, 21);
    let handle = project(with(
        issue_track(),
        [
            clip(x, OTHER, 3 * SEC, 6 * SEC),
            dissolving(y, OTHER, 6 * SEC, 8 * SEC),
        ],
    ));
    let after = applied(&handle, &ripple(&[B, x]));
    assert_eq!(
        starts(&after, &[A, C, D, y]),
        vec![0, 4 * SEC, 9 * SEC, 3 * SEC]
    );
}

// ---- R7: a removed clip on a locked track ---------------------------------

#[test]
fn r7_a_removed_clip_on_a_locked_track_pulls_nothing_back() {
    // B is named on the locked track and goes; C, beginning inside it,
    // cannot move, so the other tracks close B's full 5 s.
    let e = 20;
    let handle = project(vec![
        dissolving(B, LOCKED, 3 * SEC, 5 * SEC),
        dissolving(C, LOCKED, 7 * SEC, 5 * SEC),
        clip(e, MAIN, 10 * SEC, 5 * SEC),
    ]);
    let after = applied(&handle, &ripple(&[B]));
    assert_eq!(starts(&after, &[C, e]), vec![7 * SEC, 5 * SEC]);
}

// ---- R8: the backstop -----------------------------------------------------

#[test]
fn r8_another_tracks_clip_sliding_under_a_straddler_is_refused_whole() {
    // X [5 s, 10 s) straddles 7 s and stays; Y moves 4 s to 6 s, under X by
    // 4 s against half of X's 5 s.
    let (x, y) = (20, 21);
    let handle = project(with(
        issue_track(),
        [
            clip(x, OTHER, 5 * SEC, 5 * SEC),
            clip(y, OTHER, 10 * SEC, 10 * SEC),
        ],
    ));
    refused(
        &handle,
        &ripple(&[B]),
        &past_limit(x, y, 4 * SEC, 5 * SEC / 2),
    );
}

#[test]
fn r8_a_successor_too_short_for_the_overlap_it_inherits_is_refused() {
    // C [7.5 s, 9 s), 1.5 s, dissolving out of B by 0.5 s: closed up to
    // 7.5 s it lands at 3 s, under A by 1 s against half of its 1.5 s.
    let handle = project(vec![
        clip(A, MAIN, 0, 4 * SEC),
        dissolving(B, MAIN, 3 * SEC, 5 * SEC),
        dissolving(C, MAIN, 15 * SEC / 2, 3 * SEC / 2),
    ]);
    refused(&handle, &ripple(&[B]), &past_limit(A, C, SEC, 3 * SEC / 4));
}

#[test]
fn r8_an_adjustment_clip_a_shift_brings_into_an_overlap_is_refused_in_its_sentence() {
    // An adjustment clip X [5 s, 10 s) straddles 7 s; Y slides under it by
    // 4 s, and an adjustment clip cannot take the transition an overlap is.
    let (x, y) = (20, 21);
    let adjustment = json!({"id": x, "track": OTHER, "start": 5 * SEC, "duration": 5 * SEC,
                            "source": {"kind": "adjustment"}, "video": {}});
    let handle = project(with(
        issue_track(),
        [adjustment, clip(y, OTHER, 10 * SEC, 10 * SEC)],
    ));
    refused(
        &handle,
        &ripple(&[B]),
        &format!(
            "clips {x} and {y} would overlap, and clip {x} is an adjustment clip, which cannot \
             take a transition; fade it with opacity instead"
        ),
    );
}

// ---- R9: only the tracks it moved are judged ------------------------------

#[test]
fn r9_a_track_already_past_the_limit_that_the_ripple_does_not_move_is_not_judged() {
    // P [0, 4 s) and Q [1 s, 5 s) on the other track overlap by 3 s, past
    // half of 4 s; nothing there starts at or after 7 s, so nothing moves.
    let (p, q) = (20, 21);
    let handle = project(with(
        issue_track(),
        [clip(p, OTHER, 0, 4 * SEC), clip(q, OTHER, SEC, 4 * SEC)],
    ));
    let after = handle.apply(&ripple(&[B])).value();
    assert_eq!(
        starts(&after, &[A, C, D, p, q]),
        vec![0, 3 * SEC, 8 * SEC, 0, SEC]
    );
}

#[test]
fn r9_a_moved_track_already_past_the_limit_refuses_in_the_rules_sentence() {
    // The same P and Q, and R at 10 s, which the ripple moves: the track is
    // judged whole and P and Q answer the rule's own sentence.
    let (p, q, r) = (20, 21, 22);
    let handle = project(with(
        issue_track(),
        [
            clip(p, OTHER, 0, 4 * SEC),
            clip(q, OTHER, SEC, 4 * SEC),
            clip(r, OTHER, 10 * SEC, 5 * SEC),
        ],
    ));
    refused(&handle, &ripple(&[B]), &past_limit(p, q, 3 * SEC, 2 * SEC));
}
