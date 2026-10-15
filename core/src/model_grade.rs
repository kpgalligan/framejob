//! Tier 2's grading vocabulary (format 16, spec §11 GR-11): [`Wheels`], the
//! `video.wheels` a clip carries — lift, gamma and gain — each a [`Wheel`]
//! of a Cartesian colour push `x, y` and a `master`.
//!
//! **Rust decides, Metal does** (spec §7): the numbers are checked here
//! (`grade_check.rs`), evaluated and clamped like every other number
//! (`actions.rs`, `actions_clamp.rs`) and published in the recipe; the
//! compositor maps the push to RGB at step 4c.1, after tone and before the
//! look.
//!
//! **Written only when not neutral** (GR-2's rule, copied): each key only
//! when not 0, a wheel only when one of its three is not 0, and `wheels`
//! only when one wheel is not neutral, so an unwheeled file's text is what
//! it was. Readers that need every key — an action's interpolation, the
//! patch template, the recipe — go through `actions::wheels_json`, which
//! writes all nine, as `color_json` does tone's.
//!
//! Format 17 (spec §11 GR-12) adds [`Curves`], the `video.curves` a clip
//! carries — master, red, green and blue — each an optional list of 2–16
//! [`CurvePoint`]s on a monotone spline the compositor's strip samples
//! (Swift's `CurveTable`; the core never samples it). A channel equal to
//! the identity ([`curve_is_identity`]) is not written, and `curves` only
//! when one channel is not the identity; `actions_curves.rs`'s
//! `curves_json` writes all four, an absent one as [`IDENTITY_CURVE`].
//!
//! Format 20 (spec §11 GR-32) adds the two hue curves, `hue_hue` (a shift
//! in degrees, −180…180) and `hue_sat` (a gain, 0…2), each a list of 2–16
//! `[hue, value]` points with 0 ≤ hue < 360 on a periodic spline. Every
//! channel has a [`CurveDomain`]: what its x's and values may be, its
//! identity and its neutral. A hue curve is the identity when every value is
//! its neutral, whatever its x's ([`CurveDomain::is_identity`]); an absent
//! one is spelled [`IDENTITY_HUE_SHIFT`] or [`IDENTITY_HUE_GAIN`] by
//! `curves_json`, which now writes all six.
//!
//! Format 18 (spec §11 GR-13) adds [`Qualifier`], the `video.qualifier` an
//! ADJUSTMENT clip carries — a [`HueRange`] in degrees, two [`LevelRange`]s
//! (saturation and luma) in 0…1, each `None` when off, and `invert` —
//! written only when not neutral ([`Qualifier::is_neutral`]). It narrows
//! where the adjustment pass grades; on any other clip `set_video` refuses
//! it (`edit_adjustment.rs`) and the recipe never publishes it.
//!
//! Format 21 (spec §11 GR-35) adds the qualifier's `blur`, 0…1 (0 off),
//! written only when above 0 and counted by [`Qualifier::is_neutral`], so a
//! blur alone is kept. The compositor blurs q by a Gaussian of σ = 24·blur
//! CANVAS pixels; the unit's conversion is Swift's, never the core's.
//!
//! Re-exported whole by `model_props.rs`, which `model.rs` re-exports whole
//! in turn, so `crate::model::Wheels` resolves like every other property
//! type.

use serde::{Deserialize, Serialize};

/// The bound of each of `x`, `y` and `master`: −1…1 (GR-11).
pub const WHEEL_MAX: f64 = 1.0;

/// How far past 1 the circle test lets `x² + y²` go before it refuses
/// (GR-11): a point on the rim made by `cos`/`sin`, or divided by its
/// `hypot`, can land an ulp or two over 1, and must never be refused.
pub const WHEEL_RIM_TOLERANCE: f64 = 1e-9;

/// One wheel: the puck's position (`x`, `y`, inside the unit circle — its
/// angle the hue on the HSV ramp, 0° red, its distance the strength) and
/// the `master` brightness, −1…1. All zero is neutral.
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Wheel {
    #[serde(skip_serializing_if = "is_zero")]
    pub x: f64,
    #[serde(skip_serializing_if = "is_zero")]
    pub y: f64,
    #[serde(skip_serializing_if = "is_zero")]
    pub master: f64,
}

