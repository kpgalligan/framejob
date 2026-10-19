//! Keep pitch at a near-unity speed plays `time_domain` (spec §11 SY-26):
//! the band 0.98 ≤ speed ≤ 1.02 (≠ 1), the names the plan writes either
//! side of it, and one pitch NAME per plan audio track. Within ±0.1% of ×1
//! (0.999 ≤ speed ≤ 1.001, ≠ 1) keep pitch plays `off`, varispeed (spec §11
//! SY-39), and shares a plan audio track with keep-off clips.

use serde_json::{json, Value};

mod common;
use common::{array, int, Handle};

const SEC: i64 = 600_000;

fn media_clip(id: u32, start: i64, duration: i64, speed: f64, keep_pitch: bool) -> Value {
    json!({
        "id": id, "track": 2, "start": start, "duration": duration,
        "source": {"kind": "media", "media": 1, "in": 0}, "speed": speed,
        "video": {}, "audio": {"keep_pitch": keep_pitch}
    })
}

/// One hour of 1920x1080 media with sound, track 2, and the given clips.
fn project(clips: Vec<Value>) -> Value {
    json!({
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
    })
}

/// The pitch name the plan writes for one clip at `speed`.
fn pitch_of(speed: f64, keep_pitch: bool) -> String {
    let plan = Handle::from_value(&project(vec![media_clip(
        3,
        0,
        10 * SEC,
        speed,
        keep_pitch,
    )]))
    .plan();
    let tracks = array(&plan, "/audio_tracks");
    assert_eq!(tracks.len(), 1, "×{speed}: {plan}");
    let segments = array(&tracks[0], "/segments");
    assert_eq!(segments.len(), 1, "×{speed}: {plan}");
    segments[0]["pitch"]
        .as_str()
        .unwrap_or_else(|| panic!("×{speed}: no pitch name: {plan}"))
        .to_string()
}

#[test]
fn keep_pitch_inside_the_band_plays_time_domain() {
    for speed in [0.98, 0.99, 1.02] {
        assert_eq!(pitch_of(speed, true), "time_domain", "×{speed} keep");
    }
}

#[test]
fn keep_pitch_outside_the_band_or_at_unity_stays_spectral() {
    for speed in [0.97, 1.03, 1.0, 0.5] {
        assert_eq!(pitch_of(speed, true), "spectral", "×{speed} keep");
    }
}

#[test]
fn keep_pitch_off_is_off_inside_the_band() {
    assert_eq!(pitch_of(0.99, false), "off");
}

#[test]
fn a_track_holds_one_pitch_name() {
    // A ×1 keep clip abutting a ×0.99 keep clip on one timeline track: both
    // keep pitch, but one plays `spectral` and the other `time_domain`, so
    // they land on two plan audio tracks, one name each.
    let plan = Handle::from_value(&project(vec![
        media_clip(3, 0, 10 * SEC, 1.0, true),
        media_clip(4, 10 * SEC, 10 * SEC, 0.99, true),
    ]))
    .plan();
    let tracks = array(&plan, "/audio_tracks");
    assert_eq!(tracks.len(), 2, "spectral and time_domain split: {plan}");
    let mut names: Vec<(i64, String)> = Vec::new();
    for track in tracks {
        let segments = array(track, "/segments");
        assert_eq!(segments.len(), 1, "{track}");
        let name = segments[0]["pitch"].as_str().unwrap_or("").to_string();
        names.push((int(&segments[0], "/clip"), name));
    }
    names.sort();
    assert_eq!(
        names,
        vec![(3, "spectral".to_string()), (4, "time_domain".to_string())]
    );
}

#[test]
fn keep_pitch_within_a_tenth_of_a_percent_plays_off() {
    for speed in [0.999, 0.99999, 1.00001, 1.001] {
        assert_eq!(pitch_of(speed, true), "off", "×{speed} keep");
    }
}

#[test]
fn keep_pitch_just_outside_the_varispeed_band_plays_time_domain() {
    for speed in [0.99899, 1.00101] {
        assert_eq!(pitch_of(speed, true), "time_domain", "×{speed} keep");
    }
}

#[test]
fn a_near_unity_keep_clip_shares_a_track_with_a_keep_off_clip() {
    // A ×0.9 keep-off clip abutting a ×0.99999 keep clip: both play `off`
    // (SY-39), so they share one plan audio track.
    let plan = Handle::from_value(&project(vec![
        media_clip(3, 0, 10 * SEC, 0.9, false),
        media_clip(4, 10 * SEC, 10 * SEC, 0.99999, true),
    ]))
    .plan();
    let tracks = array(&plan, "/audio_tracks");
    assert_eq!(tracks.len(), 1, "both `off`, one track: {plan}");
    let segments = array(&tracks[0], "/segments");
    assert_eq!(segments.len(), 2, "{plan}");
    for segment in segments {
        assert_eq!(segment["pitch"].as_str(), Some("off"), "{segment}");
    }
}
