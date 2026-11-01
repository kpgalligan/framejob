//! `keep_range` — the project as one range of its own timeline (road map
//! "creator-jobs" CJ5a, spec §11 CJ-50).
//!
//! The answer holds only `[from, to)` of the TOP-LEVEL timeline, moved to
//! start at 0: what a derived document (File ▸ New Project from Range…,
//! `new_project_from_range`, CJ5b) is made of. It is applied only to that
//! document's handle, never to the one a person is editing, which is why it
//! ignores locks — the derived document keeps them — and why it has no tool
//! of its own (`AgentServer.opsWithoutTools`).
//!
//! In order, each a part of CJ-50:
//!
//! - (a) Both bounds are snapped and clamped to 0, as every op's ticks are;
//!   `to` not after `from` is an `Err`, not an identity and not a reorder
//!   (`edit_time.rs`'s `ordered_range` is deliberately not followed).
//! - (b) A nest clip a bound lies strictly inside is refused: a nest clip
//!   has no in point, so a cut there would replay it from its start.
//! - (c) Every clip, on every track, that a bound lies strictly inside is
//!   cut there by `split`'s own cutter (`edit_split.rs`'s `split_clip`) and
//!   its halves paired (`edit_link.rs`'s `pair_split_halves`), so a ramp, a
//!   timed caption page and a linked pair follow `split`'s rules exactly.
//! - (d) THE overlap rule at the edges, judged on the SOURCE's overlaps: an
//!   edge inside a transition drops the piece beyond it — the outgoing
//!   clip's piece starting at `from`, the incoming clip's piece ending at
//!   `to` — and the incoming piece that starts at `from` loses its
//!   `transition_in` (a hard start). When both bounds lie in one overlap,
//!   the incoming piece the `from` rule kept is not dropped again at `to`.
//! - (e) Clips not wholly inside the range go, the rest move by −`from`;
//!   markers inside are kept and moved, the others go; tracks and canvas
//!   are untouched.
//! - (f) Nests no kept clip reaches, and media no kept clip plays, names in
//!   a look, or converts through as `color.lut`, go.
//! - (g) Nothing left to play is refused, and so is a transition wholly
//!   inside the range whose clip an edge cut too short for it: the edge
//!   rule repairs only an overlap an edge lies in, and clips never push
//!   each other.
//!
//! The exit is `finish`, whose `settle_links` clears a link a dropped or
//! removed piece left one-sided.

use std::collections::{HashMap, HashSet};

use crate::edit_clip::clip_end;
use crate::edit_link::pair_split_halves;
use crate::edit_split::split_clip;
use crate::lut::look_media_ids;
use crate::model::{Clip, Project, Source};
use crate::outcome::Outcome;
use crate::time::Ticks;
use crate::transition::overlap_limit;

/// The nest a clip shows, when it is a nest clip.
fn nest_of(clip: &Clip) -> Option<u32> {
    match clip.source {
        Source::Nest { project } => Some(project),
        _ => None,
    }
}

/// Every piece's SOURCE clip: a second half maps to the clip its original
/// was cut from, so a piece cut twice still names the clip a person saw.
/// An uncut clip, absent from the map, is its own source.
struct Pieces(HashMap<u32, u32>);

impl Pieces {
    fn source(&self, piece: u32) -> u32 {
        self.0.get(&piece).copied().unwrap_or(piece)
    }

    /// The pieces of `source` in `project` satisfying `which`.
    fn of(&self, project: &Project, source: u32, which: impl Fn(&Clip) -> bool) -> Vec<u32> {
        project
            .clips
            .iter()
            .filter(|c| self.source(c.id) == source && which(c))
            .map(|c| c.id)
            .collect()
    }
}

