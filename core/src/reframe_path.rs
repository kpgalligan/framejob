//! The framing path's keys (road map "creator-jobs" VR2a1 and VR2a2, spec
//! §11 VR-23, VR-24): what the chosen subject per sample becomes as keys of
//! F. VR-23's moves — the median-filtered subject point, the dead zone, the
//! speed, the spacing — moved here whole from `reframe.rs`, which keeps the
//! frames, the composition and the mapping into clip time; VR-24 adds what
//! a real recording needs beyond them:
//!
//! - **a hard cut at each shot change** — a one-frame `linear` segment
//!   ending exactly on the first canvas frame that shows the new shot, onto
//!   the new shot's subject's median over its first second;
//! - **loss** — a subject gone is held [`LOSS_HOLD`], then another subject is
//!   followed, or the framing eases over [`EMPTY_EASE`] to the `where_empty`
//!   state and the path goes EMPTY;
//! - **return** — from EMPTY once a subject has been seen for
//!   [`RETURN_SEEN`];
//! - **two people** framed together when both boxes, widened by
//!   [`PAIR_WIDEN`], fit the window.
//!
//! No move or ease ends after the frame before a cut, and a cut counts as a
//! move's end for VR-23's spacing. Every key is on the canvas's grid and the
//! keys are strictly increasing.

use crate::actions::ease;
use crate::model::Curve;
use crate::reframe::{
    Frame, FramingKey, FramingPath, FramingRequest, FramingTuning, Point, WhereEmpty,
};
pub use crate::reframe_tracks::LOSS_HOLD;
use crate::reframe_tracks::{median, Chosen, SubjectBox, SubjectKind};
use crate::time::{
    one_frame, snap_down_to_frame, snap_to_frame, snap_up_to_frame, Fps, Ticks, TIMESCALE,
};

/// The ease to `where_empty` after a loss: 0.8 s.
pub const EMPTY_EASE: Ticks = TIMESCALE * 4 / 5;
/// How long a subject must be seen at every sample before the framing
/// returns to it from EMPTY: 0.6 s.
pub const RETURN_SEEN: Ticks = TIMESCALE * 3 / 5;
/// A cut places the new shot on its subject's median over this: 1 s.
pub const CUT_MEDIAN: Ticks = TIMESCALE;
/// Each of two people's boxes is widened by this about its centre before
/// their union is tested against the window.
pub const PAIR_WIDEN: f64 = 1.15;

/// The subject point's median reads ±0.5 s.
const MEDIAN_SPAN: Ticks = TIMESCALE / 2;
/// The shortest move: 0.4 s.
pub(crate) const MOVE_MIN: f64 = 0.4;
/// No move within 0.5 s of the last one's end…
pub(crate) const MOVE_SPACING: Ticks = TIMESCALE / 2;

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

/// What the framing holds: a window centred on a source-canvas point, or
/// the whole picture fitted.
#[derive(Debug, Clone, Copy, PartialEq)]
enum At {
    Window(Point),
    Fit,
}

/// The keys as they are written, and the state they leave.
struct Writer<'a> {
    frame: &'a Frame,
    keys: Vec<FramingKey>,
    current: At,
    shows_fit: bool,
    last_end: Option<Ticks>,
}

impl Writer<'_> {
    fn key(&self, t: Ticks, at: At, curve: Curve) -> FramingKey {
        match at {
            At::Window(wc) => self.frame.key(t, wc, curve),
            At::Fit => self.frame.fit_key(t, curve),
        }
    }

    /// A hold key at `start` (unless the last key is there already) and the
    /// key `to` at `end` with `curve`.
    fn go(&mut self, start: Ticks, end: Ticks, to: At, curve: Curve) {
        if start > self.keys.last().expect("the first key").t {
            self.keys.push(self.key(start, self.current, Curve::Linear));
        }
        self.keys.push(self.key(end, to, curve));
        self.shows_fit |= to == At::Fit;
        self.current = to;
        self.last_end = Some(end);
    }

    fn running(&self, t: Ticks) -> bool {
        self.last_end.is_some_and(|end| t < end)
    }
}

/// The subject point and offset of a chosen sample (VR-22), its pair's
/// union standing in when both widened boxes fit the window (VR-24 (g)).
fn point_of(frame: &Frame, c: &Chosen, headroom: f64) -> Option<(SubjectKind, Point, Point)> {
    let (kind, b) = (c.kind?, c.subject?);
    let widened = |b: &SubjectBox| {
        let (cx, cy) = (b.x + b.w / 2.0, b.y + b.h / 2.0);
        let (w, h) = (b.w * PAIR_WIDEN, b.h * PAIR_WIDEN);
        (cx - w / 2.0, cy - h / 2.0, cx + w / 2.0, cy + h / 2.0)
    };
    let pair = c.second.and_then(|other| {
        let (a, o) = (widened(&b), widened(&other));
        let (x0, y0) = (a.0.min(o.0), a.1.min(o.1));
        let (x1, y1) = (a.2.max(o.2), a.3.max(o.3));
        let (p0, p1) = (frame.point(c.t, x0, y0), frame.point(c.t, x1, y1));
        let fits = p1.0 - p0.0 <= frame.window.0 && p1.1 - p0.1 <= frame.window.1;
        fits.then_some(SubjectBox {
            x: x0,
            y: y0,
            w: x1 - x0,
            h: y1 - y0,
            c: b.c,
        })
    });
    let (p, offset) = frame.subject(c.t, kind, &pair.unwrap_or(b), headroom);
    Some((kind, p, offset))
}

