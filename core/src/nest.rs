//! Flattening nests: the walk that turns one nest clip into the clips it
//! stands for (spec §5.3, §7.2, §7.3).
//!
//! A [`Nest`] is a group of tracks and clips held in the parent's ONE id
//! space, referencing the parent's `media[]`, with its times measured from
//! its own start. Nothing downstream of this module has to know that. The
//! plan, the recipe and the envelope all ask the same question — *which
//! clips actually play on this timeline track, and when* — and get back a
//! flat list of [`Instance`]s whose times are already project times and
//! whose extents are already clipped to the nest clip that shows them. A
//! project with no nests produces exactly one instance per clip, so the
//! flattened path IS the ordinary path and there is no second code route to
//! keep in step.
//!
//! Its own module because the walk is a new concern and `evaluate.rs` is
//! over the size cap `core/CLAUDE.md` sets. It holds no policy about what a
//! layer looks like or how loud it is: it decides only what exists, where,
//! and inside what.
//!
//! ### Four decisions the walk makes
//!
//! 1. **A nest clip has no in point.** `Source::Nest` carries a nest id and
//!    nothing else (spec §5.2), so a nest always plays from its own first
//!    frame. Trimming the head of a nest clip therefore MOVES its contents
//!    later rather than cutting into them, and splitting one leaves two
//!    clips that each replay the nest from the top. That is the honest
//!    consequence of the schema; the alternative — a fourth source field —
//!    is not version 2's.
//! 2. **Contents are clipped, never stretched.** A nest clip shorter than
//!    its nest cuts the tail off (and a clip that falls entirely outside it
//!    is dropped); a longer one draws nothing over the surplus. The nest
//!    clip's duration is independent of `Nest::duration` for exactly this
//!    reason.
//! 3. **Ids are not re-minted.** A nest lives in the parent's one id space
//!    (see [`Nest`]), which is what lets a segment name a media id the app
//!    can resolve and a `clip_state` call name a nested clip by one
//!    integer. But two clips may show the SAME nest, so one clip id can
//!    appear at two places on the timeline: an instance is named by its
//!    [`Instance::path`] — the enclosing nest clip ids, outermost first,
//!    then its own — which is unique, ordered, and what the composition
//!    plan keys its clip → video track map by.
//! 4. **The order is the stacking order.** Instances come out in the order
//!    they are drawn: timeline track by timeline track, clips in start
//!    order, and a nest clip replaced in place by its own stack walked the
//!    same way. So a nest's layers occupy exactly the slot the nest clip
//!    occupied, back to front, which is what makes a nest look the same
//!    after it is made as it did before.

use serde::Serialize;

use crate::format::MAX_NEST_DEPTH;
use crate::model::{Canvas, Clip, Nest, Project, Source, Track, VideoProps};
use crate::model_query::clips_on;
use crate::time::Ticks;

/// One nest clip on the way down to an instance: what it shows, where it
/// sits, and the span of it that survives the nest clips above it.
///
/// `Copy`, so pushing a chain down the walk costs nothing but the four
/// references and two integers.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Enclosing<'a> {
    /// The nest clip itself — its transform, its volume, its transition.
    pub clip: &'a Clip,
    /// The track IT sits on, in its own container: the project's tracks for
    /// a nest clip on the timeline, an outer nest's for one inside another.
    /// Carried for `hidden`, `muted` and `solo`, which apply to everything
    /// inside.
    pub track: &'a Track,
    /// What it shows — needed for the nest's own canvas rect, which is what
    /// a flattened layer is clipped to.
    pub nest: &'a Nest,
    /// Project time of the nest clip's first frame: the origin its contents'
    /// times are measured from.
    pub origin: Ticks,
    /// Its visible span in project time, already clipped to anything above.
    pub start: Ticks,
    pub end: Ticks,
}

/// One clip as it actually plays, in project time.
///
/// A timeline clip is an instance of itself with an empty [`inside`]. A clip
/// in a nest is an instance whose times have been offset by every nest clip
/// above it and clipped to their extents.
///
/// [`inside`]: Instance::inside
#[derive(Debug, Clone)]
pub(crate) struct Instance<'a> {
    /// The clip, in whatever container holds it. Its own `start` is in that
    /// container's time base and is NOT this instance's start.
    pub clip: &'a Clip,
    /// The track it sits on, in its own container.
    pub track: &'a Track,
    /// Project time of the clip's first frame. Actions, fades and the
    /// clip's duration are all measured from here — never from `start`,
    /// which a nest clip's edge may have moved.
    pub origin: Ticks,
    /// The half-open span `[start, end)` that actually plays: the clip's own
    /// extent intersected with every enclosing nest clip's.
    pub start: Ticks,
    pub end: Ticks,
    /// The nest clips this one is inside, OUTERMOST first. Empty for a
    /// timeline clip.
    pub inside: Vec<Enclosing<'a>>,
}

