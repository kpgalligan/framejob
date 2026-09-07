//! The project value — spec §5.2 — and the lookups every editing module
//! builds on.
//!
//! The struct field names ARE the JSON keys: this file is the schema, and
//! `serde_json::to_string_pretty` of a [`Project`] is exactly the
//! `project.json` inside a `.reelcut` package. Declaration order is the
//! serialized key order, so it follows the spec's example.
//!
//! Nothing here edits, and nothing here reads: editing lives in
//! `edit_clip.rs` / `edit_track.rs` / `edit_time.rs`, each a separate
//! `impl Project` block, and construction, the id lookups and
//! [`Project::validate`] live in `model_query.rs`. This module owns the
//! types and the serde defaults that say what an absent key means — one
//! file, so that reading it top to bottom is reading the schema.
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

use serde::{Deserialize, Serialize};

use crate::format::RC_FORMAT_VERSION;
use crate::time::{Fps, Ticks, TIMESCALE};

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
    /// The groups every `source.kind = "nest"` clip points at (format
    /// version 2). Appended after `next_id` rather than filed next to
    /// `clips` because declaration order IS key order: a version-1 file
    /// diffed against a version-2 one differs by a trailing key, not by a
    /// re-ordering of everything after `clips`.
    #[serde(default)]
    pub nests: Vec<Nest>,
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
/// `still`, `image`, `text`, `shape` and `nest` may have any duration.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Source {
    Media {
        media: u32,
        /// Source time of the clip's first frame.
        #[serde(rename = "in")]
        r#in: Ticks,
        /// Play the media back to front.
        ///
        /// The core does no pixel work, so this is a FACT about the clip,
        /// not an instruction: it changes neither the plan nor the recipe.
        /// Swift resolves it by substituting a pre-rendered reversed asset
        /// for this media's segments (spec §11 — "reverse is not native;
        /// M3 pre-renders reversed segments").
        ///
        /// `in` is then measured in that REVERSED stream, which has the
        /// same duration as the forward one — so an `in` of 0 is the
        /// media's last frame, and every time computation in this crate
        /// (trimming, splitting, `source_length`) stays correct with no
        /// case for it. That is the whole reason for the convention: the
        /// alternative, a forward-source in point, would make advancing
        /// `in` on a split run the wrong way.
        #[serde(default)]
        reversed: bool,
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
        /// The [`Nest`] this clip shows, by id, in the project's `nests[]`.
        ///
        /// A NUMBER, not the path this key held in format version 1. The
        /// core has no filesystem, so a path was a reference it could never
        /// resolve — `evaluate.rs` could only filter such a clip out — and
        /// Swift has decoded this key as a `UInt32` since M1
        /// (`ProjectSnapshot.swift`), leniently swallowing the type
        /// mismatch to 0, so a nest clip silently lost its identity every
        /// time it crossed the FFI. Version 2 makes the two sides agree;
        /// `format::read` migrates a version-1 path into a named, empty
        /// nest so the clip keeps its place on the timeline.
        project: u32,
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

// ---- nests ---------------------------------------------------------------

/// A group of tracks and clips that the parent timeline shows as ONE clip
/// (spec §5.2, `source.kind = "nest"`).
///
/// **A nest is not a nested [`Project`].** It holds its tracks and clips in
/// the PARENT's one id number space, it references the parent's `media[]`,
/// and its times are measured from its own start. The recursive shape looks
/// tidier and is a trap: the composition plan keys a clip's video track by
/// clip id, every segment names a media id the app resolves through the
/// outer `media[]`, and `next_id` is a single counter — so a second id
/// space would force every inner id to be re-minted on the way out, in
/// three places, on every evaluation. One id space makes all three work
/// unchanged, keeps [`Project::validate`]'s uniqueness sweep a straight
/// extension rather than a recursion, and keeps a nested clip nameable by
/// one integer over MCP exactly like every other object.
///
/// A nest's own duration is the largest clip end inside it
/// ([`Nest::duration`]). The nest CLIP's duration is independent of that:
/// it is trimmed like any other clip, and it may be shorter (the tail is
/// cut) or longer (the surplus draws nothing).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Nest {
    pub id: u32,
    #[serde(default)]
    pub name: String,
    /// The nest's own canvas, frozen at the size the parent had when the
    /// nest was made. Deliberately NOT read from the parent at evaluation
    /// time: a later `set_canvas` would otherwise silently re-lay-out every
    /// nest in the project, moving content the user never touched.
    #[serde(default = "default_canvas_width")]
    pub width: u32,
    #[serde(default = "default_canvas_height")]
    pub height: u32,
    /// Index 0 is the BACK of the nest's own stack, as everywhere else.
    #[serde(default)]
    pub tracks: Vec<Track>,
    /// Times are relative to the nest, so its earliest clip starts at 0.
    #[serde(default)]
    pub clips: Vec<Clip>,
}

