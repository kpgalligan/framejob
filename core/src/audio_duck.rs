//! Ducking: the one term of the envelope that comes from ELSEWHERE.
//!
//! Every other factor in `audio.rs` is a property of the voice being
//! measured — its volume, its fades, its actions, its mute. A duck is the
//! opposite: a clip somewhere else in the project, on some other track,
//! pushes this one down while it plays (spec §11). That is a different
//! question with a different input — the flattened timeline rather than one
//! composition track's segments — so it is a module of its own, and
//! `audio.rs` reads it as one multiplier per ducker at a breakpoint.
//!
//! Ducking is by clip EXTENT by default: a ducking clip ducks for as long
//! as it is on the timeline whether or not it is making a sound, which is
//! what makes the result predictable from the picture of the timeline alone.
//! A duck in `speech` mode (format 29, spec §11 AU-110, AU-112) ducks over
//! its media's saved speech spans instead; `audio_duck_speech.rs` turns
//! those into project-time spans and this module's extent curve is applied
//! to each of them.
//!
//! `Ducker` is re-exported by `audio.rs`, so `crate::audio::Ducker` — the
//! path `evaluate.rs` names — still resolves.

use std::iter::once;

use crate::audio::{covers, Side};
use crate::audio_duck_speech::speech_gain;
use crate::model::{Duck, DuckMode, Project};
use crate::nest::Instance;
use crate::time::Ticks;

/// A clip elsewhere in the project that pushes this track down while it
/// plays. For an extent duck this is all the ducker's audio needed to
/// compute the gain; a speech duck carries its spans too.
///
/// `clip` is carried so a track can drop the duckers that are its OWN
/// segments; the span is project time, which for a nested ducker is the part
/// of it the nest clip lets through. `spans` is `None` for an extent duck and
/// the merged, widened project-time speech spans for a speech duck — empty
/// when the clip is not a media clip or its media has no `speech`, which
/// ducks nowhere.
#[derive(Debug, Clone)]
pub struct Ducker {
    pub(crate) clip: u32,
    pub(crate) start: Ticks,
    pub(crate) end: Ticks,
    pub(crate) duck: Duck,
    pub(crate) spans: Option<Vec<(Ticks, Ticks)>>,
}

/// The ducker's multiplier at `t`.
///
/// The attack ramps 1 → `level` from the ducker's first tick, the level
/// holds for the rest of its extent, and the release ramps back to 1 over
/// the `release` ticks AFTER it ends. That is compressor ordering — a duck
/// that released before its clip finished would lift the bed back under the
/// last words of the voiceover — and it is why the ducked span reaches past
/// the ducking clip.
///
/// An attack longer than the clip simply never arrives at `level`; the
/// release then starts from wherever it got to, so no combination of
/// lengths produces a discontinuity in the middle of the curve.
pub(crate) fn duck_gain(ducker: &Ducker, t: Ticks, side: Side) -> f64 {
    match &ducker.spans {
        Some(spans) => speech_gain(ducker, spans, t, side),
        None => extent_gain(&ducker.duck, ducker.start, ducker.end, t, side),
    }
}

/// [`duck_gain`]'s extent curve for `duck` over `[start, end)`: the whole
/// of an extent duck, and one span of a speech duck.
pub(crate) fn extent_gain(duck: &Duck, start: Ticks, end: Ticks, t: Ticks, side: Side) -> f64 {
    let level = duck.level;
    if !level.is_finite() {
        return 1.0;
    }
    // The vocabulary's 0..1 (`check_audio`'s `audio.duck.level`, and
    // `clamp_audio`'s matching bound): a duck lowers, it never boosts.
    let level = level.clamp(0.0, 1.0);
    // Negative lengths are meaningless; treat them as instantaneous rather
    // than dividing by them.
    let attack = duck.attack.max(0);
    let release = duck.release.max(0);
    let ducked_end = end.saturating_add(release);
    if !covers(start, ducked_end, t, side) {
        return 1.0;
    }

    // How far down the attack has travelled after `elapsed` ticks. The
    // endpoints are returned EXACTLY rather than through the interpolation:
    // `1 + (0.2 - 1) * 1` is 0.19999999999999996, and the whole hold of
    // every duck in every plan would print with that tail — noise in a
    // string Swift compares and a person reads.
    let reached = |elapsed: Ticks| -> f64 {
        let u = if attack > 0 {
            (elapsed.max(0) as f64 / attack as f64).clamp(0.0, 1.0)
        } else {
            // A zero attack is a step at the ducker's first tick.
            1.0
        };
        match u {
            u if u <= 0.0 => 1.0,
            u if u >= 1.0 => level,
            u => 1.0 + (level - 1.0) * u,
        }
    };

    if covers(start, end, t, side) {
        reached(t.saturating_sub(start))
    } else {
        let held = reached(end.saturating_sub(start));
        let u = if release > 0 {
            (t.saturating_sub(end) as f64 / release as f64).clamp(0.0, 1.0)
        } else {
            1.0
        };
        match u {
            u if u <= 0.0 => held,
            u if u >= 1.0 => 1.0,
            u => held + (1.0 - held) * u,
        }
    }
}

impl Project {
    /// Every ducking clip in the project, with the span it ducks over.
    ///
    /// Computed once per plan from the flattened timeline, so a duck set
    /// INSIDE a nest ducks over the part of it that plays, and a duck on the
    /// nest clip itself ducks over the whole nest. A clip appears at most
    /// once even when several instances name it — a nest shown twice ducks
    /// over the first span it was found at, which is a corner no UI can
    /// reach and not worth a second entry that would duck twice.
    ///
    /// The duck is read from the base props, not through actions: the ramp
    /// lengths describe an envelope, and an envelope whose own attack time
    /// animates is not a version-1 feature.
    ///
    /// A speech duck's spans are measured from the clip's ORIGIN (its first
    /// frame in project time) and kept to the part that plays, `start` to
    /// `end` (`audio_duck_speech.rs`).
    pub(crate) fn duckers(&self, instances: &[Instance<'_>]) -> Vec<Ducker> {
        let mut out: Vec<Ducker> = Vec::new();
        for instance in instances {
            // `chain`'s order, outermost first: each clip's origin beside it.
            let origins = (instance.inside.iter().map(|e| e.origin)).chain(once(instance.origin));
            for ((clip, start, end), origin) in instance.chain().zip(origins) {
                if out.iter().any(|d| d.clip == clip.id) {
                    continue;
                }
                if let Some(duck) = clip.audio.and_then(|a| a.duck) {
                    let spans = (duck.mode == DuckMode::Speech)
                        .then(|| self.speech_spans(clip, origin, (start, end), &duck));
                    out.push(Ducker {
                        clip: clip.id,
                        start,
                        end,
                        duck,
                        spans,
                    });
                }
            }
        }
        out
    }
}
