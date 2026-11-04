//! Choosing the subject to follow (road map "creator-jobs" VR2a1, spec §11
//! VR-21): boxes found per sample, linked into tracks here, and one track
//! chosen per sample. Nothing is stored (CJ-31): the planner builds the
//! tracks over the samples it is handed, every time.
//!
//! The analyses find boxes per sample and never track (VR-4), so a "who" is
//! this module's: a box joins the track of its kind whose last box is at
//! most [`LINK_GAP`] earlier and overlaps it most (IoU at least
//! [`LINK_IOU`]), and a shot change ends every track, since a box after a
//! cut is a different picture whatever it overlaps. The choice then reads
//! each present track's score — how steadily it is there, how big, how
//! central — under three rules: a tier (faces over people over salient
//! regions, for `subject`), a face's own body standing in for it while it is
//! away, and hysteresis, so two near-equal faces do not trade the frame
//! back and forth. An absent primary is held [`LOSS_HOLD`] (VR2a2, spec §11
//! VR-24 (c)): the best present track stands in, marked `lost`, and replaces
//! the primary only once the hold has passed. All times are CLIP ticks,
//! samples strictly increasing.

pub use crate::reframe_subjects::{SubjectBox, SubjectSample};
use crate::time::{Ticks, TIMESCALE};

/// The least IoU at which a box continues a track.
pub const LINK_IOU: f64 = 0.3;
/// The longest gap a track bridges: 1 s.
pub const LINK_GAP: Ticks = TIMESCALE;
/// The share of shared samples in which a person box must hold a face's
/// centre for the person to be that face's body.
pub const BODY_SHARE: f64 = 0.8;
/// How much better a rival must score to replace the primary…
pub const RIVAL_MARGIN: f64 = 1.25;
/// …at every sample for this long: 2 s.
pub const RIVAL_HOLD: Ticks = 2 * TIMESCALE;
/// A score reads the samples within this of its own, in its shot: ±1 s.
const SCORE_SPAN: Ticks = TIMESCALE;
/// How long an absent primary is held before another track replaces it,
/// and how long a framing holds a lost subject (spec §11 VR-24): 1 s.
pub const LOSS_HOLD: Ticks = TIMESCALE;

/// What a framing follows: `Subject` reads every kind in its tiers, the
/// others only their own kind.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Follow {
    Subject,
    Face,
    Person,
    Salient,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubjectKind {
    Face,
    Person,
    Salient,
}

/// The choice at one sample: the kind, the track and its box there, or all
/// `None` when nothing is followed.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Chosen {
    pub t: Ticks,
    pub kind: Option<SubjectKind>,
    pub track: Option<u32>,
    pub subject: Option<SubjectBox>,
    /// The chosen track's identity: a body's is its face's id (VR-21).
    pub identity: Option<u32>,
    /// Not its shot's first sample, and the primary identity — kept through
    /// a loss (VR-24 (c)) — has no present track here: what is chosen, if
    /// anything, is a stand-in.
    pub lost: bool,
    /// For a face or person pick: the best-scoring other present track of
    /// its tier with another identity, its box here (VR-24 (g)).
    pub second: Option<SubjectBox>,
}

const KINDS: [SubjectKind; 3] = [SubjectKind::Face, SubjectKind::Person, SubjectKind::Salient];

pub(crate) struct Track {
    pub(crate) id: u32,
    pub(crate) kind: SubjectKind,
    /// (sample index, box), ascending.
    pub(crate) boxes: Vec<(usize, SubjectBox)>,
}

impl Track {
    pub(crate) fn at(&self, i: usize) -> Option<SubjectBox> {
        self.boxes
            .binary_search_by_key(&i, |b| b.0)
            .ok()
            .map(|n| self.boxes[n].1)
    }
}

fn boxes_of(sample: &SubjectSample, kind: SubjectKind) -> &[SubjectBox] {
    match kind {
        SubjectKind::Face => &sample.faces,
        SubjectKind::Person => &sample.people,
        SubjectKind::Salient => &sample.salient,
    }
}

pub(crate) fn iou(a: &SubjectBox, b: &SubjectBox) -> f64 {
    let w = (a.x + a.w).min(b.x + b.w) - a.x.max(b.x);
    let h = (a.y + a.h).min(b.y + b.h) - a.y.max(b.y);
    if w <= 0.0 || h <= 0.0 {
        return 0.0;
    }
    let inter = w * h;
    let union = a.w * a.h + b.w * b.h - inter;
    if union > 0.0 {
        inter / union
    } else {
        0.0
    }
}

pub(crate) fn centre(b: &SubjectBox) -> (f64, f64) {
    (b.x + b.w / 2.0, b.y + b.h / 2.0)
}

fn holds(outer: &SubjectBox, point: (f64, f64)) -> bool {
    (outer.x..=outer.x + outer.w).contains(&point.0)
        && (outer.y..=outer.y + outer.h).contains(&point.1)
}

