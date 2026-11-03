//! `copy_pieces` (road map "creator-jobs" SW1, spec §11 SW-11, SW-12): a
//! clip's pieces between given project times copied onto another track at
//! the same times, through the FFI.
//!
//! The oracle for a piece is another op's answer: `split` at the range's two
//! ends on a copy of the project, the middle read back. Every piece is
//! field-equal to that middle except for what SW-11 says a copy changes —
//! its id, its track, its actions' ids, its link and its transition — for a
//! plain clip, ×1.25, a ramp, a reversed clip, a graphic, a timed text page
//! and a clip whose actions straddle both ends. Then every refusal in its
//! order, the errors, snapped ends, a reversed pair, the switches, the link
//! cleared, the identities and a copy inside a nest.

mod common;

use std::collections::BTreeSet;

use serde_json::{json, Value};

use common::{array, by_id, content, int, Handle, Outcome};

/// Ticks per second (spec §5.1) and one frame at 30 fps, written out.
const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;
/// Where clip 11 starts; it runs four seconds.
const START: i64 = SEC;
const END: i64 = START + 4 * SEC;

fn media_clip(id: u32, track: u32, start: i64, duration: i64, extra: Value) -> Value {
    let mut clip = json!({
        "id": id, "track": track, "start": start, "duration": duration,
        "source": {"kind": "media", "media": 1, "in": 2 * SEC},
        "video": {}, "audio": {}
    });
    if let (Some(object), Value::Object(more)) = (clip.as_object_mut(), extra) {
        for (key, value) in more {
            object.insert(key, value);
        }
    }
    clip
}

/// Tracks 2 (the source), 3 (the destination, empty) and 4; nest 50 with
/// tracks 51 and 52 and media clip 53, shown by nest clip 60 on track 4;
/// `clip` the clip under test, id 11 on track 2.
fn project(clip: Value) -> Value {
    json!({
        "version": 27,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/fixtures/angle.mov", "kind": "video",
                   "duration": 600 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
                   "has_video": true, "has_audio": true}],
        "tracks": [{"id": 2, "name": "Source"}, {"id": 3, "name": "Program"},
                   {"id": 4, "name": "Other"}],
        "clips": [clip,
                  {"id": 60, "track": 4, "start": 0, "duration": 4 * SEC,
                   "source": {"kind": "nest", "project": 50}, "video": {}}],
        "next_id": 100,
        "nests": [{"id": 50, "name": "N", "width": 1920, "height": 1080,
                   "tracks": [{"id": 51, "name": "A"}, {"id": 52, "name": "B"}],
                   "clips": [media_clip(53, 51, 0, 4 * SEC, json!({}))]}]
    })
}

fn plain() -> Handle {
    Handle::from_value(&project(media_clip(11, 2, START, 4 * SEC, json!({}))))
}

fn copy(clip: u32, track: u32, ranges: Value) -> Value {
    json!({"op": "copy_pieces", "clip": clip, "track": track, "ranges": ranges})
}

/// `content` with the two things a copy clears also stripped: the link and
/// the transition (spec §11 SW-11).
fn stripped(clip: &Value) -> Value {
    let mut out = content(clip);
    let object = out.as_object_mut().expect("a clip is an object");
    object.remove("linked");
    object.remove("transition_in");
    out
}

/// The oracle: `split` at `from` (when past the clip's start), then the
/// middle at `to` (when before its end), on a copy; the middle read back.
fn split_middle(handle: &Handle, clip: u32, from: i64, to: i64) -> Value {
    let value = handle.value();
    let original = by_id(&value, "/clips", u64::from(clip));
    let (start, track) = (int(original, "/start"), int(original, "/track"));
    let end = start + int(original, "/duration");
    let mut cut = handle.duplicate();
    let mut id = u64::from(clip);
    if from > start {
        cut = cut.apply(&json!({"op": "split", "clips": [id], "at": from}));
        id = array(&cut.value(), "/clips")
            .iter()
            .find(|c| int(c, "/track") == track && int(c, "/start") == from)
            .map(|c| int(c, "/id") as u64)
            .expect("the second half starts at the cut");
    }
    if to < end {
        cut = cut.apply(&json!({"op": "split", "clips": [id], "at": to}));
    }
    by_id(&cut.value(), "/clips", id).clone()
}

