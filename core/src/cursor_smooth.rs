//! A cursor file's smoothed path (spec §11 CU-21): the one hold rule, the
//! pins, Ramer–Douglas–Peucker between them and a centripetal Catmull–Rom
//! spline in time through what is kept. Positions stay in the file's units
//! (global points × 100) and times in its µs; `cursor_track.rs` maps them to
//! movie pixels and source ticks. Nothing here is carried from another
//! recorder (CU-8): each step is written from its stated rule.
//!
//! **The hold rule.** The recorder writes a move only when the position
//! changes, so a gap between two moves wider than the poll is the cursor
//! standing still. When moves i and i+1 are more than [`HOLD_GAP_US`] apart
//! it holds move i until `t[i+1] − POLL_US` and then moves linearly, which
//! is the poll the recorder would have seen it leave in. [`hold_end`] is the
//! one spelling of it; the raw path and the pins both read it.
//!
//! **The pins** are what the smoothed path passes through exactly: the
//! file's first and last moves (so the ends are defined), every down click
//! (replacing a move at the same t, so the cursor is where it clicked when it
//! clicked), and both ends of every hold (so a hold is still a hold). Between
//! consecutive pins RDP keeps the points further than `TOLERANCE_PT ×
//! smoothing` from the chord, so a larger smoothing keeps fewer points and
//! the spline draws a calmer path. The spline is non-causal: it reads the
//! point after the segment, so the smoothed cursor never lags a click.
//!
//! **The spline.** Centripetal Catmull–Rom (α ½) by Barry and Goldman's
//! pyramid, each segment's outer neighbours the kept points either side, a
//! missing one at the path's ends duplicated from the end itself; a knot step
//! (`|ΔP|^α`) is floored at [`KNOT_FLOOR`] so coincident points never divide
//! by zero. A segment between two equal positions is that position (a hold
//! between its two pins answers it exactly at every smoothing). Time maps
//! onto a segment linearly: `u = (at − t_i)/(t_{i+1} − t_i)` across the knot
//! span.

use crate::cursor_file::CursorFile;
use crate::cursor_track::{HOLD_GAP_US, POLL_US};

/// The RDP tolerance at smoothing 1, in points.
pub const TOLERANCE_PT: f64 = 12.0;
/// Centripetal: the knot step is the distance to this power.
const ALPHA: f64 = 0.5;
/// The smallest knot step, so a duplicated or coincident point never makes
/// a zero-width knot interval.
const KNOT_FLOOR: f64 = 1e-6;

/// Where move `i` stops holding: `t[i+1] − POLL_US` when moves i and i+1 are
/// more than `HOLD_GAP_US` apart, else `None`.
pub(crate) fn hold_end(t: &[i64], i: usize) -> Option<i64> {
    let next = *t.get(i + 1)?;
    (next - t[i] > HOLD_GAP_US).then_some(next - POLL_US)
}

/// One point of a path: µs and the file's units.
#[derive(Debug, Clone, Copy, PartialEq)]
struct Point {
    t: f64,
    x: f64,
    y: f64,
}

/// A smoothed path, built by `prepare` (or for one `path` request) and
/// never changed.
#[derive(Debug)]
pub(crate) struct SmoothPath {
    smoothing: f64,
    kept: Vec<Point>,
}

impl SmoothPath {
    /// The pins, RDP between them at `smoothing`, and the kept points in
    /// time order. A file with no moves keeps nothing.
    pub(crate) fn build(file: &CursorFile, smoothing: f64) -> SmoothPath {
        let points = pinned_points(file);
        let tolerance = TOLERANCE_PT * 100.0 * smoothing;
        let mut keep: Vec<bool> = points.iter().map(|(_, pin)| *pin).collect();
        let mut start = None;
        for (i, (_, pin)) in points.iter().enumerate() {
            if !pin {
                continue;
            }
            if let Some(s) = start {
                rdp(&points, s, i, tolerance, &mut keep);
            }
            start = Some(i);
        }
        let kept = points
            .iter()
            .zip(&keep)
            .filter(|(_, k)| **k)
            .map(|((p, _), _)| *p)
            .collect();
        SmoothPath { smoothing, kept }
    }

    pub(crate) fn smoothing(&self) -> f64 {
        self.smoothing
    }

    /// How many points the spline runs through.
    pub(crate) fn kept(&self) -> usize {
        self.kept.len()
    }

