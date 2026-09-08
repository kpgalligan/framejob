//! The frame recipe (spec §7.3): the back-to-front layer list at one
//! instant, every property already resolved through actions.
//!
//! The other half of what the platform consumes; `evaluate.rs` holds the
//! composition plan and the A/B assignment both halves share. They are split
//! because they change on different things — the plan is structural and is
//! rebuilt only when its JSON differs, the recipe is asked for once per
//! composed frame and again by the canvas overlay for hit-testing — but they
//! must agree about ONE fact, the composition track a clip's video lands on,
//! and that is why [`Project::assign`] lives in one place and is called from
//! both.
//!
//! The recipe is TOTAL: any project, any `t`, including a negative one, one
//! past the end, and one in a project with no clips at all.
//!
//! ### Nests are flattened here
//!
//! A nest clip never draws itself. It contributes one layer per drawing clip
//! inside it that is visible at `t`, with its own transform folded into each
//! of them and its canvas rect as their `clip_rect` (spec §5.3, §7.3). The
//! fold is [`Frame`]'s, and it is exact — every transform involved is
//! a similarity — so no intermediate render target is needed and the
//! compositor draws a nested layer with the same pass it draws any other.
//!
//! ### A text animation becomes a number here
//!
//! `text.animation` (spec §5.2) says what the animation IS; this file turns
//! it into what is showing NOW — a `reveal` in 0..1, a `reveal_phase` and a
//! `reveal_kind` — because everything that draws a frame reads this one
//! description and nothing else, so preview, `render_frame` and an export
//! cannot disagree about it. See [`Reveal`], and [`text_hash`] for why the
//! layer's content hash has to cover the answer.

use serde_json::{Map, Value};

use crate::actions::Evaluated;
use crate::evaluate::{json, number, Assignment};
use crate::model::{
    BlendMode, Clip, Project, Source, TextAnimation, TextAnimationKind, TransitionKind,
};
use crate::nest::{Frame, Instance};
use crate::time::Ticks;
use crate::transition;

/// FNV-1a, 64-bit. A CACHE KEY, not a security digest: Swift keys its
/// rendered text and shape textures by this hex string, so all that is
/// asked of it is that the same description always produces the same key
/// and that two different descriptions rarely collide. FNV is a dozen lines
/// with no dependency, which is the whole reason it is here rather than a
/// real hash crate.
const FNV_OFFSET: u64 = 0xcbf2_9ce4_8422_2325;
const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;

fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash = FNV_OFFSET;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    hash
}

/// The content hash of a rendered layer's description. Hashing the
/// serialized `Value` is what makes it canonical: `serde_json` writes an
/// object's keys in one fixed order, so two clips with identical text
/// always hash the same and share one texture.
fn content_hash(description: &Value) -> String {
    format!("{:016x}", fnv1a(description.to_string().as_bytes()))
}

/// How much of a text layer is showing at one instant, and which half of
/// its animation is showing it (spec §5.2's `text.animation`, §7.3).
///
/// The core decides this and the platform only draws it, which is the whole
/// reason it is computed here: preview, `render_frame` and both export
/// writers read ONE recipe, so they cannot disagree about how far a reveal
/// has got. It is derived from an animation, a clip time and a duration and
/// from nothing else — no clip, no instance — so a layer the core
/// synthesizes rather than reads off a clip can simply not have one.
#[derive(Debug, Clone, Copy)]
struct Reveal {
    /// 0 (nothing showing) through 1 (all of it), the un-reveal folded in.
    amount: f64,
    /// `"in"` while the arrival is what is holding the amount back, `"out"`
    /// once the departure is, and `None` for a layer with no animation at
    /// all — whose amount is always 1. A TENT is the exception and
    /// [`Reveal::of`] argues it: a clip too short to complete its arrival
    /// keeps one word for its whole life.
    ///
    /// The word is not decoration: one number cannot say whether a
    /// typewriter is typing or un-typing, and a line rise falls rather than
    /// rises on the way out. `transition`'s `role` is the same idea one
    /// function away, and adding this later would be a change to a shipped
    /// recipe key rather than a new one.
    phase: Option<&'static str>,
    /// Which of the three reveals this is, or `None` for a layer with no
    /// animation.
    ///
    /// It is carried because the description no longer is: the recipe
    /// strips `animation` out of the text it hands over (see
    /// [`Project::layer_source`]), so this is the renderer's ONLY word for
    /// which drawing routine to run — each kind is a different routine, not
    /// a parameter of a shared one. Carried by NAME, as the schema spells
    /// it, so the recipe never depends on the enum's declaration order.
    kind: Option<TextAnimationKind>,
}

