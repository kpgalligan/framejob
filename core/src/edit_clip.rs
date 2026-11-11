//! The clip and action ops — spec §6, tables "Clips" and "Actions".
//!
//! One `impl Project` block holding clip construction, moves, copies and
//! deletes. Timing edits are in `edit_clip_timing.rs`; their placement commit
//! is in `edit_commit.rs`. The five property patches are the
//! OTHER half of the clip surface, `edit_props.rs`'s, policed by the range
//! checks of `props_check.rs`: this file decides where a clip sits, that one
//! what it looks like. The action ops, which were here, are `edit_action.rs`;
//! the transition ops, which were here too, are `edit_transition.rs`; and
//! `split_clip` with its two helpers, which every splitter in the crate
//! routes through, is `edit_split.rs` — a split is not a placement but a
//! question about what the SECOND clip inherits, and road map 5's E2 added
//! a rule to it. Detach Audio and `set_enabled`, a clip's two halves, are
//! `edit_detach.rs`'s.
//! `edit.rs` dispatches to all of them by name; nothing here knows about JSON
//! op envelopes, and nothing here mutates `self` — an edit clones, changes
//! the clone, and hands it back (spec §5.5).
//!
//! Three rules run through all of it:
//!
//! 1. **Every tick argument is snapped to the canvas frame grid first**
//!    ([`Project::snapped`]), durations included. Nothing sub-frame ever
//!    reaches the model.
//! 2. **Placement is checked, never repaired.** A move, trim or duplicate
//!    that would break the overlap rule is REFUSED, in the rule's own
//!    sentence ([`Outcome::Refused`]) — the UI animates it back. The rule
//!    itself lives in `transition.rs` and is called, never restated, which
//!    is why the sentence the caller reads is the one the rule wrote.
//! 3. **Every op leaves the project valid.** [`Project::finish`] is the
//!    single exit: it answers [`Outcome::Identity`] when the result equals
//!    the input (no phantom undo step) and turns a broken invariant into
//!    `Err`.
//!
//! The pieces those three rules are made of — `snapped`, `frame`, the
//! `require_*` lookups, `selected_clips` and `clip_end` — are `pub(crate)`
//! so other edit modules obey the same rules by calling them. Placement
//! finalization and `finish` live in `edit_commit.rs`.
//! `add_text_clip`, `add_shape_clip` and `add_described_clip` are `edit_described.rs`'s.

use std::collections::HashMap;

use crate::edit_cut_rule::Pieces;
use crate::edit_link::{pair_split_halves, relink_copies};
use crate::edit_split::split_clip;
use crate::model::{AudioProps, Clip, Media, MediaKind, Project, Source, Track, VideoProps};
use crate::outcome::Outcome;
use crate::time::{self, Ticks, TIMESCALE};

/// Default duration for a source with no source bound — text, shape, and an
/// image whose descriptor carries no duration. Five seconds is a common
/// title default and long enough to read.
pub(crate) const DEFAULT_CLIP_DURATION: Ticks = 5 * TIMESCALE;

// ---- clip helpers --------------------------------------------------------

pub(crate) fn clip_end(clip: &Clip) -> Ticks {
    clip.start.saturating_add(clip.duration)
}

// ---- the ops -------------------------------------------------------------

impl Project {
    /// A tick value on the document's frame grid. Every op runs its
    /// arguments through this before anything else (spec §6).
    pub(crate) fn snapped(&self, t: Ticks) -> Ticks {
        time::snap_to_frame(t, self.canvas.fps)
    }

    /// The frame boundary at or after `t`, and the one at or before it —
    /// for a clamp BOUND, which cannot be rounded to the nearest frame the
    /// way a value can without letting a caller past what it protects.
    pub(crate) fn snapped_up(&self, t: Ticks) -> Ticks {
        time::snap_up_to_frame(t, self.canvas.fps)
    }

    pub(crate) fn snapped_down(&self, t: Ticks) -> Ticks {
        time::snap_down_to_frame(t, self.canvas.fps)
    }

    /// One frame of canvas time — the shortest a clip or an action may be:
    /// the grid's own first frame at every rate (`time::one_frame`, spec
    /// §11 #174), and 1/30 s only at a degenerate rate, so never zero.
    pub(crate) fn frame(&self) -> Ticks {
        time::one_frame(self.canvas.fps)
    }

    pub(crate) fn require_clip(&self, id: u32) -> Result<&Clip, String> {
        self.clip(id).ok_or_else(|| format!("no clip with id {id}"))
    }

