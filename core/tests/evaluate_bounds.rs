//! The evaluator's bounds on text and on a duck (#353), held from outside
//! through the FFI.
//!
//! `set_action_end` is deliberately lenient, so an action may end on a
//! text state no direct edit could store; `actions_clamp.rs`'s `clamp_text`
//! brings the EVALUATED value back into range, where `clip_state`, the
//! recipe and `split_clip` read it. A value `check_text` accepts passes
//! unchanged. A duck's level is held to the vocabulary's 0..1 where the
//! plan's envelope is built, so a hand-written level above 1 never boosts.

mod common;

use serde_json::{json, Value};

use common::{array, at, int, num, Handle};

/// Ticks per second (spec §5.1), written out so a change to the timescale
/// fails here rather than moving with the test.
const SEC: i64 = 600_000;

/// The first composition AUDIO track id (spec §7.2), written out for the
/// reason `SEC` is.
const FIRST_AUDIO: i64 = 1001;

/// A text clip, id 11, 0..10 s, whose base text holds every bounded group:
/// an outline, a backdrop, a width and a word style with a pill and all
/// three word colours; action 21 runs over its first two seconds, linear,
/// ending on `{}`.
fn text_project() -> Handle {
    Handle::from_value(&json!({
        "version": 9,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
            "source": { "kind": "text" },
            "video": {},
            "text": {
                "content": "Hello there",
                "size": 72.0,
                "color": [1.0, 1.0, 1.0, 1.0],
                "line_spacing": 1.2,
                "outline": { "width": 2.0, "color": [0.0, 0.0, 0.0, 1.0] },
                "backdrop": { "color": [0.0, 0.0, 0.0, 0.6], "padding": 12.0, "radius": 8.0 },
                "width": 800.0,
                "word_style": {
                    "active_color": [1.0, 0.8, 0.0, 1.0],
                    "spoken_color": [0.8, 0.8, 0.8, 1.0],
                    "upcoming_color": [0.5, 0.5, 0.5, 1.0],
                    "active_scale": 1.2,
                    "pause_dim": 0.3,
                    "active_pill": { "color": [0.55, 0.27, 0.93, 1.0], "padding": 0.2,
                                     "radius": 0.25, "glide": false }
                }
            },
            "actions": [{ "id": 21, "start": 0, "duration": 2 * SEC,
                          "curve": "linear", "end": {} }]
        }],
        "next_id": 22
    }))
}

/// The fixture with an action ending far outside every text range, written
/// through the op itself.
fn out_of_range() -> Handle {
    text_project().apply(&json!({
        "op": "set_action_end", "clip": 11, "action": 21,
        "patch": { "text": {
            "size": -40.0,
            "color": [5.0, -1.0, 0.5, 2.0],
            "line_spacing": 0.0,
            "width": -10.0,
            "outline": { "width": -3.0, "color": [2.0, 0.0, 0.0, 1.0] },
            "backdrop": { "padding": -1.0, "radius": -1.0 },
            "word_style": {
                "active_scale": 9.0,
                "pause_dim": 4.0,
                "active_color": [-2.0, 1.0, 1.0, 1.0]
            }
        } }
    }))
}

fn state_text(handle: &Handle, t: i64) -> Value {
    let state = handle.clip_state(11, t).expect("clip 11 has a state");
    at(&state, "/text").clone()
}

fn colour(value: &Value, pointer: &str) -> Vec<f64> {
    array(value, pointer)
        .iter()
        .map(|c| c.as_f64().expect("a channel"))
        .collect()
}

#[test]
fn an_action_ending_out_of_range_evaluates_to_bounded_text() {
    let handle = out_of_range();
    // Past the action's end, so the end state holds whole.
    let text = state_text(&handle, 3 * SEC);

    assert_eq!(num(&text, "/size"), 1.0);
    assert_eq!(colour(&text, "/color"), vec![1.0, 0.0, 0.5, 1.0]);
    assert_eq!(num(&text, "/line_spacing"), 1.0);
    assert_eq!(num(&text, "/width"), f64::MIN_POSITIVE);
    assert_eq!(num(&text, "/outline/width"), 0.0);
    assert_eq!(colour(&text, "/outline/color"), vec![1.0, 0.0, 0.0, 1.0]);
    assert_eq!(num(&text, "/backdrop/padding"), 0.0);
    assert_eq!(num(&text, "/backdrop/radius"), 0.0);
    assert_eq!(num(&text, "/word_style/active_scale"), 1.5);
    assert_eq!(num(&text, "/word_style/pause_dim"), 1.0);
    assert_eq!(
        colour(&text, "/word_style/active_color"),
        vec![0.0, 1.0, 1.0, 1.0]
    );

    // What draws is what the inspector reads.
    let recipe = handle.recipe(3 * SEC);
    let layer = array(&recipe, "/layers")
        .iter()
        .find(|l| int(l, "/clip") == 11)
        .expect("a layer for clip 11")
        .clone();
    assert_eq!(num(&layer, "/source/text/size"), 1.0);
    assert_eq!(
        colour(&layer, "/source/text/color"),
        vec![1.0, 0.0, 0.5, 1.0]
    );
}

