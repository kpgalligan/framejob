//! The per-clip property types of spec §5.2 — the `video`, `audio`, `text`
//! and `shape` groups a [`crate::model::Clip`] carries, and every struct
//! and enum inside them but three families, all re-exported below: the
//! region types, which are `model_regions.rs`'s, the text types, which are
//! `model_text.rs`'s, and the shape types, which are `model_shape.rs`'s.
//!
//! Split out of `model.rs` under the size rule (core/CLAUDE.md: a module
//! over ~600 lines gives something up before it takes anything on), and
//! split HERE because the property types are a concern of their own:
//! `model.rs` is the document's skeleton — project, media, tracks, clips,
//! nests, actions — while this file is what the four `set_*` patches in
//! `edit_props.rs` deep-merge into, what `actions.rs` interpolates, and
//! what the compositor's uniforms are read from. Reading one is reading the
//! schema's SHAPE; reading the other is reading its VOCABULARY.
//!
//! It has since paid the same rule THREE times itself, and every payment was
//! made before the phase that owed them took anything on. Road map 2's
//! phase 3c added `video.obscure` and its two types, which took the file to
//! 633 lines, so the boxes drawn ON the picture — [`Spotlight`],
//! [`ObscureRegion`], [`SpotShape`] and [`MAX_OBSCURE`] — went out to
//! `model_regions.rs` first; they share one coordinate frame and one shape
//! enum, which is the seam, and that module's doc states the frame. Phase 6
//! arrived at 592 owing `video.blend` and `shape.gradient`, so the text
//! vocabulary — [`TextProps`], [`TextAlign`], [`TextVAlign`], [`Outline`],
//! [`Backdrop`], [`TextAnimation`] and [`TextAnimationKind`] — went out to
//! `model_text.rs` in the same way. Its seam is the one property group the
//! model cannot MEASURE, because only the platform can lay text out; that
//! module's doc states it. Road map 5's E2 arrived AT 600 owing
//! `video.motion`, so the shape vocabulary — [`ShapeProps`], [`ShapeKind`],
//! [`Stroke`], [`Gradient`], [`GradientKind`], [`GradientStop`] and
//! [`MAX_GRADIENT_STOPS`] — went out to `model_shape.rs`, which is the
//! alternative phase 6 weighed and refused for lack of room. Its seam is
//! the text one read a second time: shape and text are the two sources the
//! model only DESCRIBES, drawn on the CPU and keyed by the recipe's content
//! hash, where everything left here is read straight into the compositor's
//! uniform block.
//!
//! Every path stays as it was, through all four cuts: `model.rs`
//! re-exports this whole module with `pub use crate::model_props::*` and
//! this module re-exports the other three the same way, so
//! `crate::model::VideoProps`, `crate::model::Spotlight`,
//! `crate::model::TextProps`, `crate::model::ShapeProps` and the crate-root
//! re-exports in `lib.rs` are all untouched. The rules are `model.rs`'s
//! too — the field names ARE the
//! JSON keys, declaration order IS key order, every type is
//! `#[serde(default)]` over a hand-written [`Default`] that says what an
//! absent key means, and nothing here carries `deny_unknown_fields`.

use serde::{Deserialize, Serialize};

use crate::model::Color;
use crate::time::{Ticks, TIMESCALE};

/// The region types — [`Spotlight`], [`ObscureRegion`], the [`SpotShape`]
/// both are drawn with and the [`MAX_OBSCURE`] budget on the second — live
/// in `model_regions.rs` and are re-exported whole, so every
/// `crate::model_props::Spotlight` path (and, through `model.rs`'s own
/// glob, every `crate::model::Spotlight` one) still resolves. See that
/// module's doc for the frame they share, which is why they are a file of
/// their own.
pub use crate::model_regions::*;

/// The text types — [`TextProps`], the [`TextAlign`] and [`TextVAlign`] it
/// is placed by, its optional [`Outline`] and [`Backdrop`], and the
/// [`TextAnimation`] and [`TextAnimationKind`] that reveal it — live in
/// `model_text.rs` and are re-exported whole, so every
/// `crate::model_props::TextProps` path (and, through `model.rs`'s own
/// glob, every `crate::model::TextProps` one) still resolves. See that
/// module's doc for the seam they share — text is the one group the model
/// cannot measure — which is why they are a file of their own.
pub use crate::model_text::*;

/// The word-caption types — [`TextCase`], [`Word`], [`WordMode`],
/// [`ActivePill`] and [`WordStyle`] — live in `model_words.rs` and are
/// re-exported whole, so every `crate::model_props::WordStyle` path (and,
/// through `model.rs`'s own glob, every `crate::model::WordStyle` one)
/// still resolves. See that module's doc for the seam: a word caption is a
/// text clip holding one page, and the core is the one counter of its
/// words. Its two `pub(crate)` functions are not widened by this glob.
pub use crate::model_words::*;

