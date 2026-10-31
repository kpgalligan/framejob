//! The bounds of a clip's EQ and hum notch (format 32, spec §11 AU-31,
//! AU-33): [`check_eq`] and [`check_hum`], which `props_check.rs`'s
//! `check_audio` runs on a direct edit and refuses in the key's own
//! sentence, and [`clamp_eq`] and [`clamp_hum`], which `actions_clamp.rs`'s
//! `clamp_audio` runs on an action's evaluated end, where there is nobody to
//! tell. The channel pick (`audio.channels`) has no bound: serde refuses a
//! word it does not know.
//!
//! The DSP is the Swift side's (`AudioBiquad.swift`, `AudioEQStage.swift`);
//! nothing here touches a sample.

use crate::model::{Equalizer, Hum};
use crate::props_check::in_range;

/// Every EQ frequency, in Hz.
pub(crate) const EQ_FREQUENCY_MIN: f64 = 20.0;
pub(crate) const EQ_FREQUENCY_MAX: f64 = 20_000.0;
/// A shelf's or a bell's gain, ± this many dB.
pub(crate) const EQ_GAIN_MAX_DB: f64 = 24.0;
/// A bell's Q.
pub(crate) const EQ_Q_MIN: f64 = 0.1;
pub(crate) const EQ_Q_MAX: f64 = 10.0;
/// How deep each hum notch cuts, in dB.
pub(crate) const HUM_DEPTH_MIN_DB: f64 = 6.0;
pub(crate) const HUM_DEPTH_MAX_DB: f64 = 60.0;
/// How many harmonics of the mains the comb takes (from 1).
pub(crate) const HUM_HARMONICS_MAX: i64 = 8;

fn frequency(slot: &str, value: f64) -> Result<(), String> {
    in_range(
        &format!("audio.eq.{slot}.frequency"),
        value,
        EQ_FREQUENCY_MIN,
        EQ_FREQUENCY_MAX,
    )
}

fn gain(slot: &str, value: f64) -> Result<(), String> {
    in_range(
        &format!("audio.eq.{slot}.gain_db"),
        value,
        -EQ_GAIN_MAX_DB,
        EQ_GAIN_MAX_DB,
    )
}

fn slope(slot: &str, value: i64) -> Result<(), String> {
    if value == 12 || value == 24 {
        Ok(())
    } else {
        Err(format!(
            "audio.eq.{slot}.slope must be 12 or 24, not {value}"
        ))
    }
}

fn band(slot: &str, frequency_hz: f64, gain_db: f64, q: f64) -> Result<(), String> {
    frequency(slot, frequency_hz)?;
    gain(slot, gain_db)?;
    in_range(&format!("audio.eq.{slot}.q"), q, EQ_Q_MIN, EQ_Q_MAX)
}

/// Each present slot's frequency, gain, Q and slope, in signal order.
pub(crate) fn check_eq(eq: &Equalizer) -> Result<(), String> {
    if let Some(pass) = &eq.high_pass {
        frequency("high_pass", pass.frequency)?;
        slope("high_pass", pass.slope)?;
    }
    if let Some(shelf) = &eq.low_shelf {
        frequency("low_shelf", shelf.frequency)?;
        gain("low_shelf", shelf.gain_db)?;
    }
    for (slot, bell) in [
        ("band_1", &eq.band_1),
        ("band_2", &eq.band_2),
        ("band_3", &eq.band_3),
    ] {
        if let Some(bell) = bell {
            band(slot, bell.frequency, bell.gain_db, bell.q)?;
        }
    }
    if let Some(shelf) = &eq.high_shelf {
        frequency("high_shelf", shelf.frequency)?;
        gain("high_shelf", shelf.gain_db)?;
    }
    if let Some(pass) = &eq.low_pass {
        frequency("low_pass", pass.frequency)?;
        slope("low_pass", pass.slope)?;
    }
    Ok(())
}

/// The mains frequency (50 or 60), the depth and the harmonic count.
pub(crate) fn check_hum(hum: &Hum) -> Result<(), String> {
    if hum.frequency != 50 && hum.frequency != 60 {
        return Err(format!(
            "audio.hum.frequency must be 50 or 60, not {}",
            hum.frequency
        ));
    }
    in_range(
        "audio.hum.depth_db",
        hum.depth_db,
        HUM_DEPTH_MIN_DB,
        HUM_DEPTH_MAX_DB,
    )?;
    if !(1..=HUM_HARMONICS_MAX).contains(&hum.harmonics) {
        return Err(format!(
            "audio.hum.harmonics must be between 1 and {HUM_HARMONICS_MAX}, not {}",
            hum.harmonics
        ));
    }
    Ok(())
}

/// A NaN to the slot's own default, every other number into its range.
fn bounded(value: f64, low: f64, high: f64, neutral: f64) -> f64 {
    if value.is_nan() {
        neutral
    } else {
        value.clamp(low, high)
    }
}

fn clamp_frequency(value: f64, neutral: f64) -> f64 {
    bounded(value, EQ_FREQUENCY_MIN, EQ_FREQUENCY_MAX, neutral)
}

fn clamp_gain(value: f64) -> f64 {
    bounded(value, -EQ_GAIN_MAX_DB, EQ_GAIN_MAX_DB, 0.0)
}

/// The nearer of the two slopes: 24 from 18 up, else 12.
fn clamp_slope(value: i64) -> i64 {
    if value >= 18 {
        24
    } else {
        12
    }
}

/// An action's evaluated EQ, every slot held to `check_eq`'s ranges.
pub(crate) fn clamp_eq(mut eq: Equalizer) -> Equalizer {
    if let Some(pass) = eq.high_pass.as_mut() {
        pass.frequency = clamp_frequency(pass.frequency, 80.0);
        pass.slope = clamp_slope(pass.slope);
    }
    if let Some(shelf) = eq.low_shelf.as_mut() {
        shelf.frequency = clamp_frequency(shelf.frequency, 100.0);
        shelf.gain_db = clamp_gain(shelf.gain_db);
    }
    for bell in [&mut eq.band_1, &mut eq.band_2, &mut eq.band_3]
        .into_iter()
        .flatten()
    {
        bell.frequency = clamp_frequency(bell.frequency, 1_000.0);
        bell.gain_db = clamp_gain(bell.gain_db);
        bell.q = bounded(bell.q, EQ_Q_MIN, EQ_Q_MAX, 1.0);
    }
    if let Some(shelf) = eq.high_shelf.as_mut() {
        shelf.frequency = clamp_frequency(shelf.frequency, 8_000.0);
        shelf.gain_db = clamp_gain(shelf.gain_db);
    }
    if let Some(pass) = eq.low_pass.as_mut() {
        pass.frequency = clamp_frequency(pass.frequency, 12_000.0);
        pass.slope = clamp_slope(pass.slope);
    }
    eq
}

/// An action's evaluated hum: the nearer mains (60 from 55 up, else 50), the
/// depth and the harmonic count held to `check_hum`'s ranges.
pub(crate) fn clamp_hum(mut hum: Hum) -> Hum {
    hum.frequency = if hum.frequency >= 55 { 60 } else { 50 };
    hum.depth_db = bounded(hum.depth_db, HUM_DEPTH_MIN_DB, HUM_DEPTH_MAX_DB, 30.0);
    hum.harmonics = hum.harmonics.clamp(1, HUM_HARMONICS_MAX);
    hum
}