impl Nest {
    /// End of the last clip inside; 0 when the nest is empty. This is what
    /// a nest clip's duration is measured against — never the parent's.
    pub fn duration(&self) -> Ticks {
        self.clips
            .iter()
            .map(|c| c.start.saturating_add(c.duration))
            .max()
            .unwrap_or(0)
            .max(0)
    }

    /// The nests this one shows directly, by id, in clip order — the edge
    /// list [`Project::validate`] walks for cycles and for depth.
    pub fn child_nests(&self) -> Vec<u32> {
        self.clips
            .iter()
            .filter_map(|c| match &c.source {
                Source::Nest { project } => Some(*project),
                _ => None,
            })
            .collect()
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
    /// Applied in the listed order, at most [`MAX_FILTERS`] of them.
    pub filters: Vec<Filter>,
    pub reflection: Option<Reflection>,
    pub spotlight: Option<Spotlight>,
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
            filters: Vec::new(),
            reflection: None,
            spotlight: None,
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

/// The most filters one layer may carry.
///
/// A SHADER BUDGET, not taste: the compositor's uniform block carries four
/// `(kind, amount)` pairs and the fragment shader applies them in a fixed
/// unrolled order, so a fifth filter has nowhere to go. `set_video` names
/// the overflow rather than dropping it — a silently ignored filter is a
/// user staring at a control that does nothing.
pub const MAX_FILTERS: usize = 4;

/// One image filter and how much of it (M3). Order matters: filters are
/// applied in the order they appear in `video.filters`, so blur-then-sepia
/// and sepia-then-blur are different pictures.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Filter {
    pub kind: FilterKind,
    /// 0 = the filter is present but does nothing, 1 = its full effect.
    pub amount: f64,
}

impl Default for Filter {
    /// Half-strength blur: the value a newly added filter takes, chosen so
    /// adding one from the inspector visibly does something without
    /// destroying the frame.
    fn default() -> Self {
        Filter {
            kind: FilterKind::Blur,
            amount: 0.5,
        }
    }
}

/// The filter set of spec §4.2. Deliberately closed and small: every one is
/// a handful of lines in `Compositor.metal`'s single pass (spec §7.5), and
/// a filter that needs its own render target is not one of these.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FilterKind {
    #[default]
    Blur,
    Sharpen,
    Pixelate,
    Sepia,
    Noir,
    Vignette,
    Invert,
}

/// A mirrored copy of the layer drawn below it, fading out (M3).
///
/// `height` and `falloff` are fractions rather than pixels so a reflection
/// survives a scale change: half the layer, however big the layer is.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Reflection {
    /// Opacity of the reflection where it touches the layer.
    pub opacity: f64,
    /// How much of the layer is mirrored, as a fraction of its CROPPED
    /// height.
    pub height: f64,
    /// Source pixels between the layer's bottom edge and the reflection.
    pub gap: f64,
    /// How fast the mirrored copy fades out: 0 does not fade at all, 1
    /// reaches transparent exactly at `height`.
    pub falloff: f64,
}