/// Every clip on `track`, by start.
fn on_track(value: &Value, track: i64) -> Vec<Value> {
    let mut clips: Vec<Value> = array(value, "/clips")
        .iter()
        .filter(|c| int(c, "/track") == track)
        .cloned()
        .collect();
    clips.sort_by_key(|c| int(c, "/start"));
    clips
}

/// Every id a project's clips and their actions use.
fn ids(value: &Value) -> BTreeSet<i64> {
    let mut out = BTreeSet::new();
    for clip in array(value, "/clips") {
        out.insert(int(clip, "/id"));
        for action in clip["actions"].as_array().into_iter().flatten() {
            out.insert(int(action, "/id"));
        }
    }
    out
}

/// Copies `ranges` of clip 11 onto track 3 and holds each piece to the
/// middle of two splits, with fresh ids, in order, at its range's start.
fn pieces_equal_splits(handle: &Handle, ranges: &[(i64, i64)]) {
    let before = handle.value();
    let wire: Vec<Value> = ranges.iter().map(|(a, b)| json!([a, b])).collect();
    let after = handle.apply(&copy(11, 3, Value::Array(wire))).value();
    let pieces = on_track(&after, 3);
    assert_eq!(pieces.len(), ranges.len(), "one piece per range");
    let old = ids(&before);
    let mut fresh = BTreeSet::new();
    for (piece, (from, to)) in pieces.iter().zip(ranges) {
        assert_eq!(int(piece, "/start"), *from);
        assert_eq!(int(piece, "/start") + int(piece, "/duration"), *to);
        assert!(piece.get("transition_in").is_none_or(Value::is_null));
        assert!(piece.get("linked").is_none_or(Value::is_null));
        assert_eq!(
            stripped(piece),
            stripped(&split_middle(handle, 11, *from, *to)),
            "the piece over [{from}, {to}] is not the middle of two splits"
        );
        let mut own = vec![int(piece, "/id")];
        own.extend(
            piece["actions"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|a| int(a, "/id")),
        );
        for id in own {
            assert!(id >= 100, "id {id} is not from the counter");
            assert!(!old.contains(&id), "id {id} is not fresh");
            assert!(fresh.insert(id), "id {id} used twice");
        }
    }
    // Nothing else moved: the source clip and every other clip are as they
    // were.
    assert_eq!(
        by_id(&after, "/clips", 11),
        by_id(&before, "/clips", 11),
        "the source clip changed"
    );
    assert_eq!(
        array(&after, "/clips").len(),
        array(&before, "/clips").len() + ranges.len()
    );
}

/// Three ranges: one from the clip's start, one inside, one to its end.
fn three() -> Vec<(i64, i64)> {
    vec![
        (START, START + SEC / 2),
        (START + SEC, START + 2 * SEC + 10 * FRAME),
        (START + 3 * SEC, END),
    ]
}

fn with_clip(extra: Value) -> Handle {
    Handle::from_value(&project(media_clip(11, 2, START, 4 * SEC, extra)))
}

// ---- each piece is the middle of two splits ------------------------------

#[test]
fn a_plain_clip() {
    let handle = with_clip(json!({"actions": [
        {"id": 21, "start": 0, "duration": SEC, "curve": "linear",
         "end": {"video": {"opacity": 0.5}}}]}));
    pieces_equal_splits(&handle, &three());
    // The whole clip is one piece equal to the clip itself.
    pieces_equal_splits(&handle, &[(START, END)]);
}

#[test]
fn a_clip_at_1_25() {
    pieces_equal_splits(&with_clip(json!({"speed": 1.25})), &three());
}

#[test]
fn a_ramp() {
    let handle = with_clip(json!({"actions": [
        {"id": 21, "start": 0, "duration": 4 * SEC, "curve": "ease_in_out",
         "end": {"speed": 3.0}}]}));
    pieces_equal_splits(&handle, &three());
}

#[test]
fn a_reversed_clip() {
    let handle = with_clip(json!({
        "source": {"kind": "media", "media": 1, "in": SEC, "reversed": true}}));
    pieces_equal_splits(&handle, &three());
}

