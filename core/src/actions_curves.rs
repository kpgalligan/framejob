//! The curves' two JSON helpers for action evaluation (spec §11 GR-12),
//! beside `actions.rs` rather than in it (that file is near the cap).
//!
//! [`curves_json`] writes all four channels, an absent one as
//! [`IDENTITY_CURVE`], for every reader of `actions::video_json`: the
//! state an action interpolates from, the patch template (so `curves.red`
//! is a known key), `split`'s state and the recipe. [`align_identity_curves`]
//! is the one rule the list rule needs to animate a grade from neutral: an
//! identity channel meeting a curve of a different count takes that
//! curve's x's, with y = x and its ends at `[0, 0]` and `[1, 1]`, so the
//! two lists match and interpolate per point. Any other count change
//! switches at the end (§5.4's list rule).

use serde_json::{Map, Value};

use crate::actions::to_json;
use crate::model::{points_are_identity, CurvePoint, Curves, IDENTITY_CURVE};

/// The curves with every channel present: an absent one as the identity.
pub(crate) fn curves_json(curves: &Curves) -> Value {
    let mut out = Map::new();
    for (name, curve) in curves.named() {
        let value = match curve {
            Some(points) => to_json(points),
            None => to_json(&IDENTITY_CURVE),
        };
        out.insert(name.to_string(), value);
    }
    Value::Object(out)
}

/// A channel's points, when the value reads as a list of `[x, y]`.
fn points(value: &Value) -> Option<Vec<CurvePoint>> {
    serde_json::from_value::<Vec<CurvePoint>>(value.clone()).ok()
}

/// The identity on `other`'s x's: its first point `[0, 0]`, its last
/// `[1, 1]`, every point between at y = x.
fn aligned(other: &[CurvePoint]) -> Value {
    let last = other.len().saturating_sub(1);
    let out: Vec<CurvePoint> = other
        .iter()
        .enumerate()
        .map(|(index, point)| {
            if index == 0 {
                [0.0, 0.0]
            } else if index == last {
                [1.0, 1.0]
            } else {
                [point[0], point[0]]
            }
        })
        .collect();
    to_json(&out)
}

/// On the two states' `video.curves`, each channel where one side is the
/// identity and the other a curve of a different point count: the identity
/// side is replaced by the identity on the other's x's ([`aligned`]). Any
/// value that does not read as points is left alone (the list rule then
/// switches it at the end).
pub(crate) fn align_identity_curves(from: &mut Value, to: &mut Value) {
    let (Some(Value::Object(from)), Some(Value::Object(to))) = (
        from.get_mut("video").and_then(|v| v.get_mut("curves")),
        to.get_mut("video").and_then(|v| v.get_mut("curves")),
    ) else {
        return;
    };
    for name in ["master", "red", "green", "blue"] {
        let (Some(a), Some(b)) = (from.get(name), to.get(name)) else {
            continue;
        };
        let (Some(a), Some(b)) = (points(a), points(b)) else {
            continue;
        };
        if a.len() == b.len() || a.is_empty() || b.is_empty() {
            continue;
        }
        if points_are_identity(&a) {
            from.insert(name.to_string(), aligned(&b));
        } else if points_are_identity(&b) {
            to.insert(name.to_string(), aligned(&a));
        }
    }
}
