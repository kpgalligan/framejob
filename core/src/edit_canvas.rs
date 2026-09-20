//! The document's canvas — spec §6, the `set_canvas` row.
//!
//! One op and the three things it has to do to the rest of the document
//! when it lands: check a dimension, rescale every clip's placement when
//! the size changes, and re-snap every stored time when the rate does.
//! `edit_track.rs` owns the track stack, the markers and the media list;
//! this file was cut out of it under the size rule and is the canvas half
//! of the same concern — the document's own shape rather than what sits
//! on it.
//!
//! The two rules worth knowing before reading:
//!
//! 1. **A canvas dimension is even**, because H.264 and HEVC encode in
//!    macroblocks over a chroma-subsampled plane. Catching it here makes
//!    it a message about the field the user just typed.
//! 2. **Nothing sub-frame may live in the model**, so a rate change
//!    re-snaps every clip, action and marker time to the new grid — and a
//!    coarser grid can land two markers on one tick, which markers may
//!    never share.

use crate::model::{Color, Project};
use crate::outcome::Outcome;
use crate::props_check::{color_ok, SCALE_MAX, SCALE_MIN};
use crate::time::{self, Fps, Ticks};

/// Canvas dimension bounds. The floor is small enough for a thumbnail-sized
/// document and large enough that the compositor has pixels to work with;
/// the ceiling is past 8K, where a single frame is already 130 MB.
///
/// `pub(crate)` because `op_table.rs` publishes this range as `width`'s and
/// `height`'s bound: the published bound is SOURCED from the constant the
/// refusal below is written against, never retyped beside it.
pub(crate) const CANVAS_MIN: u32 = 16;
pub(crate) const CANVAS_MAX: u32 = 16384;

// ---- helpers -------------------------------------------------------------

/// A canvas dimension: inside the bounds AND even.
///
/// Even is not fussiness: H.264 and HEVC encode in macroblocks over a
/// chroma-subsampled plane, so an odd width or height is either refused by
/// the encoder or silently padded. Catching it here makes it a message
/// about the canvas field the user just typed instead of an export that
/// fails an hour later.
fn check_dimension(key: &str, value: u32) -> Result<(), String> {
    if !(CANVAS_MIN..=CANVAS_MAX).contains(&value) {
        return Err(format!(
            "{key} must be between {CANVAS_MIN} and {CANVAS_MAX}, not {value}"
        ));
    }
    if !value.is_multiple_of(2) {
        return Err(format!(
            "{key} must be even (h.264 encodes in macroblocks), not {value}"
        ));
    }
    Ok(())
}

/// Multiplies every clip's placement by the canvas size ratio, so a layout
/// built for one canvas lands in the same relative place on the next (spec
/// §6, `rescale_clips`).
///
/// `x` and `y` are per-axis offsets in canvas pixels, so each follows its
/// OWN axis ratio — that is what keeps a layer's distance from an edge
/// proportional when the aspect ratio changes too. `scale` is one uniform
/// factor and cannot follow two ratios, so it follows the SMALLER of them:
/// the same `min` Fit uses, which means a layer that fitted the old canvas
/// still fits the new one, where the larger ratio could push it off an
/// edge.
///
/// Action `end` patches are deliberately NOT rescaled: a patch is opaque
/// JSON (`actions.rs` interprets it), and the op is defined on the clip's
/// props. An animated move on a resized canvas therefore keeps its old
/// target, which is visible and fixable, unlike a patch this function
/// half-understood and rewrote.
fn rescale(project: &mut Project, old_width: u32, old_height: u32) {
    if old_width == 0 || old_height == 0 {
        return;
    }
    let width_ratio = f64::from(project.canvas.width) / f64::from(old_width);
    let height_ratio = f64::from(project.canvas.height) / f64::from(old_height);
    if !(width_ratio.is_finite() && height_ratio.is_finite()) {
        return;
    }
    let scale_ratio = width_ratio.min(height_ratio);
    for clip in project.clips.iter_mut() {
        if let Some(video) = clip.video.as_mut() {
            video.x *= width_ratio;
            video.y *= height_ratio;
            // Clamped to the same range `set_video` accepts, so a chain of
            // shrinks cannot leave a scale the inspector refuses to show.
            video.scale = (video.scale * scale_ratio).clamp(SCALE_MIN, SCALE_MAX);
        }
    }
}

