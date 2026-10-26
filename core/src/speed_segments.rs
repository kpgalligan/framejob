//! A ramped clip's pieces of the composition plan (spec §7.2, §11 SR-10):
//! its video segments, and the one audio segment's map and glide spans.
//!
//! **Video** is segments: one per held piece of the clip's [`SpeedMap`],
//! and inside every ramp piece one per canvas frame, its boundaries at the
//! piece's edges and at every frame start strictly inside it in PROJECT time
//! (G = 1: SR1 read no wrong frame at any G, and a segment per frame samples
//! S exactly at every frame start). Segment k reads `in + round(S(t_k))`
//! for `round(S(t_k+1)) − round(S(t_k))` source ticks, so the source is
//! contiguous and totals `round(S(D))`.
//!
//! **Audio** is not segments (SR-6): Swift renders the clip's sound into one
//! file and plays it as one ×1 segment. What the plan hands it is the map —
//! breakpoints of clip ticks to source ticks, linear between them — and, with
//! keep pitch on, the spans that glide like tape until SR1d (SR-11).
//!
//! **The source map** (spec §11 SR-20 (a)) is what Swift's readers take
//! for a media clip, ramped or not, through `rc_project_source_map`: a
//! ramped clip's audio map, or a constant clip's two points. A ramped clip's
//! answer also carries `rate`, [`SpeedMap::rate_profile`]'s list, which the
//! action lanes draw as a line (spec §11 SR-26).
//!
//! Nothing here edits; `evaluate.rs` places what these answer.

use serde_json::{Map, Value};

use crate::model::{Clip, Project, Source};
use crate::speed_map::{Piece, SpeedMap};
use crate::time::{self, Ticks};

/// The audio map's sampling step inside a ramp piece, in clip ticks: 1 ms.
/// The renderer reads the map linearly between breakpoints, and a ramp's S
/// is a smooth polynomial, so 1 ms chords sit far under a sample's error.
pub(crate) const MAP_STEP: Ticks = 600;

/// One video segment of a ramped clip: `start` in PROJECT ticks, the source
/// range in media ticks.
pub(crate) struct SourceSpan {
    pub(crate) start: Ticks,
    pub(crate) duration: Ticks,
    pub(crate) source_in: Ticks,
    pub(crate) source_duration: Ticks,
}

/// The ramp object a ramped clip's audio segment carries.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct RampAudio {
    pub(crate) keep_pitch: bool,
    /// The ramp pieces' spans in clip ticks, abutting ones merged.
    pub(crate) glide: Vec<(Ticks, Ticks)>,
    /// `(clip tick, source tick)`, each source strictly above the last.
    pub(crate) map: Vec<(Ticks, Ticks)>,
}

fn pairs(list: &[(Ticks, Ticks)]) -> Value {
    Value::Array(
        list.iter()
            .map(|(a, b)| Value::Array(vec![Value::from(*a), Value::from(*b)]))
            .collect(),
    )
}

impl RampAudio {
    /// `{"keep_pitch", ["glide",] "map"}` — `glide` only with keep pitch
    /// on, since only that arm renders a span differently (SR-11).
    pub(crate) fn to_json(&self) -> Value {
        let mut out = Map::new();
        out.insert("keep_pitch".to_string(), Value::from(self.keep_pitch));
        if self.keep_pitch {
            out.insert("glide".to_string(), pairs(&self.glide));
        }
        out.insert("map".to_string(), pairs(&self.map));
        Value::Object(out)
    }
}

/// S(t) in whole source ticks.
fn read(map: &SpeedMap, t: Ticks) -> Ticks {
    let s = map.source_at(t).round();
    if s.is_finite() {
        s as Ticks
    } else {
        0
    }
}

impl Project {
    /// The clip-time boundaries of `piece`'s video segments: its edges and,
    /// in a ramp, every canvas frame start strictly inside it — measured in
    /// project time, since the composition's frames are the timeline's.
    fn segment_bounds(&self, clip: &Clip, piece: &Piece) -> Vec<Ticks> {
        let (from, to) = match piece {
            Piece::Held { from, to, .. } | Piece::Ramp { from, to, .. } => (*from, *to),
        };
        let mut out = vec![from];
        if let Piece::Ramp { .. } = piece {
            let fps = self.canvas.fps;
            let (lo, hi) = (
                clip.start.saturating_add(from),
                clip.start.saturating_add(to),
            );
            if let Some(first) = time::frame_index(lo, fps) {
                let mut k = first.saturating_sub(1);
                while let Some(tick) = time::tick_at_frame(k, fps) {
                    if tick >= hi {
                        break;
                    }
                    if tick > lo {
                        out.push(tick.saturating_sub(clip.start));
                    }
                    k = k.saturating_add(1);
                }
            }
        }
        out.push(to);
        out
    }

