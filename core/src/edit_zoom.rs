//! `add_zoom_action` — the screencast zoom, and the placement equation
//! behind it (spec §5.3, spec §6).
//!
//! A screencast zoom is not a new kind of animation: it is an ordinary
//! [`crate::model::Action`] whose end patch holds three numbers — `scale`,
//! `x` and `y` — chosen so that a rectangle the user drew on the picture
//! ends up filling the canvas. The op exists because CHOOSING those three
//! numbers is arithmetic nobody should do twice. The canvas gesture, the
//! inspector's button and the MCP tool all want the same answer, and the
//! road map's premise for this phase is that the answer lives in the core,
//! where spec §5.3's placement rule already lives, rather than being
//! re-derived in a drag handler.
//!
//! It is a module of its own rather than a fifth function in
//! `edit_action.rs` because its substance is GEOMETRY, not action
//! bookkeeping: `edit_action.rs` owns one rule (actions on a clip may not
//! overlap) and this file owns one equation. Phase 3c's "Place on Canvas"
//! and any later "zoom to selection" cite the derivation below rather than
//! repeating it.
//!
//! # The frames
//!
//! Two coordinate spaces meet here, and confusing them is the whole risk.
//!
//! - **Q, the spotlight's frame.** Source pixels measured from the CENTRE
//!   of the layer's cropped rect, y down. [`crate::model::Spotlight`] and
//!   (from format version 4) [`crate::model::ObscureRegion`] are in it, and
//!   so is [`ZoomRegion`]: `x`/`y` are the region's CENTRE, not a corner,
//!   and `width`/`height` its size. The field names do not say "centre",
//!   which is why the op table row, the doc comment on [`ZoomRegion`] and
//!   the MCP tool description all say it out loud. A length in Q costs
//!   nothing to convert because the layer's own `scale` is what turns it
//!   into canvas pixels.
//! - **C, canvas pixels**, from the canvas's top-left, y down. `video.x`
//!   and `video.y` are the ONLY per-layer lengths in it, and they are an
//!   offset of the layer's centre from the CANVAS centre.
//!
//! # The placement rule (★)
//!
//! With `W`, `H` the canvas size, `l, t, r, b` the crop insets in source
//! pixels, `s` the layer's `scale`, `θ` its `rotation` in degrees and
//! `R(θ)` the clockwise-on-a-y-down-screen rotation ([`crate::nest`]'s
//! `rotate`, which is the same sign as `Compositor.metal`'s `rotate2`):
//!
//! ```text
//! anchor = (W/2 + video.x, H/2 + video.y)   the centre of the UNCROPPED
//!                                           rect, and the rotation pivot
//! c      = ((l − r)/2, (t − b)/2)           the cropped rect's centre,
//!                                           in source px, relative to it
//!
//! canvas(q) = anchor + s · R(θ) · (c + q)                            (★)
//! ```
//!
//! (★) is the one placement rule the whole editor draws by. The Metal
//! vertex stage, `ProjectSnapshot.canvasRect` on the Swift side and
//! [`crate::nest::Frame::place`] are three implementations of it; `c` is
//! literally the expression `Frame::enter` uses to fold a nest's crop.
//!
//! # Solving it for a region
//!
//! Given a region whose centre is `q_c = (rx, ry)` and whose size is
//! `rw × rh`, find the `s′`, `x′`, `y′` that put it on the canvas.
//!
//! **The position.** Require the region's centre to land at the canvas
//! centre and substitute into (★):
//!
//! ```text
//! (W/2 + x′, H/2 + y′) + s′ · R(θ) · (c + q_c) = (W/2, H/2)
//!         ⟹  (x′, y′) = − s′ · R(θ) · (c + q_c)
//! ```
//!
//! So the offsets depend on the scale, which is why the scale is resolved —
//! and clamped — FIRST.
//!
//! **The scale, measured through the rotation.** Once placed, the region is
//! a rotated `s′·rw × s′·rh` rectangle centred on the canvas centre, and
//! the canvas is a `W × H` rectangle centred on the same point. A rectangle
//! contains a rotated rectangle exactly when it contains its four corners,
//! so comparing axis extents is not an approximation here — it is necessary
//! AND sufficient. With `k = |cos θ|` and `m = |sin θ|` the region's
//! canvas-space bounding box is `s′(rw·k + rh·m) × s′(rw·m + rh·k)`, and
//! the canvas's bounding box measured in the LAYER's axes is
//! `(W·k + H·m) × (W·m + H·k)` canvas pixels:
//!
//! ```text
//! fit  (the whole region visible):  s′ = min( W / (rw·k + rh·m),
//!                                             H / (rw·m + rh·k) )
//! fill (the region covers the canvas): s′ = max( (W·k + H·m) / rw,
//!                                                (W·m + H·k) / rh )
//! ```
//!
//! Both collapse to the naïve `min`/`max(W/rw, H/rh)` at θ = 0, so the
//! unrotated case — which is every screencast — reads exactly as it would
//! have without the rotation terms, and a rotated clip stops hanging its
//! corners off the canvas. The denominators cannot vanish: `rw` and `rh`
//! are checked positive and `k² + m² = 1`, so `rw·k + rh·m ≥ min(rw, rh)`.
//!
//! **Worked example, the one the tests pin.** Canvas 1920×1080, no crop,
//! θ = 0, region 480×270 centred at `(480, 0)`. Then
//! `s′ = min(1920/480, 1080/270) = 4` and `(x′, y′) = −4·(480, 0) =
//! (−1920, 0)`. Check it against (★): `anchor′ = (960 − 1920, 540)`, so the
//! region's centre lands at `(−960 + 4·480, 540) = (960, 540)`, the canvas
//! centre, and its width is `480·4 = 1920`, the canvas width. Turn the same
//! clip 90° and `s′` becomes `min(1920/270, 1080/480) = 2.25`: the two
//! formulas genuinely differ under rotation, which is the point of carrying
//! `k` and `m`.
//!
//! # What it reads, and what it writes
//!
//! Rotation and crop come from the clip EVALUATED at clip time `at`
//! ([`crate::model::Project::evaluate_clip`]), not from its base props.
//! That is the state the frame the user drew on was rendered in, and it is
//! the reading that survives an earlier action having already rotated or
//! cropped the layer — the common case on a screencast with two zooms in a
//! row. Evaluating before the new action is inserted is not circular: the
//! action does not exist yet, and at `clip_t == at` it would contribute
//! nothing anyway (its progress there is 0).
//!
//! The end patch is `{"video": {"scale", "x", "y"}}` and nothing else. No
//! rotation, no crop, no source size: `sw` and `sh` cancel out of `c`
//! entirely, so the op needs no source measurement — which is what lets it
//! zoom a TEXT clip, whose source size only the renderer can know
//! (`Project::source_size` answers `None` for one).
//!
//! Values go out raw. The core rounds no property anywhere; `canvasRound`
//! on the Swift side is a gesture-side nicety so a drag does not write
//! seventeen digits, and a computed op is not a drag.
//!
//! # The clamp, and the two limits worth knowing
//!
//! An action's end patch is deliberately NOT range-checked
//! (`edit_action.rs`), so this op is its own last line of defence. If the
//! required `s′` exceeds [`SCALE_MAX`] it is clamped and `x′`/`y′` are
//! computed from the CLAMPED value, so the region still lands exactly
//! centred and only the magnification degrades. Writing the unclamped scale
//! instead would leave `clamp_video` to bound it at render time while the
//! offsets still assumed the larger one — the region neither filling nor
//! centred, with nothing reported. The visible consequence, worth saying
//! plainly: on a 1920-wide canvas a region narrower than 192 source pixels
//! cannot reach full zoom. Raising [`SCALE_MAX`] is not the answer — it is
//! the inspector's 1–1000 % and is read by `check_video`, `clamp_video` and
//! the canvas scale gesture alike.
//!
//! Two residual limits, stated rather than chased:
//!
//! 1. A rotation or crop animated BETWEEN `at` and `at + duration` is not
//!    tracked. The offsets were computed against the rotation at `at`, so
//!    the region drifts across the span. Tracking it would mean solving
//!    (★) per frame, which the schema has no way to express.
//! 2. The derivation is against [`crate::nest::Frame::TOP`], the identity.
//!    That is sound because no op can name a nested clip — every `clip`
//!    argument resolves through `Project::clip`, which searches
//!    `self.clips` only — so the target is always a TIMELINE clip and there
//!    is no enclosing frame to compose. Were that ever to change, `place`
//!    would fold a nest's own scale and rotation on top of whatever this
//!    patch wrote.
//!
//! # Composition
//!
//! The op is `add_action` + `set_action` + `set_action_end`, run in that
//! order on one project and returned as one, exactly as `edit_insert.rs`
//! composes its two. It is ONE op because a drag is one gesture and must be
//! one undo step, and because composing it inherits every refusal
//! `add_action` already documents — the no-overlap rule above all — with no
//! second copy of `actions_overlap` and no visibility change to
//! `edit_action.rs`'s private helpers.

