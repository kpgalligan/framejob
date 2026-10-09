//! The transitions a layer plays at one instant (spec §7.3, §11 MT-8): each
//! recipe layer's `transition` and `dissolve`.
//!
//! A layer inside `n` nest clips has `n + 1` LEVELS, walked inner to outer:
//! its own clip in the innermost container, then each enclosing nest clip in
//! ITS container, outward to the timeline. Each level asks
//! [`transition::transition_among`] — the one transition lookup — at that
//! container's own time.
//!
//! ### Routed and unrouted
//!
//! A `cross_dissolve` or `zoom` whose container is a nest, or one of whose
//! two clips is a nest clip, is ROUTED ([`routed`], the one predicate): the
//! compositor draws each half alone into a target of its own and mixes the
//! two (§7.5), because a half that is more than one layer — or a layer that
//! is not on the canvas, a nest clip — cannot carry the per-layer weight
//! correction a timeline pair does (MT-3). A routed level is an entry in the
//! layer's `dissolve`, never its `transition`; `transition` is the innermost
//! level's answer that is NOT routed, as `recipe.rs`'s `transition_of`
//! answered every kind before issue batch B90 moved its walk here. A push,
//! slide, wipe or fade is never routed: none applies a partner correction.
//!
//! ### The contract the compositor relies on
//!
//! `dissolve` is `null` or the routed levels, OUTERMOST first, each
//! `{id, kind, role, progress, anchor}`. A dissolve is one [`DissolveKey`]:
//! the nest clips enclosing its container, its earlier clip and its later
//! clip, so two clips showing one nest at one instant each have their own.
//! Ids are dense from 0 in first-seen order, walking layers back to front,
//! each chain outermost first. `anchor` is the canvas point (top-left frame)
//! the half is placed at: the layer's own anchor at its own level, the
//! centre of the nest's placed canvas rectangle at a nest clip's. A layer
//! drawn into a matte keeps only the routed levels at or inside its first
//! matte level — the matte is drawn whole, and the half it lies in fades it
//! once — while its `transition` is still sought outward.

use serde_json::{Map, Value};

use crate::evaluate::{json, number};
use crate::model::{Clip, Project, Source, TransitionKind};
use crate::nest::Instance;
use crate::time::Ticks;
use crate::transition;

/// One routed dissolve at one instant: the ids of the nest clips enclosing
/// its container, outermost first — an instance path's prefix — and its two
/// clips.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct DissolveKey {
    pub path: Vec<u32>,
    pub earlier: u32,
    pub later: u32,
}

/// What [`Project::frame_transitions`] answers: per instance, in the order
/// given, the layer's `transition` and its `dissolve`.
pub(crate) struct FrameTransitions {
    pub transition: Vec<Value>,
    pub dissolve: Vec<Value>,
}

/// Whether a transition is ROUTED (spec §11 MT-8): a `cross_dissolve` or a
/// `zoom` whose container is a nest (`in_nest`), or one of whose two clips is
/// a nest clip. `partner` is `None` when the container does not hold it.
pub(crate) fn routed(
    in_nest: bool,
    kind: TransitionKind,
    clip: &Clip,
    partner: Option<&Clip>,
) -> bool {
    let is_nest = |c: &Clip| matches!(c.source, Source::Nest { .. });
    let mixed = matches!(kind, TransitionKind::CrossDissolve | TransitionKind::Zoom);
    let nested = in_nest || is_nest(clip) || partner.is_some_and(is_nest);
    mixed && nested
}

/// One routed level before ids are given.
struct Routed {
    key: DissolveKey,
    kind: TransitionKind,
    progress: f64,
    incoming: bool,
    anchor: (f64, f64),
}

