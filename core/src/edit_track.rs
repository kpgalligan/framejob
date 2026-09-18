//! Tracks, markers, the canvas and the media list — spec §6, table
//! "Tracks, markers, canvas, media".
//!
//! One `impl Project` block for everything a clip sits *in* rather than
//! everything a clip *is*: the track stack, the marker list, the document's
//! size and rate, and the media the clips point at. `edit_clip.rs` owns the
//! clips themselves; the rules both obey are written there and called from
//! here — [`Project::snapped`] for every tick argument, [`Project::finish`]
//! as the single exit that turns an identity result into
//! [`Outcome::Identity`] and a broken invariant into `Err`.
//!
//! Three invariants this module is responsible for:
//!
//! 1. **A project always has at least one track.** Removing the last one
//!    refuses; `remove_empty_tracks` keeps the back-most.
//! 2. **Two markers never share a tick.** A marker is how the user names a
//!    moment, and two at one moment is a UI the timeline cannot draw. The
//!    op that would create the collision is an `Err` naming the time.
//! 3. **One media entry per path.** Re-importing a file already in the
//!    project changes nothing; the clips reference the entry that is
//!    already there.

use serde_json::Value;

use crate::export::describe;
use crate::model::{
    Clip, Color, Marker, Media, MediaKind, Project, Source, Track, DEFAULT_MARKER_COLOR,
};
use crate::outcome::Outcome;
use crate::props_check::{color_ok, SCALE_MAX, SCALE_MIN};
use crate::time::{self, Fps, Ticks};

/// Canvas dimension bounds. The floor is small enough for a thumbnail-sized
/// document and large enough that the compositor has pixels to work with;
/// the ceiling is past 8K, where a single frame is already 130 MB.
const CANVAS_MIN: u32 = 16;
const CANVAS_MAX: u32 = 16384;

/// Media dimension ceiling. Nothing decodes at this size — it exists so a
/// probe that reports garbage (or a hand-written project) cannot put a
/// number in the document that later overflows a texture allocation or
/// collapses `fit_scale` to zero.
const MEDIA_DIMENSION_MAX: u32 = 65536;

/// The keys a media descriptor may carry: the spec §5.2 `media[]` element
/// MINUS `id`. Spelled out rather than derived from a serialized [`Media`],
/// because the point of the list is to NAME a misspelled key — serde would
/// silently drop `"widht"` and leave the user with a zero-width media.
const MEDIA_KEYS: [&str; 10] = [
    "path",
    "bookmark",
    "kind",
    "duration",
    "width",
    "height",
    "fps",
    "has_video",
    "has_audio",
    "has_alpha",
];

// ---- helpers -------------------------------------------------------------

/// Whether `clip` shows `media`. The three media-bound sources name an id;
/// text, shape and nest do not (spec §5.2) — a nest clip shows a GROUP, and
/// what that group references is asked of its own clips, which live in the
/// same id space and are swept alongside the timeline's.
fn uses_media(clip: &Clip, media: u32) -> bool {
    matches!(
        clip.source,
        Source::Media { media: id, .. } | Source::Still { media: id, .. } | Source::Image { media: id }
            if id == media
    )
}

/// A canvas dimension: inside the bounds AND even.
///
/// Even is not fussiness: H.264 and HEVC encode in macroblocks over a
/// chroma-subsampled plane, so an odd width or height is either refused by
/// the encoder or silently padded. Catching it here makes it a message
/// about the canvas field the user just typed instead of an export that
/// fails an hour later.
fn check_dimension(key: &str, value: u32) -> Result<(), String> {
    if !(CANVAS_MIN..=CANVAS_MAX).contains(&value) {
        return Err(format!(
            "{key} must be between {CANVAS_MIN} and {CANVAS_MAX}, not {value}"
        ));
    }
    if !value.is_multiple_of(2) {
        return Err(format!(
            "{key} must be even (h.264 encodes in macroblocks), not {value}"
        ));
    }
    Ok(())
}

