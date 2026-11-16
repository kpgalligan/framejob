//! A cut that would break THE overlap rule is refused (spec §11 #427),
//! through the FFI.
//!
//! The fixture is the issue's: A [0, 4 s) and B [3 s, 8 s) on one track,
//! joined by a one-second cross dissolve. A cut at 2.2 s leaves A's piece
//! [2.2 s, 4 s), 1.8 s, under B by 1 s — more than half of it (0.9 s). Every
//! number in a sentence below is computed here, by hand, and every applied
//! answer is held to the tests' own oracle (`common/overlap_oracle.rs`),
//! never to the core's rule.

mod common;
#[path = "common/overlap_oracle.rs"]
mod overlap_oracle;

use common::{array, int, Handle, Outcome};
use overlap_oracle::overlap_rule_holds;
use serde_json::{json, Value};

/// Ticks per second (spec §5.1) and one frame at 30 fps.
const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;
/// 2.2 s, the issue's cut: 66 frames, on the grid.
const CUT: i64 = 2 * SEC + SEC / 5;

const A: u32 = 10;
const B: u32 = 11;

fn video(id: u32, seconds: i64) -> Value {
    json!({"id": id, "path": format!("/fixtures/v{id}.mov"), "kind": "video",
           "duration": seconds * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
           "has_video": true, "has_audio": true})
}

/// A media clip of media 1 reading from `r#in`.
fn clip(id: u32, track: u32, start: i64, duration: i64, r#in: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "media", "media": 1, "in": r#in},
           "video": {}, "audio": {}})
}

