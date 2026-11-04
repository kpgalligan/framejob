//! `reframe_clip {follow: speaker}` (road map "creator-jobs" VR6a, spec §11
//! VR-60, VR-61), pure: a wide two-person clip framed on the face whose
//! microphone is speaking. The app hands the op who speaks when
//! (`subjects.turns`, Switch by Speaker's reading of the microphones) and
//! each face's mouth opening (`mouth`); `reframe_speaker_match.rs` matches
//! faces to microphones (its items re-exported here), and this module turns
//! the turns into held segments and writes them as cuts through
//! `reframe_path.rs`'s `write_keys`.
//!
//! - **Segments** (VR-61 (e)). Cut at the turns' bounds: one speaker frames
//!   their face, nobody holds the last (the first labelled one's at the
//!   start), two or more frame the pair (the face already framed first) when
//!   both widened median boxes fit the window, else the face already
//!   framed; equal neighbours coalesce, and the earliest segment shorter
//!   than [`SPEAKER_HOLD`] joins the one before it (the first, the one
//!   after) until none is short.
//! - **The path** (VR-61 (f)). Each segment start after 0 is a hard cut (a
//!   shot to `write_keys`), every sample choosing its segment's face, the
//!   pair's other face as `second`.
//!
//! VR-60 (d)'s sentences are all here: [`mics_refusal`] (the subject-free
//! ones, which `edit_reframe.rs` asks after (5)–(6)) and
//! [`plan_speaker_framing`]'s `Err`s (those that need `subjects`), each in
//! its order.

use crate::model::{Clip, MediaKind, Project, Source};
use crate::reframe::{
    in_clip_time, Frame, FramingPath, FramingRequest, WhereEmpty, FRAMING_TUNING,
};
use crate::reframe_path::{write_keys, PAIR_WIDEN};
pub use crate::reframe_speaker_match::{
    clip_speaker_match, pearson, speaker_match, sure, SpeakerFace, SpeakerMatch, ACTIVITY_SPAN,
    FACE_SHARE, MAX_SPEAKERS, SPEAKER_AGREEMENT,
};
use crate::reframe_speaker_match::{clip_turns, covered, faces_of, matched, median_box};
use crate::reframe_subjects::{Subjects, Turn};
use crate::reframe_tracks::{centre, Chosen, Follow, SubjectKind};
use crate::time::{Ticks, TIMESCALE};

/// The shortest segment that stands: 2 s (VR-61 (e)).
pub const SPEAKER_HOLD: Ticks = 2 * TIMESCALE;

/// VR-60 (d)'s subject-free refusals, in order: the count, a repeat, a
/// microphone with no sound of a media file or the framed clip, one with
/// its sound off, two on a track, then `mic_faces`.
pub(crate) fn mics_refusal(
    project: &Project,
    id: u32,
    mics: Option<&[u32]>,
    mic_faces: Option<&[u32]>,
) -> Option<String> {
    let mics = mics.unwrap_or(&[]);
    if !(2..=4).contains(&mics.len()) {
        return Some(format!(
            "follow speaker needs two to four microphone clips in mics, not {}",
            mics.len()
        ));
    }
    if let Some(&m) = mics
        .iter()
        .enumerate()
        .find(|(i, m)| mics[..*i].contains(m))
        .map(|(_, m)| m)
    {
        return Some(format!("clip {m} is named twice in mics"));
    }
    let clips: Vec<&Clip> = mics.iter().filter_map(|&m| project.clip(m)).collect();
    for c in &clips {
        if c.id == id {
            return Some(format!(
                "clip {id} is the clip being framed, so it cannot be one of its microphones"
            ));
        }
        let sounds = match c.source {
            Source::Media { media, .. } => project.media(media).is_some_and(|m| m.has_audio),
            _ => false,
        };
        if !sounds {
            return Some(format!(
                "clip {} has no sound from a media file, so it cannot be a microphone",
                c.id
            ));
        }
    }
    if let Some(c) = clips.iter().find(|c| !c.enabled.audio) {
        return Some(format!(
            "clip {}'s sound is off, so it never says who is talking; turn its sound on or \
             leave it out of mics",
            c.id
        ));
    }
    for (n, a) in clips.iter().enumerate() {
        if let Some(b) = clips[..n].iter().find(|b| b.track == a.track) {
            return Some(format!(
                "clips {} and {} are both on track {}; each microphone needs its own track",
                b.id, a.id, a.track
            ));
        }
    }
    let faces = mic_faces?;
    if faces.len() != mics.len() {
        return Some(format!(
            "mic_faces needs one face number for each of the {} microphones in mics, not {}",
            mics.len(),
            faces.len()
        ));
    }
    if faces.contains(&0) {
        return Some("mic_faces names face 0; faces are numbered from 1".to_string());
    }
    if let Some(&f) = faces
        .iter()
        .enumerate()
        .find(|(i, f)| faces[..*i].contains(f))
        .map(|(_, f)| f)
    {
        return Some(format!(
            "mic_faces names face {f} twice; each microphone needs its own face"
        ));
    }
    None
}

