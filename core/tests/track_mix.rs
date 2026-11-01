//! Black-box tests for a track's volume and pan (format 35, spec §11
//! AU-102..AU-104), through the C FFI as `ReelCore.swift` drives it.
//!
//! Pinned here: `set_track` stores `volume` and `pan`, refuses outside their
//! ranges in `in_range`'s sentence, and an unchanged value is an identity;
//! the track's volume is an envelope term after mute at every stage (a
//! nested clip scaled by its own track and by the nest clip's), a muted
//! track at ×4 is still silent, and a clip's volume and its track's
//! multiply; a hand-written volume past ×4 plays at ×4; the plan's audio
//! segment carries `track_pans` innermost first, cleared at a folded nest
//! clip, zeros dropped and the key absent when none remain; `nest` copies
//! volume and pan from every source track but the destination, whose copy is
//! unity and centre; `unnest` keeps neither; and a project and its plan at
//! defaults are the text they were.

mod common;

use serde_json::{json, Value};

use common::{array, assert_contains, by_id, int, num, Handle};

/// Ticks per second (spec §5.1), written out so a change to
/// `time::TIMESCALE` fails these tests instead of moving with them.
const SEC: i64 = 600_000;

const EPS: f64 = 1e-12;

// ---- fixtures ------------------------------------------------------------

/// 60 s of 1920x1080 at 30 fps with sound.
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

/// `track(id)` with `volume` and `pan` written as a file carries them.
fn mixed(id: u32, volume: f64, pan: f64) -> Value {
    json!({ "id": id, "name": format!("Track {id}"), "volume": volume, "pan": pan })
}

fn media_clip(id: u32, on: u32, start: i64, duration: i64) -> Value {
    json!({
        "id": id, "track": on, "start": start, "duration": duration,
        "source": { "kind": "media", "media": 1, "in": 0 },
        "video": {}, "audio": {}
    })
}

fn nest_clip(id: u32, on: u32, duration: i64, shows: u32, audio: Value) -> Value {
    json!({
        "id": id, "track": on, "start": 0, "duration": duration,
        "source": { "kind": "nest", "project": shows }, "video": {}, "audio": audio
    })
}

fn project(tracks: Vec<Value>, clips: Vec<Value>, nests: Vec<Value>, next_id: u32) -> Value {
    json!({
        "version": 35,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
                    "background": [0.0, 0.0, 0.0, 1.0] },
        "media": [video_media(1)], "tracks": tracks, "clips": clips, "markers": [],
        "next_id": next_id, "nests": nests
    })
}

/// One timeline track 2 (`outer`) holding clip 3 over 0 – 2 s.
fn one_clip(outer: Value) -> Handle {
    Handle::from_value(&project(
        vec![outer],
        vec![media_clip(3, 2, 0, 2 * SEC)],
        vec![],
        4,
    ))
}

/// Timeline track 2 (`outer`) holding nest clip 3 (with `audio`) over 0 –
/// 2 s, showing nest 4, whose track 5 (`inner`) holds media clip 6.
fn nested(outer: Value, inner: Value, audio: Value) -> Handle {
    Handle::from_value(&project(
        vec![outer],
        vec![nest_clip(3, 2, 2 * SEC, 4, audio)],
        vec![json!({
            "id": 4, "name": "Nest 4", "width": 1920, "height": 1080,
            "tracks": [inner], "clips": [media_clip(6, 5, 0, 2 * SEC)]
        })],
        7,
    ))
}

// ---- reading a plan --------------------------------------------------------

/// The composition audio track carrying `clip`'s segment.
fn audio_track_of(plan: &Value, clip: i64) -> &Value {
    array(plan, "/audio_tracks")
        .iter()
        .find(|t| {
            array(t, "/segments")
                .iter()
                .any(|s| int(s, "/clip") == clip)
        })
        .unwrap_or_else(|| panic!("no audio segment for clip {clip} in {plan}"))
}

fn audio_segment_of(plan: &Value, clip: i64) -> &Value {
    array(audio_track_of(plan, clip), "/segments")
        .iter()
        .find(|s| int(s, "/clip") == clip)
        .unwrap_or_else(|| panic!("no audio segment for clip {clip}"))
}

/// The one constant gain over the clip's 0 – 2 s.
fn flat_gain(plan: &Value, clip: i64) -> f64 {
    let ramps = array(audio_track_of(plan, clip), "/ramps");
    assert_eq!(ramps.len(), 1, "a constant gain is one ramp; got {ramps:?}");
    let from = num(&ramps[0], "/from");
    assert!((from - num(&ramps[0], "/to")).abs() < EPS, "{ramps:?}");
    from
}

fn track_pans(plan: &Value, clip: i64) -> Option<Vec<f64>> {
    audio_segment_of(plan, clip).get("track_pans").map(|p| {
        p.as_array()
            .expect("an array")
            .iter()
            .map(|v| v.as_f64().expect("a number"))
            .collect()
    })
}

fn close(actual: f64, expected: f64, what: &str) {
    assert!(
        (actual - expected).abs() < EPS,
        "{what}: expected {expected}, got {actual}"
    );
}

