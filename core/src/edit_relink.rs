//! `relink_media` — spec §6, table "Tracks, markers, canvas, media", and
//! spec §11 #63.
//!
//! A relink points a media at another file: Relink… after the original
//! moved (spec §5.6), the missing-media sheet, or the tool. Given the new
//! file's PROBE — the descriptor `MediaImporter.probe` answers, minus `path`
//! and `bookmark` — the record takes its duration, size, rate and flags, a
//! file of another kind is refused, and every media clip of it whose window
//! now runs past a SHORTER file's end is held to it. Without a probe the
//! record is kept: Consolidate and the open-time re-anchor point at a copy
//! of the same file.
//!
//! Cut out of `edit_track.rs`, which keeps the media list's other two ops
//! and the two things this one shares with `add_media`: `MEDIA_KEYS` and
//! `check_media_fields`, so a probe is checked in the same words a
//! descriptor is.

use std::mem;

use serde_json::Value;

use crate::edit_track::{check_media_fields, MEDIA_KEYS};
use crate::export::describe;
use crate::model::{Clip, Media, MediaKind, Project, Source};
use crate::outcome::Outcome;
use crate::source_window::SourceBound;

/// A kind's JSON spelling, for the refusal: serde's own, so the sentence
/// names the kind the way the file and the schema do.
fn kind_name(kind: MediaKind) -> String {
    serde_json::to_value(kind)
        .ok()
        .and_then(|value| value.as_str().map(str::to_string))
        .unwrap_or_default()
}

impl Project {
    /// Points a media at a new file, and — given its `probe` — takes the
    /// file's facts (spec §11 #63).
    ///
    /// A `bookmark` of `None` CLEARS the stored one rather than keeping it:
    /// a bookmark resolves to the file it was made from, so the old one
    /// would point straight back at the file the user is replacing.
    ///
    /// Answers, in order: `Err` for an unknown media or an empty path; `Err`
    /// for a probe that is not an object, that carries a key outside the
    /// descriptor's (or `path` or `bookmark`, which are this op's own
    /// arguments), that does not match the schema, or whose fields
    /// `add_media` would refuse; then a REFUSAL for a file of another kind,
    /// because each clip's source kind was chosen from it.
    ///
    /// A probed relink writes `duration`, `width`, `height`, `fps` and the
    /// three flags, then holds each `media`-source clip of this media — on
    /// the timeline and in every stored nest, orphans included — whose
    /// duration exceeds the window the file now holds to
    /// `duration_resnapped` (D4-4): on the grid, at least one frame, the
    /// frame floor winning for a clip whose `in` is past the new end.
    /// Everything else on the clip is kept, as `trim_end` keeps it; a still
    /// keeps its `at`; the overlap rule is not re-checked (D7-3).
    pub fn relink_media(
        &self,
        media: u32,
        path: &str,
        bookmark: Option<&str>,
        probe: Option<&Value>,
    ) -> Result<Outcome, String> {
        let old_kind = self.require_media(media)?.kind;
        let path = path.trim();
        if path.is_empty() {
            return Err("media path must not be empty".to_string());
        }
        let probed = match probe {
            Some(probe) => Some(read_probe(media, path, probe)?),
            None => None,
        };
        if let Some(new) = &probed {
            if new.kind != old_kind {
                return Ok(Outcome::Refused(format!(
                    "media {media} is {} media and {path} is {}: relink it to a file of the \
                     same kind, or import this one as new media",
                    kind_name(old_kind),
                    kind_name(new.kind)
                )));
            }
        }

        let mut next = self.clone();
        if let Some(found) = next.media.iter_mut().find(|m| m.id == media) {
            found.path = path.to_string();
            found.bookmark = bookmark
                .map(str::trim)
                .filter(|given| !given.is_empty())
                .map(|given| given.to_string());
            if let Some(new) = &probed {
                found.duration = new.duration;
                found.width = new.width;
                found.height = new.height;
                found.fps = new.fps;
                found.has_video = new.has_video;
                found.has_audio = new.has_audio;
                found.has_alpha = new.has_alpha;
            }
        }
        if probed.is_some() {
            // Each list is taken out for the walk so a clip's window can be
            // measured against the whole project, the new record included —
            // `edit_canvas.rs`'s `resnap` pattern, every stored nest once.
            let mut clips = mem::take(&mut next.clips);
            next.hold_to_file(&mut clips, media);
            next.clips = clips;
            for index in 0..next.nests.len() {
                let mut clips = mem::take(&mut next.nests[index].clips);
                next.hold_to_file(&mut clips, media);
                next.nests[index].clips = clips;
            }
        }
        self.finish(next)
    }

    /// Holds every `media`-source clip of `media` in `clips` whose duration
    /// runs past the window its file holds, through `source_window.rs`'s
    /// one re-snap of a media duration.
    fn hold_to_file(&self, clips: &mut [Clip], media: u32) {
        for clip in clips.iter_mut() {
            if !matches!(clip.source, Source::Media { media: id, .. } if id == media) {
                continue;
            }
            if let SourceBound::Timeline(bound) = self.source_length_on_timeline(clip) {
                if clip.duration > bound {
                    clip.duration = self.duration_resnapped(clip);
                }
            }
        }
    }
}

/// A relink's probe read as a media record, or the `Err` naming what is
/// wrong with it — the Interfaces order of spec §11 #63: not an object, an
/// unknown key, the schema, then `add_media`'s field checks.
fn read_probe(media: u32, path: &str, probe: &Value) -> Result<Media, String> {
    let Value::Object(fields) = probe else {
        return Err(format!(
            "a relink probe must be a json object, not {}",
            describe(probe)
        ));
    };
    for key in fields.keys() {
        if !MEDIA_KEYS.contains(&key.as_str()) || key == "path" || key == "bookmark" {
            return Err(format!("unknown key \"{key}\" in a relink probe"));
        }
    }
    // Deserialized through `Media` itself, as `add_media` does, so the
    // probe's schema is the model's schema with no second spelling of it.
    let mut record = fields.clone();
    record.insert("id".to_string(), Value::from(media));
    record.insert("path".to_string(), Value::from(path));
    let record: Media = serde_json::from_value(Value::Object(record))
        .map_err(|e| format!("relink probe does not match the schema: {e}"))?;
    check_media_fields(&record)?;
    Ok(record)
}
