//! Ducking by speech (format 29, spec §11 AU-110, AU-112): a ducking clip in
//! `speech` mode ducks the rest of the mix only while its media's saved
//! speech spans play, widened by `pre_roll` before and `hold` after.
//!
//! The spans are `media[].speech`, forward-file SOURCE ticks. This module
//! puts them where the clip plays them — reflected for a reversed clip,
//! through its rate or speed map, kept to the part of the instance that
//! plays — widens and merges them, and answers the three questions
//! `audio.rs` and the plan ask of a speech ducker: its multiplier at a tick,
//! the ticks its curve has to be sampled at, and its own ramps for the
//! plan's `ducks` (the line the timeline draws, AU-113).
//!
//! Each merged span ducks exactly as an extent duck over it would
//! (`audio_duck.rs`'s [`extent_gain`]) and the ducker's multiplier is the
//! MINIMUM over its spans, so the release of one word and the attack of the
//! next meet at whichever is lower rather than multiplying into a dip no
//! setting asked for. Nothing here edits.

use crate::audio::{coalesce, Ramp, Side};
use crate::audio_duck::{extent_gain, Ducker};
use crate::clip_source_time::{clip_time_of_source, Round};
use crate::model::{Clip, Duck, Media, Project, Source};
use crate::speed_map::SpeedMap;
use crate::time::Ticks;

/// A media's saved speech spans in CLIP time, `[0, clip.duration)`, each
/// edge through `clip_source_time.rs`'s `clip_time_of_source`: each
/// reflected first when the clip is reversed (`in` is measured in the
/// reversed stream, `model.rs`'s `Source::Media` doc), then read through the
/// clip's speed map when it is ramped, else at its base rate — the start
/// floored and the end ceiled, so a word's edge is never shaved off. Spans
/// that fall outside the window the clip plays are dropped. Sorted.
pub(crate) fn speech_in_clip(
    clip: &Clip,
    media: &Media,
    spans: &[[Ticks; 2]],
) -> Vec<(Ticks, Ticks)> {
    let Source::Media { reversed, .. } = clip.source else {
        return Vec::new();
    };
    if SpeedMap::of(clip).is_none() && !(clip.speed.is_finite() && clip.speed > 0.0) {
        return Vec::new();
    }
    // The guard above means the helper always answers; reflection is the
    // helper's, so a reversed span's edges swap: its start is played from
    // the span's END.
    let at = |source: Ticks, round: Round| -> Ticks {
        clip_time_of_source(clip, media, source, round).unwrap_or(0)
    };
    let mut out: Vec<(Ticks, Ticks)> = spans
        .iter()
        .map(|&[a, b]| {
            if reversed {
                (at(b, Round::Down), at(a, Round::Up))
            } else {
                (at(a, Round::Down), at(b, Round::Up))
            }
        })
        .map(|(a, b)| (a.max(0), b.min(clip.duration)))
        .filter(|(a, b)| b > a)
        .collect();
    out.sort_unstable();
    out
}

/// Widens each `[s, e)` to `[s − before, e + after]` (each floored at 0)
/// and merges the ones that then overlap or touch, in start order: a speech
/// duck's `pre_roll` and `hold`, and `video_gate.rs`'s (spec §11 CO-90).
pub(crate) fn widened(
    spans: Vec<(Ticks, Ticks)>,
    before: Ticks,
    after: Ticks,
) -> Vec<(Ticks, Ticks)> {
    let (before, after) = (before.max(0), after.max(0));
    let mut out: Vec<(Ticks, Ticks)> = Vec::with_capacity(spans.len());
    for (s, e) in spans {
        let (s, e) = (s.saturating_sub(before), e.saturating_add(after));
        match out.last_mut() {
            Some(last) if s <= last.1 => last.1 = last.1.max(e),
            _ => out.push((s, e)),
        }
    }
    out
}

impl Project {
    /// A speech ducker's spans in PROJECT time: [`Self::played_speech`],
    /// then widened and merged by its `pre_roll` and `hold`. Empty for a
    /// clip that is not a media clip or whose media has no `speech` — a
    /// speech duck with nothing to follow ducks nowhere.
    pub(crate) fn speech_spans(
        &self,
        clip: &Clip,
        origin: Ticks,
        played: (Ticks, Ticks),
        duck: &Duck,
    ) -> Vec<(Ticks, Ticks)> {
        widened(
            self.played_speech(clip, origin, played),
            duck.pre_roll,
            duck.hold,
        )
    }

