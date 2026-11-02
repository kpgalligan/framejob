//! Clip timing operations: trims and rate changes with source and action bounds.

use crate::edit_clip::clip_end;
use crate::edit_speed_profile::profile_factors;
use crate::model::{Clip, Project, Source};
use crate::model_words::rebase_words;
use crate::outcome::Outcome;
use crate::recipe_graphic::graphic_advanced;
use crate::source_window::source_advanced_through;
use crate::time::Ticks;

/// Speed range, `SPEED_MIN`–`SPEED_MAX` (spec §4.3, §11 #190). Three
/// readers: `set_speed` clamps to it, `rate_stretch` stays inside it, and
/// `Project::validate` refuses a clip outside it (spec §11 R6-10, amended by
/// #41). The app reads it through `rc_speed_limits` and never retypes it.
pub(crate) const SPEED_MIN: f64 = 0.1;
pub(crate) const SPEED_MAX: f64 = 1000.0;

/// The fastest a clip's audio still plays, in both pitch modes (spec §11
/// #190, the owner's decision of 2026-10-01). Above it the plan leaves the
/// clip's audio segment out (`evaluate.rs`); the video still runs to
/// `SPEED_MAX`. Chosen with a margin below a measured stall: an h264
/// export's loudness pass never finishes for a keep-pitch clip that starts
/// its audio track from ×15, nor in either mode from about ×20; ×12 and ×14
/// finish. B52a's mixer limits (×24 spectral, ×32 varispeed) hold only for
/// the mixer and an audio-only export, and are not the product's ceiling.
pub(crate) const AUDIO_SPEED_MAX: f64 = 12.0;

/// Every number about speed, as `rc_speed_limits` publishes it:
/// `{"min":0.1,"max":1000.0,"audio_max":12.0}`.
pub(crate) fn speed_limits() -> serde_json::Value {
    serde_json::json!({
        "min": SPEED_MIN,
        "max": SPEED_MAX,
        "audio_max": AUDIO_SPEED_MAX,
    })
}

impl Project {
    /// Moves the clip's start edge to `to`, advancing the source in point
    /// by `(to - start) × speed` so the frame under the edge does not move
    /// (spec §6).
    ///
    /// Clamped to the source bound — `to ≥ start - in/speed` snapped UP to
    /// a frame, `source_window.rs`'s `earliest_start_on_grid` (spec §11,
    /// D4-5) — and to leaving at least one frame of clip. Actions are
    /// deliberately left alone: clip-relative, rebasing would drop or bake
    /// whatever fell off the front, which is lossy and makes trimming back
    /// out not an identity. On a RAMPED clip the actions keep their clip
    /// time too, so `in` advances by round(S(Δ)) moving in and at the base
    /// rate moving out, and the edge is held where the clip still fits its
    /// media (`front_edge_held`, spec §11 SR-18 (c)): what plays after the
    /// new start can change. `text.words` are the opposite, on purpose
    /// (spec §11, W-3): a word is anchored to speech that stays where it is
    /// on the timeline, so every word is rebased by the trim's delta and a
    /// word trimmed off the front keeps its (negative) time. A graphic's
    /// `in` advances by the same delta (road map 10's G-9), with no speed
    /// and no head bound, never below 0.
    ///
    /// Without `alone`, a linked partner whose start is this clip's is
    /// trimmed to the same `to` after it, by its own clamps; with it, the
    /// clip moves alone — the J-cut (spec §11 AU-93, `carried_edge`).
    pub fn trim_start(&self, clip: u32, to: Ticks, alone: bool) -> Result<Outcome, String> {
        self.carried_edge(
            clip,
            alone,
            |target, partner| partner.start == target.start,
            |project, id| project.trim_start_one(id, to),
        )
    }

    fn trim_start_one(&self, clip: u32, to: Ticks) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let end = clip_end(&target);
        let latest = end.saturating_sub(self.frame());
        let mut to = self.snapped(to).min(latest).max(0);

        if let Some(earliest) = self.earliest_start_on_grid(&target) {
            to = to.max(earliest.max(0));
        }
        // A ramped clip's edge is held where the clip still fits its media
        // (spec §11 SR-18 (c)); a constant clip's is `to` as clamped.
        let to = self.front_edge_held(&target, to);
        // The two clamps can cross when the source has almost nothing left
        // in front: then there is no legal new start, so nothing happens.
        if to > latest || to == target.start {
            return Ok(Outcome::Identity);
        }