/// Multiplies every clip's placement by the canvas size ratio, so a layout
/// built for one canvas lands in the same relative place on the next (spec
/// §6, `rescale_clips`).
///
/// `x` and `y` are per-axis offsets in canvas pixels, so each follows its
/// OWN axis ratio — that is what keeps a layer's distance from an edge
/// proportional when the aspect ratio changes too. `scale` is one uniform
/// factor and cannot follow two ratios, so it follows the SMALLER of them:
/// the same `min` Fit uses, which means a layer that fitted the old canvas
/// still fits the new one, where the larger ratio could push it off an
/// edge.
///
/// Action `end` patches are deliberately NOT rescaled: a patch is opaque
/// JSON (`actions.rs` interprets it), and the op is defined on the clip's
/// props. An animated move on a resized canvas therefore keeps its old
/// target, which is visible and fixable, unlike a patch this function
/// half-understood and rewrote.
fn rescale(project: &mut Project, old_width: u32, old_height: u32) {
    if old_width == 0 || old_height == 0 {
        return;
    }
    let width_ratio = f64::from(project.canvas.width) / f64::from(old_width);
    let height_ratio = f64::from(project.canvas.height) / f64::from(old_height);
    if !(width_ratio.is_finite() && height_ratio.is_finite()) {
        return;
    }
    let scale_ratio = width_ratio.min(height_ratio);
    for clip in project.clips.iter_mut() {
        if let Some(video) = clip.video.as_mut() {
            video.x *= width_ratio;
            video.y *= height_ratio;
            // Clamped to the same range `set_video` accepts, so a chain of
            // shrinks cannot leave a scale the inspector refuses to show.
            video.scale = (video.scale * scale_ratio).clamp(SCALE_MIN, SCALE_MAX);
        }
    }
}

/// Re-snaps every stored time to the canvas's CURRENT frame grid, after
/// that grid has changed.
///
/// Nothing sub-frame may live in the model (spec §6), and yesterday's grid
/// is not today's: a 24 fps boundary is not a 30 fps boundary, so every
/// clip start and duration, every action span and every marker time has to
/// move to the nearest new boundary.
///
/// Two clamps keep the result valid: a duration that would round to zero
/// becomes one frame (a zero-length clip is what `validate` rejects), and
/// an action is kept inside its clip.
fn resnap(project: &mut Project) {
    let fps = project.canvas.fps;
    let frame = project.frame();
    for clip in project.clips.iter_mut() {
        clip.start = time::snap_to_frame(clip.start, fps).max(0);
        clip.duration = time::snap_to_frame(clip.duration, fps).max(frame);
        let last_start = clip.duration.saturating_sub(frame).max(0);
        for action in clip.actions.iter_mut() {
            action.start = time::snap_to_frame(action.start, fps).clamp(0, last_start);
            action.duration = time::snap_to_frame(action.duration, fps)
                .max(frame)
                .min(clip.duration.saturating_sub(action.start))
                .max(1);
        }
    }
    for marker in project.markers.iter_mut() {
        marker.time = time::snap_to_frame(marker.time, fps).max(0);
    }
    // A coarser grid can land two markers on one tick, which markers may
    // never share. The alternative — refusing a document-wide rate change
    // because two marks are 3 ms apart — is far worse than dropping the
    // second of them, so the first in the list keeps the tick.
    //
    // A linear scan over a `Vec` rather than a set: markers are capped at
    // 1024 and this runs only on a rate change.
    let mut taken: Vec<Ticks> = Vec::with_capacity(project.markers.len());
    project.markers.retain(|marker| {
        if taken.contains(&marker.time) {
            false
        } else {
            taken.push(marker.time);
            true
        }
    });
}

// ---- the ops -------------------------------------------------------------

impl Project {
    fn require_marker(&self, id: u32) -> Result<&Marker, String> {
        self.marker(id)
            .ok_or_else(|| format!("no marker with id {id}"))
    }

    // ---- tracks ----------------------------------------------------------