#[test]
fn a_graphic() {
    let handle = Handle::from_value(&project(json!({
        "id": 11, "track": 2, "start": START, "duration": 4 * SEC,
        "source": {"kind": "graphic"}, "video": {},
        "graphic": {"name": "lower-third", "width": 1920, "height": 1080,
                    "props": {"title": "Hi"}}})));
    pieces_equal_splits(&handle, &three());
}

#[test]
fn a_timed_text_page() {
    let page = Handle::from_value(&project(json!({
        "id": 11, "track": 2, "start": START, "duration": 4 * SEC,
        "source": {"kind": "text"}, "video": {},
        "text": {"content": "so here's the thing"}})))
    .apply(&json!({"op": "set_text", "clips": [11], "patch": {
        "words": [{"start": 0, "end": SEC / 2}, {"start": SEC, "end": 2 * SEC},
                  {"start": 2 * SEC + 10 * FRAME, "end": 3 * SEC},
                  {"start": 3 * SEC + 5 * FRAME, "end": 4 * SEC}],
        "word_style": {"active_scale": 1.2}}}));
    pieces_equal_splits(&page, &three());
}

#[test]
fn a_clip_whose_actions_straddle_both_ends() {
    let handle = with_clip(json!({"actions": [
        {"id": 21, "start": SEC / 2, "duration": SEC, "curve": "ease_in",
         "end": {"video": {"opacity": 0.2}}},
        {"id": 22, "start": 2 * SEC, "duration": SEC, "curve": "linear",
         "end": {"video": {"scale": 1.5, "x": 100}}}]}));
    // [START + 1 s, START + 2.5 s] cuts action 21 at its middle and action
    // 22 at its middle.
    pieces_equal_splits(&handle, &[(START + SEC, START + 2 * SEC + SEC / 2)]);
}

// ---- errors, then refusals, in order -------------------------------------

#[test]
fn an_unknown_clip_then_an_unknown_track_is_an_error() {
    let handle = plain();
    assert_eq!(
        handle.errors(&copy(99, 98, json!([[0, SEC]]))),
        "no clip with id 99"
    );
    assert_eq!(
        handle.errors(&copy(11, 98, json!([[START, END]]))),
        "no track with id 98"
    );
    // Before an empty list's identity.
    assert_eq!(
        handle.errors(&copy(11, 98, json!([]))),
        "no track with id 98"
    );
}

#[test]
fn a_nest_clip_is_refused_first() {
    plain().refuses_with(
        &copy(
            60,
            3,
            json!([[0, 9 * SEC], [SEC, 2 * SEC], [SEC / 2, 3 * SEC]]),
        ),
        "clip 60 is a nest: a piece of it would replay the nest from its first frame",
    );
}

#[test]
fn a_range_outside_the_clip_is_refused_before_an_overlap() {
    let handle = plain();
    handle.refuses_with(
        &copy(
            11,
            3,
            json!([[START + SEC, START + 2 * SEC], [START + SEC, END + SEC]]),
        ),
        &format!(
            "range [{}, {}] is outside clip 11, which runs from {START} to {END}",
            START + SEC,
            END + SEC
        ),
    );
    handle.refuses_with(
        &copy(11, 3, json!([[0, START + SEC]])),
        &format!(
            "range [0, {}] is outside clip 11, which runs from {START} to {END}",
            START + SEC
        ),
    );
}

#[test]
fn overlapping_ranges_are_refused_before_a_lock_and_touching_ones_are_not() {
    let mut value = project(media_clip(11, 2, START, 4 * SEC, json!({})));
    value["tracks"][1]["locked"] = json!(true);
    let locked = Handle::from_value(&value);
    let (a, b, c, d) = (START + 2 * SEC, END, START, START + 2 * SEC + FRAME);
    // Sorted by start before the check, so the earlier range comes first.
    locked.refuses_with(
        &copy(11, 3, json!([[a, b], [c, d]])),
        &format!("ranges [{c}, {d}] and [{a}, {b}] overlap"),
    );
    pieces_equal_splits(
        &plain(),
        &[(START, START + 2 * SEC), (START + 2 * SEC, END)],
    );
}

