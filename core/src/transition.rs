//! Overlaps between neighbouring clips, and THE overlap rule (spec §11).
//!
//! There is no separate transition object on the timeline: an overlap
//! between two clips on the same track *is* the transition, its length is
//! the transition's duration, and the later clip's `transition_in` says
//! which one it is (spec §5.2). So this module owns three related things —
//! finding overlaps, reporting a transition's progress at a time, and the
//! rule that says which overlaps are allowed at all:
//!
//! > A clip may overlap at most ONE neighbour on each side, and each
//! > overlap must be at most HALF of the shorter of the two clips.
//!
//! The rule is written here once and called from `edit_clip` (move, trim),
//! `edit_transition` (set_transition_duration) and `edit_time` (insert time,
//! ripple): a second
//! copy would drift, and the difference between the copies would be the
//! difference between a drop the UI animates back and a project the
//! compositor cannot tile into instructions.
//!
//! Clips never push each other (spec §11): a placement that breaks the rule
//! is refused, never repaired.
//!
//! Two clips overlapping inside a NEST are a transition on exactly the same
//! terms — the group was made out of clips that already had one — so the
//! three read-only halves of this module ([`overlap_before_of`],
//! [`overlap_after_of`], [`transition_among`]) take the container's clips as
//! a slice rather than reading `Project::clips`, and the `Project` methods
//! are the timeline's spelling of them. The rule itself stays a `Project`
//! method: nothing edits inside a nest except `nest` and `unnest`, and both
//! check the TIMELINE they are moving clips on to.

use crate::actions;
use crate::audio::Side;
use crate::model::{Clip, Project, Transition, TransitionKind};
use crate::model_query::clips_on;
use crate::time::Ticks;

/// One overlap: `earlier` starts first, `later` is the clip whose
/// `transition_in` names the kind, and `start`/`duration` are the span in
/// PROJECT time that both clips cover.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Overlap {
    pub earlier: u32,
    pub later: u32,
    pub start: Ticks,
    pub duration: Ticks,
}

/// The overlap between two clips, `earlier` being the one that starts
/// first. `None` when they merely touch: a zero-length overlap is not a
/// transition, it is a cut, and treating it as one would put a degenerate
/// division into every progress computation downstream.
fn overlap_of(earlier: &Clip, later: &Clip) -> Option<Overlap> {
    let start = earlier.start.max(later.start);
    let end = earlier
        .start
        .saturating_add(earlier.duration)
        .min(later.start.saturating_add(later.duration));
    let duration = end.saturating_sub(start);
    if duration <= 0 {
        return None;
    }
    Some(Overlap {
        earlier: earlier.id,
        later: later.id,
        start,
        duration,
    })
}

/// Where `t` sits inside the overlap, 0 at its first tick and approaching 1
/// at its last. Half-open at the end, so the tick the earlier clip ends on
/// is already past the transition and the instruction tiling has no
/// ambiguity. `None` when `t` is outside.
fn progress_in(overlap: &Overlap, t: Ticks) -> Option<f64> {
    let end = overlap.start.saturating_add(overlap.duration);
    if t < overlap.start || t >= end || overlap.duration <= 0 {
        return None;
    }
    let elapsed = t.saturating_sub(overlap.start) as f64;
    Some((elapsed / overlap.duration as f64).clamp(0.0, 1.0))
}

/// The whole transition the LATER clip of a pair carries. An overlap is
/// always a transition, so a clip that overlaps its predecessor with no
/// `transition_in` — only possible in hand-written JSON; `move_clip` sets
/// one when a clip gains an overlap — renders as the default cross
/// dissolve rather than as a hard cut through two visible layers.
///
/// The fallback is `Transition::default()` and deliberately NOT
/// `Transition::minted`: this is what a FILE means by an absent key, and a
/// version-6 project's bare overlap must go on drawing linearly and
/// silently (spec §11, R5-2). Minting is what an EDIT does.
fn transition_of_later(later: &Clip) -> Transition {
    later.transition_in.unwrap_or_default()
}

/// The overlap between `clip` and its predecessor among `clips` — one
/// container's clips, the timeline's or a nest's. `None` for an unknown
/// clip, the first clip on its track, or a plain cut.
pub(crate) fn overlap_before_of(clips: &[Clip], clip: u32) -> Option<Overlap> {
    let target = clips.iter().find(|c| c.id == clip)?;
    let ordered = clips_on(clips, target.track);
    let index = ordered.iter().position(|c| c.id == clip)?;
    let previous = ordered.get(index.checked_sub(1)?)?;
    overlap_of(previous, target)
}