use serde::de::{self, Deserializer};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::export::describe;
use crate::model::{Clip, Curve, Project, VideoProps};
use crate::nest::rotate;
use crate::props_check::{SCALE_MAX, SCALE_MIN};
use crate::time::Ticks;

/// The rectangle a zoom lands on, in the spotlight's frame Q: `x` and `y`
/// are its **CENTRE** as an offset in SOURCE pixels from the centre of the
/// layer's cropped rect, and `width`/`height` are its size in source pixels
/// (spec §5.3).
///
/// Centre-and-size rather than corner-and-size because that is what
/// `video.spotlight` and `video.obscure` are, and three region types in one
/// inspector where one reads its `x` differently from the other two is a
/// wrong picture discovered months later. Converting a drag's two corners
/// is one subtraction on the caller's side.
///
/// An op argument, not stored state: it never reaches a project file, so it
/// lives here beside the maths that consumes it rather than in
/// `model_props.rs`.
///
/// It is read the way a property patch is read (`patch.rs`), which is why
/// the `Deserialize` below is written out rather than derived: it is the
/// one op argument that is a caller-authored OBJECT, so a caller gets the
/// same answers here as at every other door — an unknown member and a
/// missing member named, a wrong-typed member named by its dotted path,
/// and the object required to BE an object.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct ZoomRegion {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl<'de> Deserialize<'de> for ZoomRegion {
    /// The region's four members, refused by name.
    ///
    /// Three things the derive alone would not do, and each is a spelling
    /// a caller never learnt and could only land on by accident:
    ///
    /// - **A list is not a region.** serde reads a struct from a JSON ARRAY
    ///   of its fields in declaration order, so `[0, 0, 480, 270]` would
    ///   zoom to a rectangle nobody spelled. It is the hole `patch.rs`'s
    ///   kind check closed inside a patch, closed here for the one op
    ///   argument shaped like one.
    /// - **A wrong-typed member is named.** serde's own sentence is
    ///   `invalid type: string "wide", expected f64` and says nothing of
    ///   WHICH member, so the read goes through `serde_path_to_error` and
    ///   the message opens `bad value at "region.width"`, the patch door's
    ///   own form.
    /// - **`deny_unknown_fields` and no defaults** do the other two: a
    ///   `widht` is refused beside the four the region takes, and a missing
    ///   member is refused by name, because there is no defensible default
    ///   for any of them — a region with no width is not a region.
    ///
    /// `add_zoom_action`'s `region` is an `Option` with a serde default, so
    /// an absent key and an explicit `null` never reach here: both mean a
    /// zoom BACK (`edit.rs`).
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Members {
            x: f64,
            y: f64,
            width: f64,
            height: f64,
        }

        let value = Value::deserialize(deserializer)?;
        if !value.is_object() {
            return Err(de::Error::custom(format!(
                "expected an object, not {}",
                describe(&value)
            )));
        }
        let members: Members = serde_path_to_error::deserialize(value).map_err(|e| {
            // `Path`'s root prints as `"."`, not as the empty string — a
            // missing member is reported AT the struct, so the naive
            // `format!("region.{path}")` said `region..`, which is a path
            // no caller can act on. Both spellings of "the whole region"
            // collapse to `region` here (measured, D1·5).
            let path = e.path().to_string();
            let at = if path.is_empty() || path == "." {
                "region".to_string()
            } else {
                format!("region.{path}")
            };
            de::Error::custom(format!("bad value at \"{at}\": {}", e.inner()))
        })?;
        Ok(ZoomRegion {
            x: members.x,
            y: members.y,
            width: members.width,
            height: members.height,
        })
    }
}