#[test]
fn a_lerp_inside_the_range_is_not_clamped() {
    // Halfway through a linear action: 72 + (-40 - 72) / 2 = 16, a size
    // every range holds, so the clamp leaves it exactly where the lerp put
    // it.
    let text = state_text(&out_of_range(), SEC);
    assert_eq!(num(&text, "/size"), 16.0);
}

#[test]
fn legal_text_evaluates_unchanged() {
    // Every field legal, a width in (0, 1) among them: the floor is above
    // 0, not at 1, so the clamp keeps it.
    let handle = Handle::from_value(&json!({
        "version": 9,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
            "source": { "kind": "text" },
            "video": {},
            "text": {
                "content": "Hello there",
                "size": 1.0,
                "color": [0.0, 0.25, 1.0, 0.5],
                "line_spacing": 0.5,
                "tracking": -3.0,
                "outline": { "width": 0.0, "color": [1.0, 0.0, 0.0, 0.0] },
                "backdrop": { "color": [0.2, 0.2, 0.2, 1.0], "padding": 0.0, "radius": 0.0 },
                "width": 0.5,
                "word_style": {
                    "active_color": [0.0, 0.0, 0.0, 0.0],
                    "spoken_color": [1.0, 1.0, 1.0, 1.0],
                    "upcoming_color": [0.5, 0.5, 0.5, 1.0],
                    "active_scale": 1.5,
                    "pause_dim": 1.0,
                    "active_pill": { "color": [0.1, 0.2, 0.3, 0.4], "padding": 0.0,
                                     "radius": 0.0, "glide": true }
                }
            }
        }],
        "next_id": 12
    }));

    let stored = at(&handle.value(), "/clips/0/text").clone();
    assert_eq!(state_text(&handle, SEC), stored);
}

#[test]
fn a_hand_written_duck_level_above_one_does_not_boost() {
    // Bed 11 on track 3 (0..20 s); voice 12 on track 4 (5..10 s) ducking at
    // a hand-written level of 3, which the vocabulary's 0..1 refuses at the
    // op. Held to 1, the bed is never lifted above its own gain.
    let media = |id: u32, kind: &str, has_video: bool| {
        json!({
            "id": id, "path": format!("/fixtures/{id}.mov"), "kind": kind,
            "duration": 60 * SEC,
            "width": if has_video { 1920 } else { 0 },
            "height": if has_video { 1080 } else { 0 },
            "fps": [30, 1], "has_video": has_video, "has_audio": true
        })
    };
    let handle = Handle::from_value(&json!({
        "version": 1,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media(1, "video", true), media(2, "audio", false)],
        "tracks": [{ "id": 3, "name": "Track 3" }, { "id": 4, "name": "Track 4" }],
        "clips": [
            {
                "id": 11, "track": 3, "start": 0, "duration": 20 * SEC,
                "source": { "kind": "media", "media": 1, "in": 0 },
                "video": {}, "audio": {}
            },
            {
                "id": 12, "track": 4, "start": 5 * SEC, "duration": 5 * SEC,
                "source": { "kind": "media", "media": 2, "in": 0 },
                "video": null,
                "audio": { "duck": { "level": 3.0, "attack": 0, "release": 0 } }
            }
        ],
        "next_id": 13
    }));

    let plan = handle.plan();
    let bed = array(&plan, "/audio_tracks")
        .iter()
        .find(|t| int(t, "/id") == FIRST_AUDIO)
        .expect("the bed's composition track")
        .clone();
    let ramps = array(&bed, "/ramps");
    assert!(!ramps.is_empty(), "the bed has an envelope: {bed}");
    for ramp in ramps {
        assert!(num(ramp, "/from") <= 1.0, "a ramp boosts: {ramp}");
        assert!(num(ramp, "/to") <= 1.0, "a ramp boosts: {ramp}");
    }
}
