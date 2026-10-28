//! How an export override is READ and REFUSED — the vocabulary the export
//! settings resolve from, where `export_table.rs` is the table and
//! `export.rs` the resolution.
//!
//! Cut out of `export.rs` in road map 2's phase 5, and cut HERE for the
//! reason `props_check.rs` was cut out of `edit_props.rs`: a rule about
//! how a value is spelled and what makes it a refusal is a fact about the
//! VOCABULARY, not about the resolution. Nothing in this file knows which
//! preset asked, what the canvas is, or what the settings object ends up
//! looking like; everything in it answers one question — "is this JSON
//! value a legal `width` / `fps` / `range` / bitrate / decibel figure, and
//! if not, what do we tell the caller it was?".
//!
//! The cut also paid the size rule's toll. `export.rs` stood at 578 lines
//! against the ~600 soft cap and phase 5 added two containers, two preset
//! rows, a decibel validator, two override reads and two echo lines; a
//! file at the line gives something up before it takes anything on.
//!
//! Three rules hold for every reader here, and every new one must keep
//! them, because the sheet, the `export` tool and the test suite all lean
//! on them:
//!
//! 1. **Absent and explicit null are the same thing** — "use the preset".
//!    That is what lets the export sheet build one overrides object and
//!    null the fields whose control is greyed out.
//! 2. **An unknown key is ignored, silently.** A newer UI may send fields
//!    this build has never heard of and must still get an export.
//! 3. **A refusal names the offending value**, through [`describe`], and
//!    the message is lowercase and starts `export <key> must be …`. The
//!    key is in the message because a caller sending six overrides needs
//!    to know which one it was.
//!
//! [`describe`] itself is not about export at all any more: five modules
//! outside this one (`edit.rs`, `edit_props.rs`, `edit_action.rs`,
//! `edit_paste.rs`, `edit_track.rs`) name it `crate::export::describe` for
//! their own error messages, so `export.rs` re-exports it under that path
//! and the cut costs those files nothing. [`spelled`] sits beside it for
//! the same reason: a vocabulary value's own JSON spelling, for a sentence
//! (`lut.rs`, `media_color.rs`, `edit_relink.rs`).

use serde_json::Value;

use crate::dynamic_range::DynamicRange;
use crate::export_table::EncoderSpeed;
use crate::time::{Fps, Ticks};

// ---- the shared front door -----------------------------------------------

/// A JSON value as short text for an error message, truncated on a char
/// boundary so a pasted megabyte of JSON cannot become the error string.
pub(crate) fn describe(value: &Value) -> String {
    let text = value.to_string();
    if text.chars().count() <= 40 {
        text
    } else {
        format!("{} …", text.chars().take(40).collect::<String>())
    }
}

/// A vocabulary value's JSON spelling (`warm`, `video`), serde's own, so a
/// sentence names it as the file and the schema do.
pub(crate) fn spelled<T: serde::Serialize>(value: T) -> String {
    serde_json::to_value(value)
        .ok()
        .and_then(|value| value.as_str().map(str::to_string))
        .unwrap_or_default()
}

/// The overrides object itself: `None` for absent, null or an empty
/// request, `Some` for an object, and an `Err` naming the value for
/// anything else. One place, so "overrides must be a json object" is the
/// same sentence however the caller got here.
pub(crate) fn object(overrides: Option<&Value>) -> Result<Option<&Value>, String> {
    match overrides {
        None => Ok(None),
        Some(Value::Null) => Ok(None),
        Some(value) if value.is_object() => Ok(Some(value)),
        Some(value) => Err(format!(
            "export overrides must be a json object, not {}",
            describe(value)
        )),
    }
}

/// An override field, or `None` when absent or explicitly null (null means
/// "use the preset", so a caller can build one overrides object and leave
/// the fields it does not care about).
fn field<'a>(overrides: Option<&'a Value>, key: &str) -> Option<&'a Value> {
    overrides.and_then(|o| o.get(key)).filter(|v| !v.is_null())
}

// ---- numbers -------------------------------------------------------------

