//! `add_speed_ramp`, the speed ramp presets (spec §11 SR-23, #340): a Ramp
//! Up, a Ramp Down, a Speed Dip or a Speed Burst made in ONE step out of
//! ordinary Speed actions — actions whose `end` names a `speed` (SR-1,
//! SR-10) — so undo, the band drags, the inspector and the plan read them
//! exactly as they read one made by hand.
//!
//! **Everything is CLIP time**, as `add_action`'s `at` is: `from` and `to`
//! are both given or both absent, which is the clip's whole length [0, D).
//! The BASE b is the rate the clip plays at `from` before the edit
//! (`rate_in_force`), which after an earlier speed action is that action's
//! end rate and not `clip.speed`.
//!
//! - **Ramp Up / Ramp Down** — one action [from, to) ending at `rate`: the
//!   clip ramps from b to it and holds it after.
//! - **Speed Dip / Speed Burst** — two actions of length r each, r being
//!   `(to − from)·(1 − hold)/2` snapped DOWN onto the grid and never under
//!   one frame: [from, from + r) ending at `rate`, and [to − r, to) ending
//!   at b. The span between them holds the target; at `hold` 0 they abut.
//!
//! "Up" and "down" are about the base rate, not about time: Up and Burst
//! need a rate above b, Down and Dip one below it. A ramp mirrored in TIME
//! would have to change the clip's own `speed`, and a preset makes only
//! Speed actions.
//!
//! **The lane's one rule holds** (spec §5.4): an action the span runs into
//! is a REFUSAL naming it, never replaced — a replacement would drop the
//! action's other keys — and the span tested is the WHOLE of [from, to)
//! for every shape, so an action sitting in a dip's hold gap is refused as
//! well: the gap must hold the target. **The clip keeps its slot** (SR-2):
//! a preset that would read past the media's end is refused naming the
//! largest rate that fits, through R1's solve (`largest_fitting_rate`).
//!
//! Errs come first, then the refusals, each in the order SR-23 lists them;
//! every sentence the lane already has is reused, not restated.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::edit_action::{action_overlaps, action_past_end, overlapping_action};
use crate::edit_action_speed::read_speed_end;
use crate::edit_clip_timing::{SPEED_MAX, SPEED_MIN};
use crate::model::{Action, Clip, Curve, Project};
use crate::outcome::Outcome;
use crate::speed_map::rate_in_force;
use crate::time::Ticks;

/// The four presets (SR-23 (c)).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RampShape {
    RampUp,
    RampDown,
    SpeedDip,
    SpeedBurst,
}

/// A dip's or a burst's hold when `hold` is absent: half the span at the
/// target, a quarter each side ramping.
pub const HOLD_DEFAULT: f64 = 0.5;
/// The most of the span a hold may take. Below 1 so each ramp keeps some
/// length to ease over; one frame is its floor in any case.
pub const HOLD_MAX: f64 = 0.9;

impl RampShape {
    /// The shape as a refusal names it.
    fn name(self) -> &'static str {
        match self {
            RampShape::RampUp => "a ramp up",
            RampShape::RampDown => "a ramp down",
            RampShape::SpeedDip => "a speed dip",
            RampShape::SpeedBurst => "a speed burst",
        }
    }

    /// Whether the target must lie ABOVE the base rate (Up and Burst) or
    /// below it (Down and Dip).
    fn rises(self) -> bool {
        matches!(self, RampShape::RampUp | RampShape::SpeedBurst)
    }

    /// Whether the shape returns to the base rate: two actions and a hold.
    fn returns(self) -> bool {
        matches!(self, RampShape::SpeedDip | RampShape::SpeedBurst)
    }
}

/// One Speed action: a span ending at `rate`.
fn speed_action(id: u32, start: Ticks, duration: Ticks, curve: Curve, rate: f64) -> Action {
    Action {
        id,
        start,
        duration,
        curve,
        end: json!({ "speed": rate }),
    }
}

