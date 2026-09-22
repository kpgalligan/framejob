//! Placement commit protocol: validate candidate tracks, write placements,
//! mint gained transitions, then return the edit's three-way outcome.

use crate::edit_transition::set_gained_transitions;
use crate::model::{Clip, Project};
use crate::outcome::Outcome;

impl Project {
    /// Replace already resolved clips in one draft, checking old tracks
    /// before destination tracks in caller order.
    pub(crate) fn commit_replacements(&self, replacements: Vec<Clip>) -> Result<Outcome, String> {
        let mut tracks = Vec::new();
        for clip in &replacements {
            let old = self.require_clip(clip.id)?.track;
            if !tracks.contains(&old) {
                tracks.push(old);
            }
        }
        for clip in &replacements {
            if !tracks.contains(&clip.track) {
                tracks.push(clip.track);
            }
        }
        for track in &tracks {
            if let Err(why) = self.check_overlap_rule(&replacements, *track, &[]) {
                return Ok(Outcome::Refused(why));
            }
        }

        let mut next = self.clone();
        for replacement in replacements {
            if let Some(slot) = next.clip_mut(replacement.id) {
                *slot = replacement;
            }
        }
        self.finish_placement(next, &tracks)
    }

    /// Append caller-allocated clips to a private draft after checking the
    /// input project. The draft may already contain new tracks or incidental
    /// property changes, but none of the added clips.
    pub(crate) fn commit_additions(
        &self,
        mut next: Project,
        additions: Vec<Clip>,
    ) -> Result<Outcome, String> {
        let mut tracks = Vec::new();
        for clip in &additions {
            if !tracks.contains(&clip.track) {
                tracks.push(clip.track);
            }
        }
        for track in &tracks {
            if let Err(why) = self.check_overlap_rule(&additions, *track, &[]) {
                return Ok(Outcome::Refused(why));
            }
        }
        next.clips.extend(additions);
        self.finish_placement(next, &tracks)
    }

    /// Complete a placement after its caller has chosen its exact tracks.
    /// No overlap check or early identity belongs here: even a zero-distance
    /// move can gain a transition on an affected track.
    pub(crate) fn finish_placement(
        &self,
        mut next: Project,
        tracks: &[u32],
    ) -> Result<Outcome, String> {
        set_gained_transitions(&mut next, tracks);
        self.finish(next)
    }

    /// The single exit of every op: a result equal to the input is
    /// [`Outcome::Identity`] (never a copy, which would register a phantom
    /// undo step), and a result that broke an invariant is an `Err` rather
    /// than a project the rest of the crate cannot reason about.
    ///
    /// It never answers [`Outcome::Refused`]: a rule that says no does so
    /// where it is asked, with its own sentence, before anything is built
    /// for this to judge.
    pub(crate) fn finish(&self, next: Project) -> Result<Outcome, String> {
        if next == *self {
            return Ok(Outcome::Identity);
        }
        next.validate()?;
        Ok(Outcome::Applied(next))
    }
}