/// The keys of one clip's path (spec §11 VR-23, VR-24): `chosen` one per
/// sample in clip ticks, `shots` the cuts in clip ticks (`Round::Up`).
pub(crate) fn write_keys(
    frame: &Frame,
    chosen: &[Chosen],
    shots: &[Ticks],
    duration: Ticks,
    fps: Fps,
    request: &FramingRequest,
    tuning: &FramingTuning,
) -> FramingPath {
    let shot = |t: Ticks| shots.partition_point(|&c| c <= t);
    let (ww, wh) = frame.window;
    let one = one_frame(fps);
    // Each kept cut: its shot's clip tick and its key time `c`, the first
    // canvas frame that shows the new shot (VR-24 (a)).
    let mut cuts: Vec<(Ticks, Ticks)> = shots
        .iter()
        .map(|&s| (s, snap_up_to_frame(s, fps)))
        .filter(|&(_, c)| c > one && c < duration)
        .collect();
    cuts.dedup_by_key(|&mut (_, c)| c);
    let empty_state = match request.where_empty {
        WhereEmpty::Center => At::Window(frame.centre()),
        WhereEmpty::Fit => At::Fit,
    };

    // Each chosen sample's kind, subject point and offset (VR-22, VR-24 (g)).
    let points: Vec<Option<(SubjectKind, Point, Point)>> = chosen
        .iter()
        .map(|c| point_of(frame, c, tuning.headroom))
        .collect();
    // The median over ±0.5 s of the same kind in the same shot, then the
    // desired window centre, clamped (VR-23).
    let filtered: Vec<Option<(Point, Point)>> = (0..chosen.len())
        .map(|i| {
            let (kind, _, offset) = points[i]?;
            let t = chosen[i].t;
            let lo = chosen.partition_point(|q| q.t < t - MEDIAN_SPAN);
            let hi = chosen.partition_point(|q| q.t <= t + MEDIAN_SPAN);
            let near: Vec<Point> = (lo..hi)
                .filter_map(|j| points[j].filter(|q| q.0 == kind).map(|q| (j, q.1)))
                .filter(|&(j, _)| shot(chosen[j].t) == shot(t))
                .map(|(_, p)| p)
                .collect();
            let mut xs: Vec<f64> = near.iter().map(|p| p.0).collect();
            let mut ys: Vec<f64> = near.iter().map(|p| p.1).collect();
            let fp = (median(&mut xs), median(&mut ys));
            Some((fp, frame.clamp((fp.0 + offset.0, fp.1 + offset.1))))
        })
        .collect();

    // The first key (VR-24 (f)): the first chosen sample's desired centre
    // when one is chosen within `LOSS_HOLD` in the first shot, else EMPTY.
    let first_cut = cuts.first().map_or(Ticks::MAX, |&(s, _)| s);
    let first = (0..chosen.len()).find(|&i| filtered[i].is_some());
    let (start_at, mut following) = match first {
        Some(i) if chosen[i].t < LOSS_HOLD && chosen[i].t < first_cut => (
            At::Window(filtered[i].expect("chosen").1),
            chosen[i].identity,
        ),
        _ => (empty_state, None),
    };
    let mut empty = start_at == empty_state && following.is_none();
    let mut w = Writer {
        frame,
        keys: Vec::new(),
        current: start_at,
        shows_fit: start_at == At::Fit,
        last_end: None,
    };
    w.keys.push(w.key(0, start_at, Curve::Linear));
    let mut cut_keys: Vec<Ticks> = Vec::new();

    let mut loss: Option<Ticks> = None;
    let mut seen: Option<Ticks> = None;
    let mut next = 0usize;
    // The frame before a cut's, and the latest a move or an ease may end:
    // the frame before the next cut.
    let before = |c: Ticks| snap_down_to_frame(c - 1, fps);
    let limit = |next: usize| cuts.get(next).map_or(duration, |&(_, c)| before(c));
    let mut i = 0usize;
    while i <= chosen.len() {
        let t = chosen.get(i).map_or(Ticks::MAX, |c| c.t);
        // Each cut at or before this sample, in order (VR-24 (b)).
        while next < cuts.len() && cuts[next].0 <= t {
            let (s, c) = cuts[next];
            let in_shot: Vec<usize> = (0..chosen.len())
                .filter(|&j| shot(chosen[j].t) == shot(s) && chosen[j].t < c + CUT_MEDIAN)
                .collect();
            let lead = in_shot.iter().copied().find(|&j| points[j].is_some());
            let to = match lead {
                Some(l) => {
                    let (kind, _, offset) = points[l].expect("chosen");
                    let same: Vec<Point> = in_shot
                        .iter()
                        .filter(|&&j| chosen[j].identity == chosen[l].identity)
                        .filter_map(|&j| points[j].filter(|q| q.0 == kind).map(|q| q.1))
                        .collect();
                    let mut xs: Vec<f64> = same.iter().map(|p| p.0).collect();
                    let mut ys: Vec<f64> = same.iter().map(|p| p.1).collect();
                    let m = (median(&mut xs), median(&mut ys));
                    At::Window(frame.clamp((m.0 + offset.0, m.1 + offset.1)))
                }
                None => empty_state,
            };
            if to != w.current {
                w.go(before(c), c, to, Curve::Linear);
                cut_keys.push(c);
            }
            w.last_end = Some(c);
            empty = lead.is_none();
            following = lead.and_then(|l| chosen[l].identity);
            loss = None;
            seen = None;
            next += 1;
        }
        let Some(c) = chosen.get(i) else { break };
        i += 1;
        let has = filtered[i - 1];
        if empty {
            // Return from EMPTY (VR-24 (e)).
            if has.is_none() {
                seen = None;
                continue;
            }
            let since = *seen.get_or_insert(t);
            if t - since < RETURN_SEEN || w.running(t) {
                continue;
            }
            let desired = has.expect("chosen").1;
            let centre = frame.centre();
            let distance = (desired.0 - centre.0).hypot(desired.1 - centre.1);
            let seconds = MOVE_MIN.max(distance / (tuning.speed * ww));
            if let Some((start, end)) = span(t, seconds, duration, fps) {
                if end <= limit(next) {
                    w.go(start, end, At::Window(desired), Curve::EaseInOut);
                    empty = false;
                    following = c.identity;
                    seen = None;
                    loss = None;
                }
            }
            continue;
        }
        // Loss (VR-24 (d)).
        match loss {
            None if has.is_none() || (c.lost && c.identity != following) => {
                loss = Some(t);
                continue;
            }
            None => {}
            Some(t0) => {
                if has.is_some() && !c.lost && c.identity == following {
                    loss = None;
                } else if t - t0 < LOSS_HOLD {
                    continue;
                } else if has.is_some() {
                    loss = None;
                } else {
                    if !w.running(t) {
                        let seconds = EMPTY_EASE as f64 / TIMESCALE as f64;
                        if let Some((start, end)) = span(t, seconds, duration, fps) {
                            if end <= limit(next) {
                                w.go(start, end, empty_state, Curve::EaseInOut);
                                empty = true;
                                loss = None;
                                seen = None;
                                following = None;
                            }
                        }
                    }
                    continue;
                }
            }
        }
        following = c.identity;
        // VR-23's move.
        let (fp, desired) = has.expect("chosen");
        let At::Window(current) = w.current else {
            continue;
        };
        if w.running(t) {
            continue;
        }
        let (dx, dy) = (desired.0 - current.0, desired.1 - current.1);
        if dx.abs() <= tuning.dead_zone_width * ww && dy.abs() <= tuning.dead_zone_height * wh {
            continue;
        }
        let outside = (fp.0 - current.0).abs() > ww / 2.0 || (fp.1 - current.1).abs() > wh / 2.0;
        if w.last_end.is_some_and(|end| t < end + MOVE_SPACING) && !outside {
            continue;
        }
        let seconds = MOVE_MIN.max(dx.hypot(dy) / (tuning.speed * ww));
        if let Some((start, end)) = span(t, seconds, duration, fps) {
            if end <= limit(next) {
                w.go(start, end, At::Window(desired), Curve::EaseInOut);
            }
        }
    }
    FramingPath {
        keys: w.keys,
        shows_fit: w.shows_fit,
        cuts: cut_keys,
    }
}

/// A move of `seconds` from sample `t`, snapped (VR-23): at least a frame,
/// and `None` when it would end past the clip.
pub(crate) fn span(t: Ticks, seconds: f64, duration: Ticks, fps: Fps) -> Option<(Ticks, Ticks)> {
    let length = (seconds * TIMESCALE as f64).min((duration as f64) * 2.0 + 1.0);
    let start = snap_to_frame(t, fps);
    let mut end = snap_to_frame(t.saturating_add(length.round() as Ticks), fps);
    if end <= start {
        end = snap_up_to_frame(start + 1, fps);
    }
    (end <= duration).then_some((start, end))
}