/// How the region is made to meet the canvas: `fit` shows all of it,
/// `fill` covers all of the canvas. Both are measured through the clip's
/// rotation (this module's doc).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ZoomFit {
    /// The whole region visible — the default, because a zoom the user
    /// drew a box for should show the box.
    #[default]
    Fit,
    /// The region covers the canvas, so nothing outside it is on screen.
    Fill,
}

/// The curve a zoom gets when the caller does not name one.
///
/// NOT [`Curve::default`], which is `linear`: a screencast zoom that starts
/// and stops abruptly is the one thing this feature exists to avoid, and
/// the eased forms exist (`actions.rs`) for exactly "a move, a scale, a
/// fade that does not start and stop abruptly". The argument is offered so
/// the default can be overridden in the same op rather than by a second one
/// — two ops in one gesture would cost the single undo step the composite
/// exists for.
const DEFAULT_ZOOM_CURVE: Curve = Curve::EaseInOut;

/// The region's four numbers, checked the way `props_check.rs` checks a
/// property group: named, never repaired.
///
/// The wording is `props_check`'s `finite` and `above` verbatim, restated
/// rather than reached because those helpers are private to the module that
/// owns the stored property groups and a region is an op ARGUMENT — it is
/// never a `VideoProps` field and never passes `check_video`.
fn check_region(region: &ZoomRegion) -> Result<(), String> {
    for (key, value) in [("region.x", region.x), ("region.y", region.y)] {
        if !value.is_finite() {
            return Err(format!("{key} must be a finite number, not {value}"));
        }
    }
    for (key, value) in [
        ("region.width", region.width),
        ("region.height", region.height),
    ] {
        // A zero-width region asks for an infinite scale and a zero-height
        // one for a division by nothing; both are the caller's mistake, in
        // the class `props_check` names rather than clamps.
        if !(value.is_finite() && value > 0.0) {
            return Err(format!("{key} must be greater than 0, not {value}"));
        }
    }
    Ok(())
}