impl Reveal {
    /// A layer with no animation: all of it, all of the time.
    const WHOLE: Reveal = Reveal {
        amount: 1.0,
        phase: None,
        kind: None,
    };

    /// The reveal `clip_t` ticks into a clip that is `duration` long.
    ///
    /// Both halves are measured against the CLIP's own duration, never the
    /// instance's visible span — the rule [`Project::layer`] already states
    /// for clip time. A nest clip's edge therefore cuts a nested caption off
    /// mid-reveal instead of making it un-reveal early, and the two halves
    /// of one animation are measured on one clock rather than two.
    ///
    /// The two ramps are combined with `min`, so `in + out > duration`
    /// degrades rather than refusing: the reveal becomes a tent that never
    /// reaches 1, stays inside 0..1 and simply shows a short clip a partial
    /// reveal. Nothing here refuses, and nothing clamps the animation to
    /// fit — a range check is a fact about the vocabulary
    /// (`props_check.rs`), while "these two numbers are too big for THIS
    /// clip" is a fact about a clip, which a later trim could invalidate
    /// anyway.
    ///
    /// A tent keeps ONE phase for its whole life, and that is the second
    /// half of the same argument: the phase is what the renderer staggers
    /// by, so the instant the word turns is an instant the picture mirrors,
    /// and a tent has no instant where mirroring is invisible. The `plateau`
    /// comment below has it in full.
    fn of(animation: Option<&TextAnimation>, clip_t: Ticks, duration: Ticks) -> Reveal {
        let animation = match animation {
            Some(animation) => animation,
            None => return Reveal::WHOLE,
        };
        let arriving = ramp(clip_t, animation.r#in);
        // The departure is measured back from the clip's EXCLUSIVE end, so
        // it reaches 0 one frame past the last frame anybody draws: the
        // last frame of an un-revealing clip still shows a sliver, which is
        // right — the clip is gone on the next one.
        let leaving = ramp(duration.saturating_sub(clip_t), animation.out);

        // The phase is not a label on the amount: it is the ORDER the
        // renderer staggers by. `LayerRenderers.staggerIndex` counts a
        // word_fade's words and a line_rise's lines from the other end while
        // a layer is leaving, so that the first word in is the first word
        // out. The word turning therefore MIRRORS the picture end for end,
        // and the only amount at which that is invisible is 1, where every
        // item is whole whichever end the stagger counted from.
        //
        // The two ramps meet at 1 only when the animation fits — when there
        // is a plateau between them, `in + out <= duration`. A TENT has
        // none: its ramps cross below 1, and turning the word at that peak
        // would swap a four-word cue's alphas from [1, 1, .83, .33] to
        // [.33, .83, 1, 1] between two consecutive frames whose amount did
        // not change at all. So a tent — which D-C7 lets degrade rather than
        // refuse — un-arrives the way it arrived, keeping the phase it began
        // in. That is the arrival's, unless the arrival is instant, which
        // makes the clip nothing but a departure and gives it no order to
        // contradict.
        let plateau = animation.r#in.saturating_add(animation.out) <= duration;
        let departing = if plateau {
            // A tie is the arrival's: it covers the whole middle of a clip
            // that is fully revealed and not yet leaving, and the first
            // instant of an out phase, which is on the plateau and draws the
            // same picture either way.
            leaving < arriving
        } else {
            animation.r#in <= 0
        };

        Reveal {
            amount: arriving.min(leaving),
            phase: Some(if departing { "out" } else { "in" }),
            kind: Some(animation.kind),
        }
    }
}

/// One phase's progress: how far `elapsed` has got through `over`, bounded
/// to 0..1.
///
/// A phase of zero length is complete from the start rather than a division
/// by zero, and so is a NEGATIVE one — which only an action end patch or a
/// hand-written file can produce, since `set_action_end` is deliberately
/// lenient and `clamp_video` does not touch text. This is where an absurd
/// value is caught, because this is where it is consumed.
fn ramp(elapsed: Ticks, over: Ticks) -> f64 {
    if over <= 0 {
        return 1.0;
    }
    let progress = elapsed.max(0) as f64 / over as f64;
    // Both sides are integers, so today this cannot be anything but finite.
    // The guard is one comparison and it fails toward SHOWING the text,
    // where `number()` would turn a non-finite amount into 0.0 and show
    // none of it.
    if progress.is_finite() {
        progress.clamp(0.0, 1.0)
    } else {
        1.0
    }
}

/// The cache key for a text layer: its description, and the reveal when
/// there is one.
///
/// The reveal changes the PIXELS, and this hash is the only thing standing
/// between a per-frame value and a stale texture — Swift caches a rendered
/// paragraph under `"text:" + hash` and consults nothing else — so a frame
/// at one reveal must not be able to collide with the same text at another.
/// A reveal that changed the picture without changing the key would render
/// correctly in a single `render_frame` and freeze during playback, with no
/// error anywhere.
///
/// All THREE computed keys go in, not just the amount: a word fade and a
/// typewriter half done are two different pictures of the same text, and so
/// are a half-arrived and a half-departed line rise.
///
/// A layer with NO animation hashes the bare description, byte for byte as
/// it did before format version 5, so no shipped project's texture cache
/// behaves differently after this phase. An ANIMATED layer keeps its own
/// key even at amount 1: whether a full reveal draws exactly what no
/// animation draws is the renderer's promise, and a cache key must not lean
/// on one.
fn text_hash(description: &Value, reveal: &Reveal) -> String {
    match reveal.phase {
        None => content_hash(description),
        Some(phase) => {
            let mut keyed = Map::new();
            keyed.insert("text".to_string(), description.clone());
            keyed.insert("reveal".to_string(), number(reveal.amount));
            keyed.insert("reveal_phase".to_string(), Value::from(phase));
            keyed.insert("reveal_kind".to_string(), reveal_kind(reveal));
            content_hash(&Value::Object(keyed))
        }
    }
}

/// The reveal's kind as the recipe carries it: the schema's own spelling of
/// the variant, or `null` for a layer with no animation.
fn reveal_kind(reveal: &Reveal) -> Value {
    match reveal.kind {
        Some(kind) => json(&kind),
        None => Value::Null,
    }
}

impl Project {
    /// The frame recipe at project time `t` (spec §7.3): the back-to-front
    /// layer list, every property already resolved through actions.
    ///
    /// A layer appears when `t` is inside `[start, start + duration)` — the
    /// half-open range that makes a cut show exactly one clip on the frame
    /// they share — its track is not hidden, and `enabled.video` is set.
    /// During a transition both clips are present and adjacent, each
    /// carrying the same kind and progress with opposite roles, because
    /// they are neighbours on one track and the layer list keeps track
    /// order.
    ///
    /// A NEST contributes one layer per drawing clip inside it that is
    /// visible at that instant, not one layer of its own: the nest clip's
    /// transform is folded into each of them and each carries the nest's
    /// canvas rect as its `clip_rect` (spec §5.3, §7.3).
    ///
    /// Total: `t` may be negative or past the end, and either simply
    /// produces no layers.
    pub fn frame_recipe(&self, t: Ticks) -> Value {
        let assignment = self.assign();

        let layers: Vec<Value> = self
            .drawing_instances()
            .into_iter()
            .filter(|i| i.covers(t))
            .map(|instance| self.layer(&instance, t, &assignment))
            .collect();

        let mut canvas = Map::new();
        canvas.insert("width".to_string(), Value::from(self.canvas.width));
        canvas.insert("height".to_string(), Value::from(self.canvas.height));
        canvas.insert(
            "background".to_string(),
            Value::Array(self.canvas.background.iter().map(|c| number(*c)).collect()),
        );

        let mut out = Map::new();
        out.insert("t".to_string(), Value::from(t));
        out.insert("canvas".to_string(), Value::Object(canvas));
        out.insert("layers".to_string(), Value::Array(layers));
        Value::Object(out)
    }

