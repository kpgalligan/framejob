//! Actions classed by content, with no tag (spec §11 CU-73, CO-63; CJ-8
//! (i)): what an action's end patch DOES, read from its keys. Auto Zoom's
//! Replace removes only zooms (`cursor_zoom.rs`); CO6's layouts read
//! `is_layout` and `moves`.
//!
//! - A **zoom** is an end whose `video` keys are exactly `scale`, `x` and
//!   `y`, naming no other group (an empty `audio` or `text`, or a `graphic`
//!   with no props, names nothing) and no `speed` — the twin of the app's
//!   `ActionBands.isZoom`, which draws the zoom glyph.
//! - A **layout** names all six [`PLACEMENT_KEYS`] in `video`.
//! - An action **moves** its clip when its `video` names any of the six.

use serde_json::Value;

use crate::model::Action;

/// The keys that place a picture on the canvas.
pub(crate) const PLACEMENT_KEYS: [&str; 6] =
    ["x", "y", "scale", "crop", "corner_radius", "opacity"];

/// The end's `video` object, when it is one.
fn video(action: &Action) -> Option<&serde_json::Map<String, Value>> {
    action.end.get("video").and_then(Value::as_object)
}

/// Absent, null or `{}`.
fn names_nothing(group: Option<&Value>) -> bool {
    match group {
        None | Some(Value::Null) => true,
        Some(Value::Object(map)) => map.is_empty(),
        Some(_) => false,
    }
}

/// A screencast zoom's end: `video` exactly {scale, x, y}; `audio` and
/// `text` naming nothing; `graphic` naming no props; no numeric `speed`.
pub(crate) fn is_zoom(action: &Action) -> bool {
    let Some(video) = video(action) else {
        return false;
    };
    let end = &action.end;
    let graphic_quiet = match end.get("graphic") {
        None | Some(Value::Null) => true,
        Some(g) => names_nothing(g.get("props")),
    };
    let no_speed = !end.get("speed").is_some_and(Value::is_number);
    video.len() == 3
        && ["scale", "x", "y"].iter().all(|k| video.contains_key(*k))
        && names_nothing(end.get("audio"))
        && names_nothing(end.get("text"))
        && graphic_quiet
        && no_speed
}

/// A layout action: its `video` names all six placement keys. CO6's
/// `switch_layout` is its first reader (CO-63); CU7 only defines it.
#[allow(dead_code)]
pub(crate) fn is_layout(action: &Action) -> bool {
    video(action).is_some_and(|v| PLACEMENT_KEYS.iter().all(|k| v.contains_key(*k)))
}

/// Whether the action moves its clip: its `video` names any placement key.
pub(crate) fn moves(action: &Action) -> bool {
    video(action).is_some_and(|v| PLACEMENT_KEYS.iter().any(|k| v.contains_key(*k)))
}
