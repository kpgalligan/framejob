//! The audio vocabulary of spec §5.2: [`AudioProps`], the `audio` group a
//! [`crate::model::Clip`] carries, and the [`Compressor`], [`Limiter`],
//! [`Duck`], [`Equalizer`] (with its slots [`HighPass`], [`LowShelf`],
//! [`EqBand`], [`HighShelf`] and [`LowPass`]), [`Hum`] and [`AudioChannels`]
//! inside it, and the [`Gate`] and [`DeEsser`], each over a hand-written
//! [`Default`] that says what an absent key means, and the [`Voice`]
//! (format 34, AU-140), whose kind has none, and the [`Leveller`] (format
//! 37, AU-66). The EQ's, the hum's and the
//! channel pick's bounds are `audio_eq.rs`'s (format 32, spec §11 AU-31,
//! AU-33, AU-34); the gate's, the de-esser's and the leveller's
//! `audio_dynamics.rs`'s (format 33, AU-43, AU-45; format 37, AU-66).
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
    /// The clip's EQ (format 32, spec §11 AU-31): named slots, so the group
    /// stays `Copy` and a patch merges per slot; absent is off.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub eq: Option<Equalizer>,
    /// The hum notch comb (format 32, spec §11 AU-33); absent is off.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hum: Option<Hum>,
    /// Which of a stereo source's channels plays (format 32, spec §11
    /// AU-34), written only when not `both`.
    #[serde(skip_serializing_if = "AudioChannels::is_both")]
    pub channels: AudioChannels,
    /// The downward expander/gate (format 33, spec §11 AU-43); absent is off.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gate: Option<Gate>,
    /// The split-band de-esser (format 33, spec §11 AU-45); absent is off.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub de_esser: Option<DeEsser>,
    /// The clip's voice effect (format 34, spec §11 AU-140), rendered
    /// offline by Swift; absent is off, and is not written.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub voice: Option<Voice>,
    /// The look-ahead leveller (format 37, spec §11 AU-66); absent is off.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub leveller: Option<Leveller>,
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
            eq: None,
            hum: None,
            channels: AudioChannels::Both,
            gate: None,
            de_esser: None,
            voice: None,
            leveller: None,
        }
    }
}

/// A fade's or a crossfade's gain curve over its progress u in 0..1 (spec
/// §11 AU-114, AU-115): `linear` is `u`, `s_curve` `(1 − cos πu)/2`,
/// `plus_3db` `sin(uπ/2)` (fastest near silence) and `minus_3db`
/// `1 − cos(uπ/2)` (fastest near full level). The formulas are `audio_shape.rs`'s.
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

/// The clip's EQ (spec §11 AU-31): seven named slots in signal order, each
/// absent when off, and `bypass`, which keeps the settings and silences
/// them. Each slot is written only when set, `bypass` only when true.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Equalizer {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub high_pass: Option<HighPass>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub low_shelf: Option<LowShelf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub band_1: Option<EqBand>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub band_2: Option<EqBand>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub band_3: Option<EqBand>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub high_shelf: Option<HighShelf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub low_pass: Option<LowPass>,
    #[serde(skip_serializing_if = "is_false")]
    pub bypass: bool,
}

fn is_false(value: &bool) -> bool {
    !*value
}

impl Default for Equalizer {
    /// Every slot off, not bypassed.
    fn default() -> Self {
        Equalizer {
            high_pass: None,
            low_shelf: None,
            band_1: None,
            band_2: None,
            band_3: None,
            high_shelf: None,
            low_pass: None,
            bypass: false,
        }
    }
}

/// A Butterworth high-pass: `frequency` in Hz, `slope` 12 or 24 dB/octave.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct HighPass {
    pub frequency: f64,
    pub slope: i64,
}

impl Default for HighPass {
    /// 80 Hz at 12 dB/octave.
    fn default() -> Self {
        HighPass {
            frequency: 80.0,
            slope: 12,
        }
    }
}

/// A Butterworth low-pass: `frequency` in Hz, `slope` 12 or 24 dB/octave.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct LowPass {
    pub frequency: f64,
    pub slope: i64,
}

impl Default for LowPass {
    /// 12 kHz at 12 dB/octave.
    fn default() -> Self {
        LowPass {
            frequency: 12_000.0,
            slope: 12,
        }
    }
}

/// An RBJ low shelf (S = 1): its corner in Hz and its gain in dB.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct LowShelf {
    pub frequency: f64,
    pub gain_db: f64,
}

impl Default for LowShelf {
    /// 100 Hz, flat.
    fn default() -> Self {
        LowShelf {
            frequency: 100.0,
            gain_db: 0.0,
        }
    }
}

/// An RBJ high shelf (S = 1): its corner in Hz and its gain in dB.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct HighShelf {
    pub frequency: f64,
    pub gain_db: f64,
}

impl Default for HighShelf {
    /// 8 kHz, flat.
    fn default() -> Self {
        HighShelf {
            frequency: 8_000.0,
            gain_db: 0.0,
        }
    }
}

/// An RBJ peaking bell: its centre in Hz, its gain in dB and its Q.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct EqBand {
    pub frequency: f64,
    pub gain_db: f64,
    pub q: f64,
}

impl Default for EqBand {
    /// 1 kHz, flat, Q 1.
    fn default() -> Self {
        EqBand {
            frequency: 1_000.0,
            gain_db: 0.0,
            q: 1.0,
        }
    }
}

