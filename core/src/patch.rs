//! Reading a caller-authored patch: the walk, the merge and the typed read
//! that every property patch in the crate comes through.
//!
//! A **patch** is a partial property object an op merges into a clip's
//! property group (`CONTEXT.md`). It merges key by key at every depth, an
//! array replaces its list, and `null` clears an optional key. It is the one
//! thing in the schema a CALLER writes rather than this crate — a typed
//! Swift builder, an MCP call, a project written by hand — so it is the one
//! thing that has to be read suspiciously, and this module is where that
//! happens: [`check_keys`] walks its keys and JSON kinds against the group's
//! own template, and [`merge_group`] merges and reads the result back as its
//! type, naming the dotted path (array indices included) and the offending
//! value in every refusal.
//!
//! Cut out of `edit_props.rs` under the size rule (core/CLAUDE.md: a module
//! over ~600 lines gives something up BEFORE it takes anything on), and cut
//! HERE for the reason `props_check.rs` was cut out of the same file in
//! phase 2: reading a patch is a fact about the VOCABULARY, not about an
//! edit. Nothing in this file is handed a clip, a project or a frame rate;
//! `edit_props.rs` owns the five ops that call it, and `edit_clip.rs`'s two
//! new-clip ops call it the same way.
//!
//! The rule the whole file exists for: **a key or a value the vocabulary
//! does not have is refused, never dropped and never corrected.** A typed
//! builder and an agent both reach these ops, and a key silently dropped
//! here is a bug the user would never see.

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::actions::{self, MAX_PATCH_DEPTH};
use crate::export::describe;
use crate::model::{
    AudioProps, Chroma, Compressor, Filter, Motion, ObscureRegion, Reflection, Shadow, ShapeProps,
    Spotlight, TextProps, VideoProps,
};

// ---- property groups -----------------------------------------------------

/// The four property groups a patch can address — and, as `video | audio |
/// text | shape` on the wire, the names `paste_attributes` takes. Carries
/// the group's name for error messages and its template for the
/// unknown-key check.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Group {
    Video,
    Audio,
    Text,
    Shape,
}

impl Group {
    pub(crate) fn name(self) -> &'static str {
        match self {
            Group::Video => "video",
            Group::Audio => "audio",
            Group::Text => "text",
            Group::Shape => "shape",
        }
    }

    /// The article before [`Group::name`] in the sentences that say which
    /// patch a mistake was in: `an audio patch`, never `a audio patch`.
    fn article(self) -> &'static str {
        match self {
            Group::Audio => "an",
            Group::Video | Group::Text | Group::Shape => "a",
        }
    }

    /// A fully-populated instance of the group, serialized: every optional
    /// sub-object present, so the key check can see inside `shadow`,
    /// `chroma`, `reflection`, `spotlight`, `duck`, `compressor`,
    /// `outline`, `backdrop`, `animation`, `stroke` and `gradient` even when
    /// the clip
    /// currently has `null` there — and one `filters` entry and one `obscure` region, so
    /// it can see inside the elements of the two arrays of objects too.
    /// Both entries are load-bearing: `check_keys` reads the FIRST element
    /// of the template's array as the reference for every element it is
    /// given, so a list left at its empty default would hand it no
    /// reference at all and a misspelling inside a region would be dropped
    /// in silence — the very failure the array arm was written for.
    /// `Gradient::default()` earns its place twice over for that reason: it
    /// is the only optional sub-object that CONTAINS an array of objects,
    /// and its own default carries two stops, so `stops[].at` and
    /// `stops[].color` get a reference without this arm naming them.
    fn template(self) -> Value {
        match self {
            Group::Video => actions::to_json(&VideoProps {
                shadow: Some(Shadow::default()),
                chroma: Some(Chroma::default()),
                filters: vec![Filter::default()],
                reflection: Some(Reflection::default()),
                spotlight: Some(Spotlight::default()),
                obscure: vec![ObscureRegion::default()],
                motion: Some(Motion::template()),
                ..VideoProps::default()
            }),
            Group::Audio => actions::to_json(&AudioProps {
                duck: Some(crate::model::Duck::default()),
                compressor: Some(Compressor::default()),
                ..AudioProps::default()
            }),
            Group::Text => actions::to_json(&TextProps {
                outline: Some(crate::model::Outline::default()),
                backdrop: Some(crate::model::Backdrop::default()),
                width: Some(0.0),
                animation: Some(crate::model::TextAnimation::default()),
                ..TextProps::default()
            }),
            Group::Shape => actions::to_json(&ShapeProps {
                stroke: Some(crate::model::Stroke::default()),
                fill: Some([0.0, 0.0, 0.0, 1.0]),
                gradient: Some(crate::model::Gradient::default()),
                ..ShapeProps::default()
            }),
        }
    }
}