impl Wheel {
    /// No push and no master: the wheel does nothing, and is not written.
    pub fn is_neutral(&self) -> bool {
        self.x == 0.0 && self.y == 0.0 && self.master == 0.0
    }
}

/// Lift (moves black, holds white), gamma (moves the middle, holds both
/// ends) and gain (moves white, holds black), in that order everywhere —
/// the JSON, the uniforms and the inspector.
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Wheels {
    #[serde(skip_serializing_if = "Wheel::is_neutral")]
    pub lift: Wheel,
    #[serde(skip_serializing_if = "Wheel::is_neutral")]
    pub gamma: Wheel,
    #[serde(skip_serializing_if = "Wheel::is_neutral")]
    pub gain: Wheel,
}

impl Wheels {
    /// Every wheel neutral: `video.wheels` is not written.
    pub fn is_neutral(&self) -> bool {
        self.lift.is_neutral() && self.gamma.is_neutral() && self.gain.is_neutral()
    }

    /// The three wheels with their names, in model order.
    pub fn named(&self) -> [(&'static str, &Wheel); 3] {
        [
            ("lift", &self.lift),
            ("gamma", &self.gamma),
            ("gain", &self.gain),
        ]
    }
}

/// Whether a wheel key or the qualifier's `blur` is neutral, and so left out
/// of the file.
fn is_zero(value: &f64) -> bool {
    *value == 0.0
}

/// One curve point, `[x, y]` in JSON: the input and the output, each 0…1
/// (spec §11 GR-12).
pub type CurvePoint = [f64; 2];

/// The fewest points a curve may hold (GR-12).
pub const CURVE_POINTS_MIN: usize = 2;

/// The most points a curve may hold (GR-12).
pub const CURVE_POINTS_MAX: usize = 16;

/// The identity curve's shortest spelling: what `curves_json` writes for an
/// absent channel, and what an action's Reset writes to its end.
pub const IDENTITY_CURVE: [CurvePoint; 2] = [[0.0, 0.0], [1.0, 1.0]];

/// Whether a channel is the identity (GR-12): absent, or a list whose first
/// x is 0, last x is 1 and every point has y = x. Such a channel is not
/// written.
pub fn curve_is_identity(curve: &Option<Vec<CurvePoint>>) -> bool {
    match curve {
        None => true,
        Some(points) => points_are_identity(points),
    }
}

/// [`curve_is_identity`] of a list that is present.
pub fn points_are_identity(points: &[CurvePoint]) -> bool {
    match (points.first(), points.last()) {
        (Some(first), Some(last)) => {
            first[0] == 0.0 && last[0] == 1.0 && points.iter().all(|p| p[1] == p[0])
        }
        _ => false,
    }
}

/// The most a Hue vs Hue value may turn, in degrees either way (spec §11
/// GR-32): `hue_hue`'s values are −180…180, 0 neutral.
pub const HUE_SHIFT_MAX: f64 = 180.0;

/// The most a Hue vs Sat value may scale chroma (GR-32): `hue_sat`'s values
/// are 0…2, 1 neutral.
pub const HUE_GAIN_MAX: f64 = 2.0;

/// The Hue vs Hue identity's spelling: what `curves_json` writes for an
/// absent `hue_hue`, and what an action's Reset writes to its end.
pub const IDENTITY_HUE_SHIFT: [CurvePoint; 2] = [[0.0, 0.0], [180.0, 0.0]];

/// The Hue vs Sat identity's spelling, as [`IDENTITY_HUE_SHIFT`].
pub const IDENTITY_HUE_GAIN: [CurvePoint; 2] = [[0.0, 1.0], [180.0, 1.0]];

/// What a curve channel's numbers mean (spec §11 GR-32): a tone curve maps
/// 0…1 to 0…1; a hue curve maps a hue (0 ≤ x < 360, periodic) to a shift in
/// degrees or a gain.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CurveDomain {
    Tone,
    HueShift,
    HueGain,
}

