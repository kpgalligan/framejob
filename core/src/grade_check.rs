//! Tier 2's range checks (spec §11 GR-11), called from `props_check.rs`'s
//! `check_video`: each wheel's `x`, `y` and `master` −1…1, and its push
//! inside the unit circle; and each curve's 2–16 points, x and y 0…1, x
//! strictly rising (GR-12), a hue curve's x 0 ≤ x < 360 and its value in
//! its domain's range (GR-32); and the qualifier's ranges, each bound in its
//! own sentence and low ≤ high (GR-13).
//!
//! The rule is `props_check.rs`'s: a value out of range is NAMED in the
//! rule's own sentence, never clamped (an action's end is clamped instead,
//! by `actions_clamp.rs`'s `clamp_wheels`). The circle test allows
//! [`WHEEL_RIM_TOLERANCE`] past 1, so a rim point made by `cos`/`sin` or
//! divided by its `hypot` — the inspector's puck and `clamp_wheels` both
//! make one — is never refused; the sentence still says `≤ 1`.

use crate::model::{
    CurveDomain, Curves, Qualifier, Wheels, CURVE_POINTS_MAX, CURVE_POINTS_MIN, HUE_SOFTNESS_MAX,
    HUE_TURN, WHEEL_MAX, WHEEL_RIM_TOLERANCE,
};
use crate::props_check::in_range;

/// `Ok` when every wheel is in range and inside the circle; the first
/// refusal otherwise, in model order (lift, gamma, gain; x, y, master).
pub(crate) fn check_wheels(wheels: &Wheels) -> Result<(), String> {
    for (name, wheel) in wheels.named() {
        let key = format!("video.wheels.{name}");
        in_range(&format!("{key}.x"), wheel.x, -WHEEL_MAX, WHEEL_MAX)?;
        in_range(&format!("{key}.y"), wheel.y, -WHEEL_MAX, WHEEL_MAX)?;
        in_range(
            &format!("{key}.master"),
            wheel.master,
            -WHEEL_MAX,
            WHEEL_MAX,
        )?;
        if wheel.x * wheel.x + wheel.y * wheel.y > 1.0 + WHEEL_RIM_TOLERANCE {
            return Err(format!(
                "{key} must lie inside the unit circle (x² + y² ≤ 1), not x {}, y {}",
                wheel.x, wheel.y
            ));
        }
    }
    Ok(())
}

/// `Ok` when every curve holds 2–16 points, each x and y 0…1 (bounds
/// inclusive) and x strictly rising; the first refusal otherwise, in model
/// order (master, red, green, blue, hue_hue, hue_sat), then point order,
/// indices 0-based (GR-12). A hue curve's x is 0 ≤ x < 360 and its value
/// within its domain's range (GR-32). An identity curve passes: `set_video`
/// drops it after this.
pub(crate) fn check_curves(curves: &Curves) -> Result<(), String> {
    for (name, domain, curve) in curves.named() {
        let Some(points) = curve else {
            continue;
        };
        let key = format!("video.curves.{name}");
        if !(CURVE_POINTS_MIN..=CURVE_POINTS_MAX).contains(&points.len()) {
            return Err(format!(
                "{key} needs {CURVE_POINTS_MIN} to {CURVE_POINTS_MAX} points, not {}",
                points.len()
            ));
        }
        let (low, high) = domain.value_range();
        for (index, point) in points.iter().enumerate() {
            if domain == CurveDomain::Tone {
                in_range(&format!("{key}[{index}].x"), point[0], 0.0, 1.0)?;
            } else if !(point[0].is_finite() && point[0] >= 0.0 && point[0] < HUE_TURN) {
                return Err(format!(
                    "{key}[{index}].x must be at least 0 and below {HUE_TURN}, not {}",
                    point[0]
                ));
            }
            in_range(&format!("{key}[{index}].y"), point[1], low, high)?;
            if index > 0 && point[0] <= points[index - 1][0] {
                return Err(format!(
                    "{key}[{index}].x ({}) must be greater than {key}[{}].x ({})",
                    point[0],
                    index - 1,
                    points[index - 1][0]
                ));
            }
        }
    }
    Ok(())
}

/// `Ok` when every present range is inside its bounds (all inclusive, spec
/// §11 GR-13): the hue's `center` and `width` 0…360 and its `softness`
/// 0…180; each level range's `low`, `high` and `softness` 0…1 and `low ≤
/// high`. The first refusal otherwise, in the order hue (centre, width,
/// softness), saturation (low, high, softness, then the order), luma the
/// same. A bound is compared exactly, so 360, 180, 0 and 1 all pass.
pub(crate) fn check_qualifier(qualifier: &Qualifier) -> Result<(), String> {
    if let Some(hue) = &qualifier.hue {
        in_range("video.qualifier.hue.center", hue.center, 0.0, HUE_TURN)?;
        in_range("video.qualifier.hue.width", hue.width, 0.0, HUE_TURN)?;
        in_range(
            "video.qualifier.hue.softness",
            hue.softness,
            0.0,
            HUE_SOFTNESS_MAX,
        )?;
    }
    for (name, range) in qualifier.levels() {
        let Some(range) = range else {
            continue;
        };
        let key = format!("video.qualifier.{name}");
        in_range(&format!("{key}.low"), range.low, 0.0, 1.0)?;
        in_range(&format!("{key}.high"), range.high, 0.0, 1.0)?;
        in_range(&format!("{key}.softness"), range.softness, 0.0, 1.0)?;
        if range.low > range.high {
            return Err(format!(
                "{key}.low ({}) must not be greater than {key}.high ({})",
                range.low, range.high
            ));
        }
    }
    Ok(())
}
