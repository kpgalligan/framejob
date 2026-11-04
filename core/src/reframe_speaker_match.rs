//! `follow: speaker`'s match (road map "creator-jobs" VR6a, spec §11 VR-61
//! (a)–(d)), pure, beside `reframe_speaker.rs`, which plans and writes the
//! path: which face is whose microphone.
//!
//! - **Faces** (VR-61 (a)). `reframe_tracks.rs`'s tracks of the in-clip
//!   faces (`link`, reused), chained across a gap when a later track starts
//!   after a chain's last box and overlaps it ([`LINK_IOU`], `iou`); a chain
//!   in at least [`FACE_SHARE`] of the samples is a face, at most
//!   [`MAX_SPEAKERS`] of them by sample count, numbered 1… left to right by
//!   median centre x (ties: the earlier first sample).
//! - **Activity** (b): a face's mouth's population standard deviation over
//!   ±[`ACTIVITY_SPAN`], at least two values.
//! - **Agreement** (c): Pearson's r between the activity and "a turn of the
//!   microphone covers the sample"; 0 when undefined.
//! - **Assignment** (d): the injective microphones → faces map with the
//!   greatest sum, ties to the smallest face list; [`sure`] when every pair
//!   reaches [`SPEAKER_AGREEMENT`], provisional until S-PC3 (VR-62).
//!
//! All times are CLIP ticks.

use crate::reframe_subjects::Turn;
use crate::reframe_tracks::{
    centre, iou, link, median, SubjectBox, SubjectKind, SubjectSample, LINK_IOU,
};
use crate::time::{Ticks, TIMESCALE};

/// A face's activity reads its mouths within this of a sample: ±0.25 s,
/// SW-81's 0.5 s window.
pub const ACTIVITY_SPAN: Ticks = TIMESCALE / 4;
/// The share of the samples a chain must be in to be a face.
pub const FACE_SHARE: f64 = 0.25;
/// The most faces a match considers.
pub const MAX_SPEAKERS: usize = 4;
/// The least agreement each assigned pair needs for the match to be sure;
/// PROVISIONAL until S-PC3 measures it (VR-62).
pub const SPEAKER_AGREEMENT: f64 = 0.2;

/// One face found: its number (1… left to right), its median centre x
/// (0…1 of the picture) and how many samples it is in.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SpeakerFace {
    pub face: u32,
    pub x: f64,
    pub samples: usize,
}

/// The faces, each microphone's agreement with each face (`[mic][face]`),
/// the face number per microphone and whether the match is sure.
#[derive(Debug, Clone, PartialEq)]
pub struct SpeakerMatch {
    pub faces: Vec<SpeakerFace>,
    pub agreement: Vec<Vec<f64>>,
    pub assignment: Vec<u32>,
    pub sure: bool,
}

/// A face's boxes by sample index, ascending.
pub(crate) struct FaceBoxes {
    first: usize,
    pub(crate) boxes: Vec<(usize, SubjectBox)>,
}

impl FaceBoxes {
    pub(crate) fn at(&self, i: usize) -> Option<SubjectBox> {
        self.boxes
            .binary_search_by_key(&i, |b| b.0)
            .ok()
            .map(|n| self.boxes[n].1)
    }
}

/// VR-61 (a): the faces, numbered left to right (index = number − 1).
pub(crate) fn faces_of(samples: &[SubjectSample]) -> Vec<FaceBoxes> {
    let shot = vec![0usize; samples.len()];
    let (tracks, _) = link(samples, &shot, &[SubjectKind::Face]);
    let mut order: Vec<usize> = (0..tracks.len()).collect();
    order.sort_by_key(|&n| (tracks[n].boxes[0].0, tracks[n].id));
    let mut chains: Vec<FaceBoxes> = Vec::new();
    for n in order {
        let (start, first_box) = tracks[n].boxes[0];
        let mut best: Option<(usize, f64)> = None;
        for (c, chain) in chains.iter().enumerate() {
            let (last, last_box) = *chain.boxes.last().expect("a chain has a box");
            let overlap = iou(&last_box, &first_box);
            if last < start && overlap >= LINK_IOU && best.is_none_or(|(_, o)| overlap > o) {
                best = Some((c, overlap));
            }
        }
        match best {
            Some((c, _)) => chains[c].boxes.extend(tracks[n].boxes.iter().copied()),
            None => chains.push(FaceBoxes {
                first: start,
                boxes: tracks[n].boxes.clone(),
            }),
        }
    }
    let least = FACE_SHARE * samples.len() as f64;
    chains.retain(|c| c.boxes.len() as f64 >= least);
    chains.sort_by_key(|c| (std::cmp::Reverse(c.boxes.len()), c.first));
    chains.truncate(MAX_SPEAKERS);
    let mut keyed: Vec<(f64, FaceBoxes)> = chains
        .into_iter()
        .map(|c| {
            let mut xs: Vec<f64> = c.boxes.iter().map(|(_, b)| centre(b).0).collect();
            (median(&mut xs), c)
        })
        .collect();
    keyed.sort_by(|a, b| a.0.total_cmp(&b.0).then(a.1.first.cmp(&b.1.first)));
    keyed.into_iter().map(|(_, c)| c).collect()
}

