//! `switch_layout` — a camera clip and the screen behind it laid out at the
//! playhead (road map "creator-jobs" CO6, spec §11 CO-61, CO-62, CO-64).
//! One op, so Clip ▸ Camera Layout ▸ is one undo step, "Camera Layout".
//! The geometry is `layout.rs`'s; this file is who is laid out, how far,
//! and what refuses.
//!
//! - **The roles** (CO-64): the camera, playing at `at` with a picture; the
//!   screen given (on a track behind) or found — the clip playing at `at`
//!   on the front-most visible, non-matte track behind the camera's with a
//!   drawn picture. No screen refuses `side_by_side` and `stacked`; the
//!   other three lay out the camera alone.
//! - **The switch** (CO-61): per role, the clip under `at` gets a LAYOUT
//!   ACTION (all six placement keys) at clip time `at − start`, 0.5 s and
//!   `ease_in_out` unless told, clamped to the clip and to its next later
//!   layout action, at least one frame; at its first frame the layout is
//!   its base and a one-frame layout action ends there (a cut). A layout
//!   action starting at `at` is replaced; one running at `at` is shortened
//!   to end there. The REACH (`edit_layout_reach.rs`) gives every later
//!   picture clip on the role's track starting before the next layout
//!   action, `through` or the track's end the layout as its base.
//! - **The refusals** (CO-62), in order: the camera, the screen, a nest
//!   clip asked for a radius it cannot draw, a mover — a non-layout action
//!   that moves a role clip and ends after `at` (a full-placement screen
//!   exempt in the three layouts that leave it full) — then a shape or
//!   graphic role or reach clip the layout would crop (off a matte track)
//!   or round, checked once every placement is solved and before any write
//!   (spec §11 #524) — then whatever the composed ops say. `nest: true` nests the moving role's clips first and
//!   lays out the nest clip, unless one of them is already laid out.
//!
//! Composed from `remove_action`, `set_action`, `add_action`,
//! `set_action_end`, `set_video` and `nest_clips`, each refusal inherited in
//! its own words.

use std::collections::HashSet;

use serde_json::json;

use crate::action_class::is_layout;
use crate::edit_adjustment::is_adjustment;
use crate::edit_clip::clip_end;
use crate::edit_layout_reach::{Role, RoleKind};
use crate::edit_props::described_kind;
use crate::layout::{
    camera_placement, screen_placement, CameraLayout, LayoutChoice, LayoutCorner, LayoutShape,
    Placement, DEFAULT_SWITCH,
};
use crate::model::{Clip, Crop, Curve, Project, Source};
use crate::outcome::Outcome;
use crate::time::{format_timecode, Ticks};

/// `switch_layout`'s arguments, in the op's row order (`edit.rs`).
#[derive(Debug, Clone, PartialEq)]
pub struct LayoutSwitch {
    pub camera: u32,
    pub screen: Option<u32>,
    pub layout: CameraLayout,
    pub shape: Option<LayoutShape>,
    pub corner: Option<LayoutCorner>,
    pub at: Ticks,
    pub duration: Option<Ticks>,
    pub curve: Option<Curve>,
    pub focus: Option<[f64; 2]>,
    pub nest: Option<bool>,
    pub through: Option<Ticks>,
}

/// One role's writes: the clip under `at`, `at` in its clip time, its
/// layout action's end, and each later reach clip's new base.
type RoleWrites = (u32, Ticks, Placement, Vec<(u32, Placement)>);

/// One composed step: the project it applied, unchanged on an identity,
/// or the refusal handed straight back.
macro_rules! step {
    ($next:ident, $call:expr) => {
        match $call? {
            Outcome::Applied(applied) => $next = applied,
            Outcome::Identity => {}
            Outcome::Refused(why) => return Ok(Outcome::Refused(why)),
        }
    };
}