/// What a segment frames: a face (its index), or a pair (current, other).
#[derive(Debug, Clone, Copy, PartialEq)]
enum Label {
    Face(usize),
    Both(usize, usize),
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct Segment {
    from: Ticks,
    to: Ticks,
    label: Label,
}

fn coalesced(segments: Vec<Segment>) -> Vec<Segment> {
    let mut out: Vec<Segment> = Vec::new();
    for s in segments {
        match out.last_mut() {
            Some(last) if last.label == s.label => last.to = s.to,
            _ => out.push(s),
        }
    }
    out
}

/// VR-61 (e): the segments over `[0, duration)`; `faces[m]` is mic m's face
/// index, `fits` whether a pair fits the window over a span. `None` with no
/// turn inside the clip.
fn segments(
    duration: Ticks,
    turns: &[Turn],
    mics: &[u32],
    faces: &[usize],
    fits: impl Fn(usize, usize, Ticks, Ticks) -> bool,
) -> Option<Vec<Segment>> {
    let mut bounds: Vec<Ticks> = vec![0, duration];
    bounds.extend(
        turns
            .iter()
            .flat_map(|u| [u.from, u.to])
            .map(|t| t.clamp(0, duration)),
    );
    bounds.sort_unstable();
    bounds.dedup();
    let mut raw: Vec<(Ticks, Ticks, Option<Label>)> = Vec::new();
    let mut previous: Option<Label> = None;
    for w in bounds.windows(2) {
        let (a, b) = (w[0], w[1]);
        let active: Vec<usize> = (0..mics.len())
            .filter(|&m| covered(turns, mics[m], a))
            .map(|m| faces[m])
            .collect();
        let label = match active.as_slice() {
            [] => None,
            [f] => Some(Label::Face(*f)),
            _ => {
                let held = previous.map(|l| match l {
                    Label::Face(f) | Label::Both(f, _) => f,
                });
                let current = held.filter(|f| active.contains(f)).unwrap_or(active[0]);
                let other = *active.iter().find(|&&f| f != current).expect("two faces");
                Some(if fits(current, other, a, b) {
                    Label::Both(current, other)
                } else {
                    Label::Face(current)
                })
            }
        };
        if label.is_some() {
            previous = label;
        }
        raw.push((a, b, label.or(previous)));
    }
    let first = raw.iter().find_map(|r| r.2)?;
    let mut out = coalesced(
        raw.into_iter()
            .map(|(from, to, l)| Segment {
                from,
                to,
                label: l.unwrap_or(first),
            })
            .collect(),
    );
    // SW-22 (h)'s merge: the earliest short segment joins the one before
    // it, the first the one after, until none is short.
    while out.len() > 1 {
        let Some(i) = out.iter().position(|s| s.to - s.from < SPEAKER_HOLD) else {
            break;
        };
        if i > 0 {
            out[i - 1].to = out[i].to;
        } else {
            out[1].from = out[0].from;
        }
        out.remove(i);
        out = coalesced(out);
    }
    Some(out)
}

/// The framing (spec §11 VR-60, VR-61): `mics` checked by the op before;
/// `Err` is the refusal's sentence, in VR-60 (d)'s order.
pub fn plan_speaker_framing(
    project: &Project,
    clip: u32,
    subjects: &Subjects,
    mics: &[u32],
    mic_faces: Option<&[u32]>,
    zoom: f64,
    where_empty: WhereEmpty,
) -> Result<FramingPath, String> {
    let picture = || format!("clip {clip}'s crop or scale leaves no picture to frame");
    let c = project.clip(clip).ok_or_else(picture)?;
    let Source::Media { media, .. } = c.source else {
        return Err(picture());
    };
    if !project
        .media(media)
        .is_some_and(|m| m.kind == MediaKind::Video && m.has_video)
    {
        return Err(picture());
    }
    if let Some((i, turn)) = subjects
        .turns
        .iter()
        .enumerate()
        .find(|(_, u)| !mics.contains(&u.mic))
    {
        return Err(format!(
            "subjects turns[{i}] names clip {}, which is not one of mics",
            turn.mic
        ));
    }
    let request = FramingRequest {
        follow: Follow::Face,
        zoom,
        from_width: project.canvas.width,
        from_height: project.canvas.height,
        where_empty,
    };
    let mut frame = Frame::of(project, c, &request).ok_or_else(picture)?;
    let (samples, shots) = in_clip_time(c, project, subjects);
    if let Some(&shot) = shots.first() {
        return Err(format!(
            "clip {clip} changes shot at {}; follow speaker frames one wide shot — split the \
             clip at its shot changes first",
            project.layout_timecode(c.start + shot)
        ));
    }
    if !c.actions.is_empty() {
        frame.placed = samples
            .iter()
            .map(|s| {
                let p = project.evaluate_clip(c, s.t).video;
                (s.t, p.scale, p.x, p.y)
            })
            .collect();
    }
    let turns = clip_turns(c, &subjects.turns);
    let faces = faces_of(&samples);
    let plural = |n: usize| if n == 1 { "face" } else { "faces" };
    let Some(found) = matched(&samples, &faces, &turns, mics) else {
        return Err(format!(
            "clip {clip} shows {} {} for {} microphones; follow speaker needs a face for each \
             microphone",
            faces.len(),
            plural(faces.len()),
            mics.len()
        ));
    };
    if let Some(&f) = mic_faces
        .into_iter()
        .flatten()
        .find(|&&f| f as usize > faces.len())
    {
        return Err(format!(
            "mic_faces names face {f}, but clip {clip} shows only {} {}",
            faces.len(),
            plural(faces.len())
        ));
    }
    let no_turn = || {
        format!(
            "clip {clip} has no turn of its microphones inside it, so there is no speaker to \
             follow"
        )
    };
    if turns.is_empty() {
        return Err(no_turn());
    }
    let assignment: Vec<u32> = match mic_faces {
        Some(given) => given.to_vec(),
        None if found.sure => found.assignment.clone(),
        None => {
            let least = (0..mics.len())
                .map(|m| found.agreement[m][found.assignment[m] as usize - 1])
                .fold(f64::INFINITY, f64::min);
            let places: Vec<String> = found
                .faces
                .iter()
                .enumerate()
                .map(|(n, f)| {
                    let at = format!("face {} at {} %", f.face, (f.x * 100.0).round());
                    if n == 0 {
                        format!("{at} across the picture")
                    } else {
                        at
                    }
                })
                .collect();
            return Err(format!(
                "clip {clip}'s faces do not show which microphone is whose: the best match \
                 agrees only {least:.2} (under {SPEAKER_AGREEMENT}); name each microphone's face \
                 with mic_faces, in mics' order — {}",
                places.join(", ")
            ));
        }
    };
    let index: Vec<usize> = assignment.iter().map(|&f| f as usize - 1).collect();
    let fits = |a: usize, b: usize, from: Ticks, to: Ticks| {
        let widened = |f: usize| {
            let m = median_box(&faces[f], &samples, from, to);
            let (cx, cy) = centre(&m);
            let (w, h) = (m.w * PAIR_WIDEN, m.h * PAIR_WIDEN);
            (cx - w / 2.0, cy - h / 2.0, cx + w / 2.0, cy + h / 2.0)
        };
        let (p, q) = (widened(a), widened(b));
        let p0 = frame.point(from, p.0.min(q.0), p.1.min(q.1));
        let p1 = frame.point(from, p.2.max(q.2), p.3.max(q.3));
        p1.0 - p0.0 <= frame.window.0 && p1.1 - p0.1 <= frame.window.1
    };
    let segments = segments(c.duration, &turns, mics, &index, fits).ok_or_else(no_turn)?;
    let cuts: Vec<Ticks> = segments.iter().map(|s| s.from).filter(|&t| t > 0).collect();
    let chosen: Vec<Chosen> = samples
        .iter()
        .enumerate()
        .map(|(i, s)| {
            let n = segments
                .partition_point(|g| g.to <= s.t)
                .min(segments.len() - 1);
            let (face, other) = match segments[n].label {
                Label::Face(f) => (f, None),
                Label::Both(f, o) => (f, Some(o)),
            };
            Chosen {
                t: s.t,
                kind: Some(SubjectKind::Face),
                track: Some(face as u32 + 1),
                subject: faces[face].at(i),
                identity: Some(face as u32 + 1),
                lost: false,
                second: other.and_then(|o| faces[o].at(i)),
            }
        })
        .collect();
    Ok(write_keys(
        &frame,
        &chosen,
        &cuts,
        c.duration,
        project.canvas.fps,
        &request,
        &FRAMING_TUNING,
    ))
}
