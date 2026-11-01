//! Fade and crossfade shapes (spec §11 AU-114, AU-115): the gain a
//! [`FadeShape`] gives at a progress, and the ticks a shaped fade has to be
//! sampled at for its curve to survive `audio.rs`'s coalescing.
//!
//! A shape is a curve over the fade's progress u in 0..1, read by
//! `audio.rs`'s fades (u is `t / fade_in` in, `remaining / fade_out` out) and
//! by `audio_crossfade.rs` over a transition's eased progress. `linear` is
//! `u` itself — the expression the fades always used, so a linear fade
//! plans exactly as before and needs no samples — and the other three are
//! not straight lines, so a fade in one of them is sampled on the action
//! grid, as an eased action is.
//!
//! It also holds [`Transition`]'s `Default`, because the one field that keeps
//! it from being derived is a shape: a transition's file default crossfades
//! (when `audio` is on) at R5-2's constant power, `plus_3db`, where a fade's
//! default is `linear`.

use std::f64::consts::{FRAC_PI_2, PI};

use crate::audio::{ACTION_SAMPLE, MAX_ACTION_SAMPLES};
use crate::model::{Curve, FadeShape, Transition, TransitionKind};
use crate::time::Ticks;

impl FadeShape {
    /// The gain at progress `u`, clamped to 0..1: Linear `u`, S-curve
    /// `(1 − cos πu)/2`, +3 dB `sin(uπ/2)`, −3 dB `1 − cos(uπ/2)`. Each runs
    /// from exactly 0 to exactly 1 at the two ends, so a fade never leaves a
    /// residue of gain where it should be silent or full.
    pub(crate) fn gain(self, u: f64) -> f64 {
        match self {
            FadeShape::Linear => u,
            _ if u <= 0.0 => 0.0,
            _ if u >= 1.0 => 1.0,
            FadeShape::SCurve => (1.0 - (PI * u).cos()) / 2.0,
            FadeShape::Plus3Db => (u * FRAC_PI_2).sin(),
            FadeShape::Minus3Db => 1.0 - (u * FRAC_PI_2).cos(),
        }
    }
}

/// The ticks a shaped fade over `[start, end]` (project time) is sampled at:
/// its two edges plus the action grid across it — `ACTION_SAMPLE`, widened
/// so one fade never contributes more than `MAX_ACTION_SAMPLES` points, the
/// step `audio.rs`'s action loop and `audio_crossfade.rs` both use.
pub(crate) fn fade_breaks(start: Ticks, end: Ticks) -> Vec<Ticks> {
    let mut out = vec![start, end];
    let span = end.saturating_sub(start);
    if span <= 0 {
        return out;
    }
    let step = ACTION_SAMPLE.max(span / MAX_ACTION_SAMPLES + 1);
    let mut t = start.saturating_add(step);
    while t < end {
        out.push(t);
        t = t.saturating_add(step);
    }
    out
}

impl Default for Transition {
    /// The FILE default (`model.rs`'s doc on [`Transition`]): a cross
    /// dissolve, linear, silent — and, should `audio` be switched on, R5-2's
    /// constant-power crossfade, `plus_3db` (spec §11 AU-115).
    fn default() -> Self {
        Transition {
            kind: TransitionKind::CrossDissolve,
            curve: Curve::Linear,
            audio: false,
            audio_shape: FadeShape::Plus3Db,
        }
    }
}
