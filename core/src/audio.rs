//! Volume envelopes: the `ramps` array of a composition audio track
//! (spec §7.2).
//!
//! Swift hands each ramp to `AVMutableAudioMixInputParameters` as a linear
//! volume ramp over a time range, so everything that decides how loud a
//! composition audio track is at an instant — the clip's `volume`, its
//! `fade_in`/`fade_out`, volume ACTIONS, ducking from other clips, and the
//! three ways audio can be silenced (a muted clip, a muted track, a clip
//! with `enabled.audio` false) — has to be folded into one piecewise-linear
//! function of project time before it crosses the FFI. AVFoundation has no
//! notion of "these ramps multiply".
//!
//! The shape of the computation is **sample, then simplify**:
//!
//! 1. Collect BREAKPOINTS — every tick where the envelope can change slope
//!    or jump: clip edges, fade edges, duck edges, and a 1/30 s grid across
//!    every action that touches the audio group (an eased action is a
//!    curve, and a curve only becomes ramps by sampling it).
//! 2. EVALUATE the envelope at each breakpoint, once from the right and
//!    once from the left, which is what lets a genuine jump — a clip
//!    starting at full volume, a duck with a zero-length release — survive
//!    as two ramp endpoints instead of being smeared into a slope.
//! 3. COALESCE: adjacent ramps that lie on one straight line become one.
//!    A linear volume action sampled at 1/30 s collapses back to a single
//!    ramp; an eased one keeps the samples it needs.
//!
//! The result covers the composition track's whole extent with no gaps, in
//! start order — gaps between clips are ramps at 0, so the mix never plays
//! a track's ambient level under a hole in the timeline.
//!
//! Nothing here edits, and nothing here touches a sample: this is a
//! description of a gain curve, computed from the model alone.

use serde::Serialize;

use crate::model::{AudioProps, Clip, Duck, Project};
use crate::time::{Ticks, TIMESCALE};

/// One straight-line piece of an envelope: `from` at `start`, reaching `to`
/// at `start + duration`. The field names are the §7.2 JSON keys.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct Ramp {
    pub start: Ticks,
    pub duration: Ticks,
    pub from: f64,
    pub to: f64,
}

/// How finely an action's span is sampled (spec §7.2). 1/30 s is the
/// audible resolution of a volume move: a gain step every 33 ms is below
/// what the ear hears as a step even on a fast fade, and it keeps a ten
/// second action to three hundred breakpoints rather than the six million
/// ticks it spans.
const ACTION_SAMPLE: Ticks = TIMESCALE / 30;

/// A ceiling on the samples one action contributes, so an hour-long action
/// widens its step instead of adding a hundred thousand breakpoints. 4096
/// samples is over two minutes at the 1/30 s grid; past that the ramp is
/// slow enough that a coarser grid is inaudible.
const MAX_ACTION_SAMPLES: i64 = 4096;

/// Gain ceiling. `volume` is linear and may exceed 1, up to 4 (spec §5.2);
/// clamping here keeps one bad patch from sending +80 dB to the mix.
pub(crate) const MAX_GAIN: f64 = 4.0;

/// How close two ramps must be to count as one straight line. 1e-9 of
/// linear gain is roughly 1e-8 dB — some seven orders of magnitude below
/// what an ear or a 24-bit sample resolves — so merging across it cannot
/// change what anyone hears, and it lets the exactly-collinear samples of a
/// linear action collapse despite the last bit of floating-point noise.
const JOIN_EPS: f64 = 1e-9;

/// Which side of a breakpoint an evaluation is asking about.
///
/// A clip covers `[start, end)`: at `t == start` it is playing, at
/// `t == end` it is not. Evaluating the tick just before a boundary would
/// need a fictitious "one tick earlier", so instead the membership test
/// flips to `(start, end]` and the continuous part of the formula (a fade,
/// an action) is evaluated at the boundary itself, where it already equals
/// its own limit.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Side {
    /// The value AT the breakpoint — the start of the ramp that follows.
    Right,
    /// The limit approaching the breakpoint — the end of the ramp before.
    Left,
}

fn covers(start: Ticks, end: Ticks, t: Ticks, side: Side) -> bool {
    match side {
        Side::Right => start <= t && t < end,
        Side::Left => start < t && t <= end,
    }
}

fn clip_end(clip: &Clip) -> Ticks {
    clip.start.saturating_add(clip.duration)
}

