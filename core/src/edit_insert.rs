//! Insert and overwrite — spec §6 rows `insert_clip` and `overwrite_clip`.
//!
//! The two ways to bring new material into a cut that is already timed.
//! An **insert** makes room for it: the track is cut under the drop point
//! and everything from there on moves later by the new clip's length, so
//! nothing is lost and every following clip keeps its relative timing. An
//! **overwrite** takes room from what is there: the span the new clip needs
//! is cleared on that track alone and nothing moves at all, so the cut's
//! total length and every other track are untouched.
//!
//! Both are compositions of ops that already exist — `split_clips`,
//! `insert_time`, `add_clip` — and both are ONE op anyway, for two reasons.
//! The first is undo: a drop from the media list is one gesture and must be
//! one step, and three ops applied in a row are three. The second is that
//! the composition has a rule in it that neither half states — an insert
//! cuts only the DESTINATION track and then shifts every unlocked one, so
//! the straddling clips elsewhere ride the shift whole (spec §11's rule 3)
//! while the one under the drop is cut. Written out at each call site, that
//! rule would be restated in the timeline, the menu and the MCP handler.
//!
//! Neither op invents a length: `whole_media_length` is what `add_clip`
//! itself uses, so the room an insert opens is exactly the room the clip
//! needs.

use crate::edit_clip::clip_end;
use crate::model::Project;
use crate::time::Ticks;

impl Project {
    /// The insert edit: `media` lands whole at `at` on `track`, and
    /// everything at or after `at` moves later by its length (spec §6).
    ///
    /// The clip `at` falls strictly inside on THIS track is split first, so
    /// the insert lands between two clips rather than on top of one. Other
    /// tracks are not cut: `insert_time` shifts them whole, straddlers
    /// staying put, which is what keeps a music bed unbroken under an
    /// insert into the picture.
    ///
    /// **A locked destination track refuses**, up front rather than by
    /// collision. `insert_time` will not shift a locked track, so the room
    /// an insert promises cannot be made there at all; leaving it to
    /// `add_clip` to notice would refuse only where the locked track
    /// happened to hold something at `at`, and quietly add a clip to a
    /// locked track everywhere else. `close_gap` refuses for the same
    /// reason.
    ///
    /// `Err` for an unknown track or media, or a media with no duration;
    /// `None` for a locked destination track, or when the clip could not be
    /// placed after the room was made.
    pub fn insert_clip(
        &self,
        track: u32,
        media: u32,
        at: Ticks,
    ) -> Result<Option<Project>, String> {
        if self.require_track(track)?.locked {
            return Ok(None);
        }
        let found = self.require_media(media)?.clone();
        let at = self.snapped(at).max(0);
        let length = self.whole_media_length(&found)?;

        let straddling: Vec<u32> = self
            .clips_on_track(track)
            .iter()
            .filter(|c| c.start < at && at < clip_end(c))
            .map(|c| c.id)
            .collect();
        let mut next = self
            .split_clips(&straddling, at)?
            .unwrap_or_else(|| self.clone());
        if let Some(opened) = next.insert_time(at, length)? {
            next = opened;
        }
        let Some(placed) = next.add_clip(track, media, at)? else {
            return Ok(None);
        };
        self.finish(placed)
    }

    /// The overwrite edit: `media` lands whole at `at` on `track`, and
    /// whatever that track was playing across the span it needs is removed
    /// (spec §6). Nothing moves, and no other track is touched.
    ///
    /// The span is cut at both bounds first, so everything that touched it
    /// afterwards lies entirely inside it and can be dropped whole; a clip
    /// that covered the whole span becomes a head and a tail with the new
    /// clip between them.
    ///
    /// The named track is cleared whether or not it is LOCKED — the caller
    /// named it, exactly as `ripple_delete` removes the clips it was given
    /// — while a lock still decides what may shift, which here is nothing.
    ///
    /// `Err` for an unknown track or media, or a media with no duration;
    /// `None` when the clip could not be placed after the span was cleared.
    pub fn overwrite_clip(
        &self,
        track: u32,
        media: u32,
        at: Ticks,
    ) -> Result<Option<Project>, String> {
        self.require_track(track)?;
        let found = self.require_media(media)?.clone();
        let at = self.snapped(at).max(0);
        let length = self.whole_media_length(&found)?;
        // Both bounds are already on the frame grid, so the span is too.
        let end = at.saturating_add(length);

        let mut next = self.clone();
        for bound in [at, end] {
            let cut: Vec<u32> = next
                .clips_on_track(track)
                .iter()
                .filter(|c| c.start < bound && bound < clip_end(c))
                .map(|c| c.id)
                .collect();
            let split = next.split_clips(&cut, bound)?;
            if let Some(project) = split {
                next = project;
            }
        }
        let inside: Vec<u32> = next
            .clips_on_track(track)
            .iter()
            .filter(|c| c.start >= at && clip_end(c) <= end)
            .map(|c| c.id)
            .collect();
        next.clips.retain(|c| !inside.contains(&c.id));

        let Some(placed) = next.add_clip(track, media, at)? else {
            return Ok(None);
        };
        self.finish(placed)
    }
}
