//! Linked pairs (spec §11 AU-90…AU-96): every op on a detached picture and
//! its sound, through the FFI. `link_edges.rs` holds the named edge cases.
//!
//! The fixture is one media, three tracks (1 back, 2, 3 front, empty) and a
//! pair: picture 10 on track 2 and its sound 11 on track 1, each written
//! with its own times so a J- or L-cut is a fixture, not a sequence of ops.

mod common;

use common::{at, by_id, int, Handle, Outcome};
use serde_json::{json, Value};

const SEC: i64 = 600_000;
const FRAME: i64 = SEC / 30;

fn media() -> Value {
    json!({"id": 9, "path": "/fixtures/talk.mov", "kind": "video", "duration": 20 * SEC,
           "width": 1920, "height": 1080, "fps": [30, 1],
           "has_video": true, "has_audio": true})
}

/// A media clip; `picture` decides which half it is, `linked` its partner.
fn half(id: u32, track: u32, start: i64, duration: i64, r#in: i64, picture: bool) -> Value {
    let mut clip = json!({"id": id, "track": track, "start": start, "duration": duration,
                          "source": {"kind": "media", "media": 9, "in": r#in},
                          "enabled": {"video": picture, "audio": !picture},
                          "audio": {}});
    if picture {
        clip["video"] = json!({});
    }
    clip
}

fn link(mut a: Value, mut b: Value) -> [Value; 2] {
    a["linked"] = b["id"].clone();
    b["linked"] = a["id"].clone();
    [a, b]
}

fn project(clips: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 28,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [media()],
        "tracks": [{"id": 1, "name": "A"}, {"id": 2, "name": "B"}, {"id": 3, "name": "C"}],
        "clips": clips,
        "next_id": 100
    }))
}

/// A pair in step: picture 10 and sound 11 from `start` for `duration`.
fn in_step(start: i64, duration: i64) -> Vec<Value> {
    link(
        half(10, 2, start, duration, SEC, true),
        half(11, 1, start, duration, SEC, false),
    )
    .to_vec()
}

