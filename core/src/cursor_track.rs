//! A loaded cursor file (spec §11 CU-20…CU-24): `CursorFile` parsed and
//! checked once, with the smoothed paths `prepare` stored beside it under a
//! lock. This is what an `RcCursor` handle is. It answers the arithmetic a
//! `state` request reads: where the cursor is at a source time, in movie
//! pixels; how opaque idle hide leaves it; which image is in force; which
//! click ripples are active. `cursor_query.rs` reads requests and writes
//! answers; `cursor_smooth.rs` is the smoothed path.
//!
//! **Times.** A file time is integer µs from the movie's first frame, and a
//! source tick is `time.rs`'s; file t 0 is source tick 0, and the two convert
//! through `ticks_to_seconds` / `seconds_to_ticks` × 1e6 ([`ticks_to_us`],
//! [`us_to_ticks`]) and nowhere else.
//!
//! **The mapping (CU-20, provisional M1).** A file position is global points
//! × 100. Movie px = `(p − screen_rect.origin) × content_scale ×
//! pixels_per_point + content_rect.origin × pixels_per_point`, every file
//! value ÷ 100, through the geometry entry in force at the sample's time:
//! the last entry with `t ≤` it, or the first before any. [`CursorTrack::to_movie`]
//! is the one function; movie px are content px (CU-16). CU-S2's verdict is
//! owed (JOB-29); the phase that records it amends this function if M2 or M3
//! wins.
//!
//! **The lock.** `prepared` holds every stored smoothing. A `state` holds it
//! only to clone an `Arc`; a `prepare` builds outside it and stores under
//! it. A poisoned lock is taken with `into_inner`, so no input panics.

use std::sync::{Arc, Mutex, MutexGuard};

use crate::cursor_file::{CursorFile, CursorImageMode, Geometry};
use crate::cursor_smooth::{hold_end, SmoothPath};
use crate::time::{seconds_to_ticks, ticks_to_seconds, Ticks};

/// The recorder's poll, in µs: a hold ends this long before the next move.
pub const POLL_US: i64 = 8_333;
/// A gap between moves wider than this is a hold (CU-21).
pub const HOLD_GAP_US: i64 = 25_000;
/// Idle hide's fade to nothing (CU-22).
pub const IDLE_FADE_US: i64 = 200_000;
/// Idle hide shows the cursor again this long before the next activity.
pub const IDLE_LEAD_US: i64 = 150_000;
/// How long a down click's ripple runs (CU-23).
pub const RIPPLE_US: i64 = 450_000;
/// The shader's ripple slots.
pub const MAX_RIPPLES: usize = 4;
/// A path is sampled at most 10 times a second (CU-25).
pub const PATH_MIN_STEP: Ticks = 60_000;
/// The most samples one `path` answers: four hours at 10 Hz.
pub const MAX_PATH_SAMPLES: usize = 144_000;

/// Source ticks to file µs.
pub fn ticks_to_us(t: Ticks) -> f64 {
    ticks_to_seconds(t) * 1e6
}

/// File µs to source ticks, rounded.
pub fn us_to_ticks(us: i64) -> Ticks {
    seconds_to_ticks(us as f64 / 1e6)
}

/// A click ripple at one instant: where, and how far through (0…1).
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Ripple {
    pub x: f64,
    pub y: f64,
    pub phase: f64,
}

/// One loaded cursor file and its prepared paths.
#[derive(Debug)]
pub struct CursorTrack {
    file: CursorFile,
    /// The clicks with `down` 1, by index into `file.clicks`, in time order.
    downs: Vec<usize>,
    /// Their times, for the binary searches.
    down_t: Vec<i64>,
    prepared: Mutex<Vec<Arc<SmoothPath>>>,
}

