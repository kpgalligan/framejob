//! The frame recipe (spec §7.3): the back-to-front layer list at one
//! instant, every property already resolved through actions.
//!
//! The other half of what the platform consumes; `plan.rs` holds the
//! composition plan, `evaluate.rs` the A/B assignment both share. They are split
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
//! `text.animation` (spec §5.2) says what the animation IS; the recipe
//! turns it into what is showing NOW — a `reveal` in 0..1, a
//! `reveal_phase` and a `reveal_kind` — because everything that draws a
//! frame reads this one description and nothing else, so preview,
//! `render_frame` and an export cannot disagree about it. The arithmetic
//! is [`crate::recipe_text`]'s, a file away under the size rule; what
//! stays here is the layer it lands in and the `content_hash` it folds
//! into.
//!
//! ### A recipe can be asked for more than the instant
//!
//! [`RecipeOptions`] is what a caller wanted BESIDES `t`, and road map 2's
//! phase 7 gave it its first member: a timecode burn-in. The option is
//! served here rather than by the renderer for the reason above read once
//! more — a burnt frame and a previewed one must be one description — and
//! the layer it adds is APPENDED, so [`Project::frame_recipe`] with no
//! options is byte-for-byte the recipe this file emitted before the
//! argument existed. Grading GR3 gave it a second, `ungraded` (spec §11
//! GR-4), which writes every layer's `video.color` neutral rather than
//! adding a layer, so with it off the bytes are again what they were.
//! Grading-2 G2-4 gave it `selection` and `behind` (GR-13), answered by
//! `recipe_selection.rs` over the finished list before the burn-in.

use serde_json::{Map, Value};

use crate::actions::Evaluated;
use crate::edit_adjustment::is_adjustment;
use crate::evaluate::{json, number, Assignment};
use crate::model::{BlendMode, ColorAdjust, Curves, Nest, Project, Source, VideoProps, Wheels};
use crate::motion;
use crate::nest::{Enclosing, Frame, Instance};
use crate::recipe_graphic::graphic_source;
pub(crate) use crate::recipe_layer::RecipeLayer;
pub use crate::recipe_options::RecipeOptions;
use crate::recipe_selection::{select_layers, LayerFacts};
use crate::recipe_text::burn_in_layer;
use crate::time::Ticks;

/// A nest's frozen canvas as the pair `motion::apply` wants.
fn nest_size(nest: &Nest) -> (f64, f64) {
    (f64::from(nest.width), f64::from(nest.height))
}

/// The text layer's own arithmetic — [`Reveal`], the `text_hash` that
/// folds it into the cache key, and the [`text_source`] that assembles a
/// text layer's `source` object — lives in `recipe_text.rs` and is
/// re-exported here, so `crate::recipe::text_source` resolves as though
/// the cut had not happened. See that module's doc for the seam: placement
/// is the same question for every layer, and text is the one kind that is
/// not finished when its placement is.
pub(crate) use crate::recipe_text::text_source;

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

/// The content hash of a rendered layer's description, over its keys
/// SORTED at every depth: `serde_json`'s `Map` keeps insertion order in this
/// build (`graphic` turns `preserve_order` on), so the sort is what makes
/// two clips with identical text hash the same and share one texture — and
/// it is the order every hash before the link was taken in.
pub(crate) fn content_hash(description: &Value) -> String {
    format!("{:016x}", fnv1a(sorted(description).to_string().as_bytes()))
}