impl CurveDomain {
    /// The identity's shortest spelling in this domain.
    pub fn identity(self) -> &'static [CurvePoint] {
        match self {
            CurveDomain::Tone => &IDENTITY_CURVE,
            CurveDomain::HueShift => &IDENTITY_HUE_SHIFT,
            CurveDomain::HueGain => &IDENTITY_HUE_GAIN,
        }
    }

    /// Whether a present list is this domain's identity: a tone curve's
    /// [`points_are_identity`]; a hue curve with at least one point whose
    /// every value is the neutral, whatever its x's.
    pub fn is_identity(self, points: &[CurvePoint]) -> bool {
        match self.neutral() {
            None => points_are_identity(points),
            Some(neutral) => !points.is_empty() && points.iter().all(|p| p[1] == neutral),
        }
    }

    /// The value that changes nothing: none for a tone curve (its identity
    /// is y = x), 0 for a shift, 1 for a gain.
    pub fn neutral(self) -> Option<f64> {
        match self {
            CurveDomain::Tone => None,
            CurveDomain::HueShift => Some(0.0),
            CurveDomain::HueGain => Some(1.0),
        }
    }

    /// The bounds of a point's value (y), both inclusive.
    pub fn value_range(self) -> (f64, f64) {
        match self {
            CurveDomain::Tone => (0.0, 1.0),
            CurveDomain::HueShift => (-HUE_SHIFT_MAX, HUE_SHIFT_MAX),
            CurveDomain::HueGain => (0.0, HUE_GAIN_MAX),
        }
    }

    /// Whether an absent or present channel is this domain's identity.
    fn is_identity_option(self, curve: &Option<Vec<CurvePoint>>) -> bool {
        curve
            .as_deref()
            .is_none_or(|points| self.is_identity(points))
    }
}

/// Whether `hue_hue` is the identity (absent, or every value 0): not written.
pub fn hue_shift_is_identity(curve: &Option<Vec<CurvePoint>>) -> bool {
    CurveDomain::HueShift.is_identity_option(curve)
}

/// Whether `hue_sat` is the identity (absent, or every value 1): not written.
pub fn hue_gain_is_identity(curve: &Option<Vec<CurvePoint>>) -> bool {
    CurveDomain::HueGain.is_identity_option(curve)
}

/// The four tone curves (spec §11 GR-12): `master` first, applied to all
/// three channels, then each colour's own, `channel(master(v))`; then the
/// two hue curves (GR-32), Hue vs Hue and Hue vs Sat, read at the hue the
/// tone curves leave. `None` is the identity.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Curves {
    #[serde(skip_serializing_if = "curve_is_identity")]
    pub master: Option<Vec<CurvePoint>>,
    #[serde(skip_serializing_if = "curve_is_identity")]
    pub red: Option<Vec<CurvePoint>>,
    #[serde(skip_serializing_if = "curve_is_identity")]
    pub green: Option<Vec<CurvePoint>>,
    #[serde(skip_serializing_if = "curve_is_identity")]
    pub blue: Option<Vec<CurvePoint>>,
    #[serde(skip_serializing_if = "hue_shift_is_identity")]
    pub hue_hue: Option<Vec<CurvePoint>>,
    #[serde(skip_serializing_if = "hue_gain_is_identity")]
    pub hue_sat: Option<Vec<CurvePoint>>,
}

impl Curves {
    /// Every channel the identity: `video.curves` is not written.
    pub fn is_identity(&self) -> bool {
        self.named()
            .iter()
            .all(|(_, domain, curve)| domain.is_identity_option(curve))
    }

