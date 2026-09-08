//! The per-clip property types of spec §5.2 — the `video`, `audio`, `text`
//! and `shape` groups a [`crate::model::Clip`] carries, and every struct
//! and enum inside them but the region types, which are
//! `model_regions.rs`'s and are re-exported below.
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
//! It has since paid the same rule once itself: road map 2's phase 3c added
//! `video.obscure` and its two types, which took the file to 633 lines, so
//! the boxes drawn ON the picture — [`Spotlight`], [`ObscureRegion`],
//! [`SpotShape`] and [`MAX_OBSCURE`] — went out to `model_regions.rs`
//! before the phase took anything else on. They share one coordinate frame
//! and one shape enum, which is the seam; that module's doc states the
//! frame.
//!
//! Every path stays as it was, through both cuts: `model.rs` re-exports
//! this whole module with `pub use crate::model_props::*` and this module
//! re-exports `model_regions.rs` the same way, so `crate::model::VideoProps`,
//! `crate::model::Spotlight` and the crate-root re-exports in `lib.rs` are
//! all untouched. The rules are `model.rs`'s too — the field names ARE the
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
    /// How the words arrive and how they leave, or `None` for text that is
    /// simply there for the length of its clip (format version 5).
    pub animation: Option<TextAnimation>,
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
            animation: None,
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

/// How a text layer arrives and how it leaves (format version 5, road map
/// 2's phase 4c).
///
/// Three keys and no fourth. `in` and `out` are DURATIONS, not times: the
/// reveal runs for `in` from the clip's own first frame, and the un-reveal
/// for `out` back from its own last one — the clip's, never the instance's,
/// which is the rule `recipe.rs` already states for clip time, so a nest
/// clip's edge cuts a nested caption off mid-reveal rather than making it
/// un-reveal early. Either may be 0, meaning that end of the animation
/// simply does not happen.
///
/// There is deliberately no curve field. The shape of the motion is
/// already in the kind — a typewriter's step per character, a word fade's
/// stagger, a line rise's per-line offset — and easing between two
/// arbitrary values is what the action system is for (spec §5.4). A curve
/// can be added later as a defaulted fourth key with no migration step,
/// which is the test this crate applies to leaving a field out.
///
/// Nothing here is a measurement of pixels or of time inside the reveal:
/// the model says what the animation IS, `recipe.rs` turns it into one
/// number per frame, and the platform draws it (spec §7). That is also why
/// the discriminant is called `kind` and not, say, `style`:
/// `actions.rs`'s object rule holds two objects that both name a DIFFERING
/// `kind` until the interpolation is over, so an action that moves a clip
/// from a typewriter to a line rise switches at the end instead of
/// interpolating an `in` between two animations that do not measure the
/// same thing.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct TextAnimation {
    pub kind: TextAnimationKind,
    /// How long the reveal takes, from the clip's first frame.
    #[serde(rename = "in")]
    pub r#in: Ticks,
    /// How long the un-reveal takes, measured back from the clip's last
    /// frame.
    pub out: Ticks,
}

impl Default for TextAnimation {
    /// A one-second typewriter that does not un-reveal — the animation a
    /// user gets for switching the section on and saying nothing else.
    ///
    /// The kind is the typewriter for [`Filter::default`]'s reason: a
    /// default has to be visibly SOMETHING the moment it is turned on, or
    /// the control reads as broken, and of the three this is the one
    /// everybody can already name before they see it. One second is that
    /// same test applied to the duration — long enough to read as typing
    /// rather than as a cut, short enough that a three-second caption is
    /// not still arriving when it is due to leave.
    ///
    /// `out` is 0 because most text is cut away rather than un-typed. An
    /// un-reveal is a deliberate choice about the end of a shot, and a
    /// default that quietly took a second back off the end of every
    /// animated title would be a surprise rather than a convenience.
    fn default() -> Self {
        TextAnimation {
            kind: TextAnimationKind::Typewriter,
            r#in: TIMESCALE,
            out: 0,
        }
    }
}

/// The three reveals of spec §4.3, closed at three.
///
/// Closed for [`ObscureKind`]'s reason: each one is a distinct drawing
/// routine in `LayerRenderers.renderText`, not a parameter of a shared
/// one — a prefix of the glyphs, a per-word alpha ramp, a per-line offset
/// and alpha — so an unknown kind is a value nothing downstream could
/// repair, and there is no neutral animation to fall back to the way a
/// filter's `amount` can fall back to 0. Refusing it at the serde boundary
/// makes the illegal state unrepresentable.
///
/// A kind may be added at the END. Nothing derives a number from the
/// declaration order here — the recipe carries the kind by NAME, unlike
/// [`ObscureKind`], whose order is a shader discriminant — but the JSON
/// spelling of each variant is persisted, so a variant may not be renamed
/// without a migration step.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TextAnimationKind {
    /// The default, and [`TextAnimation::default`] says why: the one
    /// reveal a user can name before they have seen it.
    #[default]
    Typewriter,
    WordFade,
    LineRise,
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
