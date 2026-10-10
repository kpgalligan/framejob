//! Adjustment clips (spec §11 GR-6): a clip kind with no picture of its
//! own. While it lasts, its `video.color` (all thirteen keys), its point
//! filters (sepia, noir, vignette, invert) and its opacity — the STRENGTH —
//! apply to everything already drawn behind it in its container, the canvas
//! background included, and never to a track in front. The compositor's
//! eighth pipeline does the grading by reading the target it draws into
//! (`Compositor+Adjustment.swift`); the core's part is the kind, the op,
//! the rules below and the recipe's `{"kind":"adjustment"}` source.
//!
//! What it refuses, and why each is a refusal rather than a clamp:
//!
//! - **A nest.** A nest is flattened into the clips inside it, and an
//!   adjustment clip in there would grade the PARENT's layers behind the
//!   nest clip as well as the nest's own, which is not what a nest means.
//!   `nest` refuses it ([`adjustment_cannot_nest`]); `validate` errors on one
//!   inside a nest ([`adjustment_nested`]), which is what a file and a paste
//!   into a scope meet, because a scoped edit is validated on the MERGED
//!   parent (`scope.rs`); and `add_adjustment_clip` has no meaning inside a
//!   scope (`scope.rs`'s `refused_inside`).
//! - **A transition.** Both halves of a dissolve are drawn into one
//!   destination as a weighted pair; a pass that grades the destination has
//!   no half to be. `add_transition`, `set_transition` and
//!   `set_transition_style` refuse ([`adjustment_transition`]), and so does
//!   the overlap rule for any pair that holds one
//!   ([`adjustment_overlap`], called from `transition.rs`'s
//!   `check_overlap_rule`, the one placement door) — so
//!   `set_gained_transitions` never mints a transition on one. Fade it with
//!   opacity instead.
//! - **Blur, sharpen, pixelate and a blend mode.** The neighbourhood
//!   filters sample the layer's own texture around a pixel, and there is
//!   none; a blend combines a layer's colour with the canvas, and an
//!   adjustment clip has no colour of its own. `set_video`, `paste` and
//!   `paste_attributes` meet [`check_adjustment_video`] beside `check_blend`
//!   (errors, its precedent), and an action's end carrying one is closed by
//!   the evaluator ([`clamp_adjustment`]), as `clamp_video` closes a nest's
//!   blend.
//!
//! **On a matte track it is inert** ([`Project::inert_adjustment`]): a
//! matte group is one track, and two clips on one track share an instant
//! only in a transition, which is refused, so the clip could only be the
//! group's sole member and would act as an EMPTY matte. The recipe leaves
//! it out before the mattes are answered. On a track CUT by a matte it
//! grades only inside the matte, which needs nothing here: the compositor
//! weights its pass by the coverage like any matted layer's.
//!
//! Its stored transform, crop, corner, shadow, reflection, chroma,
//! spotlight, obscure and motion placement are kept and do nothing;
//! refusing them would make Paste Attributes fail from any moved clip.

use crate::edit_clip::Described;
use crate::model::{BlendMode, Clip, FilterKind, Project, Source, VideoProps};
use crate::nest::Instance;
use crate::outcome::Outcome;
use crate::time::Ticks;

impl Project {
    /// An adjustment clip at `at` on `track`, five seconds long unless
    /// `duration` says otherwise, at scale 1 with default `video` (spec §6,
    /// §11 GR-6). Placed through `add_described_clip`, so the overlap rule
    /// and its sentence are the same as any sourceless clip's — with the
    /// adjustment clause, since no overlap may hold one.
    pub fn add_adjustment_clip(
        &self,
        track: u32,
        at: Ticks,
        duration: Option<Ticks>,
    ) -> Result<Outcome, String> {
        self.add_described_clip(
            track,
            at,
            duration,
            Described {
                source: Source::Adjustment,
                scale: 1.0,
                text: None,
                shape: None,
                graphic: None,
            },
        )
    }

