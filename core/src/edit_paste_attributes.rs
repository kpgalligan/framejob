//! `paste_attributes` — Edit ▸ Paste Attributes and Edit ▸ Paste Graphic
//! Properties (spec §6, table "Clips"; spec §11 G-32).
//!
//! Its own module because it is the clipboard's OTHER use: `paste` makes a
//! payload fit and places it, and this copies properties onto clips that
//! are already there and places nothing. The two share one thing, the
//! payload, whose shape stays `edit_paste.rs`'s to know and is read through
//! its [`parse_payload`]. Cut out of `edit_paste.rs` under the size rule
//! (core/CLAUDE.md), as a pure move, ahead of G-32.
//!
//! `paste_attributes` copies the EARLIEST payload clip's property groups
//! onto clips already on the timeline. It is not in `edit_props.rs` because
//! the material comes from the clipboard, not from a caller's patch. A
//! group is REPLACED whole, never merged — "make this look like that" is
//! the gesture, and a merge would leave the target's shadow under a source
//! that had none. What a target keeps is what makes it the clip it is
//! rather than how it looks: a text clip's `content` and the `words` that
//! time it (spec §11 W-6 — a timing belongs to its words); a shape's
//! `kind`, `width`, `height`, `from` and `to`. Video and audio travel whole,
//! transform included — `audio.muted` and `keep_pitch` are properties like
//! opacity, and `keep_pitch` only acts when the speed is not 1, which does
//! not travel: `speed`, `enabled`, the actions, the transition, the name,
//! the label and the source are not properties at all.
//!
//! **The qualifier follows the clip kind** (spec §11 GR-13): only an
//! adjustment clip takes one, so a picture target gets none (dropped, which
//! `paste_attributes`' description says — D2-1: a paste's answer is not
//! the place for it), and an adjustment target keeps its own when the
//! payload clip is a picture clip, which has none to give. Between two
//! adjustment clips it is copied like any other video key.
//!
//! ### The fifth group
//!
//! `graphic` (G-32) copies a graphic clip's `props`, whole, onto clips
//! drawn by the SAME module, and the target keeps its `name`, `width`,
//! `height`, `in` and `length`. It is a group a caller NAMES and never one
//! of the default set: props hold a graphic's words as well as its look,
//! and ⌥⌘V has no picker. That is why the names are [`PasteGroup`] and not
//! `patch::Group`: a patch has no `graphic` group (G-10), and `Group` is
//! matched exhaustively wherever a patch is read.
//!
//! The copied map is checked for SHAPE only — `model_graphic.rs`'s
//! `check_props` with no schema, then `check_count` — and only when a
//! target takes it, the first time one does: a paste in which no target
//! takes `graphic` never reads the map, as the four groups are checked
//! only after they have landed on a target. The write is `insert` and
//! `shift_remove`, `model_graphic.rs`'s rule, so a key both sides have
//! keeps its slot. A target key the payload lacks that an action on the
//! target names (`actions_graphic.rs`'s `names_prop`) is KEPT in its slot,
//! so the action's ramp keeps its start (spec §11 G-34 (d), amending
//! G-32 (e)).

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::actions_graphic::names_prop;
use crate::edit_adjustment::is_adjustment;
use crate::edit_paste::{absorb_media, parse_payload};
use crate::lut::{look_media_ids, remap_look_media};
use crate::model::{Clip, GraphicProps, Project, Qualifier, ShapeProps, Source, TextProps};
use crate::model_graphic::{check_count, check_props};
use crate::outcome::Outcome;
use crate::patch::{Group, GROUPS};

/// The five groups `paste_attributes` takes by name — `video | audio | text
/// | shape | graphic` on the wire. The first four are the PATCH groups
/// ([`Group`]); `graphic` is the paste's alone (module doc).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PasteGroup {
    Video,
    Audio,
    Text,
    Shape,
    Graphic,
}

impl PasteGroup {
    /// The wire name, which is the patch group's own for the first four.
    pub(crate) fn name(self) -> &'static str {
        match self.layer() {
            Some(layer) => layer.name(),
            None => "graphic",
        }
    }

    /// The patch group this names, or `None` for `graphic`, which is not a
    /// group of the layer.
    fn layer(self) -> Option<Group> {
        match self {
            PasteGroup::Video => Some(Group::Video),
            PasteGroup::Audio => Some(Group::Audio),
            PasteGroup::Text => Some(Group::Text),
            PasteGroup::Shape => Some(Group::Shape),
            PasteGroup::Graphic => None,
        }
    }

    /// The same group as a name a caller could have sent.
    fn of(layer: Group) -> PasteGroup {
        match layer {
            Group::Video => PasteGroup::Video,
            Group::Audio => PasteGroup::Audio,
            Group::Text => PasteGroup::Text,
            Group::Shape => PasteGroup::Shape,
        }
    }
}

