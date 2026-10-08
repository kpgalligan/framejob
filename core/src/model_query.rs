//! Reading a [`Project`]: construction, the id lookups, and `validate`.
//!
//! `model.rs` is the schema — the types whose field names ARE the JSON keys
//! — and nothing else. This module is everything the rest of the crate asks
//! a project *about*: build an empty one, find a clip / track / media /
//! marker / nest by id, hand out the next id, measure a duration, and check
//! that every invariant the editing modules assume actually holds. The
//! source-window arithmetic — how much material a clip shows, and how much
//! lies either side of it — was here and is `source_window.rs`, moved out
//! whole by road map 7 §10's phase A: the readers' units were not in their
//! names and six placement sites wrote the conversion back out.
//!
//! Split out of `model.rs` for room, under the "a new concern is a new
//! module" rule: the schema grows a field with every phase and the file was
//! over the size cap. Nothing here edits — every function takes `&self` (or
//! `&mut self` only to advance the id counter) and returns a value.

use std::collections::{HashMap, HashSet};

use crate::edit_clip_timing::{SPEED_MAX, SPEED_MIN};
use crate::format::{self, RC_FORMAT_VERSION};
use crate::model::{Canvas, Clip, Marker, Media, Nest, Project, Source, Track};
use crate::model_graphic::{check_name, NAME_RULE};
use crate::time::{Fps, Ticks};

/// The clips of one container on `track`, in start order, ties broken by id.
///
/// Free rather than a method because a [`Nest`] holds its clips the same way
/// a [`Project`] does and must order them the same way: the plan's A/B
/// assignment and the recipe's layer order are both defined by this
/// sequence, and two spellings of it would let a nested clip stack in an
/// order the timeline never would.
pub(crate) fn clips_on(clips: &[Clip], track: u32) -> Vec<&Clip> {
    let mut found: Vec<&Clip> = clips.iter().filter(|c| c.track == track).collect();
    found.sort_by_key(|c| (c.start, c.id));
    found
}

impl Project {
    /// An empty project at the given canvas size: one track, no media, no
    /// clips. `None` for a zero dimension or a degenerate frame rate — the
    /// contract `rc_project_new` reports as a NULL handle.
    pub fn new(width: u32, height: u32, fps: Fps) -> Option<Project> {
        if width == 0 || height == 0 || !fps.is_valid() {
            return None;
        }
        Some(Project {
            version: RC_FORMAT_VERSION,
            canvas: Canvas {
                width,
                height,
                fps,
                ..Canvas::default()
            },
            media: Vec::new(),
            tracks: vec![Track {
                id: 1,
                name: "Track 1".to_string(),
                hidden: false,
                muted: false,
                locked: false,
                solo: false,
                matte: crate::model::TrackMatte::None,
            }],
            clips: Vec::new(),
            markers: Vec::new(),
            next_id: 2,
            nests: Vec::new(),
        })
    }

    pub fn clip(&self, id: u32) -> Option<&Clip> {
        self.clips.iter().find(|c| c.id == id)
    }

    pub fn clip_mut(&mut self, id: u32) -> Option<&mut Clip> {
        self.clips.iter_mut().find(|c| c.id == id)
    }

    pub fn track(&self, id: u32) -> Option<&Track> {
        self.tracks.iter().find(|t| t.id == id)
    }

    /// The track's position in `tracks`: index 0 is the back-most layer.
    pub fn track_index(&self, id: u32) -> Option<usize> {
        self.tracks.iter().position(|t| t.id == id)
    }

    pub fn media(&self, id: u32) -> Option<&Media> {
        self.media.iter().find(|m| m.id == id)
    }

    pub fn marker(&self, id: u32) -> Option<&Marker> {
        self.markers.iter().find(|m| m.id == id)
    }

    pub fn nest(&self, id: u32) -> Option<&Nest> {
        self.nests.iter().find(|n| n.id == id)
    }

    /// Hands out the next id and advances the counter. Saturating rather
    /// than wrapping: exhausting 4 billion ids is impossible under the
    /// caps, and saturating cannot silently reissue id 0.
    pub fn allocate_id(&mut self) -> u32 {
        let id = self.next_id;
        self.next_id = self.next_id.saturating_add(1);
        id
    }

    /// Every clip on `track`, in start order. Ties break by id so the order
    /// is stable across edits (two clips may share a start only
    /// transiently, but the plan's A/B assignment must be deterministic).
    pub fn clips_on_track(&self, track: u32) -> Vec<&Clip> {
        clips_on(&self.clips, track)
    }