    /// One layer of the recipe.
    fn layer(&self, instance: &Instance, t: Ticks, assignment: &Assignment) -> Value {
        // Clip time: 0 is the clip's first frame, which is what actions are
        // measured in (spec §5.4). The clip's own first frame, not the
        // instance's — a nest clip's edge cuts a nested clip short without
        // rebasing the animation on it. Held in a local rather than
        // recomputed below, so a text reveal and the actions that produced
        // the props it reveals run off one clock.
        let clip_t = instance.clip_time(t);
        let evaluated = self.evaluate_clip(instance.clip, clip_t);
        let video = &evaluated.video;
        let (source, source_size) = self.layer_source(instance, &evaluated, clip_t, assignment);
        let frame = self.frame_of(instance, t);
        let placed = frame.place(video);

        let transition = match self.transition_of(instance, t) {
            Some((kind, progress, incoming, partner)) => {
                let mut entry = Map::new();
                entry.insert("kind".to_string(), json(&kind));
                entry.insert("progress".to_string(), number(progress));
                entry.insert(
                    "role".to_string(),
                    Value::from(if incoming { "in" } else { "out" }),
                );
                entry.insert("partner".to_string(), Value::from(partner));
                Value::Object(entry)
            }
            None => Value::Null,
        };

        let mut out = Map::new();
        out.insert("clip".to_string(), Value::from(instance.clip.id));
        out.insert("source".to_string(), source);
        out.insert("source_size".to_string(), source_size);
        // Crop, corner radius, the colour controls, the filters, the
        // reflection, the spotlight and the obscured regions are all in
        // SOURCE pixels or are per-pixel maths, so a nest's transform does
        // not touch them: only the placement is folded.
        out.insert("crop".to_string(), json(&video.crop));
        out.insert("x".to_string(), number(placed.x));
        out.insert("y".to_string(), number(placed.y));
        out.insert("scale".to_string(), number(placed.scale));
        out.insert("rotation".to_string(), number(placed.rotation));
        out.insert("opacity".to_string(), number(placed.opacity));
        // How this layer combines with what is already on the canvas
        // (format version 6) — and the ONE place that answer is overridden.
        //
        // A transition forces `normal`. The outgoing half of a dissolve
        // carries a weight correction that is the exact algebraic inverse of
        // the destination factor its incoming partner is about to apply, so
        // the pair sums to the picture either clip would have drawn alone,
        // and any non-normal blend on either half invalidates it. `add_clip`
        // onto an overlap gives the new clip a `cross_dissolve` by DEFAULT,
        // so that wrong picture is a minute away from anyone trying this.
        //
        // The CORE decides it, not the renderer, for [`Reveal`]'s reason
        // read again: everything that draws a frame reads this one
        // description, so preview, `render_frame` and both export writers
        // cannot disagree — and it is the only version PROVABLE the way this
        // project asks, a core test reading the layer's `blend` at a tick
        // inside the overlap where the shader's version needs two PNGs.
        //
        // Said out loud, because from either side alone it reads as a bug:
        // **the recipe's `blend` is what DRAWS, and the inspector reads the
        // MODEL's value through `clip_state`**, so during an overlap the
        // popup says `multiply` while the frame composites `normal`. Both
        // are honest — the clip multiplies, and this frame does not.
        out.insert(
            "blend".to_string(),
            if transition.is_null() {
                json(&video.blend)
            } else {
                json(&BlendMode::Normal)
            },
        );
        out.insert("corner_radius".to_string(), number(video.corner_radius));
        out.insert("shadow".to_string(), json(&video.shadow));
        out.insert("color".to_string(), json(&video.color));
        out.insert("chroma".to_string(), json(&video.chroma));
        out.insert("filters".to_string(), json(&video.filters));
        out.insert("reflection".to_string(), json(&video.reflection));
        out.insert("spotlight".to_string(), json(&video.spotlight));
        out.insert("obscure".to_string(), json(&video.obscure));
        // The rotated canvas rectangle this layer is clipped to, or null.
        // Only a layer out of a nest has one — the nest's own canvas rect,
        // in the place the nest clip put it.
        out.insert(
            "clip_rect".to_string(),
            match frame.clip_rect {
                Some(rect) => json(&rect),
                None => Value::Null,
            },
        );
        out.insert("transition".to_string(), transition);
        Value::Object(out)
    }