impl<'a> Instance<'a> {
    /// How long the instance plays for.
    pub fn duration(&self) -> Ticks {
        self.end.saturating_sub(self.start)
    }

    /// Whether project time `t` is inside the instance — the same half-open
    /// rule a clip uses, so a cut still shows exactly one frame.
    pub fn covers(&self, t: Ticks) -> bool {
        self.start <= t && t < self.end
    }

    /// CLIP time at project time `t`: 0 is the clip's own first frame, which
    /// is where its actions are measured from (spec §5.4).
    pub fn clip_time(&self, t: Ticks) -> Ticks {
        t.saturating_sub(self.origin)
    }

    /// The instance's name: the enclosing nest clip ids, outermost first,
    /// then the clip's own. Unique even when one nest is shown twice, which
    /// a bare clip id is not.
    pub fn path(&self) -> Vec<u32> {
        let mut path: Vec<u32> = self.inside.iter().map(|e| e.clip.id).collect();
        path.push(self.clip.id);
        path
    }

    /// Whether anything above this clip has hidden it: a cleared
    /// `enabled.video` or a hidden track, on the clip itself or on any nest
    /// clip it is inside. Says nothing about what the clip's SOURCE draws.
    pub fn shows_video(&self) -> bool {
        self.clip.enabled.video
            && !self.track.hidden
            && self
                .inside
                .iter()
                .all(|e| e.clip.enabled.video && !e.track.hidden)
    }

    /// Whether anything above this clip has excluded its sound. A MUTE is
    /// not exclusion — a muted track keeps its segments and gets a zero
    /// envelope (spec §7.2), so unmuting never rebuilds the composition —
    /// which is why only `enabled.audio` is read here.
    pub fn plays_audio(&self) -> bool {
        self.clip.enabled.audio && self.inside.iter().all(|e| e.clip.enabled.audio)
    }

    /// This clip and every nest clip it is inside, each with the span it
    /// occupies in project time. The chain ducking is measured over: a duck
    /// set inside a nest ducks the rest of the project over the span it
    /// actually plays, and one set on the nest clip ducks over the whole
    /// nest.
    pub fn chain(&self) -> impl Iterator<Item = (&'a Clip, Ticks, Ticks)> + '_ {
        self.inside
            .iter()
            .map(|e| (e.clip, e.start, e.end))
            .chain(std::iter::once((self.clip, self.start, self.end)))
    }
}

impl Project {
    /// Every clip that plays on timeline track `track`, in drawing order,
    /// with each nest clip replaced by the clips inside it.
    ///
    /// An unknown track has nothing on it, which is the same answer
    /// [`Project::clips_on_track`] gives.
    pub(crate) fn instances_on_track(&self, track: u32) -> Vec<Instance<'_>> {
        let Some(found) = self.track(track) else {
            return Vec::new();
        };
        let mut out = Vec::new();
        for clip in self.clips_on_track(track) {
            // The timeline is the outermost container: no offset, and no
            // window but the clip's own extent.
            self.expand(clip, found, 0, (Ticks::MIN, Ticks::MAX), &[], &mut out);
        }
        out
    }

