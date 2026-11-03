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
//! `keep` is `set_canvas`'s rescale on the base. Only `keep` reads `from_*`
//! (every other placement is measured from a canvas centre, so the source
//! size cancels), `fit` and `keep` ignore `zoom`, and only the following
//! kinds read `where_empty` and `subjects`; a value that cannot be read is
//! an `Err` whatever the follow.
//!
//! **Why "no subjects" is refused LAST.** The tool fills `subjects` from the
//! analysis cache (VR-28) and first tries the op without them: every other
//! refusal must answer that trial, so only a clip that could be framed waits
//! for an analysis. [`no_subjects`] is the sentence both sides know.
//!
//! **`subjects` is read strictly**, as `ZoomRegion` is: an object at every
//! level, a stray, missing or wrong-typed member named by its path. Its
//! VALUES are refusals (VR-26 (8)): a cached sample is a fact, not a typo.

use serde::de::{self, Deserializer};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::export::describe;
use crate::model::{
    Action, Clip, DuringMotion, EdgeMotion, MediaKind, Project, Source, VideoProps,
};
use crate::outcome::Outcome;
use crate::recipe_matte::matte_target;
use crate::reframe::{
    fixed_framing, in_clip_time, plan_framing, FramingRequest, Subjects, WhereEmpty, FRAMING_TUNING,
};
use crate::reframe_tracks::{Follow, SubjectSample};
use crate::time::Ticks;

/// What a framing follows (VR-26).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FramingFollow {
    Subject,
    Face,
    Person,
    Salient,
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
            Self::Center | Self::Fit | Self::Keep => None,
        }
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
    pub subjects: Option<Subjects>,
}

/// Refusal (10)'s sentence (VR-26), which the tool matches to know a clip
/// waits only for its analysis (VR-28, `AgentServer+Framing.swift`).
pub fn no_subjects(clip: u32) -> String {
    format!("clip {clip} has no subjects to follow; analyze it first")
}

impl<'de> Deserialize<'de> for Subjects {
    /// `{samples: [{t, faces?, people?, salient?: [{x, y, w, h, c}]}], shots}`.
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct SubjectsIn {
            samples: Vec<SubjectSample>,
            shots: Vec<Ticks>,
        }
        let bad =
            |at: &str, what: String| de::Error::custom(format!("bad value at \"{at}\": {what}"));
        let value = Value::deserialize(deserializer)?;
        if !value.is_object() {
            return Err(de::Error::custom(format!(
                "expected an object, not {}",
                describe(&value)
            )));
        }
        // serde would read a list into a struct member by member.
        let samples = value["samples"]
            .as_array()
            .into_iter()
            .flatten()
            .enumerate();
        for (i, sample) in samples {
            let boxes = ["faces", "people", "salient"].into_iter().flat_map(|kind| {
                let list = sample[kind].as_array().into_iter().flatten().enumerate();
                list.map(move |(j, b)| (format!("subjects.samples[{i}].{kind}[{j}]"), b))
            });
            let here = std::iter::once((format!("subjects.samples[{i}]"), sample));
            if let Some((at, v)) = here.chain(boxes).find(|(_, v)| !v.is_object()) {
                return Err(bad(&at, format!("expected an object, not {}", describe(v))));
            }
        }
        let read: SubjectsIn = serde_path_to_error::deserialize(value).map_err(|e| {
            let at = crate::patch::path_under("subjects", &e.path().to_string());
            bad(&at, e.inner().to_string())
        })?;
        Ok(Subjects {
            samples: read.samples,
            shots: read.shots,
        })
    }
}

/// VR-26 (8): the samples' count, order, box counts and values.
fn check_subjects(subjects: &Subjects) -> Result<(), String> {
    let n = subjects.samples.len();
    if n > MAX_SUBJECT_SAMPLES {
        return Err(format!(
            "subjects holds {n} samples, more than {MAX_SUBJECT_SAMPLES}"
        ));
    }
    let mut previous: Option<Ticks> = None;
    for (i, sample) in subjects.samples.iter().enumerate() {
        if let Some(p) = previous.filter(|&p| sample.t <= p) {
            return Err(format!(
                "subjects sample {i} is at {}, not after the one before it ({p}); sample \
                 times must be strictly increasing",
                sample.t
            ));
        }
        previous = Some(sample.t);
        for (kind, list) in [
            ("faces", &sample.faces),
            ("people", &sample.people),
            ("salient", &sample.salient),
        ] {
            if list.len() > MAX_SUBJECT_BOXES {
                return Err(format!(
                    "subjects sample {i} holds {} {kind}, more than {MAX_SUBJECT_BOXES}",
                    list.len()
                ));
            }
            for (j, b) in list.iter().enumerate() {
                for (key, v) in [("x", b.x), ("y", b.y), ("w", b.w), ("h", b.h), ("c", b.c)] {
                    if !(0.0..=1.0).contains(&v) {
                        return Err(format!(
                            "subjects sample {i}'s {kind}[{j}].{key} is {v}, outside 0…1"
                        ));
                    }
                }
                for (key, v) in [("w", b.w), ("h", b.h)] {
                    if v <= 0.0 {
                        return Err(format!(
                            "subjects sample {i}'s {kind}[{j}].{key} is {v}; a box's size must \
                             be greater than 0"
                        ));
                    }
                }
            }
        }
    }
    Ok(())
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
        match self.refusal(&clip, r) {
            Some(why) => Ok(Outcome::Refused(why)),
            None => self.reframed(&clip, r),
        }
    }

    /// Refusals (1)–(6) and (8) of VR-26, in order ((7) removed by VR-27).
    fn refusal(&self, clip: &Clip, r: &Reframe) -> Option<String> {
        let id = clip.id;
        let keep = r.follow == FramingFollow::Keep;
        let following = r.follow.following().is_some();
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
                _ => {}
            }
        }
        if !keep {
            if let Some(why) = self.matte_refusal(clip) {
                return Some(why);
            }
            if let Some(why) = turn_refusal(id, clip, &video) {
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
        if r.follow == FramingFollow::Keep {
            let from = (r.from_width, r.from_height);
            let from = (from.0.unwrap_or(canvas.0), from.1.unwrap_or(canvas.1));
            return self.finish(self.kept(id, from));
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
