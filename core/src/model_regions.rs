//! The regions a layer's picture carries — [`Spotlight`],
//! [`ObscureRegion`], the [`SpotShape`] both are drawn with and the
//! [`MAX_OBSCURE`] budget on the second (spec §4.2, §5.2).
//!
//! Split out of `model_props.rs` under the size rule (core/CLAUDE.md: a
//! module over ~600 lines gives something up before it takes anything on)
//! when road map 2's phase 3c added `video.obscure` and pushed it over.
//! `model.rs` → `model_query.rs` in phase 0, and `model.rs` →
//! `model_props.rs` in phase 2, are the precedent, and so is their rule:
//! the cut goes along a seam somebody can NAME, and the piece taken out is
//! re-exported whole so not one path anywhere else changes.
//!
//! # The seam: one frame, one shape
//!
//! These are not three property types that happened to be adjacent. A
//! region is a box drawn ON the picture, and every box here is in the same
//! frame:
//!
//! > `x` and `y` are the region's CENTRE, as an offset in SOURCE pixels
//! > from the centre of the layer's CROPPED rect, y down; `width` and
//! > `height` are its size in those same pixels.
//!
//! Nothing here is in canvas pixels, and nothing here is a fraction of
//! anything. That is deliberate and it is the whole reason the frame is
//! worth a module of its own: a box in source pixels rides with the layer
//! it was drawn on, through `scale`, `x`/`y`, `rotation` and a nest's
//! transform, so the region stays on the face — or the password field, or
//! the notification — it was put on. A layer's own crop is the only edit
//! that moves it, which is why the origin is the CROPPED rect's centre and
//! not the source's: crop trims in place (see [`crate::model::Crop`]), so
//! measuring from the trimmed centre is what keeps a centred region
//! centred. `edit_zoom.rs` calls this frame Q and writes out the equation
//! that turns a length in it into canvas pixels; that module doc is the
//! canonical derivation and nothing here repeats it.
//!
//! The second half of the seam is [`SpotShape`]. A region needs a distance
//! field to feather against, both of these need the same two — a rectangle
//! and an ellipse — and shared vocabulary has exactly one home
//! (core/CLAUDE.md). Two enums naming the same two shapes would be two
//! things to keep in step in Rust, in `ProjectSnapshot.swift`, in the
//! agent's enum check and in `Compositor.metal`.
//!
//! What is NOT here: the fields that HOLD these values —
//! `VideoProps.spotlight` and `VideoProps.obscure` — which are part of the
//! video group's own shape and stay in `model_props.rs` with it; and every
//! effect that acts on the whole layer rather than a box inside it
//! (filters, chroma key, colour, reflection, shadow), which have no frame
//! to share.
//!
//! # Paths
//!
//! `model_props.rs` re-exports this module whole with
//! `pub use crate::model_regions::*`, and `model.rs` re-exports
//! `model_props.rs` the same way, so `crate::model_props::Spotlight`,
//! `crate::model::Spotlight` and the crate-root re-exports in `lib.rs` all
//! still resolve and no other file needed an import changed. The schema
//! rules are `model.rs`'s too: the field names ARE the JSON keys,
//! declaration order IS key order, every type is `#[serde(default)]` over a
//! hand-written [`Default`] that says what an absent key means, and nothing
//! here carries `deny_unknown_fields`.

use serde::{Deserialize, Serialize};

/// Darkens the canvas outside a rectangle or ellipse, optionally magnifying
/// what is inside it (spec §4.2, M3) — the stand-in for a screencast editor's
/// freehand callout that works on any footage.
///
/// A `video` prop, not a `shape` one, though spec §4.2 first listed it
/// under Shape: the zoom half can only be drawn by the layer that owns the
/// pixels, so it lives beside chroma key, filters and reflection.
///
/// The centre and the box are SOURCE pixels measured from the centre of the
/// layer's cropped rect — the same frame `corner_radius` and `crop` use —
/// so a spotlight stays on the face it was put on when the layer is scaled,
/// moved or rotated.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Spotlight {
    pub shape: SpotShape,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    /// Source pixels the edge is blurred over; 0 is a hard edge.
    pub feather: f64,
    /// How much darker everything OUTSIDE is: 0 changes nothing, 1 is
    /// black.
    pub dim: f64,
    /// Magnification INSIDE the region. 1 is no zoom, which is why the
    /// range starts there and not at 0.
    pub zoom: f64,
}

