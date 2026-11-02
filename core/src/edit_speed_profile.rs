//! The rate profile a rate edit scales: the factors a ramped clip's whole
//! profile may be scaled by, and the helpers that scale a clip's actions
//! and its profile with its length (spec §6 `set_speed`, §11 SR-19). A pure
//! move out of `edit_clip_timing.rs` (road map "creator-jobs" CU9a's toll),
//! shared by `set_speed`, `rate_stretch` and `retime_range`.

use serde_json::Value;

use crate::edit_clip_timing::{SPEED_MAX, SPEED_MIN};
use crate::frame_grid::resnap_actions;
use crate::model::{Action, Clip, Project};
use crate::speed_map::{end_speed, SpeedMap};
use crate::time::Ticks;

/// The range of factors one rate edit may scale a RAMPED clip's whole
/// profile by: `(SPEED_MIN / r_min, SPEED_MAX / r_max)`, r over the base
/// and every action's `end_speed` (the rates `peak_rate` reads), so no rate
/// the clip names leaves `SPEED_MIN`–`SPEED_MAX` (spec §11 SR-19 (a)).
/// `None` when [`SpeedMap::of`] is, which is every constant clip.
pub(crate) fn profile_factors(clip: &Clip) -> Option<(f64, f64)> {
    SpeedMap::of(clip)?;
    let rates = std::iter::once(clip.speed).chain(clip.actions.iter().filter_map(end_speed));
    let (low, high) = rates.fold((f64::INFINITY, f64::NEG_INFINITY), |(lo, hi), r| {
        (lo.min(r), hi.max(r))
    });
    Some((SPEED_MIN / low, SPEED_MAX / high))
}

impl Project {
    /// Scales every action's span with the clip, so an action keeps the
    /// same clip-relative FRACTION when the clip's length changes (spec §6,
    /// `set_speed`).
    ///
    /// Rounding can leave two adjacent actions touching by a tick; that is
    /// harmless, because evaluation orders actions by `(start, id)` and is
    /// defined for overlaps — only `add_action` refuses to create one.
    pub(crate) fn rescale_actions(&self, actions: &mut [Action], old: Ticks, new: Ticks) {
        if old <= 0 || new <= 0 || old == new {
            return;
        }
        let frame = self.frame();
        let factor = new as f64 / old as f64;
        for action in actions.iter_mut() {
            let (start, duration) = self.scaled_span(action, factor);
            // Clamped so the action still fits the clip and still has a
            // positive duration, which `validate` requires.
            action.start = start.clamp(0, new.saturating_sub(frame).max(0));
            action.duration = duration
                .max(frame)
                .min(new.saturating_sub(action.start))
                .max(1);
        }
    }

    /// `action`'s start and duration × `factor`, each rounded then snapped
    /// to the grid. A product that is not finite keeps the old value. NOT
    /// clamped: `rescale_actions` clamps what it takes from here, and
    /// `scaled_profile` leaves a speed action where it lands (spec §11
    /// SR-19 (b)).
    pub(crate) fn scaled_span(&self, action: &Action, factor: f64) -> (Ticks, Ticks) {
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
        (start, duration)
    }

    /// `clip` with its whole rate profile × `factor`, `duration` long (spec
    /// §11 SR-19 (a), (b)): `speed` and every action's numeric `end.speed`,
    /// each product clamped to `SPEED_MIN`–`SPEED_MAX` (no rate is
    /// rewritten when `factor` is 1). Every SPEED action's span scales by
    /// `duration / clip.duration`, snapped and NOT clamped into the clip, so
    /// one running past the end still does and S∞′(t·D′/D) = S∞(t); every
    /// other action is rescaled and clamped as `rescale_actions` does. The
    /// duration is then held through S∞ with the speed actions as they stand
    /// (D4-3's `duration_resnapped`), as `trim_end` leaves them; when the
    /// hold shortens the clip, the other actions are re-clamped into what is
    /// left, as `resnap_clip_times`' second pass does (`resnap_actions`).
    pub(crate) fn scaled_profile(&self, clip: &Clip, factor: f64, duration: Ticks) -> Clip {
        let mut scaled = clip.clone();
        if factor != 1.0 {
            scaled.speed = (clip.speed * factor).clamp(SPEED_MIN, SPEED_MAX);
        }
        let frame = self.frame();
        let span = duration as f64 / clip.duration as f64;
        for action in scaled.actions.iter_mut() {
            let Some(rate) = end_speed(action) else {
                self.rescale_actions(std::slice::from_mut(action), clip.duration, duration);
                continue;
            };
            if factor != 1.0 {
                if let Value::Object(end) = &mut action.end {
                    let product = (rate * factor).clamp(SPEED_MIN, SPEED_MAX);
                    end.insert("speed".to_string(), Value::from(product));
                }
            }
            let (start, length) = self.scaled_span(action, span);
            action.start = start.max(0);
            action.duration = length.max(frame).max(1);
        }
        scaled.duration = duration;
        scaled.duration = self.duration_resnapped(&scaled);
        if scaled.duration != duration {
            resnap_actions(self, &mut scaled);
        }
        scaled
    }
}