    /// Every instance in the project, back-most timeline track first — the
    /// whole flattened timeline, in drawing order.
    pub(crate) fn all_instances(&self) -> Vec<Instance<'_>> {
        let mut out = Vec::new();
        for track in &self.tracks {
            for clip in self.clips_on_track(track.id) {
                self.expand(clip, track, 0, (Ticks::MIN, Ticks::MAX), &[], &mut out);
            }
        }
        out
    }

    /// Whether any clip anywhere — on the timeline or inside another nest —
    /// still shows this nest. What `unnest` asks before dropping one.
    pub(crate) fn nest_is_shown(&self, nest: u32) -> bool {
        self.every_clip()
            .any(|c| matches!(&c.source, Source::Nest { project } if *project == nest))
    }

    /// Every clip the project holds: the timeline's, then every nest's in
    /// `nests[]` order. Not a walk — a nest nothing points at is in the file
    /// and its clips still reference media (spec §5.2, one id space).
    pub(crate) fn every_clip(&self) -> impl Iterator<Item = &Clip> {
        self.clips
            .iter()
            .chain(self.nests.iter().flat_map(|n| n.clips.iter()))
    }

    /// Places one clip, and everything inside it if it is a nest clip, into
    /// `out`.
    ///
    /// `offset` is the project time this container's zero sits at, `window`
    /// the span the nest clips above allow through, and `inside` the chain
    /// of those nest clips. Recursion is bounded by [`MAX_NEST_DEPTH`]
    /// whatever the project says: `Project::validate` refuses a deeper stack
    /// and refuses a cycle, but this walk is reachable from
    /// `frame_recipe`, which is TOTAL, so it defends itself rather than
    /// trusting a caller to have validated.
    fn expand<'a>(
        &'a self,
        clip: &'a Clip,
        track: &'a Track,
        offset: Ticks,
        window: (Ticks, Ticks),
        inside: &[Enclosing<'a>],
        out: &mut Vec<Instance<'a>>,
    ) {
        let origin = clip.start.saturating_add(offset);
        let start = origin.max(window.0);
        let end = origin.saturating_add(clip.duration.max(0)).min(window.1);
        // A clip a nest clip's edge cut away entirely plays nowhere.
        if end <= start {
            return;
        }

        let Source::Nest { project } = &clip.source else {
            out.push(Instance {
                clip,
                track,
                origin,
                start,
                end,
                inside: inside.to_vec(),
            });
            return;
        };

        if inside.len() >= MAX_NEST_DEPTH as usize {
            return;
        }
        // A dangling nest id is what `validate` calls "refers to unknown
        // nest"; reaching one here means the project was never validated, so
        // the clip simply shows nothing rather than panicking.
        let Some(nest) = self.nest(*project) else {
            return;
        };

        let mut deeper = inside.to_vec();
        deeper.push(Enclosing {
            clip,
            track,
            nest,
            origin,
            start,
            end,
        });
        for inner_track in &nest.tracks {
            for inner in clips_on(&nest.clips, inner_track.id) {
                // The nest's zero is the nest clip's first frame, and its
                // contents may not outlive the part of the clip that plays.
                self.expand(inner, inner_track, origin, (start, end), &deeper, out);
            }
        }
    }
}

// ---- folding a nest's transform ------------------------------------------

/// A number that will be drawn with, or a neutral one. Everything reaching
/// here has already been clamped by `evaluate_clip` (spec §5.4), so this
/// only stops arithmetic on a value that clamping cannot rescue — an
/// infinite offset times a zero scale — from reaching the recipe as `null`.
fn finite(value: f64, fallback: f64) -> f64 {
    if value.is_finite() {
        value
    } else {
        fallback
    }
}

/// Turns `(x, y)` by `degrees` CLOCKWISE. Canvas space is y-down (spec
/// §5.3), so the textbook rotation matrix already turns clockwise on screen
/// — which is what a positive `rotation` means everywhere else in Reelcut,
/// and what `Compositor.metal`'s `rotate2` does with the same sign.
///
/// `pub(crate)` because it is the crate's ONE rotation: `edit_zoom.rs`
/// solves the placement rule for a region and needs the same sense, and a
/// second copy of four lines of trigonometry is exactly how two halves of
/// one editor come to disagree about which way is clockwise.
pub(crate) fn rotate(x: f64, y: f64, degrees: f64) -> (f64, f64) {
    let (sin, cos) = degrees.to_radians().sin_cos();
    (cos * x - sin * y, sin * x + cos * y)
}

/// The rotated rectangle a layer is clipped to, in CANVAS pixels, with
/// `x`/`y` its CENTRE measured from the canvas's top-left corner and
/// `rotation` in degrees clockwise (spec §7.3, `clip_rect`).
///
/// That frame is not the canvas-centre one a layer's `x`/`y` use: it is the
/// canvas's own top-left frame, which is what makes the rectangle cheap to
/// test — but the fragment stage does NOT arrive in it, and the sentence
/// that used to say so here cost road map 2's phase 8 a blocker. A fragment
/// arrives in DESTINATION pixels, which equalled canvas pixels for as long
/// as nothing but the canvas size was ever asked of the renderer; Preview
/// Quality asks for less, and a rectangle in canvas pixels tested against a
/// halved coordinate is magnified about the origin, which erased three
/// quarters of a nest at Half and all of it at Quarter. Swift now carries
/// canvas-pixels-per-destination-pixel in the uniform block and the shader
/// converts once. Nothing here changed; the RENDERER's side of the contract
/// did, and this paragraph is the contract.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub(crate) struct ClipRect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
    pub rotation: f64,
}

