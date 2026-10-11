//! Tier 2's range checks (spec §11 GR-11), called from `props_check.rs`'s
//! `check_video`: each wheel's `x`, `y` and `master` −1…1, and its push
//! inside the unit circle; and each curve's 2–16 points, x and y 0…1, x
//! strictly rising (GR-12).
//!
//! The rule is `props_check.rs`'s: a value out of range is NAMED in the
//! rule's own sentence, never clamped (an action's end is clamped instead,
//! by `actions_clamp.rs`'s `clamp_wheels`). The circle test allows
//! [`WHEEL_RIM_TOLERANCE`] past 1, so a rim point made by `cos`/`sin` or
//! divided by its `hypot` — the inspector's puck and `clamp_wheels` both
//! make one — is never refused; the sentence still says `≤ 1`.

use crate::model::{
    Curves, Wheels, CURVE_POINTS_MAX, CURVE_POINTS_MIN, WHEEL_MAX, WHEEL_RIM_TOLERANCE,
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
/// order (master, red, green, blue), then point order, indices 0-based
/// (GR-12). An identity curve passes: `set_video` drops it after this.
pub(crate) fn check_curves(curves: &Curves) -> Result<(), String> {
    for (name, curve) in curves.named() {
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
        for (index, point) in points.iter().enumerate() {
            in_range(&format!("{key}[{index}].x"), point[0], 0.0, 1.0)?;
            in_range(&format!("{key}[{index}].y"), point[1], 0.0, 1.0)?;
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
