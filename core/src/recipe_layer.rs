//! One recipe layer as the frame recipe publishes it (spec §7.3): the
//! struct both producers of layers build — `recipe.rs`'s `layer` and
//! `recipe_text.rs`'s burn-in — and the one place its keys are written.
//! `recipe.rs` re-exports it.

use serde_json::{Map, Value};

use crate::actions::{color_json, wheels_json};
use crate::evaluate::{json, number};
use crate::model::{BlendMode, Look, VideoProps};
use crate::nest::Frame;

/// The TWENTY-FOUR keys of a recipe layer (spec §7.3), and the one place they
/// are written.
///
/// It is a struct rather than twenty lines inside [`crate::model::Project::layer`] because
/// phase 7 gave the recipe a SECOND producer of layers — the burn-in
/// [`crate::recipe_text::burn_in_layer`] synthesizes, which belongs to no
/// clip — and a second literal copy of a twenty-four-key object is a copy that
/// drifts. It would drift SILENTLY, which is the part worth stating:
/// `FrameRecipe.swift`'s `RecipeLayer.init(from:)` reads every key
/// leniently and DEFAULTS a missing one with no diagnostic anywhere, so a
/// layer that forgot `blend` or `obscure` renders wrong rather than failing.
/// Adding a key here is the whole change; both producers get it.
///
/// The fields are what the two producers genuinely differ about. Everything
/// else is derived: the per-pixel groups all come off `video`, and the
/// placement and `clip_rect` both come off `placed`, because
/// [`Frame::place`] carries the rectangle through unchanged.
pub(crate) struct RecipeLayer<'a> {
    /// The clip that DRAWS — which for a nested layer is not a clip on the
    /// timeline, and is [`crate::recipe_text::BURN_IN_CLIP`] for a layer
    /// that came from no clip at all.
    pub clip: u32,
    pub source: Value,
    pub source_size: Value,
    /// Where crop, corner radius, the colour controls, the filters, the
    /// reflection, the spotlight and the obscured regions are read from.
    /// They are in SOURCE pixels or are per-pixel maths, so a nest's
    /// transform does not touch them: only the placement is folded.
    pub video: &'a VideoProps,
    /// The placement after every nest above this layer has been folded in —
    /// `x`, `y`, `scale`, `rotation`, `opacity`, and the `clip_rect` the
    /// innermost nest imposed.
    pub placed: Frame,
    /// Passed rather than read off `video`, because the recipe OVERRIDES
    /// it: see [`crate::model::Project::layer`], which forces `normal` under
    /// a transition and on a layer drawn into a matte (spec §11 MT-4).
    pub blend: BlendMode,
    pub transition: Value,
    /// `null`, or `{into, cut}` — the matte group this layer is drawn into
    /// and the groups that cut it (`recipe_matte.rs`, spec §7.3).
    pub matte: Value,
    /// `null`, or the routed dissolves and zooms this layer is a half of,
    /// outermost first (`recipe_dissolve.rs`, spec §7.3, §11 MT-8).
    pub dissolve: Value,
}

/// The layer's look as the compositor bakes and mixes it (spec §11 GR-7):
/// its kind, its amount and the core's definition — the colour with all
/// thirteen keys and the split tone — or `null` when there is none, when
/// its amount is 0 (a look-less layer, so the frame is byte-identical), or
/// when the frame is ungraded (`recipe.rs` removes it before this).
///
/// A LUT look (GR-8) has no definition: it is `{kind: "lut", amount,
/// media}`, and the app draws the table of that media's file. The evaluator
/// has already made a LUT look whose `media` is not a LUT of the project
/// `null` (`lut.rs`'s `evaluates_as_look`), so one that reaches here names
/// a LUT.
fn look_json(look: Option<Look>) -> Value {
    let Some(look) = look.filter(|look| look.amount > 0.0) else {
        return Value::Null;
    };
    let mut out = Map::new();
    out.insert("kind".to_string(), json(&look.kind));
    out.insert("amount".to_string(), number(look.amount));
    match look.kind.definition() {
        Some(definition) => {
            let mut body = Map::new();
            body.insert("color".to_string(), color_json(&definition.color));
            body.insert("split".to_string(), json(&definition.split));
            out.insert("definition".to_string(), Value::Object(body));
        }
        None => {
            let Some(media) = look.media else {
                return Value::Null;
            };
            out.insert("media".to_string(), Value::from(media));
        }
    }
    Value::Object(out)
}

impl RecipeLayer<'_> {
    /// The layer as the recipe publishes it.
    ///
    /// The insertions below follow the order spec §7.3 lists the keys in,
    /// and since `graphic` turned on `preserve_order` that IS the order on
    /// the wire. Nothing depends on it: Swift decodes by key, and
    /// [`crate::recipe::content_hash`] sorts before it hashes, so a key inserted in the
    /// wrong place here is a readability bug and not a cache-key change.
    pub(crate) fn object(self) -> Value {
        let video = self.video;
        let mut out = Map::new();
        out.insert("clip".to_string(), Value::from(self.clip));
        out.insert("source".to_string(), self.source);
        out.insert("source_size".to_string(), self.source_size);
        out.insert("crop".to_string(), json(&video.crop));
        out.insert("x".to_string(), number(self.placed.x));
        out.insert("y".to_string(), number(self.placed.y));
        out.insert("scale".to_string(), number(self.placed.scale));
        out.insert("rotation".to_string(), number(self.placed.rotation));
        out.insert("opacity".to_string(), number(self.placed.opacity));
        out.insert("blend".to_string(), json(&self.blend));
        out.insert("corner_radius".to_string(), number(video.corner_radius));
        out.insert("shadow".to_string(), json(&video.shadow));
        // All thirteen keys, tone's included at 0 (spec §11 GR-2).
        out.insert("color".to_string(), color_json(&video.color));
        // All nine wheel values, each at 0 when neutral (spec §11 GR-11).
        out.insert("wheels".to_string(), wheels_json(&video.wheels));
        out.insert("look".to_string(), look_json(video.look));
        out.insert("chroma".to_string(), json(&video.chroma));
        out.insert("filters".to_string(), json(&video.filters));
        out.insert("reflection".to_string(), json(&video.reflection));
        out.insert("spotlight".to_string(), json(&video.spotlight));
        out.insert("obscure".to_string(), json(&video.obscure));
        // The rotated canvas rectangle this layer is clipped to, or null.
        // Only a layer out of a nest has one — the nest's own canvas rect,
        // in the place the nest clip put it.
        out.insert(
            "clip_rect".to_string(),
            match self.placed.clip_rect {
                Some(rect) => json(&rect),
                None => Value::Null,
            },
        );
        out.insert("transition".to_string(), self.transition);
        out.insert("matte".to_string(), self.matte);
        out.insert("dissolve".to_string(), self.dissolve);
        Value::Object(out)
    }
}
