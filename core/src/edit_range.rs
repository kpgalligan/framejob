//! The range cuts — spec §6 rows `ripple_delete_range`,
//! `ripple_delete_ranges` and `lift_range`, and `clear_range`, the cutter
//! all three are built on.
//!
//! What a range op does to the cut is `clear_range`'s: both bounds are cut
//! on every unlocked track and what lies wholly between them goes. What it
//! does with the hole is the op's: a lift leaves it open, a ripple closes it
//! through `edit_time.rs`'s shift, so the three rules there (a ripple is
//! timeline-wide, locked tracks never move, straddlers stay put) hold here
//! unchanged. Moved out of `edit_time.rs` whole under the size rule
//! (`designs/adr/core-file-history.md`).
//!
//! **What a range op stores is judged by THE overlap rule, once** (spec
//! §11 #427): `clear_range` cuts through `cut_under_playhead`, which asks
//! no rule, because a piece its first cut leaves too short for a transition
//! may be one the removal then takes; each op asks `edit_cut_rule.rs`'s
//! `cut_refusal` of its result, and `ripple_delete_ranges` of the result of
//! every range together, so a list is refused whole.

use crate::edit_clip::clip_end;
use crate::edit_cut_rule::Pieces;
use crate::edit_time::{shift_clips, union, unlocked_tracks, Span};
use crate::model::Project;
use crate::outcome::Outcome;
use crate::time::Ticks;

/// The bounds a range op works on: snapped, clamped to 0 and put in order,
/// so a drag that ended left of where it began is the same range. `None`
/// for an empty one.
fn ordered_range(project: &Project, from: Ticks, to: Ticks) -> Option<(Ticks, Ticks)> {
    let first = project.snapped(from).max(0);
    let second = project.snapped(to).max(0);
    let (start, end) = if first <= second {
        (first, second)
    } else {
        (second, first)
    };
    (end > start).then_some((start, end))
}

/// Empties `[start, end)` on every unlocked track: both bounds are cut
/// first (`cut_under_playhead` is ⌘K's "split every unlocked clip here"), so
/// afterwards every unlocked clip that touched the range lies entirely
/// inside it, and those are removed.
///
/// Clips on LOCKED tracks are neither split nor removed, even when they lie
/// inside the range: rule 2 is absolute, and a locked track keeps exactly
/// what it had.
///
/// The one thing this does NOT do is decide what happens to the hole, which
/// is the whole difference between a lift and a ripple delete.
///
/// Nor does it ask the overlap rule: the cut at `start` can leave a piece
/// too short for its transition that the removal then takes, so the op
/// asks of what it would store (spec §11 #427 (a)). `pieces` learns which
/// clip each piece was cut from, for that sentence.
fn clear_range(
    project: &Project,
    start: Ticks,
    end: Ticks,
    pieces: &mut Pieces,
) -> Result<Project, String> {
    let mut current = project
        .cut_under_playhead(start, pieces)?
        .unwrap_or_else(|| project.clone());
    if let Some(cut) = current.cut_under_playhead(end, pieces)? {
        current = cut;
    }

    let unlocked = unlocked_tracks(&current);
    let inside: Vec<u32> = current
        .clips
        .iter()
        .filter(|c| unlocked.contains(&c.track) && c.start >= start && clip_end(c) <= end)
        .map(|c| c.id)
        .collect();
    current.clips.retain(|c| !inside.contains(&c.id));
    Ok(current)
}

impl Project {
    /// Removes everything between `from` and `to` on unlocked tracks and
    /// closes the hole — the range form of ripple delete (spec §6).
    ///
    /// Both bounds are cut first (`cut_under_playhead` is ⌘K's "split every
    /// unlocked clip here"), so afterwards every unlocked clip that touched
    /// the range lies entirely inside it; those are removed, and everything
    /// starting at or after `to` shifts left by the range's length.
    ///
    /// Clips on LOCKED tracks are neither split nor removed, even when they
    /// lie inside the range: rule 2 is absolute, and a locked track keeps
    /// exactly what it had.
    ///
    /// The bounds are snapped, clamped to 0 and ordered, so a drag that
    /// ended left of where it began is the same range. An empty range is an
    /// identity. Refused, nothing cut, when what it would store breaks THE
    /// overlap rule on a track it changed (spec §11 #427).
    ///
    /// It is [`Project::ripple_delete_ranges`] with one pair, and nothing
    /// else: with a single span there is nothing for the merge to merge and
    /// nothing for the right-to-left loop to order, so the two are
    /// step-for-step the same edit. Keeping a second body here would be a
    /// second implementation of one algorithm, free to drift.
    pub fn ripple_delete_range(&self, from: Ticks, to: Ticks) -> Result<Outcome, String> {
        self.ripple_delete_ranges(&[[from, to]])
    }

