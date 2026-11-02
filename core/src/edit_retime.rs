//! `retime_range` — one range of the timeline played faster or slower on
//! every unlocked track, and everything after it moved up or back to stay
//! in step (road map "creator-jobs" CU9a, spec §11 CU-90). One op, so Clip ▸
//! Retime Range… is one undo step, "Retime Range".
//!
//! In order, each a part of CU-90:
//!
//! - (a) `from` and `to` are snapped and clamped to 0, and every time inside
//!   the range maps through `f(t) = snapped(from + round((t − from) ÷
//!   rate))`, `to′ = f(to)`. Both bounds are cut by `split_under_playhead`
//!   (`from`, then `to`), so a straddler splits exactly as `split` splits
//!   it. The PIECES are the clips on unlocked tracks wholly inside the
//!   range, found before the shift; everything at or after `to` moves by
//!   `to′ − to` through `edit_time.rs`'s `shift_clips`, which carries each
//!   moved clip's linked partner (AU-91). A piece starts at `f(s)` and lasts
//!   `f(e) − f(s)`, so pieces that touched still touch: a constant media
//!   piece plays at speed × rate, held to its media by
//!   `duration_resnapped`, its actions keeping their fraction; a ramped one
//!   is `scaled_profile`'s (SR-19); every other kind scales its start and
//!   duration (a graphic keeps its `length`, G-9). Markers inside map
//!   through `f`, markers at or after `to` move with the shift. Inside a
//!   nest the view has no markers and the merge writes none back, so none
//!   moves and none is checked.
//! - (b) Errors, then refusals, in CU-90's order; nothing changes when one
//!   fires. A rate of exactly 1 is an identity once the rate is known to be
//!   in range.
//! - The exit is `finish_placement` over the unlocked tracks.

use crate::edit_clip::clip_end;
use crate::edit_clip_timing::{SPEED_MAX, SPEED_MIN};
use crate::edit_link::linked_rate_sentence;
use crate::edit_speed_profile::profile_factors;
use crate::edit_time::{locked_track, shift_clips, unlocked_tracks};
use crate::model::{Clip, Project, Source};
use crate::outcome::Outcome;
use crate::speed_map::end_speed;
use crate::time::Ticks;

/// The range's time map: `from`, `to` and `to′` on the grid, and `rate`.
struct Retime {
    from: Ticks,
    to: Ticks,
    rate: f64,
    to_new: Ticks,
}

impl Retime {
    /// `f(t)` for a `t` inside `[from, to]`.
    fn map(&self, project: &Project, t: Ticks) -> Ticks {
        let scaled = ((t - self.from) as f64 / self.rate).round();
        project.snapped(self.from.saturating_add(scaled as Ticks))
    }

    /// Where a marker at `t` goes: through `f` inside the range, by the
    /// shift at or after `to`, nowhere before `from`.
    fn marker(&self, project: &Project, t: Ticks) -> Ticks {
        if t >= self.to {
            t.saturating_add(self.to_new - self.to)
        } else if t >= self.from {
            self.map(project, t)
        } else {
            t
        }
    }
}

impl Project {
    /// Plays `[from, to)` at `rate` on every unlocked track and moves what
    /// follows by the range's lost or gained length (spec §6, §11 CU-90).
    /// `keep_pitch`, when given, is set on every media piece's audio, as
    /// `set_speed` sets it.
    pub fn retime_range(
        &self,
        from: Ticks,
        to: Ticks,
        rate: f64,
        keep_pitch: Option<bool>,
    ) -> Result<Outcome, String> {
        if !(rate.is_finite() && rate > 0.0) {
            return Err(format!("rate must be a positive number, not {rate}"));
        }
        let from = self.snapped(from).max(0);
        let to = self.snapped(to).max(0);
        if to <= from {
            return Err(format!(
                "retime_range's to must be after its from (from {from}, to {to} ticks, on the \
                 frame grid)"
            ));
        }
        if !(SPEED_MIN..=SPEED_MAX).contains(&rate) {
            return Ok(Outcome::Refused(format!(
                "a range can be retimed by ×{SPEED_MIN} to ×{SPEED_MAX}, not ×{rate}"
            )));
        }
        if rate == 1.0 {
            return Ok(Outcome::Identity);
        }
        let mut retime = Retime {
            from,
            to,
            rate,
            to_new: to,
        };
        retime.to_new = retime.map(self, to);
        if let Some(why) = self.retime_refusal(&retime) {
            return Ok(Outcome::Refused(why));
        }

        let mut cut = match self.split_under_playhead(from)? {
            Outcome::Applied(split) => split,
            Outcome::Identity | Outcome::Refused(_) => self.clone(),
        };
        if let Outcome::Applied(split) = cut.split_under_playhead(to)? {
            cut = split;
        }
        let unlocked = unlocked_tracks(&cut);
        let pieces: Vec<Clip> = cut
            .clips
            .iter()
            .filter(|c| unlocked.contains(&c.track) && c.start >= from && clip_end(c) <= to)
            .cloned()
            .collect();
        for piece in &pieces {
            if let Some(why) = self.piece_refusal(&cut, piece, &retime) {
                return Ok(Outcome::Refused(why));
            }
        }

        let mut next = cut.clone();
        if let Some(why) = shift_clips(&mut next, to, retime.to_new - to) {
            return Ok(Outcome::Refused(why));
        }
        for piece in &pieces {
            let moved = next.retimed_piece(piece, &retime, keep_pitch);
            if let Some(slot) = next.clip_mut(piece.id) {
                *slot = moved;
            }
        }
        for marker in next.markers.iter_mut() {
            marker.time = retime.marker(self, marker.time);
        }
        let unlocked = unlocked_tracks(&next);
        self.finish_placement(next, &unlocked)
    }

