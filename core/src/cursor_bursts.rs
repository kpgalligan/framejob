//! Bursts of input in a cursor file (spec §11 CU-25, CU-70): the typing
//! stretches an `events` request answers and Auto Zoom anchors on, and the
//! scroll bursts that end an Auto Zoom visit, by CU7's figures. CU9b reads
//! the same stretches. Both are one run finder with their own figures.

/// Marks closer than this belong to one stretch (strictly under 1.0 s).
pub const TYPING_GAP_US: i64 = 1_000_000;
/// The fewest marks a stretch holds.
pub const TYPING_MIN_MARKS: usize = 3;
/// Wheel events closer than this belong to one burst (strictly under 1.0 s).
pub const SCROLL_GAP_US: i64 = 1_000_000;
/// The fewest wheel events a burst holds.
pub const SCROLL_MIN_EVENTS: usize = 3;

/// Each run of `t` (µs, in order) whose neighbours are less than `gap`
/// apart and which holds at least `min` entries, as (first, last, count).
fn runs(t: &[i64], gap: i64, min: usize) -> Vec<(i64, i64, usize)> {
    let mut out = Vec::new();
    let mut start = 0;
    for i in 1..=t.len() {
        if i == t.len() || t[i] - t[i - 1] >= gap {
            if i - start >= min {
                out.push((t[start], t[i - 1], i - start));
            }
            start = i;
        }
    }
    out
}

/// The typing stretches of `t` (the `typed` marks' µs, in order): each run
/// of marks less than `TYPING_GAP_US` apart holding at least
/// `TYPING_MIN_MARKS`, as (first mark, last mark, marks).
pub(crate) fn typing_stretches(t: &[i64]) -> Vec<(i64, i64, usize)> {
    runs(t, TYPING_GAP_US, TYPING_MIN_MARKS)
}

/// The scroll bursts of `t` (the `scrolls`' µs, in order): each run of
/// wheel events less than `SCROLL_GAP_US` apart holding at least
/// `SCROLL_MIN_EVENTS`, as (first, last, events).
pub(crate) fn scroll_bursts(t: &[i64]) -> Vec<(i64, i64, usize)> {
    runs(t, SCROLL_GAP_US, SCROLL_MIN_EVENTS)
}