impl Project {
    /// Whether `clip` has a picture to lay out: a video group and a source
    /// size (CO-64).
    pub(crate) fn has_layout_picture(&self, clip: &Clip) -> bool {
        clip.video.is_some() && self.source_size(clip).is_some()
    }

    /// `at` as a timecode, for a sentence.
    pub(crate) fn layout_timecode(&self, t: Ticks) -> String {
        format_timecode(t, self.canvas.fps, self.canvas.timecode_frames)
    }

    /// Lays out `s.camera` and its screen at `s.at` (this module's doc).
    pub fn switch_layout(&self, s: &LayoutSwitch) -> Result<Outcome, String> {
        let at = self.snapped(s.at);
        if at < 0 {
            return Err(format!("at must not be negative, not {}", s.at));
        }
        let duration = match s.duration {
            None => DEFAULT_SWITCH,
            Some(given) => {
                let snapped = self.snapped(given);
                if snapped <= 0 {
                    return Err(format!("duration must be positive, not {given}"));
                }
                snapped
            }
        };
        let through = match s.through {
            None => None,
            Some(given) => {
                let snapped = self.snapped(given);
                if snapped <= at {
                    return Err(format!("through must be after at ({at}), not {given}"));
                }
                Some(snapped)
            }
        };
        let focus = match s.focus {
            None => (0.0, 0.0),
            Some([x, y]) if x.is_finite() && y.is_finite() => (x, y),
            Some([x, y]) => {
                return Err(format!("focus must be two finite numbers, not [{x}, {y}]"))
            }
        };
        let choice = LayoutChoice {
            layout: s.layout,
            shape: s.shape.unwrap_or_default(),
            corner: s.corner.unwrap_or_default(),
            focus,
        };

        // The camera (CO-64).
        let camera = self.require_clip(s.camera)?;
        if let Some(why) = self.role_refusal(camera, at) {
            return Ok(Outcome::Refused(why));
        }
        // The screen, given or found.
        let screen = match s.screen {
            Some(id) => {
                let screen = self.require_clip(id)?;
                if let Some(why) = self.role_refusal(screen, at) {
                    return Ok(Outcome::Refused(why));
                }
                let behind = match (
                    self.track_index(screen.track),
                    self.track_index(camera.track),
                ) {
                    (Some(back), Some(front)) => back < front,
                    _ => false,
                };
                if !behind {
                    return Ok(Outcome::Refused(format!(
                        "the screen (clip {}) must be on a track behind the camera's (clip {})",
                        screen.id, camera.id
                    )));
                }
                Some(screen)
            }
            None => self.screen_behind(camera, at),
        };
        if screen.is_none() && matches!(s.layout, CameraLayout::SideBySide | CameraLayout::Stacked)
        {
            return Ok(Outcome::Refused(format!(
                "no clip draws behind clip {} at {} to be the screen",
                camera.id,
                self.layout_timecode(at)
            )));
        }

        let mut roles = vec![self.role(RoleKind::Camera, camera, at, through)];
        if let Some(screen) = screen {
            roles.push(self.role(RoleKind::Screen, screen, at, through));
        }
        let movers: Vec<Option<String>> = roles
            .iter()
            .map(|role| self.mover_refusal(role, s.layout))
            .collect();
        let nesting = s.nest == Some(true);

        // A nest clip cannot draw a radius (CO-62).
        if s.layout == CameraLayout::Corner && choice.shape != LayoutShape::Square {
            let camera_role = &roles[0];
            let becomes = nesting && movers[0].is_some();
            let nested = camera_role
                .clips()
                .find(|c| matches!(c.source, Source::Nest { .. }))
                .map(|c| c.id)
                .or(becomes.then_some(camera_role.clip.id));
            if let Some(id) = nested {
                return Ok(Outcome::Refused(format!(
                    "clip {id} is a nest clip, which cannot draw a rounded corner or a circle."
                )));
            }
        }

        // The movers: refused, or nested first.
        if !nesting {
            if let Some(why) = movers.iter().flatten().next() {
                return Ok(Outcome::Refused(why.clone()));
            }
        } else if movers.iter().any(Option::is_some) {
            return self.nest_then_switch(s, &roles, &movers);
        }

        let curve = s.curve.unwrap_or(Curve::EaseInOut);
        self.compose_switch(&choice, &roles, at, duration, curve)
    }