/// The `scale` that makes `region` meet a `width × height` canvas under
/// `fit`, on a layer rotated `rotation` degrees — the module doc's two
/// formulas — clamped into the layer's legal scale range.
///
/// The clamp is here rather than at the call site so that the offsets,
/// which are computed FROM the returned value, cannot be derived from a
/// scale the renderer will not honour.
fn zoom_scale(canvas: (f64, f64), region: &ZoomRegion, fit: ZoomFit, rotation: f64) -> f64 {
    let (width, height) = canvas;
    let (sin, cos) = rotation.to_radians().sin_cos();
    let (k, m) = (cos.abs(), sin.abs());
    let scale = match fit {
        // The region's own bounding box on the canvas must fit inside it.
        ZoomFit::Fit => {
            let across = region.width * k + region.height * m;
            let down = region.width * m + region.height * k;
            (width / across).min(height / down)
        }
        // The canvas's bounding box, measured in the layer's own axes, must
        // fit inside the region.
        ZoomFit::Fill => {
            let across = width * k + height * m;
            let down = width * m + height * k;
            (across / region.width).max(down / region.height)
        }
    };
    scale.clamp(SCALE_MIN, SCALE_MAX)
}

/// The `x`, `y` that put the region's centre at the canvas centre at
/// `scale` — the module doc's `(x′, y′) = − s′ · R(θ) · (c + q_c)`.
///
/// `crop` reaches this only through `c`, the cropped rect's centre measured
/// from the uncropped one, which is the same expression
/// [`crate::nest::Frame::enter`] folds a nest's crop with.
fn zoom_offset(video: &VideoProps, region: &ZoomRegion, scale: f64) -> (f64, f64) {
    let crop = video.crop;
    let cx = (crop.l - crop.r) / 2.0 + region.x;
    let cy = (crop.t - crop.b) / 2.0 + region.y;
    let (x, y) = rotate(scale * cx, scale * cy, video.rotation);
    (-x, -y)
}

