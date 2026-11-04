//! `follow: cursor` — a screen recording framed on its recorded pointer
//! (road map "creator-jobs" VR5, spec §11 VR-50). Pure; `edit_reframe.rs`'s
//! op writes the path as it writes every framing (`reframe_compose.rs`).
//!
//! **The points.** `subjects.cursor` (`reframe_subjects.rs`), in forward-media
//! source ticks, is put into clip time by [`cursor_in_clip_time`]: kept in the
//! played window, mapped through `clip_source_time.rs`'s one mapping, one
//! point per clip tick with `click` and `typing` OR'ed over the points merged.
//!
//! **The window** is `reframe.rs`'s `Frame` at the request's zoom from the
//! current canvas: a point lands on the source canvas through the placement in
//! force (`Frame::point`, VR-27 (a)) and the desired centre is that point
//! clamped (`Frame::clamp`) — no headroom, no offset, since a pointer is a
//! point and not a head.
//!
//! **The moves** ([`CURSOR_TUNING`]): the first key on the first point; a
//! dead zone ±0.20 of the window's width and ±0.12 of its height around the
//! window's target, wider than a face's 0.15 because a pointer wanders where a
//! face holds still; a down click outside it ARRIVES — its move ends on the
//! click's frame, planned back from it at 0.8 window widths a second (at
//! least 0.4 s) and started no earlier than the last move's end; any other
//! point outside it starts VR-23's move unless one runs, it is within 0.5 s of
//! the last move's end with the pointer still in the window, the move would
//! end after a pending arrival's start, or the pointer is typing — a typing
//! stretch holds the window, where a click inside one still arrives. No cut,
//! no `fit`: `where_empty` and `backdrop` never act on it.

use crate::clip_source_time::{clip_time_of_source, in_played_window, Round};
use crate::model::{Clip, Curve, MediaKind, Project, Source};
use crate::reframe::{
    Frame, FramingKey, FramingPath, FramingRequest, FramingTuning, Point, WhereEmpty,
};
use crate::reframe_path::{span, MOVE_MIN, MOVE_SPACING};
use crate::reframe_subjects::CursorPoint;
use crate::reframe_tracks::Follow;
use crate::time::{snap_to_frame, Fps, Ticks, TIMESCALE};

/// VR-50 (d): the dead zone ±0.20 of the window's width (a face's is 0.15)
/// and ±0.12 of its height, 0.8 window widths a second, no headroom.
pub const CURSOR_TUNING: FramingTuning = FramingTuning {
    dead_zone_width: 0.20,
    dead_zone_height: 0.12,
    speed: 0.8,
    headroom: 0.0,
};

/// VR-50 (a): the points in clip time — kept in the played window, mapped
/// with `Round::Down`, sorted by (clip tick, media tick), one per clip tick
/// (the earliest media tick's position) with `click` and `typing` OR'ed over
/// the points it stands for. Empty for a clip that is not a media clip.
pub(crate) fn cursor_in_clip_time(
    clip: &Clip,
    project: &Project,
    points: &[CursorPoint],
) -> Vec<CursorPoint> {
    let Source::Media { media, .. } = clip.source else {
        return Vec::new();
    };
    let Some(media) = project.media(media) else {
        return Vec::new();
    };
    let mut mapped: Vec<(Ticks, Ticks, CursorPoint)> = points
        .iter()
        .filter(|p| in_played_window(clip, media, p.t))
        .filter_map(|p| clip_time_of_source(clip, media, p.t, Round::Down).map(|c| (c, p.t, *p)))
        .collect();
    mapped.sort_by_key(|&(c, m, _)| (c, m));
    let mut out: Vec<CursorPoint> = Vec::with_capacity(mapped.len());
    for (c, _, p) in mapped {
        match out.last_mut() {
            Some(last) if last.t == c => {
                last.click |= p.click;
                last.typing |= p.typing;
            }
            _ => out.push(CursorPoint { t: c, ..p }),
        }
    }
    out
}

