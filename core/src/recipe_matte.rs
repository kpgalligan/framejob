//! What the mattes do at one instant (spec §11 MT-2, MT-5; §7.3): each
//! recipe layer's `matte` — the group it is drawn INTO, if its track is a
//! matte, and the groups that CUT it — and the recipe's `mattes` list, the
//! groups the compositor draws before the destination pass (MT-6).
//!
//! A matte is read per instant and per pair of tracks: no clip names
//! another, so nothing here is stored and no edit can break a link. The
//! walk is over the [`Instance`]s the recipe already covers at `t` — the
//! drawing ones, so a hidden matte track or a clip with its video off has no
//! instance, draws into nothing, and leaves the track behind uncut (MT-2).
//!
//! ### Levels
//!
//! A layer inside `n` nest clips has `n + 1` LEVELS: its own track in the
//! innermost container, then each enclosing nest clip's track in ITS
//! container, outward to the timeline. Walking them inner to outer, the
//! first level whose track is a matte track makes the layer a matte source
//! (`into`), and no level outside it applies; every level before it whose
//! track is a matte's target cuts the layer (MT-5). A group is one
//! [`MatteKey`]: the matte track's id and the nest clips enclosing its
//! container, so two clips showing one nest at one instant each have their
//! own matte.
//!
//! ### The contract the compositor relies on
//!
//! Ids are dense from 0 in first-seen order, walking layers back to front,
//! a layer's `into` before its cuts. Every layer whose first matte level is
//! a matte track names its group in `into`, listed or not — that is how the
//! compositor knows not to draw it on the canvas. A group is LISTED when at
//! least one layer is drawn into it and at least one is cut by it; `cut`
//! names only listed groups, ascending; `mattes` runs deepest container
//! first (the longest path), then by id.

use serde_json::{Map, Value};

use crate::evaluate::json;
use crate::model::{Project, Track, TrackMatte};
use crate::nest::Instance;

/// The track a matte track cuts (MT-2): the track directly behind it in its
/// own container, when that track is not itself a matte track. `None` for an
/// ordinary track, a back-most matte track, a matte in front of a matte and
/// an id the container does not hold.
pub(crate) fn matte_target(tracks: &[Track], track: u32) -> Option<u32> {
    let index = tracks.iter().position(|t| t.id == track)?;
    let matte = tracks.get(index)?;
    if matte.matte.is_none() {
        return None;
    }
    let behind = tracks.get(index.checked_sub(1)?)?;
    behind.matte.is_none().then_some(behind.id)
}

/// The matte track whose target is `track`, if any: the track directly in
/// front of it, when [`matte_target`] answers `track` for it.
fn cutting_matte(tracks: &[Track], track: u32) -> Option<&Track> {
    let index = tracks.iter().position(|t| t.id == track)?;
    let front = tracks.get(index.checked_add(1)?)?;
    (matte_target(tracks, front.id) == Some(track)).then_some(front)
}

/// One matte at one instant (MT-5): the ids of the nest clips enclosing its
/// track's container, outermost first — an instance path's prefix — and the
/// matte track's id.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct MatteKey {
    pub path: Vec<u32>,
    pub track: u32,
}

/// What [`Project::frame_mattes`] answers: per instance, in the order given,
/// the layer's `matte` value and whether it is drawn into a matte (and so
/// never onto the canvas); and the recipe's `mattes` list.
pub(crate) struct FrameMattes {
    pub layer: Vec<Value>,
    pub drawn_into: Vec<bool>,
    pub listed: Value,
}

/// One layer's roles before ids are given: the matte it is drawn into, and
/// every matte whose target it sits on, innermost first.
struct Roles {
    into: Option<(MatteKey, TrackMatte)>,
    cuts: Vec<(MatteKey, TrackMatte)>,
}