    /// The six channels with their names and domains, in model order.
    pub fn named(&self) -> [(&'static str, CurveDomain, &Option<Vec<CurvePoint>>); 6] {
        [
            ("master", CurveDomain::Tone, &self.master),
            ("red", CurveDomain::Tone, &self.red),
            ("green", CurveDomain::Tone, &self.green),
            ("blue", CurveDomain::Tone, &self.blue),
            ("hue_hue", CurveDomain::HueShift, &self.hue_hue),
            ("hue_sat", CurveDomain::HueGain, &self.hue_sat),
        ]
    }

    /// The six channels with their domains, mutable, in model order.
    pub fn named_mut(&mut self) -> [(CurveDomain, &mut Option<Vec<CurvePoint>>); 6] {
        [
            (CurveDomain::Tone, &mut self.master),
            (CurveDomain::Tone, &mut self.red),
            (CurveDomain::Tone, &mut self.green),
            (CurveDomain::Tone, &mut self.blue),
            (CurveDomain::HueShift, &mut self.hue_hue),
            (CurveDomain::HueGain, &mut self.hue_sat),
        ]
    }

    /// Each identity channel becomes `None`: what `set_video` stores (so an
    /// identity patch on an uncurved clip is an identity) and what an
    /// action's end evaluates to.
    pub fn drop_identities(&mut self) {
        for (domain, curve) in self.named_mut() {
            if domain.is_identity_option(curve) {
                *curve = None;
            }
        }
    }
}

/// One turn of the hue circle, in degrees: a [`HueRange`]'s `center` and
/// `width` are 0…360 (GR-13), the centre wrapping (360 is 0); a hue curve's
/// x is 0 ≤ x < 360 (GR-32).
pub const HUE_TURN: f64 = 360.0;

/// The most a hue range's softness may be, in degrees (GR-13): half a turn,
/// past which the fall-off would wrap onto the band's other side.
pub const HUE_SOFTNESS_MAX: f64 = 180.0;

/// A hue band (spec §11 GR-13): fully selected within `width / 2` degrees
/// of `center` (wrapping), falling to nothing across `softness` degrees
/// outside each edge. The default is the skin band a person ticks on first.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct HueRange {
    pub center: f64,
    pub width: f64,
    pub softness: f64,
}

impl Default for HueRange {
    fn default() -> Self {
        HueRange {
            center: 30.0,
            width: 50.0,
            softness: 25.0,
        }
    }
}

/// A saturation or luma band (spec §11 GR-13), in 0…1: fully selected from
/// `low` to `high`, falling to nothing across `softness` outside each edge.
/// The default passes everything until it is narrowed.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct LevelRange {
    pub low: f64,
    pub high: f64,
    pub softness: f64,
}

impl Default for LevelRange {
    fn default() -> Self {
        LevelRange {
            low: 0.0,
            high: 1.0,
            softness: 0.1,
        }
    }
}

/// The most a qualifier's `blur` may be (spec §11 GR-35): 0…1, 0 off.
pub const QUALIFIER_BLUR_MAX: f64 = 1.0;

/// The qualifier (spec §11 GR-13, format 18): which of the destination's
/// pixels an adjustment clip grades. A range that is `None` is off and
/// passes everything; the weight is the product of the present ranges, then
/// its complement when `invert` is set. `blur` (format 21, GR-35) softens
/// that weight by a Gaussian before the pass reads it.
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Qualifier {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hue: Option<HueRange>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub saturation: Option<LevelRange>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub luma: Option<LevelRange>,
    #[serde(skip_serializing_if = "is_false")]
    pub invert: bool,
    #[serde(skip_serializing_if = "is_zero")]
    pub blur: f64,
}

impl Qualifier {
    /// No range, not inverted and no blur (GR-35): `video.qualifier` is not
    /// written, and the adjustment pass weighs every pixel as it did before
    /// the key existed.
    pub fn is_neutral(&self) -> bool {
        self.hue.is_none()
            && self.saturation.is_none()
            && self.luma.is_none()
            && !self.invert
            && self.blur == 0.0
    }

    /// The two level ranges with their names, in model order.
    pub fn levels(&self) -> [(&'static str, &Option<LevelRange>); 2] {
        [("saturation", &self.saturation), ("luma", &self.luma)]
    }
}

/// Whether `invert` is off, and so left out of the file.
fn is_false(value: &bool) -> bool {
    !*value
}
