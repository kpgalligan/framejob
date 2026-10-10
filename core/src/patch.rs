//! Reading a caller-authored patch: the walk, the merge and the typed read
//! that every property patch in the crate comes through.
//!
//! A **patch** is a partial property object an op merges into a clip's
//! property group (`CONTEXT.md`). It merges key by key at every depth, an
//! array replaces its list, and `null` clears an optional key. It is the one
//! thing in the schema a CALLER writes rather than this crate — a typed
//! Swift builder, an MCP call, a project written by hand — so it is the one
//! thing that has to be read suspiciously. The rule the whole file exists
//! for: **a key or a value the vocabulary does not have is refused, never
//! dropped and never corrected** — [`check_keys`] walks a patch's keys and
//! JSON kinds against the group's own template, [`merge_group`] merges and
//! reads the result back as its type, and [`check_group_patch`] does both
//! for a group that is NOT merged into a stored one, which is what
//! `edit_action.rs` builds an action's end-patch door out of. Every refusal
//! names the dotted path (array indices included) and the value sent.
//!
//! Cut out of `edit_props.rs` under the size rule (core/CLAUDE.md), and cut
//! HERE for the reason `props_check.rs` was cut out of the same file in
//! phase 2: reading a patch is a fact about the VOCABULARY, not about an
//! edit. Nothing here is handed a clip, a project or a frame rate.

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

/// The four property groups a PATCH can address, `video | audio | text |
/// shape` on the wire. `paste_attributes` takes these four and `graphic`,
/// as `edit_paste_attributes.rs`'s `PasteGroup` (spec §11 G-32): a patch
/// has no fifth group. Carries the group's name for error messages and its
/// template for the unknown-key check.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Group {
    Video,
    Audio,
    Text,
    Shape,
}

/// Every group in its order on `Clip` — the order `paste` and a default
/// `paste_attributes` visit them, so a range error names the schema's first.
pub(crate) const GROUPS: [Group; 4] = [Group::Video, Group::Audio, Group::Text, Group::Shape];

