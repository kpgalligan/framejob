//! `keep_range` (road map "creator-jobs" CJ5a, spec §11 CJ-50): the project
//! as one range of its top-level timeline, through the FFI.
//!
//! Every applied answer is held to THE overlap rule by the tests' own
//! oracle (`common/overlap_oracle.rs`), not the core's; a straddler's kept
//! piece is compared with what `split` makes at the same bound on the
//! source, moved by −`from`.

mod common;
#[path = "common/overlap_oracle.rs"]
mod overlap_oracle;

use common::{array, by_id, int, Handle, Outcome};
use overlap_oracle::overlap_rule_holds;
use serde_json::{json, Value};

/// Ticks per second (spec §5.1) and one frame at 30 fps.
const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;

fn video(id: u32) -> Value {
    json!({"id": id, "path": format!("/fixtures/v{id}.mov"), "kind": "video",
           "duration": 600 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
           "has_video": true, "has_audio": true})
}

fn lut(id: u32) -> Value {
    json!({"id": id, "path": format!("/fixtures/l{id}.cube"), "kind": "lut"})
}

/// A media clip of media 1 reading from `r#in`.
fn clip(id: u32, track: u32, start: i64, duration: i64, r#in: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
           "source": {"kind": "media", "media": 1, "in": r#in},
           "video": {}, "audio": {}})
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

fn one_track(clips: Vec<Value>) -> Value {
    project(json!([{"id": 8, "name": "Track 1"}]), clips)
}

fn keep(from: i64, to: i64) -> Value {
    json!({"op": "keep_range", "from": from, "to": to})
}

/// The op applied, its answer held to the overlap oracle.
fn kept(handle: &Handle, from: i64, to: i64) -> Value {
    let value = handle.apply(&keep(from, to)).value();
    assert!(
        overlap_rule_holds(&value),
        "keep_range {from}..{to} broke the overlap rule: {value}"
    );
    value
}

/// `(track, start, duration, in)` of every top-level clip, sorted.
fn layout(value: &Value) -> Vec<(i64, i64, i64, i64)> {
    let mut out: Vec<(i64, i64, i64, i64)> = array(value, "/clips")
        .iter()
        .map(|c| {
            (
                int(c, "/track"),
                int(c, "/start"),
                int(c, "/duration"),
                c["source"]["in"].as_i64().unwrap_or(-1),
            )
        })
        .collect();
    out.sort();
    out
}

/// `split`'s second half of `clip` at `at` on the source, moved by −`from`.
fn split_second(source: &Handle, clip: u32, at: i64, from: i64) -> Value {
    let split = source
        .apply(&json!({"op": "split", "clips": [clip], "at": at}))
        .value();
    let mut second = array(&split, "/clips")
        .iter()
        .find(|c| int(c, "/start") == at)
        .cloned()
        .expect("the second half");
    second["start"] = json!(at - from);
    second
}

/// A [0, 4 s) and B [3 s, 8 s), a one-second cross dissolve, alone on
/// track 1.
fn dissolve() -> Handle {
    let mut b = clip(11, 8, 3 * SEC, 5 * SEC, 10 * SEC);
    b["transition_in"] = json!({"kind": "cross_dissolve"});
    Handle::from_value(&one_track(vec![clip(10, 8, 0, 4 * SEC, 0), b]))
}

// ---- K1 ------------------------------------------------------------------

#[test]
fn k1_inside_kept_and_moved_outside_removed_straddlers_cut_on_every_track_locks_kept() {
    let source = Handle::from_value(&project(
        json!([{"id": 8, "name": "A"}, {"id": 9, "name": "B", "locked": true}]),
        vec![
            clip(10, 8, 0, 2 * SEC, 0),
            clip(11, 8, 2 * SEC, 3 * SEC, 0),
            clip(12, 8, 5 * SEC, SEC, 0),
            clip(13, 8, 7 * SEC, 2 * SEC, 0),
            clip(14, 8, 9 * SEC, SEC, 0),
            clip(20, 9, SEC, 3 * SEC, 0),
            clip(21, 9, 8 * SEC, SEC, 0),
        ],
    ));
    let after = kept(&source, 3 * SEC, 8 * SEC);
    assert_eq!(
        layout(&after),
        vec![
            (8, 0, 2 * SEC, SEC),
            (8, 2 * SEC, SEC, 0),
            (8, 4 * SEC, SEC, 0),
            (9, 0, SEC, 2 * SEC),
        ]
    );
    assert_eq!(by_id(&after, "/clips", 12)["start"], json!(2 * SEC));
    assert_eq!(by_id(&after, "/clips", 13)["duration"], json!(SEC));
    // The locked track was cut too, and keeps its lock; both tracks stay.
    assert_eq!(array(&after, "/tracks").len(), 2);
    assert_eq!(by_id(&after, "/tracks", 9)["locked"], json!(true));
    // The straddlers' pieces are `split`'s, moved.
    let piece = array(&after, "/clips")
        .iter()
        .find(|c| int(c, "/track") == 8 && int(c, "/start") == 0)
        .cloned()
        .unwrap();
    assert_eq!(piece, split_second(&source, 11, 3 * SEC, 3 * SEC));
}