impl Project {
    /// The speed ramp presets (the module doc, spec §11 SR-23).
    #[allow(clippy::too_many_arguments)]
    pub fn add_speed_ramp(
        &self,
        clip: u32,
        shape: RampShape,
        rate: f64,
        from: Option<Ticks>,
        to: Option<Ticks>,
        curve: Option<Curve>,
        hold: Option<f64>,
    ) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        // Only a media clip has a window to read at a rate; the sentence is
        // the end-rate door's own (`edit_action_speed.rs`).
        read_speed_end(&target, &Value::from(1.0))?;
        if !(rate.is_finite() && rate > 0.0) {
            return Err(format!("rate must be a positive number, not {rate}"));
        }
        let rate = rate.clamp(SPEED_MIN, SPEED_MAX);
        let (from, to) = match (from, to) {
            (None, None) => (0, target.duration),
            (Some(given_from), Some(given_to)) => {
                let from = self.snapped(given_from);
                if from < 0 {
                    return Err(format!("from must not be negative, not {given_from}"));
                }
                (from, self.snapped(given_to))
            }
            _ => return Err("from and to are given together or not at all".to_string()),
        };
        if to <= from {
            return Err(format!("to must be after from, not {to} against {from}"));
        }
        if hold.is_some() && !shape.returns() {
            return Err("hold is for speed_dip and speed_burst only".to_string());
        }

        let length = to - from;
        if to > target.duration {
            return Ok(Outcome::Refused(action_past_end(
                clip,
                from,
                length,
                target.duration,
            )));
        }
        // ONE test over the whole span, whatever the shape (SR-23 (e)).
        if let Some(other) = overlapping_action(&target.actions, None, from, length) {
            return Ok(Outcome::Refused(action_overlaps(clip, other)));
        }
        let frame = self.frame();
        if shape.returns() && length < 2 * frame {
            return Ok(Outcome::Refused(format!(
                "{} needs a span of at least two frames ({} ticks); {from} to {to} ticks is \
                 {length}",
                shape.name(),
                2 * frame
            )));
        }
        let base = rate_in_force(&target, from);
        let wrong_way = if shape.rises() {
            rate <= base
        } else {
            rate >= base
        };
        if wrong_way {
            return Ok(Outcome::Refused(format!(
                "{} needs a rate {} ×{base}, the rate clip {clip} plays at {from} ticks into \
                 it; ×{rate} is not",
                shape.name(),
                if shape.rises() { "above" } else { "below" }
            )));
        }

        let mut next = self.clone();
        let first = next.allocate_id();
        let second = shape.returns().then(|| next.allocate_id());
        let curve = curve.unwrap_or(Curve::EaseInOut);
        // A NaN hold reads as the default; any other is clamped into range.
        let hold = match hold {
            Some(h) if !h.is_nan() => h.clamp(0.0, HOLD_MAX),
            _ => HOLD_DEFAULT,
        };
        let ramp = self
            .snapped_down(((length as f64) * (1.0 - hold) / 2.0) as Ticks)
            .max(frame);
        // The clip with the preset at target rate `x`: the one closure the
        // edit and the fit both build from, so they cannot disagree.
        let build = |x: f64| -> Clip {
            let mut out = target.clone();
            match second {
                None => out
                    .actions
                    .push(speed_action(first, from, length, curve, x)),
                Some(second) => {
                    out.actions.push(speed_action(first, from, ramp, curve, x));
                    out.actions
                        .push(speed_action(second, to - ramp, ramp, curve, base));
                }
            }
            out
        };
        let after = build(rate);
        if let Some(over) = self.overrun(&after) {
            let floor_k = if shape.rises() {
                (base * 1000.0).floor() as i64 + 1
            } else {
                (SPEED_MIN * 1000.0).round() as i64
            };
            let head = format!(
                "{} to ×{rate} would read clip {clip} {over} ticks past the end of its media",
                shape.name()
            );
            return Ok(Outcome::Refused(
                match self.largest_fitting_rate(&build, rate, floor_k) {
                    Some(fit) => format!("{head}; the largest rate that fits is ×{fit}"),
                    None if shape.rises() => format!("{head}, and no rate above ×{base} fits"),
                    None => format!("{head}, and no rate down to ×0.1 fits"),
                },
            ));
        }
        if let Some(slot) = next.clip_mut(clip) {
            *slot = after;
        }
        self.finish(next)
    }
}
