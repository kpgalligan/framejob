//! The clip and action ops — spec §6, tables "Clips" and "Actions".
//!
//! One `impl Project` block holding every edit that adds, places, trims,
//! splits, copies or re-describes a clip, plus the action ops. The four
//! property patches are the OTHER half of the clip surface and live in
//! `edit_props.rs`, with the range checks that police them: this file
//! decides where a clip sits, that one decides what it looks like.
//! `edit.rs` dispatches to both by name; nothing here knows about JSON op
//! envelopes, and nothing here mutates `self` — an edit clones, changes
//! the clone, and hands it back (spec §5.5).
//!
//! Three rules run through all of it:
//!
//! 1. **Every tick argument is snapped to the canvas frame grid first**
//!    ([`Project::snapped`]), durations included. Nothing sub-frame ever
//!    reaches the model.
//! 2. **Placement is checked, never repaired.** A move, trim or duplicate
//!    that would break the overlap rule returns `Ok(None)` — the UI
//!    animates it back. The rule itself lives in `transition.rs` and is
//!    called, never restated.
//! 3. **Every op leaves the project valid.** [`Project::finish`] is the
//!    single exit: it returns `None` when the result equals the input (no
//!    phantom undo step) and turns a broken invariant into `Err`.
//!
//! The pieces those three rules are made of — `snapped`, `frame`, the
//! `require_*` lookups, `finish`, `selected_clips`, `clip_end` and
//! `set_gained_transitions` — are `pub(crate)` so `edit_track.rs` and
//! `edit_time.rs` obey the same rules by calling them rather than by
//! restating them.
//!
//! The two ops here that DO take a patch — `add_text_clip` and
//! `add_shape_clip` — build their preset and then hand it to
//! `edit_props`'s merge and checks, so a `text` argument is validated
//! exactly as a later `set_text` would be.

use serde_json::Value;

use crate::actions::{self, Evaluated, MAX_PATCH_DEPTH};
use crate::edit_props::{check_shape, check_text, merge_group, Group, SCALE_MAX, SCALE_MIN};
use crate::export::describe;
use crate::model::{
    Action, AudioProps, Clip, Curve, Enabled, Media, MediaKind, Project, ShapeProps, Source,
    TextProps, Track, Transition, TransitionKind, VideoProps,
};
use crate::time::{self, Ticks, TIMESCALE};

/// Default duration for a source with no source bound — text, shape, and an
/// image whose descriptor carries no duration. Five seconds is a screencast editor's
/// title default and long enough to read.
const DEFAULT_CLIP_DURATION: Ticks = 5 * TIMESCALE;

/// Default duration for `add_action`: one second of animation, the length
/// the Actions table offers before the user drags either edge.
const DEFAULT_ACTION_DURATION: Ticks = TIMESCALE;

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

/// The source material one clip shows, in source ticks: its timeline length
/// times its speed. The same quantity `evaluate::segment_of` inserts into
/// the composition, so a speed edit here and the segment there agree.
fn content_length(clip: &Clip) -> Ticks {
    let scaled = clip.duration as f64 * clip.speed;
    // The cast saturates rather than wrapping, so an absurd speed cannot
    // produce a negative length; a degenerate one falls back to 1:1.
    if scaled.is_finite() && scaled >= 1.0 {
        scaled.round() as Ticks
    } else {
        clip.duration.max(1)
    }
}

pub(crate) fn clip_end(clip: &Clip) -> Ticks {
    clip.start.saturating_add(clip.duration)
}

/// Whether `[start, start+duration)` touches any action on the clip other
/// than `skip` (the action being edited). Actions on a clip may not overlap
/// (spec §5.4); this is the test both `add_action` and `set_action` refuse
/// on.
fn actions_overlap(actions: &[Action], skip: Option<u32>, start: Ticks, duration: Ticks) -> bool {
    let end = start.saturating_add(duration);
    actions
        .iter()
        .filter(|a| Some(a.id) != skip)
        .any(|a| start < a.start.saturating_add(a.duration) && a.start < end)
}

/// Gives every clip that now overlaps its predecessor and has no
/// `transition_in` a cross dissolve. An overlap IS a transition (spec
/// §5.2), so a clip that gains one and would otherwise render as two
/// stacked layers gets the default rather than nothing.
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
            clip.transition_in = Some(Transition::default());
        }
    }
}

