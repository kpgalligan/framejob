//! A clip's rate as a function of clip time, and the source map S it
//! integrates to (spec §5.4, §11 SR-10).
//!
//! An action's `end` may carry `speed`, a number beside the property groups
//! (format version 27). The rate in force at clip time t is §5.4's rule on
//! that one number: the clip's base `speed`, then each ENDED action's
//! `end.speed` in start order, and inside the first action spanning t — when
//! it names a speed — `r_from + (r_to − r_from)·ease(u)` along its curve,
//! held after. S(t) = ∫₀ᵗ rate is the source the clip has read by t, in
//! source ticks from its `in`; the eases are polynomials, so S is closed
//! form in every piece and no reader integrates numerically.
//!
//! **Only a media clip is RAMPED** ([`is_ramped`]): a still, an image, text,
//! a shape, a graphic, a nest and an adjustment clip have no window to read
//! at a rate, so a hand-written `end.speed` on one is ignored here and every
//! path stays the constant one. A clip with no speed end is constant too, and
//! [`SpeedMap::of`] answers `None` for both, which is what keeps every plan
//! without a ramp byte-identical.
//!
//! Nothing here edits: the map is built from a clip and answers numbers.

use crate::actions::{ease, ordered_actions, spans};
use crate::edit_clip_timing::{SPEED_MAX, SPEED_MIN};
use crate::model::{Action, Clip, Curve, Source};
use crate::time::Ticks;

/// An action's end rate: `end.speed` as a finite number, clamped to
/// `SPEED_MIN`–`SPEED_MAX` as `set_speed` clamps. Any other JSON kind — a
/// string, a `null` a hand-written file stored — names no rate.
pub(crate) fn end_speed(action: &Action) -> Option<f64> {
    let rate = action.end.get("speed")?.as_f64()?;
    rate.is_finite().then(|| rate.clamp(SPEED_MIN, SPEED_MAX))
}

/// The greatest rate the clip NAMES: `clip.speed` and, on a ramped clip
/// ([`is_ramped`]), every action's [`end_speed`], whether or not the clip
/// reaches it inside [0, D). The figure `SpeedAudioDrop.peakSpeed` reads off
/// the snapshot, so the plan's ×12 test and the Speed sheet's question agree
/// on every clip, trimmed or not (spec §11 SR-19 (d)). `clip.speed` when not
/// ramped.
pub(crate) fn peak_rate(clip: &Clip) -> f64 {
    if !is_ramped(clip) {
        return clip.speed;
    }
    clip.actions
        .iter()
        .filter_map(end_speed)
        .fold(clip.speed, f64::max)
}

/// The rate the clip plays at clip time `t`: [`SpeedMap::of`]'s
/// [`SpeedMap::rate_at`] on a ramped clip (`t` clamped into `[0, D]` as it
/// clamps), `clip.speed` otherwise. `clip_state`'s `speed`, the Speed
/// section's read inside an action (spec §11 SR-21 (b)).
pub(crate) fn rate_in_force(clip: &Clip, t: Ticks) -> f64 {
    SpeedMap::of(clip).map_or(clip.speed, |map| map.rate_at(t))
}

/// Whether the clip's rate changes over its length: a `media` clip, and an
/// action whose end names a speed. False for every other source, whatever
/// its actions say.
pub(crate) fn is_ramped(clip: &Clip) -> bool {
    matches!(clip.source, Source::Media { .. })
        && clip.actions.iter().any(|a| end_speed(a).is_some())
}

/// ∫₀ᵘ ease(curve, v) dv, `u` clamped to 0..1 as `ease` clamps it — the
/// four closed forms of `actions::ease`'s polynomials.
pub(crate) fn ease_integral(curve: Curve, u: f64) -> f64 {
    let u = if u.is_nan() { 0.0 } else { u.clamp(0.0, 1.0) };
    match curve {
        Curve::Linear => u * u / 2.0,
        Curve::EaseIn => u * u * u / 3.0,
        // ∫ 1 − (1 − v)² = ∫ 2v − v².
        Curve::EaseOut => u * u - u * u * u / 3.0,
        // ∫ 3v² − 2v³.
        Curve::EaseInOut => u * u * u - u * u * u * u / 2.0,
    }
}

/// One stretch of clip time `[from, to)` over which the rate is one
/// expression: held at `rate`, or ramping along an action's curve. A ramp
/// keeps its ACTION's `start` and `duration`, because the piece may be
/// only part of it — a nest clip's tail cut ends the clip mid-action.
#[derive(Debug, Clone, PartialEq)]
pub(crate) enum Piece {
    Held {
        from: Ticks,
        to: Ticks,
        rate: f64,
    },
    Ramp {
        from: Ticks,
        to: Ticks,
        start: Ticks,
        duration: Ticks,
        curve: Curve,
        from_rate: f64,
        to_rate: f64,
    },
}

impl Piece {
    fn from(&self) -> Ticks {
        match self {
            Piece::Held { from, .. } | Piece::Ramp { from, .. } => *from,
        }
    }

