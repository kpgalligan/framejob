//! `set_action_end`'s graphic arm (format version 13, spec §11 G-34): the
//! door through which an action's `end` comes to carry
//! `graphic: {props: {<key>: <value>}, kinds: {<key>: <type>}}`.
//!
//! It is a door of its own and not a fifth `patch::Group` (G-32 (h)
//! stands): a graphic's keys are its MODULE's, not the vocabulary's, so
//! there is no template to walk. What a prop may hold is read from the
//! `schema` the op carries — the module's current revision, filled by the
//! app and never by a caller (G-4) — through `model_graphic.rs`'s
//! `check_typed`, the check `set_graphic` makes, under `graphic.props.<key>`.
//!
//! **This is the one end that IS range-checked** (§5.4's ends are not),
//! because nothing clamps a prop downstream: the engine reads no
//! `min`/`max`, and `actions_clamp.rs`'s `clamp_video` never sees `graphic`.
//! Every curve is monotone, so a ramp between two in-range ends stays in
//! range. Only the props a PATCH names are read; a stored end is never
//! re-checked, so a project whose module has since narrowed a range still
//! takes an edit to another prop.
//!
//! Each named prop's schema `type` is written into `kinds`, which is how the
//! evaluator (`actions_graphic.rs`) knows a colour from a string; a `kinds`
//! in a patch is read and discarded, so an end read back from `get_project`
//! can be sent again and no caller decides a kind. A prop the clip's own map
//! lacks starts from the schema's CURRENT default, appended in the same
//! edit (G-34 (d)). Maps change only by `insert` and `shift_remove`
//! (`model_graphic.rs`'s rule).
//!
//! A prop whose schema entry says `animate: false` is refused by name, as
//! an asset is (G-41): its module draws it whole, a count or a layout mode a
//! ramp would break. Like every check here it reads only a named, non-null
//! prop, so an end that named the prop before its module said so keeps
//! animating it as stored, and a `null` removes it.

use serde_json::{Map, Value};

use crate::edit_action::END_PATCH;
use crate::export::describe;
use crate::model::{Clip, Source};
use crate::model_color::normalise_color;
use crate::model_graphic::check_typed;
use crate::patch::unknown_key;

/// `off` cannot name `graphic` (G-34 (j)): a prop has no "off" to key.
pub(crate) const GRAPHIC_NOT_KEYED_OFF: &str =
    "graphic props cannot be keyed off; name the value a prop ends at in patch";

/// The graphic's LAYER keys: real keys of `graphic`, and not an action's.
const LAYER_KEYS: [&str; 5] = ["name", "width", "height", "in", "length"];

/// A patch's `graphic` body, read and checked.
pub(crate) struct GraphicEnd {
    /// `graphic: null` or `graphic.props: null`: drop the group.
    pub(crate) remove: bool,
    /// Each named prop, checked and normalised; `Null` means removal.
    pub(crate) props: Map<String, Value>,
    /// A `Value::String(type)` per non-null prop, from the schema.
    pub(crate) kinds: Map<String, Value>,
    /// The schema's default for each non-null prop the clip's map lacks.
    pub(crate) starts: Map<String, Value>,
}