/// `value` with every object's keys in sorted order, recursively.
fn sorted(value: &Value) -> Value {
    match value {
        Value::Object(map) => {
            let keys: std::collections::BTreeMap<&String, Value> =
                map.iter().map(|(k, v)| (k, sorted(v))).collect();
            Value::Object(keys.into_iter().map(|(k, v)| (k.clone(), v)).collect())
        }
        Value::Array(items) => Value::Array(items.iter().map(sorted).collect()),
        other => other.clone(),
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
        self.frame_recipe_opts(t, RecipeOptions::default())
    }

    /// [`Project::frame_recipe`] with the caller's [`RecipeOptions`].
    ///
    /// There is ONE implementation and `frame_recipe` is a call to it with
    /// the default options, so the two cannot drift: a key added to a layer
    /// for one caller is in the other's recipe by construction. That matters
    /// more here than it usually would, because the un-optioned answer is
    /// what preview, the overlay's hit-test and every earlier phase's proof
    /// PNG are built on, and a second copy of this fold is exactly how one
    /// of them starts drawing a different frame from the other.
    ///
    /// The burn-in is APPENDED, last, so it is topmost — a timecode under
    /// the picture is a timecode nobody can read, and appending is also what
    /// makes the un-optioned recipe byte-for-byte what it was before the
    /// argument existed. `core/tests/recipe.rs` asserts both halves: the
    /// bytes with the option off, and that dropping the last layer of a
    /// burnt recipe gives back the plain one exactly.
    pub fn frame_recipe_opts(&self, t: Ticks, opts: RecipeOptions) -> Value {
        let assignment = self.assign();

        // The covering instances, collected once: the mattes are a relation
        // between them (`recipe_matte.rs`), answered per instance in order.
        // An adjustment clip on a matte track is inert (spec §11 GR-6): it
        // is dropped here, before the mattes are answered, so it cuts nothing.
        let instances: Vec<Instance> = self
            .drawing_instances()
            .into_iter()
            .filter(|i| i.covers(t) && !self.inert_adjustment(i))
            .collect();
        let mattes = self.frame_mattes(&instances);
        // So are the routed dissolves (`recipe_dissolve.rs`, spec §11 MT-8):
        // their ids are dense over the frame.
        let transitions = self.frame_transitions(&instances, t);
        let layers: Vec<Value> = instances
            .iter()
            .zip(mattes.drawn_into.iter().zip(mattes.layer))
            .zip(transitions.transition.into_iter().zip(transitions.dissolve))
            .map(
                |((instance, (drawn_into, matte)), (transition, dissolve))| {
                    let roles = LayerRoles {
                        drawn_into: *drawn_into,
                        matte,
                        transition,
                        dissolve,
                    };
                    self.layer(instance, t, &assignment, roles, opts.ungraded)
                },
            )
            .collect();
        // The qualifier's two options (spec §11 GR-13): a selection whose
        // clip is not on the frame draws no layers on black.
        let facts: Vec<LayerFacts> = instances
            .iter()
            .zip(mattes.drawn_into.iter())
            .map(|(instance, drawn_into)| LayerFacts {
                clip: instance.clip.id,
                top_adjustment: is_adjustment(instance.clip) && instance.inside.is_empty(),
                drawn_into: *drawn_into,
            })
            .collect();
        let (mut layers, black) = select_layers(layers, &facts, &opts);
        if opts.burn_in_timecode {
            layers.push(burn_in_layer(&self.canvas, t));
        }

        let mut canvas = Map::new();
        canvas.insert("width".to_string(), Value::from(self.canvas.width));
        canvas.insert("height".to_string(), Value::from(self.canvas.height));
        let background = if black {
            [0.0, 0.0, 0.0, 1.0]
        } else {
            self.canvas.background
        };
        canvas.insert(
            "background".to_string(),
            Value::Array(background.iter().map(|c| number(*c)).collect()),
        );

        let mut out = Map::new();
        out.insert("t".to_string(), Value::from(t));
        out.insert("canvas".to_string(), Value::Object(canvas));
        out.insert("layers".to_string(), Value::Array(layers));
        out.insert("mattes".to_string(), mattes.listed);
        Value::Object(out)
    }

    /// The canvas a clip enclosed by `inside` is placed IN — the innermost
    /// nest's frozen canvas, or the project's at the top level. What a
    /// slide measures itself against (`motion.rs`).
    fn container(&self, inside: &[Enclosing]) -> (f64, f64) {
        match inside.last() {
            Some(enclosing) => nest_size(enclosing.nest),
            None => (f64::from(self.canvas.width), f64::from(self.canvas.height)),
        }
    }

    /// One layer of the recipe, its roles in the frame given (`LayerRoles`);
    /// `ungraded` writes its `video.color` neutral and removes its look (spec
    /// §11 GR-4, GR-7).
    fn layer(
        &self,
        instance: &Instance,
        t: Ticks,
        assignment: &Assignment,
        roles: LayerRoles,
        ungraded: bool,
    ) -> Value {
        let LayerRoles {
            drawn_into,
            matte,
            transition,
            dissolve,
        } = roles;
        // Clip time: 0 is the clip's first frame, which is what actions are
        // measured in (spec §5.4). The clip's own first frame, not the
        // instance's — a nest clip's edge cuts a nested clip short without
        // rebasing the animation on it. Held in a local rather than
        // recomputed below, so a text reveal and the actions that produced
        // the props it reveals run off one clock.
        let clip_t = instance.clip_time(t);
        let evaluated = self.evaluate_clip(instance.clip, clip_t);
        // `video.motion` (format version 8) turned into placement (`moved`).
        // `moved` equals `evaluated.video` in every field but the five placed
        // ones, so `RecipeLayer.video` reads its per-pixel properties off it
        // and the recipe publishes no `motion` key.
        let mut moved = self.moved(instance, clip_t, &evaluated);
        // A matte layer's drop shadow and reflection do nothing (spec §11
        // MT-4): the matte is the clip's own picture, so they are cleared
        // here, with its blend below — the recipe's second deliberate
        // override of model values, decided by the core for the reason the
        // transition's `normal` is. The inspector still shows the model's.
        if drawn_into {
            moved.shadow = None;
            moved.reflection = None;
        }
        // The ungraded option (GR-4): the grade neutral before `RecipeLayer`,
        // the one writer of layer keys, so no key is added or dropped.
        if ungraded {
            moved.color = ColorAdjust::default();
            moved.wheels = Wheels::default();
            moved.curves = Curves::default();
            moved.look = None;
        }
        let video = &moved;
        let (source, source_size) = self.layer_source(instance, &evaluated, clip_t, assignment);
        let frame = self.frame_of(instance, t);
        let placed = frame.place(video);

        // How this layer combines with what is already on the canvas
        // (format version 6) — and the ONE place that answer is overridden,
        // which is why [`RecipeLayer`] takes it rather than reading it off
        // the props.
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
        //
        // A matte layer forces `normal` too (MT-4): what it draws into is a
        // cleared target of its own, and its blend mode does nothing there.
        // So does a routed dissolve (MT-8): its half is drawn alone and mixed,
        // as a transition's pair is, and the core says so in one place.
        let blend = if transition.is_null() && dissolve.is_null() && !drawn_into {
            video.blend
        } else {
            BlendMode::Normal
        };

        // Step 0's conversion is the MEDIA's (spec §11 GR-16): every clip of a
        // file, a still of it and its reverse alike, and the ungraded branch
        // above does not touch it.
        let input = match instance.clip.source {
            Source::Media { media, .. } | Source::Still { media, .. } => self.media_input(media),
            _ => Value::Null,
        };

        RecipeLayer {
            clip: instance.clip.id,
            source,
            source_size,
            video,
            placed,
            blend,
            transition,
            matte,
            dissolve,
            input,
        }
        .object()
    }

    /// Where `instance` is placed at `t`: its props moved by `video.motion`
    /// and folded through every nest clip above it — `layer`'s placement,
    /// asked again by `recipe_dissolve.rs` for a routed half's anchor.
    pub(crate) fn placement(&self, instance: &Instance, t: Ticks) -> Frame {
        let clip_t = instance.clip_time(t);
        let evaluated = self.evaluate_clip(instance.clip, clip_t);
        self.frame_of(instance, t)
            .place(&self.moved(instance, clip_t, &evaluated))
    }

    /// A clip's evaluated props with `video.motion` turned into placement —
    /// one of `motion::apply`'s two call sites, whose module doc is the whole
    /// argument; `layer` and `placement` both read it. Here and not in
    /// `evaluate_clip` on purpose (spec §11, R5-4).
    fn moved(&self, instance: &Instance, clip_t: Ticks, evaluated: &Evaluated) -> VideoProps {
        motion::apply(
            &evaluated.video,
            clip_t,
            instance.clip.duration,
            self.source_size(instance.clip),
            self.container(&instance.inside),
        )
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
    pub(crate) fn frame_of(&self, instance: &Instance, t: Ticks) -> Frame {
        let mut frame = Frame::TOP;
        for (i, enclosing) in instance.inside.iter().enumerate() {
            let clip_t = t.saturating_sub(enclosing.origin);
            let evaluated = self.evaluate_clip(enclosing.clip, clip_t);
            // A nest clip's own motion, folded into every layer inside it —
            // `motion::apply`'s second call site. Its SIZE is the nest's
            // frozen canvas and its CONTAINER is whatever encloses IT,
            // which is what the loop gained its index for.
            let size = Some(nest_size(enclosing.nest));
            let container = self.container(&instance.inside[..i]);
            let moved = motion::apply(
                &evaluated.video,
                clip_t,
                enclosing.clip.duration,
                size,
                container,
            );
            frame = frame.enter(&moved, enclosing.nest, &self.canvas);
        }
        frame
    }

    /// A layer's `source` and `source_size`.
    ///
    /// `track` means "sample composition video track N", the id the plan
    /// gave this clip; `image` means "decode this media with ImageIO";
    /// `text`, `shape` and `graphic` carry the resolved description plus the
    /// content hash Swift caches the rendered texture by; `missing` is the slate
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
                // Only the platform can lay text out, so the model has no
                // size to report (spec §5.3, §11).
                (text_source(&text, clip_t, clip.duration), Value::Null)
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
            Source::Graphic => graphic_source(clip, evaluated, clip_t, &self.canvas),
            // No picture and no size: the compositor grades the destination
            // with the layer's colour and filters (spec §11 GR-6), weighted
            // by its qualifier, published only when not neutral so an
            // unqualified recipe is what it was (GR-13).
            Source::Adjustment => {
                let mut source = Map::new();
                source.insert("kind".to_string(), Value::from("adjustment"));
                let qualifier = &evaluated.video.qualifier;
                if !qualifier.is_neutral() {
                    source.insert("qualifier".to_string(), json(qualifier));
                }
                (Value::Object(source), Value::Null)
            }
        }
    }
}

/// A layer's roles in the frame, each answered once per frame over the
/// covering instances: whether it is drawn into a matte rather than onto the
/// canvas and its `matte` key (`recipe_matte.rs`), and its `transition` and
/// `dissolve` (`recipe_dissolve.rs`, spec §11 MT-8).
struct LayerRoles {
    drawn_into: bool,
    matte: Value,
    transition: Value,
    dissolve: Value,
}

pub(crate) fn missing_source() -> Value {
    let mut source = Map::new();
    source.insert("kind".to_string(), Value::from("missing"));
    Value::Object(source)
}