/// The cursor's framing path (spec §11 VR-50). `None` for: no such clip, not
/// a media clip of a video media, a base rotation other than 0, a media with
/// no size, a crop or scale that leaves no picture, or a zoom outside 1…4 —
/// each refused by name before `reframe_clip` calls it. With no point in the
/// played window the path is one key on the picture's centre, which the op
/// refuses as "no subjects".
pub fn plan_cursor_framing(
    project: &Project,
    clip: u32,
    points: &[CursorPoint],
    zoom: f64,
) -> Option<FramingPath> {
    let clip = project.clip(clip)?;
    let Source::Media { media, .. } = clip.source else {
        return None;
    };
    let media = project.media(media)?;
    if media.kind != MediaKind::Video || !media.has_video {
        return None;
    }
    let request = FramingRequest {
        follow: Follow::Subject,
        zoom,
        from_width: project.canvas.width,
        from_height: project.canvas.height,
        where_empty: WhereEmpty::Fit,
    };
    let mut frame = Frame::of(project, clip, &request)?;
    let points = cursor_in_clip_time(clip, project, points);
    if !clip.actions.is_empty() {
        frame.placed = points
            .iter()
            .map(|p| {
                let v = project.evaluate_clip(clip, p.t).video;
                (p.t, v.scale, v.x, v.y)
            })
            .collect();
    }
    Some(write_cursor_keys(
        &frame,
        &points,
        clip.duration,
        project.canvas.fps,
        &CURSOR_TUNING,
    ))
}

/// The keys (VR-50 (c)–(g)).
fn write_cursor_keys(
    frame: &Frame,
    points: &[CursorPoint],
    duration: Ticks,
    fps: Fps,
    tuning: &FramingTuning,
) -> FramingPath {
    let (ww, wh) = frame.window;
    let raw: Vec<Point> = points.iter().map(|p| frame.point(p.t, p.x, p.y)).collect();
    let desired: Vec<Point> = raw.iter().map(|&p| frame.clamp(p)).collect();
    let mut target = desired.first().copied().unwrap_or_else(|| frame.centre());
    let mut keys = vec![frame.key(0, target, Curve::Linear)];
    let mut last_end: Option<Ticks> = None;
    // A click whose arrival was dropped, or that is already reached, is
    // followed as any other point.
    let mut handled = 0usize;
    let outside = |target: Point, to: Point| {
        (to.0 - target.0).abs() > tuning.dead_zone_width * ww
            || (to.1 - target.1).abs() > tuning.dead_zone_height * wh
    };
    let seconds = |target: Point, to: Point| {
        MOVE_MIN.max((to.0 - target.0).hypot(to.1 - target.1) / (tuning.speed * ww))
    };
    let go = |keys: &mut Vec<FramingKey>, start: Ticks, end: Ticks, from: Point, to: Point| {
        if start > keys.last().expect("the first key").t {
            keys.push(frame.key(start, from, Curve::Linear));
        }
        keys.push(frame.key(end, to, Curve::EaseInOut));
    };
    for (i, p) in points.iter().enumerate() {
        let t = p.t;
        let running = last_end.is_some_and(|end| t < end);
        // The next click from here whose arrival is still to be made, and
        // its planned start (VR-50 (e)).
        let next_click = (i.max(handled)..points.len()).find(|&j| points[j].click);
        let mut pending: Option<Ticks> = None;
        if let Some(j) = next_click.filter(|&j| outside(target, desired[j])) {
            let end = snap_to_frame(points[j].t, fps);
            let length = (seconds(target, desired[j]) * TIMESCALE as f64).round() as Ticks;
            let planned = end.saturating_sub(length).max(last_end.unwrap_or(0));
            if end <= duration && !running && t >= planned {
                let start = snap_to_frame(t, fps);
                if start < end {
                    go(&mut keys, start, end, target, desired[j]);
                    target = desired[j];
                    last_end = Some(end);
                    handled = j + 1;
                    continue;
                }
                // Cannot last a frame: dropped; the click is any point.
                handled = j + 1;
            } else if end <= duration {
                pending = Some(planned);
            } else {
                handled = j + 1;
            }
        }
        if i >= handled && p.click {
            handled = i + 1;
        }
        // VR-50 (f): any other point.
        if running || p.typing || !outside(target, desired[i]) {
            continue;
        }
        let in_window =
            (raw[i].0 - target.0).abs() <= ww / 2.0 && (raw[i].1 - target.1).abs() <= wh / 2.0;
        if last_end.is_some_and(|end| t < end + MOVE_SPACING) && in_window {
            continue;
        }
        let Some((start, end)) = span(t, seconds(target, desired[i]), duration, fps) else {
            continue;
        };
        if pending.is_some_and(|planned| end > planned) {
            continue;
        }
        go(&mut keys, start, end, target, desired[i]);
        target = desired[i];
        last_end = Some(end);
    }
    FramingPath {
        keys,
        shows_fit: false,
        cuts: Vec::new(),
    }
}
