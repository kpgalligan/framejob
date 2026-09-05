//! The project value — spec §5.2 — and the lookups every editing module
//! builds on.
//!
//! The struct field names ARE the JSON keys: this file is the schema, and
//! `serde_json::to_string_pretty` of a [`Project`] is exactly the
//! `project.json` inside a `.reelcut` package. Declaration order is the
//! serialized key order, so it follows the spec's example.
//!
//! Nothing here edits. Editing lives in `edit_clip.rs` / `edit_track.rs` /
//! `edit_time.rs`, each a separate `impl Project` block; this module owns
//! only the types, id allocation, the read-only lookups, and [`Project::validate`].
//!
//! Every optional field carries a serde default (usually a container-level
//! `#[serde(default)]` backed by the type's [`Default`]), so a project JSON
//! hand-written by a person or by the MCP agent parses with only the
//! required keys present. Required, and therefore defaultless: a clip's
//! `id`, `track`, `start`, `duration` and `source`; a media's `id`, `path`
//! and `kind`; a track's, marker's and action's `id`.
//!
//! **Unknown keys are IGNORED, at every level, and are gone from the next
//! write.** No type here carries `deny_unknown_fields`, deliberately: a
//! file from a NEWER build is already refused outright by the version gate
//! in [`crate::format::read`], so an unknown key inside a version this
//! build does understand is a typo or a third-party annotation, and neither
//! is worth refusing a whole project — and somebody's work — over. An
//! unknown `source.kind` is NOT an unknown key: it is the discriminant, so
//! it is a schema error. Strictness lives where a person just typed the
//! key: `add_media`'s descriptor and the `set_video` / `set_audio` /
//! `set_text` / `set_shape` patches all reject an unknown key by name. The
//! one place an unknown key SURVIVES a round trip is an [`Action`]'s `end`
//! patch, which is opaque [`serde_json::Value`] here, is evaluated
//! leniently by `actions.rs`, and is kept as written by `set_action_end`.

use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use crate::format::{self, RC_FORMAT_VERSION};
use crate::time::{Fps, Ticks};

/// Linear RGBA, each channel 0..1. Alpha is premultiplied by nothing — the
/// renderer decides.
pub type Color = [f64; 4];

// ---- project -------------------------------------------------------------

/// The whole document. Holds no pixels, no selection, no playhead and no
/// view state: those live in Swift (spec §5.2).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Project {
    #[serde(default = "default_version")]
    pub version: u32,
    #[serde(default)]
    pub canvas: Canvas,
    #[serde(default)]
    pub media: Vec<Media>,
    #[serde(default)]
    pub tracks: Vec<Track>,
    #[serde(default)]
    pub clips: Vec<Clip>,
    #[serde(default)]
    pub markers: Vec<Marker>,
    #[serde(default = "default_next_id")]
    pub next_id: u32,
}

/// The fixed canvas every clip is composited onto.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Canvas {
    pub width: u32,
    pub height: u32,
    pub fps: Fps,
    pub background: Color,
    /// Scale a new clip to fit when its source exceeds the canvas.
    pub fit_new_clips: bool,
    /// Display timecode as `HH:MM:SS:FF` rather than `HH:MM:SS.mmm`.
    pub timecode_frames: bool,
}

impl Default for Canvas {
    fn default() -> Self {
        Canvas {
            width: 1920,
            height: 1080,
            fps: Fps::default(),
            background: [0.0, 0.0, 0.0, 1.0],
            fit_new_clips: true,
            timecode_frames: true,
        }
    }
}

// ---- media ---------------------------------------------------------------

/// One file on disk the project references. Media is referenced, never
/// copied (spec §11); `bookmark` is the app's alias data for surviving a
/// move, base64 in the JSON.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Media {
    pub id: u32,
    pub path: String,
    #[serde(default)]
    pub bookmark: Option<String>,
    pub kind: MediaKind,
    #[serde(default)]
    pub duration: Ticks,
    #[serde(default)]
    pub width: u32,
    #[serde(default)]
    pub height: u32,
    #[serde(default)]
    pub fps: Fps,
    #[serde(default)]
    pub has_video: bool,
    #[serde(default)]
    pub has_audio: bool,
    #[serde(default)]
    pub has_alpha: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaKind {
    Video,
    Audio,
    Image,
}

// ---- tracks and markers --------------------------------------------------

/// One kind of track only (spec §2): any clip may live on any track, and
/// a later index in `Project::tracks` draws in front.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Track {
    pub id: u32,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub hidden: bool,
    #[serde(default)]
    pub muted: bool,
    /// Locked tracks are skipped by ripple, insert-time and hit-testing.
    #[serde(default)]
    pub locked: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Marker {
    pub id: u32,
    pub time: Ticks,
    #[serde(default)]
    pub name: String,
    #[serde(default = "default_marker_color")]
    pub color: String,
    /// Chapter markers become chapter tracks on export.
    #[serde(default)]
    pub chapter: bool,
}