#[test]
fn a_locked_destination_is_refused_before_an_occupied_one() {
    let mut value = project(media_clip(11, 2, START, 4 * SEC, json!({})));
    value["tracks"][1]["locked"] = json!(true);
    value["clips"]
        .as_array_mut()
        .unwrap()
        .push(media_clip(70, 3, START, SEC, json!({})));
    Handle::from_value(&value).refuses_with(
        &copy(11, 3, json!([[START, END]])),
        "track 3 is locked, so no piece can be copied onto it",
    );
}

#[test]
fn an_occupied_destination_names_its_first_clip_by_start() {
    let mut value = project(media_clip(11, 2, START, 4 * SEC, json!({})));
    let clips = value["clips"].as_array_mut().unwrap();
    clips.push(media_clip(71, 3, START + 3 * SEC, SEC, json!({})));
    clips.push(media_clip(70, 3, START + SEC, SEC / 2, json!({})));
    let held = Handle::from_value(&value);
    held.refuses_with(
        &copy(
            11,
            3,
            json!([[START, START + SEC / 2], [START + SEC + FRAME, END]]),
        ),
        &format!(
            "track 3 holds clip 70 between {} and {}",
            START + SEC,
            START + SEC + SEC / 2
        ),
    );
    // A range that only touches a held clip is free.
    let after = held
        .apply(&copy(
            11,
            3,
            json!([[START + SEC / 2 + SEC, START + 3 * SEC]]),
        ))
        .value();
    assert_eq!(on_track(&after, 3).len(), 3);
    // The source's own track holds the source clip.
    plain().refuses_with(
        &copy(11, 2, json!([[START, START + SEC]])),
        &format!("track 2 holds clip 11 between {START} and {END}"),
    );
}

// ---- snapping, order and identities --------------------------------------

#[test]
fn both_ends_are_snapped_as_split_snaps_and_a_reversed_pair_is_the_same_range() {
    let handle = plain();
    // 7,000 ticks rounds down to the frame, 13,000 up to the next.
    let sent = copy(
        11,
        3,
        json!([[START + SEC + 7_000, START + 2 * SEC + 13_000]]),
    );
    let after = handle.apply(&sent).value();
    let piece = &on_track(&after, 3)[0];
    assert_eq!(int(piece, "/start"), START + SEC);
    assert_eq!(int(piece, "/duration"), SEC + FRAME);
    let reversed = handle
        .apply(&copy(
            11,
            3,
            json!([[START + 2 * SEC + 13_000, START + SEC + 7_000]]),
        ))
        .value();
    assert_eq!(reversed, after, "a reversed pair is the same range");
    pieces_equal_splits(&handle, &[(START + SEC, START + 2 * SEC + FRAME)]);
}

