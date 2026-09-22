//! Time: the tick timeline, frame rates, frame snapping, and timecode.
//!
//! Every time in the model is an integer [`Ticks`] at [`TIMESCALE`] per
//! second. 600 000 was chosen because it divides every common frame
//! duration exactly — 24, 25, 30, 48, 50, 60, 120 fps and the /1001 rates
//! (a 30000/1001 frame is 20 020 ticks, a 24000/1001 frame 25 025) — and
//! because `CMTime` at that timescale round-trips without loss.
//!
//! Not every conceivable rate divides exactly, so the snapping math here is
//! written rationally rather than as "multiples of a frame duration": frame
//! boundaries are computed as `t * num / (TIMESCALE * den)` rounded, then
//! mapped back. That is exact for the rates above and still correct (to
//! within a tick, i.e. 1.67 µs) for any other rate a source might carry.
//!
//! This module is the ONE home of tick arithmetic. Nothing else in the
//! crate may re-derive a frame boundary or format a timecode.

use serde::{Deserialize, Serialize};

/// The project's time unit: signed so deltas and out-of-range drags are
/// representable, 64-bit so the timeline cannot realistically overflow
/// (i64::MAX ticks is ~487 000 years).
pub type Ticks = i64;

/// Ticks per second. Mirrored by `RC_TIMESCALE` in the C header.
pub const TIMESCALE: i64 = 600_000;

/// A frame rate as an exact rational, serialized as the two-element array
/// `[num, den]` the spec uses everywhere (`[30, 1]`, `[30000, 1001]`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(from = "[u32; 2]", into = "[u32; 2]")]
pub struct Fps {
    pub num: u32,
    pub den: u32,
}

impl From<[u32; 2]> for Fps {
    fn from(pair: [u32; 2]) -> Self {
        Fps {
            num: pair[0],
            den: pair[1],
        }
    }
}

impl From<Fps> for [u32; 2] {
    fn from(fps: Fps) -> Self {
        [fps.num, fps.den]
    }
}

impl Default for Fps {
    /// 30 fps — the document default, and the rate a hand-written project
    /// JSON gets when it omits the canvas rate.
    fn default() -> Self {
        Fps { num: 30, den: 1 }
    }
}

impl Fps {
    /// A rate is usable only when both terms are non-zero; a zero term is
    /// the "degenerate rate" the header's contracts talk about.
    pub fn is_valid(self) -> bool {
        self.num != 0 && self.den != 0
    }

    /// The rate as a float, for UI display and speed math. 0.0 when
    /// degenerate, which callers must not divide by.
    pub fn as_f64(self) -> f64 {
        if self.is_valid() {
            f64::from(self.num) / f64::from(self.den)
        } else {
            0.0
        }
    }

    /// The integer frame count per timecode second used by NON-DROP
    /// timecode: `ceil(num/den)`, so 30000/1001 counts 00..29 and
    /// 24000/1001 counts 00..23. Non-drop deliberately drifts from wall
    /// clock; that drift is the definition, not a bug. `None` for a
    /// degenerate rate.
    pub fn nominal(self) -> Option<i64> {
        if !self.is_valid() {
            return None;
        }
        let num = i64::from(self.num);
        let den = i64::from(self.den);
        // Ceiling division without floats, so 29.97 -> 30 exactly.
        let n = (num + den - 1) / den;
        if n <= 0 {
            None
        } else {
            Some(n)
        }
    }
}

// ---- rational helpers ----------------------------------------------------

/// `n / d` rounded half AWAY from zero, with `d > 0`. Done in i128 so the
/// intermediate products below (a full-range tick times a full-range u32)
/// cannot overflow; i128 has ~38 digits against a worst case of ~35.
fn div_round_half_away(n: i128, d: i128) -> i128 {
    if d <= 0 {
        return 0;
    }
    if n >= 0 {
        (2 * n + d) / (2 * d)
    } else {
        -((-2 * n + d) / (2 * d))
    }
}

/// Saturating i128 -> i64, so tick math never panics on an absurd input.
fn clamp_ticks(v: i128) -> Ticks {
    if v > i64::MAX as i128 {
        i64::MAX
    } else if v < i64::MIN as i128 {
        i64::MIN
    } else {
        v as i64
    }
}

// ---- frame grid ----------------------------------------------------------

/// Ticks in one frame at `fps`, or `None` when the rate is degenerate OR
/// does not divide the timescale exactly. Callers that need a boundary for
/// an inexact rate use [`snap_to_frame`] / [`tick_at_frame`] instead, which
/// round rationally.
pub fn frame_duration(fps: Fps) -> Option<Ticks> {
    if !fps.is_valid() {
        return None;
    }
    let numer = TIMESCALE as i128 * i128::from(fps.den);
    let denom = i128::from(fps.num);
    if numer % denom != 0 {
        return None;
    }
    Some(clamp_ticks(numer / denom))
}

