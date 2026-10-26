//! A constant clip's time-scaled Keep pitch off audio segment carries the
//! two-point constant `ramp` object (spec §7.2, §11 SR-28), so Swift renders
//! and plays its sound as one ×1 segment as it does a ramp's.
//!
//! Pinned here, through the FFI: at ×0.25, ×2 and ×4 the exact map over the
//! segment's own range, `constant: true`, `pitch` `off` and the object's
//! keys; no `ramp` for Keep pitch on (×2, and ×0.9995 inside SY-39's `off`
//! band), for Keep pitch off at ×1 or for a freeze; no audio segment above
//! ×12; a reversed clip's map from its own `in`; a nest clip's tail cut
//! ending the map at the lifted duration; and a ramped clip's object
//! carrying no `constant` key.

mod common;

use serde_json::{json, Value};

use common::{array, int, Handle};

const SEC: i64 = 600_000;

/// 60 s of 1920x1080 at 30 fps with sound.
fn project(clips: Vec<Value>, nests: Vec<Value>) -> Value {
    json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/constant.mov", "kind": "video",
            "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": clips,
        "nests": nests,
        "next_id": 100
    })
}

/// Media clip 11 on track 2 at 0.5 s, `duration` long, from `in` 1 s.
fn clip(duration: i64, speed: f64, keep_pitch: bool) -> Value {
    json!({
        "id": 11, "track": 2, "start": SEC / 2, "duration": duration,
        "source": { "kind": "media", "media": 1, "in": SEC }, "speed": speed,
        "video": {}, "audio": { "keep_pitch": keep_pitch }
    })
}

/// Every segment of `clip` on the plan's `kind` tracks.
fn segments_of(plan: &Value, kind: &str, clip: i64) -> Vec<Value> {
    let mut out = Vec::new();
    for track in array(plan, &format!("/{kind}")) {
        for segment in array(track, "/segments") {
            if int(segment, "/clip") == clip {
                out.push(segment.clone());
            }
        }
    }
    out
}

fn keys(value: &Value) -> Vec<String> {
    value
        .as_object()
        .map(|o| o.keys().cloned().collect())
        .unwrap_or_default()
}

/// Clip 11's one audio segment in `project`'s plan.
fn audio_of(project: &Value) -> Value {
    let plan = Handle::from_value(project).plan();
    let audio = segments_of(&plan, "audio_tracks", 11);
    assert_eq!(audio.len(), 1, "{plan}");
    audio[0].clone()
}

/// The constant object the segment must carry: its own range.
fn assert_constant(segment: &Value) {
    let (source_in, source_duration, duration) = (
        int(segment, "/source_in"),
        int(segment, "/source_duration"),
        int(segment, "/duration"),
    );
    assert_ne!(duration, source_duration, "{segment}");
    assert_eq!(segment["pitch"], json!("off"), "{segment}");
    let ramp = &segment["ramp"];
    assert_eq!(keys(ramp), ["keep_pitch", "map", "constant"], "{segment}");
    assert_eq!(ramp["keep_pitch"], json!(false));
    assert_eq!(ramp["constant"], json!(true));
    assert_eq!(
        ramp["map"],
        json!([[0, source_in], [duration, source_in + source_duration]]),
        "{segment}"
    );
}

#[test]
fn keep_pitch_off_time_scaled_carries_the_constant_map() {
    for (speed, source_duration) in [(0.25, SEC / 2), (2.0, 4 * SEC), (4.0, 8 * SEC)] {
        let segment = audio_of(&project(vec![clip(2 * SEC, speed, false)], vec![]));
        assert_eq!(int(&segment, "/source_in"), SEC, "×{speed}");
        assert_eq!(
            int(&segment, "/source_duration"),
            source_duration,
            "×{speed}"
        );
        assert_eq!(int(&segment, "/duration"), 2 * SEC, "×{speed}");
        assert_eq!(
            segment["ramp"]["map"],
            json!([[0, SEC], [2 * SEC, SEC + source_duration]]),
            "×{speed}"
        );
        assert_constant(&segment);
    }
}

