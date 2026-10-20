//! Camera log's VOCABULARY (spec §11 GR-16, format version 19): the setting
//! a video media carries in `media.color`, re-exported by `model.rs`. What
//! the setting may hold, and every sentence refusing what it may not, is
//! `media_color.rs`; how step 0 converts with it is the app's
//! (`InputConversions.swift`). Format 22 adds a PQ file's HDR10 peak
//! (spec §11 HD-12): [`PqColor`] on `media.color.pq`, read at import
//! (`hdr10.rs`) with the person's override beside it. Format 25 adds Canon
//! Log 2 and Canon Log 3 (`canon_log2`, `canon_log3`) and their Cinema Gamut
//! (`cinema_gamut`), spec §11 HD-17.
//!
//! `LogCurve` and `CameraGamut` are closed vocabularies spelled as their
//! makers' documents name them. Their declaration order is NOT a shader
//! discriminant (the app maps each curve to its own kind), but
//! [`LogCurve::gamuts`]' FIRST entry is: it is the gamut an absent `gamut`
//! is stored as.

use serde::{Deserialize, Serialize};

/// A maker's published log curve. Apple Log 2 is Apple Log's curve with
/// Apple Wide Gamut (the Apple Log 2 white paper, GR-16's append), named
/// apart because a file's label names it apart. Canon Log 2 and Canon Log 3
/// are Canon's (its *Canon Log Gamma Curves* white paper, HD-17).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LogCurve {
    AppleLog,
    Slog3,
    Vlog,
    AppleLog2,
    CanonLog2,
    CanonLog3,
}

/// The camera gamut a log curve's signal is in, each with D65 white. Cinema
/// Gamut's chromaticities are the ACES project's Canon CSC's (HD-17 (a)).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CameraGamut {
    Bt2020,
    SGamut3Cine,
    SGamut3,
    VGamut,
    AppleWideGamut,
    CinemaGamut,
}

impl LogCurve {
    /// The gamuts the curve pairs with, its default first: Apple Log with
    /// BT.2020, Apple Log 2 with Apple Wide Gamut, S-Log3 with S-Gamut3.Cine
    /// or S-Gamut3, V-Log with V-Gamut (GR-16); Canon Log 2 and Canon Log 3
    /// each with Cinema Gamut or BT.2020 (HD-17).
    pub const fn gamuts(self) -> &'static [CameraGamut] {
        match self {
            LogCurve::AppleLog => &[CameraGamut::Bt2020],
            LogCurve::AppleLog2 => &[CameraGamut::AppleWideGamut],
            LogCurve::Slog3 => &[CameraGamut::SGamut3Cine, CameraGamut::SGamut3],
            LogCurve::Vlog => &[CameraGamut::VGamut],
            LogCurve::CanonLog2 | LogCurve::CanonLog3 => {
                &[CameraGamut::CinemaGamut, CameraGamut::Bt2020]
            }
        }
    }
}

/// The smallest and largest PQ peak a media may hold, in cd/m² (spec §11
/// HD-12): PQ's own range, SMPTE ST 2084 reaching 10,000. The one home of
/// both; the reader clamps to them and the rules refuse outside them.
pub const PEAK_MIN: u32 = 1;
pub const PEAK_MAX: u32 = 10_000;

/// Which HDR10 field gave a PQ file's peak: CTA-861.3's MaxCLL, or SMPTE
/// ST 2086's mastering-display maximum when there is no MaxCLL (HD-6).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PeakSource {
    MaxCll,
    MasteringDisplay,
}

/// A PQ file's HDR10 peak (spec §11 HD-12): `file`, what import read, in
/// whole cd/m², with `from` naming its field (present exactly when `file`
/// is); `peak`, the person's override. Each key is written only when set, so
/// a PQ file whose import read nothing stores `{}` — which still says the
/// media IS a PQ file, the one a peak may be set on.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct PqColor {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from: Option<PeakSource>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub peak: Option<u32>,
}

impl PqColor {
    /// The peak step 0 uses: the override, else the file's; `None` means
    /// the app's 1,000 cd/m².
    pub fn effective(&self) -> Option<u32> {
        self.peak.or(self.file)
    }
}

/// A video media's camera-log setting: a built-in curve and its gamut, or a
/// `lut` media used as the input conversion instead; `detected` is true
/// when import read it from the file's label; `pq` a PQ file's peak (format
/// 22). Each key is written only when set (`detected` only when true), and
/// `media.color` itself only when the media has one, so a project with none
/// writes the text it did before version 19.
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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pq: Option<PqColor>,
}

impl MediaColor {
    /// The setting with its Camera Log taken away and its PQ peak kept:
    /// `Some({pq})` for a PQ file, else `None` — what removing a converting
    /// LUT, or a paste that leaves its LUT behind, leaves on the media.
    pub fn without_camera_log(self) -> Option<MediaColor> {
        self.pq.map(|pq| MediaColor {
            pq: Some(pq),
            ..MediaColor::default()
        })
    }
}

fn is_false(value: &bool) -> bool {
    !*value
}