/// The median of `values` (the mean of the middle two when even); 0 when
/// empty. Sorts in place.
pub(crate) fn median(values: &mut [f64]) -> f64 {
    values.sort_by(f64::total_cmp);
    let n = values.len();
    match n {
        0 => 0.0,
        _ if n % 2 == 1 => values[n / 2],
        _ => (values[n / 2 - 1] + values[n / 2]) / 2.0,
    }
}

/// Each sample's shot: the number of cuts at or before it.
pub(crate) fn shots_of(samples: &[SubjectSample], cuts: &[Ticks]) -> Vec<usize> {
    let mut cuts = cuts.to_vec();
    cuts.sort_unstable();
    samples
        .iter()
        .map(|s| cuts.partition_point(|&c| c <= s.t))
        .collect()
}

/// Every kind's tracks, ids in creation order (samples in time order, and
/// within one faces, then people, then salient regions), and each sample's
/// present tracks. Only a track still open — its last box in the same shot
/// and at most [`LINK_GAP`] earlier — is a candidate.
pub(crate) fn link(
    samples: &[SubjectSample],
    shot: &[usize],
    kinds: &[SubjectKind],
) -> (Vec<Track>, Vec<Vec<usize>>) {
    let mut tracks: Vec<Track> = Vec::new();
    let mut present: Vec<Vec<usize>> = vec![Vec::new(); samples.len()];
    let mut open: Vec<usize> = Vec::new();
    for (i, sample) in samples.iter().enumerate() {
        open.retain(|&n| {
            let last = tracks[n].boxes.last().expect("a track has a box").0;
            shot[last] == shot[i] && sample.t - samples[last].t <= LINK_GAP
        });
        let before = open.clone();
        for &kind in kinds {
            for b in boxes_of(sample, kind) {
                let mut best: Option<(usize, f64)> = None;
                for &n in &before {
                    let (last, last_box) = *tracks[n].boxes.last().expect("a track has a box");
                    if tracks[n].kind != kind || last == i {
                        continue;
                    }
                    let overlap = iou(&last_box, b);
                    if overlap >= LINK_IOU && best.is_none_or(|(_, o)| overlap > o) {
                        best = Some((n, overlap));
                    }
                }
                let n = match best {
                    Some((n, _)) => {
                        tracks[n].boxes.push((i, *b));
                        n
                    }
                    None => {
                        let id = tracks.len() as u32;
                        tracks.push(Track {
                            id,
                            kind,
                            boxes: vec![(i, *b)],
                        });
                        open.push(tracks.len() - 1);
                        tracks.len() - 1
                    }
                };
                present[i].push(n);
            }
        }
        // Ascending ids, so a tie goes to the lower one.
        present[i].sort_unstable();
    }
    (tracks, present)
}

/// For each person track, the face track it is the body of, if any: the one
/// with the most shared samples among those whose centre it holds in at
/// least [`BODY_SHARE`] of them.
fn bodies(tracks: &[Track]) -> Vec<Option<u32>> {
    tracks
        .iter()
        .map(|person| {
            if person.kind != SubjectKind::Person {
                return None;
            }
            let mut best: Option<(u32, usize)> = None;
            for face in tracks.iter().filter(|t| t.kind == SubjectKind::Face) {
                let (mut shared, mut held) = (0usize, 0usize);
                for &(i, pb) in &person.boxes {
                    if let Some(fb) = face.at(i) {
                        shared += 1;
                        held += usize::from(holds(&pb, centre(&fb)));
                    }
                }
                if shared > 0
                    && held as f64 >= BODY_SHARE * shared as f64
                    && best.is_none_or(|(_, n)| shared > n)
                {
                    best = Some((face.id, shared));
                }
            }
            best.map(|(id, _)| id)
        })
        .collect()
}

/// A track's score at sample `i`: presence × median area × centrality over
/// the samples within [`SCORE_SPAN`] of it in its shot.
fn score(track: &Track, i: usize, samples: &[SubjectSample], shot: &[usize]) -> f64 {
    let t = samples[i].t;
    let in_window = |j: usize| shot[j] == shot[i] && (samples[j].t - t).abs() <= SCORE_SPAN;
    let lo = (0..=i)
        .rev()
        .take_while(|&j| in_window(j))
        .last()
        .unwrap_or(i);
    let hi = (i..samples.len())
        .take_while(|&j| in_window(j))
        .last()
        .unwrap_or(i);
    let from = track.boxes.partition_point(|b| b.0 < lo);
    let to = track.boxes.partition_point(|b| b.0 <= hi);
    let mut areas: Vec<f64> = track.boxes[from..to]
        .iter()
        .map(|(_, b)| b.w * b.h)
        .collect();
    let presence = areas.len() as f64 / (hi - lo + 1) as f64;
    let area = median(&mut areas);
    let (cx, cy) = track.at(i).map(|b| centre(&b)).unwrap_or((0.5, 0.5));
    let off = ((cx - 0.5).powi(2) + (cy - 0.5).powi(2)).sqrt();
    let centrality = 1.0 - (off / (0.5 * 2f64.sqrt())).min(1.0);
    presence * area * centrality
}

