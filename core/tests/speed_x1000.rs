//! A clip's speed runs ×0.1–×1000, and above ×12 (both pitch modes) the
//! plan leaves the clip's audio out (spec §11 #190): `set_speed`'s two arms,
//! `rate_stretch` and the reader at the new bound, the audio ceiling, one
//! pitch per plan audio track and what that does to ducking, and
//! `rc_speed_limits`.

use serde_json::{json, Value};

mod common;
use common::{array, by_id, int, num, take_string, Handle, Outcome};
use reelcut_core::ffi_query::rc_speed_limits;

const SEC: i64 = 600_000;
const FRAME: i64 = SEC / 30;
const EPS: f64 = 1e-9;

fn media_clip(id: u32, start: i64, duration: i64, speed: f64, keep_pitch: Option<bool>) -> Value {
    let mut clip = json!({
        "id": id, "track": 2, "start": start, "duration": duration,
        "source": {"kind": "media", "media": 1, "in": 0}, "speed": speed, "video": {}
    });
    if let Some(keep) = keep_pitch {
        clip["audio"] = json!({"keep_pitch": keep});
    }
    clip
}

/// One hour of 1920x1080 media with sound, track 2, and the given clips;
/// nest 6 (track 7) holds `nested` when it is given, shown by nest clip 5.
fn project(clips: Vec<Value>, nested: Option<Value>) -> Value {
    let mut p = json!({
        "version": 10,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0]},
        "media": [{"id": 1, "path": "/fixtures/hour.mov", "kind": "video",
                   "duration": 3600 * SEC, "width": 1920, "height": 1080,
                   "fps": [30, 1], "has_video": true, "has_audio": true}],
        "tracks": [{"id": 2, "name": "A"}],
        "clips": clips,
        "markers": [],
        "next_id": 20
    });
    if let Some(inner) = nested {
        let shown = json!({"id": 5, "track": 2, "start": 0, "duration": 600 * SEC,
                           "source": {"kind": "nest", "project": 6}, "video": {}});
        p["clips"].as_array_mut().expect("clips").push(shown);
        p["nests"] = json!([{"id": 6, "name": "Group", "width": 1920, "height": 1080,
                             "tracks": [{"id": 7, "name": "Inner"}], "clips": [inner]}]);
    }
    p
}

/// A 180 s clip at ×1 with keep pitch: clip 3.
fn plain() -> Handle {
    Handle::from_value(&project(
        vec![media_clip(3, 0, 180 * SEC, 1.0, Some(true))],
        None,
    ))
}

fn speed_of(handle: &Handle, clip: u64) -> f64 {
    num(by_id(&handle.value(), "/clips", clip), "/speed")
}

fn segment_clips(plan: &Value, group: &str) -> Vec<i64> {
    array(plan, &format!("/{group}"))
        .iter()
        .flat_map(|t| array(t, "/segments").iter().map(|s| int(s, "/clip")))
        .collect()
}

#[test]
fn set_speed_applies_at_1000_and_clamps_to_the_range() {
    for (rate, landed) in [
        (1000.0, 1000.0),
        (1001.0, 1000.0),
        (5000.0, 1000.0),
        (0.05, 0.1),
    ] {
        let after = plain().apply(&json!({"op": "set_speed", "clip": 3, "rate": rate}));
        assert!(
            (speed_of(&after, 3) - landed).abs() < EPS,
            "×{rate} landed elsewhere"
        );
    }
}

