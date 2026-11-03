//! A framing written as an edit (road map "creator-jobs" VR2a2, spec §11
//! VR-25, VR-26): `reframe.rs`'s path as the clip's base and actions,
//! `keep`'s rescale, and the blurred backdrop behind a `fit` span. Pure:
//! each answers a new project and `edit_reframe.rs`'s op decides, checks
//! and finishes.
//!
//! **The path F as placement.** A key `(k, dx, dy)` composes into the
//! clip's own base `video` as `scale′ = k·scale`, `x′ = k·x + dx`,
//! `y′ = k·y + dy` (VR-20, VR-3). Key 0 becomes the base; each later key whose value
//! differs from the one before becomes ONE action spanning from the previous
//! key to it, with its curve and the end `{"video": {"scale", "x", "y"}}`,
//! so the clip eases exactly as the path does (`actions::ease` both sides).
//! A hold key followed by an equal one makes no action. Every value is the
//! raw composed number: the core never rounds a placement.
//!
//! **The backdrop** (VR-25) is ONE copy of the original clip by
//! `add_blurred_background`'s builder, spanning the whole clip, because the
//! eases into and out of `fit` need it as much as the span itself. It goes
//! on the named track when that track can take it — unlocked, not a matte,
//! no clip intersecting the clip's span (touching is allowed) — and on a new
//! back-most track otherwise, so the op never refuses for a busy track.

use serde_json::json;

use crate::edit_canvas::rescale_video;
use crate::model::{Action, Clip, Project, VideoProps};
use crate::reframe::{FramingKey, FramingPath};

/// `key` composed into `base`: (scale, x, y).
fn composed(key: &FramingKey, base: &VideoProps) -> (f64, f64, f64) {
    (
        key.scale * base.scale,
        key.scale * base.x + key.x,
        key.scale * base.y + key.y,
    )
}

impl Project {
    /// `clip` with `path` written as its base and actions (the module doc),
    /// ids minted in the actions' time order. The clip carries no actions
    /// (VR-26 (7)), so its list is replaced.
    pub(crate) fn framed(&self, clip: u32, path: &FramingPath) -> Project {
        let mut next = self.clone();
        let (Some(index), Some(first)) = (
            next.clips.iter().position(|c| c.id == clip),
            path.keys.first(),
        ) else {
            return next;
        };
        let base = next.clips[index].video.clone().unwrap_or_default();
        let (scale, x, y) = composed(first, &base);
        let mut actions = Vec::new();
        for pair in path.keys.windows(2) {
            let (from, to) = (&pair[0], &pair[1]);
            if (from.scale, from.x, from.y) == (to.scale, to.x, to.y) {
                continue;
            }
            let (s, x, y) = composed(to, &base);
            actions.push(Action {
                id: next.allocate_id(),
                start: from.t,
                duration: to.t - from.t,
                curve: to.curve,
                end: json!({"video": {"scale": s, "x": x, "y": y}}),
            });
        }
        let target = &mut next.clips[index];
        target.video = Some(VideoProps {
            scale,
            x,
            y,
            ..base
        });
        target.actions = actions;
        next
    }

    /// `keep` (VR-26): `set_canvas`'s rescale rule on the clip's base, from
    /// a `from` canvas to the current one. Its actions stay as they are.
    pub(crate) fn kept(&self, clip: u32, from: (u32, u32)) -> Project {
        let mut next = self.clone();
        let (w, h) = (
            f64::from(next.canvas.width) / f64::from(from.0),
            f64::from(next.canvas.height) / f64::from(from.1),
        );
        if let Some(video) = next
            .clips
            .iter_mut()
            .find(|c| c.id == clip)
            .and_then(|c| c.video.as_mut())
        {
            if w.is_finite() && h.is_finite() {
                rescale_video(video, w, h);
            }
        }
        next
    }

    /// The backdrop of VR-25: one blurred copy of `original` on `backdrop`
    /// when that track can take it, else on a new back-most track (the
    /// module doc). The op has refused a nest and a track not behind the
    /// clip's before calling, so the `Err` is `blurred_copy`'s own and not
    /// reached in practice.
    pub(crate) fn with_backdrop(self, original: &Clip, backdrop: u32) -> Result<Project, String> {
        let (start, end) = (original.start, original.start + original.duration);
        let free = self
            .track(backdrop)
            .is_some_and(|t| !t.locked && t.matte.is_none())
            && !self
                .clips
                .iter()
                .any(|c| c.track == backdrop && c.start < end && c.start + c.duration > start);
        let (mut next, track) = if free {
            (self, backdrop)
        } else {
            self.with_back_track()
        };
        let id = next.allocate_id();
        let copy = next.blurred_copy(original, id, track)?;
        next.clips.push(copy);
        Ok(next)
    }
}