    fn to(&self) -> Ticks {
        match self {
            Piece::Held { to, .. } | Piece::Ramp { to, .. } => *to,
        }
    }

    /// The rate at clip time `t`, which the caller keeps inside the piece.
    fn rate_at(&self, t: Ticks) -> f64 {
        match self {
            Piece::Held { rate, .. } => *rate,
            Piece::Ramp {
                start,
                duration,
                curve,
                from_rate,
                to_rate,
                ..
            } => {
                let u = t.saturating_sub(*start) as f64 / *duration as f64;
                from_rate + (to_rate - from_rate) * ease(*curve, u)
            }
        }
    }

    /// ∫ rate over `[from, t)`, `t` inside the piece.
    fn integral_to(&self, t: Ticks) -> f64 {
        let from = self.from();
        let span = t.saturating_sub(from) as f64;
        match self {
            Piece::Held { rate, .. } => rate * span,
            Piece::Ramp {
                start,
                duration,
                curve,
                from_rate,
                to_rate,
                ..
            } => {
                let length = *duration as f64;
                let u_from = from.saturating_sub(*start) as f64 / length;
                let u_to = t.saturating_sub(*start) as f64 / length;
                from_rate * span
                    + (to_rate - from_rate)
                        * length
                        * (ease_integral(*curve, u_to) - ease_integral(*curve, u_from))
            }
        }
    }
}

/// A ramped clip's rate profile over `[0, duration)` and its integral.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct SpeedMap {
    pieces: Vec<Piece>,
    /// S at each piece's `from`, so a reading sums no more than one piece.
    before: Vec<f64>,
    duration: Ticks,
    base: f64,
}

/// The merged-ended rate at clip time `t`: the base, then every action
/// ENDED by `t` (as `evaluate_clip` merges them: a positive duration ending
/// at or before `t`) that names a speed, in start order.
fn ended_rate(base: f64, actions: &[&Action], t: Ticks) -> f64 {
    let mut rate = base;
    for action in actions {
        let end = action.start.saturating_add(action.duration);
        if action.duration > 0 && end <= t {
            if let Some(named) = end_speed(action) {
                rate = named;
            }
        }
    }
    rate
}

/// S∞⁻¹, FLOORED: the latest clip tick t ≥ 0 at which the clip, read on
/// past its end ([`SpeedMap::of_length`]), has read no more than `source`
/// ticks of source. The map is built over a horizon of the clip's duration
/// or its last speed action's end, whichever is later, plus
/// `ceil(source / SPEED_MIN) + 1` — every rate is at least ×0.1, so S
/// passes `source` before it (saturating). `None` when
/// [`SpeedMap::of`] is.
pub(crate) fn time_for_source(clip: &Clip, source: Ticks) -> Option<Ticks> {
    let last_end = clip
        .actions
        .iter()
        .filter(|a| end_speed(a).is_some())
        .map(|a| a.start.saturating_add(a.duration))
        .fold(clip.duration, Ticks::max);
    // The cast saturates, so an absurd `source` reaches as far as a tick can.
    let reach = (source.max(0) as f64 / SPEED_MIN).ceil() as Ticks;
    let horizon = last_end.saturating_add(reach).saturating_add(1);
    let map = SpeedMap::of_length(clip, horizon)?;
    Some(map.time_at(source as f64))
}

impl SpeedMap {
    /// The clip's map, or `None` when it is not ramped ([`is_ramped`]) —
    /// so for every source but `media` — or its base speed is not a
    /// positive finite number.
    pub(crate) fn of(clip: &Clip) -> Option<SpeedMap> {
        SpeedMap::of_length(clip, clip.duration)
    }

    /// The clip's map as if it ran `duration` long; `of(clip)` is
    /// `of_length(clip, clip.duration)`. Past the clip's own end it reads
    /// on with the clip's actions (spec §11 SR-18 (a)): an action running
    /// past the end keeps ramping, otherwise the last rate holds.
    pub(crate) fn of_length(clip: &Clip, duration: Ticks) -> Option<SpeedMap> {
        if !(is_ramped(clip) && clip.speed.is_finite() && clip.speed > 0.0) {
            return None;
        }
        let base = clip.speed;
        let duration = duration.max(0);
        let actions = ordered_actions(clip);

        let mut bounds: Vec<Ticks> = vec![0, duration];
        for action in actions.iter().filter(|a| end_speed(a).is_some()) {
            let end = action.start.saturating_add(action.duration);
            bounds.push(action.start.clamp(0, duration));
            bounds.push(end.clamp(0, duration));
        }
        bounds.sort_unstable();
        bounds.dedup();

        let mut pieces = Vec::with_capacity(bounds.len());
        for pair in bounds.windows(2) {
            let (Some(&from), Some(&to)) = (pair.first(), pair.get(1)) else {
                continue;
            };
            if to <= from {
                continue;
            }
            let rate = ended_rate(base, &actions, from);
            // Every speed action's edge is a boundary, so the first action
            // spanning the piece's first tick spans the whole of it.
            let spanning = actions.iter().find(|a| spans(a, from));
            let named = spanning.and_then(|a| end_speed(a).map(|to_rate| (a, to_rate)));
            pieces.push(match named {
                // An action ending at the rate already in force changes
                // nothing: held, so it adds no segments and no glide span.
                Some((action, to_rate)) if to_rate != rate => Piece::Ramp {
                    from,
                    to,
                    start: action.start,
                    duration: action.duration,
                    curve: action.curve,
                    from_rate: rate,
                    to_rate,
                },
                _ => Piece::Held { from, to, rate },
            });
        }

        let mut before = Vec::with_capacity(pieces.len());
        let mut total = 0.0;
        for piece in &pieces {
            before.push(total);
            total += piece.integral_to(piece.to());
        }
        Some(SpeedMap {
            pieces,
            before,
            duration,
            base,
        })
    }

