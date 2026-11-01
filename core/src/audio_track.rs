//! A track's own terms on the sound that plays through it (format version 35,
//! spec §11 AU-102..AU-104): its fader as a gain and its pan as a list the
//! plan carries.
//!
//! **Volume** is an envelope term, read by `audio.rs` exactly where the
//! track's mute is: each [`crate::audio::Stage`] carries its track's gain,
//! decided in `Voice::of`'s walk because a nested clip's track is not in
//! `Project::tracks`, and `stage_gain` multiplies it after the mute. So a
//! nested clip is scaled by its own track and by every enclosing nest clip's
//! track, the stages multiplying as their volumes do.
//!
//! **Pan** cannot be a gain curve — it needs both channels — so it travels in
//! the plan as an audio segment's `track_pans`, and the app's tap applies the
//! product of their constant-power pairs as a balance, after the clip's own
//! pan and an enclosing nest's fold and before the clip limiter (AU-104). A
//! nest clip whose base `audio.mono` is true folds everything inside it, so
//! the pans of the tracks inside it are dropped at that stage: the fold
//! flattens them. No sample work here; the balance is Swift's.

use crate::audio::Voice;
use crate::model::Track;
use crate::model_track::TRACK_VOLUME_MAX;

/// A track's fader as a linear gain, held to 0…[`TRACK_VOLUME_MAX`]: `set_track`
/// refuses outside, so a value out of range came from a hand edit. A
/// non-finite one — unreachable from JSON — is unity, the track's default.
pub(crate) fn track_gain(track: &Track) -> f64 {
    if track.volume.is_finite() {
        track.volume.clamp(0.0, TRACK_VOLUME_MAX)
    } else {
        1.0
    }
}

/// A pan held to −1…1; a non-finite one is the centre.
fn clamped_pan(pan: f64) -> f64 {
    if pan.is_finite() {
        pan.clamp(-1.0, 1.0)
    } else {
        0.0
    }
}

impl Voice<'_> {
    /// The pans of the tracks this voice plays through, innermost first, for
    /// the plan's `track_pans` (AU-104). Walking the stages innermost first,
    /// a stage whose clip's base `audio.mono` is true — a folded nest clip
    /// above everything collected so far — clears what was collected, and
    /// then the stage's own track pan is pushed. Zeros are dropped, so an
    /// untouched project's segments carry none.
    pub(crate) fn track_pans(&self) -> Vec<f64> {
        let mut pans: Vec<f64> = Vec::with_capacity(self.stages.len());
        for stage in &self.stages {
            if stage.clip.audio.as_ref().is_some_and(|a| a.mono) {
                pans.clear();
            }
            pans.push(clamped_pan(stage.track_pan));
        }
        pans.retain(|p| *p != 0.0);
        pans
    }
}
