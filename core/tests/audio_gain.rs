//! The volume ceiling (spec §5.2, §11 AU-1): `audio.volume` may reach ×32.
//!
//! Three claims, each about a place the ceiling is read:
//!
//! 1. **The app's copy is the core's.** `AudioNormalize.maxGain` is the one
//!    Swift spelling of the number — Normalize clamps to it, the Volume row's
//!    field tops out at it, and the agent's sentences print it — and it has
//!    no FFI path, so its `static let` line is read as text (the
//!    `maxTextureSide` precedent in `graphic_ffi.rs`) and held to what
//!    `set_audio` accepts and refuses. A copy that drifts below the core
//!    would stop Normalize short for no reason; one above it would have
//!    Normalize write a volume the core refuses, as a dialog.
//! 2. **A gain past the old ×4 reaches the mix.** The envelope the plan hands
//!    AVFoundation carries the stored volume, not a ×4 clamp, which is what
//!    the owner's quiet microphone needed (×7.55 to reach −1 dBFS).
//! 3. **An action's end past ×4 is played as asked**, and one past the
//!    ceiling is clamped to it (`clamp_audio`), not to 4.

mod common;

use std::fs;

use serde_json::{json, Value};

use common::{array, int, num, Handle};

const AUDIO_NORMALIZE: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../app/Sources/AudioNormalize.swift"
);

/// Ticks per second (spec §5.1).
const SEC: i64 = 600_000;

/// The gain the owner's RØDE recording wanted (−18.56 dBFS to −1 dBFS).
const MIC_GAIN: f64 = 7.548;

/// `AudioNormalize.maxGain`, read off its `static let` line.
fn app_ceiling() -> f64 {
    let text = fs::read_to_string(AUDIO_NORMALIZE).expect("app/Sources/AudioNormalize.swift");
    text.lines()
        .find_map(|line| line.trim_start().strip_prefix("static let maxGain = "))
        .and_then(|rest| rest.trim().parse().ok())
        .expect("AudioNormalize.swift has a `static let maxGain = <number>` line")
}

/// One 10 s clip of a media with sound on one track; clip 11.
fn one_clip() -> Handle {
    Handle::from_value(&json!({
        "version": 1,
        "canvas": {
            "width": 1920, "height": 1080, "fps": [30, 1],
            "background": [0.0, 0.0, 0.0, 1.0],
            "fit_new_clips": true, "timecode_frames": true
        },
        "media": [{
            "id": 1, "path": "/fixtures/mic.m4a", "bookmark": null, "kind": "audio",
            "duration": 30 * SEC, "width": 0, "height": 0, "fps": [30, 1],
            "has_video": false, "has_audio": true, "has_alpha": false
        }],
        "tracks": [{ "id": 2, "name": "Track 2" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "audio": {}
        }],
        "markers": [],
        "next_id": 12
    }))
}

fn set_volume(volume: f64) -> Value {
    json!({ "op": "set_audio", "clips": [11], "patch": { "volume": volume } })
}

/// Every ramp of the composition audio track that carries clip 11.
fn ramps(handle: &Handle) -> Vec<Value> {
    let plan = handle.plan();
    for comp in array(&plan, "/audio_tracks") {
        if array(comp, "/segments")
            .iter()
            .any(|s| int(s, "/clip") == 11)
        {
            return array(comp, "/ramps").clone();
        }
    }
    panic!("no audio track carries clip 11 in {plan}");
}

#[test]
fn the_app_ceiling_is_the_one_the_core_refuses_above() {
    let ceiling = app_ceiling();
    assert!(
        ceiling > 4.0,
        "AudioNormalize.maxGain is {ceiling}: spec §11 AU-1 lifted the ceiling past ×4"
    );
    let base = one_clip();

    let at = base.apply(&set_volume(ceiling));
    assert_eq!(
        num(&at.value(), "/clips/0/audio/volume"),
        ceiling,
        "set_audio stores the app's ceiling as sent"
    );

    let past = ceiling + 0.5;
    assert_eq!(
        base.errors(&set_volume(past)),
        format!("audio.volume must be between 0 and {ceiling}, not {past}"),
        "the core refuses just past the app's ceiling, naming that ceiling"
    );
}

#[test]
fn a_gain_past_four_reaches_the_envelope_as_stored() {
    let loud = one_clip().apply(&set_volume(MIC_GAIN));
    let ramps = ramps(&loud);
    assert!(!ramps.is_empty(), "the clip's track has an envelope");
    for ramp in &ramps {
        if int(ramp, "/start") >= 10 * SEC {
            continue;
        }
        assert_eq!(num(ramp, "/from"), MIC_GAIN, "ramp {ramp} under the clip");
        assert_eq!(num(ramp, "/to"), MIC_GAIN, "ramp {ramp} under the clip");
    }
}

#[test]
fn an_action_end_past_four_plays_and_one_past_the_ceiling_clamps_to_it() {
    let ceiling = app_ceiling();
    let base = one_clip().apply(&json!({
        "op": "add_action", "clip": 11, "at": 0, "duration": 2 * SEC
    }));
    let action = int(&base.value(), "/clips/0/actions/0/id");

    let twenty = base.apply(&json!({
        "op": "set_action_end", "clip": 11, "action": action,
        "patch": { "audio": { "volume": 20.0 } }
    }));
    let state = twenty
        .clip_state(11, 2 * SEC)
        .expect("clip_state at the action's end");
    assert_eq!(
        num(&state, "/audio/volume"),
        20.0,
        "an end of ×20 plays at ×20"
    );

    // An end patch's VALUES are not range-checked (`edit_action.rs`), so the
    // evaluator's clamp is what bounds one past the ceiling.
    let wild = base.apply(&json!({
        "op": "set_action_end", "clip": 11, "action": action,
        "patch": { "audio": { "volume": 500.0 } }
    }));
    let state = wild
        .clip_state(11, 2 * SEC)
        .expect("clip_state at the action's end");
    assert_eq!(
        num(&state, "/audio/volume"),
        ceiling,
        "an end of ×500 clamps to the ceiling"
    );
}
