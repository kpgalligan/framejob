//! Black-box tests for what `paste` does to a payload clip's property
//! groups before it lands (issue #62): the patch path's normalise-and-check,
//! run on every group of every clip the paste brings — the payload's own and
//! those inside the nests they show — BEFORE the clip's times are re-snapped,
//! so a range error names the value the payload sent and the id the PAYLOAD
//! gave the clip.

mod common;

use serde_json::{json, Value};

use common::{array, at, Handle};

/// One frame of the 30 fps destination, in ticks.
const FRAME: i64 = 20_000;

/// One second, in ticks.
const SEC: i64 = 600_000;

/// The project a paste lands in: one track, nothing on it.
fn destination() -> Handle {
    Handle::new(1920, 1080, 30, 1)
}

/// A paste at 0 of `payload`.
fn paste(payload: Value) -> Value {
    json!({"op": "paste", "at": 0, "payload": payload})
}

/// A payload holding one text clip, id 7, with `video` and `text` as given.
fn text_clip(video: Value, text: Value) -> Value {
    json!({"clips": [{"id": 7, "track": 0, "start": 0, "duration": 2 * SEC,
                      "source": {"kind": "text"}, "video": video, "text": text}]})
}

/// The pasted clips, in the order they were placed.
fn landed(handle: &Handle) -> Vec<Value> {
    array(&handle.value(), "/clips").clone()
}

#[test]
fn an_out_of_range_value_is_an_error_naming_the_payload_clip() {
    let msg = destination().errors(&paste(text_clip(
        json!({"scale": 500.0}),
        json!({"content": "hi"}),
    )));
    assert_eq!(
        msg,
        "pasted clip 7: video.scale must be between 0.01 and 10, not 500"
    );
}

#[test]
fn an_empty_motion_lands_as_null_in_either_spelling() {
    for motion in [json!({}), json!({"in": null, "out": null, "during": null})] {
        let pasted = destination().apply(&paste(text_clip(
            json!({"motion": motion}),
            json!({"content": "hi"}),
        )));
        let clips = landed(&pasted);
        assert_eq!(clips.len(), 1);
        assert_eq!(
            clips[0]["video"]["motion"],
            Value::Null,
            "{motion} is stored as the one spelling of no motion"
        );
    }
}

#[test]
fn a_word_count_that_does_not_match_the_content_is_an_error() {
    let words = json!([
        {"start": 0, "end": 10 * FRAME},
        {"start": 10 * FRAME, "end": 20 * FRAME},
        {"start": 20 * FRAME, "end": 30 * FRAME}
    ]);
    let msg = destination().errors(&paste(text_clip(
        json!({}),
        json!({"content": "one two", "words": words}),
    )));
    assert_eq!(
        msg,
        "pasted clip 7: this text is timed word by word: 3 timings for 2 words"
    );
}

#[test]
fn the_check_runs_before_the_snap_and_names_what_the_payload_sent() {
    let msg = destination().errors(&paste(text_clip(
        json!({"motion": {"in": {"kind": "fade", "duration": -1}}}),
        json!({"content": "hi"}),
    )));
    assert_eq!(
        msg,
        "pasted clip 7: video.motion.in.duration must not be negative, not -1"
    );
}

#[test]
fn a_clip_inside_a_pasted_nest_is_checked_under_its_own_payload_id() {
    let payload = json!({
        "clips": [{"id": 3, "track": 0, "start": 0, "duration": 2 * SEC,
                   "source": {"kind": "nest", "project": 4}, "video": {}}],
        "nests": [{
            "id": 4, "name": "Group", "width": 1920, "height": 1080,
            "tracks": [{"id": 5, "name": "Nested"}],
            "clips": [{"id": 6, "track": 5, "start": 0, "duration": 2 * SEC,
                       "source": {"kind": "text"}, "video": {"scale": 500.0},
                       "text": {"content": "hi"}}]
        }]
    });
    assert_eq!(
        destination().errors(&paste(payload)),
        "pasted clip 6: video.scale must be between 0.01 and 10, not 500"
    );
}

#[test]
fn a_nest_clip_inside_a_nest_is_measured_against_the_nest_it_shows() {
    // Nest A (640×360) holds clip 6, which shows nest B (100×100): a crop of
    // 120 across fits A's width and not B's, so only a check that can see B
    // — one run after every copy has landed — names it.
    let payload = json!({
        "clips": [{"id": 3, "track": 0, "start": 0, "duration": 2 * SEC,
                   "source": {"kind": "nest", "project": 4}, "video": {}}],
        "nests": [
            {"id": 4, "name": "A", "width": 640, "height": 360,
             "tracks": [{"id": 5, "name": "In A"}],
             "clips": [{"id": 6, "track": 5, "start": 0, "duration": 2 * SEC,
                        "source": {"kind": "nest", "project": 8},
                        "video": {"crop": {"l": 60.0, "r": 60.0}}}]},
            {"id": 8, "name": "B", "width": 100, "height": 100,
             "tracks": [{"id": 9, "name": "In B"}],
             "clips": [{"id": 10, "track": 9, "start": 0, "duration": 2 * SEC,
                        "source": {"kind": "text"}, "video": {},
                        "text": {"content": "hi"}}]}
        ]
    });
    assert_eq!(
        destination().errors(&paste(payload)),
        "pasted clip 6: video.crop l + r must be less than the source width 100, not 120"
    );
}

#[test]
fn a_payload_inside_every_range_still_lands_whole() {
    // The control: the same shapes with legal values paste, and the nest's
    // clip keeps what it carried.
    let payload = json!({
        "clips": [{"id": 3, "track": 0, "start": 0, "duration": 2 * SEC,
                   "source": {"kind": "nest", "project": 4}, "video": {}}],
        "nests": [{
            "id": 4, "name": "Group", "width": 1920, "height": 1080,
            "tracks": [{"id": 5, "name": "Nested"}],
            "clips": [{"id": 6, "track": 5, "start": 0, "duration": 2 * SEC,
                       "source": {"kind": "text"}, "video": {"scale": 5.0},
                       "text": {"content": "hi"}}]
        }]
    });
    let pasted = destination().apply(&paste(payload));
    let value = pasted.value();
    assert_eq!(at(&value, "/nests/0/clips/0/video/scale"), &json!(5.0));
    assert_eq!(landed(&pasted).len(), 1);
}