    pub(crate) fn require_track(&self, id: u32) -> Result<&Track, String> {
        self.track(id)
            .ok_or_else(|| format!("no track with id {id}"))
    }

    pub(crate) fn require_media(&self, id: u32) -> Result<&Media, String> {
        self.media(id)
            .ok_or_else(|| format!("no media with id {id}"))
    }

    pub(crate) fn require_track_index(&self, id: u32) -> Result<usize, String> {
        self.track_index(id)
            .ok_or_else(|| format!("no track with id {id}"))
    }

    /// How long a clip showing the WHOLE of `media` is — what `add_clip`
    /// gives one, and therefore how much room `insert_clip` opens and how
    /// much span `overwrite_clip` clears.
    ///
    /// **A timed media's length is THE bound at 1:1**, snapped DOWN
    /// (`source_window.rs`, spec §11): the nearest snap rounds UP past the
    /// end of the file, down-snapped `in + duration × speed ≤
    /// media.duration` holds and the rate is exactly 1. The price is a
    /// frame of the tail, and a media shorter than a frame, which is an
    /// `Err` naming the frame as one with no duration always has been.
    ///
    /// An image has no source bound and keeps the NEAREST snap of its
    /// descriptor's length or of the default — a constant is not on the
    /// grid of a rate that does not divide the timescale (at 30000/1001
    /// five seconds is 3 003 000 ticks, not 3 000 000), and the raw one
    /// made `insert_clip` open a hole wider than the clip it placed.
    pub(crate) fn whole_media_length(&self, media: &Media) -> Result<Ticks, String> {
        match media.kind {
            MediaKind::Lut => Err(crate::lut::lut_not_placeable(media.id)),
            MediaKind::Image if media.duration <= 0 => {
                Ok(self.snapped(DEFAULT_CLIP_DURATION).max(self.frame()))
            }
            MediaKind::Image => Ok(self.snapped(media.duration)),
            MediaKind::Video | MediaKind::Audio if media.duration <= 0 => Err(format!(
                "media {} has no duration ({} ticks)",
                media.id, media.duration
            )),
            MediaKind::Video | MediaKind::Audio => {
                // THE bound (`source_window.rs`) over the whole file from
                // tick 0 at 1:1; a literal 1.0 is always measurable.
                let duration = self
                    .longest_duration_on_grid_of(0, media, 0, 1.0)
                    .or_unbounded()
                    .unwrap_or(0);
                if duration <= 0 {
                    return Err(format!(
                        "media {} is shorter than a frame ({} ticks; a frame is {} ticks)",
                        media.id,
                        media.duration,
                        self.snapped_up(1)
                    ));
                }
                Ok(duration)
            }
        }
    }

    // ---- adding clips ----------------------------------------------------

    /// Places the whole of `media` as one clip at `at` on `track`, source
    /// in 0, with Fit scale when the canvas asks for it and the source
    /// exceeds it (spec §6).
    ///
    /// `video` is `null` for an audio-only file and `audio` is `null` for a
    /// file with no audio track, which is how the inspector knows which
    /// tabs to enable. Refuses when the placement breaks the overlap rule;
    /// `Err` for an unknown track or media, or a media with no usable
    /// duration.
    pub fn add_clip(&self, track: u32, media: u32, at: Ticks) -> Result<Outcome, String> {
        self.require_track(track)?;
        let found = self.require_media(media)?.clone();
        // A drag can start left of zero; the timeline has no negative time.
        let at = self.snapped(at).max(0);

        let duration = self.whole_media_length(&found)?;
        let source = match found.kind {
            MediaKind::Image => Source::Image { media },
            MediaKind::Video | MediaKind::Audio => Source::Media {
                media,
                r#in: 0,
                reversed: false,
            },
            MediaKind::Lut => return Err(crate::lut::lut_not_placeable(media)),
        };

        let has_pixels = found.has_video || matches!(found.kind, MediaKind::Image);
        let video = has_pixels.then(|| VideoProps {
            scale: self.fit_scale(f64::from(found.width), f64::from(found.height)),
            ..VideoProps::default()
        });
        let audio = found.has_audio.then(AudioProps::default);

        let mut next = self.clone();
        let clip = Clip {
            video,
            audio,
            ..Clip::placed(next.allocate_id(), track, at, duration, source)
        };
        self.commit_additions(next, vec![clip])
    }

