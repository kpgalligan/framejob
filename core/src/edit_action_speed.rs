//! `set_action_end`'s `speed` arm (format version 27, spec §11 SR-10), and
//! the refusals every action op that can move a ramped clip's out point
//! answers (SR-2, the road map's C).
//!
//! `speed` is a number at the TOP of an action's `end`, beside the groups:
//! the rate the clip ramps to along the action's curve and holds after
//! (`speed_map.rs`). It is a door of its own, as `graphic` is
//! (`edit_action_graphic.rs`): not a property group, so `check_end_patch`
//! steps over it and this file reads it. A finite number is clamped to
//! ×0.1–×1000 as `set_speed` clamps; any other kind is an `Err`, and so is a
//! rate on a clip that is not a media clip, which has no window to read at
//! one; a `null` removes it, as it removes any key.
//!
//! **The clip keeps its slot** (SR-2): a ramp edit never moves `start` or
//! `duration`, it changes how much source the clip reads, `in + S(D)`. An
//! edit that would read past the media's end is REFUSED, naming what fits:
//! the largest end rate (R1) — S(D) is affine in one action's end rate, so
//! two readings solve it — or, when no rate down to ×0.1 fits, the latest
//! clip end at ×0.1 (R2); and for a retime, a removal or an end rate taken
//! away, the latest clip end (R3).

use serde_json::Value;

use crate::edit_clip_timing::{SPEED_MAX, SPEED_MIN};
use crate::export::describe;
use crate::model::{Clip, Project, Source};
use crate::speed_map::SpeedMap;
use crate::time::Ticks;

/// Reads a patch's `speed` for `clip`: `None` for a `null` (remove it), the
/// clamped rate for a number. `Err` for any other JSON kind, then for a
/// clip that is not a media clip.
pub(crate) fn read_speed_end(clip: &Clip, value: &Value) -> Result<Option<f64>, String> {
    if value.is_null() {
        return Ok(None);
    }
    let Some(rate) = value.as_f64() else {
        return Err(format!("speed must be a number, not {}", describe(value)));
    };
    if !matches!(clip.source, Source::Media { .. }) {
        return Err(format!(
            "clip {} is not a media clip, and only a media clip's action can end at a speed",
            clip.id
        ));
    }
    Ok(Some(rate.clamp(SPEED_MIN, SPEED_MAX)))
}

/// `clip` with action `action`'s end rate set to `rate`.
fn ending_at(clip: &Clip, action: u32, rate: f64) -> Clip {
    let mut out = clip.clone();
    if let Some(found) = out.actions.iter_mut().find(|a| a.id == action) {
        if let Value::Object(end) = &mut found.end {
            end.insert("speed".to_string(), Value::from(rate));
        }
    }
    out
}

/// The `{}` a refusal names a rate in, on the 0.001 grid it was found on.
fn thousandths(k: i64) -> f64 {
    k as f64 / 1000.0
}

impl Project {
    /// The latest clip END that fits: the clip's start plus S⁻¹ of what the
    /// file holds past `in`, snapped DOWN onto the grid, never before the
    /// start.
    fn latest_fitting_end(&self, clip: &Clip) -> Ticks {
        let Some((source_in, file)) = self.window_of(clip) else {
            return clip.start;
        };
        let remaining = file.saturating_sub(source_in).max(0) as f64;
        let fits = match SpeedMap::of(clip) {
            Some(map) => map.time_at(remaining),
            None if clip.speed.is_finite() && clip.speed > 0.0 => {
                let t = (remaining / clip.speed).floor();
                if t.is_finite() {
                    t as Ticks
                } else {
                    0
                }
            }
            None => remaining as Ticks,
        };
        self.snapped_down(clip.start.saturating_add(fits))
            .max(clip.start)
    }

