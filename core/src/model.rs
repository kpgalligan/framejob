//! The project value — spec §5.2 — and the lookups every editing module
//! builds on.
//!
//! The struct field names ARE the JSON keys: this file is the schema, and
//! `serde_json::to_string_pretty` of a [`Project`] is exactly the
//! `project.json` inside a `.framejob` package. Declaration order is the
//! serialized key order, so it follows the spec's example.
//!
//! Nothing here edits, and nothing here reads: editing lives in
//! `edit_clip.rs` / `edit_track.rs` / `edit_time.rs`, each a separate
//! `impl Project` block, and construction, the id lookups and
//! [`Project::validate`] live in `model_query.rs`. This module owns the
//! document's types and the serde defaults that say what an absent key
//! means, so that reading it top to bottom is reading the schema's shape;
//! the per-clip property groups (`VideoProps` and its friends) are
//! `model_props.rs`, re-exported here whole, so that reading THAT is
//! reading the schema's vocabulary.
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
//! patch, which is opaque [`serde_json::Value`] here and is evaluated
//! leniently by `actions.rs`. That is the READER's doing and only the
//! reader's: `set_action_end` refuses an unknown key by its path like every
//! other patch op (`edit_action.rs`), so strictness at the op never costs a
//! file a newer build wrote.

use serde::{Deserialize, Serialize};

use crate::format::RC_FORMAT_VERSION;
use crate::time::{Fps, Ticks};

/// The per-clip property types live in `model_props.rs` and are re-exported
/// whole, so every `crate::model::VideoProps` path written before the split
/// still resolves — see that module's doc for why they are a file of their
/// own.
pub use crate::model_props::*;

/// Camera log's vocabulary (format version 19, spec §11 GR-16), a file of
/// its own for the reason `model_props.rs` is.
pub use crate::model_media_color::{CameraGamut, LogCurve, MediaColor};

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
    /// The project's dynamic range (format version 23, spec §11 HD-2,
    /// HD-13): `sdr` composes in Rec. 709, `hlg` in HLG-encoded BT.2020.
    /// Written only when `hlg`, so an SDR project and every older file
    /// round-trip byte for byte.
    #[serde(skip_serializing_if = "CanvasOutput::is_sdr")]
    pub output: CanvasOutput,
}

/// A canvas's dynamic range (spec §11 HD-2): `Sdr`, the default, or `Hlg`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CanvasOutput {
    #[default]
    Sdr,
    Hlg,
}

impl CanvasOutput {
    /// Whether this is an SDR canvas: the `skip_serializing_if` on
    /// `Canvas.output`, so an SDR project writes no key.
    pub fn is_sdr(&self) -> bool {
        *self == CanvasOutput::Sdr
    }
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
            output: CanvasOutput::Sdr,
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
    #[serde(default)]
    pub original: Option<MediaOriginal>,
    /// Camera log (format version 19, spec §11 GR-16): a video media's log
    /// curve and gamut, or the `lut` media converting it, at step 0. Written
    /// only when set, so a media with none writes the text it did.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color: Option<MediaColor>,
}

/// The file a playable copy was made from (format version 11, spec §11
/// #228-O): a WebM or Matroska file the app copied into a `.mov`. `path`
/// and `bookmark` above are the copy's; these are the original's, which is
/// what the app names, reveals and copies again when the copy is gone.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MediaOriginal {
    pub path: String,
    #[serde(default)]
    pub bookmark: Option<String>,
}

