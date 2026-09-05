//! The four property patches — `set_video`, `set_audio`, `set_text`,
//! `set_shape` (spec §6, the "Clips" table) — and the range checks that
//! police everything written into a clip's property groups.
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
//! The bounds themselves are the inspector's (spec §4.3), so a value this
//! module accepts is a value a control can show.

use serde_json::Value;

use crate::actions::{self, MAX_PATCH_DEPTH};
use crate::audio::MAX_GAIN;
use crate::export::describe;
use crate::model::{
    AudioProps, Chroma, Clip, Color, Project, Shadow, ShapeProps, Source, TextProps, VideoProps,
};
use crate::time::Ticks;

/// Scale range, matching the inspector's 1–1000 % (spec §4.3). The lower
/// bound is not 0: a zero scale is an invisible layer that looks like a
/// broken render, and `opacity` is the way to hide something.
pub(crate) const SCALE_MIN: f64 = 0.01;
pub(crate) const SCALE_MAX: f64 = 10.0;

// ---- property groups -----------------------------------------------------

/// The four property groups a patch can address. Carries the group's name
/// for error messages and its template for the unknown-key check.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Group {
    Video,
    Audio,
    Text,
    Shape,
}

impl Group {
    fn name(self) -> &'static str {
        match self {
            Group::Video => "video",
            Group::Audio => "audio",
            Group::Text => "text",
            Group::Shape => "shape",
        }
    }

    /// A fully-populated instance of the group, serialized: every optional
    /// sub-object present, so the key check can see inside `shadow`,
    /// `chroma`, `duck`, `outline`, `backdrop` and `stroke` even when the
    /// clip currently has `null` there.
    fn template(self) -> Value {
        match self {
            Group::Video => actions::to_json(&VideoProps {
                shadow: Some(Shadow::default()),
                chroma: Some(Chroma::default()),
                ..VideoProps::default()
            }),
            Group::Audio => actions::to_json(&AudioProps {
                duck: Some(crate::model::Duck::default()),
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
    let (Value::Object(given), Value::Object(known)) = (patch, template) else {
        // A leaf, a `null` (clearing an optional group), or an array: no
        // keys to check.
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

// ---- range checks --------------------------------------------------------

fn finite(key: &str, value: f64) -> Result<(), String> {
    if value.is_finite() {
        Ok(())
    } else {
        Err(format!("{key} must be a finite number, not {value}"))
    }
}

fn in_range(key: &str, value: f64, low: f64, high: f64) -> Result<(), String> {
    if value.is_finite() && value >= low && value <= high {
        Ok(())
    } else {
        Err(format!(
            "{key} must be between {low} and {high}, not {value}"
        ))
    }
}

fn at_least(key: &str, value: f64, low: f64) -> Result<(), String> {
    if value.is_finite() && value >= low {
        Ok(())
    } else {
        Err(format!("{key} must be at least {low}, not {value}"))
    }
}

fn above(key: &str, value: f64, low: f64) -> Result<(), String> {
    if value.is_finite() && value > low {
        Ok(())
    } else {
        Err(format!("{key} must be greater than {low}, not {value}"))
    }
}

/// Colors are `[r, g, b, a]` floats 0–1 (spec §5.2); a channel outside that
/// is a unit mistake (0–255) the renderer would turn into a blown-out
/// layer, so it is named rather than clamped.
pub(crate) fn color_ok(key: &str, color: &Color) -> Result<(), String> {
    for channel in color {
        in_range(key, *channel, 0.0, 1.0)?;
    }
    Ok(())
}

fn ticks_positive_or_zero(key: &str, value: Ticks) -> Result<(), String> {
    if value >= 0 {
        Ok(())
    } else {
        Err(format!("{key} must not be negative, not {value}"))
    }
}

/// The video group. `size` is the source's pixel size when it is known, so
/// a crop can be checked against the thing being cropped.
fn check_video(props: &VideoProps, size: Option<(f64, f64)>) -> Result<(), String> {
    finite("video.x", props.x)?;
    finite("video.y", props.y)?;
    in_range("video.scale", props.scale, SCALE_MIN, SCALE_MAX)?;
    finite("video.rotation", props.rotation)?;
    in_range("video.opacity", props.opacity, 0.0, 1.0)?;
    at_least("video.corner_radius", props.corner_radius, 0.0)?;
    at_least("video.crop.l", props.crop.l, 0.0)?;
    at_least("video.crop.t", props.crop.t, 0.0)?;
    at_least("video.crop.r", props.crop.r, 0.0)?;
    at_least("video.crop.b", props.crop.b, 0.0)?;
    // Opposite edges must leave something behind: a crop that meets or
    // crosses is an empty rectangle, which no renderer can draw.
    if let Some((width, height)) = size {
        let horizontal = props.crop.l + props.crop.r;
        if horizontal >= width {
            return Err(format!(
                "video.crop l + r must be less than the source width {width}, not {horizontal}"
            ));
        }
        let vertical = props.crop.t + props.crop.b;
        if vertical >= height {
            return Err(format!(
                "video.crop t + b must be less than the source height {height}, not {vertical}"
            ));
        }
    }
    if let Some(shadow) = &props.shadow {
        color_ok("video.shadow.color", &shadow.color)?;
        in_range("video.shadow.opacity", shadow.opacity, 0.0, 1.0)?;
        at_least("video.shadow.blur", shadow.blur, 0.0)?;
        finite("video.shadow.angle", shadow.angle)?;
        at_least("video.shadow.distance", shadow.distance, 0.0)?;
    }
    // The color controls are offsets from neutral, not absolute levels, so
    // any finite value is meaningful; the UI's sliders bound them.
    finite("video.color.brightness", props.color.brightness)?;
    finite("video.color.contrast", props.color.contrast)?;
    finite("video.color.saturation", props.color.saturation)?;
    finite("video.color.hue", props.color.hue)?;
    if let Some(chroma) = &props.chroma {
        for channel in &chroma.key {
            in_range("video.chroma.key", *channel, 0.0, 1.0)?;
        }
        in_range("video.chroma.tolerance", chroma.tolerance, 0.0, 1.0)?;
        in_range("video.chroma.softness", chroma.softness, 0.0, 1.0)?;
        in_range("video.chroma.spill", chroma.spill, 0.0, 1.0)?;
    }
    Ok(())
}

fn check_audio(props: &AudioProps) -> Result<(), String> {
    in_range("audio.volume", props.volume, 0.0, MAX_GAIN)?;
    ticks_positive_or_zero("audio.fade_in", props.fade_in)?;
    ticks_positive_or_zero("audio.fade_out", props.fade_out)?;
    if let Some(duck) = &props.duck {
        in_range("audio.duck.level", duck.level, 0.0, 1.0)?;
        ticks_positive_or_zero("audio.duck.attack", duck.attack)?;
        ticks_positive_or_zero("audio.duck.release", duck.release)?;
    }
    Ok(())
}

pub(crate) fn check_text(props: &TextProps) -> Result<(), String> {
    above("text.size", props.size, 0.0)?;
    color_ok("text.color", &props.color)?;
    above("text.line_spacing", props.line_spacing, 0.0)?;
    finite("text.tracking", props.tracking)?;
    if let Some(outline) = &props.outline {
        at_least("text.outline.width", outline.width, 0.0)?;
        color_ok("text.outline.color", &outline.color)?;
    }
    if let Some(backdrop) = &props.backdrop {
        color_ok("text.backdrop.color", &backdrop.color)?;
        at_least("text.backdrop.padding", backdrop.padding, 0.0)?;
        at_least("text.backdrop.radius", backdrop.radius, 0.0)?;
    }
    if let Some(width) = props.width {
        above("text.width", width, 0.0)?;
    }
    Ok(())
}

pub(crate) fn check_shape(props: &ShapeProps) -> Result<(), String> {
    above("shape.width", props.width, 0.0)?;
    above("shape.height", props.height, 0.0)?;
    at_least("shape.radius", props.radius, 0.0)?;
    if let Some(stroke) = &props.stroke {
        at_least("shape.stroke.width", stroke.width, 0.0)?;
        color_ok("shape.stroke.color", &stroke.color)?;
    }
    if let Some(fill) = &props.fill {
        color_ok("shape.fill", fill)?;
    }
    for point in [&props.from, &props.to] {
        for coordinate in point {
            finite("shape.from/to", *coordinate)?;
        }
    }
    Ok(())
}

// ---- the ops -------------------------------------------------------------

impl Project {
    /// The source's pixel size, when the model knows it. `None` for text
    /// (only the platform can measure a layout, spec §5.3), for a nested
    /// project, and for a media whose descriptor carries no size.
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
            Source::Text | Source::Nest { .. } => None,
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
