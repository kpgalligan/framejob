//! The property patches — `set_video`, `set_audio`, `set_text`, `set_shape`
//! and, for the clip's own name and label, `set_clip` (spec §6, the "Clips"
//! table). The range checks that police everything written into a clip's
//! property groups are `props_check.rs`'s, cut out of here in phase 2;
//! this file runs them after every merge and restates none of them.
//!
//! This is the schema half of editing, split off from `edit_clip.rs`'s
//! placement half: nothing here moves a clip in time or on a track, and
//! nothing here decides what a clip IS. It answers one question — is this
//! patch a legal description of this group, and what does the group look
//! like once it is merged in?
//!
//! Three things run through all of it:
//!
//! 1. **A patch is a subset of one group**, merged with `actions::merge` —
//!    the same deep merge action evaluation uses, so a field is patchable
//!    the moment `model.rs` declares it and there is no second list of
//!    patchable keys to forget to update.
//! 2. **An unknown key is an `Err`**, unlike an action's `end` patch. A
//!    typed Swift builder and an MCP call both reach these ops, and a key
//!    silently dropped here is a bug the user would never see. The check
//!    runs against a fully-populated template of the group, so
//!    `{"shadow": {"blurr": 8}}` is caught even when the clip's shadow is
//!    currently `null`. A value of the wrong JSON kind and a misspelt
//!    variant are `Err`s too, and every one of the three names the dotted
//!    path to the mistake, array indices included (`filters[1].kind`), and
//!    the value sent — `merge_group` is where.
//! 3. **Values are named, never clamped.** A channel outside 0–1 is a units
//!    mistake (0–255) and a scale of 50 is a typo; silently clamping them
//!    would leave the user looking at a number the inspector did not
//!    accept. The one deliberate exception is `set_speed`, which lives in
//!    `edit_clip.rs` and clamps because a slider asking for ×20 wants the
//!    fastest thing available.
//!
//! The bounds themselves, and the four checks against them, are
//! `props_check.rs`'s (the inspector's numbers, spec §4.3): a value that
//! passes there is a value a control can show, and a merge here is stored
//! only once its group has passed. Exactly one check stays behind —
//! [`check_blend`], which refuses a blend mode on a nest clip — because it
//! is a fact about the CLIP and not about the vocabulary, and nothing in
//! `props_check.rs` is handed a clip to ask.

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::actions::{self, MAX_PATCH_DEPTH};
use crate::export::describe;
use crate::model::{
    AudioProps, BlendMode, Chroma, Clip, Compressor, Filter, Motion, ObscureRegion, Project,
    Reflection, Shadow, ShapeProps, Source, Spotlight, TextProps, VideoProps,
};
use crate::props_check::{check_audio, check_shape, check_text, check_video};

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

/// The one check a video group cannot make on its own: a NEST clip may not
/// carry a blend mode (format version 6).
///
/// A nest is FLATTENED rather than composited offscreen (`nest.rs`), so
/// there is no such thing as "the nest's picture" for a blend to combine
/// with what is under it — each clip inside contributes its own layer, and a
/// blend on the nest clip could only mean "blend every one of them
/// separately against whatever happens to be below". That is a different
/// picture from the one the popup promises, and a wrong picture is worse
/// than a refusal.
///
/// **Only a non-normal MERGED value fires**, which is not leniency for its
/// own sake. `paste_attributes` replaces the video group WHOLE, so a check
/// on any MENTION of the key would fail an all-or-nothing paste of an
/// ordinary look — one that never touched blend — onto a nest clip, for a
/// value that changes nothing. `{"blend": "normal"}` on a nest clip is
/// therefore the identity and answers `None` through the usual `finish`.
///
/// It lives HERE rather than in `props_check.rs` because it is not a fact
/// about the vocabulary: the value is perfectly legal and it is the CLIP it
/// was written onto that refuses it, where `props_check.rs` never sees a
/// clip. Both callers — the patch path and `paste_attributes`' `check_group`
/// — run this one function, so the two give the identical message.
///
/// It is not the whole story either: `set_action_end` validates nothing but
/// "is it an object", so an end patch can still carry a blend onto a nest
/// clip. `actions.rs`'s `clamp_video` is what closes that door, for the
/// recipe, `clip_state` and both export writers at once.
fn check_blend(clip: &Clip, props: &VideoProps) -> Result<(), String> {
    if props.blend != BlendMode::Normal && matches!(clip.source, Source::Nest { .. }) {
        return Err(format!(
            "clip {} shows a nest and cannot take a blend mode",
            clip.id
        ));
    }
    Ok(())
}