impl Project {
    /// The mattes at the instant `instances` cover (spec §7.3): one entry
    /// per instance, in their order, and the listed groups. See the module
    /// doc for the contract.
    pub(crate) fn frame_mattes(&self, instances: &[Instance<'_>]) -> FrameMattes {
        let roles: Vec<Roles> = instances.iter().map(|i| self.matte_roles(i)).collect();

        // A group is listed when something is drawn into it AND something
        // is cut by it: a matte with nothing to cut, or a target with no
        // matte clip showing, costs the compositor nothing.
        let listed = |key: &MatteKey| {
            roles
                .iter()
                .any(|r| r.into.as_ref().is_some_and(|(k, _)| k == key))
                && roles.iter().any(|r| r.cuts.iter().any(|(k, _)| k == key))
        };

        let mut groups: Vec<(MatteKey, TrackMatte)> = Vec::new();
        let mut id_of = |key: &MatteKey, mode: TrackMatte| -> usize {
            match groups.iter().position(|(k, _)| k == key) {
                Some(found) => found,
                None => {
                    groups.push((key.clone(), mode));
                    groups.len() - 1
                }
            }
        };

        let mut layer = Vec::with_capacity(roles.len());
        let mut drawn_into = Vec::with_capacity(roles.len());
        for role in &roles {
            let into = role.into.as_ref().map(|(k, mode)| id_of(k, *mode));
            let mut cut: Vec<usize> = role
                .cuts
                .iter()
                .filter(|(k, _)| listed(k))
                .map(|(k, mode)| id_of(k, *mode))
                .collect();
            cut.sort_unstable();
            drawn_into.push(into.is_some());
            layer.push(if into.is_none() && cut.is_empty() {
                Value::Null
            } else {
                let mut entry = Map::new();
                entry.insert("into".to_string(), into.map_or(Value::Null, Value::from));
                entry.insert(
                    "cut".to_string(),
                    Value::Array(cut.into_iter().map(Value::from).collect()),
                );
                Value::Object(entry)
            });
        }

        // Deepest container first, so a matte drawn inside a nest is ready
        // before a matte that nest's composite belongs to; then by id.
        let mut order: Vec<usize> = (0..groups.len())
            .filter(|i| groups.get(*i).is_some_and(|(k, _)| listed(k)))
            .collect();
        order.sort_by_key(|i| {
            let depth = groups.get(*i).map_or(0, |(k, _)| k.path.len());
            (std::cmp::Reverse(depth), *i)
        });
        let mattes = order
            .into_iter()
            .filter_map(|i| groups.get(i).map(|(_, mode)| (i, *mode)))
            .map(|(id, mode)| {
                let mut entry = Map::new();
                entry.insert("group".to_string(), Value::from(id));
                entry.insert("mode".to_string(), json(&mode));
                Value::Object(entry)
            })
            .collect();

        FrameMattes {
            layer,
            drawn_into,
            listed: Value::Array(mattes),
        }
    }

    /// One layer's levels walked inner to outer (MT-5): the first matte
    /// track met is the layer's `into` and ends the walk; each level up to
    /// it whose track a matte targets adds that matte to the cuts.
    fn matte_roles(&self, instance: &Instance<'_>) -> Roles {
        let depth = instance.inside.len();
        let mut cuts = Vec::new();
        for level in (0..=depth).rev() {
            let track = if level == depth {
                instance.track
            } else {
                match instance.inside.get(level) {
                    Some(enclosing) => enclosing.track,
                    None => break,
                }
            };
            let tracks: &[Track] = match level.checked_sub(1) {
                Some(up) => match instance.inside.get(up) {
                    Some(enclosing) => &enclosing.nest.tracks,
                    None => break,
                },
                None => &self.tracks,
            };
            let path: Vec<u32> = instance
                .inside
                .iter()
                .take(level)
                .map(|e| e.clip.id)
                .collect();
            // Asked before the matte test, so that `matte_target` alone
            // says a matte track is nobody's target (MT-2): a matte in front
            // of a matte cuts nothing because of that rule, not because of
            // the order of these two tests.
            if let Some(front) = cutting_matte(tracks, track.id) {
                let key = MatteKey {
                    path: path.clone(),
                    track: front.id,
                };
                cuts.push((key, front.matte));
            }
            if !track.matte.is_none() {
                let key = MatteKey {
                    path,
                    track: track.id,
                };
                return Roles {
                    into: Some((key, track.matte)),
                    cuts,
                };
            }
        }
        Roles { into: None, cuts }
    }
}