/// One [`Chosen`] per sample (spec §11 VR-21). `samples` in clip ticks,
/// strictly increasing; `cuts` in clip ticks.
pub fn choose_subject(samples: &[SubjectSample], cuts: &[Ticks], follow: Follow) -> Vec<Chosen> {
    let kinds: &[SubjectKind] = match follow {
        Follow::Subject => &KINDS,
        Follow::Face => &KINDS[0..1],
        Follow::Person => &KINDS[1..2],
        Follow::Salient => &KINDS[2..3],
    };
    let shot = shots_of(samples, cuts);
    let (tracks, present) = link(samples, &shot, kinds);
    let body = if follow == Follow::Subject {
        bodies(&tracks)
    } else {
        vec![None; tracks.len()]
    };
    // A track's identity: a body is its face.
    let identity = |n: usize| body[n].unwrap_or(tracks[n].id);
    let mut primary: Option<u32> = None;
    let mut rivals: Vec<(u32, Ticks)> = Vec::new();
    // The first sample at which the primary had no present track (VR-24 (c)).
    let mut absent_since: Option<Ticks> = None;
    let mut out = Vec::with_capacity(samples.len());
    for (i, sample) in samples.iter().enumerate() {
        let first_of_shot = i == 0 || shot[i] != shot[i - 1];
        let tier = kinds
            .iter()
            .copied()
            .find(|&kind| present[i].iter().any(|&n| tracks[n].kind == kind));
        let Some(tier) = tier else {
            // Nothing present: a shot's first sample clears the primary, any
            // other sample counts towards its absence.
            if first_of_shot {
                primary = None;
                rivals.clear();
                absent_since = None;
            } else if primary.is_some() {
                absent_since.get_or_insert(sample.t);
            }
            out.push(Chosen {
                t: sample.t,
                kind: None,
                track: None,
                subject: None,
                identity: None,
                lost: primary.is_some() && !first_of_shot,
                second: None,
            });
            continue;
        };
        let candidates: Vec<(usize, f64)> = present[i]
            .iter()
            .copied()
            .filter(|&n| tracks[n].kind == tier)
            .map(|n| (n, score(&tracks[n], i, samples, &shot)))
            .collect();
        let best_of = |set: &mut dyn Iterator<Item = (usize, f64)>| {
            set.fold(None, |best: Option<(usize, f64)>, (n, s)| match best {
                Some((_, b)) if s <= b => best,
                _ => Some((n, s)),
            })
        };
        let best = best_of(&mut candidates.iter().copied()).expect("a tier has a track");
        let staying = best_of(
            &mut candidates
                .iter()
                .copied()
                .filter(|&(n, _)| Some(identity(n)) == primary),
        );
        let mut lost = false;
        let chosen = match staying {
            Some((stay, stay_score)) if !first_of_shot => {
                let meeting: Vec<(usize, f64)> = candidates
                    .iter()
                    .copied()
                    .filter(|&(n, s)| {
                        Some(identity(n)) != primary && s >= RIVAL_MARGIN * stay_score
                    })
                    .collect();
                rivals.retain(|(id, _)| meeting.iter().any(|&(n, _)| identity(n) == *id));
                for &(n, _) in &meeting {
                    if !rivals.iter().any(|(id, _)| *id == identity(n)) {
                        rivals.push((identity(n), sample.t));
                    }
                }
                let ready = best_of(&mut meeting.iter().copied().filter(|&(n, _)| {
                    rivals
                        .iter()
                        .any(|&(id, since)| id == identity(n) && sample.t - since >= RIVAL_HOLD)
                }));
                match ready {
                    Some((n, _)) => n,
                    None => stay,
                }
            }
            // The primary absent (VR-24 (c)): the best present track stands
            // in, the primary kept, until `LOSS_HOLD` has passed.
            None if !first_of_shot && primary.is_some() => {
                let since = *absent_since.get_or_insert(sample.t);
                lost = sample.t - since < LOSS_HOLD;
                best.0
            }
            _ => best.0,
        };
        if !lost {
            absent_since = None;
            if Some(identity(chosen)) != primary {
                primary = Some(identity(chosen));
                rivals.clear();
            }
        }
        let second = match tracks[chosen].kind {
            SubjectKind::Face | SubjectKind::Person => best_of(
                &mut candidates
                    .iter()
                    .copied()
                    .filter(|&(n, _)| identity(n) != identity(chosen)),
            )
            .and_then(|(n, _)| tracks[n].at(i)),
            SubjectKind::Salient => None,
        };
        out.push(Chosen {
            t: sample.t,
            kind: Some(tracks[chosen].kind),
            track: Some(tracks[chosen].id),
            subject: tracks[chosen].at(i),
            identity: Some(identity(chosen)),
            lost,
            second,
        });
    }
    out
}
