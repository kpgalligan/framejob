use serde_json::{json, Value};

use crate::common::Handle;

/// One tick per frame. The two occupied tracks and a spare track make
/// placement, ordering and isolation visible without snap rounding.
pub fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 7,
        "canvas": {"width": 1920, "height": 1080, "fps": [600000, 1],
            "background": [0, 0, 0, 1]},
        "media": [{"id": 1, "path": "/m/one.mov", "kind": "video",
            "duration": 6000000, "width": 1920, "height": 1080,
            "fps": [30, 1], "has_video": true, "has_audio": true}],
        "tracks": [{"id": 2, "name": "A"}, {"id": 3, "name": "B"},
            {"id": 4, "name": "Spare"}],
        "clips": [
            {"id": 10, "track": 2, "start": 0, "duration": 1000000,
                "source": {"kind": "media", "media": 1, "in": 0},
                "video": {}, "audio": {}},
            {"id": 11, "track": 2, "start": 2000000, "duration": 1000000,
                "source": {"kind": "media", "media": 1, "in": 0},
                "video": {}, "audio": {}},
            {"id": 12, "track": 3, "start": 0, "duration": 1000000,
                "source": {"kind": "media", "media": 1, "in": 0},
                "video": {}, "audio": {}}
        ],
        "nests": [], "markers": [], "next_id": 50
    }))
}

pub fn clip(value: &Value, id: u64) -> &Value {
    value["clips"]
        .as_array()
        .unwrap()
        .iter()
        .find(|clip| clip["id"] == id)
        .unwrap_or_else(|| panic!("missing clip {id}"))
}

pub fn clip_mut(value: &mut Value, id: u64) -> &mut Value {
    value["clips"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .find(|clip| clip["id"] == id)
        .unwrap_or_else(|| panic!("missing clip {id}"))
}

pub fn media_clip(value: &Value, id: u64, track: u64, start: i64, duration: i64) -> Value {
    let mut clip = clip(value, 10).clone();
    clip["id"] = json!(id);
    clip["track"] = json!(track);
    clip["start"] = json!(start);
    clip["duration"] = json!(duration);
    clip
}

pub fn track(value: &Value, id: u64, name: &str) -> Value {
    let mut track = value["tracks"][0].clone();
    track["id"] = json!(id);
    track["name"] = json!(name);
    track
}

#[allow(dead_code)] // Each integration suite compiles this shared fixture separately.
pub fn cross_dissolve() -> Value {
    json!({"kind":"cross_dissolve","curve":"ease_in_out","audio":true})
}

#[allow(dead_code)]
pub fn text_props(font: &str, content: &str) -> Value {
    json!({
        "align":"center", "animation":null, "backdrop":null,
        "color":[1.0,1.0,1.0,1.0], "content":content,
        "font":font, "line_spacing":1.0,
        "outline":null, "size":72.0, "tracking":0.0,
        "valign":"middle", "width":null
    })
}

#[allow(dead_code)]
pub fn text_clip(
    value: &Value,
    id: u64,
    track: u64,
    start: i64,
    duration: i64,
    font: &str,
    content: &str,
) -> Value {
    let mut result = media_clip(value, id, track, start, duration);
    result["source"] = json!({"kind":"text"});
    result["audio"] = Value::Null;
    result["text"] = text_props(font, content);
    result
}

#[allow(dead_code)]
pub fn nested_single(value: &Value) -> Value {
    let mut expected = value.clone();
    let mut inner = clip(value, 10).clone();
    inner["track"] = json!(51);
    let nested_track = track(value, 51, "A");
    expected["nests"].as_array_mut().unwrap().push(json!({
        "id":50, "name":"Nest 1", "width":1920, "height":1080,
        "tracks":[nested_track], "clips":[inner]
    }));
    expected["clips"].as_array_mut().unwrap().remove(0);
    let mut nest_clip = media_clip(value, 52, 2, 0, 1_000_000);
    nest_clip["source"] = json!({"kind":"nest","project":50});
    expected["clips"].as_array_mut().unwrap().push(nest_clip);
    expected["next_id"] = json!(53);
    expected
}

#[allow(dead_code)]
pub fn nested_pair(value: &Value) -> Value {
    let mut expected = value.clone();
    let mut first = clip(value, 10).clone();
    let mut second = clip(value, 11).clone();
    first["track"] = json!(51);
    second["track"] = json!(51);
    expected["nests"].as_array_mut().unwrap().push(json!({
        "id":50, "name":"Nest 1", "width":1920, "height":1080,
        "tracks":[track(value, 51, "A")], "clips":[first, second]
    }));
    expected["clips"] = json!([clip(value, 12), {
        "id":52, "track":2, "start":0, "duration":3_000_000,
        "source":{"kind":"nest","project":50},
        "enabled":{"audio":true,"video":true}, "speed":1.0,
        "video":clip(value, 10)["video"], "audio":clip(value, 10)["audio"],
        "text":null, "shape":null, "actions":[], "transition_in":null,
        "name":null, "label":null
    }]);
    expected["next_id"] = json!(53);
    expected
}