// ---- clips ---------------------------------------------------------------

/// A span on a track showing one source. `duration` is timeline time, so a
/// 2x clip of a 10 s source has `duration` 5 s (spec §6, `set_speed`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Clip {
    pub id: u32,
    pub track: u32,
    pub start: Ticks,
    pub duration: Ticks,
    pub source: Source,
    #[serde(default)]
    pub enabled: Enabled,
    #[serde(default = "default_one")]
    pub speed: f64,
    #[serde(default)]
    pub video: Option<VideoProps>,
    #[serde(default)]
    pub audio: Option<AudioProps>,
    #[serde(default)]
    pub text: Option<TextProps>,
    #[serde(default)]
    pub shape: Option<ShapeProps>,
    #[serde(default)]
    pub actions: Vec<Action>,
    /// The transition covering this clip's overlap with its predecessor on
    /// the same track. Its duration IS that overlap; with no overlap it is
    /// ignored (spec §5.2).
    #[serde(default)]
    pub transition_in: Option<Transition>,
}

/// What a clip shows. `media` is the only kind with a source bound —
/// `still`, `image`, `text` and `shape` may have any duration; `nest` is
/// M3 and is parsed and round-tripped only.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Source {
    Media {
        media: u32,
        /// Source time of the clip's first frame.
        #[serde(rename = "in")]
        r#in: Ticks,
    },
    Still {
        media: u32,
        /// The source time the frozen frame is taken from.
        at: Ticks,
    },
    Image {
        media: u32,
    },
    Text,
    Shape,
    Nest {
        project: String,
    },
}

/// Per-clip video/audio enablement. Detach Audio flips these across two
/// clips (spec §6).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct Enabled {
    pub video: bool,
    pub audio: bool,
}

impl Default for Enabled {
    fn default() -> Self {
        Enabled {
            video: true,
            audio: true,
        }
    }
}

// ---- video properties ----------------------------------------------------

/// Placement on the canvas plus the per-clip image controls. `x`/`y` are an
/// offset of the layer's center from the canvas center, in canvas pixels;
/// `scale` 1 is native pixels (spec §5.3).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct VideoProps {
    pub x: f64,
    pub y: f64,
    pub scale: f64,
    /// Degrees, about the layer center.
    pub rotation: f64,
    pub opacity: f64,
    pub crop: Crop,
    /// Source pixels, applied to the cropped rect before rotation.
    pub corner_radius: f64,
    pub shadow: Option<Shadow>,
    pub color: ColorAdjust,
    pub chroma: Option<Chroma>,
}

impl Default for VideoProps {
    fn default() -> Self {
        VideoProps {
            x: 0.0,
            y: 0.0,
            scale: 1.0,
            rotation: 0.0,
            opacity: 1.0,
            crop: Crop::default(),
            corner_radius: 0.0,
            shadow: None,
            color: ColorAdjust::default(),
            chroma: None,
        }
    }
}

/// Edges removed IN PLACE, in source pixels — cropping never shifts the
/// content (a screencast editor's behaviour, spec §5.3).
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Crop {
    pub l: f64,
    pub t: f64,
    pub r: f64,
    pub b: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Shadow {
    pub color: Color,
    pub opacity: f64,
    pub blur: f64,
    /// Degrees, 0 = to the right, increasing counter-clockwise.
    pub angle: f64,
    pub distance: f64,
}

impl Default for Shadow {
    /// The spec §5.2 example's shadow: a soft drop shadow down-and-right.
    fn default() -> Self {
        Shadow {
            color: [0.0, 0.0, 0.0, 1.0],
            opacity: 0.5,
            blur: 12.0,
            angle: 315.0,
            distance: 8.0,
        }
    }
}

/// All four are offsets from neutral: 0 changes nothing, which is why the
/// derived `Default` is correct here.
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct ColorAdjust {
    pub brightness: f64,
    pub contrast: f64,
    pub saturation: f64,
    pub hue: f64,
}

/// Chroma key (M3). `key` is the RGB being removed.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Chroma {
    pub key: [f64; 3],
    pub tolerance: f64,
    pub softness: f64,
    pub spill: f64,
}

impl Default for Chroma {
    /// Green screen, with the spec §5.2 example's tolerances.
    fn default() -> Self {
        Chroma {
            key: [0.0, 1.0, 0.0],
            tolerance: 0.2,
            softness: 0.1,
            spill: 0.5,
        }
    }
}

