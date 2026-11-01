//! The grading clamps `clamp_video` runs on an action's evaluated video props: the wheels, the
//! curves and the qualifier, each bounded as its own doc says.
//! A pure move out of `actions_clamp.rs` under road map "creator-jobs" CU0a's toll U5.

use crate::actions_clamp::bounded;
use crate::model::{
    CurveDomain, CurvePoint, Curves, HueRange, LevelRange, Qualifier, Wheels, CURVE_POINTS_MAX,
    CURVE_POINTS_MIN, HUE_SOFTNESS_MAX, HUE_TURN, QUALIFIER_BLUR_MAX, WHEEL_MAX,
};

/// The wheels (spec §11 GR-11): a NaN to 0, each value to ±1, and a push
/// outside the unit circle divided by its `hypot` onto the rim — a point
/// `grade_check.rs`'s circle test always takes (its `WHEEL_RIM_TOLERANCE`).
pub(crate) fn clamp_wheels(wheels: &mut Wheels) {
    for wheel in [&mut wheels.lift, &mut wheels.gamma, &mut wheels.gain] {
        wheel.x = bounded(wheel.x, -WHEEL_MAX, WHEEL_MAX, 0.0);
        wheel.y = bounded(wheel.y, -WHEEL_MAX, WHEEL_MAX, 0.0);
        wheel.master = bounded(wheel.master, -WHEEL_MAX, WHEEL_MAX, 0.0);
        if wheel.x * wheel.x + wheel.y * wheel.y > 1.0 {
            let radius = wheel.x.hypot(wheel.y);
            wheel.x /= radius;
            wheel.y /= radius;
        }
    }
}

/// The curves (spec §11 GR-12): each x and y to 0…1, a channel holding a
/// NaN removed; a channel with fewer than 2 or more than 16 points, or whose
/// x's do not strictly rise after the clamp, removed; then every identity
/// channel removed, so an action that ends on the identity ends uncurved.
/// A hue curve (GR-32) clamps its x's to 0…360 and is removed when its last
/// x is 360, and its values to its domain's range.
pub(crate) fn clamp_curves(curves: &mut Curves) {
    for (domain, curve) in curves.named_mut() {
        if let Some(points) = curve.as_mut() {
            if !clamp_points(points, domain) {
                *curve = None;
            }
        }
    }
    curves.drop_identities();
}

/// One channel's points clamped in place; false when the channel must go.
fn clamp_points(points: &mut [CurvePoint], domain: CurveDomain) -> bool {
    if !(CURVE_POINTS_MIN..=CURVE_POINTS_MAX).contains(&points.len()) {
        return false;
    }
    let x_high = if domain == CurveDomain::Tone {
        1.0
    } else {
        HUE_TURN
    };
    let (low, high) = domain.value_range();
    for point in points.iter_mut() {
        if point.iter().any(|value| value.is_nan()) {
            return false;
        }
        point[0] = point[0].clamp(0.0, x_high);
        point[1] = point[1].clamp(low, high);
    }
    if domain != CurveDomain::Tone && points.last().is_some_and(|last| last[0] >= HUE_TURN) {
        return false;
    }
    points.windows(2).all(|pair| pair[1][0] > pair[0][0])
}

/// The qualifier (spec §11 GR-13): a range holding a NaN removed; every
/// other number to its bounds — the hue's width 0…360 and softness 0…180,
/// each level 0…1 — the hue centre taken `rem_euclid 360` (so a centre an
/// action moved past 360 or below 0 on the short way round,
/// `actions_qualifier.rs`, comes back onto the circle), and a level range
/// whose `low` passed its `high` closed at `high = low`. The `blur` (GR-35):
/// non-finite → 0, then 0…1.
pub(crate) fn clamp_qualifier(qualifier: &mut Qualifier) {
    if let Some(hue) = qualifier.hue {
        qualifier.hue = clamp_hue(hue);
    }
    for range in [&mut qualifier.saturation, &mut qualifier.luma] {
        if let Some(level) = *range {
            *range = clamp_level(level);
        }
    }
    qualifier.blur = if qualifier.blur.is_finite() {
        qualifier.blur.clamp(0.0, QUALIFIER_BLUR_MAX)
    } else {
        0.0
    };
}

/// One hue range clamped, or `None` when it must go.
fn clamp_hue(hue: HueRange) -> Option<HueRange> {
    if !hue.center.is_finite() || hue.width.is_nan() || hue.softness.is_nan() {
        return None;
    }
    Some(HueRange {
        center: hue.center.rem_euclid(HUE_TURN),
        width: hue.width.clamp(0.0, HUE_TURN),
        softness: hue.softness.clamp(0.0, HUE_SOFTNESS_MAX),
    })
}

/// One level range clamped, or `None` when it must go.
fn clamp_level(level: LevelRange) -> Option<LevelRange> {
    if level.low.is_nan() || level.high.is_nan() || level.softness.is_nan() {
        return None;
    }
    let low = level.low.clamp(0.0, 1.0);
    Some(LevelRange {
        low,
        high: level.high.clamp(0.0, 1.0).max(low),
        softness: level.softness.clamp(0.0, 1.0),
    })
}