/// Reads `body`, the patch's `graphic` value, for `clip` against `schema`.
/// `Err` in the dotted path's own sentence for a body or `props` that is not
/// an object, a layer key, an unknown key, and for each non-null prop, in
/// this order: a clip that is not a graphic, no schema, a prop the schema
/// lacks, a prop marked `animate: false` (G-41), an asset, and whatever
/// `check_typed` refuses.
pub(crate) fn read_graphic_end(
    clip: &Clip,
    body: &Value,
    schema: Option<&Value>,
) -> Result<GraphicEnd, String> {
    let mut read = GraphicEnd {
        remove: false,
        props: Map::new(),
        kinds: Map::new(),
        starts: Map::new(),
    };
    let fields = match body {
        Value::Null => {
            read.remove = true;
            return Ok(read);
        }
        Value::Object(fields) => fields,
        other => {
            return Err(format!(
                "graphic in an action end patch must be a json object, not {}",
                describe(other)
            ))
        }
    };
    let mut props = None;
    for (key, value) in fields {
        match key.as_str() {
            "props" => props = Some(value),
            // Rewritten from the schema for every named prop (G-34 (a)).
            "kinds" => {}
            layer if LAYER_KEYS.contains(&layer) => {
                return Err(format!(
                    "graphic.{layer} is not an animation target; an action animates graphic.props"
                ))
            }
            other => return Err(unknown_key(&format!("graphic.{other}"), END_PATCH)),
        }
    }
    let props = match props {
        None => return Ok(read),
        Some(Value::Null) => {
            read.remove = true;
            return Ok(read);
        }
        Some(Value::Object(props)) => props,
        Some(other) => {
            return Err(format!(
                "graphic.props must be a json object, not {}",
                describe(other)
            ))
        }
    };
    for (key, value) in props {
        // A removal is never checked, so a stale key can go (G-34 (j)).
        if value.is_null() {
            read.props.insert(key.clone(), Value::Null);
            continue;
        }
        let stored = clip
            .graphic
            .as_ref()
            .filter(|_| matches!(clip.source, Source::Graphic))
            .ok_or_else(|| format!("clip {} is not a graphic clip", clip.id))?;
        let schema = schema.ok_or_else(|| {
            format!(
                "graphic.props.{key} needs its module's schema to animate, and none came with the op"
            )
        })?;
        let entry = schema
            .get(key)
            .ok_or_else(|| unknown_key(&format!("graphic.props.{key}"), END_PATCH))?;
        if entry.get("animate") == Some(&Value::Bool(false)) {
            return Err(format!(
                "graphic.props.{key} is marked animate: false by its module; an action does not \
                 animate it — set it with set_graphic"
            ));
        }
        let kind = entry.get("type").and_then(Value::as_str).unwrap_or("");
        if kind == "asset" {
            return Err(format!(
                "graphic.props.{key} is an asset; an action does not animate an image — set it \
                 with set_graphic"
            ));
        }
        let value = check_typed(key, entry, value).map_err(|why| format!("graphic.{why}"))?;
        read.props.insert(key.clone(), value);
        read.kinds
            .insert(key.clone(), Value::String(kind.to_string()));
        if !stored.props.contains_key(key) {
            if let Some(default) = schema_default(schema, key) {
                read.starts.insert(key.clone(), default);
            }
        }
    }
    Ok(read)
}

/// Writes a read `graphic` body into `end`, an object after the generic
/// merge. A group or slot that is not an object is replaced by `{}` only
/// when a value is to be written into it; a removal creates nothing.
pub(crate) fn write_graphic_end(end: &mut Value, read: &GraphicEnd) {
    let Value::Object(groups) = end else {
        return;
    };
    if read.remove {
        groups.shift_remove("graphic");
        return;
    }
    if read.props.values().any(|value| !value.is_null()) {
        let graphic = groups
            .entry("graphic")
            .or_insert_with(|| Value::Object(Map::new()));
        if !graphic.is_object() {
            *graphic = Value::Object(Map::new());
        }
        if let Value::Object(graphic) = graphic {
            // `props` before `kinds`, the stored order.
            for slot in ["props", "kinds"] {
                let slot = graphic
                    .entry(slot)
                    .or_insert_with(|| Value::Object(Map::new()));
                if !slot.is_object() {
                    *slot = Value::Object(Map::new());
                }
            }
        }
    }
    let Some(Value::Object(graphic)) = groups.get_mut("graphic") else {
        return;
    };
    for (key, value) in &read.props {
        if value.is_null() {
            for slot in ["props", "kinds"] {
                if let Some(Value::Object(map)) = graphic.get_mut(slot) {
                    map.shift_remove(key);
                }
            }
            continue;
        }
        if let Some(Value::Object(map)) = graphic.get_mut("props") {
            map.insert(key.clone(), value.clone());
        }
        if let (Some(kind), Some(Value::Object(map))) =
            (read.kinds.get(key), graphic.get_mut("kinds"))
        {
            map.insert(key.clone(), kind.clone());
        }
    }
}

/// The schema entry's default for `key`, a `color` normalised (G-12);
/// `None` for no entry, no default, or an `asset`, which an action never
/// animates.
pub(crate) fn schema_default(schema: &Value, key: &str) -> Option<Value> {
    let entry = schema.get(key)?;
    let default = entry.get("default")?;
    match entry.get("type").and_then(Value::as_str) {
        Some("asset") => None,
        Some("color") => default
            .as_str()
            .and_then(normalise_color)
            .map(Value::String),
        _ => Some(default.clone()),
    }
}
