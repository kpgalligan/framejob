//! The curves' JSON helpers for action evaluation (spec §11 GR-12, GR-34),
//! beside `actions.rs` rather than in it (that file is near the cap).
//!
//! [`curves_json`] writes all six channels, an absent one as its domain's
//! identity ([`IDENTITY_CURVE`], `IDENTITY_HUE_SHIFT`, `IDENTITY_HUE_GAIN`,
//! spec §11 GR-32), for every reader of `actions::video_json`: the state an
//! action interpolates from, the patch template (so `curves.red` is a known
//! key) and `split`'s state. [`align_identity_curves`] is the one rule the
//! list rule needs to animate a grade from neutral: an identity channel
//! meeting a curve of a different count takes that curve's x's — on a tone
//! curve with y = x and its ends at `[0, 0]` and `[1, 1]`, on a hue curve
//! with the neutral value — so the two lists match and interpolate per
//! point.
//!
//! Any other count change — two non-identity curves of different point
//! counts — BLENDS their values (GR-34): the list rule holds the list at its
//! start value `a`, so the evaluated props hold `a`, and [`curve_blends`]
//! names each such channel with the end curve `b` and the eased progress t.
//! [`blended_curves_json`] writes the recipe's and `clip_state`'s `curves`
//! with each blended channel as `{from, to, t}`, which Swift's strip samples
//! as `(1 − t)·a(x) + t·b(x)`. The core never samples a spline; a blend is
//! never written to a file (the model, a split, a paste and the template
//! hold points through [`curves_json`]).

use serde_json::{Map, Value};

use crate::actions::to_json;
use crate::actions_clamp::clamp_curves;
use crate::model::{CurveDomain, CurvePoint, Curves};

/// One channel blended inside an action (spec §11 GR-34): its held curve
/// `from`, the action's clamped end curve `to`, both non-identity and of
/// different point counts, and the eased progress `t`, strictly inside 0…1.
#[derive(Debug, Clone, PartialEq)]
pub struct CurveBlend {
    pub channel: &'static str,
    pub from: Vec<CurvePoint>,
    pub to: Vec<CurvePoint>,
    pub t: f64,
}

/// The channels to blend at eased progress `t`: one per channel, in model
/// order, where `held` (the evaluated, clamped curves) and the action's
/// merged `target` (its `video.curves` decoded and clamped as an end is) are
/// both non-identity with different point counts. Empty unless 0 < t < 1,
/// and when the target's curves do not decode.
pub(crate) fn curve_blends(held: &Curves, target: &Value, t: f64) -> Vec<CurveBlend> {
    if t.is_nan() || t <= 0.0 || t >= 1.0 {
        return Vec::new();
    }
    let Some(value) = target.get("video").and_then(|video| video.get("curves")) else {
        return Vec::new();
    };
    let Ok(mut ends) = serde_json::from_value::<Curves>(value.clone()) else {
        return Vec::new();
    };
    clamp_curves(&mut ends);
    let mut out = Vec::new();
    for ((channel, _, from), (_, _, to)) in held.named().into_iter().zip(ends.named()) {
        if let (Some(from), Some(to)) = (from, to) {
            if from.len() == to.len() {
                continue;
            }
            out.push(CurveBlend {
                channel,
                from: from.clone(),
                to: to.clone(),
                t,
            });
        }
    }
    out
}

/// [`curves_json`] with each blended channel written as `{"from": [[x, y],
/// …], "to": [[x, y], …], "t": t}` (spec §11 GR-34): the recipe's `curves`
/// and `clip_state`'s `video.curves`. With no blends it is [`curves_json`]
/// byte for byte.
pub(crate) fn blended_curves_json(curves: &Curves, blends: &[CurveBlend]) -> Value {
    let mut out = curves_json(curves);
    if let Value::Object(channels) = &mut out {
        for blend in blends {
            let mut fields = Map::new();
            fields.insert("from".to_string(), to_json(&blend.from));
            fields.insert("to".to_string(), to_json(&blend.to));
            fields.insert("t".to_string(), to_json(&blend.t));
            channels.insert(blend.channel.to_string(), Value::Object(fields));
        }
    }
    out
}

/// The curves with every channel present: an absent one as its domain's
/// identity.
pub(crate) fn curves_json(curves: &Curves) -> Value {
    let mut out = Map::new();
    for (name, domain, curve) in curves.named() {
        let value = match curve {
            Some(points) => to_json(points),
            None => to_json(&domain.identity()),
        };
        out.insert(name.to_string(), value);
    }
    Value::Object(out)
}

/// A channel's points, when the value reads as a list of `[x, y]`.
fn points(value: &Value) -> Option<Vec<CurvePoint>> {
    serde_json::from_value::<Vec<CurvePoint>>(value.clone()).ok()
}

/// The identity on `other`'s x's: on a tone curve its first point `[0, 0]`,
/// its last `[1, 1]`, every point between at y = x; on a hue curve every
/// point at the neutral value.
fn aligned(other: &[CurvePoint], domain: CurveDomain) -> Value {
    let last = other.len().saturating_sub(1);
    let out: Vec<CurvePoint> = other
        .iter()
        .enumerate()
        .map(|(index, point)| {
            if let Some(neutral) = domain.neutral() {
                [point[0], neutral]
            } else if index == 0 {
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
/// holds it, and [`curve_blends`] blends two curves of different counts).
pub(crate) fn align_identity_curves(from: &mut Value, to: &mut Value) {
    let (Some(Value::Object(from)), Some(Value::Object(to))) = (
        from.get_mut("video").and_then(|v| v.get_mut("curves")),
        to.get_mut("video").and_then(|v| v.get_mut("curves")),
    ) else {
        return;
    };
    for (name, domain, _) in Curves::default().named() {
        let (Some(a), Some(b)) = (from.get(name), to.get(name)) else {
            continue;
        };
        let (Some(a), Some(b)) = (points(a), points(b)) else {
            continue;
        };
        if a.len() == b.len() || a.is_empty() || b.is_empty() {
            continue;
        }
        if domain.is_identity(&a) {
            from.insert(name.to_string(), aligned(&b, domain));
        } else if domain.is_identity(&b) {
            to.insert(name.to_string(), aligned(&a, domain));
        }
    }
}
