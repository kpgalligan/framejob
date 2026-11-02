//! Text Behind Subject at one instant (spec §11 CO-50, CO-51; §7.3): which
//! cut-out layers are behind each clip with `video.behind_subject`, the
//! SUBJECT COPIES that draw them into matte groups, and those groups merged
//! into the recipe's `matte` and `mattes` after the track groups.
//!
//! ### The relation
//!
//! A **subject** is a covering instance whose layer's `cutout` is non-null
//! and which is not drawn into a matte (`background` `remove` or `keep`
//! alike: a kept background still has a person in front of the room). A
//! **behind layer** is an instance not drawn into a matte and not an
//! adjustment clip whose evaluated `video.behind_subject` is true. Subject L
//! is behind B when, with d = B's nest depth, L is at least as deep, L's
//! first d enclosing nest clips are B's, and L's level-d track — its own
//! when L's depth is d, else its d-th enclosing nest clip's — has a lower
//! index than B's track in that container's tracks. So a subject inside a
//! nest behind a top-level title cuts it, and a top-level camera never cuts
//! a title inside a nest (the nest's composite is one picture to the
//! timeline; the title is not in it). No clip names another, so no edit
//! breaks the relation.
//!
//! ### The contract with the compositor
//!
//! A subject cutting at least one behind layer is LISTED. Listed subjects
//! take group ids n, n + 1, … in instance order, n one past the largest id
//! any layer's `matte` names (0 with none), so the track groups
//! (`recipe_matte.rs`) keep their ids and order. Each listed subject gets a
//! copy inserted directly after it — the original layer with exactly
//! `blend: "normal"`, `shadow: null`, `reflection: null`,
//! `cutout.background: "remove"`, `cutout.subject_copy: true` (appended) and
//! `matte: {into: s, cut: <the original's track-matte cut>}`, every other
//! key kept (CO-51, MT-4's third override) — whose Show Selection fact is
//! drawn-into. Each behind layer's `matte` gains its subjects' ids in `cut`,
//! ascending; each group `{group: s, mode: "alpha_inverted"}` is appended to
//! `mattes` after every track group. A frame with no behind layer cut by a
//! subject comes back exactly as it went in, so its bytes are what they
//! were before the flag existed.

use serde_json::{Map, Value};

use crate::edit_adjustment::is_adjustment;
use crate::evaluate::json;
use crate::model::{Project, Track, TrackMatte};
use crate::nest::Instance;
use crate::recipe_selection::LayerFacts;
use crate::time::Ticks;

/// Whether a layer object carries a cutout (`cutout` non-null).
fn has_cutout(layer: &Value) -> bool {
    layer.get("cutout").is_some_and(|c| !c.is_null())
}

/// The ids a layer's `matte` names, `into` and `cut` alike.
fn named_ids(layer: &Value) -> impl Iterator<Item = u64> + '_ {
    let matte = layer.get("matte");
    let into = matte.and_then(|m| m.get("into")).and_then(Value::as_u64);
    let cut = matte
        .and_then(|m| m.get("cut"))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_u64);
    into.into_iter().chain(cut)
}

/// The track-matte cut of a layer: its `matte.cut`, or none.
fn track_cut(layer: &Value) -> Value {
    layer
        .get("matte")
        .and_then(|m| m.get("cut"))
        .cloned()
        .unwrap_or_else(|| Value::Array(Vec::new()))
}

/// The subject copy of `layer`, drawn into group `group` (CO-51).
fn subject_copy(layer: &Value, group: u64) -> Value {
    let mut copy = layer.clone();
    if let Value::Object(object) = &mut copy {
        let mut matte = Map::new();
        matte.insert("into".to_string(), Value::from(group));
        matte.insert("cut".to_string(), track_cut(layer));
        object.insert("blend".to_string(), Value::from("normal"));
        object.insert("shadow".to_string(), Value::Null);
        object.insert("reflection".to_string(), Value::Null);
        object.insert("matte".to_string(), Value::Object(matte));
        if let Some(Value::Object(cutout)) = object.get_mut("cutout") {
            cutout.insert("background".to_string(), Value::from("remove"));
            cutout.insert("subject_copy".to_string(), Value::Bool(true));
        }
    }
    copy
}

/// `layer`'s `matte` with `ids` added to its `cut`, ascending.
fn cut_by(layer: &mut Value, ids: &[u64]) {
    let Value::Object(object) = layer else {
        return;
    };
    let mut cut: Vec<u64> = object
        .get("matte")
        .and_then(|m| m.get("cut"))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_u64)
        .collect();
    cut.extend_from_slice(ids);
    cut.sort_unstable();
    let into = object
        .get("matte")
        .and_then(|m| m.get("into"))
        .cloned()
        .unwrap_or(Value::Null);
    let mut matte = Map::new();
    matte.insert("into".to_string(), into);
    matte.insert(
        "cut".to_string(),
        Value::Array(cut.into_iter().map(Value::from).collect()),
    );
    object.insert("matte".to_string(), Value::Object(matte));
}

