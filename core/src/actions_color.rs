//! The model's own colours in action evaluation (spec §11 G-43), beside
//! `actions.rs` rather than in it (that file is near the cap).
//!
//! `actions.rs`'s `lerp` moves every number of an action's state element
//! by element, which is right for a position and wrong for a colour. So
//! after the spanning action's `lerp`, [`blend_colors`] overwrites each
//! colour of the lerped state with the OKLab blend of the action's two
//! ends, through `model_color.rs`'s unit path — the arithmetic graphic
//! `color` props blend with (G-40), in floating point, never rounded to a
//! byte, with straight alpha.
//!
//! - **By key, never by shape.** The colours are the nine paths below:
//!   [`COLOR_POINTERS`]' eight `[r, g, b, a]` and [`CHROMA_KEY_POINTER`]'s
//!   `[r, g, b]`. A four-number array anywhere else (a crop is an object; a
//!   point is two numbers) is not a colour.
//! - **The arity rule.** A key is blended only when both ends hold an array
//!   of exactly its arity (4, or 3 for the key) whose every element reads
//!   as a number, and the lerped state has a value there. Anything else — a
//!   `null`, a missing group, a wrong length, a non-number — keeps what
//!   `lerp` produced, which is §5.4's hold-then-switch.
//! - **Only a key that moves.** A key whose two ends are equal keeps
//!   `lerp`'s exact copy: the OKLab round trip drifts by ~1e-7, and an
//!   untouched colour must stay what is stored, mid-action and in a
//!   split's second half.
//! - **Strictly inside.** Nothing is done unless `0 < u < 1`, so an
//!   action's first tick is its start exactly as stored and its end is its
//!   end.
//! - A non-finite result leaves the lerped value alone.
//!
//! **The invariant that makes this sound:** no object on a pointer's path
//! carries `kind` or `media` (`actions.rs`'s `OBJECT_DISCRIMINANTS`), and
//! none sits in a list, so `lerp_at` always walks to each colour (depth
//! ≤ 4, under `MAX_PATCH_DEPTH`) and the value overwritten here is that
//! walk's, never a whole object held at its start.

use serde_json::{Number, Value};

use crate::model_color::{oklab_mix_rgb, oklab_mix_unit};

/// Every four-channel colour an action's state holds, by key (spec §11 G-43).
pub(crate) const COLOR_POINTERS: [&str; 8] = [
    "/video/shadow/color",
    "/text/color",
    "/text/outline/color",
    "/text/backdrop/color",
    "/text/word_style/active_color",
    "/text/word_style/spoken_color",
    "/text/word_style/upcoming_color",
    "/text/word_style/active_pill/color",
];

/// `video.chroma.key`, the one three-channel colour (no alpha).
pub(crate) const CHROMA_KEY_POINTER: &str = "/video/chroma/key";

/// Overwrites each colour in `out` (the lerped state) with the OKLab blend of `from`'s and
/// `to`'s values at the same pointer, by eased progress `u`.
pub(crate) fn blend_colors(from: &Value, to: &Value, u: f64, out: &mut Value) {
    let inside = u > 0.0 && u < 1.0;
    if !inside {
        return;
    }
    for pointer in COLOR_POINTERS {
        if let Some((a, b)) = ends::<4>(from, to, pointer) {
            write(out, pointer, &oklab_mix_unit(a, b, u));
        }
    }
    if let Some((a, b)) = ends::<3>(from, to, CHROMA_KEY_POINTER) {
        write(out, CHROMA_KEY_POINTER, &oklab_mix_rgb(a, b, u));
    }
}

/// The two ends at `pointer` as colours of arity `N`, or `None` when
/// either does not read as one or they are the same numbers (compared
/// parsed, so a stored `1.0` and an end's `1` are one colour).
fn ends<const N: usize>(from: &Value, to: &Value, pointer: &str) -> Option<([f64; N], [f64; N])> {
    let a = channels::<N>(from.pointer(pointer)?)?;
    let b = channels::<N>(to.pointer(pointer)?)?;
    (a != b).then_some((a, b))
}

/// An array of exactly `N` numbers.
fn channels<const N: usize>(value: &Value) -> Option<[f64; N]> {
    let list = value.as_array()?;
    if list.len() != N {
        return None;
    }
    let mut out = [0.0; N];
    for (slot, element) in out.iter_mut().zip(list) {
        *slot = element.as_f64()?;
    }
    Some(out)
}

/// Writes `channels` as floats at `pointer`, when `out` has a value there
/// and every channel is finite.
fn write(out: &mut Value, pointer: &str, channels: &[f64]) {
    let Some(numbers) = channels
        .iter()
        .map(|&v| Number::from_f64(v).map(Value::Number))
        .collect::<Option<Vec<Value>>>()
    else {
        return;
    };
    if let Some(slot) = out.pointer_mut(pointer) {
        *slot = Value::Array(numbers);
    }
}
