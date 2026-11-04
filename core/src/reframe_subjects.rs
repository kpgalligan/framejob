//! `reframe_clip`'s `subjects` argument (road map "creator-jobs" VR2a2,
//! spec §11 VR-26): the analysed samples and shots of a clip's media, in
//! MEDIA source ticks of the forward file, read strictly and checked. A pure
//! move out of `reframe.rs` (the type) and `edit_reframe.rs` (its reader and
//! check), so the cursor's points (VR5) land beside them.
//!
//! **The cursor** (VR5, spec §11 VR-50): `cursor`, optional, is a recorded
//! pointer's points `{t, x, y, click?, typing?}` — `t` in forward-media
//! source ticks, `x`, `y` 0…1 of the upright picture from its top-left
//! (CJ-22), `click` a down click and `typing` inside a typing stretch, both
//! false when absent — which `follow: cursor` frames on
//! (`reframe_cursor.rs`). A face follow never reads it (VR-51).
//!
//! **`subjects` is read strictly**, as `ZoomRegion` is: an object at every
//! level, a stray, missing or wrong-typed member named by its path. Its
//! VALUES are refusals (VR-26 (8)): a cached sample is a fact, not a typo.

use serde::de::{self, Deserializer};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::edit_reframe::{MAX_SUBJECT_BOXES, MAX_SUBJECT_SAMPLES};
use crate::export::describe;
use crate::reframe_tracks::SubjectSample;
use crate::time::Ticks;

/// One recorded cursor point (spec §11 VR-50): media source ticks of the
/// forward file, 0…1 of the upright picture.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CursorPoint {
    pub t: Ticks,
    pub x: f64,
    pub y: f64,
    #[serde(default)]
    pub click: bool,
    #[serde(default)]
    pub typing: bool,
}

/// A clip's analysed subjects in MEDIA source ticks of the forward file.
/// `reframe_clip`'s `subjects` argument; its strict `Deserialize` is below.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Subjects {
    pub samples: Vec<SubjectSample>,
    pub shots: Vec<Ticks>,
    /// The recorded cursor (VR-50), empty when absent.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub cursor: Vec<CursorPoint>,
}

impl<'de> Deserialize<'de> for Subjects {
    /// `{samples: [{t, faces?, people?, salient?: [{x, y, w, h, c}]}], shots,
    /// cursor?: [{t, x, y, click?, typing?}]}`.
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct SubjectsIn {
            samples: Vec<SubjectSample>,
            shots: Vec<Ticks>,
            #[serde(default)]
            cursor: Vec<CursorPoint>,
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
        let points = value["cursor"].as_array().into_iter().flatten().enumerate();
        for (i, point) in points {
            if !point.is_object() {
                let at = format!("subjects.cursor[{i}]");
                return Err(bad(
                    &at,
                    format!("expected an object, not {}", describe(point)),
                ));
            }
        }
        let read: SubjectsIn = serde_path_to_error::deserialize(value).map_err(|e| {
            let at = crate::patch::path_under("subjects", &e.path().to_string());
            bad(&at, e.inner().to_string())
        })?;
        Ok(Subjects {
            samples: read.samples,
            shots: read.shots,
            cursor: read.cursor,
        })
    }
}

/// VR-26 (8): the samples' count, order, box counts and values; then the
/// cursor's count, order and values (VR-50).
pub(crate) fn check_subjects(subjects: &Subjects) -> Result<(), String> {
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
    check_cursor(&subjects.cursor)
}

/// VR-50's three refusals, each naming `cursor[i]`.
fn check_cursor(points: &[CursorPoint]) -> Result<(), String> {
    let n = points.len();
    if n > MAX_SUBJECT_SAMPLES {
        return Err(format!(
            "subjects holds {n} cursor points, more than {MAX_SUBJECT_SAMPLES}"
        ));
    }
    let mut previous: Option<Ticks> = None;
    for (i, point) in points.iter().enumerate() {
        if let Some(p) = previous.filter(|&p| point.t <= p) {
            return Err(format!(
                "subjects cursor[{i}] is at {}, not after the one before it ({p}); cursor \
                 times must be strictly increasing",
                point.t
            ));
        }
        previous = Some(point.t);
        for (key, v) in [("x", point.x), ("y", point.y)] {
            if !(0.0..=1.0).contains(&v) {
                return Err(format!("subjects cursor[{i}].{key} is {v}, outside 0…1"));
            }
        }
    }
    Ok(())
}
