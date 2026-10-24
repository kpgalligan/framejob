//! `add_transition`'s handles on a RAMPED clip (spec §6, §11 SR-18 (a) and
//! (b), the road map's H).
//!
//! Pinned here, through the FFI, against closed-form oracles written in this
//! file: the incoming ramped clip's head read at its base rate — its `in`
//! moved back by `head × speed`, its actions moved with its first frame, and
//! its out point unchanged — and the outgoing ramped clip's tail handle read
//! through S∞, the map run on past the clip's end at its last rate.

mod common;

use serde_json::{json, Value};

use common::{array, by_id, int, Handle};

/// Ticks per second and per 30 fps frame (spec §5.1), written out.
const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;

fn media(id: u32, file: i64) -> Value {
    json!({
        "id": id, "path": format!("/fixtures/handle-{id}.mov"), "kind": "video",
        "duration": file, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

fn clip(id: u32, media: u32, start: i64, source_in: i64, speed: f64, actions: Value) -> Value {
    json!({
        "id": id, "track": 2, "start": start, "duration": 2 * SEC,
        "source": { "kind": "media", "media": media, "in": source_in },
        "speed": speed, "video": {}, "audio": {}, "actions": actions
    })
}

fn ramp(id: u32, start: i64, duration: i64, rate: f64) -> Value {
    json!({ "id": id, "start": start, "duration": duration, "curve": "linear",
            "end": { "speed": rate } })
}

fn pair(files: [i64; 2], earlier: Value, later: Value) -> Handle {
    Handle::from_value(&json!({
        "version": 27,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [media(1, files[0]), media(3, files[1])],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [earlier, later],
        "next_id": 100
    }))
}

/// The clip's one audio segment's source out point: what the plan reads.
fn planned_out(handle: &Handle, clip: i64) -> i64 {
    let plan = handle.plan();
    for track in array(&plan, "/audio_tracks") {
        for segment in array(track, "/segments") {
            if int(segment, "/clip") == clip {
                return int(segment, "/source_in") + int(segment, "/source_duration");
            }
        }
    }
    panic!("no audio segment for clip {clip}");
}

#[test]
fn the_incoming_ramped_clip_s_head_reads_at_its_base_rate_and_keeps_its_out_point() {
    // B at 2 s from in 2 s at ×1.5, ×1.5 → ×3 over [0.5 s, 1.5 s): a 1 s
    // head moves `in` back 1.5 s of source and the action 1 s later.
    let handle = pair(
        [600 * SEC, 600 * SEC],
        clip(11, 1, 0, 0, 1.0, json!([])),
        clip(
            12,
            3,
            2 * SEC,
            2 * SEC,
            1.5,
            json!([ramp(22, SEC / 2, SEC, 3.0)]),
        ),
    );
    let out = planned_out(&handle, 12);
    let after = handle.apply(&json!({
        "op": "add_transition", "clip": 12, "duration": SEC, "align": "before"
    }));
    let value = after.value();
    let b = by_id(&value, "/clips", 12);
    assert_eq!(int(b, "/start"), SEC);
    assert_eq!(int(b, "/duration"), 3 * SEC);
    assert_eq!(int(b, "/source/in"), 2 * SEC - 900_000);
    let action = &array(b, "/actions")[0];
    assert_eq!(int(action, "/start"), SEC / 2 + SEC);
    assert_eq!(int(action, "/duration"), SEC);
    assert_eq!(planned_out(&after, 12), out, "the out point stays");
    assert_eq!(int(by_id(&value, "/clips", 11), "/duration"), 2 * SEC);
}

#[test]
fn the_outgoing_ramped_clip_s_tail_handle_reads_through_the_map() {
    // A at 0 from in 0, ×1 → ×2 over [0, 1 s), ×2 after, in a 4 s file:
    // S∞⁻¹(4 s) = 1 s + 2.5 s / 2 = 2.25 s, so the tail holds 0.25 s,
    // seven whole frames — where one rate would read 2 s more.
    let handle = pair(
        [4 * SEC, 600 * SEC],
        clip(11, 1, 0, 0, 1.0, json!([ramp(21, 0, SEC, 2.0)])),
        clip(12, 3, 2 * SEC, 0, 1.0, json!([])),
    );
    let after = handle
        .apply(&json!({
            "op": "add_transition", "clip": 12, "duration": SEC, "align": "after"
        }))
        .value();
    let a = by_id(&after, "/clips", 11);
    assert_eq!(int(a, "/duration"), 2 * SEC + 7 * FRAME);
    let b = by_id(&after, "/clips", 12);
    assert_eq!(int(b, "/start"), 2 * SEC);
    assert_eq!(int(b, "/source/in"), 0);
}