impl Project {
    /// The project holding only `[from, to)` of its top-level timeline,
    /// moved to start at 0 (spec §11 CJ-50; the module doc is the rule).
    pub fn keep_range(&self, from: Ticks, to: Ticks) -> Result<Outcome, String> {
        let from = self.snapped(from).max(0);
        let to = self.snapped(to).max(0);
        if to <= from {
            return Err(format!(
                "keep_range's to must be after its from (from {from}, to {to} ticks, on the frame \
                 grid)"
            ));
        }

        // (b) Before anything is cut: a nest clip across either edge.
        for bound in [from, to] {
            if let Some(nest) = self
                .clips
                .iter()
                .find(|c| nest_of(c).is_some() && c.start < bound && bound < clip_end(c))
            {
                return Ok(Outcome::Refused(format!(
                    "Clip {} is a nest across the range's edge; a nest clip has no in point, so a \
                     cut there would replay it from its start. Move the edge, or open the nest \
                     and unnest it.",
                    nest.id
                )));
            }
        }

        // (c) Both bounds cut on every track, locked or not.
        let mut next = self.clone();
        let mut pieces = Pieces(HashMap::new());
        for bound in [from, to] {
            let ids: Vec<u32> = next
                .clips
                .iter()
                .filter(|c| c.start < bound && bound < clip_end(c))
                .map(|c| c.id)
                .collect();
            let mut halves: Vec<(u32, u32)> = Vec::new();
            for id in ids {
                // `split_clip` allocates the second half's id first.
                let second = next.next_id;
                if split_clip(&mut next, id, bound) {
                    let source = pieces.source(id);
                    pieces.0.insert(second, source);
                    halves.push((id, second));
                }
            }
            pair_split_halves(&mut next, &halves);
        }

        // (d) THE overlap rule at the edges, on the source's overlaps.
        let mut dropped: HashSet<u32> = HashSet::new();
        let mut hard_start: HashSet<u32> = HashSet::new();
        for track in &self.tracks {
            for overlap in self.overlaps_on_track(track.id) {
                let os = overlap.start;
                let oe = overlap.start.saturating_add(overlap.duration);
                if os <= from && from < oe {
                    dropped.extend(pieces.of(&next, overlap.earlier, |c| c.start == from));
                    hard_start.extend(pieces.of(&next, overlap.later, |c| c.start == from));
                }
                if os < to && to <= oe {
                    // A piece starting at `from` is the incoming piece the
                    // `from` rule just kept: both bounds lie in this one
                    // overlap, and it stays, hard-cut.
                    dropped.extend(pieces.of(&next, overlap.later, |c| {
                        clip_end(c) == to && c.start != from
                    }));
                }
            }
        }

        // (e) Keep what lies wholly inside, and move it to 0.
        next.clips
            .retain(|c| !dropped.contains(&c.id) && c.start >= from && clip_end(c) <= to);
        for clip in &mut next.clips {
            clip.start = clip.start.saturating_sub(from);
            if hard_start.contains(&clip.id) {
                clip.transition_in = None;
            }
        }
        next.markers.retain(|m| from <= m.time && m.time < to);
        for marker in &mut next.markers {
            marker.time = marker.time.saturating_sub(from);
        }

        // (f) What the kept timeline no longer reaches.
        prune_unused(&mut next);

        // (g) Refusals on what is left.
        if next.clips.is_empty() {
            return Ok(Outcome::Refused(format!(
                "Nothing plays between {from} and {to} ticks."
            )));
        }
        for track in &next.tracks {
            let Err(why) = next.check_overlap_rule(&[], track.id, &[]) else {
                continue;
            };
            let too_long = next.overlaps_on_track(track.id).into_iter().find(|o| {
                match (next.clip(o.earlier), next.clip(o.later)) {
                    (Some(a), Some(b)) => o.duration > overlap_limit(a, b),
                    _ => false,
                }
            });
            let Some(overlap) = too_long else {
                return Ok(Outcome::Refused(why));
            };
            let limit = match (next.clip(overlap.earlier), next.clip(overlap.later)) {
                (Some(a), Some(b)) => overlap_limit(a, b),
                _ => 0,
            };
            return Ok(Outcome::Refused(format!(
                "Keeping {from} to {to} ticks would leave clips {} and {} overlapping by {} \
                 ticks, more than half of the shorter piece ({limit} ticks); move an edge \
                 further from their transition.",
                pieces.source(overlap.earlier),
                pieces.source(overlap.later),
                overlap.duration
            )));
        }
        self.finish(next)
    }
}

/// Removes the nests no kept top-level clip reaches (through nest clips in
/// kept nests too), and every media that no kept clip plays or names in a
/// look and no kept media names as its `color.lut`. Order is kept.
fn prune_unused(project: &mut Project) {
    let mut nests: HashSet<u32> = HashSet::new();
    let mut frontier: Vec<u32> = project.clips.iter().filter_map(nest_of).collect();
    while let Some(id) = frontier.pop() {
        if !nests.insert(id) {
            continue;
        }
        if let Some(nest) = project.nest(id) {
            frontier.extend(nest.clips.iter().filter_map(nest_of));
        }
    }
    project.nests.retain(|n| nests.contains(&n.id));

    let mut media: HashSet<u32> = HashSet::new();
    let clips = project
        .clips
        .iter()
        .chain(project.nests.iter().flat_map(|n| n.clips.iter()));
    for clip in clips {
        media.extend(clip.source.media());
        media.extend(look_media_ids(clip));
    }
    // A kept media's LUT, and that LUT's, until nothing new is named.
    loop {
        let luts: Vec<u32> = project
            .media
            .iter()
            .filter(|m| media.contains(&m.id))
            .filter_map(|m| m.color.as_ref().and_then(|c| c.lut))
            .filter(|id| !media.contains(id))
            .collect();
        if luts.is_empty() {
            break;
        }
        media.extend(luts);
    }
    project.media.retain(|m| media.contains(&m.id));
}
