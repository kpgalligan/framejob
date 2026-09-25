//! Slip and roll — spec §6 rows `slip` and `roll`.
//!
//! What separates these two from `edit_clip.rs`'s trims is that neither
//! changes how long the CUT is. A **slip** changes what a clip shows
//! without moving it: the window stays where it is on the timeline and the
//! film slides under it. A **roll** moves the frame two clips meet on
//! without moving anything else: one grows by exactly what the other loses.
//! They are what a cutter reaches for once the rough assembly is down, when
//! every following clip is already where it belongs and nothing may shift.
//!
//! Both are therefore *conservative* ops, and both are written to refuse
//! rather than approximate. A slip that has run out of source at one end
//! stops, and a slip that could not move at all is an identity — the
//! alternative is a drag that silently becomes a different, shorter edit
//! than the gesture asked for. A roll needs a hard cut to move: with a gap,
//! or with an overlap (which IS a transition, whose length is
//! `set_transition_duration`'s job), there is nothing here to roll.
//!
//! The arithmetic is `source_window.rs`'s — the three measurements of a
//! source window, the conversion into source ticks and the two last legal
//! positions all live there, and this module only clamps against them, so a
//! slip and a trim can never disagree about where a media ends.

use crate::edit_clip::clip_end;
use crate::model::{Project, Source};
use crate::model_words::rebase_words;
use crate::outcome::Outcome;
use crate::recipe_graphic::graphic_advanced;
use crate::source_window::{source_advanced, timeline_to_source};
use crate::time::Ticks;

