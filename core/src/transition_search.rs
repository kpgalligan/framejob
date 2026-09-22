//! Bounded searches for the two ways a hard cut gains an overlap.
//!
//! The handle path is monotone after an affected track passes the original
//! overlap rule: the outer neighbours are bounded away before searching,
//! and growing either clip cannot invalidate an already valid outer pair.
//! At the cut itself, with extensions `tail` and `head`, the two limits are
//! `tail + 2*head <= A.duration` and `2*tail + head <= B.duration`.
//! Reducing either side improves both; inward grid snapping only reduces
//! an extension. A pair that swaps order or contains its partner cannot
//! pass before these constraints do. Thus the old decrement path has one
//! pass/fail boundary and can be searched without enumerating frames.
//!
//! Ripple has no such global monotonicity: a moved clip can pass across a
//! fixed clip and become valid again. Its forbidden integer intervals are
//! calculated exactly instead. Pairwise half-shorter checks also enforce
//! the non-adjacent rule for positive durations: if A reaches C across B,
//! either B ends before C (then A covers all B), or A/B staying within
//! half B puts A's end before B's midpoint while B/C staying within half B
//! puts C's start after that midpoint, contradicting A reaching C.

use crate::model::Project;
use crate::time::Ticks;
use crate::transition::overlap_limit;

/// The old larger-side decrement path, including its head-first tie rule.
pub(crate) fn reduced_split(tail: Ticks, head: Ticks, total: Ticks) -> (Ticks, Ticks) {
    let smaller = tail.min(head);
    if total > 2 * smaller {
        if tail > head {
            (total - head, head)
        } else {
            (tail, total - tail)
        }
    } else {
        ((total + 1) / 2, total / 2)
    }
}

/// Greatest passing integer in `0..=limit`; zero must pass and the
/// predicate must be downward closed. At most 64 probes for i64 limits.
pub(crate) fn largest_passing(limit: Ticks, mut fits: impl FnMut(Ticks) -> bool) -> Ticks {
    let mut good = 0_i128;
    let mut bad = i128::from(limit) + 1;
    while good + 1 < bad {
        let mid = good + (bad - good) / 2;
        if fits(mid as Ticks) {
            good = mid;
        } else {
            bad = mid;
        }
    }
    good as Ticks
}

/// Greatest positive shift count not forbidden by a fixed/moved pair on
/// any touched track. The caller checked the original affected tracks and
/// supplies the same shift set as `shift_clips`.
pub(crate) fn shift_frame_limit(
    project: &Project,
    cut: Ticks,
    frame: Ticks,
    limit: Ticks,
    touched: &[u32],
) -> Option<Ticks> {
    let mut forbidden: Vec<(i128, i128)> = Vec::new();
    let frame = i128::from(frame);
    let maximum = i128::from(limit);
    for track in touched {
        let fixed: Vec<_> = project
            .clips
            .iter()
            .filter(|c| c.track == *track && c.start < cut)
            .collect();
        let moved: Vec<_> = project
            .clips
            .iter()
            .filter(|c| c.track == *track && c.start >= cut)
            .collect();
        for a in &fixed {
            for b in &moved {
                let s = i128::from(a.start);
                let e = s + i128::from(a.duration);
                let m = i128::from(b.start);
                let n = m + i128::from(b.duration);
                let half = i128::from(overlap_limit(a, b));
                // Too much overlap iff m-e+L < k*frame < n-s-L.
                // div_euclid is signed floor; strict upper uses one less tick.
                let low = (m - e + half).div_euclid(frame) + 1;
                let high = (n - s - half - 1).div_euclid(frame);
                let low = low.max(1);
                let high = high.min(maximum);
                if low <= high {
                    forbidden.push((low, high));
                }
            }
        }
    }
    forbidden.sort_unstable_by_key(|interval| interval.0);
    let mut best = maximum;
    // Scanning from the highest interval down finds the greatest uncovered
    // count even if the forbidden set has holes after pair crossings.
    for &(low, high) in forbidden.iter().rev() {
        if low <= best && best <= high {
            best = low - 1;
        }
    }
    (best > 0).then_some(best as Ticks)
}
