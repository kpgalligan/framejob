//! Frame-grid normalization shared by clip transfer and canvas edits.

use crate::model::{Clip, Project};

/// Re-snaps a clip's actions onto this project's frame grid and
/// clamps them inside its (already re-snapped) duration.
///
/// The same clamps serve canvas, paste and unnest: yesterday's grid is not
/// today's, a
/// duration that rounds to zero is what `validate` rejects, and an action
/// must still fit the clip it is on.
pub(crate) fn resnap_actions(project: &Project, clip: &mut Clip) {
    let frame = project.frame();
    let last_start = clip.duration.saturating_sub(frame).max(0);
    for action in clip.actions.iter_mut() {
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
    /// clocks and are deliberately left alone.
    pub(crate) fn resnap_clip_times(&self, clip: &mut Clip) {
        clip.start = self.snapped(clip.start).max(0);
        clip.duration = self.duration_resnapped(clip);
        resnap_actions(self, clip);
        if let Some(video) = clip.video.as_mut() {
            self.snap_motion(video);
        }
        if let Some(text) = clip.text.as_mut() {
            self.snap_animation(text);
        }
    }
}