    /// The position at `t_us`, in the file's units: the first kept point
    /// before the path, the last after it. `None` with nothing kept.
    pub(crate) fn at(&self, t_us: f64) -> Option<(f64, f64)> {
        let k = &self.kept;
        let first = k.first()?;
        let last = k[k.len() - 1];
        if t_us <= first.t {
            return Some((first.x, first.y));
        }
        if t_us >= last.t {
            return Some((last.x, last.y));
        }
        // The segment [i, i+1] with k[i].t ≤ t_us < k[i+1].t.
        let i = k.partition_point(|p| p.t <= t_us) - 1;
        let (p1, p2) = (k[i], k[i + 1]);
        if p1.x == p2.x && p1.y == p2.y {
            return Some((p1.x, p1.y));
        }
        let p0 = if i > 0 { k[i - 1] } else { p1 };
        let p3 = k.get(i + 2).copied().unwrap_or(p2);
        let u = (t_us - p1.t) / (p2.t - p1.t);
        Some(catmull_rom(p0, p1, p2, p3, u))
    }
}

/// The moves with the clicks and the hold ends merged in, in time order,
/// each flagged when it is a pin.
fn pinned_points(file: &CursorFile) -> Vec<(Point, bool)> {
    let m = &file.moves;
    let n = m.t.len();
    if n == 0 {
        return Vec::new();
    }
    let c = &file.clicks;
    let downs: Vec<usize> = (0..c.t.len()).filter(|&i| c.down[i] == 1).collect();
    let down_t: Vec<i64> = downs.iter().map(|&i| c.t[i]).collect();
    let mut points: Vec<(Point, bool)> = Vec::with_capacity(n + downs.len() + 16);
    for i in 0..n {
        let p = Point {
            t: m.t[i] as f64,
            x: m.x[i] as f64,
            y: m.y[i] as f64,
        };
        let hold = hold_end(&m.t, i);
        // A move at a down click's t gives way to the click.
        if down_t.binary_search(&m.t[i]).is_err() {
            points.push((p, i == 0 || i == n - 1 || hold.is_some()));
        }
        if let Some(h) = hold {
            points.push((Point { t: h as f64, ..p }, true));
        }
    }
    for &i in &downs {
        let p = Point {
            t: c.t[i] as f64,
            x: c.x[i] as f64,
            y: c.y[i] as f64,
        };
        points.push((p, true));
    }
    // Stable, so a click lands after the moves and hold ends at its t.
    points.sort_by(|a, b| a.0.t.total_cmp(&b.0.t));
    points
}

/// Ramer–Douglas–Peucker over `points[a..=b]` with an explicit stack: marks
/// every point further than `tolerance` from its chord (to the segment, so
/// a point beyond either end counts by its distance to that end).
fn rdp(points: &[(Point, bool)], a: usize, b: usize, tolerance: f64, keep: &mut [bool]) {
    let mut stack = vec![(a, b)];
    while let Some((s, e)) = stack.pop() {
        if e <= s + 1 {
            continue;
        }
        let (ps, pe) = (points[s].0, points[e].0);
        let mut far = (0.0, s);
        for (j, (p, _)) in points.iter().enumerate().take(e).skip(s + 1) {
            let d = distance_to_segment(*p, ps, pe);
            if d > far.0 {
                far = (d, j);
            }
        }
        if far.0 > tolerance {
            keep[far.1] = true;
            stack.push((s, far.1));
            stack.push((far.1, e));
        }
    }
}

fn distance_to_segment(p: Point, a: Point, b: Point) -> f64 {
    let (dx, dy) = (b.x - a.x, b.y - a.y);
    let len2 = dx * dx + dy * dy;
    let s = if len2 > 0.0 {
        (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0)
    } else {
        0.0
    };
    (p.x - (a.x + s * dx)).hypot(p.y - (a.y + s * dy))
}

/// The knot step from `a` to `b`, floored.
fn knot(a: Point, b: Point) -> f64 {
    (b.x - a.x).hypot(b.y - a.y).powf(ALPHA).max(KNOT_FLOOR)
}

/// Barry–Goldman's pyramid at `u` (0…1) across the span from `p1` to `p2`.
fn catmull_rom(p0: Point, p1: Point, p2: Point, p3: Point, u: f64) -> (f64, f64) {
    let t0 = 0.0;
    let t1 = t0 + knot(p0, p1);
    let t2 = t1 + knot(p1, p2);
    let t3 = t2 + knot(p2, p3);
    let t = t1 + u * (t2 - t1);
    let mix = |a: (f64, f64), b: (f64, f64), ta: f64, tb: f64| {
        let (wa, wb) = ((tb - t) / (tb - ta), (t - ta) / (tb - ta));
        (wa * a.0 + wb * b.0, wa * a.1 + wb * b.1)
    };
    let (q0, q1, q2, q3) = ((p0.x, p0.y), (p1.x, p1.y), (p2.x, p2.y), (p3.x, p3.y));
    let a1 = mix(q0, q1, t0, t1);
    let a2 = mix(q1, q2, t1, t2);
    let a3 = mix(q2, q3, t2, t3);
    let b1 = mix(a1, a2, t0, t2);
    let b2 = mix(a2, a3, t1, t3);
    mix(b1, b2, t1, t2)
}
