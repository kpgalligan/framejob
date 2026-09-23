//! The text vocabulary — [`TextProps`], the [`TextAlign`] and
//! [`TextVAlign`] it is placed by, the optional [`Outline`] and
//! [`Backdrop`] drawn with it, and the [`TextAnimation`] (with its
//! [`TextAnimationKind`]) that reveals it (spec §5.2, §5.3). Version 9's
//! three word-caption fields — `case`, `words` and `word_style` — close
//! [`TextProps`]; their TYPES are `model_words.rs`'s.
//!
//! Split out of `model_props.rs` under the size rule (core/CLAUDE.md: a
//! module over ~600 lines gives something up BEFORE it takes anything on)
//! when road map 2's phase 6 came to add `video.blend` and
//! `shape.gradient` to a file already standing at 592. `model.rs` →
//! `model_query.rs` in phase 0, `model.rs` → `model_props.rs` in phase 2
//! and `model_props.rs` → `model_regions.rs` in phase 3c are the
//! precedent, and so is their rule: the cut goes along a seam somebody can
//! NAME, and the piece taken out is re-exported whole so not one path
//! anywhere else changes. This is also the seam core/CLAUDE.md and the
//! road map both named in advance, which is the other half of why it is
//! the one phase 6 takes rather than a convenient two hundred lines.
//!
//! # The seam: the one group the model cannot measure
//!
//! Every other property group is made of quantities the core owns. A
//! `scale`, a `crop`, a shape's `width` and `height`, a region's box: the
//! core bounds them (`props_check.rs`), interpolates them (`actions.rs`),
//! solves geometry against them (`edit_zoom.rs`) and hands the renderer
//! numbers that are already the answer. Text is the one group where the
//! model can only state an INTENT — these words, that font, that size —
//! because only the platform can lay a string out, and the measurement
//! comes back the other way, through a cache the renderer fills (spec
//! §5.3, §11). Nothing here is ever a measured size, and that is a
//! standing rule rather than an omission.
//!
//! The rest of the file follows from it. `align`, `valign`,
//! `line_spacing`, `tracking`, `width`, the outline and the backdrop are
//! all instructions to that one layout and are meaningless to anything
//! that is not performing it; and [`TextAnimation`] is the same fact one
//! step further on — the model says WHAT the reveal is, `recipe.rs`'s
//! `Reveal` turns it into one number per frame, and the platform is the
//! only thing that knows which glyphs, words or lines that number picks
//! out. A file of types nothing but a text layout engine can consume is
//! one concern.
//!
//! What is NOT here: the field that HOLDS these values — `Clip.text` —
//! which is part of the clip's own shape and stays in `model.rs` with it;
//! the per-frame reveal the animation becomes, which `recipe.rs` computes
//! and never stores; and the caption machinery that produces text clips
//! (`CaptionCues`, `CaptionLayout`), which is Swift and is placement, not
//! schema.
//!
//! # Paths
//!
//! `model_props.rs` re-exports this module whole with
//! `pub use crate::model_text::*`, and `model.rs` re-exports
//! `model_props.rs` the same way, so `crate::model_props::TextProps`,
//! `crate::model::TextProps` and the crate-root re-exports in `lib.rs` all
//! still resolve and no other file needed an import changed. The schema
//! rules are `model.rs`'s too: the field names ARE the JSON keys,
//! declaration order IS key order, every type is `#[serde(default)]` over a
//! hand-written [`Default`] that says what an absent key means, and nothing
//! here carries `deny_unknown_fields`.

use serde::{Deserialize, Serialize};

use crate::model::Color;
use crate::model_words::{TextCase, Word, WordStyle};
use crate::time::{Ticks, TIMESCALE};

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
    /// A transform applied before layout (format version 9); never
    /// changes the token count.
    pub case: TextCase,
    /// One `{start, end}` per whitespace token of `content`, in clip time,
    /// or empty for an untimed text (format version 9, spec §11 W-2).
    pub words: Vec<Word>,
    /// How a timed page shows the word being said, or `None` for a text
    /// that draws its words all alike (format version 9).
    pub word_style: Option<WordStyle>,
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
            case: TextCase::AsWritten,
            words: Vec::new(),
            word_style: None,
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
    /// The kind is the typewriter for the reason
    /// [`crate::model::Filter::default`] gives: a default has to be visibly
    /// SOMETHING the moment it is turned on, or the control reads as
    /// broken, and of the three this is the one everybody can already name
    /// before they see it. One second is that same test applied to the
    /// duration — long enough to read as typing rather than as a cut, short
    /// enough that a three-second caption is not still arriving when it is
    /// due to leave.
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
/// Closed for [`crate::model::ObscureKind`]'s reason: each one is a
/// distinct drawing routine in `LayerRenderers.renderText`, not a shared
/// one — a prefix of the glyphs, a per-word alpha ramp, a per-line offset
/// and alpha — so an unknown kind is a value nothing downstream could
/// repair, and there is no neutral animation to fall back to the way a
/// filter's `amount` can fall back to 0. Refusing it at the serde boundary
/// makes the illegal state unrepresentable.
///
/// A kind may be added at the END. Nothing derives a number from the
/// declaration order here — the recipe carries the kind by NAME, unlike
/// [`crate::model::ObscureKind`], whose order is a shader discriminant —
/// but the JSON spelling of each variant is persisted, so it may not be
/// renamed without a migration step.
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
