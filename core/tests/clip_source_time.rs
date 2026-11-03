//! `clip_source_time.rs` (spec §11 VR-20): one forward-file source tick in
//! clip time, and whether it is in the window the clip plays. Every expected
//! tick is worked by hand from the clip's `in`, its rate or speed map and the
//! media's duration; the ramp's figures are `duck_speech.rs`'s (rate 1 → 2
//! linearly over the first 2 s, then 2: S(2 s) = 3 s), whose
//! `a_reversed_ducker_reads_its_spans_reflected` holds `speech_in_clip`'s
//! reversed answer through the same helper.

use framejob_core::clip_source_time::{clip_time_of_source, in_played_window, Round};
use framejob_core::model::{Clip, Media};
use serde_json::{json, Value};

const SEC: i64 = 600_000;

fn media(duration: i64) -> Media {
    serde_json::from_value(json!({"id": 1, "path": "/m.mov", "kind": "video",
                                  "duration": duration, "width": 1920, "height": 1080,
                                  "fps": [30, 1], "has_video": true}))
    .unwrap()
}

fn clip(source: Value, duration: i64, extra: Value) -> Clip {
    let mut value = json!({"id": 3, "track": 2, "start": 0, "duration": duration,
                           "source": source});
    for (k, v) in extra.as_object().unwrap() {
        value[k] = v.clone();
    }
    serde_json::from_value(value).unwrap()
}

fn media_source(r#in: i64, reversed: bool) -> Value {
    json!({"kind": "media", "media": 1, "in": r#in, "reversed": reversed})
}

fn both(clip: &Clip, media: &Media, t: i64) -> (Option<i64>, Option<i64>) {
    (
        clip_time_of_source(clip, media, t, Round::Down),
        clip_time_of_source(clip, media, t, Round::Up),
    )
}

#[test]
fn a_forward_clip_subtracts_its_in() {
    let c = clip(media_source(2 * SEC, false), 3 * SEC, json!({}));
    assert_eq!(
        both(&c, &media(20 * SEC), 5 * SEC),
        (Some(3 * SEC), Some(3 * SEC))
    );
    // Before `in` the read is negative, and so is the clip time: the helper
    // does not clamp, the caller keeps what it needs.
    assert_eq!(
        clip_time_of_source(&c, &media(20 * SEC), SEC, Round::Down),
        Some(-SEC)
    );
}

#[test]
fn a_double_speed_clip_floors_down_and_ceils_up() {
    let c = clip(media_source(0, false), 3 * SEC, json!({"speed": 2.0}));
    // 1 800 001 ticks read at ×2 is 900 000.5 ticks of clip.
    assert_eq!(
        both(&c, &media(20 * SEC), 3 * SEC + 1),
        (Some(900_000), Some(900_001))
    );
    assert_eq!(
        both(&c, &media(20 * SEC), 4 * SEC),
        (Some(2 * SEC), Some(2 * SEC))
    );
}

#[test]
fn a_reversed_clip_reflects_over_the_media_duration() {
    // Media 20 s; a reversed clip from `in` 15 s. Forward 1 s is reversed
    // 19 s, read 4 s; forward 3 s is reversed 17 s, read 2 s.
    let c = clip(media_source(15 * SEC, true), 5 * SEC, json!({}));
    let m = media(20 * SEC);
    assert_eq!(both(&c, &m, SEC), (Some(4 * SEC), Some(4 * SEC)));
    assert_eq!(both(&c, &m, 3 * SEC), (Some(2 * SEC), Some(2 * SEC)));
}

#[test]
fn a_ramped_clip_reads_through_its_speed_map() {
    let c = clip(
        media_source(0, false),
        5 * SEC,
        json!({"actions": [{"id": 11, "start": 0, "duration": 2 * SEC,
                            "curve": "linear", "end": {"speed": 2.0}}]}),
    );
    let m = media(20 * SEC);
    assert_eq!(
        both(&c, &m, 4 * SEC),
        (Some(25 * SEC / 10), Some(25 * SEC / 10))
    );
    assert_eq!(both(&c, &m, 5 * SEC), (Some(3 * SEC), Some(3 * SEC)));
    // Inside the ramp: S(t) = t + t²/4 s for t ≤ 2 s; S(1 s) = 1.25 s.
    assert_eq!(
        clip_time_of_source(&c, &m, 125 * SEC / 100, Round::Down),
        Some(SEC)
    );
}

#[test]
fn no_answer_without_a_media_source_or_a_rate() {
    let m = media(20 * SEC);
    let still = clip(
        json!({"kind": "still", "media": 1, "at": 0}),
        SEC,
        json!({}),
    );
    assert_eq!(both(&still, &m, SEC), (None, None));
    assert!(!in_played_window(&still, &m, SEC));
    let stopped = clip(media_source(0, false), SEC, json!({"speed": 0.0}));
    assert_eq!(both(&stopped, &m, SEC), (None, None));
}

#[test]
fn the_played_window_at_both_edges() {
    let m = media(20 * SEC);
    // Forward ×1 from 2 s for 3 s: [2 s, 5 s).
    let c = clip(media_source(2 * SEC, false), 3 * SEC, json!({}));
    assert!(!in_played_window(&c, &m, 2 * SEC - 1));
    assert!(in_played_window(&c, &m, 2 * SEC));
    assert!(in_played_window(&c, &m, 5 * SEC - 1));
    assert!(!in_played_window(&c, &m, 5 * SEC));
    // ×2 from 0 for 3 s reads [0, 6 s).
    let fast = clip(media_source(0, false), 3 * SEC, json!({"speed": 2.0}));
    assert!(in_played_window(&fast, &m, 6 * SEC - 1));
    assert!(!in_played_window(&fast, &m, 6 * SEC));
    // Reversed from 15 s for 5 s reads reversed [15 s, 20 s): forward (0, 5 s].
    let back = clip(media_source(15 * SEC, true), 5 * SEC, json!({}));
    assert!(in_played_window(&back, &m, 5 * SEC));
    assert!(!in_played_window(&back, &m, 5 * SEC + 1));
    assert!(in_played_window(&back, &m, 1));
    assert!(!in_played_window(&back, &m, 0));
}
