//! `.cube` LUTs as media and as looks (spec §11 GR-8): the rules a `lut`
//! media row and a `video.look {kind: "lut", media}` obey, written once for
//! every door that meets them.
//!
//! - **The row.** A LUT is media so it is referenced, relinked and
//!   consolidated like footage, but it has no picture of its own: its row
//!   carries no video, audio, alpha or duration ([`check_lut_fields`], which
//!   `edit_track.rs`'s `check_media_fields` calls for `add_media` and a
//!   relink's probe), and it is never placed as a clip — `add_clip`,
//!   `insert_clip`, `overwrite_clip` and `add_background` answer
//!   [`lut_not_placeable`].
//! - **The look.** `media` is required with `lut` and goes with nothing
//!   else, and must name a `lut` media of the project
//!   ([`Project::check_look_media`], beside `check_adjustment_video` on the
//!   patch path and on every pasted group, and in `validate` for a file). A
//!   patch naming a built-in kind and no `media` drops a stored one
//!   ([`normalise_look`]), so a built-in kind on a LUT clip replaces the LUT.
//! - **An action's end** is never checked against the media list
//!   (`set_action_end` checks shape only), so an end may name a LUT that is
//!   not there: the evaluator reads such a look as NO look
//!   ([`Project::evaluates_as_look`]), and `actions.rs` switches `media` at
//!   the end like a `kind`, so an id is never interpolated.
//! - **Removing a used LUT** ([`Project::remove_lut`]) refuses naming the
//!   clips whose base look it is, or with `with_clips` clears those looks and
//!   keeps the clips; ends are left alone (inert by the evaluator).
//! - **Paste** brings a LUT's row by path like any media; an id the payload
//!   does not carry becomes no look ([`remap_look_media`]) rather than
//!   another media's id.

use std::collections::HashMap;

use serde::Serialize;
use serde_json::Value;

use crate::model::{Clip, Look, LookKind, Media, MediaKind, Project, VideoProps};
use crate::outcome::Outcome;

/// A vocabulary value's JSON spelling (`warm`, `video`), serde's own, so a
/// sentence names it as the file and the schema do.
fn spelled<T: Serialize>(value: T) -> String {
    serde_json::to_value(value)
        .ok()
        .and_then(|value| value.as_str().map(str::to_string))
        .unwrap_or_default()
}

/// The refusal for `media` on a built-in kind.
fn media_goes_with_lut(kind: LookKind) -> String {
    format!("video.look.media goes with kind lut, not {}", spelled(kind))
}

/// What `add_clip` and the other placing ops answer for a LUT: it is a look,
/// and the sentence says how to apply one.
pub(crate) fn lut_not_placeable(media: u32) -> String {
    format!(
        "media {media} is a LUT: apply it as a look (set_video {{look: {{kind: \"lut\", \
         media: {media}}}}}), it is not placed as a clip"
    )
}

/// A `lut` row's own check: it has no picture or sound, so none of the
/// flags or a duration. Any other kind passes.
pub(crate) fn check_lut_fields(media: &Media) -> Result<(), String> {
    if media.kind == MediaKind::Lut
        && (media.has_video || media.has_audio || media.has_alpha || media.duration != 0)
    {
        return Err("a lut media has no video, audio, alpha or duration".to_string());
    }
    Ok(())
}

/// After a video patch has merged: a patch that names a built-in `kind` and
/// no `media` drops a stored `media` (the built-in replaces the LUT), and a
/// patch that names `media` on a built-in kind is refused.
pub(crate) fn normalise_look(props: &mut VideoProps, patch: &Value) -> Result<(), String> {
    let Some(Value::Object(asked)) = patch.get("look") else {
        return Ok(());
    };
    let Some(look) = props.look.as_mut() else {
        return Ok(());
    };
    if look.kind == LookKind::Lut {
        return Ok(());
    }
    let names_media = asked.get("media").is_some_and(|media| !media.is_null());
    if names_media {
        return Err(media_goes_with_lut(look.kind));
    }
    if asked.get("kind").is_some_and(|kind| !kind.is_null()) {
        look.media = None;
    }
    Ok(())
}

/// The LUT a clip's base look names, if it is a LUT look.
fn base_lut(clip: &Clip) -> Option<u32> {
    let look = clip.video.as_ref()?.look?;
    (look.kind == LookKind::Lut).then_some(look.media).flatten()
}

