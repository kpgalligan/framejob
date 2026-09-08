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

use serde_json::{Map, Value};

use crate::actions::Evaluated;
use crate::evaluate::{json, number, Assignment};
use crate::model::{Clip, Project, Source, TransitionKind};
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
        // rebasing the animation on it.
        let evaluated = self.evaluate_clip(instance.clip, instance.clip_time(t));
        let video = &evaluated.video;
        let (source, source_size) = self.layer_source(instance, &evaluated, assignment);
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
                let description = json(&text);
                let mut source = Map::new();
                source.insert("kind".to_string(), Value::from("text"));
                source.insert("hash".to_string(), Value::from(content_hash(&description)));
                source.insert("text".to_string(), description);
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