    /// The index of the piece holding clip time `t` (the last piece for
    /// `t` at or past the end).
    fn index_at(&self, t: Ticks) -> Option<usize> {
        if self.pieces.is_empty() {
            return None;
        }
        let found = self.pieces.iter().position(|p| t < p.to());
        Some(found.unwrap_or(self.pieces.len() - 1))
    }

    /// S(t): source ticks read by clip time `t`, `t` clamped to
    /// `[0, duration]`.
    pub(crate) fn source_at(&self, t: Ticks) -> f64 {
        let t = t.clamp(0, self.duration);
        let Some(i) = self.index_at(t) else {
            return 0.0;
        };
        match (self.pieces.get(i), self.before.get(i)) {
            (Some(piece), Some(before)) => before + piece.integral_to(t.min(piece.to())),
            _ => 0.0,
        }
    }

    /// S⁻¹(source), FLOORED: the latest clip tick whose S does not exceed
    /// `source`, in `[0, duration]`. Closed form in a held piece; a
    /// bisection over whole ticks in a ramp piece, where S is a polynomial
    /// of degree up to five in t and strictly increasing (every rate is at
    /// least ×0.1).
    pub(crate) fn time_at(&self, source: f64) -> Ticks {
        if source.is_nan() || source <= 0.0 {
            return 0;
        }
        if source >= self.source_at(self.duration) {
            return self.duration;
        }
        for (piece, before) in self.pieces.iter().zip(&self.before) {
            let after = before + piece.integral_to(piece.to());
            if source >= after {
                continue;
            }
            let (from, to) = (piece.from(), piece.to());
            return match piece {
                Piece::Held { rate, .. } => {
                    let step = ((source - before) / rate).floor();
                    let t = if step.is_finite() { step as Ticks } else { 0 };
                    from.saturating_add(t).clamp(from, to)
                }
                Piece::Ramp { .. } => {
                    let (mut lo, mut hi) = (from, to);
                    while hi - lo > 1 {
                        let mid = lo + (hi - lo) / 2;
                        if before + piece.integral_to(mid) <= source {
                            lo = mid;
                        } else {
                            hi = mid;
                        }
                    }
                    lo
                }
            };
        }
        self.duration
    }

    /// The rate at clip time `t`, `t` clamped to `[0, duration]`. A split
    /// takes the rate at the cut as the second half's base (spec §11
    /// SR-18 (e)).
    pub(crate) fn rate_at(&self, t: Ticks) -> f64 {
        let t = t.clamp(0, self.duration);
        match self.index_at(t).and_then(|i| self.pieces.get(i)) {
            Some(piece) => piece.rate_at(t.min(piece.to())),
            None => self.base,
        }
    }

    /// The end rate at which `action`, cut to end at clip time `cut`, reads
    /// by `cut` exactly the source this map reads by `cut` (spec §11 SR-18
    /// (e)): `r_from + (r_to − r_from)·E(c)/(c·E(1))`, E the action's
    /// curve's [`ease_integral`], `c = (cut − start)/duration`, `r_from`
    /// the rate at the action's start and `r_to` its end rate — R1's affine
    /// solve in closed form. Clamped to `SPEED_MIN`–`SPEED_MAX`. `None`
    /// when the action names no speed or does not straddle `cut`
    /// (`start < cut < start + duration`).
    pub(crate) fn head_end_rate(&self, action: &Action, cut: Ticks) -> Option<f64> {
        let to_rate = end_speed(action)?;
        let end = action.start.saturating_add(action.duration);
        if !(action.start < cut && cut < end) {
            return None;
        }
        let c = cut.saturating_sub(action.start) as f64 / action.duration as f64;
        let from_rate = self.rate_at(action.start);
        let whole = ease_integral(action.curve, 1.0);
        let rate = from_rate + (to_rate - from_rate) * ease_integral(action.curve, c) / (c * whole);
        rate.is_finite().then(|| rate.clamp(SPEED_MIN, SPEED_MAX))
    }

    pub(crate) fn pieces(&self) -> &[Piece] {
        &self.pieces
    }
}