/// Rejects any key in `patch` the group's schema does not have, and any
/// value whose JSON kind is not the one the schema has there, naming the
/// dotted path to it — array indices included, so `filters[1].kindd` says
/// WHICH entry to fix, where a bare `filters.kindd` would leave the caller
/// comparing every entry it sent. `path` is the path to `patch` itself,
/// empty at the group's root. Recursion is bounded by the same depth action
/// patches use; past it the check stops rather than descending an arbitrary
/// tree, and serde drops whatever it finds there.
fn check_keys(
    patch: &Value,
    template: &Value,
    group: Group,
    path: &str,
    depth: u32,
) -> Result<(), String> {
    // The kind comes first, and it is not only a nicer sentence than
    // serde's `expected struct Duck`: serde READS two wrong kinds. A struct
    // deserializes from a JSON array of its fields in declaration order, so
    // `{"duck": [0.9, 300000, 600000]}` would store a duck, and a unit
    // variant from a one-key object, so `{"blend": {"multiply": null}}`
    // would store a blend — spellings the caller never learnt from
    // `get_project` and a typo could land on by accident.
    if let Some(expected) = wrong_kind(patch, template) {
        return Err(format!(
            "bad value at \"{path}\" in {} {} patch: expected {expected}, not {}",
            group.article(),
            group.name(),
            describe(patch)
        ));
    }
    // An array of objects — `video.filters`, and from format version 4
    // `video.obscure` — is where the schema puts keys inside an array, and
    // every element has the SAME shape, so the template's first entry
    // describes all of them. Without this a misspelled
    // `{"filters": [{"amont": 1}]}` would be dropped in silence by serde,
    // which is exactly the failure this check exists to prevent.
    // Arrays of numbers (a colour, `from`/`to`) fall through it harmlessly:
    // a number against a number has no keys to check.
    if let (Value::Array(given), Value::Array(known)) = (patch, template) {
        if depth < MAX_PATCH_DEPTH {
            if let Some(reference) = known.first() {
                for (index, value) in given.iter().enumerate() {
                    let here = format!("{path}[{index}]");
                    check_keys(value, reference, group, &here, depth + 1)?;
                }
            }
        }
        return Ok(());
    }
    let (Value::Object(given), Value::Object(known)) = (patch, template) else {
        // A leaf or a `null` (clearing an optional group): no keys to
        // check.
        return Ok(());
    };
    if depth >= MAX_PATCH_DEPTH {
        return Ok(());
    }
    for (key, value) in given {
        let here = if path.is_empty() {
            key.clone()
        } else {
            format!("{path}.{key}")
        };
        let Some(reference) = known.get(key) else {
            return Err(format!(
                "unknown key \"{here}\" in {} {} patch",
                group.article(),
                group.name()
            ));
        };
        check_keys(value, reference, group, &here, depth + 1)?;
    }
    Ok(())
}

/// The JSON kind the schema has where the template holds `reference`, as a
/// refusal says it, when `given` is NOT that kind; `None` when it is.
///
/// A `null` on either side passes: in a patch it clears, and whether the
/// field may be cleared is the read's to say (an optional takes it, a
/// required one refuses it). A number is one kind with one refinement —
/// the template writes every `f64` with a fraction and every tick count
/// without one, so a fraction where a tick count belongs is named here
/// rather than as serde's `expected i64`.
fn wrong_kind(given: &Value, reference: &Value) -> Option<&'static str> {
    let fits = match (given, reference) {
        (Value::Null, _) | (_, Value::Null) => true,
        (Value::Number(given), Value::Number(reference)) => reference.is_f64() || !given.is_f64(),
        (Value::Bool(_), Value::Bool(_))
        | (Value::String(_), Value::String(_))
        | (Value::Array(_), Value::Array(_))
        | (Value::Object(_), Value::Object(_)) => true,
        _ => false,
    };
    if fits {
        return None;
    }
    Some(match reference {
        Value::Number(number) if !number.is_f64() => "a whole number",
        Value::Number(_) => "a number",
        Value::Bool(_) => "true or false",
        Value::String(_) => "a string",
        Value::Array(_) => "a list",
        Value::Object(_) | Value::Null => "an object",
    })
}

/// Checks the patch's keys and kinds, merges it into `base` and reads the
/// merged group back as its type — the one door every caller-authored patch
/// of a group comes through, `set_*` and the `text` / `shape` of a new clip
/// alike. The merge itself is `actions::merge`, the one deep merge in the
/// crate.
///
/// The walk has already refused an unknown key and a value of the wrong
/// kind; the read is where what only the TYPE knows is caught — a misspelt
/// variant, a `null` a required field cannot take, a colour of the wrong
/// length. It goes through `serde_path_to_error` so that refusal says WHERE
/// in the walk's own spelling: serde's sentence alone names the value and
/// what the vocabulary allows, but not which of four filters it was in. The
/// path is into the MERGED group, which is the patch's path too: the merge
/// keeps every key where the patch put it and an array replaces whole, and
/// the base was written by this crate and reads back cleanly, so the only
/// values that can fail are the patch's.
pub(crate) fn merge_group<T: Serialize + DeserializeOwned>(
    base: &T,
    patch: &Value,
    group: Group,
) -> Result<T, String> {
    if !patch.is_object() {
        return Err(format!(
            "{} patch must be a json object, not {}",
            group.name(),
            describe(patch)
        ));
    }
    check_keys(patch, &group.template(), group, "", 0)?;
    let merged = actions::merge(&actions::to_json(base), patch);
    serde_path_to_error::deserialize(merged).map_err(|e| {
        format!(
            "bad value at \"{}\" in {} {} patch: {}",
            e.path(),
            group.article(),
            group.name(),
            e.inner()
        )
    })
}
