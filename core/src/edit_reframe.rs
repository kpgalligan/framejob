//! `reframe_clip` — one clip framed on the current canvas (road map
//! "creator-jobs" VR2a2 and VR2b1, spec §11 VR-26, VR-27). The planner is
//! `reframe.rs`'s (VR-20…VR-24), the writing `reframe_compose.rs`'s (the
//! path composed into the base and the actions the clip already carries,
//! VR-27) and `reframe_cover.rs`'s (`keep`, the backdrop, VR-25); this
//! module reads the arguments, refuses in VR-26's order, and finishes.
//! `replace: true` strips `x`, `y` and `scale` from the ends and fits the
//! base before planning, for every follow but `keep`.
//!
//! **What reads what.** The FOLLOWING kinds (`subject`, `face`, `person`,
//! `salient`) plan over `subjects`; `center` and `fit` are `fixed_framing`;
//! `keep` is `set_canvas`'s rescale on the base. `layout` (VR5b, spec §11
//! VR-53) re-lays a camera's switches and its screen's on the current
//! canvas through `reframe_layout.rs`, reading no `zoom`, `where_empty`,
//! `backdrop`, `replace` or `subjects` and skipping refusals (5) and (6) as
//! `keep` does. Only `keep` and `layout` read `from_*`
//! (every other placement is measured from a canvas centre, so the source
//! size cancels), `fit` and `keep` ignore `zoom`, and only the following
//! kinds read `where_empty` and `subjects`; a value that cannot be read is
//! an `Err` whatever the follow. `cursor` (VR5, spec §11 VR-50) plans over
//! `subjects.cursor` with `reframe_cursor.rs`'s planner and reads no
//! `where_empty`; a face follow never reads the cursor, and a clip whose
//! media has a cursor file is never followed by faces (VR-51).
//!
//! `speaker` (VR6a, spec §11 VR-60, VR-61) frames a wide shot on whoever
//! speaks: it reads `subjects` (its faces' `mouth` and its `turns`) and
//! `mics`, `mic_faces`, `zoom`, `where_empty`, `backdrop` and `replace` as
//! `face` does, and plans through `reframe_speaker.rs`; its subject-free
//! refusals (the microphones', `mic_faces`') come here after (5)–(6) and
//! before `subjects`' values, and the rest are the planner's sentences after
//! "no subjects". No other follow reads `mics` or `mic_faces`.
//!
//! **Why "no subjects" is refused LAST.** The tool fills `subjects` from the
//! analysis cache (VR-28) and first tries the op without them: every other
//! refusal must answer that trial, so only a clip that could be framed waits
//! for an analysis. [`no_subjects`] is the sentence both sides know.
//!
//! **`subjects` is read strictly** (`reframe_subjects.rs`, its reader and
//! [`check_subjects`]).

use serde::{Deserialize, Serialize};

use crate::model::{
    Action, Clip, DuringMotion, EdgeMotion, MediaKind, Project, Source, VideoProps,
};
use crate::outcome::Outcome;
use crate::recipe_matte::matte_target;
use crate::reframe::{
    fixed_framing, in_clip_time, plan_framing, FramingRequest, Subjects, WhereEmpty, FRAMING_TUNING,
};
use crate::reframe_cursor::{cursor_in_clip_time, plan_cursor_framing};
use crate::reframe_speaker::{mics_refusal, plan_speaker_framing};
use crate::reframe_subjects::check_subjects;
use crate::reframe_tracks::Follow;

/// What a framing follows (VR-26).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FramingFollow {
    Subject,
    Face,
    Person,
    Salient,
    Cursor,
    Layout,
    Speaker,
    Center,
    Fit,
    Keep,
}

impl FramingFollow {
    fn following(self) -> Option<Follow> {
        match self {
            Self::Subject => Some(Follow::Subject),
            Self::Face => Some(Follow::Face),
            Self::Person => Some(Follow::Person),
            Self::Salient => Some(Follow::Salient),
            Self::Cursor | Self::Layout | Self::Speaker | Self::Center | Self::Fit | Self::Keep => {
                None
            }
        }
    }