/// The hum notch comb (spec §11 AU-33): the mains `frequency` (50 or 60
/// Hz), how deep each notch cuts in dB, and how many harmonics (1…8) it
/// takes.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Hum {
    pub frequency: i64,
    pub depth_db: f64,
    pub harmonics: i64,
}

impl Default for Hum {
    /// 60 Hz mains, 30 dB deep, four harmonics.
    fn default() -> Self {
        Hum {
            frequency: 60,
            depth_db: 30.0,
            harmonics: 4,
        }
    }
}

/// Which channels of a stereo source play (spec §11 AU-34): `left` and
/// `right` copy that channel into every channel, `swapped` exchanges them.
/// A one-channel track ignores it, as it does pan.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AudioChannels {
    #[default]
    Both,
    Left,
    Right,
    Swapped,
}

impl AudioChannels {
    pub fn is_both(&self) -> bool {
        *self == AudioChannels::Both
    }
}

/// The downward expander/gate (spec §11 AU-40, AU-43): below
/// `threshold_db` (dB relative to the clip's measured loudness, AU-41) the
/// level is pushed down by `ratio − 1` dB per dB under, never more than
/// `range_db`; `hold` keeps it open after the level falls, `attack` opens it
/// and `release` closes it. The DSP is the Swift side's.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Gate {
    /// dB re the clip's loudness: −40…0.
    pub threshold_db: f64,
    /// 1…20.
    pub ratio: f64,
    /// dB, 1…80: the most the gate takes away.
    pub range_db: f64,
    /// Ticks: 0…60 000 (100 ms).
    pub attack: Ticks,
    /// Ticks: 0…300 000 (500 ms).
    pub hold: Ticks,
    /// Ticks: 600…1 200 000 (1 ms…2 s).
    pub release: Ticks,
}

impl Default for Gate {
    /// 10 dB under the clip's loudness, 4:1, 20 dB deep, 1 ms to open, held
    /// 50 ms, 100 ms to close.
    fn default() -> Self {
        Gate {
            threshold_db: -10.0,
            ratio: 4.0,
            range_db: 20.0,
            attack: 600,
            hold: 30_000,
            release: 60_000,
        }
    }
}

/// The split-band de-esser (spec §11 AU-44, AU-45): the band above
/// `frequency` is turned down by as much as its sidechain passes
/// `threshold_db` (dB relative to the clip's loudness), never more than
/// `range_db`. The DSP is the Swift side's.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct DeEsser {
    /// Hz, 2 000…12 000: the crossover and the sidechain's cut.
    pub frequency: f64,
    /// dB re the clip's loudness: −30…+20.
    pub threshold_db: f64,
    /// dB, 1…24.
    pub range_db: f64,
}

impl Default for DeEsser {
    /// 6 kHz, at the clip's loudness, 6 dB deep.
    fn default() -> Self {
        DeEsser {
            frequency: 6_000.0,
            threshold_db: 0.0,
            range_db: 6.0,
        }
    }
}

/// The leveller (spec §11 AU-66): a gain curve made ahead of time from the
/// clip's measured loudness and its speech, smoothed both ways over
/// `response`, bringing each phrase to `target_db` re the clip's loudness,
/// never more than `max_up_db` up or `max_down_db` down; pauses hold. Bounds
/// are `audio_dynamics.rs`'s; the curve and the DSP are the Swift side's.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Leveller {
    /// dB re the clip's loudness: −20…10.
    pub target_db: f64,
    /// dB, 0…24.
    pub max_up_db: f64,
    /// dB, 0…24.
    pub max_down_db: f64,
    /// Ticks: 300 000…6 000 000 (0.5…10 s).
    pub response: Ticks,
}

impl Default for Leveller {
    /// At the loudness, 12 dB either way, 2 s.
    fn default() -> Self {
        Leveller {
            target_db: 0.0,
            max_up_db: 12.0,
            max_down_db: 12.0,
            response: 1_200_000,
        }
    }
}

/// The amount a voice takes when a patch names only its kind: all of it
/// (spec §11 AU-140), as a look's does.
pub const VOICE_DEFAULT_AMOUNT: f64 = 1.0;

fn default_voice_amount() -> f64 {
    VOICE_DEFAULT_AMOUNT
}

/// The sixteen voice effects (spec §11 AU-140), in E8's order and groups —
/// voice: pitch, high, deep, robot; tone: bass, treble, bright, telephone,
/// radio; character: lofi, distorted; space: echo, room, hall, plate,
/// cathedral. Append, never reorder: the spelling is persisted, and the
/// order is the popup's.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VoiceKind {
    Pitch,
    High,
    Deep,
    Robot,
    Bass,
    Treble,
    Bright,
    Telephone,
    Radio,
    Lofi,
    Distorted,
    Echo,
    Room,
    Hall,
    Plate,
    Cathedral,
}

/// A clip's voice effect: which, how much (0…1) and, for `pitch`, `high`
/// and `deep`, the shift in semitones (−12…12; absent is the kind's own).
/// `kind` has NO default, as `video.look`'s has none, so a voice patch
/// naming only an amount over a clip with no voice is refused. The chains
/// are Swift's (`VoiceChain.swift`).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Voice {
    pub kind: VoiceKind,
    #[serde(default = "default_voice_amount")]
    pub amount: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pitch: Option<f64>,
}
