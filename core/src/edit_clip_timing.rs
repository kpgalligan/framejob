//! Clip timing operations: trims and rate changes with source and action bounds.

use crate::edit_clip::clip_end;
use crate::model::{Action, Project, Source};
use crate::outcome::Outcome;
use crate::source_window::source_advanced;
use crate::time::Ticks;

/// Speed range, matching the inspector's ×0.1 – ×10 (spec §4.3). Outside
/// it, `scaleTimeRange` and the time-pitch unit stop producing anything
/// anyone wants to watch.
const SPEED_MIN: f64 = 0.1;
const SPEED_MAX: f64 = 10.0;

impl Project {
    /// Scales every action's span with the clip, so an action keeps the
    /// same clip-relative FRACTION when the clip's length changes (spec §6,
    /// `set_speed`).
    ///
    /// Rounding can leave two adjacent actions touching by a tick; that is
    /// harmless, because evaluation orders actions by `(start, id)` and is
    /// defined for overlaps — only `add_action` refuses to create one.
    fn rescale_actions(&self, actions: &mut [Action], old: Ticks, new: Ticks) {
        if old <= 0 || new <= 0 || old == new {
            return;
        }
        let frame = self.frame();
        let factor = new as f64 / old as f64;
        for action in actions.iter_mut() {
            let scaled_start = (action.start as f64 * factor).round();
            let scaled_duration = (action.duration as f64 * factor).round();
            let start = if scaled_start.is_finite() {
                self.snapped(scaled_start as Ticks)
            } else {
                action.start
            };
            let duration = if scaled_duration.is_finite() {
                self.snapped(scaled_duration as Ticks)
            } else {
                action.duration
            };
            // Clamped so the action still fits the clip and still has a
            // positive duration, which `validate` requires.
            action.start = start.clamp(0, new.saturating_sub(frame).max(0));
            action.duration = duration
                .max(frame)
                .min(new.saturating_sub(action.start))
                .max(1);
        }
    }

    /// Moves the clip's start edge to `to`, advancing the source in point
    /// by `(to - start) × speed` so the frame under the edge does not move
    /// (spec §6).
    ///
    /// Clamped to the source bound — `to ≥ start - in/speed` snapped UP to
    /// a frame, `source_window.rs`'s `earliest_start_on_grid` (spec §11,
    /// D4-5) — and to leaving at least one frame of clip. Actions are
    /// deliberately left alone: clip-relative, rebasing would drop or bake
    /// whatever fell off the front, which is lossy and makes trimming back
    /// out not an identity.
    pub fn trim_start(&self, clip: u32, to: Ticks) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let end = clip_end(&target);
        let latest = end.saturating_sub(self.frame());
        let mut to = self.snapped(to).min(latest).max(0);

        if let Some(earliest) = self.earliest_start_on_grid(&target) {
            to = to.max(earliest.max(0));
        }
        // The two clamps can cross when the source has almost nothing left
        // in front: then there is no legal new start, so nothing happens.
        if to > latest || to == target.start {
            return Ok(Outcome::Identity);
        }

        let delta = to.saturating_sub(target.start);
        let mut moved = target.clone();
        moved.source = source_advanced(&target.source, delta, target.speed);
        moved.start = to;
        moved.duration = end.saturating_sub(to);
        self.commit_replacements(vec![moved])
    }

    /// Moves the clip's end edge to `to`, clamped to the source's remaining
    /// length (media sources) and to at least one frame of clip (spec §6).
    /// The source in point and the actions are untouched. The bound is
    /// `source_window.rs`'s `latest_end_on_grid`, measured at this clip's
    /// OWN start: the last frame at or before the end of the file, and
    /// never the one past it (spec §11, #22 and D4-2).
    pub fn trim_end(&self, clip: u32, to: Ticks) -> Result<Outcome, String> {
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
    /// Refuses when the resulting rate falls outside ×0.1 – ×10, when the
    /// new length is under a frame, or when the placement breaks the
    /// overlap rule. Actions keep their clip-relative fraction.
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
        let rate = self.content_length_in_source(&target) as f64 / duration as f64;
        if !rate.is_finite() || !(SPEED_MIN..=SPEED_MAX).contains(&rate) {
            return Ok(Outcome::Identity);
        }

        let mut moved = target.clone();
        moved.speed = rate;
        moved.duration = duration;
        self.rescale_actions(&mut moved.actions, target.duration, duration);
        self.commit_replacements(vec![moved])
    }

    /// Sets the clip's playback rate: `duration = source_len / rate` held
    /// to what the file holds AT THAT RATE (`duration_at_speed`, spec §11
    /// D4-3), actions keeping their clip-relative fraction (spec §6). Media
    /// sources only; `keep_pitch`, when given, sets the time-pitch flag.
    ///
    /// The rate is clamped to the inspector's ×0.1 – ×10 rather than
    /// refused, because a slider or an MCP call that asks for ×20 wants the
    /// fastest thing available. `Err` for a non-media clip or a rate that
    /// is not a positive finite number; refuses on an overlap-rule
    /// violation.
    pub fn set_speed(
        &self,
        clip: u32,
        rate: f64,
        keep_pitch: Option<bool>,
    ) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        if !matches!(target.source, Source::Media { .. }) {
            return Err(format!("clip {clip} is not a media clip"));
        }
        if !(rate.is_finite() && rate > 0.0) {
            return Err(format!("speed must be a positive number, not {rate}"));
        }
        let rate = rate.clamp(SPEED_MIN, SPEED_MAX);

        let mut moved = target.clone();
        moved.speed = rate;
        moved.duration = self.duration_at_speed(&target, rate);
        self.rescale_actions(&mut moved.actions, target.duration, moved.duration);
        if let (Some(keep), Some(audio)) = (keep_pitch, moved.audio.as_mut()) {
            audio.keep_pitch = keep;
        }
        self.commit_replacements(vec![moved])
    }
}
