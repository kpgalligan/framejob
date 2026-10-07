//! The graphic vocabulary (format version 10, road map 10's G2a) —
//! [`GraphicProps`], what a graphic clip is drawn from, and the checks
//! every writer of one shares: the module name rule (G-3), the side bound,
//! the schema a module declares and the props checked against it (G-4),
//! whose `color` props are stored through `model_color.rs`'s CSS colour
//! normalisation (G-12) — and whose `color` DEFAULTS are checked by it too,
//! so a default G-12 refuses refuses the schema (G-25 (a)).
//!
//! A graphic is a source the model only DESCRIBES, as text and shape are.
//! The core never reads the module (it has no filesystem), so the schema a
//! patch is checked against is an ARGUMENT of the op, and without one only
//! the shape is checked. The checks are the core's own, over [`Value`]: no
//! module of the model may name the engine's crate (spec §11 G-2), so its
//! schema sentences are COPIED verbatim and its limits restated.
//!
//! **`props` keeps the caller's key order.** `serde_json`'s map is
//! insertion-ordered in this build (`core/Cargo.toml`), the file is read
//! back byte for byte, and under that feature `Map::remove` SWAPS the last
//! key into the hole. So a props map is only ever changed by `insert` (an
//! existing key keeps its slot, a new one is appended) and `shift_remove`.
//! The serde rules are `model.rs`'s.

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::export::describe;
use crate::model_color::normalise_color;
use crate::time::Ticks;

/// The smallest side a graphic draws at, in pixels.
pub const GRAPHIC_MIN_SIDE: u32 = 1;

/// The largest side a graphic draws at, in pixels. Restates the engine's
/// `MAX_SIDE` and the header's `RC_GRAPHIC_MAX_SIDE` (G-2 forbids importing
/// it); `graphic_ffi.rs`'s `one_max_side_…` test pins the three equal.
pub const GRAPHIC_MAX_SIDE: u32 = 8192;

/// The most keys a stored `props` object may hold. Restates the engine's
/// `MAX_PROPS`, which bounds a schema the same way (G-4; G-2 forbids importing
/// it); `graphic_ffi.rs`'s `one_max_props_…` test pins the two equal.
pub const GRAPHIC_MAX_PROPS: usize = 64;

/// The engine's `MAX_OPTIONS` (an `enum` entry's), `MAX_STRING` (in characters) and
/// `TYPES` (its refusal's order), restated (G-2); `graphic_ffi.rs`'s `one_…` tests pin each.
pub const GRAPHIC_MAX_OPTIONS: usize = 32;
pub const GRAPHIC_MAX_STRING: usize = 4096;
pub const GRAPHIC_TYPES: [&str; 6] = ["string", "number", "boolean", "color", "enum", "asset"];

/// A bad module name's clause, for the ops and `validate` alike.
pub(crate) const NAME_RULE: &str = "is not a module name (lowercase letters, digits and -, \
     starting with a letter or a digit, at most 63 characters)";

/// A graphic clip's description: which module draws it, at what size, over
/// which stretch of its own timeline, with which props (road map 10 §5g).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct GraphicProps {
    /// The module, `graphics/<name>.js` in the package (G-3).
    pub name: String,
    /// The size the module draws at, in pixels — the layer's source size.
    pub width: u32,
    pub height: u32,
    /// The graphic's own frame the clip's first frame shows, in ticks.
    /// Not patchable: `trim_start`, `roll` and `split` own it (G-9).
    #[serde(rename = "in")]
    pub r#in: Ticks,
    /// The graphic's own length in ticks, or `None` for "the clip's
    /// duration" (G-9).
    pub length: Option<Ticks>,
    /// The values the module is drawn with, in the caller's key order.
    pub props: Map<String, Value>,
}

impl Default for GraphicProps {
    /// A hand-written file's graphic with no keys; never what an op stores.
    fn default() -> Self {
        GraphicProps {
            name: String::new(),
            width: 0,
            height: 0,
            r#in: 0,
            length: None,
            props: Map::new(),
        }
    }
}