impl CursorTrack {
    /// `CursorFile::parse`, and an empty set of prepared paths.
    pub fn parse(bytes: &[u8]) -> Result<CursorTrack, String> {
        let file = CursorFile::parse(bytes)?;
        let c = &file.clicks;
        let downs: Vec<usize> = (0..c.t.len()).filter(|&i| c.down[i] == 1).collect();
        let down_t = downs.iter().map(|&i| c.t[i]).collect();
        Ok(CursorTrack {
            file,
            downs,
            down_t,
            prepared: Mutex::new(Vec::new()),
        })
    }

    pub fn file(&self) -> &CursorFile {
        &self.file
    }

    fn lock(&self) -> MutexGuard<'_, Vec<Arc<SmoothPath>>> {
        self.prepared.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// The stored path at `smoothing`, if `prepare` stored one.
    pub(crate) fn prepared(&self, smoothing: f64) -> Option<Arc<SmoothPath>> {
        self.lock()
            .iter()
            .find(|p| p.smoothing() == smoothing)
            .cloned()
    }

    /// Builds and stores the path at `smoothing` (above 0) unless one is
    /// stored; answers how many points it keeps.
    pub(crate) fn prepare(&self, smoothing: f64) -> usize {
        if let Some(path) = self.prepared(smoothing) {
            return path.kept();
        }
        let built = Arc::new(SmoothPath::build(&self.file, smoothing));
        let mut stored = self.lock();
        if let Some(path) = stored.iter().find(|p| p.smoothing() == smoothing) {
            return path.kept();
        }
        let kept = built.kept();
        stored.push(built);
        kept
    }

    /// Drops the stored path at `smoothing`; whether one was stored.
    pub(crate) fn unprepare(&self, smoothing: f64) -> bool {
        let mut stored = self.lock();
        let before = stored.len();
        stored.retain(|p| p.smoothing() != smoothing);
        stored.len() != before
    }

    /// The geometry entry in force at `t_us`: the last at or before it, the
    /// first before any (a checked file has at least one).
    fn geometry_at(&self, t_us: f64) -> &Geometry {
        let g = &self.file.geometry;
        let after = g.partition_point(|e| (e.t as f64) <= t_us);
        &g[after.saturating_sub(1)]
    }

    /// Pixels per point at `t_us`: `content_scale × pixels_per_point`.
    pub(crate) fn px_per_point(&self, t_us: f64) -> f64 {
        self.geometry_at(t_us).content_scale * self.file.pixels_per_point
    }

    /// CU-20's M1: a position in the file's units at `t_us` to movie px.
    pub(crate) fn to_movie(&self, t_us: f64, x: f64, y: f64) -> (f64, f64) {
        let g = self.geometry_at(t_us);
        let ppp = self.file.pixels_per_point;
        let map = |p: f64, screen: i64, content: i64| {
            (p / 100.0 - screen as f64 / 100.0) * g.content_scale * ppp
                + content as f64 / 100.0 * ppp
        };
        (
            map(x, g.screen_rect[0], g.content_rect[0]),
            map(y, g.screen_rect[1], g.content_rect[1]),
        )
    }

    /// The raw path at `t_us` (smoothing 0, CU-21): the moves linearly
    /// interpolated under the hold rule, the first move before them and the
    /// last after. `None` with no moves.
    pub(crate) fn raw_at(&self, t_us: f64) -> Option<(f64, f64)> {
        let m = &self.file.moves;
        let n = m.t.len();
        if n == 0 {
            return None;
        }
        let point = |i: usize| (m.x[i] as f64, m.y[i] as f64);
        if t_us <= m.t[0] as f64 {
            return Some(point(0));
        }
        if t_us >= m.t[n - 1] as f64 {
            return Some(point(n - 1));
        }
        let i = m.t.partition_point(|&t| (t as f64) <= t_us) - 1;
        let from = match hold_end(&m.t, i) {
            Some(h) if t_us <= h as f64 => return Some(point(i)),
            Some(h) => h as f64,
            None => m.t[i] as f64,
        };
        let s = (t_us - from) / (m.t[i + 1] as f64 - from);
        let (a, b) = (point(i), point(i + 1));
        Some((a.0 + s * (b.0 - a.0), a.1 + s * (b.1 - a.1)))
    }