    /// The video segments of a ramped `clip` (lifted: `start` in project
    /// time, `duration` cut by any nest clip above it), reading from
    /// `source_in` in a media `file` ticks long, each clamped into the file
    /// as `evaluate.rs`'s constant segment is clamped.
    pub(crate) fn ramp_spans(
        &self,
        clip: &Clip,
        map: &SpeedMap,
        source_in: Ticks,
        file: Ticks,
    ) -> Vec<SourceSpan> {
        let last = file.saturating_sub(1).max(0);
        let mut out = Vec::new();
        for piece in map.pieces() {
            let bounds = self.segment_bounds(clip, piece);
            for pair in bounds.windows(2) {
                let (Some(&a), Some(&b)) = (pair.first(), pair.get(1)) else {
                    continue;
                };
                if b <= a {
                    continue;
                }
                let (sa, sb) = (read(map, a), read(map, b));
                let start_in = source_in.saturating_add(sa).clamp(0, last);
                let remaining = file.saturating_sub(start_in).max(0);
                out.push(SourceSpan {
                    start: clip.start.saturating_add(a),
                    duration: b.saturating_sub(a),
                    source_in: start_in,
                    source_duration: sb.saturating_sub(sa).max(1).min(remaining).max(1),
                });
            }
        }
        out
    }

    /// The ramp object of a ramped `clip`'s one audio segment: its keep
    /// pitch, its glide spans, and the map from `source_in` — breakpoints
    /// at 0, D, every piece edge and every [`MAP_STEP`] from each ramp
    /// piece's start; one whose source does not pass the last kept one is
    /// dropped, and D is always kept, displacing its predecessor instead.
    pub(crate) fn ramp_audio(&self, clip: &Clip, map: &SpeedMap, source_in: Ticks) -> RampAudio {
        let duration = clip.duration.max(0);
        let mut times: Vec<Ticks> = vec![0, duration];
        let mut glide: Vec<(Ticks, Ticks)> = Vec::new();
        for piece in map.pieces() {
            match piece {
                Piece::Held { from, to, .. } => times.extend([*from, *to]),
                Piece::Ramp { from, to, .. } => {
                    let mut t = *from;
                    while t < *to {
                        times.push(t);
                        t = t.saturating_add(MAP_STEP);
                    }
                    times.push(*to);
                    match glide.last_mut() {
                        Some(last) if last.1 == *from => last.1 = *to,
                        _ => glide.push((*from, *to)),
                    }
                }
            }
        }
        times.retain(|t| (0..=duration).contains(t));
        times.sort_unstable();
        times.dedup();

        let mut points: Vec<(Ticks, Ticks)> = Vec::with_capacity(times.len());
        for t in times {
            let source = source_in.saturating_add(read(map, t));
            let rises = points.last().is_none_or(|(_, s)| source > *s);
            if t == duration && !rises && points.len() > 1 {
                points.pop();
                points.push((t, source));
            } else if rises {
                points.push((t, source));
            }
        }
        RampAudio {
            keep_pitch: clip.audio.map(|a| a.keep_pitch).unwrap_or(true),
            glide,
            map: points,
        }
    }

    /// A media clip's source map (spec §11 SR-20 (a)): `{"ramped", "map"}`
    /// from `in` clamped into the file, as `ramp_segments_of` clamps it. A
    /// ramped clip answers [`Project::ramp_audio`]'s map, the plan's audio
    /// segment's own, and `"rate"`, [`SpeedMap::rate_profile`]'s
    /// `[[clip_tick, rate], …]` (spec §11 SR-26); a constant one
    /// `[[0, in], [D, in + length]]` and no `rate`. The clip is this
    /// project's own, unlifted. `None` for an unknown id, a clip that is not
    /// a media clip, or one whose media is gone.
    pub(crate) fn source_map(&self, clip_id: u32) -> Option<Value> {
        let clip = self.clip(clip_id)?;
        let Source::Media { media, r#in, .. } = &clip.source else {
            return None;
        };
        let found = self.media(*media)?;
        let last = found.duration.saturating_sub(1).max(0);
        let source_in = (*r#in).clamp(0, last);
        let (ramped, points, rate) = match SpeedMap::of(clip) {
            Some(map) => (
                true,
                self.ramp_audio(clip, &map, source_in).map,
                Some(map.rate_profile()),
            ),
            None => {
                let end = source_in.saturating_add(self.content_length_in_source(clip));
                (false, vec![(0, source_in), (clip.duration, end)], None)
            }
        };
        let mut out = Map::new();
        out.insert("ramped".to_string(), Value::from(ramped));
        out.insert("map".to_string(), pairs(&points));
        if let Some(rate) = rate {
            let rows = rate
                .iter()
                .map(|(t, r)| Value::Array(vec![Value::from(*t), Value::from(*r)]))
                .collect();
            out.insert("rate".to_string(), Value::Array(rows));
        }
        Some(Value::Object(out))
    }
}
