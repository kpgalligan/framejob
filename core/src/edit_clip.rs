//! The clip and action ops — spec §6, tables "Clips" and "Actions".
//!
//! One `impl Project` block holding every edit that adds, places, trims,
//! splits, copies or re-describes a clip. The five property patches are the
//! OTHER half of the clip surface, `edit_props.rs`'s, policed by the range
//! checks of `props_check.rs`: this file decides where a clip sits, that one
//! what it looks like. The action ops, which were here, are `edit_action.rs`;
//! the transition ops, which were here too, are `edit_transition.rs`; and
//! `split_clip` with its two helpers, which every splitter in the crate
//! routes through, is `edit_split.rs` — a split is not a placement but a
//! question about what the SECOND clip inherits, and road map 5's E2 added
//! a rule to it.
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
//! `require_*` lookups, `finish`, `selected_clips` and `clip_end` — are
//! `pub(crate)` so `edit_track.rs` and `edit_time.rs` obey the same rules by
//! calling them rather than by restating them. `set_gained_transitions` is
//! the sixth and now lives in `edit_transition.rs`, re-exported from here so
//! every caller's path is unchanged.
//!
//! The two ops here that DO take a patch — `add_text_clip` and
//! `add_shape_clip` — build their preset and then hand it to `edit_props`'s
//! merge and `props_check`'s checks, so a `text` argument is validated
//! exactly as a later `set_text` would be.

use serde_json::Value;

use crate::edit_split::split_clip;
use crate::model::{
    Action, AudioProps, Clip, Enabled, Media, MediaKind, Project, ShapeKind, ShapeProps, Source,
    TextProps, Track, VideoProps,
};
use crate::outcome::Outcome;
use crate::patch::{merge_group, Group};
use crate::props_check::{check_shape, check_text, SCALE_MAX, SCALE_MIN};
use crate::time::{self, Ticks, TIMESCALE};

/// Re-exported from its new home so the nine call sites here and the three
/// in `edit_time.rs`, `edit_nest.rs` and `edit_paste.rs` keep naming it at
/// the path they always did.
pub(crate) use crate::edit_transition::set_gained_transitions;

/// Default duration for a source with no source bound — text, shape, and an
/// image whose descriptor carries no duration. Five seconds is a screencast editor's
/// title default and long enough to read.
const DEFAULT_CLIP_DURATION: Ticks = 5 * TIMESCALE;

/// Speed range, matching the inspector's ×0.1 – ×10 (spec §4.3). Outside
/// it, `scaleTimeRange` and the time-pitch unit stop producing anything
/// anyone wants to watch.
const SPEED_MIN: f64 = 0.1;
const SPEED_MAX: f64 = 10.0;

/// The font of the Title text preset (spec §4.3). A concrete face, not a
/// family: the renderer asks for exactly this name, and a bold weight is
/// what a title over footage needs to stay legible.
const TITLE_FONT: &str = "SourceSans3-Bold";

/// Placeholder content for a new text clip. A text clip that renders
/// nothing is indistinguishable from a broken one, so a new one says what
/// it is and arrives selected for the user to overtype.
const TITLE_CONTENT: &str = "Title";

// ---- clip helpers --------------------------------------------------------

