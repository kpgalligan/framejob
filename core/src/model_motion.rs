//! The motion vocabulary (format version 8, road map 5's E2): [`Motion`]
//! and the three slots it holds — an entrance ([`MotionEdge`] with an
//! [`EdgeMotion`] kind), an exit (the same pair) and a continuous
//! [`MotionDuring`] with a [`DuringMotion`] kind.
//!
//! **Motion is a preset, not a value.** Every other member of the video
//! group is a quantity the compositor reads more or less straight — an
//! opacity, a scale, four crop edges — while these five types say only what
//! the clip should DO, and the placement that comes out of it is computed
//! by `motion.rs` at render time from the clip's own duration, the
//! container's canvas and the source's size. Nothing here is ever a number
//! the renderer receives: `recipe.rs` publishes no `motion` key at all, and
//! a layer's `scale`, `rotation`, `opacity`, `x` and `y` are where a preset
//! shows up (spec §5.3, §7.3). That is the seam, and it is why these types
//! are their own module rather than five more structs in `model_props.rs`.
//!
//! Re-exported whole by `model_props.rs`, which `model.rs` re-exports whole
//! in turn, so `crate::model::Motion` resolves like every other property
//! type; the FIELD holding it (`VideoProps.motion`) stays with the video
//! group.
//!
//! Neither enum's declaration ORDER is load-bearing — `motion.rs` matches
//! on the variant and nothing crosses to a shader, where
//! [`crate::model::BlendMode`]'s and [`crate::model::ObscureKind`]'s orders
//! are discriminants — so a kind may be added at the END. The JSON spelling
//! of each variant IS persisted, so a rename needs a migration step. Both
//! are closed, so a misspelt kind is refused at the serde boundary rather
//! than clamped later: there is no neutral motion to fall back to, which is
//! [`crate::model::TextAnimationKind`]'s reason exactly. `spin` is spelled
//! in BOTH, which is deliberate and is what the enum sweep in
//! `core/tests/model_tests.rs` reads off the fixture rather than off a
//! list of its own.
//!
//! The rules are `model.rs`'s: the field names ARE the JSON keys,
//! declaration order IS key order, every struct is `#[serde(default)]` over
//! a hand-written [`Default`] that says what an absent key means, and
//! nothing here carries `deny_unknown_fields`.

use serde::{Deserialize, Serialize};

use crate::time::{Ticks, TIMESCALE};

/// What a clip does on its way in, on its way out, and all the way
/// through — three independent slots, each `null` when the clip does
/// nothing of that sort.
///
/// `VideoProps.motion` is `Option<Motion>` rather than this struct with
/// three `None`s, so a clip that does not move writes `"motion": null`
/// instead of three nulls and `{"motion": null}` is an exact clear. A
/// `Motion` whose three slots are all `None` is NORMALISED back to `None`
/// by the patch path (`edit_props.rs`) and by the split rule
/// (`edit_split.rs`), so one clip has one spelling of "no motion" and
/// `is_empty` is the test both use.
///
/// It is NOT an animation target: `set_action_end` refuses a patch naming
/// it, and `evaluate_clip` restores the base value over whatever an action
/// reached, because a preset is anchored to the clip's two ends and an
/// action is a ramp between two states — interpolating "half a slide" into
/// "half a spin" is not a picture anybody asked for (spec §5.4).
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Motion {
    /// The entrance, measured forward from the clip's first frame.
    #[serde(rename = "in")]
    pub r#in: Option<MotionEdge>,
    /// The exit, measured back from the clip's last frame.
    pub out: Option<MotionEdge>,
    /// What the clip does for its whole length, under the two edges.
    pub during: Option<MotionDuring>,
}

impl Motion {
    /// True when no slot is filled — the state that is stored as `None`.
    pub fn is_empty(&self) -> bool {
        self.r#in.is_none() && self.out.is_none() && self.during.is_none()
    }

