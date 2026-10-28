//! The bundled encoders a row's video can take (spec §11 CX-12): the route,
//! [`Writer`], and the speed vocabulary, [`EncoderSpeed`].
//!
//! Moved whole out of `export_table.rs` under the size rule (core/CLAUDE.md:
//! a module at ~600 lines gives something up BEFORE it takes anything on),
//! as codec-export C3's toll T1, a pure move. `export_table.rs` re-exports
//! both, so every `crate::export_table::Writer` and
//! `crate::export_table::EncoderSpeed` path holds.

/// The route a row's video takes when it is not AVFoundation's own
/// encoder (spec §11 CX-12 (1)): `None` on a row means VideoToolbox or
/// ProRes through `AVAssetWriter`, or ImageIO where `avf_preset` is null.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Writer {
    /// SVT-AV1, bundled and called from Swift (CX-2, CX-4).
    SvtAv1,
    /// libvpx's VP9, bundled and called from Swift (CX-3, CX-4, CX-16).
    Libvpx,
}

impl Writer {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Writer::SvtAv1 => "svt_av1",
            Writer::Libvpx => "libvpx",
        }
    }

    /// Whether the encoder has speeds to choose from: SVT-AV1's three
    /// (CX-2), and not libvpx's one (CX-3, CX-16 (2)).
    pub(crate) fn takes_speed(self) -> bool {
        match self {
            Writer::SvtAv1 => true,
            Writer::Libvpx => false,
        }
    }
}

/// A bundled encoder's speed (spec §11 CX-2, CX-12 (2)): Faster, Balanced
/// and Smaller file are SVT-AV1's presets 8, 6 and 4 — the number is the
/// app's to map, the word is the vocabulary the sheet and `export` share.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum EncoderSpeed {
    Faster,
    Balanced,
    Smaller,
}

impl EncoderSpeed {
    /// Every speed, in the sheet's order.
    pub(crate) const ALL: [EncoderSpeed; 3] = [
        EncoderSpeed::Faster,
        EncoderSpeed::Balanced,
        EncoderSpeed::Smaller,
    ];

    pub(crate) fn parse(text: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|speed| speed.as_str() == text)
    }

    pub(crate) fn as_str(self) -> &'static str {
        match self {
            EncoderSpeed::Faster => "faster",
            EncoderSpeed::Balanced => "balanced",
            EncoderSpeed::Smaller => "smaller",
        }
    }
}