/// The index of the frame nearest `t` (0 = the frame starting at tick 0).
/// Negative for negative times. `None` for a degenerate rate.
pub fn frame_index(t: Ticks, fps: Fps) -> Option<i64> {
    frame_index_wide(t, fps).map(clamp_ticks)
}

fn frame_index_wide(t: Ticks, fps: Fps) -> Option<i128> {
    if !fps.is_valid() {
        return None;
    }
    // t seconds = t / TIMESCALE; frames = seconds * num/den.
    let numer = i128::from(t) * i128::from(fps.num);
    let denom = TIMESCALE as i128 * i128::from(fps.den);
    Some(div_round_half_away(numer, denom))
}

/// The tick at which frame `index` begins. Inverse of [`frame_index`] up to
/// a tick of rounding for rates that do not divide the timescale exactly.
/// `None` for a degenerate rate.
pub fn tick_at_frame(index: i64, fps: Fps) -> Option<Ticks> {
    tick_at_frame_wide(i128::from(index), fps)
}

fn tick_at_frame_wide(index: i128, fps: Fps) -> Option<Ticks> {
    if !fps.is_valid() {
        return None;
    }
    let numer = index * TIMESCALE as i128 * i128::from(fps.den);
    let denom = i128::from(fps.num);
    Some(clamp_ticks(div_round_half_away(numer, denom)))
}

/// Rounds `t` to the NEAREST frame boundary of `fps`, half away from zero,
/// and returns `t` unchanged for a degenerate rate. Every tick that reaches
/// the model goes through here first: the model never stores a sub-frame
/// time.
pub fn snap_to_frame(t: Ticks, fps: Fps) -> Ticks {
    match frame_index_wide(t, fps).and_then(|index| tick_at_frame_wide(index, fps)) {
        Some(snapped) => snapped,
        None => t,
    }
}

/// The first frame boundary at or after `t` — [`snap_to_frame`] rounded
/// UP rather than to the nearest.
///
/// A clamp BOUND cannot be rounded to the nearest frame the way a value
/// can: rounding a lower bound down would let a caller land a frame outside
/// what the bound was protecting. The two directional forms exist for
/// exactly that, and `roll` is their first caller — its bounds come from
/// floored source measurements and are not on the grid.
pub fn snap_up_to_frame(t: Ticks, fps: Fps) -> Ticks {
    let nearest = snap_to_frame(t, fps);
    if nearest >= t {
        return nearest;
    }
    match frame_index_wide(t, fps).and_then(|index| tick_at_frame_wide(index + 1, fps)) {
        Some(next) => next,
        None => t,
    }
}

/// The last frame boundary at or before `t` — the mirror of
/// [`snap_up_to_frame`], for an upper bound.
pub fn snap_down_to_frame(t: Ticks, fps: Fps) -> Ticks {
    let nearest = snap_to_frame(t, fps);
    if nearest <= t {
        return nearest;
    }
    match frame_index_wide(t, fps).and_then(|index| tick_at_frame_wide(index - 1, fps)) {
        Some(previous) => previous,
        None => t,
    }
}

// ---- seconds -------------------------------------------------------------

/// Seconds to ticks, rounded. A NaN or out-of-range input saturates rather
/// than panicking (Rust's float-to-int casts are saturating, NaN -> 0).
pub fn seconds_to_ticks(s: f64) -> Ticks {
    (s * TIMESCALE as f64).round() as Ticks
}

/// Ticks to seconds. Exact for any tick count under 2^53.
pub fn ticks_to_seconds(t: Ticks) -> f64 {
    t as f64 / TIMESCALE as f64
}

// ---- timecode ------------------------------------------------------------

/// Non-drop timecode: `"HH:MM:SS:FF"` when `frames`, else
/// `"HH:MM:SS.mmm"`. Negative times get a leading `-`. Hours are not
/// wrapped — a 100-hour timeline prints `100:00:00:00`. A degenerate rate
/// falls back to the milliseconds form, which does not need a rate.
///
/// The sign comes from the ROUNDED reading, not from `t` itself. Both
/// forms quantize — to a frame, or to a millisecond — and a tick inside
/// the first half of the unit below zero rounds to a reading of all
/// zeroes. Taking the sign from `t` would print `-00:00:00:00` in the
/// toolbar's timecode field: a minus sign on a zero, and a string that
/// parses back to 0 rather than to itself.
pub fn format_timecode(t: Ticks, fps: Fps, frames: bool) -> String {
    // unsigned_abs avoids the i64::MIN negation overflow.
    let magnitude = i128::from(t.unsigned_abs());
    let sign_of = |reading: i128| if t < 0 && reading != 0 { "-" } else { "" };

    if frames {
        if let (Some(nominal), Some(index)) =
            (fps.nominal(), frame_index(clamp_ticks(magnitude), fps))
        {
            let sign = sign_of(i128::from(index));
            let ff = index % nominal;
            let total_seconds = index / nominal;
            let ss = total_seconds % 60;
            let mm = (total_seconds / 60) % 60;
            let hh = total_seconds / 3600;
            return format!("{sign}{hh:02}:{mm:02}:{ss:02}:{ff:02}");
        }
    }

    // TIMESCALE / 1000 = 600 ticks per millisecond, exactly. Rounding
    // before the split lets a carry (999.6 ms) roll into the seconds.
    let total_ms = div_round_half_away(magnitude, TIMESCALE as i128 / 1000);
    let sign = sign_of(total_ms);
    let ms = total_ms % 1000;
    let total_seconds = total_ms / 1000;
    let ss = total_seconds % 60;
    let mm = (total_seconds / 60) % 60;
    let hh = total_seconds / 3600;
    format!("{sign}{hh:02}:{mm:02}:{ss:02}.{ms:03}")
}

