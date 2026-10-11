//! The two qualifier options of a recipe (spec §11 GR-13): `selection`,
//! Show Selection's, and `behind`, Pick from Canvas's — both a question
//! about ONE top-level adjustment clip and the layers in front of it,
//! answered here over the finished layer list so `recipe.rs` takes one
//! call.
//!
//! - **`selection: N`** marks clip N's adjustment layer (`"selection":
//!   true` in its source, which the compositor reads as "write `q` ×
//!   coverage as opaque grey instead of grading") and leaves out every
//!   later layer — everything drawn in front of it — so the grey is not
//!   covered. No such layer on the frame (the clip is outside its span,
//!   deleted, or not an adjustment clip) answers no layers at all, and
//!   `recipe.rs` then writes a black background: the selection of a clip
//!   that is not there is nothing.
//! - **`behind: N`** leaves out that layer and every later one, so the
//!   frame is the picture the clip READS — what a pick samples. No such
//!   layer leaves the list as it was.
//!
//! A layer drawn INTO a matte is never left out, in front or not: a matte
//! track over the adjustment clip is what limits it (`q` × coverage), and
//! the coverage needs its layers. Matte and dissolve ids are not
//! renumbered; an id whose layers went with the rest names nothing drawn.
//! With neither option set the list comes back untouched, so every
//! recipe without them is byte-identical to the one before they existed.

use serde_json::Value;

use crate::recipe::RecipeOptions;

/// What [`select_layers`] needs of each layer, in the layer list's order:
/// its clip, whether it is an adjustment clip at the top level (the only
/// kind either option names — an adjustment clip cannot be nested, GR-6),
/// and whether it is drawn into a matte rather than onto the canvas.
pub(crate) struct LayerFacts {
    pub clip: u32,
    pub top_adjustment: bool,
    pub drawn_into: bool,
}

/// The layers `opts` asks for and whether the frame is the black of a
/// selection whose clip is not on it (module doc).
pub(crate) fn select_layers(
    layers: Vec<Value>,
    facts: &[LayerFacts],
    opts: &RecipeOptions,
) -> (Vec<Value>, bool) {
    if let Some(clip) = opts.selection {
        let Some(at) = position(facts, clip) else {
            return (Vec::new(), true);
        };
        let mut kept = keep_behind(layers, facts, at + 1);
        if let Some(Value::Object(source)) = kept.get_mut(at).and_then(|l| l.get_mut("source")) {
            source.insert("selection".to_string(), Value::Bool(true));
        }
        return (kept, false);
    }
    if let Some(clip) = opts.behind {
        if let Some(at) = position(facts, clip) {
            return (keep_behind(layers, facts, at), false);
        }
    }
    (layers, false)
}

/// Where clip `clip`'s top-level adjustment layer sits, if it is drawn.
fn position(facts: &[LayerFacts], clip: u32) -> Option<usize> {
    facts
        .iter()
        .position(|fact| fact.clip == clip && fact.top_adjustment)
}

/// The first `keep` layers, then only the later layers drawn into a matte.
/// The ones kept before `keep` are untouched, so the marked layer keeps its
/// index.
fn keep_behind(layers: Vec<Value>, facts: &[LayerFacts], keep: usize) -> Vec<Value> {
    layers
        .into_iter()
        .zip(facts)
        .enumerate()
        .filter(|(index, (_, fact))| *index < keep || fact.drawn_into)
        .map(|(_, (layer, _))| layer)
        .collect()
}