/// The shape types — [`ShapeProps`], the [`ShapeKind`] it draws, the
/// [`Stroke`] around it, and the [`Gradient`], [`GradientKind`],
/// [`GradientStop`] and [`MAX_GRADIENT_STOPS`] that fill it — live in
/// `model_shape.rs` and are re-exported whole, so every
/// `crate::model_props::ShapeProps` path (and, through `model.rs`'s own
/// glob, every `crate::model::ShapeProps` one) still resolves. See that
/// module's doc for the seam they share with the text types — shape and
/// text are the two CPU-rendered, hash-keyed sources — which is why they
/// are a file of their own.
pub use crate::model_shape::*;

/// The graphic types — [`GraphicProps`] and the [`GRAPHIC_MIN_SIDE`],
/// [`GRAPHIC_MAX_SIDE`] and [`GRAPHIC_MAX_PROPS`] bounds on it — live in
/// `model_graphic.rs` and are re-exported whole, so every
/// `crate::model_props::GraphicProps` path (and, through `model.rs`'s own
/// glob, every `crate::model::GraphicProps` one) still resolves. See that
/// module's doc for the seam: a graphic is a source the model only
/// describes and never reads, so its props are checked against a schema
/// the op carries. Its `pub(crate)` checks are not widened by this glob.
pub use crate::model_graphic::*;

/// The motion types — [`Motion`] and the [`MotionEdge`], [`MotionDuring`],
/// [`EdgeMotion`] and [`DuringMotion`] it is made of — live in
/// `model_motion.rs` and are re-exported whole, so every
/// `crate::model_props::Motion` path (and, through `model.rs`'s own glob,
/// every `crate::model::Motion` one) still resolves. See that module's doc
/// for the seam: motion is a PRESET and not a value, the one member of the
/// video group whose meaning is computed at render time rather than read.
pub use crate::model_motion::*;

/// The matte vocabulary — [`TrackMatte`], what a track's clips do to the
/// track directly behind it (format version 14, spec §11 MT-1) — lives in
/// `model_matte.rs` and is re-exported whole, so every
/// `crate::model::TrackMatte` path resolves. See that module's doc for why
/// its declaration order is a shader discriminant.
pub use crate::model_matte::*;

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
    /// Hidden regions, at most [`MAX_OBSCURE`] of them (format version 4).
    pub obscure: Vec<ObscureRegion>,
    /// How this layer combines with what is already on the canvas
    /// (format version 6). `Normal` is source-over, which is what every
    /// project drew before the key existed. It belongs to the LAYER, not to
    /// a source kind — media, image, still, text and shape all draw through
    /// one fragment stage — with the nest clip an op's refusal rather than
    /// a schema one (`edit_props.rs`'s `check_blend`).
    pub blend: BlendMode,
    /// What this layer DOES — an entrance, an exit, a continuous motion, or
    /// any two of the three (format version 8). `None` is a clip that sits
    /// where it is placed, which is what every project did before the key
    /// existed.
    ///
    /// Unlike every other field here it is not a quantity the compositor
    /// reads: `motion.rs` turns it into `scale`, `rotation`, `opacity`, `x`
    /// and `y` where `recipe.rs` produces PLACEMENT, and the recipe
    /// publishes no `motion` key at all. Everything that evaluates a clip
    /// rather than placing it — `clip_state`, `get_project`, the inspector,
    /// `split_clip`'s state, `add_zoom_action`, `freeze_frame`, the audio
    /// plan — therefore reads the clip UN-MOVED, which is what keeps an
    /// edit working on the numbers a person typed (spec §5.4, §7.3).
    pub motion: Option<Motion>,
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
            obscure: Vec::new(),
            blend: BlendMode::Normal,
            motion: None,
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

/// How a layer combines with what is already on the canvas (format version
/// 6, road map 2's phase 6) — what turns a shape clip into a tint, a glow
/// or a matte instead of a sticker. Eight modes: `Normal`, six separable
/// blends the fragment stage computes from one source and one destination
/// fragment, and `Add`, which is plus-lighter rather than a separable
/// blend at all. The formulas live once, in `Compositor.metal`'s
/// `blendPremultiplied`; nothing in the core computes a colour, it only
/// says WHICH (spec §7).
///
/// **Declaration order IS a contract.** It is the shader discriminant, the
/// way [`crate::model::ObscureKind`]'s is: `ProjectSnapshot.swift` derives
/// `shaderCode` from the case index and `Compositor.metal` compares against
/// integer constants in this order. A mode may be added at the END; the
/// eight here may never be reordered or removed. The JSON spelling of each
/// is persisted as well, so a rename needs a migration step.
///
/// `Normal` is 0 with no `+1` offset, unlike the filter and obscure
/// discriminants, where 0 is reserved for "empty slot". There is nothing to
/// reserve — a layer has exactly one blend mode — and reserving it would
/// cost the property that makes this field safe to add to a shipped schema:
/// a zeroed uniform block, a recipe emitted by an older core and a file
/// with no `blend` key must all render source-over, which is what every
/// project drew before the key existed. Three absences, one value, no code
/// in between.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BlendMode {
    #[default]
    Normal,
    Multiply,
    Screen,
    Add,
    Overlay,
    Darken,
    Lighten,
    Difference,
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
