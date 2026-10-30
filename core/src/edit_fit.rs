//! The two scales a new clip can be placed at — Fit and Fill — and nothing
//! else.
//!
//! Cut out of `edit_clip.rs` under the size rule, a pure move (road map
//! "audio" AP9's toll, `designs/adr/core-file-history.md`): `edit_clip.rs`
//! decides where a clip sits, and these two decide how big a new one is
//! drawn. Fit is a RESCUE for oversized footage and honours
//! `canvas.fit_new_clips`; Fill is a REQUIREMENT, ignores it, scales up as
//! readily as down and clamps to `SCALE_MAX`.

use crate::model::Project;
use crate::props_check::{SCALE_MAX, SCALE_MIN};

impl Project {
    /// Fit scale for a new clip: `min(cw/sw, ch/sh)` when `fit_new_clips`
    /// is on and the source exceeds the canvas, else 1 (spec §5.3). A
    /// source that already fits is never scaled UP — Fit is a rescue for
    /// oversized footage, not a stretch.
    pub(crate) fn fit_scale(&self, source_width: f64, source_height: f64) -> f64 {
        if !(self.canvas.fit_new_clips && source_width > 0.0 && source_height > 0.0) {
            return 1.0;
        }
        let canvas_width = f64::from(self.canvas.width);
        let canvas_height = f64::from(self.canvas.height);
        if source_width <= canvas_width && source_height <= canvas_height {
            return 1.0;
        }
        let scale = (canvas_width / source_width).min(canvas_height / source_height);
        if scale.is_finite() {
            scale.clamp(SCALE_MIN, SCALE_MAX)
        } else {
            1.0
        }
    }

    /// Fill scale: `max(cw/sw, ch/sh)`, the smallest scale that leaves no
    /// canvas showing — [`Project::fit_scale`]'s sibling, and what
    /// `edit_background.rs` gives a backdrop.
    ///
    /// Three differences from Fit, all of them one difference read three
    /// ways: Fit is a RESCUE for oversized footage and Fill is a
    /// REQUIREMENT. So it ignores `canvas.fit_new_clips` — a backdrop that
    /// leaves a bar down the side has failed at its one job whatever that
    /// flag says; it scales UP as readily as down, a source smaller than the
    /// canvas being exactly the case that needs it; and it clamps HERE, so
    /// no caller can store a scale `check_video` would refuse. The clamp's
    /// visible cost is `edit_zoom.rs`'s, for the same constant: on a
    /// 1920-wide canvas a source under 192 pixels cannot reach the edge, and
    /// what comes back is the biggest legal magnification rather than a
    /// refusal. A degenerate source has no ratio to take and answers 1;
    /// callers refuse one by name before they ever reach this.
    pub(crate) fn fill_scale(&self, source_width: f64, source_height: f64) -> f64 {
        let scale = (f64::from(self.canvas.width) / source_width)
            .max(f64::from(self.canvas.height) / source_height);
        if scale.is_finite() && scale > 0.0 {
            scale.clamp(SCALE_MIN, SCALE_MAX)
        } else {
            1.0
        }
    }
}