    /// Inserts a track at `index`, where 0 is the BACK-most (bottom) layer
    /// and `tracks.len()` is the front; `None` means the front, which is
    /// where a new layer goes (spec §6).
    ///
    /// The default name is `Track <count + 1>` — named by the count, not by
    /// the index, so inserting in the middle does not renumber the tracks
    /// above it under the user. A name of only whitespace is treated as
    /// absent. `Err` for an index past the end, or (through `finish`) for
    /// exceeding the track cap.
    pub fn add_track(&self, index: Option<usize>, name: Option<&str>) -> Result<Outcome, String> {
        let at = match index {
            None => self.tracks.len(),
            Some(given) if given <= self.tracks.len() => given,
            Some(given) => {
                return Err(format!(
                    "track index {given} is out of range (0..={})",
                    self.tracks.len()
                ))
            }
        };

        let mut next = self.clone();
        let id = next.allocate_id();
        let name = name
            .map(str::trim)
            .filter(|given| !given.is_empty())
            .map(|given| given.to_string())
            .unwrap_or_else(|| format!("Track {}", next.tracks.len().saturating_add(1)));
        next.tracks.insert(
            at,
            Track {
                id,
                name,
                hidden: false,
                muted: false,
                locked: false,
                solo: false,
            },
        );
        self.finish(next)
    }

    /// Removes a track. Refuses on a track that still holds clips unless
    /// `with_clips`, which removes those clips with it, and refuses to
    /// remove the LAST track: a project always has somewhere to put a clip,
    /// and an empty track stack is a UI with nothing to drop onto.
    ///
    /// `Err` only for an unknown track.
    pub fn remove_track(&self, track: u32, with_clips: bool) -> Result<Outcome, String> {
        self.require_track(track)?;
        if self.tracks.len() <= 1 {
            return Ok(Outcome::Identity);
        }
        let occupied = self.clips.iter().any(|c| c.track == track);
        if occupied && !with_clips {
            return Ok(Outcome::Identity);
        }

        let mut next = self.clone();
        next.tracks.retain(|t| t.id != track);
        next.clips.retain(|c| c.track != track);
        self.finish(next)
    }

    /// Moves a track to `index` in the stack (0 = back-most), sliding the
    /// tracks it passes over the other way — the layer reorder the timeline
    /// drag makes (spec §6).
    ///
    /// `Err` for an unknown track or an index past the end; `None` when the
    /// track is already there.
    pub fn move_track(&self, track: u32, index: usize) -> Result<Outcome, String> {
        let from = self.require_track_index(track)?;
        if index >= self.tracks.len() {
            return Err(format!(
                "track index {index} is out of range (0..{})",
                self.tracks.len()
            ));
        }
        if index == from {
            return Ok(Outcome::Identity);
        }

        let mut next = self.clone();
        // `from` came from `track_index`, so it addresses a track that is
        // there; `index` was just bounds-checked against the same list.
        let moved = next.tracks.remove(from);
        next.tracks.insert(index, moved);
        self.finish(next)
    }

    /// Sets any subset of a track's fields; an omitted argument keeps its
    /// value (spec §6). The name is stored trimmed, and an empty name is
    /// allowed — it means "unnamed", and the timeline draws the track's
    /// position instead.
    pub fn set_track(
        &self,
        track: u32,
        name: Option<&str>,
        hidden: Option<bool>,
        muted: Option<bool>,
        locked: Option<bool>,
        solo: Option<bool>,
    ) -> Result<Outcome, String> {
        self.require_track(track)?;
        let mut next = self.clone();
        if let Some(found) = next.tracks.iter_mut().find(|t| t.id == track) {
            if let Some(name) = name {
                found.name = name.trim().to_string();
            }
            if let Some(hidden) = hidden {
                found.hidden = hidden;
            }
            if let Some(muted) = muted {
                found.muted = muted;
            }
            if let Some(locked) = locked {
                found.locked = locked;
            }
            if let Some(solo) = solo {
                found.solo = solo;
            }
        }
        self.finish(next)
    }