// ---- K2, K3, K14: THE overlap rule at the edges --------------------------

#[test]
fn k2_from_at_inside_and_at_the_end_of_an_overlap_drops_the_outgoing_and_hard_starts() {
    let source = dissolve();
    for from in [3 * SEC, 3 * SEC + SEC / 2, 4 * SEC] {
        let after = kept(&source, from, 7 * SEC);
        let clips = array(&after, "/clips");
        assert_eq!(clips.len(), 1, "from {from}: {after}");
        let incoming = &clips[0];
        assert_eq!(int(incoming, "/start"), 0, "from {from}");
        assert_eq!(int(incoming, "/duration"), 7 * SEC - from, "from {from}");
        assert_eq!(
            int(incoming, "/source/in"),
            10 * SEC + (from - 3 * SEC),
            "from {from}: the incoming clip's piece"
        );
        assert!(
            incoming["transition_in"].is_null(),
            "from {from}: a hard start, {incoming}"
        );
    }
}

#[test]
fn k3_to_just_after_inside_and_at_the_end_of_an_overlap_drops_the_incoming() {
    let source = dissolve();
    for to in [3 * SEC + FRAME, 3 * SEC + SEC / 2, 4 * SEC] {
        let after = kept(&source, SEC, to);
        let clips = array(&after, "/clips");
        assert_eq!(clips.len(), 1, "to {to}: {after}");
        let outgoing = &clips[0];
        assert_eq!(int(outgoing, "/start"), 0, "to {to}");
        assert_eq!(int(outgoing, "/duration"), to - SEC, "to {to}");
        assert_eq!(int(outgoing, "/source/in"), SEC, "to {to}");
    }
}

#[test]
fn k14_both_bounds_in_one_overlap_keep_the_incoming_piece_hard_cut() {
    let after = kept(&dissolve(), 3 * SEC + SEC / 5, 3 * SEC + 4 * SEC / 5);
    let clips = array(&after, "/clips");
    assert_eq!(clips.len(), 1, "{after}");
    let incoming = &clips[0];
    assert_eq!(int(incoming, "/start"), 0);
    assert_eq!(int(incoming, "/duration"), 3 * SEC / 5);
    assert_eq!(int(incoming, "/source/in"), 10 * SEC + SEC / 5);
    assert!(incoming["transition_in"].is_null(), "{incoming}");
}

// ---- K4 ------------------------------------------------------------------

#[test]
fn k4_a_transition_inside_whose_clip_an_edge_cut_too_short_is_refused_with_source_ids() {
    let from = 2 * SEC + SEC / 5;
    dissolve().refuses_with(
        &keep(from, 9 * SEC),
        &format!(
            "Keeping {from} to {} ticks would leave clips 10 and 11 overlapping by {SEC} ticks, \
             more than half of the shorter piece ({} ticks); move an edge further from their \
             transition.",
            9 * SEC,
            (4 * SEC - from) / 2
        ),
    );
}

// ---- K5, K6: `split`'s rules ---------------------------------------------

#[test]
fn k5_a_ramped_clip_across_from_is_split_s_second_half() {
    let mut ramped = clip(11, 8, 0, 4 * SEC, 0);
    ramped["actions"] = json!([{"id": 21, "start": 0, "duration": 4 * SEC,
                                "curve": "ease_in_out", "end": {"speed": 3.0}}]);
    let source = Handle::from_value(&one_track(vec![ramped]));
    let from = SEC + SEC / 2;
    let after = kept(&source, from, 10 * SEC);
    assert_eq!(array(&after, "/clips").len(), 1);
    assert_eq!(
        array(&after, "/clips")[0],
        split_second(&source, 11, from, from)
    );
}

#[test]
fn k6_a_timed_caption_page_across_from_is_split_s_words() {
    let page = json!({"id": 11, "track": 8, "start": 0, "duration": 6 * SEC,
                      "source": {"kind": "text"}, "video": {},
                      "text": {"content": "so here's the thing"}});
    let source = Handle::from_value(&one_track(vec![page])).apply(&json!({
        "op": "set_text", "clips": [11], "patch": {"words": [
            {"start": 0, "end": 100_000}, {"start": 120_000, "end": 280_000},
            {"start": 280_000, "end": 340_000}, {"start": 360_000, "end": 620_000}]}}));
    let from = 10 * FRAME;
    let after = kept(&source, from, 10 * SEC);
    let piece = &array(&after, "/clips")[0];
    assert_eq!(piece, &split_second(&source, 11, from, from));
    assert_eq!(piece["text"]["words"][0]["start"], json!(-from));
}

