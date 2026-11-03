//! How far a camera-layout switch reaches, and what in that reach refuses
//! it (road map "creator-jobs" CO6, spec §11 CO-61, CO-62): a part of
//! `edit_layout.rs`, cut beside it for the 400-line cap on a new module.
//!
//! A [`Role`] is the camera or the screen: the clip under `at`, and the
//! REACH's later clips — every picture clip on the same track starting
//! after `at` and before the earliest of the first later layout action's
//! absolute start on that track, `through` and the track's end.

use crate::action_class::{is_layout, is_zoom, moves};
use crate::edit_clip::clip_end;
use crate::layout::{full_placement, holds_full, CameraLayout, Placement};
use crate::model::{Clip, Project};
use crate::time::Ticks;

/// Which role a clip plays.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum RoleKind {
    Camera,
    Screen,
}

impl RoleKind {
    /// The role's word in a sentence.
    fn word(self) -> &'static str {
        match self {
            RoleKind::Camera => "camera",
            RoleKind::Screen => "screen",
        }
    }
}

/// One role's clips in the reach.
#[derive(Debug, Clone)]
pub(crate) struct Role<'a> {
    pub kind: RoleKind,
    /// The clip playing at `at`.
    pub clip: &'a Clip,
    /// `at` in project time.
    pub at: Ticks,
    /// The later picture clips starting inside the reach, in time order.
    pub later: Vec<&'a Clip>,
    /// The clip whose own layout action ends the reach, when one does.
    pub ender: Option<u32>,
}

impl<'a> Role<'a> {
    /// The clip under `at`, then the later reach clips.
    pub(crate) fn clips(&self) -> impl Iterator<Item = &'a Clip> + '_ {
        std::iter::once(self.clip).chain(self.later.iter().copied())
    }

    /// What `nest: true` nests: [`Role::clips`] but a later clip whose own
    /// layout action ends the reach (CO-62).
    pub(crate) fn nested(&self) -> impl Iterator<Item = &'a Clip> + '_ {
        let ender = self.ender;
        std::iter::once(self.clip).chain(
            self.later
                .iter()
                .copied()
                .filter(move |c| Some(c.id) != ender),
        )
    }
}

impl Project {
    /// The role `kind` played by `clip` (which plays at `at`), its reach
    /// found on `clip`'s track (CO-61).
    pub(crate) fn role<'a>(
        &'a self,
        kind: RoleKind,
        clip: &'a Clip,
        at: Ticks,
        through: Option<Ticks>,
    ) -> Role<'a> {
        let on_track = || self.clips.iter().filter(move |c| c.track == clip.track);
        let mut end = on_track().map(clip_end).max().unwrap_or(at);
        let mut ender = None;
        for owner in on_track() {
            for action in owner.actions.iter().filter(|a| is_layout(a)) {
                let starts = owner.start.saturating_add(action.start);
                if starts > at && starts < end {
                    end = starts;
                    ender = Some(owner.id);
                }
            }
        }
        if let Some(through) = through {
            if through < end {
                end = through;
                ender = None;
            }
        }
        let mut later: Vec<&Clip> = on_track()
            .filter(|c| c.id != clip.id && c.start > at && c.start < end)
            .filter(|c| self.has_layout_picture(c))
            .collect();
        later.sort_by_key(|c| (c.start, c.id));
        Role {
            kind,
            clip,
            at,
            later,
            ender,
        }
    }

    /// The first mover in `role`'s reach, as CO-62's sentence, or `None`.
    /// A screen that already holds its full placement is not checked in a
    /// layout that leaves it there.
    pub(crate) fn mover_refusal(&self, role: &Role<'_>, layout: CameraLayout) -> Option<String> {
        let exempt = |clip: &Clip, placed: Placement| {
            role.kind == RoleKind::Screen
                && layout.screen_full()
                && self
                    .source_size(clip)
                    .is_some_and(|size| holds_full(&placed, &full_placement(self, size)))
        };
        for clip in role.clips() {
            let under = clip.id == role.clip.id;
            let t = role.at - clip.start;
            let placed = if under {
                Placement::of(&self.evaluate_clip(clip, t).video)
            } else {
                Placement::of(&clip.video.clone().unwrap_or_default())
            };
            if exempt(clip, placed) {
                continue;
            }
            let found = clip
                .actions
                .iter()
                .filter(|a| moves(a) && !is_layout(a))
                .filter(|a| !under || a.start.saturating_add(a.duration) > t)
                .min_by_key(|a| (a.start, a.id));
            if let Some(action) = found {
                let role_word = role.kind.word();
                let (verb, noun) = if is_zoom(action) {
                    ("zooms", "zoom")
                } else {
                    ("moves", "action")
                };
                return Some(format!(
                    "The {role_word} clip {} at {} {verb} (action {}); nest the {role_word}'s \
                     clips so the layout moves the nest and the {noun} stays inside it.",
                    clip.id,
                    self.layout_timecode(clip.start),
                    action.id
                ));
            }
        }
        None
    }

    /// Whether `clip` is already laid out (CO-62): its base six keys, or the
    /// end of any of its layout actions, not its full placement.
    pub(crate) fn laid_out(&self, clip: &Clip) -> bool {
        let Some(size) = self.source_size(clip) else {
            return false;
        };
        let full = full_placement(self, size);
        let base = Placement::of(&clip.video.clone().unwrap_or_default());
        !holds_full(&base, &full)
            || clip
                .actions
                .iter()
                .filter(|a| is_layout(a))
                .any(|a| Placement::from_end(&a.end).is_none_or(|end| !holds_full(&end, &full)))
    }
}
