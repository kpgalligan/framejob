//! `copy_pieces` — a clip's pieces between given project times copied onto
//! another track at the same times (road map "creator-jobs" SW1, spec §11
//! SW-11, SW-12). It is the primitive Clip ▸ Switch Angle ▸ writes with: a
//! piece of a synced angle shows the angle's own frame at every time.
//!
//! A piece is EXACTLY the middle a `split` at its two ends would leave —
//! its source window, a ramp's map and rate, its actions clipped, a
//! graphic's `in` and `length`, its words rebased — because it is made by
//! `edit_split.rs`'s `split_clip` itself, on a scratch copy holding only the
//! source clip. This module states none of those rules; it only says where
//! the middle lands: a fresh id and fresh action ids from the result's own
//! counter, `track` the destination, `start` the range's start, no
//! transition and no link, and `enabled` overridden where `video`/`audio`
//! are given.
//!
//! In order (SW-11): `Err` for an unknown clip, then for an unknown track;
//! each pair put in order and snapped, a range empty on the grid dropped
//! (nothing left is an identity), the rest sorted by start; then the
//! refusals — a nest clip, a range outside the clip, overlapping ranges, a
//! locked destination, a destination holding a clip over a range. The exit
//! is `finish`.

use crate::edit_clip::clip_end;
use crate::edit_split::split_clip;
use crate::edit_time::locked_track;
use crate::model::{Clip, Project, Source};
use crate::outcome::Outcome;
use crate::time::Ticks;

impl Project {
    /// Copies `clip`'s pieces between each range's ends onto `track` at the
    /// same project times (this module's doc, spec §6, §11 SW-11).
    pub fn copy_pieces(
        &self,
        clip: u32,
        track: u32,
        ranges: &[[Ticks; 2]],
        video: Option<bool>,
        audio: Option<bool>,
    ) -> Result<Outcome, String> {
        let source = self.require_clip(clip)?.clone();
        let destination = self.require_track(track)?;

        let mut spans: Vec<(Ticks, Ticks)> = ranges
            .iter()
            .map(|[a, b]| {
                let (low, high) = if a <= b { (*a, *b) } else { (*b, *a) };
                (self.snapped(low), self.snapped(high))
            })
            .filter(|(from, to)| to > from)
            .collect();
        if spans.is_empty() {
            return Ok(Outcome::Identity);
        }
        spans.sort_by_key(|&(from, to)| (from, to));

        if let Some(why) = self.pieces_refusal(&source, destination.id, destination.locked, &spans)
        {
            return Ok(Outcome::Refused(why));
        }

        let mut scratch = self.clone();
        scratch.clips = vec![source.clone()];
        let mut next = self.clone();
        let mut pieces: Vec<Clip> = Vec::with_capacity(spans.len());
        for &(from, to) in &spans {
            // `middle` answers `None` only when a cut is not strictly inside
            // the clip, which the checks above rule out (every span is
            // non-empty and inside the clip), so no range is ever skipped.
            let Some(mut piece) = middle(&scratch, &source, from, to) else {
                continue;
            };
            next.remint(&mut piece);
            piece.track = track;
            piece.start = from;
            piece.transition_in = None;
            piece.linked = None;
            if let Some(on) = video {
                piece.enabled.video = on;
            }
            if let Some(on) = audio {
                piece.enabled.audio = on;
            }
            pieces.push(piece);
        }
        next.clips.extend(pieces);
        self.finish(next)
    }

    /// The first refusal SW-11 names for `spans` (ordered, snapped, sorted),
    /// in its order: a nest clip, a range outside the clip, overlapping
    /// ranges, a locked destination, a destination holding a clip.
    fn pieces_refusal(
        &self,
        source: &Clip,
        track: u32,
        locked: bool,
        spans: &[(Ticks, Ticks)],
    ) -> Option<String> {
        if matches!(source.source, Source::Nest { .. }) {
            return Some(format!(
                "clip {} is a nest: a piece of it would replay the nest from its first frame",
                source.id
            ));
        }
        let (start, end) = (source.start, clip_end(source));
        if let Some((from, to)) = spans.iter().find(|(from, to)| *from < start || *to > end) {
            return Some(format!(
                "range [{from}, {to}] is outside clip {}, which runs from {start} to {end}",
                source.id
            ));
        }
        if let Some(pair) = spans.windows(2).find(|pair| pair[0].1 > pair[1].0) {
            let ((a, b), (c, d)) = (pair[0], pair[1]);
            return Some(format!("ranges [{a}, {b}] and [{c}, {d}] overlap"));
        }
        if locked {
            return Some(locked_track(track, "no piece can be copied onto it"));
        }
        let holder = self.clips_on_track(track).into_iter().find(|held| {
            let held_end = clip_end(held);
            spans
                .iter()
                .any(|(from, to)| held.start < *to && held_end > *from)
        })?;
        Some(format!(
            "track {track} holds clip {} between {} and {}",
            holder.id,
            holder.start,
            clip_end(holder)
        ))
    }
}

/// The middle `split_clip` leaves of `source` at `from` and `to` on a clone
/// of `scratch` (the project holding only `source`): split at `from` when it
/// is past the clip's start, the second half being the middle, then the
/// middle split at `to` when it is before the clip's end, the first half
/// being the middle (spec §11 SW-12).
fn middle(scratch: &Project, source: &Clip, from: Ticks, to: Ticks) -> Option<Clip> {
    let mut cut = scratch.clone();
    let mut id = source.id;
    if from > source.start {
        if !split_clip(&mut cut, id, from) {
            return None;
        }
        id = cut.clips.last()?.id;
    }
    if to < clip_end(source) && !split_clip(&mut cut, id, to) {
        return None;
    }
    cut.clip(id).cloned()
}