/// The transform a container hands to everything inside it: where its canvas
/// centre sits (an offset from the PROJECT canvas centre, in canvas pixels),
/// the scale and rotation its contents inherit, the opacity they are
/// multiplied by, and the rectangle they are clipped to.
///
/// The timeline is [`Frame::TOP`] — the identity, clipped to nothing.
/// Entering a nest clip composes that clip's own transform onto it
/// ([`Frame::enter`]), and every layer inside is then placed through the
/// result ([`Frame::place`]).
///
/// **Why this is exact.** Every transform here is a similarity — uniform
/// scale, rotation, translation — and similarities compose to similarities,
/// so a nested layer's flattened placement is not an approximation of what
/// rendering the nest to an offscreen buffer and transforming that would
/// give: it is the same picture, with no intermediate render target and no
/// resampling. **Four things do NOT survive the flattening**, and the first
/// two are noted in the recipe's own docs:
///
/// 1. A nest clip's `opacity` multiplies each inner layer separately rather
///    than the composite, so inner layers that overlap each other show
///    through.
/// 2. Only the innermost `clip_rect` is carried, because the recipe gives a
///    layer one rectangle and the intersection of two rotated rectangles is
///    not one.
/// 3. **A nest clip's own PER-PIXEL properties reach no layer at all.**
///    What folds down is what this struct holds — x, y, scale, rotation,
///    opacity, and the crop, as the nest's clipping rect. Everything else
///    in the nest clip's `video` group is dropped: its filters, its colour
///    controls, its chroma key, its shadow, its reflection, its spotlight,
///    its hidden regions and its blend. A nest clip never becomes a layer,
///    so `recipe.rs::layer` reads every one of those off the INNER clip and
///    never off the container. Two ops refuse rather than let that be
///    silent — `edit_props.rs`'s `check_blend` on `video.blend`, backed by
///    `clamp_video` for an end patch, and `edit_background.rs`'s
///    `add_blurred_background`, whose whole product is a filter — and the
///    rest are dropped without a word, which is a debt this doc records
///    rather than a rule it states.
/// 4. **A blend on a clip INSIDE a nest composites against the whole
///    canvas**, not against the nest's own picture, for the same reason
///    there is no intermediate render target: the layer is placed on the
///    project canvas and blends with whatever is already there, including
///    everything painted behind the nest clip. It is allowed, because
///    refusing it would make grouping change how a look reads; it is an
///    honest limit (spec §5.3), not an oversight.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Frame {
    pub x: f64,
    pub y: f64,
    pub scale: f64,
    pub rotation: f64,
    pub opacity: f64,
    pub clip_rect: Option<ClipRect>,
}

impl Frame {
    /// The project canvas itself: no offset, no scale, nothing clipped.
    pub const TOP: Frame = Frame {
        x: 0.0,
        y: 0.0,
        scale: 1.0,
        rotation: 0.0,
        opacity: 1.0,
        clip_rect: None,
    };

    /// A layer placed in this frame, as the recipe must publish it:
    /// scales multiply, rotations add, opacities multiply, and the layer's
    /// own offset is scaled and turned by the frame before it is added to
    /// it (spec §5.3).
    pub fn place(&self, video: &VideoProps) -> Frame {
        let (dx, dy) = rotate(
            finite(video.x, 0.0) * self.scale,
            finite(video.y, 0.0) * self.scale,
            self.rotation,
        );
        Frame {
            x: finite(self.x + dx, 0.0),
            y: finite(self.y + dy, 0.0),
            scale: finite(self.scale * finite(video.scale, 1.0), 1.0),
            rotation: finite(self.rotation + finite(video.rotation, 0.0), 0.0),
            opacity: finite(self.opacity * finite(video.opacity, 1.0), 1.0),
            clip_rect: self.clip_rect,
        }
    }

    /// The frame INSIDE a nest clip: the clip's own placement, plus the
    /// nest's canvas rect as what everything in it is clipped to.
    ///
    /// The rect is the nest's canvas after the clip's crop, which is why the
    /// crop is read here and nowhere else in the fold: cropping a nest clip
    /// means showing less of the nest, and it removes edges in place (spec
    /// §5.3), so the remaining rectangle's centre moves by half the
    /// difference of each pair of opposite insets.
    pub fn enter(&self, video: &VideoProps, nest: &Nest, canvas: &Canvas) -> Frame {
        let mut inner = self.place(video);
        let crop = video.crop;
        let width = f64::from(nest.width) - finite(crop.l, 0.0) - finite(crop.r, 0.0);
        let height = f64::from(nest.height) - finite(crop.t, 0.0) - finite(crop.b, 0.0);
        let (dx, dy) = rotate(
            finite(crop.l - crop.r, 0.0) / 2.0 * inner.scale,
            finite(crop.t - crop.b, 0.0) / 2.0 * inner.scale,
            inner.rotation,
        );
        inner.clip_rect = Some(ClipRect {
            x: finite(f64::from(canvas.width) / 2.0 + inner.x + dx, 0.0),
            y: finite(f64::from(canvas.height) / 2.0 + inner.y + dy, 0.0),
            w: finite(width.max(1.0) * inner.scale, 1.0),
            h: finite(height.max(1.0) * inner.scale, 1.0),
            rotation: inner.rotation,
        });
        inner
    }
}
