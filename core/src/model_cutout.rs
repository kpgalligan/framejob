//! The cutout's model vocabulary (format 39, spec §11 CO-20): [`Cutout`], a
//! clip's `video.cutout` — Remove Background, the clip's own layer drawn as
//! its subject alone or whole — with [`CutoutSubject`], [`CutoutQuality`],
//! [`CutoutBackground`] and the ranges `cutout_check.rs` checks and clamps
//! to.
//!
//! Re-exported whole by `model_props.rs` (and so by `model.rs`), so every
//! `crate::model::Cutout` path resolves. What the recipe makes of it is
//! `recipe_layer.rs`'s `layer_cutout` (CO-21). The JSON spelling of each enum
//! variant is persisted: append, never rename.

use serde::{Deserialize, Serialize};

/// `video.cutout.edge`'s range: the outline shrunk (below 0) or grown
/// (above 0) (CO-20).
pub const CUTOUT_EDGE_MIN: f64 = -1.0;
pub const CUTOUT_EDGE_MAX: f64 = 1.0;
/// `video.cutout.feather`'s upper bound; its lower is 0 (CO-20).
pub const CUTOUT_FEATHER_MAX: f64 = 1.0;

/// What the mask finds: a person (CO-1). CO10 appends `foreground`.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CutoutSubject {
    #[default]
    Person,
}

/// Which masks: Standard, or Best (CO4's). A file's `best` reads; the ops
/// refuse it until Best masks are made (CO-20).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CutoutQuality {
    #[default]
    Standard,
    Best,
}

/// What the layer draws: its subject alone, or whole — the subject still
/// hiding Behind Subject clips (CO-20).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CutoutBackground {
    #[default]
    Remove,
    Keep,
}

/// A clip's `video.cutout` (CO-20), every field written in this order; `{}`
/// reads as the defaults. The key's presence, `subject` and `quality` are
/// the clip's own — the evaluator restores the base over any action's end
/// (`cutout_check.rs`'s `restore_base_cutout`); `edge` and `feather`
/// animate and `background` switches at an action's end.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Cutout {
    pub subject: CutoutSubject,
    pub quality: CutoutQuality,
    pub background: CutoutBackground,
    /// −1…1.
    pub edge: f64,
    /// 0…1.
    pub feather: f64,
}

impl Default for Cutout {
    fn default() -> Self {
        Cutout {
            subject: CutoutSubject::Person,
            quality: CutoutQuality::Standard,
            background: CutoutBackground::Remove,
            edge: 0.0,
            feather: 0.0,
        }
    }
}
