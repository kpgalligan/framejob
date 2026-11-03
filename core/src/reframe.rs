//! The framing planner (road map "creator-jobs" VR2a1, spec §11 VR-20,
//! VR-22, VR-23): a clip's analysed subjects in, a [`FramingPath`] out — a
//! similarity per instant from the canvas the clip was authored for (`Ws ×
//! Hs`) to the current one (`W × H`). Pure; nothing here edits.
//! `edit_reframe.rs`'s op writes the path as the clip's base and actions
//! (`reframe_cover.rs`).
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
//! **The placement in force** (VR-27 (a)). A clip with actions moves its
//! picture under the window: a sample's point is (★) through the clip's
//! evaluated placement at its own tick (`Frame.placed`), and the rect the
//! window is clamped into is the COMMON one — the cropped rects of the base
//! and of the placement at every action's end, intersected — with `k`
//! raised until the window fits it, held so `k·s` stays at most `SCALE_MAX`
//! at every one of those placements. A clip with no actions is VR2a2's.
//!
//! **The path.** VR-21 (`reframe_tracks.rs`) chooses a subject per sample;
//! VR-22 composes the window on it; `reframe_path.rs` writes the keys —
//! VR-23's moves only when the median-filtered subject leaves a dead zone,
//! each a hold key and an eased key, and VR-24's hard cuts, loss, return and
//! two people — snapped to the canvas's frames. Where there is nothing to
//! follow the path holds a `where_empty` state ([`WhereEmpty`]): the window on
//! the cropped centre, or the whole cropped picture fitted (`edit_zoom.rs`'s
//! solves at θ = 0), which [`fixed_framing`] also answers for `follow`
//! `center` and `fit` (VR2a2).

use crate::clip_source_time::{clip_time_of_source, in_played_window, Round};
use crate::edit_zoom::{zoom_offset, zoom_scale, ZoomFit, ZoomRegion};
use crate::model::{Clip, Curve, MediaKind, Project, Source};
use crate::props_check::SCALE_MAX;
use crate::reframe_path::write_keys;
pub use crate::reframe_tracks::{
    choose_subject, Chosen, Follow, SubjectBox, SubjectKind, SubjectSample,
};
use crate::time::Ticks;
use serde::{Deserialize, Serialize};

/// A clip's analysed subjects in MEDIA source ticks of the forward file.
/// `reframe_clip`'s `subjects` argument; its strict `Deserialize` is
/// `edit_reframe.rs`'s.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Subjects {
    pub samples: Vec<SubjectSample>,
    pub shots: Vec<Ticks>,
}

/// What a framing shows where there is nothing to follow (spec §11 VR-24
/// (h)): the whole cropped picture fitted, or the follow window on its
/// centre.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WhereEmpty {
    #[default]
    Fit,
    Center,
}

/// What to follow, how tight (1…4 × fill), the canvas the clip was
/// authored for, and what to show with nothing to follow.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FramingRequest {
    pub follow: Follow,
    pub zoom: f64,
    pub from_width: u32,
    pub from_height: u32,
    pub where_empty: WhereEmpty,
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
    /// Some key holds the `fit` state (VR-24 (h)): the picture shows the
    /// canvas around it, so VR-25's backdrop has a span to fill.
    pub shows_fit: bool,
    /// Each hard cut's key time `c` whose key differs from the hold at
    /// `c − frame` (VR-24 (b)), ascending: `reframe_compose.rs` splits the
    /// action a cut lands in (VR-27 (d)).
    pub cuts: Vec<Ticks>,
}

pub(crate) type Point = (f64, f64);

/// The geometry one plan reads: the clip's placement on the source canvas,
/// the common cropped rect (VR-27 (a)), and the window.
pub(crate) struct Frame {
    pub(crate) anchor: Point,
    pub(crate) s: f64,
    pub(crate) media: Point,
    pub(crate) rect: (Point, Point),
    /// The placement in force at each in-clip sample tick, `(tick, scale, x,
    /// y)`, sorted; empty for a clip with no actions, whose points read the
    /// base (VR-27 (a)).
    pub(crate) placed: Vec<(Ticks, f64, f64, f64)>,
    pub(crate) k: f64,
    pub(crate) window: Point,
    pub(crate) half_source: Point,
    /// The `fit` state as a key of F: `(k, dx, dy)` (VR-24 (h)).
    pub(crate) fit: (f64, f64, f64),
}