    /// The switch composed once its refusals have passed (CO-61): every
    /// placement solved on the project as it is, then per role the layout
    /// action at `at` (replacing one starting there, shortening one running
    /// there, a cut at a first frame) and the bases of `later`. Shared by
    /// `switch_layout` and `reframe_layout.rs`'s replay (spec §11 VR-53 (b)).
    pub(crate) fn compose_switch(
        &self,
        choice: &LayoutChoice,
        roles: &[Role<'_>],
        at: Ticks,
        duration: Ticks,
        curve: Curve,
    ) -> Result<Outcome, String> {
        // Every placement is solved on the project as it is.
        let screen_size = roles
            .iter()
            .find(|role| role.kind == RoleKind::Screen)
            .and_then(|role| self.source_size(role.clip));
        let mut writes: Vec<RoleWrites> = Vec::new();
        for role in roles {
            let solve = |clip: &Clip, kept: Placement| -> Option<Placement> {
                let source = self.source_size(clip)?;
                Some(match role.kind {
                    RoleKind::Camera => camera_placement(self, choice, source, screen_size, &kept),
                    RoleKind::Screen => screen_placement(self, choice.layout, source),
                })
            };
            let t = at - role.clip.start;
            let kept = Placement::of(&self.evaluate_clip(role.clip, t).video);
            let Some(end) = solve(role.clip, kept) else {
                continue;
            };
            let bases = role
                .later
                .iter()
                .filter_map(|c| {
                    let base = Placement::of(c.video.as_ref()?);
                    solve(c, base).map(|p| (c.id, p))
                })
                .collect();
            writes.push((role.clip.id, t, end, bases));
        }

        // A shape or graphic clip given a crop or a radius (spec §11 #524),
        // refused up front so every `at` and every replay answers alike.
        for (id, _, end, bases) in &writes {
            let placed = std::iter::once((*id, end)).chain(bases.iter().map(|(c, p)| (*c, p)));
            for (id, placed) in placed {
                let clip = self.require_clip(id)?;
                if let Some(why) = self.drawn_layout_refusal(clip, placed) {
                    return Ok(Outcome::Refused(why));
                }
            }
        }

        let frame = self.frame();
        let mut next = self.clone();
        for (id, t, end, bases) in &writes {
            let (id, t) = (*id, *t);
            let clip = self.require_clip(id)?.clone();
            let video = end.to_json();
            let patch = json!({ "video": video });
            // One starting at `at` is replaced; one running at `at` ends there.
            if let Some(found) = clip.actions.iter().find(|a| is_layout(a) && a.start == t) {
                step!(next, next.remove_action(id, found.id));
            }
            if let Some(found) = clip
                .actions
                .iter()
                .find(|a| is_layout(a) && a.start < t && t < a.start.saturating_add(a.duration))
            {
                step!(
                    next,
                    next.set_action(id, found.id, None, Some(t - found.start), None)
                );
            }
            if t == 0 {
                // A cut: the base, and a one-frame action ending at it.
                step!(next, next.set_video(&[id], &video));
                let action = next.next_id;
                step!(next, next.add_action(id, 0, Some(frame)));
                step!(next, next.set_action_end(id, action, &patch, &[], None));
            } else {
                let mut length = duration.min(clip.duration - t);
                if let Some(later) = clip
                    .actions
                    .iter()
                    .filter(|a| is_layout(a) && a.start > t)
                    .map(|a| a.start)
                    .min()
                {
                    length = length.min(later - t);
                }
                let length = length.max(frame);
                let action = next.next_id;
                step!(next, next.add_action(id, t, Some(length)));
                step!(next, next.set_action(id, action, None, None, Some(curve)));
                step!(next, next.set_action_end(id, action, &patch, &[], None));
            }
            for (later, base) in bases {
                step!(next, next.set_video(&[*later], &base.to_json()));
            }
        }
        self.finish(next)
    }

    /// The refusal for a shape or graphic clip `placed` would crop (off a
    /// matte track) or round (spec §11 #524): such a clip has no Crop or
    /// Corner Radius section. A text clip never reaches it: it has no source
    /// size, so it is never a role (CO-64).
    fn drawn_layout_refusal(&self, clip: &Clip, placed: &Placement) -> Option<String> {
        let kind = described_kind(clip)?;
        let on_matte = self.track(clip.track).is_some_and(|t| !t.matte.is_none());
        let cropped = placed.crop != Crop::default() && !on_matte;
        (placed.corner_radius != 0.0 || cropped).then(|| {
            format!(
                "clip {} is {kind} and cannot take a camera layout's crop or corner radius",
                clip.id
            )
        })
    }

    /// The camera's (or a given screen's) refusal: no picture, or not
    /// playing at `at` (CO-64).
    fn role_refusal(&self, clip: &Clip, at: Ticks) -> Option<String> {
        if !self.has_layout_picture(clip) {
            return Some(format!("clip {} has no picture to lay out", clip.id));
        }
        if !(clip.start <= at && at < clip_end(clip)) {
            return Some(format!(
                "clip {} does not play at {}",
                clip.id,
                self.layout_timecode(at)
            ));
        }
        None
    }

    /// The screen found behind `camera` at `at` (CO-64): the clip playing
    /// there on the front-most track behind the camera's that is shown and
    /// not a matte track, drawing a picture, not an adjustment clip.
    fn screen_behind(&self, camera: &Clip, at: Ticks) -> Option<&Clip> {
        let front = self.track_index(camera.track)?;
        self.tracks
            .get(..front)?
            .iter()
            .rev()
            .filter(|track| !track.hidden && track.matte.is_none())
            .find_map(|track| {
                self.clips.iter().find(|c| {
                    c.track == track.id
                        && c.start <= at
                        && at < clip_end(c)
                        && c.enabled.video
                        && !is_adjustment(c)
                        && self.has_layout_picture(c)
                })
            })
    }

    /// `nest: true` (CO-62): each moving role's clips nested, refused when
    /// one is already laid out, then the switch on the nest clips.
    fn nest_then_switch(
        &self,
        s: &LayoutSwitch,
        roles: &[Role<'_>],
        movers: &[Option<String>],
    ) -> Result<Outcome, String> {
        let mut again = s.clone();
        again.nest = None;
        let mut next = self.clone();
        for (role, mover) in roles.iter().zip(movers) {
            if mover.is_none() {
                continue;
            }
            let nested: Vec<&Clip> = role.nested().collect();
            if let Some(id) = nested.iter().find(|c| self.laid_out(c)).map(|c| c.id) {
                return Ok(Outcome::Refused(format!(
                    "clip {id} is already laid out; a nest would lay it out twice."
                )));
            }
            let ids: Vec<u32> = nested.iter().map(|c| c.id).collect();
            let before: HashSet<u32> = next.clips.iter().map(|c| c.id).collect();
            step!(next, next.nest_clips(&ids, None));
            let made = next
                .clips
                .iter()
                .find(|c| !before.contains(&c.id) && matches!(c.source, Source::Nest { .. }))
                .map(|c| c.id);
            if let Some(made) = made {
                match role.kind {
                    RoleKind::Camera => again.camera = made,
                    RoleKind::Screen => again.screen = Some(made),
                }
            }
        }
        match next.switch_layout(&again)? {
            Outcome::Applied(laid) => self.finish(laid),
            Outcome::Identity => self.finish(next),
            Outcome::Refused(why) => Ok(Outcome::Refused(why)),
        }
    }
}