/// VR-61 (b): per box, the population standard deviation of the face's
/// mouths within ±[`ACTIVITY_SPAN`] of its sample; `None` under two values.
/// The boxes ascend by sample and the samples by `t` (`reframe.rs` sorts
/// them), so each window is two indices that only move forward: the cost is
/// the boxes times a window's boxes (about five at 10 Hz), not the boxes
/// squared. Each window's values are summed in box order, two passes, so a
/// still mouth's deviation is exactly 0.
fn activities(face: &FaceBoxes, samples: &[SubjectSample]) -> Vec<(usize, Option<f64>)> {
    let times: Vec<Ticks> = face.boxes.iter().map(|&(i, _)| samples[i].t).collect();
    let (mut lo, mut hi) = (0usize, 0usize);
    let mut values: Vec<f64> = Vec::new();
    face.boxes
        .iter()
        .zip(&times)
        .map(|(&(i, _), &t)| {
            while times[lo] < t - ACTIVITY_SPAN {
                lo += 1;
            }
            while hi < times.len() && times[hi] <= t + ACTIVITY_SPAN {
                hi += 1;
            }
            values.clear();
            values.extend(face.boxes[lo..hi].iter().filter_map(|(_, b)| b.mouth));
            if values.len() < 2 {
                return (i, None);
            }
            let n = values.len() as f64;
            let mean = values.iter().sum::<f64>() / n;
            let variance = values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / n;
            (i, Some(variance.sqrt()))
        })
        .collect()
}

/// Pearson's r of the pairs; 0 when it is undefined (VR-61 (c)).
pub fn pearson(pairs: &[(f64, f64)]) -> f64 {
    let n = pairs.len() as f64;
    if pairs.len() < 2 {
        return 0.0;
    }
    let (mx, my) = (
        pairs.iter().map(|p| p.0).sum::<f64>() / n,
        pairs.iter().map(|p| p.1).sum::<f64>() / n,
    );
    let (mut sxy, mut sxx, mut syy) = (0.0, 0.0, 0.0);
    for &(x, y) in pairs {
        sxy += (x - mx) * (y - my);
        sxx += (x - mx).powi(2);
        syy += (y - my).powi(2);
    }
    let r = sxy / (sxx * syy).sqrt();
    if r.is_finite() {
        r
    } else {
        0.0
    }
}

/// Whether a match is sure: every assigned agreement at least
/// [`SPEAKER_AGREEMENT`] (VR-61 (d)).
pub fn sure(agreements: &[f64]) -> bool {
    agreements.iter().all(|&a| a >= SPEAKER_AGREEMENT)
}

pub(crate) fn covered(turns: &[Turn], mic: u32, t: Ticks) -> bool {
    turns
        .iter()
        .any(|u| u.mic == mic && u.from <= t && t < u.to)
}

/// [`covered`] at each of `times`, ascending, in one forward walk over
/// `own` — one microphone's turns as `(from, to)`, sorted: a time is covered
/// exactly when the latest end of the turns begun by it is after it.
fn coverage(own: &[(Ticks, Ticks)], times: impl Iterator<Item = Ticks>) -> Vec<bool> {
    let (mut next, mut reach) = (0usize, Ticks::MIN);
    times
        .map(|t| {
            while next < own.len() && own[next].0 <= t {
                reach = reach.max(own[next].1);
                next += 1;
            }
            t < reach
        })
        .collect()
}

