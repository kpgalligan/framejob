//! Speech spans on a media (format 29, spec §11 AU-110, AU-111):
//! `set_media_speech`, and the rules a `media.speech` obeys, written once for
//! the op and for `validate`.
//!
//! - **The op.** `set_media_speech {media, spans}` stores the spans the app
//!   read from its voice-activity cache on the media, as forward-file SOURCE
//!   ticks `[start, end)`. Choosing Duck by Speech writes it, in the same
//!   undo step as the `set_audio` that turns the mode on, for a media that
//!   has none yet; an empty list is a media in which no speech was found,
//!   and is stored as such. Equal spans are an identity. Unknown media is an
//!   `Err`; every rule below is a refusal in its own sentence.
//! - **The rules** ([`Project::check_media_speech`]): the media has audio;
//!   each span starts at 0 or later, ends after it starts and at or before
//!   the media's `duration`; the spans are sorted and do not overlap (they
//!   may touch); there are at most [`MAX_SPEECH_SPANS`]. `validate` holds a
//!   file to the same rules, as errors.
//! - **What reads them** is `audio_duck_speech.rs`, for a ducker in `speech`
//!   mode. A relink that probes the new file clips or clears them
//!   (`edit_relink.rs`, AU-116); `add_media` and a probe never carry them.

use crate::model::{Media, Project};
use crate::outcome::Outcome;
use crate::time::Ticks;

/// The most spans one media may carry: some 28 hours of speech broken every
/// second, and a bound on what one op can make the plan sample.
pub const MAX_SPEECH_SPANS: usize = 100_000;

impl Project {
    /// Stores `spans` as `media`'s speech (spec §11 AU-110). `Err` for an
    /// unknown media; a refusal for spans [`Project::check_media_speech`]
    /// refuses; an identity when they equal what the media already has.
    pub fn set_media_speech(&self, media: u32, spans: &[[Ticks; 2]]) -> Result<Outcome, String> {
        let current = self.require_media(media)?;
        if current.speech.as_deref() == Some(spans) {
            return Ok(Outcome::Identity);
        }
        let mut next = self.clone();
        let Some(row) = next.media.iter_mut().find(|m| m.id == media) else {
            return Err(format!("no media with id {media}"));
        };
        row.speech = Some(spans.to_vec());
        if let Err(why) = self.check_media_speech(row) {
            return Ok(Outcome::Refused(why));
        }
        self.finish(next)
    }

    /// The rules a media's `speech` obeys, each failure its own sentence
    /// naming the media and the span. A media without `speech` passes.
    pub(crate) fn check_media_speech(&self, media: &Media) -> Result<(), String> {
        let Some(spans) = &media.speech else {
            return Ok(());
        };
        let id = media.id;
        if !media.has_audio {
            return Err(format!(
                "media {id} has no audio, so it has no speech to duck by"
            ));
        }
        if spans.len() > MAX_SPEECH_SPANS {
            return Err(format!(
                "media {id} carries {} speech spans, more than {MAX_SPEECH_SPANS}",
                spans.len()
            ));
        }
        let mut previous: Option<Ticks> = None;
        for (i, &[start, end]) in spans.iter().enumerate() {
            if start < 0 {
                return Err(format!(
                    "media {id} speech span {i} starts at {start}, before 0"
                ));
            }
            if end <= start {
                return Err(format!(
                    "media {id} speech span {i} ends at {end}, not after its start {start}"
                ));
            }
            if end > media.duration {
                return Err(format!(
                    "media {id} speech span {i} ends at {end}, past the media's duration {}",
                    media.duration
                ));
            }
            if let Some(before) = previous.filter(|before| start < *before) {
                return Err(format!(
                    "media {id} speech span {i} starts at {start}, before span {} ends at \
                     {before}: speech spans are sorted and do not overlap",
                    i - 1
                ));
            }
            previous = Some(end);
        }
        Ok(())
    }
}
