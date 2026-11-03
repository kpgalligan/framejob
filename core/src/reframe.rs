//! The framing planner (road map "creator-jobs" VR2a1, spec §11 VR-20,
//! VR-22, VR-23): a clip's analysed subjects in, a [`FramingPath`] out — a
//! similarity per instant from the canvas the clip was authored for (`Ws ×
//! Hs`) to the current one (`W × H`). Pure; nothing here edits. VR2a2's op
//! writes the path as the clip's base and actions.
//!
//! **The frames.** A box is 0…1 of the upright picture from its top-left. Its
//! point `(bx, by)` is `u = (bx·mw − mw/2, by·mh − mh/2)` px from the
//! UNCROPPED centre (`mw × mh` the media's displayed size), and lands on the
//! source canvas at `anchor + s·u` — `edit_zoom.rs`'s (★) at θ = 0, with
//! `anchor` and `s` the clip's base `video`. A crop moves only the
//! picture's extent, the cropped rect `anchor + s·(c ± (cw/2, ch/2))`, so
//! the analysis cache never depends on it.
//!
//! **The window.** The part of the source canvas the target shows: `W/k ×
//! H/k`, where `k·s` is `zoom ×` the fill scale of the cropped picture on
//! the target (`Project::fill_scale`), at most `SCALE_MAX`. A key is
//! `(k, dx, dy)` with `dx = k·(Ws/2 − wc.x)`, `dy = k·(Hs/2 − wc.y)` for a
//! window centred at `wc`; composed into a placement as `scale′ = k·scale,
//! x′ = k·x + dx, y′ = k·y + dy` (VR-3, VR-27). Every `wc` is clamped so the
//! window lies inside the cropped rect (VR-7's covering key).
//!
//! **The path.** VR-21 (`reframe_tracks.rs`) chooses a subject per sample;
//! VR-22 composes the window on it; VR-23 moves the window only when the
//! median-filtered subject leaves a dead zone, each move a hold key and an
//! eased key, snapped to the canvas's frames.

use crate::actions::ease;
use crate::clip_source_time::{clip_time_of_source, in_played_window, Round};
use crate::model::{Clip, Curve, MediaKind, Project, Source};
use crate::props_check::SCALE_MAX;
use crate::reframe_tracks::median;
pub use crate::reframe_tracks::{
    choose_subject, Chosen, Follow, SubjectBox, SubjectKind, SubjectSample,
};
use crate::time::{snap_to_frame, snap_up_to_frame, Ticks, TIMESCALE};

/// A clip's analysed subjects in MEDIA source ticks of the forward file.
#[derive(Debug, Clone, PartialEq)]
pub struct Subjects {
    pub samples: Vec<SubjectSample>,
    pub shots: Vec<Ticks>,
}

/// What to follow, how tight (1…4 × fill), and the canvas the clip was
/// authored for.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FramingRequest {
    pub follow: Follow,
    pub zoom: f64,
    pub from_width: u32,
    pub from_height: u32,
}

/// VR-22's and VR-23's numbers: the dead zone as shares of the window's
/// width and height, the speed in window widths a second, the headroom as a
/// share of the window's height.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FramingTuning {
    pub dead_zone_width: f64,
    pub dead_zone_height: f64,
    pub speed: f64,
    pub headroom: f64,
}

/// VR-S2's verdict (spec §11 VR-23): the dead zone 0.15 of the window's
/// width and 0.12 of its height, 0.8 window widths a second, the headroom
/// 0.38 (which the canned run could not measure, so it stays the first
/// number).
pub const FRAMING_TUNING: FramingTuning = FramingTuning {
    dead_zone_width: 0.15,
    dead_zone_height: 0.12,
    speed: 0.8,
    headroom: 0.38,
};