/// Parses `"HH:MM:SS:FF"`, `"HH:MM:SS.mmm"`, `"HH:MM:SS"`, `"MM:SS"`,
/// `"SS.sss"` and a bare number of seconds, with an optional leading `-`.
/// The result is snapped to the frame grid. `None` when the text is not a
/// time (which is how the toolbar's timecode field rejects typing).
pub fn parse_timecode(s: &str, fps: Fps) -> Option<Ticks> {
    let text = s.trim();
    let (negative, body) = match text.strip_prefix('-') {
        Some(rest) => (true, rest.trim_start()),
        None => (false, text),
    };
    if body.is_empty() {
        return None;
    }

    let parts: Vec<&str> = body.split(':').collect();
    if parts.len() > 4 || parts.iter().any(|part| part.is_empty()) {
        return None;
    }

    let ticks: i128 = match parts.as_slice() {
        // Frames form. Only the last field may name frames, and none of the
        // fields may carry a fraction — "00:00:01:12.5" is not a timecode.
        [hh, mm, ss, ff] => {
            let nominal = fps.nominal()?;
            let hours = parse_digits(hh)?;
            let minutes = parse_digits(mm)?;
            let seconds = parse_digits(ss)?;
            let frames = parse_digits(ff)?;
            let whole = hours
                .checked_mul(3600)?
                .checked_add(minutes.checked_mul(60)?)?;
            let index = whole
                .checked_add(seconds)?
                .checked_mul(i128::from(nominal))?;
            let index = index.checked_add(frames)?;
            i128::from(tick_at_frame(clamp_ticks(index), fps)?)
        }
        [hh, mm, ss] => {
            let hours = parse_digits(hh)?;
            let minutes = parse_digits(mm)?;
            hours
                .checked_mul(3600 * TIMESCALE as i128)?
                .checked_add(minutes.checked_mul(60 * TIMESCALE as i128)?)?
                .checked_add(seconds_field_to_ticks(ss)?)?
        }
        [mm, ss] => {
            let minutes = parse_digits(mm)?;
            minutes
                .checked_mul(60 * TIMESCALE as i128)?
                .checked_add(seconds_field_to_ticks(ss)?)?
        }
        [ss] => seconds_field_to_ticks(ss)?,
        _ => return None,
    };

    let signed = if negative { -ticks } else { ticks };
    Some(snap_to_frame(clamp_ticks(signed), fps))
}

/// A run of ASCII digits as an i128. Rejects signs, spaces and separators,
/// so `parse` cannot quietly accept `"+3"` or `"1e3"`.
fn parse_digits(s: &str) -> Option<i128> {
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse::<i128>().ok()
}

/// `"SS"` or `"SS.sss"` as ticks. The fraction is scaled by an exact power
/// of ten rather than parsed as a float, so `"0.1"` is 60 000 ticks and not
/// 59 999.999…; digits past the ninth are dropped because one tick is
/// already 1.67 µs.
fn seconds_field_to_ticks(field: &str) -> Option<i128> {
    let (whole, fraction) = match field.split_once('.') {
        Some((w, f)) => (w, f),
        None => (field, ""),
    };
    if whole.is_empty() && fraction.is_empty() {
        return None;
    }
    let mut ticks = if whole.is_empty() {
        0
    } else {
        parse_digits(whole)?.checked_mul(TIMESCALE as i128)?
    };
    if !fraction.is_empty() {
        if !fraction.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        // Safe to slice by bytes: every byte was just checked ASCII.
        let digits = &fraction[..fraction.len().min(9)];
        let value = parse_digits(digits)?;
        let scale = 10i128.checked_pow(digits.len() as u32)?;
        ticks = ticks.checked_add(div_round_half_away(value * TIMESCALE as i128, scale))?;
    }
    Some(ticks)
}
