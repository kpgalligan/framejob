//! The transition ops — spec §6, table "Transitions".
//!
//! An overlap between two clips on one track IS the transition (spec §5.2),
//! so there is no transition object to add or remove: what these ops edit is
//! either the later clip's `transition_in` — which kind, and (version 7) how
//! it is eased and whether it crossfades the sound — or the OVERLAP itself,
//! by moving the later clip. `transition.rs` is the read half (finding
//! overlaps, the overlap rule, progress at a time); this is the write half.
//!
//! Cut out of `edit_clip.rs` under the size rule, and cut HERE because
//! placement and transitions are different questions: every op in
//! `edit_clip.rs` decides where a clip SITS, while these decide what happens
//! where two of them meet. `set_gained_transitions` comes with them — it is
//! the rule that a clip which gains an overlap gains a transition, which is
//! about the meeting and not about the move, and it is re-exported from
//! `edit_clip.rs` so the nine call sites there and the three in
//! `edit_time.rs`, `edit_nest.rs` and `edit_paste.rs` are unchanged.
//!
//! The three rules of `edit_clip.rs`'s module doc hold here too: every tick
//! argument is snapped to the frame grid first, a placement that would break
//! the overlap rule is refused rather than repaired, and [`Project::finish`]
//! is the single exit.

use serde::{Deserialize, Serialize};

use crate::edit_clip::clip_end;
use crate::edit_time::{locked_track, shift_clips, unlocked_tracks};
use crate::model::{Clip, Curve, Project, Source, Transition, TransitionKind};
use crate::outcome::Outcome;
use crate::time::Ticks;

/// Where the overlap [`Project::add_transition`] makes is taken FROM.
///
/// It lives here rather than in `edit.rs` for `ZoomFit`'s reason
/// (`edit_zoom.rs`): an argument whose whole meaning belongs to one op
/// belongs beside that op, where the doc that explains it is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransitionAlign {
    /// Half from each side — the default, because that is what a person who
    /// points at a cut and asks for a transition means: the moment of the
    /// cut stays where it is and the transition happens around it. An odd
    /// frame goes to the incoming clip.
    #[default]
    Center,
    /// The whole overlap comes out of the INCOMING clip's head, so the
    /// outgoing clip's last frame stays exactly where it was.
    Before,
    /// The whole overlap comes out of the OUTGOING clip's tail, so the
    /// incoming clip's first frame stays exactly where it was.
    After,
}

/// Gives every clip that now overlaps its predecessor and has no
/// `transition_in` a cross dissolve. An overlap IS a transition (spec
/// §5.2), so a clip that gains one and would otherwise render as two
/// stacked layers gets one rather than nothing.
///
/// It is MINTED (spec §11, R5-2) — eased and crossfading — and not
/// `Transition::default()`, which is the FILE default a version-6 project's
/// overlap reads as. A clip that gains an overlap now is a new transition
/// now.
pub(crate) fn set_gained_transitions(project: &mut Project, tracks: &[u32]) {
    let mut gained: Vec<u32> = Vec::new();
    for track in tracks {
        for clip in project.clips_on_track(*track) {
            if clip.transition_in.is_none() && project.overlap_before(clip.id).is_some() {
                gained.push(clip.id);
            }
        }
    }
    for id in gained {
        if let Some(clip) = project.clip_mut(id) {
            clip.transition_in = Some(Transition::minted(TransitionKind::default()));
        }
    }
}