/// A strictly positive integer override — the pixel dimensions and the two
/// bitrates, which want the identical check. `u64::MAX` is not the ceiling
/// on purpose: a bitrate is bits per second, and `u32`'s 4.3 Gbit/s is an
/// order of magnitude past anything deliverable (ProRes 422 at 4K is about
/// 0.7), so the same bound that keeps a width sane keeps a bitrate honest.
/// Zero and negative both land in the error arm, which names the value.
pub(crate) fn positive_u32(overrides: Option<&Value>, key: &str) -> Result<Option<u32>, String> {
    let Some(value) = field(overrides, key) else {
        return Ok(None);
    };
    match value.as_u64() {
        Some(n) if n > 0 && n <= u64::from(u32::MAX) => Ok(Some(n as u32)),
        _ => Err(format!(
            "export {key} must be a positive integer, not {}",
            describe(value)
        )),
    }
}

/// A decibel override: a finite number inside `[min, max]`. The f64 twin
/// of [`positive_u32`], and a separate function because the two loudness
/// figures are NEGATIVE FRACTIONS — −14.5 LUFS is a real request — so
/// every guard `positive_u32` applies is the wrong one here.
///
/// `as_f64` is the whole type check: `serde_json` answers `None` for a
/// bool, a string, an array and an object alike, so the error arm catches
/// them all and names what arrived. Non-finite is checked even though JSON
/// cannot spell a NaN or an infinity — the function takes a `Value` from
/// whoever has one, and a bound comparison against a NaN is silently false
/// rather than an error.
fn decibels(
    overrides: Option<&Value>,
    key: &str,
    min: f64,
    max: f64,
) -> Result<Option<f64>, String> {
    let Some(value) = field(overrides, key) else {
        return Ok(None);
    };
    match value.as_f64() {
        Some(db) if db.is_finite() && db >= min && db <= max => Ok(Some(db)),
        _ => Err(format!(
            "export {key} must be a number from {min} to {max}, not {}",
            describe(value)
        )),
    }
}

/// The bottom of the loudness target's range. −70 LUFS is BS.1770-4's own
/// absolute gate: a programme quieter than that measures as nothing at
/// all, so a target at or below it is a request the measurement cannot
/// even express. The top is 0 LUFS — full scale, unwise but legal, and the
/// bound is where it is so the message is about the value.
const LOUDNESS_MIN: f64 = -70.0;
const LOUDNESS_MAX: f64 = 0.0;

/// The true-peak ceiling's range. 0 dBTP is legal (and what a master with
/// no headroom asks for); −20 is far below anything a deliverable wants
/// and exists only so a mistyped LUFS figure lands in the error arm rather
/// than turning the programme down by 60 dB.
const PEAK_MIN: f64 = -20.0;
const PEAK_MAX: f64 = 0.0;

/// The two loudness overrides, read together: `loudness_lufs`, the
/// integrated target the export is normalised to, and `peak_dbtp`, the
/// true-peak ceiling the gain is capped against.
///
/// **`peak_dbtp` without `loudness_lufs` is an `Err`.** Everywhere else in
/// this file an override that the chosen format cannot use is accepted and
/// echoed (a GIF takes an audio bitrate), because the format flags say
/// what the output can carry and one rule for reading beats two. This one
/// is not that case: a ceiling is not a thing the format cannot use, it is
/// a thing that has nothing to act on. Normalisation is gain-only with no
/// limiter, so the ceiling exists solely to cap a gain that a target
/// computed; asked for on its own it would mean "turn the programme down
/// until its peak fits", which is peak normalisation — a different feature
/// with a different sound — and the crate has no precedent for a key that
/// is accepted, echoed and silently inert.
///
/// Both are emitted by the resolver only when asked for, exactly as the
/// bitrates are: an absent `loudness_lufs` is "do not normalise", which is
/// what `ExportSettings.loudnessLufs == nil` says on the Swift side.
pub(crate) fn loudness(overrides: Option<&Value>) -> Result<(Option<f64>, Option<f64>), String> {
    let target = decibels(overrides, "loudness_lufs", LOUDNESS_MIN, LOUDNESS_MAX)?;
    let ceiling = decibels(overrides, "peak_dbtp", PEAK_MIN, PEAK_MAX)?;
    if target.is_none() && ceiling.is_some() {
        return Err(
            "export peak_dbtp needs a loudness_lufs to be the ceiling for: normalisation \
             is gain-only, so a ceiling on its own would change nothing"
                .to_string(),
        );
    }
    Ok((target, ceiling))
}