    /// The transform every nest clip above this instance composes to, at
    /// project time `t`. [`Frame::TOP`] for a timeline clip, which is the
    /// identity, so an unnested project is unaffected to the bit.
    ///
    /// Each nest clip's own props are evaluated through ITS actions at ITS
    /// clip time, so a move animated on a nest carries everything inside it.
    ///
    /// The chain is walked again for every layer inside a nest rather than
    /// once per nest — a few dozen extra `evaluate_clip` calls per frame at
    /// the depths anyone actually uses. A memo keyed by the path would save
    /// them and lives entirely inside one `frame_recipe` call, so it is
    /// worth adding the day a deep nest shows up in a profile.
    fn frame_of(&self, instance: &Instance, t: Ticks) -> Frame {
        let mut frame = Frame::TOP;
        for enclosing in &instance.inside {
            let evaluated = self.evaluate_clip(enclosing.clip, t.saturating_sub(enclosing.origin));
            frame = frame.enter(&evaluated.video, enclosing.nest, &self.canvas);
        }
        frame
    }

    /// The transition this layer is playing at `t`.
    ///
    /// A nested clip's own transition — with a neighbour inside the nest —
    /// wins, evaluated in the nest's own time base. Failing that, the layer
    /// inherits the transition of the nearest nest clip above it that has
    /// one, because a dissolve INTO a nest has to dissolve everything the
    /// nest draws; without it a nested layer would cut in at full opacity
    /// while its neighbour faded. The inherited `partner` names a clip that
    /// is not itself a layer (it was flattened too), which the compositor
    /// treats as no partner — the same answer it already gives for a
    /// transition whose partner is on a hidden track.
    fn transition_of(
        &self,
        instance: &Instance,
        t: Ticks,
    ) -> Option<(TransitionKind, f64, bool, u32)> {
        // A container's own time base: its zero sits at `origin - start`, so
        // this maps project time onto it for any clip in it.
        let local =
            |clip: &Clip, origin: Ticks| t.saturating_sub(origin).saturating_add(clip.start);

        let container = match instance.inside.last() {
            Some(innermost) => &innermost.nest.clips,
            None => &self.clips,
        };
        if let Some(found) = transition::transition_among(
            container,
            instance.clip.id,
            local(instance.clip, instance.origin),
        ) {
            return Some(found);
        }

        for (index, enclosing) in instance.inside.iter().enumerate().rev() {
            let outer = match index.checked_sub(1).and_then(|up| instance.inside.get(up)) {
                Some(above) => &above.nest.clips,
                None => &self.clips,
            };
            if let Some(found) = transition::transition_among(
                outer,
                enclosing.clip.id,
                local(enclosing.clip, enclosing.origin),
            ) {
                return Some(found);
            }
        }
        None
    }