/// The pair as [`Project::add_transition`] would leave it: `earlier` grown
/// by `tail` ticks at its end, `later` moved back `head` ticks and grown by
/// the same, its `in` following.
///
/// One function, so the trial the overlap rule is checked against and the
/// clips that are finally written cannot be two different arithmetics.
/// Actions and the transition itself are the caller's, because the trial
/// does not care about either.
fn extended(earlier: &Clip, later: &Clip, tail: Ticks, head: Ticks) -> (Clip, Clip) {
    let mut grown = earlier.clone();
    grown.duration = grown.duration.saturating_add(tail);

    let mut moved = later.clone();
    if let Source::Media {
        media,
        r#in,
        reversed,
    } = later.source
    {
        // The source ticks that lie under `head` ticks of timeline at this
        // clip's speed — `trim_start` and `roll`'s own arithmetic, and the
        // reason the handle above is measured in TIMELINE time and never
        // divided by the speed a second time.
        let back = head as f64 * later.speed;
        let back = if back.is_finite() {
            back.round() as Ticks
        } else {
            0
        };
        moved.source = Source::Media {
            media,
            r#in: r#in.saturating_sub(back).max(0),
            reversed,
        };
    }
    moved.start = later.start.saturating_sub(head);
    moved.duration = later.duration.saturating_add(head);
    (grown, moved)
}

