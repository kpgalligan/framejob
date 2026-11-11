//! A cut and THE overlap rule (spec §11 #427): what a cut is judged on, and
//! the sentence it is refused in.
//!
//! A cut can leave a piece too short for the transition it carries: A
//! [0, 4 s) and B [3 s, 8 s) with a one-second dissolve, cut at 2.2 s, leave
//! A's piece [2.2 s, 4 s) under B by 1 s, more than half of its 1.8 s. Every
//! op that cuts asks the rule of what it would STORE, never of a cut on the
//! way there: a range op cuts both bounds and then removes what lies between
//! them, and a piece the first cut leaves too short may be one the removal
//! takes away (the range {2.2 s, 4 s} above ends legal). So the cutters
//! (`edit_clip.rs`'s `cut_clips` and `cut_under_playhead`) ask no rule and
//! record in [`Pieces`] which clip each piece was cut from, and the op asks
//! [`Project::cut_refusal`] once, of its result.
//!
//! Only the tracks the op changed are judged — a track whose clips' ids,
//! starts or durations differ from the input's — as `close_gap` judges only
//! the tracks it moves: a violation elsewhere is not this op's to report. A
//! changed track is judged WHOLE, as every placement op judges it, so a pair
//! already past the limit there refuses too, in the rule's own sentence,
//! which names two clips the caller has.
//!
//! A pair the cut made too long is named by the clips its pieces were cut
//! from: a second half's id is minted by the cut and exists only in the
//! answer that was refused, so a caller could do nothing with it
//! (`keep_range`'s rule, spec §11 CJ-50 (g), whose map this is). A pair of
//! source clips already past the limit before the op is not the cut's even
//! when the cut reaches one of them — no cut position mends it — and
//! answers the rule's own sentence, still by source.

use std::collections::HashMap;

use crate::model::{Clip, Project};
use crate::time::Ticks;
use crate::transition::{overlap_limit, past_limit};

/// Every piece's SOURCE clip: a second half maps to the clip its original
/// was cut from, so a piece cut twice still names the clip a person saw.
/// An uncut clip, absent from the map, is its own source.
pub(crate) struct Pieces(HashMap<u32, u32>);

impl Pieces {
    pub(crate) fn new() -> Pieces {
        Pieces(HashMap::new())
    }

    pub(crate) fn source(&self, piece: u32) -> u32 {
        self.0.get(&piece).copied().unwrap_or(piece)
    }

    /// `second` was cut from `first`, so it names `first`'s source.
    pub(crate) fn halved(&mut self, first: u32, second: u32) {
        let source = self.source(first);
        self.0.insert(second, source);
    }

    /// The pieces of `source` in `project` satisfying `which`.
    pub(crate) fn of(
        &self,
        project: &Project,
        source: u32,
        which: impl Fn(&Clip) -> bool,
    ) -> Vec<u32> {
        project
            .clips
            .iter()
            .filter(|c| self.source(c.id) == source && which(c))
            .map(|c| c.id)
            .collect()
    }
}

/// What a track holds, as the rule sees it: each clip's id, start and
/// duration, in the track's order.
fn placements(project: &Project, track: u32) -> Vec<(u32, Ticks, Ticks)> {
    project
        .clips_on_track(track)
        .iter()
        .map(|c| (c.id, c.start, c.duration))
        .collect()
}

impl Project {
    /// THE overlap rule asked of `next`, what a cut of `self` would store,
    /// on each track the cut changed, in track order: `None` when it holds,
    /// else the sentence the op is refused in (the module doc is the rule).
    pub(crate) fn cut_refusal(&self, next: &Project, pieces: &Pieces) -> Option<String> {
        for track in &next.tracks {
            if placements(self, track.id) == placements(next, track.id) {
                continue;
            }
            let Err(why) = next.check_overlap_rule(&[], track.id, &[]) else {
                continue;
            };
            // Each pair past its limit, named by its source clips, and
            // whether the cut made it: one of its clips a piece, and the
            // source pair not already past the limit before the op.
            let over: Vec<(u32, u32, Ticks, Ticks, bool)> = next
                .overlaps_on_track(track.id)
                .into_iter()
                .filter_map(|o| {
                    let (a, b) = (next.clip(o.earlier)?, next.clip(o.later)?);
                    let limit = overlap_limit(a, b);
                    let (first, second) = (pieces.source(a.id), pieces.source(b.id));
                    let made = (self.was_cut(a) || self.was_cut(b))
                        && !self.was_past_limit(track.id, first, second);
                    (o.duration > limit).then_some((first, second, o.duration, limit, made))
                })
                .collect();
            if let Some(&(first, second, overlap, limit, _)) = over.iter().find(|o| o.4) {
                return Some(format!(
                    "clips {first} and {second} would overlap by {overlap} ticks, more than half \
                     of the shorter piece the cut leaves ({limit} ticks); cut further from their \
                     transition, or shorten it first"
                ));
            }
            // A pair no cut made: the rule's own sentence, still by source,
            // since a second half's id exists only in the refused answer.
            if let Some(&(first, second, overlap, limit, _)) = over.first() {
                return Some(past_limit(first, second, overlap, limit));
            }
            return Some(why);
        }
        None
    }

    /// Whether `clip` of a cut's result is a piece: a second half `self`
    /// has not got, or a first half shorter than the clip it kept the id of.
    fn was_cut(&self, clip: &Clip) -> bool {
        self.clip(clip.id)
            .is_none_or(|before| before.duration != clip.duration)
    }

    /// Whether `first` and `second` already overlapped past their limit on
    /// `track` before the op: no cut made that pair, and none can mend it.
    fn was_past_limit(&self, track: u32, first: u32, second: u32) -> bool {
        self.overlaps_on_track(track).into_iter().any(|o| {
            let pair = (o.earlier, o.later) == (first, second);
            pair && matches!(
                (self.clip(o.earlier), self.clip(o.later)),
                (Some(a), Some(b)) if o.duration > overlap_limit(a, b)
            )
        })
    }
}