    /// The largest end rate on the 0.001 grid, below `rate`, at which
    /// action `action` of `after` reads inside its file: R1's solve, then
    /// its step down. `None` when none down to ×0.1 does. Read by R1 and by
    /// a split's second half (spec §11 SR-18 (e)).
    pub(crate) fn largest_fitting_end_rate(
        &self,
        after: &Clip,
        action: u32,
        rate: f64,
    ) -> Option<f64> {
        let floor = (SPEED_MIN * 1000.0).round() as i64;
        self.largest_fitting_rate(&|x| ending_at(after, action, x), rate, floor)
    }

    /// The largest rate x on the 0.001 grid, below `rate` and at or above
    /// `floor_k` thousandths, at which the clip `at_rate(x)` reads inside
    /// its file: R1's solve, then its step down. `None` when none does.
    /// `at_rate` must make S(D) affine in x — one action's end rate
    /// (`largest_fitting_end_rate`), or a preset's target, which every
    /// piece it builds ramps to, holds or ramps from (`add_speed_ramp`,
    /// spec §11 SR-23 (g)).
    pub(crate) fn largest_fitting_rate(
        &self,
        at_rate: &dyn Fn(f64) -> Clip,
        rate: f64,
        floor_k: i64,
    ) -> Option<f64> {
        let probe = at_rate(rate);
        let (source_in, file) = self.window_of(&probe)?;
        let fits = |x: f64| self.overrun(&at_rate(x)).is_none();
        // S(D) = α + β·x in the rate x: read at two rates in range, solved
        // for the file's remainder.
        let read = |x: f64| SpeedMap::of(&at_rate(x)).map(|m| m.source_at(probe.duration));
        let solved = match (read(SPEED_MIN), read(1.0)) {
            (Some(low), Some(one)) => {
                let beta = (one - low) / (1.0 - SPEED_MIN);
                let alpha = low - SPEED_MIN * beta;
                let remaining = file.saturating_sub(source_in) as f64;
                (beta > 0.0).then(|| (remaining - alpha) / beta)
            }
            _ => None,
        };
        let x = solved.filter(|x| x.is_finite())?;
        // Floored to 0.001, never at or above the rate that overran, then
        // stepped down a thousandth until it fits. The millionth keeps a
        // solve that lands a hair under an exact thousandth (×4 read as
        // 3.9999999) on it; the step down catches the rest.
        let below = (rate * 1000.0).ceil() as i64 - 1;
        let mut k = ((x * 1000.0 + 1e-6).floor() as i64).min(below).max(floor_k);
        while k >= floor_k {
            if fits(thousandths(k)) {
                return Some(thousandths(k));
            }
            k -= 1;
        }
        None
    }

    /// R1 / R2: `after` is the clip with action `action` ending at `rate`
    /// (already clamped). `None` when it fits.
    pub(crate) fn end_rate_refusal(&self, after: &Clip, action: u32, rate: f64) -> Option<String> {
        let over = self.overrun(after)?;
        let clip = after.id;
        if let Some(fitting) = self.largest_fitting_end_rate(after, action, rate) {
            return Some(format!(
                "ending action {action} at ×{rate} would read clip {clip} {over} ticks past the \
                 end of its media; the largest end rate that fits is ×{fitting}"
            ));
        }
        let end = self.latest_fitting_end(&ending_at(after, action, SPEED_MIN));
        Some(format!(
            "ending action {action} at ×{rate} would read clip {clip} {over} ticks past the end \
             of its media, and no end rate down to ×0.1 fits; at ×0.1 the latest clip end that \
             fits is {end} ticks"
        ))
    }

    /// R3: `after` is the clip once `what` (`retiming action 7`, `removing
    /// action 7`, `removing action 7's end rate`) is done. `None` when it
    /// fits.
    pub(crate) fn overrun_refusal(&self, after: &Clip, what: &str) -> Option<String> {
        let over = self.overrun(after)?;
        let end = self.latest_fitting_end(after);
        Some(format!(
            "{what} would read clip {} {over} ticks past the end of its media; the latest clip \
             end that fits is {end} ticks",
            after.id
        ))
    }
}