/// Whether a clip HAS the group — the model's only notion of what a clip
/// can take, the same one `edit_props.rs`'s patches go by.
fn has_group(clip: &Clip, group: Group) -> bool {
    match group {
        Group::Video => clip.video.is_some(),
        Group::Audio => clip.audio.is_some(),
        Group::Text => clip.text.is_some(),
        Group::Shape => clip.shape.is_some(),
    }
}

/// What a graphic clip is drawn from, or `None` for a clip that is not one
/// — `set_graphic`'s test: the source AND the description.
fn graphic_of(clip: &Clip) -> Option<&GraphicProps> {
    match clip.source {
        Source::Graphic => clip.graphic.as_ref(),
        _ => None,
    }
}

/// Whether a clip has a group a caller can name.
fn has(clip: &Clip, group: PasteGroup) -> bool {
    match group.layer() {
        Some(layer) => has_group(clip, layer),
        None => graphic_of(clip).is_some(),
    }
}

/// The copied props as they may be stored: shape-checked with no schema,
/// `null`s dropped, counted (G-32 (f)). The sentences are
/// `model_graphic.rs`'s own.
fn checked_props(from: &GraphicProps) -> Result<Map<String, Value>, String> {
    let mut stored = check_props(&from.props, None)?;
    stored.retain(|_, value| !value.is_null());
    check_count(&stored)?;
    Ok(stored)
}

/// Makes `into` hold exactly `props` plus the keys in `keep`: a key that
/// neither `props` nor `keep` holds is removed with `shift_remove`, a key
/// both maps have keeps its slot, a kept key keeps its slot and value, and
/// a new key is appended in `props`' order.
fn replace_props(into: &mut Map<String, Value>, props: &Map<String, Value>, keep: &[String]) {
    let gone: Vec<String> = into
        .keys()
        .filter(|key| !props.contains_key(*key) && !keep.contains(*key))
        .cloned()
        .collect();
    for key in gone {
        into.shift_remove(&key);
    }
    for (key, value) in props {
        into.insert(key.clone(), value.clone());
    }
}

/// Replaces `target`'s group with a copy of `source`'s, keeping the fields
/// that make the target the clip it is (module doc). A side that lacks the
/// group leaves the target as it was — the caller has already refused that
/// case by name, so this is only the shape that cannot invent a group.
fn copy_group(target: &mut Clip, source: &Clip, group: Group) {
    match group {
        Group::Video => {
            let picture_target = !is_adjustment(target);
            let picture_source = !is_adjustment(source);
            if let (Some(into), Some(from)) = (target.video.as_mut(), &source.video) {
                let own = into.qualifier;
                *into = from.clone();
                // The qualifier follows the clip kind (module doc, GR-13).
                if picture_target {
                    into.qualifier = Qualifier::default();
                } else if picture_source {
                    into.qualifier = own;
                }
            }
        }
        Group::Audio => {
            if let (Some(into), Some(from)) = (target.audio.as_mut(), &source.audio) {
                *into = *from;
            }
        }
        Group::Text => {
            if let (Some(into), Some(from)) = (target.text.as_mut(), &source.text) {
                let content = std::mem::take(&mut into.content);
                let words = std::mem::take(&mut into.words);
                *into = TextProps {
                    content,
                    words,
                    ..from.clone()
                };
            }
        }
        Group::Shape => {
            if let (Some(into), Some(from)) = (target.shape.as_mut(), &source.shape) {
                *into = ShapeProps {
                    kind: into.kind,
                    width: into.width,
                    height: into.height,
                    from: into.from,
                    to: into.to,
                    ..from.clone()
                };
            }
        }
    }
}