/// G-3's rule, `^[a-z0-9][a-z0-9-]{0,62}$`: safe on disk, in a URL, in a tool.
pub(crate) fn check_name(name: &str) -> Result<(), String> {
    let mut chars = name.chars();
    let head = chars
        .next()
        .is_some_and(|c| c.is_ascii_lowercase() || c.is_ascii_digit());
    let rest = chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-');
    if head && rest && name.len() <= 63 {
        Ok(())
    } else {
        Err(format!("graphic name \"{name}\" {NAME_RULE}"))
    }
}

/// A side in pixels, 1 to 8192; a `u64` so a patch's number is named as sent.
pub(crate) fn check_side(key: &str, value: u64) -> Result<(), String> {
    if (u64::from(GRAPHIC_MIN_SIDE)..=u64::from(GRAPHIC_MAX_SIDE)).contains(&value) {
        Ok(())
    } else {
        Err(format!(
            "{key} must be between {GRAPHIC_MIN_SIDE} and {GRAPHIC_MAX_SIDE}, not {value}"
        ))
    }
}

/// §5c's rules for a schema, each refused in the engine's own sentence
/// (its `props.rs`, copied verbatim).
pub(crate) fn check_schema(schema: &Value) -> Result<(), String> {
    let Some(entries) = schema.as_object() else {
        return Err("schema must be an object".to_string());
    };
    if entries.len() > GRAPHIC_MAX_PROPS {
        return Err(format!(
            "schema has {} keys; the most is {GRAPHIC_MAX_PROPS}",
            entries.len()
        ));
    }
    for (key, entry) in entries {
        check_entry(key, entry)?;
    }
    Ok(())
}

fn check_entry(key: &str, entry: &Value) -> Result<(), String> {
    if !is_name(key) {
        return Err(format!(
            "schema key \"{key}\" is not a name (letters, digits and _, starting with a letter or _, at most 32 characters)"
        ));
    }
    let Some(kind) = entry.get("type").and_then(Value::as_str) else {
        return Err(format!("schema.{key} must be an object with a type"));
    };
    if !GRAPHIC_TYPES.contains(&kind) {
        return Err(format!(
            "schema.{key}.type \"{kind}\" is not one of string, number, boolean, color, enum, asset"
        ));
    }
    if kind == "enum" {
        let good = entry
            .get("options")
            .and_then(Value::as_array)
            .is_some_and(|o| {
                (1..=GRAPHIC_MAX_OPTIONS).contains(&o.len()) && o.iter().all(Value::is_string)
            });
        if !good {
            return Err(format!("schema.{key}.options must be 1–32 strings"));
        }
    }
    let Some(default) = entry.get("default") else {
        return Err(format!("schema.{key} has no default"));
    };
    let fits = match kind {
        "string" => default
            .as_str()
            .is_some_and(|s| s.chars().count() <= GRAPHIC_MAX_STRING),
        "color" => default.as_str().and_then(normalise_color).is_some(),
        "number" => default.as_f64().is_some_and(f64::is_finite),
        "boolean" => default.is_boolean(),
        "enum" => options(entry).contains(default),
        "asset" => default.is_string() || default.is_null(),
        _ => false,
    };
    if !fits {
        return Err(format!("schema.{key}.default {default} is not a {kind}"));
    }
    Ok(())
}