/// True or false, or `default` when the key is absent — the shape every
/// flag override wants and only `optimize_for_network` has so far.
pub(crate) fn boolean(overrides: Option<&Value>, key: &str, default: bool) -> Result<bool, String> {
    match field(overrides, key) {
        None => Ok(default),
        Some(value) => value.as_bool().ok_or_else(|| {
            format!(
                "export {key} must be true or false, not {}",
                describe(value)
            )
        }),
    }
}

/// The `dynamic_range` override (spec §11 HD-14 (c)): `hlg`, `pq` or `sdr`,
/// `None` when absent or null. Which of them a row may write is the
/// resolver's question (`Project::deliverable`); this answers only whether
/// the value is one of the three words.
pub(crate) fn dynamic_range(overrides: Option<&Value>) -> Result<Option<DynamicRange>, String> {
    let Some(value) = field(overrides, "dynamic_range") else {
        return Ok(None);
    };
    match value.as_str().and_then(DynamicRange::parse) {
        Some(range) => Ok(Some(range)),
        None => Err(format!(
            "export dynamic_range must be \"hlg\", \"pq\" or \"sdr\", not {}",
            describe(value)
        )),
    }
}

/// The `encoder_speed` override (spec §11 CX-12 (2)): `faster`, `balanced`
/// or `smaller`, `None` when absent or null. Whether the row takes one is
/// the resolver's question; this answers only whether it is one of the
/// three words, so a misspelling is refused by name on any row.
pub(crate) fn encoder_speed(overrides: Option<&Value>) -> Result<Option<EncoderSpeed>, String> {
    let Some(value) = field(overrides, "encoder_speed") else {
        return Ok(None);
    };
    match value.as_str().and_then(EncoderSpeed::parse) {
        Some(speed) => Ok(Some(speed)),
        None => Err(format!(
            "export encoder_speed must be \"faster\", \"balanced\" or \"smaller\", not {}",
            describe(value)
        )),
    }
}

// ---- compound values -----------------------------------------------------

/// The `fps` override as `[num, den]`, or `default` when it is absent.
/// Both terms are read as `u64` and bounded by `u32::MAX` because that is
/// what [`Fps`] holds, and both must be non-zero: a zero numerator is a
/// frozen export and a zero denominator is a division by nothing, and
/// either would reach the frame-snapping arithmetic before anyone noticed.
pub(crate) fn fps(overrides: Option<&Value>, default: Fps) -> Result<Fps, String> {
    let Some(value) = field(overrides, "fps") else {
        return Ok(default);
    };
    let terms = value.as_array().and_then(|a| {
        match (
            a.first().and_then(Value::as_u64),
            a.get(1).and_then(Value::as_u64),
        ) {
            (Some(num), Some(den)) if a.len() == 2 => Some((num, den)),
            _ => None,
        }
    });
    match terms {
        Some((num, den))
            if num > 0 && den > 0 && num <= u64::from(u32::MAX) && den <= u64::from(u32::MAX) =>
        {
            Ok(Fps {
                num: num as u32,
                den: den as u32,
            })
        }
        _ => Err(format!(
            "export fps must be [num, den] with non-zero terms, not {}",
            describe(value)
        )),
    }
}

/// One end of a range, in ticks.
fn ticks(value: &Value, what: &str) -> Result<Ticks, String> {
    value.as_i64().ok_or_else(|| {
        format!(
            "export {what} must be an integer number of ticks, not {}",
            describe(value)
        )
    })
}

/// The `range` override as the raw `(start, duration)` pair it asked for,
/// each falling back to its half of `default` — which is `(0, the whole
/// project)`, so `{"start": …}` alone keeps the project's length and
/// `{"duration": …}` alone keeps its start.
///
/// RAW is the word: nothing here snaps or clamps. Both are decisions about
/// a project and an export rate, which this file knows nothing about, and
/// the ORDER of the two (snap first, then clamp) is load-bearing enough to
/// stay visible where the settings are resolved.
pub(crate) fn range(
    overrides: Option<&Value>,
    default: (Ticks, Ticks),
) -> Result<(Ticks, Ticks), String> {
    let Some(range) = field(overrides, "range") else {
        return Ok(default);
    };
    if !range.is_object() {
        return Err(format!(
            "export range must be a json object with start and duration, not {}",
            describe(range)
        ));
    }
    let (mut start, mut duration) = default;
    if let Some(value) = field(Some(range), "start") {
        start = ticks(value, "range start")?;
    }
    if let Some(value) = field(Some(range), "duration") {
        duration = ticks(value, "range duration")?;
    }
    Ok((start, duration))
}
