//! How a project's layers are blended (format version 24, spec §11 GR-18,
//! HD-9, HD-16): [`CanvasBlending`], the canvas's `blending` key.
//!
//! `encoded` is the default and every project before format 24: layers blend
//! on their encoded values (GR-3). `linear` decodes every layer to the
//! project's own transfer as scene light after its grade (the sRGB EOTF in
//! an SDR project, HLG's inverse OETF in an HLG one), blends there and
//! encodes once at the output pass. The field holding it is `Canvas.blending`
//! in `model.rs`, which re-exports this type; the recipe canvas carries it
//! only when linear (`recipe.rs`).
//!
//! Closed: a misspelt value is refused at the serde boundary naming both.

use serde::{Deserialize, Serialize};

/// A canvas's blending (spec §11 HD-16 (a)): `Encoded`, the default, or
/// `Linear`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CanvasBlending {
    #[default]
    Encoded,
    Linear,
}

impl CanvasBlending {
    /// Whether this is encoded blending: the `skip_serializing_if` on
    /// `Canvas.blending`, so an encoded project writes no key.
    pub fn is_encoded(&self) -> bool {
        *self == CanvasBlending::Encoded
    }
}
