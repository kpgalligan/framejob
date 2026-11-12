//! `lift_range` held to the tracks it is given (spec §11 #602), through the
//! FFI.
//!
//! The fixture is #427's, with a second track behind it: A [0, 4 s) and B
//! [3 s, 8 s) dissolving for one second on track 8, and on track 7 C
//! [0, 2.6 s), which a cut at 2.2 s would reach, and D [3 s, 5 s), which a
//! range {2.2 s, 8 s} holds whole. The issue's switch cleared {2.2 s, 8 s}
//! on track 8 with `split`s, and the split at 2.2 s is refused although what
//! the clear leaves, A [0, 2.2 s), is legal. Every expected number is
//! worked here by hand; every applied answer is held to the tests' own
//! overlap oracle, and "a track not named is as a locked one" to the plain
//! lift of the same project with the other tracks locked.

mod common;
#[path = "common/overlap_oracle.rs"]
mod overlap_oracle;

use common::{array, by_id, int, Handle};
use overlap_oracle::overlap_rule_holds;
use serde_json::{json, Value};

/// Ticks per second (spec §5.1).
const SEC: i64 = 600_000;
/// 2.2 s, the issue's range start: 66 frames at 30 fps, on the grid.
const CUT: i64 = 2 * SEC + SEC / 5;

const A: u32 = 10;
const B: u32 = 11;
const C: u32 = 12;
const D: u32 = 13;

fn video(id: u32) -> Value {
    json!({"id": id, "path": format!("/fixtures/v{id}.mov"), "kind": "video",
           "duration": 600 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
           "has_video": true, "has_audio": true})
}

fn clip(id: u32, track: u32, start: i64, duration: i64, r#in: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "media", "media": 1, "in": r#in},
           "video": {}, "audio": {}})
}