/// A clip elsewhere in the project that pushes this track down while it
/// plays. Ducking is by clip EXTENT, not by voice activity (spec §11), so
/// this is all the ducker's audio needed to compute the gain.
#[derive(Debug, Clone, Copy)]
struct Ducker {
    start: Ticks,
    end: Ticks,
    duck: Duck,
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
fn duck_gain(ducker: &Ducker, t: Ticks, side: Side) -> f64 {
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

/// Merges ramps that continue one another as a single straight line.
///
/// Sampling an action produces a run of short ramps; where the underlying
/// curve is straight (a linear action, or any stretch with no action at
/// all) they all lie on one line and the run collapses to one entry. The
/// test extends the first ramp's line across the second's span and asks
/// whether it lands on the second's end value, which bounds the error in
/// GAIN units — the thing that matters — rather than in slope units.
fn coalesce(ramps: Vec<Ramp>) -> Vec<Ramp> {
    let mut out: Vec<Ramp> = Vec::with_capacity(ramps.len());
    for ramp in ramps {
        // A zero-length ramp carries no information and AVFoundation
        // rejects an empty time range.
        if ramp.duration <= 0 {
            continue;
        }
        if let Some(last) = out.last_mut() {
            if joins(last, &ramp) {
                last.duration = last.duration.saturating_add(ramp.duration);
                last.to = ramp.to;
                continue;
            }
        }
        out.push(ramp);
    }
    out
}

fn joins(a: &Ramp, b: &Ramp) -> bool {
    if a.duration <= 0 || b.duration <= 0 {
        return false;
    }
    // A jump between the two is a real event (a clip edge, a hard mute).
    if (a.to - b.from).abs() > JOIN_EPS {
        return false;
    }
    let total = a.duration.saturating_add(b.duration);
    let predicted = a.from + (a.to - a.from) / a.duration as f64 * total as f64;
    predicted.is_finite() && (predicted - b.to).abs() <= JOIN_EPS
}

impl Project {
    /// The volume envelope for ONE composition audio track: the clips in
    /// `comp_track_clips` are its segments (spec §7.2's A/B assignment
    /// guarantees they do not overlap).
    ///
    /// The returned ramps are in start order and tile the track's whole
    /// extent — first clip start to last clip end — with no gaps, so Swift
    /// can walk them straight into `setVolumeRamp(fromStartVolume:…)`
    /// without inventing anything in between. An empty input is an empty
    /// envelope.
    ///
    /// Folded in, in this order: the clip's `volume`; its fades; its volume
    /// actions; then ducking from every OTHER clip in the project whose
    /// `audio.duck` is set, multiplied over the whole thing. A clip that is
    /// silenced — `enabled.audio` false, `audio.muted`, or a muted track —
    /// contributes 0 over its extent, and so does a gap.
    pub fn audio_ramps(&self, comp_track_clips: &[&Clip]) -> Vec<Ramp> {
        let mut clips: Vec<&Clip> = comp_track_clips
            .iter()
            .copied()
            .filter(|c| c.duration > 0)
            .collect();
        clips.sort_by_key(|c| (c.start, c.id));
        let (Some(extent_start), Some(extent_end)) = (
            clips.iter().map(|c| c.start).min(),
            clips.iter().map(|c| clip_end(c)).max(),
        ) else {
            return Vec::new();
        };
        if extent_end <= extent_start {
            return Vec::new();
        }

        let duckers = self.duckers(&clips);
        let breaks = self.breakpoints(&clips, &duckers, extent_start, extent_end);

        let mut ramps: Vec<Ramp> = Vec::with_capacity(breaks.len());
        for pair in breaks.windows(2) {
            let (Some(&a), Some(&b)) = (pair.first(), pair.get(1)) else {
                continue;
            };
            if b <= a {
                continue;
            }
            ramps.push(Ramp {
                start: a,
                duration: b.saturating_sub(a),
                from: self.gain_at(&clips, &duckers, a, Side::Right),
                to: self.gain_at(&clips, &duckers, b, Side::Left),
            });
        }
        coalesce(ramps)
    }

    /// Every clip whose `audio.duck` is set that is NOT one of this
    /// composition track's own segments. A clip does not duck the track it
    /// plays on: ducking exists to lower the OTHER material, and a segment
    /// ducking its own neighbours on one composition track would be a
    /// feedback loop with no user-visible cause.
    ///
    /// The duck is read from the base props, not through actions: the ramp
    /// lengths describe an envelope, and an envelope whose own attack time
    /// animates is not a version-1 feature.
    fn duckers(&self, own: &[&Clip]) -> Vec<Ducker> {
        self.clips
            .iter()
            .filter(|c| !own.iter().any(|o| o.id == c.id))
            .filter_map(|c| {
                c.audio.and_then(|a| a.duck).map(|duck| Ducker {
                    start: c.start,
                    end: clip_end(c),
                    duck,
                })
            })
            .collect()
    }

    /// The ticks the envelope is sampled at: the ends of the extent, every
    /// clip and fade edge, every duck edge, and a 1/30 s grid inside each
    /// action that touches the audio group. Sorted, deduplicated, and
    /// clipped to the extent, so the ramps built from consecutive entries
    /// tile it exactly.
    fn breakpoints(
        &self,
        clips: &[&Clip],
        duckers: &[Ducker],
        extent_start: Ticks,
        extent_end: Ticks,
    ) -> Vec<Ticks> {
        let mut breaks: Vec<Ticks> = vec![extent_start, extent_end];

        for clip in clips {
            let end = clip_end(clip);
            breaks.push(clip.start);
            breaks.push(end);
            // Fades come from the base props. If an action animates a fade
            // length the action's own samples below carry the change; the
            // fade edges are only a promise that the two obvious corners
            // are breakpoints.
            let props = clip.audio.unwrap_or_default();
            if props.fade_in > 0 {
                breaks.push(clip.start.saturating_add(props.fade_in));
            }
            if props.fade_out > 0 {
                breaks.push(end.saturating_sub(props.fade_out));
            }

            for action in &clip.actions {
                // Only the audio group can move the envelope: an action
                // interpolates the whole state toward its patch, so a patch
                // that never mentions `audio` leaves the gain exactly
                // constant across its span and needs no samples.
                if action.duration <= 0 || action.end.get("audio").is_none() {
                    continue;
                }
                let start = clip.start.saturating_add(action.start);
                let end = start.saturating_add(action.duration);
                breaks.push(start);
                breaks.push(end);
                let step = ACTION_SAMPLE.max(action.duration / MAX_ACTION_SAMPLES + 1);
                let mut t = start.saturating_add(step);
                while t < end {
                    breaks.push(t);
                    t = t.saturating_add(step);
                }
            }
        }

        for ducker in duckers {
            breaks.push(ducker.start);
            breaks.push(ducker.start.saturating_add(ducker.duck.attack.max(0)));
            breaks.push(ducker.end);
            breaks.push(ducker.end.saturating_add(ducker.duck.release.max(0)));
        }

        breaks.retain(|t| *t >= extent_start && *t <= extent_end);
        breaks.sort_unstable();
        breaks.dedup();
        breaks
    }

    /// The whole track's gain at one instant: the covering segment's own
    /// gain (0 in a gap) times every ducker's multiplier.
    fn gain_at(&self, clips: &[&Clip], duckers: &[Ducker], t: Ticks, side: Side) -> f64 {
        // Segments on one composition track never overlap, so the first
        // covering clip is the only one; `find` on the start-ordered list
        // keeps a hand-written overlap deterministic rather than summing
        // two clips into a gain nobody asked for.
        let mut gain = clips
            .iter()
            .find(|c| covers(c.start, clip_end(c), t, side))
            .map(|c| self.clip_gain(c, t))
            .unwrap_or(0.0);
        for ducker in duckers {
            gain *= duck_gain(ducker, t, side);
        }
        gain
    }

    /// One clip's own gain at project time `t`: its evaluated volume shaped
    /// by its fades, or 0 if it is silenced.
    fn clip_gain(&self, clip: &Clip, t: Ticks) -> f64 {
        if !clip.enabled.audio {
            return 0.0;
        }
        // A muted TRACK still gets its segments in the composition — the
        // plan does not change when the user unmutes (spec §7.2) — so the
        // mute has to show up here, as a zero envelope.
        if self.track(clip.track).is_some_and(|t| t.muted) {
            return 0.0;
        }

        let clip_t = t.saturating_sub(clip.start);
        let props = self.audio_props_at(clip, clip_t);
        if props.muted {
            return 0.0;
        }
        let mut gain = if props.volume.is_finite() {
            props.volume.clamp(0.0, MAX_GAIN)
        } else {
            0.0
        };

        // Fades are ramps from 0 and to 0 at the clip's OWN edges, in clip
        // time, so they follow the clip when it moves and shrink with a
        // trim only when the user shortens them. A fade longer than the
        // clip, or a pair that overlaps, multiplies — the honest reading of
        // "both are in effect here" and a dip rather than a discontinuity.
        if props.fade_in > 0 && clip_t < props.fade_in {
            gain *= (clip_t.max(0) as f64 / props.fade_in as f64).clamp(0.0, 1.0);
        }
        let fade_out_start = clip.duration.saturating_sub(props.fade_out.max(0));
        if props.fade_out > 0 && clip_t > fade_out_start {
            let remaining = clip.duration.saturating_sub(clip_t).max(0) as f64;
            gain *= (remaining / props.fade_out as f64).clamp(0.0, 1.0);
        }
        gain
    }

    /// The clip's audio props at a clip time, through its actions.
    ///
    /// The fast path matters: [`Project::audio_ramps`] asks for this at
    /// every breakpoint, and a clip with no actions has the same props at
    /// all of them, so the serialize/deserialize round trip in
    /// `evaluate_clip` is skipped entirely for the common case.
    fn audio_props_at(&self, clip: &Clip, clip_t: Ticks) -> AudioProps {
        if clip.actions.is_empty() {
            return clip.audio.unwrap_or_default();
        }
        self.evaluate_clip(clip, clip_t).audio
    }
}