/// What a sourceless clip — text or shape — is made of, so the shared
/// placement tail takes one argument instead of four.
struct Described {
    source: Source,
    scale: f64,
    text: Option<TextProps>,
    shape: Option<ShapeProps>,
}

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

    /// One frame of canvas time — the shortest a clip or an action may be.
    /// A degenerate canvas rate falls back to 1/30 s so the minimum is
    /// never zero.
    pub(crate) fn frame(&self) -> Ticks {
        time::frame_duration(self.canvas.fps)
            .unwrap_or(TIMESCALE / 30)
            .max(1)
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

    /// How long a clip showing the WHOLE of `media` is — what `add_clip`
    /// gives one, and therefore how much room `insert_clip` opens and how
    /// much span `overwrite_clip` clears.
    ///
    /// A still image has no source bound, so it gets the default length
    /// unless its descriptor carried one; a timed media with no duration is
    /// an `Err`, because a zero-length clip is not a thing the timeline can
    /// hold.
    ///
    /// **The default is snapped like every other length.** It is a constant
    /// number of ticks, and a constant is not on the frame grid of a rate
    /// that does not divide the timescale — at 30000/1001 five seconds is
    /// 3 003 000 ticks, not 3 000 000. Handing back the raw constant made
    /// `insert_clip` open a hole a sliver wider than the clip it placed and
    /// `overwrite_clip` clear a span that missed the fragment `split_clips`
    /// had just made, which refused the whole op. One length, on the grid,
    /// for all three callers.
    pub(crate) fn whole_media_length(&self, media: &Media) -> Result<Ticks, String> {
        match media.kind {
            MediaKind::Image if media.duration <= 0 => {
                Ok(self.snapped(DEFAULT_CLIP_DURATION).max(self.frame()))
            }
            MediaKind::Image => Ok(self.snapped(media.duration)),
            MediaKind::Video | MediaKind::Audio => {
                let duration = self.snapped(media.duration);
                if duration <= 0 {
                    return Err(format!(
                        "media {} has no duration ({} ticks)",
                        media.id, media.duration
                    ));
                }
                Ok(duration)
            }
        }
    }

    /// Fit scale for a new clip: `min(cw/sw, ch/sh)` when `fit_new_clips`
    /// is on and the source exceeds the canvas, else 1 (spec §5.3). A
    /// source that already fits is never scaled UP — Fit is a rescue for
    /// oversized footage, not a stretch.
    pub(crate) fn fit_scale(&self, source_width: f64, source_height: f64) -> f64 {
        if !(self.canvas.fit_new_clips && source_width > 0.0 && source_height > 0.0) {
            return 1.0;
        }
        let canvas_width = f64::from(self.canvas.width);
        let canvas_height = f64::from(self.canvas.height);
        if source_width <= canvas_width && source_height <= canvas_height {
            return 1.0;
        }
        let scale = (canvas_width / source_width).min(canvas_height / source_height);
        if scale.is_finite() {
            scale.clamp(SCALE_MIN, SCALE_MAX)
        } else {
            1.0
        }
    }

    /// Fill scale: `max(cw/sw, ch/sh)`, the smallest scale that leaves no
    /// canvas showing — [`Project::fit_scale`]'s sibling, and what
    /// `edit_background.rs` gives a backdrop.
    ///
    /// Three differences from Fit, all of them one difference read three
    /// ways: Fit is a RESCUE for oversized footage and Fill is a
    /// REQUIREMENT. So it ignores `canvas.fit_new_clips` — a backdrop that
    /// leaves a bar down the side has failed at its one job whatever that
    /// flag says; it scales UP as readily as down, a source smaller than the
    /// canvas being exactly the case that needs it; and it clamps HERE, so
    /// no caller can store a scale `check_video` would refuse. The clamp's
    /// visible cost is `edit_zoom.rs`'s, for the same constant: on a
    /// 1920-wide canvas a source under 192 pixels cannot reach the edge, and
    /// what comes back is the biggest legal magnification rather than a
    /// refusal. A degenerate source has no ratio to take and answers 1;
    /// callers refuse one by name before they ever reach this.
    pub(crate) fn fill_scale(&self, source_width: f64, source_height: f64) -> f64 {
        let scale = (f64::from(self.canvas.width) / source_width)
            .max(f64::from(self.canvas.height) / source_height);
        if scale.is_finite() && scale > 0.0 {
            scale.clamp(SCALE_MIN, SCALE_MAX)
        } else {
            1.0
        }
    }

    /// Scales every action's span with the clip, so an action keeps the
    /// same clip-relative FRACTION when the clip's length changes (spec §6,
    /// `set_speed`).
    ///
    /// Rounding can leave two adjacent actions touching by a tick; that is
    /// harmless, because evaluation orders actions by `(start, id)` and is
    /// defined for overlaps — only `add_action` refuses to create one.
    fn rescale_actions(&self, actions: &mut [Action], old: Ticks, new: Ticks) {
        if old <= 0 || new <= 0 || old == new {
            return;
        }
        let frame = self.frame();
        let factor = new as f64 / old as f64;
        for action in actions.iter_mut() {
            let scaled_start = (action.start as f64 * factor).round();
            let scaled_duration = (action.duration as f64 * factor).round();
            let start = if scaled_start.is_finite() {
                self.snapped(scaled_start as Ticks)
            } else {
                action.start
            };
            let duration = if scaled_duration.is_finite() {
                self.snapped(scaled_duration as Ticks)
            } else {
                action.duration
            };
            // Clamped so the action still fits the clip and still has a
            // positive duration, which `validate` requires.
            action.start = start.clamp(0, new.saturating_sub(frame).max(0));
            action.duration = duration
                .max(frame)
                .min(new.saturating_sub(action.start))
                .max(1);
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
        };

        let has_pixels = found.has_video || matches!(found.kind, MediaKind::Image);
        let video = has_pixels.then(|| VideoProps {
            scale: self.fit_scale(f64::from(found.width), f64::from(found.height)),
            ..VideoProps::default()
        });
        let audio = found.has_audio.then(AudioProps::default);

        let mut next = self.clone();
        let clip = Clip {
            id: next.allocate_id(),
            track,
            start: at,
            duration,
            source,
            enabled: Enabled::default(),
            speed: 1.0,
            video,
            audio,
            text: None,
            shape: None,
            actions: Vec::new(),
            transition_in: None,
            name: None,
            label: None,
        };
        if let Err(why) = self.check_overlap_rule(std::slice::from_ref(&clip), track, &[]) {
            return Ok(Outcome::Refused(why));
        }
        next.clips.push(clip);
        set_gained_transitions(&mut next, &[track]);
        self.finish(next)
    }

    /// A text clip at `at` on `track`: the Title preset, centered, five
    /// seconds by default, with `text` merged over it as a `set_text`
    /// patch (spec §6, §4.3).
    ///
    /// Refuses on an overlap-rule violation, in the rule's own sentence;
    /// `Err` for an unknown track, a non-positive duration, or a bad patch.
    pub fn add_text_clip(
        &self,
        track: u32,
        at: Ticks,
        duration: Option<Ticks>,
        text: Option<&Value>,
    ) -> Result<Outcome, String> {
        let title = TextProps {
            content: TITLE_CONTENT.to_string(),
            font: TITLE_FONT.to_string(),
            size: 72.0,
            color: [1.0, 1.0, 1.0, 1.0],
            ..TextProps::default()
        };
        let props = match text {
            None => title,
            Some(patch) => {
                let mut props = merge_group(&title, patch, Group::Text)?;
                check_text(&props)?;
                // The same door `set_text` is, ticks included
                // (`edit_props.rs`'s `snap_animation`, and the Times rule
                // it keeps).
                self.snap_animation(&mut props);
                props
            }
        };
        self.add_described_clip(
            track,
            at,
            duration,
            Described {
                source: Source::Text,
                // Text has no source size — only the platform can measure a
                // layout — so a new text clip is always at native scale.
                scale: 1.0,
                text: Some(props),
                shape: None,
            },
        )
    }

    /// A shape clip at `at` on `track`: the default stroked box, five
    /// seconds by default, with `shape` merged over it as a `set_shape`
    /// patch (spec §6). An arrow is created with its head on.
    pub fn add_shape_clip(
        &self,
        track: u32,
        at: Ticks,
        duration: Option<Ticks>,
        shape: Option<&Value>,
    ) -> Result<Outcome, String> {
        let props = match shape {
            None => ShapeProps::default(),
            Some(patch) => {
                // An arrow with `arrow_end: false` draws as a plain diagonal
                // line, which is not what asking for an arrow means and not
                // what spec §5.2's own arrow example shows. The head is
                // switched on HERE, in the creation preset, rather than in
                // `ShapeProps::default()`: that default is also the base a
                // stored shape is deserialized against and the value a
                // later `set_shape { "kind": "arrow" }` merges into, and a
                // patch that re-paints a field the caller did not name
                // would break the merge contract. Merging the patch over
                // this preset (not under it) keeps an explicit
                // `"arrow_end": false` winning.
                let kind = patch
                    .get("kind")
                    .and_then(|value| serde_json::from_value(value.clone()).ok());
                let base = ShapeProps {
                    arrow_end: matches!(kind, Some(ShapeKind::Arrow)),
                    ..ShapeProps::default()
                };
                let props = merge_group(&base, patch, Group::Shape)?;
                check_shape(&props)?;
                props
            }
        };
        // A shape's box IS its source size, so an oversized one fits like
        // oversized footage does.
        let scale = self.fit_scale(props.width, props.height);
        self.add_described_clip(
            track,
            at,
            duration,
            Described {
                source: Source::Shape,
                scale,
                text: None,
                shape: Some(props),
            },
        )
    }

    /// The shared tail of `add_text_clip` and `add_shape_clip`: a clip with
    /// no source bound, placed under the same rules as any other.
    fn add_described_clip(
        &self,
        track: u32,
        at: Ticks,
        duration: Option<Ticks>,
        described: Described,
    ) -> Result<Outcome, String> {
        self.require_track(track)?;
        let at = self.snapped(at).max(0);
        let duration = match duration {
            None => DEFAULT_CLIP_DURATION,
            Some(given) => {
                let snapped = self.snapped(given);
                if snapped < self.frame() {
                    return Err(format!(
                        "clip duration must be at least one frame ({} ticks), not {given}",
                        self.frame()
                    ));
                }
                snapped
            }
        };

        let mut next = self.clone();
        let clip = Clip {
            id: next.allocate_id(),
            track,
            start: at,
            duration,
            source: described.source,
            enabled: Enabled::default(),
            speed: 1.0,
            video: Some(VideoProps {
                scale: described.scale,
                ..VideoProps::default()
            }),
            audio: None,
            text: described.text,
            shape: described.shape,
            actions: Vec::new(),
            transition_in: None,
            name: None,
            label: None,
        };
        if let Err(why) = self.check_overlap_rule(std::slice::from_ref(&clip), track, &[]) {
            return Ok(Outcome::Refused(why));
        }
        next.clips.push(clip);
        set_gained_transitions(&mut next, &[track]);
        self.finish(next)
    }

    // ---- moving and trimming ---------------------------------------------

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

        // Snapping the delta keeps a dragged clip on the grid: every start
        // is already on it, so a snapped delta lands on it too.
        let mut delta = self.snapped(delta);
        let earliest = selection.iter().map(|c| c.start).min().unwrap_or(0);
        if delta < -earliest {
            delta = -earliest;
        }

        let index_delta = match track {
            None => 0i64,
            Some(destination) => {
                let destination_index = self.require_track_index(destination)? as i64;
                // The anchor is the FIRST clip of the selection in the
                // order the timeline draws — back-most track, then earliest
                // — and the whole selection moves by its offset, which is
                // what keeps a two-track selection two tracks apart.
                let mut keyed: Vec<(usize, Ticks, u32)> = Vec::new();
                for clip in &selection {
                    keyed.push((self.require_track_index(clip.track)?, clip.start, clip.id));
                }
                let anchor = keyed.iter().min().map(|k| k.0).unwrap_or(0) as i64;
                destination_index - anchor
            }
        };

        let mut candidates: Vec<Clip> = Vec::new();
        for clip in &selection {
            let mut moved = (*clip).clone();
            moved.start = moved.start.saturating_add(delta).max(0);
            if index_delta != 0 {
                let from = self.require_track_index(clip.track)? as i64;
                let to = from.saturating_add(index_delta);
                // A selection dragged off either end of the track list is a
                // refusal, not a clamp: clamping would silently stack two
                // clips on one track.
                let Some(destination) = usize::try_from(to)
                    .ok()
                    .and_then(|index| self.tracks.get(index))
                else {
                    return Ok(Outcome::Identity);
                };
                moved.track = destination.id;
            }
            candidates.push(moved);
        }

        let mut affected: Vec<u32> = Vec::new();
        for clip in selection
            .iter()
            .map(|c| c.track)
            .chain(candidates.iter().map(|c| c.track))
        {
            if !affected.contains(&clip) {
                affected.push(clip);
            }
        }
        for track in &affected {
            if let Err(why) = self.check_overlap_rule(&candidates, *track, &[]) {
                return Ok(Outcome::Refused(why));
            }
        }

        let mut next = self.clone();
        for moved in &candidates {
            if let Some(clip) = next.clip_mut(moved.id) {
                clip.start = moved.start;
                clip.track = moved.track;
            }
        }
        set_gained_transitions(&mut next, &affected);
        self.finish(next)
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

    /// Moves the clip's start edge to `to`, advancing the source in point
    /// by `(to - start) × speed` so the frame under the edge does not move
    /// (spec §6).
    ///
    /// Clamped to the source bound (`to ≥ start - in/speed`) and to leaving
    /// at least one frame of clip. Actions are deliberately left alone:
    /// they are clip-relative, and rebasing them would have to drop or bake
    /// whatever fell off the front, which is lossy and makes trimming back
    /// out not an identity.
    pub fn trim_start(&self, clip: u32, to: Ticks) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let end = clip_end(&target);
        let latest = end.saturating_sub(self.frame());
        let mut to = self.snapped(to).min(latest).max(0);

        if let Some(head) = self.source_head(&target) {
            to = to.max(target.start.saturating_sub(head).max(0));
        }
        // The two clamps can cross when the source has almost nothing left
        // in front: then there is no legal new start, so nothing happens.
        if to > latest || to == target.start {
            return Ok(Outcome::Identity);
        }

        let delta = to.saturating_sub(target.start);
        let mut moved = target.clone();
        if let Source::Media {
            media,
            r#in,
            reversed,
        } = target.source
        {
            let advance = (delta as f64 * target.speed).round();
            let advance = if advance.is_finite() {
                advance as Ticks
            } else {
                0
            };
            moved.source = Source::Media {
                media,
                r#in: r#in.saturating_add(advance).max(0),
                reversed,
            };
        }
        moved.start = to;
        moved.duration = end.saturating_sub(to);
        if let Err(why) = self.check_overlap_rule(&[moved.clone()], moved.track, &[]) {
            return Ok(Outcome::Refused(why));
        }

        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            *slot = moved;
        }
        set_gained_transitions(&mut next, &[target.track]);
        self.finish(next)
    }

    /// Moves the clip's end edge to `to`, clamped to the source's remaining
    /// length (media sources) and to at least one frame of clip (spec §6).
    /// The source in point and the actions are untouched.
    pub fn trim_end(&self, clip: u32, to: Ticks) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let earliest = target.start.saturating_add(self.frame());
        let mut to = self.snapped(to).max(earliest);
        if let Some(available) = self.source_length(&target) {
            to = to.min(target.start.saturating_add(available));
        }
        if to < earliest || to == clip_end(&target) {
            return Ok(Outcome::Identity);
        }

        let mut moved = target.clone();
        moved.duration = to.saturating_sub(target.start);
        if let Err(why) = self.check_overlap_rule(&[moved.clone()], moved.track, &[]) {
            return Ok(Outcome::Refused(why));
        }

        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            *slot = moved;
        }
        set_gained_transitions(&mut next, &[target.track]);
        self.finish(next)
    }

    /// Drags the clip's end edge to `to_end` by changing its SPEED, not the
    /// source range it shows: `speed = source_len / (to_end - start)`
    /// (spec §6). Media sources only.
    ///
    /// Refuses when the resulting rate falls outside ×0.1 – ×10, when the
    /// new length is under a frame, or when the placement breaks the
    /// overlap rule. Actions keep their clip-relative fraction.
    pub fn rate_stretch(&self, clip: u32, to_end: Ticks) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        if !matches!(target.source, Source::Media { .. }) {
            return Err(format!("clip {clip} is not a media clip"));
        }
        let to_end = self.snapped(to_end);
        let duration = to_end.saturating_sub(target.start);
        if duration < self.frame() {
            return Ok(Outcome::Identity);
        }
        let rate = self.content_length(&target) as f64 / duration as f64;
        if !rate.is_finite() || !(SPEED_MIN..=SPEED_MAX).contains(&rate) {
            return Ok(Outcome::Identity);
        }

        let mut moved = target.clone();
        moved.speed = rate;
        moved.duration = duration;
        self.rescale_actions(&mut moved.actions, target.duration, duration);
        if let Err(why) = self.check_overlap_rule(&[moved.clone()], moved.track, &[]) {
            return Ok(Outcome::Refused(why));
        }

        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            *slot = moved;
        }
        set_gained_transitions(&mut next, &[target.track]);
        self.finish(next)
    }

    // ---- splitting, deleting, duplicating --------------------------------

    /// Cuts each named clip at project time `at` (spec §6). A clip `at` is
    /// not strictly inside is skipped; when nothing can be cut the whole op
    /// is an identity. `Err` only for an unknown clip id.
    pub fn split_clips(&self, clips: &[u32], at: Ticks) -> Result<Outcome, String> {
        let at = self.snapped(at);
        let ids: Vec<u32> = self.selected_clips(clips)?.iter().map(|c| c.id).collect();
        let mut next = self.clone();
        let mut cut = false;
        for id in ids {
            cut |= split_clip(&mut next, id, at);
        }
        if !cut {
            return Ok(Outcome::Identity);
        }
        self.finish(next)
    }

    /// Cuts every clip on an UNLOCKED track that `at` falls strictly inside
    /// — ⌘K with no selection (spec §6, §9).
    pub fn split_under_playhead(&self, at: Ticks) -> Result<Outcome, String> {
        let at = self.snapped(at);
        let ids: Vec<u32> = self
            .clips
            .iter()
            .filter(|c| self.track(c.track).is_some_and(|t| !t.locked))
            .filter(|c| c.start < at && at < clip_end(c))
            .map(|c| c.id)
            .collect();
        if ids.is_empty() {
            return Ok(Outcome::Identity);
        }
        let mut next = self.clone();
        let mut cut = false;
        for id in ids {
            cut |= split_clip(&mut next, id, at);
        }
        if !cut {
            return Ok(Outcome::Identity);
        }
        self.finish(next)
    }

    /// Removes the named clips. Gaps stay — rippling is `edit_time`'s job
    /// (spec §6).
    pub fn delete_clips(&self, clips: &[u32]) -> Result<Outcome, String> {
        let ids: Vec<u32> = self.selected_clips(clips)?.iter().map(|c| c.id).collect();
        if ids.is_empty() {
            return Ok(Outcome::Identity);
        }
        let mut next = self.clone();
        next.clips.retain(|c| !ids.contains(&c.id));
        self.finish(next)
    }

    /// Copies the named clips immediately after their own span, on their
    /// own tracks (spec §6): the copies start one span-length later, so a
    /// multi-clip selection keeps its internal timing exactly.
    ///
    /// Clips and their actions get fresh ids. Refuses when the copies would
    /// break the overlap rule.
    pub fn duplicate_clips(&self, clips: &[u32]) -> Result<Outcome, String> {
        let selection: Vec<Clip> = self
            .selected_clips(clips)?
            .into_iter()
            .cloned()
            .collect::<Vec<Clip>>();
        if selection.is_empty() {
            return Ok(Outcome::Identity);
        }
        let span_start = selection.iter().map(|c| c.start).min().unwrap_or(0);
        let span_end = selection.iter().map(clip_end).max().unwrap_or(0);
        let delta = span_end.saturating_sub(span_start);
        if delta <= 0 {
            return Ok(Outcome::Identity);
        }

        let mut next = self.clone();
        let mut copies: Vec<Clip> = Vec::new();
        let mut affected: Vec<u32> = Vec::new();
        for clip in &selection {
            let mut copy = clip.clone();
            copy.id = next.allocate_id();
            copy.start = clip.start.saturating_add(delta);
            for action in copy.actions.iter_mut() {
                action.id = next.allocate_id();
            }
            if !affected.contains(&copy.track) {
                affected.push(copy.track);
            }
            copies.push(copy);
        }
        for track in &affected {
            if let Err(why) = self.check_overlap_rule(&copies, *track, &[]) {
                return Ok(Outcome::Refused(why));
            }
        }
        next.clips.extend(copies);
        set_gained_transitions(&mut next, &affected);
        self.finish(next)
    }

    // ---- speed and audio detach ------------------------------------------

    /// Sets the clip's playback rate: `duration = source_len / rate`, with
    /// the actions keeping their clip-relative fraction (spec §6). Media
    /// sources only; `keep_pitch`, when given, sets the time-pitch flag.
    ///
    /// The rate is clamped to the inspector's ×0.1 – ×10 rather than
    /// refused, because a slider or an MCP call that asks for ×20 wants the
    /// fastest thing available. `Err` for a non-media clip or a rate that
    /// is not a positive finite number; refuses on an overlap-rule
    /// violation.
    pub fn set_speed(
        &self,
        clip: u32,
        rate: f64,
        keep_pitch: Option<bool>,
    ) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        if !matches!(target.source, Source::Media { .. }) {
            return Err(format!("clip {clip} is not a media clip"));
        }
        if !(rate.is_finite() && rate > 0.0) {
            return Err(format!("speed must be a positive number, not {rate}"));
        }
        let rate = rate.clamp(SPEED_MIN, SPEED_MAX);

        let scaled = self.content_length(&target) as f64 / rate;
        let duration = if scaled.is_finite() {
            self.snapped(scaled.round() as Ticks).max(self.frame())
        } else {
            target.duration
        };

        let mut moved = target.clone();
        moved.speed = rate;
        moved.duration = duration;
        self.rescale_actions(&mut moved.actions, target.duration, duration);
        if let (Some(keep), Some(audio)) = (keep_pitch, moved.audio.as_mut()) {
            audio.keep_pitch = keep;
        }
        if let Err(why) = self.check_overlap_rule(&[moved.clone()], moved.track, &[]) {
            return Ok(Outcome::Refused(why));
        }

        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            *slot = moved;
        }
        set_gained_transitions(&mut next, &[target.track]);
        self.finish(next)
    }

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
    /// convention, and every trim, split and `source_length` in the crate
    /// would need to know which one was in force.
    ///
    /// A non-media source is an `Err` and not a refusal — the non-media
    /// rule (`edit.rs`, Results). An identity when the clip already plays
    /// that way.
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

        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            slot.source = Source::Media {
                media,
                r#in,
                reversed,
            };
        }
        self.finish(next)
    }

    /// Splits the clip's audio onto its own clip on the track BELOW,
    /// inserting a track at index 0 when the clip is already on the bottom
    /// one (spec §6).
    ///
    /// The original keeps its video and gets `enabled.audio = false`; the
    /// new clip is `{video: false, audio: true}` with the same source, in
    /// point, duration and speed. Its VIDEO props are carried over too, so
    /// re-enabling video on it is not lossy.
    ///
    /// Refuses when the media has no audio, when the audio is already
    /// detached, or when the new clip would break the overlap rule on the
    /// track below.
    pub fn detach_audio(&self, clip: u32) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?.clone();
        let Source::Media { media, .. } = target.source else {
            // Stills, images, text and shapes have no audio to detach.
            return Ok(Outcome::Identity);
        };
        let Some(found) = self.media(media) else {
            return Ok(Outcome::Identity);
        };
        if !found.has_audio || !target.enabled.audio {
            return Ok(Outcome::Identity);
        }
        let index = self.require_track_index(target.track)?;

        let mut next = self.clone();
        let below = match index.checked_sub(1).and_then(|i| self.tracks.get(i)) {
            Some(track) => track.id,
            None => {
                // The clip is on the bottom track, so the audio needs a new
                // one under it. Naming by the count keeps it unique without
                // renumbering the tracks above.
                let id = next.allocate_id();
                let name = format!("Track {}", next.tracks.len().saturating_add(1));
                next.tracks.insert(
                    0,
                    Track {
                        id,
                        name,
                        hidden: false,
                        muted: false,
                        locked: false,
                        solo: false,
                    },
                );
                id
            }
        };

        let mut audio_clip = target.clone();
        audio_clip.id = next.allocate_id();
        audio_clip.track = below;
        audio_clip.enabled = Enabled {
            video: false,
            audio: true,
        };
        audio_clip.audio = target.audio.or_else(|| Some(AudioProps::default()));
        // Actions move with the clip and need their own ids; a video action
        // on a non-drawing clip is inert, and dropping it would lose the
        // volume actions that belong here.
        for action in audio_clip.actions.iter_mut() {
            action.id = next.allocate_id();
        }
        // The transition describes an overlap on the ORIGINAL track.
        audio_clip.transition_in = None;

        if let Err(why) = self.check_overlap_rule(&[audio_clip.clone()], below, &[]) {
            return Ok(Outcome::Refused(why));
        }
        if let Some(slot) = next.clip_mut(clip) {
            slot.enabled.audio = false;
        }
        next.clips.push(audio_clip);
        set_gained_transitions(&mut next, &[below]);
        self.finish(next)
    }

    // ---- enablement ------------------------------------------------------

    /// Per-clip visibility and mute (spec §6). An argument left `None` is
    /// left alone, so the two halves of Detach Audio can be set
    /// independently.
    pub fn set_enabled(
        &self,
        clip: u32,
        video: Option<bool>,
        audio: Option<bool>,
    ) -> Result<Outcome, String> {
        self.require_clip(clip)?;
        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            if let Some(value) = video {
                slot.enabled.video = value;
            }
            if let Some(value) = audio {
                slot.enabled.audio = value;
            }
        }
        self.finish(next)
    }
}