fn dissolving(id: u32, track: u32, start: i64, duration: i64, r#in: i64) -> Value {
    let mut c = clip(id, track, start, duration, r#in);
    c["transition_in"] = json!({"kind": "cross_dissolve"});
    c
}

fn project(tracks: Value, clips: Vec<Value>) -> Value {
    json!({
        "version": 37,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [video(1)],
        "tracks": tracks,
        "clips": clips,
        "markers": [],
        "next_id": 100,
        "nests": []
    })
}

fn issue_clips() -> Vec<Value> {
    vec![
        clip(C, 7, 0, 2 * SEC + 3 * SEC / 5, 0),
        clip(D, 7, 3 * SEC, 2 * SEC, 50 * SEC),
        clip(A, 8, 0, 4 * SEC, 0),
        dissolving(B, 8, 3 * SEC, 5 * SEC, 10 * SEC),
    ]
}

fn two_tracks(locked_7: bool) -> Value {
    json!([{"id": 7, "name": "Behind", "locked": locked_7}, {"id": 8, "name": "Program"}])
}

fn issue() -> Handle {
    Handle::from_value(&project(two_tracks(false), issue_clips()))
}

fn lift(from: i64, to: i64, tracks: Value) -> Value {
    json!({"op": "lift_range", "from": from, "to": to, "tracks": tracks})
}

fn plain(from: i64, to: i64) -> Value {
    json!({"op": "lift_range", "from": from, "to": to})
}

/// What a track holds: each clip's id, start and duration, in start order.
fn held(project: &Value, track: i64) -> Vec<(i64, i64, i64)> {
    let mut out: Vec<(i64, i64, i64)> = array(project, "/clips")
        .iter()
        .filter(|c| int(c, "/track") == track)
        .map(|c| (int(c, "/id"), int(c, "/start"), int(c, "/duration")))
        .collect();
    out.sort_by_key(|&(_, start, _)| start);
    out
}

/// The op applied, its answer held to the overlap oracle.
fn applied(handle: &Handle, op: &Value) -> Value {
    let value = handle.apply(op).value();
    assert!(
        overlap_rule_holds(&value),
        "{op} broke the overlap rule: {value}"
    );
    value
}

/// T2's oracle: `tracks: [8]` answers what the plain lift answers on the
/// same project with every other track locked, the locks then put back.
fn as_if_locked(source: &Value, from: i64, to: i64) {
    let named = Handle::from_value(source).apply(&lift(from, to, json!([8])));
    let mut locked = source.clone();
    for track in locked["tracks"].as_array_mut().expect("tracks") {
        if track["id"] != json!(8) {
            track["locked"] = json!(true);
        }
    }
    let mut oracle = Handle::from_value(&locked).apply(&plain(from, to)).value();
    for (index, track) in source["tracks"]
        .as_array()
        .expect("tracks")
        .iter()
        .enumerate()
    {
        oracle["tracks"][index]["locked"] = track.get("locked").cloned().unwrap_or(json!(false));
    }
    assert_eq!(
        named.value(),
        Handle::from_value(&oracle).value(),
        "tracks: [8] over {{{from}, {to}}} is not the plain lift with the others locked"
    );
}

// ---- T1, T2: the issue ----------------------------------------------------

#[test]
fn t1_the_issue_s_range_lifted_on_its_track_applies_and_leaves_the_other_alone() {
    let source = issue();
    // The contrast the issue rests on: the cut alone is the rule's refusal.
    source.refuses_with(
        &json!({"op": "split", "clips": [A], "at": CUT}),
        &format!(
            "clips {A} and {B} would overlap by {SEC} ticks, more than half of the shorter \
             piece the cut leaves ({} ticks); cut further from their transition, or shorten \
             it first",
            (4 * SEC - CUT) / 2
        ),
    );
    let lifted = applied(&source, &lift(CUT, 8 * SEC, json!([8])));
    assert_eq!(held(&lifted, 8), vec![(A as i64, 0, CUT)]);
    assert_eq!(
        held(&lifted, 7),
        held(&source.value(), 7),
        "track 7 was not named, so it keeps exactly what it had"
    );
}

#[test]
fn t2_a_track_not_named_is_as_a_locked_one() {
    let source = project(two_tracks(false), issue_clips());
    as_if_locked(&source, CUT, 8 * SEC);
    as_if_locked(&source, SEC, 6 * SEC);
    let (picture, _) = linked_pair();
    as_if_locked(&picture, 2 * SEC, 4 * SEC);
    as_if_locked(&picture, SEC, 7 * SEC);
}

// ---- T3: no tracks is the plain form --------------------------------------

#[test]
fn t3_absent_and_null_are_every_unlocked_track_as_before() {
    let source = issue();
    let absent = source.apply(&plain(SEC, 6 * SEC)).to_json();
    let null = source.apply(&lift(SEC, 6 * SEC, Value::Null)).to_json();
    assert_eq!(absent, null);
    // The plain form still cuts and clears track 7: C cut at 1 s, D gone.
    let value: Value = serde_json::from_str(&absent).expect("json");
    assert_eq!(held(&value, 7), vec![(C as i64, 0, SEC)]);
}

// ---- T4: a named locked track ---------------------------------------------

#[test]
fn t4_a_named_locked_track_refuses_the_whole_lift() {
    let mut tracks = two_tracks(true);
    tracks
        .as_array_mut()
        .expect("tracks")
        .push(json!({"id": 9, "name": "Also locked", "locked": true}));
    let source = Handle::from_value(&project(tracks, issue_clips()));
    let before = source.to_json();
    let sentence = |id: u32| format!("track {id} is locked, so nothing on it can be lifted");
    source.refuses_with(&lift(CUT, 8 * SEC, json!([7])), &sentence(7));
    // Refused whole, track 8 untouched with it; the first locked in the
    // caller's order is named.
    source.refuses_with(&lift(CUT, 8 * SEC, json!([8, 7])), &sentence(7));
    source.refuses_with(&lift(CUT, 8 * SEC, json!([9, 7])), &sentence(9));
    source.refuses_with(&lift(CUT, 8 * SEC, json!([7, 9])), &sentence(7));
    assert_eq!(source.to_json(), before, "a refusal changed the handle");
    // Not named, the locked track is no obstacle.
    applied(&source, &lift(CUT, 8 * SEC, json!([8])));
}

// ---- T5: an unknown id, an empty list, a repeated id ----------------------

#[test]
fn t5_an_unknown_id_errors_an_empty_list_changes_nothing_a_repeat_counts_once() {
    let source = issue();
    assert_eq!(
        source.errors(&lift(CUT, 8 * SEC, json!([99]))),
        "no track with id 99"
    );
    assert_eq!(
        source.errors(&lift(CUT, 8 * SEC, json!([8, 99]))),
        "no track with id 99"
    );
    // The unknown id is read before any lock.
    let locked = Handle::from_value(&project(two_tracks(true), issue_clips()));
    assert_eq!(
        locked.errors(&lift(CUT, 8 * SEC, json!([7, 99]))),
        "no track with id 99"
    );
    source.refuses(&lift(CUT, 8 * SEC, json!([])));
    assert!(matches!(
        source.try_apply(&lift(CUT, 8 * SEC, json!([]))),
        Ok(common::Outcome::Identity)
    ));
    assert_eq!(
        source.apply(&lift(CUT, 8 * SEC, json!([8, 8]))).to_json(),
        source.apply(&lift(CUT, 8 * SEC, json!([8]))).to_json()
    );
    // A range with nothing on the named track to give up is an identity.
    assert!(matches!(
        source.try_apply(&lift(9 * SEC, 10 * SEC, json!([8]))),
        Ok(common::Outcome::Identity)
    ));
}

// ---- T6: the rule is still asked, on the tracks changed -------------------

#[test]
fn t6_the_overlap_rule_judges_what_the_lift_stores_on_the_tracks_it_changed() {
    // {0, 2.2 s} on track 8 leaves A's piece [2.2 s, 4 s) under B by 1 s.
    issue().refuses_with(
        &lift(0, CUT, json!([8])),
        &format!(
            "clips {A} and {B} would overlap by {SEC} ticks, more than half of the shorter \
             piece the cut leaves ({} ticks); cut further from their transition, or shorten \
             it first",
            (4 * SEC - CUT) / 2
        ),
    );
    // X [0, 1 s) and Y [0.4 s, 10 s) on unlocked track 7 are past the limit,
    // stored so. Not named, track 7 is not judged; the plain lift cuts it
    // and is refused in the rule's own sentence.
    let source = Handle::from_value(&project(
        two_tracks(false),
        vec![
            clip(40, 7, 0, SEC, 0),
            dissolving(41, 7, 2 * SEC / 5, 10 * SEC - 2 * SEC / 5, 10 * SEC),
            clip(A, 8, 0, 4 * SEC, 0),
            dissolving(B, 8, 3 * SEC, 5 * SEC, 10 * SEC),
        ],
    ));
    let lifted = source.apply(&lift(CUT, 8 * SEC, json!([8]))).value();
    assert_eq!(held(&lifted, 8), vec![(A as i64, 0, CUT)]);
    source.refuses_with(
        &plain(CUT, 8 * SEC),
        &format!(
            "clips 40 and 41 would overlap by {} ticks, more than half of the shorter clip \
             ({} ticks)",
            3 * SEC / 5,
            SEC / 2
        ),
    );
}

// ---- T7: a linked partner on a track not named ----------------------------

const P: u32 = 20;
const S: u32 = 21;

/// P, a picture on track 8, and S, its detached sound on track 7, both
/// [0, 8 s) and linked.
fn linked_pair() -> (Value, Handle) {
    let mut picture = clip(P, 8, 0, 8 * SEC, 0);
    picture["linked"] = json!(S);
    picture["enabled"] = json!({"video": true, "audio": false});
    let mut sound = clip(S, 7, 0, 8 * SEC, 0);
    sound["linked"] = json!(P);
    sound["enabled"] = json!({"video": false, "audio": true});
    let value = project(two_tracks(false), vec![sound, picture]);
    let handle = Handle::from_value(&value);
    (value, handle)
}

fn link(project: &Value, id: u32) -> Option<i64> {
    by_id(project, "/clips", id as u64)["linked"].as_i64()
}

#[test]
fn t7_a_linked_partner_elsewhere_is_neither_cut_nor_removed() {
    let (_, source) = linked_pair();
    // {2 s, 4 s}: P is cut twice and its middle removed; S stays whole and
    // names the piece sharing more of its time, P's tail [4 s, 8 s).
    let lifted = applied(&source, &lift(2 * SEC, 4 * SEC, json!([8])));
    assert_eq!(held(&lifted, 7), vec![(S as i64, 0, 8 * SEC)]);
    let pieces = held(&lifted, 8);
    assert_eq!(
        pieces.iter().map(|&(_, s, d)| (s, d)).collect::<Vec<_>>(),
        vec![(0, 2 * SEC), (4 * SEC, 4 * SEC)]
    );
    let tail = pieces[1].0;
    assert_eq!(link(&lifted, S), Some(tail));
    assert_eq!(link(&lifted, tail as u32), Some(S as i64));
    assert_eq!(link(&lifted, P), None);
    // {1 s, 7 s}: the piece S shares most with is the one removed, so its
    // link is cleared rather than left one-sided.
    let wide = applied(&source, &lift(SEC, 7 * SEC, json!([8])));
    assert_eq!(held(&wide, 7), vec![(S as i64, 0, 8 * SEC)]);
    assert_eq!(link(&wide, S), None);
    // Both answers read back: no one-sided link was stored.
    for value in [&lifted, &wide] {
        Handle::try_from_value(value).expect("the answer reloads");
    }
    // The plain form still cuts the partner with its picture (AU-92).
    let both = source.apply(&plain(2 * SEC, 4 * SEC)).value();
    assert_eq!(held(&both, 7).len(), 2);
}

// ---- T8: inside a nest ----------------------------------------------------

#[test]
fn t8_inside_a_nest_the_ids_are_the_nest_s_own() {
    let source = Handle::from_value(&json!({
        "version": 37,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [video(1)],
        "tracks": [{"id": 2, "name": "Timeline"}],
        "clips": [{"id": 3, "track": 2, "start": 0, "duration": 4 * SEC,
                   "source": {"kind": "nest", "project": 4}, "video": {}}],
        "markers": [],
        "next_id": 100,
        "nests": [{"id": 4, "name": "Nest 4", "width": 1920, "height": 1080,
                   "tracks": [{"id": 5, "name": "In 5"}, {"id": 6, "name": "In 6"}],
                   "clips": [clip(7, 5, 0, 4 * SEC, 0), clip(8, 6, 0, 4 * SEC, 0)]}]
    }));
    let mut op = lift(SEC, 2 * SEC, json!([5]));
    op["scope"] = json!(4);
    let inside = source.apply(&op).scoped(4).value();
    assert_eq!(
        held(&inside, 5)
            .iter()
            .map(|&(_, s, d)| (s, d))
            .collect::<Vec<_>>(),
        vec![(0, SEC), (2 * SEC, 2 * SEC)]
    );
    assert_eq!(held(&inside, 6), vec![(8, 0, 4 * SEC)]);
    // The timeline's own track is not a track of the nest.
    let mut outside = lift(SEC, 2 * SEC, json!([2]));
    outside["scope"] = json!(4);
    assert_eq!(source.errors(&outside), "no track with id 2");
}
