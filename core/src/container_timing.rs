//! The times a copied frame is written with, and the space a copy needs
//! (spec §11 #216-R). Every number here is a DECISION the movie keeps.
//!
//! - **Laced frames.** Frame j of a lace is its Block's time plus the
//!   durations of frames 0…j−1: DefaultDuration for video (a laced copied
//!   video track without one is refused at open, `container.rs`), and
//!   samples for audio — the Opus TOC's count or AAC's 1024.
//! - **Raw video times** are the file's own: in units of TimestampScale when
//!   1e9 divides by it exactly (milliseconds for nearly every file), else
//!   microseconds. A duplicate raw time moves one unit later, since two
//!   frames cannot present at one instant.
//! - **The grid.** `snapped_video` puts every frame on `fps`'s grid — frame
//!   k at k·den in a timescale of num — when every frame lies within a
//!   quarter frame of a grid point and no two frames share one. A file
//!   written at a steady rate in milliseconds then answers an exact-time
//!   request with its own frame (measured: 47/30 lands on frame 47, where
//!   ffmpeg's copy lands a frame early). A variable-rate file — most browser
//!   recordings — keeps its raw times, because snapping would merge or move
//!   real frames.
//! - **Decode times** are the presentation times sorted, shifted back by the
//!   largest reorder (`shift = max(sorted[i] − pts[i])`), so B-frames decode
//!   before they present and decode times strictly increase; a negative
//!   decode time is accepted by the writer (measured).
//! - **Durations**: one frame on the grid; otherwise the gap to the next
//!   time in presentation order, the last frame keeping DefaultDuration or
//!   the gap before it.
//! - **Audio** is timed in samples: `round((block − CodecDelay) × rate /
//!   1e9)` plus the lace's samples before the frame; every packet is a sync
//!   sample, and the writer trims what lands before zero (measured).

use crate::container_blocks::Frame;
use crate::time::Fps;

const NS: i128 = 1_000_000_000;

/// One track's times, each vector in decode (file) order.
#[derive(Clone, Debug)]
pub(crate) struct Timing {
    pub pts: Vec<i64>,
    pub dts: Vec<i64>,
    pub duration: Vec<i64>,
    pub timescale: i64,
    pub grid: bool,
}

impl Timing {
    /// A track that is not copied: no samples.
    pub(crate) fn empty(timescale: i64) -> Timing {
        Timing {
            pts: Vec::new(),
            dts: Vec::new(),
            duration: Vec::new(),
            timescale,
            grid: false,
        }
    }
}

/// `n / d` rounded half up, `d > 0`.
fn div_round(n: i128, d: i128) -> i128 {
    let (q, r) = (n.div_euclid(d), n.rem_euclid(d));
    if 2 * r >= d {
        q + 1
    } else {
        q
    }
}

fn narrow(v: i128) -> i64 {
    i64::try_from(v).unwrap_or(if v < 0 { i64::MIN } else { i64::MAX })
}

/// Each video frame's time in nanoseconds, a laced frame's included.
pub(crate) fn video_ns(frames: &[Frame], default_duration: Option<u64>) -> Vec<i64> {
    let step = i128::from(default_duration.unwrap_or(0));
    let at = |f: &Frame| narrow(i128::from(f.ns) + i128::from(f.lace) * step);
    frames.iter().map(at).collect()
}

/// The raw timescale: 1e9 / TimestampScale when that is exact, else µs.
pub(crate) fn raw_timescale(scale: u64) -> i64 {
    if scale > 0 && 1_000_000_000 % scale == 0 {
        (1_000_000_000 / scale) as i64
    } else {
        1_000_000
    }
}

/// The rate the frames run at: from DefaultDuration, else the median gap
/// between the sorted times.
pub(crate) fn nominal_fps(ns: &[i64], default_duration: Option<u64>) -> Option<f64> {
    if let Some(d) = default_duration {
        return Some(1e9 / d as f64);
    }
    let mut sorted = ns.to_vec();
    sorted.sort_unstable();
    let mut gaps: Vec<i128> = sorted
        .windows(2)
        .map(|w| i128::from(w[1]) - i128::from(w[0]))
        .filter(|g| *g > 0)
        .collect();
    gaps.sort_unstable();
    let median = *gaps.get(gaps.len() / 2)?;
    Some(1e9 / median as f64)
}

