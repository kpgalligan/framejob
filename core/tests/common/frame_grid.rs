#![allow(dead_code)]

use serde_json::{json, Value};

pub const FRAME_30: i64 = 20_000;
pub const FRAME_24: i64 = 25_000;

pub fn track(id: u32) -> Value {
    json!({"id": id, "name": format!("Track {id}")})
}

pub fn media(id: u32, duration: i64) -> Value {
    json!({"id": id, "path": format!("/fixtures/grid-{id}.mov"),
        "kind": "video", "duration": duration, "width": 640,
        "height": 360, "fps": [30, 1], "has_video": true, "has_audio": true})
}

pub fn motion() -> Value {
    json!({"in": {"kind": "fade", "duration": 10_000},
        "out": {"kind": "fade", "duration": 12_500},
        "during": {"kind": "pulse", "amount": 0.5, "period": 10_000}})
}

pub fn action(id: u32, start: i64, duration: i64) -> Value {
    json!({"id": id, "start": start, "duration": duration,
        "end": {"video": {"opacity": 0.4, "motion": {"in": {
            "kind": "fade", "duration": 12_500}}}}})
}

pub fn text_clip(id: u32, track_id: u32, start: i64, duration: i64) -> Value {
    json!({"id": id, "track": track_id, "start": start, "duration": duration,
        "source": {"kind": "text"}, "video": {"motion": motion()},
        "text": {"content": "Keep", "animation": {"kind": "typewriter",
            "in": 20_000, "out": 60_000}},
        "audio": {"fade_in": 10_001, "fade_out": 12_501},
        "actions": [action(id + 1, 10_000, 12_500)]})
}

pub fn nest(id: u32, track_id: u32, clips: Vec<Value>) -> Value {
    json!({"id": id, "name": format!("Nest {id}"), "width": 640,
        "height": 360, "tracks": [track(track_id)], "clips": clips})
}

pub fn project(fps: [u32; 2], clips: Vec<Value>, nests: Vec<Value>, next_id: u32) -> Value {
    json!({"version": 8, "canvas": {"width": 640, "height": 360, "fps": fps},
        "media": [], "tracks": [track(1)], "clips": clips,
        "markers": [], "nests": nests, "next_id": next_id})
}

pub fn nest_clip(id: u32, start: i64, duration: i64, shows: u32) -> Value {
    json!({"id": id, "track": 1, "start": start, "duration": duration,
        "source": {"kind": "nest", "project": shows}, "video": {}})
}
