//! Ripple, insert time, range delete, lift, close gap and freeze frame —
//! spec §6 rows `ripple_delete`, `ripple_delete_range`,
//! `ripple_delete_ranges`, `lift_range`, `close_gap`, `insert_time` and
//! `freeze_frame`, and the §11 decisions they implement.
//!
//! What separates these from `edit_clip.rs`'s ops is that they move
//! material they were never given: closing or opening a hole in the cut
//! shifts clips the caller did not name, on tracks the caller did not name.
//! Three rules run through all of it (spec §11):
//!
//! 1. **Ripple is timeline-wide.** A ripple shifts every UNLOCKED track,
//!    not only the tracks the removed clips were on — that is a screencast editor's
//!    behaviour and the only one that keeps a music bed in sync with the
//!    picture it was cut to.
//! 2. **Locked tracks never move.** Locking a track is how the user says
//!    "this stays where it is", and it is the only protection from a
//!    timeline-wide shift.
//! 3. **Straddling clips stay put.** A clip that covers a boundary is not
//!    cut by a shift; only clips that begin at or after the boundary move.
//!    Clips never push each other, and a shift never splits anything the
//!    user did not ask to split.
//!
//! Everything here is composed from the primitives in `edit_clip.rs` —
//! `split_clips`, `split_under_playhead`, `snapped`, `finish` — rather than
//! restating them, so a split made by a range delete is the same split ⌘T
//! makes.

use crate::edit_clip::clip_end;
use crate::model::{Clip, Enabled, Project, Source, VideoProps};
use crate::outcome::Outcome;
use crate::source_window::in_advanced;
use crate::time::{Ticks, TIMESCALE};

/// Default freeze length (spec §6). Two seconds is long enough for a hold
/// to read as deliberate and short enough that the user trims it rather
/// than deletes it.
const DEFAULT_FREEZE_DURATION: Ticks = 2 * TIMESCALE;

/// A half-open span of project time a ripple removes.
#[derive(Debug, Clone, Copy)]
struct Span {
    start: Ticks,
    end: Ticks,
}

/// The spans merged into disjoint ones, ascending.
///
/// Adjacent spans merge as well as overlapping ones: two clips that meet at
/// a cut leave ONE hole, and shifting twice by two lengths is the same as
/// shifting once by their sum only when the boundaries are handled in one
/// piece. Empty spans are dropped — a zero-length hole moves nothing.
fn union(mut spans: Vec<Span>) -> Vec<Span> {
    spans.sort_by_key(|s| (s.start, s.end));
    let mut out: Vec<Span> = Vec::new();
    for span in spans {
        if span.end <= span.start {
            continue;
        }
        match out.last_mut() {
            Some(last) if span.start <= last.end => last.end = last.end.max(span.end),
            _ => out.push(span),
        }
    }
    out
}

/// THE locked-track refusal, written once (spec §5.5, deepening D2·3).
///
/// Three ops refuse over a lock — `close_gap` and `insert_clip` on their
/// destination track, `add_transition`'s ripple form on the incoming clip's
/// track — and each has its own consequence to report, so `what` is the
/// clause after the comma. What every caller acts on is the same: the id of
/// the track to unlock.
pub(crate) fn locked_track(track: u32, what: &str) -> String {
    format!("track {track} is locked, so {what}")
}

/// The ids of every track a timeline-wide shift may touch.
pub(crate) fn unlocked_tracks(project: &Project) -> Vec<u32> {
    project
        .tracks
        .iter()
        .filter(|t| !t.locked)
        .map(|t| t.id)
        .collect()
}