pub(crate) fn matched(
    samples: &[SubjectSample],
    faces: &[FaceBoxes],
    turns: &[Turn],
    mics: &[u32],
) -> Option<SpeakerMatch> {
    if faces.len() < mics.len() {
        return None;
    }
    let acts: Vec<Vec<(usize, Option<f64>)>> =
        faces.iter().map(|f| activities(f, samples)).collect();
    let agreement: Vec<Vec<f64>> = mics
        .iter()
        .map(|&mic| {
            let mut own: Vec<(Ticks, Ticks)> = turns
                .iter()
                .filter(|u| u.mic == mic)
                .map(|u| (u.from, u.to))
                .collect();
            own.sort_unstable();
            acts.iter()
                .map(|a| {
                    let cover = coverage(&own, a.iter().map(|&(i, _)| samples[i].t));
                    let pairs: Vec<(f64, f64)> = a
                        .iter()
                        .zip(cover)
                        .filter_map(|(&(_, v), c)| v.map(|v| (v, f64::from(u8::from(c)))))
                        .collect();
                    pearson(&pairs)
                })
                .collect()
        })
        .collect();
    // Every injective map in lexicographic order; a strictly greater sum
    // replaces the best, so a tie keeps the smallest face list.
    let mut best: Option<(f64, Vec<usize>)> = None;
    let mut chosen: Vec<usize> = Vec::new();
    fn walk(
        agreement: &[Vec<f64>],
        faces: usize,
        chosen: &mut Vec<usize>,
        best: &mut Option<(f64, Vec<usize>)>,
    ) {
        if chosen.len() == agreement.len() {
            let sum: f64 = chosen
                .iter()
                .enumerate()
                .map(|(m, &f)| agreement[m][f])
                .sum();
            if best.as_ref().is_none_or(|(b, _)| sum > *b) {
                *best = Some((sum, chosen.clone()));
            }
            return;
        }
        for f in 0..faces {
            if !chosen.contains(&f) {
                chosen.push(f);
                walk(agreement, faces, chosen, best);
                chosen.pop();
            }
        }
    }
    walk(&agreement, faces.len(), &mut chosen, &mut best);
    let (_, list) = best?;
    let assigned: Vec<f64> = list
        .iter()
        .enumerate()
        .map(|(m, &f)| agreement[m][f])
        .collect();
    Some(SpeakerMatch {
        faces: faces
            .iter()
            .enumerate()
            .map(|(n, f)| {
                let mut xs: Vec<f64> = f.boxes.iter().map(|(_, b)| centre(b).0).collect();
                SpeakerFace {
                    face: n as u32 + 1,
                    x: median(&mut xs),
                    samples: f.boxes.len(),
                }
            })
            .collect(),
        agreement,
        assignment: list.iter().map(|&f| f as u32 + 1).collect(),
        sure: sure(&assigned),
    })
}

/// VR-61 (a)–(d) over samples and turns in CLIP ticks; `None` when fewer
/// faces are found than there are microphones. The samples must ascend by
/// `t`, as `reframe.rs`'s `in_clip_time` leaves them: each face's activity
/// window only moves forward.
pub fn speaker_match(
    samples: &[SubjectSample],
    turns: &[Turn],
    mics: &[u32],
) -> Option<SpeakerMatch> {
    matched(samples, &faces_of(samples), turns, mics)
}

/// The median box of a face over the samples in `[a, b)`, else over all.
pub(crate) fn median_box(
    face: &FaceBoxes,
    samples: &[SubjectSample],
    a: Ticks,
    b: Ticks,
) -> SubjectBox {
    let inside: Vec<SubjectBox> = face
        .boxes
        .iter()
        .filter(|(i, _)| (a..b).contains(&samples[*i].t))
        .map(|&(_, b)| b)
        .collect();
    let list = if inside.is_empty() {
        face.boxes.iter().map(|&(_, b)| b).collect()
    } else {
        inside
    };
    let of = |f: fn(&SubjectBox) -> f64| median(&mut list.iter().map(f).collect::<Vec<_>>());
    SubjectBox {
        x: of(|b| b.x),
        y: of(|b| b.y),
        w: of(|b| b.w),
        h: of(|b| b.h),
        c: of(|b| b.c),
        mouth: None,
    }
}