/// What a media file is. `Lut` is a `.cube` 3D LUT (spec §11 GR-8): media
/// so it is referenced, relinked and consolidated like footage, but never
/// placed as a clip — it is drawn only as a clip's `video.look`, and its row
/// carries no video, audio, alpha or duration (`lut.rs`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaKind {
    Video,
    Audio,
    Image,
    Lut,
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
    /// Solo (format version 3): while ANY track in this container — the
    /// timeline, or one nest's own tracks — is soloed, every track that is
    /// not is silent, and a track that is both muted and soloed stays
    /// silent, because mute wins. Audio only: a solo hides nothing, and it
    /// is applied as a gain envelope in `audio.rs`, never in the plan.
    #[serde(default)]
    pub solo: bool,
    /// Matte (format version 14, spec §11 MT-1): `none` is an ordinary
    /// track; any other mode makes the track's clips draw nothing on the
    /// canvas and cut the track directly behind (MT-2, MT-3). Written only
    /// when not `none` — this file's one `skip_serializing_if`, the model's
    /// first (tone's nine keys in `model_props.rs` are the rest) — so an
    /// ordinary track and every older file round-trip byte for byte.
    #[serde(default, skip_serializing_if = "TrackMatte::is_none")]
    pub matte: TrackMatte,
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
    /// What a graphic clip draws (format version 10): which module, at
    /// what size, over which stretch of its own timeline, with which props.
    #[serde(default)]
    pub graphic: Option<GraphicProps>,
    #[serde(default)]
    pub actions: Vec<Action>,
    /// The transition covering this clip's overlap with its predecessor on
    /// the same track. Its duration IS that overlap; with no overlap it is
    /// ignored (spec §5.2).
    #[serde(default)]
    pub transition_in: Option<Transition>,
    /// The clip's own name (format version 3). `None` is the common case
    /// and means "call it what it shows": the app falls back to the nest's
    /// or the media's name, then to the kind. `set_clip` stores it trimmed;
    /// the schema itself keeps whatever it is given.
    #[serde(default)]
    pub name: Option<String>,
    /// A colour label, or `None` for none (format version 3). A palette
    /// NAME the UI resolves to a swatch — the marker vocabulary: red,
    /// orange, yellow, green, blue, purple — and, exactly like
    /// [`Marker::color`], never validated here: a build that policed the
    /// list would refuse a project written by a newer one.
    #[serde(default)]
    pub label: Option<String>,
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
    /// Drawn by a JavaScript module in the package (format version 10);
    /// described by [`Clip::graphic`].
    Graphic,
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
    /// No picture of its own: grades what is drawn behind it in its
    /// container (spec §11 GR-6, `edit_adjustment.rs`).
    Adjustment,
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

/// The transition covering an overlap — which one, how its progress is
/// eased, and whether the two clips' sound crosses over with the picture.
///
/// The DERIVED default is the FILE default: `cross_dissolve`, `linear`,
/// `audio: false`. That is what a version-6 project's `{"kind": "wipe"}`
/// reads as and what an overlap carrying no `transition_in` at all draws,
/// so a project made before version 7 sounds and looks exactly as it did.
/// It is deliberately NOT what a transition the CORE mints looks like —
/// [`Transition::minted`] is that, and spec §11's R5-2 says why the two
/// differ.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Transition {
    pub kind: TransitionKind,
    pub curve: Curve,
    pub audio: bool,
}

impl Transition {
    /// A transition the core is MINTING now — from `add_transition`, from
    /// `set_transition` on a clip that had none, from
    /// `set_gained_transitions` when a clip gains an overlap (spec §11,
    /// R5-2): eased at both ends, and crossfading its sound.
    ///
    /// The one place those two values are written, so "what a new
    /// transition is" is a single fact rather than a habit spread over
    /// a dozen call sites.
    pub fn minted(kind: TransitionKind) -> Transition {
        Transition {
            kind,
            curve: Curve::EaseInOut,
            audio: true,
        }
    }
}

/// The transitions the compositor can draw. `wipe` keeps its name and its
/// meaning — the edge travels rightward — and the three directions appended
/// at version 7 are the other ways it can travel. Appended rather than
/// interleaved, because the JSON spelling of a variant is the wire format
/// and a reorder is a migration; the declaration ORDER itself is not a
/// shader discriminant (`Compositor.swift` maps each name to a code and a
/// direction vector by hand), unlike `BlendMode`'s and `ObscureKind`'s.
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
    WipeLeft,
    WipeUp,
    WipeDown,
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