// ---- set_track -------------------------------------------------------------

#[test]
fn set_track_stores_volume_and_pan_and_an_unchanged_value_is_an_identity() {
    let base = one_clip(track(2));
    let after = base.apply(&json!({"op": "set_track", "track": 2, "volume": 0.5, "pan": -0.25}));
    let value = after.value();
    close(num(&value, "/tracks/0/volume"), 0.5, "volume");
    close(num(&value, "/tracks/0/pan"), -0.25, "pan");
    let again = after.try_apply(&json!({"op": "set_track", "track": 2, "volume": 0.5}));
    assert!(matches!(again, Ok(common::Outcome::Identity)), "{again:?}");
    // Back to the defaults writes neither key again.
    let reset = after.apply(&json!({"op": "set_track", "track": 2, "volume": 1, "pan": 0}));
    assert_eq!(reset.to_json(), base.to_json());
}

#[test]
fn set_track_refuses_a_volume_or_a_pan_out_of_range() {
    let base = one_clip(track(2));
    let message = base.errors(&json!({"op": "set_track", "track": 2, "volume": 5}));
    assert_contains(&message, "volume must be between 0 and 4, not 5");
    let message = base.errors(&json!({"op": "set_track", "track": 2, "volume": -0.5}));
    assert_contains(&message, "volume must be between 0 and 4, not -0.5");
    let message = base.errors(&json!({"op": "set_track", "track": 2, "pan": 2}));
    assert_contains(&message, "pan must be between -1 and 1, not 2");
    let message = base.errors(&json!({"op": "set_track", "track": 2, "pan": -1.5}));
    assert_contains(&message, "pan must be between -1 and 1, not -1.5");
    // The ends themselves are in range.
    base.apply(&json!({"op": "set_track", "track": 2, "volume": 4, "pan": -1}));
    base.apply(&json!({"op": "set_track", "track": 2, "volume": 0, "pan": 1}));
}

// ---- the envelope ----------------------------------------------------------

#[test]
fn a_track_volume_scales_its_clips_envelope() {
    let plan = one_clip(mixed(2, 0.5, 0.0)).plan();
    close(flat_gain(&plan, 3), 0.5, "track volume 0.5");
}

#[test]
fn a_clip_volume_and_its_track_volume_multiply() {
    let mut clip = media_clip(3, 2, 0, 2 * SEC);
    clip["audio"] = json!({"volume": 2.0});
    let plan =
        Handle::from_value(&project(vec![mixed(2, 0.25, 0.0)], vec![clip], vec![], 4)).plan();
    close(flat_gain(&plan, 3), 0.5, "clip 2 × track 0.25");
}

#[test]
fn a_nested_clip_is_scaled_by_its_own_track_and_the_nest_clips() {
    let plan = nested(mixed(2, 0.5, 0.0), mixed(5, 0.5, 0.0), json!({})).plan();
    close(flat_gain(&plan, 6), 0.25, "inner 0.5 × outer 0.5");
    let plan = nested(mixed(2, 0.5, 0.0), track(5), json!({})).plan();
    close(flat_gain(&plan, 6), 0.5, "outer alone");
    let plan = nested(track(2), mixed(5, 0.5, 0.0), json!({})).plan();
    close(flat_gain(&plan, 6), 0.5, "inner alone");
}

#[test]
fn a_muted_track_at_four_times_is_still_silent() {
    let mut muted = mixed(2, 4.0, 0.0);
    muted["muted"] = json!(true);
    let plan = one_clip(muted).plan();
    close(flat_gain(&plan, 3), 0.0, "mute wins over the fader");
}

#[test]
fn a_hand_written_volume_past_four_plays_at_four() {
    let plan = one_clip(mixed(2, 9.0, 0.0)).plan();
    close(flat_gain(&plan, 3), 4.0, "clamped to TRACK_VOLUME_MAX");
}

// ---- the plan's track_pans -------------------------------------------------

#[test]
fn a_panned_track_puts_its_pan_on_the_segment() {
    let plan = one_clip(mixed(2, 1.0, -0.5)).plan();
    assert_eq!(track_pans(&plan, 3), Some(vec![-0.5]));
    // A hand-written pan past the end is clamped.
    let plan = one_clip(mixed(2, 1.0, -3.0)).plan();
    assert_eq!(track_pans(&plan, 3), Some(vec![-1.0]));
}

#[test]
fn track_pans_run_innermost_first_and_drop_zeros() {
    let plan = nested(mixed(2, 1.0, 0.5), mixed(5, 1.0, -0.5), json!({})).plan();
    assert_eq!(track_pans(&plan, 6), Some(vec![-0.5, 0.5]));
    let plan = nested(mixed(2, 1.0, 0.5), track(5), json!({})).plan();
    assert_eq!(track_pans(&plan, 6), Some(vec![0.5]));
    let plan = nested(track(2), mixed(5, 1.0, -0.5), json!({})).plan();
    assert_eq!(track_pans(&plan, 6), Some(vec![-0.5]));
}

