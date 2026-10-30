//! The audio vocabulary of spec §5.2: [`AudioProps`], the `audio` group a
//! [`crate::model::Clip`] carries, and the [`Compressor`] and [`Duck`]
//! inside it, each over a hand-written [`Default`] that says what an absent
//! key means.
//!
//! A pure move out of `model_props.rs` (its audio section, whole) for road
//! map "audio" AP0, before the phases that add audio keys, so the audio
//! group can grow without `model_props.rs` paying for it. Re-exported whole
//! by `model_props.rs`, which `model.rs` re-exports whole in turn, so
//! `crate::model::AudioProps`, `crate::model::Compressor` and
//! `crate::model::Duck` resolve as they always have. The rules are
//! `model_props.rs`'s: the field names ARE the JSON keys, declaration order
//! IS key order, and nothing here carries `deny_unknown_fields`.

use serde::{Deserialize, Serialize};

use crate::time::{Ticks, TIMESCALE};

// ---- audio properties ----------------------------------------------------

/// `volume` is a linear gain and may exceed 1, up to 32 (spec §5.2, §11 AU-1).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct AudioProps {
    pub volume: f64,
    pub muted: bool,
    pub fade_in: Ticks,
    pub fade_out: Ticks,
    pub duck: Option<Duck>,
    pub mono: bool,
    /// Preserve pitch when the clip's speed is not 1.
    pub keep_pitch: bool,
    /// -1 hard left, 0 centred, +1 hard right.
    pub pan: f64,
    pub compressor: Option<Compressor>,
    /// How much background noise to remove: 0 is off, 1 the most the
    /// platform will do.
    pub noise_reduction: f64,
}

impl Default for AudioProps {
    fn default() -> Self {
        AudioProps {
            volume: 1.0,
            muted: false,
            fade_in: 0,
            fade_out: 0,
            duck: None,
            mono: false,
            keep_pitch: true,
            pan: 0.0,
            compressor: None,
            noise_reduction: 0.0,
        }
    }
}

/// "Smooth volume levels" (spec §4.3): a downward compressor over the
/// clip's own samples.
///
/// Unlike [`Duck`], which the core resolves into ramps on OTHER clips'
/// envelopes, this one cannot be expressed as a gain curve — it depends on
/// the samples — so the model carries the parameters and the DSP happens on
/// the Swift side. The units are the ones an audio engineer types:
/// dBFS for the threshold and the makeup, a plain ratio for the knee, and
/// ticks for the two time constants like every other time in the schema.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Compressor {
    /// dBFS above which gain reduction starts.
    pub threshold_db: f64,
    /// N:1 — 1 is no compression at all, 20 is effectively a limiter.
    pub ratio: f64,
    pub attack: Ticks,
    pub release: Ticks,
    /// dB of gain applied after compression, to win back what it took.
    pub makeup_db: f64,
}

impl Default for Compressor {
    /// A gentle speech setting: 3:1 above -18 dBFS, fast enough to catch a
    /// consonant (10 ms) and slow enough not to pump (200 ms).
    fn default() -> Self {
        Compressor {
            threshold_db: -18.0,
            ratio: 3.0,
            attack: TIMESCALE / 100,
            release: TIMESCALE / 5,
            makeup_db: 0.0,
        }
    }
}

/// Ducking is by clip extent, not voice activity (spec §11): every other
/// clip's envelope is multiplied by `level` over this clip's extent, with
/// linear `attack` and `release` ramps.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Duck {
    pub level: f64,
    pub attack: Ticks,
    pub release: Ticks,
}

impl Default for Duck {
    /// The spec §5.2 example: down to 20 %, 0.5 s in, 1 s out.
    fn default() -> Self {
        Duck {
            level: 0.2,
            attack: 300_000,
            release: 600_000,
        }
    }
}
