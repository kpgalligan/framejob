//! Auto Zoom's visits (spec §11 CU-70): anchors in container time become
//! visits, and visits become planned zoom-ins, pans, follow pans and zoom
//! backs, still in container time and not yet on any clip. Pure: no
//! `Project`, no cursor file — `cursor_zoom.rs` maps the file into
//! [`Anchor`]s, scroll-burst starts, barriers and a cursor sampler, and
//! moves what comes back onto clips (CU-74).
//!
//! Positions are in P: source pixels from the centre of the UNCROPPED
//! picture, y down. A region is centred on its aim and clamped inside the
//! cropped rect ([`Frame`]); `cursor_zoom.rs` turns P into Q per clip.
//!
//! **Barriers** are cuts a hold may not cross (a cut into a clip that was
//! not given, or into one whose kept action meets the hold) and the run's
//! end. No visit spans one; a visit whose zoom back would end past one is
//! closed with a zoom back ending at it, counted when the barrier is a cut.

use crate::time::{Ticks, TIMESCALE};

/// A zoom back's length: 0.8 s.
pub(crate) const BACK: Ticks = TIMESCALE * 8 / 10;
/// A follow pan's length: 0.5 s.
const FOLLOW_PAN: Ticks = TIMESCALE / 2;
/// How long the cursor stays outside the inner 70 % before a follow pan.
const FOLLOW_OUTSIDE: Ticks = TIMESCALE * 3 / 10;
/// At most one follow pan a second, start to start.
const FOLLOW_EVERY: Ticks = TIMESCALE;
/// The follow sampler's step: 10 Hz.
const SAMPLE: Ticks = TIMESCALE / 10;
/// A zoom back ending under this before the next zoom-in starts merges.
const MERGE_GAP: Ticks = TIMESCALE;
/// Half the inner part an anchor must leave to pan: 60 %.
const ANCHOR_HALF: f64 = 0.3;
/// Half the inner part the followed cursor must leave: 70 %.
const FOLLOW_HALF: f64 = 0.35;

/// One anchor: a down click, or a typing stretch aimed per CU-72.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Anchor {
    /// Container time of the click, or of the stretch's first mark.
    pub t: Ticks,
    /// Container time the activity runs to (`t` for a click).
    pub end: Ticks,
    /// Where it aims, in P.
    pub p: (f64, f64),
}

/// The region's size and the cropped rect it is clamped inside, in P.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Frame {
    pub size: (f64, f64),
    pub min: (f64, f64),
    pub max: (f64, f64),
}

impl Frame {
    /// The region centre for an aim: clamped so the region stays inside
    /// the cropped rect, centred on an axis it exceeds.
    pub(crate) fn clamp(&self, p: (f64, f64)) -> (f64, f64) {
        let axis = |v: f64, size: f64, lo: f64, hi: f64| {
            if size >= hi - lo {
                (lo + hi) / 2.0
            } else {
                v.clamp(lo + size / 2.0, hi - size / 2.0)
            }
        };
        (
            axis(p.0, self.size.0, self.min.0, self.max.0),
            axis(p.1, self.size.1, self.min.1, self.max.1),
        )
    }

    fn outside(&self, centre: (f64, f64), p: (f64, f64), half: f64) -> bool {
        (p.0 - centre.0).abs() > half * self.size.0 || (p.1 - centre.1).abs() > half * self.size.1
    }
}

/// The figures a plan is made with.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Timing {
    pub lead: Ticks,
    pub stay: Ticks,
    pub follow: bool,
    /// One frame of the grid: a pan shorter than this is not planned.
    pub frame: Ticks,
}

/// What a planned action does.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Kind {
    In,
    Pan,
    Follow,
    Back,
}

impl Kind {
    pub(crate) fn name(self) -> &'static str {
        match self {
            Kind::In => "in",
            Kind::Pan => "pan",
            Kind::Follow => "follow",
            Kind::Back => "back",
        }
    }
}

/// One planned action in container time; `aim` is the region's centre in
/// P, `None` for a zoom back.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Planned {
    pub from: Ticks,
    pub to: Ticks,
    pub kind: Kind,
    pub aim: Option<(f64, f64)>,
    /// The index into [`Plan::holds`] of the hold that planned it, so the
    /// aim in force at a cut is read only from the hold spanning it.
    pub hold: usize,
}

/// A time no hold crosses; `counted` for a cut, not for the run's end.
#[derive(Debug, Clone, Copy)]
pub(crate) struct Barrier {
    pub at: Ticks,
    pub counted: bool,
}

/// The plan of one run.
#[derive(Debug, Default)]
pub(crate) struct Plan {
    pub actions: Vec<Planned>,
    pub visits: usize,
    pub closed: usize,
    /// Each hold's span, its zoom-in's start to its zoom back's end,
    /// indexed by `Planned::hold`.
    pub holds: Vec<(Ticks, Ticks)>,
}

struct Visit {
    anchors: Vec<Anchor>,
    last: Ticks,
    back: Ticks,
}