#[test]
fn a_folded_nest_clip_drops_the_pans_inside_it() {
    // The nest clip asks for mono: its fold flattens the inner track's pan,
    // and only the outer track's survives.
    let plan = nested(
        mixed(2, 1.0, 0.5),
        mixed(5, 1.0, -0.5),
        json!({"mono": true}),
    )
    .plan();
    assert_eq!(track_pans(&plan, 6), Some(vec![0.5]));
    let plan = nested(track(2), mixed(5, 1.0, -0.5), json!({"mono": true})).plan();
    assert_eq!(track_pans(&plan, 6), None, "all dropped: no key");
}

#[test]
fn a_clips_own_mono_keeps_its_track_pan() {
    let mut clip = media_clip(3, 2, 0, 2 * SEC);
    clip["audio"] = json!({"mono": true});
    let plan =
        Handle::from_value(&project(vec![mixed(2, 1.0, -0.5)], vec![clip], vec![], 4)).plan();
    assert_eq!(track_pans(&plan, 3), Some(vec![-0.5]));
}

#[test]
fn defaults_write_no_keys_and_the_same_plan() {
    let bare = one_clip(track(2));
    let written = one_clip(mixed(2, 1.0, 0.0));
    assert_eq!(bare.to_json(), written.to_json());
    let stored = bare.value()["tracks"][0].clone();
    assert!(
        stored.get("volume").is_none() && stored.get("pan").is_none(),
        "{stored}"
    );
    assert_eq!(bare.plan_text(), written.plan_text());
    assert!(
        !bare.plan_text().contains("track_pans"),
        "{}",
        bare.plan_text()
    );
    let nested_bare = nested(track(2), track(5), json!({}));
    assert!(!nested_bare.plan_text().contains("track_pans"));
}

// ---- nest and unnest -------------------------------------------------------

/// Two timeline tracks: 2 (back) holding clip 4 over 0 – 2 s, and 3 (front)
/// holding clip 5 over 1 – 3 s.
fn two_tracks(back: Value, front: Value) -> Handle {
    Handle::from_value(&project(
        vec![back, front],
        vec![media_clip(4, 2, 0, 2 * SEC), media_clip(5, 3, SEC, 2 * SEC)],
        vec![],
        6,
    ))
}

#[test]
fn nest_copies_volume_and_pan_from_every_source_track_but_the_destination() {
    let before = two_tracks(mixed(2, 0.5, -0.5), mixed(3, 0.25, 0.75));
    let nest_id = int(&before.value(), "/next_id") as u64;
    let after = before
        .apply(&json!({"op": "nest", "clips": [4, 5]}))
        .value();
    // The nest clip lands on track 3, the front-most.
    let nest_clip = &array(&after, "/clips")[0];
    assert_eq!(int(nest_clip, "/track"), 3);
    let nest = by_id(&after, "/nests", nest_id);
    let tracks = array(nest, "/tracks");
    close(
        num(&tracks[0], "/volume"),
        0.5,
        "the back source track's volume",
    );
    close(num(&tracks[0], "/pan"), -0.5, "the back source track's pan");
    assert!(
        tracks[1].get("volume").is_none(),
        "destination copy unity: {}",
        tracks[1]
    );
    assert!(
        tracks[1].get("pan").is_none(),
        "destination copy centre: {}",
        tracks[1]
    );
    // The timeline's tracks keep their own.
    close(
        num(&after, "/tracks/1/volume"),
        0.25,
        "track 3 keeps its volume",
    );
}

#[test]
fn nesting_a_clip_alone_leaves_its_level_and_pans_unchanged() {
    let before = one_clip(mixed(2, 0.5, -0.5));
    let plan = before.plan();
    let after = before.apply(&json!({"op": "nest", "clips": [3]}));
    let nested_plan = after.plan();
    close(
        flat_gain(&nested_plan, 3),
        flat_gain(&plan, 3),
        "level unchanged",
    );
    assert_eq!(track_pans(&nested_plan, 3), track_pans(&plan, 3));
}

#[test]
fn a_clip_from_another_source_track_gets_the_destinations_terms_too() {
    let before = two_tracks(mixed(2, 0.5, 0.0), mixed(3, 0.5, 0.25));
    let after = before.apply(&json!({"op": "nest", "clips": [4, 5]})).plan();
    // Clip 4: its own copied 0.5 × the destination's 0.5.
    let ramps = array(audio_track_of(&after, 4), "/ramps");
    close(num(&ramps[0], "/from"), 0.25, "clip 4 under both tracks");
    assert_eq!(track_pans(&after, 4), Some(vec![0.25]));
    assert_eq!(track_pans(&after, 5), Some(vec![0.25]));
}

#[test]
fn unnest_keeps_neither() {
    let before = nested(track(2), mixed(5, 0.5, -0.5), json!({}));
    let after = before.apply(&json!({"op": "unnest", "clip": 3}));
    let value = after.value();
    for t in array(&value, "/tracks") {
        assert!(t.get("volume").is_none() && t.get("pan").is_none(), "{t}");
    }
    let plan = after.plan();
    let clip = int(&array(&value, "/clips")[0], "/id");
    close(flat_gain(&plan, clip), 1.0, "unity on the timeline");
    assert_eq!(track_pans(&plan, clip), None);
}