impl Default for Reflection {
    /// The glassy shelf: a dim half-height mirror hard against the layer.
    fn default() -> Self {
        Reflection {
            opacity: 0.35,
            height: 0.5,
            gap: 0.0,
            falloff: 1.0,
        }
    }
}

/// Darkens the canvas outside a rectangle or ellipse, optionally magnifying
/// what is inside it (spec §4.2, M3) — the stand-in for a screencast editor's
/// freehand callout that works on any footage.
///
/// A `video` prop, not a `shape` one, though spec §4.2 first listed it
/// under Shape: the zoom half can only be drawn by the layer that owns the
/// pixels, so it lives beside chroma key, filters and reflection.
///
/// The centre and the box are SOURCE pixels measured from the centre of the
/// layer's cropped rect — the same frame `corner_radius` and `crop` use —
/// so a spotlight stays on the face it was put on when the layer is scaled,
/// moved or rotated.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Spotlight {
    pub shape: SpotShape,
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    /// Source pixels the edge is blurred over; 0 is a hard edge.
    pub feather: f64,
    /// How much darker everything OUTSIDE is: 0 changes nothing, 1 is
    /// black.
    pub dim: f64,
    /// Magnification INSIDE the region. 1 is no zoom, which is why the
    /// range starts there and not at 0.
    pub zoom: f64,
}

impl Default for Spotlight {
    /// A 480 × 270 window — a 16:9 quarter of a 1080p source — centred, at
    /// the spec's "darkens the canvas outside" with no zoom.
    fn default() -> Self {
        Spotlight {
            shape: SpotShape::Rect,
            x: 0.0,
            y: 0.0,
            width: 480.0,
            height: 270.0,
            feather: 40.0,
            dim: 0.6,
            zoom: 1.0,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpotShape {
    #[default]
    Rect,
    Ellipse,
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
    /// -1 hard left, 0 centred, +1 hard right.
    pub pan: f64,
    pub compressor: Option<Compressor>,
    /// How much background noise to remove: 0 is off, 1 the most the
    /// platform will do.
    pub noise_reduction: f64,
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
            pan: 0.0,
            compressor: None,
            noise_reduction: 0.0,
        }
    }
}

/// "Smooth volume levels" (spec §4.3): a downward compressor over the
/// clip's own samples.
///
/// Unlike [`Duck`], which the core resolves into ramps on OTHER clips'
/// envelopes, this one cannot be expressed as a gain curve — it depends on
/// the samples — so the model carries the parameters and the DSP happens on
/// the Swift side. The units are the ones an audio engineer types:
/// dBFS for the threshold and the makeup, a plain ratio for the knee, and
/// ticks for the two time constants like every other time in the schema.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Compressor {
    /// dBFS above which gain reduction starts.
    pub threshold_db: f64,
    /// N:1 — 1 is no compression at all, 20 is effectively a limiter.
    pub ratio: f64,
    pub attack: Ticks,
    pub release: Ticks,
    /// dB of gain applied after compression, to win back what it took.
    pub makeup_db: f64,
}

impl Default for Compressor {
    /// A gentle speech setting: 3:1 above -18 dBFS, fast enough to catch a
    /// consonant (10 ms) and slow enough not to pump (200 ms).
    fn default() -> Self {
        Compressor {
            threshold_db: -18.0,
            ratio: 3.0,
            attack: TIMESCALE / 100,
            release: TIMESCALE / 5,
            makeup_db: 0.0,
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

/// A [`Nest`]'s canvas when the file does not say. The same 1080p
/// [`Canvas::default`] gives, and for the same reason: a size a nest can be
/// laid out against is better than a zero one `validate` would have to
/// refuse, and a nest written without a canvas came from a hand edit.
fn default_canvas_width() -> u32 {
    Canvas::default().width
}

fn default_canvas_height() -> u32 {
    Canvas::default().height
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