    /// End of the last clip; 0 when there are no clips.
    pub fn duration(&self) -> Ticks {
        self.clips
            .iter()
            .map(|c| c.start.saturating_add(c.duration))
            .max()
            .unwrap_or(0)
            .max(0)
    }

    /// The source's pixel size, when the model knows it. `None` for text
    /// (only the platform can measure a layout, spec §5.3) and for a media
    /// whose descriptor carries no size, which is every audio-only file.
    ///
    /// A NEST's size is its own canvas — the size it was frozen at, not the
    /// project's current one — which is what a crop on a nest clip is
    /// measured against and what the flattened layers are clipped to
    /// (`nest.rs`).
    ///
    /// Every arm tests for a POSITIVE size, the shape arm in floats where
    /// the others are in integers: a hand-written project can hold a shape
    /// clip of width 0 (`validate` checks ids, caps and the canvas, never
    /// the property vocabulary), and `fill_scale` of a degenerate source
    /// answers 1 rather than refusing, so an unguarded arm would let
    /// `add_blurred_background` place a full-size sharp copy and call it a
    /// background. A `NaN` fails `> 0.0` too, which is the answer wanted
    /// there as well.
    ///
    /// This is ONE reader where there were two — `edit_props.rs`'s private
    /// `source_size` and `edit_background.rs`'s stricter
    /// `source_pixel_size`, whose doc asked for exactly this collapse.
    /// Reading a project is this module's stated concern, and a source kind
    /// added to `model.rs` is now answered in one place rather than two.
    /// The stricter reading is the one kept, so `check_video`'s crop check
    /// on a degenerate 0-width shape clip — reachable only through a
    /// hand-written file — no longer has a size to measure against and
    /// accepts the crop; `core/tests/background.rs` pins it.
    pub(crate) fn source_size(&self, clip: &Clip) -> Option<(f64, f64)> {
        let sized = |width: u32, height: u32| {
            (width > 0 && height > 0).then(|| (f64::from(width), f64::from(height)))
        };
        match &clip.source {
            Source::Media { media, .. } | Source::Still { media, .. } | Source::Image { media } => {
                let found = self.media(*media)?;
                sized(found.width, found.height)
            }
            Source::Shape => clip
                .shape
                .as_ref()
                .filter(|shape| shape.width > 0.0 && shape.height > 0.0)
                .map(|shape| (shape.width, shape.height)),
            Source::Graphic => clip
                .graphic
                .as_ref()
                .and_then(|graphic| sized(graphic.width, graphic.height)),
            Source::Nest { project } => {
                let found = self.nest(*project)?;
                sized(found.width, found.height)
            }
            Source::Text => None,
        }
    }

    /// True when no `media[]` entry carries this id.
    ///
    /// This is NOT spec §5.6's "the media is missing" — that is about the
    /// FILE being gone, and the entry (with its path and bookmark) survives
    /// it, so only Swift can find it out and only Swift draws that slate.
    /// A dangling media *id* is a corrupt project, and [`Project::validate`]
    /// refuses one; this predicate is what several callers ask before they
    /// dereference, plus the defensive fallback in `evaluate.rs`.
    pub fn is_missing_media(&self, media: u32) -> bool {
        self.media(media).is_none()
    }