// ---- K7: linked pairs ----------------------------------------------------

fn half(id: u32, track: u32, start: i64, duration: i64, picture: bool, partner: u32) -> Value {
    let mut c = clip(id, track, start, duration, start);
    c["enabled"] = json!({"video": picture, "audio": !picture});
    c["linked"] = json!(partner);
    c
}

fn two_tracks(clips: Vec<Value>) -> Handle {
    Handle::from_value(&project(
        json!([{"id": 8, "name": "Sound"}, {"id": 9, "name": "Picture"}]),
        clips,
    ))
}

fn linked_of(value: &Value, track: i64) -> (u64, Option<u64>) {
    let c = array(value, "/clips")
        .iter()
        .find(|c| int(c, "/track") == track)
        .unwrap_or_else(|| panic!("no clip on track {track}: {value}"));
    (
        c["id"].as_u64().unwrap(),
        c.get("linked").and_then(Value::as_u64),
    )
}

#[test]
fn k7_a_pair_both_across_an_edge_keeps_its_halves_linked() {
    let source = two_tracks(vec![
        half(10, 9, 0, 6 * SEC, true, 11),
        half(11, 8, 0, 6 * SEC, false, 10),
    ]);
    let after = kept(&source, 2 * SEC, 4 * SEC);
    let (picture, to_sound) = linked_of(&after, 9);
    let (sound, to_picture) = linked_of(&after, 8);
    assert_eq!(to_sound, Some(sound));
    assert_eq!(to_picture, Some(picture));
}

#[test]
fn k7_a_pair_one_across_links_to_the_kept_half_or_clears() {
    // J-cut: the sound leads the picture; only the sound crosses `from`.
    let source = two_tracks(vec![
        half(10, 9, 3 * SEC, 3 * SEC, true, 11),
        half(11, 8, 0, 6 * SEC, false, 10),
    ]);
    let after = kept(&source, SEC, 4 * SEC);
    let (picture, to_sound) = linked_of(&after, 9);
    let (sound, to_picture) = linked_of(&after, 8);
    assert_eq!(to_sound, Some(sound));
    assert_eq!(to_picture, Some(picture));

    // L-cut: the picture ends before the range; the sound alone is kept.
    let source = two_tracks(vec![
        half(10, 9, 0, 2 * SEC, true, 11),
        half(11, 8, 0, 6 * SEC, false, 10),
    ]);
    let after = kept(&source, 3 * SEC, 5 * SEC);
    assert_eq!(array(&after, "/clips").len(), 1);
    assert_eq!(linked_of(&after, 8).1, None);
}

// ---- K8: markers ---------------------------------------------------------

#[test]
fn k8_markers_inside_are_kept_and_moved_the_rest_removed() {
    let mut value = one_track(vec![clip(10, 8, 0, 10 * SEC, 0)]);
    value["markers"] = json!([
        {"id": 50, "time": SEC, "name": "before"},
        {"id": 51, "time": 2 * SEC, "name": "at from"},
        {"id": 52, "time": 3 * SEC, "name": "inside"},
        {"id": 53, "time": 5 * SEC, "name": "at to"},
        {"id": 54, "time": 7 * SEC, "name": "after"}
    ]);
    let after = kept(&Handle::from_value(&value), 2 * SEC, 5 * SEC);
    let markers: Vec<(i64, i64)> = array(&after, "/markers")
        .iter()
        .map(|m| (int(m, "/id"), int(m, "/time")))
        .collect();
    assert_eq!(markers, vec![(51, 0), (52, SEC)]);
}

// ---- K9: what a range leaves unused --------------------------------------

