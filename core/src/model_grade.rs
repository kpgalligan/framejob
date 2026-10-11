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

/// Whether a wheel key is neutral, and so left out of the file.
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

/// The four tone curves (spec §11 GR-12): `master` first, applied to all
/// three channels, then each colour's own, `channel(master(v))`. `None` is
/// the identity.
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
}

impl Curves {
    /// Every channel the identity: `video.curves` is not written.
    pub fn is_identity(&self) -> bool {
        self.named()
            .iter()
            .all(|(_, curve)| curve_is_identity(curve))
    }

    /// The four channels with their names, in model order.
    pub fn named(&self) -> [(&'static str, &Option<Vec<CurvePoint>>); 4] {
        [
            ("master", &self.master),
            ("red", &self.red),
            ("green", &self.green),
            ("blue", &self.blue),
        ]
    }

    /// Each identity channel becomes `None`: what `set_video` stores (so an
    /// identity patch on an uncurved clip is an identity) and what an
    /// action's end evaluates to.
    pub fn drop_identities(&mut self) {
        for curve in [
            &mut self.master,
            &mut self.red,
            &mut self.green,
            &mut self.blue,
        ] {
            if curve_is_identity(curve) {
                *curve = None;
            }
        }
    }
}