// ---- the ops -------------------------------------------------------------

impl Project {
    /// Merges `patch` into every named clip's video props (spec §6).
    /// Refuses (`None`) when nothing changes; `Err` for an unknown clip, a
    /// clip with no video props, an unknown key, or a value out of range.
    pub fn set_video(&self, clips: &[u32], patch: &Value) -> Result<Option<Project>, String> {
        self.patch_clips(clips, patch, Group::Video)
    }

    /// Merges `patch` into every named clip's audio props (spec §6).
    pub fn set_audio(&self, clips: &[u32], patch: &Value) -> Result<Option<Project>, String> {
        self.patch_clips(clips, patch, Group::Audio)
    }

    /// Merges `patch` into every named text clip's text props (spec §6).
    pub fn set_text(&self, clips: &[u32], patch: &Value) -> Result<Option<Project>, String> {
        self.patch_clips(clips, patch, Group::Text)
    }

    /// Merges `patch` into every named shape clip's shape props (spec §6).
    pub fn set_shape(&self, clips: &[u32], patch: &Value) -> Result<Option<Project>, String> {
        self.patch_clips(clips, patch, Group::Shape)
    }

    /// Sets or clears every named clip's own name and label (spec §6) — the
    /// fifth patch op, shaped like `set_video` so that "absent keeps, null
    /// clears" lives where it already does in this crate: inside a patch
    /// object, never as an envelope argument, whose absent and null mean the
    /// same thing. The keys are `name` and `label`, each a string or `null`.
    /// A string is stored trimmed, and an EMPTY one — after trimming — clears
    /// too: `set_track`'s rule for a name, except that "unnamed" is `None`
    /// here, so the app's fallback name returns. `Err` for an unknown clip,
    /// an unknown key, or a value that is neither a string nor `null`;
    /// `None` when nothing changes.
    pub fn set_clip(&self, clips: &[u32], patch: &Value) -> Result<Option<Project>, String> {
        let Some(fields) = patch.as_object() else {
            return Err(format!(
                "clip patch must be a json object, not {}",
                describe(patch)
            ));
        };
        // The outer `Option` is "was the key given"; the inner is what to
        // store, `None` for a clear.
        let mut name: Option<Option<String>> = None;
        let mut label: Option<Option<String>> = None;
        for (key, value) in fields {
            let slot = match key.as_str() {
                "name" => &mut name,
                "label" => &mut label,
                other => return Err(format!("unknown key \"{other}\" in a clip patch")),
            };
            *slot = Some(match value {
                Value::Null => None,
                Value::String(text) => Some(text.trim())
                    .filter(|t| !t.is_empty())
                    .map(String::from),
                other => {
                    return Err(format!(
                        "\"{key}\" in a clip patch must be a string or null, not {}",
                        describe(other)
                    ))
                }
            });
        }
        let ids: Vec<u32> = self.selected_clips(clips)?.iter().map(|c| c.id).collect();

        let mut next = self.clone();
        for id in ids {
            if let Some(slot) = next.clip_mut(id) {
                if let Some(name) = &name {
                    slot.name = name.clone();
                }
                if let Some(label) = &label {
                    slot.label = label.clone();
                }
            }
        }
        self.finish(next)
    }

