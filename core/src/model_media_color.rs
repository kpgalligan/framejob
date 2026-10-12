//! Camera log's VOCABULARY (spec §11 GR-16, format version 19): the setting
//! a video media carries in `media.color`, re-exported by `model.rs`. What
//! the setting may hold, and every sentence refusing what it may not, is
//! `media_color.rs`; how step 0 converts with it is the app's
//! (`InputConversions.swift`).
//!
//! `LogCurve` and `CameraGamut` are closed vocabularies spelled as their
//! makers' documents name them. Their declaration order is NOT a shader
//! discriminant (the app maps each curve to its own kind), but
//! [`LogCurve::gamuts`]' FIRST entry is: it is the gamut an absent `gamut`
//! is stored as.

use serde::{Deserialize, Serialize};

/// A maker's published log curve. Apple Log 2 is Apple Log's curve with
/// Apple Wide Gamut (the Apple Log 2 white paper, GR-16's append), named
/// apart because a file's label names it apart.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LogCurve {
    AppleLog,
    Slog3,
    Vlog,
    AppleLog2,
}

/// The camera gamut a log curve's signal is in, each with D65 white.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CameraGamut {
    Bt2020,
    SGamut3Cine,
    SGamut3,
    VGamut,
    AppleWideGamut,
}

impl LogCurve {
    /// The gamuts the curve pairs with, its default first: Apple Log with
    /// BT.2020, Apple Log 2 with Apple Wide Gamut, S-Log3 with S-Gamut3.Cine
    /// or S-Gamut3, V-Log with V-Gamut (GR-16).
    pub const fn gamuts(self) -> &'static [CameraGamut] {
        match self {
            LogCurve::AppleLog => &[CameraGamut::Bt2020],
            LogCurve::AppleLog2 => &[CameraGamut::AppleWideGamut],
            LogCurve::Slog3 => &[CameraGamut::SGamut3Cine, CameraGamut::SGamut3],
            LogCurve::Vlog => &[CameraGamut::VGamut],
        }
    }
}

/// A video media's camera-log setting: a built-in curve and its gamut, or a
/// `lut` media used as the input conversion instead; `detected` is true
/// when import read it from the file's label. Each key is written only when
/// set (`detected` only when true), and `media.color` itself only when the
/// media has one, so a project with none writes the text it did before
/// version 19.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct MediaColor {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub log: Option<LogCurve>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gamut: Option<CameraGamut>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lut: Option<u32>,
    #[serde(skip_serializing_if = "is_false")]
    pub detected: bool,
}

fn is_false(value: &bool) -> bool {
    !*value
}
