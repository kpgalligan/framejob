//! The matte vocabulary (format version 14, spec §11 MT-1): [`TrackMatte`],
//! what a track's clips do to the track directly behind it.
//!
//! A matte is a TRACK relation, not a clip property: a clip is a matte only
//! by the track it sits on, so moving it off makes it ordinary and no clip
//! ever names another (MT-2). The field holding it is `Track.matte` in
//! `model.rs`; what a matte cuts at an instant is `recipe_matte.rs`'s.
//!
//! Re-exported whole by `model_props.rs`, which `model.rs` re-exports whole
//! in turn, so `crate::model::TrackMatte` resolves like every other
//! property type.
//!
//! **The declaration ORDER is a shader discriminant** (MT-3): `none` is 0
//! and `luma_inverted` 4, `TrackMatte.shaderCode` on the Swift side is the
//! case index and `Compositor.metal`'s `kMatte*` constants compare against
//! the same integers — so a mode is appended, never inserted, like
//! [`crate::model::BlendMode`]'s and [`crate::model::ObscureKind`]'s. The
//! JSON spelling of each variant is persisted, so a rename needs a migration
//! step. Closed: a misspelt mode is refused at the serde boundary naming the
//! five, because there is no neutral matte to fall back to.

use serde::{Deserialize, Serialize};

/// How a matte track's picture cuts the track directly behind it (MT-3):
/// by its alpha, its inverted alpha, its Rec. 709 luma or its inverted
/// luma. `None` — the default — is an ordinary track.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TrackMatte {
    #[default]
    None,
    Alpha,
    AlphaInverted,
    Luma,
    LumaInverted,
}

impl TrackMatte {
    /// Whether this is an ordinary track. The `skip_serializing_if` on
    /// `Track.matte`, so an ordinary track writes no key and every older
    /// file round-trips byte for byte (MT-1).
    pub fn is_none(&self) -> bool {
        *self == TrackMatte::None
    }
}
