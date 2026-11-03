//! The cutout's rules on the model (format 39, spec §11 CO-20): the range
//! and quality checks `props_check.rs`'s `check_video` runs on
//! `video.cutout` ([`check_cutout`]); the clip-kind refusal and, since
//! format 41 (spec §11 CO-100), the foreground subject's refusal on a media
//! or still clip, both run by `edit_props.rs`'s `settle_video`, where the
//! clip is known ([`check_cutout_clip`]); the evaluator's clamp `actions_clamp.rs`'s
//! `clamp_video` runs on an action's end ([`clamp_cutout`], which never
//! fails, so the video group always decodes); and [`restore_base_cutout`],
//! `actions.rs`'s statement that the key's presence, `subject` and `quality`
//! are the clip's BASE values, beside motion's. And `video.behind_subject`'s
//! clip-kind refusal (format 40, spec §11 CO-52), run beside the cutout's in
//! `settle_video` ([`check_behind_subject_clip`]). And `video.hide_silent`'s
//! (format 43, spec §11 CO-92): its ranges ([`check_hide_silent`], in
//! `check_video`), its media and the nest refusal
//! ([`Project::check_hide_silent_clip`], in `settle_video`), and the base's
//! gate put back over an action's end beside the cutout's
//! ([`restore_base_video_keys`]).

use serde_json::{Map, Value};

use crate::actions_clamp::bounded;
use crate::evaluate::json;
use crate::model::{
    Clip, Cutout, CutoutQuality, CutoutSubject, HideSilent, Project, Source, VideoProps,
    CUTOUT_EDGE_MAX, CUTOUT_EDGE_MIN, CUTOUT_FEATHER_MAX, HIDE_SILENT_MAX,
};
use crate::props_check::{in_range, ticks_in_range};

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

/// A cutout on a clip that cannot take it, refused naming what the clip is
/// (CO-20): a `media`, `still` or `image` clip takes one (CO-100). Then the
/// subject: `foreground` is an image clip's only, and on a `media` or
/// `still` clip it is refused in its own sentence, checked after the kind
/// refusals so every other kind keeps its sentence. Fires only when `props`
/// carries a cutout.
pub(crate) fn check_cutout_clip(clip: &Clip, props: &VideoProps) -> Result<(), String> {
    let Some(cutout) = props.cutout else {
        return Ok(());
    };
    let what = match clip.source {
        Source::Image { .. } => return Ok(()),
        Source::Media { .. } => "a media clip",
        Source::Still { .. } => "a still clip",
        Source::Text => return Err(cannot_take(clip, "a text clip")),
        Source::Shape => return Err(cannot_take(clip, "a shape clip")),
        Source::Graphic => return Err(cannot_take(clip, "a graphic clip")),
        Source::Adjustment => return Err(cannot_take(clip, "an adjustment clip")),
        Source::Nest { .. } => {
            return Err(format!(
                "clip {} shows a nest and cannot take a cutout",
                clip.id
            ))
        }
    };
    if cutout.subject == CutoutSubject::Foreground {
        return Err(format!(
            "clip {} is {what} and cannot take a foreground cutout: only an image clip can",
            clip.id
        ));
    }
    Ok(())
}

/// CO-20's kind refusal, naming what the clip is.
fn cannot_take(clip: &Clip, what: &str) -> String {
    format!("clip {} is {what} and cannot take a cutout", clip.id)
}

/// `video.behind_subject` on a clip that cannot be cut by a subject,
/// refused naming what the clip is (CO-52): an adjustment clip draws no
/// picture of its own, and a nest clip never draws itself (its layers are
/// its contents'). Fires only when the flag is on.
pub(crate) fn check_behind_subject_clip(clip: &Clip, props: &VideoProps) -> Result<(), String> {
    if !props.behind_subject {
        return Ok(());
    }
    match clip.source {
        Source::Adjustment => Err(format!(
            "clip {} is an adjustment clip and cannot be put behind a subject",
            clip.id
        )),
        Source::Nest { .. } => Err(format!(
            "clip {} shows a nest and cannot be put behind a subject",
            clip.id
        )),
        _ => Ok(()),
    }
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

/// `video.hide_silent`'s three ranges (CO-91), each 0…5 s in
/// `ticks_in_range`'s sentence under its own key. No gate is nothing to
/// check.
pub(crate) fn check_hide_silent(gate: &Option<HideSilent>) -> Result<(), String> {
    let Some(gate) = gate else {
        return Ok(());
    };
    for (key, value) in [
        ("pre_roll", gate.pre_roll),
        ("hold", gate.hold),
        ("fade", gate.fade),
    ] {
        ticks_in_range(
            &format!("video.hide_silent.{key}"),
            value,
            0,
            HIDE_SILENT_MAX,
        )?;
    }
    Ok(())
}

impl Project {
    /// `video.hide_silent` on this clip (CO-92): the media named (0 is not),
    /// in the project, with sound; then a nest clip refused, since it never
    /// draws itself. Fires only when `props` carries a gate.
    pub(crate) fn check_hide_silent_clip(
        &self,
        clip: &Clip,
        props: &VideoProps,
    ) -> Result<(), String> {
        let Some(gate) = props.hide_silent else {
            return Ok(());
        };
        if gate.media == 0 {
            return Err(
                "video.hide_silent.media is required: the media whose speech the clip follows"
                    .to_string(),
            );
        }
        let Some(media) = self.media(gate.media) else {
            return Err(format!(
                "video.hide_silent.media {} is not a media of this project",
                gate.media
            ));
        };
        if !media.has_audio {
            return Err(format!(
                "video.hide_silent.media {} has no sound to follow",
                gate.media
            ));
        }
        if let Source::Nest { .. } = clip.source {
            return Err(format!(
                "clip {} shows a nest and cannot hide while silent: set it on the clips inside",
                clip.id
            ));
        }
        Ok(())
    }
}

/// The base's video keys no action may change, put back over the evaluated
/// state: the cutout's ([`restore_base_cutout`]) and the whole
/// `hide_silent` (CO-92) — the base's, or no key with none.
pub(crate) fn restore_base_video_keys(video: &mut Map<String, Value>, base: &VideoProps) {
    restore_base_cutout(video, base.cutout.as_ref());
    match &base.hide_silent {
        Some(gate) => {
            video.insert("hide_silent".to_string(), json(gate));
        }
        None => {
            video.shift_remove("hide_silent");
        }
    }
}
