//! Tier 2's range checks (spec §11 GR-11), called from `props_check.rs`'s
//! `check_video`: each wheel's `x`, `y` and `master` −1…1, and its push
//! inside the unit circle.
//!
//! The rule is `props_check.rs`'s: a value out of range is NAMED in the
//! rule's own sentence, never clamped (an action's end is clamped instead,
//! by `actions_clamp.rs`'s `clamp_wheels`). The circle test allows
//! [`WHEEL_RIM_TOLERANCE`] past 1, so a rim point made by `cos`/`sin` or
//! divided by its `hypot` — the inspector's puck and `clamp_wheels` both
//! make one — is never refused; the sentence still says `≤ 1`.

use crate::model::{Wheels, WHEEL_MAX, WHEEL_RIM_TOLERANCE};
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