/// The evaluated state as an action-style patch object, so `split` can hand
/// the first half of a straddled action the state it must reach.
fn state_patch(evaluated: &Evaluated) -> Value {
    let mut out = serde_json::Map::new();
    out.insert("video".to_string(), actions::to_json(&evaluated.video));
    out.insert("audio".to_string(), actions::to_json(&evaluated.audio));
    if let Some(text) = &evaluated.text {
        out.insert("text".to_string(), actions::to_json(text));
    }
    Value::Object(out)
}

/// `state` narrowed to the keys `shape` mentions — the minimal patch with
/// the same reach as the original. Keeping the shape means a split action's
/// first half animates exactly the fields the whole action animated, rather
/// than pinning every property of the clip.
fn narrow_to(state: &Value, shape: &Value, depth: u32) -> Value {
    let (Value::Object(from), Value::Object(keys)) = (state, shape) else {
        return shape.clone();
    };
    if depth >= MAX_PATCH_DEPTH {
        return shape.clone();
    }
    let mut out = serde_json::Map::new();
    for (key, sub) in keys {
        match from.get(key) {
            Some(value) if value.is_object() && sub.is_object() => {
                out.insert(key.clone(), narrow_to(value, sub, depth + 1));
            }
            Some(value) => {
                out.insert(key.clone(), value.clone());
            }
            // A key the state does not have (an unknown patch key): carry
            // the original through untouched, exactly as evaluation would.
            None => {
                out.insert(key.clone(), sub.clone());
            }
        }
    }
    Value::Object(out)
}

/// Removes from `value` every key the incoming `patch` set to `null` —
/// `set_action_end`'s delete rule (spec §6). Only keys the patch mentions
/// are touched, so a `null` that was already in the end patch (animating a
/// shadow away, say) survives untouched.
fn prune_removed(value: &mut Value, patch: &Value, depth: u32) {
    let Value::Object(patched) = patch else {
        return;
    };
    let Value::Object(target) = value else {
        return;
    };
    if depth >= MAX_PATCH_DEPTH {
        return;
    }
    for (key, sub) in patched {
        if sub.is_null() {
            target.remove(key);
        } else if let Some(slot) = target.get_mut(key) {
            prune_removed(slot, sub, depth + 1);
        }
    }
}

/// Cuts `clip_id` in two at project time `at`, in place. Returns false —
/// and changes nothing — when `at` is not strictly inside the clip, which
/// is the spec's refusal.
///
/// The second clip's BASE props are the evaluated state at the cut, so the
/// join is invisible; its actions are the ones that had not finished,
/// rebased to its own clip time.
fn split_clip(project: &mut Project, clip_id: u32, at: Ticks) -> bool {
    let Some(original) = project.clip(clip_id).cloned() else {
        return false;
    };
    let clip_t = at.saturating_sub(original.start);
    if clip_t <= 0 || clip_t >= original.duration {
        return false;
    }
    let state = project.evaluate_clip(&original, clip_t);
    let patch_source = state_patch(&state);

    let mut second = original.clone();
    second.id = project.allocate_id();
    second.start = at;
    second.duration = clip_end(&original).saturating_sub(at);
    // The cut consumes `clip_t` of timeline, which is `clip_t * speed` of
    // source; a still's frozen frame and the sourceless kinds do not move.
    if let Source::Media { media, r#in } = original.source {
        let advance = (clip_t as f64 * original.speed).round();
        let advance = if advance.is_finite() {
            advance as Ticks
        } else {
            0
        };
        second.source = Source::Media {
            media,
            r#in: r#in.saturating_add(advance).max(0),
        };
    }
    // Presence of a group is a fact about the clip, so an audio-only clip
    // stays audio-only; only the values come from the evaluation.
    second.video = original.video.as_ref().map(|_| state.video.clone());
    second.audio = original.audio.map(|_| state.audio);
    second.text = state.text.clone();
    second.shape = original.shape.clone();
    // The transition covers the join with the PREVIOUS clip, which is still
    // the first half's business (spec §6).
    second.transition_in = None;

    let mut first_actions: Vec<Action> = Vec::new();
    let mut second_actions: Vec<Action> = Vec::new();
    for action in &original.actions {
        let end = action.start.saturating_add(action.duration);
        if end <= clip_t {
            first_actions.push(action.clone());
        } else if action.start >= clip_t {
            let mut moved = action.clone();
            moved.start = action.start.saturating_sub(clip_t);
            second_actions.push(moved);
        } else {
            // Straddles the cut. The first half ends at the state the
            // evaluation reached there, narrowed to the keys the action
            // animated; the second half keeps the original target. The
            // curve is kept on both halves: re-deriving an exact sub-curve
            // is impossible for the eased forms, and the endpoints — which
            // is what a viewer sees at the join — are exact either way.
            let mut head = action.clone();
            head.duration = clip_t.saturating_sub(action.start);
            head.end = narrow_to(&patch_source, &action.end, 0);
            first_actions.push(head);

            let mut tail = action.clone();
            tail.id = project.allocate_id();
            tail.start = 0;
            tail.duration = end.saturating_sub(clip_t);
            second_actions.push(tail);
        }
    }
    second.actions = second_actions;

    if let Some(first) = project.clip_mut(clip_id) {
        first.duration = clip_t;
        first.actions = first_actions;
    }
    project.clips.push(second);
    true
}