// ---- audio properties ----------------------------------------------------

/// `volume` is a linear gain and may exceed 1, up to 4 (spec §5.2).
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct AudioProps {
    pub volume: f64,
    pub muted: bool,
    pub fade_in: Ticks,
    pub fade_out: Ticks,
    pub duck: Option<Duck>,
    pub mono: bool,
    /// Preserve pitch when the clip's speed is not 1.
    pub keep_pitch: bool,
}

impl Default for AudioProps {
    fn default() -> Self {
        AudioProps {
            volume: 1.0,
            muted: false,
            fade_in: 0,
            fade_out: 0,
            duck: None,
            mono: false,
            keep_pitch: true,
        }
    }
}

/// Ducking is by clip extent, not voice activity (spec §11): every other
/// clip's envelope is multiplied by `level` over this clip's extent, with
/// linear `attack` and `release` ramps.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Duck {
    pub level: f64,
    pub attack: Ticks,
    pub release: Ticks,
}

impl Default for Duck {
    /// The spec §5.2 example: down to 20 %, 0.5 s in, 1 s out.
    fn default() -> Self {
        Duck {
            level: 0.2,
            attack: 300_000,
            release: 600_000,
        }
    }
}

// ---- text ----------------------------------------------------------------

/// A text layer's description. The model never stores a measured size —
/// only the platform can lay text out, and it reports the size back to the
/// overlay through a cache (spec §5.3, §11).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct TextProps {
    pub content: String,
    pub font: String,
    pub size: f64,
    pub color: Color,
    pub align: TextAlign,
    pub valign: TextVAlign,
    /// Multiplier on the font's natural line height.
    pub line_spacing: f64,
    /// Extra letter spacing, in points.
    pub tracking: f64,
    pub outline: Option<Outline>,
    pub backdrop: Option<Backdrop>,
    /// Wrapping width in canvas pixels; `None` lays out on one line.
    pub width: Option<f64>,
}