impl Project {
    /// The subjects at the instant `instances` cover, merged into the
    /// recipe's layers, their Show Selection facts and `mattes` (module
    /// doc). `layers` and `facts` are aligned with `instances`; the answer's
    /// two lists are aligned with each other.
    pub(crate) fn frame_subjects(
        &self,
        instances: &[Instance<'_>],
        t: Ticks,
        layers: Vec<Value>,
        facts: Vec<LayerFacts>,
        mattes: Value,
    ) -> (Vec<Value>, Vec<LayerFacts>, Value) {
        // The cheap test first: no cutout on the frame, nothing to evaluate.
        if !layers.iter().any(has_cutout) {
            return (layers, facts, mattes);
        }
        let drawn_into = |i: usize| facts.get(i).is_some_and(|f| f.drawn_into);
        let behind: Vec<usize> = instances
            .iter()
            .enumerate()
            .filter(|(i, instance)| {
                !drawn_into(*i)
                    && !is_adjustment(instance.clip)
                    && self
                        .evaluate_clip(instance.clip, instance.clip_time(t))
                        .video
                        .behind_subject
            })
            .map(|(i, _)| i)
            .collect();
        if behind.is_empty() {
            return (layers, facts, mattes);
        }
        let subjects: Vec<usize> = (0..instances.len())
            .filter(|i| !drawn_into(*i) && layers.get(*i).is_some_and(has_cutout))
            .collect();

        // Which subjects cut which behind layers; a subject is listed only
        // when it cuts one.
        let mut cuts: Vec<Vec<usize>> = vec![Vec::new(); instances.len()];
        let mut listed: Vec<usize> = Vec::new();
        for &s in &subjects {
            let Some(subject) = instances.get(s) else {
                continue;
            };
            let mut any = false;
            for &b in &behind {
                let Some(target) = instances.get(b) else {
                    continue;
                };
                if self.subject_behind(subject, target) {
                    if let Some(list) = cuts.get_mut(b) {
                        list.push(s);
                    }
                    any = true;
                }
            }
            if any {
                listed.push(s);
            }
        }
        if listed.is_empty() {
            return (layers, facts, mattes);
        }

        let first = layers
            .iter()
            .flat_map(named_ids)
            .max()
            .map_or(0, |largest| largest + 1);
        let group_of = |s: usize| -> Option<u64> {
            listed
                .iter()
                .position(|l| *l == s)
                .map(|k| first + k as u64)
        };

        let mut out_layers = Vec::with_capacity(layers.len() + listed.len());
        let mut out_facts = Vec::with_capacity(layers.len() + listed.len());
        for (i, (mut layer, fact)) in layers.into_iter().zip(facts).enumerate() {
            let copy = group_of(i).map(|group| (subject_copy(&layer, group), fact.clip));
            if let Some(list) = cuts.get(i).filter(|list| !list.is_empty()) {
                let ids: Vec<u64> = list.iter().filter_map(|s| group_of(*s)).collect();
                cut_by(&mut layer, &ids);
            }
            out_layers.push(layer);
            out_facts.push(fact);
            if let Some((copy, clip)) = copy {
                out_layers.push(copy);
                out_facts.push(LayerFacts {
                    clip,
                    top_adjustment: false,
                    drawn_into: true,
                });
            }
        }

        let mut groups = match mattes {
            Value::Array(groups) => groups,
            _ => Vec::new(),
        };
        for k in 0..listed.len() {
            let mut entry = Map::new();
            entry.insert("group".to_string(), Value::from(first + k as u64));
            entry.insert("mode".to_string(), json(&TrackMatte::AlphaInverted));
            groups.push(Value::Object(entry));
        }
        (out_layers, out_facts, Value::Array(groups))
    }

    /// Whether `subject` is behind `behind` in `behind`'s own container
    /// (module doc): at least as deep, inside the same nest clips down to
    /// `behind`'s depth, and on a track (at that depth) behind its track.
    fn subject_behind(&self, subject: &Instance<'_>, behind: &Instance<'_>) -> bool {
        let depth = behind.inside.len();
        if subject.inside.len() < depth {
            return false;
        }
        let same_nests = subject
            .inside
            .iter()
            .zip(&behind.inside)
            .all(|(s, b)| s.clip.id == b.clip.id);
        if !same_nests {
            return false;
        }
        let level_track = match subject.inside.get(depth) {
            Some(enclosing) => enclosing.track.id,
            None => subject.track.id,
        };
        let tracks: &[Track] = match depth.checked_sub(1) {
            Some(up) => match behind.inside.get(up) {
                Some(enclosing) => &enclosing.nest.tracks,
                None => return false,
            },
            None => &self.tracks,
        };
        let index = |id: u32| tracks.iter().position(|t| t.id == id);
        match (index(level_track), index(behind.track.id)) {
            (Some(subject_index), Some(behind_index)) => subject_index < behind_index,
            _ => false,
        }
    }
}