        let delta = to.saturating_sub(target.start);
        let mut moved = target.clone();
        moved.source = source_advanced_through(&target, delta);
        moved.start = to;
        moved.duration = end.saturating_sub(to);
        moved.graphic = graphic_advanced(target.graphic.as_ref(), delta);
        if let Some(text) = moved.text.as_mut() {
            rebase_words(text, delta);
        }
        self.commit_replacements(vec![moved])
    }

    /// Moves the clip's end edge to `to`, clamped to the source's remaining
    /// length (media sources) and to at least one frame of clip (spec §6).
    /// The source in point and the actions are untouched. The bound is
    /// `source_window.rs`'s `latest_end_on_grid`, measured at this clip's
    /// OWN start: the last frame at or before the end of the file, and
    /// never the one past it (spec §11, #22 and D4-2). A ramped clip's bound
    /// reads its map on past the end (S∞, spec §11 SR-18 (a)). A graphic's
    /// `length` is untouched: null follows the new end, a number stays (G-9).
    /// `alone` is `trim_start`'s: without it a linked partner ending where
    /// this clip ends follows; with it, the L-cut (spec §11 AU-93).
    pub fn trim_end(&self, clip: u32, to: Ticks, alone: bool) -> Result<Outcome, String> {
        self.carried_edge(
            clip,
            alone,
            |target, partner| clip_end(partner) == clip_end(target),
            |project, id| project.trim_end_one(id, to),
        )
    }

    fn trim_end_one(&self, clip: u32, to: Ticks) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let earliest = target.start.saturating_add(self.frame());
        let mut to = self.snapped(to).max(earliest);
        if let Some(latest) = self.latest_end_on_grid(&target) {
            to = to.min(latest);
        }
        if to < earliest || to == clip_end(&target) {
            return Ok(Outcome::Identity);
        }

        let mut moved = target.clone();
        moved.duration = to.saturating_sub(target.start);
        self.commit_replacements(vec![moved])
    }

    /// Drags the clip's end edge to `to_end` by changing its SPEED, not the
    /// source range it shows: `speed = source_len / (to_end - start)`
    /// (spec §6). Media sources only.
    ///
    /// An IDENTITY when the new length is under a frame or the resulting rate
    /// falls outside `SPEED_MIN`–`SPEED_MAX`; refused only when the placement
    /// breaks the overlap rule. Actions keep their clip-relative fraction.
    ///
    /// On a RAMPED clip the whole rate profile scales by f = D ÷ (to_end −
    /// start) through `scaled_profile`, so the ramp keeps its shape and its
    /// window; an f that would take any rate the clip names past the limits
    /// (`profile_factors`) changes nothing (spec §11 SR-19 (a), (b)).
    /// Refused on a linked clip (spec §11 AU-94).
    pub fn rate_stretch(&self, clip: u32, to_end: Ticks) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        if !matches!(target.source, Source::Media { .. }) {
            return Err(format!("clip {clip} is not a media clip"));
        }
        let to_end = self.snapped(to_end);
        let duration = to_end.saturating_sub(target.start);
        if duration < self.frame() {
            return Ok(Outcome::Identity);
        }
        if let Some((low, high)) = profile_factors(&target) {
            let factor = target.duration as f64 / duration as f64;
            if !factor.is_finite() || !(low..=high).contains(&factor) {
                return Ok(Outcome::Identity);
            }
            let moved = self.scaled_profile(&target, factor, duration);
            return self.commit_rate(&target, moved);
        }
        let rate = self.content_length_in_source(&target) as f64 / duration as f64;
        if !rate.is_finite() || !(SPEED_MIN..=SPEED_MAX).contains(&rate) {
            return Ok(Outcome::Identity);
        }

        let mut moved = target.clone();
        moved.speed = rate;
        moved.duration = duration;
        self.rescale_actions(&mut moved.actions, target.duration, duration);
        self.commit_rate(&target, moved)
    }

    /// A rate edit's commit: refused on a linked clip whose rate it changes
    /// (spec §11 AU-94), else placed as any replacement is.
    fn commit_rate(&self, before: &Clip, moved: Clip) -> Result<Outcome, String> {
        if let Some(why) = self.linked_rate_refusal(before, &moved) {
            return Ok(Outcome::Refused(why));
        }
        self.commit_replacements(vec![moved])
    }

    /// Sets the clip's playback rate: `duration = source_len / rate` held
    /// to what the file holds AT THAT RATE (`duration_at_speed`, spec §11
    /// D4-3), actions keeping their clip-relative fraction (spec §6). Media
    /// sources only; `keep_pitch`, when given, sets the time-pitch flag.
    ///
    /// Takes a `rate` or a `duration`, exactly one (spec §11 #190). A
    /// duration is the Fit arm: snapped to the grid, held to a frame, and
    /// turned into the rate that plays the clip's content in it; the current
    /// duration keeps the current rate, so it makes no phantom step.
    ///
    /// Either rate is clamped to `SPEED_MIN`–`SPEED_MAX` rather than
    /// refused, because a slider or an MCP call that asks for more wants the
    /// fastest thing available. `Err` for both or neither, a non-media clip,
    /// a rate that is not a positive finite number or a duration that is not
    /// positive; refuses on an overlap-rule violation.
    ///
    /// On a RAMPED clip the whole rate profile scales by one factor f — the
    /// clamped rate over the base, or D ÷ d — clamped so no rate the clip
    /// names passes a limit (`profile_factors`): the ramp keeps its shape
    /// and its window, and its base may stop short of the rate asked; when
    /// f does not clamp, the base is the clamped rate itself. The
    /// new duration is d, or snapped(round(D ÷ f)) when f clamped or the
    /// rate arm set it, held through `scaled_profile` (spec §11 SR-19 (a),
    /// (b)). An f of 1 changes nothing but `keep_pitch`. A linked clip's
    /// rate is refused (spec §11 AU-94); `keep_pitch` alone is not a rate.
    pub fn set_speed(
        &self,
        clip: u32,
        rate: Option<f64>,
        duration: Option<Ticks>,
        keep_pitch: Option<bool>,
    ) -> Result<Outcome, String> {
        match (rate, duration) {
            (Some(_), Some(_)) => {
                return Err(format!(
                    "set_speed takes a rate or a duration, not both (clip {clip})"
                ))
            }
            (None, None) => {
                return Err(format!(
                    "set_speed takes a rate or a duration (clip {clip})"
                ))
            }
            _ => {}
        }
        let target = self.require_clip(clip)?.clone();
        if !matches!(target.source, Source::Media { .. }) {
            return Err(format!("clip {clip} is not a media clip"));
        }
        if let Some(rate) = rate {
            if !(rate.is_finite() && rate > 0.0) {
                return Err(format!("speed must be a positive number, not {rate}"));
            }
        }
        if let Some(duration) = duration {
            if duration <= 0 {
                return Err(format!("duration must be positive, not {duration}"));
            }
        }
        if let Some((low, high)) = profile_factors(&target) {
            let frame = self.frame();
            let (asked, fitted) = match (rate, duration) {
                (Some(rate), _) => (rate.clamp(SPEED_MIN, SPEED_MAX) / target.speed, None),
                (None, Some(duration)) => {
                    let d = self.snapped(duration).max(frame);
                    if d == target.duration {
                        (1.0, None)
                    } else {
                        (target.duration as f64 / d as f64, Some(d))
                    }
                }
                (None, None) => (1.0, None),
            };
            let factor = asked.clamp(low, high);
            let length = match fitted {
                Some(d) if factor == asked => d,
                _ => {
                    let scaled = (target.duration as f64 / factor).round();
                    if scaled.is_finite() {
                        self.snapped(scaled as Ticks).max(frame)
                    } else {
                        target.duration
                    }
                }
            };
            let mut moved = self.scaled_profile(&target, factor, length);
            // An unclamped rate arm writes the rate asked itself: `speed ×
            // (rate ÷ speed)` can miss it by an ULP (spec §11 SR-19 (a)).
            if let (Some(rate), true) = (rate, factor == asked) {
                moved.speed = rate.clamp(SPEED_MIN, SPEED_MAX);
            }
            if let (Some(keep), Some(audio)) = (keep_pitch, moved.audio.as_mut()) {
                audio.keep_pitch = keep;
            }
            return self.commit_rate(&target, moved);
        }
        let rate = match (rate, duration) {
            (Some(rate), _) => rate,
            (None, Some(duration)) => {
                let d = self.snapped(duration).max(self.frame());
                if d == target.duration {
                    target.speed
                } else {
                    self.content_length_in_source(&target) as f64 / d as f64
                }
            }
            (None, None) => target.speed,
        };
        let rate = rate.clamp(SPEED_MIN, SPEED_MAX);

        let mut moved = target.clone();
        moved.speed = rate;
        moved.duration = self.duration_at_speed(&target, rate);
        self.rescale_actions(&mut moved.actions, target.duration, moved.duration);
        if let (Some(keep), Some(audio)) = (keep_pitch, moved.audio.as_mut()) {
            audio.keep_pitch = keep;
        }
        self.commit_rate(&target, moved)
    }
}
