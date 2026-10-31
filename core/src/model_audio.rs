//! The audio vocabulary of spec §5.2: [`AudioProps`], the `audio` group a
//! [`crate::model::Clip`] carries, and the [`Compressor`], [`Limiter`] and
//! [`Duck`] inside it, each over a hand-written [`Default`] that says what an absent
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
    /// The shape of `fade_in` and `fade_out` (format 29, spec §11 AU-114),
    /// each written only when not `linear`, so an older file's text holds.
    #[serde(skip_serializing_if = "FadeShape::is_linear")]
    pub fade_in_shape: FadeShape,
    #[serde(skip_serializing_if = "FadeShape::is_linear")]
    pub fade_out_shape: FadeShape,
    /// The clip's true-peak limiter (format version 30, spec §11 AU-21),
    /// last in the tap's chain; absent is off, and is not written.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub limiter: Option<Limiter>,
    /// How much of Apple's isolated voice replaces the clip's own sound,
    /// 0 off … 1 all of it (format 31, spec §11 AU-50), written only when
    /// not 0 so an older file's text holds. The render is Swift's, offline.
    #[serde(skip_serializing_if = "is_zero")]
    pub isolation: f64,
}

fn is_zero(v: &f64) -> bool {
    *v == 0.0
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
            fade_in_shape: FadeShape::Linear,
            fade_out_shape: FadeShape::Linear,
            limiter: None,
            isolation: 0.0,
        }
    }
}

/// A fade's or a crossfade's gain curve over its progress u in 0..1 (spec
/// §11 AU-114, AU-115): `linear` is `u`, `s_curve` `(1 − cos πu)/2`,
/// `plus_3db` `sin(uπ/2)` (fast start) and `minus_3db` `1 − cos(uπ/2)`
/// (slow start). The formulas are `audio_shape.rs`'s.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FadeShape {
    #[default]
    Linear,
    SCurve,
    #[serde(rename = "plus_3db")]
    Plus3Db,
    #[serde(rename = "minus_3db")]
    Minus3Db,
}

impl FadeShape {
    pub fn is_linear(&self) -> bool {
        *self == FadeShape::Linear
    }

    /// A transition's default, R5-2's constant power (spec §11 AU-115).
    pub fn is_plus_3db(&self) -> bool {
        *self == FadeShape::Plus3Db
    }
}

/// What a [`Duck`] follows (format 29, spec §11 AU-110): the ducking clip's
/// whole extent (the default and the only mode before 29), or the speech
/// spans saved on its media (`media[].speech`).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DuckMode {
    #[default]
    Extent,
    Speech,
}

impl DuckMode {
    pub fn is_extent(&self) -> bool {
        *self == DuckMode::Extent
    }
}

/// `pre_roll`'s and `hold`'s default: 0.5 s (spec §11 AU-112).
pub const DUCK_SPEECH_PAD: Ticks = 300_000;

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

/// The clip's true-peak limiter (spec §11 AU-20, AU-21): a ceiling in dBTP
/// that holds AFTER the clip's fader at its base volume (AU-22), and the
/// time its gain takes to recover. The DSP is the Swift side's, as the
/// compressor's is.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Limiter {
    /// dBTP, post-fader: −24…0.
    pub ceiling_db: f64,
    /// Ticks: 600…600 000 (1 ms…1 s).
    pub release: Ticks,
}

impl Default for Limiter {
    /// −1 dBTP (AU-4's ceiling) and a 100 ms release.
    fn default() -> Self {
        Limiter {
            ceiling_db: -1.0,
            release: TIMESCALE / 10,
        }
    }
}

/// Every other clip's envelope is multiplied by `level` over this clip's
/// extent (spec §11), with linear `attack` and `release` ramps — or, in
/// `speech` mode (AU-110, AU-112), over each of its media's speech spans
/// widened by `pre_roll` before and `hold` after. The three keys of format 29
/// are each written only when not their default, in either mode (AU-116).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Duck {
    pub level: f64,
    pub attack: Ticks,
    pub release: Ticks,
    #[serde(skip_serializing_if = "DuckMode::is_extent")]
    pub mode: DuckMode,
    #[serde(skip_serializing_if = "is_speech_pad")]
    pub pre_roll: Ticks,
    #[serde(skip_serializing_if = "is_speech_pad")]
    pub hold: Ticks,
}

fn is_speech_pad(ticks: &Ticks) -> bool {
    *ticks == DUCK_SPEECH_PAD
}

impl Default for Duck {
    /// The spec §5.2 example: down to 20 %, 0.5 s in, 1 s out.
    fn default() -> Self {
        Duck {
            level: 0.2,
            attack: 300_000,
            release: 600_000,
            mode: DuckMode::Extent,
            pre_roll: DUCK_SPEECH_PAD,
            hold: DUCK_SPEECH_PAD,
        }
    }
}