/// Re-snaps every stored time to the canvas's CURRENT frame grid, after
/// that grid has changed.
///
/// Nothing sub-frame may live in the model (spec §6), and yesterday's grid
/// is not today's: a 24 fps boundary is not a 30 fps boundary, so every
/// clip start and duration, every action span and every marker time has to
/// move to the nearest new boundary.
///
/// Three clamps keep the result valid: a media clip's duration is held to
/// the source it still has, snapped DOWN to the new grid, so a coarser rate
/// cannot round a whole-file clip past the end of its file (spec §11); a
/// duration that would round to zero becomes one frame (a zero-length clip
/// is what `validate` rejects), which is the ONE case the source bound
/// cannot hold and `evaluate.rs`'s clamp covers; and an action is kept
/// inside its clip.
fn resnap(project: &mut Project) {
    let fps = project.canvas.fps;
    let frame = project.frame();
    // By index: the source bound is read off the PROJECT (the clip's media)
    // while the clip itself is about to be mutated.
    for index in 0..project.clips.len() {
        let available = project
            .source_length(&project.clips[index])
            .map(|length| time::snap_down_to_frame(length, fps));
        let clip = &mut project.clips[index];
        clip.start = time::snap_to_frame(clip.start, fps).max(0);
        clip.duration = time::snap_to_frame(clip.duration, fps).max(frame);
        if let Some(available) = available {
            clip.duration = clip.duration.min(available).max(frame);
        }
        let last_start = clip.duration.saturating_sub(frame).max(0);
        for action in clip.actions.iter_mut() {
            action.start = time::snap_to_frame(action.start, fps).clamp(0, last_start);
            action.duration = time::snap_to_frame(action.duration, fps)
                .max(frame)
                .min(clip.duration.saturating_sub(action.start))
                .max(1);
        }
    }
    for marker in project.markers.iter_mut() {
        marker.time = time::snap_to_frame(marker.time, fps).max(0);
    }
    // A coarser grid can land two markers on one tick, which markers may
    // never share. The alternative — refusing a document-wide rate change
    // because two marks are 3 ms apart — is far worse than dropping the
    // second of them, so the first in the list keeps the tick.
    //
    // A linear scan over a `Vec` rather than a set: markers are capped at
    // 1024 and this runs only on a rate change.
    let mut taken: Vec<Ticks> = Vec::with_capacity(project.markers.len());
    project.markers.retain(|marker| {
        if taken.contains(&marker.time) {
            false
        } else {
            taken.push(marker.time);
            true
        }
    });
}

// ---- the op --------------------------------------------------------------

impl Project {
    /// Sets any subset of the document's canvas fields (spec §6). An
    /// omitted argument keeps its value.
    ///
    /// `rescale_clips` multiplies every clip's `x`, `y` and `scale` by the
    /// size ratio (see [`rescale`]) so a finished layout survives a resize.
    /// Changing `fps` re-snaps EVERY stored time to the new grid — clip
    /// starts and durations, action spans, marker times (see [`resnap`]) —
    /// because nothing sub-frame may live in the model.
    ///
    /// `Err` for a dimension outside 16..16384 or odd (H.264 needs even
    /// dimensions), a frame rate with a zero term, or a background channel
    /// outside 0..1.
    ///
    /// The rate change is deliberately NOT re-checked against the overlap
    /// rule: re-snapping moves each edge by less than one frame, so an
    /// overlap can grow by at most a frame, and refusing a document-wide
    /// rate change over a one-frame drift would be worse than the drift.
    #[allow(clippy::too_many_arguments)]
    // The argument list IS the op's argument list (spec §6); a struct would
    // hold exactly the same seven optional fields and one more name.
    pub fn set_canvas(
        &self,
        width: Option<u32>,
        height: Option<u32>,
        fps: Option<Fps>,
        background: Option<Color>,
        rescale_clips: bool,
        fit_new_clips: Option<bool>,
        timecode_frames: Option<bool>,
    ) -> Result<Outcome, String> {
        let width = match width {
            None => self.canvas.width,
            Some(given) => {
                check_dimension("canvas width", given)?;
                given
            }
        };
        let height = match height {
            None => self.canvas.height,
            Some(given) => {
                check_dimension("canvas height", given)?;
                given
            }
        };
        let fps = match fps {
            None => self.canvas.fps,
            Some(given) if given.is_valid() => given,
            Some(given) => {
                return Err(format!(
                    "canvas fps must be [num, den] with non-zero terms, not [{}, {}]",
                    given.num, given.den
                ))
            }
        };
        if let Some(background) = background.as_ref() {
            color_ok("canvas background", background)?;
        }

        let mut next = self.clone();
        next.canvas.width = width;
        next.canvas.height = height;
        next.canvas.fps = fps;
        if let Some(background) = background {
            next.canvas.background = background;
        }
        if let Some(fit_new_clips) = fit_new_clips {
            next.canvas.fit_new_clips = fit_new_clips;
        }
        if let Some(timecode_frames) = timecode_frames {
            next.canvas.timecode_frames = timecode_frames;
        }

        let resized = width != self.canvas.width || height != self.canvas.height;
        if rescale_clips && resized {
            rescale(&mut next, self.canvas.width, self.canvas.height);
        }
        if fps != self.canvas.fps {
            resnap(&mut next);
        }
        self.finish(next)
    }
}