/// Decode times from presentation times, by the largest reorder.
fn decode_times(pts: &[i64]) -> Vec<i64> {
    let mut sorted = pts.to_vec();
    sorted.sort_unstable();
    let shift = sorted
        .iter()
        .zip(pts)
        .map(|(s, p)| i128::from(*s) - i128::from(*p))
        .max()
        .unwrap_or(0);
    sorted
        .iter()
        .map(|s| narrow(i128::from(*s) - shift))
        .collect()
}

/// The raw times, bumped apart where two collide.
pub(crate) fn raw_video(ns: &[i64], scale: u64, default_duration: Option<u64>) -> Timing {
    let timescale = raw_timescale(scale);
    let ts = i128::from(timescale);
    let mut pts: Vec<i64> = ns
        .iter()
        .map(|t| narrow(div_round(i128::from(*t) * ts, NS)))
        .collect();
    // Presentation order, the earlier frame in the file first among equal
    // times; a sweep then moves each collision one unit past its neighbour.
    let mut order: Vec<usize> = (0..pts.len()).collect();
    order.sort_unstable_by_key(|i| (pts[*i], *i));
    let mut prev: Option<i64> = None;
    for &i in &order {
        if let Some(p) = prev.filter(|p| pts[i] <= *p) {
            pts[i] = p.saturating_add(1);
        }
        prev = Some(pts[i]);
    }
    // Durations by the gap to the next frame in presentation order.
    let tail = default_duration.map(|d| narrow(div_round(i128::from(d) * ts, NS)));
    let mut duration = vec![1i64; pts.len()];
    let mut last_gap = None;
    for (k, &i) in order.iter().enumerate() {
        let gap = match order.get(k + 1) {
            Some(&next) => Some(pts[next].saturating_sub(pts[i])),
            None => tail.filter(|d| *d > 0).or(last_gap),
        };
        duration[i] = gap.unwrap_or(1).max(1);
        last_gap = gap.or(last_gap);
    }
    Timing {
        dts: decode_times(&pts),
        pts,
        duration,
        timescale,
        grid: false,
    }
}

/// Every frame on `fps`'s grid, or `None` when one is more than a quarter
/// frame off it or two frames land on one grid point.
pub(crate) fn snapped_video(ns: &[i64], fps: Fps) -> Option<Timing> {
    if !fps.is_valid() || ns.is_empty() {
        return None;
    }
    let (num, den) = (i128::from(fps.num), i128::from(fps.den));
    let period = den * NS; // one frame, in ns × num
    let mut ks = Vec::with_capacity(ns.len());
    for t in ns {
        let scaled = i128::from(*t) * num;
        let k = div_round(scaled, period);
        if 4 * (scaled - k * period).abs() > period {
            return None;
        }
        ks.push(k);
    }
    let mut sorted = ks.clone();
    sorted.sort_unstable();
    if sorted.windows(2).any(|w| w[0] == w[1]) {
        return None;
    }
    let pts: Vec<i64> = ks.iter().map(|k| narrow(k * den)).collect();
    Some(Timing {
        dts: decode_times(&pts),
        duration: vec![i64::from(fps.den); pts.len()],
        pts,
        timescale: i64::from(fps.num),
        grid: true,
    })
}

/// Audio times in samples at `rate`, CodecDelay taken off and each laced
/// frame placed after the samples before it in its Block.
pub(crate) fn audio(frames: &[Frame], counts: &[u32], codec_delay: u64, rate: i64) -> Timing {
    let rate = i128::from(rate.max(1));
    let delay = i128::from(codec_delay);
    let mut pts = Vec::with_capacity(frames.len());
    let mut into_lace: i128 = 0;
    for (f, count) in frames.iter().zip(counts) {
        if f.first {
            into_lace = 0;
        }
        let block = div_round((i128::from(f.ns) - delay) * rate, NS);
        pts.push(narrow(block + into_lace));
        into_lace += i128::from(*count);
    }
    Timing {
        dts: pts.clone(),
        duration: counts.iter().map(|c| i64::from(*c)).collect(),
        pts,
        timescale: rate as i64,
        grid: false,
    }
}

/// The free space a copy needs: the copied payload, 64 bytes of movie
/// structure a sample, and 16 MiB besides. Each pair is (samples, bytes).
pub(crate) fn required_bytes(video: (u64, u64), audio: (u64, u64)) -> u64 {
    let samples = video.0.saturating_add(audio.0);
    video
        .1
        .saturating_add(audio.1)
        .saturating_add(samples.saturating_mul(64))
        .saturating_add(16 << 20)
}