    /// CU-90 (b)'s refusals (2)–(6), on the project as the caller sent it.
    fn retime_refusal(&self, retime: &Retime) -> Option<String> {
        let (from, to) = (retime.from, retime.to);
        if to - from < self.frame().saturating_mul(2) {
            return Some(format!(
                "the range from {from} to {to} ticks is shorter than two frames"
            ));
        }
        for track in self.tracks.iter().filter(|t| t.locked) {
            if self
                .clips
                .iter()
                .any(|c| c.track == track.id && clip_end(c) > from)
            {
                return Some(locked_track(
                    track.id,
                    "its clips after the range's start would fall out of step with the retimed \
                     range",
                ));
            }
        }
        let unlocked = unlocked_tracks(self);
        let inside = self
            .clips
            .iter()
            .filter(|c| unlocked.contains(&c.track) && c.start < to && clip_end(c) > from);
        for clip in inside {
            let c = clip.id;
            if matches!(clip.source, Source::Nest { .. }) {
                return Some(format!(
                    "clip {c} is a nest, which has no speed; move the range off it, or retime \
                     inside the nest"
                ));
            }
            if clip.text.as_ref().is_some_and(|t| !t.words.is_empty()) {
                return Some(format!(
                    "clip {c} is a caption page with timed words, which a retime cannot move; \
                     move the range off it"
                ));
            }
            if let Some(partner) = clip.linked {
                return Some(linked_rate_sentence(c, partner));
            }
        }
        for track in &unlocked {
            for overlap in self.overlaps_on_track(*track) {
                let end = overlap.start.saturating_add(overlap.duration);
                if overlap.start <= to && end >= from {
                    return Some(format!(
                        "clip {} has a transition from clip {} from {} to {end} ticks, which \
                         touches the range; move the range off it or remove the transition",
                        overlap.later, overlap.earlier, overlap.start
                    ));
                }
            }
        }
        let moved: Vec<Ticks> = self
            .markers
            .iter()
            .map(|m| retime.marker(self, m.time))
            .collect();
        for (j, time) in moved.iter().enumerate() {
            if let Some(i) = moved.iter().take(j).position(|t| t == time) {
                return Some(format!(
                    "markers {} and {} would both be at {time} ticks after a retime by ×{}, and \
                     two markers may not share a time; move one of them first",
                    self.markers[i].id, self.markers[j].id, retime.rate
                ));
            }
        }
        None
    }

    /// CU-90 (b)'s refusal (7) for one piece of `cut`: a rate past the
    /// speed limits, or a piece under one frame. The piece is named by its
    /// source clip — a piece `self` has not got is the second half of the
    /// clip that straddled `from` on its track.
    fn piece_refusal(&self, cut: &Project, piece: &Clip, retime: &Retime) -> Option<String> {
        let source = match self.clip(piece.id) {
            Some(clip) => clip.id,
            None => self
                .clips
                .iter()
                .find(|c| {
                    c.track == piece.track && c.start < retime.from && clip_end(c) > retime.from
                })
                .map_or(piece.id, |c| c.id),
        };
        let rate = retime.rate;
        if matches!(piece.source, Source::Media { .. }) {
            let past = match profile_factors(piece) {
                None => Some(piece.speed * rate),
                Some((low, high)) => {
                    let rates = std::iter::once(piece.speed)
                        .chain(piece.actions.iter().filter_map(end_speed));
                    if rate > high {
                        Some(rates.fold(f64::NEG_INFINITY, f64::max) * rate)
                    } else if rate < low {
                        Some(rates.fold(f64::INFINITY, f64::min) * rate)
                    } else {
                        None
                    }
                }
            };
            if let Some(r) = past.filter(|r| !(SPEED_MIN..=SPEED_MAX).contains(r)) {
                let (limit, which) = match r > SPEED_MAX {
                    true => (SPEED_MAX, "fastest"),
                    false => (SPEED_MIN, "slowest"),
                };
                return Some(format!(
                    "clip {source} would play at ×{r}, past ×{limit}, the {which} a clip can play"
                ));
            }
        }
        let length = retime.map(cut, clip_end(piece)) - retime.map(cut, piece.start);
        if length < cut.frame() {
            return Some(format!(
                "clip {source} would last under one frame at ×{rate}"
            ));
        }
        None
    }

    /// One piece retimed: started at `f(s)`, lasting `f(e) − f(s)` — a
    /// media piece at speed × rate (held to its media) or its ramp scaled
    /// (SR-19), every other kind scaled; actions keep their fraction.
    fn retimed_piece(&self, piece: &Clip, retime: &Retime, keep_pitch: Option<bool>) -> Clip {
        let start = retime.map(self, piece.start);
        let length = retime.map(self, clip_end(piece)) - start;
        let mut moved = piece.clone();
        moved.start = start;
        if !matches!(piece.source, Source::Media { .. }) {
            moved.duration = length;
            self.rescale_actions(&mut moved.actions, piece.duration, length);
            return moved;
        }
        if profile_factors(piece).is_some() {
            moved = self.scaled_profile(&moved, retime.rate, length);
        } else {
            moved.speed = piece.speed * retime.rate;
            moved.duration = length;
            moved.duration = self.duration_resnapped(&moved);
            self.rescale_actions(&mut moved.actions, piece.duration, moved.duration);
        }
        if let (Some(keep), Some(audio)) = (keep_pitch, moved.audio.as_mut()) {
            audio.keep_pitch = keep;
        }
        moved
    }
}
