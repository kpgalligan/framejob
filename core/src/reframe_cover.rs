//! A framing written as an edit (road map "creator-jobs" VR2a2 and VR2b1,
//! spec §11 VR-25…VR-27): `keep`'s rescale and the blurred backdrop behind
//! a `fit` span; the path itself is composed into the clip by
//! `reframe_compose.rs`. Pure: each answers a new project and
//! `edit_reframe.rs`'s op decides, checks and finishes.
//!
//! **`keep`** (VR-26, VR-27 (h)) is `set_canvas`'s rescale rule on the
//! clip's base and on every end key among `x`, `y` and `scale` that the end
//! names, through `rescale_video` itself.
//!
//! **The backdrop** (VR-25) is ONE copy of the original clip by
//! `add_blurred_background`'s builder, spanning the whole clip, because the
//! eases into and out of `fit` need it as much as the span itself. It goes
//! on the named track when that track can take it — unlocked, not a matte,
//! no clip intersecting the clip's span (touching is allowed) — and on a new
//! back-most track otherwise, so the op never refuses for a busy track. It
//! keeps the original's actions that name `speed`, each end narrowed to
//! `speed`, so a ramped clip's copy reads the same frames (VR-27 (i)).

use serde_json::{Map, Value};

use crate::edit_canvas::rescale_video;
use crate::model::{Action, Clip, Project, VideoProps};

impl Project {
    /// `keep` (VR-26, VR-27 (h)): `set_canvas`'s rescale rule on the clip's
    /// base and on each `x`, `y` and `scale` an action's end names, from a
    /// `from` canvas to the current one.
    pub(crate) fn kept(&self, clip: u32, from: (u32, u32)) -> Project {
        let mut next = self.clone();
        let (w, h) = (
            f64::from(next.canvas.width) / f64::from(from.0),
            f64::from(next.canvas.height) / f64::from(from.1),
        );
        let Some(target) = next.clips.iter_mut().find(|c| c.id == clip) else {
            return next;
        };
        if !(w.is_finite() && h.is_finite()) {
            return next;
        }
        if let Some(video) = target.video.as_mut() {
            rescale_video(video, w, h);
        }
        for action in &mut target.actions {
            let Some(Value::Object(end)) = action.end.get_mut("video") else {
                continue;
            };
            let read = |key: &str| end.get(key).and_then(Value::as_f64);
            let mut video = VideoProps::default();
            video.scale = read("scale").unwrap_or(video.scale);
            video.x = read("x").unwrap_or(video.x);
            video.y = read("y").unwrap_or(video.y);
            rescale_video(&mut video, w, h);
            for (key, value) in [("scale", video.scale), ("x", video.x), ("y", video.y)] {
                if end.get(key).is_some_and(Value::is_number) {
                    end.insert(key.to_string(), Value::from(value));
                }
            }
        }
        next
    }

    /// The backdrop of VR-25: one blurred copy of `original` on `backdrop`
    /// when that track can take it, else on a new back-most track (the
    /// module doc), with the original's speed actions (VR-27 (i)), their ids
    /// after the copy's. The op has refused a nest and a track not behind
    /// the clip's before calling, so the `Err` is `blurred_copy`'s own and
    /// not reached in practice.
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
        let mut copy = next.blurred_copy(original, id, track)?;
        for a in original.actions.iter() {
            let Some(speed) = a.end.get("speed") else {
                continue;
            };
            let mut end = Map::new();
            end.insert("speed".to_string(), speed.clone());
            copy.actions.push(Action {
                id: next.allocate_id(),
                end: Value::Object(end),
                ..a.clone()
            });
        }
        next.clips.push(copy);
        Ok(next)
    }
}
