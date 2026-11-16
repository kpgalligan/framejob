//! `reframe_clip {follow: "layout"}` — a camera and the screen behind it
//! re-laid on the current canvas (road map "creator-jobs" VR5b, spec §11
//! VR-53). Each switch Clip ▸ Camera Layout ▸ made is recognised on the
//! AUTHORED canvas (`from`, `layout_recognise.rs`) and solved again here by
//! `switch_layout`'s own composition (`compose_switch`), so a re-laid switch
//! is exactly the one a person would make on this canvas.
//!
//! - **The group.** Every top-level clip holding a layout action
//!   (`is_layout`) is laid out. A camera action at absolute T pairs with the
//!   layout action starting at T on the front-most track behind the
//!   camera's that holds one (CO-64's front and behind); a laid-out clip is
//!   a SCREEN when one on a track in front holds a layout action starting
//!   when one of its own does, else a CAMERA. The group is the closure over
//!   pairing from the given clip, plus each switch's PIECES: the clips of the
//!   same source (`same_source`, which ignores `in`) on a role's track
//!   starting after its action and before the track's next layout action,
//!   whose base is `alike` that action's end — the cut pieces of a laid-out
//!   recording, which CO-61's reach gave the layout as their base.
//! - **The replay.** Every group clip and piece takes `keep`'s per-axis
//!   rescale of its BASE (`rescale_video`); the group's layout actions are
//!   removed; the switches are composed again in time order at the camera
//!   action's absolute start, with [`switch_timing`]'s duration and curve,
//!   the recognised layout (Side by Side as Stacked on a canvas taller than
//!   wide) and its pieces as each role's later clips, nothing ending a
//!   reach. The focus is the old crop's centre (`focus_of`).
//! - **The other moves.** Each other moving end of a group clip or piece (a
//!   zoom) is re-based by [`conjugate`] from the placement in effect at its
//!   start on the old project to the one on the new, so what it zooms on
//!   keeps its place in the picture.
//!
//! Refused in VR-53 (c)'s order (`edit.rs`'s row); CO-62's refusals are not
//! asked again: each switch passed them when it was made.

use std::collections::{BTreeSet, HashMap};

use serde_json::{Map, Value};

use crate::action_class::{is_layout, moves};
use crate::edit_canvas::rescale_video;
use crate::edit_layout_reach::{Role, RoleKind};
use crate::layout::{CameraLayout, LayoutChoice, Placement, DEFAULT_SWITCH};
use crate::layout_recognise::{alike, recognise, same_source, RoleEnd};
use crate::model::{Action, Clip, Curve, Project, Source};
use crate::outcome::Outcome;
use crate::props_check::{SCALE_MAX, SCALE_MIN};
use crate::time::Ticks;

/// One layout action: its clip, its id and its absolute start.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Act {
    clip: u32,
    action: u32,
    at: Ticks,
}

/// A recognised switch: the camera's action, the screen's paired one, the
/// layout, and each role's pieces.
struct Switch {
    camera: Act,
    screen: Option<Act>,
    choice: LayoutChoice,
    camera_pieces: Vec<u32>,
    screen_pieces: Vec<u32>,
}

/// The duration and curve a switch is replayed with: those of its longest
/// role action that does not start at its clip's first frame (a cut there
/// is one frame long whatever the switch's length), else the camera
/// action's — `actions` holds the camera's first.
pub(crate) fn switch_timing(actions: &[(&Clip, &Action)]) -> (Ticks, Curve) {
    let mut chosen: Option<&Action> = None;
    for (_, action) in actions {
        if action.start != 0 && chosen.is_none_or(|c| action.duration > c.duration) {
            chosen = Some(action);
        }
    }
    match chosen.or(actions.first().map(|(_, a)| *a)) {
        Some(action) => (action.duration, action.curve),
        None => (DEFAULT_SWITCH, Curve::EaseInOut),
    }
}

