//! A module's schema and the props drawn with it (road map 10 §5c, G-4):
//! the schema is checked strictly when a module compiles; stored props are
//! laid over it leniently at render time, every surprise a warning.

use serde_json::{Map, Value};

use crate::diagnostic::Diagnostic;

const MAX_KEYS: usize = 64;
const MAX_OPTIONS: usize = 32;
const MAX_STRING: usize = 4096;
const TYPES: [&str; 6] = ["string", "number", "boolean", "color", "enum", "asset"];

/// §5c's rules for a schema, each refused in its own sentence.
pub(crate) fn check_schema(schema: &Value) -> Result<(), Diagnostic> {
    let Some(entries) = schema.as_object() else {
        return Err(Diagnostic::error("schema must be an object"));
    };
    if entries.len() > MAX_KEYS {
        return Err(Diagnostic::error(format!(
            "schema has {} keys; the most is {MAX_KEYS}",
            entries.len()
        )));
    }
    for (key, entry) in entries {
        check_entry(key, entry).map_err(Diagnostic::error)?;
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
    if !TYPES.contains(&kind) {
        return Err(format!(
            "schema.{key}.type \"{kind}\" is not one of string, number, boolean, color, enum, asset"
        ));
    }
    if kind == "enum" {
        let good = entry
            .get("options")
            .and_then(Value::as_array)
            .is_some_and(|o| {
                (1..=MAX_OPTIONS).contains(&o.len()) && o.iter().all(Value::is_string)
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
            .is_some_and(|s| s.chars().count() <= MAX_STRING),
        _ => fits(kind, entry, default),
    };
    if !fits {
        return Err(format!("schema.{key}.default {default} is not a {kind}"));
    }
    Ok(())
}

fn is_name(key: &str) -> bool {
    let mut chars = key.chars();
    let head = chars
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_');
    head && key.len() <= 32 && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

/// Whether `value` is of the entry's `kind` (render time: a string's length
/// is not checked).
fn fits(kind: &str, entry: &Value, value: &Value) -> bool {
    match kind {
        "string" | "color" => value.is_string(),
        "number" => value.as_f64().is_some_and(f64::is_finite),
        "boolean" => value.is_boolean(),
        "enum" => options(entry).contains(value),
        "asset" => value.is_string() || value.is_null(),
        _ => false,
    }
}

fn options(entry: &Value) -> Vec<Value> {
    entry
        .get("options")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

/// `stored` laid over the schema's defaults, in the schema's key order,
/// then the stored keys the schema lacks, passed through. Never refuses:
/// every key that did not fit is the default plus a warning.
pub fn overlay(schema: &Value, stored: &Value) -> (Value, Vec<Diagnostic>) {
    let mut warnings = Vec::new();
    let empty = Map::new();
    let stored = match stored {
        Value::Object(map) => map,
        other => {
            warnings.push(Diagnostic::warning(format!(
                "props is {}, not an object; the defaults are used",
                kind_of(other)
            )));
            &empty
        }
    };
    let entries = schema.as_object().cloned().unwrap_or_default();
    let mut props = Map::new();
    for (key, entry) in &entries {
        let default = entry.get("default").cloned().unwrap_or(Value::Null);
        let kind = entry.get("type").and_then(Value::as_str).unwrap_or("");
        let value = match stored.get(key) {
            None => default,
            Some(value) if fits(kind, entry, value) => value.clone(),
            Some(value) if kind == "enum" && value.is_string() => {
                warnings.push(Diagnostic::warning(format!(
                    "props.{key} = {value} is not one of {}; the default {default} is used",
                    Value::from(options(entry))
                )));
                default
            }
            Some(value) => {
                warnings.push(Diagnostic::warning(format!(
                    "props.{key} is {} but the schema says {kind}; the default {default} is used",
                    kind_of(value)
                )));
                default
            }
        };
        props.insert(key.clone(), value);
    }
    for (key, value) in stored {
        if !entries.contains_key(key) {
            warnings.push(Diagnostic::warning(format!(
                "props.{key} is not in the schema; it is passed through"
            )));
            props.insert(key.clone(), value.clone());
        }
    }
    (Value::Object(props), warnings)
}

fn kind_of(value: &Value) -> &'static str {
    match value {
        Value::String(_) => "a string",
        Value::Number(_) => "a number",
        Value::Bool(_) => "a boolean",
        Value::Null => "null",
        Value::Array(_) => "an array",
        Value::Object(_) => "an object",
    }
}