impl Project {
    /// Adds an action at CLIP time `at` whose end patch zooms the layer so
    /// that `region` meets the canvas (spec §6).
    ///
    /// `region`'s `x`/`y` are its CENTRE and `width`/`height` its size,
    /// both in SOURCE pixels measured from the centre of the clip's cropped
    /// rect — the spotlight's frame. `fit` shows the whole region, `fill`
    /// covers the whole canvas; both are measured through the clip's
    /// rotation. Rotation and crop are read from the clip evaluated at
    /// `at`, the scale is clamped to the layer's maximum and the offsets
    /// are computed from the clamped value, so a region too small to fill
    /// the canvas still lands exactly centred. The module doc carries the
    /// derivation and the two residual limits.
    ///
    /// `region` absent or `null` is a zoom BACK: the end patch is the
    /// clip's own base `scale`, `x` and `y`, which is the only reading that
    /// survives earlier actions. An absent `duration` is `add_action`'s
    /// default and an absent `curve` is `ease_in_out`.
    ///
    /// Refuses (`None`) wherever `add_action` does — an overlap with
    /// another action on the clip, or a span running past the clip's end.
    /// `Err` on an unknown clip, a clip with no video properties (it draws
    /// nothing, so there is nothing to zoom), a region that is not four
    /// usable numbers, a negative `at` or a non-positive `duration`.
    pub fn add_zoom_action(
        &self,
        clip: u32,
        at: Ticks,
        duration: Option<Ticks>,
        region: Option<ZoomRegion>,
        fit: Option<ZoomFit>,
        curve: Option<Curve>,
    ) -> Result<Option<Project>, String> {
        let target = self.require_clip(clip)?.clone();
        // The presence of the group is the aspect (`edit_props.rs`): a clip
        // with no video props draws nothing, so there is no picture to zoom
        // and no base transform to zoom back to.
        let base = target
            .video
            .clone()
            .ok_or_else(|| format!("clip {clip} has no video properties"))?;
        if let Some(region) = region.as_ref() {
            check_region(region)?;
        }

        // The tick the action will actually depart from. `add_action`'s
        // first act is this same `self.snapped(at)`, so calling the one
        // helper here rather than reading the start back out of the project
        // it returns costs nothing — and it keeps the ARGUMENT errors (a
        // malformed region above, a negative time below) ahead of the
        // refusals, which is the order every op reports in.
        let start = self.snapped(at);
        let patch = self.zoom_patch(&target, start, &base, region, fit);

        let id = self.next_id;
        let Some(mut next) = self.add_action(clip, at, duration)? else {
            return Ok(None);
        };
        let curve = curve.unwrap_or(DEFAULT_ZOOM_CURVE);
        if let Some(recurved) = next.set_action(clip, id, None, None, Some(curve))? {
            next = recurved;
        }
        if let Some(patched) = next.set_action_end(clip, id, &patch)? {
            next = patched;
        }
        self.finish(next)
    }

    /// The end patch for one zoom: three video keys and nothing else.
    ///
    /// Split out so the maths reads as maths — it takes the clip, the state
    /// to read the rotation and crop from, and the region, and it touches
    /// no project.
    fn zoom_patch(
        &self,
        target: &Clip,
        start: Ticks,
        base: &VideoProps,
        region: Option<ZoomRegion>,
        fit: Option<ZoomFit>,
    ) -> Value {
        let Some(region) = region else {
            // Zoom back: the clip's BASE transform, not the state at `at`.
            // "Back" means the place the clip sits when nothing is
            // animating it, which is what the user asked for and what a
            // later zoom in the same clip measures from.
            return json!({"video": {"scale": base.scale, "x": base.x, "y": base.y}});
        };
        let canvas = (f64::from(self.canvas.width), f64::from(self.canvas.height));
        // Evaluated, not base: the rectangle was drawn on the frame the
        // clip is actually in at `at` (module doc, "What it reads").
        let evaluated = self.evaluate_clip(target, start).video;
        let scale = zoom_scale(canvas, &region, fit.unwrap_or_default(), evaluated.rotation);
        let (x, y) = zoom_offset(&evaluated, &region, scale);
        json!({"video": {"scale": scale, "x": x, "y": y}})
    }
}