    // ---- moving -----------------------------------------------------------

    /// Shifts `clips` by `delta` ticks and, when `track` is given, moves
    /// them to that track keeping their relative track offsets (spec §6).
    ///
    /// The EARLIEST clip clamps at 0 and the rest keep their offsets, so a
    /// drag past the start of the timeline compresses nothing. The
    /// destination is computed as an index delta from the first clip of the
    /// selection (by track order, then start), which is what makes a
    /// two-track selection land two tracks apart.
    ///
    /// Refuses when a clip would land outside the track list or the overlap
    /// rule fails on any affected track. A clip that gains a predecessor
    /// overlap and has no transition gets a cross dissolve.
    ///
    /// **A linked partner follows in TIME, not in track** (spec §11 AU-91):
    /// every clip of the closure moves by the one delta, the clamp at 0 is
    /// taken over the closure so a J-cut's lead is kept, and the track delta
    /// is anchored on and applied to the CALLER's clips only — so a sound
    /// half dragged to a track of its own goes alone and its picture stays.
    pub fn move_clips(
        &self,
        clips: &[u32],
        delta: Ticks,
        track: Option<u32>,
    ) -> Result<Outcome, String> {
        let selection = self.selected_clips(clips)?;
        if selection.is_empty() {
            return Ok(Outcome::Identity);
        }
        let closure = self.selected_clips(&self.with_links(clips)?)?;

        // Snapping the delta keeps a dragged clip on the grid: every start
        // is already on it, so a snapped delta lands on it too.
        let mut delta = self.snapped(delta);
        let earliest = closure.iter().map(|c| c.start).min().unwrap_or(0);
        if delta < -earliest {
            delta = -earliest;
        }

        let index_delta = self.track_index_delta(&selection, track)?;

        let mut candidates: Vec<Clip> = Vec::new();
        for clip in &closure {
            let mut moved = (*clip).clone();
            moved.start = moved.start.saturating_add(delta).max(0);
            if selection.iter().any(|c| c.id == clip.id) {
                match self.landing_track(clip, index_delta)? {
                    Ok(landed) => moved.track = landed,
                    Err(why) => return Ok(Outcome::Refused(why)),
                }
            }
            candidates.push(moved);
        }

        self.commit_replacements(candidates)
    }

    /// How many track indices a selection headed for `track` shifts by: 0
    /// with no destination. The anchor is the FIRST of `anchors` in the
    /// order the timeline draws — back-most track, then earliest — and the
    /// whole selection moves by its offset, which is what keeps a two-track
    /// selection two tracks apart. `Err` for an unknown track.
    fn track_index_delta(&self, anchors: &[&Clip], track: Option<u32>) -> Result<i64, String> {
        let Some(destination) = track else {
            return Ok(0);
        };
        let destination_index = self.require_track_index(destination)? as i64;
        let mut keyed: Vec<(usize, Ticks, u32)> = Vec::new();
        for clip in anchors {
            keyed.push((self.require_track_index(clip.track)?, clip.start, clip.id));
        }
        let anchor = keyed.iter().min().map(|k| k.0).unwrap_or(0) as i64;
        Ok(destination_index - anchor)
    }

    /// The track `clip` lands on `index_delta` indices along: the outer
    /// `Err` an unknown track, the inner one the refusal's sentence. A
    /// selection dragged off either end of the track list is a refusal and
    /// not a clamp — clamping would silently stack two clips on one track —
    /// and it says so in `move_track`'s own words for the same mistake.
    fn landing_track(&self, clip: &Clip, index_delta: i64) -> Result<Result<u32, String>, String> {
        let from = self.require_track_index(clip.track)? as i64;
        let to = from.saturating_add(index_delta);
        let landed = usize::try_from(to)
            .ok()
            .and_then(|index| self.tracks.get(index));
        Ok(landed.map(|track| track.id).ok_or_else(|| {
            format!(
                "clip {} would land on track index {to}, which is out of range (0..{})",
                clip.id,
                self.tracks.len()
            )
        }))
    }

    /// The named clips, deduplicated, in the order given. `Err` on an
    /// unknown id — every multi-clip op names its clips explicitly, so a
    /// stale id is a caller bug, not a refusal.
    pub(crate) fn selected_clips(&self, clips: &[u32]) -> Result<Vec<&Clip>, String> {
        let mut out: Vec<&Clip> = Vec::new();
        for id in clips {
            let clip = self.require_clip(*id)?;
            if !out.iter().any(|c| c.id == clip.id) {
                out.push(clip);
            }
        }
        Ok(out)
    }