/// A moving end re-based from the placement `old` it was made over to
/// `new`: with `r = new.scale / old.scale`, each of `x`, `y` and `scale`
/// the end names is written `new.x + r·(x − old.x)`, `new.y + r·(y − old.y)`
/// and `scale·r` (clamped), so the picture point it shows at a canvas point
/// keeps its place relative to the layout's picture.
pub(crate) fn conjugate(end: &mut Map<String, Value>, old: &Placement, new: &Placement) {
    let r = new.scale / old.scale;
    if !(r.is_finite() && r > 0.0) {
        return;
    }
    let read = |end: &Map<String, Value>, key: &str| end.get(key).and_then(Value::as_f64);
    if let Some(x) = read(end, "x") {
        end.insert("x".into(), Value::from(new.x + r * (x - old.x)));
    }
    if let Some(y) = read(end, "y") {
        end.insert("y".into(), Value::from(new.y + r * (y - old.y)));
    }
    if let Some(scale) = read(end, "scale") {
        end.insert(
            "scale".into(),
            Value::from((scale * r).clamp(SCALE_MIN, SCALE_MAX)),
        );
    }
}

/// The layout actions of `clip`, in its action order.
fn layout_acts(clip: &Clip) -> Vec<Act> {
    clip.actions
        .iter()
        .filter(|a| is_layout(a))
        .map(|a| Act {
            clip: clip.id,
            action: a.id,
            at: clip.start.saturating_add(a.start),
        })
        .collect()
}

/// The placement in effect at clip time `t`: the latest layout end starting
/// at or before it, else the base.
fn in_effect(clip: &Clip, t: Ticks) -> Placement {
    clip.actions
        .iter()
        .filter(|a| is_layout(a) && a.start <= t)
        .max_by_key(|a| (a.start, a.id))
        .and_then(|a| Placement::from_end(&a.end))
        .unwrap_or_else(|| Placement::of(&clip.video.clone().unwrap_or_default()))
}

impl Project {
    /// The layout action starting at absolute `at` on the front-most track
    /// behind `camera`'s that holds one.
    fn paired(&self, camera: &Clip, at: Ticks) -> Option<Act> {
        let front = self.track_index(camera.track)?;
        self.tracks.get(..front)?.iter().rev().find_map(|track| {
            self.clips
                .iter()
                .filter(|c| c.track == track.id && c.id != camera.id)
                .flat_map(layout_acts)
                .filter(|act| act.at == at)
                .min_by_key(|act| (act.clip, act.action))
        })
    }

    /// Whether a laid-out clip on a track in front of `clip`'s holds a
    /// layout action starting when one of `clip`'s does.
    fn is_screen(&self, clip: &Clip) -> bool {
        let Some(own) = self.track_index(clip.track) else {
            return false;
        };
        let starts: Vec<Ticks> = layout_acts(clip).iter().map(|a| a.at).collect();
        self.clips.iter().any(|c| {
            c.id != clip.id
                && self.track_index(c.track).is_some_and(|i| i > own)
                && layout_acts(c).iter().any(|a| starts.contains(&a.at))
        })
    }

    /// `act`'s clip and action.
    fn action_of(&self, act: &Act) -> Option<(&Clip, &Action)> {
        let owner = self.clip(act.clip)?;
        Some((owner, owner.actions.iter().find(|a| a.id == act.action)?))
    }

    /// `act`'s end, its clip's source size and whether that is a nest.
    fn end_of(&self, act: &Act) -> Option<RoleEnd> {
        let (owner, action) = self.action_of(act)?;
        let nest = matches!(owner.source, Source::Nest { .. });
        let (end, source) = (Placement::from_end(&action.end)?, self.source_size(owner)?);
        Some(RoleEnd { end, source, nest })
    }