/// `clip` with a cross dissolve into it.
fn dissolving(id: u32, track: u32, start: i64, duration: i64, r#in: i64) -> Value {
    let mut c = clip(id, track, start, duration, r#in);
    c["transition_in"] = json!({"kind": "cross_dissolve"});
    c
}

fn project(tracks: Value, clips: Vec<Value>) -> Value {
    json!({
        "version": 37,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [video(1, 600), video(2, 2)],
        "tracks": tracks,
        "clips": clips,
        "markers": [],
        "next_id": 100,
        "nests": []
    })
}

/// The issue's fixture: A and B, a one-second dissolve, alone on track 8.
fn dissolve() -> Handle {
    Handle::from_value(&project(
        json!([{"id": 8, "name": "Track 1"}]),
        vec![
            clip(A, 8, 0, 4 * SEC, 0),
            dissolving(B, 8, 3 * SEC, 5 * SEC, 10 * SEC),
        ],
    ))
}

/// The cut sentence for A and B: a 1 s overlap against the piece the cut
/// left, `piece` ticks long.
fn too_short(a: u32, b: u32, overlap: i64, piece: i64) -> String {
    format!(
        "clips {a} and {b} would overlap by {overlap} ticks, more than half of the shorter \
         piece the cut leaves ({} ticks); cut further from their transition, or shorten it \
         first",
        piece / 2
    )
}

/// The issue's sentence: A's 1.8 s piece under B by 1 s.
fn issue_sentence() -> String {
    too_short(A, B, SEC, 4 * SEC - CUT)
}

fn split(clips: Option<&[u32]>, at: i64) -> Value {
    match clips {
        Some(ids) => json!({"op": "split", "clips": ids, "at": at}),
        None => json!({"op": "split", "at": at}),
    }
}

fn range(op: &str, from: i64, to: i64) -> Value {
    json!({"op": op, "from": from, "to": to})
}

fn ranges(pairs: &[[i64; 2]]) -> Value {
    json!({"op": "ripple_delete_ranges", "ranges": pairs})
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

// ---- C1: the issue's three cuts -------------------------------------------

#[test]
fn c1_split_at_the_issue_cut_is_refused_naming_a_and_b() {
    let source = dissolve();
    refused(&source, &split(None, CUT), &issue_sentence());
    refused(&source, &split(Some(&[A]), CUT), &issue_sentence());
}

#[test]
fn c1_lift_and_ripple_of_the_issue_range_are_refused_naming_a_and_b() {
    let source = dissolve();
    refused(&source, &range("lift_range", 0, CUT), &issue_sentence());
    refused(
        &source,
        &range("ripple_delete_range", 0, CUT),
        &issue_sentence(),
    );
    // A reversed range is the same range, and the same refusal.
    refused(&source, &range("lift_range", CUT, 0), &issue_sentence());
}

#[test]
fn c1_a_piece_cut_twice_is_named_by_the_clip_it_was_cut_from() {
    // Cut at 1 s, then its second half at 2.2 s: the piece left under B is
    // the second half's second half, and the sentence still names A.
    refused(
        &dissolve(),
        &range("lift_range", SEC, CUT),
        &issue_sentence(),
    );
}

// ---- C2: a batch cut refused whole ----------------------------------------

#[test]
fn c2_ripple_delete_ranges_with_one_bad_range_is_refused_whole() {
    let source = dissolve();
    // The harmless range alone applies: it cuts B at 5 s and 6 s, and B's
    // head [3 s, 5 s) keeps the dissolve within its limit.
    applied(&source, &ranges(&[[5 * SEC, 6 * SEC]]));
    // With the issue's range beside it, nothing is cut. Right to left, B is
    // left [3 s, 5 s) then shifted with A's 1.8 s piece: the overlap is 1 s
    // against a limit of half the 1.8 s piece.
    refused(
        &source,
        &ranges(&[[5 * SEC, 6 * SEC], [0, CUT]]),
        &issue_sentence(),
    );
}

// ---- C3: the composites that cut ------------------------------------------

#[test]
fn c3_retime_range_with_a_bound_at_the_issue_cut_is_refused() {
    // [1 s, 2.2 s) at ×2: A's piece [2.2 s, 4 s) and B move up together by
    // 0.6 s, so the piece is still 1.8 s under B by 1 s.
    refused(
        &dissolve(),
        &json!({"op": "retime_range", "from": SEC, "to": CUT, "rate": 2.0}),
        &issue_sentence(),
    );
}

#[test]
fn c3_overwrite_refuses_a_linked_partners_piece_cut_too_short() {
    // P (picture, track 8) and S (its sound, track 9) linked over [0, 10 s);
    // S2 dissolves in from S at 9 s. An overwrite of the 2 s media 2 at
    // 8.5 s cuts S at 8.5 s too (AU-92) and leaves S's piece [8.5 s, 10 s),
    // 1.5 s, under S2 by 1 s.
    const P: u32 = 20;
    const S: u32 = 21;
    const S2: u32 = 22;
    let mut picture = clip(P, 8, 0, 10 * SEC, 0);
    picture["linked"] = json!(S);
    picture["enabled"] = json!({"video": true, "audio": false});
    let mut sound = clip(S, 9, 0, 10 * SEC, 0);
    sound["linked"] = json!(P);
    sound["enabled"] = json!({"video": false, "audio": true});
    let source = Handle::from_value(&project(
        json!([{"id": 8, "name": "V"}, {"id": 9, "name": "A"}]),
        vec![
            picture,
            sound,
            dissolving(S2, 9, 9 * SEC, 5 * SEC, 20 * SEC),
        ],
    ));
    let at = 8 * SEC + SEC / 2;
    refused(
        &source,
        &json!({"op": "overwrite_clip", "track": 8, "media": 2, "at": at}),
        &too_short(S, S2, SEC, 10 * SEC - at),
    );
    // Clear of the dissolve the same overwrite applies.
    applied(
        &source,
        &json!({"op": "overwrite_clip", "track": 8, "media": 2, "at": 2 * SEC}),
    );
}

#[test]
fn c3_insert_and_freeze_at_the_issue_cut_name_a_and_b() {
    let source = dissolve();
    refused(
        &source,
        &json!({"op": "insert_clip", "track": 8, "media": 2, "at": CUT}),
        &issue_sentence(),
    );
    refused(
        &source,
        &json!({"op": "freeze_frame", "clip": A, "at": CUT}),
        &issue_sentence(),
    );
}

// ---- C4: controls, green before and after ---------------------------------

#[test]
fn c4_the_bound_is_the_rule_s_own() {
    let source = dissolve();
    // At 2 s the piece is 2 s and the 1 s dissolve is exactly half of it.
    let cut = applied(&source, &split(None, 2 * SEC));
    assert_eq!(array(&cut, "/clips").len(), 3);
    // One frame later the piece is a frame shorter and the half is short of
    // the dissolve.
    refused(
        &source,
        &split(None, 2 * SEC + FRAME),
        &too_short(A, B, SEC, 4 * SEC - (2 * SEC + FRAME)),
    );
}

#[test]
fn c4_a_range_whose_short_piece_is_removed_applies() {
    // The cut at 2.2 s alone leaves A's piece too short, but the range takes
    // that piece and B's head with it: A [0, 2.2 s), then B's rest
    // hard-cut from 4 s.
    let source = dissolve();
    let lifted = applied(&source, &range("lift_range", CUT, 4 * SEC));
    let mut spans: Vec<(i64, i64)> = array(&lifted, "/clips")
        .iter()
        .map(|c| (int(c, "/start"), int(c, "/duration")))
        .collect();
    spans.sort();
    assert_eq!(spans, vec![(0, CUT), (4 * SEC, 4 * SEC)]);
    applied(&source, &range("ripple_delete_range", CUT, 4 * SEC));
}

#[test]
fn c4_a_violation_on_a_track_the_cut_did_not_change_is_not_its_to_report() {
    // Track 9 is locked and holds C and D past the limit (stored as the
    // defect left them; `validate` does not ask the rule). A cut on track 8
    // changes nothing there, so it applies.
    let mut tracks = json!([{"id": 8, "name": "V"}, {"id": 9, "name": "L", "locked": true}]);
    let mut clips = vec![
        clip(A, 8, 0, 4 * SEC, 0),
        dissolving(B, 8, 3 * SEC, 5 * SEC, 10 * SEC),
        clip(30, 9, 0, 2 * SEC, 0),
        dissolving(31, 9, SEC / 2, 2 * SEC, 0),
    ];
    let locked = Handle::from_value(&project(tracks.clone(), clips.clone()));
    let cut = locked.apply(&split(None, SEC)).value();
    assert_eq!(array(&cut, "/clips").len(), 5);
    // The same pair on an UNLOCKED track the cut does not reach.
    tracks[1]["locked"] = json!(false);
    clips[2]["start"] = json!(5 * SEC);
    clips[3]["start"] = json!(5 * SEC + SEC / 2);
    let unlocked = Handle::from_value(&project(tracks, clips));
    let cut = unlocked.apply(&split(Some(&[A]), SEC)).value();
    assert_eq!(array(&cut, "/clips").len(), 5);
}

// ---- C5: a pair already past the limit on a track the cut moves -----------

#[test]
fn c5_a_pair_already_past_the_limit_refuses_in_the_rule_s_own_sentence() {
    // C [5 s, 9 s) and D [6 s, 8 s) on track 9 overlap by all of D (2 s,
    // limit 1 s), stored so. A ripple far from them shifts track 9, which is
    // then judged whole — and the sentence is the rule's, about two clips
    // the caller has, never "the cut leaves".
    let source = Handle::from_value(&project(
        json!([{"id": 8, "name": "V"}, {"id": 9, "name": "M"}]),
        vec![
            clip(A, 8, 0, 4 * SEC, 0),
            clip(30, 9, 5 * SEC, 4 * SEC, 0),
            dissolving(31, 9, 6 * SEC, 2 * SEC, 0),
        ],
    ));
    refused(
        &source,
        &range("ripple_delete_range", SEC / 2, SEC),
        &format!(
            "clips 30 and 31 would overlap by {} ticks, more than half of the shorter clip \
             ({} ticks)",
            2 * SEC,
            SEC
        ),
    );
    // A lift there moves nothing on track 9, so it applies.
    let lifted = source.apply(&range("lift_range", SEC / 2, SEC)).value();
    assert_eq!(array(&lifted, "/clips").len(), 4);
}

#[test]
fn c5_a_pair_a_ripple_only_moved_past_the_limit_answers_the_rule_s_sentence() {
    // S (sound, track 9) [0.6 s, 3 s) is linked to P (picture, track 8)
    // [5 s, 10 s), and R [0, 0.6 s) touches S. A ripple of {4 s, 4.5 s} cuts
    // nothing; it moves P and, with it, S, 0.5 s onto R: past R's half
    // (0.3 s). Neither clip is a piece, so the sentence is the rule's.
    const R: u32 = 50;
    const S: u32 = 51;
    const P: u32 = 52;
    let mut picture = clip(P, 8, 5 * SEC, 5 * SEC, 0);
    picture["linked"] = json!(S);
    picture["enabled"] = json!({"video": true, "audio": false});
    let mut sound = clip(S, 9, 3 * SEC / 5, 3 * SEC - 3 * SEC / 5, 0);
    sound["linked"] = json!(P);
    sound["enabled"] = json!({"video": false, "audio": true});
    let source = Handle::from_value(&project(
        json!([{"id": 8, "name": "V"}, {"id": 9, "name": "A"}]),
        vec![clip(R, 9, 0, 3 * SEC / 5, 20 * SEC), sound, picture],
    ));
    refused(
        &source,
        &range("ripple_delete_range", 4 * SEC, 4 * SEC + SEC / 2),
        &format!(
            "clips {R} and {S} would overlap by {} ticks, more than half of the shorter clip \
             ({} ticks)",
            SEC / 2,
            3 * SEC / 10
        ),
    );
}

#[test]
fn c5_a_pair_already_past_the_limit_is_not_the_cut_s_when_the_cut_reaches_it() {
    // X [0, 1 s) and Y [0.4 s, 10 s) overlap by 0.6 s, past X's half
    // (0.5 s), stored so. A cut of either clip leaves a piece in that pair,
    // but no cut made it and none can mend it, so the answer is the rule's
    // own sentence about X and Y — never "cut further from their transition".
    const X: u32 = 40;
    const Y: u32 = 41;
    let source = Handle::from_value(&project(
        json!([{"id": 8, "name": "V"}]),
        vec![
            clip(X, 8, 0, SEC, 0),
            dissolving(Y, 8, 2 * SEC / 5, 10 * SEC - 2 * SEC / 5, 10 * SEC),
        ],
    ));
    let rule = |shorter: i64| {
        format!(
            "clips {X} and {Y} would overlap by {} ticks, more than half of the shorter clip \
             ({} ticks)",
            3 * SEC / 5,
            shorter / 2
        )
    };
    // Y cut at 5 s, far from the pair: Y's first half keeps its id, and X is
    // still the shorter clip.
    refused(&source, &split(Some(&[Y]), 5 * SEC), &rule(SEC));
    // X cut at 0.2 s: the pair is X's second half [0.2 s, 1 s) and Y, named
    // by the clip that half was cut from, against the half's own length.
    refused(&source, &split(Some(&[X]), SEC / 5), &rule(SEC - SEC / 5));
}

// ---- C6: the sweep --------------------------------------------------------

/// The sweep's op `name` at `t`: a split at `t`, or the range {0, `t`}.
fn swept(name: &str, t: i64) -> Value {
    match name {
        "split" => split(None, t),
        _ => range(name, 0, t),
    }
}

#[test]
fn c6_every_frame_applied_holds_the_rule_and_both_answers_are_seen() {
    let source = dissolve();
    for name in ["split", "lift_range", "ripple_delete_range"] {
        let (mut seen_applied, mut seen_refused) = (0, 0);
        let mut t = FRAME;
        while t < 8 * SEC {
            match source.try_apply(&swept(name, t)).expect("a valid op") {
                Outcome::Applied(next) => {
                    let value = next.value();
                    assert!(
                        overlap_rule_holds(&value),
                        "{name} at {t} applied and broke the overlap rule: {value}"
                    );
                    seen_applied += 1;
                }
                Outcome::Refused(_) => seen_refused += 1,
                Outcome::Identity => {}
            }
            t += FRAME;
        }
        assert!(
            seen_applied > 0 && seen_refused > 0,
            "{name}: {seen_applied} applied and {seen_refused} refused over the sweep"
        );
    }
}