/// A person box's top sits this share of the window's height below its top.
const PERSON_TOP: f64 = 0.12;
/// The subject point's median reads ±0.5 s.
const MEDIAN_SPAN: Ticks = TIMESCALE / 2;
/// The shortest move: 0.4 s.
const MOVE_MIN: f64 = 0.4;
/// No move within 0.5 s of the last one's end…
const MOVE_SPACING: Ticks = TIMESCALE / 2;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FramingKey {
    pub t: Ticks,
    pub scale: f64,
    pub x: f64,
    pub y: f64,
    pub curve: Curve,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FramingPath {
    pub keys: Vec<FramingKey>,
}

impl FramingPath {
    /// (scale, x, y) at clip tick `t`: the segment ending at key i eases with
    /// key i's curve (`actions::ease`); before the first key its value, after
    /// the last its value.
    pub fn at(&self, t: Ticks) -> (f64, f64, f64) {
        let value = |k: &FramingKey| (k.scale, k.x, k.y);
        let Some(first) = self.keys.first() else {
            return (1.0, 0.0, 0.0);
        };
        let Some(i) = self.keys.iter().position(|k| k.t >= t) else {
            return value(self.keys.last().expect("not empty"));
        };
        if i == 0 {
            return value(first);
        }
        let (a, b) = (&self.keys[i - 1], &self.keys[i]);
        let e = ease(b.curve, (t - a.t) as f64 / (b.t - a.t) as f64);
        (
            a.scale + (b.scale - a.scale) * e,
            a.x + (b.x - a.x) * e,
            a.y + (b.y - a.y) * e,
        )
    }

    /// Keys whose (scale, x, y) differ from the previous key's.
    pub fn moves(&self) -> usize {
        self.keys
            .windows(2)
            .filter(|w| (w[0].scale, w[0].x, w[0].y) != (w[1].scale, w[1].x, w[1].y))
            .count()
    }
}

type Point = (f64, f64);

/// The geometry one plan reads: the clip's placement on the source canvas,
/// the cropped rect, and the window.
struct Frame {
    anchor: Point,
    s: f64,
    media: Point,
    rect: (Point, Point),
    k: f64,
    window: Point,
    half_source: Point,
}

impl Frame {
    fn of(project: &Project, clip: &Clip, request: &FramingRequest) -> Option<Frame> {
        let Source::Media { media, .. } = clip.source else {
            return None;
        };
        let media = project.media(media)?;
        let video = clip.video.clone().unwrap_or_default();
        if media.kind != MediaKind::Video || !media.has_video || video.rotation != 0.0 {
            return None;
        }
        let (mw, mh) = (f64::from(media.width), f64::from(media.height));
        let zoom = request.zoom;
        let (ws, hs) = (
            f64::from(request.from_width),
            f64::from(request.from_height),
        );
        if mw <= 0.0 || mh <= 0.0 || !(1.0..=4.0).contains(&zoom) || ws <= 0.0 || hs <= 0.0 {
            return None;
        }
        let crop = video.crop;
        let (cw, ch) = (mw - crop.l - crop.r, mh - crop.t - crop.b);
        let s = video.scale;
        if !(cw > 0.0 && ch > 0.0 && s.is_finite() && s > 0.0) {
            return None;
        }
        let anchor = (ws / 2.0 + video.x, hs / 2.0 + video.y);
        let c = ((crop.l - crop.r) / 2.0, (crop.t - crop.b) / 2.0);
        let rect = (
            (
                anchor.0 + s * (c.0 - cw / 2.0),
                anchor.1 + s * (c.1 - ch / 2.0),
            ),
            (
                anchor.0 + s * (c.0 + cw / 2.0),
                anchor.1 + s * (c.1 + ch / 2.0),
            ),
        );
        let k = (zoom * project.fill_scale(cw, ch)).min(SCALE_MAX) / s;
        let (w, h) = (
            f64::from(project.canvas.width),
            f64::from(project.canvas.height),
        );
        Some(Frame {
            anchor,
            s,
            media: (mw, mh),
            rect,
            k,
            window: (w / k, h / k),
            half_source: (ws / 2.0, hs / 2.0),
        })
    }

    /// A box point (0…1 of the picture) on the source canvas.
    fn point(&self, bx: f64, by: f64) -> Point {
        let (mw, mh) = self.media;
        (
            self.anchor.0 + self.s * (bx * mw - mw / 2.0),
            self.anchor.1 + self.s * (by * mh - mh / 2.0),
        )
    }

    /// `wc` moved so the window lies inside the cropped rect (its centre
    /// when the window is the larger).
    fn clamp(&self, wc: Point) -> Point {
        let ((x0, y0), (x1, y1)) = self.rect;
        let axis = |v: f64, lo: f64, hi: f64| {
            if lo > hi {
                (lo + hi) / 2.0
            } else {
                v.clamp(lo, hi)
            }
        };
        (
            axis(wc.0, x0 + self.window.0 / 2.0, x1 - self.window.0 / 2.0),
            axis(wc.1, y0 + self.window.1 / 2.0, y1 - self.window.1 / 2.0),
        )
    }

    fn key(&self, t: Ticks, wc: Point, curve: Curve) -> FramingKey {
        FramingKey {
            t,
            scale: self.k,
            x: self.k * (self.half_source.0 - wc.0),
            y: self.k * (self.half_source.1 - wc.1),
            curve,
        }
    }

    /// VR-22: the subject point of a kind's box, and the window centre's
    /// offset from it.
    fn subject(&self, kind: SubjectKind, b: &SubjectBox, headroom: f64) -> (Point, Point) {
        let (w, h) = self.window;
        match kind {
            SubjectKind::Face => {
                let lift = if h > w { h / 2.0 - headroom * h } else { 0.0 };
                (self.point(b.x + b.w / 2.0, b.y + b.h / 2.0), (0.0, lift))
            }
            SubjectKind::Person => (
                self.point(b.x + b.w / 2.0, b.y),
                (0.0, h / 2.0 - PERSON_TOP * h),
            ),
            SubjectKind::Salient => (self.point(b.x + b.w / 2.0, b.y + b.h / 2.0), (0.0, 0.0)),
        }
    }
}

/// The samples and shots in clip time (VR-20): kept when in the played
/// window, ascending, one sample per clip tick (the earliest media tick's),
/// one shot per tick, a cut at 0 or at or past the end dropped.
fn in_clip_time(
    clip: &Clip,
    project: &Project,
    subjects: &Subjects,
) -> (Vec<SubjectSample>, Vec<Ticks>) {
    let Source::Media { media, .. } = clip.source else {
        return (Vec::new(), Vec::new());
    };
    let Some(media) = project.media(media) else {
        return (Vec::new(), Vec::new());
    };
    let at = |t: Ticks| {
        in_played_window(clip, media, t)
            .then(|| clip_time_of_source(clip, media, t, Round::Down))
            .flatten()
    };
    let mut samples: Vec<(Ticks, Ticks, &SubjectSample)> = subjects
        .samples
        .iter()
        .filter_map(|s| at(s.t).map(|c| (c, s.t, s)))
        .collect();
    samples.sort_by_key(|&(c, m, _)| (c, m));
    samples.dedup_by_key(|&mut (c, _, _)| c);
    let mut shots: Vec<Ticks> = subjects
        .shots
        .iter()
        .filter_map(|&t| at(t))
        .filter(|&c| c > 0 && c < clip.duration)
        .collect();
    shots.sort_unstable();
    shots.dedup();
    let samples = samples
        .into_iter()
        .map(|(c, _, s)| SubjectSample { t: c, ..s.clone() })
        .collect();
    (samples, shots)
}

/// The planner (spec §11 VR-20…VR-23). `None` for: no such clip, not a
/// media clip of a video media, a base rotation other than 0, a media with
/// no size, a crop or scale that leaves no picture, a zoom outside 1…4, or a
/// zero `from_width`/`from_height`. VR2a2 refuses each by name before
/// calling.
pub fn plan_framing(
    project: &Project,
    clip: u32,
    subjects: &Subjects,
    request: &FramingRequest,
    tuning: &FramingTuning,
) -> Option<FramingPath> {
    let clip = project.clip(clip)?;
    let frame = Frame::of(project, clip, request)?;
    let fps = project.canvas.fps;
    let (samples, shots) = in_clip_time(clip, project, subjects);
    let chosen = choose_subject(&samples, &shots, request.follow);
    let shot = |t: Ticks| shots.partition_point(|&c| c <= t);
    let (ww, wh) = frame.window;

    // Each chosen sample: its kind, subject point and offset (VR-22).
    let points: Vec<(Ticks, SubjectKind, Point, Point)> = chosen
        .iter()
        .filter_map(|c: &Chosen| match (c.kind, c.subject) {
            (Some(kind), Some(b)) => {
                let (p, offset) = frame.subject(kind, &b, tuning.headroom);
                Some((c.t, kind, p, offset))
            }
            _ => None,
        })
        .collect();
    // The median over ±0.5 s of the same kind in the same shot, then the
    // desired window centre, clamped (VR-23).
    let filtered: Vec<(Ticks, Point, Point)> = points
        .iter()
        .map(|&(t, kind, _, offset)| {
            let lo = points.partition_point(|q| q.0 < t - MEDIAN_SPAN);
            let hi = points.partition_point(|q| q.0 <= t + MEDIAN_SPAN);
            let near: Vec<Point> = points[lo..hi]
                .iter()
                .filter(|q| q.1 == kind && shot(q.0) == shot(t))
                .map(|q| q.2)
                .collect();
            let mut xs: Vec<f64> = near.iter().map(|p| p.0).collect();
            let mut ys: Vec<f64> = near.iter().map(|p| p.1).collect();
            let fp = (median(&mut xs), median(&mut ys));
            (t, fp, frame.clamp((fp.0 + offset.0, fp.1 + offset.1)))
        })
        .collect();

    let mut current = match filtered.first() {
        Some(&(_, _, desired)) => desired,
        None => {
            let ((x0, y0), (x1, y1)) = frame.rect;
            ((x0 + x1) / 2.0, (y0 + y1) / 2.0)
        }
    };
    let mut keys = vec![frame.key(0, current, Curve::Linear)];
    let mut last_end: Option<Ticks> = None;
    for &(t, fp, desired) in &filtered {
        if last_end.is_some_and(|end| t < end) {
            continue;
        }
        let (dx, dy) = (desired.0 - current.0, desired.1 - current.1);
        if dx.abs() <= tuning.dead_zone_width * ww && dy.abs() <= tuning.dead_zone_height * wh {
            continue;
        }
        let outside = (fp.0 - current.0).abs() > ww / 2.0 || (fp.1 - current.1).abs() > wh / 2.0;
        if last_end.is_some_and(|end| t < end + MOVE_SPACING) && !outside {
            continue;
        }
        let seconds = MOVE_MIN.max(dx.hypot(dy) / (tuning.speed * ww));
        let length = (seconds * TIMESCALE as f64).min((clip.duration as f64) * 2.0 + 1.0);
        let start = snap_to_frame(t, fps);
        let mut end = snap_to_frame(t.saturating_add(length.round() as Ticks), fps);
        if end <= start {
            end = snap_up_to_frame(start + 1, fps);
        }
        if end > clip.duration {
            continue;
        }
        if start > keys.last().expect("the first key").t {
            keys.push(frame.key(start, current, Curve::Linear));
        }
        keys.push(frame.key(end, desired, Curve::EaseInOut));
        current = desired;
        last_end = Some(end);
    }
    Some(FramingPath { keys })
}