/// Anchors (any order), scroll-burst starts, barriers, the figures and the
/// frame, and the cursor in P at a container time → the run's plan.
pub(crate) fn plan(
    mut anchors: Vec<Anchor>,
    bursts: &[Ticks],
    barriers: &[Barrier],
    timing: Timing,
    frame: Frame,
    cursor: &dyn Fn(Ticks) -> Option<(f64, f64)>,
) -> Plan {
    anchors.sort_by_key(|a| a.t);
    let barrier_in = |lo: Ticks, hi: Ticks| barriers.iter().any(|b| lo < b.at && b.at <= hi);
    let mut visits: Vec<Visit> = Vec::new();
    for a in anchors {
        let joins = visits.last().is_some_and(|v| {
            let prev = v.anchors.last().map_or(a.t, |p| p.t);
            a.t <= v.last + timing.stay
                && !bursts.iter().any(|&b| v.last < b && b < a.t)
                && !barrier_in(prev, a.t)
        });
        match visits.last_mut() {
            Some(v) if joins => {
                v.last = v.last.max(a.end);
                v.anchors.push(a);
            }
            _ => visits.push(Visit {
                anchors: vec![a],
                last: a.end,
                back: 0,
            }),
        }
    }
    let mut out = Plan {
        visits: visits.len(),
        ..Plan::default()
    };
    // Each visit's zoom back: Stay after its last activity, or the first
    // scroll burst after its last anchor, closed at the next barrier.
    let mut closed_by = vec![false; visits.len()];
    for (i, v) in visits.iter_mut().enumerate() {
        let last_anchor = v.anchors.last().map_or(0, |a| a.t);
        let mut back = v.last + timing.stay;
        if let Some(&b) = bursts.iter().find(|&&b| b > last_anchor) {
            back = back.min(b);
        }
        if let Some(bar) = barriers.iter().find(|b| b.at > last_anchor) {
            if back + BACK > bar.at {
                back = bar.at - BACK;
                closed_by[i] = true;
                if bar.counted {
                    out.closed += 1;
                }
            }
        }
        v.back = back;
    }
    // Chains: a visit whose zoom back would end under MERGE_GAP before the
    // next one's zoom-in starts runs on into it with one pan.
    let mut chains: Vec<Vec<usize>> = Vec::new();
    for i in 0..visits.len() {
        let merge = i > 0 && !closed_by[i - 1] && {
            let (v, w) = (&visits[i - 1], &visits[i]);
            let next = w.anchors[0].t;
            let prev = v.anchors.last().map_or(next, |a| a.t);
            next - timing.lead - (v.back + BACK) < MERGE_GAP && !barrier_in(prev, next)
        };
        match chains.last_mut() {
            Some(chain) if merge => chain.push(i),
            _ => chains.push(vec![i]),
        }
    }
    for chain in chains {
        plan_chain(&chain, &visits, timing, frame, cursor, &mut out);
    }
    out
}

/// One hold: a zoom-in, the anchors' pans (a merged visit's first anchor
/// always pans), follow pans, a zoom back.
fn plan_chain(
    chain: &[usize],
    visits: &[Visit],
    timing: Timing,
    frame: Frame,
    cursor: &dyn Fn(Ticks) -> Option<(f64, f64)>,
    out: &mut Plan,
) {
    let mut anchors: Vec<(Anchor, bool)> = Vec::new();
    for (k, &i) in chain.iter().enumerate() {
        for (j, a) in visits[i].anchors.iter().enumerate() {
            anchors.push((*a, k > 0 && j == 0));
        }
    }
    let back = visits[chain[chain.len() - 1]].back;
    let first = anchors[0].0;
    let mut region = frame.clamp(first.p);
    let hold_start = first.t - timing.lead;
    let hold = out.holds.len();
    out.actions.push(Planned {
        from: hold_start,
        to: first.t,
        kind: Kind::In,
        aim: Some(region),
        hold,
    });
    let mut busy = first.t;
    let mut next = 1;
    let mut t = first.t;
    let mut outside_since: Option<Ticks> = None;
    let mut last_follow: Option<Ticks> = None;
    loop {
        while next < anchors.len() && anchors[next].0.t - timing.lead <= t {
            let (a, forced) = anchors[next];
            if forced || frame.outside(region, a.p, ANCHOR_HALF) {
                let start = (a.t - timing.lead).max(busy);
                if a.t - start >= timing.frame {
                    region = frame.clamp(a.p);
                    out.actions.push(Planned {
                        from: start,
                        to: a.t,
                        kind: Kind::Pan,
                        aim: Some(region),
                        hold,
                    });
                    busy = a.t;
                }
            }
            outside_since = None;
            next += 1;
        }
        if t >= back {
            break;
        }
        let watched = timing.follow && t >= busy;
        match watched.then(|| cursor(t)).flatten() {
            Some(p) if frame.outside(region, p, FOLLOW_HALF) => {
                let since = *outside_since.get_or_insert(t);
                let end = t + FOLLOW_PAN;
                let free = !anchors[next..]
                    .iter()
                    .any(|(a, _)| a.t - timing.lead < end && t < a.t);
                if t - since >= FOLLOW_OUTSIDE
                    && last_follow.is_none_or(|l| t - l >= FOLLOW_EVERY)
                    && end <= back
                    && free
                {
                    region = frame.clamp(p);
                    out.actions.push(Planned {
                        from: t,
                        to: end,
                        kind: Kind::Follow,
                        aim: Some(region),
                        hold,
                    });
                    busy = end;
                    last_follow = Some(t);
                    outside_since = None;
                }
            }
            _ => outside_since = None,
        }
        t += SAMPLE;
    }
    let from = back.max(busy);
    let to = back + BACK;
    if to - from >= timing.frame {
        out.actions.push(Planned {
            from,
            to,
            kind: Kind::Back,
            aim: None,
            hold,
        });
    }
    out.holds.push((hold_start, to));
}
