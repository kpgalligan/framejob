//! An HLG project's deliverables (spec §11 HD-5, HD-14): which picture an
//! export row writes — the HLG master, HDR10 (PQ) or the SDR version — and the
//! two refusals that keep a file from carrying a picture it cannot label.
//!
//! The vocabulary is three words, `hlg`, `pq` and `sdr`, spelled
//! `dynamic_range` both as an export override (`export_overrides.rs` reads it)
//! and as a recipe option (`recipe_options.rs`), because the two are one
//! decision seen from two sides: the export publishes its settings' `color` as
//! the recipe option of the key it draws, so the output pass the preview draws
//! for Show SDR Version is the one the file is written through.
//!
//! An SDR project is untouched by all of it: `deliverable` answers `None` for
//! every row there, so its settings carry no `color` and its recipes no
//! `dynamic_range`, and every SDR file and frame is the text and the bytes it
//! was.

use crate::export_table::Preset;
use crate::model::{CanvasOutput, Project};

/// The picture an HLG project's export or frame is drawn as (spec §11 HD-14).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DynamicRange {
    /// The working space itself, BT.2100 HLG: no output pass.
    Hlg,
    /// HDR10: the HLG display light at 1,000 cd/m² through ST 2084.
    Pq,
    /// The SDR version (spec §11 HD-4): the inverse of the lift with a
    /// shoulder above reference white, encoded Rec. 709.
    Sdr,
}

impl DynamicRange {
    /// The word for `text`, or `None` for anything else.
    pub fn parse(text: &str) -> Option<DynamicRange> {
        match text {
            "hlg" => Some(DynamicRange::Hlg),
            "pq" => Some(DynamicRange::Pq),
            "sdr" => Some(DynamicRange::Sdr),
            _ => None,
        }
    }

    /// The word as it is spelled in JSON.
    pub fn as_str(self) -> &'static str {
        match self {
            DynamicRange::Hlg => "hlg",
            DynamicRange::Pq => "pq",
            DynamicRange::Sdr => "sdr",
        }
    }
}

/// The rows that carry an HDR picture (spec §11 HD-5, CX-14, CX-15, CX-16):
/// the six HDR rows, each 10-bit for an HDR picture (`vp9_webm` is 8-bit only
/// at `sdr`). Every other video row of an HLG project writes the SDR version.
pub(crate) const HDR_ROWS: [&str; 6] = [
    "hevc_10bit",
    "av1",
    "av1_webm",
    "vp9_webm",
    "prores_422",
    "prores_4444",
];

impl Project {
    /// What `preset` writes for this project when `asked` was requested
    /// (spec §11 HD-14 (c)): `None` for an audio row and for every row of an
    /// SDR project (nothing to label), else the resolved picture. An audio row
    /// reads the argument and ignores it, as a bitrate on a GIF is; an SDR
    /// project takes `sdr` as nothing; `hlg` and `pq` are refused in an SDR
    /// project and on a row that is not 10-bit, each in its own sentence.
    pub(crate) fn deliverable(
        &self,
        preset: &Preset,
        asked: Option<DynamicRange>,
    ) -> Result<Option<DynamicRange>, String> {
        if !preset.video {
            return Ok(None);
        }
        let hdr_asked = asked.filter(|range| *range != DynamicRange::Sdr);
        if self.canvas.output != CanvasOutput::Hlg {
            return match hdr_asked {
                Some(range) => Err(format!(
                    "dynamic_range \"{}\" needs an HLG project; set_canvas output \"hlg\" first",
                    range.as_str()
                )),
                None => Ok(None),
            };
        }
        if HDR_ROWS.contains(&preset.id) {
            return Ok(Some(asked.unwrap_or(DynamicRange::Hlg)));
        }
        match hdr_asked {
            Some(range) => Err(format!(
                "{} is 8-bit and writes the SDR version; export dynamic_range \"{}\" as \
                 hevc_10bit, av1, av1_webm, vp9_webm, prores_422 or prores_4444",
                preset.id,
                range.as_str()
            )),
            None => Ok(Some(DynamicRange::Sdr)),
        }
    }
}
