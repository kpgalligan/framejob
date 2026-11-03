//! A run of Auto Zoom (spec §11 CU-74), cut out of `cursor_zoom.rs` by
//! the 400-line rule for a new file: which clips are one run, and what a run
//! is planned against — its given clips' anchors and scroll bursts in
//! container time (CU-70, CU-72), its barriers, the raw cursor for follow,
//! and where a planned span lands (no straddled cut, only given clips).

use crate::cursor_bursts::{scroll_bursts, typing_stretches};
use crate::cursor_track::{ticks_to_us, us_to_ticks, CursorTrack};
use crate::cursor_zoom_visits::{Anchor, Barrier, Frame, Planned};
use crate::edit_zoom::region_size;
use crate::model::{Clip, Project, Source, VideoProps};
use crate::source_window::{source_advanced_through, source_read_by};
use crate::speed_map::{is_ramped, time_for_source};
use crate::time::Ticks;

pub(crate) fn base(clip: &Clip) -> VideoProps {
    clip.video.clone().unwrap_or_default()
}

pub(crate) fn end(c: &Clip) -> Ticks {
    c.start.saturating_add(c.duration)
}

pub(crate) fn media_in(clip: &Clip) -> Option<(u32, Ticks)> {
    match &clip.source {
        Source::Media {
            media,
            r#in,
            reversed: false,
        } => Some((*media, *r#in)),
        _ => None,
    }
}

/// Whether `b` continues `a` in one run.
pub(crate) fn continues(a: &Clip, b: &Clip) -> bool {
    let (Some((ma, _)), Some((mb, ib))) = (media_in(a), media_in(b)) else {
        return false;
    };
    let advanced = match source_advanced_through(a, a.duration) {
        Source::Media { r#in, .. } => r#in,
        _ => return false,
    };
    ma == mb && b.start == end(a) && ib == advanced
}

/// The run `clip` is in, in time order.
pub(crate) fn run_of<'p>(project: &'p Project, clip: &Clip) -> Vec<&'p Clip> {
    let mut on: Vec<&Clip> = project
        .clips
        .iter()
        .filter(|c| c.track == clip.track)
        .collect();
    on.sort_by_key(|c| c.start);
    let Some(at) = on.iter().position(|c| c.id == clip.id) else {
        return Vec::new();
    };
    let (mut lo, mut hi) = (at, at);
    while lo > 0 && continues(on[lo - 1], on[lo]) {
        lo -= 1;
    }
    while hi + 1 < on.len() && continues(on[hi], on[hi + 1]) {
        hi += 1;
    }
    on[lo..=hi].to_vec()
}

/// Clip time for `read` source ticks past `in`: through S on a ramp,
/// `⌊read / speed⌋` otherwise.
pub(crate) fn clip_time(clip: &Clip, read: Ticks) -> Ticks {
    if is_ramped(clip) {
        return time_for_source(clip, read).unwrap_or(0);
    }
    (read as f64 / clip.speed).floor() as Ticks
}

/// What a run is planned against.
pub(crate) struct Run<'a> {
    pub clips: Vec<&'a Clip>,
    pub given: &'a [u32],
    pub tracks: &'a [&'a CursorTrack],
    /// The project as it will be at apply (Replace's removals made).
    pub next: &'a Project,
    pub window: (Ticks, Ticks),
    pub typing: bool,
    /// Half the media's size, P's origin in movie px.
    pub half: (f64, f64),
}