#[test]
fn an_empty_list_and_ranges_empty_on_the_grid_are_identities() {
    let handle = plain();
    assert!(matches!(
        handle.try_apply(&copy(11, 3, json!([]))),
        Ok(Outcome::Identity)
    ));
    assert!(matches!(
        handle.try_apply(&copy(11, 3, json!([[START + SEC, START + SEC + 3_000]]))),
        Ok(Outcome::Identity)
    ));
    assert!(matches!(
        handle.try_apply(&copy(11, 3, json!([[START, START], [END, END + 4_000]]))),
        Ok(Outcome::Identity)
    ));
    // Dropped before the refusals: an empty range outside the clip is not
    // one.
    assert!(matches!(
        handle.try_apply(&copy(11, 3, json!([[9 * SEC, 9 * SEC]]))),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn ranges_are_sorted_by_start() {
    let handle = plain();
    let sorted = handle
        .apply(&copy(
            11,
            3,
            json!([[START, START + SEC], [START + 2 * SEC, END]]),
        ))
        .value();
    let shuffled = handle
        .apply(&copy(
            11,
            3,
            json!([[START + 2 * SEC, END], [START, START + SEC]]),
        ))
        .value();
    assert_eq!(sorted, shuffled);
}

// ---- switches, link, nest ------------------------------------------------

fn enabled(clip: &Value, half: &str) -> bool {
    clip.pointer(&format!("/enabled/{half}"))
        .and_then(Value::as_bool)
        .unwrap_or(true)
}

#[test]
fn video_and_audio_set_each_pieces_switches_when_given() {
    let handle = plain();
    let ranges = json!([[START, START + SEC], [START + 2 * SEC, END]]);
    let mut off = copy(11, 3, ranges.clone());
    off["video"] = json!(false);
    let after = handle.apply(&off).value();
    for piece in on_track(&after, 3) {
        assert!(!enabled(&piece, "video"));
        assert!(enabled(&piece, "audio"));
    }
    let mut both = copy(11, 3, ranges.clone());
    both["video"] = json!(true);
    both["audio"] = json!(false);
    for piece in on_track(&handle.apply(&both).value(), 3) {
        assert!(enabled(&piece, "video"));
        assert!(!enabled(&piece, "audio"));
    }
    // Absent keeps the clip's own: a clip with its sound off copies off.
    let quiet = handle.apply(&json!({"op": "set_enabled", "clip": 11, "audio": false}));
    for piece in on_track(&quiet.apply(&copy(11, 3, ranges)).value(), 3) {
        assert!(enabled(&piece, "video"));
        assert!(!enabled(&piece, "audio"));
    }
}

#[test]
fn a_copy_of_a_linked_clip_has_no_link() {
    let linked = plain().apply(&json!({"op": "detach_audio", "clip": 11}));
    let value = linked.value();
    let partner = int(by_id(&value, "/clips", 11), "/linked");
    let free = array(&value, "/tracks")
        .iter()
        .map(|t| int(t, "/id"))
        .find(|t| on_track(&value, *t).is_empty())
        .expect("an empty track");
    let after = linked
        .apply(&copy(11, free as u32, json!([[START, START + SEC]])))
        .value();
    let piece = &on_track(&after, free)[0];
    assert!(
        piece.get("linked").is_none_or(Value::is_null),
        "the copy kept the link"
    );
    // The pair keeps its own.
    assert_eq!(int(by_id(&after, "/clips", 11), "/linked"), partner);
    assert_eq!(int(by_id(&after, "/clips", partner as u64), "/linked"), 11);
}

#[test]
fn a_copy_has_no_transition() {
    // Clip 13 overlaps clip 11 by 10 frames with a dissolve from it;
    // the piece of 13 from its start drops the transition.
    let mut value = project(media_clip(11, 2, START, 4 * SEC, json!({})));
    value["clips"].as_array_mut().unwrap().push(media_clip(
        13,
        2,
        END - 10 * FRAME,
        2 * SEC,
        json!({"transition_in": {"kind": "cross_dissolve"}}),
    ));
    let handle = Handle::from_value(&value);
    let after = handle
        .apply(&copy(13, 3, json!([[END - 10 * FRAME, END + SEC]])))
        .value();
    let piece = &on_track(&after, 3)[0];
    assert!(piece.get("transition_in").is_none_or(Value::is_null));
    assert!(by_id(&after, "/clips", 13)["transition_in"].is_object());
}

#[test]
fn inside_a_nest_a_copy_lands_on_the_nests_track() {
    let handle = plain();
    let mut op = copy(53, 52, json!([[SEC, 2 * SEC]]));
    op["scope"] = json!(50);
    let after = handle.apply(&op).value();
    let nest = by_id(&after, "/nests", 50);
    let pieces: Vec<&Value> = array(nest, "/clips")
        .iter()
        .filter(|c| int(c, "/track") == 52)
        .collect();
    assert_eq!(pieces.len(), 1);
    assert_eq!(int(pieces[0], "/start"), SEC);
    assert_eq!(int(pieces[0], "/duration"), SEC);
    assert_eq!(int(pieces[0], "/source/in"), 3 * SEC);
    assert!(int(pieces[0], "/id") >= 100);
    // The same copy at the top level of the nest's own project agrees.
    let top = handle
        .scoped(50)
        .apply(&copy(53, 52, json!([[SEC, 2 * SEC]])));
    let expected = on_track(&top.value(), 52);
    assert_eq!(stripped(pieces[0]), stripped(&expected[0]));
}