    /// The pieces of `act`'s role (the module doc).
    fn pieces(&self, act: &Act) -> Vec<u32> {
        let Some((role, action)) = self.action_of(act) else {
            return Vec::new();
        };
        let Some(end) = Placement::from_end(&action.end) else {
            return Vec::new();
        };
        let next = self
            .clips
            .iter()
            .filter(|c| c.track == role.track)
            .flat_map(layout_acts)
            .map(|a| a.at)
            .filter(|&t| t > act.at)
            .min()
            .unwrap_or(Ticks::MAX);
        let mut found: Vec<&Clip> = self
            .clips
            .iter()
            .filter(|c| {
                c.id != role.id
                    && c.track == role.track
                    && same_source(&c.source, &role.source)
                    && c.start > act.at
                    && c.start < next
                    && self.has_layout_picture(c)
                    && c.video
                        .as_ref()
                        .is_some_and(|v| alike(&Placement::of(v), &end))
            })
            .collect();
        found.sort_by_key(|c| (c.start, c.id));
        found.iter().map(|c| c.id).collect()
    }

    /// The first unrecognised switch's refusal, by its role's action.
    fn unrecognised(&self, act: &Act, from: (u32, u32)) -> Outcome {
        Outcome::Refused(format!(
            "clip {}'s layout action {} at {} is not a camera layout Frame Job made on the {} × {} \
             canvas, so it cannot be re-laid; keep its clips as placed",
            act.clip,
            act.action,
            self.layout_timecode(act.at),
            from.0,
            from.1
        ))
    }