    /// The range check for ONE of a clip's groups — what `paste_attributes`
    /// runs on each group it has just replaced, and only on those, so a
    /// payload written by hand meets the bounds a patch does and a group the
    /// op did not touch is not its business. A group the clip lacks has
    /// nothing to check.
    pub(crate) fn check_group(&self, clip: &Clip, group: Group) -> Result<(), String> {
        match group {
            Group::Video => match &clip.video {
                // The vocabulary's ranges, then the one rule that is about
                // this CLIP rather than about the values — so a payload
                // pasted onto a nest clip is refused with the same sentence
                // `set_video` would have used.
                Some(video) => {
                    check_video(video, self.source_size(clip))?;
                    check_blend(clip, video)
                }
                None => Ok(()),
            },
            Group::Audio => clip.audio.as_ref().map_or(Ok(()), check_audio),
            Group::Text => clip.text.as_ref().map_or(Ok(()), check_text),
            Group::Shape => clip.shape.as_ref().map_or(Ok(()), check_shape),
        }
    }

    /// The one implementation behind the four `set_*` property ops: merge,
    /// check the keys against the group's schema, deserialize, range-check,
    /// store.
    ///
    /// A clip that does not HAVE the group is an error, not a silent skip:
    /// the group's presence is what "this clip has audio" / "this is a text
    /// clip" means, and inventing it would put text props on a video clip.
    fn patch_clips(
        &self,
        clips: &[u32],
        patch: &Value,
        group: Group,
    ) -> Result<Option<Project>, String> {
        if !patch.is_object() {
            return Err(format!(
                "{} patch must be a json object, not {}",
                group.name(),
                describe(patch)
            ));
        }
        let ids: Vec<u32> = self.selected_clips(clips)?.iter().map(|c| c.id).collect();
        if ids.is_empty() {
            return Ok(None);
        }

        let mut next = self.clone();
        for id in ids {
            let clip = match next.clip(id) {
                Some(clip) => clip.clone(),
                None => continue,
            };
            match group {
                Group::Video => {
                    let base = clip
                        .video
                        .clone()
                        .ok_or_else(|| format!("clip {id} has no video properties"))?;
                    let mut props = merge_group(&base, patch, group)?;
                    // One spelling of "no motion" (format version 8): a
                    // patch that clears the last filled slot leaves a
                    // `Motion` with three `None`s behind, which round-trips
                    // as `{"in": null, "out": null, "during": null}` and
                    // would make two equal clips compare unequal. It is
                    // normalised HERE rather than in serde, because the
                    // deep merge is what produces the empty one — a caller
                    // who writes `{"motion": {}}` means the same thing and
                    // gets the same answer.
                    if props.motion.is_some_and(|motion| motion.is_empty()) {
                        props.motion = None;
                    }
                    check_video(&props, self.source_size(&clip))?;
                    check_blend(&clip, &props)?;
                    if let Some(slot) = next.clip_mut(id) {
                        slot.video = Some(props);
                    }
                }
                Group::Audio => {
                    let base = clip
                        .audio
                        .ok_or_else(|| format!("clip {id} has no audio properties"))?;
                    let props = merge_group(&base, patch, group)?;
                    check_audio(&props)?;
                    if let Some(slot) = next.clip_mut(id) {
                        slot.audio = Some(props);
                    }
                }
                Group::Text => {
                    let base = clip
                        .text
                        .clone()
                        .ok_or_else(|| format!("clip {id} has no text properties"))?;
                    let props = merge_group(&base, patch, group)?;
                    check_text(&props)?;
                    if let Some(slot) = next.clip_mut(id) {
                        slot.text = Some(props);
                    }
                }
                Group::Shape => {
                    let base = clip
                        .shape
                        .clone()
                        .ok_or_else(|| format!("clip {id} has no shape properties"))?;
                    let props = merge_group(&base, patch, group)?;
                    check_shape(&props)?;
                    if let Some(slot) = next.clip_mut(id) {
                        slot.shape = Some(props);
                    }
                }
            }
        }
        self.finish(next)
    }
}
