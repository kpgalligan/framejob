//! The qualifier's one rule for action evaluation (spec §11 GR-13), beside
//! `actions.rs` rather than in it (that file is near the cap), as GR-12's
//! `actions_curves.rs` is.
//!
//! §5.4 interpolates numbers, so an animated hue centre from 350 to 10
//! would sweep the long way round, through the greens and blues at 180.
//! The owner chose the SHORT way round (G2-4's choice 11): before the lerp,
//! [`align_hue_center`] moves the interpolation TARGET's centre by ±360 when
//! the two centres are more than 180 degrees apart, so the lerp takes the
//! shorter arc (350 → 370), and `actions_clamp.rs`'s `clamp_qualifier`
//! brings the lerped centre back onto the circle with `rem_euclid 360`
//! (355, then 0, then 5). Two centres exactly 180 apart have no shorter
//! arc and go linearly. Only the target of the action the time is INSIDE
//! is touched: an ended action's end is merged as written.

use serde_json::Value;

/// The `video.qualifier.hue.center` number of an action state, mutably.
fn center(state: &mut Value) -> Option<&mut Value> {
    state
        .get_mut("video")?
        .get_mut("qualifier")?
        .get_mut("hue")?
        .get_mut("center")
}

/// On the two states' `video.qualifier.hue.center`, when both are numbers
/// and more than 180 apart: `to`'s centre moves by ±360 so the two are less
/// than 180 apart (module doc). Anything else is left alone.
pub(crate) fn align_hue_center(from: &mut Value, to: &mut Value) {
    let Some(start) = center(from).and_then(|value| value.as_f64()) else {
        return;
    };
    let Some(end) = center(to) else {
        return;
    };
    let Some(target) = end.as_f64() else {
        return;
    };
    let turn = crate::model::HUE_TURN;
    let moved = if target - start > turn / 2.0 {
        target - turn
    } else if start - target > turn / 2.0 {
        target + turn
    } else {
        return;
    };
    if let Some(number) = serde_json::Number::from_f64(moved) {
        *end = Value::Number(number);
    }
}
