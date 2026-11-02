//! Black-box tests for the plan's instance keys (spec §11 TX-10, road map
//! "creator-jobs" TX1): a NESTED audio segment carries `path` — the enclosing
//! nest clip ids outermost first, then the clip's own — and `origin`, the
//! project time of the inner clip's first frame; a top-level segment carries
//! neither, so every plan without a nest is the text it was.
//!
//! The digests below are the SHA-256 of `rc_composition_plan`'s text for
//! eight non-nest projects, printed at TX1's base (`0210dfe7`) BEFORE
//! `plan.rs` changed, and pinned here: together they exercise a speed ramp,
//! `track_pans`, `automation`, `ducks`, `output`, a transition and a muted
//! track. A key written on a top-level segment changes one of them.

mod common;

use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use common::{array, int, Handle};

const SEC: i64 = 600_000;

// ---- fixtures ------------------------------------------------------------

fn video_media(id: u32) -> Value {
    json!({
        "id": id, "path": format!("/fixtures/{id}.mov"), "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

fn track(id: u32) -> Value {
    json!({ "id": id, "name": format!("Track {id}") })
}

fn media_clip(id: u32, on: u32, start: i64, duration: i64, media: u32) -> Value {
    json!({
        "id": id, "track": on, "start": start, "duration": duration,
        "source": { "kind": "media", "media": media, "in": 0 },
        "video": {}, "audio": {}
    })
}

fn nest_clip(id: u32, on: u32, start: i64, duration: i64, shows: u32) -> Value {
    json!({
        "id": id, "track": on, "start": start, "duration": duration,
        "source": { "kind": "nest", "project": shows }, "video": {}, "audio": {}
    })
}

fn nest(id: u32, tracks: Vec<Value>, clips: Vec<Value>) -> Value {
    json!({
        "id": id, "name": format!("Nest {id}"), "width": 1920, "height": 1080,
        "tracks": tracks, "clips": clips
    })
}

fn project(media: Vec<Value>, tracks: Vec<Value>, clips: Vec<Value>, nests: Vec<Value>) -> Value {
    json!({
        "version": 37,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0] },
        "media": media, "tracks": tracks, "clips": clips, "markers": [],
        "next_id": 200, "nests": nests
    })
}

/// Two media clips abutting on track 3 and one on track 4 in front of them.
fn base() -> Value {
    project(
        vec![video_media(1), video_media(2)],
        vec![track(3), track(4)],
        vec![
            media_clip(10, 3, 0, 4 * SEC, 1),
            media_clip(11, 3, 4 * SEC, 4 * SEC, 2),
            media_clip(12, 4, SEC, 6 * SEC, 2),
        ],
        vec![],
    )
}

/// The eight non-nest projects whose plans are pinned.
fn pinned() -> Vec<(&'static str, Handle)> {
    let plain = Handle::from_value(&base());
    let mut ramp = base();
    ramp["clips"][0]["actions"] = json!([{ "id": 90, "start": SEC, "duration": 2 * SEC,
                                           "curve": "linear", "end": { "speed": 2.0 } }]);
    let mut automation = base();
    automation["clips"][1]["actions"] = json!([{ "id": 91, "start": SEC, "duration": SEC,
                                                 "curve": "linear",
                                                 "end": { "audio": { "pan": 0.5 } } }]);
    let mut ducks = base();
    ducks["media"][0]["speech"] = json!([[SEC, 3 * SEC]]);
    ducks["clips"][0]["audio"] = json!({ "duck": { "level": 0.2, "attack": SEC / 10,
                                                   "release": SEC / 5, "mode": "speech",
                                                   "pre_roll": 3 * SEC / 10,
                                                   "hold": 4 * SEC / 10 } });
    vec![
        ("plain", plain.duplicate()),
        ("ramp", Handle::from_value(&ramp)),
        (
            "track_pans",
            plain.apply(&json!({ "op": "set_track", "track": 4, "pan": -0.25 })),
        ),
        ("automation", Handle::from_value(&automation)),
        ("ducks", Handle::from_value(&ducks)),
        (
            "output",
            plain.apply(&json!({ "op": "set_canvas", "output": "hlg" })),
        ),
        (
            "transition",
            plain.apply(&json!({ "op": "add_transition", "clip": 11, "duration": SEC })),
        ),
        (
            "muted",
            plain.apply(&json!({ "op": "set_track", "track": 4, "muted": true })),
        ),
    ]
}

/// Each pinned project's plan digest at TX1's base.
const DIGESTS: [(&str, &str); 8] = [
    (
        "plain",
        "7a71c28b5f9fe040afca3d83faba0cc35a7b986cce7d793c0c434f60c0ae0bda",
    ),
    (
        "ramp",
        "deb865b35ef619b408a1d6bc936f19cf12fe13f24a3ffd2f9faf45d5190b6213",
    ),
    (
        "track_pans",
        "3a3d439bf15aff894e62947b36f97c2f18a507eb2f5d049cd7f21ac56bbe9f1e",
    ),
    (
        "automation",
        "8be98d51b68b7f03d891311ddb1fc1659614411b4c899377bb0c6a2dec819700",
    ),
    (
        "ducks",
        "08be283a5f2463f34e4ed3e7e228bd5040ec32ad6e591a6ce68ea953a3c1767e",
    ),
    (
        "output",
        "cae62c1f446262f9da731a1a552f13510e5b8f222311781c32f294a7e4354f83",
    ),
    (
        "transition",
        "ba0e1c68383e5ecddc7cfa067557d5afa07c74c45e0366aa8376f2b61de6e0a7",
    ),
    (
        "muted",
        "16e0f782b70672faeb377ec226eead4c8af67e1d893b7f98063b2cad0ae918d1",
    ),
];

fn digest(text: &str) -> String {
    Sha256::digest(text.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn audio_segments(plan: &Value) -> Vec<Value> {
    array(plan, "/audio_tracks")
        .iter()
        .flat_map(|t| array(t, "/segments").clone())
        .collect()
}

fn segments_of(plan: &Value, clip: i64) -> Vec<Value> {
    audio_segments(plan)
        .into_iter()
        .filter(|s| int(s, "/clip") == clip)
        .collect()
}

fn path(segment: &Value) -> Vec<i64> {
    array(segment, "/path")
        .iter()
        .map(|v| v.as_i64().expect("a path id is an integer"))
        .collect()
}

// ---- tests -----------------------------------------------------------------

#[test]
fn every_plan_without_a_nest_is_the_text_it_was() {
    for ((name, handle), (pinned_name, pinned)) in pinned().into_iter().zip(DIGESTS) {
        assert_eq!(name, pinned_name);
        assert_eq!(digest(&handle.plan_text()), pinned, "{name}'s plan moved");
    }
}

#[test]
fn the_fixtures_exercise_what_they_are_named_for() {
    let plans: Vec<(&str, Value)> = pinned().into_iter().map(|(n, h)| (n, h.plan())).collect();
    let find = |name: &str| {
        plans
            .iter()
            .find(|(n, _)| *n == name)
            .map(|(_, p)| p.clone())
    };
    let has = |plan: &Value, key: &str| audio_segments(plan).iter().any(|s| s.get(key).is_some());
    assert!(has(&find("ramp").expect("ramp"), "ramp"));
    assert!(has(&find("track_pans").expect("pans"), "track_pans"));
    assert!(has(&find("automation").expect("automation"), "automation"));
    assert!(!array(&find("ducks").expect("ducks"), "/ducks").is_empty());
    assert_eq!(find("output").expect("output")["output"], json!("hlg"));
    assert_ne!(find("transition"), find("plain"));
    assert_ne!(find("muted"), find("plain"));
}

#[test]
fn no_top_level_segment_carries_path_or_origin() {
    for (name, handle) in pinned() {
        for segment in audio_segments(&handle.plan()) {
            assert!(segment.get("path").is_none(), "{name}: {segment}");
            assert!(segment.get("origin").is_none(), "{name}: {segment}");
        }
    }
}

/// A nest (4) holding clip 6 at 1 s for 2 s, shown by nest clip 3 at 3 s and
/// nest clip 7 at 10 s, beside a top-level clip 8.
fn nest_twice() -> Handle {
    Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![
            nest_clip(3, 2, 3 * SEC, 4 * SEC, 4),
            nest_clip(7, 2, 10 * SEC, 4 * SEC, 4),
            media_clip(8, 2, 20 * SEC, 2 * SEC, 1),
        ],
        vec![nest(
            4,
            vec![track(5)],
            vec![media_clip(6, 5, SEC, 2 * SEC, 1)],
        )],
    ))
}

#[test]
fn a_nest_shown_twice_gives_two_segments_with_their_own_path_and_origin() {
    let plan = nest_twice().plan();
    let mut inner = segments_of(&plan, 6);
    inner.sort_by_key(|s| int(s, "/start"));
    assert_eq!(inner.len(), 2, "{plan}");
    assert_eq!(path(&inner[0]), vec![3, 6]);
    assert_eq!(path(&inner[1]), vec![7, 6]);
    // The inner clip starts 1 s into the nest: at 4 s under clip 3 and 11 s
    // under clip 7.
    assert_eq!(int(&inner[0], "/origin"), 4 * SEC);
    assert_eq!(int(&inner[1], "/origin"), 11 * SEC);
    assert_eq!(int(&inner[0], "/start"), 4 * SEC);
    assert_eq!(int(&inner[1], "/start"), 11 * SEC);
    let top = segments_of(&plan, 8);
    assert_eq!(top.len(), 1);
    assert!(top[0].get("path").is_none() && top[0].get("origin").is_none());
}

#[test]
fn a_nest_clip_shorter_than_its_nest_cuts_the_segment_and_keeps_the_origin() {
    // The inner clip runs 1 s – 5 s of its nest; nest clip 3 at 3 s shows
    // only 3 s of it, so the segment is 4 s – 6 s with its origin at 4 s.
    let plan = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![nest_clip(3, 2, 3 * SEC, 3 * SEC, 4)],
        vec![nest(
            4,
            vec![track(5)],
            vec![media_clip(6, 5, SEC, 4 * SEC, 1)],
        )],
    ))
    .plan();
    let inner = segments_of(&plan, 6);
    assert_eq!(inner.len(), 1, "{plan}");
    assert_eq!(path(&inner[0]), vec![3, 6]);
    assert_eq!(int(&inner[0], "/origin"), 4 * SEC);
    assert_eq!(int(&inner[0], "/start"), 4 * SEC);
    assert_eq!(int(&inner[0], "/duration"), 2 * SEC);
}