    /// Removes every track that holds no clips — the tidy-up after a big
    /// delete (spec §6).
    ///
    /// If that would empty the stack, the back-most track survives: it is
    /// the one a fresh project starts with, and keeping the bottom of the
    /// stack means the surviving track is where a drop lands.
    pub fn remove_empty_tracks(&self) -> Result<Outcome, String> {
        let mut next = self.clone();
        next.tracks
            .retain(|t| self.clips.iter().any(|c| c.track == t.id));
        if next.tracks.is_empty() {
            next.tracks = self.tracks.iter().take(1).cloned().collect();
        }
        self.finish(next)
    }

    // ---- markers ---------------------------------------------------------

    /// Adds a marker at `at`, snapped to the frame grid and clamped to 0 —
    /// a drag can start left of the timeline, and there is no negative time
    /// (spec §6).
    ///
    /// The default name is `Marker <count + 1>` and the default colour is
    /// `"red"`. `Err` when another marker already holds the tick: two
    /// markers may not share a time, and moving the existing one is the
    /// caller's decision, not this op's.
    pub fn add_marker(
        &self,
        at: Ticks,
        name: Option<&str>,
        chapter: Option<bool>,
        color: Option<&str>,
    ) -> Result<Outcome, String> {
        let at = self.snapped(at).max(0);
        if let Some(existing) = self.markers.iter().find(|m| m.time == at) {
            return Err(format!("marker {} is already at {at} ticks", existing.id));
        }

        let mut next = self.clone();
        let id = next.allocate_id();
        let name = name
            .map(|given| given.trim().to_string())
            .unwrap_or_else(|| format!("Marker {}", next.markers.len().saturating_add(1)));
        let color = color
            .map(str::trim)
            .filter(|given| !given.is_empty())
            .unwrap_or(DEFAULT_MARKER_COLOR)
            .to_string();
        next.markers.push(Marker {
            id,
            time: at,
            name,
            color,
            chapter: chapter.unwrap_or(false),
        });
        self.finish(next)
    }

    /// Sets any subset of a marker's fields; an omitted argument keeps its
    /// value. A new time is snapped and clamped to 0 like `add_marker`'s,
    /// and collides with another marker the same way (`Err`).
    ///
    /// An empty `name` is allowed: it clears the label, which is how a
    /// marker becomes a plain mark.
    pub fn set_marker(
        &self,
        marker: u32,
        time: Option<Ticks>,
        name: Option<&str>,
        chapter: Option<bool>,
        color: Option<&str>,
    ) -> Result<Outcome, String> {
        self.require_marker(marker)?;
        let time = match time {
            None => None,
            Some(given) => {
                let at = self.snapped(given).max(0);
                if let Some(other) = self.markers.iter().find(|m| m.id != marker && m.time == at) {
                    return Err(format!("marker {} is already at {at} ticks", other.id));
                }
                Some(at)
            }
        };

        let mut next = self.clone();
        if let Some(found) = next.markers.iter_mut().find(|m| m.id == marker) {
            if let Some(time) = time {
                found.time = time;
            }
            if let Some(name) = name {
                found.name = name.trim().to_string();
            }
            if let Some(chapter) = chapter {
                found.chapter = chapter;
            }
            // An empty colour falls back to the default rather than being
            // stored: the UI has to draw the mark as something.
            if let Some(color) = color.map(str::trim).filter(|given| !given.is_empty()) {
                found.color = color.to_string();
            }
        }
        self.finish(next)
    }

    /// Removes a marker. `Err` only for an unknown id.
    pub fn remove_marker(&self, marker: u32) -> Result<Outcome, String> {
        self.require_marker(marker)?;
        let mut next = self.clone();
        next.markers.retain(|m| m.id != marker);
        self.finish(next)
    }

    // ---- canvas ----------------------------------------------------------