/// A J-cut: the sound 11 starts `lead` before picture 10 (and reads `lead`
/// earlier in the file); both end together.
fn j_cut(start: i64, duration: i64, lead: i64) -> Vec<Value> {
    link(
        half(10, 2, start, duration, SEC, true),
        half(11, 1, start - lead, duration + lead, SEC - lead, false),
    )
    .to_vec()
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

fn linked(project: &Value, id: u64) -> Option<i64> {
    clip(project, id).get("linked").and_then(Value::as_i64)
}

fn has(project: &Value, id: u64) -> bool {
    at(project, "/clips")
        .as_array()
        .is_some_and(|c| c.iter().any(|x| x["id"] == json!(id)))
}

fn rate_refusal(clip: u32, partner: u32) -> String {
    format!(
        "clip {clip} is linked to clip {partner}: Attach Audio before changing its speed or \
         direction"
    )
}

// ---- detach and the format ---------------------------------------------

#[test]
fn detach_audio_links_the_two_halves() {
    let mut picture = half(10, 2, 0, 2 * SEC, 0, true);
    picture["enabled"]["audio"] = json!(true);
    let before = project(vec![picture]);
    let after = before
        .apply(&json!({"op": "detach_audio", "clip": 10}))
        .value();
    assert_eq!(linked(&after, 10), Some(100));
    assert_eq!(linked(&after, 100), Some(10));
    assert_eq!(track(&after, 100), 1);
}

#[test]
fn a_clip_with_no_link_writes_no_key() {
    let before = project(vec![half(12, 3, 0, SEC, 0, true)]);
    assert!(!before.to_json().contains("\"linked\""));
}

// ---- move ---------------------------------------------------------------

#[test]
fn moving_either_half_moves_both_in_time() {
    let before = project(in_step(2 * SEC, 4 * SEC));
    for named in [10, 11] {
        let after = before
            .apply(&json!({"op": "move_clip", "clips": [named], "delta": SEC}))
            .value();
        assert_eq!(start(&after, 10), 3 * SEC, "named {named}");
        assert_eq!(start(&after, 11), 3 * SEC, "named {named}");
        assert_eq!((track(&after, 10), track(&after, 11)), (2, 1));
    }
}

#[test]
fn only_the_named_clip_changes_track() {
    let before = project(in_step(2 * SEC, 4 * SEC));
    // The picture one track up: its sound follows in time and stays put.
    let after = before
        .apply(&json!({"op": "move_clip", "clips": [10], "delta": SEC, "track": 3}))
        .value();
    assert_eq!((track(&after, 10), track(&after, 11)), (3, 1));
    assert_eq!((start(&after, 10), start(&after, 11)), (3 * SEC, 3 * SEC));
    assert_eq!(linked(&after, 10), Some(11));
}

#[test]
fn a_still_move_is_an_identity_on_a_pair() {
    let before = project(in_step(2 * SEC, 4 * SEC));
    assert!(matches!(
        before.try_apply(&json!({"op": "move_clip", "clips": [10], "delta": 0})),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn a_partner_on_a_locked_track_stays_and_stays_linked() {
    let before = project(in_step(2 * SEC, 4 * SEC));
    let locked = before.apply(&json!({"op": "set_track", "track": 1, "locked": true}));
    let after = locked
        .apply(&json!({"op": "move_clip", "clips": [10], "delta": SEC}))
        .value();
    assert_eq!((start(&after, 10), start(&after, 11)), (3 * SEC, 2 * SEC));
    assert_eq!(linked(&after, 10), Some(11));
    // Nor is it deleted with its picture.
    let deleted = locked
        .apply(&json!({"op": "delete", "clips": [10]}))
        .value();
    assert!(has(&deleted, 11));
    assert_eq!(linked(&deleted, 11), None, "its partner is gone");
}

// ---- split (AU-92) ------------------------------------------------------

#[test]
fn a_split_through_both_halves_pairs_the_second_halves() {
    let before = project(in_step(2 * SEC, 4 * SEC));
    let after = before
        .apply(&json!({"op": "split", "clips": [10], "at": 3 * SEC}))
        .value();
    // 100 is 10's second half, 101 is 11's.
    assert_eq!(start(&after, 100), 3 * SEC);
    assert_eq!(start(&after, 101), 3 * SEC);
    assert_eq!(
        (linked(&after, 10), linked(&after, 11)),
        (Some(11), Some(10))
    );
    assert_eq!(
        (linked(&after, 100), linked(&after, 101)),
        (Some(101), Some(100))
    );
}

#[test]
fn an_uncut_partner_keeps_the_half_it_shares_more_time_with() {
    // A J-cut cut inside its lead: the picture is not cut, and shares all
    // of its time with the sound's SECOND half.
    let before = project(j_cut(2 * SEC, 4 * SEC, SEC / 2));
    let after = before
        .apply(&json!({"op": "split", "clips": [11], "at": 2 * SEC - 6 * FRAME}))
        .value();
    assert_eq!(linked(&after, 10), Some(100));
    assert_eq!(linked(&after, 100), Some(10));
    assert_eq!(linked(&after, 11), None);

    // An L-cut cut inside its tail: the picture shares its time with the
    // sound's FIRST half.
    let l_cut = link(
        half(10, 2, 2 * SEC, 4 * SEC, SEC, true),
        half(11, 1, 2 * SEC, 5 * SEC, SEC, false),
    );
    let after = project(l_cut.to_vec())
        .apply(&json!({"op": "split", "clips": [11], "at": 6 * SEC + SEC / 2}))
        .value();
    assert_eq!(linked(&after, 10), Some(11));
    assert_eq!(linked(&after, 11), Some(10));
    assert_eq!(linked(&after, 100), None);
}

// ---- delete and ripple (AU-91) ------------------------------------------

#[test]
fn deleting_a_picture_takes_its_sound() {
    let after = project(in_step(2 * SEC, 4 * SEC))
        .apply(&json!({"op": "delete", "clips": [10]}))
        .value();
    assert!(!has(&after, 10) && !has(&after, 11));
}

#[test]
fn deleting_a_sound_alone_keeps_its_picture_silent() {
    let after = project(in_step(2 * SEC, 4 * SEC))
        .apply(&json!({"op": "delete", "clips": [11]}))
        .value();
    assert!(has(&after, 10) && !has(&after, 11));
    assert_eq!(linked(&after, 10), None, "the link settles away");
    assert_eq!(at(clip(&after, 10), "/enabled/audio"), &json!(false));
}

#[test]
fn ripple_deleting_either_half_removes_both() {
    let mut clips = in_step(2 * SEC, 4 * SEC);
    clips.push(half(20, 2, 7 * SEC, SEC, 0, true));
    let before = project(clips);
    for named in [10, 11] {
        let after = before
            .apply(&json!({"op": "ripple_delete", "clips": [named]}))
            .value();
        assert!(!has(&after, 10) && !has(&after, 11), "named {named}");
        assert_eq!(start(&after, 20), 3 * SEC);
    }
}

#[test]
fn a_shift_moves_a_partner_that_starts_before_the_boundary() {
    // The picture starts at 2 s and its sound leads it by half a second:
    // inserting time at 2 s moves the sound, though it starts at 1.5 s.
    let before = project(j_cut(2 * SEC, 4 * SEC, SEC / 2));
    let after = before
        .apply(&json!({"op": "insert_time", "at": 2 * SEC, "length": SEC}))
        .value();
    assert_eq!(start(&after, 10), 3 * SEC);
    assert_eq!(start(&after, 11), 3 * SEC - SEC / 2);
}

// ---- copies (AU-96) -----------------------------------------------------

#[test]
fn duplicating_a_picture_copies_its_sound_linked_to_the_copy() {
    let after = project(in_step(2 * SEC, 4 * SEC))
        .apply(&json!({"op": "duplicate", "clips": [10]}))
        .value();
    assert_eq!(linked(&after, 100), Some(101));
    assert_eq!(linked(&after, 101), Some(100));
    assert_eq!(start(&after, 101), 6 * SEC);
    assert_eq!(
        (linked(&after, 10), linked(&after, 11)),
        (Some(11), Some(10))
    );
}

#[test]
fn a_pasted_pair_re_pairs_and_a_lone_half_is_unlinked() {
    let before = project(vec![]);
    let mut pair = link(half(1, 1, 0, SEC, 0, true), half(2, 0, 0, SEC, 0, false));
    let payload = json!({"clips": pair.clone(), "media": [media()]});
    let after = before
        .apply(&json!({"op": "paste", "at": 0, "payload": payload}))
        .value();
    let ids: Vec<u64> = at(&after, "/clips")
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["id"].as_u64().unwrap())
        .collect();
    assert_eq!(ids.len(), 2);
    assert_eq!(linked(&after, ids[0]), Some(ids[1] as i64));
    assert_eq!(linked(&after, ids[1]), Some(ids[0] as i64));

    pair[1]["id"] = json!(3);
    let lone = json!({"clips": [pair[0].clone()], "media": [media()]});
    let after = before
        .apply(&json!({"op": "paste", "at": 0, "payload": lone}))
        .value();
    assert!(!after.to_string().contains("\"linked\""), "{after}");
}

#[test]
fn nest_takes_the_pair_and_unnest_re_pairs_it() {
    let before = project(in_step(2 * SEC, 4 * SEC));
    let nested = before.apply(&json!({"op": "nest", "clips": [10]}));
    let value = nested.value();
    let inside = at(&value, "/nests/0/clips").as_array().unwrap();
    assert_eq!(inside.len(), 2, "the sound went in with its picture");
    let nest_clip = value["next_id"].as_u64().unwrap() - 1;
    let opened = nested
        .apply(&json!({"op": "unnest", "clip": nest_clip}))
        .value();
    let clips = at(&opened, "/clips").as_array().unwrap();
    assert_eq!(clips.len(), 2);
    let (a, b) = (
        clips[0]["id"].as_u64().unwrap(),
        clips[1]["id"].as_u64().unwrap(),
    );
    assert_eq!(linked(&opened, a), Some(b as i64));
    assert_eq!(linked(&opened, b), Some(a as i64));
}

#[test]
fn inside_a_nest_the_pair_moves_as_one() {
    let nested = project(in_step(2 * SEC, 4 * SEC)).apply(&json!({"op": "nest", "clips": [10]}));
    let nest_id = at(&nested.value(), "/nests/0/id").as_u64().unwrap();
    let after = nested
        .apply(&json!({"op": "move_clip", "clips": [10], "delta": SEC, "scope": nest_id}))
        .value();
    let inside = at(&after, "/nests/0/clips").as_array().unwrap();
    let starts: Vec<i64> = inside
        .iter()
        .map(|c| c["start"].as_i64().unwrap())
        .collect();
    assert_eq!(starts, vec![SEC, SEC]);
}

// ---- edges (AU-93) ------------------------------------------------------

#[test]
fn a_picture_trim_carries_to_a_sound_whose_edge_coincides() {
    let before = project(in_step(2 * SEC, 4 * SEC));
    let after = before
        .apply(&json!({"op": "trim_start", "clip": 10, "to": 3 * SEC}))
        .value();
    assert_eq!((start(&after, 10), start(&after, 11)), (3 * SEC, 3 * SEC));
    let after = before
        .apply(&json!({"op": "trim_end", "clip": 11, "to": 5 * SEC}))
        .value();
    assert_eq!(int(clip(&after, 10), "/duration"), 3 * SEC);
}

#[test]
fn a_trim_does_not_carry_across_a_j_cut() {
    // The sound starts earlier, so the picture's front edge is its own.
    let before = project(j_cut(2 * SEC, 4 * SEC, SEC / 2));
    let after = before
        .apply(&json!({"op": "trim_start", "clip": 10, "to": 3 * SEC}))
        .value();
    assert_eq!(start(&after, 10), 3 * SEC);
    assert_eq!(start(&after, 11), 2 * SEC - SEC / 2);
}

#[test]
fn trimming_the_sound_alone_makes_the_j_and_l_cuts() {
    let before = project(in_step(2 * SEC, 4 * SEC));
    let j = before
        .apply(&json!({"op": "trim_start", "clip": 11, "to": 2 * SEC - 15 * FRAME, "alone": true}))
        .value();
    assert_eq!(start(&j, 11), 2 * SEC - 15 * FRAME);
    assert_eq!(start(&j, 10), 2 * SEC);
    assert_eq!(linked(&j, 10), Some(11));
    let l = before
        .apply(&json!({"op": "trim_end", "clip": 10, "to": 6 * SEC - 15 * FRAME, "alone": true}))
        .value();
    assert_eq!(int(clip(&l, 10), "/duration"), 4 * SEC - 15 * FRAME);
    assert_eq!(int(clip(&l, 11), "/duration"), 4 * SEC);
}

#[test]
fn a_refusal_on_the_partner_is_the_answer() {
    // A two-frame clip right after the sound: carrying a one-second
    // extension onto it breaks the overlap rule there.
    let mut clips = in_step(2 * SEC, 4 * SEC);
    let mut blocker = half(20, 1, 6 * SEC, 2 * FRAME, 0, false);
    blocker["enabled"]["audio"] = json!(true);
    clips.push(blocker);
    let before = project(clips);
    let alone = json!({"op": "trim_end", "clip": 10, "to": 7 * SEC, "alone": true});
    assert!(matches!(before.try_apply(&alone), Ok(Outcome::Applied(_))));
    before.refuses(&json!({"op": "trim_end", "clip": 10, "to": 7 * SEC}));
}

#[test]
fn roll_carries_to_the_sound_cut_unless_alone() {
    let mut clips = link(
        half(10, 2, 0, 2 * SEC, 0, true),
        half(11, 1, 0, 2 * SEC, 0, false),
    )
    .to_vec();
    clips.extend(link(
        half(12, 2, 2 * SEC, 2 * SEC, 4 * SEC, true),
        half(13, 1, 2 * SEC, 2 * SEC, 4 * SEC, false),
    ));
    let before = project(clips);
    let rolled = before
        .apply(&json!({"op": "roll", "clip": 12, "to": SEC}))
        .value();
    assert_eq!((start(&rolled, 12), start(&rolled, 13)), (SEC, SEC));
    assert_eq!(int(clip(&rolled, 11), "/duration"), SEC);
    let alone = before
        .apply(&json!({"op": "roll", "clip": 12, "to": SEC, "alone": true}))
        .value();
    assert_eq!((start(&alone, 12), start(&alone, 13)), (SEC, 2 * SEC));
}

// ---- slip and rates (AU-94) ---------------------------------------------

#[test]
fn slip_moves_both_halves_by_the_smaller_clamp() {
    // The J-cut sound reads from half a second into the file, the picture
    // from a second: a slip of −0.8 s stops where the sound reaches 0.
    let before = project(j_cut(2 * SEC, 4 * SEC, SEC / 2));
    let after = before
        .apply(&json!({"op": "slip", "clip": 10, "delta": -8 * SEC / 10}))
        .value();
    assert_eq!(common::source_in(&after, 11), 0);
    assert_eq!(common::source_in(&after, 10), SEC / 2);
}

#[test]
fn speed_direction_and_ramps_are_refused_on_a_linked_clip() {
    let before = project(in_step(2 * SEC, 4 * SEC));
    let refusal = rate_refusal(10, 11);
    for op in [
        json!({"op": "set_speed", "clip": 10, "rate": 2.0}),
        json!({"op": "set_speed", "clip": 10, "duration": 2 * SEC}),
        json!({"op": "rate_stretch", "clip": 10, "to_end": 8 * SEC}),
        json!({"op": "set_reversed", "clip": 10, "reversed": true}),
        json!({"op": "add_speed_ramp", "clip": 10, "shape": "ramp_up", "rate": 2.0}),
    ] {
        before.refuses_with(&op, &refusal);
    }
    before.refuses_with(
        &json!({"op": "set_speed", "clip": 11, "rate": 0.5}),
        &rate_refusal(11, 10),
    );
    // Keep pitch alone is not a rate, and an action that names none is not
    // either.
    let kept = before.apply(&json!({"op": "set_speed", "clip": 11, "rate": 1.0,
                                    "keep_pitch": false}));
    assert_eq!(
        at(clip(&kept.value(), 11), "/audio/keep_pitch"),
        &json!(false)
    );
    let action = before.apply(&json!({"op": "add_action", "clip": 10, "at": 0}));
    let id = action.value()["next_id"].as_u64().unwrap() - 1;
    action.apply(&json!({"op": "set_action", "clip": 10, "action": id, "duration": SEC / 2}));
    action.refuses_with(
        &json!({"op": "set_action_end", "clip": 10, "action": id, "patch": {"speed": 2.0}}),
        &refusal,
    );
}

#[test]
fn a_speed_action_on_a_linked_clip_cannot_move_or_go() {
    let mut clips = in_step(2 * SEC, 4 * SEC);
    clips[0]["actions"] = json!([{"id": 50, "start": 0, "duration": SEC, "end": {"speed": 1.5}}]);
    let before = project(clips);
    let refusal = rate_refusal(10, 11);
    before.refuses_with(
        &json!({"op": "set_action", "clip": 10, "action": 50, "curve": "ease_in"}),
        &refusal,
    );
    before.refuses_with(
        &json!({"op": "remove_action", "clip": 10, "action": 50}),
        &refusal,
    );
    before.refuses_with(
        &json!({"op": "set_action_end", "clip": 10, "action": 50, "patch": {"speed": null}}),
        &refusal,
    );
}

// ---- Attach Audio (AU-95) -----------------------------------------------

#[test]
fn attach_merges_an_in_step_pair_into_one_clip() {
    let mut clips = in_step(2 * SEC, 4 * SEC);
    clips[0]["audio"] = json!({"volume": 0.25});
    clips[0]["actions"] = json!([
        {"id": 50, "start": 0, "duration": SEC, "end": {"video": {"opacity": 0.5},
                                                        "audio": {"volume": 0.1}}},
        {"id": 51, "start": SEC, "duration": SEC, "end": {"audio": {"volume": 0.1}}}
    ]);
    clips[1]["audio"] = json!({"volume": 0.5});
    clips[1]["actions"] = json!([
        {"id": 52, "start": 0, "duration": SEC, "end": {"audio": {"volume": 0.9}}},
        {"id": 53, "start": SEC, "duration": SEC, "end": {}}
    ]);
    let before = project(clips);
    for named in [10, 11] {
        let after = before
            .apply(&json!({"op": "attach_audio", "clip": named}))
            .value();
        assert!(has(&after, 10) && !has(&after, 11), "named {named}");
        let merged = clip(&after, 10);
        assert_eq!(merged.get("linked"), None);
        assert_eq!(
            at(merged, "/enabled"),
            &json!({"video": true, "audio": true})
        );
        assert_eq!(at(merged, "/audio/volume"), &json!(0.5));
        assert_eq!(
            at(merged, "/actions/0/end"),
            &json!({"video": {"opacity": 0.5}, "audio": {"volume": 0.9}})
        );
        assert_eq!(at(merged, "/actions/1/end"), &json!({}));
        assert_eq!(
            at(&after, "/tracks").as_array().unwrap().len(),
            3,
            "the track stays"
        );
    }
}

#[test]
fn detach_then_attach_is_the_clip_it_was() {
    let mut picture = half(10, 2, 0, 2 * SEC, 0, true);
    picture["enabled"]["audio"] = json!(true);
    let before = project(vec![picture]);
    let after = before
        .apply(&json!({"op": "detach_audio", "clip": 10}))
        .apply(&json!({"op": "attach_audio", "clip": 100}))
        .value();
    let mut expected = before.value();
    expected["next_id"] = after["next_id"].clone();
    assert_eq!(after, expected);
}

#[test]
fn attach_refuses_in_its_own_sentences() {
    let lone = project(vec![half(12, 3, 0, SEC, 0, true)]);
    lone.refuses_with(
        &json!({"op": "attach_audio", "clip": 12}),
        "clip 12 is not linked to a detached sound",
    );
    let two_pictures = link(half(10, 2, 0, SEC, 0, true), half(11, 3, 0, SEC, 0, true));
    project(two_pictures.to_vec()).refuses_with(
        &json!({"op": "attach_audio", "clip": 10}),
        "clips 10 and 11 are not a picture and its detached sound",
    );
    let j = project(j_cut(2 * SEC, 4 * SEC, SEC / 2));
    let sentence = "clip 10's picture and clip 11's sound do not cover the same time; trim \
                    them to match before Attach Audio";
    j.refuses_with(&json!({"op": "attach_audio", "clip": 11}), sentence);
    let mut slipped = in_step(2 * SEC, 4 * SEC);
    slipped[1]["source"]["in"] = json!(2 * SEC);
    project(slipped).refuses_with(&json!({"op": "attach_audio", "clip": 10}), sentence);
}