impl Frame {
    /// The geometry of `clip`, sized through [`Project::source_size`]; `None`
    /// for no size, a base rotation other than 0, a zoom outside 1…4, a zero
    /// source canvas, or a crop or scale that leaves no picture.
    pub(crate) fn of(project: &Project, clip: &Clip, request: &FramingRequest) -> Option<Frame> {
        let video = clip.video.clone().unwrap_or_default();
        if video.rotation != 0.0 {
            return None;
        }
        let (mw, mh) = project.source_size(clip)?;
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
        let rect_of = |s: f64, anchor: Point| {
            (
                (
                    anchor.0 + s * (c.0 - cw / 2.0),
                    anchor.1 + s * (c.1 - ch / 2.0),
                ),
                (
                    anchor.0 + s * (c.0 + cw / 2.0),
                    anchor.1 + s * (c.1 + ch / 2.0),
                ),
            )
        };
        let base_rect = rect_of(s, anchor);
        let (w, h) = (
            f64::from(project.canvas.width),
            f64::from(project.canvas.height),
        );
        // VR-27 (a): the common rect over the base and every action's end,
        // and the largest scale among them.
        let (mut rect, mut s_max) = (base_rect, s);
        for a in &clip.actions {
            let p = project
                .evaluate_clip(clip, a.start.saturating_add(a.duration))
                .video;
            if !(p.scale.is_finite() && p.scale > 0.0 && p.x.is_finite() && p.y.is_finite()) {
                continue;
            }
            let ((x0, y0), (x1, y1)) = rect_of(p.scale, (ws / 2.0 + p.x, hs / 2.0 + p.y));
            rect = (
                (rect.0 .0.max(x0), rect.0 .1.max(y0)),
                (rect.1 .0.min(x1), rect.1 .1.min(y1)),
            );
            s_max = s_max.max(p.scale);
        }
        let ((x0, y0), (x1, y1)) = rect;
        if !(x0 < x1 && y0 < y1) {
            rect = base_rect;
        }
        let mut k = (zoom * project.fill_scale(cw, ch)).min(SCALE_MAX) / s;
        // Only a smaller rect raises `k`, so an action-free clip's `k` is
        // VR2a2's to the bit.
        let raised = rect != base_rect;
        if raised {
            let ((x0, y0), (x1, y1)) = rect;
            k = k.max(w / (x1 - x0)).max(h / (y1 - y0));
        }
        if raised || s_max > s {
            k = k.min(SCALE_MAX / s_max);
        }
        // Fit: the cropped picture fitted at θ = 0 by `edit_zoom.rs`'s two
        // solves, written as F so it composes like any key.
        let whole = ZoomRegion {
            x: 0.0,
            y: 0.0,
            width: cw,
            height: ch,
        };
        let fit_scale = zoom_scale((w, h), &whole, ZoomFit::Fit, 0.0);
        let (fx, fy) = zoom_offset(&video, &whole, fit_scale);
        let kf = fit_scale / s;
        Some(Frame {
            anchor,
            s,
            media: (mw, mh),
            rect,
            k,
            window: (w / k, h / k),
            half_source: (ws / 2.0, hs / 2.0),
            fit: (kf, fx - kf * video.x, fy - kf * video.y),
            placed: Vec::new(),
        })
    }

    /// A box point (0…1 of the picture) on the source canvas, through the
    /// placement in force at clip tick `t` (VR-27 (a)); the base's when
    /// none was read there.
    pub(crate) fn point(&self, t: Ticks, bx: f64, by: f64) -> Point {
        let (mw, mh) = self.media;
        let (s, anchor) = match self.placed.binary_search_by_key(&t, |p| p.0) {
            Ok(i) => {
                let (_, s, x, y) = self.placed[i];
                (s, (self.half_source.0 + x, self.half_source.1 + y))
            }
            Err(_) => (self.s, self.anchor),
        };
        (
            anchor.0 + s * (bx * mw - mw / 2.0),
            anchor.1 + s * (by * mh - mh / 2.0),
        )
    }