impl Default for TextProps {
    /// The Title preset: white, centered, at the spec's example font.
    fn default() -> Self {
        TextProps {
            content: String::new(),
            font: "SourceSans3-SemiBold".to_string(),
            size: 72.0,
            color: [1.0, 1.0, 1.0, 1.0],
            align: TextAlign::Center,
            valign: TextVAlign::Middle,
            line_spacing: 1.0,
            tracking: 0.0,
            outline: None,
            backdrop: None,
            width: None,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TextAlign {
    Left,
    #[default]
    Center,
    Right,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TextVAlign {
    Top,
    #[default]
    Middle,
    Bottom,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Outline {
    pub width: f64,
    pub color: Color,
}

impl Default for Outline {
    fn default() -> Self {
        Outline {
            width: 2.0,
            color: [0.0, 0.0, 0.0, 1.0],
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Backdrop {
    pub color: Color,
    pub padding: f64,
    pub radius: f64,
}

impl Default for Backdrop {
    /// A translucent black plate — the readable default behind white text.
    fn default() -> Self {
        Backdrop {
            color: [0.0, 0.0, 0.0, 0.6],
            padding: 12.0,
            radius: 8.0,
        }
    }
}

// ---- shapes --------------------------------------------------------------

/// A shape layer. A rounded rectangle is [`ShapeKind::Rectangle`] with a
/// non-zero `radius`; `from`/`to` are unit coordinates inside the box and
/// apply to lines and arrows only (spec §5.2).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct ShapeProps {
    pub kind: ShapeKind,
    pub width: f64,
    pub height: f64,
    pub stroke: Option<Stroke>,
    pub fill: Option<Color>,
    pub arrow_start: bool,
    pub arrow_end: bool,
    pub radius: f64,
    pub from: [f64; 2],
    pub to: [f64; 2],
}

impl Default for ShapeProps {
    /// The spec §5.2 example's box, stroked and unfilled so a newly added
    /// shape is visible over any footage.
    fn default() -> Self {
        ShapeProps {
            kind: ShapeKind::Rectangle,
            width: 320.0,
            height: 120.0,
            stroke: Some(Stroke::default()),
            fill: None,
            arrow_start: false,
            arrow_end: false,
            radius: 0.0,
            from: [0.0, 1.0],
            to: [1.0, 0.0],
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShapeKind {
    #[default]
    Rectangle,
    Ellipse,
    Line,
    Arrow,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Stroke {
    pub width: f64,
    pub color: Color,
}

impl Default for Stroke {
    fn default() -> Self {
        Stroke {
            width: 6.0,
            color: [1.0, 1.0, 1.0, 1.0],
        }
    }
}

// ---- actions and transitions ---------------------------------------------

/// A span on a clip, in CLIP time, whose `end` patch is the state to reach
/// by its end (spec §5.4). The patch is opaque JSON here — `actions.rs`
/// interprets it against the clip's `video` / `audio` / `text` props — so
/// this module stays free of interpolation logic.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Action {
    pub id: u32,
    pub start: Ticks,
    pub duration: Ticks,
    #[serde(default)]
    pub curve: Curve,
    #[serde(default = "empty_patch")]
    pub end: serde_json::Value,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Curve {
    #[default]
    Linear,
    EaseIn,
    EaseOut,
    EaseInOut,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Transition {
    pub kind: TransitionKind,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransitionKind {
    #[default]
    CrossDissolve,
    FadeBlack,
    FadeWhite,
    PushLeft,
    PushRight,
    PushUp,
    PushDown,
    Wipe,
    Slide,
    Zoom,
}

// ---- serde defaults ------------------------------------------------------

fn default_version() -> u32 {
    RC_FORMAT_VERSION
}

/// Ids start at 1 so 0 can mean "none" on the Swift side.
fn default_next_id() -> u32 {
    1
}

fn default_one() -> f64 {
    1.0
}

/// The colour a marker has when nothing says otherwise, matching the
/// spec §5.2 example. It is a palette NAME the UI resolves to a swatch, not
/// a hex triple, so the core stores whatever string it is given and never
/// validates it: a build that policed the list would reject a project
/// written by a newer one.
///
/// One home for it, here, next to the serde default: `add_marker` uses the
/// same constant, so a marker created by an op and a marker read from a
/// file that omitted the key are the same colour.
pub const DEFAULT_MARKER_COLOR: &str = "red";

fn default_marker_color() -> String {
    DEFAULT_MARKER_COLOR.to_string()
}

fn empty_patch() -> serde_json::Value {
    serde_json::Value::Object(serde_json::Map::new())
}

// ---- lookups and invariants ----------------------------------------------

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
            }],
            clips: Vec::new(),
            markers: Vec::new(),
            next_id: 2,
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
        let mut clips: Vec<&Clip> = self.clips.iter().filter(|c| c.track == track).collect();
        clips.sort_by_key(|c| (c.start, c.id));
        clips
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

    /// The longest timeline duration `clip` could have: the media's
    /// remaining source length from its in point, divided by `speed` (at 2x
    /// a 10 s remainder fills 5 s of timeline). Floored, so a clip can
    /// never outrun its source by a partial frame.
    ///
    /// `None` for a source with no source bound — `still`, `image`, `text`,
    /// `shape` and `nest` may have ANY duration — and for an unknown media
    /// or a speed that is not a positive finite number.
    pub fn source_length(&self, clip: &Clip) -> Option<Ticks> {
        let (media_id, source_in) = match &clip.source {
            Source::Media { media, r#in } => (*media, *r#in),
            _ => return None,
        };
        let media = self.media(media_id)?;
        if !(clip.speed.is_finite() && clip.speed > 0.0) {
            return None;
        }
        let remaining = media.duration.saturating_sub(source_in).max(0);
        Some((remaining as f64 / clip.speed).floor() as Ticks)
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
    /// media, tracks, clips, actions and markers, then per-clip references
    /// and durations, then `next_id`.
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

        for clip in &self.clips {
            if self.track(clip.track).is_none() {
                return Err(format!(
                    "clip {} is on unknown track {}",
                    clip.id, clip.track
                ));
            }
            if clip.duration <= 0 {
                return Err(format!(
                    "clip {} has non-positive duration {}",
                    clip.id, clip.duration
                ));
            }
            if clip.start < 0 {
                return Err(format!(
                    "clip {} has negative start {}",
                    clip.id, clip.start
                ));
            }
            // Only the media-bound sources name a media; nest is M3 and
            // carries a path, not an id.
            let referenced = match &clip.source {
                Source::Media { media, .. } => Some(*media),
                Source::Still { media, .. } => Some(*media),
                Source::Image { media } => Some(*media),
                Source::Text | Source::Shape | Source::Nest { .. } => None,
            };
            if let Some(media) = referenced {
                if self.is_missing_media(media) {
                    return Err(format!(
                        "clip {} refers to unknown media {}",
                        clip.id, media
                    ));
                }
            }
            for action in &clip.actions {
                if action.duration <= 0 {
                    return Err(format!(
                        "action {} on clip {} has non-positive duration {}",
                        action.id, clip.id, action.duration
                    ));
                }
            }
        }

        if self.next_id <= max_id {
            return Err(format!(
                "next_id {} is not greater than id {}",
                self.next_id, max_id
            ));
        }
        Ok(())
    }
}