impl Run<'_> {
    pub(crate) fn is_given(&self, c: &Clip) -> bool {
        self.given.contains(&c.id)
    }

    fn track(&self, c: &Clip) -> Option<&CursorTrack> {
        let i = self.given.iter().position(|&g| g == c.id)?;
        self.tracks.get(i).copied()
    }

    fn p(&self, track: &CursorTrack, t_us: f64, x: i64, y: i64) -> (f64, f64) {
        let (mx, my) = track.to_movie(t_us, x as f64, y as f64);
        (mx - self.half.0, my - self.half.1)
    }

    /// The region's size at `scale` and the cropped rect, from the run's
    /// first given clip.
    pub(crate) fn frame(&self, scale: f64) -> Frame {
        let first = self.clips.iter().find(|c| self.is_given(c));
        let v = first.map(|c| base(c)).unwrap_or_default();
        let canvas = (
            f64::from(self.next.canvas.width),
            f64::from(self.next.canvas.height),
        );
        let (hw, hh) = self.half;
        Frame {
            size: region_size(canvas, scale, v.rotation),
            min: (-hw + v.crop.l, -hh + v.crop.t),
            max: (hw - v.crop.r, hh - v.crop.b),
        }
    }

    /// Every given clip's anchors (CU-70, CU-72) and scroll-burst starts,
    /// in container time.
    pub(crate) fn anchors(&self) -> (Vec<Anchor>, Vec<Ticks>) {
        let (mut anchors, mut bursts) = (Vec::new(), Vec::new());
        for &c in self.clips.iter().filter(|c| self.is_given(c)) {
            let (Some(track), Some((_, source_in))) = (self.track(c), media_in(c)) else {
                continue;
            };
            let length = self.next.content_length_in_source(c);
            let file = track.file();
            let inside = |us: i64| {
                let s = us_to_ticks(us);
                (source_in <= s && s < source_in.saturating_add(length))
                    .then(|| c.start.saturating_add(clip_time(c, s - source_in)))
            };
            let kept = |t: Ticks| self.window.0 <= t && t < self.window.1;
            let k = &file.clicks;
            let downs: Vec<usize> = (0..k.t.len()).filter(|&i| k.down[i] == 1).collect();
            for &i in &downs {
                if let Some(t) = inside(k.t[i]).filter(|&t| kept(t)) {
                    let p = self.p(track, k.t[i] as f64, k.x[i], k.y[i]);
                    anchors.push(Anchor { t, end: t, p });
                }
            }
            if self.typing {
                for (first, last, _) in typing_stretches(&file.keys.typed.t) {
                    let Some(t) = inside(first).filter(|&t| kept(t)) else {
                        continue;
                    };
                    let read = us_to_ticks(last) - source_in;
                    let until = c.start.saturating_add(clip_time(c, read)).max(t);
                    // CU-72: the last down click at or before the first mark.
                    let aim = downs.iter().rev().find(|&&i| k.t[i] <= first);
                    let p = match aim {
                        Some(&i) => self.p(track, k.t[i] as f64, k.x[i], k.y[i]),
                        None => match track.raw_at(first as f64) {
                            Some((x, y)) => {
                                let (mx, my) = track.to_movie(first as f64, x, y);
                                (mx - self.half.0, my - self.half.1)
                            }
                            None => continue,
                        },
                    };
                    anchors.push(Anchor { t, end: until, p });
                }
            }
            for (first, _, _) in scroll_bursts(&file.scrolls.t) {
                bursts.extend(inside(first));
            }
        }
        bursts.sort_unstable();
        (anchors, bursts)
    }

    /// Cuts into a clip that was not given, and the run's end.
    pub(crate) fn barriers(&self) -> Vec<Barrier> {
        let mut out: Vec<Barrier> = self
            .clips
            .windows(2)
            .filter(|w| !self.is_given(w[1]))
            .map(|w| Barrier {
                at: end(w[0]),
                counted: true,
            })
            .collect();
        if let Some(last) = self.clips.last() {
            out.push(Barrier {
                at: end(last),
                counted: false,
            });
        }
        out
    }

    /// Cuts a hold crosses into a given clip with a kept action meeting
    /// the hold, not yet barriers.
    pub(crate) fn closing_cuts(&self, holds: &[(Ticks, Ticks)], have: &[Barrier]) -> Vec<Barrier> {
        let mut out: Vec<Barrier> = Vec::new();
        for w in self.clips.windows(2) {
            let cut = end(w[0]);
            if have.iter().chain(&out).any(|b| b.at == cut) {
                continue;
            }
            let Some(after) = self.next.clip(w[1].id) else {
                continue;
            };
            let hit = holds.iter().any(|&(lo, hi)| {
                lo < cut
                    && cut < hi
                    && after.actions.iter().any(|a| {
                        let s = after.start.saturating_add(a.start);
                        s < hi && cut < s.saturating_add(a.duration)
                    })
            });
            if hit {
                out.push(Barrier {
                    at: cut,
                    counted: true,
                });
            }
        }
        out
    }

    /// The raw cursor in P at container time `t`, inside a given clip.
    pub(crate) fn cursor(&self, t: Ticks) -> Option<(f64, f64)> {
        let c = self
            .clips
            .iter()
            .find(|c| self.is_given(c) && c.start <= t && t < end(c))?;
        let track = self.track(c)?;
        let (_, source_in) = media_in(c)?;
        let us = ticks_to_us(source_in.saturating_add(source_read_by(c, t - c.start)));
        let (x, y) = track.raw_at(us)?;
        let (mx, my) = track.to_movie(us, x, y);
        Some((mx - self.half.0, my - self.half.1))
    }

    /// CU-74: the given clip a planned span lands on, the span moved so it
    /// straddles no cut and held inside the clip.
    pub(crate) fn land(&self, mut p: Planned) -> Option<(u32, Planned)> {
        let mid = p.from + (p.to - p.from) / 2;
        let overlap = |c: &Clip| (p.to.min(end(c)) - p.from.max(c.start)).max(0);
        let distance = |c: &Clip| (c.start - p.to).max(p.from - end(c)).max(0);
        let target = self
            .clips
            .iter()
            .find(|c| self.is_given(c) && c.start <= mid && mid < end(c))
            .or_else(|| {
                self.clips
                    .iter()
                    .filter(|c| self.is_given(c))
                    .min_by_key(|c| (-overlap(c), distance(c)))
            })?;
        let d = p.to - p.from;
        if p.from < target.start {
            (p.from, p.to) = (target.start, target.start + d);
        }
        if p.to > end(target) {
            (p.from, p.to) = (end(target) - d, end(target));
        }
        p.from = p.from.max(target.start);
        Some((target.id, p))
    }
}
