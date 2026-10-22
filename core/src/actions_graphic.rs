//! A graphic clip's props at a clip time (format version 13, spec §11
//! G-34): the fourth thing an action animates, beside `actions.rs`'s three
//! groups and outside its `merge` / `lerp`, because a prop's kind is not
//! the value's shape and a whole number is not a tick count.
//!
//! The rule is §5.4's, applied to `graphic.props` alone. Each FINISHED
//! action's `end.graphic.props` is laid over the clip's own map in start
//! order, by `insert` (`model_graphic.rs`'s rule, so a stored key keeps its
//! slot and an action's new key goes after the stored ones). Then the
//! action that SPANS the time moves each prop it names from the value
//! reached so far toward its end along its curve:
//!
//! - **a number** in floating point, `a + (b − a) × eased`, never rounded
//!   and never snapped to a `step` (G-34 (e)) — so two whole ends 64 and
//!   129 give 96.5 halfway, and a module that wants a whole number rounds;
//! - **a colour**, known by `end.graphic.kinds.<key> == "color"` and never
//!   by the value's shape, in OKLab through `model_color.rs`'s
//!   `color_channels`, `oklab_mix` and `color_hex` — stdlib's
//!   `interpolateColors`' blend, byte for byte, with STRAIGHT alpha, each
//!   channel rounded to the nearest byte (G-40, amending G-34 (f)). The
//!   model's own `[r, g, b, a]` colours blend through `actions_color.rs`
//!   with the same arithmetic, in floating point (G-43);
//! - **anything else** — a string, a boolean, an enum, an asset (G-42), two values of
//!   different JSON kinds, a colour it cannot read — holds its start and
//!   takes the end's value at the action's END.
//!
//! **Total.** A malformed `graphic`, `props` or `kinds` reads as "names
//! nothing" and a prop with no start stays absent until its action ends, so
//! no frame fails: a file is stored as found and nothing here unwraps.

use serde_json::{Map, Number, Value};

use crate::actions::{ease, ordered_actions, spans};
use crate::model::{Clip, GraphicProps};
use crate::model_color::{color_channels, color_hex, oklab_mix};
use crate::time::Ticks;

/// The clip's `graphic` with its `props` evaluated at `clip_t`, its other
/// fields as stored; `None` when the clip has no graphic.
pub(crate) fn evaluate_graphic(clip: &Clip, clip_t: Ticks) -> Option<GraphicProps> {
    let mut graphic = clip.graphic.clone()?;
    if clip.actions.is_empty() {
        return Some(graphic);
    }
    let actions = ordered_actions(clip);
    for action in &actions {
        let end = action.start.saturating_add(action.duration);
        if action.duration > 0 && end <= clip_t {
            for (key, value) in end_props(&action.end).into_iter().flatten() {
                if !value.is_null() {
                    graphic.props.insert(key.clone(), value.clone());
                }
            }
        }
    }
    if let Some(action) = actions.iter().find(|a| spans(a, clip_t)) {
        let elapsed = clip_t.saturating_sub(action.start) as f64;
        let u = ease(action.curve, elapsed / action.duration as f64);
        for (key, to) in end_props(&action.end).into_iter().flatten() {
            if to.is_null() {
                continue;
            }
            // A prop with no start has nothing to move from: it stays
            // absent until the action ends, then the loop above lays it in.
            let Some(from) = graphic.props.get(key) else {
                continue;
            };
            let value = lerp_prop(from, to, is_colour(&action.end, key), u);
            graphic.props.insert(key.clone(), value);
        }
    }
    Some(graphic)
}

/// True when some action on the clip names `key` in its end's
/// `graphic.props` with a value that is not `null` — the question
/// `set_graphic`'s `null` and `paste_attributes`' kept key both ask
/// (G-34 (d)).
pub(crate) fn names_prop(clip: &Clip, key: &str) -> bool {
    clip.actions.iter().any(|action| {
        end_props(&action.end)
            .and_then(|props| props.get(key))
            .is_some_and(|value| !value.is_null())
    })
}

/// An end's `graphic.props`, or `None` when the end, its `graphic` or its
/// `props` is not an object.
fn end_props(end: &Value) -> Option<&Map<String, Value>> {
    end.get("graphic")?.get("props")?.as_object()
}

/// The end records `key`'s kind as `color`. Anything else — no `kinds`, a
/// `kinds` that is not an object, another kind — is not a colour, so a
/// file written before `kinds` existed switches its colours at the end.
fn is_colour(end: &Value, key: &str) -> bool {
    end.get("graphic")
        .and_then(|graphic| graphic.get("kinds"))
        .and_then(|kinds| kinds.get(key))
        .and_then(Value::as_str)
        == Some("color")
}

/// One prop from `from` toward `to` by eased progress `u`.
///
/// The two switch points come first, as in `actions.rs`'s `lerp_at`: at
/// `u <= 0` the start as stored, so an integer start stays an integer and
/// the layer's hash at an action's first tick is the hash before it; at
/// `u >= 1` the end as stored.
fn lerp_prop(from: &Value, to: &Value, colour: bool, u: f64) -> Value {
    if u <= 0.0 {
        return from.clone();
    }
    if u >= 1.0 {
        return to.clone();
    }
    match (from, to) {
        (Value::Number(a), Value::Number(b)) => match (a.as_f64(), b.as_f64()) {
            // Never rounded, even when both ends are whole (G-34 (e));
            // `from_f64` refuses a non-finite result, which holds instead.
            (Some(a), Some(b)) => Number::from_f64(a + (b - a) * u)
                .map(Value::Number)
                .unwrap_or_else(|| from.clone()),
            _ => from.clone(),
        },
        (Value::String(a), Value::String(b)) if colour => {
            match (color_channels(a), color_channels(b)) {
                (Some(a), Some(b)) => Value::String(color_hex(oklab_mix(a, b, u))),
                _ => from.clone(),
            }
        }
        _ => from.clone(),
    }
}