// ---- the ops -------------------------------------------------------------

impl Project {
    /// A tick value on the document's frame grid. Every op runs its
    /// arguments through this before anything else (spec §6).
    pub(crate) fn snapped(&self, t: Ticks) -> Ticks {
        time::snap_to_frame(t, self.canvas.fps)
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

    /// The single exit of every op: identity is `None` (never a copy, which
    /// would register a phantom undo step), and a result that broke an
    /// invariant is an `Err` rather than a project the rest of the crate
    /// cannot reason about.
    pub(crate) fn finish(&self, next: Project) -> Result<Option<Project>, String> {
        if next == *self {
            return Ok(None);
        }
        next.validate()?;
        Ok(Some(next))
    }

    /// Fit scale for a new clip: `min(cw/sw, ch/sh)` when `fit_new_clips`
    /// is on and the source exceeds the canvas, else 1 (spec §5.3). A
    /// source that already fits is never scaled UP — Fit is a rescue for
    /// oversized footage, not a stretch.
    fn fit_scale(&self, source_width: f64, source_height: f64) -> f64 {
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
    /// tabs to enable. Refuses (`None`) when the placement breaks the
    /// overlap rule; `Err` for an unknown track or media, or a media with
    /// no usable duration.
    pub fn add_clip(&self, track: u32, media: u32, at: Ticks) -> Result<Option<Project>, String> {
        self.require_track(track)?;
        let found = self.require_media(media)?.clone();
        // A drag can start left of zero; the timeline has no negative time.
        let at = self.snapped(at).max(0);

        let (source, duration) = match found.kind {
            // A still image has no source bound, so it gets the default
            // length unless the descriptor gave it one.
            MediaKind::Image => {
                let duration = if found.duration > 0 {
                    self.snapped(found.duration)
                } else {
                    DEFAULT_CLIP_DURATION
                };
                (Source::Image { media }, duration)
            }
            MediaKind::Video | MediaKind::Audio => {
                let duration = self.snapped(found.duration);
                if duration <= 0 {
                    return Err(format!(
                        "media {media} has no duration ({} ticks)",
                        found.duration
                    ));
                }
                (Source::Media { media, r#in: 0 }, duration)
            }
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
        };
        if self
            .check_overlap_rule(std::slice::from_ref(&clip), track, &[])
            .is_err()
        {
            return Ok(None);
        }
        next.clips.push(clip);
        set_gained_transitions(&mut next, &[track]);
        self.finish(next)
    }

    /// A text clip at `at` on `track`: the Title preset, centered, five
    /// seconds by default, with `text` merged over it as a `set_text`
    /// patch (spec §6, §4.3).
    ///
    /// Refuses (`None`) on an overlap-rule violation; `Err` for an unknown
    /// track, a non-positive duration, or a bad patch.
    pub fn add_text_clip(
        &self,
        track: u32,
        at: Ticks,
        duration: Option<Ticks>,
        text: Option<&Value>,
    ) -> Result<Option<Project>, String> {
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
                let merged = merge_group(&actions::to_json(&title), patch, Group::Text)?;
                let props: TextProps = serde_json::from_value(merged)
                    .map_err(|e| format!("text patch does not match the schema: {e}"))?;
                check_text(&props)?;
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
    /// patch (spec §6).
    pub fn add_shape_clip(
        &self,
        track: u32,
        at: Ticks,
        duration: Option<Ticks>,
        shape: Option<&Value>,
    ) -> Result<Option<Project>, String> {
        let props = match shape {
            None => ShapeProps::default(),
            Some(patch) => {
                let merged = merge_group(
                    &actions::to_json(&ShapeProps::default()),
                    patch,
                    Group::Shape,
                )?;
                let props: ShapeProps = serde_json::from_value(merged)
                    .map_err(|e| format!("shape patch does not match the schema: {e}"))?;
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
    ) -> Result<Option<Project>, String> {
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
        };
        if self
            .check_overlap_rule(std::slice::from_ref(&clip), track, &[])
            .is_err()
        {
            return Ok(None);
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
    /// Refuses (`None`) when a clip would land outside the track list or
    /// the overlap rule fails on any affected track. A clip that gains a
    /// predecessor overlap and has no transition gets a cross dissolve.
    pub fn move_clips(
        &self,
        clips: &[u32],
        delta: Ticks,
        track: Option<u32>,
    ) -> Result<Option<Project>, String> {
        let selection = self.selected_clips(clips)?;
        if selection.is_empty() {
            return Ok(None);
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
                    return Ok(None);
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
            if self.check_overlap_rule(&candidates, *track, &[]).is_err() {
                return Ok(None);
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
    pub fn trim_start(&self, clip: u32, to: Ticks) -> Result<Option<Project>, String> {
        let target = self.require_clip(clip)?.clone();
        let end = clip_end(&target);
        let latest = end.saturating_sub(self.frame());
        let mut to = self.snapped(to).min(latest).max(0);

        if let Source::Media { r#in, .. } = target.source {
            // `in` ticks of source lie before the clip's first frame, which
            // is `in / speed` ticks of TIMELINE at this clip's rate.
            let head = if target.speed.is_finite() && target.speed > 0.0 {
                let head = (r#in.max(0) as f64 / target.speed).floor();
                if head.is_finite() {
                    head as Ticks
                } else {
                    0
                }
            } else {
                0
            };
            to = to.max(target.start.saturating_sub(head).max(0));
        }
        // The two clamps can cross when the source has almost nothing left
        // in front: then there is no legal new start, so nothing happens.
        if to > latest || to == target.start {
            return Ok(None);
        }

        let delta = to.saturating_sub(target.start);
        let mut moved = target.clone();
        if let Source::Media { media, r#in } = target.source {
            let advance = (delta as f64 * target.speed).round();
            let advance = if advance.is_finite() {
                advance as Ticks
            } else {
                0
            };
            moved.source = Source::Media {
                media,
                r#in: r#in.saturating_add(advance).max(0),
            };
        }
        moved.start = to;
        moved.duration = end.saturating_sub(to);
        if self
            .check_overlap_rule(&[moved.clone()], moved.track, &[])
            .is_err()
        {
            return Ok(None);
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
    pub fn trim_end(&self, clip: u32, to: Ticks) -> Result<Option<Project>, String> {
        let target = self.require_clip(clip)?.clone();
        let earliest = target.start.saturating_add(self.frame());
        let mut to = self.snapped(to).max(earliest);
        if let Some(available) = self.source_length(&target) {
            to = to.min(target.start.saturating_add(available));
        }
        if to < earliest || to == clip_end(&target) {
            return Ok(None);
        }

        let mut moved = target.clone();
        moved.duration = to.saturating_sub(target.start);
        if self
            .check_overlap_rule(&[moved.clone()], moved.track, &[])
            .is_err()
        {
            return Ok(None);
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
    /// Refuses (`None`) when the resulting rate falls outside ×0.1 – ×10,
    /// when the new length is under a frame, or when the placement breaks
    /// the overlap rule. Actions keep their clip-relative fraction.
    pub fn rate_stretch(&self, clip: u32, to_end: Ticks) -> Result<Option<Project>, String> {
        let target = self.require_clip(clip)?.clone();
        if !matches!(target.source, Source::Media { .. }) {
            return Err(format!("clip {clip} is not a media clip"));
        }
        let to_end = self.snapped(to_end);
        let duration = to_end.saturating_sub(target.start);
        if duration < self.frame() {
            return Ok(None);
        }
        let rate = content_length(&target) as f64 / duration as f64;
        if !rate.is_finite() || !(SPEED_MIN..=SPEED_MAX).contains(&rate) {
            return Ok(None);
        }

        let mut moved = target.clone();
        moved.speed = rate;
        moved.duration = duration;
        self.rescale_actions(&mut moved.actions, target.duration, duration);
        if self
            .check_overlap_rule(&[moved.clone()], moved.track, &[])
            .is_err()
        {
            return Ok(None);
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
    /// refuses (`None`). `Err` only for an unknown clip id.
    pub fn split_clips(&self, clips: &[u32], at: Ticks) -> Result<Option<Project>, String> {
        let at = self.snapped(at);
        let ids: Vec<u32> = self.selected_clips(clips)?.iter().map(|c| c.id).collect();
        let mut next = self.clone();
        let mut cut = false;
        for id in ids {
            cut |= split_clip(&mut next, id, at);
        }
        if !cut {
            return Ok(None);
        }
        self.finish(next)
    }

    /// Cuts every clip on an UNLOCKED track that `at` falls strictly inside
    /// — ⌘K with no selection (spec §6, §9).
    pub fn split_under_playhead(&self, at: Ticks) -> Result<Option<Project>, String> {
        let at = self.snapped(at);
        let ids: Vec<u32> = self
            .clips
            .iter()
            .filter(|c| self.track(c.track).is_some_and(|t| !t.locked))
            .filter(|c| c.start < at && at < clip_end(c))
            .map(|c| c.id)
            .collect();
        if ids.is_empty() {
            return Ok(None);
        }
        let mut next = self.clone();
        let mut cut = false;
        for id in ids {
            cut |= split_clip(&mut next, id, at);
        }
        if !cut {
            return Ok(None);
        }
        self.finish(next)
    }

    /// Removes the named clips. Gaps stay — rippling is `edit_time`'s job
    /// (spec §6).
    pub fn delete_clips(&self, clips: &[u32]) -> Result<Option<Project>, String> {
        let ids: Vec<u32> = self.selected_clips(clips)?.iter().map(|c| c.id).collect();
        if ids.is_empty() {
            return Ok(None);
        }
        let mut next = self.clone();
        next.clips.retain(|c| !ids.contains(&c.id));
        self.finish(next)
    }

    /// Copies the named clips immediately after their own span, on their
    /// own tracks (spec §6): the copies start one span-length later, so a
    /// multi-clip selection keeps its internal timing exactly.
    ///
    /// Clips and their actions get fresh ids. Refuses (`None`) when the
    /// copies would break the overlap rule.
    pub fn duplicate_clips(&self, clips: &[u32]) -> Result<Option<Project>, String> {
        let selection: Vec<Clip> = self
            .selected_clips(clips)?
            .into_iter()
            .cloned()
            .collect::<Vec<Clip>>();
        if selection.is_empty() {
            return Ok(None);
        }
        let span_start = selection.iter().map(|c| c.start).min().unwrap_or(0);
        let span_end = selection.iter().map(clip_end).max().unwrap_or(0);
        let delta = span_end.saturating_sub(span_start);
        if delta <= 0 {
            return Ok(None);
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
            if self.check_overlap_rule(&copies, *track, &[]).is_err() {
                return Ok(None);
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
    /// is not a positive finite number; refuses (`None`) on an overlap-rule
    /// violation.
    pub fn set_speed(
        &self,
        clip: u32,
        rate: f64,
        keep_pitch: Option<bool>,
    ) -> Result<Option<Project>, String> {
        let target = self.require_clip(clip)?.clone();
        if !matches!(target.source, Source::Media { .. }) {
            return Err(format!("clip {clip} is not a media clip"));
        }
        if !(rate.is_finite() && rate > 0.0) {
            return Err(format!("speed must be a positive number, not {rate}"));
        }
        let rate = rate.clamp(SPEED_MIN, SPEED_MAX);

        let scaled = content_length(&target) as f64 / rate;
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
        if self
            .check_overlap_rule(&[moved.clone()], moved.track, &[])
            .is_err()
        {
            return Ok(None);
        }

        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            *slot = moved;
        }
        set_gained_transitions(&mut next, &[target.track]);
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
    /// Refuses (`None`) when the media has no audio, when the audio is
    /// already detached, or when the new clip would break the overlap rule
    /// on the track below.
    pub fn detach_audio(&self, clip: u32) -> Result<Option<Project>, String> {
        let target = self.require_clip(clip)?.clone();
        let Source::Media { media, .. } = target.source else {
            // Stills, images, text and shapes have no audio to detach.
            return Ok(None);
        };
        let Some(found) = self.media(media) else {
            return Ok(None);
        };
        if !found.has_audio || !target.enabled.audio {
            return Ok(None);
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

        if self
            .check_overlap_rule(&[audio_clip.clone()], below, &[])
            .is_err()
        {
            return Ok(None);
        }
        if let Some(slot) = next.clip_mut(clip) {
            slot.enabled.audio = false;
        }
        next.clips.push(audio_clip);
        set_gained_transitions(&mut next, &[below]);
        self.finish(next)
    }

    // ---- enablement and transitions --------------------------------------

    /// Per-clip visibility and mute (spec §6). An argument left `None` is
    /// left alone, so the two halves of Detach Audio can be set
    /// independently.
    pub fn set_enabled(
        &self,
        clip: u32,
        video: Option<bool>,
        audio: Option<bool>,
    ) -> Result<Option<Project>, String> {
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

    /// Sets — or clears, with `None` — the transition covering the clip's
    /// overlap with its predecessor (spec §6). A clip with no overlap may
    /// still carry a kind; it is simply ignored until one exists, which is
    /// what lets the inspector set the kind before dragging the overlap.
    pub fn set_transition(
        &self,
        clip: u32,
        kind: Option<TransitionKind>,
    ) -> Result<Option<Project>, String> {
        self.require_clip(clip)?;
        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            slot.transition_in = kind.map(|kind| Transition { kind });
        }
        self.finish(next)
    }

    /// Moves the clip so its overlap with its predecessor is exactly
    /// `duration` (spec §6) — the transition's length IS that overlap, so
    /// there is nothing else to set.
    ///
    /// Refuses (`None`) when the clip has no predecessor on its track, when
    /// the new start would be negative, or when the result breaks the
    /// overlap rule. `Err` on a negative duration.
    pub fn set_transition_duration(
        &self,
        clip: u32,
        duration: Ticks,
    ) -> Result<Option<Project>, String> {
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
            None => return Ok(None),
        };
        let Some(previous) = index.checked_sub(1).and_then(|i| ordered.get(i)) else {
            return Ok(None);
        };
        // The overlap is the tail of the previous clip the later one covers,
        // so the later one starts exactly `duration` before that tail ends.
        let start = clip_end(previous).saturating_sub(duration);
        if start < 0 {
            return Ok(None);
        }

        let mut moved = target.clone();
        moved.start = start;
        if self
            .check_overlap_rule(&[moved.clone()], moved.track, &[])
            .is_err()
        {
            return Ok(None);
        }

        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            slot.start = start;
        }
        set_gained_transitions(&mut next, &[target.track]);
        self.finish(next)
    }

    // ---- actions ---------------------------------------------------------

    /// Adds an action to the clip at CLIP time `at` — the caller converts
    /// the playhead by subtracting the clip's start — one second long by
    /// default, with an empty end patch, so it changes nothing until the
    /// inspector edits it (spec §6).
    ///
    /// Refuses (`None`) when it would overlap another action on the clip or
    /// run past the clip's end. `Err` on a negative start or a non-positive
    /// duration.
    pub fn add_action(
        &self,
        clip: u32,
        at: Ticks,
        duration: Option<Ticks>,
    ) -> Result<Option<Project>, String> {
        let target = self.require_clip(clip)?.clone();
        let at = self.snapped(at);
        if at < 0 {
            return Err(format!("action start must not be negative, not {at}"));
        }
        let duration = match duration {
            None => DEFAULT_ACTION_DURATION,
            Some(given) => {
                let snapped = self.snapped(given);
                if snapped <= 0 {
                    return Err(format!("action duration must be positive, not {given}"));
                }
                snapped
            }
        };
        if at.saturating_add(duration) > target.duration {
            return Ok(None);
        }
        if actions_overlap(&target.actions, None, at, duration) {
            return Ok(None);
        }

        let mut next = self.clone();
        let id = next.allocate_id();
        if let Some(slot) = next.clip_mut(clip) {
            slot.actions.push(Action {
                id,
                start: at,
                duration,
                curve: Curve::default(),
                end: Value::Object(serde_json::Map::new()),
            });
        }
        self.finish(next)
    }

    /// Retimes or re-curves one action; every argument left `None` keeps
    /// its current value (spec §6). Same overlap and clip-end checks as
    /// `add_action`.
    pub fn set_action(
        &self,
        clip: u32,
        action: u32,
        start: Option<Ticks>,
        duration: Option<Ticks>,
        curve: Option<Curve>,
    ) -> Result<Option<Project>, String> {
        let target = self.require_clip(clip)?.clone();
        let existing = target
            .actions
            .iter()
            .find(|a| a.id == action)
            .ok_or_else(|| format!("no action with id {action} on clip {clip}"))?
            .clone();

        let new_start = match start {
            None => existing.start,
            Some(given) => {
                let snapped = self.snapped(given);
                if snapped < 0 {
                    return Err(format!("action start must not be negative, not {given}"));
                }
                snapped
            }
        };
        let new_duration = match duration {
            None => existing.duration,
            Some(given) => {
                let snapped = self.snapped(given);
                if snapped <= 0 {
                    return Err(format!("action duration must be positive, not {given}"));
                }
                snapped
            }
        };
        if new_start.saturating_add(new_duration) > target.duration {
            return Ok(None);
        }
        if actions_overlap(&target.actions, Some(action), new_start, new_duration) {
            return Ok(None);
        }

        let mut next = self.clone();
        if let Some(slot) = next
            .clip_mut(clip)
            .and_then(|c| c.actions.iter_mut().find(|a| a.id == action))
        {
            slot.start = new_start;
            slot.duration = new_duration;
            if let Some(curve) = curve {
                slot.curve = curve;
            }
        }
        self.finish(next)
    }

    /// Merges `patch` into the action's end state; a key set to `null`
    /// REMOVES it, which is how the inspector stops animating one property
    /// without deleting the action (spec §6).
    ///
    /// Unknown keys are kept, not rejected: an end patch is evaluated
    /// leniently (`actions.rs`), and a project written by a newer build
    /// must survive a round trip through this one.
    pub fn set_action_end(
        &self,
        clip: u32,
        action: u32,
        patch: &Value,
    ) -> Result<Option<Project>, String> {
        let target = self.require_clip(clip)?;
        let existing = target
            .actions
            .iter()
            .find(|a| a.id == action)
            .ok_or_else(|| format!("no action with id {action} on clip {clip}"))?;
        if !patch.is_object() {
            return Err(format!(
                "action end patch must be a json object, not {}",
                describe(patch)
            ));
        }
        let mut merged = actions::merge(&existing.end, patch);
        prune_removed(&mut merged, patch, 0);

        let mut next = self.clone();
        if let Some(slot) = next
            .clip_mut(clip)
            .and_then(|c| c.actions.iter_mut().find(|a| a.id == action))
        {
            slot.end = merged;
        }
        self.finish(next)
    }

    /// Removes one action from a clip (spec §6).
    pub fn remove_action(&self, clip: u32, action: u32) -> Result<Option<Project>, String> {
        let target = self.require_clip(clip)?;
        if !target.actions.iter().any(|a| a.id == action) {
            return Err(format!("no action with id {action} on clip {clip}"));
        }
        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            slot.actions.retain(|a| a.id != action);
        }
        self.finish(next)
    }
}