/// THE shift primitive: every clip on an unlocked track whose start is at
/// or after `from` moves by `delta`, in place. Ripple, the range form and
/// insert time differ only in what they compute for `from` and `delta`.
///
/// The comparison is on `start` alone, which is rule 3: a clip that
/// straddles `from` began before it and stays.
pub(crate) fn shift_clips(project: &mut Project, from: Ticks, delta: Ticks) {
    if delta == 0 {
        return;
    }
    let unlocked = unlocked_tracks(project);
    for clip in project.clips.iter_mut() {
        if clip.start >= from && unlocked.contains(&clip.track) {
            // Saturating and floored: a caller's delta can never push a
            // clip to a negative start, which `validate` rejects.
            clip.start = clip.start.saturating_add(delta).max(0);
        }
    }
}

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
/// first (`split_under_playhead` IS "split every unlocked clip here"), so
/// afterwards every unlocked clip that touched the range lies entirely
/// inside it, and those are removed.
///
/// Clips on LOCKED tracks are neither split nor removed, even when they lie
/// inside the range: rule 2 is absolute, and a locked track keeps exactly
/// what it had.
///
/// The one thing this does NOT do is decide what happens to the hole, which
/// is the whole difference between a lift and a ripple delete.
fn clear_range(project: &Project, start: Ticks, end: Ticks) -> Result<Project, String> {
    // A splitter has no rule to refuse with — it either cut something or it
    // did not — so both of its non-applied answers mean "nothing was cut at
    // this bound". A splitter that ever gains a rule has to be given a way
    // out of here first: this function answers a `Project`, not an
    // [`Outcome`], so it has nowhere to put a sentence.
    let mut current = match project.split_under_playhead(start)? {
        Outcome::Applied(split) => split,
        Outcome::Identity | Outcome::Refused(_) => project.clone(),
    };
    match current.split_under_playhead(end)? {
        Outcome::Applied(split) => current = split,
        Outcome::Identity | Outcome::Refused(_) => {}
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

// ---- the ops -------------------------------------------------------------

impl Project {
    /// Removes the named clips and closes the holes they leave: for each
    /// removed span, every clip on an UNLOCKED track that starts at or
    /// after the span's end shifts left by the span's length (spec §6).
    ///
    /// The spans are the union of the removed clips' spans and are
    /// processed RIGHT TO LEFT, because shifting for an earlier span moves
    /// the clips a later span's bounds were computed against.
    ///
    /// The named clips are removed whether or not their track is locked —
    /// the caller named them — while the lock decides only what may SHIFT.
    ///
    /// Markers do not move. A ripple can remove several spans, and a marker
    /// inside one of them has no moment left to name and nowhere to go that
    /// is not already taken by another marker; leaving every mark in place
    /// is visible and fixable, where a silent drop is not. (`insert_time`
    /// is the opposite case — one point, one length, no collision possible
    /// — and does move them.)
    ///
    /// `Err` on an unknown clip id; an identity for an empty selection.
    pub fn ripple_delete(&self, clips: &[u32]) -> Result<Outcome, String> {
        let selection = self.selected_clips(clips)?;
        if selection.is_empty() {
            return Ok(Outcome::Identity);
        }
        let ids: Vec<u32> = selection.iter().map(|c| c.id).collect();
        let spans = union(
            selection
                .iter()
                .map(|c| Span {
                    start: c.start,
                    end: clip_end(c),
                })
                .collect(),
        );

        let mut next = self.clone();
        next.clips.retain(|c| !ids.contains(&c.id));
        for span in spans.iter().rev() {
            let length = span.end.saturating_sub(span.start);
            shift_clips(&mut next, span.end, -length);
        }
        // A shift can slide a clip onto a straddling neighbour on another
        // track; an overlap IS a transition, so give the newcomer the
        // default rather than leaving two stacked layers.
        let unlocked = unlocked_tracks(&next);
        self.finish_placement(next, &unlocked)
    }

    /// Removes everything between `from` and `to` on unlocked tracks and
    /// closes the hole — the range form of ripple delete (spec §6).
    ///
    /// Both bounds are cut first (`split_under_playhead` IS "split every
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
    /// identity.
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

        let mut next = self.clone();
        for span in spans.iter().rev() {
            next = clear_range(&next, span.start, span.end)?;
            // Negated by subtraction rather than by `-length`, so an absurd
            // range cannot overflow on the negation.
            shift_clips(&mut next, span.end, span.start.saturating_sub(span.end));
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
    pub fn lift_range(&self, from: Ticks, to: Ticks) -> Result<Outcome, String> {
        let Some((start, end)) = ordered_range(self, from, to) else {
            return Ok(Outcome::Identity);
        };
        // No shift, so nothing can be brought into contact with anything
        // and no transition can be gained.
        self.finish(clear_range(self, start, end)?)
    }

    /// Closes the empty span on `track` that contains `at`: everything from
    /// the far side of it, on every unlocked track, moves left by the gap's
    /// length (spec §6).
    ///
    /// The gap is bounded by the nearest clip edges ON `track` — the last
    /// end at or before `at`, or 0 when nothing precedes it, and the first
    /// start after it. A playhead ON a clip is not in a gap, and a gap with
    /// nothing after it is not one to close: both are identities.
    ///
    /// The shift is the ripple's, timeline-wide over unlocked tracks with
    /// straddlers staying put, so the material that follows the gap keeps
    /// its relative timing on every track. **A locked `track` refuses in
    /// [`locked_track`]'s words**: its own clips are the ones that would not
    /// move, and closing a gap by shifting everything except the track the
    /// gap is on is not what anyone asked for.
    ///
    /// **Refuses when the shift would break the overlap rule** anywhere it
    /// moved something, rather than closing as far as it can. A gap closes
    /// fully or not at all: a partial close leaves the user looking at a
    /// smaller gap with no way to tell whether the op ran.
    ///
    /// Markers do not move, as they do not for any other ripple (only
    /// `insert_time`, where no collision is possible, moves them).
    ///
    /// `Err` for an unknown track.
    pub fn close_gap(&self, track: u32, at: Ticks) -> Result<Outcome, String> {
        if self.require_track(track)?.locked {
            return Ok(Outcome::Refused(locked_track(
                track,
                "the gap on it cannot be closed",
            )));
        }
        let at = self.snapped(at).max(0);
        let ordered = self.clips_on_track(track);
        if ordered.iter().any(|c| c.start <= at && at < clip_end(c)) {
            return Ok(Outcome::Identity);
        }
        let start = ordered
            .iter()
            .map(|c| clip_end(c))
            .filter(|end| *end <= at)
            .max()
            .unwrap_or(0);
        let Some(end) = ordered.iter().map(|c| c.start).filter(|s| *s > at).min() else {
            return Ok(Outcome::Identity);
        };
        if end <= start {
            return Ok(Outcome::Identity);
        }

        // Only the tracks something actually moves on can gain an overlap,
        // and only those are checked: a rule violation elsewhere is not
        // this op's to report, and refusing over one would make a gap
        // uncloseable for a reason the user cannot see.
        let unlocked = unlocked_tracks(self);
        let mut touched: Vec<u32> = Vec::new();
        for clip in &self.clips {
            if clip.start >= end && unlocked.contains(&clip.track) && !touched.contains(&clip.track)
            {
                touched.push(clip.track);
            }
        }

        let mut next = self.clone();
        shift_clips(&mut next, end, start.saturating_sub(end));
        for id in &touched {
            if let Err(why) = next.check_overlap_rule(&[], *id, &[]) {
                return Ok(Outcome::Refused(why));
            }
        }
        self.finish_placement(next, &touched)
    }

    /// Opens `length` of empty time at `at`: every clip on an unlocked
    /// track that starts at or after `at` shifts right, and straddling
    /// clips stay put (spec §6).
    ///
    /// Markers at or after `at` shift too. A marker names a moment in the
    /// CUT — "the intro ends here" — not a wall-clock time, so material
    /// inserted before it must carry it along; a marker left behind would
    /// point at whatever the insert pushed under it. No marker can collide:
    /// every mark at or after `at` moves by the same length, and the ones
    /// before it never reach `at`.
    ///
    /// `Err` for a length still negative after snapping; an identity for zero.
    pub fn insert_time(&self, at: Ticks, length: Ticks) -> Result<Outcome, String> {
        let at = self.snapped(at).max(0);
        let length = self.snapped(length);
        if length < 0 {
            return Err(format!("insert length must not be negative, not {length}"));
        }
        if length == 0 {
            return Ok(Outcome::Identity);
        }

        let mut next = self.clone();
        shift_clips(&mut next, at, length);
        for marker in next.markers.iter_mut() {
            if marker.time >= at {
                marker.time = marker.time.saturating_add(length);
            }
        }
        self.finish(next)
    }

    /// Holds the frame under `at` for `duration` (default two seconds),
    /// spec §6.
    ///
    /// The three-op composition IS the definition: **split** the clip at
    /// `at`, **insert time** so `duration` of empty timeline opens across
    /// every unlocked track — which is what keeps the rest of the cut in
    /// sync with the hold (spec §11) — and then fill the hole this clip's
    /// track now has with a `still` naming the source time that was under
    /// the playhead. No image is extracted: a still is one source frame
    /// scaled in the composition (spec §11).
    ///
    /// The source time is `in + (at - start) × speed`, clamped inside the
    /// media so the still names a frame that exists. The still carries the
    /// clip's video properties EVALUATED at the cut, not its base ones: the
    /// frozen frame must sit exactly where the frame it froze sat, and an
    /// action may have been moving it. For the same reason the still gets
    /// no actions — the state it froze at is baked into its base props, and
    /// a copied action would animate away from the frame the cut matched.
    ///
    /// `Err` for an unknown clip, a non-media source, an `at` outside the
    /// clip, or a duration under one frame; refused, in the rule's own
    /// sentence, if the still would break the overlap rule.
    pub fn freeze_frame(
        &self,
        clip: u32,
        at: Ticks,
        duration: Option<Ticks>,
    ) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let Source::Media { media, r#in, .. } = target.source else {
            return Err(format!("clip {clip} is not a media clip"));
        };
        // A clip with no video props draws nothing, so there is no frame to
        // hold — the same "presence of the group is the aspect" rule the
        // property patches use.
        if target.video.is_none() {
            return Err(format!("clip {clip} has no video properties"));
        }

        let at = self.snapped(at);
        if at < target.start || at > clip_end(&target) {
            return Err(format!("clip {clip} does not cover {at}"));
        }
        let frame = self.frame();
        let duration = match duration {
            None => DEFAULT_FREEZE_DURATION,
            Some(given) => {
                let snapped = self.snapped(given);
                if snapped < frame {
                    return Err(format!(
                        "freeze duration must be at least one frame ({frame} ticks), not {given}"
                    ));
                }
                snapped
            }
        };

        let clip_t = at.saturating_sub(target.start);
        let source_at = in_advanced(r#in, clip_t, target.speed);
        // The clamp only has to keep the still's source time inside the
        // media, which is `source_window.rs`'s `last_still_time`; a media
        // the project does not have cannot bound anything.
        let limit = self
            .media(media)
            .map_or(source_at, |m| self.last_still_time(m));
        let source_at = source_at.clamp(0, limit);

        let video = self.evaluate_clip(&target, clip_t).video;
        let mut next = match self.split_clips(&[clip], at)? {
            Outcome::Applied(split) => split,
            // The playhead sat on a clip boundary: nothing to cut, and the
            // freeze still has somewhere to go.
            Outcome::Identity => self.clone(),
            Outcome::Refused(why) => return Ok(Outcome::Refused(why)),
        };
        match next.insert_time(at, duration)? {
            Outcome::Applied(inserted) => next = inserted,
            Outcome::Identity => {}
            Outcome::Refused(why) => return Ok(Outcome::Refused(why)),
        }

        let still = Clip {
            id: next.allocate_id(),
            track: target.track,
            start: at,
            duration,
            source: Source::Still {
                media,
                at: source_at,
            },
            // A held frame has no sound, so the audio side is off and there
            // are no audio props to carry.
            enabled: Enabled {
                video: true,
                audio: false,
            },
            speed: 1.0,
            // A still is a NEW clip with new ends, so it does not inherit
            // the preset anchored to the ones it was taken from (format
            // version 8): a freeze taken mid-arrival would otherwise arrive
            // again, and one taken anywhere at all would carry a departure
            // onto a frame that is meant to hold. The evaluated placement
            // it keeps is the un-moved one — `evaluate_clip` never applies
            // motion — so the still sits exactly where the inspector said
            // the clip was, which is the documented jump (road map 5 §5h).
            video: Some(VideoProps {
                motion: None,
                ..video
            }),
            audio: None,
            text: None,
            shape: None,
            actions: Vec::new(),
            transition_in: None,
            name: None,
            label: None,
        };
        if let Err(why) = next.check_overlap_rule(std::slice::from_ref(&still), still.track, &[]) {
            return Ok(Outcome::Refused(why));
        }
        next.clips.push(still);
        self.finish(next)
    }
}