    // ---- splitting, deleting, duplicating --------------------------------

    /// Cuts each named clip at project time `at` (spec §6). A clip `at` is
    /// not strictly inside is skipped; when nothing can be cut the whole op
    /// is an identity. `Err` only for an unknown clip id.
    ///
    /// A linked partner is cut too, and the halves are paired (spec §11
    /// AU-92, `edit_link.rs`'s `pair_split_halves`).
    ///
    /// **Refused, nothing cut, when the cut would break THE overlap rule**
    /// on a track it changed — a piece left too short for the transition it
    /// carries — in `edit_cut_rule.rs`'s sentence (spec §11 #427).
    pub fn split_clips(&self, clips: &[u32], at: Ticks) -> Result<Outcome, String> {
        let mut pieces = Pieces::new();
        let Some(next) = self.cut_clips(clips, at, &mut pieces)? else {
            return Ok(Outcome::Identity);
        };
        if let Some(why) = self.cut_refusal(&next, &pieces) {
            return Ok(Outcome::Refused(why));
        }
        Ok(Outcome::Applied(next))
    }

    /// [`Project::split_clips`]' cut with no rule asked: each named clip
    /// and its linked partner cut at `at`, the halves paired, each second
    /// half's source recorded in `pieces`, and the result through `finish`
    /// (so `validate` and the caps judge every cut, as they always did).
    /// `None` when nothing was cut.
    ///
    /// The range ops, `overwrite_clip` and `retime_range` cut through this
    /// and ask the overlap rule once, of what they would store: a piece one
    /// cut leaves too short may be one they remove (spec §11 #427 (a)).
    pub(crate) fn cut_clips(
        &self,
        clips: &[u32],
        at: Ticks,
        pieces: &mut Pieces,
    ) -> Result<Option<Project>, String> {
        let at = self.snapped(at);
        let ids = self.with_links(clips)?;
        let mut next = self.clone();
        let mut halves: Vec<(u32, u32)> = Vec::new();
        for id in ids {
            // `split_clip` allocates the second half's id first.
            let second = next.next_id;
            if split_clip(&mut next, id, at) {
                halves.push((id, second));
            }
        }
        if halves.is_empty() {
            return Ok(None);
        }
        pair_split_halves(&mut next, &halves);
        for (first, second) in &halves {
            pieces.halved(*first, *second);
        }
        // `finish` never refuses, and a cut that minted a clip is never an
        // identity.
        match self.finish(next)? {
            Outcome::Applied(cut) => Ok(Some(cut)),
            Outcome::Identity | Outcome::Refused(_) => Ok(None),
        }
    }

    /// Cuts every clip on an UNLOCKED track that `at` falls strictly inside
    /// — ⌘K with no selection (spec §6, §9).
    ///
    /// The SELECTION is all this op computes; the cutting is
    /// [`Project::split_clips`]'s, called rather than copied, so the two
    /// spellings of ⌘K cannot answer differently. An empty selection is its
    /// identity, which is the same answer a list of clips none of which
    /// straddles `at` gets there.
    pub fn split_under_playhead(&self, at: Ticks) -> Result<Outcome, String> {
        self.split_clips(&self.under_playhead(at), at)
    }

    /// [`Project::split_under_playhead`]'s selection cut by
    /// [`Project::cut_clips`], asking no rule.
    pub(crate) fn cut_under_playhead(
        &self,
        at: Ticks,
        pieces: &mut Pieces,
    ) -> Result<Option<Project>, String> {
        self.cut_clips(&self.under_playhead(at), at, pieces)
    }

    /// Every clip on an unlocked track that `at`, snapped, is strictly
    /// inside.
    fn under_playhead(&self, at: Ticks) -> Vec<u32> {
        let at = self.snapped(at);
        self.clips
            .iter()
            .filter(|c| self.track(c.track).is_some_and(|t| !t.locked))
            .filter(|c| c.start < at && at < clip_end(c))
            .map(|c| c.id)
            .collect()
    }

    /// Removes the named clips. Gaps stay — rippling is `edit_time`'s job
    /// (spec §6). A picture takes its linked sound with it; a linked sound
    /// named alone goes alone (spec §11 AU-91, `delete_closure`).
    pub fn delete_clips(&self, clips: &[u32]) -> Result<Outcome, String> {
        let ids = self.delete_closure(clips)?;
        if ids.is_empty() {
            return Ok(Outcome::Identity);
        }
        let mut next = self.clone();
        next.clips.retain(|c| !ids.contains(&c.id));
        self.finish(next)
    }

