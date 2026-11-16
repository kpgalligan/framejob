//! Frames timecode at a fractional rate (spec §11 #532), black box over the
//! FFI.
//!
//! At an NTSC rate — the denominator over the gcd of the terms is 1001 — a
//! timecode second is `ceil(num/den)` frames (non-drop, §7.3b). At any other
//! fractional rate SS is the whole second a frame STARTS in and FF counts
//! from that second's first frame, so a 12.5 fps second holds 13 frames and
//! then 12. The expected strings below are worked by hand in the comments,
//! and the walking oracle counts seconds frame by frame rather than by the
//! implementation's floor and ceiling.

mod common;

use common::{cstring, expect_string};
use framejob_core::ffi::{rc_timecode_format, rc_timecode_parse};

fn timecode(ticks: i64, fps: (u32, u32), frames: bool) -> String {
    expect_string(
        unsafe { rc_timecode_format(ticks, fps.0, fps.1, frames) },
        "rc_timecode_format",
    )
}

fn parse(text: &str, fps: (u32, u32)) -> Option<i64> {
    let s = cstring(text);
    let mut out = 0i64;
    let ok = unsafe { rc_timecode_parse(s.as_ptr(), fps.0, fps.1, &mut out) };
    ok.then_some(out)
}

/// The tick frame `i` starts at: `i · 600000 · den / num`, rounded half
/// away from zero (§5.1's snapping).
fn tick_at(i: i64, fps: (u32, u32)) -> i64 {
    let n = i128::from(i) * 600_000 * i128::from(fps.1);
    let d = i128::from(fps.0);
    ((2 * n + d) / (2 * d)) as i64
}

/// The real-seconds reading of every frame 0..=last, walked: the second
/// advances at the first frame whose start is at or past it
/// (`frame · den ≥ second · num`), and FF counts from there.
fn walked(last: i64, fps: (u32, u32)) -> Vec<String> {
    let (num, den) = (i64::from(fps.0), i64::from(fps.1));
    let mut out = Vec::new();
    let (mut second, mut first) = (0i64, 0i64);
    for i in 0..=last {
        if i * den >= (second + 1) * num {
            second += 1;
            first = i;
        }
        let (hh, mm, ss) = (second / 3600, (second / 60) % 60, second % 60);
        out.push(format!("{hh:02}:{mm:02}:{ss:02}:{:02}", i - first));
    }
    out
}

const TWELVE_AND_A_HALF: (u32, u32) = (25, 2);

#[test]
fn a_twelve_and_a_half_fps_timecode_counts_real_seconds() {
    // 40 s = 500 frames; 500 · 2 / 25 = 40 exactly, the second's first frame.
    assert_eq!(timecode(24_000_000, TWELVE_AND_A_HALF, true), "00:00:40:00");
    assert_eq!(timecode(36_000_000, TWELVE_AND_A_HALF, true), "00:01:00:00");
    // 3 s = frame 37.5, rounded to 38; second 3 starts at ceil(37.5) = 38.
    assert_eq!(timecode(1_800_000, TWELVE_AND_A_HALF, true), "00:00:03:00");
    // Frame 37 (2.96 s): second 2 starts at frame 25, so FF = 12.
    assert_eq!(timecode(1_776_000, TWELVE_AND_A_HALF, true), "00:00:02:12");
    // Frame 12 is second 0's last; frame 13 opens second 1 (13 then 12).
    assert_eq!(timecode(576_000, TWELVE_AND_A_HALF, true), "00:00:00:12");
    assert_eq!(timecode(624_000, TWELVE_AND_A_HALF, true), "00:00:01:00");
    assert_eq!(
        timecode(-24_000_000, TWELVE_AND_A_HALF, true),
        "-00:00:40:00"
    );
    assert_eq!(parse("00:00:01:00", TWELVE_AND_A_HALF), Some(624_000));
}

#[test]
fn a_rate_with_three_decimals_counts_real_seconds() {
    // 10 s at 47.3 fps is frame 473, which opens second 10.
    assert_eq!(timecode(6_000_000, (47300, 1000), true), "00:00:10:00");
}

#[test]
fn an_ntsc_rate_stays_non_drop_reduced_or_not() {
    // 60 s at 29.97 is frame 1798.2 → 1798 = 59 · 30 + 28.
    assert_eq!(timecode(36_000_000, (30000, 1001), true), "00:00:59:28");
    assert_eq!(timecode(36_000_000, (60000, 2002), true), "00:00:59:28");
    for i in 0..=3000 {
        let t = tick_at(i, (30000, 1001));
        assert_eq!(
            timecode(t, (60000, 2002), true),
            timecode(t, (30000, 1001), true),
            "frame {i}"
        );
        let t = tick_at(i, (24000, 1001));
        assert_eq!(
            timecode(t, (48000, 2002), true),
            timecode(t, (24000, 1001), true),
            "frame {i}"
        );
    }
}

#[test]
fn a_whole_rate_reads_the_same_however_it_is_written() {
    for i in 0..=2000 {
        let t = tick_at(i, (120, 1));
        assert_eq!(
            timecode(t, (120000, 1000), true),
            timecode(t, (120, 1), true),
            "frame {i}"
        );
    }
}

#[test]
fn every_frame_matches_the_walked_seconds_at_a_fractional_rate() {
    for fps in [(25, 2), (15, 2), (47300, 1000), (24, 1), (120000, 1000)] {
        let expected = walked(3000, fps);
        for (i, text) in expected.iter().enumerate() {
            assert_eq!(
                &timecode(tick_at(i as i64, fps), fps, true),
                text,
                "{fps:?} frame {i}"
            );
        }
    }
}

#[test]
fn parse_inverts_format_frame_by_frame() {
    for fps in [
        (25, 2),
        (15, 2),
        (47300, 1000),
        (30000, 1001),
        (60000, 2002),
        (24000, 1001),
        (24, 1),
    ] {
        for i in 0..=3000 {
            let t = tick_at(i, fps);
            let text = timecode(t, fps, true);
            assert_eq!(parse(&text, fps), Some(t), "{fps:?} frame {i} read {text}");
        }
    }
}

#[test]
fn the_milliseconds_form_is_unchanged() {
    assert_eq!(
        timecode(1_776_000, TWELVE_AND_A_HALF, false),
        "00:00:02.960"
    );
    assert_eq!(
        timecode(24_000_000, TWELVE_AND_A_HALF, false),
        "00:00:40.000"
    );
}