    /// Checks every invariant the rest of the crate assumes, naming the
    /// FIRST violation. Order: caps, the canvas, then id uniqueness across
    /// media, tracks, clips, actions and markers, then per-clip references,
    /// durations and speeds, then `next_id`.
    pub fn validate(&self) -> Result<(), String> {
        format::check_caps(self)?;

        // The canvas is what everything downstream is measured against.
        // `composition_plan` publishes it verbatim as `render_size`, which
        // AVFoundation cannot use at zero, and `frame()` needs a rate to
        // derive the frame grid from. `Project::new` already refuses both,
        // and `set_canvas` refuses anything outside 16..16384 with a
        // non-zero rate, so nothing this build produces can fail this — it
        // is the gate on a hand-edited or third-party `project.json`.
        //
        // Deliberately only "usable", not `set_canvas`'s stricter bounds:
        // the reader accepts every prior version (spec §5.6), and refusing
        // to open somebody's work over an odd width would be worse than the
        // encoder padding it.
        if self.canvas.width == 0 || self.canvas.height == 0 {
            return Err(format!(
                "canvas must have a positive width and height, not {}x{}",
                self.canvas.width, self.canvas.height
            ));
        }
        if !self.canvas.fps.is_valid() {
            return Err(format!(
                "canvas fps must be [num, den] with non-zero terms, not [{}, {}]",
                self.canvas.fps.num, self.canvas.fps.den
            ));
        }

        let mut ids: HashSet<u32> = HashSet::new();
        let mut max_id = 0u32;
        // Ids are unique across ALL kinds so an MCP call can name anything
        // by one integer (spec §5.2).
        for media in &self.media {
            if !ids.insert(media.id) {
                return Err(format!("duplicate id {} on media", media.id));
            }
            max_id = max_id.max(media.id);
        }
        for track in &self.tracks {
            if !ids.insert(track.id) {
                return Err(format!("duplicate id {} on track", track.id));
            }
            max_id = max_id.max(track.id);
        }
        for clip in &self.clips {
            if !ids.insert(clip.id) {
                return Err(format!("duplicate id {} on clip", clip.id));
            }
            max_id = max_id.max(clip.id);
            for action in &clip.actions {
                if !ids.insert(action.id) {
                    return Err(format!("duplicate id {} on action", action.id));
                }
                max_id = max_id.max(action.id);
            }
        }
        for marker in &self.markers {
            if !ids.insert(marker.id) {
                return Err(format!("duplicate id {} on marker", marker.id));
            }
            max_id = max_id.max(marker.id);
        }
        // A nest holds its tracks and clips in this SAME id space (see
        // [`Nest`]), so its ids join the one sweep rather than getting a
        // second one — which is the whole reason a nest is not a nested
        // project.
        for nest in &self.nests {
            if !ids.insert(nest.id) {
                return Err(format!("duplicate id {} on nest", nest.id));
            }
            max_id = max_id.max(nest.id);
            for track in &nest.tracks {
                if !ids.insert(track.id) {
                    return Err(format!(
                        "duplicate id {} on a track in nest {}",
                        track.id, nest.id
                    ));
                }
                max_id = max_id.max(track.id);
            }
            for clip in &nest.clips {
                if !ids.insert(clip.id) {
                    return Err(format!(
                        "duplicate id {} on a clip in nest {}",
                        clip.id, nest.id
                    ));
                }
                max_id = max_id.max(clip.id);
                for action in &clip.actions {
                    if !ids.insert(action.id) {
                        return Err(format!(
                            "duplicate id {} on an action in nest {}",
                            action.id, nest.id
                        ));
                    }
                    max_id = max_id.max(action.id);
                }
            }
        }

        self.check_clips(&self.clips, &self.tracks, "")?;
        for nest in &self.nests {
            self.check_clips(&nest.clips, &nest.tracks, &format!(" in nest {}", nest.id))?;
        }
        self.check_nesting()?;

        if self.next_id <= max_id {
            return Err(format!(
                "next_id {} is not greater than id {}",
                self.next_id, max_id
            ));
        }
        crate::time_bounds::check_stored_times(self)?;
        Ok(())
    }