#[test]
fn rate_stretch_applies_at_500_and_is_an_identity_past_1000() {
    // 200 s of content: ×500 is 12 frames, ×1200 is 5.
    let h = Handle::from_value(&project(vec![media_clip(3, 0, 200 * SEC, 1.0, None)], None));
    let after = h.apply(&json!({"op": "rate_stretch", "clip": 3, "to_end": 12 * FRAME}));
    assert!((speed_of(&after, 3) - 500.0).abs() < EPS);
    assert!(matches!(
        h.try_apply(&json!({"op": "rate_stretch", "clip": 3, "to_end": 5 * FRAME})),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn the_reader_opens_1000_and_refuses_the_float_above_it() {
    let at = project(vec![media_clip(3, 0, SEC, 1000.0, None)], None);
    assert_eq!(
        Handle::from_value(&at).value()["clips"][0]["speed"],
        json!(1000.0)
    );
    // 1000.0000000000001 is the float directly above 1000, but without
    // `float_roundtrip` it parses to 1000.0 and opens; this is the nearest
    // one above the bound the reader can see.
    let over = project(vec![media_clip(3, 0, SEC, 1000.0000000000002, None)], None);
    assert_eq!(
        Handle::try_from_value(&over).err().as_deref(),
        Some("clip 3's speed 1000.0000000000002 is outside ×0.1–×1000")
    );
}

#[test]
fn fit_lands_on_the_duration_and_clamps_at_both_ends() {
    let after = plain().apply(&json!({"op": "set_speed", "clip": 3, "duration": 30 * SEC}));
    let clip = by_id(&after.value(), "/clips", 3).clone();
    assert_eq!(int(&clip, "/duration"), 18_000_000);
    assert!((num(&clip, "/speed") - 6.0).abs() < EPS);

    let short = plain().apply(&json!({"op": "set_speed", "clip": 3, "duration": FRAME}));
    assert!(
        (speed_of(&short, 3) - 1000.0).abs() < EPS,
        "too short clamps to ×1000"
    );
    let long = plain().apply(&json!({"op": "set_speed", "clip": 3, "duration": 3600 * SEC}));
    assert!(
        (speed_of(&long, 3) - 0.1).abs() < EPS,
        "too long clamps to ×0.1"
    );
}

#[test]
fn fit_to_the_current_duration_is_an_identity_and_keep_pitch_rides_along() {
    let h = plain();
    assert!(matches!(
        h.try_apply(&json!({"op": "set_speed", "clip": 3, "duration": 180 * SEC})),
        Ok(Outcome::Identity)
    ));
    let pitched =
        h.apply(&json!({"op": "set_speed", "clip": 3, "duration": 180 * SEC, "keep_pitch": false}));
    let clip = by_id(&pitched.value(), "/clips", 3).clone();
    assert_eq!(clip["audio"]["keep_pitch"], json!(false));
    assert!((num(&clip, "/speed") - 1.0).abs() < EPS);
    assert_eq!(int(&clip, "/duration"), 180 * SEC);
}

#[test]
fn fit_errors_name_both_neither_a_bad_duration_and_a_non_media_clip() {
    let h = plain();
    assert_eq!(
        h.errors(&json!({"op": "set_speed", "clip": 3, "rate": 2.0, "duration": SEC})),
        "set_speed takes a rate or a duration, not both (clip 3)"
    );
    assert_eq!(
        h.errors(&json!({"op": "set_speed", "clip": 3})),
        "set_speed takes a rate or a duration (clip 3)"
    );
    // Before the clip is looked up, as `add_background` checks first.
    assert_eq!(
        h.errors(&json!({"op": "set_speed", "clip": 99})),
        "set_speed takes a rate or a duration (clip 99)"
    );
    for bad in [0, -SEC] {
        assert_eq!(
            h.errors(&json!({"op": "set_speed", "clip": 3, "duration": bad})),
            format!("duration must be positive, not {bad}")
        );
    }
    let text = h.apply(&json!({"op": "add_text_clip", "track": 2, "at": 200 * SEC,
                               "duration": SEC}));
    let id = array(&text.value(), "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("text"))
        .map(|c| int(c, "/id"))
        .expect("a text clip");
    assert_eq!(
        text.errors(&json!({"op": "set_speed", "clip": id, "duration": SEC})),
        format!("clip {id} is not a media clip")
    );
}

#[test]
fn fit_works_in_a_nest_scope() {
    let inner = json!({"id": 8, "track": 7, "start": 0, "duration": 180 * SEC,
                       "source": {"kind": "media", "media": 1, "in": 0}, "video": {},
                       "audio": {"keep_pitch": true}});
    let h = Handle::from_value(&project(vec![], Some(inner)));
    let after = h.apply(&json!({"op": "set_speed", "clip": 8, "duration": 30 * SEC,
                                "scope": 6}));
    let clip = by_id(&after.value(), "/nests/0/clips", 8).clone();
    assert_eq!(int(&clip, "/duration"), 18_000_000);
    assert!((num(&clip, "/speed") - 6.0).abs() < EPS);
    assert_eq!(
        h.errors(&json!({"op": "set_speed", "clip": 8, "scope": 6})),
        "set_speed takes a rate or a duration (clip 8)"
    );
}

#[test]
fn audio_is_left_out_above_12_in_both_pitch_modes() {
    for (speed, keep, audible) in [
        (12.0, Some(true), true),
        (12.5, Some(true), false),
        (12.0, Some(false), true),
        (12.5, Some(false), false),
        (12.0, None, true),
        (12.5, None, false),
        (1000.0, Some(false), false),
    ] {
        let h = Handle::from_value(&project(vec![media_clip(3, 0, SEC, speed, keep)], None));
        let before = h.to_json();
        let plan = h.plan();
        assert_eq!(h.to_json(), before, "reading the plan changed the project");
        assert_eq!(
            segment_clips(&plan, "audio_tracks") == vec![3],
            audible,
            "×{speed} keep_pitch {keep:?}"
        );
        assert_eq!(
            segment_clips(&plan, "video_tracks"),
            vec![3],
            "the video stays"
        );
    }
}

#[test]
fn a_nested_clip_follows_the_same_ceiling() {
    for (speed, audible) in [(12.0, true), (12.5, false)] {
        let inner = json!({"id": 8, "track": 7, "start": 0, "duration": SEC,
                           "source": {"kind": "media", "media": 1, "in": 0},
                           "speed": speed, "video": {}, "audio": {"keep_pitch": true}});
        let h = Handle::from_value(&project(vec![], Some(inner)));
        let plan = h.plan();
        assert_eq!(
            segment_clips(&plan, "audio_tracks") == vec![8],
            audible,
            "×{speed}"
        );
        assert_eq!(segment_clips(&plan, "video_tracks"), vec![8]);
    }
}

fn two_abutting(b_keeps_pitch: bool, a_audio: Value) -> Value {
    let mut a = media_clip(3, 0, 10 * SEC, 1.0, Some(true));
    a["audio"] = a_audio;
    let b = media_clip(4, 10 * SEC, 10 * SEC, 1.0, Some(b_keeps_pitch));
    project(vec![a, b], None)
}

#[test]
fn each_plan_audio_track_has_one_pitch() {
    let split = Handle::from_value(&two_abutting(false, json!({"keep_pitch": true}))).plan();
    let tracks = array(&split, "/audio_tracks");
    assert_eq!(tracks.len(), 2, "keep pitch and varispeed split: {split}");
    for track in tracks {
        let pitches: Vec<&Value> = array(track, "/segments")
            .iter()
            .map(|s| &s["pitch"])
            .collect();
        assert!(pitches.windows(2).all(|w| w[0] == w[1]), "{track}");
    }
    // CONTROL: the same pitch shares one track.
    let same = Handle::from_value(&two_abutting(true, json!({"keep_pitch": true}))).plan();
    assert_eq!(array(&same, "/audio_tracks").len(), 1);
}

#[test]
fn the_split_puts_an_other_pitch_neighbour_under_a_duckers_release() {
    // The accepted cost of the split (spec §11 #190): A ducks, and B, abutting
    // it on the same timeline track with the other pitch mode, now sits on
    // another composition track and is ducked by A's release.
    let duck = json!({"keep_pitch": true,
                      "duck": {"level": 0.25, "attack": 0, "release": SEC}});
    let plan = Handle::from_value(&two_abutting(false, duck.clone())).plan();
    let b_track = array(&plan, "/audio_tracks")
        .iter()
        .find(|t| array(t, "/segments").iter().any(|s| int(s, "/clip") == 4))
        .expect("B has an audio track");
    let release = array(b_track, "/ramps")
        .iter()
        .find(|r| int(r, "/start") == 10 * SEC)
        .unwrap_or_else(|| panic!("no ramp at 10 s: {b_track}"));
    assert_eq!(int(release, "/duration"), SEC, "{release}");
    assert!((num(release, "/from") - 0.25).abs() < EPS, "{release}");
    assert!((num(release, "/to") - 1.0).abs() < EPS, "{release}");

    // CONTROL: with keep pitch, B shares A's track and nothing ducks it.
    let plan = Handle::from_value(&two_abutting(true, duck)).plan();
    let tracks = array(&plan, "/audio_tracks");
    assert_eq!(tracks.len(), 1);
    for ramp in array(&tracks[0], "/ramps") {
        if int(ramp, "/start") >= 10 * SEC {
            assert!(
                num(ramp, "/from") >= 1.0 - EPS && num(ramp, "/to") >= 1.0 - EPS,
                "{ramp}"
            );
        }
    }
}

#[test]
fn rc_speed_limits_publishes_every_number() {
    let text = take_string(unsafe { rc_speed_limits() }).expect("never NULL");
    assert_eq!(text, r#"{"min":0.1,"max":1000.0,"audio_max":12.0}"#);
}