/// The overlap between `clip` and its successor among `clips` — the one the
/// SUCCESSOR's `transition_in` describes.
pub(crate) fn overlap_after_of(clips: &[Clip], clip: u32) -> Option<Overlap> {
    let target = clips.iter().find(|c| c.id == clip)?;
    let ordered = clips_on(clips, target.track);
    let index = ordered.iter().position(|c| c.id == clip)?;
    let next = ordered.get(index.checked_add(1)?)?;
    overlap_of(target, next)
}

/// The transition `clip` is playing at `t`, among the clips of its own
/// container — [`Project::transition_at`]'s implementation, and the one a
/// nested clip is evaluated with (at NEST time, not project time).
///
/// The progress is EASED by the transition's own `curve` (format version 7)
/// before it is returned, so every consumer of it gets one number and none
/// of them has to know the curve exists. `actions::ease` is the crate's one
/// implementation of the four curves, and `Curve::Linear` is the identity —
/// which is what makes a version-6 file's transitions byte-identical to
/// what they were.
pub(crate) fn transition_among(
    clips: &[Clip],
    clip: u32,
    t: Ticks,
) -> Option<(TransitionKind, f64, bool, u32)> {
    let target = clips.iter().find(|c| c.id == clip)?;
    if let Some(overlap) = overlap_before_of(clips, clip) {
        if let Some(progress) = progress_in(&overlap, t) {
            // This clip is the later one, so it carries the transition.
            let transition = transition_of_later(target);
            let eased = actions::ease(transition.curve, progress);
            return Some((transition.kind, eased, true, overlap.earlier));
        }
    }
    if let Some(overlap) = overlap_after_of(clips, clip) {
        if let Some(progress) = progress_in(&overlap, t) {
            let later = clips.iter().find(|c| c.id == overlap.later)?;
            let transition = transition_of_later(later);
            let eased = actions::ease(transition.curve, progress);
            return Some((transition.kind, eased, false, overlap.later));
        }
    }
    None
}

/// The crossfade `clip` is in at `t`, among the clips of its own container:
/// `(the later clip's transition, eased progress, is_incoming)`.
///
/// The audio twin of [`transition_among`], and it differs from it in one
/// way that matters: on [`Side::Left`] the overlap is CLOSED at its end, so
/// the outgoing clip's last sample reads p = 1 and its fade finishes at
/// zero. `progress_in` is half-open — right for the picture, where the tick
/// the earlier clip ends on is already past the transition and the
/// instruction tiling must have no ambiguity — but an envelope evaluated
/// from the LEFT at that tick is asking for the limit approaching it, and
/// a `None` there would read as gain 1 and undo the whole fade on the last
/// breakpoint.
///
/// The partner id is not returned because nothing in the envelope needs it:
/// each stage multiplies its OWN term, and the two clips of a pair are
/// different voices on different composition tracks.
pub(crate) fn crossfade_among(
    clips: &[Clip],
    clip: u32,
    t: Ticks,
    side: Side,
) -> Option<(Transition, f64, bool)> {
    let closed = |overlap: &Overlap| -> Option<f64> {
        if let Some(progress) = progress_in(overlap, t) {
            return Some(progress);
        }
        if side == Side::Left && overlap.duration > 0 {
            let end = overlap.start.saturating_add(overlap.duration);
            if t == end {
                return Some(1.0);
            }
        }
        None
    };

    let target = clips.iter().find(|c| c.id == clip)?;
    if let Some(overlap) = overlap_before_of(clips, clip) {
        if let Some(progress) = closed(&overlap) {
            let transition = transition_of_later(target);
            return Some((transition, actions::ease(transition.curve, progress), true));
        }
    }
    if let Some(overlap) = overlap_after_of(clips, clip) {
        if let Some(progress) = closed(&overlap) {
            let later = clips.iter().find(|c| c.id == overlap.later)?;
            let transition = transition_of_later(later);
            return Some((transition, actions::ease(transition.curve, progress), false));
        }
    }
    None
}

impl Project {
    /// Every overlap on `track`, in time order.
    ///
    /// Only ADJACENT clips (in start order) are considered, which is the
    /// timeline's model of a transition: it sits between two neighbours.
    /// The overlap rule guarantees nothing else can overlap anyway, and
    /// [`Project::check_overlap_rule`] is what detects a project where
    /// something does.
    pub fn overlaps_on_track(&self, track: u32) -> Vec<Overlap> {
        let clips = self.clips_on_track(track);
        let mut out = Vec::new();
        for pair in clips.windows(2) {
            if let (Some(earlier), Some(later)) = (pair.first(), pair.get(1)) {
                if let Some(overlap) = overlap_of(earlier, later) {
                    out.push(overlap);
                }
            }
        }
        out
    }

