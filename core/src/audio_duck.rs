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
//! Ducking is by clip EXTENT, not by voice activity: a ducking clip ducks
//! for as long as it is on the timeline whether or not it is making a sound,
//! which is what makes the result predictable from the picture of the
//! timeline alone.
//!
//! `Ducker` is re-exported by `audio.rs`, so `crate::audio::Ducker` — the
//! path `evaluate.rs` names — still resolves.

use crate::audio::{covers, Side, MAX_GAIN};
use crate::model::{Duck, Project};
use crate::nest::Instance;
use crate::time::Ticks;

/// A clip elsewhere in the project that pushes this track down while it
/// plays. Ducking is by clip EXTENT, not by voice activity (spec §11), so
/// this is all the ducker's audio needed to compute the gain.
///
/// `clip` is carried so a track can drop the duckers that are its OWN
/// segments; the span is project time, which for a nested ducker is the part
/// of it the nest clip lets through.
#[derive(Debug, Clone, Copy)]
pub struct Ducker {
    pub(crate) clip: u32,
    pub(crate) start: Ticks,
    pub(crate) end: Ticks,
    pub(crate) duck: Duck,
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
    let level = ducker.duck.level;
    if !level.is_finite() {
        return 1.0;
    }
    let level = level.clamp(0.0, MAX_GAIN);
    // Negative lengths are meaningless; treat them as instantaneous rather
    // than dividing by them.
    let attack = ducker.duck.attack.max(0);
    let release = ducker.duck.release.max(0);
    let ducked_end = ducker.end.saturating_add(release);
    if !covers(ducker.start, ducked_end, t, side) {
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

    if covers(ducker.start, ducker.end, t, side) {
        reached(t.saturating_sub(ducker.start))
    } else {
        let held = reached(ducker.end.saturating_sub(ducker.start));
        let u = if release > 0 {
            (t.saturating_sub(ducker.end) as f64 / release as f64).clamp(0.0, 1.0)
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
    pub(crate) fn duckers(&self, instances: &[Instance<'_>]) -> Vec<Ducker> {
        let mut out: Vec<Ducker> = Vec::new();
        for instance in instances {
            for (clip, start, end) in instance.chain() {
                if out.iter().any(|d| d.clip == clip.id) {
                    continue;
                }
                if let Some(duck) = clip.audio.and_then(|a| a.duck) {
                    out.push(Ducker {
                        clip: clip.id,
                        start,
                        end,
                        duck,
                    });
                }
            }
        }
        out
    }
}