    /// A layer's `source` and `source_size`.
    ///
    /// `track` means "sample composition video track N", the id the plan
    /// gave this clip; `image` means "decode this media with ImageIO";
    /// `text` and `shape` carry the resolved description plus the content
    /// hash Swift caches the rendered texture by; `missing` is the slate
    /// (spec §7.3).
    ///
    /// **The `missing` arms are defensive, not a feature path.** They fire
    /// for a clip whose media id is not in `media[]`, and
    /// [`Project::validate`] refuses exactly that, so no project the FFI
    /// can hand out reaches them. Spec §5.6's missing media is the FILE
    /// being gone with the `media[]` entry intact — the core has no
    /// filesystem, so it cannot see that; Swift substitutes the same
    /// `missing` source when an asset fails to load. Keeping these arms
    /// means one vocabulary for the slate rather than two, and means a
    /// future reader that tolerates a dangling id renders instead of
    /// panicking.
    fn layer_source(
        &self,
        instance: &Instance,
        evaluated: &Evaluated,
        clip_t: Ticks,
        assignment: &Assignment,
    ) -> (Value, Value) {
        let media_size = |media: u32| -> Value {
            match self.media(media) {
                Some(m) => Value::Array(vec![Value::from(m.width), Value::from(m.height)]),
                None => Value::Null,
            }
        };

        let clip = instance.clip;
        match &clip.source {
            Source::Media { media, .. } | Source::Still { media, .. } => {
                // By PATH: two clips may show one nest, and its contents
                // then play twice, on two composition tracks.
                match assignment.video_of.get(&instance.path()) {
                    Some(track_id) => {
                        let mut source = Map::new();
                        source.insert("kind".to_string(), Value::from("track"));
                        source.insert("track_id".to_string(), Value::from(*track_id));
                        (Value::Object(source), media_size(*media))
                    }
                    // Reachable only for media the project does not have:
                    // `drawing_clips` already dropped the clips whose media
                    // exists but carries no video.
                    None => (missing_source(), Value::Null),
                }
            }
            Source::Image { media } => {
                if self.is_missing_media(*media) {
                    return (missing_source(), Value::Null);
                }
                let mut source = Map::new();
                source.insert("kind".to_string(), Value::from("image"));
                source.insert("media".to_string(), Value::from(*media));
                (Value::Object(source), media_size(*media))
            }
            Source::Text => {
                // A text clip with no description is malformed rather than
                // impossible; the defaults keep the recipe renderable.
                let text = evaluated.text.clone().unwrap_or_default();
                let reveal = Reveal::of(text.animation.as_ref(), clip_t, clip.duration);
                let mut description = json(&text);
                // The animation is STRIPPED from the description carried
                // here: the computed reveal below is the only account of it
                // a renderer gets. Left in, it would be a second one — and
                // the wrong one, since nothing downstream has the clip time
                // to evaluate it against. Removing it also keeps an
                // unanimated clip's hash byte-identical to what it was
                // before format version 5. The inspector reads the
                // animation FIELD through `clip_state`; this description is
                // what draws.
                if let Some(map) = description.as_object_mut() {
                    map.remove("animation");
                }
                let mut source = Map::new();
                source.insert("kind".to_string(), Value::from("text"));
                source.insert(
                    "hash".to_string(),
                    Value::from(text_hash(&description, &reveal)),
                );
                source.insert("text".to_string(), description);
                // The three computed keys ride INSIDE the source object,
                // where the kind-specific description already lives, and
                // all three are emitted on every text layer whether it
                // animates or not: an absent key would mean two things — no
                // animation here, or an older core that never computed one
                // — which is the argument `obscure` settled one layer up. A
                // layer-level key instead would put a null on every layer
                // that can never carry one.
                //
                // Together they are the WHOLE of what a renderer is told
                // about the animation: which routine (`reveal_kind`), how
                // far (`reveal`), and which way (`reveal_phase`). The two
                // nulls always travel together — no kind means no phase
                // means an amount of 1.
                source.insert("reveal".to_string(), number(reveal.amount));
                source.insert(
                    "reveal_phase".to_string(),
                    match reveal.phase {
                        Some(phase) => Value::from(phase),
                        None => Value::Null,
                    },
                );
                source.insert("reveal_kind".to_string(), reveal_kind(&reveal));
                // Only the platform can lay text out, so the model has no
                // size to report (spec §5.3, §11).
                (Value::Object(source), Value::Null)
            }
            Source::Shape => {
                let shape = evaluated.shape.clone().unwrap_or_default();
                let description = json(&shape);
                let mut source = Map::new();
                source.insert("kind".to_string(), Value::from("shape"));
                source.insert("hash".to_string(), Value::from(content_hash(&description)));
                source.insert("shape".to_string(), description);
                let size = Value::Array(vec![number(shape.width), number(shape.height)]);
                (Value::Object(source), size)
            }
            // A nest is never a layer: the walk replaced it with the clips
            // inside it. Only a dangling nest id reaches here, which
            // `drawing_instances` has already dropped, so this arm exists
            // to keep the match exhaustive.
            Source::Nest { .. } => (missing_source(), Value::Null),
        }
    }
}

fn missing_source() -> Value {
    let mut source = Map::new();
    source.insert("kind".to_string(), Value::from("missing"));
    Value::Object(source)
}
