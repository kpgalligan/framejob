//! Bursts of input in a cursor file (spec §11 CU-25): the typing stretches
//! an `events` request answers, by CU7's figures. CU7 and CU9b read the same
//! stretches, and CU7 adds scroll bursts here.

/// Marks closer than this belong to one stretch (strictly under 1.0 s).
pub const TYPING_GAP_US: i64 = 1_000_000;
/// The fewest marks a stretch holds.
pub const TYPING_MIN_MARKS: usize = 3;

/// The typing stretches of `t` (the `typed` marks' µs, in order): each run
/// of marks less than `TYPING_GAP_US` apart holding at least
/// `TYPING_MIN_MARKS`, as (first mark, last mark, marks).
pub(crate) fn typing_stretches(t: &[i64]) -> Vec<(i64, i64, usize)> {
    let mut out = Vec::new();
    let mut start = 0;
    for i in 1..=t.len() {
        if i == t.len() || t[i] - t[i - 1] >= TYPING_GAP_US {
            if i - start >= TYPING_MIN_MARKS {
                out.push((t[start], t[i - 1], i - start));
            }
            start = i;
        }
    }
    out
}