    /// Sets any subset of the document's canvas fields (spec §6). An
    /// omitted argument keeps its value.
    ///
    /// `rescale_clips` multiplies every clip's `x`, `y` and `scale` by the
    /// size ratio (see [`rescale`]) so a finished layout survives a resize.
    /// Changing `fps` re-snaps EVERY stored time to the new grid — clip
    /// starts and durations, action spans, marker times (see [`resnap`]) —
    /// because nothing sub-frame may live in the model.
    ///
    /// `Err` for a dimension outside 16..16384 or odd (H.264 needs even
    /// dimensions), a frame rate with a zero term, or a background channel
    /// outside 0..1.
    ///
    /// The rate change is deliberately NOT re-checked against the overlap
    /// rule: re-snapping moves each edge by less than one frame, so an
    /// overlap can grow by at most a frame, and refusing a document-wide
    /// rate change over a one-frame drift would be worse than the drift.
    #[allow(clippy::too_many_arguments)]
    // The argument list IS the op's argument list (spec §6); a struct would
    // hold exactly the same seven optional fields and one more name.
    pub fn set_canvas(
        &self,
        width: Option<u32>,
        height: Option<u32>,
        fps: Option<Fps>,
        background: Option<Color>,
        rescale_clips: bool,
        fit_new_clips: Option<bool>,
        timecode_frames: Option<bool>,
    ) -> Result<Outcome, String> {
        let width = match width {
            None => self.canvas.width,
            Some(given) => {
                check_dimension("canvas width", given)?;
                given
            }
        };
        let height = match height {
            None => self.canvas.height,
            Some(given) => {
                check_dimension("canvas height", given)?;
                given
            }
        };
        let fps = match fps {
            None => self.canvas.fps,
            Some(given) if given.is_valid() => given,
            Some(given) => {
                return Err(format!(
                    "canvas fps must be [num, den] with non-zero terms, not [{}, {}]",
                    given.num, given.den
                ))
            }
        };
        if let Some(background) = background.as_ref() {
            color_ok("canvas background", background)?;
        }

        let mut next = self.clone();
        next.canvas.width = width;
        next.canvas.height = height;
        next.canvas.fps = fps;
        if let Some(background) = background {
            next.canvas.background = background;
        }
        if let Some(fit_new_clips) = fit_new_clips {
            next.canvas.fit_new_clips = fit_new_clips;
        }
        if let Some(timecode_frames) = timecode_frames {
            next.canvas.timecode_frames = timecode_frames;
        }

        let resized = width != self.canvas.width || height != self.canvas.height;
        if rescale_clips && resized {
            rescale(&mut next, self.canvas.width, self.canvas.height);
        }
        if fps != self.canvas.fps {
            resnap(&mut next);
        }
        self.finish(next)
    }

    // ---- media -----------------------------------------------------------