    /// Every slot filled with its default.
    ///
    /// Not a value any clip is given: this is what `Group::template`
    /// (`edit_props.rs`) hands `check_keys`, which walks a patch against a
    /// fully populated struct to find a misspelt key. Against a `None`
    /// motion there would be nothing to walk INTO, so `{"motion": {"in":
    /// {"durration": 1}}}` would be accepted and silently dropped; with
    /// this, the recursion reaches every level and the refusal names the
    /// dotted path for free.
    pub fn template() -> Motion {
        Motion {
            r#in: Some(MotionEdge::default()),
            out: Some(MotionEdge::default()),
            during: Some(MotionDuring::default()),
        }
    }
}

/// One end of a clip: what it does, and for how long.
///
/// `duration` is a DURATION rather than a time, [`crate::model::TextAnimation`]'s
/// convention — an `in` is measured forward from the clip's first frame and
/// an `out` back from its last — so trimming a clip moves the preset with
/// the edge it belongs to. When `in + out` runs past the clip's own
/// duration the two are scaled down to meet in the middle rather than
/// refused (the tent rule, `motion.rs`), because "too long for THIS clip"
/// is a fact about a clip and not about the vocabulary, and a later trim
/// would invalidate any refusal anyway.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct MotionEdge {
    pub kind: EdgeMotion,
    pub duration: Ticks,
}

impl Default for MotionEdge {
    /// Half a second of [`EdgeMotion::Fade`] — what a caller gets for
    /// naming a slot and saying nothing else.
    ///
    /// The kind is the fade for [`crate::model::Filter::default`]'s reason:
    /// a default must be visibly SOMETHING the moment it is switched on or
    /// the control reads as broken, and of the nine this is the one
    /// everybody can name before they see it. Half a second is that same
    /// test applied to the duration — long enough to read as an entrance
    /// rather than as a cut, short enough that a two-second cutaway is not
    /// still arriving when it is due to leave.
    fn default() -> Self {
        MotionEdge {
            kind: EdgeMotion::Fade,
            duration: TIMESCALE / 2,
        }
    }
}

/// What a clip does for its whole length, under whatever its two edges are
/// doing.
///
/// `amount` is 0–1 and `period` is how long one cycle takes; what each
/// means in pixels or degrees is `motion.rs`'s table, and
/// [`DuringMotion::Drift`] ignores `period` entirely. Both are checked but
/// neither is clamped by the schema: `props_check.rs` refuses an `amount`
/// outside 0–1 and a `period` under one tick on the way in, and `motion.rs`
/// guards them again on the way out, because a hand-written file reaches
/// the renderer without passing an op.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct MotionDuring {
    pub kind: DuringMotion,
    /// 0–1, how much of the preset to apply. 0 is the identity.
    pub amount: f64,
    /// One cycle, in ticks. Ignored by [`DuringMotion::Drift`].
    pub period: Ticks,
}

impl Default for MotionDuring {
    /// A half-strength one-second [`DuringMotion::Pulse`], on
    /// [`MotionEdge::default`]'s terms: the one continuous motion a reader
    /// can name before seeing it, at the middle of its range, over a period
    /// slow enough to read as breathing rather than as a flicker.
    fn default() -> Self {
        MotionDuring {
            kind: DuringMotion::Pulse,
            amount: 0.5,
            period: TIMESCALE,
        }
    }
}

/// The nine entrances and exits of road map 5 §5b.
///
/// One kind, read at an edge: the same variant means the mirrored thing on
/// the way out — `ZoomIn` grows INTO the frame as an entrance and grows
/// away from the viewer as an exit, `SlideLeft` enters from the right edge
/// and leaves past the left one. `motion.rs`'s two tables are the
/// normative statement of every number.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EdgeMotion {
    /// The default, and [`MotionEdge::default`] says why.
    #[default]
    Fade,
    ZoomIn,
    ZoomOut,
    SlideLeft,
    SlideRight,
    SlideUp,
    SlideDown,
    Spin,
    Pop,
}

/// The five continuous motions of road map 5 §5b.
///
/// Every one of them is the identity at clip time 0, so a clip starts
/// exactly where it is placed whatever it goes on to do; `motion.rs`'s
/// table is the normative statement.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DuringMotion {
    /// The default, and [`MotionDuring::default`] says why.
    #[default]
    Pulse,
    Shake,
    /// Spelled in [`EdgeMotion`] too, and deliberately: the same word
    /// means the same thing at an edge and throughout.
    Spin,
    Bounce,
    Drift,
}