impl Default for Spotlight {
    /// A 480 × 270 window — a 16:9 quarter of a 1080p source — centred, at
    /// the spec's "darkens the canvas outside" with no zoom.
    fn default() -> Self {
        Spotlight {
            shape: SpotShape::Rect,
            x: 0.0,
            y: 0.0,
            width: 480.0,
            height: 270.0,
            feather: 40.0,
            dim: 0.6,
            zoom: 1.0,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpotShape {
    #[default]
    Rect,
    Ellipse,
}

/// The most hidden regions one layer may carry.
///
/// A SHADER BUDGET, exactly as [`crate::model::MAX_FILTERS`] is: the
/// uniform block carries four regions and the fragment stage applies them
/// in a fixed unrolled order, so a fifth has nowhere to go. `set_video`
/// names the overflow rather than dropping it, and the reason is sharper
/// here than it is for a filter — a region the user drew over a face and
/// cannot see is not a control that does nothing, it is the face still on
/// screen.
pub const MAX_OBSCURE: usize = 4;

/// One region of the picture hidden behind a blur or a pixelation (road map
/// 2, phase 3c) — the spotlight's inverse. A face, a password field, a
/// notification that slid in halfway through the take.
///
/// The geometry is [`Spotlight`]'s frame, and the paragraph above that type
/// is its canonical statement: `x`/`y` are the region's CENTRE as an offset
/// in SOURCE pixels from the centre of the layer's cropped rect, `width`
/// and `height` its size in the same pixels. So a region rides with its
/// layer through scale, move and rotation, and stays on the face it was put
/// on. Nothing here is in canvas pixels, and a nest's transform folds into
/// the layer around it rather than into this box.
///
/// `shape` is [`SpotShape`] — the spotlight's own rect/ellipse, reused
/// rather than copied. It is the same vocabulary naming the same distance
/// field, and shared vocabulary has exactly one home (core/CLAUDE.md); if
/// the two ever have to diverge, splitting an enum is a rename, while
/// merging two is a schema migration.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct ObscureRegion {
    pub shape: SpotShape,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    /// Source pixels the effect is ramped in over; 0 is a hard edge.
    pub feather: f64,
    pub kind: ObscureKind,
    /// 0 = the region is there but hides nothing, 1 = its full effect.
    pub amount: f64,
}

impl Default for ObscureRegion {
    /// A 480 × 270 window, centred — [`Spotlight`]'s own default box, so
    /// the two region controls put the SAME rectangle on screen and a user
    /// who has met one recognises the other — pixelated at full strength.
    ///
    /// The kind and the amount are the opposite of
    /// [`crate::model::Filter`]'s half-strength blur, for the opposite
    /// reason. A filter has to be visible without destroying the frame; a
    /// region that only half hides has failed at the one job this feature
    /// has, so its default is the setting that actually hides. Between the
    /// two kinds that is `pixelate`: a blur at the shader's maximum radius
    /// is a SOFT blur — a large password field can still be read through
    /// it — while a pixelation at full strength destroys the detail
    /// outright.
    ///
    /// `feather` is 20 rather than the spotlight's 40 because a region put
    /// over a face is usually much smaller than a callout window, and a
    /// 40-pixel ramp on a 200-pixel box is mostly ramp.
    fn default() -> Self {
        ObscureRegion {
            shape: SpotShape::Rect,
            x: 0.0,
            y: 0.0,
            width: 480.0,
            height: 270.0,
            feather: 20.0,
            kind: ObscureKind::Pixelate,
            amount: 1.0,
        }
    }
}

/// How a region hides what is under it.
///
/// Closed at two, and a type of its own rather than a
/// [`crate::model::FilterKind`] restricted to two of its seven: a range
/// check that had to say "kind must be blur or pixelate" would be a rule
/// about a type enforced a long way from it, which is what `props_check.rs`
/// argues against, and serde would take `"sepia"` out of a hand-written
/// file into a field nothing downstream could repair — there is no neutral
/// obscure kind to fall back to, the way a filter's `amount` can fall back
/// to 0. A closed enum makes the illegal state unrepresentable and hands
/// the shader a two-value discriminant.
///
/// Declaration order is that discriminant's order (`ProjectSnapshot.swift`
/// derives `shaderCode` from the case index and `Compositor.metal` reads
/// the number), so a kind may be added at the END but the two here must
/// never be swapped.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ObscureKind {
    Blur,
    /// The default, and [`ObscureRegion::default`] says why: it is the kind
    /// that actually hides.
    #[default]
    Pixelate,
}
