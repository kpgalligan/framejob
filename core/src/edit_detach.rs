//! A clip's video and audio halves — Detach Audio and the two enablement
//! flags it sets, `set_enabled`.
//!
//! Cut out of `edit_clip.rs` under the size rule at grading L3, a pure move:
//! `edit_clip.rs` decides where a clip sits, this decides which of its halves
//! plays.

use crate::model::{AudioProps, Enabled, Project, Source};
use crate::outcome::Outcome;

impl Project {
    /// Splits the clip's audio onto its own clip on the track BELOW,
    /// inserting a track at index 0 when the clip is already on the bottom
    /// one (spec §6).
    ///
    /// The original keeps its video and gets `enabled.audio = false`; the
    /// new clip is `{video: false, audio: true}` with the same source, in
    /// point, duration and speed, and its VIDEO props, so re-enabling video
    /// on it is not lossy. Refuses, naming why, with no audio to detach
    /// (spec §11 #88), and when the new clip breaks the overlap rule below.
    pub fn detach_audio(&self, clip: u32) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let why = match target.source {
            Source::Media { media, .. } if !self.require_media(media)?.has_audio => {
                format!("media {media} has no audio track")
            }
            Source::Media { .. } if target.enabled.audio => String::new(),
            Source::Media { .. } => "its audio is switched off".to_string(),
            _ => "it is not a media clip".to_string(),
        };
        if !why.is_empty() {
            let why = format!("clip {clip} has no audio to detach: {why}");
            return Ok(Outcome::Refused(why));
        }
        let index = self.require_track_index(target.track)?;

        let mut next = self.clone();
        let below = match index.checked_sub(1).and_then(|i| self.tracks.get(i)) {
            Some(track) => track.id,
            None => {
                // The clip is on the bottom track, so the audio needs a new
                // one under it. Naming by the count keeps it unique without
                // renumbering the tracks above.
                let track = next.numbered_track();
                let id = track.id;
                next.tracks.insert(0, track);
                id
            }
        };

        let mut audio_clip = target.clone();
        // Actions move with the clip and need their own ids; a video action
        // on a non-drawing clip is inert, and dropping it would lose the
        // volume actions that belong here.
        next.remint(&mut audio_clip);
        audio_clip.track = below;
        audio_clip.enabled = Enabled {
            video: false,
            audio: true,
        };
        audio_clip.audio = target.audio.or_else(|| Some(AudioProps::default()));
        // The transition describes an overlap on the ORIGINAL track.
        audio_clip.transition_in = None;

        if let Some(slot) = next.clip_mut(clip) {
            slot.enabled.audio = false;
        }
        self.commit_additions(next, vec![audio_clip])
    }

    // ---- enablement ------------------------------------------------------

    /// Per-clip visibility and mute (spec §6). An argument left `None` is
    /// left alone, so the two halves of Detach Audio can be set
    /// independently.
    pub fn set_enabled(
        &self,
        clip: u32,
        video: Option<bool>,
        audio: Option<bool>,
    ) -> Result<Outcome, String> {
        self.require_clip(clip)?;
        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            if let Some(value) = video {
                slot.enabled.video = value;
            }
            if let Some(value) = audio {
                slot.enabled.audio = value;
            }
        }
        self.finish(next)
    }
}