impl Project {
    /// Copies one payload clip's property groups onto every named clip (spec
    /// §6) — Edit ▸ Paste Attributes. The clip is the EARLIEST, then the
    /// front-most (`track` is a depth, 0 = front), then the lower id: Copy
    /// writes a selection in storage — creation — order, not the timeline's,
    /// so the array's first is a clip the user cannot see. Which fields
    /// travel, which a target keeps and why a group is replaced rather than
    /// merged are the module doc's.
    ///
    /// `groups` absent means every one of the four LAYER groups both sides
    /// have, silently skipping the rest: video onto a text clip from a media
    /// clip copies the video, leaves the text alone and drops the audio,
    /// which has nowhere to go. `graphic` is never in that set, and
    /// `skip_missing` changes nothing there. A NAMED group is different —
    /// one the source lacks is an `Err` naming the group, one a target lacks
    /// is `Err("clip N has no audio properties")`, the patches' answer, and
    /// `graphic` onto a clip drawn by another module is an `Err` naming both
    /// modules — because a caller who asked for it would otherwise never
    /// learn it did not happen. With `skip_missing` a caller says it does
    /// not need to: a named group the source lacks is dropped and a target
    /// that cannot take one is skipped for it (G-32). An empty explicit
    /// list, an identity paste and an empty selection are all identities.
    /// The copied layer groups then pass the range checks a patch does, so a
    /// payload written by hand cannot smuggle in a value the inspector would
    /// refuse; copied graphic props pass the shape check, the first time a
    /// target takes them.
    pub fn paste_attributes(
        &self,
        clips: &[u32],
        payload: &Value,
        groups: Option<&[PasteGroup]>,
        skip_missing: bool,
    ) -> Result<Outcome, String> {
        let payload = parse_payload(payload)?;
        let earliest = |c: &&Clip| (c.start, c.track, c.id);
        let Some(source) = payload.clips.iter().min_by_key(earliest) else {
            return Err("paste payload has no clips".to_string());
        };
        let mut named: Option<Vec<PasteGroup>> = None;
        if let Some(asked) = groups {
            let mut kept = Vec::new();
            for group in asked {
                if has(source, *group) {
                    kept.push(*group);
                } else if !skip_missing {
                    return Err(format!("payload clip has no {} properties", group.name()));
                }
            }
            named = Some(kept);
        }
        let ids: Vec<u32> = self.selected_clips(clips)?.iter().map(|c| c.id).collect();

        let mut next = self.clone();
        // Read at most once, by the first target that takes it (G-32 (f)).
        let mut copied: Option<Map<String, Value>> = None;
        // The source with its looks pointing at THIS project's LUTs, made by
        // the first target that takes the video group (spec §11 GR-8): the
        // LUTs it names are absorbed by path, as `paste` absorbs media, and
        // an id the payload lacks becomes no look.
        let mut looked: Option<Clip> = None;
        for id in ids {
            let Some(mut target) = next.clip(id).cloned() else {
                continue;
            };
            let chosen: Vec<PasteGroup> = match &named {
                Some(named) => named.clone(),
                None => GROUPS
                    .into_iter()
                    .filter(|g| has_group(source, *g) && has_group(&target, *g))
                    .map(PasteGroup::of)
                    .collect(),
            };
            let takes_video = chosen.contains(&PasteGroup::Video) && target.video.is_some();
            if takes_video && looked.is_none() {
                let map = absorb_media(&mut next, &payload, &[], &look_media_ids(source))?;
                let mut copy = source.clone();
                remap_look_media(&mut copy, &map);
                looked = Some(copy);
            }
            let from = looked.as_ref().unwrap_or(source);
            for group in chosen {
                if !has(&target, group) {
                    if skip_missing {
                        continue;
                    }
                    return Err(format!("clip {id} has no {} properties", group.name()));
                }
                let Some(layer) = group.layer() else {
                    let keep: Vec<String> = target.graphic.as_ref().map_or_else(Vec::new, |g| {
                        let named = g.props.keys().filter(|key| names_prop(&target, key));
                        named.cloned().collect()
                    });
                    let (Some(from), Some(into)) = (graphic_of(from), target.graphic.as_mut())
                    else {
                        continue;
                    };
                    if into.name != from.name {
                        if skip_missing {
                            continue;
                        }
                        return Err(format!(
                            "clip {id} is drawn by \"{}\" and the payload clip by \"{}\"; \
                             graphic props are pasted only between clips of one module",
                            into.name, from.name
                        ));
                    }
                    if copied.is_none() {
                        copied = Some(checked_props(from)?);
                    }
                    if let Some(props) = &copied {
                        replace_props(&mut into.props, props, &keep);
                    }
                    continue;
                };
                copy_group(&mut target, from, layer);
                next.normalise_and_check_group(&mut target, layer)?;
            }
            if let Some(slot) = next.clip_mut(id) {
                *slot = target;
            }
        }
        self.finish(next)
    }
}
