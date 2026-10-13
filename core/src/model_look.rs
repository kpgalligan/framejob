//! The look vocabulary (spec §11 GR-7, format 15):
//! [`Look`], the `video.look` a clip carries — one of the eight built-in
//! [`LookKind`]s or an imported `.cube` LUT (`lut`, GR-8, naming its media),
//! and how much of it — and each built-in kind's [`LookDefinition`], the
//! DATA the compositor bakes.
//!
//! **Rust decides, Metal does** (spec §7): a look is defined here, as Color's
//! four keys, Light's nine and a [`SplitTone`], and published in the recipe
//! as that definition; the app bakes it on the GPU into a 33³ lattice with
//! the layer stage's own functions and mixes it at step 4d. Nothing here is
//! a colour table: the eight are Frame Job's own first numbers (tuned by the
//! owner at GR7), built from the textbook operations tone already uses — the
//! Concat rule (`designs/adr/effects-survey.md`) stands.
//!
//! Re-exported whole by `model_props.rs`, which `model.rs` re-exports whole
//! in turn, so `crate::model::Look` resolves like every other property type.
//!
//! **The declaration ORDER of [`LookKind`] is the gallery's and the menu's**
//! (GR-7): append, never reorder; `Lut` comes last and is not one of
//! [`LookKind::BUILT_IN`]. The JSON spelling of each variant is persisted, so
//! a rename needs a migration step. Closed: a misspelt kind is refused at the
//! serde boundary naming the nine, because there is no neutral look to fall
//! back to — "no look" is `video.look` absent. What `media` must name, and
//! when, is `lut.rs`'s.

use serde::{Deserialize, Serialize};

use crate::model::ColorAdjust;

/// The amount a look takes when a patch names only its kind: all of it
/// (GR-7 choice 2).
pub const LOOK_DEFAULT_AMOUNT: f64 = 1.0;

fn default_look_amount() -> f64 {
    LOOK_DEFAULT_AMOUNT
}

/// The eight built-in looks, in the gallery's order (GR-7 choice 1), and
/// `Lut`, an imported `.cube` file (GR-8), whose table is the media's.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LookKind {
    Warm,
    Cool,
    TealOrange,
    Vivid,
    Faded,
    Vintage,
    Dramatic,
    BlackWhite,
    Lut,
}

/// A clip's look: which, and how much (0…1, `props_check.rs` refuses
/// outside it). `kind` has NO default, so a `look` without one does not read
/// — a patch naming only an amount on a clip that has no look is refused,
/// and an action's end that does so evaluates as no look (`actions.rs`).
/// `media` is the LUT's media id, with `Lut` only (GR-8; `lut.rs` holds the
/// rule), written between `kind` and `amount` and only when set.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Look {
    pub kind: LookKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub media: Option<u32>,
    #[serde(default = "default_look_amount")]
    pub amount: f64,
}

/// Two hues pushed into the shadows and the highlights, the one building
/// block a look has that Light does not (GR-7 choice 4). Hues in degrees,
/// amounts 0…1; the bake weights each by (1 − Y)² and Y², Y the luma.
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize)]
pub struct SplitTone {
    pub shadow_hue: f64,
    pub shadow_amount: f64,
    pub highlight_hue: f64,
    pub highlight_amount: f64,
}

/// What a look IS: the colour, tone and split tone its lattice is baked
/// from. Published in the recipe under the layer's `look` key.
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize)]
pub struct LookDefinition {
    pub color: ColorAdjust,
    pub split: SplitTone,
}

impl LookKind {
    /// The eight built-in kinds, in declaration order (`Lut` is not one).
    pub const BUILT_IN: [LookKind; 8] = [
        LookKind::Warm,
        LookKind::Cool,
        LookKind::TealOrange,
        LookKind::Vivid,
        LookKind::Faded,
        LookKind::Vintage,
        LookKind::Dramatic,
        LookKind::BlackWhite,
    ];

    /// The kind's definition — GR-7's table, every unlisted value 0; `None`
    /// for `Lut`, whose table is a file's.
    pub fn definition(self) -> Option<LookDefinition> {
        let neutral = ColorAdjust::default();
        let none = SplitTone::default();
        let (color, split) = match self {
            LookKind::Lut => return None,
            LookKind::Warm => (
                ColorAdjust {
                    temperature: 0.35,
                    tint: 0.05,
                    vibrance: 0.10,
                    ..neutral
                },
                SplitTone {
                    highlight_hue: 40.0,
                    highlight_amount: 0.25,
                    ..none
                },
            ),
            LookKind::Cool => (
                ColorAdjust {
                    temperature: -0.35,
                    contrast: 0.05,
                    ..neutral
                },
                SplitTone {
                    shadow_hue: 215.0,
                    shadow_amount: 0.30,
                    ..none
                },
            ),
            LookKind::TealOrange => (
                ColorAdjust {
                    contrast: 0.15,
                    vibrance: 0.20,
                    ..neutral
                },
                SplitTone {
                    shadow_hue: 190.0,
                    shadow_amount: 0.60,
                    highlight_hue: 35.0,
                    highlight_amount: 0.45,
                },
            ),
            LookKind::Vivid => (
                ColorAdjust {
                    contrast: 0.15,
                    saturation: 0.10,
                    vibrance: 0.40,
                    whites: 0.20,
                    blacks: -0.20,
                    ..neutral
                },
                none,
            ),
            LookKind::Faded => (
                ColorAdjust {
                    contrast: -0.15,
                    saturation: -0.25,
                    highlights: -0.15,
                    fade: 0.60,
                    ..neutral
                },
                none,
            ),
            LookKind::Vintage => (
                ColorAdjust {
                    contrast: -0.05,
                    saturation: -0.30,
                    temperature: 0.25,
                    fade: 0.40,
                    ..neutral
                },
                SplitTone {
                    shadow_hue: 160.0,
                    shadow_amount: 0.30,
                    highlight_hue: 50.0,
                    highlight_amount: 0.35,
                },
            ),
            LookKind::Dramatic => (
                ColorAdjust {
                    exposure: -0.25,
                    contrast: 0.25,
                    saturation: -0.35,
                    highlights: -0.20,
                    shadows: -0.20,
                    ..neutral
                },
                SplitTone {
                    shadow_hue: 220.0,
                    shadow_amount: 0.20,
                    ..none
                },
            ),
            LookKind::BlackWhite => (
                ColorAdjust {
                    saturation: -1.0,
                    contrast: 0.20,
                    whites: 0.10,
                    blacks: -0.10,
                    ..neutral
                },
                none,
            ),
        };
        Some(LookDefinition { color, split })
    }
}