    /// The invariants a clip must satisfy wherever it lives: the track it
    /// names is in the SAME container, its times are sane, its speed is
    /// inside the ops' `SPEED_MIN..=SPEED_MAX` (spec §11 R6-10, amended by
    /// #41), whatever it references exists, and every action on it has a
    /// duration.
    ///
    /// `whose` names the container in the message — `""` on the timeline,
    /// `" in nest 12"` inside one — so a violation is reported where it
    /// actually is. Media, by contrast, is always the project's: a nest
    /// references the parent's `media[]`, never one of its own.
    fn check_clips(&self, clips: &[Clip], tracks: &[Track], whose: &str) -> Result<(), String> {
        for clip in clips {
            if !tracks.iter().any(|t| t.id == clip.track) {
                return Err(format!(
                    "clip {}{whose} is on unknown track {}",
                    clip.id, clip.track
                ));
            }
            if clip.duration <= 0 {
                return Err(format!(
                    "clip {}{whose} has non-positive duration {}",
                    clip.id, clip.duration
                ));
            }
            if clip.start < 0 {
                return Err(format!(
                    "clip {}{whose} has negative start {}",
                    clip.id, clip.start
                ));
            }
            // Spelled as JSON spells it: `{}` writes 1e300 as 301 digits,
            // and a NaN fails the range too.
            if !(SPEED_MIN..=SPEED_MAX).contains(&clip.speed) {
                return Err(format!(
                    "clip {}{whose}'s speed {} is outside ×{SPEED_MIN}–×{SPEED_MAX}",
                    clip.id,
                    serde_json::Value::from(clip.speed)
                ));
            }
            // Only the media-bound sources name a media; a nest names a
            // nest, and the generated kinds name nothing.
            let referenced = match &clip.source {
                Source::Media { media, .. } => Some(*media),
                Source::Still { media, .. } => Some(*media),
                Source::Image { media } => Some(*media),
                Source::Text | Source::Shape | Source::Graphic | Source::Nest { .. } => None,
            };
            if let Some(media) = referenced {
                if self.is_missing_media(media) {
                    return Err(format!(
                        "clip {}{whose} refers to unknown media {}",
                        clip.id, media
                    ));
                }
            }
            // An absent description is tolerated as an absent `text` is
            // (spec §11 G-18(c)); a present one names a module, and a name
            // that could not be a file in `graphics/` is a corrupt clip (G-3).
            if let (Source::Graphic, Some(graphic)) = (&clip.source, &clip.graphic) {
                if check_name(&graphic.name).is_err() {
                    return Err(format!(
                        "clip {}{whose} has graphic name \"{}\", which {NAME_RULE}",
                        clip.id, graphic.name
                    ));
                }
            }
            if let Source::Nest { project } = &clip.source {
                if self.nest(*project).is_none() {
                    return Err(format!(
                        "clip {}{whose} refers to unknown nest {}",
                        clip.id, project
                    ));
                }
            }
            for action in &clip.actions {
                if action.duration <= 0 {
                    return Err(format!(
                        "action {} on clip {}{whose} has non-positive duration {}",
                        action.id, clip.id, action.duration
                    ));
                }
            }
        }
        Ok(())
    }

    /// Refuses a nest that contains itself at any remove, and a stack of
    /// nests deeper than [`format::MAX_NEST_DEPTH`].
    ///
    /// Both are the same walk. Every nest reachable from the timeline is
    /// visited, and then every nest that is NOT — an orphan is still part
    /// of the file, `unnest` can still put its contents back on the
    /// timeline, and a cycle hiding in one is a corrupt project whether or
    /// not anything points at it today.
    fn check_nesting(&self) -> Result<(), String> {
        let mut chain: Vec<u32> = Vec::new();
        let mut known: HashMap<u32, u32> = HashMap::new();
        for clip in &self.clips {
            if let Source::Nest { project } = &clip.source {
                self.nest_height(*project, 1, &mut chain, &mut known)?;
            }
        }
        for nest in &self.nests {
            if !known.contains_key(&nest.id) {
                self.nest_height(nest.id, 1, &mut chain, &mut known)?;
            }
        }
        Ok(())
    }

    /// How many levels of nest this one is the top of — 1 for a nest that
    /// contains no nests — given that it sits at `level` itself.
    ///
    /// `chain` is the path currently being walked, so a repeat in it is a
    /// cycle. `known` memoizes finished nests: without it a diamond (two
    /// clips in one nest showing the same nest) would be walked twice, and
    /// eight levels of that is exponential. A memoized nest is finished, so
    /// it can never be on `chain`, so the memo can never hide a cycle.
    ///
    /// Recursion is bounded by the depth cap, not by the number of nests:
    /// the check happens on the way DOWN, so a 4096-deep chain in a
    /// hand-written file is refused at level 9 rather than walked.
    fn nest_height(
        &self,
        id: u32,
        level: u32,
        chain: &mut Vec<u32>,
        known: &mut HashMap<u32, u32>,
    ) -> Result<u32, String> {
        let cap = format::MAX_NEST_DEPTH;
        if level > cap {
            return Err(format!("nests are more than {cap} deep at nest {id}"));
        }
        // An unknown nest is `check_clips`'s error to report, not this
        // walk's: reaching one here means it named a nest that is not in
        // `nests[]`, which that sweep has already refused.
        let Some(nest) = self.nest(id) else {
            return Ok(0);
        };
        if let Some(height) = known.get(&id).copied() {
            if level.saturating_add(height).saturating_sub(1) > cap {
                return Err(format!("nests are more than {cap} deep at nest {id}"));
            }
            return Ok(height);
        }
        if chain.contains(&id) {
            return Err(format!("nest {id} contains itself"));
        }
        chain.push(id);
        let mut tallest = 0;
        for child in nest.child_nests() {
            tallest = tallest.max(self.nest_height(child, level + 1, chain, known)?);
        }
        chain.pop();
        let height = tallest + 1;
        known.insert(id, height);
        Ok(height)
    }
}