    /// Adds one probed file to the media list. `descriptor` is the spec
    /// §5.2 `media[]` element MINUS `id` — the host probes the file and
    /// fills in kind, duration, size, rate and the track flags.
    ///
    /// **The new media's id is the project's `next_id` BEFORE this call.**
    /// There is one JSON op entry point (spec §11), so an op cannot return
    /// a value; reading `next_id` first is how the caller learns the id it
    /// is about to be able to `add_clip` with.
    ///
    /// Adding a file whose path is already in the list changes nothing (an
    /// identity): two entries for one path would each carry their own
    /// bookmark, thumbnails and peaks, and relinking one would leave the
    /// other missing. The caller that gets it looks the path up to find the
    /// id that is already there.
    ///
    /// `Err` for a descriptor that is not an object, an unknown or `id`
    /// key, a value that does not match the schema, an empty path, a
    /// negative duration, or a media with pixels whose size or rate is not
    /// usable.
    pub fn add_media(&self, descriptor: &Value) -> Result<Outcome, String> {
        let Value::Object(fields) = descriptor else {
            return Err(format!(
                "a media descriptor must be a json object, not {}",
                describe(descriptor)
            ));
        };
        if fields.contains_key("id") {
            return Err(format!(
                "a media descriptor must not carry an id: the project assigns it (this one gets {})",
                self.next_id
            ));
        }
        for key in fields.keys() {
            if !MEDIA_KEYS.contains(&key.as_str()) {
                return Err(format!("unknown key \"{key}\" in a media descriptor"));
            }
        }

        // Deserializing through `Media` itself means the descriptor's
        // schema is the model's schema — `kind` is checked against the
        // three variants, `fps` against `[num, den]` — with no second
        // spelling of it here. The id is stamped in first because `Media`
        // requires one.
        let mut with_id = descriptor.clone();
        if let Value::Object(map) = &mut with_id {
            map.insert("id".to_string(), Value::from(self.next_id));
        }
        let media: Media = serde_json::from_value(with_id)
            .map_err(|e| format!("media descriptor does not match the schema: {e}"))?;

        let path = media.path.trim().to_string();
        if path.is_empty() {
            return Err("media path must not be empty".to_string());
        }
        if media.duration < 0 {
            return Err(format!(
                "media duration must not be negative, not {}",
                media.duration
            ));
        }
        // Size and rate are only meaningful for a media with pixels: an
        // audio file legitimately reports 0×0. A drawing media with a zero
        // dimension would make `fit_scale` and the frame recipe's
        // `source_size` meaningless.
        let draws = media.has_video || matches!(media.kind, MediaKind::Image);
        if draws {
            if media.width == 0 || media.height == 0 {
                return Err(format!(
                    "a media with pixels must have a positive width and height, not {}x{}",
                    media.width, media.height
                ));
            }
            if media.width > MEDIA_DIMENSION_MAX || media.height > MEDIA_DIMENSION_MAX {
                return Err(format!(
                    "media dimensions must be at most {MEDIA_DIMENSION_MAX}, not {}x{}",
                    media.width, media.height
                ));
            }
        }
        if media.has_video && !media.fps.is_valid() {
            return Err(format!(
                "a media with video must have a frame rate with non-zero terms, not [{}, {}]",
                media.fps.num, media.fps.den
            ));
        }

        if self.media.iter().any(|m| m.path == path) {
            return Ok(Outcome::Identity);
        }

        let mut next = self.clone();
        let mut record = media;
        record.id = next.allocate_id();
        record.path = path;
        // An empty bookmark is not a bookmark; storing one would make
        // `relink` think the file had been located once.
        record.bookmark = record.bookmark.filter(|b| !b.trim().is_empty());
        next.media.push(record);
        self.finish(next)
    }

    /// Points a media at a new file — Relink… after the original moved
    /// (spec §5.6).
    ///
    /// A `bookmark` of `None` CLEARS the stored one rather than keeping it:
    /// a bookmark resolves to the file it was made from, so the old one
    /// would point straight back at the file the user is replacing.
    ///
    /// `Err` for an unknown media or an empty path.
    pub fn relink_media(
        &self,
        media: u32,
        path: &str,
        bookmark: Option<&str>,
    ) -> Result<Outcome, String> {
        self.require_media(media)?;
        let path = path.trim();
        if path.is_empty() {
            return Err("media path must not be empty".to_string());
        }

        let mut next = self.clone();
        if let Some(found) = next.media.iter_mut().find(|m| m.id == media) {
            found.path = path.to_string();
            found.bookmark = bookmark
                .map(str::trim)
                .filter(|given| !given.is_empty())
                .map(|given| given.to_string());
        }
        self.finish(next)
    }

    /// Removes a media entry. Refuses while clips still show it unless
    /// `with_clips`, which removes those clips with it (spec §6) — the
    /// model has no "missing on purpose" state, and a clip pointing at an
    /// id that is gone is what `validate` rejects.
    pub fn remove_media(&self, media: u32, with_clips: bool) -> Result<Outcome, String> {
        self.require_media(media)?;
        // A nest references the project's `media[]` like everything else
        // (spec §5.2, one id space), so a clip INSIDE one counts as usage
        // and is removed with `with_clips` — but the nest CLIP is not
        // itself a user of the media and stays put. Taking it out would
        // throw away everything else in the group over one file.
        let used = self.every_clip().any(|c| uses_media(c, media));
        if used && !with_clips {
            return Ok(Outcome::Identity);
        }

        let mut next = self.clone();
        next.clips.retain(|c| !uses_media(c, media));
        for nest in next.nests.iter_mut() {
            nest.clips.retain(|c| !uses_media(c, media));
        }
        next.media.retain(|m| m.id != media);
        self.finish(next)
    }
}
