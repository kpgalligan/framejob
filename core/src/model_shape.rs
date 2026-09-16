//! The shape vocabulary — [`ShapeProps`], the [`ShapeKind`] it draws, the
//! [`Stroke`] around it and the [`Gradient`] (with [`GradientKind`],
//! [`GradientStop`] and the [`MAX_GRADIENT_STOPS`] budget on it) that fills
//! it.
//!
//! Cut out of `model_props.rs` in road map 5's E2, when that file stood AT
//! the 600-line cap owing `video.motion`, and cut HERE because
//! `model_text.rs` is its own precedent: a whole property group moved out
//! with the types only it names. Text and shape are the two CPU-rendered,
//! hash-keyed sources — neither reaches the fragment stage as a sampled
//! texture the model describes, both are drawn by
//! `LayerRenderers`/`LayerRenderersText` into one, and both are keyed by
//! the recipe's content hash — so taking the second after the first leaves
//! `model_props.rs` holding what the compositor's uniform block is read
//! from and nothing else. Nothing here is ever a shader discriminant, and
//! that is a standing rule rather than an omission: [`GradientKind`]'s own
//! doc says a kind may be added at the END and that nothing derives a
//! number from the order, where [`crate::model::BlendMode`]'s order IS the
//! discriminant.
//!
//! Re-exported whole by `model_props.rs`, which `model.rs` re-exports whole
//! in turn, so `crate::model::ShapeProps` and every other path is
//! unchanged. The FIELD that holds these values (`Clip.shape`) stays in
//! `model.rs` with the clip's other property groups.
//!
//! The rules are `model.rs`'s: the field names ARE the JSON keys,
//! declaration order IS key order, every type is `#[serde(default)]` over a
//! hand-written [`Default`] that says what an absent key means, and nothing
//! here carries `deny_unknown_fields`.

use serde::{Deserialize, Serialize};

use crate::model::Color;

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
/// it is 8 where [`crate::model::MAX_FILTERS`] and
/// [`crate::model::MAX_OBSCURE`] are both 4: those two are SLOTS — the uniform block carries exactly four `(kind, amount)` pairs
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
    /// Degrees from the RIGHT, counter-clockwise —
    /// [`crate::model::Shadow`]'s `angle` convention, which is the crate's
    /// only one. Meaningless for
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
    /// [`crate::model::Filter::default`]'s rule and
    /// [`crate::model::ObscureRegion::default`]'s, that a default must be
    /// visibly SOMETHING the moment it is switched on or the control reads as
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
/// — this enum never reaches a shader, unlike
/// [`crate::model::BlendMode`] — but each variant's JSON spelling is
/// persisted, so a rename needs a migration step.
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
    /// ([`crate::model::Outline::default`],
    /// [`crate::model::Shadow::default`]); 0 is the ramp's own origin, the
    /// one position that needs no argument.
    fn default() -> Self {
        GradientStop {
            at: 0.0,
            color: [0.0, 0.0, 0.0, 1.0],
        }
    }
}