#[test]
fn the_video_segment_carries_nothing() {
    let plan = Handle::from_value(&project(vec![clip(2 * SEC, 2.0, false)], vec![])).plan();
    let video = segments_of(&plan, "video_tracks", 11);
    assert_eq!(video.len(), 1, "{plan}");
    assert!(video[0].get("ramp").is_none(), "{plan}");
}

#[test]
fn keep_pitch_on_unity_and_a_freeze_carry_no_ramp() {
    for (speed, keep_pitch) in [(2.0, true), (0.9995, true), (1.0, false)] {
        let segment = audio_of(&project(vec![clip(2 * SEC, speed, keep_pitch)], vec![]));
        assert!(
            segment.get("ramp").is_none(),
            "×{speed} keep {keep_pitch}: {segment}"
        );
    }
    let still = json!({
        "id": 11, "track": 2, "start": 0, "duration": 2 * SEC,
        "source": { "kind": "still", "media": 1, "at": SEC },
        "video": {}, "audio": { "keep_pitch": false }
    });
    let plan = Handle::from_value(&project(vec![still], vec![])).plan();
    for segment in segments_of(&plan, "audio_tracks", 11)
        .iter()
        .chain(segments_of(&plan, "video_tracks", 11).iter())
    {
        assert!(segment.get("ramp").is_none(), "{plan}");
    }
}

#[test]
fn above_x12_there_is_no_audio_segment() {
    let plan = Handle::from_value(&project(vec![clip(2 * SEC, 13.0, false)], vec![])).plan();
    assert!(segments_of(&plan, "audio_tracks", 11).is_empty(), "{plan}");
    assert_eq!(segments_of(&plan, "video_tracks", 11).len(), 1, "{plan}");
}

#[test]
fn a_reversed_clip_maps_from_its_own_in() {
    let mut value = clip(2 * SEC, 2.0, false);
    value["source"] = json!({ "kind": "media", "media": 1, "in": 3 * SEC, "reversed": true });
    let segment = audio_of(&project(vec![value], vec![]));
    assert_eq!(int(&segment, "/source_in"), 3 * SEC);
    assert_eq!(
        segment["ramp"]["map"],
        json!([[0, 3 * SEC], [2 * SEC, 7 * SEC]])
    );
    assert_constant(&segment);
}

#[test]
fn a_nest_s_tail_cut_ends_the_map_at_the_lifted_duration() {
    // Nest 50 holds clip 51: 4 s at ×2 from 0, Keep pitch off; nest clip 60
    // shows it at 1 s for 3 s, cutting its last second.
    let inner = json!({
        "id": 51, "track": 53, "start": 0, "duration": 4 * SEC,
        "source": { "kind": "media", "media": 1, "in": 0 }, "speed": 2.0,
        "video": {}, "audio": { "keep_pitch": false }
    });
    let nest = json!({ "id": 50, "name": "Nest", "width": 1920, "height": 1080,
                       "tracks": [{ "id": 53, "name": "Inner" }], "clips": [inner] });
    let shown = json!({ "id": 60, "track": 2, "start": SEC, "duration": 3 * SEC,
                        "source": { "kind": "nest", "project": 50 } });
    let plan = Handle::from_value(&project(vec![shown], vec![nest])).plan();
    let audio = segments_of(&plan, "audio_tracks", 51);
    assert_eq!(audio.len(), 1, "{plan}");
    let segment = &audio[0];
    assert_eq!(int(segment, "/start"), SEC);
    assert_eq!(int(segment, "/duration"), 3 * SEC);
    assert_eq!(int(segment, "/source_duration"), 6 * SEC);
    assert_eq!(segment["ramp"]["map"], json!([[0, 0], [3 * SEC, 6 * SEC]]));
    assert_constant(segment);
}

#[test]
fn a_ramped_clip_s_object_has_no_constant_key() {
    let mut value = clip(3 * SEC, 1.0, false);
    value["actions"] = json!([{ "id": 21, "start": SEC, "duration": SEC,
                                "curve": "linear", "end": { "speed": 3.0 } }]);
    let segment = audio_of(&project(vec![value], vec![]));
    assert_eq!(keys(&segment["ramp"]), ["keep_pitch", "map"], "{segment}");
}