    /// `follow: layout` on `clip`, authored on a `from` canvas (the module
    /// doc).
    pub(crate) fn relaid(&self, clip: u32, from: (u32, u32)) -> Result<Outcome, String> {
        let given = self.require_clip(clip)?;
        if !given.actions.iter().any(is_layout) {
            return Ok(Outcome::Refused(format!(
                "clip {clip} holds no camera layout to re-lay; frame it with subject, center, fit \
                 or keep"
            )));
        }
        // Pairing over every laid-out clip, then the closure from `clip`.
        let edges: Vec<(Act, Act)> = self
            .clips
            .iter()
            .flat_map(|c| layout_acts(c).into_iter().map(move |act| (c, act)))
            .filter_map(|(c, act)| Some((act, self.paired(c, act.at)?)))
            .collect();
        let mut group: BTreeSet<u32> = BTreeSet::from([clip]);
        loop {
            let before = group.len();
            for (a, b) in &edges {
                if group.contains(&a.clip) || group.contains(&b.clip) {
                    group.insert(a.clip);
                    group.insert(b.clip);
                }
            }
            if group.len() == before {
                break;
            }
        }
        let clips: Vec<&Clip> = group.iter().filter_map(|id| self.clip(*id)).collect();
        let screens: HashMap<u32, bool> = clips.iter().map(|c| (c.id, self.is_screen(c))).collect();

        // A clip both a camera and a screen.
        if let Some(both) = clips
            .iter()
            .find(|c| screens[&c.id] && edges.iter().any(|(a, _)| a.clip == c.id))
        {
            return Ok(Outcome::Refused(format!(
                "clip {} is laid out both as a camera and as a screen, so its layouts cannot be \
                 re-laid; keep its clips as placed",
                both.id
            )));
        }
        // A screen action with no camera switch in front of it.
        let unpaired = clips
            .iter()
            .filter(|c| screens[&c.id])
            .flat_map(|c| layout_acts(c))
            .filter(|act| !edges.iter().any(|(_, s)| s == act))
            .min_by_key(|act| (act.at, act.clip, act.action));
        if let Some(act) = unpaired {
            return Ok(Outcome::Refused(format!(
                "clip {}'s layout action {} at {} has no camera switch in front of it, so it \
                 cannot be re-laid; keep its clips as placed",
                act.clip,
                act.action,
                self.layout_timecode(act.at)
            )));
        }

        // Each switch recognised on the authored canvas, in time order.
        let mut authored = self.clone();
        authored.canvas.width = from.0;
        authored.canvas.height = from.1;
        let mut acts: Vec<Act> = clips
            .iter()
            .filter(|c| !screens[&c.id])
            .flat_map(|c| layout_acts(c))
            .collect();
        acts.sort_by_key(|act| (act.at, act.clip, act.action));
        let mut switches: Vec<Switch> = Vec::new();
        for camera in acts {
            let screen = edges.iter().find(|(a, _)| *a == camera).map(|(_, s)| *s);
            let found = match (self.end_of(&camera), screen.map(|s| self.end_of(&s))) {
                (None, _) => Err(RoleKind::Camera),
                (Some(_), Some(None)) => Err(RoleKind::Screen),
                (Some(cam), shown) => recognise(&authored, &cam, shown.flatten().as_ref()),
            };
            let choice = match found {
                Ok(choice) => choice,
                Err(kind) => {
                    let named = screen.filter(|_| kind == RoleKind::Screen);
                    return Ok(self.unrecognised(&named.unwrap_or(camera), from));
                }
            };
            switches.push(Switch {
                camera,
                screen,
                choice,
                camera_pieces: self.pieces(&camera),
                screen_pieces: screen.map_or_else(Vec::new, |s| self.pieces(&s)),
            });
        }

        // The members: the group's clips and every switch's pieces.
        let mut members: BTreeSet<u32> = group.clone();
        for s in &switches {
            members.extend(s.camera_pieces.iter().chain(&s.screen_pieces));
        }
        let (w, h) = (
            f64::from(self.canvas.width) / f64::from(from.0),
            f64::from(self.canvas.height) / f64::from(from.1),
        );
        let mut next = self.clone();
        for c in next.clips.iter_mut().filter(|c| members.contains(&c.id)) {
            if let Some(video) = c.video.as_mut() {
                rescale_video(video, w, h);
            }
            if group.contains(&c.id) {
                c.actions.retain(|a| !is_layout(a));
            }
        }

        // The replay, in time order.
        let tall = self.canvas.height > self.canvas.width;
        for s in &switches {
            let mut choice = s.choice;
            if tall && choice.layout == CameraLayout::SideBySide {
                choice.layout = CameraLayout::Stacked;
            }
            let timed: Vec<(&Clip, &Action)> = std::iter::once(s.camera)
                .chain(s.screen)
                .filter_map(|act| self.action_of(&act))
                .collect();
            let (duration, curve) = switch_timing(&timed);
            let outcome = {
                let role = |kind: RoleKind, act: &Act, pieces: &[u32]| -> Option<Role<'_>> {
                    Some(Role {
                        kind,
                        clip: next.clip(act.clip)?,
                        at: act.at,
                        later: pieces.iter().filter_map(|id| next.clip(*id)).collect(),
                        ender: None,
                    })
                };
                let mut roles = Vec::new();
                roles.extend(role(RoleKind::Camera, &s.camera, &s.camera_pieces));
                if let Some(screen) = &s.screen {
                    roles.extend(role(RoleKind::Screen, screen, &s.screen_pieces));
                }
                next.compose_switch(&choice, &roles, s.camera.at, duration, curve)
            };
            match outcome? {
                Outcome::Applied(applied) => next = applied,
                Outcome::Identity => {}
                Outcome::Refused(why) => return Ok(Outcome::Refused(why)),
            }
        }

        // The other moving ends, re-based.
        for id in &members {
            let (Some(old), Some(new)) = (self.clip(*id), next.clip(*id)) else {
                continue;
            };
            let bases: Vec<(usize, Placement, Placement)> = new
                .actions
                .iter()
                .enumerate()
                .filter(|(_, a)| moves(a) && !is_layout(a))
                .map(|(i, a)| (i, in_effect(old, a.start), in_effect(new, a.start)))
                .collect();
            let Some(target) = next.clips.iter_mut().find(|c| c.id == *id) else {
                continue;
            };
            for (i, was, now) in bases {
                if let Some(Value::Object(end)) = target.actions[i].end.get_mut("video") {
                    conjugate(end, &was, &now);
                }
            }
        }
        self.finish(next)
    }
}