impl Project {
    /// Slides the source window under a fixed clip: what the clip shows
    /// changes, where it sits does not (spec §6).
    ///
    /// `delta` is TIMELINE ticks — the distance the gesture travelled — so
    /// the source moves by `delta × speed`, the same conversion
    /// `trim_start` makes when it advances `in`. A positive `delta` shows
    /// LATER material, which is the direction the drag reads: pulling the
    /// clip right pulls the film forward under the window.
    ///
    /// Clamped so the window stays inside the media — `in ≥ 0` at the head,
    /// `in + duration × speed ≤ media.duration` at the tail — and a slip
    /// the clamps reduce to nothing is an identity.
    ///
    /// A `still` has one source TIME rather than a window, so it moves that
    /// instead, clamped inside the media the same way. Every other source
    /// has nothing to slip and is an `Err` under the non-media rule.
    ///
    /// **The source kind is decided FIRST**, before the delta is even
    /// measured. A text clip named for a slip is an invalid argument
    /// whatever the delta was, and letting a sub-frame delta short-circuit
    /// to an identity would answer "valid, changes nothing" to a call that
    /// was never valid — the one answer the non-media rule exists to stop
    /// the MCP agent being given.
    ///
    /// Nothing moves, so there is no overlap to check and no transition can
    /// be gained; the actions are clip-relative and stay exactly where they
    /// are.
    pub fn slip(&self, clip: u32, delta: Ticks) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let (media, current) = match target.source {
            Source::Media { media, r#in, .. } => (media, r#in),
            Source::Still { media, at } => (media, at),
            _ => return Err(format!("clip {clip} is not a media clip")),
        };

        let delta = self.snapped(delta);
        // Timeline ticks to source ticks, at this clip's rate. A sub-tick
        // move at a very slow speed rounds to nothing, which is a refusal
        // and not an edit.
        let moved_by = timeline_to_source(delta, target.speed);
        if moved_by == 0 {
            return Ok(Outcome::Identity);
        }

        // The last legal position of what the clip shows: a window is
        // pushed against the tail of the file, a still stops one frame
        // short of it. Both are `source_window.rs`'s, which is also where
        // the reasons for the two shapes are written down.
        let media = self.require_media(media)?;
        let last = match target.source {
            Source::Still { .. } => self.last_still_time(media),
            _ => self.last_in_point(&target, media),
        };
        let slipped = current.saturating_add(moved_by).clamp(0, last);
        if slipped == current {
            return Ok(Outcome::Identity);
        }

        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            slot.source = match &slot.source {
                Source::Media {
                    media, reversed, ..
                } => Source::Media {
                    media: *media,
                    r#in: slipped,
                    reversed: *reversed,
                },
                Source::Still { media, .. } => Source::Still {
                    media: *media,
                    at: slipped,
                },
                other => other.clone(),
            };
        }
        self.finish(next)
    }

    /// Moves a hard cut: this clip's start and its predecessor's end both
    /// become `to`, and nothing else in the timeline moves (spec §6).
    ///
    /// The predecessor is the clip on the same track that ends EXACTLY at
    /// this clip's start. With no such clip the op refuses — a gap has no
    /// cut to roll, and an overlap is a transition whose length
    /// `set_transition_duration` owns.
    ///
    /// `to` is clamped four ways, one pair per side: each clip keeps at
    /// least one frame, this clip may only reach back as far as its own
    /// source head allows (it grows at the FRONT, with front-trim
    /// semantics, so `in` follows), and the predecessor may only reach
    /// forward as far as its remaining source allows (it grows at the END,
    /// a plain end trim, so its `in` does not move). A `to` the clamps
    /// leave equal to the current cut is an identity, and so is a pair of
    /// clamps that cross — a cut with no legal position is not one this op
    /// can move.
    ///
    /// Neither clip's outer edge moves, so the pair still abuts exactly and
    /// no transition can be gained; the actions on both are clip-relative
    /// and stay where they are, as they do for a trim. This clip's
    /// `text.words` are rebased by the move, as `trim_start` rebases them
    /// (spec §11, W-3): a word stays on the speech it times. Its
    /// `graphic.in` advances by the move as `trim_start`'s does, and the
    /// predecessor's `length` is untouched (road map 10's G-9).
    pub fn roll(&self, clip: u32, to: Ticks) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let Some(previous) = self
            .clips_on_track(target.track)
            .into_iter()
            .find(|c| c.id != target.id && clip_end(c) == target.start)
            .cloned()
        else {
            return Ok(Outcome::Identity);
        };

        let frame = self.frame();
        let mut earliest = previous.start.saturating_add(frame);
        let mut latest = clip_end(&target).saturating_sub(frame);
        if let Some(start) = self.earliest_start_on_grid(&target) {
            earliest = earliest.max(start.max(0));
        }
        if let Some(end) = self.latest_end_on_grid(&previous) {
            latest = latest.min(end);
        }
        // The two source bounds arrive on the grid (`source_window.rs`
        // snaps each inward, and this pair is where that rule came from),
        // but the one-frame bounds are measured from the clips' own starts,
        // which a hand-written document may put off it. So both are snapped
        // INWARD again — up at the bottom, down at the top — and the cut
        // lands on a frame that is still inside the source both clips have.
        let earliest = self.snapped_up(earliest);
        let latest = self.snapped_down(latest);
        if earliest > latest {
            return Ok(Outcome::Identity);
        }
        let to = self.snapped(to).clamp(earliest, latest);
        if to == target.start {
            return Ok(Outcome::Identity);
        }

        let mut moved = target.clone();
        moved.source = source_advanced(
            &target.source,
            to.saturating_sub(target.start),
            target.speed,
        );
        moved.graphic = graphic_advanced(target.graphic.as_ref(), to.saturating_sub(target.start));
        moved.start = to;
        moved.duration = clip_end(&target).saturating_sub(to);
        if let Some(text) = moved.text.as_mut() {
            rebase_words(text, to.saturating_sub(target.start));
        }

        let mut grown = previous.clone();
        grown.duration = to.saturating_sub(previous.start);

        // The clamps make this unreachable for the pair itself; it is here
        // because every placement op checks, and because a track that
        // already held something the rule dislikes should not have it made
        // worse by an edit that thought it was safe.
        if let Err(why) =
            self.check_overlap_rule(&[moved.clone(), grown.clone()], target.track, &[])
        {
            return Ok(Outcome::Refused(why));
        }

        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(target.id) {
            *slot = moved;
        }
        if let Some(slot) = next.clip_mut(previous.id) {
            *slot = grown;
        }
        self.finish(next)
    }
}
