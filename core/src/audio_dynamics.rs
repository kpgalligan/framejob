//! The bounds of a clip's gate and de-esser (format 33, spec §11 AU-43,
//! AU-45): [`check_gate`] and [`check_de_esser`], which `props_check.rs`'s
//! `check_audio` runs on a direct edit and refuses in the key's own
//! sentence, and [`clamp_gate`] and [`clamp_de_esser`], which
//! `actions_clamp.rs`'s `clamp_audio` runs on an action's evaluated end,
//! where there is nobody to tell.
//!
//! Both thresholds are dB relative to the clip's measured loudness (AU-41),
//! which only the Swift side knows; the DSP is Swift's too
//! (`AudioGateStage.swift`, `AudioDeEsserStage.swift`). Nothing here touches
//! a sample.

use crate::model::{DeEsser, Gate};
use crate::props_check::{in_range, ticks_in_range};
use crate::time::Ticks;

/// The gate's threshold, dB re the clip's loudness, up to 0.
pub(crate) const GATE_THRESHOLD_MIN_DB: f64 = -40.0;
/// The gate's ratio, from 1.
pub(crate) const GATE_RATIO_MAX: f64 = 20.0;
/// The most the gate takes away, in dB.
pub(crate) const GATE_RANGE_MIN_DB: f64 = 1.0;
pub(crate) const GATE_RANGE_MAX_DB: f64 = 80.0;
/// The gate's times, in ticks: attack from 0 (100 ms), hold from 0
/// (500 ms), release 1 ms…2 s.
pub(crate) const GATE_ATTACK_MAX: Ticks = 60_000;
pub(crate) const GATE_HOLD_MAX: Ticks = 300_000;
pub(crate) const GATE_RELEASE_MIN: Ticks = 600;
pub(crate) const GATE_RELEASE_MAX: Ticks = 1_200_000;
/// The de-esser's crossover and sidechain cut, in Hz.
pub(crate) const DE_ESSER_FREQUENCY_MIN: f64 = 2_000.0;
pub(crate) const DE_ESSER_FREQUENCY_MAX: f64 = 12_000.0;
/// The de-esser's threshold, dB re the clip's loudness.
pub(crate) const DE_ESSER_THRESHOLD_MIN_DB: f64 = -30.0;
pub(crate) const DE_ESSER_THRESHOLD_MAX_DB: f64 = 20.0;
/// The most the de-esser takes from the band, in dB.
pub(crate) const DE_ESSER_RANGE_MIN_DB: f64 = 1.0;
pub(crate) const DE_ESSER_RANGE_MAX_DB: f64 = 24.0;

/// Each of the gate's six fields, in declaration order.
pub(crate) fn check_gate(g: &Gate) -> Result<(), String> {
    in_range(
        "audio.gate.threshold_db",
        g.threshold_db,
        GATE_THRESHOLD_MIN_DB,
        0.0,
    )?;
    in_range("audio.gate.ratio", g.ratio, 1.0, GATE_RATIO_MAX)?;
    in_range(
        "audio.gate.range_db",
        g.range_db,
        GATE_RANGE_MIN_DB,
        GATE_RANGE_MAX_DB,
    )?;
    ticks_in_range("audio.gate.attack", g.attack, 0, GATE_ATTACK_MAX)?;
    ticks_in_range("audio.gate.hold", g.hold, 0, GATE_HOLD_MAX)?;
    ticks_in_range(
        "audio.gate.release",
        g.release,
        GATE_RELEASE_MIN,
        GATE_RELEASE_MAX,
    )
}

/// The de-esser's frequency, threshold and range.
pub(crate) fn check_de_esser(d: &DeEsser) -> Result<(), String> {
    in_range(
        "audio.de_esser.frequency",
        d.frequency,
        DE_ESSER_FREQUENCY_MIN,
        DE_ESSER_FREQUENCY_MAX,
    )?;
    in_range(
        "audio.de_esser.threshold_db",
        d.threshold_db,
        DE_ESSER_THRESHOLD_MIN_DB,
        DE_ESSER_THRESHOLD_MAX_DB,
    )?;
    in_range(
        "audio.de_esser.range_db",
        d.range_db,
        DE_ESSER_RANGE_MIN_DB,
        DE_ESSER_RANGE_MAX_DB,
    )
}

/// A NaN to the field's own default, every other number into its range.
fn bounded(value: f64, low: f64, high: f64, neutral: f64) -> f64 {
    if value.is_nan() {
        neutral
    } else {
        value.clamp(low, high)
    }
}

/// An action's evaluated gate, every field held to `check_gate`'s ranges.
pub(crate) fn clamp_gate(mut g: Gate) -> Gate {
    let neutral = Gate::default();
    g.threshold_db = bounded(
        g.threshold_db,
        GATE_THRESHOLD_MIN_DB,
        0.0,
        neutral.threshold_db,
    );
    g.ratio = bounded(g.ratio, 1.0, GATE_RATIO_MAX, neutral.ratio);
    g.range_db = bounded(
        g.range_db,
        GATE_RANGE_MIN_DB,
        GATE_RANGE_MAX_DB,
        neutral.range_db,
    );
    g.attack = g.attack.clamp(0, GATE_ATTACK_MAX);
    g.hold = g.hold.clamp(0, GATE_HOLD_MAX);
    g.release = g.release.clamp(GATE_RELEASE_MIN, GATE_RELEASE_MAX);
    g
}

/// An action's evaluated de-esser, every field held to `check_de_esser`'s
/// ranges.
pub(crate) fn clamp_de_esser(mut d: DeEsser) -> DeEsser {
    let neutral = DeEsser::default();
    d.frequency = bounded(
        d.frequency,
        DE_ESSER_FREQUENCY_MIN,
        DE_ESSER_FREQUENCY_MAX,
        neutral.frequency,
    );
    d.threshold_db = bounded(
        d.threshold_db,
        DE_ESSER_THRESHOLD_MIN_DB,
        DE_ESSER_THRESHOLD_MAX_DB,
        neutral.threshold_db,
    );
    d.range_db = bounded(
        d.range_db,
        DE_ESSER_RANGE_MIN_DB,
        DE_ESSER_RANGE_MAX_DB,
        neutral.range_db,
    );
    d
}
