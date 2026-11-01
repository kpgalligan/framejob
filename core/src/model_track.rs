//! A track — spec §5.2's `tracks[]` and a nest's own tracks — moved out of
//! `model.rs` whole (a pure move), which re-exports it, so every
//! `crate::model::Track` path holds. The track vocabulary's new keys land
//! here: format 35's `volume` and `pan` (spec §11 AU-102), each written only
//! when not its default, and format 36's `compressor` and `limiter` (AU-150),
//! each written only when set.

use serde::{Deserialize, Serialize};

use crate::model::{Compressor, Limiter, TrackMatte};

/// One kind of track only (spec §2): any clip may live on any track, and
/// a later index in `Project::tracks` draws in front.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Track {
    pub id: u32,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub hidden: bool,
    #[serde(default)]
    pub muted: bool,
    /// Locked tracks are skipped by ripple, insert-time and hit-testing.
    #[serde(default)]
    pub locked: bool,
    /// Solo (format version 3): while ANY track in this container — the
    /// timeline, or one nest's own tracks — is soloed, every track that is
    /// not is silent, and a track that is both muted and soloed stays
    /// silent, because mute wins. Audio only: a solo hides nothing, and it
    /// is applied as a gain envelope in `audio.rs`, never in the plan.
    #[serde(default)]
    pub solo: bool,
    /// Matte (format version 14, spec §11 MT-1): `none` is an ordinary
    /// track; any other mode makes the track's clips draw nothing on the
    /// canvas and cut the track directly behind (MT-2, MT-3). Written only
    /// when not `none` — this file's one `skip_serializing_if`, the model's
    /// first (tone's nine keys in `model_props.rs` are the rest) — so an
    /// ordinary track and every older file round-trip byte for byte.
    #[serde(default, skip_serializing_if = "TrackMatte::is_none")]
    pub matte: TrackMatte,
    /// The track's fader (format version 35, spec §11 AU-102, AU-103):
    /// linear, 0…[`TRACK_VOLUME_MAX`], default 1, an envelope term after the
    /// track's mute in `audio.rs`. Written only when not 1.
    #[serde(default = "unity", skip_serializing_if = "is_unity")]
    pub volume: f64,
    /// The track's pan (format version 35, AU-104): −1 hard left … 1 hard
    /// right, default 0, a balance by the app's pan law carried in the plan as
    /// an audio segment's `track_pans`. Written only when not 0.
    #[serde(default, skip_serializing_if = "is_centre")]
    pub pan: f64,
    /// The track's compressor (format version 36, spec §11 AU-150, AU-151):
    /// the clip's own type, run post-fader on the track's sub-mix before its
    /// limiter. Timeline tracks only: on a nest's own track it is ignored
    /// where it plays. Written only when set.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub compressor: Option<Compressor>,
    /// The track's true-peak limiter (format version 36, AU-150, AU-151):
    /// the ceiling in dBTP on what the track hands the mix, after its
    /// compressor. Timeline tracks only. Written only when set.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub limiter: Option<Limiter>,
}

/// A track's loudest fader: ×4, +12.04 dB (spec §11 AU-102). `set_track`
/// refuses above it and `audio_track.rs` clamps a hand-written value to it.
pub const TRACK_VOLUME_MAX: f64 = 4.0;

fn unity() -> f64 {
    1.0
}

/// The `skip_serializing_if` on `Track.volume`: a track at unity writes no key.
fn is_unity(volume: &f64) -> bool {
    *volume == 1.0
}

/// The `skip_serializing_if` on `Track.pan`: a centred track writes no key.
fn is_centre(pan: &f64) -> bool {
    *pan == 0.0
}