    /// Removes SEVERAL ranges and closes each hole in one edit — the
    /// silence cut (spec §6), one op because it is one undo step.
    ///
    /// **The op is defined as merge-then-cut, not as N
    /// `ripple_delete_range`s**, and the difference is visible in the
    /// document, so it is worth stating plainly: each pair is snapped,
    /// clamped to 0 and put in order exactly as the single range is, the
    /// results are MERGED — touching pairs as well as overlapping ones —
    /// and only the survivors are cut. Two quiet spans that meet leave one
    /// hole, and cutting at a boundary that no longer exists would split
    /// clips into fragments nobody asked for and burn the ids to prove it.
    /// A caller that wants N separate edits sends N ops.
    ///
    /// The survivors are cut and closed RIGHT TO LEFT, because closing an
    /// earlier hole moves the clips a later hole's bounds were measured
    /// against — every bound here is a time in the project as the caller
    /// saw it, not in the project as the previous cut left it.
    ///
    /// `set_gained_transitions` runs ONCE at the end, over the unlocked
    /// tracks, as it does for `ripple_delete`'s own union of spans: a clip
    /// that overlaps a neighbour between two shifts and then slides clear
    /// again should not come out holding a transition for an overlap that
    /// no longer exists.
    ///
    /// Everything else is `ripple_delete_range`'s contract: locked tracks
    /// are neither split, removed nor shifted; straddlers stay put; markers
    /// do not move (a marker inside a removed span has no moment left to
    /// name, and giving the plural a second marker rule would give two
    /// ripples two rules); a clip a shift brings onto a neighbour gains the
    /// default transition rather than stacking.
    ///
    /// There is no cap on the list: the op is pure, so nothing is
    /// half-applied, and a pathological call is already answered — each cut
    /// splits, every split validates, and `format::check_caps` refuses the
    /// clip count it would take to get there.
    ///
    /// An empty list, a list of empty ranges, and a list that merges to
    /// nothing all change nothing.
    ///
    /// **Refused whole**, nothing cut, when what the whole list would store
    /// breaks THE overlap rule on a track it changed — one range cut too
    /// close to a transition refuses every range (spec §11 #427 (e)).
    pub fn ripple_delete_ranges(&self, ranges: &[[Ticks; 2]]) -> Result<Outcome, String> {
        // Snapped FIRST, merged after: two ranges three ticks apart are the
        // same range once both bounds are on the frame grid, and only a
        // merge that runs afterwards can see it.
        let spans = union(
            ranges
                .iter()
                .filter_map(|pair| ordered_range(self, pair[0], pair[1]))
                .map(|(start, end)| Span { start, end })
                .collect(),
        );
        if spans.is_empty() {
            return Ok(Outcome::Identity);
        }

        let mut pieces = Pieces::new();
        let mut next = self.clone();
        for span in spans.iter().rev() {
            next = clear_range(&next, span.start, span.end, &mut pieces)?;
            // Negated by subtraction rather than by `-length`, so an absurd
            // range cannot overflow on the negation.
            if let Some(why) = shift_clips(&mut next, span.end, span.start.saturating_sub(span.end))
            {
                return Ok(Outcome::Refused(why));
            }
        }
        if let Some(why) = self.cut_refusal(&next, &pieces) {
            return Ok(Outcome::Refused(why));
        }
        let unlocked = unlocked_tracks(&next);
        self.finish_placement(next, &unlocked)
    }

    /// Removes everything between `from` and `to` on unlocked tracks and
    /// leaves the hole open — `ripple_delete_range` without the close
    /// (spec §6).
    ///
    /// The lift is the cut that costs nothing downstream: every clip that
    /// starts at or after `to` keeps the moment it had, so a mix, a caption
    /// track and a music bed stay where they were cut to. It is the
    /// counterpart of a ripple, not a lesser one — ⌫ with a range and
    /// nothing selected, where ⌘⌫ ripples.
    ///
    /// Markers do not move either, for the plainer reason that nothing
    /// under them did.
    ///
    /// The bounds are snapped, clamped to 0 and ordered, so a drag that
    /// ended left of where it began is the same range. An empty range, or
    /// one that held nothing an unlocked track could give up, is an identity.
    /// Refused, nothing cut, when what it would store breaks THE overlap
    /// rule on a track it changed (spec §11 #427).
    pub fn lift_range(&self, from: Ticks, to: Ticks) -> Result<Outcome, String> {
        let Some((start, end)) = ordered_range(self, from, to) else {
            return Ok(Outcome::Identity);
        };
        // No shift, so nothing can be brought into contact with anything
        // and no transition can be gained.
        let mut pieces = Pieces::new();
        let next = clear_range(self, start, end, &mut pieces)?;
        if let Some(why) = self.cut_refusal(&next, &pieces) {
            return Ok(Outcome::Refused(why));
        }
        self.finish(next)
    }
}
