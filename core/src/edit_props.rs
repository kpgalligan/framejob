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
//!    currently `null`.
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
//! only once its group has passed.

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::actions::{self, MAX_PATCH_DEPTH};
use crate::export::describe;
use crate::model::{
    AudioProps, Chroma, Clip, Compressor, Filter, Project, Reflection, Shadow, ShapeProps, Source,
    Spotlight, TextProps, VideoProps,
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

    /// A fully-populated instance of the group, serialized: every optional
    /// sub-object present, so the key check can see inside `shadow`,
    /// `chroma`, `reflection`, `spotlight`, `duck`, `compressor`,
    /// `outline`, `backdrop` and `stroke` even when the clip currently has
    /// `null` there — and one `filters` entry, so it can see inside the
    /// array's elements too.
    fn template(self) -> Value {
        match self {
            Group::Video => actions::to_json(&VideoProps {
                shadow: Some(Shadow::default()),
                chroma: Some(Chroma::default()),
                filters: vec![Filter::default()],
                reflection: Some(Reflection::default()),
                spotlight: Some(Spotlight::default()),
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
                ..TextProps::default()
            }),
            Group::Shape => actions::to_json(&ShapeProps {
                stroke: Some(crate::model::Stroke::default()),
                fill: Some([0.0, 0.0, 0.0, 1.0]),
                ..ShapeProps::default()
            }),
        }
    }
}

/// Rejects any key in `patch` the group's schema does not have, naming the
/// dotted path. Recursion is bounded by the same depth action patches use;
/// past it the check stops rather than descending an arbitrary tree, and
/// serde drops whatever it finds there.
fn check_keys(
    patch: &Value,
    template: &Value,
    group: Group,
    path: &str,
    depth: u32,
) -> Result<(), String> {
    // An array of objects — `video.filters` — is the one place the schema
    // puts keys inside an array, and every element has the SAME shape, so
    // the template's first entry describes all of them. Without this a
    // misspelled `{"filters": [{"amont": 1}]}` would be dropped in silence
    // by serde, which is exactly the failure this check exists to prevent.
    // Arrays of numbers (a colour, `from`/`to`) fall through it harmlessly:
    // a number against a number has no keys to check.
    if let (Value::Array(given), Value::Array(known)) = (patch, template) {
        if depth < MAX_PATCH_DEPTH {
            if let Some(reference) = known.first() {
                for value in given {
                    check_keys(value, reference, group, path, depth + 1)?;
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
        let Some(reference) = known.get(key) else {
            return Err(format!(
                "unknown key \"{path}{key}\" in a {} patch",
                group.name()
            ));
        };
        check_keys(value, reference, group, &format!("{path}{key}."), depth + 1)?;
    }
    Ok(())
}

/// Checks the patch's shape and merges it into `base` (already serialized).
/// The merge itself is `actions::merge` — the one deep merge in the crate.
pub(crate) fn merge_group(base: &Value, patch: &Value, group: Group) -> Result<Value, String> {
    if !patch.is_object() {
        return Err(format!(
            "{} patch must be a json object, not {}",
            group.name(),
            describe(patch)
        ));
    }
    check_keys(patch, &group.template(), group, "", 0)?;
    Ok(actions::merge(base, patch))
}

// ---- the ops -------------------------------------------------------------

impl Project {
    /// The source's pixel size, when the model knows it. `None` for text
    /// (only the platform can measure a layout, spec §5.3) and for a media
    /// whose descriptor carries no size.
    ///
    /// A NEST's size is its own canvas — the size it was frozen at, not the
    /// project's current one — which is what a crop on a nest clip is
    /// measured against and what the flattened layers are clipped to
    /// (`nest.rs`).
    fn source_size(&self, clip: &Clip) -> Option<(f64, f64)> {
        match &clip.source {
            Source::Media { media, .. } | Source::Still { media, .. } | Source::Image { media } => {
                let found = self.media(*media)?;
                if found.width == 0 || found.height == 0 {
                    None
                } else {
                    Some((f64::from(found.width), f64::from(found.height)))
                }
            }
            Source::Shape => clip.shape.as_ref().map(|s| (s.width, s.height)),
            Source::Nest { project } => {
                let found = self.nest(*project)?;
                if found.width == 0 || found.height == 0 {
                    None
                } else {
                    Some((f64::from(found.width), f64::from(found.height)))
                }
            }
            Source::Text => None,
        }
    }

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
                Some(video) => check_video(video, self.source_size(clip)),
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
                    let merged = merge_group(&actions::to_json(&base), patch, group)?;
                    let props: VideoProps = serde_json::from_value(merged)
                        .map_err(|e| format!("video patch does not match the schema: {e}"))?;
                    check_video(&props, self.source_size(&clip))?;
                    if let Some(slot) = next.clip_mut(id) {
                        slot.video = Some(props);
                    }
                }
                Group::Audio => {
                    let base = clip
                        .audio
                        .ok_or_else(|| format!("clip {id} has no audio properties"))?;
                    let merged = merge_group(&actions::to_json(&base), patch, group)?;
                    let props: AudioProps = serde_json::from_value(merged)
                        .map_err(|e| format!("audio patch does not match the schema: {e}"))?;
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
                    let merged = merge_group(&actions::to_json(&base), patch, group)?;
                    let props: TextProps = serde_json::from_value(merged)
                        .map_err(|e| format!("text patch does not match the schema: {e}"))?;
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
                    let merged = merge_group(&actions::to_json(&base), patch, group)?;
                    let props: ShapeProps = serde_json::from_value(merged)
                        .map_err(|e| format!("shape patch does not match the schema: {e}"))?;
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