/// The engine's key rule, `^[A-Za-z_][A-Za-z0-9_]{0,31}$`.
fn is_name(key: &str) -> bool {
    let mut chars = key.chars();
    let head = chars
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_');
    head && key.len() <= 32 && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn options(entry: &Value) -> Vec<Value> {
    entry
        .get("options")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

/// A `props` patch checked key by key, answered as the copy to merge: each
/// `color` normalised, every `null` KEPT as a removal for the caller. With
/// a schema, each non-null key must be an entry and each value its type,
/// range and membership — a `null` is exempt, so a key stored before the
/// module dropped it can still be removed; without one only the shape is
/// checked. The key COUNT is
/// [`check_count`]'s, on the object about to be stored.
pub(crate) fn check_props(
    patch: &Map<String, Value>,
    schema: Option<&Value>,
) -> Result<Map<String, Value>, String> {
    let mut checked = Map::new();
    for (key, value) in patch {
        let value = match schema {
            // A removal is never checked, so a stale key can be cleared.
            Some(_) if value.is_null() => Value::Null,
            Some(schema) => {
                let Some(entry) = schema.get(key) else {
                    return Err(crate::patch::unknown_key(
                        &format!("props.{key}"),
                        "a graphic patch",
                    ));
                };
                check_typed(key, entry, value)?
            }
            None => {
                check_shape_only(key, value)?;
                value.clone()
            }
        };
        checked.insert(key.clone(), value);
    }
    Ok(checked)
}

/// One value against its schema entry, answered normalised.
pub(crate) fn check_typed(key: &str, entry: &Value, value: &Value) -> Result<Value, String> {
    let kind = entry.get("type").and_then(Value::as_str).unwrap_or("");
    let wrong = |what: &str| format!("props.{key} must be {what}, not {}", describe(value));
    match kind {
        "string" => {
            let text = value.as_str().ok_or_else(|| wrong("a string"))?;
            check_length(key, text)?;
        }
        "number" => {
            let number = value
                .as_f64()
                .filter(|n| n.is_finite())
                .ok_or_else(|| wrong("a number"))?;
            check_range(key, entry, number, value)?;
        }
        "boolean" => {
            value.as_bool().ok_or_else(|| wrong("a boolean"))?;
        }
        "color" => {
            let colour = value.as_str().and_then(normalise_color).ok_or_else(|| {
                wrong("a CSS colour (#rgb, #rgba, #rrggbb, #rrggbbaa, rgb(), rgba(), hsl(), hsla() or a colour name)")
            })?;
            return Ok(Value::String(colour));
        }
        "enum" => {
            let listed = options(entry);
            if !listed.contains(value) {
                let names: Vec<&str> = listed.iter().filter_map(Value::as_str).collect();
                return Err(wrong(&format!("one of {}", names.join(", "))));
            }
        }
        "asset" => {
            value
                .as_str()
                .ok_or_else(|| wrong("an asset's file name or null"))?;
        }
        // `check_schema` refuses any other type, and a schema reaches here
        // only through it.
        _ => return Err(wrong(&format!("a {kind}"))),
    }
    Ok(value.clone())
}

/// A number inside its entry's `min` and `max`, either of which may be
/// absent. `step` is a hint to the inspector's slider, not a rule.
fn check_range(key: &str, entry: &Value, number: f64, value: &Value) -> Result<(), String> {
    let min = entry.get("min").filter(|m| m.is_number());
    let max = entry.get("max").filter(|m| m.is_number());
    let below = min.and_then(Value::as_f64).is_some_and(|m| number < m);
    let above = max.and_then(Value::as_f64).is_some_and(|m| number > m);
    if !(below || above) {
        return Ok(());
    }
    let bounds = match (min, max) {
        (Some(min), Some(max)) => format!("between {min} and {max}"),
        (Some(min), None) => format!("at least {min}"),
        (None, Some(max)) => format!("at most {max}"),
        // Outside no bound is inside every bound.
        (None, None) => return Ok(()),
    };
    Err(format!("props.{key} must be {bounds}, not {value}"))
}

fn check_length(key: &str, text: &str) -> Result<(), String> {
    let count = text.chars().count();
    if count > GRAPHIC_MAX_STRING {
        return Err(format!(
            "props.{key} must be at most {GRAPHIC_MAX_STRING} characters, not {count}"
        ));
    }
    Ok(())
}

/// G-4's shape rule, the whole check when no schema came with the op.
fn check_shape_only(key: &str, value: &Value) -> Result<(), String> {
    if !is_name(key) {
        return Err(format!(
            "props key \"{key}\" is not a name (letters, digits and _, starting with a letter or _, at most 32 characters)"
        ));
    }
    match value {
        Value::String(text) => check_length(key, text),
        Value::Number(_) | Value::Bool(_) | Value::Null => Ok(()),
        other => Err(format!(
            "props.{key} must be a string, a number or a boolean, not {}",
            describe(other)
        )),
    }
}

/// G-4's key limit, on the object about to be STORED — after a merge and
/// its removals — because a patch of one key can push a full map over.
pub(crate) fn check_count(props: &Map<String, Value>) -> Result<(), String> {
    if props.len() > GRAPHIC_MAX_PROPS {
        return Err(format!(
            "props has {} keys; the most is {GRAPHIC_MAX_PROPS}",
            props.len()
        ));
    }
    Ok(())
}
