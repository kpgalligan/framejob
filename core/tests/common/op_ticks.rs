//! Independent frame-grid vectors for every published tick argument.
#![allow(dead_code)]

use serde_json::{json, Value};

pub enum TickAnswer {
    Applied(Vec<(&'static str, Value)>),
    Identity,
    Error(&'static str),
}

pub struct TickCase {
    pub label: &'static str,
    pub argument: &'static str,
    pub project: Value,
    pub op: Value,
    pub answer: TickAnswer,
}

pub fn clip(id: u32, track: u32, start: i64, duration: i64, source_in: i64) -> Value {
    json!({"id": id, "track": track, "start": start, "duration": duration,
        "source": {"kind": "media", "media": 2, "in": source_in},
        "video": {}, "audio": {}})
}

pub fn project(fps: [u32; 2], frame: i64, clips: Vec<Value>) -> Value {
    json!({"version": 8, "canvas": {"width": 640, "height": 360, "fps": fps},
        "media": [{"id":2,"path":"/fixtures/ticks.mov","kind":"video",
            "duration": 500*frame,"width":640,"height":360,
            "fps":[30,1],"has_video":true,"has_audio":true},
            {"id":4,"path":"/fixtures/short.mov","kind":"video",
            "duration":8*frame,"width":640,"height":360,
            "fps":[30,1],"has_video":true,"has_audio":true}],
        "tracks": [{"id":1,"name":"A"},{"id":3,"name":"B"}],
        "clips": clips, "markers": [], "nests": [], "next_id": 100})
}

pub fn pair(fps: [u32; 2], frame: i64) -> Value {
    project(
        fps,
        frame,
        vec![
            clip(10, 1, 10 * frame, 20 * frame, 40 * frame),
            clip(11, 1, 30 * frame, 20 * frame, 80 * frame),
        ],
    )
}

pub fn one(fps: [u32; 2], frame: i64) -> Value {
    project(
        fps,
        frame,
        vec![clip(10, 1, 10 * frame, 20 * frame, 40 * frame)],
    )
}

pub fn off(index: i64, frame: i64) -> i64 {
    index * frame + frame * 3 / 5
}

pub fn applied(
    label: &'static str,
    argument: &'static str,
    project: Value,
    op: Value,
    expected: Vec<(&'static str, Value)>,
) -> TickCase {
    TickCase {
        label,
        argument,
        project,
        op,
        answer: TickAnswer::Applied(expected),
    }
}

pub fn error(
    label: &'static str,
    argument: &'static str,
    project: Value,
    op: Value,
    expected: &'static str,
) -> TickCase {
    TickCase {
        label,
        argument,
        project,
        op,
        answer: TickAnswer::Error(expected),
    }
}
