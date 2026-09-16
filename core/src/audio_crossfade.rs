//! The transition crossfade: the other term of the envelope that does not
//! come from the voice being measured.
//!
//! `audio_duck.rs` is the first — a clip on some other TRACK pushing this
//! one down — and this is the second: the clip on the same track that this
//! one OVERLAPS (format version 7, spec §7.2, spec §11's R5-2). Both are
//! facts about the neighbourhood rather than about the clip, both are read
//! by `audio.rs` as one multiplier at a breakpoint, and both are a module
//! of their own for that reason.
//!
//! Two halves, and they have to agree: the GAIN at an instant, and the
//! ticks the envelope has to be sampled at for that gain to survive
//! coalescing. Neither the sine law nor an eased progress is a straight
//! line, so a crossfade that contributed no breakpoints would be flattened
//! into a single ramp from 1 to 0 and the constant-power curve would be
//! exactly the equal-gain one it exists to avoid.
//!
//! The law is `cos(p·π/2)` going out and `sin(p·π/2)` coming in, over the
//! EASED progress `transition.rs` reports, and 1 wherever there is no
//! overlap or the transition's `audio` is false — so a project written
//! before version 7 is untouched, and mute, solo, ducking, volume and the
//! fades all keep their precedence, since this multiplies rather than
//! replacing anything.

use std::f64::consts::FRAC_PI_2;

use crate::audio::{Side, Stage, ACTION_SAMPLE, MAX_ACTION_SAMPLES};
use crate::model::Project;
use crate::time::Ticks;
use crate::transition;

impl Project {
    /// The constant-power crossfade multiplier at `t` for one stage (format
    /// version 7, spec §11's R5-2): `cos(p·π/2)` going out, `sin(p·π/2)`
    /// coming in, and 1 wherever there is no overlap or the transition's
    /// `audio` is false.
    ///
    /// Constant power rather than equal gain because the two clips of a
    /// transition are UNCORRELATED material — a Remove Silences cut, a jump
    /// between takes — where `cos² + sin² = 1` holds the level and a linear
    /// pair dips 3 dB in the middle.
    ///
    /// It is measured in the CONTAINER's time base over the CONTAINER's
    /// clips, because an overlap is a fact about neighbours and a nested
    /// clip's neighbours are the nest's. `t - origin` is clip time and
    /// `+ clip.start` puts it back on the container's own clock —
    /// `recipe.rs`'s `local`, the same mapping.
    ///
    /// Every stage multiplies its own term, so a clip inside an overlap
    /// inside a nest that is ITSELF in a transition gets both fades. That
    /// differs from the picture, where `recipe.rs` picks the clip's own
    /// transition first and stops — and it is right for sound: both fades
    /// are audible, where two dissolves on one layer would be two opacity
    /// ramps the compositor has only one slot for.
    pub(crate) fn crossfade_gain(&self, stage: &Stage<'_>, t: Ticks, side: Side) -> f64 {
        let clips = stage
            .container
            .map(|nest| &nest.clips[..])
            .unwrap_or(&self.clips);
        let local = t
            .saturating_sub(stage.origin)
            .saturating_add(stage.clip.start);
        let Some((transition, progress, is_incoming)) =
            transition::crossfade_among(clips, stage.clip.id, local, side)
        else {
            return 1.0;
        };
        if !transition.audio {
            return 1.0;
        }
        let angle = progress.clamp(0.0, 1.0) * FRAC_PI_2;
        if is_incoming {
            angle.sin()
        } else {
            angle.cos()
        }
    }

    /// Every tick one stage's crossfade needs sampled at, in PROJECT time,
    /// or `None` when the stage is in no audio-true overlap.
    ///
    /// The two edges plus a grid across the span, at the step the action
    /// loop uses: `ACTION_SAMPLE` normally, widened so one span can never
    /// contribute more than `MAX_ACTION_SAMPLES` points. Both constants stay
    /// private to this module — the crossfade is sampled here, beside the
    /// actions, exactly so that nothing has to widen for it.
    pub(crate) fn crossfade_breaks(&self, stage: &Stage<'_>) -> Option<Vec<Ticks>> {
        let clips = stage
            .container
            .map(|nest| &nest.clips[..])
            .unwrap_or(&self.clips);
        let mut out: Vec<Ticks> = Vec::new();
        for overlap in [
            transition::overlap_before_of(clips, stage.clip.id),
            transition::overlap_after_of(clips, stage.clip.id),
        ]
        .into_iter()
        .flatten()
        {
            // Asked through `crossfade_among` rather than by reading the
            // later clip's `transition_in` here, so "what transition covers
            // this instant" has one spelling in the crate.
            let Some((transition, _, _)) =
                transition::crossfade_among(clips, stage.clip.id, overlap.start, Side::Right)
            else {
                continue;
            };
            if !transition.audio || overlap.duration <= 0 {
                continue;
            }
            // Container time back to project time: the inverse of
            // `crossfade_gain`'s `local`.
            let project = |c: Ticks| {
                c.saturating_sub(stage.clip.start)
                    .saturating_add(stage.origin)
            };
            let start = project(overlap.start);
            let end = project(overlap.start.saturating_add(overlap.duration));
            out.push(start);
            out.push(end);
            let step = ACTION_SAMPLE.max(overlap.duration / MAX_ACTION_SAMPLES + 1);
            let mut t = start.saturating_add(step);
            while t < end {
                out.push(t);
                t = t.saturating_add(step);
            }
        }
        if out.is_empty() {
            None
        } else {
            Some(out)
        }
    }
}
