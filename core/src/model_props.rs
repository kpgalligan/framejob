//! The per-clip property types of spec §5.2 — the `video`, `audio`, `text`
//! and `shape` groups a [`crate::model::Clip`] carries, and every struct
//! and enum inside them but two families, both re-exported below: the
//! region types, which are `model_regions.rs`'s, and the text types, which
//! are `model_text.rs`'s.
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
//! It has since paid the same rule TWICE itself, and both payments were
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
//! module's doc states it.
//!
//! Every path stays as it was, through all three cuts: `model.rs`
//! re-exports this whole module with `pub use crate::model_props::*` and
//! this module re-exports the other two the same way, so
//! `crate::model::VideoProps`, `crate::model::Spotlight`,
//! `crate::model::TextProps` and the crate-root re-exports in `lib.rs` are
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

/// The text types — [`TextProps`], the [`TextAlign`] and [`TextVAlign`] it
/// is placed by, its optional [`Outline`] and [`Backdrop`], and the
/// [`TextAnimation`] and [`TextAnimationKind`] that reveal it — live in
/// `model_text.rs` and are re-exported whole, so every
/// `crate::model_props::TextProps` path (and, through `model.rs`'s own
/// glob, every `crate::model::TextProps` one) still resolves. See that
/// module's doc for the seam they share — text is the one group the model
/// cannot measure — which is why they are a file of their own.
pub use crate::model_text::*;

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
    /// A gradient fill, taking precedence over `fill` when set
    /// (format version 6). Ignored on `Line` and `Arrow`, which have no
    /// area.
    pub gradient: Option<Gradient>,
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
            gradient: None,
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

/// The most stops one gradient may carry. NOT a shader budget, which is why
/// it is 8 where [`MAX_FILTERS`] and [`MAX_OBSCURE`] are both 4: those two
/// are SLOTS — the uniform block carries exactly four `(kind, amount)` pairs
/// and exactly four regions, and a fifth of either has nowhere to go — while
/// a gradient never reaches the fragment stage at all, since
/// `LayerRenderers.renderShape` hands the stops to `CGGradient` on the CPU,
/// which takes as many as it is given. Four here would be a real limitation
/// (a sunset, a spectrum, a brand ramp) bought for no technical reason, and
/// a cap that turns out too high costs nothing where one that turns out too
/// low is reported as a bug. It is NAMED rather than trimmed all the same,
/// the posture the other two take: a stop silently dropped from the next
/// write is a colour the user placed and can no longer see.
pub const MAX_GRADIENT_STOPS: usize = 8;

/// A gradient fill for a shape (format version 6, road map 2's phase 6) —
/// what `shape.fill`'s single colour becomes when a flat plate is not
/// enough: a sky behind a title, a brand ramp, the wash on the full-canvas
/// background clip `edit_background.rs` puts on the back track.
///
/// **Setting a gradient does not clear `fill`.** Both persist and the
/// RENDERER prefers the gradient while it is non-null, which makes
/// `{"gradient": null}` an exact inverse — the inspector's Reset restores
/// the colour underneath rather than leaving an invisible shape — and keeps
/// the precedence rule in one statable place instead of spreading it as a
/// side effect of whichever op wrote last. The stops are NOT required to be
/// sorted, and that too is a decision rather than an omission:
/// `props_check.rs` argues the missing check where it would have gone, and
/// the renderer sorts.
///
/// [`ShapeKind::Line`] and [`ShapeKind::Arrow`] have no area, so they ignore
/// a gradient entirely: stored, range-checked, not drawn, with the
/// inspector's rows disabled for them. That is `radius`'s precedent exactly —
/// every kind carries it, only the rectangle reads it — and worth restating,
/// because refusing the field per kind looks tidier: it would mean the kind
/// popup had to CLEAR the field on its way past, and a value a popup deleted
/// is work nobody can get back.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Gradient {
    pub kind: GradientKind,
    pub stops: Vec<GradientStop>,
    /// Degrees from the RIGHT, counter-clockwise — [`Shadow`]'s `angle`
    /// convention, which is the crate's only one. Meaningless for
    /// [`GradientKind::Radial`]; stored and range-checked there all the
    /// same, so flipping a gradient's kind and back does not lose it.
    pub angle: f64,
}

impl Default for Gradient {
    /// Black to white, left to right.
    ///
    /// The feature's whole first impression, not a formality: the
    /// container-level `#[serde(default)]` over a `null` base means
    /// `{"gradient": {}}` — the inspector's Add, and the most natural thing
    /// an agent will write — produces exactly this. So it follows
    /// [`Filter::default`]'s rule and
    /// [`ObscureRegion::default`]'s, that a default must be visibly
    /// SOMETHING the moment it is switched on or the control reads as
    /// broken, taken as far as it goes: black and white are the two colours
    /// that cannot be mistaken for footage, for the canvas or for each
    /// other in either appearance, and every gradient anybody actually
    /// wants is two swatch clicks away. Angle 0 is to the RIGHT (see the
    /// field), so the ramp runs the way a left-to-right reader expects, and
    /// the kind is `Linear`, the one the angle means anything to.
    fn default() -> Self {
        Gradient {
            kind: GradientKind::Linear,
            stops: vec![
                GradientStop {
                    at: 0.0,
                    color: [0.0, 0.0, 0.0, 1.0],
                },
                GradientStop {
                    at: 1.0,
                    color: [1.0, 1.0, 1.0, 1.0],
                },
            ],
            angle: 0.0,
        }
    }
}

/// The two gradient geometries, closed for [`crate::model::ObscureKind`]'s
/// reason: each is a different `CGGradient` call taking different
/// arguments, not a parameter of a shared one, so an unknown kind is a
/// value nothing downstream could repair and there is no neutral geometry
/// to fall back to. Refusing it at the serde boundary makes the illegal
/// state unrepresentable.
///
/// A kind may be added at the END. Nothing derives a number from the order
/// — this enum never reaches a shader, unlike [`BlendMode`] — but each
/// variant's JSON spelling is persisted, so a rename needs a migration
/// step.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GradientKind {
    #[default]
    Linear,
    Radial,
}

/// One colour, and where along the ramp it sits.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct GradientStop {
    /// 0–1 along the gradient.
    pub at: f64,
    pub color: Color,
}

impl Default for GradientStop {
    /// Opaque black at the start of the ramp. This one does a different job
    /// from [`Gradient::default`]: it is what the container-level
    /// `#[serde(default)]` fills in, so `{"at": 0.75}` gets a colour and
    /// `{"color": [1, 0, 0, 1]}` gets a position rather than a schema
    /// error. A stop the inspector ADDS is never this one — a new row lands
    /// between its neighbours, which the model cannot do, having no idea
    /// which row was clicked. Black is what the crate reaches for whenever
    /// a colour must exist before anybody has chosen one
    /// ([`Outline::default`], [`Shadow::default`]); 0 is the ramp's own
    /// origin, the one position that needs no argument.
    fn default() -> Self {
        GradientStop {
            at: 0.0,
            color: [0.0, 0.0, 0.0, 1.0],
        }
    }
}