impl Project {
    /// Sets — or clears, with `None` — the transition covering the clip's
    /// overlap with its predecessor (spec §6). A clip with no overlap may
    /// still carry a kind; it is simply ignored until one exists, which is
    /// what lets the inspector set the kind before dragging the overlap.
    ///
    /// **A kind change KEEPS the style** (format version 7): when the clip
    /// already has a `transition_in`, only its `kind` moves and its `curve`
    /// and `audio` stay where the person put them. Only a clip that had
    /// none gets a whole new transition, and that one is
    /// [`Transition::minted`]. Without that rule, choosing a wipe from the
    /// popup, the Clip menu or MCP would silently reset a curve — and the
    /// op has no way to say "curve unchanged", which is exactly why
    /// [`Project::set_transition_style`] is a second op rather than two
    /// more arguments here.
    pub fn set_transition(
        &self,
        clip: u32,
        kind: Option<TransitionKind>,
    ) -> Result<Outcome, String> {
        let stored = self.require_clip(clip)?.transition_in;
        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            slot.transition_in = kind.map(|kind| match stored {
                Some(existing) => Transition { kind, ..existing },
                None => Transition::minted(kind),
            });
        }
        self.finish(next)
    }

    /// Makes an overlap at a HARD CUT out of the two clips' unused handles,
    /// and puts a transition on it (spec §6, road map 5 E1; spec §11 R5-3).
    ///
    /// `clip` is the INCOMING clip — B — and the cut is the one at its
    /// start. Nothing else on the timeline moves: the extensions come out
    /// of material the two clips already have and are clamped so A's new
    /// end cannot reach B's successor and B's new start cannot reach A's
    /// predecessor.
    ///
    /// **Not being at a hard cut is an `Err`**, naming which of the three it
    /// is — no predecessor, a gap, an existing overlap — because this op is
    /// pointed at one cut by a caller who meant THAT cut, unlike `roll`,
    /// which a drag can reach at any edge. **Having no handle is a domain
    /// refusal**: a shorter transition is the same edit at a
    /// size the media allows, so the duration is clamped rather than
    /// refused, and only a request that clamps below one whole frame gives
    /// up.
    ///
    /// **`ripple` makes the overlap by MOVING instead** (spec §11, R5-3's
    /// amendment of 2026-09-16), and is [`Project::add_transition_by_shift`];
    /// steps 0 and 1 and the kind (step 10) are shared, and nothing between
    /// them runs.
    ///
    /// The steps, in order:
    ///
    /// 0. A `duration` that is not positive is an `Err` before anything
    ///    else is read.
    /// 1. Find A: the clip on B's track that ends EXACTLY where B begins —
    ///    `roll`'s own test (`edit_edge.rs`).
    /// 2. Measure the handles in TIMELINE ticks. B's head is
    ///    `source_head` for a media clip, UNBOUNDED for a still, an image,
    ///    text and a shape — none of which has a source window — and **0
    ///    for a nest**, because trimming a nest clip's head moves its
    ///    contents (`nest.rs`) rather than revealing anything, so a nest
    ///    gives nothing on that side. A's tail is
    ///    `source_length − duration` for a media clip (a `source_length` of
    ///    `None` — unknown media, degenerate speed — means NO tail),
    ///    unbounded for the sourceless kinds, and
    ///    `max(0, nest.duration() − A.duration)` for a nest, past which it
    ///    would draw nothing.
    /// 3. Convert to whole FRAMES, the request snapped down and each handle
    ///    floored inward. This happens BEFORE the split: snapping two half
    ///    extensions separately would lose the odd frame (1.5 + 1.5 frames
    ///    snap to 1 + 1).
    /// 4. Split by `align`. Under `center` the odd frame goes to B, and a
    ///    side that cannot supply its share passes the shortfall to the
    ///    other side — up to that side's own handle — before the total
    ///    shrinks.
    /// 5. Clamp against the neighbours, closed form.
    /// 6. Check the overlap rule (`transition.rs`, which is not part of
    ///    `validate`, so it is called here as `roll` calls it). Its bound
    ///    is half of the SHORTER clip and both durations are growing, so
    ///    the answer is not monotone in an obvious direction: a failure
    ///    steps the total down one frame, taken from the larger side, and
    ///    retries. The loop is bounded by step 4's own frame count.
    /// 7. Nothing left to give — below one frame — is a refusal.
    /// 8. Write: A grows at the end, B grows at the front and its `in`
    ///    moves back by the same timeline time TIMES its speed, the
    ///    arithmetic `trim_start` and `roll` both use.
    /// 9. Rebase B's ACTIONS by the same amount, so an action stays on the
    ///    source frame it was drawn over — a screencast zoom stays on its
    ///    click. `trim_start` deliberately does not do this, and the
    ///    difference is the point: a trim is the user saying "start later",
    ///    where a transition reveals material in FRONT of a first frame
    ///    that was never meant to move. B's `fade_in` and its text reveal
    ///    are measured from B's new first frame and so begin under the
    ///    transition, which is what a transition is for.
    /// 10. The kind: the argument if given, else B's own stored kind if it
    ///     has one (Clip ▸ Transition ▸ stores an undrawn one at a hard
    ///     cut), else `cross_dissolve`. A stored transition keeps its
    ///     style; a new one is [`Transition::minted`].
    pub fn add_transition(
        &self,
        clip: u32,
        kind: Option<TransitionKind>,
        duration: Ticks,
        align: Option<TransitionAlign>,
        ripple: bool,
    ) -> Result<Outcome, String> {
        // 0. The one wrong ARGUMENT that is not about the timeline.
        if duration <= 0 {
            return Err(format!("duration must be positive, not {duration}"));
        }
        let later = self.require_clip(clip)?.clone();
        let align = align.unwrap_or_default();

        // 1. The cut. `roll`'s test: the predecessor is whatever ends
        //    EXACTLY where this clip begins.
        let ordered: Vec<Clip> = self
            .clips_on_track(later.track)
            .into_iter()
            .cloned()
            .collect();
        let index = match ordered.iter().position(|c| c.id == clip) {
            Some(index) => index,
            None => return Ok(Outcome::Identity),
        };
        let previous = index.checked_sub(1).and_then(|i| ordered.get(i));
        let earlier = match previous {
            None => {
                return Err(format!(
                    "clip {clip} is not at a hard cut: it is the first clip on its track"
                ))
            }
            Some(p) if clip_end(p) < later.start => {
                let gap = later.start.saturating_sub(clip_end(p));
                return Err(format!(
                    "clip {clip} is not at a hard cut: there is a gap of {gap} ticks before it"
                ));
            }
            Some(p) if clip_end(p) > later.start => {
                return Err(format!(
                    "clip {clip} is not at a hard cut: it already overlaps clip {} — \
                     use set_transition or set_transition_duration",
                    p.id
                ))
            }
            Some(p) => p.clone(),
        };
        if ripple {
            return self.add_transition_by_shift(&earlier, &later, kind, duration);
        }

        let frame = self.frame();
        // 2 and 3. The handles, floored to whole frames. `None` is
        //    UNBOUNDED, which is not the same as a handle of zero.
        let head_frames = self.head_handle_frames(&later, frame);
        let tail_frames = self.tail_handle_frames(&earlier, frame);

        // 3. The request, snapped down to whole frames before it is split.
        let requested = duration / frame;

        // 4. The split, and `center`'s shortfall moving sides.
        let (want_b, want_a) = match align {
            TransitionAlign::Center => {
                let b = requested.div_euclid(2) + requested.rem_euclid(2);
                (b, requested - b)
            }
            TransitionAlign::Before => (requested, 0),
            TransitionAlign::After => (0, requested),
        };
        let capped = |want: Ticks, handle: Option<Ticks>| handle.map_or(want, |h| want.min(h));
        let mut b = capped(want_b, head_frames);
        let mut a = capped(want_a, tail_frames);
        if align == TransitionAlign::Center {
            let short = (want_b - b) + (want_a - a);
            if short > 0 {
                let room_b = head_frames.map_or(short, |h| (h - b).max(0));
                let moved = short.min(room_b);
                b += moved;
                let room_a = tail_frames.map_or(short - moved, |h| (h - a).max(0));
                a += (short - moved).min(room_a);
            }
        }

        // 5. The neighbours. A may not reach B's successor, and B may not
        //    reach A's predecessor. Both are closed form.
        if let Some(next_clip) = ordered.get(index + 1) {
            let room = next_clip.start.saturating_sub(clip_end(&earlier)).max(0) / frame;
            a = a.min(room);
        }
        if let Some(before) = index.checked_sub(2).and_then(|i| ordered.get(i)) {
            let room = later.start.saturating_sub(clip_end(before)).max(0) / frame;
            b = b.min(room);
        }

        // 6 and 7. The overlap rule, stepping down from the larger side.
        loop {
            if a + b <= 0 {
                // Three clamps can land here — the two handles, the
                // neighbours on the track, and the step-down below — so the
                // sentence names all three rather than guessing which one
                // it was, and names the number the caller sent, which is
                // the one it would change.
                return Ok(Outcome::Refused(format!(
                    "the cut before clip {clip} has no room for an overlap: the {requested} \
                     frames asked for clamp to nothing against the two clips' unused \
                     material, their neighbours and the overlap rule; pass ripple: true to \
                     make the overlap by shifting the timeline left instead"
                )));
            }
            let (grown, moved) = extended(&earlier, &later, a * frame, b * frame);
            if self
                .check_overlap_rule(&[grown, moved], later.track, &[])
                .is_ok()
            {
                break;
            }
            if b >= a {
                b -= 1;
            } else {
                a -= 1;
            }
        }

        // 8, 9 and 10. Write.
        let (grown, mut moved) = extended(&earlier, &later, a * frame, b * frame);
        for action in &mut moved.actions {
            action.start = action.start.saturating_add(b * frame);
        }
        moved.transition_in = Some(match (kind, later.transition_in) {
            (Some(kind), Some(stored)) => Transition { kind, ..stored },
            (Some(kind), None) => Transition::minted(kind),
            (None, Some(stored)) => stored,
            (None, None) => Transition::minted(TransitionKind::default()),
        });

        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(earlier.id) {
            *slot = grown;
        }
        if let Some(slot) = next.clip_mut(clip) {
            *slot = moved;
        }
        self.finish(next)
    }

    /// `add_transition` with `ripple` — the overlap made by SHIFTING the
    /// incoming clip left over the end of the outgoing one, for the cut
    /// where neither clip has a frame of unused material (two whole files
    /// placed back to back, which the handle form can never join).
    ///
    /// No handle is read and `align` means nothing: the outgoing clip keeps
    /// every frame and its place, the incoming clip keeps its source window
    /// and its actions (they are clip time, and the clip moves whole), and
    /// its first frames blend over the outgoing clip's last ones. What moves
    /// is `close_gap`'s set — every clip at or after the cut on every
    /// UNLOCKED track, through the same [`shift_clips`] — so the tracks stay
    /// in sync and the timeline gets shorter by the overlap. Markers do not
    /// move, as they do not for `ripple_delete` or `close_gap`.
    ///
    /// The duration is snapped down to whole frames, capped at half the
    /// shorter of the two clips (the pair's own overlap rule, closed form),
    /// and then stepped down a frame at a time until every track something
    /// moved on passes the overlap rule — clamped rather than refused, the
    /// handle form's posture. A clip on another track that the shift pushes
    /// into its predecessor gains a minted `cross_dissolve`, which is
    /// `close_gap`'s rule for the same shift.
    ///
    /// Three refusals, each in its own sentence: an incoming clip on a
    /// LOCKED track cannot move ([`locked_track`]); a pair whose shorter
    /// clip is under two frames has no half to give; and a shift every
    /// length of which would break the overlap rule somewhere it moved
    /// something.
    pub(crate) fn add_transition_by_shift(
        &self,
        earlier: &Clip,
        later: &Clip,
        kind: Option<TransitionKind>,
        duration: Ticks,
    ) -> Result<Outcome, String> {
        let unlocked = unlocked_tracks(self);
        if !unlocked.contains(&later.track) {
            return Ok(Outcome::Refused(locked_track(
                later.track,
                &format!(
                    "clip {} cannot be shifted left to make the overlap",
                    later.id
                ),
            )));
        }
        let frame = self.frame();
        let cut = later.start;
        let mut touched: Vec<u32> = Vec::new();
        for clip in &self.clips {
            if clip.start >= cut && unlocked.contains(&clip.track) && !touched.contains(&clip.track)
            {
                touched.push(clip.track);
            }
        }

        let shorter = earlier.duration.min(later.duration);
        let asked = duration / frame;
        let allowed = shorter / 2 / frame;
        // Asked first, so a request under a frame and a pair too short to
        // halve are told apart by the two numbers rather than by a guess.
        let mut frames = asked.min(allowed);
        if frames <= 0 {
            return Ok(Outcome::Refused(format!(
                "clips {} and {} have no room to overlap by shifting: {asked} frames were \
                 asked for and half of the shorter clip is {allowed} frames",
                earlier.id, later.id
            )));
        }
        let most = frames;
        while frames > 0 {
            let mut next = self.clone();
            shift_clips(&mut next, cut, -(frames * frame));
            if touched
                .iter()
                .all(|track| next.check_overlap_rule(&[], *track, &[]).is_ok())
            {
                if let Some(slot) = next.clip_mut(later.id) {
                    slot.transition_in = Some(match (kind, later.transition_in) {
                        (Some(kind), Some(stored)) => Transition { kind, ..stored },
                        (Some(kind), None) => Transition::minted(kind),
                        (None, Some(stored)) => stored,
                        (None, None) => Transition::minted(TransitionKind::default()),
                    });
                }
                set_gained_transitions(&mut next, &touched);
                return self.finish(next);
            }
            frames -= 1;
        }
        Ok(Outcome::Refused(format!(
            "clips {} and {} cannot overlap by shifting: no overlap from {most} frames down \
             to one leaves every track the shift moves inside the overlap rule",
            earlier.id, later.id
        )))
    }

    /// How many whole frames the INCOMING clip could be extended backward
    /// by, or `None` for a source with no window at all. See
    /// [`Project::add_transition`] step 2 for why a nest answers `Some(0)`.
    fn head_handle_frames(&self, clip: &Clip, frame: Ticks) -> Option<Ticks> {
        let head = match clip.source {
            Source::Media { .. } => self.source_head(clip).unwrap_or(0),
            Source::Nest { .. } => 0,
            _ => return None,
        };
        // Snapped INWARD from the earliest start the handle allows, so the
        // count is whole frames of material that is really there even when
        // the clip's own start is not on the grid.
        let earliest = self.snapped_up(clip.start.saturating_sub(head));
        Some(clip.start.saturating_sub(earliest).max(0) / frame)
    }

    /// How many whole frames the OUTGOING clip could be extended forward
    /// by, or `None` for a source with no window at all.
    fn tail_handle_frames(&self, clip: &Clip, frame: Ticks) -> Option<Ticks> {
        let tail = match clip.source {
            Source::Media { .. } => match self.source_length(clip) {
                // No measurable window is no tail, not an unbounded one.
                None => 0,
                Some(available) => available.saturating_sub(clip.duration).max(0),
            },
            Source::Nest { project, .. } => self
                .nest(project)
                .map_or(0, |nest| nest.duration().saturating_sub(clip.duration))
                .max(0),
            _ => return None,
        };
        let end = clip_end(clip);
        let latest = self.snapped_down(end.saturating_add(tail));
        Some(latest.saturating_sub(end).max(0) / frame)
    }

    /// Sets the transition's CURVE and whether it crossfades the sound
    /// (spec §6, format version 7), leaving its kind alone.
    ///
    /// A second op rather than two more arguments on
    /// [`Project::set_transition`], and the reason is the envelope: that op
    /// reads an absent `kind` and an explicit `null` as the same thing — a
    /// CLEAR — so it has no way to spell "leave the curve where it is".
    /// Here neither argument is nullable, so an absent key is unambiguous
    /// and means keep.
    ///
    /// It stores on the same terms `set_transition` does: any clip, with or
    /// without an overlap, since a stored transition on a clip with no
    /// overlap is simply undrawn until one exists. With NO stored
    /// transition and at least one key given it mints
    /// (`cross_dissolve`, spec §11 R5-2) and applies the style over it;
    /// with NEITHER key given it is an identity whatever the clip holds
    /// and never mints — asking for no change is not a way to make a
    /// transition. `Err` for an unknown clip.
    pub fn set_transition_style(
        &self,
        clip: u32,
        curve: Option<Curve>,
        audio: Option<bool>,
    ) -> Result<Outcome, String> {
        let stored = self.require_clip(clip)?.transition_in;
        if curve.is_none() && audio.is_none() {
            return Ok(Outcome::Identity);
        }
        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            let mut transition =
                stored.unwrap_or_else(|| Transition::minted(TransitionKind::default()));
            if let Some(curve) = curve {
                transition.curve = curve;
            }
            if let Some(audio) = audio {
                transition.audio = audio;
            }
            slot.transition_in = Some(transition);
        }
        self.finish(next)
    }

    /// Moves the clip so its overlap with its predecessor is exactly
    /// `duration` (spec §6) — the transition's length IS that overlap, so
    /// there is nothing else to set.
    ///
    /// Refuses when the clip has no predecessor on its track, when the new
    /// start would be negative, or when the result breaks the overlap rule.
    /// `Err` on a negative duration.
    pub fn set_transition_duration(&self, clip: u32, duration: Ticks) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let duration = self.snapped(duration);
        if duration < 0 {
            return Err(format!(
                "transition duration must not be negative, not {duration}"
            ));
        }
        let ordered = self.clips_on_track(target.track);
        let index = match ordered.iter().position(|c| c.id == clip) {
            Some(index) => index,
            None => return Ok(Outcome::Identity),
        };
        let Some(previous) = index.checked_sub(1).and_then(|i| ordered.get(i)) else {
            return Ok(Outcome::Identity);
        };
        // The overlap is the tail of the previous clip the later one covers,
        // so the later one starts exactly `duration` before that tail ends.
        let start = clip_end(previous).saturating_sub(duration);
        if start < 0 {
            return Ok(Outcome::Identity);
        }

        let mut moved = target.clone();
        moved.start = start;
        if let Err(why) = self.check_overlap_rule(&[moved.clone()], moved.track, &[]) {
            return Ok(Outcome::Refused(why));
        }

        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            slot.start = start;
        }
        set_gained_transitions(&mut next, &[target.track]);
        self.finish(next)
    }
}