#[test]
fn a_nest_in_a_nest_gives_a_three_id_path() {
    let plan = Handle::from_value(&project(
        vec![video_media(1)],
        vec![track(2)],
        vec![nest_clip(3, 2, 2 * SEC, 6 * SEC, 4)],
        vec![
            nest(4, vec![track(5)], vec![nest_clip(6, 5, SEC, 4 * SEC, 7)]),
            nest(7, vec![track(8)], vec![media_clip(9, 8, SEC, 2 * SEC, 1)]),
        ],
    ))
    .plan();
    let inner = segments_of(&plan, 9);
    assert_eq!(inner.len(), 1, "{plan}");
    assert_eq!(path(&inner[0]), vec![3, 6, 9]);
    // 2 s + 1 s + 1 s.
    assert_eq!(int(&inner[0], "/origin"), 4 * SEC);
}

#[test]
fn the_keys_follow_automation_and_a_video_segment_has_neither() {
    let mut value = nest_twice().value();
    value["nests"][0]["clips"][0]["actions"] = json!([{ "id": 95, "start": 0, "duration": SEC,
                                                       "curve": "linear",
                                                       "end": { "audio": { "pan": 0.5 } } }]);
    let handle = Handle::from_value(&value);
    let text = handle.plan_text();
    let at_automation = text.find("\"automation\"").expect("automation is written");
    let at_path = text.find("\"path\"").expect("path is written");
    assert!(at_automation < at_path, "path after automation: {text}");
    let plan = handle.plan();
    for track in array(&plan, "/video_tracks") {
        for segment in array(track, "/segments") {
            assert!(segment.get("path").is_none() && segment.get("origin").is_none());
        }
    }
}
