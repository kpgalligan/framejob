//! Placement commit protocol: validate candidate tracks, write placements,
//! mint gained transitions, then return the edit's three-way outcome.
//!
//! It also holds what a placement is built from: `Clip::placed`, the one
//! literal of a freshly placed clip that every adding op overrides by
//! struct update; `Project::add_tracks_behind`, the tracks a placement
//! missing behind its destination inserts at the back; and [`Landing`],
//! unnest's and paste's shared landing — the wanted track, then the
//! fallbacks already added, then a new track in front.

use crate::edit_transition::set_gained_transitions;
use crate::model::{Clip, Enabled, Project, Source};
use crate::outcome::Outcome;
use crate::time::Ticks;

impl Clip {
    /// A freshly placed clip: enabled both ways, ×1, no actions, and every
    /// optional group, transition, name and label absent. Each adding op
    /// overrides what it sets by struct update.
    ///
    /// A field added to [`Clip`] later silently takes this default at every
    /// placing site. That is deliberate: a newly placed clip has none of the
    /// new state. Not a `Default` impl, because a clip with no id, track or
    /// source is not a clip.
    pub(crate) fn placed(
        id: u32,
        track: u32,
        start: Ticks,
        duration: Ticks,
        source: Source,
    ) -> Clip {
        Clip {
            id,
            track,
            start,
            duration,
            source,
            enabled: Enabled::default(),
            speed: 1.0,
            video: None,
            audio: None,
            text: None,
            shape: None,
            graphic: None,
            actions: Vec::new(),
            transition_in: None,
            name: None,
            label: None,
        }
    }
}

/// Where unnest's and paste's clips land, one clip at a time, in the order
/// the caller places them: the track `depth` back from `base`, then any
/// fallback track already added, then a new track in front. Remembers the
/// tracks it touched, in first-seen order, for `finish_placement`.
pub(crate) struct Landing {
    base: i64,
    fallbacks: Vec<u32>,
    touched: Vec<u32>,
}

impl Landing {
    pub(crate) fn new(base: i64) -> Landing {
        Landing {
            base,
            fallbacks: Vec::new(),
            touched: Vec::new(),
        }
    }

    /// Lands `clip` on the first candidate the overlap rule accepts and
    /// pushes it onto `next`. A fallback track is PUSHED (in front), ordinary.
    pub(crate) fn land(&mut self, next: &mut Project, mut clip: Clip, depth: i64) {
        let wanted = next
            .tracks
            .get((self.base - depth).max(0) as usize)
            .map(|t| t.id);
        let mut chosen: Option<u32> = None;
        for candidate in wanted.into_iter().chain(self.fallbacks.iter().copied()) {
            clip.track = candidate;
            if next
                .check_overlap_rule(std::slice::from_ref(&clip), candidate, &[])
                .is_ok()
            {
                chosen = Some(candidate);
                break;
            }
        }
        // A brand-new track holds nothing, so the last arm always
        // succeeds and the loop always terminates.
        let landed = match chosen {
            Some(id) => id,
            None => {
                let track = next.numbered_track();
                let id = track.id;
                next.tracks.push(track);
                self.fallbacks.push(id);
                id
            }
        };
        clip.track = landed;
        if !self.touched.contains(&landed) {
            self.touched.push(landed);
        }
        next.clips.push(clip);
    }

    /// The tracks a clip landed on, in first-seen order.
    pub(crate) fn touched(&self) -> &[u32] {
        &self.touched
    }
}

impl Project {
    /// Inserts the tracks missing behind a placement's destination: `deepest`
    /// is the deepest depth it lands, `base` the destination's index. Each
    /// is a [`Project::numbered_track`] inserted at index 0, one at a time;
    /// inserting there shifts every existing track up, so the answer is the
    /// destination's index after them, `base` plus their count.
    pub(crate) fn add_tracks_behind(&mut self, deepest: i64, base: i64) -> i64 {
        let deficit = (deepest - base).max(0);
        for _ in 0..deficit {
            let track = self.numbered_track();
            self.tracks.insert(0, track);
        }
        base + deficit
    }

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