#[test]
fn k9_media_and_nests_no_kept_clip_reaches_are_removed() {
    let mut looked = clip(10, 8, 0, 2 * SEC, 0);
    looked["video"] = json!({"look": {"kind": "lut", "media": 3}});
    looked["actions"] = json!([{"id": 60, "start": 0, "duration": SEC, "curve": "linear",
                                "end": {"video": {"look": {"kind": "lut", "media": 4}}}}]);
    let mut outside = clip(12, 8, 8 * SEC, SEC, 0);
    outside["source"]["media"] = json!(2);
    let nest_clip = |id: u32, start: i64, nest: u32| {
        json!({"id": id, "track": 8, "start": start, "duration": SEC,
               "source": {"kind": "nest", "project": nest}, "video": {}})
    };
    let nest = |id: u32, clip_id: u32, media: u32| {
        json!({"id": id, "name": "Group", "width": 1920, "height": 1080,
               "tracks": [{"id": id + 1, "name": "Track 1"}],
               "clips": [{"id": clip_id, "track": id + 1, "start": 0, "duration": SEC,
                          "source": {"kind": "media", "media": media, "in": 0},
                          "video": {}, "audio": {}}]})
    };
    let mut value = one_track(vec![
        looked,
        nest_clip(11, 3 * SEC, 30),
        outside,
        nest_clip(13, 9 * SEC, 40),
    ]);
    let mut main = video(1);
    main["color"] = json!({"lut": 5});
    value["media"] = json!([main, video(2), lut(3), lut(4), lut(5), video(6), video(7)]);
    value["nests"] = json!([nest(30, 32, 6), nest(40, 42, 7), nest(50, 52, 7)]);
    let after = kept(&Handle::from_value(&value), 0, 5 * SEC);
    let media: Vec<i64> = array(&after, "/media")
        .iter()
        .map(|m| int(m, "/id"))
        .collect();
    assert_eq!(media, vec![1, 3, 4, 5, 6]);
    let nests: Vec<i64> = array(&after, "/nests")
        .iter()
        .map(|n| int(n, "/id"))
        .collect();
    assert_eq!(nests, vec![30]);
}

// ---- K10: a nest across an edge ------------------------------------------

#[test]
fn k10_a_nest_clip_across_either_edge_is_refused_and_one_ending_at_from_is_not() {
    let mut value = one_track(vec![
        json!({"id": 11, "track": 8, "start": 2 * SEC, "duration": 2 * SEC,
               "source": {"kind": "nest", "project": 30}, "video": {}}),
        clip(12, 8, 4 * SEC, 2 * SEC, 0),
    ]);
    value["nests"] = json!([{"id": 30, "name": "Group", "width": 1920, "height": 1080,
        "tracks": [{"id": 31, "name": "Track 1"}],
        "clips": [{"id": 32, "track": 31, "start": 0, "duration": 2 * SEC,
                   "source": {"kind": "media", "media": 1, "in": 0},
                   "video": {}, "audio": {}}]}]);
    let source = Handle::from_value(&value);
    let sentence = "Clip 11 is a nest across the range's edge; a nest clip has no in point, so a \
                    cut there would replay it from its start. Move the edge, or open the nest \
                    and unnest it.";
    source.refuses_with(&keep(3 * SEC, 10 * SEC), sentence);
    source.refuses_with(&keep(0, 3 * SEC), sentence);
    let after = kept(&source, 4 * SEC, 10 * SEC);
    assert_eq!(layout(&after), vec![(8, 0, 2 * SEC, 0)]);
    assert!(array(&after, "/nests").is_empty());
}

// ---- K11, K12, K13 -------------------------------------------------------

#[test]
fn k11_to_not_after_from_is_an_error_and_a_negative_from_clamps_to_zero() {
    let source = Handle::from_value(&one_track(vec![clip(10, 8, 0, 4 * SEC, 0)]));
    assert_eq!(
        source.errors(&keep(SEC, SEC + 1)),
        format!("keep_range's to must be after its from (from {SEC}, to {SEC} ticks, on the frame grid)")
    );
    assert_eq!(
        source.errors(&keep(2 * SEC, SEC)),
        format!(
            "keep_range's to must be after its from (from {}, to {SEC} ticks, on the frame grid)",
            2 * SEC
        )
    );
    assert_eq!(kept(&source, -SEC, 2 * SEC), kept(&source, 0, 2 * SEC));
}

#[test]
fn k12_a_range_where_nothing_plays_is_refused() {
    let source = Handle::from_value(&one_track(vec![
        clip(10, 8, 0, SEC / 2, 0),
        clip(11, 8, 3 * SEC, SEC, 0),
    ]));
    source.refuses_with(
        &keep(SEC, 2 * SEC),
        &format!("Nothing plays between {SEC} and {} ticks.", 2 * SEC),
    );
}

#[test]
fn k13_the_whole_timeline_with_nothing_unused_is_an_identity() {
    let mut value = one_track(vec![clip(10, 8, 0, 4 * SEC, 0)]);
    value["markers"] = json!([{"id": 50, "time": SEC, "name": "inside"}]);
    let source = Handle::from_value(&value);
    assert!(matches!(
        source.try_apply(&keep(0, 4 * SEC)),
        Ok(Outcome::Identity)
    ));
}