    /// Whether `instance` is an adjustment clip on a top-level matte track,
    /// which draws nothing and cuts nothing (this module's doc): the recipe
    /// drops it before `frame_mattes` sees it.
    pub(crate) fn inert_adjustment(&self, instance: &Instance) -> bool {
        is_adjustment(instance.clip)
            && instance.inside.is_empty()
            && !instance.track.matte.is_none()
    }
}

/// Whether the clip is an adjustment clip.
pub(crate) fn is_adjustment(clip: &Clip) -> bool {
    matches!(clip.source, Source::Adjustment)
}

/// The one rule about an adjustment CLIP's video group: no neighbourhood
/// filter and no blend mode. An `Err`, as `check_blend`'s is, so `paste` and
/// `paste_attributes` meet it through `check_group` and refuse the whole
/// paste. Any other clip passes.
pub(crate) fn check_adjustment_video(clip: &Clip, props: &VideoProps) -> Result<(), String> {
    if !is_adjustment(clip) {
        return Ok(());
    }
    for filter in &props.filters {
        let name = match filter.kind {
            FilterKind::Blur => "blur",
            FilterKind::Sharpen => "sharpen",
            FilterKind::Pixelate => "pixelate",
            FilterKind::Sepia | FilterKind::Noir | FilterKind::Vignette | FilterKind::Invert => {
                continue
            }
        };
        return Err(format!(
            "clip {} is an adjustment clip and cannot take the {name} filter",
            clip.id
        ));
    }
    if props.blend != BlendMode::Normal {
        return Err(format!(
            "clip {} is an adjustment clip and cannot take a blend mode",
            clip.id
        ));
    }
    Ok(())
}

/// The overlap rule's sentence for an overlapping pair that holds an
/// adjustment clip, naming the later one when both are; `None` when neither
/// is. Its one caller is `check_overlap_rule`, with a pair it has already
/// found overlapping.
pub(crate) fn adjustment_overlap(a: &Clip, b: &Clip) -> Option<String> {
    let named = if is_adjustment(b) {
        b
    } else if is_adjustment(a) {
        a
    } else {
        return None;
    };
    Some(format!(
        "clips {} and {} would overlap, and clip {} is an adjustment clip, which cannot take a \
         transition; fade it with opacity instead",
        a.id, b.id, named.id
    ))
}

/// The refusal `add_transition`, `set_transition` and
/// `set_transition_style` give an adjustment clip; `None` for any other.
pub(crate) fn adjustment_transition(clip: &Clip) -> Option<String> {
    is_adjustment(clip).then(|| {
        format!(
            "clip {} is an adjustment clip and cannot take a transition; fade it with opacity \
             instead",
            clip.id
        )
    })
}

/// `validate`'s error for an adjustment clip inside a nest; `whose` is
/// `check_clips`' container clause (`" in nest 4"`).
pub(crate) fn adjustment_nested(clip: u32, whose: &str) -> String {
    format!(
        "clip {clip}{whose} is an adjustment clip, and an adjustment clip cannot be inside a nest"
    )
}

/// `nest`'s refusal for a selection holding an adjustment clip.
pub(crate) fn adjustment_cannot_nest(clip: u32) -> String {
    format!("clip {clip} is an adjustment clip, and an adjustment clip cannot go inside a nest")
}

/// The evaluator's last line of defence for an adjustment clip (an
/// action's end is checked against the vocabulary, never the clip): a
/// blend forced to `normal` and the neighbourhood filters dropped.
pub(crate) fn clamp_adjustment(mut props: VideoProps) -> VideoProps {
    props.blend = BlendMode::Normal;
    props.filters.retain(|filter| {
        !matches!(
            filter.kind,
            FilterKind::Blur | FilterKind::Sharpen | FilterKind::Pixelate
        )
    });
    props
}
