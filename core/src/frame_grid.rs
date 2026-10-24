//! Frame-grid normalization shared by clip transfer and canvas edits.

use crate::model::{Clip, Project};
use crate::recipe_graphic::graphic_resnapped;
use crate::speed_map::{end_speed, is_ramped};

/// Re-snaps a clip's actions onto this project's frame grid and
/// clamps them inside its (already re-snapped) duration.
///
/// The same clamps serve canvas, paste and unnest: yesterday's grid is not
/// today's, a
/// duration that rounds to zero is what `validate` rejects, and an action
/// must still fit the clip it is on.
///
/// On a RAMPED clip a SPEED action is snapped but not clamped into the
/// clip: one running past the end keeps running past it, as `trim_end`
/// leaves it, so S∞ and what the clip reads by its end are kept up to the
/// grid's rounding (spec §11 SR-19 (g)). Every other action clamps.
pub(crate) fn resnap_actions(project: &Project, clip: &mut Clip) {
    let frame = project.frame();
    let last_start = clip.duration.saturating_sub(frame).max(0);
    let ramped = is_ramped(clip);
    for action in clip.actions.iter_mut() {
        if ramped && end_speed(action).is_some() {
            action.start = project.snapped(action.start).max(0);
            action.duration = project.snapped(action.duration).max(frame).max(1);
            continue;
        }
        action.start = project.snapped(action.start).clamp(0, last_start);
        action.duration = project
            .snapped(action.duration)
            .max(frame)
            .min(clip.duration.saturating_sub(action.start))
            .max(1);
    }
}

impl Project {
    /// Normalize one clip after its source IDs and caller-specific placement
    /// have been resolved. Source positions and audio envelopes are separate
    /// clocks and are deliberately left alone; a graphic's `in` and `length`
    /// are the canvas's frames, so they re-snap through `graphic_resnapped`
    /// (spec §11 G-18·b).
    ///
    /// A RAMPED clip's duration is held a second time, against its
    /// re-snapped speed actions, whose new grid can make it read more, and
    /// its other actions are re-clamped into what is left (spec §11 SR-19
    /// (g)).
    pub(crate) fn resnap_clip_times(&self, clip: &mut Clip) {
        clip.start = self.snapped(clip.start).max(0);
        clip.duration = self.duration_resnapped(clip);
        resnap_actions(self, clip);
        if is_ramped(clip) {
            clip.duration = self.duration_resnapped(clip);
            resnap_actions(self, clip);
        }
        if let Some(video) = clip.video.as_mut() {
            self.snap_motion(video);
        }
        if let Some(text) = clip.text.as_mut() {
            self.snap_animation(text);
        }
        clip.graphic = graphic_resnapped(clip.graphic.as_ref(), self);
    }
}