    /// The kinds that read `subjects`: the following kinds, `cursor` and
    /// `speaker`.
    fn reads_subjects(self) -> bool {
        self.following().is_some() || matches!(self, Self::Cursor | Self::Speaker)
    }
}

/// The most samples `subjects` may hold, and boxes of a kind per sample.
pub const MAX_SUBJECT_SAMPLES: usize = 100_000;
pub const MAX_SUBJECT_BOXES: usize = 8;

/// `reframe_clip`'s arguments, in the row's order.
#[derive(Debug, Clone, PartialEq)]
pub struct Reframe {
    pub clip: u32,
    pub follow: FramingFollow,
    pub zoom: Option<f64>,
    pub where_empty: Option<WhereEmpty>,
    pub from_width: Option<u32>,
    pub from_height: Option<u32>,
    pub backdrop: Option<u32>,
    pub replace: Option<bool>,
    pub mics: Option<Vec<u32>>,
    pub mic_faces: Option<Vec<u32>>,
    pub subjects: Option<Subjects>,
}

/// Refusal (10)'s sentence (VR-26), which the tool matches to know a clip
/// waits only for its analysis (VR-28, `AgentServer+Framing.swift`).
pub fn no_subjects(clip: u32) -> String {
    format!("clip {clip} has no subjects to follow; analyze it first")
}

/// VR-50 (h): `cursor` on a media clip whose media has no cursor file.
pub fn no_cursor_file(clip: u32) -> String {
    format!(
        "clip {clip}'s media has no cursor file, so there is no cursor to follow; frame it with \
         subject, center, fit or keep"
    )
}

/// VR-51: a following kind on a media clip whose media has a cursor file.
pub fn cursor_not_faces(clip: u32) -> String {
    format!(
        "clip {clip}'s media has a cursor file, so it follows the cursor, not faces; frame it \
         with cursor, center, fit or keep"
    )
}

impl Project {
    /// The op (spec §11 VR-26; this module's doc, and `edit.rs`'s row).
    pub fn reframe_clip(&self, r: &Reframe) -> Result<Outcome, String> {
        let clip = self.require_clip(r.clip)?.clone();
        if let Some(z) = r
            .zoom
            .filter(|z| !(z.is_finite() && (1.0..=4.0).contains(z)))
        {
            return Err(format!("zoom must be between 1 and 4 times fill, not {z}"));
        }
        for (key, value) in [("from_width", r.from_width), ("from_height", r.from_height)] {
            if value == Some(0) {
                return Err(format!("{key} must be greater than 0, not 0"));
            }
        }
        if let Some(track) = r.backdrop {
            self.require_track(track)?;
        }
        if r.follow == FramingFollow::Speaker {
            for &mic in r.mics.iter().flatten() {
                self.require_clip(mic)?;
            }
        }
        match self.refusal(&clip, r) {
            Some(why) => Ok(Outcome::Refused(why)),
            None => self.reframed(&clip, r),
        }
    }