impl Group {
    pub(crate) fn name(self) -> &'static str {
        match self {
            Group::Video => "video",
            Group::Audio => "audio",
            Group::Text => "text",
            Group::Shape => "shape",
        }
    }

    /// What a refusal calls this group's patch — the whole phrase, so the
    /// sentences read `an audio patch` and never `a audio patch`.
    /// [`check_keys`] takes one as a string because it walks an action's
    /// END patch too, which spans three groups and is [`END_PATCH`].
    fn subject(self) -> &'static str {
        match self {
            Group::Video => "a video patch",
            Group::Audio => "an audio patch",
            Group::Text => "a text patch",
            Group::Shape => "a shape patch",
        }
    }

    /// A fully-populated instance of the group, serialized: every optional
    /// sub-object present, so the key check can see inside `shadow`,
    /// `chroma`, `reflection`, `spotlight`, `duck`, `compressor`, `outline`,
    /// `backdrop`, `animation`, `word_style`, `stroke` and `gradient` even
    /// when the clip currently has `null` there — and one `filters` entry,
    /// one `obscure` region and one `text.words` entry, so it can see inside
    /// the three arrays of objects too.
    /// Both entries are load-bearing: `check_keys` reads the FIRST element
    /// of the template's array as the reference for every element it is
    /// given, so a list left at its empty default would hand it no reference
    /// and a misspelling inside a region would be dropped in silence — the
    /// very failure the array arm was written for. `Gradient::default()`
    /// earns its place twice over: it is the only optional sub-object that
    /// CONTAINS an array of objects, and its own default carries two stops,
    /// so `stops[].at` and `stops[].color` get a reference without this arm
    /// naming them.
    fn template(self) -> Value {
        match self {
            // `video_json`: tone's neutral keys are left out of `to_json`
            // and would read as unknown here (spec §11 GR-2).
            Group::Video => actions::video_json(&VideoProps {
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
                words: vec![crate::model::Word::default()],
                word_style: Some(crate::model::WordStyle::template()),
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
/// patches use; past it the check stops rather than walking an arbitrary
/// tree, and serde drops whatever it finds there.
fn check_keys(
    patch: &Value,
    template: &Value,
    subject: &str,
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
            "bad value at \"{path}\" in {subject}: expected {expected}, not {}",
            describe(patch)
        ));
    }
    // An array of objects — `video.filters`, and from format version 4
    // `video.obscure` — is where the schema puts keys inside an array, and
    // every element has the SAME shape, so the template's first entry
    // describes all of them. Without this a misspelled
    // `{"filters": [{"amont": 1}]}` would be dropped in silence by serde,
    // the failure this check exists to prevent. Arrays of numbers (a
    // colour, `from`/`to`) fall through harmlessly: a number against a
    // number has no keys to check.
    if let (Value::Array(given), Value::Array(known)) = (patch, template) {
        if depth < MAX_PATCH_DEPTH {
            if let Some(reference) = known.first() {
                let required = COMPLETE_ENTRIES
                    .iter()
                    .find(|(key, _)| *key == last_segment(path))
                    .map(|(_, keys)| *keys);
                for (index, value) in given.iter().enumerate() {
                    let here = format!("{path}[{index}]");
                    check_keys(value, reference, subject, &here, depth + 1)?;
                    if let Some(required) = required {
                        check_complete(value, required, subject, &here)?;
                    }
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
            return Err(format!("unknown key \"{here}\" in {subject}"));
        };
        check_keys(value, reference, subject, &here, depth + 1)?;
    }
    Ok(())
}

/// The lists whose entries a patch must spell out IN FULL, by the key that
/// holds them.
///
/// An array replaces its list (`CONTEXT.md`), so an entry in a patch is
/// merged over NOTHING and every key it leaves out comes from the type's
/// serde defaults instead. For `video.filters` that completion is a picture
/// nobody asked for: `{"filters": [{"amount": 1}]}` reads as "the same
/// filter, more of it", which is what it means while an action interpolates
/// it, and lands as a half-strength BLUR — the two keys ARE the filter, and
/// neither has a defensible default when the other is named.
///
/// The schema's other two lists of objects are deliberately NOT here:
/// `video.obscure` is a box whose six geometry defaults are a real, centred
/// region and `shape.gradient.stops` is a position and a colour, so in both
/// an omitted key leaves the entry recognisably the thing the caller named.
/// The match is on the LAST segment of the path, so the rule holds at
/// `filters` in a group patch and at `video.filters` in an end patch
/// without being written twice.
///
/// The required keys are SPELLED rather than taken from the template's own
/// entry, and the difference only shows up later: a field added to
/// [`crate::model::Filter`] would otherwise join the requirement the day it
/// landed and refuse every patch every agent had already learnt to write —
/// where a new field's serde default is, by construction, the value every
/// older project already has.
///
/// `text.words` (format version 9) is the second entry, for the filter's
/// reason read on a clock: a word IS its two times, and a `{"start": …}`
/// whose `end` came from the type's default would be a word that ends at
/// clip time 0 — before it starts, which `check_text` would then refuse in
/// a sentence about an `end` the caller never sent. Naming the missing key
/// is the refusal that tells the caller what to fix.
const COMPLETE_ENTRIES: [(&str, &[&str]); 2] = [
    ("filters", &["kind", "amount"]),
    ("words", &["start", "end"]),
];

/// The last dotted segment of `path` — the key an array is held under,
/// which is what [`COMPLETE_ENTRIES`] is matched against.
fn last_segment(path: &str) -> &str {
    path.rsplit('.').next().unwrap_or(path)
}

/// Refuses an entry of a [`COMPLETE_ENTRIES`] list that does not name every
/// `required` key, by the path to the key it left out. A `null` is not a
/// spelling of a key either: it clears an optional field, and nothing named
/// here is optional.
fn check_complete(
    entry: &Value,
    required: &[&str],
    subject: &str,
    path: &str,
) -> Result<(), String> {
    let Value::Object(given) = entry else {
        return Ok(());
    };
    for key in required {
        if given.get(*key).unwrap_or(&Value::Null).is_null() {
            return Err(format!("missing key \"{path}.{key}\" in {subject}"));
        }
    }
    Ok(())
}

/// Reads a merged group back as its type, naming the path and the value of
/// whatever only the TYPE can refuse — a misspelt variant, a `null` a
/// required field cannot take, a colour of the wrong length.
///
/// `serde_path_to_error` is what makes the path possible: serde's sentence
/// names the value and what the vocabulary allows, but not which of four
/// filters it was in. `prefix` is what the path hangs off when the group is
/// not the root — its name inside an end patch — so one sentence serves
/// both doors.
fn read_merged<T: DeserializeOwned>(
    merged: Value,
    subject: &str,
    prefix: &str,
) -> Result<T, String> {
    serde_path_to_error::deserialize(merged).map_err(|e| {
        let path = path_under(prefix, &e.path().to_string());
        format!("bad value at \"{path}\" in {subject}: {}", e.inner())
    })
}

/// Where a `serde_path_to_error` path sits under `prefix` — the one
/// spelling of that join, because there are two callers and the trap is
/// invisible from either: `Path`'s ROOT prints as `"."` and not as the
/// empty string, so the naive `format!("{prefix}.{inside}")` reads
/// `video..` for an error at the group itself. Both spellings of "the whole
/// thing" collapse onto `prefix` here.
///
/// `edit_zoom.rs`'s `ZoomRegion` is the second caller, and it is what found
/// this: its `region..` was reachable from the app the moment D1·5 stopped
/// the Swift side refusing a missing member first.
pub(crate) fn path_under(prefix: &str, inside: &str) -> String {
    let inside = if inside == "." { "" } else { inside };
    match (prefix, inside) {
        ("", inside) => inside.to_string(),
        (prefix, "") => prefix.to_string(),
        (prefix, inside) => format!("{prefix}.{inside}"),
    }
}

/// The refusal every walk gives for a key the vocabulary does not have,
/// spelled once so a door that walks a patch group by group
/// (`edit_action.rs`'s end patch) says it in the same words.
pub(crate) fn unknown_key(path: &str, subject: &str) -> String {
    format!("unknown key \"{path}\" in {subject}")
}

/// Walks and reads ONE group's body out of a patch that is not being merged
/// into a stored group — an action's end state, where the patch is a patch
/// of a patch and there is no clip to merge into.
///
/// `prefix` is where the body sits in the patch (`video`), so the paths the
/// refusals name carry it: `bad value at "video.filters[1].kind"`. The read
/// goes against the group's own TEMPLATE, which is what lets a sparse patch
/// read at all; the merged value is thrown away, because only the refusal
/// is wanted. It is a walk and a read and NOT a range check: the state a
/// clip interpolates toward may legitimately name a value no stored group
/// could hold, and `actions_clamp.rs`'s `clamp_video` bounds the evaluated value
/// instead.
///
/// **A `null` here can only be a REMOVAL**, there being no stored value to
/// clear, so the read never sees one: `{"crop": null}` is "stop animating
/// the crop", where the same spelling in a `set_video` patch is a required
/// field being cleared and is refused. The WALK does see it, which is what
/// keeps `{"blurr": null}` an unknown key rather than a key quietly
/// dropped.
pub(crate) fn check_group_patch(
    body: &Value,
    group: Group,
    subject: &str,
    prefix: &str,
) -> Result<(), String> {
    let template = group.template();
    check_keys(body, &template, subject, prefix, 0)?;
    let merged = actions::merge(&template, &without_nulls(body, 0));
    match group {
        Group::Video => read_merged::<VideoProps>(merged, subject, prefix).map(|_| ()),
        Group::Audio => read_merged::<AudioProps>(merged, subject, prefix).map(|_| ()),
        Group::Text => read_merged::<TextProps>(merged, subject, prefix).map(|_| ()),
        Group::Shape => read_merged::<ShapeProps>(merged, subject, prefix).map(|_| ()),
    }
}

/// A copy of `patch` with every `null`-valued key dropped, at every depth —
/// [`check_group_patch`]'s removal rule, and the shape `edit_action.rs`'s
/// `prune_removed` applies to the STORED end state. Only object keys go: a
/// `null` inside a list is not a removal, and the read refuses it by index.
fn without_nulls(patch: &Value, depth: u32) -> Value {
    let Value::Object(fields) = patch else {
        return patch.clone();
    };
    if depth >= MAX_PATCH_DEPTH {
        return patch.clone();
    }
    Value::Object(
        fields
            .iter()
            .filter(|(_, value)| !value.is_null())
            .map(|(key, value)| (key.clone(), without_nulls(value, depth + 1)))
            .collect(),
    )
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
/// kind; the read ([`read_merged`]) is where what only the TYPE knows is
/// caught — a misspelt variant, a `null` a required field cannot take, a
/// colour of the wrong length. The path it names is into the MERGED group,
/// which is the patch's path too: the merge keeps every key where the patch
/// put it and an array replaces whole, and the base was written by this
/// crate and reads back cleanly, so the only values that can fail are the
/// patch's.
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
    check_keys(patch, &group.template(), group.subject(), "", 0)?;
    let merged = actions::merge(&actions::to_json(base), patch);
    read_merged(merged, group.subject(), "")
}
