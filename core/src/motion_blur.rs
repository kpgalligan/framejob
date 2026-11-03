//! Motion blur's vocabulary (format 42, spec §11 CU-110…CU-114): the one
//! sample count, `video.motion_blur`'s range check, its clamp, the clips
//! that cannot take it, and the shutter's sub-frame offsets.
//!
//! `video.motion_blur` is the shutter as a fraction of one CANVAS frame,
//! 0…1, 0 off (CU-113). The shutter is centred on the frame's instant: its
//! N samples sit at round(((2k+1−N)/(2N))·s·F) ticks from it, k = 0…N−1
//! ascending, F the canvas's frame in ticks, and its ends at ∓round(s·F/2)
//! (CU-114). One N, [`MOTION_BLUR_SAMPLES`], serves the preview,
//! `render_frame` and every export (CU-112): spike CU-S5 chose it (CU-110).
//! `recipe_blur.rs` turns the offsets into a layer's `blur` key.

use crate::model::{Clip, Source, VideoProps};
use crate::props_check::in_range;
use crate::time::{Fps, Ticks, TIMESCALE};

/// How many sub-frame placements a blurred layer is drawn at (spec §11
/// CU-110: CU-S5's N, the largest of 16, 8 and 4 within its bounds).
pub const MOTION_BLUR_SAMPLES: usize = 16;

/// `video.motion_blur`'s range (CU-113): "video.motion_blur must be between
/// 0 and 1, not 1.5".
pub(crate) fn check_motion_blur(value: f64) -> Result<(), String> {
    in_range("video.motion_blur", value, 0.0, 1.0)
}

/// An evaluated `motion_blur` brought into 0…1, NaN to 0 (an action's end is
/// checked for its keys, not its values). Never fails.
pub(crate) fn clamp_motion_blur(value: f64) -> f64 {
    if value.is_nan() {
        0.0
    } else {
        value.clamp(0.0, 1.0)
    }
}

/// `video.motion_blur` above 0 on a clip that cannot take it, refused naming
/// what the clip is (CU-111): a nest clip never draws itself (its layers are
/// its contents', each with its own blur), and an adjustment clip draws no
/// picture to move. 0 is always accepted.
pub(crate) fn check_motion_blur_clip(clip: &Clip, props: &VideoProps) -> Result<(), String> {
    if props.motion_blur <= 0.0 {
        return Ok(());
    }
    match clip.source {
        Source::Nest { .. } => Err(format!(
            "clip {} shows a nest and cannot take motion blur: set it on the clips inside",
            clip.id
        )),
        Source::Adjustment => Err(format!(
            "clip {} is an adjustment clip and cannot take motion blur",
            clip.id
        )),
        _ => Ok(()),
    }
}

/// The shutter's [`MOTION_BLUR_SAMPLES`] centred offsets from the frame's
/// instant, ascending, and its two ends, for a shutter of `shutter` frames at
/// `fps` (CU-114). F = TIMESCALE·den/num as f64; a degenerate rate has no
/// frame, so every offset is 0.
pub(crate) fn shutter_offsets(fps: Fps, shutter: f64) -> (Vec<Ticks>, (Ticks, Ticks)) {
    let frame = if fps.is_valid() {
        TIMESCALE as f64 * f64::from(fps.den) / f64::from(fps.num)
    } else {
        0.0
    };
    let span = shutter * frame;
    let n = MOTION_BLUR_SAMPLES as f64;
    let offsets = (0..MOTION_BLUR_SAMPLES)
        .map(|k| ((2.0 * k as f64 + 1.0 - n) / (2.0 * n) * span).round() as Ticks)
        .collect();
    let half = (span / 2.0).round() as Ticks;
    (offsets, (-half, half))
}
