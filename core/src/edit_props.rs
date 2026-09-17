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
//! 1. **A patch is a subset of one group**, read by `patch.rs`'s
//!    [`merge_group`] — the walk of keys and JSON kinds against the group's
//!    template, the deep merge and the typed read back, so a field is
//!    patchable the moment `model.rs` declares it and there is no second
//!    list of patchable keys to forget to update. That module was cut out
//!    of this one under the size rule, and it holds every sentence about
//!    what a patch may CARRY; nothing here restates them.
//! 2. **A mistake is named, never dropped.** A typed Swift builder and an
//!    MCP call both reach these ops, and a key silently dropped here is a
//!    bug the user would never see.
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

use serde_json::Value;

use crate::export::describe;
use crate::model::{BlendMode, Clip, Project, Source, TextProps, VideoProps};
use crate::patch::{merge_group, Group};
use crate::props_check::{check_audio, check_shape, check_text, check_video};

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
/// It is not the whole story either: `set_action_end` checks the VOCABULARY
/// and never the clip, and a blend mode is a legal value, so an end patch
/// can still carry one onto a nest clip. `actions.rs`'s `clamp_video` is
/// what closes that door, for the recipe, `clip_state` and both export
/// writers at once.
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

    /// Puts a motion preset's two edge durations and its `during` period on
    /// the document's frame grid — the core's Times rule (core/CLAUDE.md:
    /// every tick value that reaches the model is snapped first) applied at
    /// the patch door, where before D1·2 a comment in `props_check.rs` said
    /// "the inspector snaps" and left an agent's value sub-frame.
    ///
    /// It runs AFTER the range check, so a refusal names the number the
    /// caller actually sent: a `duration` of −1 is a sign mistake and is
    /// refused, where snapping first would have turned it into a legal 0 and
    /// said nothing. Snapping cannot undo that check — a non-negative
    /// duration snaps to a non-negative one — with one exception, and
    /// `period` carries its own floor for it: it divides in every `during`
    /// formula, so a period under half a frame would snap to 0 and stop the
    /// motion the caller asked for. On the grid the smallest period there
    /// is is one frame, so that is where it lands.
    fn snap_motion(&self, props: &mut VideoProps) {
        let Some(motion) = props.motion.as_mut() else {
            return;
        };
        for edge in [motion.r#in.as_mut(), motion.out.as_mut()]
            .into_iter()
            .flatten()
        {
            edge.duration = self.snapped(edge.duration);
        }
        if let Some(during) = motion.during.as_mut() {
            during.period = self.snapped(during.period).max(self.frame());
        }
    }

    /// The same for a text animation's two timings ([`Self::snap_motion`]
    /// argues the order and the rounding). Both are DURATIONS, so 0 is
    /// legal and a reveal shorter than half a frame lands there: it is a
    /// reveal no frame could show.
    fn snap_animation(&self, props: &mut TextProps) {
        let Some(animation) = props.animation.as_mut() else {
            return;
        };
        animation.r#in = self.snapped(animation.r#in);
        animation.out = self.snapped(animation.out);
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
                    self.snap_motion(&mut props);
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
                    let mut props = merge_group(&base, patch, group)?;
                    check_text(&props)?;
                    self.snap_animation(&mut props);
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