/// Every media id a clip's looks name: the base look's, then each action
/// end's `video.look.media`, in action order, without repeats. Paste's
/// absorb list, after the source's media.
pub(crate) fn look_media_ids(clip: &Clip) -> Vec<u32> {
    let mut ids: Vec<u32> = Vec::new();
    let base = clip.video.as_ref().and_then(|video| video.look?.media);
    let ends = clip.actions.iter().filter_map(|action| {
        let media = action.end.get("video")?.get("look")?.get("media")?;
        u32::try_from(media.as_u64()?).ok()
    });
    for id in base.into_iter().chain(ends) {
        if !ids.contains(&id) {
            ids.push(id);
        }
    }
    ids
}

/// Points a pasted clip's looks at this project's media ids. An id `map`
/// does not carry never stays (it could name another media here): the base
/// look becomes no look, and an end's look becomes `null`.
pub(crate) fn remap_look_media(clip: &mut Clip, map: &HashMap<u32, u32>) {
    if let Some(video) = clip.video.as_mut() {
        if let Some(id) = video.look.and_then(|look| look.media) {
            match map.get(&id) {
                Some(local) => {
                    if let Some(look) = video.look.as_mut() {
                        look.media = Some(*local);
                    }
                }
                None => video.look = None,
            }
        }
    }
    for action in clip.actions.iter_mut() {
        let Some(Value::Object(video)) = action.end.get_mut("video") else {
            continue;
        };
        let Some(Value::Object(look)) = video.get_mut("look") else {
            continue;
        };
        let Some(id) = look
            .get("media")
            .and_then(Value::as_u64)
            .and_then(|id| u32::try_from(id).ok())
        else {
            continue;
        };
        match map.get(&id) {
            Some(local) => {
                look.insert("media".to_string(), Value::from(*local));
            }
            None => {
                video.insert("look".to_string(), Value::Null);
            }
        }
    }
}

impl Project {
    /// A look's `media` against this project: required with `lut` and naming
    /// a `lut` media of it, and absent with a built-in kind.
    pub(crate) fn check_look_media(&self, props: &VideoProps) -> Result<(), String> {
        let Some(look) = props.look else {
            return Ok(());
        };
        match (look.kind, look.media) {
            (LookKind::Lut, None) => Err("video.look.media is required with kind lut".to_string()),
            (LookKind::Lut, Some(id)) => match self.media(id) {
                None => Err(format!(
                    "video.look.media {id} is not a media of this project"
                )),
                Some(found) if found.kind != MediaKind::Lut => {
                    let kind = spelled(found.kind);
                    let article = if kind.starts_with(['a', 'e', 'i', 'o', 'u']) {
                        "an"
                    } else {
                        "a"
                    };
                    Err(format!(
                        "video.look.media {id} is {article} {kind} media, not a lut"
                    ))
                }
                Some(_) => Ok(()),
            },
            (kind, Some(_)) => Err(media_goes_with_lut(kind)),
            (_, None) => Ok(()),
        }
    }

    /// Whether a merged look (an action's end laid over the base) draws: it
    /// decodes, and a LUT look names a `lut` media of this project. The
    /// evaluator writes `null` for one that does not.
    pub(crate) fn evaluates_as_look(&self, look: &Value) -> bool {
        let Ok(look) = serde_json::from_value::<Look>(look.clone()) else {
            return false;
        };
        look.kind != LookKind::Lut
            || look
                .media
                .and_then(|id| self.media(id))
                .is_some_and(|media| media.kind == MediaKind::Lut)
    }

    /// `remove_media` for a LUT: refused naming the clips whose base look it
    /// is unless `with_clips`, which clears those looks — on the timeline and
    /// in every nest — and keeps the clips. Ends naming it are left: the
    /// evaluator reads them as no look.
    pub(crate) fn remove_lut(&self, media: u32, with_clips: bool) -> Result<Outcome, String> {
        let used: Vec<u32> = self
            .every_clip()
            .filter(|clip| base_lut(clip) == Some(media))
            .map(|clip| clip.id)
            .collect();
        if !used.is_empty() && !with_clips {
            return Ok(Outcome::Refused(format!(
                "media {media} is the look of {}; pass with_clips: true to remove it and clear \
                 their looks",
                crate::edit_track::clip_list(&used)
            )));
        }
        let mut next = self.clone();
        let clips = next
            .clips
            .iter_mut()
            .chain(next.nests.iter_mut().flat_map(|nest| nest.clips.iter_mut()));
        for clip in clips {
            if base_lut(clip) == Some(media) {
                if let Some(video) = clip.video.as_mut() {
                    video.look = None;
                }
            }
        }
        next.media.retain(|m| m.id != media);
        self.finish(next)
    }
}