    /// `wc` moved so the window lies inside the cropped rect (its centre
    /// when the window is the larger).
    pub(crate) fn clamp(&self, wc: Point) -> Point {
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

    /// The cropped rect's centre.
    pub(crate) fn centre(&self) -> Point {
        let ((x0, y0), (x1, y1)) = self.rect;
        ((x0 + x1) / 2.0, (y0 + y1) / 2.0)
    }

    /// The `fit` state's key at `t`.
    pub(crate) fn fit_key(&self, t: Ticks, curve: Curve) -> FramingKey {
        let (scale, x, y) = self.fit;
        FramingKey {
            t,
            scale,
            x,
            y,
            curve,
        }
    }

    pub(crate) fn key(&self, t: Ticks, wc: Point, curve: Curve) -> FramingKey {
        FramingKey {
            t,
            scale: self.k,
            x: self.k * (self.half_source.0 - wc.0),
            y: self.k * (self.half_source.1 - wc.1),
            curve,
        }
    }

    /// VR-22: the subject point of a kind's box at clip tick `t`, and the
    /// window centre's offset from it.
    pub(crate) fn subject(
        &self,
        t: Ticks,
        kind: SubjectKind,
        b: &SubjectBox,
        headroom: f64,
    ) -> (Point, Point) {
        let (w, h) = self.window;
        match kind {
            SubjectKind::Face => {
                let lift = if h > w { h / 2.0 - headroom * h } else { 0.0 };
                (self.point(t, b.x + b.w / 2.0, b.y + b.h / 2.0), (0.0, lift))
            }
            SubjectKind::Person => (
                self.point(t, b.x + b.w / 2.0, b.y),
                (0.0, h / 2.0 - PERSON_TOP * h),
            ),
            SubjectKind::Salient => (self.point(t, b.x + b.w / 2.0, b.y + b.h / 2.0), (0.0, 0.0)),
        }
    }
}

/// The samples and shots in clip time (VR-20): kept when in the played
/// window, ascending, one sample per clip tick (the earliest media tick's),
/// one shot per tick, a cut at 0 or at or past the end dropped.
pub(crate) fn in_clip_time(
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
    // A shot rounds UP (VR-24 (a)): its clip tick is the first that shows
    // the new shot, where a sample's rounds down.
    let at_up = |t: Ticks| {
        in_played_window(clip, media, t)
            .then(|| clip_time_of_source(clip, media, t, Round::Up))
            .flatten()
    };
    let mut shots: Vec<Ticks> = subjects
        .shots
        .iter()
        .filter_map(|&t| at_up(t))
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

/// The planner (spec §11 VR-20…VR-24). `None` for: no such clip, not a
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
    let Source::Media { media, .. } = clip.source else {
        return None;
    };
    let media = project.media(media)?;
    if media.kind != MediaKind::Video || !media.has_video {
        return None;
    }
    let mut frame = Frame::of(project, clip, request)?;
    let (samples, shots) = in_clip_time(clip, project, subjects);
    if !clip.actions.is_empty() {
        frame.placed = samples
            .iter()
            .map(|s| {
                let p = project.evaluate_clip(clip, s.t).video;
                (s.t, p.scale, p.x, p.y)
            })
            .collect();
    }
    let chosen = choose_subject(&samples, &shots, request.follow);
    Some(write_keys(
        &frame,
        &chosen,
        &shots,
        clip.duration,
        project.canvas.fps,
        request,
        tuning,
    ))
}

/// One key at 0 holding a `where_empty` state for the whole clip (spec §11
/// VR-24 (h), VR-26): `follow` `center` (the window at fill × `zoom` on the
/// cropped centre) and `fit` (the cropped picture fitted; `zoom` unread).
/// `None` for no such clip, no size, a base rotation other than 0, a zoom
/// outside 1…4, or a crop or scale that leaves no picture. Offsets are
/// measured from the canvas's own centre, so the source canvas is the
/// current one.
pub fn fixed_framing(
    project: &Project,
    clip: u32,
    state: WhereEmpty,
    zoom: f64,
) -> Option<FramingPath> {
    let clip = project.clip(clip)?;
    let request = FramingRequest {
        follow: Follow::Subject,
        zoom,
        from_width: project.canvas.width,
        from_height: project.canvas.height,
        where_empty: state,
    };
    let frame = Frame::of(project, clip, &request)?;
    let key = match state {
        WhereEmpty::Center => frame.key(0, frame.centre(), Curve::Linear),
        WhereEmpty::Fit => frame.fit_key(0, Curve::Linear),
    };
    Some(FramingPath {
        keys: vec![key],
        shows_fit: state == WhereEmpty::Fit,
        cuts: Vec::new(),
    })
}