impl Project {
    /// The transitions at the instant `instances` cover (spec §7.3): one
    /// `transition` and one `dissolve` per instance, in their order. See the
    /// module doc for the contract.
    pub(crate) fn frame_transitions(
        &self,
        instances: &[Instance<'_>],
        t: Ticks,
    ) -> FrameTransitions {
        let walked: Vec<(Value, Vec<Routed>)> = instances
            .iter()
            .map(|i| self.transition_levels(i, t))
            .collect();

        let mut keys: Vec<DissolveKey> = Vec::new();
        let mut id_of = |key: &DissolveKey| -> usize {
            match keys.iter().position(|k| k == key) {
                Some(found) => found,
                None => {
                    keys.push(key.clone());
                    keys.len() - 1
                }
            }
        };

        let mut transition = Vec::with_capacity(walked.len());
        let mut dissolve = Vec::with_capacity(walked.len());
        for (found, chain) in walked {
            transition.push(found);
            dissolve.push(if chain.is_empty() {
                Value::Null
            } else {
                Value::Array(
                    chain
                        .iter()
                        .map(|level| dissolve_entry(id_of(&level.key), level))
                        .collect(),
                )
            });
        }
        FrameTransitions {
            transition,
            dissolve,
        }
    }

    /// One layer's levels walked inner to outer: its `transition` (the
    /// innermost unrouted answer) and its routed levels, outermost first.
    fn transition_levels(&self, instance: &Instance<'_>, t: Ticks) -> (Value, Vec<Routed>) {
        // A container's own time base: its zero sits at `origin - start`, so
        // this maps project time onto it for any clip in it.
        let local =
            |clip: &Clip, origin: Ticks| t.saturating_sub(origin).saturating_add(clip.start);

        let depth = instance.inside.len();
        let mut transition = Value::Null;
        let mut chain = Vec::new();
        let mut stopped = false;
        for level in (0..=depth).rev() {
            let (clip, origin, track) = if level == depth {
                (instance.clip, instance.origin, instance.track)
            } else {
                match instance.inside.get(level) {
                    Some(enclosing) => (enclosing.clip, enclosing.origin, enclosing.track),
                    None => break,
                }
            };
            let container: &[Clip] = match level.checked_sub(1) {
                Some(up) => match instance.inside.get(up) {
                    Some(enclosing) => &enclosing.nest.clips,
                    None => break,
                },
                None => &self.clips,
            };
            if let Some((kind, progress, incoming, partner)) =
                transition::transition_among(container, clip.id, local(clip, origin))
            {
                let other = container.iter().find(|c| c.id == partner);
                if routed(level > 0, kind, clip, other) {
                    if !stopped {
                        let path = instance.inside.iter().take(level).map(|e| e.clip.id);
                        let (earlier, later) = if incoming {
                            (partner, clip.id)
                        } else {
                            (clip.id, partner)
                        };
                        chain.push(Routed {
                            key: DissolveKey {
                                path: path.collect(),
                                earlier,
                                later,
                            },
                            kind,
                            progress,
                            incoming,
                            anchor: self.half_anchor(instance, level, t),
                        });
                    }
                } else if transition.is_null() {
                    transition = transition_entry(kind, progress, incoming, partner);
                }
            }
            // The first matte level ends the routed walk (MT-8): what is
            // drawn into a matte is drawn whole.
            if !track.matte.is_none() {
                stopped = true;
            }
        }
        chain.reverse();
        (transition, chain)
    }

    /// The canvas point (top-left frame) the half at `level` is placed at:
    /// the layer's own anchor at its own level, else the centre of the clip
    /// rectangle the nest clip at `level` gives its contents.
    fn half_anchor(&self, instance: &Instance<'_>, level: usize, t: Ticks) -> (f64, f64) {
        let width = f64::from(self.canvas.width);
        let height = f64::from(self.canvas.height);
        if level >= instance.inside.len() {
            let placed = self.placement(instance, t);
            return (width / 2.0 + placed.x, height / 2.0 + placed.y);
        }
        let mut entered = instance.clone();
        entered.inside.truncate(level + 1);
        match self.frame_of(&entered, t).clip_rect {
            Some(rect) => (rect.x, rect.y),
            None => (width / 2.0, height / 2.0),
        }
    }
}

/// A layer's `transition` object: `{kind, progress, role, partner}`.
fn transition_entry(kind: TransitionKind, progress: f64, incoming: bool, partner: u32) -> Value {
    let mut entry = Map::new();
    entry.insert("kind".to_string(), json(&kind));
    entry.insert("progress".to_string(), number(progress));
    entry.insert("role".to_string(), Value::from(role(incoming)));
    entry.insert("partner".to_string(), Value::from(partner));
    Value::Object(entry)
}

/// One `dissolve` entry: `{id, kind, role, progress, anchor}`.
fn dissolve_entry(id: usize, level: &Routed) -> Value {
    let mut entry = Map::new();
    entry.insert("id".to_string(), Value::from(id));
    entry.insert("kind".to_string(), json(&level.kind));
    entry.insert("role".to_string(), Value::from(role(level.incoming)));
    entry.insert("progress".to_string(), number(level.progress));
    entry.insert(
        "anchor".to_string(),
        Value::Array(vec![number(level.anchor.0), number(level.anchor.1)]),
    );
    Value::Object(entry)
}

fn role(incoming: bool) -> &'static str {
    if incoming {
        "in"
    } else {
        "out"
    }
}