    /// Copies the named clips (spec §6). With no `delta` the copies start
    /// one span-length later, immediately after their own span; `delta`
    /// lands them that far from their originals, snapped and clamped at 0
    /// over the closure as [`Project::move_clips`] clamps, so a multi-clip
    /// selection keeps its internal timing exactly either way. With no
    /// `track` each copy stays on its original's track; `track` shifts the
    /// copies of the NAMED clips as `move_clips` shifts them, anchored on
    /// them alone, and a linked partner's copy keeps its original's track
    /// and moves by the one time delta (spec §11 #465, AU-91).
    ///
    /// Clips and their actions get fresh ids, and a linked partner is
    /// copied too, the copies linked to each other (spec §11 AU-96).
    /// Refuses when a named clip's copy would leave the track list, or when
    /// the copies, the partner's included, would break the overlap rule at
    /// the landing, which is the only place it is asked. `Err` for an
    /// unknown track.
    pub fn duplicate_clips(
        &self,
        clips: &[u32],
        delta: Option<Ticks>,
        track: Option<u32>,
    ) -> Result<Outcome, String> {
        let selection = self.selected_clips(clips)?;
        let closure: Vec<Clip> = self
            .selected_clips(&self.with_links(clips)?)?
            .into_iter()
            .cloned()
            .collect::<Vec<Clip>>();
        if closure.is_empty() {
            return Ok(Outcome::Identity);
        }
        let span_start = closure.iter().map(|c| c.start).min().unwrap_or(0);
        let delta = match delta {
            Some(delta) => self.snapped(delta).max(-span_start),
            None => {
                let span_end = closure.iter().map(clip_end).max().unwrap_or(0);
                let span = span_end.saturating_sub(span_start);
                if span <= 0 {
                    return Ok(Outcome::Identity);
                }
                span
            }
        };
        let index_delta = self.track_index_delta(&selection, track)?;

        let mut next = self.clone();
        let mut copies: Vec<Clip> = Vec::new();
        let mut fresh: HashMap<u32, u32> = HashMap::new();
        for clip in &closure {
            let mut copy = clip.clone();
            next.remint(&mut copy);
            fresh.insert(clip.id, copy.id);
            copy.start = clip.start.saturating_add(delta).max(0);
            if selection.iter().any(|c| c.id == clip.id) {
                match self.landing_track(clip, index_delta)? {
                    Ok(landed) => copy.track = landed,
                    Err(why) => return Ok(Outcome::Refused(why)),
                }
            }
            copies.push(copy);
        }
        relink_copies(&mut copies, &fresh);
        self.commit_additions(next, copies)
    }

    // ---- reversal ---------------------------------------------------------

    /// Plays a media clip back to front, or forward again (spec §6).
    ///
    /// The core does no pixel work, so this only records a FACT about the
    /// clip: neither the plan nor the recipe changes, and Swift resolves it
    /// by substituting a pre-rendered reversed asset for this media's
    /// segments (spec §11).
    ///
    /// The in point is left exactly where it is, and that is the whole
    /// subtlety: `in` is measured in the stream the clip PLAYS
    /// (`model::Source::Media`), so reversing keeps the in point and
    /// therefore shows different frames — the tail of the file instead of
    /// its head. Advancing it to keep the same frames would be a second
    /// convention, and every trim, split and `source_window.rs`'s
    /// `source_length_on_timeline` would need to know which one was in
    /// force.
    ///
    /// A non-media source is an `Err` and not a refusal — the non-media
    /// rule (`edit.rs`, Results). An identity when the clip already plays
    /// that way. Refused on a linked clip (spec §11 AU-94).
    pub fn set_reversed(&self, clip: u32, reversed: bool) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?;
        let Source::Media {
            media,
            r#in,
            reversed: current,
        } = target.source
        else {
            return Err(format!("clip {clip} is not a media clip"));
        };
        if current == reversed {
            return Ok(Outcome::Identity);
        }

        let mut after = target.clone();
        after.source = Source::Media {
            media,
            r#in,
            reversed,
        };
        if let Some(why) = self.linked_rate_refusal(target, &after) {
            return Ok(Outcome::Refused(why));
        }
        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            *slot = after;
        }
        self.finish(next)
    }
}
