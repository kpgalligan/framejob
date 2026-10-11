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