    /// The position at `t_us` and `smoothing`, in the file's units: the
    /// stored path when `prepare` stored one, the raw path otherwise (a
    /// `state` never builds one, CU-21).
    pub(crate) fn position(&self, t_us: f64, smoothing: f64) -> Option<(f64, f64)> {
        if smoothing > 0.0 {
            if let Some(path) = self.prepared(smoothing) {
                return path.at(t_us);
            }
        }
        self.raw_at(t_us)
    }

    /// Idle hide's opacity at `t_us` (CU-22). `hide_idle` in µs, or `None`
    /// for never; 0 inside a recorded hidden span and with no moves.
    pub(crate) fn opacity(&self, t_us: f64, hide_idle: Option<f64>) -> f64 {
        if self.file.moves.t.is_empty() || self.in_hidden(t_us) {
            return 0.0;
        }
        let Some(idle) = hide_idle else {
            return 1.0;
        };
        let (last, next) = self.activity_around(t_us);
        if let Some(n) = next {
            if t_us >= n - IDLE_LEAD_US as f64 {
                return 1.0;
            }
        }
        let Some(l) = last else {
            return 0.0;
        };
        let idle_for = t_us - l;
        if idle_for < idle {
            return 1.0;
        }
        (1.0 - (idle_for - idle) / IDLE_FADE_US as f64).max(0.0)
    }

    fn in_hidden(&self, t_us: f64) -> bool {
        let h = &self.file.hidden;
        let after = h.from.partition_point(|&f| (f as f64) <= t_us);
        after > 0 && t_us < h.to[after - 1] as f64
    }

    /// The last activity (a move or a down click) at or before `t_us`, and
    /// the first after it.
    fn activity_around(&self, t_us: f64) -> (Option<f64>, Option<f64>) {
        let around = |t: &[i64]| {
            let after = t.partition_point(|&v| (v as f64) <= t_us);
            let last = after.checked_sub(1).map(|i| t[i] as f64);
            (last, t.get(after).map(|&v| v as f64))
        };
        let (lm, nm) = around(&self.file.moves.t);
        let (lc, nc) = around(&self.down_t);
        let max = |a: Option<f64>, b: Option<f64>| match (a, b) {
            (Some(a), Some(b)) => Some(a.max(b)),
            (a, b) => a.or(b),
        };
        let min = |a: Option<f64>, b: Option<f64>| match (a, b) {
            (Some(a), Some(b)) => Some(a.min(b)),
            (a, b) => a.or(b),
        };
        (max(lm, lc), min(nm, nc))
    }

    /// The image id in force at `t_us`: the last change at or before it;
    /// `None` before the first and under `cursor_image: none`.
    pub(crate) fn image_at(&self, t_us: f64) -> Option<usize> {
        if self.file.cursor_image == CursorImageMode::None {
            return None;
        }
        let ic = &self.file.image_changes;
        let after = ic.t.partition_point(|&t| (t as f64) <= t_us);
        let id = ic.id[after.checked_sub(1)?];
        usize::try_from(id).ok()
    }

    /// The down clicks whose ripple runs at `t_us` (CU-23), newest first,
    /// at most `MAX_RIPPLES`, each at its own position mapped at its own
    /// time.
    pub(crate) fn ripples(&self, t_us: f64) -> Vec<Ripple> {
        let c = &self.file.clicks;
        let after = self.down_t.partition_point(|&t| (t as f64) <= t_us);
        let mut out = Vec::new();
        for k in (0..after).rev() {
            let t = self.down_t[k] as f64;
            let phase = (t_us - t) / RIPPLE_US as f64;
            if phase >= 1.0 || out.len() == MAX_RIPPLES {
                break;
            }
            let i = self.downs[k];
            let (x, y) = self.to_movie(t, c.x[i] as f64, c.y[i] as f64);
            out.push(Ripple { x, y, phase });
        }
        out
    }
}