    /// A media clip's speech in PROJECT time, unwidened: its media's speech
    /// in clip time, moved to `origin` (the clip's first frame) and kept to
    /// `played` (the part of the instance that plays). Sorted. Empty for a
    /// clip that is not a media clip or whose media has no `speech`.
    pub(crate) fn played_speech(
        &self,
        clip: &Clip,
        origin: Ticks,
        played: (Ticks, Ticks),
    ) -> Vec<(Ticks, Ticks)> {
        let Source::Media { media, .. } = clip.source else {
            return Vec::new();
        };
        let Some(media) = self.media(media) else {
            return Vec::new();
        };
        let Some(spans) = &media.speech else {
            return Vec::new();
        };
        speech_in_clip(clip, media, spans)
            .into_iter()
            .map(|(a, b)| {
                let a = origin.saturating_add(a).max(played.0);
                (a, origin.saturating_add(b).min(played.1))
            })
            .filter(|(a, b)| b > a)
            .collect()
    }
}

/// A speech ducker's multiplier at `t`: the extent curve of each span, the
/// MINIMUM over them, and 1 with no span (spec §11 AU-112).
pub(crate) fn speech_gain(ducker: &Ducker, spans: &[(Ticks, Ticks)], t: Ticks, side: Side) -> f64 {
    spans
        .iter()
        .map(|&(s, e)| extent_gain(&ducker.duck, s, e, t, side))
        .fold(1.0, f64::min)
}

/// The ticks a speech ducker's curve has to be sampled at: each span's four
/// edges (its start, the attack's end, its end, the release's end), and the
/// tick where one span's release crosses the next one's attack, which is
/// where the minimum turns from one to the other.
pub(crate) fn speech_breaks(ducker: &Ducker, spans: &[(Ticks, Ticks)]) -> Vec<Ticks> {
    let duck = &ducker.duck;
    let (attack, release) = (duck.attack.max(0), duck.release.max(0));
    let mut out = Vec::with_capacity(spans.len().saturating_mul(5));
    for &(s, e) in spans {
        out.extend([s, s.saturating_add(attack), e, e.saturating_add(release)]);
    }
    let level = if duck.level.is_finite() {
        duck.level.clamp(0.0, 1.0)
    } else {
        1.0
    };
    if attack == 0 || release == 0 {
        return out;
    }
    for pair in spans.windows(2) {
        let (Some(&(s1, e1)), Some(&(s2, _))) = (pair.first(), pair.get(1)) else {
            continue;
        };
        // The release rises from `held` at e1 with slope a; the attack falls
        // from 1 at s2 with slope b. They meet where the two lines agree.
        let held = extent_gain(duck, s1, e1, e1, Side::Left);
        let a = (1.0 - held) / release as f64;
        let b = (1.0 - level) / attack as f64;
        if a + b <= 0.0 {
            continue;
        }
        let t = (1.0 - held + a * e1 as f64 + b * s2 as f64) / (a + b);
        let lo = e1.max(s2) as f64;
        let hi = e1.saturating_add(release).min(s2.saturating_add(attack)) as f64;
        if t.is_finite() && t > lo && t < hi {
            out.push(t.round() as Ticks);
        }
    }
    out
}

/// A speech ducker's own multiplier as ramps over its widened extent — its
/// first span's start to its last span's release — for the plan's `ducks`
/// (spec §7.2, §11 AU-113). Empty with no spans.
pub(crate) fn duck_ramps(ducker: &Ducker, spans: &[(Ticks, Ticks)]) -> Vec<Ramp> {
    let (Some(first), Some(last)) = (spans.first(), spans.last()) else {
        return Vec::new();
    };
    let (from, to) = (first.0, last.1.saturating_add(ducker.duck.release.max(0)));
    let mut breaks = speech_breaks(ducker, spans);
    breaks.retain(|t| *t >= from && *t <= to);
    breaks.sort_unstable();
    breaks.dedup();
    let ramps = breaks
        .windows(2)
        .filter_map(|pair| match (pair.first(), pair.get(1)) {
            (Some(&a), Some(&b)) if b > a => Some(Ramp {
                start: a,
                duration: b.saturating_sub(a),
                from: speech_gain(ducker, spans, a, Side::Right),
                to: speech_gain(ducker, spans, b, Side::Left),
            }),
            _ => None,
        })
        .collect();
    coalesce(ramps)
}
