//! The cutout's rules on the model (format 39, spec §11 CO-20): the range
//! and quality checks `props_check.rs`'s `check_video` runs on
//! `video.cutout` ([`check_cutout`]); the clip-kind refusal
//! `edit_props.rs`'s `settle_video` runs, where the clip is known
//! ([`check_cutout_clip`]); the evaluator's clamp `actions_clamp.rs`'s
//! `clamp_video` runs on an action's end ([`clamp_cutout`], which never
//! fails, so the video group always decodes); and [`restore_base_cutout`],
//! `actions.rs`'s statement that the key's presence, `subject` and `quality`
//! are the clip's BASE values, beside motion's.

use serde_json::{Map, Value};

use crate::actions_clamp::bounded;
use crate::evaluate::json;
use crate::model::{
    Clip, Cutout, CutoutQuality, Source, VideoProps, CUTOUT_EDGE_MAX, CUTOUT_EDGE_MIN,
    CUTOUT_FEATHER_MAX,
};
use crate::props_check::in_range;

/// `video.cutout`'s ranges, each refused in `in_range`'s sentence under its
/// own key, then `best`, which the vocabulary holds and no op may set until
/// Best masks are made (CO-20). No cutout is nothing to check.
pub(crate) fn check_cutout(cutout: &Option<Cutout>) -> Result<(), String> {
    let Some(cutout) = cutout else {
        return Ok(());
    };
    in_range(
        "video.cutout.edge",
        cutout.edge,
        CUTOUT_EDGE_MIN,
        CUTOUT_EDGE_MAX,
    )?;
    in_range(
        "video.cutout.feather",
        cutout.feather,
        0.0,
        CUTOUT_FEATHER_MAX,
    )?;
    if cutout.quality != CutoutQuality::Standard {
        return Err(
            "video.cutout.quality must be standard: Best masks are not made yet".to_string(),
        );
    }
    Ok(())
}

/// A cutout on a clip whose picture is not a media's frames, refused naming
/// what the clip is (CO-20): only a `media` or `still` clip takes one
/// (images until CO10). Fires only when `props` carries a cutout.
pub(crate) fn check_cutout_clip(clip: &Clip, props: &VideoProps) -> Result<(), String> {
    if props.cutout.is_none() {
        return Ok(());
    }
    let what = match clip.source {
        Source::Media { .. } | Source::Still { .. } => return Ok(()),
        Source::Text => "a text clip",
        Source::Shape => "a shape clip",
        Source::Graphic => "a graphic clip",
        Source::Adjustment => "an adjustment clip",
        Source::Image { .. } => "an image clip",
        Source::Nest { .. } => {
            return Err(format!(
                "clip {} shows a nest and cannot take a cutout",
                clip.id
            ))
        }
    };
    Err(format!(
        "clip {} is {what} and cannot take a cutout",
        clip.id
    ))
}

/// An evaluated cutout brought into its ranges (CO-20): `edge` to −1…1 and
/// `feather` to 0…1, NaN to 0. Never fails.
pub(crate) fn clamp_cutout(cutout: &mut Option<Cutout>) {
    let Some(cutout) = cutout.as_mut() else {
        return;
    };
    cutout.edge = bounded(cutout.edge, CUTOUT_EDGE_MIN, CUTOUT_EDGE_MAX, 0.0);
    cutout.feather = bounded(cutout.feather, 0.0, CUTOUT_FEATHER_MAX, 0.0);
}

/// The base's cutout put back over the evaluated `video` state (CO-20), at
/// the `Value` level for motion's reason (`actions.rs`): with no base
/// cutout the state's is `null`, whatever an end carried; with one and an
/// object in the state, that object takes the base's `subject` and
/// `quality`, keeping its `edge`, `feather` and `background`; with one and
/// anything else there (an end's hand-written `null`), the base's whole.
pub(crate) fn restore_base_cutout(video: &mut Map<String, Value>, base: Option<&Cutout>) {
    let Some(base) = base else {
        video.insert("cutout".to_string(), Value::Null);
        return;
    };
    match video.get_mut("cutout") {
        Some(Value::Object(state)) => {
            state.insert("subject".to_string(), json(&base.subject));
            state.insert("quality".to_string(), json(&base.quality));
        }
        _ => {
            video.insert("cutout".to_string(), json(base));
        }
    }
}