    /// Refusals (1)–(6) and (8) of VR-26, in order ((7) removed by VR-27),
    /// VR-50's and VR-51's after the nest and still refusals.
    fn refusal(&self, clip: &Clip, r: &Reframe) -> Option<String> {
        let id = clip.id;
        let keep = r.follow == FramingFollow::Keep;
        let following = r.follow.reads_subjects();
        let kind = match clip.source {
            Source::Text => "text",
            Source::Shape => "shape",
            Source::Graphic => "graphic",
            Source::Adjustment => "adjustment",
            _ => "",
        };
        if !kind.is_empty() {
            return (!keep).then(|| {
                format!(
                    "clip {id} is a {kind} clip, with no picture to frame; only keep reframes it"
                )
            });
        }
        let picture = match clip.source {
            Source::Media { media, .. } | Source::Still { media, .. } => self
                .media(media)
                .is_some_and(|m| m.has_video && m.kind == MediaKind::Video),
            _ => true,
        };
        let Some((mw, mh)) = self.source_size(clip).filter(|_| picture) else {
            return Some(format!("clip {id}'s media has no picture to frame"));
        };
        let video = clip.video.clone().unwrap_or_default();
        let crop = video.crop;
        if !(mw - crop.l - crop.r > 0.0
            && mh - crop.t - crop.b > 0.0
            && video.scale.is_finite()
            && video.scale > 0.0)
        {
            return Some(no_picture(id));
        }
        if following {
            match clip.source {
                Source::Nest { .. } => {
                    return Some(format!(
                        "clip {id} shows a nest, which has no subjects to follow; frame it with \
                         center, fit or keep"
                    ))
                }
                Source::Still { .. } | Source::Image { .. } => {
                    return Some(format!(
                        "clip {id} shows a still picture, which has no subjects to follow; frame \
                         it with center, fit or keep"
                    ))
                }
                Source::Media { media, .. } => {
                    let cursor = self.media(media).is_some_and(|m| m.cursor.is_some());
                    if r.follow == FramingFollow::Cursor && !cursor {
                        return Some(no_cursor_file(id));
                    }
                    if r.follow != FramingFollow::Cursor && cursor {
                        return Some(cursor_not_faces(id));
                    }
                }
                _ => {}
            }
        }
        // `layout` re-lays switches that passed CO-62 when made (VR-53 (c)).
        if !keep && r.follow != FramingFollow::Layout {
            if let Some(why) = self.matte_refusal(clip) {
                return Some(why);
            }
            if let Some(why) = turn_refusal(id, clip, &video) {
                return Some(why);
            }
        }
        if r.follow == FramingFollow::Speaker {
            let (mics, faces) = (r.mics.as_deref(), r.mic_faces.as_deref());
            if let Some(why) = mics_refusal(self, id, mics, faces) {
                return Some(why);
            }
        }
        if following {
            if let Some(Err(why)) = r.subjects.as_ref().map(check_subjects) {
                return Some(why);
            }
        }
        None
    }

    /// Refusal (5): a matte track's clip, or one a matte cuts.
    fn matte_refusal(&self, clip: &Clip) -> Option<String> {
        let id = clip.id;
        let index = self.track_index(clip.track)?;
        if self.tracks[index].matte.is_none() {
            let front = self.tracks.get(index + 1)?;
            return (matte_target(&self.tracks, front.id) == Some(clip.track)).then(|| {
                format!(
                    "clip {id} is cut by the matte on track {}, which framing would move it \
                     out of; only keep reframes it",
                    front.id
                )
            });
        }
        Some(format!(
            "clip {id} is on a matte track, which framing would move; only keep reframes it"
        ))
    }