    /// The overlap between `clip` and its predecessor on the same track —
    /// the one its own `transition_in` describes. `None` for an unknown
    /// clip, the first clip on a track, or a plain cut.
    pub fn overlap_before(&self, clip: u32) -> Option<Overlap> {
        overlap_before_of(&self.clips, clip)
    }

    /// The overlap between `clip` and its successor on the same track — the
    /// one the SUCCESSOR's `transition_in` describes. `None` for an unknown
    /// clip, the last clip on a track, or a plain cut.
    pub fn overlap_after(&self, clip: u32) -> Option<Overlap> {
        overlap_after_of(&self.clips, clip)
    }

    /// The transition `clip` is playing at project time `t`, as
    /// `(kind, progress, is_incoming, partner)`.
    ///
    /// Both clips of a pair report the SAME kind and the SAME progress —
    /// the compositor draws them as one pair (spec §7.3) — and
    /// `is_incoming` is the `role` field: true for the later clip coming
    /// in, false for the earlier one going out. `partner` is the other
    /// clip's id.
    ///
    /// `None` when `t` is a plain cut or ordinary body of the clip.
    pub fn transition_at(&self, clip: u32, t: Ticks) -> Option<(TransitionKind, f64, bool, u32)> {
        transition_among(&self.clips, clip, t)
    }

    /// Checks the overlap rule against the state `track` would be left in.
    ///
    /// `candidates` are the clips in their PROPOSED positions (a move's
    /// destinations, a trim's result, a new clip); `ignore` lists clip ids
    /// to treat as absent, which is how a move removes the clips from where
    /// they were. A candidate's own id is ignored too, so a caller that
    /// forgets `ignore` still gets the right answer instead of a clip
    /// colliding with itself. Candidates for other tracks are skipped, so a
    /// multi-track move can pass the whole set to each destination track.
    ///
    /// The check is over the WHOLE resulting track, not just around the
    /// candidates: the rule is an invariant of the track, and the plan's
    /// A/B assignment (spec §7.2, at most two composition tracks per
    /// timeline track) depends on it holding everywhere.
    ///
    /// `Ok(())` or an `Err` naming the first violation, which the calling
    /// op hands straight on as its refusal — `Outcome::Refused` carrying
    /// THIS sentence, `reason_out` at the FFI, an animate-back in the UI.
    /// The rule is therefore written once: the clip ids and the tick counts
    /// a caller acts on are the ones computed here.
    pub fn check_overlap_rule(
        &self,
        candidates: &[Clip],
        track: u32,
        ignore: &[u32],
    ) -> Result<(), String> {
        let mut placed: Vec<&Clip> = self
            .clips
            .iter()
            .filter(|c| {
                c.track == track
                    && !ignore.contains(&c.id)
                    && !candidates.iter().any(|k| k.id == c.id)
            })
            .collect();
        placed.extend(candidates.iter().filter(|c| c.track == track));
        placed.sort_by_key(|c| (c.start, c.id));

        for i in 0..placed.len() {
            if let (Some(a), Some(b)) = (placed.get(i), placed.get(i + 1)) {
                if let Some(overlap) = overlap_of(a, b) {
                    // Half of the SHORTER clip. Integer halving truncates,
                    // which errs toward refusing — the safe side, since an
                    // over-long overlap is what breaks the A/B assignment.
                    let limit = a.duration.min(b.duration) / 2;
                    if overlap.duration > limit {
                        return Err(format!(
                            "clips {} and {} would overlap by {} ticks, more than half of the \
                             shorter clip ({} ticks)",
                            a.id, b.id, overlap.duration, limit
                        ));
                    }
                }
            }
            // Clips are in start order, so a clip that reaches any
            // non-adjacent clip necessarily reaches the one two along:
            // testing i and i+2 catches every "two neighbours on one side"
            // case in a single linear pass.
            if let (Some(a), Some(b), Some(c)) =
                (placed.get(i), placed.get(i + 1), placed.get(i + 2))
            {
                if overlap_of(a, c).is_some() {
                    return Err(format!(
                        "clip {} would overlap more than one neighbour on one side \
                         (clips {} and {})",
                        a.id, b.id, c.id
                    ));
                }
            }
        }
        Ok(())
    }
}
