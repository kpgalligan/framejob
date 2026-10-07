//! The fixture `graphic_actions.rs` and `graphic_action_door.rs` share (spec
//! §11 G-34): a 30 fps project holding graphic clip 11 (0–5 s) and text
//! clip 12, the module schema the op carries, and the reads every claim is
//! made through — the recipe layer's `source`, `clip_state` and the
//! written text's key order. Included by `#[path]`, beside `common`.
#![allow(dead_code)] // Each suite that includes this uses part of it.

use serde_json::{json, Value};

use crate::common::{array, int, Handle};

/// Ticks per second (spec §5.1), written out rather than imported.
pub const SEC: i64 = 600_000;

/// One frame at 30 fps.
pub const FRAME: i64 = 20_000;

/// The module's schema: one entry of each type, `extra` and `tint` being
/// two the clip's own props do not hold.
pub fn schema() -> Value {
    json!({
        "title": {"type": "string", "default": "Jane"},
        "size": {"type": "number", "default": 64, "min": 0, "max": 400},
        "accent": {"type": "color", "default": "#ff5a36"},
        "boxed": {"type": "boolean", "default": true},
        "align": {"type": "enum", "default": "left", "options": ["left", "center", "right"]},
        "logo": {"type": "asset", "default": null},
        "extra": {"type": "number", "default": 7},
        "tint": {"type": "color", "default": "red"}
    })
}

/// The project as a value: graphic clip 11 on track 2 with props `title`,
/// `size` (an integer), `accent` (transparent black), `boxed`, `align`, in
/// that order, and text clip 12 on track 3.
pub fn base() -> Value {
    json!({
        "version": 12,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "tracks": [{"id": 2, "name": "G"}, {"id": 3, "name": "T"}],
        "clips": [
            {"id": 11, "track": 2, "start": 0, "duration": 5 * SEC,
             "source": {"kind": "graphic"}, "video": {},
             "graphic": {"name": "lower-third", "width": 640, "height": 360,
                         "props": {"title": "A", "size": 64, "accent": "#00000000",
                                   "boxed": true, "align": "left"}}},
            {"id": 12, "track": 3, "start": 0, "duration": 5 * SEC,
             "source": {"kind": "text"}, "video": {}, "text": {"content": "hi"}}
        ],
        "next_id": 20
    })
}

pub fn project() -> Handle {
    Handle::from_value(&base())
}

/// [`base`] with clip 11's props `key` set to `value`.
pub fn project_with(key: &str, value: Value) -> Handle {
    let mut project = base();
    project["clips"][0]["graphic"]["props"][key] = value;
    Handle::from_value(&project)
}

/// `handle` with a linear action on clip 11 at 1 s for 1 s, and its id.
pub fn with_action_on(handle: &Handle) -> (Handle, i64) {
    let added = handle.apply(&json!({"op": "add_action", "clip": 11, "at": SEC, "duration": SEC}));
    let id = int(&clip(&added, 11), "/actions/0/id");
    (added, id)
}

pub fn with_action() -> (Handle, i64) {
    with_action_on(&project())
}

/// `set_action_end` on clip 11 with the module's schema, as the app sends it.
pub fn end(action: i64, patch: Value) -> Value {
    json!({"op": "set_action_end", "clip": 11, "action": action, "patch": patch,
           "schema": schema()})
}

/// Clip `id` in `handle`'s project.
pub fn clip(handle: &Handle, id: i64) -> Value {
    array(&handle.value(), "/clips")
        .iter()
        .find(|c| int(c, "/id") == id)
        .unwrap_or_else(|| panic!("no clip {id}"))
        .clone()
}

/// The one graphic layer's `source` in the recipe at `t`.
pub fn source_at(handle: &Handle, t: i64) -> Value {
    let recipe = handle.recipe(t);
    array(&recipe, "/layers")
        .iter()
        .find(|l| l["source"]["kind"] == json!("graphic"))
        .unwrap_or_else(|| panic!("no graphic layer in {recipe}"))["source"]
        .clone()
}

pub fn props_at(handle: &Handle, t: i64) -> Value {
    source_at(handle, t)["props"].clone()
}

pub fn hash_at(handle: &Handle, t: i64) -> Value {
    source_at(handle, t)["hash"].clone()
}

/// The written text parsed: `serde_json`'s map keeps insertion order in
/// this build, so its keys are in the order the text holds them.
pub fn written(handle: &Handle) -> Value {
    serde_json::from_str(&handle.to_json()).expect("the written text")
}

/// The keys of the object at `pointer` in `value`, in order.
pub fn keys(value: &Value, pointer: &str) -> Vec<String> {
    value
        .pointer(pointer)
        .and_then(Value::as_object)
        .unwrap_or_else(|| panic!("no object at {pointer} in {value}"))
        .keys()
        .cloned()
        .collect()
}