    /// Planned, refused (9) and (10), written and finished.
    fn reframed(&self, clip: &Clip, r: &Reframe) -> Result<Outcome, String> {
        let id = clip.id;
        let zoom = r.zoom.unwrap_or(1.0);
        let canvas = (self.canvas.width, self.canvas.height);
        let from = (r.from_width, r.from_height);
        let from = (from.0.unwrap_or(canvas.0), from.1.unwrap_or(canvas.1));
        match r.follow {
            FramingFollow::Keep => return self.finish(self.kept(id, from)),
            FramingFollow::Layout => return self.relaid(id, from),
            _ => {}
        }
        // VR-27 (g): the strip and the Fit base come before the plan.
        let stripped;
        let source = if r.replace == Some(true) {
            stripped = self.replaced(id);
            &stripped
        } else {
            self
        };
        let path = match (r.follow, r.follow.following()) {
            (FramingFollow::Center, _) => fixed_framing(source, id, WhereEmpty::Center, zoom),
            (FramingFollow::Fit, _) => fixed_framing(source, id, WhereEmpty::Fit, 1.0),
            (FramingFollow::Speaker, _) => {
                let Some(subjects) = &r.subjects else {
                    return Ok(Outcome::Refused(no_subjects(id)));
                };
                let mics = r.mics.as_deref().unwrap_or(&[]);
                let empty = r.where_empty.unwrap_or_default();
                let faces = r.mic_faces.as_deref();
                match plan_speaker_framing(source, id, subjects, mics, faces, zoom, empty) {
                    Ok(path) => Some(path),
                    Err(why) => return Ok(Outcome::Refused(why)),
                }
            }
            (FramingFollow::Cursor, _) => {
                let Some(subjects) = &r.subjects else {
                    return Ok(Outcome::Refused(no_subjects(id)));
                };
                plan_cursor_framing(source, id, &subjects.cursor, zoom)
            }
            (_, Some(follow)) => {
                let Some(subjects) = &r.subjects else {
                    return Ok(Outcome::Refused(no_subjects(id)));
                };
                let request = FramingRequest {
                    follow,
                    zoom,
                    from_width: canvas.0,
                    from_height: canvas.1,
                    where_empty: r.where_empty.unwrap_or_default(),
                };
                plan_framing(source, id, subjects, &request, &FRAMING_TUNING)
            }
            (_, None) => None,
        };
        // No path is unreached: every arm the planner has is refused above.
        let Some(path) = path else {
            return Ok(Outcome::Refused(no_picture(id)));
        };
        let backdrop = r.backdrop.filter(|_| path.shows_fit);
        let original = Clip {
            video: Some(clip.video.clone().unwrap_or_default()),
            ..clip.clone()
        };
        if let Some(track) = backdrop {
            if let Err(why) = self.blurred_copy(&original, 0, 0) {
                return Ok(Outcome::Refused(why));
            }
            if self.track_index(track) >= self.track_index(clip.track) {
                return Ok(Outcome::Refused(format!(
                    "track {track} is not behind clip {id}'s track, so a backdrop there would \
                     cover it"
                )));
            }
        }
        if let (Some(_), Some(subjects)) = (r.follow.following(), &r.subjects) {
            if in_clip_time(clip, self, subjects).0.is_empty() {
                return Ok(Outcome::Refused(no_subjects(id)));
            }
        }
        if let (FramingFollow::Cursor, Some(subjects)) = (r.follow, &r.subjects) {
            if cursor_in_clip_time(clip, self, &subjects.cursor).is_empty() {
                return Ok(Outcome::Refused(no_subjects(id)));
            }
        }
        let (mut next, _) = source.composed(id, &path);
        if let Some(track) = backdrop {
            next = next.with_backdrop(&original, track)?;
        }
        self.finish(next)
    }
}

/// Refusal (2)'s crop sentence.
fn no_picture(id: u32) -> String {
    format!("clip {id}'s crop or scale leaves no picture to frame")
}

/// Refusal (6): a turned base, an action end turning the clip, or a spin.
fn turn_refusal(id: u32, clip: &Clip, video: &VideoProps) -> Option<String> {
    let upright = "framing works on an upright picture; only keep reframes it";
    if video.rotation != 0.0 {
        return Some(format!(
            "clip {id} is turned {}°, and {upright}",
            video.rotation
        ));
    }
    let turning = |a: &&Action| {
        a.end["video"]["rotation"]
            .as_f64()
            .is_some_and(|r| r != 0.0)
    };
    if let Some(action) = clip.actions.iter().find(turning) {
        return Some(format!(
            "clip {id}'s action {} turns it, and {upright}",
            action.id
        ));
    }
    let spins = video.motion.as_ref().is_some_and(|m| {
        [m.r#in, m.out]
            .iter()
            .flatten()
            .any(|e| e.kind == EdgeMotion::Spin)
            || m.during.is_some_and(|d| d.kind == DuringMotion::Spin)
    });
    spins.then(|| format!("clip {id} spins in its motion, and {upright}"))
}
