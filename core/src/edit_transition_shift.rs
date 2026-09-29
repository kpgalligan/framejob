//! The `ripple` half of `add_transition` — the overlap made by SHIFTING
//! rather than out of the two clips' handles.
//!
//! Cut out of `edit_transition.rs` under the size rule, a pure move. It
//! sits in its own file rather than beside the handle form because the two
//! answer the same question out of different material: the handle form
//! spends unused source and moves nothing, while this one spends the
//! TIMELINE and moves every clip at or after the cut, which is
//! `close_gap`'s set and `close_gap`'s rules. `add_transition` reads the
//! arguments, finds the cut and hands over here (spec §11, R5-3's
//! amendment of 2026-09-16); nothing else calls it.

use crate::edit_time::{locked_track, shift_clips, unlocked_tracks};
use crate::edit_transition::transition_too_short;
use crate::model::{Clip, Project, Transition, TransitionKind};
use crate::outcome::Outcome;
use crate::time::{frames_back, frames_in, frames_within, snap_up_to_frame, Ticks};
use crate::transition_search::shift_frame_limit;

impl Project {
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
    /// The duration is counted in whole frames of the canvas's own grid
    /// (`time::frames_in`), capped at the frames that fit in half the
    /// shorter of the two clips back from the cut (the pair's own overlap
    /// rule, closed form), and then searched for the greatest count at which
    /// every track something moved on passes the overlap rule — clamped
    /// rather than refused, the handle form's posture. The incoming clip
    /// lands that many GRID frames back from the cut (`time::frames_back`),
    /// and everything else moves by the same delta (spec §11 #42). A clip on
    /// another track that the shift pushes into its predecessor gains a
    /// minted `cross_dissolve`, which is `close_gap`'s rule for the same
    /// shift.
    ///
    /// Four refusals, each in its own sentence: an incoming clip on a
    /// LOCKED track cannot move ([`locked_track`]); a request under one grid
    /// frame is too short ([`transition_too_short`]); a pair whose shorter
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
        let fps = self.canvas.fps;
        let asked = frames_in(duration, fps);
        if asked < 1 {
            let one = snap_up_to_frame(1, fps);
            return Ok(Outcome::Refused(transition_too_short(
                later.id, duration, one,
            )));
        }
        let cut = later.start;
        let mut touched: Vec<u32> = Vec::new();
        for clip in &self.clips {
            if clip.start >= cut && unlocked.contains(&clip.track) && !touched.contains(&clip.track)
            {
                touched.push(clip.track);
            }
        }

        let shorter = earlier.duration.min(later.duration);
        // The pair rule is in ticks; how many grid frames back from the cut
        // fit inside it is the count the shift may spend.
        let allowed = frames_within(cut, shorter / 2, fps);
        let frames = asked.min(allowed);
        if frames <= 0 {
            return Ok(Outcome::Refused(format!(
                "clips {} and {} have no room to overlap by shifting: the overlap asked \
                 for is {asked} frames and half of the shorter clip is {allowed} frames",
                earlier.id, later.id
            )));
        }
        let most = frames;
        for track in &touched {
            if let Err(why) = self.check_overlap_rule(&[], *track, &[]) {
                return Ok(Outcome::Refused(why));
            }
        }
        if let Some(frames) = shift_frame_limit(self, cut, most, &touched) {
            let mut next = self.clone();
            shift_clips(
                &mut next,
                cut,
                frames_back(cut, frames, fps).saturating_sub(cut),
            );
            for track in &touched {
                if let Err(why) = next.check_overlap_rule(&[], *track, &[]) {
                    return Ok(Outcome::Refused(why));
                }
            }
            if let Some(slot) = next.clip_mut(later.id) {
                slot.transition_in = Some(match (kind, later.transition_in) {
                    (Some(kind), Some(stored)) => Transition { kind, ..stored },
                    (Some(kind), None) => Transition::minted(kind),
                    (None, Some(stored)) => stored,
                    (None, None) => Transition::minted(TransitionKind::default()),
                });
            }
            return self.finish_placement(next, &touched);
        }
        Ok(Outcome::Refused(format!(
            "clips {} and {} cannot overlap by shifting: no overlap from {most} frames down \
             to one leaves every track the shift moves inside the overlap rule",
            earlier.id, later.id
        )))
    }
}
